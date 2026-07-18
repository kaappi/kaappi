//! `kaappi doctor` — installation and environment self-check
//! (kaappi#1513, part of the machine-legibility epic kaappi#1503).
//!
//! "Why doesn't `(import (kaappi json))` work?" has a fixed set of answers —
//! library-path resolution, thottam state, a missing native library, the wrong
//! binary on PATH — that were previously diagnosed by hand. `doctor` runs those
//! checks itself and prints, per check, a `PASS`/`WARN`/`FAIL` line with a
//! concrete, actionable suggestion on every failure.
//!
//! Like `kaappi explain` and `kaappi test`, this is a meta-command: it inspects
//! the environment and never runs user code, so main dispatches it before any
//! VM, GC, or library setup exists (`maybeRun`).
//!
//! Forms:
//!   kaappi doctor            human-readable table, one line per check
//!   kaappi doctor --json     one JSON object (meta + a `checks` array)
//!
//! Exit code is nonzero only when a check is `FAIL` — a genuinely broken
//! configuration (e.g. `KAAPPI_LIB_DIR` set to a directory with no runtime
//! library). `WARN`-level findings (a missing `~/.kaappi/lib`, no C compiler on
//! PATH) describe a degraded-but-usable environment and keep the exit code 0.

const std = @import("std");
const platform = @import("platform.zig");
const builtin = @import("builtin");
const reporting = @import("reporting.zig");
const lsp_diagnostic = @import("lsp_diagnostic.zig");
const kaappi_paths = @import("kaappi_paths.zig");
const file_utils = @import("file_utils.zig");
const native_compiler = @import("native_compiler.zig");

pub const version = @import("build_options").version;

const writeStdout = reporting.writeStdout;
const writeStderr = reporting.writeStderr;

pub const USAGE_ERROR_EXIT: u8 = 2;

/// The build's target triple and optimize mode are comptime-known, so they are
/// module constants shared by the human table, the JSON meta, and the tests.
const target_triple = @tagName(builtin.cpu.arch) ++ "-" ++ @tagName(builtin.os.tag) ++ "-" ++ @tagName(builtin.abi);

/// Platform spelling of the native-backend runtime archive (`libkaappi_rt.a`;
/// `kaappi_rt.lib` on Windows) — the messages below must name the file the
/// user would actually see on disk (#1610).
const rt_lib = platform.rt_lib_name;
const build_mode = @tagName(builtin.mode);

// ── Findings model ───────────────────────────────────────────────────────────

pub const Status = enum {
    pass,
    warn,
    fail,

    /// Fixed-width human label, so the status column in the table aligns.
    pub fn label(self: Status) []const u8 {
        return switch (self) {
            .pass => "PASS",
            .warn => "WARN",
            .fail => "FAIL",
        };
    }

    /// Lowercase machine label for `--json` (mirrors the `explain` convention).
    pub fn jsonLabel(self: Status) []const u8 {
        return switch (self) {
            .pass => "pass",
            .warn => "warn",
            .fail => "fail",
        };
    }
};

pub const Finding = struct {
    /// Check category, e.g. "binary", "library", "native-backend".
    group: []const u8,
    /// Short name of the individual check within the group.
    label: []const u8,
    status: Status,
    /// Human-readable one-line result.
    detail: []const u8,
    /// Actionable fix; present only when the check did not pass cleanly.
    suggestion: ?[]const u8 = null,
};

/// The overall verdict is the most severe finding: `fail` beats `warn` beats
/// `pass`.
pub fn overall(findings: []const Finding) Status {
    var result: Status = .pass;
    for (findings) |f| {
        if (f.status == .fail) return .fail;
        if (f.status == .warn) result = .warn;
    }
    return result;
}

/// Exit code contract: nonzero only when at least one check is `FAIL`.
pub fn exitCode(findings: []const Finding) u8 {
    for (findings) |f| {
        if (f.status == .fail) return 1;
    }
    return 0;
}

/// Accumulates findings. Every detail/suggestion string is allocated in the
/// arena, so the whole report is freed in one `deinit`.
pub const Report = struct {
    arena: std.heap.ArenaAllocator,
    findings: std.ArrayList(Finding) = .empty,

    pub fn init(base: std.mem.Allocator) Report {
        return .{ .arena = std.heap.ArenaAllocator.init(base) };
    }

    pub fn deinit(self: *Report) void {
        self.arena.deinit();
    }

    fn allocator(self: *Report) std.mem.Allocator {
        return self.arena.allocator();
    }

    /// Arena-format a string; falls back to a fixed marker on OOM so a probe
    /// never has to error out over a detail line.
    fn fmt(self: *Report, comptime f: []const u8, args: anytype) []const u8 {
        return std.fmt.allocPrint(self.allocator(), f, args) catch "(out of memory)";
    }

    fn add(self: *Report, group: []const u8, item: []const u8, status: Status, detail: []const u8, suggestion: ?[]const u8) void {
        self.findings.append(self.allocator(), .{
            .group = group,
            .label = item,
            .status = status,
            .detail = detail,
            .suggestion = suggestion,
        }) catch {};
    }

    pub fn items(self: *const Report) []const Finding {
        return self.findings.items;
    }
};

// ── Public entry ─────────────────────────────────────────────────────────────

/// A parsed `kaappi doctor …` invocation.
pub const Request = struct {
    json: bool = false,
    /// `--lib-path` entries, surfaced in the library-resolution check exactly as
    /// a real run would prepend them to the search path.
    lib_paths: [][]const u8 = &.{},
};

/// If `args` is a `kaappi doctor …` invocation, handle it fully and return the
/// process exit code; otherwise return null so normal CLI dispatch proceeds.
pub fn maybeRun(allocator: std.mem.Allocator, args: std.process.Args) ?u8 {
    var it = platform.argsIterate(args);
    _ = it.skip(); // argv[0]
    const first = it.next() orelse return null;
    if (!std.mem.eql(u8, first, "doctor")) return null;

    var lib_paths: std.ArrayList([]const u8) = .empty;
    defer lib_paths.deinit(allocator);

    var req: Request = .{};
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            req.json = true;
        } else if (std.mem.eql(u8, arg, "--lib-path")) {
            const value = it.next() orelse {
                writeStderr("kaappi doctor: --lib-path requires a path argument\n");
                return USAGE_ERROR_EXIT;
            };
            lib_paths.append(allocator, value) catch return 1;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printUsage();
            return 0;
        } else if (arg.len > 1 and arg[0] == '-') {
            writeStderr("kaappi doctor: unknown option '");
            writeStderr(arg);
            writeStderr("'\nUsage: kaappi doctor [--json] [--lib-path <path>]\n");
            return USAGE_ERROR_EXIT;
        } else {
            writeStderr("kaappi doctor: unexpected argument '");
            writeStderr(arg);
            writeStderr("'\nUsage: kaappi doctor [--json] [--lib-path <path>]\n");
            return USAGE_ERROR_EXIT;
        }
    }
    req.lib_paths = lib_paths.items;
    return run(allocator, req);
}

/// Run every check and render the report; returns the process exit code.
pub fn run(allocator: std.mem.Allocator, req: Request) u8 {
    var report = Report.init(allocator);
    defer report.deinit();

    probeAll(&report, req.lib_paths);

    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    (if (req.json) renderJson(&aw.writer, &report) else renderText(&aw.writer, &report)) catch {
        writeStderr("kaappi doctor: out of memory\n");
        return 1;
    };
    writeStdout(aw.written());

    return exitCode(report.items());
}

/// Runs each check group in the order they appear in the human table.
fn probeAll(report: *Report, lib_paths: []const []const u8) void {
    collectBinary(report);
    collectLibrary(report, lib_paths);
    collectPackageManager(report);
    collectNativeBackend(report);
    collectRepl(report);
    collectFfi(report);
}

// ── Checks ───────────────────────────────────────────────────────────────────

fn collectBinary(r: *Report) void {
    r.add("binary", "version", .pass, r.fmt("v{s}", .{version}), null);
    r.add("binary", "target", .pass, target_triple, null);
    r.add("binary", "build-mode", .pass, build_mode, null);

    // Surface the running binary and the `kaappi` a shell would pick from PATH.
    // Both are shown (never a WARN): when they differ, that IS the "wrong binary
    // on PATH" diagnosis, and showing both lets the reader see it directly
    // without doctor guessing which one they meant.
    var exe_buf: [4096]u8 = undefined;
    const running = kaappi_paths.getExePath(&exe_buf);
    if (running) |ep| {
        r.add("binary", "running", .pass, r.fmt("{s}", .{ep}), null);
    }
    if (findInPath(r.allocator(), "kaappi")) |on_path| {
        const resolved = realpath(r.allocator(), on_path) orelse on_path;
        const same = if (running) |ep| std.mem.eql(u8, ep, resolved) else false;
        const note = if (running == null)
            ""
        else if (same)
            " (same as running binary)"
        else
            " (differs from running binary — a bare `kaappi` runs this one)";
        r.add("binary", "on-PATH", .pass, r.fmt("{s}{s}", .{ on_path, note }), null);
    } else {
        r.add("binary", "on-PATH", .pass, "kaappi is not on PATH (invoked by explicit path)", null);
    }
}

fn collectLibrary(r: *Report, lib_paths: []const []const u8) void {
    const a = r.allocator();

    // 1. `--lib-path` entries, in the order they would be prepended.
    for (lib_paths) |lp| {
        if (dirExists(a, lp)) {
            r.add("library", r.fmt("--lib-path {s}", .{lp}), .pass, "directory exists", null);
        } else {
            r.add("library", r.fmt("--lib-path {s}", .{lp}), .warn, "directory does not exist", r.fmt("create '{s}', or correct the --lib-path argument", .{lp}));
        }
    }

    // 2. The script's own directory is added per-run when a file is given;
    //    `doctor` has no file, so state that rather than omit it silently.
    r.add("library", "script directory", .pass, "added to the search path at runtime when a file argument is given", null);

    // 3. ~/.kaappi/lib — where thottam installs libraries.
    var home_buf: [512]u8 = undefined;
    if (kaappi_paths.getHome(&home_buf)) |home| {
        const klib = r.fmt("{s}/lib", .{home});
        if (dirExists(a, klib)) {
            r.add("library", "~/.kaappi/lib", .pass, klib, null);
        } else {
            r.add("library", "~/.kaappi/lib", .warn, r.fmt("{s} (missing)", .{klib}), "run 'thottam install <pkg>' to install libraries there");
        }
    } else {
        r.add("library", "~/.kaappi/lib", .warn, "cannot resolve: neither KAAPPI_HOME nor HOME is set", "set HOME (or KAAPPI_HOME) so ~/.kaappi/lib can be located");
    }

    // 4. <exe>/../lib — the from-source / installed-prefix fallback. Absence is
    //    normal (an installed layout uses ~/.kaappi/lib), so never a WARN.
    var exe_lib_buf: [1024]u8 = undefined;
    if (kaappi_paths.getExeRelativeLibDir(&exe_lib_buf)) |elib| {
        const detail = if (dirExists(a, elib))
            r.fmt("{s}", .{elib})
        else
            r.fmt("{s} (absent — fallback only)", .{elib});
        r.add("library", "exe-relative ../lib", .pass, detail, null);
    }
}

fn collectPackageManager(r: *Report) void {
    const a = r.allocator();

    if (findInPath(a, "thottam")) |tp| {
        r.add("package-manager", "thottam", .pass, r.fmt("found: {s}", .{tp}), null);
    } else {
        r.add("package-manager", "thottam", .warn, "not found on PATH", "thottam ships alongside kaappi; add its directory to PATH to install libraries");
    }

    var home_buf: [512]u8 = undefined;
    const home = kaappi_paths.getHome(&home_buf) orelse {
        // Without a home dir there is no lockfile to reconcile; the library
        // check already warned about the same root cause.
        return;
    };
    const lockfile = r.fmt("{s}/thottam.lock", .{home});
    const src_dir = r.fmt("{s}/src", .{home});

    const content = file_utils.readWholeFile(a, lockfile, 1 << 20) catch {
        r.add("package-manager", "lockfile", .pass, "no lockfile (no packages installed via thottam)", null);
        return;
    };

    var total: usize = 0;
    var missing: usize = 0;
    var first_missing: ?[]const u8 = null;
    var lines = std.mem.splitScalar(u8, content, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        // Each line is "<pkg> <sha> [source]"; the package name is the first token.
        const pkg = line[0 .. std.mem.indexOfScalar(u8, line, ' ') orelse line.len];
        if (pkg.len == 0) continue;
        total += 1;
        const pkg_dir = r.fmt("{s}/{s}", .{ src_dir, pkg });
        if (!dirExists(a, pkg_dir)) {
            missing += 1;
            if (first_missing == null) first_missing = r.fmt("{s}", .{pkg});
        }
    }

    if (total == 0) {
        r.add("package-manager", "lockfile", .pass, "lockfile present but empty", null);
    } else if (missing == 0) {
        r.add("package-manager", "lockfile", .pass, r.fmt("{d} locked package(s) present in ~/.kaappi/src", .{total}), null);
    } else {
        r.add("package-manager", "lockfile", .warn, r.fmt("{d} of {d} locked package(s) missing from ~/.kaappi/src (first: {s})", .{ missing, total, first_missing.? }), "run 'thottam update' to restore missing package sources");
    }
}

fn collectNativeBackend(r: *Report) void {
    const a = r.allocator();

    // C compiler discovery uses native_compiler's own search order, so the
    // finding names the driver `kaappi compile` will actually pick.
    var found_cc = false;
    for (native_compiler.cc_search_order) |cc| {
        const cc_path = findInPath(a, cc) orelse continue;
        found_cc = true;
        if (platform.is_netbsd and (std.mem.eql(u8, cc, "cc") or std.mem.eql(u8, cc, "gcc"))) {
            // NetBSD's base cc is GCC, which cannot consume the LLVM IR
            // kaappi compile emits — a smoke-link of a C program below
            // still passes, so call the gap out here (docs/dev/netbsd.md).
            r.add("native-backend", "c-compiler", .warn, r.fmt("{s}: {s} (GCC — cannot compile the LLVM IR `kaappi compile` emits)", .{ cc, cc_path }), "install an LLVM-capable driver: pkgin install clang");
        } else {
            const note = if (std.mem.eql(u8, cc, "zig")) " (links via 'zig cc')" else "";
            r.add("native-backend", "c-compiler", .pass, r.fmt("{s}: {s}{s}", .{ cc, cc_path, note }), null);
        }
        break;
    }
    if (!found_cc) {
        r.add("native-backend", "c-compiler", .warn, "none of zig, cc, clang, gcc found on PATH", "install zig (recommended), clang, or gcc to compile native binaries");
    }

    // Runtime-archive lookup across the four documented locations, in the
    // order native_compiler.findLibDir consults them.
    var archive_dir: ?[]const u8 = null;

    // An explicit KAAPPI_LIB_DIR that does not resolve is a definite
    // misconfiguration — the user asked for a specific runtime library and it
    // is not there — so it is the one FAIL-level finding doctor emits.
    if (platform.getenv("KAAPPI_LIB_DIR")) |env| {
        const dir = std.mem.sliceTo(env, 0);
        if (!dirExists(a, dir)) {
            r.add("native-backend", "KAAPPI_LIB_DIR", .fail, r.fmt("{s} (directory does not exist)", .{dir}), "point KAAPPI_LIB_DIR at a directory containing " ++ rt_lib ++ ", or unset it to use the default search");
        } else if (hasArchive(a, dir)) {
            archive_dir = dir;
            r.add("native-backend", "KAAPPI_LIB_DIR", .pass, r.fmt("{s} (contains " ++ rt_lib ++ ")", .{dir}), null);
        } else {
            r.add("native-backend", "KAAPPI_LIB_DIR", .fail, r.fmt("{s} (exists but has no " ++ rt_lib ++ ")", .{dir}), "place " ++ rt_lib ++ " in that directory, or unset KAAPPI_LIB_DIR to use the default search");
        }
    }

    if (archive_dir == null) {
        var exe_lib_buf: [1024]u8 = undefined;
        if (kaappi_paths.getExeRelativeLibDir(&exe_lib_buf)) |elib| {
            if (hasArchive(a, elib)) archive_dir = r.fmt("{s}", .{elib});
        }
    }
    if (archive_dir == null) {
        const candidates = [_][]const u8{ "zig-out/lib", "/usr/local/lib" };
        for (candidates) |dir| {
            if (hasArchive(a, dir)) {
                archive_dir = dir;
                break;
            }
        }
    }

    if (archive_dir) |dir| {
        r.add("native-backend", rt_lib, .pass, r.fmt("found in {s}", .{dir}), null);
    } else {
        r.add("native-backend", rt_lib, .warn, "not found in KAAPPI_LIB_DIR, <exe>/../lib, zig-out/lib, or /usr/local/lib", "run 'zig build lib' in a source checkout, or install a release build that ships " ++ rt_lib);
    }

    // Smoke link: prove the discovered compiler can actually link a program
    // against the discovered archive. Only meaningful when both were found.
    if (found_cc and archive_dir != null) {
        smokeLink(r, archive_dir.?);
    } else {
        r.add("native-backend", "smoke-link", .pass, "skipped (needs both a C compiler and " ++ rt_lib ++ ")", null);
    }
}

fn collectRepl(r: *Report) void {
    const a = r.allocator();

    var home_buf: [512]u8 = undefined;
    if (kaappi_paths.getHome(&home_buf)) |home| {
        const hist = r.fmt("{s}/history", .{home});
        // Writability is a property of the containing ~/.kaappi directory: the
        // history file is created on first REPL exit, so it need not exist yet.
        if (!dirExists(a, home)) {
            r.add("repl", "history", .pass, r.fmt("{s} (parent ~/.kaappi created on first REPL/thottam use)", .{hist}), null);
        } else if (dirWritable(a, home)) {
            r.add("repl", "history", .pass, r.fmt("{s} (writable)", .{hist}), null);
        } else {
            r.add("repl", "history", .warn, r.fmt("{s} (~/.kaappi is not writable)", .{home}), "make ~/.kaappi writable so REPL history can be saved");
        }
    } else {
        r.add("repl", "history", .warn, "cannot resolve ~/.kaappi (neither KAAPPI_HOME nor HOME set)", "set HOME (or KAAPPI_HOME) so REPL history has a home");
    }

    const stdin_tty = platform.isatty(0);
    const stdout_tty = platform.isatty(1);
    const term = if (platform.getenv("TERM")) |t| std.mem.sliceTo(t, 0) else "(unset)";
    r.add("repl", "terminal", .pass, r.fmt("stdin tty={s}, stdout tty={s}, TERM={s}", .{ boolStr(stdin_tty), boolStr(stdout_tty), term }), null);
}

fn collectFfi(r: *Report) void {
    const a = r.allocator();

    var home_buf: [512]u8 = undefined;
    const home = kaappi_paths.getHome(&home_buf) orelse {
        r.add("ffi", "native-libraries", .pass, "skipped: cannot resolve ~/.kaappi/lib", null);
        return;
    };
    const lib_dir = r.fmt("{s}/lib", .{home});

    const lib_dir_z = a.dupeZ(u8, lib_dir) catch {
        r.add("ffi", "native-libraries", .pass, "skipped: out of memory", null);
        return;
    };
    var dir = platform.DirIter.open(lib_dir_z) orelse {
        r.add("ffi", "native-libraries", .pass, r.fmt("no native libraries ({s} not present)", .{lib_dir}), null);
        return;
    };
    defer dir.close();

    var checked: usize = 0;
    var failed: usize = 0;
    while (dir.next()) |name| {
        if (!isNativeLibrary(name)) continue;
        checked += 1;

        const full = r.fmt("{s}/{s}", .{ lib_dir, name });
        const full_z = a.dupeZ(u8, full) catch continue;
        if (platform.dlOpen(full_z)) |handle| {
            platform.dlClose(handle);
            r.add("ffi", r.fmt("{s}", .{name}), .pass, "dlopen succeeded", null);
        } else {
            failed += 1;
            const err = if (platform.dlError()) |e| std.mem.span(e) else "dlopen failed";
            r.add("ffi", r.fmt("{s}", .{name}), .warn, r.fmt("{s}", .{err}), "rebuild or reinstall the library (its dependencies may be missing)");
        }
    }

    if (checked == 0) {
        r.add("ffi", "native-libraries", .pass, r.fmt("no native libraries (.dylib/.so) in {s}", .{lib_dir}), null);
    } else if (failed == 0) {
        r.add("ffi", "native-libraries", .pass, r.fmt("{d} native library(ies) loadable", .{checked}), null);
    }
}

// ── Smoke link ───────────────────────────────────────────────────────────────

/// Compile and link a tiny C program that references one leaf runtime export
/// (`kaappi_fixnum_add`) against the runtime archive. A successful link proves
/// the C compiler works and the archive is well-formed and resolvable — the
/// exact path `kaappi compile` takes. The program is never executed.
fn smokeLink(r: *Report, lib_dir: []const u8) void {
    // Never fork a compiler from within the unit-test binary: `probeAll` runs
    // this path, and tests must stay hermetic and fast. The shell test exercises
    // the real link end-to-end.
    if (builtin.is_test) {
        r.add("native-backend", "smoke-link", .pass, "skipped (test build)", null);
        return;
    }

    const a = r.allocator();

    const tmp = platform.tempDir();

    // Work inside a private 0700 directory with a random name (mkdtemp-style).
    // `mkdir` refuses to reuse an existing name, so a hostile pre-planted
    // symlink in a shared TMPDIR cannot redirect the C input or the
    // compiler-written output; both live inside this directory.
    const hex = randomHex();
    const dir_path = r.fmt("{s}/kaappi-doctor-{s}", .{ tmp, hex[0..] });
    const dir_z = a.dupeZ(u8, dir_path) catch return;
    if (platform.mkdir(dir_z, 0o700) != 0) {
        r.add("native-backend", "smoke-link", .pass, r.fmt("skipped (cannot create temp dir in {s})", .{tmp}), null);
        return;
    }
    defer _ = platform.rmdir(dir_z);

    const c_path = r.fmt("{s}/smoke.c", .{dir_path});
    const out_path = r.fmt("{s}/smoke.out", .{dir_path});
    const c_path_z = a.dupeZ(u8, c_path) catch return;
    const out_path_z = a.dupeZ(u8, out_path) catch return;
    defer _ = platform.unlink(c_path_z);
    defer _ = platform.unlink(out_path_z);

    const c_source =
        \\extern unsigned long long kaappi_fixnum_add(unsigned long long, unsigned long long);
        \\int main(void) { return (int)kaappi_fixnum_add(0, 0); }
        \\
    ;
    const cfd = platform.openWriteTruncExcl(c_path_z, 0o600) catch {
        r.add("native-backend", "smoke-link", .pass, r.fmt("skipped (cannot write temp file in {s})", .{tmp}), null);
        return;
    };
    reporting.writeToFd(cfd, c_source);
    _ = platform.close(cfd);

    // A C compiler capable of driving the linker is required; `zig` needs the
    // `cc` subcommand. Prefer zig cc (per the repo's linking rule), then cc.
    const use_zig = findInPath(a, "zig") != null;
    const cc = if (use_zig) (findInPath(a, "zig").?) else (findInPath(a, "cc") orelse findInPath(a, "clang") orelse findInPath(a, "gcc") orelse {
        r.add("native-backend", "smoke-link", .pass, "skipped (no C compiler)", null);
        return;
    });

    const lib_flag = r.fmt("-L{s}", .{lib_dir});

    var argv: [16]?[*:0]const u8 = .{null} ** 16;
    var argc: usize = 0;
    const push = struct {
        fn f(buf: *[16]?[*:0]const u8, n: *usize, alloc: std.mem.Allocator, s: []const u8) void {
            if (n.* >= buf.len - 1) return;
            buf[n.*] = alloc.dupeZ(u8, s) catch return;
            n.* += 1;
        }
    }.f;

    push(&argv, &argc, a, cc);
    if (use_zig) push(&argv, &argc, a, "cc");
    push(&argv, &argc, a, "-w");
    push(&argv, &argc, a, c_path);
    push(&argv, &argc, a, "-o");
    push(&argv, &argc, a, out_path);
    push(&argv, &argc, a, lib_flag);
    push(&argv, &argc, a, "-lkaappi_rt");
    push(&argv, &argc, a, "-lc");
    push(&argv, &argc, a, "-lm");
    // Windows: the runtime archive calls Winsock (#1608) and a foreign link
    // must name the import lib itself — mirrors native_compiler.tryLink (#1610).
    if (comptime platform.is_windows) push(&argv, &argc, a, "-lws2_32") else push(&argv, &argc, a, "-lpthread");
    argv[argc] = null;

    const link_ok = blk: {
        if (comptime platform.is_windows) {
            // winSpawnCapture already silences the compiler (stdout captured,
            // stderr → NUL); only the exit status matters here.
            var argv_slices: [16][]const u8 = undefined;
            for (argv[0..argc], 0..) |arg, i| argv_slices[i] = std.mem.sliceTo(arg.?, 0);
            const out = platform.winSpawnCapture(a, argv_slices[0..argc], null) catch break :blk false;
            a.free(out);
            break :blk true;
        }
        const child = std.posix.system.fork();
        if (child < 0) {
            r.add("native-backend", "smoke-link", .pass, "skipped (fork failed)", null);
            return;
        }
        if (child == 0) {
            // Silence the compiler's own diagnostics so they don't pollute doctor's
            // output; the link's exit status is all we inspect.
            const devnull = platform.openNullSink() catch -1;
            if (devnull >= 0) {
                _ = std.c.dup2(devnull, 1);
                _ = std.c.dup2(devnull, 2);
            }
            _ = std.posix.system.execve(@ptrCast(argv[0].?), @ptrCast(&argv), @ptrCast(std.c.environ));
            std.process.exit(127);
        }

        var status: c_int = 0;
        _ = std.c.waitpid(child, &status, 0);
        const raw: c_uint = @bitCast(status);
        const exited = (raw & 0x7f) == 0;
        const code = (raw >> 8) & 0xff;
        break :blk exited and code == 0;
    };
    if (link_ok) {
        r.add("native-backend", "smoke-link", .pass, r.fmt("linked a test program against " ++ rt_lib ++ " in {s}", .{lib_dir}), null);
    } else {
        r.add("native-backend", "smoke-link", .warn, "link against " ++ rt_lib ++ " failed", "run 'kaappi compile <file.scm>' to see the linker error");
    }
}

// ── Filesystem / PATH helpers ────────────────────────────────────────────────

fn dirExists(a: std.mem.Allocator, path: []const u8) bool {
    const path_z = a.dupeZ(u8, path) catch return false;
    return platform.isDir(path_z);
}

fn dirWritable(a: std.mem.Allocator, path: []const u8) bool {
    const path_z = a.dupeZ(u8, path) catch return false;
    return platform.accessWritable(path_z);
}

fn fileExists(a: std.mem.Allocator, path: []const u8) bool {
    const path_z = a.dupeZ(u8, path) catch return false;
    const fd = platform.openRead(path_z) catch return false;
    _ = platform.close(fd);
    return true;
}

fn hasArchive(a: std.mem.Allocator, dir: []const u8) bool {
    const path = std.fmt.allocPrint(a, "{s}/" ++ rt_lib, .{dir}) catch return false;
    return fileExists(a, path);
}

/// Returns the first `<dir>/name` on PATH that opens for reading, allocated in
/// `a`. Mirrors native_compiler's discovery so doctor and compile agree.
fn findInPath(a: std.mem.Allocator, name: []const u8) ?[]const u8 {
    const path_env = platform.getenv("PATH") orelse return null;
    const path_str = std.mem.sliceTo(path_env, 0);
    var iter = std.mem.splitScalar(u8, path_str, platform.path_list_sep);
    while (iter.next()) |raw_dir| {
        if (raw_dir.len == 0) continue;
        // Trim trailing slashes so a "…/bin/" PATH entry doesn't render as
        // "…/bin//kaappi" — this string is shown to the user.
        const dir = std.mem.trimEnd(u8, raw_dir, if (platform.is_windows) "/\\" else "/");
        if (dir.len == 0) continue;
        const full = std.fmt.allocPrint(a, "{s}/{s}{s}", .{ dir, name, platform.exe_suffix }) catch continue;
        const full_z = a.dupeZ(u8, full) catch continue;
        const fd = platform.openRead(full_z) catch continue;
        _ = platform.close(fd);
        return full;
    }
    return null;
}

/// Canonicalizes `path` via realpath into an arena copy (or null on failure).
fn realpath(a: std.mem.Allocator, path: []const u8) ?[]const u8 {
    const path_z = a.dupeZ(u8, path) catch return null;
    var buf: [platform.PATH_MAX]u8 = undefined;
    const resolved = platform.realPath(path_z, &buf) orelse return null;
    return a.dupe(u8, resolved) catch null;
}

/// 16 lowercase hex chars of entropy for a private temp-dir name. Reads
/// `/dev/urandom` (portable across macOS and Linux); falls back to the
/// monotonic clock only if that device is unavailable.
fn randomHex() [16]u8 {
    var raw: [8]u8 = undefined;
    if (comptime !platform.is_windows) {
        if (platform.openRead("/dev/urandom")) |fd| {
            const n = platform.read(fd, &raw, raw.len);
            _ = platform.close(fd);
            if (n == raw.len) return std.fmt.bytesToHex(raw, .lower);
        } else |_| {}
    }
    const seed = platform.monotonicNs() ^ (@as(u64, @intCast(@abs(platform.realTime().nsec))) << 17);
    std.mem.writeInt(u64, raw[0..8], seed, .little);
    return std.fmt.bytesToHex(raw, .lower);
}

fn isNativeLibrary(name: []const u8) bool {
    return std.mem.endsWith(u8, name, ".dylib") or
        std.mem.endsWith(u8, name, ".so") or
        std.mem.indexOf(u8, name, ".so.") != null or
        std.mem.endsWith(u8, name, ".dll");
}

fn boolStr(b: bool) []const u8 {
    return if (b) "yes" else "no";
}

// ── Rendering ────────────────────────────────────────────────────────────────

fn renderText(w: *std.Io.Writer, report: *const Report) std.Io.Writer.Error!void {
    const findings = report.items();

    try w.writeAll("kaappi doctor\n\n");

    var prev_group: ?[]const u8 = null;
    for (findings) |f| {
        if (prev_group == null or !std.mem.eql(u8, prev_group.?, f.group)) {
            if (prev_group != null) try w.writeByte('\n');
            try w.print("{s}\n", .{f.group});
            prev_group = f.group;
        }
        try w.print("  {s}  {s}: {s}\n", .{ f.status.label(), f.label, f.detail });
        if (f.suggestion) |s| {
            try w.print("        \u{2192} {s}\n", .{s});
        }
    }

    var n_pass: usize = 0;
    var n_warn: usize = 0;
    var n_fail: usize = 0;
    for (findings) |f| switch (f.status) {
        .pass => n_pass += 1,
        .warn => n_warn += 1,
        .fail => n_fail += 1,
    };

    try w.print("\nSummary: {d} pass, {d} warn, {d} fail — ", .{ n_pass, n_warn, n_fail });
    try w.writeAll(switch (overall(findings)) {
        .pass => "environment looks healthy.\n",
        .warn => "usable, but some checks need attention.\n",
        .fail => "problems found; see FAIL lines above.\n",
    });
}

fn renderJson(w: *std.Io.Writer, report: *const Report) std.Io.Writer.Error!void {
    const findings = report.items();

    try w.writeAll("{\"version\":");
    try lsp_diagnostic.writeJsonString(w, version);
    try w.writeAll(",\"target\":");
    try lsp_diagnostic.writeJsonString(w, target_triple);
    try w.writeAll(",\"build_mode\":");
    try lsp_diagnostic.writeJsonString(w, build_mode);
    try w.writeAll(",\"status\":");
    try lsp_diagnostic.writeJsonString(w, overall(findings).jsonLabel());
    try w.print(",\"ok\":{s}", .{if (exitCode(findings) == 0) "true" else "false"});
    try w.writeAll(",\"checks\":[");
    for (findings, 0..) |f, i| {
        if (i > 0) try w.writeByte(',');
        try w.writeAll("{\"group\":");
        try lsp_diagnostic.writeJsonString(w, f.group);
        try w.writeAll(",\"label\":");
        try lsp_diagnostic.writeJsonString(w, f.label);
        try w.writeAll(",\"status\":");
        try lsp_diagnostic.writeJsonString(w, f.status.jsonLabel());
        try w.writeAll(",\"detail\":");
        try lsp_diagnostic.writeJsonString(w, f.detail);
        try w.writeAll(",\"suggestion\":");
        if (f.suggestion) |s| {
            try lsp_diagnostic.writeJsonString(w, s);
        } else {
            try w.writeAll("null");
        }
        try w.writeByte('}');
    }
    try w.writeAll("]}\n");
}

fn printUsage() void {
    writeStdout(
        \\Usage: kaappi doctor [--json] [--lib-path <path>]
        \\
        \\Check the installation and environment: binary, library search path,
        \\package manager, native backend, REPL, and FFI. Prints PASS/WARN/FAIL
        \\per check, each failure with a concrete suggestion.
        \\
        \\  --json              Emit one JSON object (meta + a "checks" array).
        \\  --lib-path <path>   Include a path in the library-resolution check,
        \\                      exactly as a real run would prepend it.
        \\
        \\Exit status is nonzero only when a check is FAIL.
        \\
    );
}

// ── Tests ────────────────────────────────────────────────────────────────────

const testing = std.testing;

test "overall verdict is the most severe finding" {
    try testing.expectEqual(Status.pass, overall(&.{
        .{ .group = "g", .label = "a", .status = .pass, .detail = "" },
    }));
    try testing.expectEqual(Status.warn, overall(&.{
        .{ .group = "g", .label = "a", .status = .pass, .detail = "" },
        .{ .group = "g", .label = "b", .status = .warn, .detail = "" },
    }));
    try testing.expectEqual(Status.fail, overall(&.{
        .{ .group = "g", .label = "a", .status = .warn, .detail = "" },
        .{ .group = "g", .label = "b", .status = .fail, .detail = "" },
    }));
    try testing.expectEqual(Status.pass, overall(&.{}));
}

test "exit code is nonzero only when a finding is FAIL" {
    try testing.expectEqual(@as(u8, 0), exitCode(&.{
        .{ .group = "g", .label = "a", .status = .pass, .detail = "" },
        .{ .group = "g", .label = "b", .status = .warn, .detail = "" },
    }));
    try testing.expectEqual(@as(u8, 1), exitCode(&.{
        .{ .group = "g", .label = "a", .status = .warn, .detail = "" },
        .{ .group = "g", .label = "b", .status = .fail, .detail = "" },
    }));
}

test "isNativeLibrary matches platform shared-library names" {
    try testing.expect(isNativeLibrary("libfoo.dylib"));
    try testing.expect(isNativeLibrary("libfoo.so"));
    try testing.expect(isNativeLibrary("libfoo.so.6"));
    try testing.expect(!isNativeLibrary("foo.sld"));
    try testing.expect(!isNativeLibrary("README.md"));
    try testing.expect(!isNativeLibrary("libfoo.a"));
}

test "text render groups findings and prints a summary" {
    var report = Report.init(testing.allocator);
    defer report.deinit();
    report.add("binary", "version", .pass, "v9.9.9", null);
    report.add("native-backend", "libkaappi_rt.a", .warn, "not found", "run 'zig build lib'");

    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    try renderText(&aw.writer, &report);
    const out = aw.written();

    try testing.expect(std.mem.indexOf(u8, out, "kaappi doctor") != null);
    try testing.expect(std.mem.indexOf(u8, out, "binary") != null);
    try testing.expect(std.mem.indexOf(u8, out, "PASS  version: v9.9.9") != null);
    try testing.expect(std.mem.indexOf(u8, out, "WARN  libkaappi_rt.a: not found") != null);
    // suggestion arrow line
    try testing.expect(std.mem.indexOf(u8, out, "run 'zig build lib'") != null);
    try testing.expect(std.mem.indexOf(u8, out, "1 pass, 1 warn, 0 fail") != null);
}

test "json render is one object with meta and a checks array" {
    var report = Report.init(testing.allocator);
    defer report.deinit();
    report.add("binary", "version", .pass, "v9.9.9", null);
    report.add("native-backend", "KAAPPI_LIB_DIR", .fail, "missing", "unset it");

    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    try renderJson(&aw.writer, &report);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, aw.written(), .{});
    defer parsed.deinit();
    const obj = parsed.value.object;

    try testing.expect(obj.get("version") != null);
    try testing.expect(obj.get("target") != null);
    try testing.expect(obj.get("build_mode") != null);
    // A FAIL finding drives status=fail and ok=false.
    try testing.expectEqualStrings("fail", obj.get("status").?.string);
    try testing.expectEqual(false, obj.get("ok").?.bool);

    const checks = obj.get("checks").?.array;
    try testing.expectEqual(@as(usize, 2), checks.items.len);
    try testing.expectEqualStrings("binary", checks.items[0].object.get("group").?.string);
    try testing.expectEqualStrings("version", checks.items[0].object.get("label").?.string);
    // A pass finding with no suggestion serializes suggestion as JSON null.
    switch (checks.items[0].object.get("suggestion").?) {
        .null => {},
        else => return error.TestExpectedNullSuggestion,
    }
    try testing.expectEqualStrings("unset it", checks.items[1].object.get("suggestion").?.string);
}

test "json render marks ok=true when no finding fails" {
    var report = Report.init(testing.allocator);
    defer report.deinit();
    report.add("binary", "version", .pass, "v9.9.9", null);
    report.add("library", "~/.kaappi/lib", .warn, "missing", "install");

    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    try renderJson(&aw.writer, &report);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, aw.written(), .{});
    defer parsed.deinit();
    try testing.expectEqualStrings("warn", parsed.value.object.get("status").?.string);
    try testing.expectEqual(true, parsed.value.object.get("ok").?.bool);
}

test "probeAll produces findings for every check group" {
    var report = Report.init(testing.allocator);
    defer report.deinit();
    probeAll(&report, &.{});

    const groups = [_][]const u8{ "binary", "library", "package-manager", "native-backend", "repl", "ffi" };
    for (groups) |g| {
        var seen = false;
        for (report.items()) |f| {
            if (std.mem.eql(u8, f.group, g)) {
                seen = true;
                break;
            }
        }
        try testing.expect(seen);
    }
}
