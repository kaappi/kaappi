const std = @import("std");
const memory = @import("memory.zig");
const reader_mod = @import("reader.zig");
const bytecode_file = @import("bytecode_file.zig");
const compiler_mod = @import("compiler.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const library = @import("library.zig");
const types = @import("types.zig");
const fuzz_gen = @import("fuzz_gen.zig");

const Context = @TypeOf(.{});

// Input buffer sizes per target. Seeds must fit the target's buffer: Smith
// replays an over-long slice decision as an EMPTY input rather than failing
// loudly, so `seed()` takes the buffer size and rejects oversized seeds at
// compile time.
const reader_buf_len = 256;
const compiler_buf_len = 256;
const eval_buf_len = 128;
const loader_buf_len = 512;

// ---------------------------------------------------------------------------
// Seed corpus encoding
//
// `FuzzInputOptions.corpus` entries are serialized Smith DECISION streams,
// not raw application inputs. Each byte-input target below makes exactly one
// `smith.sliceWithHash(&buf, 0)` call, and Smith replays a slice decision as
//
//   <4-byte little-endian length><bytes>
//
// Passing raw `.scm` bytes as a corpus entry would misread the first four
// source bytes as the length. Always wrap new seeds in `seed()`.
//
// Under plain `zig build test` each corpus entry is replayed once through the
// test body (plus one empty input); under `zig build test --fuzz` the entries
// become the fuzzer's starting corpus.
// ---------------------------------------------------------------------------

fn seed(comptime buf_len: usize, comptime s: []const u8) []const u8 {
    if (s.len > buf_len) @compileError("seed exceeds the target's input buffer: " ++ s);
    comptime {
        var out: [4 + s.len]u8 = undefined;
        std.mem.writeInt(u32, out[0..4], s.len, .little);
        @memcpy(out[4..], s);
        const final = out;
        return &final;
    }
}

// Datum-level lexical variety for the reader: nesting, dotted pairs, vectors,
// bytevectors, chars, string escapes, block/datum comments, quasiquote,
// numeric tower literals, datum labels, and pipe symbols.
const reader_corpus = [_][]const u8{
    seed(reader_buf_len, "(a b c (d e (f . g)))"),
    seed(reader_buf_len, "#(1 2 #(3 4)) #u8(0 255 128)"),
    seed(reader_buf_len, "#\\x3BB #\\newline #\\space #\\a"),
    seed(reader_buf_len, "\"a\\nb\\\"c\\\\d \\x41;e\""),
    seed(reader_buf_len, "#| block #| nested |# comment |# 42"),
    seed(reader_buf_len, "#;(ignored datum) (kept)"),
    seed(reader_buf_len, "`(a ,b ,@(c d))"),
    seed(reader_buf_len, "-123456789012345678901234567890 22/7 -1.5e10 +inf.0 -nan.0"),
    seed(reader_buf_len, "#b1010 #o777 #xDEADBEEF #e1.5 #i3/4"),
    seed(reader_buf_len, "#0=(1 2 . #0#)"),
    seed(reader_buf_len, "|sym with spaces| 'quoted"),
};

// One expression per core form; the compiler target reads a single datum.
const compiler_corpus = [_][]const u8{
    seed(compiler_buf_len, "(define (fact n) (if (< n 2) 1 (* n (fact (- n 1)))))"),
    seed(compiler_buf_len, "(lambda (x . rest) (apply + x rest))"),
    seed(compiler_buf_len, "(let ((x 1) (y 2)) (* x y))"),
    seed(compiler_buf_len, "(letrec ((even? (lambda (n) (if (zero? n) #t (odd? (- n 1))))) (odd? (lambda (n) (if (zero? n) #f (even? (- n 1)))))) (even? 10))"),
    seed(compiler_buf_len, "(if (< 1 2) 'yes 'no)"),
    seed(compiler_buf_len, "(and 1 2 (or #f 3))"),
    seed(compiler_buf_len, "(cond ((= 1 2) 'a) ((> 3 2) 'b) (else 'c))"),
    seed(compiler_buf_len, "(case (* 2 3) ((2 3 5 7) 'prime) ((1 4 6 8 9) 'composite) (else 'other))"),
    seed(compiler_buf_len, "(do ((i 0 (+ i 1)) (acc '() (cons i acc))) ((= i 5) acc))"),
    seed(compiler_buf_len, "(let loop ((n 10) (acc 1)) (if (= n 0) acc (loop (- n 1) (* acc n))))"),
    seed(compiler_buf_len, "(set! x 42)"),
    seed(compiler_buf_len, "`(1 ,(+ 1 1) ,@(list 3 4))"),
    seed(compiler_buf_len, "(define-syntax swap! (syntax-rules () ((_ a b) (let ((tmp a)) (set! a b) (set! b tmp)))))"),
    seed(compiler_buf_len, "(when #t (unless #f 'both))"),
    seed(compiler_buf_len, "(case-lambda ((x) x) ((x y) (+ x y)))"),
    seed(compiler_buf_len, "(guard (e (#t 'caught)) (raise 'boom))"),
};

// Small self-contained programs that actually run (128-byte budget).
// Keep seeds pure — the evaluated result is discarded, and evalOne silences
// stdout only as a backstop against fuzzer-discovered (display ...) calls.
const eval_corpus = [_][]const u8{
    seed(eval_buf_len, "(* (+ 1 2) (- 10 4))"),
    seed(eval_buf_len, "(define (adder n) (lambda (x) (+ x n))) ((adder 3) 4)"),
    seed(eval_buf_len, "(define (loop n) (if (zero? n) 'done (loop (- n 1)))) (loop 100000)"),
    seed(eval_buf_len, "(call/cc (lambda (k) (+ 1 (k 42))))"),
    seed(eval_buf_len, "(string-append \"foo\" (number->string 42))"),
    seed(eval_buf_len, "(let ((v (make-vector 3 0))) (vector-set! v 1 7) (vector-ref v 1))"),
    seed(eval_buf_len, "(guard (e (#t 'caught)) (raise 'boom))"),
    seed(eval_buf_len, "(define-values (q r) (floor/ 7 2)) (cons q r)"),
};

// ---------------------------------------------------------------------------
// Bytecode loader fixture
//
// A small valid .sbc checked in at src/testdata/fuzz-seed.sbc. Regenerate it
// after a bytecode format VERSION bump (the sanity test below will fail):
//
//   zig build && zig-out/bin/kaappi --compile src/testdata/fuzz-seed.scm \
//     -o src/testdata/fuzz-seed.sbc
// ---------------------------------------------------------------------------

const raw_fixture = @embedFile("testdata/fuzz-seed.sbc");

// Offset of the compiler-version hash in the .sbc header:
// magic(4) + format version(2) + source hash(8).
const compiler_hash_offset = 14;

/// The .sbc header embeds a hash of the interpreter version string; patch it
/// at comptime so the checked-in fixture keeps deserializing after version
/// bumps. The format has no whole-file checksum, so a field patch is safe.
fn patchedFixture() [raw_fixture.len]u8 {
    var out: [raw_fixture.len]u8 = raw_fixture.*;
    std.mem.writeInt(u64, out[compiler_hash_offset..][0..8], bytecode_file.compilerHash(), .little);
    return out;
}

const sbc_fixture = patchedFixture();

fn corruptedFixture(comptime offset: usize, comptime mask: u8) []const u8 {
    comptime {
        var out = sbc_fixture;
        out[offset] ^= mask;
        const final = out;
        return &final;
    }
}

const loader_corpus = [_][]const u8{
    seed(loader_buf_len, &sbc_fixture), // valid file
    seed(loader_buf_len, sbc_fixture[0..4]), // magic only
    seed(loader_buf_len, sbc_fixture[0..32]), // truncated after header
    seed(loader_buf_len, sbc_fixture[0 .. sbc_fixture.len / 2]), // truncated body
    seed(loader_buf_len, sbc_fixture[0 .. sbc_fixture.len - 1]), // one byte short
    seed(loader_buf_len, corruptedFixture(0, 0x01)), // corrupt magic
    seed(loader_buf_len, corruptedFixture(4, 0xFF)), // corrupt format version
    seed(loader_buf_len, corruptedFixture(22, 0x10)), // corrupt function count
    seed(loader_buf_len, corruptedFixture(sbc_fixture.len / 2, 0x01)), // mid-body bit flip
    seed(loader_buf_len, corruptedFixture(sbc_fixture.len - 2, 0x80)), // tail bit flip
};

/// Mirrors main.zig's cleanup of a successful DeserializeResult. The loaded
/// Function objects themselves are GC-owned (and rooted in gc.extra_roots),
/// so gc.deinit reclaims those.
fn freeLoaded(allocator: std.mem.Allocator, loaded: bytecode_file.DeserializeResult) void {
    allocator.free(loaded.funcs);
    if (loaded.bundled_files) |bf| {
        var map = bf;
        var it = map.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        map.deinit();
    }
    if (loaded.preamble) |preamble| {
        for (preamble) |p| allocator.free(p);
        allocator.free(preamble);
    }
}

// Guards the corpus against silent rot: if the bytecode format VERSION bumps,
// the fixture stops deserializing and this test fails. Regenerate it with the
// command in the fixture comment above.
test "fuzz seed .sbc fixture stays loadable" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    const loaded = (try bytecode_file.readFromBuffer(&gc, &sbc_fixture)) orelse
        return error.StaleFuzzFixture;
    freeLoaded(std.testing.allocator, loaded);
}

// ---------------------------------------------------------------------------
// Shared eval harness: full read -> compile -> VM execute of one input, with
// a 100 ms execution deadline. Ordinary Scheme errors are expected outcomes;
// only panics, crashes, and leaks fail the target.
// ---------------------------------------------------------------------------

const EvalOutcome = enum { ok, scheme_error, harness_unavailable };

fn evalOne(input: []const u8) void {
    _ = evalOneOutcome(input);
}

fn evalOneOutcome(input: []const u8) EvalOutcome {
    // Redirect fd 1 to /dev/null for the duration: generated programs can
    // call (display ...), and the test binary's stdout is the build-runner
    // IPC pipe — a stray write there deadlocks the run.
    const c = std.posix.system;
    const saved_stdout = c.dup(1);
    if (saved_stdout < 0) return .harness_unavailable;
    defer _ = c.close(saved_stdout);
    const devnull = c.open("/dev/null", .{ .ACCMODE = .WRONLY });
    if (devnull < 0) return .harness_unavailable;
    if (c.dup2(devnull, 1) < 0) {
        _ = c.close(devnull);
        return .harness_unavailable;
    }
    _ = c.close(devnull);
    defer _ = c.dup2(saved_stdout, 1);

    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    // gc lives on this stack frame; don't leave the threadlocal dangling.
    defer memory.gc_instance = null;
    const vm = std.testing.allocator.create(vm_mod.VM) catch return .harness_unavailable;
    vm.* = vm_mod.VM.init(&gc) catch {
        std.testing.allocator.destroy(vm);
        return .harness_unavailable;
    };
    defer {
        vm.deinit();
        std.testing.allocator.destroy(vm);
    }
    vm_mod.setVMInstance(vm);
    // Sandboxed registration: filesystem, process, FFI, and thread
    // primitives are absent, so fuzz inputs reaching those forms get an
    // ordinary undefined-variable error instead of touching the host
    // (per the operating guidance in docs/dev/fuzzing-feasibility.md).
    primitives.registerSandboxed(vm) catch return .harness_unavailable;
    memory.setGCInstance(&gc);
    vm_mod.vm_bootstrap.install(vm) catch return .harness_unavailable;
    library.registerSandboxedLibraries(&vm.libraries, vm.globals) catch return .harness_unavailable;
    vm.sandbox_mode = true;
    vm.timeout_deadline_ns = @import("vm_calls.zig").clockNs() + 100_000_000;
    _ = vm.eval(input) catch return .scheme_error;
    return .ok;
}

test "fuzz reader" {
    try std.testing.fuzz(Context{}, struct {
        fn testOne(_: Context, smith: *std.testing.Smith) anyerror!void {
            var buf: [reader_buf_len]u8 = undefined;
            const len = smith.sliceWithHash(&buf, 0);
            const input = buf[0..len];
            var gc = memory.GC.init(std.testing.allocator);
            defer gc.deinit();
            var r = reader_mod.Reader.init(&gc, input);
            defer r.deinit();
            while (true) {
                _ = r.readDatum() catch break;
            }
        }
    }.testOne, .{ .corpus = &reader_corpus });
}

test "fuzz bytecode loader" {
    try std.testing.fuzz(Context{}, struct {
        fn testOne(_: Context, smith: *std.testing.Smith) anyerror!void {
            var buf: [loader_buf_len]u8 = undefined;
            const len = smith.sliceWithHash(&buf, 0);
            const input = buf[0..len];
            var gc = memory.GC.init(std.testing.allocator);
            defer gc.deinit();
            const loaded = (bytecode_file.readFromBuffer(&gc, input) catch return) orelse return;
            freeLoaded(std.testing.allocator, loaded);
        }
    }.testOne, .{ .corpus = &loader_corpus });
}

test "fuzz compiler" {
    try std.testing.fuzz(Context{}, struct {
        fn testOne(_: Context, smith: *std.testing.Smith) anyerror!void {
            var buf: [compiler_buf_len]u8 = undefined;
            const len = smith.sliceWithHash(&buf, 0);
            const input = buf[0..len];
            var gc = memory.GC.init(std.testing.allocator);
            defer gc.deinit();
            var r = reader_mod.Reader.init(&gc, input);
            defer r.deinit();
            const expr = r.readDatum() catch return;
            var macros = std.StringHashMap(types.Value).init(std.testing.allocator);
            defer macros.deinit();
            var globals = std.StringHashMap(types.Value).init(std.testing.allocator);
            defer globals.deinit();
            _ = compiler_mod.compileExpressionWithMacros(&gc, expr, &macros, &globals) catch return;
        }
    }.testOne, .{ .corpus = &compiler_corpus });
}

test "fuzz eval" {
    try std.testing.fuzz(Context{}, struct {
        fn testOne(_: Context, smith: *std.testing.Smith) anyerror!void {
            var buf: [eval_buf_len]u8 = undefined;
            const len = smith.sliceWithHash(&buf, 0);
            evalOne(buf[0..len]);
        }
    }.testOne, .{ .corpus = &eval_corpus });
}

// ---------------------------------------------------------------------------
// Token-vocabulary target
//
// Byte-level mutation mostly dies in the lexer. Mutating TOKEN sequences
// instead produces inputs that lex and mostly parse without being confined
// to grammatically valid programs (Salls et al., "Token-Level Fuzzing",
// USENIX Security 2021). Deliberately no parenthesis balancing and no
// grammar checks — near-miss inputs are the point. The single space entry
// is the only separator; adjacent word tokens merging into one longer
// identifier is fine.
// ---------------------------------------------------------------------------

const token_table = [_][]const u8{
    // keywords / special forms
    "define",                         "lambda",
    "let",                            "let*",
    "letrec",                         "if",
    "cond",                           "case",
    "do",                             "set!",
    "begin",                          "and",
    "or",                             "when",
    "unless",                         "else",
    "=>",                             "quote",
    "quasiquote",                     "unquote",
    "define-syntax",                  "syntax-rules",
    "define-values",                  "define-record-type",
    "guard",                          "raise",
    "dynamic-wind",                   "call/cc",
    "call-with-current-continuation", "delay",
    "force",                          "parameterize",
    "let-values",                     "case-lambda",
    // punctuation
    "(",                              ")",
    ".",                              "'",
    "`",                              ",",
    ",@",                             "#(",
    "#u8(",                           "#;",
    // literals
    "#t",                             "#f",
    "0",                              "1",
    "2",                              "17",
    "-5",                             "3.14",
    "22/7",                           "+inf.0",
    "\"str\"",                        "#\\a",
    "#\\x3BB",                        "#\\newline",
    // identifiers
    "x",                              "y",
    "f",                              "lst",
    "+",                              "-",
    "*",                              "cons",
    "car",                            "cdr",
    "list",                           "vector",
    "map",                            "apply",
    "eq?",                            "null?",
    // separator
    " ",
};

const max_tokens = 64;
const tokens_buf_len = 512;

test "fuzz tokens" {
    try std.testing.fuzz(Context{}, struct {
        fn testOne(_: Context, smith: *std.testing.Smith) anyerror!void {
            var buf: [tokens_buf_len]u8 = undefined;
            var len: usize = 0;
            const count = smith.valueRangeAtMost(u8, 1, max_tokens);
            var i: usize = 0;
            while (i < count) : (i += 1) {
                const tok = token_table[smith.index(token_table.len)];
                if (len + tok.len > buf.len) break;
                @memcpy(buf[len..][0..tok.len], tok);
                len += tok.len;
            }
            evalOne(buf[0..len]);
        }
    }.testOne, .{});
}

// ---------------------------------------------------------------------------
// Grammar-generated target (Tier 2, #1392)
//
// src/fuzz_gen.zig maps the Smith decision stream to a VALID, well-bound,
// resource-bounded R7RS program — a Zest-style parametric generator. Unlike
// the raw-bytes and token targets (which stay for parser robustness), every
// input here reaches the compiler and VM, so this is the target that
// exercises compiler_*.zig, vm_dispatch.zig, and the GC write-barrier paths.
// No corpus: the decision stream IS the input, and any stream decodes to a
// valid program (an empty stream yields the minimal one).
// ---------------------------------------------------------------------------

test "fuzz grammar" {
    try std.testing.fuzz(Context{}, struct {
        fn testOne(_: Context, smith: *std.testing.Smith) anyerror!void {
            const src = fuzz_gen.generateProgram(smith, std.testing.allocator) catch return;
            defer std.testing.allocator.free(src);
            evalOne(src);
        }
    }.testOne, .{});
}

// Guards the generator's value proposition: the point of Tier 2 is programs
// that RUN, not just parse (the Phase 1 token target manages 76% parsing).
// Deterministic (fixed seeds, fixed generator), so a regression here means a
// generator change made programs start dying at runtime — fix the generator
// or consciously re-baseline.
test "grammar generator: majority of programs evaluate without error" {
    // A gc-stress build slows evaluation by orders of magnitude, so the
    // 100 ms deadline converts slow-but-correct programs into errors and
    // the rate stops measuring the generator. Skip: the CI gc-stress
    // variant still replays the fuzz targets themselves.
    if (@import("build_options").gc_stress) return error.SkipZigTest;
    var ok: u32 = 0;
    var total: u32 = 0;
    var seed_n: u64 = 0;
    while (seed_n < 60) : (seed_n += 1) {
        const src = try fuzz_gen.generateSeeded(seed_n, std.testing.allocator);
        defer std.testing.allocator.free(src);
        switch (evalOneOutcome(src)) {
            .ok => ok += 1,
            .scheme_error => {},
            .harness_unavailable => return error.SkipZigTest,
        }
        total += 1;
    }
    // Measured rate is 98% over 300 seeds (294/300; the rest are expected
    // outcomes — guard re-raises and deadline hits on loop-heavy programs).
    // The threshold sits far below that because deadline outcomes are
    // load-sensitive: a real generator regression tanks the rate, CI jitter
    // must not.
    try std.testing.expect(ok * 100 >= total * 75);
}
