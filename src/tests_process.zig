//! Unit tests for `(kaappi process)` — KEP-0022 Phase 1 (POSIX).
//!
//! Every test spawns real children through /bin/sh (present on every hosted
//! POSIX CI target: macOS, Linux, the three BSDs), so these cover the actual
//! posix_spawnp path, not a mock. The suite skips on WASM and Windows, where
//! the library itself is unregistered.
//!
//! GC discipline inside the tests: any Value held in a Zig local across an
//! allocating call is rooted (pushRoot/popRoot), and loops that would be
//! quadratic under `-Dgc-stress` scale their iteration counts down via
//! build_options.gc_stress.

const std = @import("std");
const builtin = @import("builtin");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const build_options = @import("build_options");

const is_posix = switch (builtin.os.tag) {
    .windows, .wasi => false,
    else => true,
};

const shell = "/bin/sh";

/// expectEvalTrue, but on a caller-owned VM — for the tests that need
/// several evals to share one interaction environment (imports, defines).
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

test "process: cond-expand library gate is present on POSIX" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const s = try evalTo(ctx.vm, "(cond-expand ((library (kaappi process)) 'present) (else 'absent))");
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("present", s);
}

test "process: spawn, wait, status matrix" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // Normal exit 0 and a propagated nonzero code
    try expectTrue(vm, "(= 0 (process-wait (spawn-process '(\"true\"))))");
    try expectTrue(vm, "(= 7 (process-wait (spawn-process '(\"/bin/sh\" \"-c\" \"exit 7\"))))");

    // status is #f while running (a sleeper pinned open by its own stdin
    // pipe, so there is no exit race with the poll), the code after; waiting
    // a reaped process returns the stored status immediately. process-status
    // itself reaps non-blockingly, so it must never return #f for an
    // already-exited child — the sleeper is the only way to see #f.
    try expectTrue(vm,
        \\(let* ((p (spawn-process '("/bin/sh" "-c" "read x; exit 3") 'stdin: 'pipe))
        \\       (s1 (process-status p)))
        \\  (write-string "go\n" (process-stdin p))
        \\  (close-output-port (process-stdin p))
        \\  (let* ((w1 (process-wait p))
        \\         (s2 (process-status p))
        \\         (w2 (process-wait p)))
        \\    (and (eq? s1 #f) (= w1 3) (= s2 3) (= w2 3))))
    );

    // process-status reaps on its own: after the child is certainly gone,
    // polling (with no intervening process-wait) reports the code.
    try expectTrue(vm,
        \\(let ((p (spawn-process '("/bin/sh" "-c" "exit 4"))))
        \\  (let loop ((n 0))
        \\    (let ((st (process-status p)))
        \\      (cond ((and (integer? st) (= st 4)) #t)
        \\            ((> n 5000000) 'timeout)
        \\            (else (loop (+ n 1)))))))
    );

    // Signaled death: (signaled . n). $$ is sh's own pid.
    try expectTrue(vm,
        \\(let* ((p (spawn-process '("/bin/sh" "-c" "kill -9 $$")))
        \\       (st (process-wait p)))
        \\  (and (pair? st) (eq? (car st) 'signaled) (= (cdr st) 9)))
    );

    // process-kill default is SIGTERM (15)
    try expectTrue(vm,
        \\(let* ((p (spawn-process '("/bin/sleep" "30")))
        \\       (st (and (process-kill p) (process-wait p))))
        \\  (and (pair? st) (eq? (car st) 'signaled) (= (cdr st) 15)))
    );
}

test "process: kill after reap is a no-op, never re-signals the pid" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // A second kill after reap must quietly do nothing — the pid may be
    // reused, so signaling it again could hit an unrelated process.
    try expectTrue(vm,
        \\(let* ((p (spawn-process '("true")))
        \\       (st (process-wait p)))
        \\  (and (= st 0) (process-kill p) (process-kill p 'signal: 9) #t))
    );
}

test "process: predicates and accessors" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    try expectTrue(vm, "(process? (spawn-process '(\"true\")))");
    try expectTrue(vm, "(not (process? 42))");
    try expectTrue(vm, "(not (process? (open-input-string \"x\")))");

    // pid is a positive integer; group is #f without new-group:
    try expectTrue(vm,
        \\(let ((p (spawn-process '("true"))))
        \\  (and (integer? (process-pid p)) (> (process-pid p) 0)
        \\       (eq? (process-group p) #f)
        \\       (= (process-wait p) 0)))
    );

    // new-group: makes the child its own leader: pgid == pid
    try expectTrue(vm,
        \\(let ((p (spawn-process '("true") 'new-group: #t)))
        \\  (and (= (process-group p) (process-pid p))
        \\       (= (process-wait p) 0)))
    );

    // Accessors: a port for the 'pipe spec, #f for every other spec
    try expectTrue(vm,
        \\(let ((p (spawn-process '("true") 'stdout: 'pipe)))
        \\  (and (port? (process-stdout p))
        \\       (eq? (process-stdin p) #f)
        \\       (eq? (process-stderr p) #f)
        \\       (= (process-wait p) 0)))
    );

    // Type errors on non-process arguments
    try std.testing.expectError(vm_mod.VMError.TypeError, vm.eval("(process-pid 3)"));
    try std.testing.expectError(vm_mod.VMError.TypeError, vm.eval("(process-stdout 'sym)"));
    try std.testing.expectError(vm_mod.VMError.TypeError, vm.eval("(process-wait #f)"));
    try std.testing.expectError(vm_mod.VMError.TypeError, vm.eval("(process-kill \"x\")"));
}

test "process: stdin/stdout pipe round trip" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // cat echoes stdin back: write, half-close (EOF for cat), read, wait.
    const s = try evalTo(vm,
        \\(let* ((p (spawn-process '("/bin/cat") 'stdin: 'pipe 'stdout: 'pipe))
        \\       (in (process-stdin p))
        \\       (out (process-stdout p)))
        \\  (write-string "round-trip" in)
        \\  (flush-output-port in)
        \\  (close-output-port in)
        \\  (let ((line (read-line out)))
        \\    (list line (process-wait p))))
    );
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(\"round-trip\" 0)", s);
}

test "process: redirection matrix" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;
    _ = try vm.eval("(import (scheme file))");

    // 'null: the child's stdout goes to the null device. Two 'stdout:
    // options are given and the last one wins, so the earlier 'pipe is
    // discarded, no pipe is created, and the accessor is #f.
    try expectTrue(vm,
        \\(let* ((p (spawn-process '("/bin/echo" "discarded") 'stdout: 'pipe 'stdout: 'null)))
        \\  (and (eq? (process-stdout p) #f)
        \\       (= (process-wait p) 0)))
    );

    // A caller-supplied fd port as stdout: the child writes INTO the port's
    // descriptor; the accessor is #f and no pipe was created.
    try expectTrue(vm,
        \\(let* ((path "/tmp/kaappi-process-test.out")
        \\       (sink (open-output-file path))
        \\       (p (spawn-process '("/bin/echo" "to-file") 'stdout: sink)))
        \\  (and (eq? (process-stdout p) #f)
        \\       (= (process-wait p) 0)
        \\       (begin (close-port sink) #t)))
    );
    const content = try evalTo(vm,
        \\(call-with-input-file "/tmp/kaappi-process-test.out" read-line)
    );
    defer std.testing.allocator.free(content);
    try std.testing.expectEqualStrings("\"to-file\"", content);

    // An fd port as stdin: the child reads FROM the file descriptor
    try expectTrue(vm,
        \\(let* ((sink (open-output-file "/tmp/kaappi-process-test.in")))
        \\  (write-string "from-file" sink)
        \\  (close-port sink)
        \\  (let* ((src (open-input-file "/tmp/kaappi-process-test.in"))
        \\         (p (spawn-process '("/bin/cat") 'stdin: src 'stdout: 'pipe))
        \\         (line (read-line (process-stdout p))))
        \\    (and (string? line) (= (process-wait p) 0))))
    );

    // stderr 'stdout merges the streams: both lines land on the stdout
    // pipe, and the stderr accessor is #f. sh sequences the two echoes.
    const merged = try evalTo(vm,
        \\(let* ((p (spawn-process '("/bin/sh" "-c" "echo out; echo err 1>&2")
        \\                            'stdout: 'pipe 'stderr: 'stdout))
        \\       (l1 (read-line (process-stdout p)))
        \\       (l2 (read-line (process-stdout p))))
        \\  (list l1 l2 (eq? (process-stderr p) #f) (process-wait p)))
    );
    defer std.testing.allocator.free(merged);
    try std.testing.expectEqualStrings("(\"out\" \"err\" #t 0)", merged);

    // 'inherit (the default) keeps the parent's own stdio: #f everywhere
    try expectTrue(vm,
        \\(let ((p (spawn-process '("true"))))
        \\  (and (eq? (process-stdin p) #f)
        \\       (eq? (process-stdout p) #f)
        \\       (eq? (process-stderr p) #f)
        \\       (= (process-wait p) 0)))
    );
}

test "process: env replaces wholesale" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    const s = try evalTo(vm,
        \\(let* ((p (spawn-process '("/bin/sh" "-c" "echo $KAPVAR1:$KAPVAR2")
        \\                         'stdout: 'pipe
        \\                         'env: '(("KAPVAR1" . "one") ("KAPVAR2" . "two")))))
        \\  (read-line (process-stdout p)))
    );
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("\"one:two\"", s);

    // The empty list means an EMPTY environment (not "inherit"): HOME is
    // gone, so the default expansion prints "unset" rather than the
    // inherited home directory.
    const empty_env = try evalTo(vm,
        \\(let* ((p (spawn-process '("/bin/sh" "-c" "echo ${HOME:-unset}")
        \\                         'stdout: 'pipe 'env: '())))
        \\  (read-line (process-stdout p)))
    );
    defer std.testing.allocator.free(empty_env);
    try std.testing.expectEqualStrings("\"unset\"", empty_env);

    // Malformed entries are type errors
    try std.testing.expectError(vm_mod.VMError.TypeError, vm.eval(
        "(spawn-process '(\"true\") 'env: '((\"OK\" . 1)))",
    ));
}

test "process: process-environment returns a (name . value) alist" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // Every entry is a pair of strings, PATH is present, and the shape
    // feeds straight back into env: (the copy-and-extend idiom).
    try expectTrue(vm,
        \\(let* ((env (process-environment))
        \\       (all-pairs (let loop ((rest env) (ok #t))
        \\                    (cond ((null? rest) ok)
        \\                          ((and (pair? (car rest))
        \\                                (string? (car (car rest)))
        \\                                (string? (cdr (car rest))))
        \\                           (loop (cdr rest) ok))
        \\                          (else #f)))))
        \\  (and all-pairs (pair? (assoc "PATH" env))))
    );
}

test "process: fd hygiene — the child inherits only the three stdio slots" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // Close-by-default means the strong assertion holds even inside the
    // unit-test binary, whatever descriptors the harness (or kcov) holds:
    // CLOEXEC fds die at exec, non-CLOEXEC strays are closed by the
    // spawner's explicit close actions (macOS: CLOEXEC_DEFAULT). The child
    // probes openness by DUPLICATING each fd (`: <&N` in a subshell) — a
    // stat of /dev/fd/N would false-positive on the BSDs, where those
    // entries are static device nodes that exist whether or not the fd is
    // open.
    try expectTrue(vm,
        \\(let* ((p (spawn-process '("/bin/sh" "-c" "i=3; while [ $i -le 32 ]; do if (eval \": <&$i\") 2>/dev/null; then echo $i; fi; i=$((i+1)); done")
        \\                            'stdout: 'pipe))
        \\       (out (process-stdout p)))
        \\  (let loop ((acc '()))
        \\    (let ((line (read-line out)))
        \\      (if (eof-object? line)
        \\          (begin (process-wait p) (null? acc))
        \\          (loop (cons line acc))))))
    );
}

test "process: fd hygiene — a deliberately inheritable fd is closed for the child" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // The kaappi#2414 review repro: an fd Kaappi *inherited* (here: opened
    // via raw libc with no O_CLOEXEC, standing in for `kaappi 9</dev/null`)
    // has no CLOEXEC flag, so only the spawner's close-by-default pass can
    // keep it out of the child. First prove the probe discriminates — the
    // fd IS open and non-CLOEXEC in the parent — then spawn a child that
    // must find it closed (dup of it fails -> exit 1).
    const platform = @import("platform.zig");
    const fd = std.c.open("/dev/null", .{ .ACCMODE = .RDONLY }, @as(c_uint, 0));
    try std.testing.expect(fd >= 3);
    defer _ = platform.close(fd);
    const flags = platform.getFdFlags(fd);
    try std.testing.expect(flags >= 0);
    try std.testing.expect((flags & 1) == 0); // no FD_CLOEXEC: genuinely inheritable

    const source = try std.fmt.allocPrint(std.testing.allocator,
        \\(let ((p (spawn-process '("/bin/sh" "-c" "if (eval \": <&{d}\") 2>/dev/null; then exit 1; else exit 0; fi"))))
        \\  (= (process-wait p) 0))
    , .{fd});
    defer std.testing.allocator.free(source);
    try expectTrue(vm, source);
}

test "process: gc-stress rooting of Process and its ports" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // Under -Dgc-stress every allocation collects, so a spawn loop stresses
    // the Process/port rooting discipline hard. Iterations scale down; the
    // assertion is behavioral (exit status + output), so a mis-rooted port
    // would surface as a wrong read or a crash.
    const n: usize = if (build_options.gc_stress) 20 else 200;
    const source = try std.fmt.allocPrint(std.testing.allocator,
        \\(let loop ((i {d}) (acc 0))
        \\  (if (= i 0)
        \\      acc
        \\      (let* ((p (spawn-process '("{s}" "-c" "echo x") 'stdout: 'pipe))
        \\             (line (read-line (process-stdout p)))
        \\             (st (process-wait p)))
        \\        (loop (- i 1) (+ acc (if (and (string? line) (= st 0)) 1 0))))))
    , .{ n, shell });
    defer std.testing.allocator.free(source);
    const result = try vm.eval(source);
    try std.testing.expectEqual(@as(i64, @intCast(n)), types.toFixnum(result));
}

test "process: spawn failure raises a catchable file error" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // ENOENT rides the condition; file-error? sees it.
    try expectTrue(vm,
        \\(guard (e ((file-error? e) #t) (else 'wrong-kind))
        \\  (spawn-process '("/nonexistent/kaappi-test-program")))
    );

    // argv must be a non-empty list of strings: '() fails the pair check
    // (TypeError), a non-string element the element check.
    try std.testing.expectError(vm_mod.VMError.TypeError, vm.eval("(spawn-process '())"));
    try std.testing.expectError(vm_mod.VMError.TypeError, vm.eval("(spawn-process '(\"/bin/echo\" 42))"));

    // 'stdout is a stderr-only spec
    try std.testing.expectError(vm_mod.VMError.InvalidArgument, vm.eval("(spawn-process '(\"true\") 'stdout: 'stdout)"));
}

test "process: printer shows pid and state without erroring" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // #<process PID running> while live, #<process PID exited N> reaped:
    // assert the shape via string prefixes/suffixes, not the pid itself.
    const s = try evalTo(vm,
        \\(let* ((p (spawn-process '("true")))
        \\       (sp1 (open-output-string)))
        \\  (write p sp1)
        \\  (let ((running (get-output-string sp1)))
        \\    (process-wait p)
        \\    (let ((sp2 (open-output-string)))
        \\      (write p sp2)
        \\      (list (string-prefix? "#<process " running)
        \\            (string-suffix? "running>" running)
        \\            (string-prefix? "#<process " (get-output-string sp2))
        \\            (string-suffix? "exited 0>" (get-output-string sp2))))))
    );
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(#t #t #t #t)", s);
}

test "process: cyclic argv and env lists are errors, not hangs" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // kaappi#2414 review: types.listLength-style walks spin forever on a
    // legal cyclic pair, uninterruptibly, inside the native primitive. Both
    // list surfaces must reject the cycle instead.
    try std.testing.expectError(vm_mod.VMError.InvalidArgument, vm.eval(
        \\(let ((x (list "true"))) (set-cdr! x x) (spawn-process x))
    ));
    try std.testing.expectError(vm_mod.VMError.InvalidArgument, vm.eval(
        \\(let ((e (list (cons "A" "b")))) (set-cdr! e e)
        \\  (spawn-process '("true") 'env: e))
    ));
}

test "process: embedded NUL bytes are rejected on every C-string surface" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // kaappi#2414 review: dupeZ would silently truncate at the interior NUL
    // — the child would receive (or exec!) something other than what the
    // program supplied. \x0; is R7RS string-escape syntax for U+0000.
    try std.testing.expectError(vm_mod.VMError.InvalidArgument, vm.eval(
        "(spawn-process '(\"/bin/echo\" \"a\\x0;b\"))",
    ));
    try std.testing.expectError(vm_mod.VMError.InvalidArgument, vm.eval(
        "(spawn-process '(\"true\") 'env: '((\"A\\x0;B\" . \"v\")))",
    ));
    try std.testing.expectError(vm_mod.VMError.InvalidArgument, vm.eval(
        "(spawn-process '(\"true\") 'env: '((\"A\" . \"v\\x0;w\")))",
    ));
    try std.testing.expectError(vm_mod.VMError.InvalidArgument, vm.eval(
        "(spawn-process '(\"true\") 'directory: \"/tm\\x0;p\")",
    ));
    // Environment-name shape: empty and '='-carrying names could
    // reinterpret the entry.
    try std.testing.expectError(vm_mod.VMError.InvalidArgument, vm.eval(
        "(spawn-process '(\"true\") 'env: '((\"\" . \"v\")))",
    ));
    try std.testing.expectError(vm_mod.VMError.InvalidArgument, vm.eval(
        "(spawn-process '(\"true\") 'env: '((\"A=B\" . \"v\")))",
    ));
}

test "process: writing to a dead child's stdin raises a catchable EPIPE error" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // kaappi#2414 review: with SIGPIPE ignored process-wide, the KEP-0005
    // contract is that the EPIPE surfaces as an ordinary catchable
    // file-error on the explicit write/flush — not a silently dropped
    // buffer reporting success.
    try expectTrue(vm,
        \\(let ((p (spawn-process '("true") 'stdin: 'pipe)))
        \\  (process-wait p)
        \\  (guard (e ((file-error? e) #t) (else 'wrong-kind))
        \\    (write-string "into the void" (process-stdin p))
        \\    (flush-output-port (process-stdin p))
        \\    'not-raised))
    );
}

test "process: the child's SIGPIPE disposition is reset to default" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // kaappi#2414 review: the parent runs with SIGPIPE ignored (VM.init) and
    // ignored dispositions survive exec, so without POSIX_SPAWN_SETSIGDEF a
    // child would silently inherit the runtime's policy. A self-SIGPIPE must
    // therefore kill it: (signaled . 13). This also pins the SETSIGDEF flag
    // *value*, which differs between the BSDs (0x10) and everyone else
    // (0x04) — the wrong constant makes this test report a normal exit.
    try expectTrue(vm,
        \\(let* ((p (spawn-process '("/bin/sh" "-c" "kill -PIPE $$; exit 42")))
        \\       (st (process-wait p)))
        \\  (and (pair? st) (eq? (car st) 'signaled) (= (cdr st) 13)))
    );
}

test "process: pipe creation reclaims descriptors via GC on exhaustion (#1993)" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // A legal program may abandon process handles faster than the GC's
    // allocation-count threshold trips; their parent-end pipe fds are then
    // only released at a collection. spawn's pipe(2) must therefore mirror
    // open(2)'s EMFILE recovery (kaappi#1993/#2324): collect and retry once.
    // Deterministic version of what the OpenBSD CI leg's low `ulimit -n`
    // caught in the spawn-loop rooting test: lower the soft NOFILE limit to
    // a small headroom above the fds already open, then run more pipe
    // spawns than the headroom allows — without the retry, spawn raises
    // "cannot create stdout pipe" partway through.
    const platform = @import("platform.zig");
    var highest: std.posix.rlim_t = 0;
    var fd: platform.fd_t = 0;
    while (fd < 1024) : (fd += 1) {
        if (platform.getFdFlags(fd) >= 0) highest = @intCast(fd);
    }
    const old = std.posix.getrlimit(.NOFILE) catch return error.SkipZigTest;
    const lowered: std.posix.rlim_t = highest + 32;
    if (lowered >= old.cur) return error.SkipZigTest; // already that low; nothing to prove
    std.posix.setrlimit(.NOFILE, .{ .cur = lowered, .max = old.max }) catch return error.SkipZigTest;
    defer std.posix.setrlimit(.NOFILE, old) catch {};

    // Three pipes per spawn and no reads keep the fd burn rate (3/iteration)
    // far ahead of the allocation rate, so the soft limit is reached well
    // before the GC's own allocation-count threshold could trip a natural
    // collection — without the retry this loop deterministically raises
    // "cannot create ... pipe" partway through (verified by mutation:
    // disabling the retry fails it).
    const n: usize = 20;
    const source = try std.fmt.allocPrint(std.testing.allocator,
        \\(let loop ((i {d}) (acc 0))
        \\  (if (= i 0)
        \\      acc
        \\      (let* ((p (spawn-process '("true") 'stdin: 'pipe 'stdout: 'pipe 'stderr: 'pipe))
        \\             (st (process-wait p)))
        \\        (loop (- i 1) (+ acc (if (= st 0) 1 0))))))
    , .{n});
    defer std.testing.allocator.free(source);
    const result = vm.eval(source) catch |e| {
        std.debug.print("spawn under lowered RLIMIT_NOFILE failed: {s}\n", .{vm.last_error_detail[0..vm.last_error_detail_len]});
        return e;
    };
    try std.testing.expectEqual(@as(i64, @intCast(n)), types.toFixnum(result));
}

test "process: the sweep stores status without an explicit wait" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // p1 exits on its own; p2's spawn runs the WNOHANG sweep first, which
    // may already reap p1 and store its status. Waiting p1 afterwards must
    // return 5 without blocking, whichever way it went.
    try expectTrue(vm,
        \\(begin
        \\  (define p1 (spawn-process '("/bin/sh" "-c" "exit 5")))
        \\  (define p2 (spawn-process '("/bin/sh" "-c" "exit 0")))
        \\  (= (process-wait p2) 0))
    );
    try expectTrue(vm, "(= (process-wait p1) 5)");
}
