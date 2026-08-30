//! Behavioral tests for `(kaappi process)` — Phase 1 (KEP-0022, kaappi#2414).
//! POSIX only: the whole library is excluded from the WASM and Windows
//! builds, so every test here skips on those targets. The GC-tracing /
//! remembered-set coverage for the `Process` heap type lives in
//! `tests_gc_tracing.zig` (which owns the tracing harness).
//!
//! These drive real child processes (`sh`, `printf`, `cat`, …) through
//! evaluated Scheme, exercising the whole path — spawn, pipe ports, blocking
//! wait, status decoding — and stay green under `-Dgc-stress=true` because
//! every spawn allocates a `Process` plus its ports through the rooted
//! allocator path.
//!
//! Single-expression assertions use `th.expectEval*`; tests that need the
//! shared `drain` helper across multiple evaluations use `th.TestContext`.

const std = @import("std");
const builtin = @import("builtin");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const platform = @import("platform.zig");

const posix = builtin.os.tag != .wasi and builtin.os.tag != .windows;
/// posix_spawn_file_actions_addchdir_np is absent on NetBSD/OpenBSD, so
/// `directory:` is unsupported there (matches primitives_process.have_addchdir_np).
const have_chdir = switch (builtin.os.tag) {
    .linux, .macos, .freebsd => true,
    else => false,
};

fn isCloexec(fd: platform.fd_t) bool {
    const flags = std.c.fcntl(fd, std.posix.F.GETFD, @as(c_int, 0));
    return flags >= 0 and (flags & std.posix.FD_CLOEXEC) != 0;
}

/// Read a whole binary port to EOF, returning the bytes as a string.
const drain_def =
    \\(define (drain port)
    \\  (let loop ((acc '()))
    \\    (let ((b (read-u8 port)))
    \\      (if (eof-object? b)
    \\          (list->string (map integer->char (reverse acc)))
    \\          (loop (cons b acc))))))
;

/// A TestContext with `drain` already defined — for the pipe/capture tests.
fn withDrain(ctx: *th.TestContext) !void {
    try ctx.init();
    _ = try ctx.vm.eval(drain_def);
}

fn evalTrue(ctx: *th.TestContext, src: []const u8) !void {
    try std.testing.expectEqual(types.TRUE, try ctx.vm.eval(src));
}

// --- exit-status matrix -----------------------------------------------------

test "process: exit status matrix (exit code)" {
    if (!posix) return error.SkipZigTest;
    try th.expectEval("(process-wait (spawn-process '(\"sh\" \"-c\" \"exit 0\")))", 0);
    try th.expectEval("(process-wait (spawn-process '(\"sh\" \"-c\" \"exit 7\")))", 7);
}

test "process: signal death decodes to (signaled . n)" {
    if (!posix) return error.SkipZigTest;
    // Kill with SIGKILL, which is uncatchable, so the child always dies *by
    // the signal* on every platform. A shell's own SIGTERM handling is not
    // portable — OpenBSD's /bin/sh turns `kill -TERM $$` into a 143 exit code
    // rather than a signal death — so drive the kill through Kaappi instead.
    try th.expectEvalTrue(
        \\(let ((p (spawn-process '("sleep" "60"))))
        \\  (process-kill p 'signal: 9)
        \\  (equal? '(signaled . 9) (process-wait p)))
    );
}

// --- predicate & accessors --------------------------------------------------

test "process: predicate" {
    if (!posix) return error.SkipZigTest;
    // Reap the child so the test leaves no zombie behind.
    try th.expectEvalTrue(
        \\(let ((p (spawn-process '("sh" "-c" "exit 0"))))
        \\  (let ((ok (process? p)))
        \\    (process-wait p)
        \\    ok))
    );
    try th.expectEvalTrue("(not (process? 42))");
}

test "process: positive pid" {
    if (!posix) return error.SkipZigTest;
    try th.expectEvalTrue(
        \\(let ((p (spawn-process '("sh" "-c" "exit 0"))))
        \\  (let ((ok (> (process-pid p) 0)))
        \\    (process-wait p)
        \\    ok))
    );
}

test "process: 'inherit accessors return #f" {
    if (!posix) return error.SkipZigTest;
    try th.expectEvalTrue(
        \\(let ((p (spawn-process '("sh" "-c" "exit 0"))))
        \\  (let ((r (and (not (process-stdin p))
        \\                (not (process-stdout p))
        \\                (not (process-stderr p)))))
        \\    (process-wait p)
        \\    r))
    );
}

test "process: 'inherit gives the child a working stream" {
    if (!posix) return error.SkipZigTest;
    // A child that writes to inherited stderr must succeed (exit 0), not fail
    // with EBADF (exit 7) — the regression for the macOS
    // POSIX_SPAWN_CLOEXEC_DEFAULT behavior that closed inherited stdio.
    try th.expectEval(
        \\(process-wait (spawn-process '("sh" "-c" "printf x 1>&2 || exit 7")
        \\                             'stderr: 'inherit))
    , 0);
}

// --- pipes ------------------------------------------------------------------

test "process: capture stdout via pipe" {
    if (!posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try withDrain(&ctx);
    defer ctx.deinit();
    try evalTrue(&ctx,
        \\(let ((p (spawn-process '("sh" "-c" "printf hello") 'stdout: 'pipe)))
        \\  (let ((s (drain (process-stdout p))))
        \\    (process-wait p)
        \\    (string=? s "hello")))
    );
}

test "process: bidirectional pipe (cat round-trip)" {
    if (!posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try withDrain(&ctx);
    defer ctx.deinit();
    try evalTrue(&ctx,
        \\(let ((p (spawn-process '("cat") 'stdin: 'pipe 'stdout: 'pipe)))
        \\  (let ((in (process-stdin p)))
        \\    (write-u8 (char->integer #\O) in)
        \\    (write-u8 (char->integer #\K) in)
        \\    (close-port in))
        \\  (let ((s (drain (process-stdout p))))
        \\    (process-wait p)
        \\    (string=? s "OK")))
    );
}

// --- redirection matrix -----------------------------------------------------

test "process: stderr 'null is discarded, stdout still captured" {
    if (!posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try withDrain(&ctx);
    defer ctx.deinit();
    try evalTrue(&ctx,
        \\(let ((p (spawn-process '("sh" "-c" "printf OUT; printf ERR 1>&2")
        \\                        'stdout: 'pipe 'stderr: 'null)))
        \\  (let ((s (drain (process-stdout p))))
        \\    (process-wait p)
        \\    (string=? s "OUT")))
    );
}

test "process: stderr 'stdout merges into the stdout pipe" {
    if (!posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try withDrain(&ctx);
    defer ctx.deinit();
    try evalTrue(&ctx,
        \\(let ((p (spawn-process '("sh" "-c" "printf O; printf E 1>&2")
        \\                        'stdout: 'pipe 'stderr: 'stdout)))
        \\  (let ((s (drain (process-stdout p))))
        \\    (process-wait p)
        \\    (string=? s "OE")))
    );
}

// --- directory: / env: ------------------------------------------------------

test "process: directory: changes the child's cwd" {
    if (!posix or !have_chdir) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try withDrain(&ctx);
    defer ctx.deinit();
    try evalTrue(&ctx,
        \\(let ((p (spawn-process '("sh" "-c" "pwd") 'stdout: 'pipe 'directory: "/")))
        \\  (let ((s (drain (process-stdout p))))
        \\    (process-wait p)
        \\    (string=? s "/\n")))
    );
}

test "process: env: replaces the environment wholesale" {
    if (!posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try withDrain(&ctx);
    defer ctx.deinit();
    try evalTrue(&ctx,
        \\(let ((p (spawn-process '("sh" "-c" "printf %s \"$KP_TEST_VAR\"")
        \\                        'stdout: 'pipe
        \\                        'env: '(("KP_TEST_VAR" . "kaappi-2414")
        \\                                ("PATH" . "/usr/bin:/bin")))))
        \\  (let ((s (drain (process-stdout p))))
        \\    (process-wait p)
        \\    (string=? s "kaappi-2414")))
    );
}

test "process: process-environment returns a non-empty alist" {
    if (!posix) return error.SkipZigTest;
    try th.expectEvalTrue(
        \\(let ((e (process-environment)))
        \\  (and (pair? e) (pair? (car e)) (string? (caar e))))
    );
}

// --- status / wait ----------------------------------------------------------

test "process: status is stable after wait; wait is idempotent" {
    if (!posix) return error.SkipZigTest;
    try th.expectEvalTrue(
        \\(let ((p (spawn-process '("sh" "-c" "exit 4"))))
        \\  (let ((a (process-wait p))
        \\        (b (process-wait p))
        \\        (c (process-status p)))
        \\    (and (= a 4) (= b 4) (= c 4))))
    );
}

// --- kill -------------------------------------------------------------------

test "process: kill terminates a child; kill-after-reap is a no-op" {
    if (!posix) return error.SkipZigTest;
    try th.expectEvalTrue(
        \\(let ((p (spawn-process '("sleep" "60"))))
        \\  (process-kill p)
        \\  (equal? '(signaled . 15) (process-wait p)))
    );
    try th.expectEvalTrue(
        \\(let ((p (spawn-process '("sh" "-c" "exit 0"))))
        \\  (process-wait p)
        \\  (process-kill p 'signal: 9)
        \\  (= 0 (process-status p)))
    );
}

test "process: out-of-range signal raises, never aborts the VM" {
    if (!posix) return error.SkipZigTest;
    // Regression: process-kill fed a signal fixnum outside c_int range must
    // raise a catchable error, not trip @intCast's overflow check and abort
    // the process uncatchably (kaappi#2414 review).
    try th.expectEvalTrue(
        \\(let ((p (spawn-process '("sleep" "60"))))
        \\  (let ((raised (guard (e (#t #t))
        \\                  (process-kill p 'signal: 999999999999)
        \\                  #f)))
        \\    (process-kill p)      ; a normal kill still works afterward
        \\    (process-wait p)
        \\    raised))
    );
}

test "process: new-group puts the child in its own group; group kill works" {
    if (!posix) return error.SkipZigTest;
    try th.expectEvalTrue(
        \\(let ((p (spawn-process '("sleep" "60") 'new-group: #t)))
        \\  (let ((own-group (= (process-group p) (process-pid p))))
        \\    (process-kill p 'group: #t 'signal: 9)
        \\    (and own-group (equal? '(signaled . 9) (process-wait p)))))
    );
    // group: #t without new-group: is refused rather than signalling the
    // parent's own group.
    try th.expectEvalTrue(
        \\(let ((p (spawn-process '("sleep" "60"))))
        \\  (let ((r (guard (e (#t #t)) (process-kill p 'group: #t) #f)))
        \\    (process-kill p)
        \\    (process-wait p)
        \\    r))
    );
}

// --- fd hygiene (CLOEXEC audit, kaappi#2414) --------------------------------
// The CLOEXEC audit that keeps Kaappi's own descriptors out of a spawned
// child. The end-to-end "child sees only 0/1/2" assertion lives in
// tests/scheme/process/ — run against a clean binary, since the Zig test
// harness itself holds extra inherited fds (its --listen pipe) that would
// pollute a raw fd count. Here we test the audit's two primitives directly.

test "process: platform.pipe sets FD_CLOEXEC on both ends" {
    if (!posix) return error.SkipZigTest;
    var fds: [2]platform.fd_t = undefined;
    try std.testing.expectEqual(@as(c_int, 0), platform.pipe(&fds));
    defer {
        _ = platform.close(fds[0]);
        _ = platform.close(fds[1]);
    }
    try std.testing.expect(isCloexec(fds[0]));
    try std.testing.expect(isCloexec(fds[1]));
}

test "process: setFdCloexec marks a raw descriptor close-on-exec" {
    if (!posix) return error.SkipZigTest;
    // A raw pipe(2) starts without FD_CLOEXEC; setFdCloexec adds it and
    // reports success.
    var fds: [2]platform.fd_t = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.pipe(&fds));
    defer {
        _ = platform.close(fds[0]);
        _ = platform.close(fds[1]);
    }
    try std.testing.expect(!isCloexec(fds[0]));
    try std.testing.expect(platform.setFdCloexec(fds[0]));
    try std.testing.expect(isCloexec(fds[0]));
}
