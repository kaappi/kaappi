const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const CallFrame = vm_mod.CallFrame;
const MAX_REGISTERS = vm_mod.MAX_REGISTERS;
const MAX_FRAMES = vm_mod.MAX_FRAMES;

const jit = @import("jit.zig");
const memory = @import("memory.zig");
const vm_continuations = @import("vm_continuations.zig");

pub fn clockNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

pub fn profileCreditSelf(vm: *VM) void {
    const now = clockNs();
    const elapsed = now -% vm.profile_last_ns;
    if (vm.profile_time_depth > 0) {
        if (vm.profile_time_stack[vm.profile_time_depth - 1].func) |f| {
            f.profile_time_ns +%= elapsed;
        }
    }
    vm.profile_last_ns = now;
}

pub fn profilePushCall(vm: *VM, func: *types.Function) void {
    const now = clockNs();
    const elapsed = now -% vm.profile_last_ns;
    if (vm.profile_time_depth > 0) {
        if (vm.profile_time_stack[vm.profile_time_depth - 1].func) |f| {
            f.profile_time_ns +%= elapsed;
        }
    }
    if (vm.profile_time_depth < vm.profile_time_stack.len) {
        vm.profile_time_stack[vm.profile_time_depth] = .{
            .func = func,
            .entry_ns = now,
        };
        vm.profile_time_depth += 1;
    }
    vm.profile_last_ns = now;
    vm.gc.profile_alloc_target = &func.profile_alloc_bytes;
}

pub fn profilePopReturn(vm: *VM) void {
    const now = clockNs();
    const elapsed = now -% vm.profile_last_ns;
    if (vm.profile_time_depth > 0) {
        const entry = &vm.profile_time_stack[vm.profile_time_depth - 1];
        if (entry.func) |f| {
            f.profile_time_ns +%= elapsed;
            f.profile_inclusive_ns +%= now -% entry.entry_ns;
        }
        vm.profile_time_depth -= 1;
    }
    vm.profile_last_ns = now;
    if (vm.profile_time_depth > 0) {
        if (vm.profile_time_stack[vm.profile_time_depth - 1].func) |f| {
            vm.gc.profile_alloc_target = &f.profile_alloc_bytes;
        } else {
            vm.gc.profile_alloc_target = null;
        }
    } else {
        vm.gc.profile_alloc_target = null;
    }
}

pub fn profileTailCall(vm: *VM, new_func: *types.Function) void {
    const now = clockNs();
    const elapsed = now -% vm.profile_last_ns;
    if (vm.profile_time_depth > 0) {
        const entry = &vm.profile_time_stack[vm.profile_time_depth - 1];
        if (entry.func) |f| {
            f.profile_time_ns +%= elapsed;
            f.profile_inclusive_ns +%= now -% entry.entry_ns;
        }
        entry.func = new_func;
        entry.entry_ns = now;
    }
    vm.profile_last_ns = now;
    vm.gc.profile_alloc_target = &new_func.profile_alloc_bytes;
}

pub fn execute(vm: *VM, func: *types.Function) VMError!Value {
    vm_mod.setVMInstance(vm);
    vm.resetExecutionState();

    // Create a top-level closure
    const closure_val = vm.gc.allocClosure(func) catch return VMError.OutOfMemory;
    const closure = types.toObject(closure_val).as(types.Closure);

    // Push initial frame
    vm.frames[0] = .{
        .closure = closure,
        .code = func.code.items,
        .ip = 0,
        .base = 0,
        .dst = 0,
        .saved_wind_count = 0,
    };
    vm.frame_count = 1;

    if (vm.profile_mode) {
        vm.profile_time_depth = 1;
        vm.profile_time_stack[0] = .{ .func = func, .entry_ns = clockNs() };
        vm.profile_last_ns = vm.profile_time_stack[0].entry_ns;
        vm.gc.profile_alloc_target = &func.profile_alloc_bytes;
    }

    const result = run(vm) catch |err| {
        vm.last_stack_trace_len = vm.getStackTrace(&vm.last_stack_trace);
        if (vm.profile_mode) {
            vm.profile_time_depth = 0;
            vm.gc.profile_alloc_target = null;
        }
        vm.resetExecutionState();
        return err;
    };
    if (vm.profile_mode) {
        profileCreditSelf(vm);
        vm.profile_time_depth = 0;
        vm.gc.profile_alloc_target = null;
    }
    vm.last_stack_trace_len = 0;
    vm.resetExecutionState();
    return result;
}

pub fn run(vm: *VM) VMError!Value {
    if (vm.scheduler) |sched| {
        return runWithScheduler(vm, sched);
    }
    return vm.runUntil(0, 0);
}

pub fn runWithScheduler(vm: *VM, sched: *@import("fiber.zig").FiberScheduler) VMError!Value {
    while (true) {
        const result = vm.runUntil(0, 0) catch |err| {
            if (err == VMError.Yielded) {
                const current = sched.fibers[sched.current_idx] orelse return VMError.InvalidBytecode;
                sched.saveCurrentFiber();

                if (current.status == .running) current.status = .suspended;

                if (current.status == .completed or current.status == .errored) {
                    sched.wakeWaiters(current);
                }

                if (sched.schedule()) |next_idx| {
                    sched.switchTo(next_idx);
                    continue;
                }
                if (sched.fibers[0]) |main_fiber| {
                    if (main_fiber.status == .completed) return main_fiber.result;
                    if (main_fiber.status == .waiting) {
                        const target_val = main_fiber.waiting_on;
                        if (types.isFiber(target_val)) {
                            const target = types.toObject(target_val).as(@import("fiber.zig").Fiber);
                            if (target.status == .completed) {
                                main_fiber.result = target.result;
                                main_fiber.status = .suspended;
                                sched.restoreFiber(0);
                                sched.current_idx = 0;
                                vm.current_fiber = main_fiber;
                                main_fiber.status = .running;
                                continue;
                            }
                        }
                    }
                }
                return types.VOID;
            }
            return err;
        };

        const current = sched.fibers[sched.current_idx] orelse return result;
        current.status = .completed;
        current.result = result;
        sched.saveCurrentFiber();
        sched.wakeWaiters(current);

        if (sched.current_idx == 0) return result;

        if (sched.schedule()) |next_idx| {
            sched.switchTo(next_idx);
            continue;
        }
        return result;
    }
}

/// Restore a captured continuation (delegates to vm_continuations).
pub fn restoreContinuation(self: *VM, cont: *types.Continuation, value: Value) VMError!void {
    try vm_continuations.restoreContinuation(self, cont, value);
}

pub fn handleNativeError(_: *VM, err: anyerror, _: u16, _: u8) VMError {
    return switch (err) {
        error.TypeError => VMError.TypeError,
        error.DivisionByZero => VMError.DivisionByZero,
        error.IndexOutOfBounds => VMError.IndexOutOfBounds,
        error.InvalidArgument => VMError.InvalidArgument,
        error.OutOfMemory => VMError.OutOfMemory,
        error.ExceptionRaised => VMError.ExceptionRaised,
        error.ContinuationInvoked => VMError.ContinuationInvoked,
        error.Yielded => VMError.Yielded,
        else => VMError.InvalidBytecode,
    };
}

pub fn callValue(vm: *VM, callee: Value, base: u16, nargs: u8) VMError!void {
    // Check closure first — by far the most common case in Scheme programs
    if (types.isClosure(callee)) {
        return callClosure(vm, types.toObject(callee).as(types.Closure), base, nargs);
    }
    if (types.isNativeFn(callee)) {
        return callNative(vm, types.toObject(callee).as(types.NativeFn), base, nargs);
    }
    if (types.isFfiFunction(callee)) {
        const ffi_fn = types.toObject(callee).as(types.FfiFunction);
        if (nargs != ffi_fn.param_count) return VMError.ArityMismatch;
        const ffi_mod = @import("ffi.zig");
        const result = ffi_mod.callFfi(ffi_fn, vm.registers[base + 1 .. base + 1 + nargs], vm.gc) catch return VMError.TypeError;
        vm.registers[base] = result;
        return;
    }
    if (types.isParameter(callee)) {
        const param = types.toObject(callee).as(types.ParameterObject);
        if (nargs == 0) {
            vm.registers[base] = vm.getParameterValue(param);
        } else {
            var new_val = vm.registers[base + 1];
            if (param.converter != types.NIL) {
                new_val = vm.callWithArgs(param.converter, &[_]Value{new_val}) catch |err| return err;
            }
            try vm.setParameterValue(param, new_val);
            vm.registers[base] = types.VOID;
        }
        return;
    }
    if (types.isContinuation(callee)) {
        const cont = types.toObject(callee).as(types.Continuation);
        // Get the value to pass (0 args => void, 1 arg => that arg)
        const value = if (nargs == 0) types.VOID else vm.registers[base + 1];

        if (cont.is_escape) {
            // Escape continuation: unwind the live stack, no snapshot restore.
            try vm.invokeEscape(cont, value);
            return VMError.ContinuationInvoked;
        }

        // Handle dynamic-wind: unwind current, rewind to saved
        try vm.performWindTransition(cont.wind_records[0..cont.wind_count], cont.wind_count);

        // Restore state and place result
        try vm.restoreContinuation(cont, value);

        // Signal to ALL callers that state was replaced
        return VMError.ContinuationInvoked;
    }
    // Remaining cases handled by the closure/native fast paths above
    vm.setErrorDetail("not a procedure", .{});
    return VMError.NotAProcedure;
}

pub fn callClosure(vm: *VM, closure: *types.Closure, base: u16, nargs: u8) VMError!void {
    const func = closure.func;

    if (base + @as(u16, @max(nargs + 1, func.locals_count)) >= MAX_REGISTERS)
        return VMError.StackOverflow;

    if (!func.is_variadic) {
        if (nargs != func.arity) {
            if (func.name) |name| {
                vm.setErrorDetail("'{s}': expected {d} arguments, got {d}", .{ name, func.arity, nargs });
            } else {
                vm.setErrorDetail("expected {d} arguments, got {d}", .{ func.arity, nargs });
            }
            return VMError.ArityMismatch;
        }
    } else {
        if (nargs < func.arity) {
            if (func.name) |name| {
                vm.setErrorDetail("'{s}': expected at least {d} arguments, got {d}", .{ name, func.arity, nargs });
            } else {
                vm.setErrorDetail("expected at least {d} arguments, got {d}", .{ func.arity, nargs });
            }
            return VMError.ArityMismatch;
        }
        // Collect rest args into a list
        const rest_start = func.arity;
        var rest_list: Value = types.NIL;
        var i: u8 = nargs;
        while (i > rest_start) {
            i -= 1;
            rest_list = vm.gc.allocPair(
                vm.registers[base + 1 + i],
                rest_list,
            ) catch return VMError.OutOfMemory;
        }
        vm.registers[base + 1 + rest_start] = rest_list;
    }

    if (vm.frame_count >= MAX_FRAMES) return VMError.StackOverflow;

    // The callee is in base, args are in base+1..base+nargs
    // New frame's registers start at base (callee reg becomes r0 for the function)
    const new_base = base + 1; // skip the callee register
    vm.frames[vm.frame_count] = .{
        .closure = closure,
        .code = func.code.items,
        .ip = 0,
        .base = new_base,
        .dst = @intCast(base - vm.frames[vm.frame_count - 1].base),
        .saved_wind_count = @intCast(vm.wind_count),
    };
    vm.frame_count += 1;

    if (vm.profile_mode) {
        closure.func.profile_calls += 1;
        profilePushCall(vm, closure.func);
    }

    // Breakpoint check: pause if entering a function with a matching name
    if (vm.debug_mode and vm.breakpoint_count > 0) {
        if (func.name) |fname| {
            for (vm.breakpoints[0..vm.breakpoint_count]) |bp| {
                if (std.mem.eql(u8, bp, fname)) {
                    vm.step_mode = .step;
                    break;
                }
            }
        }
    }

    // JIT: compile hot functions, execute via native code
    if (!vm.debug_mode and !vm.jit_disabled) {
        func.call_count +%= 1;
        if (func.jit_code == null and func.call_count == jit.JIT_THRESHOLD) {
            jit.tryCompile(func, vm);
        }
        if (func.jit_code) |jit_code| {
            const entry: jit.JitEntryFn = @ptrCast(@alignCast(jit_code.entry));
            const result = entry(vm, new_base, func.constants.items.ptr, closure);
            if (vm.jit_error) |err| {
                vm.jit_error = null;
                return err;
            }
            if (result > 0 and result != 0xFFFFFFFF) {
                vm.frames[vm.frame_count - 1].ip = @intCast(result - 1);
            }
            return;
        }
    }
}

pub fn callNative(vm: *VM, native: *types.NativeFn, base: u16, nargs: u8) VMError!void {
    if (vm.profile_mode) {
        native.profile_calls += 1;
    }

    if (base + @as(u16, nargs) + 1 >= MAX_REGISTERS)
        return VMError.StackOverflow;

    switch (native.arity) {
        .exact => |expected| {
            if (nargs != expected) {
                vm.setErrorDetail("'{s}': expected {d} arguments, got {d}", .{ native.name, expected, nargs });
                return VMError.ArityMismatch;
            }
        },
        .variadic => |min| {
            if (nargs < min) {
                vm.setErrorDetail("'{s}': expected at least {d} arguments, got {d}", .{ native.name, min, nargs });
                return VMError.ArityMismatch;
            }
        },
    }

    const saved_alloc_target = vm.gc.profile_alloc_target;
    if (vm.profile_mode) {
        profileCreditSelf(vm);
        vm.gc.profile_alloc_target = &native.profile_alloc_bytes;
    }

    const args = vm.registers[base + 1 .. base + 1 + nargs];
    vm.last_error_detail_len = 0;

    const native_start = if (vm.profile_mode) clockNs() else 0;

    const result = native.func(args) catch |err| {
        if (vm.profile_mode) {
            native.profile_time_ns +%= clockNs() -% native_start;
            vm.profile_last_ns = clockNs();
            vm.gc.profile_alloc_target = saved_alloc_target;
        }
        return switch (err) {
            error.TypeError => blk: {
                if (vm.last_error_detail_len == 0) {
                    if (args.len > 0) {
                        const p = @import("printer.zig");
                        const s = p.valueToString(vm.gc.allocator, args[0], .write) catch "";
                        defer if (s.len > 0) vm.gc.allocator.free(s);
                        vm.setErrorDetail("type error in '{s}': got {s}", .{ native.name, s });
                    } else {
                        vm.setErrorDetail("type error in '{s}'", .{native.name});
                    }
                }
                break :blk VMError.TypeError;
            },
            error.DivisionByZero => VMError.DivisionByZero,
            error.IndexOutOfBounds => blk_iob: {
                if (vm.last_error_detail_len == 0)
                    vm.setErrorDetail("index out of bounds in '{s}'", .{native.name});
                break :blk_iob VMError.IndexOutOfBounds;
            },
            error.InvalidArgument => blk_ia: {
                if (vm.last_error_detail_len == 0)
                    vm.setErrorDetail("invalid argument in '{s}'", .{native.name});
                break :blk_ia VMError.InvalidArgument;
            },
            error.OutOfMemory => VMError.OutOfMemory,
            error.ExceptionRaised => VMError.ExceptionRaised,
            error.ContinuationInvoked => VMError.ContinuationInvoked,
            error.Yielded => VMError.Yielded,
            else => VMError.InvalidBytecode,
        };
    };

    if (vm.profile_mode) {
        native.profile_time_ns +%= clockNs() -% native_start;
        vm.profile_last_ns = clockNs();
        vm.gc.profile_alloc_target = saved_alloc_target;
    }

    vm.registers[base] = result;
}
