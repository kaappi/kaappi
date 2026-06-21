const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const CallFrame = vm_mod.CallFrame;

pub const MAX_FIBERS = 64;

pub fn clockNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @intCast(ts.sec)) * 1_000_000_000 + @as(u64, @intCast(ts.nsec));
}

pub const FiberStatus = enum(u8) {
    created,
    running,
    suspended,
    completed,
    errored,
    waiting,
};

pub const Fiber = struct {
    header: types.Object,
    registers: [vm_mod.MAX_REGISTERS]Value,
    frames: [vm_mod.MAX_FRAMES]CallFrame,
    frame_count: usize,
    handler_stack: [vm_mod.MAX_HANDLERS]vm_mod.ExceptionHandler,
    handler_count: usize,
    wind_stack: [vm_mod.MAX_WINDS]types.WindRecord,
    wind_count: usize,
    current_exception: ?Value,
    continuation_invoked: bool,
    continuation_value: Value,
    status: FiberStatus,
    thunk: Value,
    result: Value,
    waiting_on: Value,
    id: u32,
    name: Value = types.VOID,
    specific: Value = types.VOID,
    param_overrides: std.AutoHashMap(usize, Value),
    deadline_ns: ?u64 = null,
    timed_out: bool = false,
    terminated: bool = false,
    os_thread: ?std.Thread = null,
};

pub const FiberScheduler = struct {
    fibers: [MAX_FIBERS]?*Fiber,
    fiber_count: usize,
    current_idx: usize,
    next_id: u32,
    vm: *VM,

    pub fn init(vm: *VM) FiberScheduler {
        return .{
            .fibers = .{null} ** MAX_FIBERS,
            .fiber_count = 0,
            .current_idx = 0,
            .next_id = 0,
            .vm = vm,
        };
    }

    pub fn addFiber(self: *FiberScheduler, fiber: *Fiber) !void {
        if (self.fiber_count >= MAX_FIBERS) return VMError.StackOverflow;
        self.fibers[self.fiber_count] = fiber;
        self.fiber_count += 1;
    }

    pub fn spawnFiber(self: *FiberScheduler, thunk: Value) !*Fiber {
        const fiber = try self.vm.gc.allocFiber(thunk, self.next_id);
        self.next_id += 1;

        if (!types.isClosure(thunk)) return VMError.NotAProcedure;
        const closure = types.toObject(thunk).as(types.Closure);

        @memset(&fiber.registers, types.UNDEFINED);
        fiber.registers[0] = thunk;
        fiber.frames[0] = .{
            .closure = closure,
            .code = closure.func.code.items,
            .ip = 0,
            .base = 0,
            .dst = 0,
            .saved_wind_count = 0,
        };
        fiber.frame_count = 1;
        fiber.status = .created;

        // Inherit parent's parameter bindings
        const source = if (self.vm.current_fiber) |f| &f.param_overrides else &self.vm.param_overrides;
        var it = source.iterator();
        while (it.next()) |entry| {
            fiber.param_overrides.put(entry.key_ptr.*, entry.value_ptr.*) catch {};
        }

        try self.addFiber(fiber);
        return fiber;
    }

    pub fn saveCurrentFiber(self: *FiberScheduler) void {
        const fiber = self.fibers[self.current_idx] orelse return;
        const vm = self.vm;
        @memcpy(&fiber.registers, &vm.registers);
        @memcpy(fiber.frames[0..vm.frame_count], vm.frames[0..vm.frame_count]);
        fiber.frame_count = vm.frame_count;
        @memcpy(fiber.handler_stack[0..vm.handler_count], vm.handler_stack[0..vm.handler_count]);
        fiber.handler_count = vm.handler_count;
        @memcpy(fiber.wind_stack[0..vm.wind_count], vm.wind_stack[0..vm.wind_count]);
        fiber.wind_count = vm.wind_count;
        fiber.current_exception = vm.current_exception;
        fiber.continuation_invoked = vm.continuation_invoked;
        fiber.continuation_value = vm.continuation_value;
    }

    pub fn restoreFiber(self: *FiberScheduler, idx: usize) void {
        const fiber = self.fibers[idx] orelse return;
        const vm = self.vm;
        @memcpy(&vm.registers, &fiber.registers);
        @memcpy(vm.frames[0..fiber.frame_count], fiber.frames[0..fiber.frame_count]);
        vm.frame_count = fiber.frame_count;
        @memcpy(vm.handler_stack[0..fiber.handler_count], fiber.handler_stack[0..fiber.handler_count]);
        vm.handler_count = fiber.handler_count;
        @memcpy(vm.wind_stack[0..fiber.wind_count], fiber.wind_stack[0..fiber.wind_count]);
        vm.wind_count = fiber.wind_count;
        vm.current_exception = fiber.current_exception;
        vm.continuation_invoked = fiber.continuation_invoked;
        vm.continuation_value = fiber.continuation_value;
    }

    pub fn switchTo(self: *FiberScheduler, next_idx: usize) void {
        if (next_idx == self.current_idx) return;
        const current = self.fibers[self.current_idx] orelse return;

        self.saveCurrentFiber();
        if (current.status == .running) current.status = .suspended;

        self.restoreFiber(next_idx);
        const next = self.fibers[next_idx] orelse return;
        next.status = .running;
        self.current_idx = next_idx;
        self.vm.current_fiber = next;
    }

    pub fn schedule(self: *FiberScheduler) ?usize {
        if (self.fiber_count == 0) return null;
        const now = clockNs();
        for (self.fibers[0..self.fiber_count]) |f| {
            if (f) |fiber| {
                if (fiber.status == .waiting) {
                    if (fiber.deadline_ns) |deadline| {
                        if (now >= deadline) {
                            fiber.status = .suspended;
                            fiber.timed_out = true;
                            fiber.deadline_ns = null;
                        }
                    }
                }
            }
        }
        var i: usize = 1;
        while (i <= self.fiber_count) : (i += 1) {
            const idx = (self.current_idx + i) % self.fiber_count;
            if (self.fibers[idx]) |f| {
                if (f.status == .created or f.status == .suspended) return idx;
            }
        }
        return null;
    }

    pub fn hasRunnableFibers(self: *FiberScheduler) bool {
        for (self.fibers[0..self.fiber_count]) |f| {
            if (f) |fiber| {
                if (fiber.status == .created or fiber.status == .suspended or fiber.status == .running)
                    return true;
                if (fiber.status == .waiting and fiber.deadline_ns != null)
                    return true;
            }
        }
        return false;
    }

    pub fn wakeWaiters(self: *FiberScheduler, completed_fiber: *Fiber) void {
        const completed_val = types.makePointer(@ptrCast(completed_fiber));
        for (self.fibers[0..self.fiber_count]) |f| {
            if (f) |fiber| {
                if (fiber.status == .waiting and fiber.waiting_on == completed_val) {
                    fiber.status = .suspended;
                    fiber.result = completed_fiber.result;
                }
            }
        }
    }

    pub fn wakeMutexWaiters(self: *FiberScheduler, mutex_val: Value) void {
        for (self.fibers[0..self.fiber_count]) |f| {
            if (f) |fiber| {
                if (fiber.status == .waiting and fiber.waiting_on == mutex_val) {
                    fiber.status = .suspended;
                    return;
                }
            }
        }
    }

    pub fn wakeOneCondVarWaiter(self: *FiberScheduler, cv_val: Value) void {
        for (self.fibers[0..self.fiber_count]) |f| {
            if (f) |fiber| {
                if (fiber.status == .waiting and fiber.waiting_on == cv_val) {
                    fiber.status = .suspended;
                    return;
                }
            }
        }
    }

    pub fn wakeAllCondVarWaiters(self: *FiberScheduler, cv_val: Value) void {
        for (self.fibers[0..self.fiber_count]) |f| {
            if (f) |fiber| {
                if (fiber.status == .waiting and fiber.waiting_on == cv_val) {
                    fiber.status = .suspended;
                }
            }
        }
    }

    pub fn markRoots(self: *FiberScheduler, gc: *memory.GC) void {
        for (self.fibers[0..self.fiber_count]) |f| {
            if (f) |fiber| {
                gc.markValue(types.makePointer(@ptrCast(fiber)));
                if (fiber.status == .running) continue;
                markFiberState(gc, fiber);
            }
        }
    }
};

pub fn markFiberState(gc: *memory.GC, fiber: *Fiber) void {
    gc.markValue(fiber.thunk);
    gc.markValue(fiber.result);
    gc.markValue(fiber.waiting_on);
    gc.markValue(fiber.name);
    gc.markValue(fiber.specific);

    for (fiber.frames[0..fiber.frame_count]) |f| {
        if (f.closure) |cls| gc.markValue(types.makePointer(@ptrCast(cls)));
        if (f.native) |nf| gc.markValue(types.makePointer(@ptrCast(nf)));
        const window: usize = if (f.closure) |cls| blk: {
            const lc = cls.func.locals_count;
            break :blk if (lc == 0) 256 else @as(usize, lc);
        } else 256;
        const end: usize = @min(@as(usize, f.base) + window, vm_mod.MAX_REGISTERS);
        var r: usize = f.base;
        while (r < end) : (r += 1) gc.markValue(fiber.registers[r]);
    }

    for (fiber.handler_stack[0..fiber.handler_count]) |h| gc.markValue(h.handler);

    for (fiber.wind_stack[0..fiber.wind_count]) |wr| {
        gc.markValue(wr.before);
        gc.markValue(wr.after);
    }

    var pit = fiber.param_overrides.valueIterator();
    while (pit.next()) |v| gc.markValue(v.*);

    if (fiber.current_exception) |exc| gc.markValue(exc);
    gc.markValue(fiber.continuation_value);
}
