// KEP-0001 Phase 3: non-blocking port reads/writes through the reactor.
// Complements tests_reactor.zig (Phase 1, reactor in isolation) and
// tests_scheduler.zig (Phase 2, scheduler/reactor plumbing). These tests
// exercise the port layer end-to-end over real pipes: fibers parking on
// EAGAIN and resuming losslessly, the main fiber driving the scheduler
// while it waits, write buffering with real flush, and the close-port
// wake discipline.
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const fiber_mod = @import("fiber.zig");
const primitives_io = @import("primitives_io.zig");

fn makePipe() [2]std.c.fd_t {
    var fds: [2]std.c.fd_t = undefined;
    if (std.c.pipe(&fds) != 0) unreachable;
    return fds;
}

fn setNonblockingFd(fd: std.c.fd_t) void {
    const flags = std.c.fcntl(fd, std.posix.F.GETFL, @as(c_int, 0));
    const nonblock: c_int = @intCast(@as(u32, @bitCast(std.posix.O{ .NONBLOCK = true })));
    _ = std.c.fcntl(fd, std.posix.F.SETFL, flags | nonblock);
}

/// Wraps `fd` in a port and binds it to `name` as a global. The port owns
/// the fd from here on: the GC's freeObject (or an explicit close-port)
/// closes it, so tests must not close it again themselves.
fn definePortGlobal(vm: *th.VM, name: []const u8, fd: std.c.fd_t, is_input: bool, is_output: bool) !*types.Port {
    const port_val = try vm.gc.allocPort(fd, is_input, is_output, name, false);
    try vm.defineGlobal(name, port_val);
    return types.toObject(port_val).as(types.Port);
}

test "two fibers reading two pipes park and interleave through the reactor" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pipe1 = makePipe();
    const pipe2 = makePipe();
    _ = try definePortGlobal(vm, "rp1", pipe1[0], true, false);
    _ = try definePortGlobal(vm, "wp1", pipe1[1], false, true);
    _ = try definePortGlobal(vm, "rp2", pipe2[0], true, false);
    _ = try definePortGlobal(vm, "wp2", pipe2[1], false, true);

    _ = try vm.eval("(import (kaappi fibers))");
    // Both readers park on empty pipes before the writer runs; the writer
    // fills pipe 2 first, then pipe 1. If either read blocked the OS
    // thread instead of parking, the writer would never run and this test
    // would deadlock rather than pass.
    _ = try vm.eval("(define f1 (spawn (lambda () (read-char rp1))))");
    _ = try vm.eval("(define f2 (spawn (lambda () (read-char rp2))))");
    _ = try vm.eval(
        \\(define w (spawn (lambda ()
        \\  (write-char #\b wp2) (flush-output-port wp2)
        \\  (write-char #\a wp1) (flush-output-port wp1))))
    );
    const r1 = try vm.eval("(fiber-join f1)");
    const r2 = try vm.eval("(fiber-join f2)");
    try std.testing.expectEqual(types.makeChar('a'), r1);
    try std.testing.expectEqual(types.makeChar('b'), r2);
}

test "main fiber read drives the scheduler while it waits" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pipe = makePipe();
    _ = try definePortGlobal(vm, "rp", pipe[0], true, false);
    _ = try definePortGlobal(vm, "wp", pipe[1], false, true);

    _ = try vm.eval("(import (kaappi fibers))");
    // The producer only runs while main's read-line waits: main (fiber 0)
    // cannot park-and-retry, so its wait must dispatch siblings in place.
    _ = try vm.eval(
        \\(define w (spawn (lambda ()
        \\  (write-string "hello\n" wp) (flush-output-port wp))))
    );
    const r = try vm.eval("(equal? (read-line rp) \"hello\")");
    try std.testing.expectEqual(types.TRUE, r);
}

test "write larger than the pipe buffer parks the writer; a reader fiber drains it losslessly" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pipe = makePipe();
    _ = try definePortGlobal(vm, "rp", pipe[0], true, false);
    _ = try definePortGlobal(vm, "wp", pipe[1], false, true);

    _ = try vm.eval("(import (kaappi fibers))");
    // 100000 bytes exceeds any platform's default pipe capacity (16-64 KiB),
    // so the flush hits EAGAIN mid-buffer and the writer suspends on write
    // readiness; the reader's read-string in turn parks whenever the pipe
    // runs dry. The final count and spot-checks prove no byte was lost or
    // duplicated across those park/retry cycles.
    _ = try vm.eval("(define n 100000)");
    _ = try vm.eval(
        \\(define writer (spawn (lambda ()
        \\  (write-string (make-string n #\x) wp)
        \\  (flush-output-port wp)
        \\  (close-port wp))))
    );
    _ = try vm.eval(
        \\(define reader (spawn (lambda ()
        \\  (let loop ((total 0) (ok #t))
        \\    (let ((s (read-string 4096 rp)))
        \\      (if (eof-object? s)
        \\          (and ok (= total n))
        \\          (loop (+ total (string-length s))
        \\                (and ok (string=? s (make-string (string-length s) #\x))))))))))
    );
    const r = try vm.eval("(fiber-join reader)");
    try std.testing.expectEqual(types.TRUE, r);
}

test "(read) parked mid-datum resumes with the buffered prefix" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pipe = makePipe();
    _ = try definePortGlobal(vm, "rp", pipe[0], true, false);
    _ = try definePortGlobal(vm, "wp", pipe[1], false, true);

    _ = try vm.eval("(import (kaappi fibers) (srfi 18))");
    _ = try vm.eval("(define f (spawn (lambda () (read rp))))");
    // The sleep forces real sequencing: the reader wakes on the first
    // chunk, parses an incomplete datum, hits EAGAIN, and must stash
    // "(1 2 " into port.read_buf before parking again. If that stash were
    // lost, the retry would parse "3)" alone and error.
    _ = try vm.eval(
        \\(define w (spawn (lambda ()
        \\  (write-string "(1 2 " wp) (flush-output-port wp)
        \\  (thread-sleep! 0.05)
        \\  (write-string "3)" wp) (flush-output-port wp))))
    );
    const r = try vm.eval("(equal? (fiber-join f) '(1 2 3))");
    try std.testing.expectEqual(types.TRUE, r);
}

test "closing a port with a parked reader raises a clean error in that fiber" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pipe = makePipe();
    _ = try definePortGlobal(vm, "rp", pipe[0], true, false);
    _ = try definePortGlobal(vm, "wp", pipe[1], false, true);

    _ = try vm.eval("(import (kaappi fibers))");
    _ = try vm.eval(
        \\(define f (spawn (lambda ()
        \\  (guard (e (#t (list 'caught (error-object? e))))
        \\    (read-char rp)
        \\    'not-reached))))
    );
    _ = try vm.eval("(define closer (spawn (lambda () (close-port rp))))");
    // The join completing at all is the "nothing hangs" half of the
    // acceptance criterion; the guard result is the "clean error" half.
    const r = try vm.eval("(equal? (fiber-join f) '(caught #t))");
    try std.testing.expectEqual(types.TRUE, r);
}

test "thread-terminate! pulls a parked reader off the reactor; the fd stays usable" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pipe = makePipe();
    _ = try definePortGlobal(vm, "rp", pipe[0], true, false);
    _ = try definePortGlobal(vm, "wp", pipe[1], false, true);

    _ = try vm.eval("(import (kaappi fibers) (srfi 18))");
    _ = try vm.eval("(define f (spawn (lambda () (read-char rp))))");
    // Dispatch f so it parks on the empty pipe, then kill it. Terminate
    // must remove f from the reactor's waiter list for this fd (mirroring
    // its removeTimer discipline) or the dead fiber would linger there as
    // a stale registration for the next reader below.
    _ = try vm.eval("(fiber-join (spawn (lambda () 1)))");
    const f_val = try vm.eval("f");
    try std.testing.expectEqual(fiber_mod.FiberStatus.io_waiting, types.toObject(f_val).as(fiber_mod.Fiber).status);
    _ = try vm.eval("(thread-terminate! f)");
    try std.testing.expectEqual(@as(?std.posix.fd_t, null), types.toObject(f_val).as(fiber_mod.Fiber).io_fd);

    _ = try vm.eval("(define g (spawn (lambda () (read-char rp))))");
    _ = try vm.eval("(define w (spawn (lambda () (write-char #\\k wp) (flush-output-port wp))))");
    const r = try vm.eval("(fiber-join g)");
    try std.testing.expectEqual(types.makeChar('k'), r);
}

test "port write buffer holds bytes until flush; close-port flushes the remainder" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pipe = makePipe();
    setNonblockingFd(pipe[0]); // test-side reads must not block on an empty pipe
    _ = try definePortGlobal(vm, "wp", pipe[1], false, true);
    defer _ = std.posix.system.close(pipe[0]); // read end stays Zig-owned

    _ = try vm.eval("(write-char #\\z wp)");
    var buf: [8]u8 = undefined;
    // Buffered: nothing reaches the pipe before the flush.
    try std.testing.expect(std.posix.system.read(pipe[0], &buf, buf.len) < 0);
    _ = try vm.eval("(flush-output-port wp)");
    try std.testing.expectEqual(@as(isize, 1), std.posix.system.read(pipe[0], &buf, buf.len));
    try std.testing.expectEqual(@as(u8, 'z'), buf[0]);

    _ = try vm.eval("(write-char #\\q wp)");
    _ = try vm.eval("(close-port wp)");
    try std.testing.expectEqual(@as(isize, 1), std.posix.system.read(pipe[0], &buf, buf.len));
    try std.testing.expectEqual(@as(u8, 'q'), buf[0]);
}

test "a read on the same port flushes its pending writes first" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // One bidirectional port over a socketpair: the request must reach the
    // peer before the port waits for the response, or request/response
    // protocols over one port would deadlock on the unflushed request.
    var fds: [2]std.c.fd_t = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, &fds));
    _ = try definePortGlobal(vm, "sp", fds[0], true, true);
    defer _ = std.posix.system.close(fds[1]); // peer end stays Zig-owned

    // Stage the peer's response up front so the read completes immediately
    // once the flush-before-read has happened.
    _ = std.posix.system.write(fds[1], "y", 1);

    _ = try vm.eval("(write-char #\\x sp)"); // buffered request
    const r = try vm.eval("(read-char sp)");
    try std.testing.expectEqual(types.makeChar('y'), r);

    var buf: [8]u8 = undefined;
    try std.testing.expectEqual(@as(isize, 1), std.posix.system.read(fds[1], &buf, buf.len));
    try std.testing.expectEqual(@as(u8, 'x'), buf[0]);
}

test "(read) must not lose read_buf when its write drain parks" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // Bidirectional port over a socketpair with tiny kernel buffers so a
    // buffered-write drain hits EAGAIN.
    var fds: [2]std.c.fd_t = undefined;
    try std.testing.expectEqual(@as(c_int, 0), std.c.socketpair(std.posix.AF.UNIX, std.posix.SOCK.STREAM, 0, &fds));
    const small: c_int = 4096;
    try std.posix.setsockopt(fds[0], std.posix.SOL.SOCKET, std.posix.SO.SNDBUF, &std.mem.toBytes(small));
    try std.posix.setsockopt(fds[1], std.posix.SOL.SOCKET, std.posix.SO.RCVBUF, &std.mem.toBytes(small));
    _ = try definePortGlobal(vm, "sp", fds[0], true, true);
    _ = try definePortGlobal(vm, "peer", fds[1], true, true);

    // The first (read sp) consumes (a) and stashes " (b)" into port.read_buf.
    _ = std.posix.system.write(fds[1], "(a) (b)", 7);
    const first = try vm.eval("(equal? (read sp) '(a))");
    try std.testing.expectEqual(types.TRUE, first);

    _ = try vm.eval("(import (kaappi fibers))");
    // f buffers a 20 KB write (a single write-string is appended whole —
    // the high-water drain only flushes *prior* pending bytes), then calls
    // (read sp). readDatumFn moves read_buf's " (b)" into its local buf,
    // then drains the write buffer, which EAGAINs against the tiny socket
    // buffers and parks f. If the Yielded unwound without stashing buf,
    // " (b)" would be gone and f's retry would read "(c)" off the fd
    // instead.
    _ = try vm.eval(
        \\(define f (spawn (lambda ()
        \\  (write-string (make-string 20000 #\x) sp)
        \\  (read sp))))
    );
    _ = try vm.eval(
        \\(define g (spawn (lambda ()
        \\  (read-string 20000 peer)
        \\  (write-string "(c)" peer)
        \\  (flush-output-port peer))))
    );
    const got_b = try vm.eval("(equal? (fiber-join f) '(b))");
    try std.testing.expectEqual(types.TRUE, got_b);
}

test "binary read-u8 drains bytes a prior (read) left in the port buffer" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pipe = makePipe();
    _ = try definePortGlobal(vm, "rp", pipe[0], true, false);
    defer _ = std.posix.system.close(pipe[1]);

    // (read) slurps a 4 KiB chunk, consumes "(a)", and stashes " 7" in
    // port.read_buf. The old binary-side byte reader had its own copy that
    // skipped read_buf entirely, silently losing these bytes.
    _ = std.posix.system.write(pipe[1], "(a) 7", 5);
    const datum_ok = try vm.eval("(equal? (read rp) '(a))");
    try std.testing.expectEqual(types.TRUE, datum_ok);
    const b = try vm.eval("(read-u8 rp)");
    try std.testing.expectEqual(types.makeFixnum(' '), b);
    const b2 = try vm.eval("(read-u8 rp)");
    try std.testing.expectEqual(types.makeFixnum('7'), b2);
}

test "lazy O_NONBLOCK: set only for fd > 2 and only once a scheduler exists" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pipe = makePipe();
    const rport = try definePortGlobal(vm, "rp", pipe[0], true, false);
    defer _ = std.posix.system.close(pipe[1]);

    // Sequential program: reads never flip the fd, so blocking semantics
    // and the syscall profile are untouched.
    _ = std.posix.system.write(pipe[1], "a", 1);
    _ = try vm.eval("(read-char rp)");
    try std.testing.expect(!rport.nonblocking);

    // The guard itself: fd 0/1/2 never flip even with a scheduler running.
    _ = try vm.eval("(import (kaappi fibers)) (fiber-join (spawn (lambda () 1)))");
    const stdin_port = types.toObject(vm.stdin_port).as(types.Port);
    primitives_io.maybeSetNonblocking(stdin_port);
    try std.testing.expect(!stdin_port.nonblocking);

    // A real-fd port does flip on its next use now that fibers exist.
    _ = std.posix.system.write(pipe[1], "b", 1);
    _ = try vm.eval("(read-char rp)");
    try std.testing.expect(rport.nonblocking);
}

test "flush-output-port accepts string ports and the default port" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const r = try vm.eval(
        \\(let ((sp (open-output-string)))
        \\  (write-string "ab" sp)
        \\  (flush-output-port sp)
        \\  (flush-output-port)
        \\  (get-output-string sp))
    );
    const s = types.toObject(r).as(types.SchemeString);
    try std.testing.expectEqualStrings("ab", s.data[0..s.len]);
}

test "file I/O with fibers active stays correct (files never EAGAIN)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    defer _ = std.posix.system.unlink("/tmp/kaappi-port-io-test.txt");
    const r = try vm.eval(
        \\(begin
        \\  (import (kaappi fibers))
        \\  (fiber-join (spawn (lambda () 1)))
        \\  (let ((out (open-output-file "/tmp/kaappi-port-io-test.txt")))
        \\    (write-string "line one" out)
        \\    (close-port out))
        \\  (let* ((in (open-input-file "/tmp/kaappi-port-io-test.txt"))
        \\         (line (read-line in)))
        \\    (close-port in)
        \\    (equal? line "line one")))
    );
    try std.testing.expectEqual(types.TRUE, r);
}

// #1478: (fd->port fd) hands a raw FFI descriptor (a kaappi-net socket) the
// same reactor-integrated, non-blocking I/O the built-in file ports get, so a
// blocking-looking read suspends the fiber on the reactor instead of
// busy-polling the fd with a 1ms sleep.

test "#1478: fd->port read parks the fiber on the reactor until the peer writes" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    // The two fd->port ports take ownership of these fds; the GC's freeObject
    // (or close-port) closes them, so the test must not close them itself.
    const pipe = makePipe();

    // reader parks on an empty pipe (EAGAIN -> reactor); writer fills it. If
    // fd->port didn't route through the reactor, the reader would either
    // block the whole thread on a blocking read or spin -- here it must wake
    // exactly when the byte arrives and read it back.
    var buf: [768]u8 = undefined;
    const src = try std.fmt.bufPrint(&buf,
        \\(import (kaappi ffi) (kaappi fibers) (scheme base))
        \\(define rp (fd->port {d}))
        \\(define wp (fd->port {d}))
        \\(define reader (spawn (lambda () (read-u8 rp))))
        \\(define writer (spawn (lambda () (write-u8 66 wp) (flush-output-port wp))))
        \\(fiber-join writer)
        \\(fiber-join reader)
    , .{ pipe[0], pipe[1] });

    const result = try vm.eval(src);
    try std.testing.expectEqual(@as(i64, 66), types.toFixnum(result));
}

test "#1478: fd->port rejects the standard streams and non-fixnums" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (kaappi ffi))");
    // fd 0/1/2 keep their blocking semantics -- fd->port must refuse them.
    try std.testing.expectError(error.TypeError, vm.eval("(fd->port 1)"));
    try std.testing.expectError(error.TypeError, vm.eval("(fd->port \"nope\")"));
}

// #1460: readOneByte reads a chunk into read_buf and serves subsequent bytes
// from memory, so byte-at-a-time consumers (read-u8, read-char,
// read-bytevector, read-string, read-line) pay one read(2) per burst rather
// than one per byte.

test "readOneByte batches an available burst into read_buf, not one syscall per byte" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pipe = makePipe();
    const rport = try definePortGlobal(vm, "rp", pipe[0], true, false);
    defer _ = std.posix.system.close(pipe[1]);

    // Stage a burst, then read a single byte. Batching pulls the whole burst
    // in one read(2) and parks the tail in read_buf; without it every byte
    // would cost its own read(2) and read_buf would stay empty -- this is the
    // one assertion that fails on the pre-#1460 single-byte reader.
    const burst = "ABCDEFGHIJ";
    try std.testing.expectEqual(@as(isize, burst.len), std.posix.system.write(pipe[1], burst, burst.len));
    const first = try vm.eval("(read-u8 rp)");
    try std.testing.expectEqual(types.makeFixnum('A'), first);
    try std.testing.expectEqual(@as(usize, burst.len - 1), rport.read_buf_len);

    // The buffered tail is then served in order from memory.
    const rest = try vm.eval("(read-string 9 rp)");
    const s = types.toObject(rest).as(types.SchemeString);
    try std.testing.expectEqualStrings("BCDEFGHIJ", s.data[0..s.len]);
}

test "read-bytevector over a large file preserves byte order across batched chunk boundaries" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    defer _ = std.posix.system.unlink("/tmp/kaappi-readbv-large.bin");
    // 10000 bytes spans the 4096-byte read chunk twice. A deterministic,
    // position-dependent pattern makes any dropped, duplicated, or reordered
    // byte across a chunk boundary fail the equal? against the in-memory
    // original (which never touched the fd).
    const r = try vm.eval(
        \\(let ((n 10000) (path "/tmp/kaappi-readbv-large.bin"))
        \\  (define original (make-bytevector n 0))
        \\  (let loop ((i 0))
        \\    (when (< i n)
        \\      (bytevector-u8-set! original i (modulo (* i 31) 256))
        \\      (loop (+ i 1))))
        \\  (let ((out (open-binary-output-file path)))
        \\    (write-bytevector original out)
        \\    (close-port out))
        \\  (let ((in (open-binary-input-file path)))
        \\    (let ((got (read-bytevector n in)))
        \\      (close-port in)
        \\      (and (= (bytevector-length got) n) (equal? got original)))))
    );
    try std.testing.expectEqual(types.TRUE, r);
}

test "read-bytevector composes read_buf left by a prior (read) with fresh fd reads" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    defer _ = std.posix.system.unlink("/tmp/kaappi-readbv-afterread.txt");
    // (read) slurps a chunk, parses (a b c), and stashes that chunk's tail in
    // read_buf; the 6000 trailing 'z' bytes overflow one chunk, so
    // read-bytevector must drain the stash and then batch more from the fd,
    // with byte 122 ('z') throughout.
    const r = try vm.eval(
        \\(let ((path "/tmp/kaappi-readbv-afterread.txt"))
        \\  (let ((out (open-output-file path)))
        \\    (write-string "(a b c)" out)
        \\    (write-string (make-string 6000 #\z) out)
        \\    (close-port out))
        \\  (let ((in (open-input-file path)))
        \\    (let ((datum (read in)))
        \\      (let ((bv (read-bytevector 6000 in)))
        \\        (close-port in)
        \\        (and (equal? datum '(a b c))
        \\             (= (bytevector-length bv) 6000)
        \\             (let chk ((i 0))
        \\               (if (= i 6000) #t
        \\                   (and (= (bytevector-u8-ref bv i) 122) (chk (+ i 1))))))))))
    );
    try std.testing.expectEqual(types.TRUE, r);
}

test "read-bytevector after peek-char includes the peeked byte in order" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    defer _ = std.posix.system.unlink("/tmp/kaappi-readbv-afterpeek.txt");
    // peek-char pulls a batched chunk: byte 0 goes back into peek_byte, the
    // rest stays in read_buf. read-bytevector must then deliver the peeked
    // byte first, the read_buf tail next, and the fd last -- all in order.
    const r = try vm.eval(
        \\(let ((path "/tmp/kaappi-readbv-afterpeek.txt"))
        \\  (let ((out (open-output-file path)))
        \\    (write-string "hello world" out)
        \\    (close-port out))
        \\  (let ((in (open-input-file path)))
        \\    (let ((pc (peek-char in)))
        \\      (let ((bv (read-bytevector 11 in)))
        \\        (close-port in)
        \\        (and (char=? pc #\h)
        \\             (equal? bv (string->utf8 "hello world")))))))
    );
    try std.testing.expectEqual(types.TRUE, r);
}

test "a parked mid-read-bytevector retry over a pipe loses no bytes" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const pipe = makePipe();
    _ = try definePortGlobal(vm, "rp", pipe[0], true, false);
    _ = try definePortGlobal(vm, "wp", pipe[1], false, true);

    _ = try vm.eval("(import (kaappi fibers) (srfi 18))");
    // 10000 bytes, position-dependent. The writer sends it in two 5000-byte
    // bursts with a sleep between: the reader consumes burst one (crossing a
    // chunk boundary), finds the pipe dry, stashes its 5000-byte partial
    // progress and parks. Its retry must re-serve that stash and then batch
    // burst two -- any loss or reordering across the park fails equal?.
    _ = try vm.eval(
        \\(begin
        \\  (define n 10000)
        \\  (define half 5000)
        \\  (define original (make-bytevector n 0))
        \\  (let loop ((i 0))
        \\    (when (< i n)
        \\      (bytevector-u8-set! original i (modulo i 256))
        \\      (loop (+ i 1)))))
    );
    _ = try vm.eval("(define reader (spawn (lambda () (read-bytevector n rp))))");
    _ = try vm.eval(
        \\(define writer (spawn (lambda ()
        \\  (write-bytevector original wp 0 half) (flush-output-port wp)
        \\  (thread-sleep! 0.05)
        \\  (write-bytevector original wp half n) (flush-output-port wp)
        \\  (close-port wp))))
    );
    _ = try vm.eval("(fiber-join writer)");
    const r = try vm.eval("(equal? (fiber-join reader) original)");
    try std.testing.expectEqual(types.TRUE, r);
}
