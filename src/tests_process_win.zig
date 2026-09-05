//! Unit tests for `(kaappi process)` on Windows — KEP-0022 Phase 3
//! (kaappi#2416).
//!
//! The POSIX suite (`tests_process.zig`) spawns real children through
//! `/bin/sh`; these spawn real children through `cmd.exe`, so they cover the
//! actual `CreateProcessW` path, not a mock. Everything here skips on every
//! other target.
//!
//! Two mechanisms have no POSIX counterpart and are asserted directly rather
//! than through their symptoms:
//!
//! * **The Job Object.** `IsProcessInJob` proves `new-group:` assigned the
//!   child, and `QueryInformationJobObject(JobObjectBasicProcessIdList)`
//!   proves the *grandchild* joined it too — which is the whole reason a Job
//!   Object is used instead of `TerminateProcess`, and the property the
//!   issue's acceptance criterion names.
//! * **The signal mapping.** Windows has no signal delivery, so `signal:`
//!   folds into the exit code `TerminateProcess` stamps: `128 + n`.
//!
//! `ping -n <k> 127.0.0.1` is the sleeper throughout: unlike `timeout`, it
//! needs no console input handle, so it behaves identically whether or not
//! the test runner's stdin is redirected.

const std = @import("std");
const builtin = @import("builtin");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const platform = @import("platform.zig");

const is_windows = builtin.os.tag == .windows;
const win = platform.win;

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

fn expectPrints(vm: *vm_mod.VM, source: []const u8, want: []const u8) !void {
    const got = try evalTo(vm, source);
    defer std.testing.allocator.free(got);
    try std.testing.expectEqualStrings(want, got);
}

test "process/win: the library is present on Windows since Phase 3" {
    if (comptime !is_windows) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try expectPrints(ctx.vm, "(cond-expand ((library (kaappi process)) 'present) (else 'absent))", "present");
}

test "process/win: spawn, wait, status matrix" {
    if (comptime !is_windows) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;
    _ = try vm.eval("(import (kaappi process))");

    try expectTrue(vm, "(= 0 (process-wait (spawn-process '(\"cmd.exe\" \"/c\" \"exit 0\"))))");
    try expectTrue(vm, "(= 7 (process-wait (spawn-process '(\"cmd.exe\" \"/c\" \"exit 7\"))))");
    // Windows has no wait-status word: a status is always the plain exit
    // code, so `(signaled . n)` never appears (types_process.decodeStatus).
    try expectTrue(vm,
        \\(let ((p (spawn-process '("cmd.exe" "/c" "exit 3"))))
        \\  (let* ((w1 (process-wait p)) (s (process-status p)) (w2 (process-wait p)))
        \\    (and (= w1 3) (= s 3) (= w2 3))))
    );
    // A still-running child polls as #f.
    try expectTrue(vm,
        \\(let ((p (spawn-process '("cmd.exe" "/c" "ping -n 20 127.0.0.1 > NUL"))))
        \\  (let ((live (process-status p)))
        \\    (process-kill p 'signal: 9)
        \\    (process-wait p)
        \\    (eq? live #f)))
    );
}

test "process/win: a spawn of a missing program raises a catchable file error" {
    if (comptime !is_windows) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;
    _ = try vm.eval("(import (kaappi process) (srfi 170))");
    // ERROR_FILE_NOT_FOUND folds onto ENOENT (process_win.lastError), so the
    // condition answers the same SRFI-170 predicates a POSIX ENOENT does.
    try expectTrue(vm,
        \\(guard (e ((file-error? e) (and (posix-error? e) (eq? 'ENOENT (posix-error-name e)))))
        \\  (spawn-process '("kaappi-definitely-not-a-real-program-2416"))
        \\  #f)
    );
}

test "process/win: pipes — stdout, stderr, the stderr merge, and null" {
    if (comptime !is_windows) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;
    _ = try vm.eval("(import (kaappi process) (scheme write))");

    // cmd's `echo` emits CRLF; `read-line` treats it as one line ending, so
    // nothing here has to trim a stray CR. Redirections are written *before*
    // the command (`>&2 echo err`, not `echo err 1>&2`) because cmd's `echo`
    // otherwise emits the space that precedes the redirection token as part
    // of the line.
    try expectTrue(vm,
        \\(let ((p (spawn-process '("cmd.exe" "/c" "echo hello") 'stdout: 'pipe)))
        \\  (let ((line (read-line (process-stdout p))))
        \\    (process-wait p)
        \\    (string=? line "hello")))
    );
    // Separate streams: stdout carries only "out", stderr only "err".
    try expectTrue(vm,
        \\(let ((p (spawn-process '("cmd.exe" "/c" "echo out& >&2 echo err")
        \\                        'stdout: 'pipe 'stderr: 'pipe)))
        \\  (let ((o (read-line (process-stdout p)))
        \\        (e (read-line (process-stderr p))))
        \\    (process-wait p)
        \\    (and (string=? o "out") (string=? e "err"))))
    );
    // The merge: stderr becomes the child's stdout handle itself (one file
    // object, dup2(1,2)'s semantics), so both lines arrive on one pipe and
    // `process-stderr` is #f.
    try expectTrue(vm,
        \\(let ((p (spawn-process '("cmd.exe" "/c" "echo one& >&2 echo two")
        \\                        'stdout: 'pipe 'stderr: 'stdout)))
        \\  (let* ((a (read-line (process-stdout p)))
        \\         (b (read-line (process-stdout p))))
        \\    (process-wait p)
        \\    (and (eq? #f (process-stderr p))
        \\         (string=? a "one")
        \\         (string=? b "two"))))
    );
    // 'null is the NUL device: the child writes, nothing is captured, and
    // the accessor is #f.
    try expectTrue(vm,
        \\(let ((p (spawn-process '("cmd.exe" "/c" "echo discarded") 'stdout: 'null)))
        \\  (and (eq? #f (process-stdout p)) (= 0 (process-wait p))))
    );
}

test "process/win: stdin pipe feeds the child" {
    if (comptime !is_windows) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;
    _ = try vm.eval("(import (kaappi process) (scheme write))");
    // `sort` reads stdin to EOF; closing our write end is what ends it, so
    // this also proves the parent's pipe end is genuinely closed by
    // close-output-port rather than lingering in a duplicate.
    try expectTrue(vm,
        \\(let ((p (spawn-process '("cmd.exe" "/c" "sort") 'stdin: 'pipe 'stdout: 'null)))
        \\  (write-string "b\na\n" (process-stdin p))
        \\  (close-output-port (process-stdin p))
        \\  (= 0 (process-wait p)))
    );
}

test "process/win: env: hands the child the environment it names" {
    if (comptime !is_windows) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;
    _ = try vm.eval("(import (kaappi process) (scheme write))");
    // cmd.exe needs COMSPEC/SystemRoot to run at all, so the replacement set
    // carries them — which is exactly the copy-and-extend idiom
    // (process-environment) exists for, exercised end to end.
    try expectTrue(vm,
        \\(let* ((base (process-environment))
        \\       (keep (let loop ((e base) (acc '()))
        \\               (cond ((null? e) acc)
        \\                     ((member (car (car e)) '("SystemRoot" "COMSPEC" "ComSpec" "PATH" "Path"))
        \\                      (loop (cdr e) (cons (car e) acc)))
        \\                     (else (loop (cdr e) acc)))))
        \\       (p (spawn-process '("cmd.exe" "/c" "echo %KAAPPI_2416%")
        \\                         'stdout: 'pipe
        \\                         'env: (cons (cons "KAAPPI_2416" "phase-three") keep))))
        \\  (let ((line (read-line (process-stdout p))))
        \\    (process-wait p)
        \\    (string=? line "phase-three")))
    );
}

test "process/win: directory: runs the child elsewhere" {
    if (comptime !is_windows) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;
    _ = try vm.eval("(import (kaappi process) (scheme write))");
    // Windows honors `directory:` natively (CreateProcessW's
    // lpCurrentDirectory); since kaappi#2517 every POSIX build honors it
    // too — addchdir_np where its comptime link gate allows, the fork+exec
    // fallback's child-side chdir where it does not.
    try expectTrue(vm,
        \\(let ((p (spawn-process '("cmd.exe" "/c" "cd") 'directory: "C:\\Windows" 'stdout: 'pipe)))
        \\  (let ((line (read-line (process-stdout p))))
        \\    (process-wait p)
        \\    (string-ci=? line "C:\\Windows")))
    );
}

test "process/win: signal: folds into the exit code TerminateProcess stamps" {
    if (comptime !is_windows) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;
    _ = try vm.eval("(import (kaappi process))");
    // The documented mapping: 128 + n, the shell convention. Default SIGTERM
    // (15) -> 143; an explicit 'signal: 9 -> 137.
    try expectTrue(vm,
        \\(let ((p (spawn-process '("cmd.exe" "/c" "ping -n 30 127.0.0.1 > NUL"))))
        \\  (process-kill p)
        \\  (= 143 (process-wait p)))
    );
    try expectTrue(vm,
        \\(let ((p (spawn-process '("cmd.exe" "/c" "ping -n 30 127.0.0.1 > NUL"))))
        \\  (process-kill p 'signal: 9)
        \\  (= 137 (process-wait p)))
    );
    // 'signal: 0 keeps its POSIX meaning: probe, deliver nothing.
    try expectTrue(vm,
        \\(let ((p (spawn-process '("cmd.exe" "/c" "ping -n 30 127.0.0.1 > NUL"))))
        \\  (process-kill p 'signal: 0)
        \\  (let ((still-running (eq? #f (process-status p))))
        \\    (process-kill p 'signal: 9)
        \\    (process-wait p)
        \\    still-running))
    );
    // A kill after the reap is a quiet no-op, never a re-signal.
    try expectTrue(vm,
        \\(let ((p (spawn-process '("cmd.exe" "/c" "exit 0"))))
        \\  (process-wait p)
        \\  (process-kill p)
        \\  (= 0 (process-status p)))
    );
}

test "process/win: group: without new-group: is refused" {
    if (comptime !is_windows) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;
    _ = try vm.eval("(import (kaappi process))");
    try expectTrue(vm,
        \\(let ((p (spawn-process '("cmd.exe" "/c" "exit 0"))))
        \\  (process-wait p)
        \\  (eq? #f (process-group p)))
    );
    try expectTrue(vm,
        \\(let ((p (spawn-process '("cmd.exe" "/c" "ping -n 30 127.0.0.1 > NUL"))))
        \\  (let ((refused (guard (e (#t 'refused)) (process-kill p 'group: #t) 'accepted)))
        \\    (process-kill p 'signal: 9)
        \\    (process-wait p)
        \\    (eq? refused 'refused)))
    );
}

/// The live process ids in `job`. The SDK struct is variable-length; the
/// 64-slot tail here is far more than these tests create.
fn jobProcessCount(job: win.HANDLE) !u32 {
    var info: win.JobBasicProcessIdList = undefined;
    if (win.QueryInformationJobObject(job, win.JobObjectBasicProcessIdList, &info, @sizeOf(win.JobBasicProcessIdList), null) == 0)
        return error.QueryFailed;
    return info.assigned;
}

test "kaappi#2416: new-group: puts the child in a Job Object, and group: kills the whole tree" {
    if (comptime !is_windows) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;
    _ = try vm.eval("(import (kaappi process))");

    // `cmd /c ping ...` is a two-level tree by construction: cmd.exe is the
    // child, ping.exe the grandchild. A top-level define keeps the Process
    // rooted through vm.globals across the evals below.
    _ = try vm.eval("(define p (spawn-process '(\"cmd.exe\" \"/c\" \"ping -n 30 127.0.0.1 > NUL\") 'new-group: #t))");
    const proc_val = try vm.eval("p");
    const proc = types.toObject(proc_val).as(types.Process);

    // The group is real: `process-group` reports the pid (the POSIX group
    // leader's value), and the kernel agrees the child is in the job.
    try expectTrue(vm, "(= (process-group p) (process-pid p))");
    const job = proc.win_job orelse return error.TestExpectedJobObject;
    const child = proc.win_handle orelse return error.TestExpectedProcessHandle;
    var in_job: c_int = 0;
    try std.testing.expect(win.IsProcessInJob(child, job, &in_job) != 0);
    try std.testing.expect(in_job != 0);

    // The grandchild joins the job on its own — that automatic membership is
    // the entire reason a Job Object is used, since TerminateProcess would
    // reach only cmd.exe. Bounded poll: cmd.exe needs a moment to launch it.
    var waited: u32 = 0;
    while (waited < 5_000 and (try jobProcessCount(job)) < 2) : (waited += 25) {
        platform.sleepNs(25 * std.time.ns_per_ms);
    }
    try std.testing.expect((try jobProcessCount(job)) >= 2);

    // TerminateJobObject reaches every member. The child's own status is the
    // stamped 128+15; the tree assertion is that the job empties, which a
    // TerminateProcess-based kill could never achieve.
    try expectTrue(vm, "(begin (process-kill p 'group: #t) (= 143 (process-wait p)))");
    waited = 0;
    while (waited < 5_000 and (try jobProcessCount(job)) != 0) : (waited += 25) {
        platform.sleepNs(25 * std.time.ns_per_ms);
    }
    try std.testing.expectEqual(@as(u32, 0), try jobProcessCount(job));
}

test "kaappi#2416: process-wait parks instead of blocking, and timeout: expires to #f" {
    if (comptime !is_windows) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;
    _ = try vm.eval("(import (kaappi process))");

    // Python's contract: expiry returns #f with the child still alive.
    try expectTrue(vm,
        \\(let ((p (spawn-process '("cmd.exe" "/c" "ping -n 30 127.0.0.1 > NUL"))))
        \\  (let ((expired (process-wait p 'timeout: 0.05)))
        \\    (let ((alive (eq? #f (process-status p))))
        \\      (process-kill p 'signal: 9)
        \\      (and (eq? expired #f) alive (= 137 (process-wait p))))))
    );

    // The reactor path: the exit event (a signaled process HANDLE in the
    // WindowsEventBackend wait set) is what resolves this wait, and a
    // sibling fiber keeps running while it is parked.
    _ = try vm.eval("(import (kaappi fibers))");
    try expectTrue(vm,
        \\(let ((p (spawn-process '("cmd.exe" "/c" "ping -n 30 127.0.0.1 > NUL")))
        \\      (turns 0))
        \\  (spawn (lambda ()
        \\           (let loop ((i 0))
        \\             (set! turns (+ turns 1))
        \\             (if (< i 10)
        \\                 (begin (yield) (loop (+ i 1)))
        \\                 (process-kill p 'signal: 9)))))
        \\  (and (= 137 (process-wait p)) (>= turns 11)))
    );
}
