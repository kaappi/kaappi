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
    try expectTrue(vm,
        \\(let* ((p (spawn-process '("/bin/sleep" "3") 'stdin: 'pipe))
        \\       (in (process-stdin p)))
        \\  (write-string (make-string 60000 #\x) in)
        \\  (flush-output-port in)
        \\  (write-string (make-string 8100 #\y) in)
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

    const src =
        \\(let ((p (spawn-process '("true") 'stdin: 'pipe 'stdout: 'pipe 'stderr: 'pipe)))
        \\  (process-wait p) #t)
    ;
    // Baseline: one full run so lazily-created infrastructure (reactor fds,
    // caches) exists before the count is taken.
    _ = try vm.eval(src);
    gc.collectFull();
    const before = countFds();

    var n: u32 = 0;
    while (n < 400) : (n += 1) {
        gc.oom_countdown = n;
        _ = vm.eval(src) catch {};
        gc.oom_countdown = null;
    }
    gc.collectFull();
    sweepUnreapedForTest(gc);
    const after = countFds();
    try std.testing.expectEqual(before, after);
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

    // Control: the probe must DETECT an open fd, or "closed" verdicts below
    // are vacuous (a shell that rejects multi-digit redirection fds would
    // report every fd closed). fd 2 is inherited and certainly open.
    try expectTrue(vm,
        \\(let ((p (spawn-process '("/bin/sh" "-c" "if (eval \": <&2\") 2>/dev/null; then exit 0; else exit 1; fi"))))
        \\  (= (process-wait p) 0))
    );
    try expectTrue(vm,
        \\(let ((p (spawn-process '("/bin/sh" "-c" "if (eval \": <&70000\") 2>/dev/null; then exit 1; else exit 0; fi"))))
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
