//! `kaappi test [paths...]` — first-class SRFI-64 test runner (kaappi#1509,
//! part of the machine-legibility epic kaappi#1503).
//!
//! The suite already standardises on SRFI-64; what was missing is a runner an
//! agent or CI can drive and parse without scraping the human report. This
//! module is that runner, in two cooperating roles:
//!
//!  * **Orchestrator** (`maybeRun`) — the `kaappi test` process. It discovers
//!    SRFI-64 suites, runs each in its own worker subprocess, aggregates the
//!    counts the SRFI-64 runner itself reports (never by grepping the
//!    "# of expected passes" lines), and prints a human summary or JSON Lines.
//!    Exit status is nonzero iff a test failed, unexpectedly passed, or a file
//!    errored.
//!
//!  * **Worker** (`workerEmitPath`, `installCollector`, `emitResult`) — a
//!    child `kaappi <file>` invocation with `KAAPPI_TEST_EMIT` set in its
//!    environment. Before the file runs it swaps in a quiet collecting
//!    test-runner (built on `test-runner-null`, so no SRFI-64 chatter and no
//!    `.log` files) whose per-test hook records structured results; afterwards
//!    it writes exactly one JSON object describing the file.
//!
//! Subprocess isolation is deliberate, not incidental: a file that loops,
//! segfaults, leaks a thread, or calls `(exit 1)` in its failure epilogue can
//! neither corrupt the run nor bleed into another file's results. The worker
//! sets `vm.suppress_exit` so that a file's `(exit)` cannot rob it of the
//! chance to emit its result.

const std = @import("std");
const builtin = @import("builtin");
const reporting = @import("reporting.zig");
const lsp_diagnostic = @import("lsp_diagnostic.zig");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const file_utils = @import("file_utils.zig");
const kaappi_paths = @import("kaappi_paths.zig");
const test_selection = @import("test_selection.zig");

const VM = vm_mod.VM;
const Value = types.Value;
const writeStdout = reporting.writeStdout;
const writeStderr = reporting.writeStderr;
const clockNs = @import("vm_calls.zig").clockNs;

pub const USAGE_ERROR_EXIT: u8 = 2;

/// Environment channel between orchestrator and worker. `EMIT_ENV` names the
/// file the worker writes its one JSON result object to (per file, robust to
/// the worker crashing or the test file calling `(exit)`); `SEED_ENV` carries
/// the run-wide SRFI-27 seed.
const EMIT_ENV = "KAAPPI_TEST_EMIT";
const SEED_ENV = "KAAPPI_TEST_SEED";

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

fn getEnv(name: [*:0]const u8) ?[]const u8 {
    const v = std.c.getenv(name) orelse return null;
    return std.mem.span(v);
}

// ── Worker role ────────────────────────────────────────────────────────

/// The Scheme prelude the worker evaluates before running a test file. It
/// installs a collecting test-runner factory so every `test-begin` in the file
/// (there may be several) produces a runner that funnels results into the
/// `%kt-*` accumulators. Built on `test-runner-null`, so the SRFI-64 machinery
/// prints nothing and writes no log file — this runner speaks only through the
/// accumulators, which `%kt-collect` hands back to Zig as one vector.
const collector_prelude =
    \\(import (scheme base) (scheme write) (srfi 64))
    \\(define %kt-pass 0)
    \\(define %kt-fail 0)
    \\(define %kt-xpass 0)
    \\(define %kt-xfail 0)
    \\(define %kt-skip 0)
    \\(define %kt-suite #f)
    \\(define %kt-failures '())
    \\(define (%kt-render x)
    \\  (let ((p (open-output-string)))
    \\    (write x p)
    \\    (get-output-string p)))
    \\(define (%kt-name->string x)
    \\  (cond ((eq? x #f) #f)
    \\        ((string? x) x)
    \\        (else (%kt-render x))))
    \\(define (%kt-on-group-begin r name count)
    \\  (if (and (not %kt-suite) (null? (test-runner-group-stack r)))
    \\      (set! %kt-suite (%kt-name->string name))))
    \\(define (%kt-on-test-end r)
    \\  (let ((kind (test-result-kind r))
    \\        (alist (test-result-alist r)))
    \\    (cond
    \\     ((eq? kind 'pass) (set! %kt-pass (+ %kt-pass 1)))
    \\     ((eq? kind 'xfail) (set! %kt-xfail (+ %kt-xfail 1)))
    \\     ((eq? kind 'skip) (set! %kt-skip (+ %kt-skip 1)))
    \\     ((or (eq? kind 'fail) (eq? kind 'xpass))
    \\      (if (eq? kind 'fail)
    \\          (set! %kt-fail (+ %kt-fail 1))
    \\          (set! %kt-xpass (+ %kt-xpass 1)))
    \\      (let ((nm (assq 'test-name alist))
    \\            (ev (assq 'expected-value alist))
    \\            (av (assq 'actual-value alist))
    \\            (sf (assq 'source-file alist))
    \\            (sl (assq 'source-line alist)))
    \\        (set! %kt-failures
    \\              (cons (vector (if nm (%kt-name->string (cdr nm)) #f)
    \\                            (symbol->string kind)
    \\                            (if ev (%kt-render (cdr ev)) #f)
    \\                            (if av (%kt-render (cdr av)) #f)
    \\                            (if (and sf (string? (cdr sf))) (cdr sf) #f)
    \\                            (if (and sl (exact-integer? (cdr sl))) (cdr sl) #f))
    \\                    %kt-failures))))
    \\     (else (set! %kt-skip (+ %kt-skip 1))))))
    \\(define (%kt-factory)
    \\  (let ((r (test-runner-null)))
    \\    (test-runner-on-test-end! r %kt-on-test-end)
    \\    (test-runner-on-group-begin! r %kt-on-group-begin)
    \\    r))
    \\(test-runner-factory %kt-factory)
    \\(define (%kt-collect)
    \\  (vector %kt-pass %kt-fail %kt-xpass %kt-xfail %kt-skip %kt-suite
    \\          (reverse %kt-failures)))
;

/// The emit-file path if this process was launched as a `kaappi test` worker,
/// else null. Presence of the env var is what puts a plain `kaappi <file>` run
/// into worker mode.
pub fn workerEmitPath() ?[]const u8 {
    return getEnv(EMIT_ENV);
}

/// Install the collecting runner (and, when `SEED_ENV` is set, seed SRFI-27's
/// default source deterministically). Must run after `vm.lib_paths` is set and
/// before the test file runs. Returns an error only if the prelude itself fails
/// to evaluate — a corrupt build, essentially.
pub fn installCollector(vm: *VM) !void {
    _ = vm.eval(collector_prelude) catch return error.CollectorInstallFailed;

    if (getEnv(SEED_ENV)) |seed_str| {
        const seed = std.fmt.parseInt(u64, seed_str, 10) catch return;
        var buf: [256]u8 = undefined;
        // `random-source-pseudo-randomize!` sets the source state as a pure
        // function of (i, j), so the same seed reproduces the same draws. We
        // seed the default source that `random-integer`/`random-real` use.
        const prog = std.fmt.bufPrint(
            &buf,
            "(import (srfi 27)) (random-source-pseudo-randomize! default-random-source 0 {d})",
            .{seed},
        ) catch return;
        _ = vm.eval(prog) catch {};
    }
}

/// Write the file's one JSON result object to `emit_path`. Called after the
/// test file has run (whether it completed, errored, or asked to exit). `errored`
/// records a file-level failure — an uncaught top-level error or a nonzero
/// `(exit)` — distinct from ordinary test failures, which live in the counts.
pub fn emitResult(vm: *VM, emit_path: []const u8, file_path: []const u8, errored: bool, err_msg: ?[]const u8, duration_ms: f64) void {
    const allocator = vm.gc.allocator;
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    buildFileJson(&aw.writer, vm, file_path, errored, err_msg, duration_ms) catch {
        // Fall back to a minimal, always-valid error object so the orchestrator
        // never has to treat a write we attempted as a missing result.
        writeFile(emit_path, "{\"type\":\"file\",\"error\":true,\"error_message\":\"result serialization failed\"}\n");
        return;
    };
    writeFile(emit_path, aw.written());
}

/// Serialize one `{"type":"file", ...}` object from the `%kt-collect` vector.
fn buildFileJson(w: *std.Io.Writer, vm: *VM, file_path: []const u8, errored: bool, err_msg: ?[]const u8, duration_ms: f64) !void {
    var collected: Value = vm.eval("(%kt-collect)") catch types.FALSE;
    vm.gc.pushRoot(&collected);
    defer vm.gc.popRoot();

    var pass: i64 = 0;
    var fail: i64 = 0;
    var xpass: i64 = 0;
    var xfail: i64 = 0;
    var skip: i64 = 0;
    var suite: Value = types.FALSE;
    var failures: Value = types.NIL;

    if (types.isVector(collected)) {
        const vec = types.toObject(collected).as(types.Vector).data;
        if (vec.len >= 7) {
            pass = fixOr0(vec[0]);
            fail = fixOr0(vec[1]);
            xpass = fixOr0(vec[2]);
            xfail = fixOr0(vec[3]);
            skip = fixOr0(vec[4]);
            suite = vec[5];
            failures = vec[6];
        }
    }
    const tests = pass + fail + xpass + xfail + skip;

    try w.writeAll("{\"type\":\"file\",\"file\":");
    try lsp_diagnostic.writeJsonString(w, file_path);
    try w.writeAll(",\"suite\":");
    try writeStrOrNull(w, suite);
    try w.print(
        ",\"tests\":{d},\"pass\":{d},\"fail\":{d},\"xpass\":{d},\"xfail\":{d},\"skip\":{d}",
        .{ tests, pass, fail, xpass, xfail, skip },
    );
    try w.writeAll(",\"error\":");
    try w.writeAll(if (errored) "true" else "false");
    try w.writeAll(",\"error_message\":");
    if (err_msg) |m| try lsp_diagnostic.writeJsonString(w, m) else try w.writeAll("null");
    try w.print(",\"duration_ms\":{d:.3},\"failures\":[", .{duration_ms});

    var first = true;
    var cur = failures;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        const rec = types.car(cur);
        if (!types.isVector(rec)) continue;
        const rv = types.toObject(rec).as(types.Vector).data;
        if (rv.len < 6) continue;
        if (!first) try w.writeByte(',');
        first = false;
        try w.writeAll("{\"name\":");
        try writeStrOrNull(w, rv[0]);
        try w.writeAll(",\"kind\":");
        try writeStrOrNull(w, rv[1]);
        try w.writeAll(",\"expected\":");
        try writeStrOrNull(w, rv[2]);
        try w.writeAll(",\"actual\":");
        try writeStrOrNull(w, rv[3]);
        try w.writeAll(",\"source_file\":");
        try writeStrOrNull(w, rv[4]);
        try w.writeAll(",\"source_line\":");
        try writeIntOrNull(w, rv[5]);
        try w.writeByte('}');
    }
    try w.writeAll("]}\n");
}

fn fixOr0(v: Value) i64 {
    return if (types.isFixnum(v)) types.toFixnum(v) else 0;
}

fn stringBytes(v: Value) ?[]const u8 {
    if (!types.isString(v)) return null;
    const s = types.toObject(v).as(types.SchemeString);
    return s.data[0..s.len];
}

fn writeStrOrNull(w: *std.Io.Writer, v: Value) !void {
    if (stringBytes(v)) |bytes| {
        try lsp_diagnostic.writeJsonString(w, bytes);
    } else {
        try w.writeAll("null");
    }
}

fn writeIntOrNull(w: *std.Io.Writer, v: Value) !void {
    if (types.isFixnum(v)) {
        try w.print("{d}", .{types.toFixnum(v)});
    } else {
        try w.writeAll("null");
    }
}

fn writeFile(path: []const u8, bytes: []const u8) void {
    var buf: [std.posix.PATH_MAX]u8 = undefined;
    if (path.len >= buf.len) return;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    const path_z: [*:0]const u8 = @ptrCast(&buf);
    const fd = std.posix.openatZ(std.posix.AT.FDCWD, path_z, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, 0o644) catch return;
    defer _ = std.posix.system.close(fd);
    reporting.writeToFd(fd, bytes);
}

// ── Orchestrator role ──────────────────────────────────────────────────

const ParentOpts = struct {
    json: bool = false,
    seed: ?u64 = null,
    /// Run only tests affected by the change set (`--changed`).
    changed: bool = false,
    /// Print affected tests without running them (`--list-affected`).
    list_affected: bool = false,
    /// git revision the change set is computed against (`--since`, default HEAD).
    since: []const u8 = "HEAD",
    since_given: bool = false,
    lib_paths: std.ArrayList([]const u8) = .empty,
    paths: std.ArrayList([]const u8) = .empty,

    /// True when either affected-selection mode is active.
    fn selecting(self: *const ParentOpts) bool {
        return self.changed or self.list_affected;
    }

    fn deinit(self: *ParentOpts, allocator: std.mem.Allocator) void {
        self.lib_paths.deinit(allocator);
        self.paths.deinit(allocator);
    }
};

/// Running totals across every file, plus the exit-relevant tallies.
const Totals = struct {
    files: u64 = 0,
    files_failed: u64 = 0,
    errors: u64 = 0,
    pass: u64 = 0,
    fail: u64 = 0,
    xpass: u64 = 0,
    xfail: u64 = 0,
    skip: u64 = 0,
};

/// If `args` is a `kaappi test …` invocation, run it fully and return the
/// process exit code; otherwise return null so normal CLI dispatch proceeds.
/// Like `explain`, the orchestrator needs no VM of its own — it spawns workers
/// — so main dispatches it before any VM/GC setup.
pub fn maybeRun(allocator: std.mem.Allocator, args: std.process.Args) ?u8 {
    var it = args.iterate();
    const argv0 = it.next() orelse return null;
    const first = it.next() orelse return null;
    if (!std.mem.eql(u8, first, "test")) return null;

    var opts: ParentOpts = .{};
    defer opts.deinit(allocator);

    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            opts.json = true;
        } else if (std.mem.eql(u8, arg, "--seed")) {
            const val = it.next() orelse {
                writeStderr("kaappi test: --seed requires an integer argument\n");
                return USAGE_ERROR_EXIT;
            };
            opts.seed = std.fmt.parseInt(u64, val, 10) catch {
                writeStderr("kaappi test: --seed requires a non-negative integer\n");
                return USAGE_ERROR_EXIT;
            };
        } else if (std.mem.eql(u8, arg, "--lib-path")) {
            const val = it.next() orelse {
                writeStderr("kaappi test: --lib-path requires a path argument\n");
                return USAGE_ERROR_EXIT;
            };
            opts.lib_paths.append(allocator, val) catch return oom();
        } else if (std.mem.eql(u8, arg, "--changed")) {
            opts.changed = true;
        } else if (std.mem.eql(u8, arg, "--list-affected")) {
            opts.list_affected = true;
        } else if (std.mem.eql(u8, arg, "--since")) {
            const val = it.next() orelse {
                writeStderr("kaappi test: --since requires a revision argument\n");
                return USAGE_ERROR_EXIT;
            };
            opts.since = val;
            opts.since_given = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printUsage();
            return 0;
        } else if (arg.len > 1 and arg[0] == '-') {
            writeStderr("kaappi test: unknown option '");
            writeStderr(arg);
            writeStderr("'\nRun 'kaappi test --help' for usage.\n");
            return USAGE_ERROR_EXIT;
        } else {
            opts.paths.append(allocator, arg) catch return oom();
        }
    }

    if (opts.since_given and !opts.selecting()) {
        writeStderr("kaappi test: --since requires --changed or --list-affected\n");
        return USAGE_ERROR_EXIT;
    }

    return run(allocator, argv0, &opts);
}

fn run(allocator: std.mem.Allocator, argv0: []const u8, opts: *ParentOpts) u8 {
    // The exe to spawn as a worker: prefer the resolved self-path so it works
    // regardless of how the parent was invoked, falling back to argv[0].
    var exe_buf: [std.posix.PATH_MAX]u8 = undefined;
    const exe_path = kaappi_paths.getExePath(&exe_buf) orelse argv0;

    // One seed for the whole run; a random but human-typable value when the
    // caller didn't pin one, so any failure is reproducible via --seed.
    const seed = opts.seed orelse randomSeed();
    {
        var sbuf: [32]u8 = undefined;
        const s = std.fmt.bufPrintZ(&sbuf, "{d}", .{seed}) catch return 1;
        _ = setenv(SEED_ENV, s.ptr, 1);
    }

    var files: std.ArrayList([]const u8) = .empty;
    defer {
        for (files.items) |f| allocator.free(f);
        files.deinit(allocator);
    }
    discover(allocator, opts.paths.items, &files) catch {
        writeStderr("kaappi test: out of memory during discovery\n");
        return 1;
    };

    if (files.items.len == 0) {
        if (opts.paths.items.len == 0) {
            writeStderr("kaappi test: no SRFI-64 suites found under ./tests (pass paths explicitly, or run from a repo with a tests/ directory)\n");
        } else {
            writeStderr("kaappi test: no test files matched the given paths\n");
        }
        return 1;
    }
    std.mem.sort([]const u8, files.items, {}, lessThanStr);

    // Affected-test selection (--changed / --list-affected). The selection note
    // always goes to stderr so a full-run fallback is loud and JSON stdout stays
    // pure. --list-affected prints and exits without running anything.
    var selection: ?test_selection.Selection = null;
    defer if (selection) |*s| s.deinit(allocator);
    if (opts.selecting()) {
        selection = test_selection.select(allocator, files.items, opts.since, opts.lib_paths.items);
        const sel = &selection.?;
        writeStderr(sel.note);
        writeStderr("\n");
        if (opts.list_affected) {
            printAffected(allocator, sel.*, opts.json, opts.since);
            return 0;
        }
    }
    const run_list: []const []const u8 = if (selection) |*s| s.files else files.items;

    // Seed note goes to stderr so JSON Lines on stdout stay pure, and is
    // present on every run per the reproducibility requirement.
    {
        var nbuf: [128]u8 = undefined;
        const note = std.fmt.bufPrint(&nbuf, "kaappi test: seed {d} (reproduce with: kaappi test --seed {d})\n", .{ seed, seed }) catch "";
        writeStderr(note);
    }

    var totals: Totals = .{};
    const start_ns = clockNs();

    for (run_list, 0..) |file, i| {
        runOneFile(allocator, exe_path, file, opts, i, &totals);
    }

    const total_ms = @as(f64, @floatFromInt(clockNs() -| start_ns)) / 1_000_000.0;
    emitSummary(allocator, opts.json, &totals, seed, total_ms);

    return if (totals.fail > 0 or totals.xpass > 0 or totals.errors > 0) 1 else 0;
}

fn runOneFile(allocator: std.mem.Allocator, exe_path: []const u8, file: []const u8, opts: *ParentOpts, index: usize, totals: *Totals) void {
    const emit_path = std.fmt.allocPrint(allocator, "{s}/kaappi-test-{d}-{d}.json", .{ tmpDir(), std.c.getpid(), index }) catch {
        writeStderr("kaappi test: out of memory\n");
        return;
    };
    defer allocator.free(emit_path);

    {
        var pbuf: [std.posix.PATH_MAX]u8 = undefined;
        if (emit_path.len < pbuf.len) {
            @memcpy(pbuf[0..emit_path.len], emit_path);
            pbuf[emit_path.len] = 0;
            _ = setenv(EMIT_ENV, @ptrCast(&pbuf), 1);
        }
    }

    const spawn = spawnWorker(allocator, exe_path, file, opts.lib_paths.items) catch {
        reportSpawnFailure(file, totals, opts.json);
        return;
    };
    defer allocator.free(spawn.output);

    const result_json: ?[]u8 = file_utils.readWholeFile(allocator, emit_path, 8 * 1024 * 1024) catch null;
    defer if (result_json) |rj| allocator.free(rj);
    unlinkPath(emit_path);

    accumulateAndReport(allocator, file, result_json, spawn, totals, opts.json);
}

const SpawnResult = struct {
    output: []u8,
    exit_code: u8,
    signaled: bool,
};

/// Fork/exec `exe_path` on one file, capturing its combined stdout+stderr.
/// `KAAPPI_TEST_EMIT` (set by the caller) is inherited via the environment, so
/// the child runs as a worker and writes its JSON to that path. Output is
/// capped so a runaway test can't exhaust memory here.
fn spawnWorker(allocator: std.mem.Allocator, exe_path: []const u8, file: []const u8, lib_paths: []const []const u8) !SpawnResult {
    var argv: std.ArrayList([]const u8) = .empty;
    defer argv.deinit(allocator);
    try argv.append(allocator, exe_path);
    for (lib_paths) |p| {
        try argv.append(allocator, "--lib-path");
        try argv.append(allocator, p);
    }
    try argv.append(allocator, file);

    const argv_z = try allocator.alloc(?[*:0]const u8, argv.items.len + 1);
    @memset(argv_z, null);
    defer {
        for (argv_z) |maybe_ptr| {
            if (maybe_ptr) |p| {
                const len = std.mem.len(p);
                const ptr: [*]u8 = @constCast(p);
                allocator.free(ptr[0 .. len + 1]);
            }
        }
        allocator.free(argv_z);
    }
    for (argv.items, 0..) |arg, i| {
        argv_z[i] = (try allocator.dupeZ(u8, arg)).ptr;
    }

    var pipe: [2]c_int = undefined;
    if (std.c.pipe(&pipe) != 0) return error.PipeFailed;

    const pid = std.posix.system.fork();
    if (pid < 0) {
        _ = std.c.close(pipe[0]);
        _ = std.c.close(pipe[1]);
        return error.ForkFailed;
    }

    if (pid == 0) {
        // Child: both stdout and stderr go down the pipe, so the file's own
        // chatter and any error diagnostics are captured together.
        _ = std.c.close(pipe[0]);
        _ = std.c.dup2(pipe[1], 1);
        _ = std.c.dup2(pipe[1], 2);
        _ = std.c.close(pipe[1]);
        _ = std.posix.system.execve(
            @ptrCast(argv_z[0].?),
            @ptrCast(argv_z.ptr),
            @ptrCast(std.c.environ),
        );
        std.process.exit(127);
    }

    _ = std.c.close(pipe[1]);
    const cap: usize = 1024 * 1024;
    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(pipe[0], &tmp) catch break;
        if (n == 0) break;
        if (output.items.len < cap) {
            const room = cap - output.items.len;
            output.appendSlice(allocator, tmp[0..@min(n, room)]) catch break;
        }
    }
    _ = std.c.close(pipe[0]);

    var status: c_int = 0;
    _ = std.c.waitpid(pid, &status, 0);
    const raw: c_uint = @bitCast(status);
    const wifexited = (raw & 0x7f) == 0;
    const exit_code: u8 = @intCast((raw >> 8) & 0xff);

    return .{
        .output = output.toOwnedSlice(allocator) catch return error.OutOfMemory,
        .exit_code = if (wifexited) exit_code else 1,
        .signaled = !wifexited,
    };
}

// ── Result shapes parsed back from a worker ────────────────────────────

const FailureJson = struct {
    name: ?[]const u8 = null,
    kind: []const u8 = "fail",
    expected: ?[]const u8 = null,
    actual: ?[]const u8 = null,
    source_file: ?[]const u8 = null,
    source_line: ?i64 = null,
};

const FileResultJson = struct {
    type: []const u8 = "file",
    file: []const u8 = "",
    suite: ?[]const u8 = null,
    tests: u64 = 0,
    pass: u64 = 0,
    fail: u64 = 0,
    xpass: u64 = 0,
    xfail: u64 = 0,
    skip: u64 = 0,
    @"error": bool = false,
    error_message: ?[]const u8 = null,
    duration_ms: f64 = 0,
    failures: []FailureJson = &.{},
};

fn accumulateAndReport(allocator: std.mem.Allocator, file: []const u8, result_json: ?[]u8, spawn: SpawnResult, totals: *Totals, json: bool) void {
    const bytes = result_json orelse {
        reportMissingResult(allocator, file, spawn, totals, json);
        return;
    };
    if (std.mem.trim(u8, bytes, " \t\r\n").len == 0) {
        reportMissingResult(allocator, file, spawn, totals, json);
        return;
    }

    const parsed = std.json.parseFromSlice(FileResultJson, allocator, bytes, .{ .ignore_unknown_fields = true }) catch {
        reportMissingResult(allocator, file, spawn, totals, json);
        return;
    };
    defer parsed.deinit();
    const r = parsed.value;

    totals.files += 1;
    totals.pass += r.pass;
    totals.fail += r.fail;
    totals.xpass += r.xpass;
    totals.xfail += r.xfail;
    totals.skip += r.skip;
    const errored = r.@"error" or spawn.signaled;
    if (errored) totals.errors += 1;
    const failed = errored or r.fail > 0 or r.xpass > 0;
    if (failed) totals.files_failed += 1;

    if (json) {
        // Re-serialize from the parsed object so the parent is the single
        // producer of user-facing JSON and can enrich it: a killed worker gets
        // error=true, and an errored file with no message of its own gets the
        // diagnostic we captured from its output (which the worker itself never
        // saw — it went to the pipe we own).
        var enriched = r;
        if (spawn.signaled) enriched.@"error" = true;
        const override: ?[]const u8 = if (enriched.@"error" and enriched.error_message == null)
            errorTail(if (spawn.signaled) "worker killed by signal" else spawn.output)
        else
            null;
        emitFileObject(allocator, enriched, override);
    } else {
        reportFileText(file, r, errored, spawn);
    }
}

fn reportFileText(file: []const u8, r: FileResultJson, errored: bool, spawn: SpawnResult) void {
    var buf: [1024]u8 = undefined;
    if (errored) {
        const line = std.fmt.bufPrint(&buf, "  ERROR {s}\n", .{file}) catch "  ERROR (file)\n";
        writeStdout(line);
        printCapturedOutput(spawn.output);
        return;
    }
    if (r.fail > 0 or r.xpass > 0) {
        const line = std.fmt.bufPrint(&buf, "  FAIL  {s}  ({d}/{d} failed, {d:.0}ms)\n", .{ file, r.fail + r.xpass, r.tests, r.duration_ms }) catch "  FAIL\n";
        writeStdout(line);
        for (r.failures) |f| printFailure(f);
    } else {
        const line = std.fmt.bufPrint(&buf, "  PASS  {s}  ({d} tests, {d} skipped, {d:.0}ms)\n", .{ file, r.tests, r.skip, r.duration_ms }) catch "  PASS\n";
        writeStdout(line);
    }
}

fn printFailure(f: FailureJson) void {
    var buf: [2048]u8 = undefined;
    const name = f.name orelse "(unnamed)";
    const line = if (f.expected != null and f.actual != null)
        std.fmt.bufPrint(&buf, "        - {s}: expected {s}, got {s}\n", .{ name, f.expected.?, f.actual.? }) catch return
    else if (f.actual != null)
        std.fmt.bufPrint(&buf, "        - {s}: got {s}\n", .{ name, f.actual.? }) catch return
    else
        std.fmt.bufPrint(&buf, "        - {s}\n", .{name}) catch return;
    writeStdout(line);
}

/// Show the tail of a failed/errored worker's captured output, indented, so the
/// real diagnostic (a compile error, a stack trace) is visible inline.
fn printCapturedOutput(output: []const u8) void {
    const trimmed = std.mem.trim(u8, output, " \t\r\n");
    if (trimmed.len == 0) return;
    var lines = std.mem.splitScalar(u8, trimmed, '\n');
    while (lines.next()) |ln| {
        writeStdout("        | ");
        writeStdout(ln);
        writeStdout("\n");
    }
}

fn reportMissingResult(allocator: std.mem.Allocator, file: []const u8, spawn: SpawnResult, totals: *Totals, json: bool) void {
    totals.files += 1;
    totals.errors += 1;
    totals.files_failed += 1;
    if (json) {
        const r: FileResultJson = .{ .file = file, .@"error" = true };
        const msg = if (spawn.signaled) "worker killed by signal" else errorTail(spawn.output) orelse "worker produced no result";
        emitFileObject(allocator, r, msg);
    } else {
        var buf: [1024]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "  ERROR {s}  (worker produced no result{s})\n", .{ file, if (spawn.signaled) ", killed by signal" else "" }) catch "  ERROR (no result)\n";
        writeStdout(line);
        printCapturedOutput(spawn.output);
    }
}

fn reportSpawnFailure(file: []const u8, totals: *Totals, json: bool) void {
    totals.files += 1;
    totals.errors += 1;
    totals.files_failed += 1;
    if (json) {
        emitFileObject(std.heap.page_allocator, .{ .file = file, .@"error" = true }, "failed to spawn worker");
    } else {
        var buf: [1024]u8 = undefined;
        const line = std.fmt.bufPrint(&buf, "  ERROR {s}  (failed to spawn worker)\n", .{file}) catch "  ERROR (spawn failed)\n";
        writeStdout(line);
    }
}

/// Serialize one `{"type":"file", ...}` line from a parsed/synthesized result.
/// `error_message_override` fills `error_message` when the result carries none
/// of its own — used to surface a captured diagnostic for a file that errored.
/// This is the parent's counterpart to the worker's `buildFileJson`; both must
/// emit the same shape (covered by a round-trip parse test).
fn emitFileObject(allocator: std.mem.Allocator, r: FileResultJson, error_message_override: ?[]const u8) void {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    writeFileObject(&aw.writer, r, error_message_override) catch return;
    writeStdout(aw.written());
}

fn writeFileObject(w: *std.Io.Writer, r: FileResultJson, error_message_override: ?[]const u8) !void {
    try w.writeAll("{\"type\":\"file\",\"file\":");
    try lsp_diagnostic.writeJsonString(w, r.file);
    try w.writeAll(",\"suite\":");
    if (r.suite) |s| try lsp_diagnostic.writeJsonString(w, s) else try w.writeAll("null");
    try w.print(",\"tests\":{d},\"pass\":{d},\"fail\":{d},\"xpass\":{d},\"xfail\":{d},\"skip\":{d}", .{ r.tests, r.pass, r.fail, r.xpass, r.xfail, r.skip });
    try w.writeAll(",\"error\":");
    try w.writeAll(if (r.@"error") "true" else "false");
    try w.writeAll(",\"error_message\":");
    const msg = r.error_message orelse error_message_override;
    if (msg) |m| try lsp_diagnostic.writeJsonString(w, m) else try w.writeAll("null");
    try w.print(",\"duration_ms\":{d:.3},\"failures\":[", .{r.duration_ms});
    for (r.failures, 0..) |f, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeAll("{\"name\":");
        if (f.name) |n| try lsp_diagnostic.writeJsonString(w, n) else try w.writeAll("null");
        try w.writeAll(",\"kind\":");
        try lsp_diagnostic.writeJsonString(w, f.kind);
        try w.writeAll(",\"expected\":");
        if (f.expected) |e| try lsp_diagnostic.writeJsonString(w, e) else try w.writeAll("null");
        try w.writeAll(",\"actual\":");
        if (f.actual) |a| try lsp_diagnostic.writeJsonString(w, a) else try w.writeAll("null");
        try w.writeAll(",\"source_file\":");
        if (f.source_file) |sf| try lsp_diagnostic.writeJsonString(w, sf) else try w.writeAll("null");
        try w.writeAll(",\"source_line\":");
        if (f.source_line) |sl| try w.print("{d}", .{sl}) else try w.writeAll("null");
        try w.writeByte('}');
    }
    try w.writeAll("]}\n");
}

/// The trailing slice of captured worker output to use as an error message —
/// trimmed, and capped so a long stack trace doesn't bloat the JSON. Null when
/// there is nothing useful to report.
fn errorTail(output: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, output, " \t\r\n");
    if (trimmed.len == 0) return null;
    const cap = 1024;
    return if (trimmed.len > cap) trimmed[trimmed.len - cap ..] else trimmed;
}

fn emitSummary(allocator: std.mem.Allocator, json: bool, t: *Totals, seed: u64, total_ms: f64) void {
    if (json) {
        var aw: std.Io.Writer.Allocating = .init(allocator);
        defer aw.deinit();
        const w = &aw.writer;
        (blk: {
            w.print(
                "{{\"type\":\"summary\",\"files\":{d},\"files_failed\":{d},\"errors\":{d},\"tests\":{d},\"pass\":{d},\"fail\":{d},\"xpass\":{d},\"xfail\":{d},\"skip\":{d},\"seed\":{d},\"duration_ms\":{d:.3}}}\n",
                .{ t.files, t.files_failed, t.errors, t.pass + t.fail + t.xpass + t.xfail + t.skip, t.pass, t.fail, t.xpass, t.xfail, t.skip, seed, total_ms },
            ) catch break :blk error.W;
            break :blk {};
        }) catch return;
        writeStdout(aw.written());
        return;
    }

    var buf: [512]u8 = undefined;
    writeStdout("\n");
    const s1 = std.fmt.bufPrint(&buf, "Summary: {d} passed, {d} failed, {d} unexpected-pass, {d} expected-fail, {d} skipped\n", .{ t.pass, t.fail, t.xpass, t.xfail, t.skip }) catch "";
    writeStdout(s1);
    const s2 = std.fmt.bufPrint(&buf, "Files:   {d} run, {d} failed, {d} errored ({d:.0}ms)\n", .{ t.files, t.files_failed, t.errors, total_ms }) catch "";
    writeStdout(s2);
    const s3 = std.fmt.bufPrint(&buf, "Seed:    {d}  (reproduce with: kaappi test --seed {d})\n", .{ seed, seed }) catch "";
    writeStdout(s3);
}

/// Print the affected suites for `--list-affected` (nothing is run). Text mode
/// writes one path per line to stdout, so the list pipes cleanly; JSON mode
/// writes a single `{"type":"affected", …}` object. The explanatory note has
/// already gone to stderr, so both stdout forms stay machine-clean.
fn printAffected(allocator: std.mem.Allocator, sel: test_selection.Selection, json: bool, since: []const u8) void {
    if (!json) {
        for (sel.files) |f| {
            writeStdout(f);
            writeStdout("\n");
        }
        return;
    }
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const w = &aw.writer;
    buildAffectedJson(w, sel, since) catch return;
    writeStdout(aw.written());
}

fn buildAffectedJson(w: *std.Io.Writer, sel: test_selection.Selection, since: []const u8) !void {
    try w.writeAll("{\"type\":\"affected\",\"since\":");
    try lsp_diagnostic.writeJsonString(w, since);
    try w.writeAll(",\"full_run\":");
    try w.writeAll(if (sel.full_run) "true" else "false");
    try w.print(",\"count\":{d},\"files\":[", .{sel.files.len});
    for (sel.files, 0..) |f, i| {
        if (i > 0) try w.writeByte(',');
        try lsp_diagnostic.writeJsonString(w, f);
    }
    try w.writeAll("]}\n");
}

// ── Discovery ──────────────────────────────────────────────────────────

/// Fill `out` with the test files to run. With no explicit paths, recurse
/// `./tests` and keep only files that use SRFI-64. An explicit file path is
/// taken as-is (the caller asked for it by name); an explicit directory is
/// recursed with the same SRFI-64 filter.
fn discover(allocator: std.mem.Allocator, paths: []const []const u8, out: *std.ArrayList([]const u8)) !void {
    if (paths.len == 0) {
        if (isDirectory("tests")) try discoverDir(allocator, "tests", out, 0);
        return;
    }
    for (paths) |p| {
        if (isDirectory(p)) {
            try discoverDir(allocator, p, out, 0);
        } else {
            // A named path that isn't a directory is taken as a file to run,
            // whether or not it exists — a missing file surfaces as a worker
            // error, which is more useful than silently dropping it.
            try out.append(allocator, try allocator.dupe(u8, p));
        }
    }
}

const max_discover_depth = 32;

fn discoverDir(allocator: std.mem.Allocator, dir_path: []const u8, out: *std.ArrayList([]const u8), depth: usize) !void {
    if (depth > max_discover_depth) return;

    const dir_z = allocator.dupeZ(u8, dir_path) catch return error.OutOfMemory;
    defer allocator.free(dir_z);
    const dir = std.c.opendir(dir_z) orelse return;
    defer _ = std.c.closedir(dir);

    while (std.c.readdir(dir)) |entry| {
        const name_ptr: [*:0]const u8 = @ptrCast(&entry.name);
        const name = std.mem.span(name_ptr);
        if (name.len == 0 or name[0] == '.') continue; // skip . .. and dotfiles

        const full = try std.fs.path.join(allocator, &.{ dir_path, name });
        var keep = false;
        defer if (!keep) allocator.free(full);

        if (isDirectory(full)) {
            try discoverDir(allocator, full, out, depth + 1);
        } else if (std.mem.endsWith(u8, name, ".scm") and usesSrfi64(allocator, full)) {
            try out.append(allocator, full);
            keep = true;
        }
    }
}

/// True if `path` names a directory. Implemented by attempting to open it as
/// one (opendir fails with ENOTDIR on a regular file) — no stat needed, matching
/// the raw-libc filesystem style used elsewhere in the tree.
fn isDirectory(path: []const u8) bool {
    var buf: [std.posix.PATH_MAX]u8 = undefined;
    if (path.len >= buf.len) return false;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    const dir = std.c.opendir(@ptrCast(&buf)) orelse return false;
    _ = std.c.closedir(dir);
    return true;
}

/// A cheap gate so directory recursion runs only SRFI-64 suites — skipping
/// benchmarks, the chibi-test R7RS suite, and coverage helpers. A false
/// positive merely runs a file that reports no tests.
fn usesSrfi64(allocator: std.mem.Allocator, path: []const u8) bool {
    const src = file_utils.readWholeFile(allocator, path, 4 * 1024 * 1024) catch return false;
    defer allocator.free(src);
    return sourceUsesSrfi64(src);
}

fn sourceUsesSrfi64(src: []const u8) bool {
    return std.mem.indexOf(u8, src, "srfi 64") != null;
}

// ── Small helpers ──────────────────────────────────────────────────────

fn lessThanStr(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

fn tmpDir() []const u8 {
    return getEnv("TMPDIR") orelse "/tmp";
}

fn randomSeed() u64 {
    const entropy = clockNs() ^ (@as(u64, @intCast(std.c.getpid())) << 32);
    var prng = std.Random.DefaultPrng.init(entropy);
    return prng.random().intRangeLessThan(u64, 1, 1_000_000);
}

fn unlinkPath(path: []const u8) void {
    var buf: [std.posix.PATH_MAX]u8 = undefined;
    if (path.len >= buf.len) return;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    _ = std.c.unlink(@ptrCast(&buf));
}

fn oom() u8 {
    writeStderr("kaappi test: out of memory\n");
    return 1;
}

fn printUsage() void {
    writeStdout(
        \\Usage: kaappi test [options] [paths...]
        \\
        \\Discover and run SRFI-64 test suites, aggregating results from the
        \\test runner itself. With no paths, recurses ./tests for SRFI-64 files.
        \\A named file is run as given; a named directory is recursed.
        \\
        \\Options:
        \\  --json             Emit JSON Lines: one object per file, then a summary.
        \\  --seed <n>         Seed SRFI-27's default random source (default: random,
        \\                     printed on every run so failures are reproducible).
        \\  --lib-path <path>  Add a library search path (repeatable), forwarded to
        \\                     each test file — e.g. kaappi test --lib-path ./lib.
        \\  --changed          Run only tests affected by files changed since --since,
        \\                     computed from the R7RS import graph (imports + includes).
        \\  --list-affected    Print affected tests (one per line) without running them.
        \\  --since <rev>      git revision the change set is diffed against (default:
        \\                     HEAD). Requires --changed or --list-affected.
        \\  -h, --help         Show this help.
        \\
        \\Exit status is nonzero iff a test failed, unexpectedly passed, or a file
        \\errored. With --changed, an empty affected set is a clean exit (0).
        \\
        \\When the change set can't be trusted — git is unavailable, a revision is
        \\unknown, or a native/FFI artifact changed — all tests run and the reason is
        \\printed to stderr; a test is skipped only when its whole import closure is
        \\provably unchanged.
        \\
    );
}

// ── Tests ──────────────────────────────────────────────────────────────

const testing = std.testing;

test "FileResultJson parses a worker object" {
    const bytes =
        \\{"type":"file","file":"t.scm","suite":"s","tests":3,"pass":2,"fail":1,"xpass":0,"xfail":0,"skip":0,"error":false,"error_message":null,"duration_ms":1.5,"failures":[{"name":"n","kind":"fail","expected":"1","actual":"2","source_file":null,"source_line":null}]}
    ;
    const parsed = try std.json.parseFromSlice(FileResultJson, testing.allocator, bytes, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try testing.expectEqualStrings("file", parsed.value.type);
    try testing.expectEqualStrings("s", parsed.value.suite.?);
    try testing.expectEqual(@as(u64, 2), parsed.value.pass);
    try testing.expectEqual(@as(u64, 1), parsed.value.fail);
    try testing.expect(!parsed.value.@"error");
    try testing.expectEqual(@as(usize, 1), parsed.value.failures.len);
    try testing.expectEqualStrings("2", parsed.value.failures[0].actual.?);
}

test "randomSeed is in the human-typable range" {
    const s = randomSeed();
    try testing.expect(s >= 1 and s < 1_000_000);
}

test "sourceUsesSrfi64 gates on the import substring" {
    try testing.expect(sourceUsesSrfi64("(import (scheme base) (srfi 64))\n(test-begin \"a\")"));
    try testing.expect(sourceUsesSrfi64("(import\n  (srfi 64))"));
    try testing.expect(!sourceUsesSrfi64("(import (scheme base))\n(display \"no tests\")"));
    try testing.expect(!sourceUsesSrfi64("(import (srfi 1) (srfi 128))"));
}

test "writeFileObject round-trips through the JSON parser" {
    var failures = [_]FailureJson{.{ .name = "n", .kind = "fail", .expected = "1", .actual = "2" }};
    const r: FileResultJson = .{
        .file = "t.scm",
        .suite = "s",
        .tests = 2,
        .pass = 1,
        .fail = 1,
        .duration_ms = 1.25,
        .failures = &failures,
    };
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    try writeFileObject(&aw.writer, r, null);

    const parsed = try std.json.parseFromSlice(FileResultJson, testing.allocator, aw.written(), .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try testing.expectEqualStrings("t.scm", parsed.value.file);
    try testing.expectEqual(@as(u64, 1), parsed.value.fail);
    try testing.expectEqualStrings("2", parsed.value.failures[0].actual.?);
}

test "writeFileObject uses the error-message override only when none is present" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    try writeFileObject(&aw.writer, .{ .file = "t.scm", .@"error" = true }, "captured diagnostic");
    const parsed = try std.json.parseFromSlice(FileResultJson, testing.allocator, aw.written(), .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try testing.expect(parsed.value.@"error");
    try testing.expectEqualStrings("captured diagnostic", parsed.value.error_message.?);
}

// A test file's SRFI-64 failure epilogue often calls `(exit 1)`. The worker
// sets `suppress_exit` so that becomes a recorded no-op instead of tearing the
// worker down before it can emit its result — without which a failing suite
// would report as a crash. Guards the exitFn change in primitives_r7rs.zig.
test "suppress_exit turns (exit) into a recorded no-op, VM stays usable" {
    const th = @import("testing_helpers.zig");
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    ctx.vm.suppress_exit = true;
    const r = try ctx.vm.eval("(import (scheme process-context)) (exit 7)");
    try testing.expectEqual(types.VOID, r);
    try testing.expect(ctx.vm.exit_requested);
    try testing.expectEqual(@as(u8, 7), ctx.vm.exit_code);

    const after = try ctx.vm.eval("(+ 1 2)");
    try testing.expectEqual(@as(i64, 3), types.toFixnum(after));
}
