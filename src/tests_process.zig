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
const fiber_mod = @import("fiber.zig");

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
    // open. Two probe-artifact guards: stderr is 'null rather than a
    // per-command `2>/dev/null`, and stdin is closed up front (`exec
    // 0<&-`) — bash implements a per-command redirection by parking the
    // real descriptor at fd 10+ for the command's duration, so probing
    // `<&10` while stdin is open would detect the shell's own save of it.
    try expectTrue(vm,
        \\(let* ((p (spawn-process '("/bin/sh" "-c" "exec 0<&-; i=3; while [ $i -le 32 ]; do if (eval \": <&$i\"); then echo $i; fi; i=$((i+1)); done")
        \\                            'stdout: 'pipe 'stderr: 'null))
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

test "process: an input redirect port's read-ahead is given back to the child" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // Reading one character pulls a whole chunk into the port's software
    // read-ahead, leaving the kernel offset far past the logical position.
    // A child handed the raw fd then starts at the kernel offset, silently
    // skipping everything buffered-but-unconsumed (kaappi#2442 review).
    // The fd is seekable, so the spawner must rewind it: after the parent
    // reads "A", the child must see "B" first.
    _ = try vm.eval("(import (scheme file))");
    try expectTrue(vm,
        \\(let ((sink (open-output-file "/tmp/kaappi-readahead-2442.txt")))
        \\  (write-string "AB" sink)
        \\  (write-string (make-string 5000 #\x) sink)
        \\  (close-port sink)
        \\  (let* ((src (open-input-file "/tmp/kaappi-readahead-2442.txt"))
        \\         (first (read-char src))
        \\         (p (spawn-process '("/bin/sh" "-c" "dd bs=1 count=1 2>/dev/null")
        \\                           'stdin: src 'stdout: 'pipe))
        \\         (child-first (read-line (process-stdout p)))
        \\         (st (process-wait p)))
        \\    (close-port src)
        \\    (and (char=? first #\A) (equal? child-first "B") (= st 0))))
    );
}

test "process: collecting an abandoned pipe port never blocks the sweep" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // kaappi#2442 review: the sweep's best-effort flush used a BLOCKING
    // write, and a fresh process pipe stays in blocking mode — so dropping
    // a port with pending buffered output against a child that never reads
    // wedged the collector. Fill the pipe near capacity (flushed), buffer
    // more below the high-water mark (unflushed), abandon everything, and
    // require the full collection to come back promptly.
    // A 4096-byte flushed prefill is at or below one pipe page everywhere
    // (Linux under the per-user pipe-page soft limit may hand out 2-page,
    // 8 KiB pipes — kaappi#2442 review), so the explicit flush can never
    // block; the 68000-byte unflushed tail then exceeds even a 64 KiB
    // pipe's remaining capacity, so the abandoned buffer is guaranteed
    // larger than what any drain could sink.
    try expectTrue(vm,
        \\(let* ((p (spawn-process '("/bin/sleep" "3") 'stdin: 'pipe))
        \\       (in (process-stdin p)))
        \\  (write-string (make-string 4096 #\x) in)
        \\  (flush-output-port in)
        \\  (write-string (make-string 68000 #\y) in)
        \\  #t)
    );
    const platform = @import("platform.zig");
    const start_ns = platform.monotonicNs();
    ctx.gc.collectFull();
    const elapsed_ns = platform.monotonicNs() - start_ns;
    // The child sleeps 3 s and never reads; a blocking flush would sit the
    // whole 3 s (or forever against a longer-lived child). Generous bound
    // for slow CI, still far under the sleep.
    try std.testing.expect(elapsed_ns < 2 * std.time.ns_per_s);
}

test "process: spawn failure paths leak no descriptors (OOM sweep)" {
    if (comptime !is_posix) return error.SkipZigTest;
    if (build_options.gc_stress) return error.SkipZigTest; // countdown + stress interact combinatorially
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;
    const platform = @import("platform.zig");
    const memory = @import("memory.zig");
    const gc = memory.gc_instance.?;

    // Drive an allocation failure at every GC-allocation point of a
    // pipe-heavy spawn (kaappi#2442 review: an OOM between the spawn and
    // the last port allocation used to leak the parent pipe ends). The
    // invariant: however the spawn dies, no descriptor survives once the
    // garbage ports are collected.
    const countFds = struct {
        fn count() usize {
            var n: usize = 0;
            var fd: platform.fd_t = 0;
            while (fd < 256) : (fd += 1) {
                if (platform.getFdFlags(fd) >= 0) n += 1;
            }
            return n;
        }
    }.count;

    // Compile the spawn once; the sweep then re-evals only a tiny call, so
    // nearly all of each iteration's countdown budget lands inside the
    // spawn path itself — denser failure-point coverage AND an order of
    // magnitude less work per iteration, which is what keeps the emulated
    // QEMU CI legs (riscv64/s390x/ppc64le) inside their job budget.
    // A LONG-LIVED child (self-killed on the success path), not `true`:
    // with a child that exits instantly, a failure path that abandons a
    // still-running child is invisible — the child is gone before any
    // assertion looks (kaappi#2442 review). With `sleep`, an abandoned
    // child survives to the post-sweep checks below.
    _ = try vm.eval(
        \\(define (kaappi-oom-spawn-2442)
        \\  (let ((p (spawn-process '("/bin/sleep" "30") 'stdin: 'pipe 'stdout: 'pipe 'stderr: 'pipe)))
        \\    (process-kill p 'signal: 9) (process-wait p) #t))
    );
    const src = "(kaappi-oom-spawn-2442)";
    // Baseline: one full run so lazily-created infrastructure (reactor fds,
    // caches) exists before the count is taken — armed with a huge countdown
    // whose remainder measures the call's TOTAL GC-allocation count, so the
    // sweep below covers exactly the failure window and not one iteration
    // more (every iteration past it is a full successful spawn that asserts
    // nothing and, under the QEMU CI legs, costs real wall clock).
    gc.oom_countdown = 100_000;
    _ = try vm.eval(src);
    const total: u32 = @intCast(100_000 - (gc.oom_countdown orelse 0));
    gc.oom_countdown = null;
    // Sanity: a collapsed measurement (counting broken, or the call never
    // reaching the spawn) would silently shrink the sweep to nothing. The
    // real window is small by design — the compiled call's GC allocations
    // are essentially just the Process, its ports, and the status decode —
    // so the floor only guards against zero-shaped breakage.
    try std.testing.expect(total >= 4);
    gc.collectFull();
    const before = countFds();

    const upper = @min(total + 8, 250);
    var n: u32 = 0;
    while (n < upper) : (n += 1) {
        gc.oom_countdown = n;
        _ = vm.eval(src) catch {};
        gc.oom_countdown = null;
    }
    // Registry check BEFORE collectFull (kaappi#2442 review: a collection
    // would drop an unreachable Process entry even with its child still
    // live, hiding exactly the leak this guards). At this point every
    // legitimate flow has emptied it — successful iterations reaped via
    // process-wait, spawnImpl-internal failures via the errdefer's blocking
    // kill+reap, caller-path SIGKILLed stragglers via the WNOHANG sweep —
    // so a survivor is an abandoned child.
    sweepUnreapedForTest(gc);
    try std.testing.expectEqual(@as(usize, 0), gc.unreaped_processes.items.len);

    gc.collectFull();
    const after = countFds();
    try std.testing.expectEqual(before, after);

    // And the OS agrees: within a bounded window, waitpid(-1) must reach
    // -1/ECHILD — no child of ours left, living or zombie. A persistent 0
    // is a LIVE abandoned child (the mutation shape: spawnImpl failing
    // without killing) and fails the test; positive returns are killed
    // stragglers mid-death on a slow box, reaped and retried. The caller's
    // own kill runs before its first post-spawn allocation, so a countdown
    // cannot abandon an un-killed child by the caller's hand here.
    var reached_echild = false;
    var tries: u32 = 0;
    while (tries < 500) : (tries += 1) {
        var zst: c_int = 0;
        const r = platform.waitPid(-1, &zst, platform.WNOHANG);
        if (r < 0) {
            reached_echild = true;
            break;
        }
        if (r == 0) platform.sleepNs(10 * std.time.ns_per_ms);
    }
    try std.testing.expect(reached_echild);
}

/// Reap any stragglers the OOM sweep left (children whose Process was
/// collected mid-construction are reaped by freeObject; ones that survived
/// as unreaped registry entries get the ordinary sweep).
fn sweepUnreapedForTest(gc: *@import("memory.zig").GC) void {
    const platform = @import("platform.zig");
    var i: usize = 0;
    while (i < gc.unreaped_processes.items.len) {
        const proc = gc.unreaped_processes.items[i];
        var st: c_int = 0;
        if (platform.waitPid(proc.pid, &st, platform.WNOHANG) == proc.pid) {
            proc.status = @bitCast(st);
            _ = gc.unreaped_processes.swapRemove(i);
        } else {
            i += 1;
        }
    }
}

test "process: close-by-default reaches descriptors above 65536" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;
    const platform = @import("platform.zig");

    // kaappi#2442 review: the scan's old 65536 cap silently exempted valid
    // high descriptors on systems with a six-figure RLIMIT_NOFILE (FreeBSD's
    // reference VM runs at 117153). Park an inheritable fd at 70000 and
    // require the child to find it closed. Skipped where the limit forbids
    // an fd that high.
    const low = std.c.open("/dev/null", .{ .ACCMODE = .RDONLY }, @as(c_uint, 0));
    if (low < 0) return error.SkipZigTest;
    defer _ = platform.close(low);
    if (platform.dup2(low, 70000) < 0) return error.SkipZigTest;
    defer _ = platform.close(70000);
    const flags = platform.getFdFlags(70000);
    try std.testing.expect(flags >= 0);
    try std.testing.expect((flags & 1) == 0); // inheritable

    // The probe cannot be a shell `<&70000` dup: FreeBSD's /bin/sh rejects
    // the multi-digit operand outright, so it reports every high fd closed
    // and the test would stay green with addclosefrom_np removed
    // (kaappi#2442 review). Instead, ask the OS's own fd inventory — the
    // per-OS spelling below is exact on the platforms this test can run on
    // (the BSDs without such an inventory have default limits far below
    // 70000 and skip at the dup2 above). Each probe is validated by an
    // fd-2 control that must report OPEN before the 70000 verdict counts.
    const probe = struct {
        fn cmd(comptime fd_str: []const u8, comptime open_exit: []const u8, comptime closed_exit: []const u8) []const u8 {
            const check = switch (builtin.os.tag) {
                .macos, .ios => "[ -e /dev/fd/" ++ fd_str ++ " ]",
                .linux => "[ -e /proc/self/fd/" ++ fd_str ++ " ]",
                .freebsd => "procstat -f $$ 2>/dev/null | awk '$3 == " ++ fd_str ++ "' | grep -q .",
                else => "",
            };
            return "(let ((p (spawn-process (list \"/bin/sh\" \"-c\" \"if " ++ check ++
                "; then exit " ++ open_exit ++ "; else exit " ++ closed_exit ++
                "; fi\")))) (= (process-wait p) 0))";
        }
    };
    if (comptime (builtin.os.tag != .macos and builtin.os.tag != .ios and
        builtin.os.tag != .linux and builtin.os.tag != .freebsd)) return error.SkipZigTest;
    try expectTrue(vm, comptime probe.cmd("2", "0", "1")); // control: OPEN detected
    try expectTrue(vm, comptime probe.cmd("70000", "1", "0")); // must be CLOSED
}

test "process: a bidirectional redirect port reconciles read-ahead before its output" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;
    const platform = @import("platform.zig");

    // kaappi#2442 review: draining buffered output BEFORE rewinding the
    // input read-ahead lands the parent's writes at the stale kernel offset
    // (end of the read-ahead chunk) instead of the logical position. With
    // an O_RDWR file holding ABCDEF: read A (pulling BCDEF into
    // read-ahead), buffer X, hand the port to a child — the file must
    // become AXCDEF (X at the logical position) and the child must read
    // from position 2 (C), not from wherever the raw offset drifted.
    const path = "/tmp/kaappi-bidi-2442.txt";
    {
        const f = std.c.open(path, .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true }, @as(c_uint, 0o644));
        try std.testing.expect(f >= 0);
        _ = platform.write(f, "ABCDEF", 6);
        _ = platform.close(f);
    }
    // No defer close: fd->port takes ownership of `rw`, and the collected
    // port's sweep closes it — a second close here could hit a reused fd.
    const rw = std.c.open(path, .{ .ACCMODE = .RDWR }, @as(c_uint, 0));
    try std.testing.expect(rw >= 0);

    const source = try std.fmt.allocPrint(std.testing.allocator,
        \\(let* ((bp (fd->port {d}))
        \\       (first (read-char bp)))
        \\  (write-string "X" bp)
        \\  (let* ((p (spawn-process '("/bin/sh" "-c" "dd bs=1 count=1 2>/dev/null")
        \\                           'stdin: bp 'stdout: 'pipe))
        \\         (child-first (read-line (process-stdout p)))
        \\         (st (process-wait p)))
        \\    (and (char=? first #\A) (equal? child-first "C") (= st 0))))
    , .{rw});
    defer std.testing.allocator.free(source);
    _ = try vm.eval("(import (kaappi ffi))");
    try expectTrue(vm, source);

    var buf: [8]u8 = undefined;
    const chk = std.c.open(path, .{ .ACCMODE = .RDONLY }, @as(c_uint, 0));
    try std.testing.expect(chk >= 0);
    defer _ = platform.close(chk);
    const nread = platform.read(chk, &buf, 8);
    try std.testing.expectEqual(@as(isize, 6), nread);
    try std.testing.expectEqualStrings("AXCDEF", buf[0..6]);
}

test "process: the sweep's teardown drain leaves dup aliases blocking" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;
    const platform = @import("platform.zig");

    // kaappi#2442 review: O_NONBLOCK lives on the shared open-file
    // description, so the sweep's teardown flip must be undone before the
    // close or every dup/dup2 alias of the descriptor comes out of a
    // collection permanently non-blocking.
    var fds: [2]platform.fd_t = .{ -1, -1 };
    try std.testing.expectEqual(@as(c_int, 0), platform.pipe(&fds));
    defer {
        if (fds[0] >= 0) _ = platform.close(fds[0]);
    }
    const alias = platform.fcntlDupCloexec(fds[1]);
    try std.testing.expect(alias >= 0);
    defer _ = platform.close(alias);

    const nonblock: c_int = @intCast(@as(u32, @bitCast(std.posix.O{ .NONBLOCK = true })));
    const flags_before = std.c.fcntl(alias, std.posix.F.GETFL, @as(c_int, 0));
    try std.testing.expect(flags_before >= 0);
    try std.testing.expect((flags_before & nonblock) == 0);

    // Wrap the write end in a port, buffer output without flushing, drop
    // the port, and collect: the sweep drains (flipping the description
    // non-blocking for the drain) and closes the port's fd.
    const source = try std.fmt.allocPrint(std.testing.allocator,
        \\(let ((p (fd->port {d}))) (write-string "x" p) #t)
    , .{fds[1]});
    defer std.testing.allocator.free(source);
    _ = try vm.eval("(import (kaappi ffi))");
    try expectTrue(vm, source);
    fds[1] = -1; // the collected port owns and closes it
    ctx.gc.collectFull();

    const flags_after = std.c.fcntl(alias, std.posix.F.GETFL, @as(c_int, 0));
    try std.testing.expect(flags_after >= 0);
    try std.testing.expect((flags_after & nonblock) == 0);
}

test "process: explicit stdio self-redirect needs no spare descriptor" {
    if (comptime !is_posix) return error.SkipZigTest;
    if (build_options.gc_stress) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;
    const platform = @import("platform.zig");

    // kaappi#2442 review: `stdout: (current-output-port)` is explicit
    // inheritance — source fd == destination slot — and must not require a
    // staging duplicate, or it fails under a full fd table where the plain
    // default succeeds. Starve the PARENT's table by lowering the soft
    // limit to a still-comfortable 256 and filling it with CLOEXEC
    // /dev/null descriptors until EMFILE. Lowering alone to "zero free"
    // would also starve the CHILD's exec — dyld aborts when it cannot open
    // the image, measured as (signaled . 6) — but at 256 the child is
    // unaffected: its exec closes every CLOEXEC fill fd first, and its own
    // opens land at small numbers far below the limit.
    const old = std.posix.getrlimit(.NOFILE) catch return error.SkipZigTest;
    if (old.cur > 256) {
        std.posix.setrlimit(.NOFILE, .{ .cur = 256, .max = old.max }) catch return error.SkipZigTest;
    }
    defer std.posix.setrlimit(.NOFILE, old) catch {};
    var fill: std.ArrayList(platform.fd_t) = .empty;
    defer {
        for (fill.items) |f| _ = platform.close(f);
        fill.deinit(std.testing.allocator);
    }
    var filled_up = false;
    while (fill.items.len < 65536) {
        const f = std.c.open("/dev/null", .{ .ACCMODE = .RDONLY, .CLOEXEC = true }, @as(c_uint, 0));
        if (f < 0) {
            filled_up = true;
            break;
        }
        fill.append(std.testing.allocator, f) catch {
            _ = platform.close(f);
            break;
        };
    }
    if (!filled_up) return error.SkipZigTest; // could not exhaust the table

    // Control 1: a staged duplicate is impossible right now.
    try std.testing.expect(platform.dupCloexecAtLeast(1, 3) < 0);

    // Control 2: a PLAIN spawn must work under the full table, or the
    // premise doesn't hold in this environment and the redirect assertion
    // below would blame the wrong thing. Concretely: under QEMU
    // user-emulation (the ppc64le/s390x CI legs), binfmt needs a spare
    // descriptor to load the interpreter before the child ever reaches its
    // exec-time CLOEXEC cleanup, so no spawn at all survives a zero-free
    // table there (kaappi#2442 review; CI jobs 99546383549/99546383648).
    _ = vm.eval(
        \\(let ((p (spawn-process '("true")))) (process-wait p) #t)
    ) catch return error.SkipZigTest;

    try expectTrue(vm,
        \\(let ((p (spawn-process '("true") 'stdout: (current-output-port))))
        \\  (= (process-wait p) 0))
    );
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

// ---------------------------------------------------------------------------
// KEP-0022 Phase 2 (kaappi#2415): fiber-parking process-wait, timeout, group
// kill. The exit-triggering idiom is `cat` on a stdin pipe — closing the pipe
// EOFs the child, so a test controls *when* the exit happens (and from which
// fiber) with no sleeps in the assertion path.
// ---------------------------------------------------------------------------

test "process-wait phase2: a slow child does not starve a sibling fiber" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // The wait can only resolve after the sibling has run 11 times — it is
    // the sibling's 11th turn that closes the child's stdin. A starved
    // sibling (the Phase-1 blocking wait) deadlocks here instead; the
    // counter assertion additionally pins that every turn really ran.
    try expectTrue(vm,
        \\(begin
        \\  (define p (spawn-process '("cat") 'stdin: 'pipe 'stdout: 'null))
        \\  (define counter 0)
        \\  (spawn (lambda ()
        \\    (let loop ((i 0))
        \\      (set! counter (+ counter 1))
        \\      (if (< i 10)
        \\          (begin (yield) (loop (+ i 1)))
        \\          (close-port (process-stdin p))))))
        \\  (and (= 0 (process-wait p)) (>= counter 11)))
    );
    // The wait's reactor registration must not outlive it.
    try std.testing.expectEqual(@as(usize, 0), vm.reactor.?.procs.count());
    // Reaped through the reactor: the unreaped registry is empty too.
    try std.testing.expectEqual(@as(usize, 0), ctx.gc.unreaped_processes.items.len);
}

test "process-wait phase2: timeout contract — #f, child lives, kill, final wait reaps" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    try expectTrue(vm,
        \\(begin
        \\  (define p (spawn-process '("/bin/sleep" "30")))
        \\  (and (eq? #f (process-wait p 'timeout: 0.05))
        \\       (eq? #f (process-status p))))
    );
    // The timed-out waiter withdrew itself: no registration, no timer left.
    try std.testing.expectEqual(@as(usize, 0), vm.reactor.?.procs.count());
    try std.testing.expectEqual(@as(usize, 0), vm.reactor.?.timers.count());
    try expectTrue(vm,
        \\(begin
        \\  (process-kill p)
        \\  (equal? '(signaled . 15) (process-wait p)))
    );
    try std.testing.expectEqual(@as(usize, 0), vm.reactor.?.procs.count());
}

test "process-wait phase2: 'timeout: #f means no timeout, and delivery wins over a generous one" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // A 30-second timeout must not delay a prompt exit: the whole scenario
    // (sibling closes stdin on its first turn) completes in well under it.
    const t0 = fiber_mod.clockNs();
    try expectTrue(vm,
        \\(begin
        \\  (define p (spawn-process '("cat") 'stdin: 'pipe 'stdout: 'null))
        \\  (spawn (lambda () (close-port (process-stdin p))))
        \\  (= 0 (process-wait p 'timeout: 30)))
    );
    const elapsed = fiber_mod.clockNs() - t0;
    try std.testing.expect(elapsed < 20 * std.time.ns_per_s);
    try std.testing.expectEqual(@as(usize, 0), vm.reactor.?.timers.count());

    // timeout: #f = wait forever (the timeoutToDeadlineNs convention).
    try expectTrue(vm,
        \\(begin
        \\  (define p2 (spawn-process '("cat") 'stdin: 'pipe 'stdout: 'null))
        \\  (spawn (lambda () (close-port (process-stdin p2))))
        \\  (= 0 (process-wait p2 'timeout: #f)))
    );
}

test "process-wait phase2: a dispatched fiber flat-parks and is woken by the exit" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // f parks on its first dispatch (the child is still alive); g's fifth
    // turn triggers the exit. Both waiters of p see the same stored status —
    // the reactor reaps once and wakes everyone.
    try expectTrue(vm,
        \\(begin
        \\  (define p (spawn-process '("cat") 'stdin: 'pipe 'stdout: 'null))
        \\  (define f1 (spawn (lambda () (process-wait p))))
        \\  (define f2 (spawn (lambda () (process-wait p))))
        \\  (define g (spawn (lambda ()
        \\    (let loop ((i 0))
        \\      (if (< i 5)
        \\          (begin (yield) (loop (+ i 1)))
        \\          (close-port (process-stdin p)))))))
        \\  (and (= 0 (fiber-join f1))
        \\       (= 0 (fiber-join f2))
        \\       (begin (fiber-join g) #t)))
    );
    try std.testing.expectEqual(@as(usize, 0), vm.reactor.?.procs.count());
}

test "process-wait phase2: a dispatched fiber's timeout fires while the child lives" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    try expectTrue(vm,
        \\(begin
        \\  (define p (spawn-process '("/bin/sleep" "30")))
        \\  (define f (spawn (lambda () (process-wait p 'timeout: 0.05))))
        \\  (and (eq? #f (fiber-join f))
        \\       (eq? #f (process-status p))))
    );
    try std.testing.expectEqual(@as(usize, 0), vm.reactor.?.procs.count());
    try std.testing.expectEqual(@as(usize, 0), vm.reactor.?.timers.count());
    try expectTrue(vm,
        \\(begin
        \\  (process-kill p 'signal: 9)
        \\  (equal? '(signaled . 9) (process-wait p)))
    );
}

test "process-wait phase2: a sibling's process-status reap wakes a parked waiter" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // g's poll loop may be the one that reaps (tryReapOne) — the parked f
    // must still be woken (wakeProcessWaiters), never left to a kernel event
    // that already fired into a dropped registration.
    try expectTrue(vm,
        \\(begin
        \\  (define p (spawn-process '("cat") 'stdin: 'pipe 'stdout: 'null))
        \\  (define f (spawn (lambda () (process-wait p))))
        \\  (define g (spawn (lambda ()
        \\    (let loop ((i 0))
        \\      (cond ((process-status p) 'saw-it)
        \\            (else (when (= i 5) (close-port (process-stdin p)))
        \\                  (yield)
        \\                  (loop (+ i 1))))))))
        \\  (and (= 0 (fiber-join f)) (eq? 'saw-it (fiber-join g))))
    );
    try std.testing.expectEqual(@as(usize, 0), vm.reactor.?.procs.count());
}

test "process-wait phase2: group kill reaches the child's own child" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    const platform = @import("platform.zig");
    // The shell backgrounds a sleeper (its own child, same fresh process
    // group), reports the grandchild's pid, and waits. `group: #t` must
    // bring down both — the grandchild's death is observed from out here via
    // kill(gpid, 0) turning ESRCH once init reaps it.
    const gpid_val = try vm.eval(
        \\(begin
        \\  (define p (spawn-process '("/bin/sh" "-c" "sleep 30 & echo $!; wait")
        \\                           'stdout: 'pipe 'new-group: #t))
        \\  (string->number (read-line (process-stdout p))))
    );
    const gpid: i32 = @intCast(types.toFixnum(gpid_val));
    try std.testing.expect(gpid > 0);
    // The grandchild exists right now (the shell printed its pid).
    try std.testing.expectEqual(@as(c_int, 0), platform.procKill(gpid, 0));

    try expectTrue(vm,
        \\(begin
        \\  (process-kill p 'group: #t)
        \\  (let ((st (process-wait p)))
        \\    (or (pair? st) (integer? st))))
    );

    // The grandchild dies with the group; once init reaps it, signaling it
    // reports ESRCH. Bounded: a surviving grandchild fails the test at the
    // deadline (and its 30-second sleep ends it soon after regardless).
    const deadline = fiber_mod.clockNs() + 10 * std.time.ns_per_s;
    while (platform.procKill(gpid, 0) == 0) {
        if (fiber_mod.clockNs() > deadline) return error.GrandchildSurvivedGroupKill;
        platform.sleepNs(10 * std.time.ns_per_ms);
    }
}

test "process-wait phase2: re-waiting a reactor-reaped process returns the stored status" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    try expectTrue(vm,
        \\(begin
        \\  (define p (spawn-process '("cat") 'stdin: 'pipe 'stdout: 'null))
        \\  (spawn (lambda () (close-port (process-stdin p))))
        \\  (and (= 0 (process-wait p))
        \\       (= 0 (process-wait p))
        \\       (= 0 (process-status p))))
    );
    try std.testing.expectEqual(@as(usize, 0), ctx.gc.unreaped_processes.items.len);
}

test "process-wait phase2: option errors are loud" {
    if (comptime !is_posix) return error.SkipZigTest;
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    try expectTrue(vm,
        \\(begin
        \\  (define p (spawn-process '("true")))
        \\  (define (bad thunk) (guard (e (#t #t)) (thunk) #f))
        \\  (and (bad (lambda () (process-wait p 'timeout:)))
        \\       (bad (lambda () (process-wait p 'nonsense: 1)))
        \\       (bad (lambda () (process-wait p 'timeout: 'soon)))
        \\       (begin (process-wait p) #t)))
    );
}

test "process-wait phase2: a child reaped behind kaappi's back raises, never #f-before-deadline" {
    if (comptime !is_posix) return error.SkipZigTest;
    const platform = @import("platform.zig");
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const vm = ctx.vm;

    // Reap the child directly (the test binary IS the parent), bypassing the
    // registry — the shape a misbehaving C FFI library's wait(-1) produces.
    const pid_val = try vm.eval(
        \\(begin (define p (spawn-process '("/bin/sleep" "30"))) (process-pid p))
    );
    const pid: i32 = @intCast(types.toFixnum(pid_val));
    try std.testing.expectEqual(@as(c_int, 0), platform.procKill(pid, 9));
    var st: c_int = 0;
    while (true) {
        const r = platform.waitPid(pid, &st, 0);
        if (r == pid) break;
        if (r < 0 and std.c._errno().* != @intFromEnum(std.c.E.INTR)) return error.ReapFailed;
    }

    // A timed wait must not report `#f` ahead of its generous deadline (the
    // spurious-timeout hazard: a no-status wake flips `timed_out`), and an
    // untimed wait must not hang or return `#f` either — both surface the
    // waitpid error, catchably, and promptly.
    const t0 = fiber_mod.clockNs();
    try expectTrue(vm,
        \\(guard (e (#t (file-error? e)))
        \\  (process-wait p 'timeout: 30)
        \\  'no-error-raised)
    );
    try expectTrue(vm,
        \\(guard (e (#t (file-error? e)))
        \\  (process-wait p)
        \\  'no-error-raised)
    );
    const elapsed = fiber_mod.clockNs() - t0;
    try std.testing.expect(elapsed < 20 * std.time.ns_per_s);
}
