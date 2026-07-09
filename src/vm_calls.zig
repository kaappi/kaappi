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

/// Clear local registers beyond `used` args up to `locals_count` to prevent
/// the GC from scanning stale values left by previously popped frames.
pub fn clearFrameLocals(vm: *VM, base: u32, used: usize, locals_count: u16) void {
    const clear_start = @as(usize, base) + used;
    const clear_end = @min(@as(usize, base) + @as(usize, locals_count), vm.registers.len);
    if (clear_end > clear_start) {
        @memset(vm.registers[clear_start..clear_end], types.UNDEFINED);
    }
}

/// Package continuation arguments the same way `values` does:
/// 1 arg → that arg directly, 0 or 2+ → MultipleValues.
pub fn continuationArgValue(gc: *memory.GC, args: []const Value) VMError!Value {
    if (args.len == 1) return args[0];
    return gc.allocMultipleValues(args) catch return VMError.OutOfMemory;
}

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
    clearFrameLocals(vm, 0, 0, func.locals_count);

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
        // Unwind any pending dynamic-wind after-thunks so that
        // (dynamic-wind before thunk after) calls after even when
        // thunk raises an uncaught exception that escapes execute().
        // Preserve the error detail: after-thunks that make native
        // calls (e.g. display) clear last_error_detail as a side
        // effect, which would lose the real exception message.
        const saved_detail_len = vm.last_error_detail_len;
        var saved_detail: [256]u8 = undefined;
        @memcpy(saved_detail[0..saved_detail_len], vm.last_error_detail[0..saved_detail_len]);
        while (vm.wind_count > 0) {
            vm.wind_count -= 1;
            _ = vm.callThunk(vm.wind_stack[vm.wind_count].after) catch {};
        }
        @memcpy(vm.last_error_detail[0..saved_detail_len], saved_detail[0..saved_detail_len]);
        vm.last_error_detail_len = saved_detail_len;
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

pub fn mapNativeError(vm: *VM, err: anyerror, name: []const u8, args: []const Value) VMError {
    return switch (err) {
        error.TypeError => blk: {
            if (vm.last_error_detail_len == 0) {
                if (args.len > 0) {
                    const p = @import("printer.zig");
                    const s = p.valueToString(vm.gc.allocator, args[0], .write) catch "";
                    defer if (s.len > 0) vm.gc.allocator.free(s);
                    vm.setErrorDetail("type error in '{s}': got {s}", .{ name, s });
                } else {
                    vm.setErrorDetail("type error in '{s}'", .{name});
                }
            }
            break :blk VMError.TypeError;
        },
        error.DivisionByZero => VMError.DivisionByZero,
        error.IndexOutOfBounds => blk_iob: {
            if (vm.last_error_detail_len == 0)
                vm.setErrorDetail("index out of bounds in '{s}'", .{name});
            break :blk_iob VMError.IndexOutOfBounds;
        },
        error.InvalidArgument => blk_ia: {
            if (vm.last_error_detail_len == 0)
                vm.setErrorDetail("invalid argument in '{s}'", .{name});
            break :blk_ia VMError.InvalidArgument;
        },
        error.OutOfMemory => VMError.OutOfMemory,
        error.ExceptionRaised => VMError.ExceptionRaised,
        error.ContinuationInvoked => VMError.ContinuationInvoked,
        error.Yielded => VMError.Yielded,
        error.ArityMismatch => VMError.ArityMismatch,
        error.StackOverflow => VMError.StackOverflow,
        error.UndefinedVariable => VMError.UndefinedVariable,
        error.NotAProcedure => VMError.NotAProcedure,
        error.InvalidBytecode => VMError.InvalidBytecode,
        error.CompileError => VMError.CompileError,
        error.ExecutionTimeout => VMError.ExecutionTimeout,
        error.Terminated => VMError.Terminated,
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
        if (nargs != ffi_fn.param_count) {
            vm.setErrorDetail("'{s}': expected {d} arguments, got {d}", .{ ffi_fn.name, ffi_fn.param_count, nargs });
            return VMError.ArityMismatch;
        }
        const ffi_mod = @import("ffi.zig");
        const result = ffi_mod.callFfi(ffi_fn, vm.registers[base + 1 .. base + 1 + nargs], vm.gc, vm) catch {
            if (vm.last_error_detail_len == 0)
                vm.setErrorDetail("'{s}': unsupported FFI signature", .{ffi_fn.name});
            return VMError.TypeError;
        };
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
        const value = try continuationArgValue(vm.gc, vm.registers[base + 1 .. base + 1 + @as(usize, nargs)]);

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
        const rest_start = func.arity;
        const vm_dispatch = @import("vm_dispatch.zig");
        vm.registers[base + 1 + rest_start] = try vm_dispatch.buildRestList(vm.gc, vm.registers[base + 1 + rest_start .. base + 1 + nargs]);
    }

    try vm.ensureFrameCapacity(vm.frame_count + 1);

    // The callee is in base, args are in base+1..base+nargs
    // New frame's registers start at base (callee reg becomes r0 for the function)
    const new_base = if (base < std.math.maxInt(u32)) base + 1 else return VMError.StackOverflow;
    clearFrameLocals(vm, new_base, if (func.is_variadic) @as(usize, func.arity) + 1 else @as(usize, nargs), func.locals_count);

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
        return mapNativeError(vm, err, native.name, args);
    };

    if (vm.profile_mode) {
        native.profile_time_ns +%= clockNs() -% native_start;
        vm.profile_last_ns = clockNs();
        vm.gc.profile_alloc_target = saved_alloc_target;
    }

    vm.registers[base] = result;
}

fn computeReentrantBase(vm: *VM) u32 {
    if (vm.frame_count > 0) {
        const prev = vm.frames[vm.frame_count - 1];
        const stride: u32 = if (prev.closure) |c|
            @max(16, @as(u16, c.func.locals_count) + 2)
        else
            32;
        return prev.base + stride;
    }
    return 0;
}

fn callReentrant(vm: *VM, closure: *types.Closure, base: u32, dst: u8, returns_to_native: bool) VMError!Value {
    const max_native_depth: u16 = if (@import("builtin").mode == .Debug) 200 else 3000;
    if (vm.native_reentry_depth >= max_native_depth or
        vm.gc.root_count > memory.GC.MAX_ROOT_CAPACITY - 32)
    {
        vm.setErrorDetail("native re-entrancy too deep", .{});
        return VMError.StackOverflow;
    }
    try vm.ensureFrameCapacity(vm.frame_count + 1);

    const func = closure.func;
    const used: usize = if (func.is_variadic) @as(usize, func.arity) + 1 else @as(usize, func.arity);
    clearFrameLocals(vm, base, used, func.locals_count);

    vm.native_reentry_depth += 1;
    defer vm.native_reentry_depth -= 1;

    const saved_frame_count = vm.frame_count;
    const saved_handler_count = vm.handler_count;
    const saved_wind_count = vm.wind_count;
    const saved_cgen = vm.continuation_generation;
    vm.frames[vm.frame_count] = .{
        .closure = closure,
        .code = closure.func.code.items,
        .ip = 0,
        .base = base,
        .dst = dst,
        .returns_to_native = returns_to_native,
        .saved_wind_count = @intCast(vm.wind_count),
        .seq = vm.nextFrameSeq(),
    };
    vm.frame_count += 1;

    return vm.runUntil(saved_frame_count, saved_wind_count) catch |err| {
        if (err == VMError.ContinuationInvoked) {
            if (vm.continuation_generation == saved_cgen and vm.frame_count >= saved_frame_count)
                return vm.continuation_value;
            return err;
        }
        if (vm.continuation_generation == saved_cgen) {
            vm.frame_count = saved_frame_count;
            vm.handler_count = saved_handler_count;
            // Unwind any winds pushed during this re-entrant call by
            // calling their after-thunks (Scheme-level dynamic-wind
            // records from %push-wind). This ensures proper cleanup
            // when exceptions propagate through callReentrant.
            while (vm.wind_count > saved_wind_count) {
                vm.wind_count -= 1;
                _ = vm.callThunk(vm.wind_stack[vm.wind_count].after) catch {};
            }
        }
        return err;
    };
}

pub fn callHandler(vm: *VM, handler_val: Value, arg: Value, return_dst: u8) VMError!Value {
    if (types.isContinuation(handler_val)) {
        const cont = types.toObject(handler_val).as(types.Continuation);
        if (cont.is_escape) {
            try vm_continuations.invokeEscape(vm, cont, arg);
            return VMError.ContinuationInvoked;
        }
        try vm_continuations.performWindTransition(vm, cont.wind_records[0..cont.wind_count], cont.wind_count);
        try vm_continuations.restoreContinuation(vm, cont, arg);
        return VMError.ContinuationInvoked;
    }
    if (types.isClosure(handler_val)) {
        const closure = types.toObject(handler_val).as(types.Closure);
        const func = closure.func;

        const base = computeReentrantBase(vm);
        try vm.ensureRegisterCapacity(@as(usize, base) + @as(usize, func.locals_count) + 1);

        if (func.is_variadic and func.arity == 0) {
            vm.registers[base] = vm.gc.allocPair(arg, types.NIL) catch return VMError.OutOfMemory;
        } else if (func.is_variadic and func.arity == 1) {
            vm.registers[base] = arg;
            vm.registers[base + 1] = types.NIL;
        } else {
            vm.registers[base] = arg;
        }

        return callReentrant(vm, closure, base, return_dst, false);
    } else if (types.isNativeFn(handler_val)) {
        const native = types.toObject(handler_val).as(types.NativeFn);
        const args = [1]Value{arg};
        vm.last_error_detail_len = 0;
        const result = native.func(&args) catch |err| {
            return mapNativeError(vm, err, native.name, &args);
        };
        return result;
    } else {
        vm.setErrorDetail("not a procedure", .{});
        return VMError.NotAProcedure;
    }
}

pub fn callThunk(vm: *VM, thunk_val: Value) VMError!Value {
    if (types.isClosure(thunk_val)) {
        const closure = types.toObject(thunk_val).as(types.Closure);
        const func = closure.func;

        const base = computeReentrantBase(vm);
        try vm.ensureRegisterCapacity(@as(usize, base) + @as(usize, func.locals_count) + 1);

        if (func.is_variadic and func.arity == 0) {
            vm.registers[base] = types.NIL;
        }

        return callReentrant(vm, closure, base, 0, false);
    } else if (types.isNativeFn(thunk_val)) {
        const native = types.toObject(thunk_val).as(types.NativeFn);
        const empty_args: []const Value = &.{};
        const result = native.func(empty_args) catch |err| {
            return mapNativeError(vm, err, native.name, empty_args);
        };
        return result;
    } else {
        return VMError.NotAProcedure;
    }
}

pub fn callWithArgs(vm: *VM, proc: Value, args: []const Value) VMError!Value {
    if (types.isFfiFunction(proc)) {
        const ffi_fn = types.toObject(proc).as(types.FfiFunction);
        if (args.len != ffi_fn.param_count) {
            vm.setErrorDetail("'{s}': expected {d} arguments, got {d}", .{ ffi_fn.name, ffi_fn.param_count, args.len });
            return VMError.ArityMismatch;
        }
        const ffi_mod = @import("ffi.zig");
        return ffi_mod.callFfi(ffi_fn, args, vm.gc, vm) catch {
            if (vm.last_error_detail_len == 0)
                vm.setErrorDetail("'{s}': unsupported FFI signature", .{ffi_fn.name});
            return VMError.TypeError;
        };
    }
    if (types.isParameter(proc)) {
        const param = types.toObject(proc).as(types.ParameterObject);
        if (args.len == 0) {
            return vm.getParameterValue(param);
        } else {
            var new_val = args[0];
            if (param.converter != types.NIL) {
                new_val = try callWithArgs(vm, param.converter, &[_]Value{new_val});
            }
            try vm.setParameterValue(param, new_val);
            return types.VOID;
        }
    }
    if (types.isContinuation(proc)) {
        const cont = types.toObject(proc).as(types.Continuation);
        const value = try continuationArgValue(vm.gc, args);
        if (cont.is_escape) {
            try vm_continuations.invokeEscape(vm, cont, value);
            return VMError.ContinuationInvoked;
        }
        try vm_continuations.performWindTransition(vm, cont.wind_records[0..cont.wind_count], cont.wind_count);
        try vm_continuations.restoreContinuation(vm, cont, value);
        return VMError.ContinuationInvoked;
    }
    if (types.isClosure(proc)) {
        const closure = types.toObject(proc).as(types.Closure);
        const func = closure.func;

        const base = computeReentrantBase(vm);
        try vm.ensureRegisterCapacity(@as(usize, base) + @as(usize, func.locals_count) + 1);

        if (args.len > std.math.maxInt(u8)) return VMError.ArityMismatch;
        const nargs: u8 = @intCast(args.len);
        if (!func.is_variadic) {
            if (nargs != func.arity) return VMError.ArityMismatch;
        } else {
            if (nargs < func.arity) return VMError.ArityMismatch;
            const rest_start = func.arity;
            const vm_dispatch = @import("vm_dispatch.zig");
            const rest_list = try vm_dispatch.buildRestList(vm.gc, args[rest_start..nargs]);
            for (0..rest_start) |ri| {
                vm.registers[base + ri] = args[ri];
            }
            vm.registers[base + rest_start] = rest_list;
        }

        if (!func.is_variadic) {
            for (args, 0..) |a, i| {
                vm.registers[base + i] = a;
            }
        }

        return callReentrant(vm, closure, base, 0, true);
    } else if (types.isNativeClosure(proc)) {
        const nc = types.toObject(proc).as(types.NativeClosure);
        if (args.len != nc.arity) {
            vm.setErrorDetail("'{s}': expected {d} arguments, got {d}", .{ nc.name, nc.arity, args.len });
            return VMError.ArityMismatch;
        }
        const result = nc.fn_ptr(vm, args.ptr, args.len, nc.upvalues.ptr);
        return result;
    } else if (types.isNativeFn(proc)) {
        const native = types.toObject(proc).as(types.NativeFn);
        switch (native.arity) {
            .exact => |expected| {
                if (args.len != expected) {
                    vm.setErrorDetail("'{s}': expected {d} arguments, got {d}", .{ native.name, expected, args.len });
                    return VMError.ArityMismatch;
                }
            },
            .variadic => |min| {
                if (args.len < min) {
                    vm.setErrorDetail("'{s}': expected at least {d} arguments, got {d}", .{ native.name, min, args.len });
                    return VMError.ArityMismatch;
                }
            },
        }
        vm.last_error_detail_len = 0;
        const result = native.func(args) catch |err| {
            return mapNativeError(vm, err, native.name, args);
        };
        return result;
    } else {
        vm.setErrorDetail("not a procedure", .{});
        return VMError.NotAProcedure;
    }
}
