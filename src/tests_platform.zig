// Platform shim tests (src/platform.zig), extracted from that file's tail
// when it outgrew the 1500-line policy. They run on the host platform; the
// Windows arms are exercised by the cross-compiled unit-test binary on a
// Windows machine. appendQuotedArg/buildCommandLineW are pub solely for
// this file.
const std = @import("std");
const builtin = @import("builtin");
const platform = @import("platform.zig");

const is_windows = platform.is_windows;
const is_wasm = builtin.target.cpu.arch.isWasm();

fn expectQuoted(expected: []const u8, arg: []const u8) !void {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(std.testing.allocator);
    try platform.appendQuotedArg(&list, std.testing.allocator, arg);
    try std.testing.expectEqualStrings(expected, list.items);
}

// CommandLineToArgvW-inverse quoting: these are the canonical cases from
// the Windows command-line parsing rules; the child's CRT must parse each
// quoted form back to the original argument.
test "appendQuotedArg: plain arg unquoted" {
    try expectQuoted("abc", "abc");
}

test "appendQuotedArg: spaces force quotes" {
    try expectQuoted("\"two words\"", "two words");
}

test "appendQuotedArg: empty arg becomes empty quotes" {
    try expectQuoted("\"\"", "");
}

test "appendQuotedArg: embedded quote gets a backslash" {
    try expectQuoted("\"say \\\" it\"", "say \" it");
}

test "appendQuotedArg: backslashes before a quote double" {
    // arg: a\"b  →  "a\\\"b" (the two backslashes encode one literal \,
    // the third escapes the quote)
    try expectQuoted("\"a\\\\\\\"b\"", "a\\\"b");
}

test "appendQuotedArg: trailing backslashes double before the closing quote" {
    // arg: dir\ with a space → "dir \\" so the closing quote isn't eaten
    try expectQuoted("\"dir \\\\\"", "dir \\");
}

test "appendQuotedArg: backslashes not before a quote stay literal" {
    // Windows paths with spaces: no doubling mid-string
    try expectQuoted("\"C:\\Program Files\\kaappi\"", "C:\\Program Files\\kaappi");
}

test "buildCommandLineW joins and round-trips through WTF-16" {
    const argv = [_][]const u8{ "git", "-C", "C:\\repo dir", "checkout", "v1.0.0", "--" };
    const wline = try platform.buildCommandLineW(std.testing.allocator, &argv);
    defer std.testing.allocator.free(wline);
    var narrow: [256]u8 = undefined;
    const n = std.unicode.wtf16LeToWtf8(&narrow, wline);
    try std.testing.expectEqualStrings("git -C \"C:\\repo dir\" checkout v1.0.0 --", narrow[0..n]);
}

test "monotonicNs advances" {
    const a = platform.monotonicNs();
    const b = platform.monotonicNs();
    try std.testing.expect(b >= a);
}

test "realTime is after 2020" {
    const rt = platform.realTime();
    try std.testing.expect(rt.sec > 1577836800); // 2020-01-01
    try std.testing.expect(rt.nsec >= 0 and rt.nsec < 1_000_000_000);
}

test "statPath reports a directory" {
    if (comptime is_wasm) return error.SkipZigTest;
    const cwd_path = if (is_windows) "." else "/tmp";
    const st = platform.statPath(cwd_path) orelse return error.TestUnexpectedResult;
    try std.testing.expect(st.is_dir);
    try std.testing.expect(!st.is_file);
}

test "write to stdout-like sink via openNullSink" {
    if (comptime is_wasm) return error.SkipZigTest;
    const fd = try platform.openNullSink();
    defer platform.close(fd);
    const msg = "platform shim probe\n";
    const rc = platform.write(fd, msg.ptr, msg.len);
    try std.testing.expect(rc == @as(isize, @intCast(msg.len)));
}

test "dlSym on the dlOpen(null) process handle finds CRT symbols (#1611)" {
    // The (ffi-open #f) contract: the process handle resolves C runtime
    // symbols — on Windows via the all-loaded-modules search (abs lives in
    // ucrtbase.dll, never in the exe's export table), on POSIX via dlsym's
    // global symbol scope.
    if (comptime is_wasm) return error.SkipZigTest;
    if (comptime builtin.target.abi.isMusl()) return error.SkipZigTest; // static libc: no dynamic loading
    const proc = platform.dlOpen(null) orelse return error.TestUnexpectedResult;
    defer platform.dlClose(proc);
    try std.testing.expect(platform.dlSym(proc, "abs") != null);
    // A miss reports failure without poisoning later lookups.
    try std.testing.expect(platform.dlSym(proc, "kaappi_no_such_symbol_1611") == null);
    _ = platform.dlError();
    try std.testing.expect(platform.dlSym(proc, "abs") != null);
}

test "getExePath resolves the running test binary to an absolute path" {
    // Per-OS lookup (kaappi_paths.zig): /proc/self/exe on Linux,
    // _NSGetExecutablePath on macOS, GetModuleFileNameW on Windows,
    // sysctl kern.proc.pathname on FreeBSD, sysctl
    // kern.proc_args.<pid>.pathname on NetBSD, argv[0] resolution on
    // OpenBSD. Every platform this suite executes on must resolve the
    // test binary itself; only WASI (which never runs unit tests)
    // legitimately returns null.
    if (comptime is_wasm) return error.SkipZigTest;
    const paths = @import("kaappi_paths.zig");
    var buf: [4096]u8 = undefined;
    const p = paths.getExePath(&buf) orelse return error.TestUnexpectedResult;
    if (is_windows) {
        try std.testing.expect(p.len > 2 and p[1] == ':');
    } else {
        try std.testing.expect(p.len > 0 and p[0] == '/');
    }
}

var fpcr_denormal_numerator: f64 = 4.9406564584124654e-308;
var fpcr_denormal_divisor: f64 = 1e16;

test "denormal arithmetic survives after normalizeFpEnvBestEffort" {
    // NetBSD/aarch64 boots processes with FPCR.FZ set — denormals flush
    // to zero and SRFI-144's `(> fl-least 0.0)` turns false — which
    // normalizeFpEnvBestEffort corrects at startup (platform.zig). The
    // test binary has no main.zig startup, so make the call here, then
    // prove gradual underflow works: this quotient is the smallest
    // positive denormal (5e-324) under IEEE-754 and exactly 0.0 under
    // flush-to-zero. Globals (not comptime consts) keep the division a
    // runtime operation. On every other platform the call is a no-op and
    // the property already holds.
    platform.normalizeFpEnvBestEffort();
    const q = fpcr_denormal_numerator / fpcr_denormal_divisor;
    try std.testing.expect(q > 0.0);
    try std.testing.expect(q == std.math.floatTrueMin(f64));
}
