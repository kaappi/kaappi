//! Unit tests for `run-process` and the `process-timeout` condition —
//! KEP-0022 Phase 4 (kaappi#2417).
//!
//! Split out of `tests_process.zig` (already near the 1500-line policy
//! ceiling) along the phase seam: everything here exercises the one-shot
//! layer — option parsing, the concurrent drain, `input:`, `timeout:` and
//! the condition it raises — rather than the spawn/wait/kill primitives
//! underneath it.
//!
//! Like its sibling, every test drives a real child through /bin/sh, so the
//! POSIX gate is the same. Windows coverage for the same surface lives in
//! the portable Scheme matrix (`tests/scheme/process/process-portable.scm`),
//! which runs kaappi itself as the child.

const std = @import("std");
const builtin = @import("builtin");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");

const is_posix = switch (builtin.os.tag) {
    .windows, .wasi => false,
    else => true,
};

/// `th.expectEvalTrue` on a *caller-owned* VM. Every test below that needs
/// only one assertion uses the shared helper directly (it builds and tears
/// down its own VM); this one exists for the tests that must share a single
/// interaction environment across several evals, which the shared helper
/// cannot do — and mixing the two in one test would leave `gc_instance`
/// dangling when the helper's context deinits. Same split, and the same
/// reason, as `tests_process.zig`.
fn expectTrue(vm: *vm_mod.VM, source: []const u8) !void {
    const result = vm.eval(source) catch |e| {
        std.debug.print("eval error from: {s}\n  detail: {s}\n", .{ source, vm.last_error_detail[0..vm.last_error_detail_len] });
        return e;
    };
    if (result != types.TRUE) {
        std.debug.print("expected #t from: {s}\n", .{source});
        return error.TestExpectedTrue;
    }
}

fn evalTo(vm: *vm_mod.VM, source: []const u8) ![]u8 {
    const printer = @import("printer.zig");
    const result = try vm.eval(source);
    return printer.valueToString(std.testing.allocator, result, .write);
}

test "run-process: status, stdout and stderr come back as three values" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const s = try evalTo(ctx.vm,
        \\(call-with-values
        \\  (lambda ()
        \\    (run-process '("/bin/sh" "-c" "printf out; printf err 1>&2; exit 3")))
        \\  list)
    );
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(3 \"out\" \"err\")", s);
}

test "run-process: stdin is /dev/null unless input: is given" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    // A child that reads stdin must see EOF immediately rather than the
    // parent's terminal: a one-shot capture that blocks on the tty is the
    // failure mode `'null` (Go's `exec.Cmd` default) exists to prevent.
    const s = try evalTo(ctx.vm,
        \\(call-with-values (lambda () (run-process '("/bin/cat"))) list)
    );
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(0 \"\" \"\")", s);
}

test "run-process: input: feeds the child, as a string or a bytevector" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    try expectTrue(vm,
        \\(call-with-values (lambda () (run-process '("/bin/cat") 'input: "hello"))
        \\  (lambda (st out err) (and (= st 0) (string=? out "hello") (string=? err ""))))
    );
    try expectTrue(vm,
        \\(call-with-values
        \\  (lambda () (run-process '("/bin/cat") 'input: (string->utf8 "bytes")))
        \\  (lambda (st out err) (string=? out "bytes")))
    );
}

test "run-process: a child that never reads its stdin is not an error (EPIPE is swallowed)" {
    if (comptime !is_posix) return error.SkipZigTest;

    // The write side gets EPIPE the moment `true` exits; Python's
    // communicate() swallows the same BrokenPipeError, because the child's
    // verdict is its exit status, not a failure of the feed.
    //
    // 256 KiB, not 64: Linux's default pipe capacity is *exactly* 65536, so
    // a 64 KiB feed can land in the buffer whole and never break at all —
    // the assertion would pass without the swallow it exists to check.
    try th.expectEvalTrue(
        \\(call-with-values
        \\  (lambda () (run-process '("/usr/bin/true") 'input: (make-string 262144 #\x)))
        \\  (lambda (st out err) (and (= st 0) (string=? out ""))))
    );
}

test "run-process: a pipe past its buffer drains while the wait parks" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // The deadlock this API exists to prevent. Both directions are past the
    // 64 KiB pipe buffer every supported platform uses, so a serial
    // "feed it, then read it" wedges: the parent blocks writing while the
    // child blocks writing to a stdout nobody is draining.
    //
    // /bin/cat is the generator on purpose. `head -c` is a GNU/FreeBSD
    // extension OpenBSD's head does not have, and `dd count=` on a pipe
    // counts read() calls rather than bytes — both make a "generate N
    // bytes" child unportable, and the three-streams-at-once case is
    // covered portably in tests/scheme/process/process-run.scm, whose
    // child is kaappi itself.
    // 70 KiB-ish: past the 64 KiB pipe buffer, which is the only property
    // this test needs, and a third of the byte traffic a rounder 200_000
    // would cost the QEMU-emulated riscv64/s390x legs. Deliberately *not*
    // scaled down under -Dgc-stress: a size below the pipe buffer produces
    // no backpressure at all, so the stress leg would run a test that
    // cannot fail. The byte count costs it nothing either way — the cost
    // under stress is per allocation, and a bulk read is a handful.
    const n: usize = 70_000;
    var buf: [512]u8 = undefined;

    const to_stdout = try std.fmt.bufPrint(&buf,
        \\(call-with-values
        \\  (lambda () (run-process '("/bin/cat") 'input: (make-string {d} #\i)))
        \\  (lambda (st out err)
        \\    (and (= st 0) (= (string-length out) {d}) (string=? err ""))))
    , .{ n, n });
    try expectTrue(vm, to_stdout);

    var buf2: [512]u8 = undefined;
    const to_stderr = try std.fmt.bufPrint(&buf2,
        \\(call-with-values
        \\  (lambda () (run-process '("/bin/sh" "-c" "cat 1>&2")
        \\                          'input: (make-string {d} #\i)))
        \\  (lambda (st out err)
        \\    (and (= st 0) (string=? out "") (= (string-length err) {d}))))
    , .{ n, n });
    try expectTrue(vm, to_stderr);
}

test "run-process: output: 'bytevector returns raw bytes" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    const s = try evalTo(vm,
        \\(call-with-values
        \\  (lambda () (run-process '("/bin/sh" "-c" "printf abc") 'output: 'bytevector))
        \\  (lambda (st out err) out))
    );
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("#u8(97 98 99)", s);

    // The reason the option exists: a child emitting non-UTF-8 bytes has no
    // string representation, and the default would fail in `utf8->string`
    // with a type error naming a procedure the caller never called.
    try expectTrue(vm,
        \\(call-with-values
        \\  (lambda () (run-process '("/bin/sh" "-c" "printf '\\377\\376'") 'output: 'bytevector))
        \\  (lambda (st out err) (= 2 (bytevector-length out))))
    );
}

test "run-process: directory: and env: pass through to the spawn" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // `directory:` has no portable POSIX backing: NetBSD's and OpenBSD's
    // libc have no `posix_spawn_file_actions_addchdir_np`, and
    // `process_posix.supports_directory` is false there, so spawn-process
    // rejects the option with an argument error (KP3007) rather than
    // silently ignoring it. Both outcomes are asserted precisely — a bare
    // `(guard (e (#t #t)) ...)` would pass on every platform for the wrong
    // reason.
    try expectTrue(vm,
        \\(guard (e ((error-object? e) (eq? 'KP3007 (error-object-code e))))
        \\  (call-with-values
        \\    (lambda () (run-process '("/bin/sh" "-c" "pwd") 'directory: "/"))
        \\    (lambda (st out err) (string=? out "/\n"))))
    );
    try expectTrue(vm,
        \\(call-with-values
        \\  (lambda () (run-process '("/bin/sh" "-c" "printf %s $KP2417")
        \\                          'env: (cons (cons "KP2417" "set") (process-environment))))
        \\  (lambda (st out err) (string=? out "set")))
    );
}

test "run-process: timeout: raises process-timeout carrying the partial output" {
    if (comptime !is_posix) return error.SkipZigTest;
    // The child prints, then sleeps past the deadline. What it managed to
    // write must survive on the condition — the condition is the only route
    // to it, since the values return never happens.
    try th.expectEvalTrue(
        \\(guard (e ((process-timeout? e)
        \\           (and (string=? (process-timeout-stdout e) "partial")
        \\                (string=? (process-timeout-stderr e) "half")
        \\                (error-object? e)
        \\                (equal? (error-object-irritants e)
        \\                        (list '("/bin/sh" "-c" "printf partial; printf half 1>&2; sleep 30") 0.25)))))
        \\  (run-process '("/bin/sh" "-c" "printf partial; printf half 1>&2; sleep 30")
        \\               'timeout: 0.25)
        \\  'no-condition-raised)
    );
}

test "run-process: a child finishing inside its timeout returns normally" {
    if (comptime !is_posix) return error.SkipZigTest;
    try th.expectEvalTrue(
        \\(call-with-values
        \\  (lambda () (run-process '("/bin/sh" "-c" "printf quick") 'timeout: 30))
        \\  (lambda (st out err) (and (= st 0) (string=? out "quick"))))
    );
}

test "run-process: the timeout kill reaches a grandchild holding the same pipe" {
    if (comptime !is_posix) return error.SkipZigTest;
    // `timeout:` implies `new-group: #t`, and the group kill is what lets the
    // drain fibers reach EOF at all: the grandchild inherits stdout, so a
    // child-only kill would leave the pipe open and this call would never
    // return. Reaching the guard clause *is* the assertion.
    try th.expectEvalTrue(
        \\(guard (e ((process-timeout? e) (string=? (process-timeout-stdout e) "up")))
        \\  (run-process '("/bin/sh" "-c" "sleep 30 & printf up; sleep 30") 'timeout: 0.25)
        \\  'no-condition-raised)
    );
}

test "run-process: process-timeout accessors reject every other condition" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    _ = try vm.eval("(define plain (guard (e (#t e)) (error \"x\")))");
    try expectTrue(vm, "(error-object? plain)");
    try expectTrue(vm, "(not (process-timeout? plain))");
    try expectTrue(vm, "(not (process-timeout? 42))");
    try std.testing.expectError(
        vm_mod.VMError.TypeError,
        vm.eval("(process-timeout-stdout plain)"),
    );
    try std.testing.expectError(
        vm_mod.VMError.TypeError,
        vm.eval("(process-timeout-stderr 42)"),
    );
}

test "run-process: option errors are loud" {
    if (comptime !is_posix) return error.SkipZigTest;
    try th.expectEvalTrue(
        \\(begin
        \\  (define (bad thunk) (guard (e (#t #t)) (thunk) #f))
        \\  (and (bad (lambda () (run-process '("/usr/bin/true") 'nonsense: 1)))
        \\       (bad (lambda () (run-process '("/usr/bin/true") 'input:)))
        \\       (bad (lambda () (run-process '("/usr/bin/true") 'input: 42)))
        \\       (bad (lambda () (run-process '("/usr/bin/true") 'output: 'utf16)))
        \\       (bad (lambda () (run-process '("/no/such/program/2417"))))))
    );
}

test "run-process: a spawn failure is a file error, not a timeout condition" {
    if (comptime !is_posix) return error.SkipZigTest;
    // KEP-0005 taxonomy: program-not-found is the same family as a failed
    // open, so `file-error?` sees it and errno tells ENOENT from EACCES.
    try th.expectEvalTrue(
        \\(guard (e (#t (and (file-error? e) (not (process-timeout? e)))))
        \\  (run-process '("/no/such/program/2417"))
        \\  'no-error-raised)
    );
}

test "run-process: runs inside a spawned fiber, and siblings overlap" {
    if (comptime !is_posix) return error.SkipZigTest;
    // Two children that each sleep must finish in about one sleep, not two:
    // the internal drain fibers of one call must not block the other call's
    // wait. This also covers the dispatched-fiber entry path, where
    // `process-wait` parks flat instead of driving the scheduler in place.
    try th.expectEvalTrue(
        \\(begin
        \\  (import (kaappi fibers))
        \\  (define (sleeper) (spawn (lambda ()
        \\    (call-with-values (lambda () (run-process '("/bin/sh" "-c" "sleep 0.4; printf x")))
        \\      (lambda (st out err) out)))))
        \\  (let* ((t0 (current-jiffy))
        \\         (a (sleeper))
        \\         (b (sleeper))
        \\         (ra (fiber-join a))
        \\         (rb (fiber-join b))
        \\         (dt (/ (- (current-jiffy) t0) (jiffies-per-second))))
        \\    (and (string=? ra "x") (string=? rb "x") (< dt 0.75))))
    );
}
