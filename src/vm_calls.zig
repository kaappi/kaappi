const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const CallFrame = vm_mod.CallFrame;

const memory = @import("memory.zig");
const vm_continuations = @import("vm_continuations.zig");
const fiber_mod = @import("fiber.zig");

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

    // Each top-level form starts on the main fiber. A previous form may have
    // left the scheduler positioned on a spawned fiber, or the main fiber
    // marked .completed (set when its form finished); both are per-form
    // states that must not leak into the next form.
    if (vm.scheduler) |sched| {
        if (sched.fibers[0]) |main_fiber| {
            sched.current_idx = 0;
            main_fiber.status = .running;
            vm.current_fiber = main_fiber;
        }
    }

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
        .seq = vm.nextFrameSeq(),
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
        vm.noteUncaughtException(err);
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
    return vm.runUntil(0, 0) catch |err| {
        if (err == VMError.Yielded) {
            // A fiber primitive (spawn, mutex-lock!, ...) created the
            // scheduler during this run and the main fiber then yielded.
            // Route the yield through the scheduler instead of aborting
            // the top-level form.
            if (vm.scheduler) |sched| {
                if (scheduleNextAfterYield(vm, sched)) {
                    return runWithScheduler(vm, sched);
                }
                return mainFiberResult(sched);
            }
        }
        return err;
    };
}

pub fn runWithScheduler(vm: *VM, sched: *fiber_mod.FiberScheduler) VMError!Value {
    while (true) {
        // Fibers dispatched here (after the main fiber yields) may park
        // themselves on an empty channel via the yield_retry protocol. A
        // dangling yield_retry (a forwarding native converted a park's
        // Yielded into another error) must not survive into this run.
        vm.yield_retry = false;
        vm.sched_dispatch_pending = true;
        const result = vm.runUntil(0, 0) catch |err| {
            if (err == VMError.Yielded) {
                if (scheduleNextAfterYield(vm, sched)) continue;
                return mainFiberResult(sched);
            }
            return err;
        };

        const current = sched.fibers[sched.current_idx] orelse return result;
        current.status = .completed;
        current.result = result;
        vm.gc.writeBarrier(&current.header, result);
        sched.saveCurrentFiber();
        sched.wakeWaiters(current);

        if (sched.current_idx == 0) return result;

        if (sched.schedule()) |next_idx| {
            sched.switchTo(next_idx);
            continue;
        }
        // No runnable fibers remain and the last runUntil unwound out of a
        // spawned fiber, not the main one. The main fiber's top-level form
        // completed earlier inside a nested scheduler loop (a blocked
        // fiber's native primitive resumes other fibers via runUntil), so
        // its saved result — not this fiber's thunk result — is the value
        // of the top-level form.
        return mainFiberResult(sched);
    }
}

/// Handle a yield: save the current fiber and switch to the next runnable
/// one, or resume a main fiber whose join target completed. Returns false
/// when nothing can be scheduled; the caller should then finish the
/// top-level form with mainFiberResult().
fn scheduleNextAfterYield(vm: *VM, sched: *fiber_mod.FiberScheduler) bool {
    const current = sched.fibers[sched.current_idx] orelse return false;
    sched.saveCurrentFiber();

    if (current.status == .running) current.status = .suspended;

    if (current.status == .completed or current.status == .errored) {
        sched.wakeWaiters(current);
    }

    if (sched.schedule()) |next_idx| {
        sched.switchTo(next_idx);
        return true;
    }
    if (sched.fibers[0]) |main_fiber| {
        if (main_fiber.status == .waiting) {
            const target_val = main_fiber.waiting_on;
            if (types.isFiber(target_val)) {
                const target = types.toObject(target_val).as(fiber_mod.Fiber);
                if (target.status == .completed) {
                    main_fiber.result = target.result;
                    sched.restoreFiber(0);
                    sched.current_idx = 0;
                    vm.current_fiber = main_fiber;
                    main_fiber.status = .running;
                    return true;
                }
            }
        }
    }
    return false;
}

/// Value of the top-level form once no fiber can run: the main fiber's
/// result if its form completed (possibly inside a nested scheduler loop),
/// VOID otherwise (deadlock — every fiber is blocked).
fn mainFiberResult(sched: *fiber_mod.FiberScheduler) Value {
    if (sched.fibers[0]) |main_fiber| {
        if (main_fiber.status == .completed) return main_fiber.result;
    }
    return types.VOID;
}

/// Restore a captured continuation (delegates to vm_continuations).
pub fn restoreContinuation(self: *VM, cont: *types.Continuation, value: Value) VMError!void {
    try vm_continuations.restoreContinuation(self, cont, value);
}

pub fn handleNativeError(_: *VM, err: anyerror, _: u32, _: u8) VMError {
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

pub fn callValue(vm: *VM, callee: Value, base: u32, nargs: u8) VMError!void {
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

pub fn callClosure(vm: *VM, closure: *types.Closure, base: u32, nargs: u8) VMError!void {
    const func = closure.func;

    try vm.ensureRegisterCapacity(@as(usize, base) + @as(usize, @max(nargs + 1, func.locals_count)) + 1);

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
        vm.gc.pushRoot(&rest_list) catch return VMError.OutOfMemory;
        var i: u8 = nargs;
        while (i > rest_start) {
            i -= 1;
            rest_list = vm.gc.allocPair(
                vm.registers[base + 1 + i],
                rest_list,
            ) catch {
                vm.gc.popRoot();
                return VMError.OutOfMemory;
            };
        }
        vm.gc.popRoot();
        vm.registers[base + 1 + rest_start] = rest_list;
    }

    try vm.ensureFrameCapacity(vm.frame_count + 1);

    // The callee is in base, args are in base+1..base+nargs
    // New frame's registers start at base (callee reg becomes r0 for the function)
    const new_base = if (base < std.math.maxInt(u32)) base + 1 else return VMError.StackOverflow;
    vm.frames[vm.frame_count] = .{
        .closure = closure,
        .code = func.code.items,
        .ip = 0,
        .base = new_base,
        .dst = @intCast(base - vm.frames[vm.frame_count - 1].base),
        .saved_wind_count = @intCast(vm.wind_count),
        .seq = vm.nextFrameSeq(),
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
                if (std.mem.eql(u8, bp.name, fname)) {
                    if (bp.condition) |cond| {
                        const reader_mod = @import("reader.zig");
                        var r = reader_mod.Reader.init(vm.gc, cond);
                        defer r.deinit();
                        const expr = r.readDatum() catch {
                            vm.step_mode = .step;
                            break;
                        };
                        const compiler = @import("compiler.zig");
                        const cond_func = compiler.compileExpression(vm.gc, expr) catch {
                            vm.step_mode = .step;
                            break;
                        };
                        const saved_fc = vm.frame_count;
                        const saved_hc = vm.handler_count;
                        const saved_wc = vm.wind_count;
                        const result = vm.execute(cond_func) catch {
                            vm.frame_count = saved_fc;
                            vm.handler_count = saved_hc;
                            vm.wind_count = saved_wc;
                            vm.step_mode = .step;
                            break;
                        };
                        vm.frame_count = saved_fc;
                        vm.handler_count = saved_hc;
                        vm.wind_count = saved_wc;
                        if (result != types.FALSE) {
                            vm.step_mode = .step;
                        }
                    } else {
                        vm.step_mode = .step;
                    }
                    break;
                }
            }
        }
    }
}

pub fn callNative(vm: *VM, native: *types.NativeFn, base: u32, nargs: u8) VMError!void {
    if (vm.profile_mode) {
        native.profile_calls += 1;
    }

    if (@as(usize, base) + @as(usize, nargs) + 1 > vm.registers.len)
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
