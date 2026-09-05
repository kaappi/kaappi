const std = @import("std");
const builtin = @import("builtin");
const is_wasm = builtin.os.tag == .wasi;
const platform = @import("platform.zig");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const compiler_mod = @import("compiler.zig");
const reader_mod = @import("reader.zig");
const printer = @import("printer.zig");
const ir_mod = @import("ir.zig");
const file_utils = @import("file_utils.zig");
const bytecode_file = @import("bytecode_file.zig");
const cache = @import("cache.zig");
const timings = @import("timings.zig");
const crash = @import("crash.zig");
const reporting = @import("reporting.zig");
const diagnostics = @import("diagnostics.zig");
const lsp_diagnostic = @import("lsp_diagnostic.zig");
const vm_library_cache_mod = @import("vm_library_cache.zig");
const test_runner = @import("test_runner.zig");

const writeStdout = reporting.writeStdout;
const writeStderr = reporting.writeStderr;

pub const Location = struct {
    source: []const u8,
    line: u32,
    /// 1-based column of the failing instruction, or 0 when unknown (older
    /// functions with only a `source_line`, or a top-level form line). Rendered
    /// as `file:line:col` when known (kaappi#1506).
    col: u32 = 0,
};

/// How top-level diagnostics are rendered. `text` is the default human format
/// (unchanged); `json` emits one LSP `Diagnostic` object per line on stderr for
/// agents and editors (`--diagnostics=json`, kaappi#1505). Both formats share
/// the same codes, messages, and reporting funnel — only the rendering differs.
pub const DiagnosticFormat = enum { text, json };

// A process-wide setting (like `ir_mod.optimize_enabled`): set once from the
// parsed CLI options before anything runs, then read by every report function.
// The REPL, file runner, and stdin runner all funnel through here, so one
// switch covers every surface.
var diagnostic_format: DiagnosticFormat = .text;

pub fn setDiagnosticFormat(fmt: DiagnosticFormat) void {
    diagnostic_format = fmt;
}

pub fn diagnosticFormat() DiagnosticFormat {
    return diagnostic_format;
}

/// Set when a script run (file or stdin, never the REPL) hit an uncaught
/// read/compile/runtime error that was reported but recovered from — the
/// driver prints the diagnostic and continues with the next top-level form,
/// so the run can reach its normal end looking successful. Two consumers
/// must not be fooled by that recovery:
///
///  * the exit status: `mainInner` turns the flag into exit(1) on a normal
///    return, and the `exit` primitive upgrades an explicit `(exit 0)` to 1
///    so a script cannot launder a failed run through its own epilogue
///    (kaappi#2512). A non-zero explicit status stays as given; the flag
///    only upgrades 0.
///  * `--compile`: a flagged run writes no artifact, prints no `Compiled`
///    line, and removes any stale file at the output target (kaappi#2513).
///
/// The `kaappi test` worker consumes the flag per file (`emitResult`, which
/// weighs it in the verdict) and clears it, so the worker itself always
/// exits 0 with the verdict travelling in the emitted JSON. REPL sessions
/// never set it: carrying on after an error is what a REPL is for.
///
/// A process-wide flag like `diagnostic_format` above — written on the
/// single main pipeline thread, read at the exit points.
pub var script_had_error: bool = false;

/// Serialize one diagnostic and write it as a single line to stderr. On the
/// rare overflow of the fixed buffer (a pathologically long detail message),
/// emit a minimal valid object instead of a truncated one so the JSON Lines
/// stream stays parseable end to end.
fn emitJsonLine(diag: lsp_diagnostic.Diagnostic) void {
    var buf: [2048]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    diag.writeJson(&w) catch {
        writeStderr("{\"severity\":1,\"source\":\"kaappi\",\"message\":\"diagnostic too large to serialize\"}\n");
        return;
    };
    writeStderr(w.buffered());
    writeStderr("\n");
}

fn lspSeverity(code: diagnostics.Code) lsp_diagnostic.Severity {
    return lsp_diagnostic.severityOf(code.info().severity);
}

// Every diagnostic Kaappi prints carries a stable KP code (KEP-0005, #1504).
// The leading digit encodes the stage: KP1xxx read, KP2xxx compile, KP3xxx
// runtime. The stage word ("read error" / "compile error" / runtime "error")
// is kept for the human reader; the bracketed code is the machine handle. The
// registry also supplies the fallback message that replaces the raw
// `error.XxxYyy` Zig-enum names these paths used to leak.

pub fn reportReadError(source_name: []const u8, line: u32, col: u32, err: anyerror) void {
    const code = diagnostics.readErrorCode(err);
    // A malformed-token error (e.g. a digit-led identifier, kaappi#1723) may
    // carry a detail string that echoes the token and explains the rule; a
    // plain reader failure has none. Prefer it over the bare registry
    // template when present, same pattern as reportCompileError's `detail`.
    const detail = reader_mod.getReadErrorDetail();
    const msg = if (detail.len > 0) detail else code.message();
    var cbuf: [diagnostics.Code.render_width]u8 = undefined;
    if (diagnostic_format == .json) {
        emitJsonLine(.{
            .range = lsp_diagnostic.pointRange(line, col),
            .severity = lspSeverity(code),
            .code = code.render(&cbuf),
            .message = msg,
        });
        reader_mod.resetReadErrorDetail();
        return;
    }
    var buf: [256]u8 = undefined;
    const prefix = std.fmt.bufPrint(&buf, "{s}:{d}:{d}: read error[{s}]: ", .{
        source_name, line, col, code.render(&cbuf),
    }) catch "read error: ";
    writeStderr(prefix);
    writeStderr(msg);
    writeStderr("\n");
    reader_mod.resetReadErrorDetail();
}

pub fn reportCompileError(source_name: []const u8, line: u32, col: u32, err: anyerror) void {
    var cbuf: [diagnostics.Code.render_width]u8 = undefined;
    const detail = compiler_mod.getSyntaxErrorDetail();
    // A macro/syntax-rules rejection carries a detail string and is the "expand"
    // stage; a plain compile failure has none. Both are KP2xxx.
    const code = if (detail.len > 0) diagnostics.Code.syntax_error else diagnostics.compileErrorCode(err);
    const msg = if (detail.len > 0) detail else code.message();

    // Prefer the precise span the compiler recorded for the failing form; fall
    // back to the top-level datum position the caller passed (kaappi#1506).
    const span = compiler_mod.getCompileErrorSpan() orelse
        types.Span{ .line = line, .col = col };
    const eff_line = if (span.line > 0) span.line else line;
    const eff_col = if (span.line > 0) span.col else col;
    defer compiler_mod.resetCompileErrorSpan();

    if (diagnostic_format == .json) {
        emitJsonLine(.{
            .range = lsp_diagnostic.spanRange(span),
            .severity = lspSeverity(code),
            .code = code.render(&cbuf),
            .message = msg,
        });
        if (detail.len > 0) compiler_mod.syntax_error_detail_len = 0;
        return;
    }

    if (detail.len > 0) {
        var buf: [256]u8 = undefined;
        const prefix = if (eff_col > 0)
            std.fmt.bufPrint(&buf, "{s}:{d}:{d}: syntax-error[{s}]: ", .{ source_name, eff_line, eff_col, code.render(&cbuf) }) catch "syntax-error: "
        else
            std.fmt.bufPrint(&buf, "{s}:{d}: syntax-error[{s}]: ", .{ source_name, eff_line, code.render(&cbuf) }) catch "syntax-error: ";
        writeStderr(prefix);
        writeStderr(detail);
        writeStderr("\n");
        compiler_mod.syntax_error_detail_len = 0;
    } else {
        var buf: [256]u8 = undefined;
        const s = if (eff_col > 0)
            std.fmt.bufPrint(&buf, "{s}:{d}:{d}: compile error[{s}]: {s}\n", .{ source_name, eff_line, eff_col, code.render(&cbuf), code.message() }) catch "compile error\n"
        else
            std.fmt.bufPrint(&buf, "{s}:{d}: compile error[{s}]: {s}\n", .{ source_name, eff_line, code.render(&cbuf), code.message() }) catch "compile error\n";
        writeStderr(s);
    }
}

pub fn reportRuntimeError(vm: *vm_mod.VM, err: anyerror, location: ?Location) void {
    const detail = vm.getErrorDetail();
    const code = runtimeCode(vm, err);
    // A raise-site detail (e.g. "type error in 'car': ...") is richer than the
    // registry template, so prefer it when present; the code rides along either
    // way and the template is the no-detail fallback that killed the Zig leak.
    const msg = if (detail.len > 0) detail else code.message();
    var cbuf: [diagnostics.Code.render_width]u8 = undefined;
    const code_str = code.render(&cbuf);

    if (diagnostic_format == .json) {
        // A "did you mean" hint is carried structurally (set at the raise site,
        // kaappi#1505) so a tool can apply the rename directly; the message is
        // then the clean form, with the redundant prose stripped.
        var sug_buf: [1]lsp_diagnostic.Suggestion = undefined;
        var suggestions: []const lsp_diagnostic.Suggestion = &.{};
        var clean_msg = msg;
        if (vm.last_error_suggestion) |replacement| {
            sug_buf[0] = .{ .kind = "rename", .replacement = replacement };
            suggestions = sug_buf[0..1];
            clean_msg = messageWithoutSuggestion(msg, replacement);
        }
        emitJsonLine(.{
            .range = lsp_diagnostic.pointRange(
                if (location) |loc| loc.line else 0,
                if (location) |loc| loc.col else 0,
            ),
            .severity = lspSeverity(code),
            .code = code_str,
            .message = clean_msg,
            .suggestions = suggestions,
        });
        vm.last_error_detail_len = 0;
        vm.last_error_code = .uncategorized;
        vm.last_error_suggestion = null;
        return;
    }

    if (location) |loc| {
        var buf: [512]u8 = undefined;
        const s = if (loc.line > 0 and loc.col > 0)
            std.fmt.bufPrint(&buf, "{s}:{d}:{d}: error[{s}]: {s}\n", .{ loc.source, loc.line, loc.col, code_str, msg }) catch "runtime error\n"
        else if (loc.line > 0)
            std.fmt.bufPrint(&buf, "{s}:{d}: error[{s}]: {s}\n", .{ loc.source, loc.line, code_str, msg }) catch "runtime error\n"
        else
            std.fmt.bufPrint(&buf, "{s}: error[{s}]: {s}\n", .{ loc.source, code_str, msg }) catch "runtime error\n";
        writeStderr(s);
    } else {
        var buf: [512]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "error[{s}]: {s}\n", .{ code_str, msg }) catch "runtime error\n";
        writeStderr(s);
    }
    vm.last_error_detail_len = 0;
    vm.last_error_code = .uncategorized;
    vm.last_error_suggestion = null;
}

/// Return `detail` without the exact "did you mean" suffix that
/// `raiseUndefinedVariable` appended for `replacement`. Deterministic: we rebuild
/// the same suffix we produced and strip it only on an exact match, so this is
/// not prose-scraping. Used to keep the JSON message clean when the hint is
/// already present in `data.suggestions`.
fn messageWithoutSuggestion(detail: []const u8, replacement: []const u8) []const u8 {
    var buf: [80]u8 = undefined;
    const suffix = std.fmt.bufPrint(&buf, ". Did you mean '{s}'?", .{replacement}) catch return detail;
    if (std.mem.endsWith(u8, detail, suffix)) return detail[0 .. detail.len - suffix.len];
    return detail;
}

/// The diagnostic code for a runtime error: the code carried on the raised
/// error object if any (set in noteUncaughtException), else one derived from the
/// escaping Zig error. Callers outside `reportRuntimeError` (the bundled-binary
/// and include paths) use this so every runtime-error surface agrees.
pub fn runtimeCode(vm: *vm_mod.VM, err: anyerror) diagnostics.Code {
    return if (vm.last_error_code != .uncategorized)
        vm.last_error_code
    else
        diagnostics.runtimeErrorCode(err);
}

pub fn vmErrorLocation(vm: *vm_mod.VM, fallback_source: []const u8, fallback_line: u32) Location {
    const have_precise = vm.last_error_line > 0;
    return .{
        .source = vm.last_error_source orelse fallback_source,
        .line = if (have_precise) vm.last_error_line else fallback_line,
        // Only trust the column when it pairs with the precise line; a fallback
        // line has no matching column.
        .col = if (have_precise) vm.last_error_col else 0,
    };
}

pub fn printStackTrace(vm: *vm_mod.VM) void {
    // These human-oriented extras would corrupt the one-object-per-line JSON
    // stream, so suppress them in JSON mode (a future phase may surface frames
    // as LSP `relatedInformation`).
    if (diagnostic_format == .json) return;
    const trace = vm.getLastStackTrace();
    if (trace.len > 1) {
        for (trace[1..]) |frame| {
            var buf: [256]u8 = undefined;
            if (frame.name) |name| {
                const s = std.fmt.bufPrint(&buf, "  in {s} ({s}:{d})\n", .{ name, frame.source orelse "?", frame.line }) catch continue;
                writeStderr(s);
            } else if (frame.line > 0) {
                const s = std.fmt.bufPrint(&buf, "  called from {s}:{d}\n", .{ frame.source orelse "?", frame.line }) catch continue;
                writeStderr(s);
            }
        }
    }
}

/// Iterates one top-level datum as the sequence of top-level forms it
/// contributes: a `begin` or a matched `cond-expand` contributes its body's
/// forms, recursively; every other form contributes just itself.
///
/// Compile-only drivers (`kaappi --compile`, `kaappi --disassemble`) use this
/// so those bodies are **compiled** rather than **evaluated**. Routing them
/// through `handleTopLevelForm` ran user code while producing the artifact, so
/// `(begin (delete-file "x"))` deleted the file at compile time — and again at
/// run time from the preamble the artifact records (#2156). `check.zig` splices
/// the same two heads for the same reason, by hand.
///
/// Every Value handed out is reachable from the `expr` the caller passed, so
/// the caller's single root over `expr` keeps the whole traversal alive and the
/// iterator roots nothing itself. Nesting is held on the heap rather than the
/// native stack, so arbitrarily deep `(begin (begin ...))` cannot overflow it.
pub const TopLevelForms = struct {
    vm: *vm_mod.VM,
    allocator: std.mem.Allocator,
    /// The not-yet-visited tail of each spliced body, innermost last.
    stack: std.ArrayList(types.Value),
    /// The datum the caller passed, before its first `next()`.
    root: ?types.Value,

    pub fn init(vm: *vm_mod.VM, allocator: std.mem.Allocator, expr: types.Value) TopLevelForms {
        return .{ .vm = vm, .allocator = allocator, .stack = .empty, .root = expr };
    }

    pub fn deinit(self: *TopLevelForms) void {
        self.stack.deinit(self.allocator);
    }

    /// The next form, or null once the datum is exhausted. An error means a
    /// malformed `cond-expand` — the same error `eval` reports for it.
    pub fn next(self: *TopLevelForms) ?(vm_mod.VMError!types.Value) {
        while (self.take()) |form| {
            const spliced = self.vm.topLevelSpliceBody(form) orelse return form;
            const body = spliced catch |err| return err;
            self.stack.append(self.allocator, body) catch return vm_mod.VMError.OutOfMemory;
        }
        return null;
    }

    fn take(self: *TopLevelForms) ?types.Value {
        if (self.root) |r| {
            self.root = null;
            return r;
        }
        while (self.stack.items.len > 0) {
            const tail = &self.stack.items[self.stack.items.len - 1];
            if (types.isPair(tail.*)) {
                const form = types.car(tail.*);
                // An improper body tail is silently ignored, matching the
                // leniency of the `handleTopLevelBegin` this mirrors.
                tail.* = types.cdr(tail.*);
                return form;
            }
            _ = self.stack.pop();
        }
        return null;
    }
};

pub fn printSourceSnippet(source: []const u8, line: u32) void {
    if (diagnostic_format == .json) return;
    if (line == 0 or source.len == 0) return;
    var current_line: u32 = 1;
    var line_start: usize = 0;
    for (source, 0..) |c, i| {
        if (current_line == line) {
            var line_end = i;
            while (line_end < source.len and source[line_end] != '\n') : (line_end += 1) {}
            const snippet = source[line_start..line_end];
            if (snippet.len > 0) {
                writeStderr("    ");
                writeStderr(snippet);
                writeStderr("\n");
            }
            return;
        }
        if (c == '\n') {
            current_line += 1;
            line_start = i + 1;
        }
    }
    if (current_line == line and line_start < source.len) {
        writeStderr("    ");
        writeStderr(source[line_start..]);
        writeStderr("\n");
    }
}

// ── Source drivers ───────────────────────────────────────────────────────────
//
// The loops that drive top-level forms from a concrete source: run a script
// file (`runFile`, with the bytecode-cache replay), stdin (`runStdin`),
// compile one to an artifact (`compileFile`), disassemble one
// (`disassembleFile`), and the `kaappi test` worker wrapper
// (`runWorkerFile`). main.zig keeps process entry, CLI parsing, VM setup and
// mode dispatch; everything past that dispatch lives here. Each loop reports
// through the diagnostics above and records unrecovered failures in
// `script_had_error`, which the exit points of the process turn into the
// run's status (#2512) and into `--compile`'s no-artifact rule (#2513).

// Multiple values print one per line, matching other Scheme REPLs
// (Chez, Guile, Racket, Chibi). Void results print nothing.
pub fn printTopLevelResult(allocator: std.mem.Allocator, result: types.Value) void {
    if (types.isMultipleValues(result)) {
        const mv = types.toObject(result).as(types.MultipleValues);
        for (mv.values) |val| printSingleResult(allocator, val);
    } else {
        printSingleResult(allocator, result);
    }
}

fn printSingleResult(allocator: std.mem.Allocator, value: types.Value) void {
    if (value == types.VOID) return;
    const s = printer.valueToString(allocator, value, .write) catch return;
    defer allocator.free(s);
    writeStdout(s);
    writeStdout("\n");
}

fn readFileContents(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    if (comptime !is_wasm) {
        const path_z = allocator.dupeZ(u8, path) catch return error.OutOfMemory;
        defer allocator.free(path_z);
        if (platform.isDir(path_z)) {
            std.debug.print("Error: '{s}' is a directory\n", .{path});
            return error.IsDir;
        }
    }

    return file_utils.readWholeFile(allocator, path, 1024 * 1024) catch |err| {
        switch (err) {
            error.FileNotFound => std.debug.print("Error opening file '{s}'\n", .{path}),
            error.StreamTooLong => std.debug.print("File too large\n", .{}),
            error.InputOutput => std.debug.print("Error reading file '{s}'\n", .{path}),
            else => std.debug.print("Error reading file '{s}'\n", .{path}),
        }
        return err;
    };
}

fn readAllStdin(allocator: std.mem.Allocator) ![]u8 {
    const max_size: usize = 10 * 1024 * 1024;
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    var tmp: [4096]u8 = undefined;
    while (true) {
        const raw = platform.read(0, &tmp, tmp.len);
        if (raw == 0) break;
        if (raw < 0) {
            if (platform.errno(raw) == .INTR) continue;
            break;
        }
        const bytes_read: usize = @intCast(raw);
        if (result.items.len + bytes_read > max_size) return error.StreamTooLong;
        result.appendSlice(allocator, tmp[0..bytes_read]) catch |err| return err;
    }
    return result.toOwnedSlice(allocator);
}

fn getSbcPath(allocator: std.mem.Allocator, scm_path: []const u8) ![]u8 {
    return bytecode_file.getSbcPath(allocator, scm_path);
}

/// `--compile` writes an artifact the user asked for by name, so a refused
/// constant (kaappi#2113) must fail loudly with the reason — the old behavior
/// wrote an artifact whose embedded bytecode the loader would reject at run
/// time, which surfaced as "invalid embedded bytecode" long after the fact.
fn reportBytecodeWriteError(err: anyerror) void {
    switch (err) {
        error.LimitExceeded => writeStderr("error: a constant exceeds the .sbc format limits (nesting deeper than 256, or an oversized literal) and cannot be serialized\n"),
        error.UnsupportedConstant => writeStderr("error: a constant cannot be represented in the .sbc format\n"),
        else => writeStderr("Error writing bytecode file\n"),
    }
}

/// SRFI 59/193: absolute-ize `path` without following symlinks -- a pure
/// lexical join+normalize (`.`/`..` collapsed) against the process's
/// starting cwd, never a `realpath`-style syscall. Returns `null` (rather
/// than propagating an allocation failure) on the rare case `getCwd` itself
/// fails; callers treat that identically to "not running a script".
fn resolveScriptPath(allocator: std.mem.Allocator, path: []const u8) ?[]const u8 {
    if (std.fs.path.isAbsolute(path)) {
        // Still route through `resolve` -- an already-absolute input like
        // "/tmp/../app.scm" must still have its `.`/`..` collapsed to honor
        // the documented normalization contract; `resolve` is pure lexical
        // manipulation (no cwd needed, no symlink resolution) either way.
        return std.fs.path.resolve(allocator, &.{path}) catch null;
    }
    var buf: [platform.PATH_MAX]u8 = undefined;
    const cwd = platform.getCwd(&buf) orelse return null;
    return std.fs.path.resolve(allocator, &.{ cwd, path }) catch null;
}

/// Execute one cached top-level function and report its result/error exactly
/// as the fresh-compile loop does: the #1922 line fallback, the source
/// snippet, the stack trace, and `printTopLevelResult`. Shared by the v13
/// slot replay (kaappi#1888) and the pre-slot legacy path.
fn runCachedTopLevelFunc(vm: *vm_mod.VM, func: *types.Function, source: []const u8, path: []const u8) !void {
    const allocator = vm.gc.allocator;
    var func_val = types.makePointer(&func.header);
    vm.gc.pushRoot(&func_val);
    timings.begin(.execute);
    const exec_result = vm.execute(func);
    timings.end();
    const result = exec_result catch |err| {
        vm.gc.popRoot();
        script_had_error = true;
        // kaappi#1922: fall back to the form's own line — serialized as
        // Function.source_line — exactly as the fresh-compile path passes
        // datum_lc.line, so an error with no line-table entry (raise,
        // division by zero) keeps its location and snippet on a cache HIT.
        const loc = vmErrorLocation(vm, path, func.source_line);
        reportRuntimeError(vm, err, loc);
        printSourceSnippet(source, loc.line);
        printStackTrace(vm);
        return;
    };
    vm.gc.popRoot();
    printTopLevelResult(allocator, result);
}

pub fn runFile(vm: *vm_mod.VM, path: []const u8) !void {
    const allocator = vm.gc.allocator;

    // Per-run include/dependency records for this file's cache entry
    // (kaappi#1888 review): every file-backed library it imports and every
    // file a top-level include reads. Cleared again once the entry is
    // written (or the run declines).
    vm_library_cache_mod.beginRunRecording(vm);
    defer vm_library_cache_mod.clearRunRecords(vm);

    // Resolve top-level `(include ...)` paths relative to the program's directory.
    const saved_lib_dir = vm.current_lib_dir;
    vm.current_lib_dir = if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| path[0 .. pos + 1] else "";
    defer vm.current_lib_dir = saved_lib_dir;

    // SRFI 59/193: resolve the script's absolute path once, up front. Free
    // any previous value first -- runFile only ever runs on the root VM
    // (owns_globals == true; threads run a thunk, never a file), so this
    // never races a child VM's borrowed reference (see the field doc in
    // vm.zig), but a future caller running more than one file per process
    // must not leak the prior allocation.
    if (vm.script_path) |old| allocator.free(old);
    vm.script_path = resolveScriptPath(allocator, path);

    // Crash breadcrumb (kaappi#1514): name the file once; stages update per-form.
    crash.noteFile(path);

    const source = readFileContents(allocator, path) catch {
        script_had_error = true;
        return;
    };
    defer allocator.free(source);

    const source_hash = bytecode_file.sourceHash(source);

    // Try loading cached bytecode from the central cache (~/.kaappi/cache).
    // Skipped in sandbox mode (no filesystem side effects) and under
    // --no-ir-opt (cache keys don't include the flag, so a no-opt run must
    // neither reuse optimized bytecode nor write unoptimized bytecode that a
    // later optimized run would load). pathForSource returns null when there
    // is no home dir to cache in — then this run just compiles from source.
    const sbc_path = if (vm.sandbox_mode or !ir_mod.optimize_enabled) null else cache.pathForSource(allocator, path);
    defer if (sbc_path) |p| allocator.free(p);

    // `--timings` (kaappi#1515): record why caching was skipped entirely, so the
    // report never leaves the cache line blank. HIT/MISS are recorded below.
    if (sbc_path == null) {
        if (vm.sandbox_mode) {
            timings.cacheOff("sandbox");
        } else if (!ir_mod.optimize_enabled) {
            timings.cacheOff("--no-ir-opt");
        } else {
            timings.cacheOff("no home dir");
        }
    }

    if (sbc_path) |sp| {
        if (bytecode_file.readFileWithTopLevel(vm.gc, source_hash, sp) catch null) |loaded_const| {
            var loaded = loaded_const;
            // Kind check (#1888 review): a LIBRARY entry shares this cache key
            // with running the .sld directly, and its functions are library
            // body thunks — replaying them as a program would run them with
            // no env and no transformer registrations. Only a program entry
            // with a slot stream is replayable here.
            if (loaded.entry_kind != bytecode_file.ENTRY_PROGRAM or loaded.slots == null) {
                vm_library_cache_mod.dropDeserializeRoots(vm.gc, &loaded);
                bytecode_file.freeDeserializeResult(allocator, &loaded);
            } else if (!vm_library_cache_mod.recordsValid(
                vm,
                loaded.includes orelse &.{},
                loaded.deps orelse &.{},
            )) {
                // Stale program entry: a file-backed library it imported, or a
                // top-level include file it read, changed since the entry was
                // written. The compiled slots embed those macro expansions, so
                // this must be an ordinary miss (nothing has executed yet).
                timings.cacheReason("stale dependency");
                vm_library_cache_mod.dropDeserializeRoots(vm.gc, &loaded);
                bytecode_file.freeDeserializeResult(allocator, &loaded);
            } else {
                timings.cacheHit(sp);
                defer bytecode_file.freeDeserializeResult(allocator, &loaded);

                var bundled_files_map = loaded.bundled_files orelse std.StringHashMap([]const u8).init(allocator);
                defer {
                    var bfit = bundled_files_map.iterator();
                    while (bfit.next()) |entry| {
                        allocator.free(entry.key_ptr.*);
                        allocator.free(entry.value_ptr.*);
                    }
                    bundled_files_map.deinit();
                }
                if (loaded.bundled_files != null) {
                    vm.bundled_files = &bundled_files_map;
                }
                defer vm.bundled_files = null;

                if (loaded.preamble) |preamble| {
                    defer {
                        for (preamble) |p| allocator.free(p);
                        allocator.free(preamble);
                    }
                    for (preamble) |src| {
                        var pr = reader_mod.Reader.init(vm.gc, src);
                        defer pr.deinit();
                        while (pr.hasMore() catch break) {
                            var expr = pr.readDatum() catch break;
                            vm.gc.pushRoot(&expr);
                            defer vm.gc.popRoot();
                            timings.begin(.execute); // preamble replay re-runs imports (kaappi#1515)
                            const top = vm.handleTopLevelForm(expr);
                            timings.end();
                            if (top) |top_result| {
                                _ = top_result catch {};
                            }
                        }
                    }
                }

                // Set source_name on all loaded functions — the path is valid
                // for the entire runFile scope, matching the fresh-compile path
                // where the compiler sets source_name to the same pointer.
                for (loaded.funcs) |func| {
                    func.source_name = path;
                }

                crash.noteStage(.executing);

                // v13 program entries (kaappi#1888) replay through positional
                // slots: a compiled function, or a declaration's verbatim source
                // re-dispatched through handleTopLevelForm — in the exact
                // top-level order, so an `import` between two defines stays
                // between them (no preamble hoisting, the #2200 reorder class).
                // Older-format entries are unreachable: the VERSION check
                // rejects them, and the kind/slots check above is what admits a
                // replayable entry.
                {
                    for (loaded.slots.?) |slot| {
                        switch (slot) {
                            .function => |idx| {
                                if (idx >= loaded.top_level_count) continue;
                                const func = loaded.funcs[idx];
                                try runCachedTopLevelFunc(vm, func, source, path);
                            },
                            .declaration => |decl| {
                                var dr = reader_mod.Reader.init(vm.gc, decl.src);
                                // A `#!fold-case` directive falls inside an earlier
                                // form's span; the slot carries the reader state
                                // that applied when the form was read (#1888
                                // review).
                                dr.fold_case = decl.fold_case;
                                defer dr.deinit();
                                while (dr.hasMore() catch break) {
                                    var dexpr = dr.readDatum() catch break;
                                    vm.gc.pushRoot(&dexpr);
                                    defer vm.gc.popRoot();
                                    crash.noteStage(.executing);
                                    timings.begin(.execute);
                                    // The cold run recorded this slot because
                                    // handleTopLevelForm claimed the form; the
                                    // replayed imports restore the same macro
                                    // state, so it is claimed again. The
                                    // compile-and-run fallback keeps an unclaimed
                                    // form correct rather than silently dropped.
                                    if (vm.topLevelHead(dexpr)) |head| {
                                        const result = vm.runTopLevelHead(head, dexpr) catch |err| {
                                            timings.end();
                                            script_had_error = true;
                                            reportRuntimeError(vm, err, .{ .source = path, .line = decl.line });
                                            continue;
                                        };
                                        timings.end();
                                        printTopLevelResult(allocator, result);
                                        continue;
                                    }
                                    const func = compiler_mod.compileExpressionWithMacrosAt(vm.gc, dexpr, &vm.macros, vm.globals, decl.line, path, false) catch |err| {
                                        timings.end();
                                        script_had_error = true;
                                        reportCompileError(path, decl.line, 1, err);
                                        continue;
                                    };
                                    timings.end();
                                    try runCachedTopLevelFunc(vm, func, source, path);
                                }
                            },
                        }
                    }
                    return;
                } // slot replay
            } // kind/records-validated replay (else branch)
        }
    }

    // No cache — compile from source. A non-null sbc_path here means the cache
    // was consulted and missed (kaappi#1515); the write below marks it written.
    if (sbc_path) |sp| timings.cacheMiss(sp);

    var compiled_funcs: std.ArrayList(*types.Function) = .empty;
    defer compiled_funcs.deinit(allocator);
    // The positional replay stream (kaappi#1888): one slot per top-level form,
    // function or declaration, in order. Owned src slices freed with the list.
    var slots: std.ArrayList(bytecode_file.Slot) = .empty;
    defer {
        for (slots.items) |*s| {
            if (s.* == .declaration) allocator.free(s.declaration.src);
        }
        slots.deinit(allocator);
    }
    var defines_syntax = false;
    var had_compile_error = false;

    var r = reader_mod.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    crash.noteStage(.reading);
    while (r.hasMore() catch |err| {
        const lc = r.getLineCol();
        reportReadError(path, lc.line, lc.col, err);
        script_had_error = true;
        return;
    }) {
        crash.noteStage(.reading);
        const datum_lc = r.getLineCol();
        // Byte span of this form (leading trivia included — it re-parses to
        // the same datum), for the declaration replay slot (kaappi#1888).
        const span_start = r.pos;
        timings.begin(.read);
        const read_result = r.readDatum();
        timings.end();
        const span_end = r.pos;
        var expr = read_result catch |err| {
            const lc = r.getLineCol();
            reportReadError(path, lc.line, lc.col, err);
            script_had_error = true;
            return;
        };

        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();

        // A top-level declaration — import/define-library/include runs library
        // code here; the other five heads are interpreted directly. Classify
        // before dispatching: evaluating one form can change how the next is
        // classified, so the head and its handler must be read from the same
        // moment (#2114). Since #1888 these are cacheable as declaration
        // slots: the HIT re-reads the verbatim source span and re-dispatches
        // it, positionally — library loads hit their own .sld entries.
        if (vm.topLevelHead(expr)) |head| {
            // Structure flag: a top-level include reached from here is the
            // MAIN file's structure, so its file feeds the run recorder (the
            // macro an included file defines is baked into later compiled
            // slots — kaappi#1888 review). A runtime `(eval "(include …)")`
            // inside a function keeps depth 0 and records nothing.
            vm.lib_structure_depth += 1;
            defer vm.lib_structure_depth -= 1;
            if (sbc_path != null and !defines_syntax and !had_compile_error) {
                const src_copy = allocator.dupe(u8, source[span_start..span_end]) catch return error.OutOfMemory;
                slots.append(allocator, .{ .declaration = .{ .line = datum_lc.line, .src = src_copy, .fold_case = r.fold_case } }) catch {
                    allocator.free(src_copy);
                    return error.OutOfMemory;
                };
            }
            crash.noteStage(.executing);
            timings.begin(.execute);
            const top_result = vm.runTopLevelHead(head, expr);
            timings.end();
            const result = top_result catch |err| {
                script_had_error = true;
                reportRuntimeError(vm, err, .{ .source = path, .line = datum_lc.line });
                continue;
            };
            printTopLevelResult(allocator, result);
            continue;
        }

        crash.noteStage(.compiling);
        // kaappi#2112: `define-syntax` / `define-property` register into the
        // VM's macro and syntax-property tables as a side effect of
        // *compilation* and emit no bytecode that would replay them, so a
        // cache HIT (which compiles nothing) leaves both tables empty and a
        // run-time `eval` diverges from the cold run. Detect the side effect
        // semantically — did compiling this form grow either table? — which
        // also covers a macro use that expands into a `define-syntax`.
        const macros_before = vm.macros.count();
        const props_before = vm.syntax_properties.count();
        const compile_result = compiler_mod.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, datum_lc.line, path, false);
        if (vm.macros.count() != macros_before or vm.syntax_properties.count() != props_before)
            defines_syntax = true;
        const func = compile_result catch |err| {
            reportCompileError(path, datum_lc.line, datum_lc.col, err);
            script_had_error = true;
            had_compile_error = true;
            continue;
        };

        compiled_funcs.append(allocator, func) catch return error.OutOfMemory;
        vm.gc.extra_roots.append(allocator, types.makePointer(&func.header)) catch return error.OutOfMemory;
        if (sbc_path != null and !defines_syntax and !had_compile_error) {
            slots.append(allocator, .{ .function = @intCast(compiled_funcs.items.len - 1) }) catch return error.OutOfMemory;
        }

        var func_val = types.makePointer(&func.header);
        vm.gc.pushRoot(&func_val);

        crash.noteStage(.executing);
        timings.begin(.execute);
        const exec_result = vm.execute(func);
        timings.end();
        const result = exec_result catch |err| {
            vm.gc.popRoot();
            script_had_error = true;
            const loc = vmErrorLocation(vm, path, datum_lc.line);
            reportRuntimeError(vm, err, loc);
            printSourceSnippet(source, loc.line);
            printStackTrace(vm);
            continue;
        };
        vm.gc.popRoot();

        printTopLevelResult(allocator, result);
    }

    // Cache compiled bytecode. Skipped in three cases.
    //
    // No compiled form AND no declaration (an empty or comment-only file).
    //
    // A form that registered a macro or syntax property at compile time (a HIT
    // would not replay the registration and run-time `eval` would diverge —
    // kaappi#2112), and any form that failed to compile (a HIT would silently
    // run the partial program with exit 0 where the cold run reported the error
    // with exit 1). Both also stop SLOT RECORDING mid-file (the guards in the
    // loop above), so a poisoned prefix can never pair with a clean suffix.
    //
    // The eight top-level declaration heads no longer refuse anything
    // (kaappi#1888): each becomes a declaration slot — its verbatim source
    // span, replayed positionally through the same dispatch on a HIT — while
    // `import`/`define-library`/`include` inside them hit the per-.sld library
    // cache. Best-effort: a failed write (read-only home, etc.) just means the
    // next run recompiles.
    // vm.run_cache_ok is false when some imported library declined caching
    // or could not write its entry: no record would ever validate it, so a
    // program entry here would serve stale compiled slots forever (#1888
    // review).
    if (!vm_library_cache_mod.runCacheOk(vm) and sbc_path != null) {
        timings.cacheReason("uncacheable dependency");
    }
    if (vm_library_cache_mod.runCacheOk(vm) and !defines_syntax and !had_compile_error and (compiled_funcs.items.len > 0 or slots.items.len > 0)) {
        if (sbc_path) |sp| {
            cache.ensureDir();
            if (bytecode_file.writeFileWithSlots(allocator, compiled_funcs.items, slots.items, vm.run_cache_includes.items, vm.run_cache_deps.items, source_hash, path, sp)) |_| {
                timings.cacheWrote(); // kaappi#1515: the miss's bytecode is now cached
            } else |err| switch (err) {
                // kaappi#2113: the writer refuses entries the reader would
                // reject rather than truncating them, so a permanent-miss
                // entry is never written — record why for `--timings`.
                error.LimitExceeded => timings.cacheReason("constant exceeds .sbc limits"),
                error.UnsupportedConstant => timings.cacheReason("unsupported constant"),
                else => {},
            }
        }
    } else if (sbc_path != null) {
        // A miss was recorded but nothing will be written — say why (#2114).
        if (defines_syntax) {
            timings.cacheReason("define-syntax");
        } else if (had_compile_error) {
            timings.cacheReason("compile error");
        }
    }
}

/// `kaappi test` worker path: install the collecting SRFI-64 runner, run the
/// file, then emit its one JSON result object. `suppress_exit` lets a file's
/// `(exit 1)` — or `(emergency-exit …)`, kaappi#2521 — epilogue be recorded
/// instead of terminating the worker before it reports. The worker always
/// exits 0 — the orchestrator reads pass/fail from the emitted JSON, not from
/// this process's status (a missing/empty result is what signals a crash).
pub fn runWorkerFile(vm: *vm_mod.VM, fp: []const u8, emit_path: []const u8) !void {
    vm.suppress_exit = true;
    test_runner.installCollector(vm) catch {
        test_runner.emitResult(vm, emit_path, fp, true, "test collector setup failed", 0);
        script_had_error = false;
        return;
    };

    const start_ns = @import("vm_calls.zig").clockNs();
    script_had_error = false;
    runFile(vm, fp) catch {
        script_had_error = true;
    };
    const duration_ms = @as(f64, @floatFromInt(@import("vm_calls.zig").clockNs() -| start_ns)) / 1_000_000.0;

    // `script_had_error` means an *uncaught*
    // read/compile/runtime error at top level — SRFI-64 catches test
    // failures internally, so those never set it. Whether that makes the
    // file errored is `test_runner.resolveVerdict`'s call, not ours:
    // `suppress_exit` above swallowed any `(exit)` the file made, and that
    // call's semantics still have to be applied (kaappi#1903).
    test_runner.emitResult(vm, emit_path, fp, script_had_error, null, duration_ms);
    // The result is emitted; don't let the file's error propagate to a nonzero
    // worker exit — the orchestrator uses the JSON.
    script_had_error = false;
}

pub fn runStdin(vm: *vm_mod.VM) !void {
    const allocator = vm.gc.allocator;
    const source = readAllStdin(allocator) catch {
        writeStderr("error: failed to read stdin\n");
        script_had_error = true;
        return;
    };
    defer allocator.free(source);

    crash.note(.reading, "<stdin>");

    var r = reader_mod.Reader.initWithName(vm.gc, source, "<stdin>");
    defer r.deinit();

    while (r.hasMore() catch |err| {
        const lc = r.getLineCol();
        reportReadError("<stdin>", lc.line, lc.col, err);
        script_had_error = true;
        return;
    }) {
        crash.noteStage(.reading);
        // Capture the datum's start position before reading it, so a compile
        // error with no recorded span still falls back to the form's start
        // column (not the post-datum position) — kaappi#1506.
        const datum_lc = r.getLineCol();
        var expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            reportReadError("<stdin>", lc.line, lc.col, err);
            script_had_error = true;
            return;
        };

        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();

        crash.noteStage(.executing);
        if (vm.handleTopLevelForm(expr)) |top_result| {
            const result = top_result catch |err| {
                script_had_error = true;
                reportRuntimeError(vm, err, null);
                continue;
            };
            printTopLevelResult(allocator, result);
            continue;
        }

        crash.noteStage(.compiling);
        const func = compiler_mod.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, datum_lc.line, "<stdin>", false) catch |err| {
            reportCompileError("<stdin>", datum_lc.line, datum_lc.col, err);
            script_had_error = true;
            return;
        };

        var func_val = types.makePointer(&func.header);
        vm.gc.pushRoot(&func_val);

        crash.noteStage(.executing);
        const result = vm.execute(func) catch |err| {
            vm.gc.popRoot();
            script_had_error = true;
            reportRuntimeError(vm, err, null);
            continue;
        };
        vm.gc.popRoot();

        printTopLevelResult(allocator, result);
    }
}

pub fn disassembleFile(vm: *vm_mod.VM, path: []const u8) !void {
    const allocator = vm.gc.allocator;
    const source = readFileContents(allocator, path) catch {
        script_had_error = true;
        return;
    };
    defer allocator.free(source);

    const saved_lib_dir = vm.current_lib_dir;
    vm.current_lib_dir = if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| path[0 .. pos + 1] else "";
    defer vm.current_lib_dir = saved_lib_dir;

    var r = reader_mod.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    while (r.hasMore() catch |err| {
        const lc = r.getLineCol();
        reportReadError(path, lc.line, lc.col, err);
        script_had_error = true;
        return;
    }) {
        const datum_lc = r.getLineCol();
        var expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            reportReadError(path, lc.line, lc.col, err);
            script_had_error = true;
            return;
        };

        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();

        // Same compile-only discipline as `--compile` (#2156): splice
        // `begin` / `cond-expand` so their bodies are disassembled rather than
        // run, and evaluate only the declarations the compiler depends on.
        var forms = TopLevelForms.init(vm, allocator, expr);
        defer forms.deinit();
        while (forms.next()) |form_result| {
            const form = form_result catch |err| {
                script_had_error = true;
                reportRuntimeError(vm, err, .{ .source = path, .line = datum_lc.line });
                continue;
            };

            if (vm.topLevelHead(form)) |head| {
                if (!head.isEnvSetup()) continue;
                _ = vm.runTopLevelHead(head, form) catch |err| {
                    script_had_error = true;
                    reportRuntimeError(vm, err, .{ .source = path, .line = datum_lc.line });
                };
                continue;
            }

            const func = compiler_mod.compileExpressionWithMacrosAt(vm.gc, form, &vm.macros, vm.globals, datum_lc.line, path, false) catch |err| {
                reportCompileError(path, datum_lc.line, datum_lc.col, err);
                script_had_error = true;
                continue;
            };

            const disasm = @import("disassembler.zig");
            disasm.disassemble(func, allocator);
        }
    }
}

/// Best-effort unlink of an artifact target (#2513): silent on any failure —
/// the error that caused the cleanup was already reported at its site, so a
/// removal failure (permissions, a path over PATH_MAX) has nothing to add.
fn unlinkQuiet(path: []const u8) void {
    var pbuf: [platform.PATH_MAX]u8 = undefined;
    if (std.fmt.bufPrintZ(&pbuf, "{s}", .{path})) |pz| {
        _ = platform.unlink(pz);
    } else |_| {}
}

pub fn compileFile(vm: *vm_mod.VM, path: []const u8, output_path: ?[]const u8) !void {
    const allocator = vm.gc.allocator;

    // The artifact target is decided up front so a failure anywhere below can
    // still leave the target clean (#2513): a failed compile must leave NO
    // file at the exact -o / derived-.sbc path — not the truncated one a
    // failed write leaves behind, and not a stale one from a previous good
    // build that the build step would then embed as if it were current.
    const sbc_path = if (output_path) |op|
        allocator.dupe(u8, op) catch {
            writeStderr("Error creating output path\n");
            script_had_error = true;
            // This exit predates the cleanup defer below, but the -o target
            // is known even here: leave it clean (#2513), or a stale
            // artifact from a previous good build outlives this failed run
            // looking current.
            unlinkQuiet(op);
            return;
        }
    else
        getSbcPath(allocator, path) catch {
            writeStderr("Error creating output path\n");
            script_had_error = true;
            // The derived-.sbc target could not be computed, so there is
            // nothing to clean; the -o arm above is the one with a name.
            return;
        };
    defer allocator.free(sbc_path);
    // Runs before the free above (LIFO): best-effort, and deliberately only
    // the exact target — the error itself was already reported at its site,
    // so a removal failure (permissions) has nothing further to add.
    // Keyed on whether THIS call wrote the artifact, not on
    // script_had_error: the `try`/OOM exits below (the preamble's
    // valueToString and append, the compiled-funcs append) return without
    // setting the flag, and they must not leave a previous good build's
    // artifact at the target looking current either (kaappi#2513 review).
    var wrote_artifact = false;
    defer if (!wrote_artifact) unlinkQuiet(sbc_path);

    const source = readFileContents(allocator, path) catch {
        script_had_error = true;
        return;
    };
    defer allocator.free(source);

    const source_hash = bytecode_file.sourceHash(source);

    // Resolve top-level `(include ...)` paths relative to the program's directory.
    const saved_lib_dir = vm.current_lib_dir;
    vm.current_lib_dir = if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| path[0 .. pos + 1] else "";
    defer vm.current_lib_dir = saved_lib_dir;

    // Collect library files for bundling
    var collect_files = std.StringHashMap([]const u8).init(allocator);
    defer {
        var it = collect_files.iterator();
        while (it.next()) |entry| {
            allocator.free(entry.key_ptr.*);
            allocator.free(entry.value_ptr.*);
        }
        collect_files.deinit();
    }
    vm.compile_collect_files = &collect_files;
    defer vm.compile_collect_files = null;

    // Collect preamble (top-level forms: import, include, define-library)
    var preamble: std.ArrayList([]const u8) = .empty;
    defer {
        for (preamble.items) |p| allocator.free(p);
        preamble.deinit(allocator);
    }

    var compiled_funcs: std.ArrayList(*types.Function) = .empty;
    defer compiled_funcs.deinit(allocator);

    var r = reader_mod.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    while (r.hasMore() catch |err| {
        const lc = r.getLineCol();
        reportReadError(path, lc.line, lc.col, err);
        script_had_error = true;
        return;
    }) {
        const datum_lc = r.getLineCol();
        timings.begin(.read); // kaappi#1515
        const read_result = r.readDatum();
        timings.end();
        var expr = read_result catch |err| {
            const lc = r.getLineCol();
            reportReadError(path, lc.line, lc.col, err);
            script_had_error = true;
            return;
        };

        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();

        // Splice top-level `begin` / `cond-expand` instead of evaluating them:
        // their bodies are ordinary program code and belong in the bytecode,
        // not in this process (#2156).
        var forms = TopLevelForms.init(vm, allocator, expr);
        defer forms.deinit();
        while (forms.next()) |form_result| {
            const form = form_result catch |err| {
                script_had_error = true;
                reportRuntimeError(vm, err, .{ .source = path, .line = datum_lc.line });
                continue;
            };

            if (vm.topLevelHead(form)) |head| {
                // Only the env-setup declarations belong in the preamble, which
                // the artifact replays *before* any compiled form. `import` /
                // `include` / `include-ci` / `define-library` /
                // `define-record-type` establish the environment later forms
                // are compiled against, so hoisting them ahead of the compiled
                // stream is exactly what a preamble is for.
                //
                // `define-values` is NOT env setup: its producer is arbitrary
                // program code that can depend on earlier forms, so hoisting it
                // into the preamble reorders execution and can fail where the
                // interpreter succeeds (#2200). It has a compilable lowering
                // (`compileDefineValues`), so let it fall through to ordinary
                // compilation and keep its position in the compiled stream.
                // `begin` and `cond-expand` never reach here; TopLevelForms
                // already spliced them.
                if (head.isEnvSetup()) {
                    // Record the declaration for replay when the artifact runs.
                    // Propagate an allocation failure rather than dropping the
                    // form: silently continuing here writes an artifact missing
                    // an `import`, then prints `Compiled ... -> ...` and exits 0.
                    // `runFile`'s equivalent site returns error.OutOfMemory too.
                    const form_src = try printer.valueToString(allocator, form, .write);
                    preamble.append(allocator, form_src) catch {
                        allocator.free(form_src);
                        return error.OutOfMemory;
                    };
                    _ = vm.runTopLevelHead(head, form) catch |err| {
                        script_had_error = true;
                        reportRuntimeError(vm, err, .{ .source = path, .line = datum_lc.line });
                    };
                    continue;
                }
            }

            const func = compiler_mod.compileExpressionWithMacrosAt(vm.gc, form, &vm.macros, vm.globals, datum_lc.line, path, false) catch |err| {
                reportCompileError(path, datum_lc.line, datum_lc.col, err);
                script_had_error = true;
                continue;
            };

            // Likewise: dropping a compiled top-level form here would emit an
            // artifact silently missing that code.
            compiled_funcs.append(allocator, func) catch return error.OutOfMemory;
        }
    }

    // A run that reported any uncaught error must not write an artifact or
    // claim success (#2513): the driver recovers from each error and keeps
    // compiling, so `compiled_funcs` here can be a plausible-looking partial
    // bundle — an import that failed at evaluation time, everything after it
    // missing or uncompilable. The exit-status rule already fails the run;
    // writing the artifact anyway would replace a previous good build at the
    // target with the broken one (or leave a stale one, via the defer above)
    // and the `Compiled ... -> ...` line would tell a stdout-reading build
    // step that it worked.
    if (script_had_error) return;

    if (compiled_funcs.items.len > 0 or preamble.items.len > 0) {
        timings.setOutput(sbc_path); // kaappi#1515: the named .sbc artifact

        const has_bundle = collect_files.count() > 0 or preamble.items.len > 0;
        if (has_bundle) {
            bytecode_file.writeFileWithBundle(
                allocator,
                compiled_funcs.items,
                source_hash,
                path,
                &collect_files,
                preamble.items,
                sbc_path,
            ) catch |err| {
                reportBytecodeWriteError(err);
                script_had_error = true;
                return;
            };
        } else {
            bytecode_file.writeFileWithTopLevel(allocator, compiled_funcs.items, source_hash, path, sbc_path) catch |err| {
                reportBytecodeWriteError(err);
                script_had_error = true;
                return;
            };
        }

        // Both write arms return internally on failure, so reaching here
        // means the artifact landed — this is what keys the cleanup defer
        // above, and it is only true on the path that prints `Compiled`.
        wrote_artifact = true;

        writeStdout("Compiled ");
        writeStdout(path);
        writeStdout(" -> ");
        writeStdout(sbc_path);
        writeStdout("\n");
    }
}

// ── #2513 regression tests ──────────────────────────────────────────────────
//
// Drive the real `--compile` driver loop over real files. The shell-level
// twin, which also asserts the exit status and the missing `Compiled ...`
// line, is tests/scheme/errors/compile-failure-signals-2513.sh.
//
// Both compileFile tests route their expected output away from the real
// stdio: the success case's `Compiled ... -> ...` line must not reach fd 1
// (th.QuietStdout — under `zig build test` that fd is the build runner's
// server-protocol channel, and a raw write into it wedges the runner; see
// the helper's doc comment), and the failure case's KP diagnostics must not
// reach fd 2 (th.QuietStderr — expected-error output renders a green run
// like a crash, kaappi#2447).

test "compileFile: failed compile leaves no artifact and sets the flag (#2513)" {
    if (comptime is_wasm) return error.SkipZigTest; // writes real files
    const th = @import("testing_helpers.zig");
    const testing = std.testing;

    var tc: th.TestContext = undefined;
    try tc.init();
    defer tc.deinit();
    const allocator = tc.vm.gc.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try th.tmpDirRealPathAlloc(&tmp, allocator);
    defer allocator.free(dir_path);

    // The import fails at evaluation time while the display form still
    // compiles — exactly the shape that used to fall out the loop with a
    // partial function list, write the artifact anyway, and print `Compiled`.
    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "bad.scm",
        .data = "(import (nonexistent-library-2513))\n(display \"this form still compiles\")\n",
    });
    const bad_path = try std.fs.path.join(allocator, &.{ dir_path, "bad.scm" });
    defer allocator.free(bad_path);
    const out_path = try std.fs.path.join(allocator, &.{ dir_path, "out.sbc" });
    defer allocator.free(out_path);

    script_had_error = false;
    defer script_had_error = false;

    // The two KP2001 diagnostics per run are this test's premise, not news:
    // keep them off the runner's captured stderr (kaappi#2447).
    var quiet_err: th.QuietStderr = .{};
    quiet_err.init();
    defer quiet_err.deinit();

    try compileFile(tc.vm, bad_path, out_path);
    try testing.expect(script_had_error);
    try testing.expectError(error.FileNotFound, tmp.dir.statFile(testing.io, "out.sbc", .{}));

    // A stale artifact at the target from a previous good build must be
    // removed by the failed run, not silently kept looking current.
    try tmp.dir.writeFile(testing.io, .{ .sub_path = "out.sbc", .data = "stale artifact" });
    script_had_error = false;
    try compileFile(tc.vm, bad_path, out_path);
    try testing.expect(script_had_error);
    try testing.expectError(error.FileNotFound, tmp.dir.statFile(testing.io, "out.sbc", .{}));
}

test "compileFile: successful compile still writes the artifact (#2513 control)" {
    if (comptime is_wasm) return error.SkipZigTest; // writes real files
    const th = @import("testing_helpers.zig");
    const testing = std.testing;

    var tc: th.TestContext = undefined;
    try tc.init();
    defer tc.deinit();
    const allocator = tc.vm.gc.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try th.tmpDirRealPathAlloc(&tmp, allocator);
    defer allocator.free(dir_path);

    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "good.scm",
        .data = "(import (scheme base))\n(display \"fine\")\n",
    });
    const good_path = try std.fs.path.join(allocator, &.{ dir_path, "good.scm" });
    defer allocator.free(good_path);
    const out_path = try std.fs.path.join(allocator, &.{ dir_path, "out.sbc" });
    defer allocator.free(out_path);

    script_had_error = false;
    defer script_had_error = false;

    // The success path prints `Compiled ... -> ...` on stdout — protocol
    // poison under the build runner (see th.QuietStdout's doc comment). The
    // `Compiled` line itself is pinned end-to-end by the shell twin,
    // tests/scheme/errors/compile-failure-signals-2513.sh; this test's own
    // assertions are the artifact and the flag.
    var quiet_out: th.QuietStdout = .{};
    quiet_out.init();
    defer quiet_out.deinit();

    try compileFile(tc.vm, good_path, out_path);
    try testing.expect(!script_had_error);
    _ = try tmp.dir.statFile(testing.io, "out.sbc", .{});
}

// #2513 review: the cleanup defer keys on `wrote_artifact`, not
// `script_had_error`, because the `try`/OOM exits in between (the preamble's
// valueToString and append, the compiled-funcs append) return without ever
// setting the flag — and they must not leave a previous good build's
// artifact at the target looking current. `GC.oom_countdown` cannot reach
// those sites (they are raw-allocator allocations; see its doc comment: "a
// compile with no macro use in it never fails here"), so the sweep wraps
// `vm.gc.allocator` — a plain field — in `OomAllocator` (#2435), whose own
// countdown fails raw acquisitions. Each `n` lets a different allocation be
// the last to succeed; the invariant under test is that the target holds a
// file exactly when the run completed cleanly.
test "compileFile: an error-return exit still leaves no artifact (#2513 OOM sweep)" {
    if (comptime is_wasm) return error.SkipZigTest;
    const th = @import("testing_helpers.zig");
    const memory_mod = @import("memory.zig");
    const build_options = @import("build_options");
    const testing = std.testing;

    var tc: th.TestContext = undefined;
    try tc.init();
    defer tc.deinit();
    const allocator = tc.vm.gc.allocator;

    var tmp = testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try th.tmpDirRealPathAlloc(&tmp, allocator);
    defer allocator.free(dir_path);

    try tmp.dir.writeFile(testing.io, .{
        .sub_path = "good.scm",
        .data = "(import (scheme base))\n(display \"fine\")\n",
    });
    const good_path = try std.fs.path.join(allocator, &.{ dir_path, "good.scm" });
    defer allocator.free(good_path);
    const out_path = try std.fs.path.join(allocator, &.{ dir_path, "out.sbc" });
    defer allocator.free(out_path);

    var quiet_out: th.QuietStdout = .{};
    quiet_out.init();
    defer quiet_out.deinit();
    // Each failing iteration reports a read/compile diagnostic on stderr —
    // expected, and ~a hundred lines of it over the sweep — so keep it off
    // the runner's captured stderr (kaappi#2447) or a green run of this
    // test renders exactly like a crash in every CI log.
    var quiet_err: th.QuietStderr = .{};
    quiet_err.init();
    defer quiet_err.deinit();

    const saved_allocator = tc.vm.gc.allocator;
    defer tc.vm.gc.allocator = saved_allocator;

    var oom_returns: usize = 0;
    var clean_successes: usize = 0;
    const sweep_max: usize = if (build_options.gc_stress) 24 else 64;
    var n: usize = 0;
    while (n <= sweep_max) : (n += 1) {
        // Plant a stale artifact before every run: the #2513 hazard is a
        // previous good build's file sitting at the target while this run
        // fails, and an ascending sweep without this never has a file to
        // leave — every failure lands before the first success, so a
        // cleanup that never fires would still pass vacuously.
        try tmp.dir.writeFile(testing.io, .{ .sub_path = "out.sbc", .data = "stale artifact" });

        var oom = memory_mod.OomAllocator.init(saved_allocator);
        oom.countdown = n;
        tc.vm.gc.allocator = oom.allocator();
        script_had_error = false;
        const result = compileFile(tc.vm, good_path, out_path);
        tc.vm.gc.allocator = saved_allocator;

        var succeeded = true;
        if (result) |_| {
            clean_successes += 1;
        } else |_| {
            succeeded = false;
            oom_returns += 1;
        }

        // The invariant (#2513): the target holds a file exactly when this
        // run completed with nothing reported. Every other exit — a
        // reported error, or an error-return like OOM — must leave NO file,
        // or a previous good build's artifact sits there looking current.
        const stat = tmp.dir.statFile(testing.io, "out.sbc", .{});
        if (succeeded and !script_had_error) {
            _ = stat catch |err| {
                std.debug.print("clean compile (n={d}) wrote no artifact: {t}\n", .{ n, err });
                return err;
            };
        } else {
            try testing.expectError(error.FileNotFound, stat);
        }
    }

    // Both halves matter, as in the other OOM sweeps: `oom_returns` proves
    // the injector reached the exits this test exists for (a countdown that
    // never fired makes the sweep vacuous), `clean_successes` proves it ran
    // past the whole allocation profile of a good compile.
    try testing.expect(oom_returns > 0);
    try testing.expect(clean_successes > 0);
}
