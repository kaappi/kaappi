// KEP-0001 Phase 2: scheduler <-> reactor integration. Complements
// tests_reactor.zig (Phase 1, reactor in isolation) and tests_fibers.zig
// (existing fiber/channel behavior). These tests exercise the new pieces
// specifically: io_waiting exclusion/inclusion in scheduling decisions,
// parkOnReactor's ready-list handling against a real fd, and the
// live-window bound on per-fiber save/restore storage.
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const fiber_mod = @import("fiber.zig");
const reactor_mod = @import("reactor.zig");

fn makePipe() [2]std.c.fd_t {
    var fds: [2]std.c.fd_t = undefined;
    if (std.c.pipe(&fds) != 0) unreachable;
    return fds;
}

fn closeFd(fd: std.c.fd_t) void {
    _ = std.posix.system.close(fd);
}

fn writeByte(fd: std.c.fd_t, byte: u8) void {
    const buf = [1]u8{byte};
    const n = std.posix.system.write(fd, &buf, 1);
    std.testing.expectEqual(@as(isize, 1), n) catch unreachable;
}

test "schedule() does not select an io_waiting fiber" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () 1)))");
    const sched = vm.scheduler.?;
    const f_val = try vm.eval("f");
    const f = types.toObject(f_val).as(fiber_mod.Fiber);
    try std.testing.expectEqual(fiber_mod.FiberStatus.created, f.status);

    f.status = .io_waiting;
    try std.testing.expectEqual(@as(?usize, null), sched.schedule());

    f.status = .suspended;
    try std.testing.expect(sched.schedule() != null);
}

test "hasRunnableFibers reports io_waiting as alive but not a merely-running ancestor" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () 1)))");
    const sched = vm.scheduler.?;
    const f_val = try vm.eval("f");
    const f = types.toObject(f_val).as(fiber_mod.Fiber);

    // Main (id 0) is .running here (execute()'s prologue sets it on every
    // top-level form); with f neutralized, nothing should look runnable —
    // parkOnReactor's whole point is that a .running ancestor deep in its
    // own recursive dispatch must not count as "other progress possible".
    f.status = .completed;
    try std.testing.expect(!sched.hasRunnableFibers());

    f.status = .io_waiting;
    try std.testing.expect(sched.hasRunnableFibers());
}

test "parkOnReactor wakes a manually io_waiting fiber when its fd becomes readable" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () 1)))");
    const sched = vm.scheduler.?;
    const reactor = vm.reactor.?;
    const f_val = try vm.eval("f");
    const f = types.toObject(f_val).as(fiber_mod.Fiber);

    const pipe = makePipe();
    defer closeFd(pipe[0]);
    defer closeFd(pipe[1]);

    f.status = .io_waiting;
    f.io_fd = pipe[0];
    f.io_interest = .read;
    try reactor.register(pipe[0], .read, f);

    writeByte(pipe[1], 'x');

    const made_progress = try fiber_mod.parkOnReactor(vm, sched);
    try std.testing.expect(made_progress);
    try std.testing.expectEqual(fiber_mod.FiberStatus.suspended, f.status);
}

test "parkOnReactor reports no progress (genuine deadlock) when nothing is pending" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () 1)))");
    const sched = vm.scheduler.?;
    const f_val = try vm.eval("f");
    const f = types.toObject(f_val).as(fiber_mod.Fiber);
    f.status = .completed; // neutralize: nothing left that could ever wake

    const made_progress = try fiber_mod.parkOnReactor(vm, sched);
    try std.testing.expect(!made_progress);
}

test "fiber switch does not grow the fiber's own register storage to match a large VM register file" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (kaappi fibers)) (define f (spawn (lambda () 42)))");
    const sched = vm.scheduler.?;
    const f_val = try vm.eval("f");
    const f = types.toObject(f_val).as(fiber_mod.Fiber);
    try std.testing.expect(f.registers.len < 1024);

    // Simulate the VM having grown large from unrelated deep recursion
    // elsewhere in the program, then switch to and back from the small
    // fiber (main -> f saves main; f -> main saves f — the second switch
    // is the one that would balloon f's storage if save/restore weren't
    // live-window bounded, KEP-0001 Phase 2 resolved question 5).
    try vm.ensureRegisterCapacity(8192);
    sched.switchTo(1);
    sched.switchTo(0);

    try std.testing.expect(f.registers.len < 1024);

    // The fiber's saved state must still be semantically correct after
    // the dance above — bounded copying must not lose live data.
    const result = try vm.eval("(fiber-join f)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}
