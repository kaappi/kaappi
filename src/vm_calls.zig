const std = @import("std");
const platform = @import("platform.zig");
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

/// Invoke a SRFI-254 guardian, which is itself a procedure. Zero arguments
/// removes and returns a resurrected element (or #f); the register forms add an
/// element. An object guardian takes `(g obj [rep])` and returns an unspecified
/// value; a transport cell guardian takes `(tg key value)`, wraps them in a
/// fresh transport cell it registers, and returns that cell. The result is a
/// plain value — no frame is pushed — so every call-dispatch site handles a
/// guardian the same way it handles a parameter.
pub fn invokeGuardian(vm: *VM, guardian: Value, args: []const Value) VMError!Value {
    // Root the guardian across the transport-cell allocation below: on the
    // callWithArgs path it may be held only in a Zig local.
    var self_val = guardian;
    vm.gc.pushRoot(&self_val);
    defer vm.gc.popRoot();

    // `registered`/`ready` are raw Zig ArrayLists owned by the heap that
    // allocated the guardian, and `vm.gc` below is the *calling* thread's GC.
    // gc_deep_copy.zig refuses the `.guardian` tag, so a guardian reaches
    // another thread only through the globals route (a top-level binding,
    // shared by pointer) -- where, without this check, a child thread grows
    // the parent's list with the child's own allocator and no lock at all
    // (#2008: a deterministic abort with empty stdout and stderr), and
    // registers child-heap objects the parent's collector later reads out of
    // the freed child arena. Mirrors primitives_srfi18.checkThreadOwner and
    // the channel checks in primitives_fiber.zig, and covers both the
    // register and the retrieve path; `guardian?` stays a total predicate.
    if (types.toObject(self_val).owner != vm.gc.id) {
        vm.setErrorDetail("guardian belongs to another thread; a guardian may only be used by the thread that created it", .{});
        return VMError.InvalidArgument;
    }

    const g = types.toGuardian(self_val);

    if (args.len == 0) {
        // Retrieve. A transport cell guardian never resurrects on this
        // non-moving collector, so its ready queue stays empty and this
        // returns #f.
        if (g.ready.items.len == 0) return types.FALSE;
        const e = g.ready.orderedRemove(0);
        return if (g.is_transport) e.watched else e.payload;
    }

    if (g.is_transport) {
        if (args.len != 2) {
            vm.setErrorDetail("transport cell guardian: expected 2 arguments (key value), got {d}", .{args.len});
            return VMError.ArityMismatch;
        }
        const cell = vm.gc.allocTransportCell(args[0], args[1]) catch return VMError.OutOfMemory;
        g.registered.append(vm.gc.allocator, .{ .watched = cell, .payload = types.NIL }) catch return VMError.OutOfMemory;
        return cell;
    }

    if (args.len > 2) {
        vm.setErrorDetail("guardian: expected 1 or 2 arguments, got {d}", .{args.len});
        return VMError.ArityMismatch;
    }
    const obj = args[0];
    const rep = if (args.len == 2) args[1] else obj;
    if (obj == types.FALSE or rep == types.FALSE) {
        vm.setErrorDetail("guardian: guarded object and representative must not be #f", .{});
        return VMError.InvalidArgument;
    }
    g.registered.append(vm.gc.allocator, .{ .watched = obj, .payload = rep }) catch return VMError.OutOfMemory;
    return types.VOID;
}

/// Package continuation arguments the same way `values` does:
/// 1 arg → that arg directly, 0 or 2+ → MultipleValues.
pub fn continuationArgValue(gc: *memory.GC, args: []const Value) VMError!Value {
    if (args.len == 1) return args[0];
    return gc.allocMultipleValues(args) catch return VMError.OutOfMemory;
}

pub fn clockNs() u64 {
    return platform.monotonicNs();
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
    // Runtime half of the #1855 boundary reset. The `run` error branch below
    // truncates explicitly rather than relying on this errdefer, because that
    // branch runs pending dynamic-wind after-thunks *before* returning: those
    // allocate, so a root leaked deep in the failed run — `fiber.zig`'s spawn
    // path pushes a root around a bare `try`, the runtime code with this
    // shape — would otherwise still be live when they collect. The errdefer
    // covers the other error returns out of this function.
    const root_depth = vm.gc.root_count;
    errdefer vm.gc.truncateRoots(root_depth);
    vm.resetExecutionState();
    // Clear the diagnostic code at entry (not in resetExecutionState, which also
    // runs on the error-exit path *after* noteUncaughtException has recorded the
    // escaping error's code — see the last_error_detail save/restore there).
    vm.last_error_code = .uncategorized;
    vm.last_error_suggestion = null;

    // Each top-level form starts on the main fiber. A previous form may have
    // left the scheduler positioned on a spawned fiber, or the main fiber
    // marked .completed (set when its form finished); both are per-form
    // states that must not leak into the next form.
    if (vm.scheduler) |sched| {
        if (sched.fibers.items[0]) |main_fiber| {
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
        vm.gc.truncateRoots(root_depth);
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
                if (try scheduleNextAfterYield(vm, sched)) {
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
                if (try scheduleNextAfterYield(vm, sched)) continue;
                return mainFiberResult(sched);
            }
            return err;
        };

        const current = sched.fibers.items[sched.current_idx] orelse return result;
        sched.retireSlot(current, .completed);
        current.result = result;
        vm.gc.writeBarrier(&current.header, result);
        try sched.saveCurrentFiber();
        sched.wakeWaiters(current);

        if (sched.current_idx == 0) return result;

        if (sched.schedule()) |next_idx| {
            try sched.switchTo(next_idx);
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
fn scheduleNextAfterYield(vm: *VM, sched: *fiber_mod.FiberScheduler) VMError!bool {
    const current = sched.fibers.items[sched.current_idx] orelse return false;
    try sched.saveCurrentFiber();

    if (current.status == .running) {
        current.status = .suspended;
        sched.markRunnable(current);
    }

    if (current.status == .completed or current.status == .errored) {
        sched.wakeWaiters(current);
    }

    if (sched.schedule()) |next_idx| {
        try sched.switchTo(next_idx);
        return true;
    }
    if (sched.fibers.items[0]) |main_fiber| {
        if (main_fiber.status == .waiting) {
            const target_val = main_fiber.waiting_on;
            if (types.isFiber(target_val)) {
                const target = types.toObject(target_val).as(fiber_mod.Fiber);
                if (target.status == .completed) {
                    main_fiber.result = target.result;
                    try sched.restoreFiber(0);
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
    if (sched.fibers.items[0]) |main_fiber| {
        if (main_fiber.status == .completed) return main_fiber.result;
    }
    return types.VOID;
}

/// `mapNativeError`'s counterpart for `ffi.callFfi`, which reports through an
/// inline `error{TypeError}` set of its own rather than the VM's.
///
/// `callFfi` guarantees a detail on every path it can currently fail through
/// (`validateArgsDetailed` covers every user-reachable argument problem, and
/// `callFfi` has this same fallback at its own exit), so the fallback here is
/// unreachable today. It exists because the four call sites did not used to
/// agree: the two in this file had it and the two hot ones in
/// `vm_dispatch.zig` did not, so a future `callFfi` failure that forgot a
/// detail would have reported usefully or not at all depending on which opcode
/// dispatched the call (kaappi#1880). One shared mapper is cheaper than
/// separate copies of the same guard staying in sync.
///
/// The four sites are callValue and callWithArgs here, and the tail-call and
/// tail-apply opcodes in `vm_dispatch.zig`. Note that a *non*-tail call
/// reaches neither of the latter two, which is why
/// `tests/scheme/ffi/error-messages.scm` covers them with tail-position forms.
pub fn mapFfiError(vm: *VM, err: anyerror, ffi_fn: *types.FfiFunction) VMError {
    if (err == error.ExceptionRaised) return VMError.ExceptionRaised;
    if (vm.last_error_detail_len == 0)
        vm.setErrorDetail("'{s}': unsupported FFI signature", .{ffi_fn.name});
    return VMError.TypeError; // bare-ok: this is mapFfiError itself
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

/// Invoke a natively-compiled closure (LLVM backend). The emitted function
/// reads its parameters lazily from the args pointer and may re-enter the
/// VM, which can grow (realloc) vm.registers — so the pointer handed to it
/// must not alias the register file. Copy args into a stack buffer; the
/// originals stay reachable through the caller's storage (registers or
/// rooted buffers), so the copies need no GC roots of their own.
pub fn callNativeClosure(vm: *VM, nc: *types.NativeClosure, args: []const Value) VMError!Value {
    if (args.len != nc.arity) {
        vm.setErrorDetail("'{s}': expected {d} arguments, got {d}", .{ nc.name, nc.arity, args.len });
        return VMError.ArityMismatch;
    }
    var buf: [256]Value = undefined;
    @memcpy(buf[0..args.len], args);
    return nc.fn_ptr(vm, &buf, args.len, nc.upvalues.ptr);
}

pub fn callValue(vm: *VM, callee: Value, base: u32, nargs: u8) VMError!void {
    // Check closure first — by far the most common case in Scheme programs
    if (types.isClosure(callee)) {
        return callClosure(vm, types.toObject(callee).as(types.Closure), base, nargs);
    }
    if (types.isNativeFn(callee)) {
        return callNative(vm, types.toObject(callee).as(types.NativeFn), base, nargs);
    }
    if (types.isNativeClosure(callee)) {
        const nc = types.toObject(callee).as(types.NativeClosure);
        if (@as(usize, base) + @as(usize, nargs) + 1 > vm.registers.len)
            return VMError.StackOverflow;
        const result = try callNativeClosure(vm, nc, vm.registers[base + 1 .. base + 1 + nargs]);
        vm.registers[base] = result;
        return;
    }
    if (types.isFfiFunction(callee)) {
        const ffi_fn = types.toObject(callee).as(types.FfiFunction);
        if (nargs != ffi_fn.param_count) {
            vm.setErrorDetail("'{s}': expected {d} arguments, got {d}", .{ ffi_fn.name, ffi_fn.param_count, nargs });
            return VMError.ArityMismatch;
        }
        const ffi_mod = @import("ffi.zig");
        const result = ffi_mod.callFfi(ffi_fn, vm.registers[base + 1 .. base + 1 + nargs], vm.gc, vm) catch |err|
            return mapFfiError(vm, err, ffi_fn);
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
    if (types.isGuardian(callee)) {
        vm.registers[base] = try invokeGuardian(vm, callee, vm.registers[base + 1 .. base + 1 + @as(usize, nargs)]);
        return;
    }
    if (types.isContinuation(callee)) {
        const cont = types.toObject(callee).as(types.Continuation);
        try vm_continuations.checkContinuationOwner(vm, cont);
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

    // nargs is a u8 and 255 is a legal argument count (the ISA's maximum),
    // so the +1 must not happen in u8 arithmetic (#2185).
    try vm.ensureRegisterCapacity(@as(usize, base) + @max(@as(usize, nargs) + 1, func.locals_count) + 1);

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

/// Validate `nargs` against a native procedure's declared arity.
///
/// A `NativeFn` body indexes `args[0]`, `args[1]`, … without bounds checks of
/// its own, because the VM is expected to have validated arity before the call.
/// Every site that hands one an argument slice therefore has to run this — and
/// the two re-entrancy helpers did not, so a wrong-arity *native* handler or
/// thunk read past the end of a fixed-size argument array. Under the default
/// ReleaseSafe build that is a panic, i.e. a process abort out of ordinary
/// Scheme (`(call-with-values cons list)` was enough), not the catchable
/// ArityMismatch the closure path produces.
fn checkNativeArity(vm: *VM, native: *types.NativeFn, nargs: usize) VMError!void {
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
}

pub fn callNative(vm: *VM, native: *types.NativeFn, base: u32, nargs: u8) VMError!void {
    if (vm.profile_mode) {
        native.profile_calls += 1;
    }

    if (@as(usize, base) + @as(usize, nargs) + 1 > vm.registers.len)
        return VMError.StackOverflow;

    try checkNativeArity(vm, native, nargs);

    const saved_alloc_target = vm.gc.profile_alloc_target;
    if (vm.profile_mode) {
        profileCreditSelf(vm);
        vm.gc.profile_alloc_target = &native.profile_alloc_bytes;
    }

    const args = vm.registers[base + 1 .. base + 1 + nargs];
    vm.last_error_detail_len = 0;
    // SRFI 248: a regular (non-tail) call — clear the tail latch so
    // raise/raise-continuable does not misreport an empty continuation.
    vm.native_call_was_tail = false;

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

/// Bind `args` into the parameter registers of a hand-built frame at `base`,
/// validating arity exactly as `callClosure` does for the `call` opcode and
/// folding surplus arguments into a variadic callee's rest list.
///
/// This lives on the `callReentrant` path rather than in each of its callers
/// because a caller that stages its own arguments is a caller that can forget
/// the check — and two of the three did. `callHandler` and `callThunk` wrote
/// their argument straight into the register file and jumped to
/// `callReentrant`, so a wrong-arity exception handler, `with-exception-handler`
/// thunk, `call-with-values` producer or non-tail `call/cc` receiver ran
/// anyway, with its surplus parameters reading whatever the register file
/// happened to hold — including live values from a neighbouring frame (#2034).
fn bindReentrantArgs(vm: *VM, func: *types.Function, base: u32, args: []const Value) VMError!void {
    if (!func.is_variadic) {
        if (args.len != func.arity) {
            if (func.name) |name| {
                vm.setErrorDetail("'{s}': expected {d} arguments, got {d}", .{ name, func.arity, args.len });
            } else {
                vm.setErrorDetail("expected {d} arguments, got {d}", .{ func.arity, args.len });
            }
            return VMError.ArityMismatch;
        }
        for (args, 0..) |a, i| vm.registers[base + i] = a;
        return;
    }

    if (args.len < func.arity) {
        if (func.name) |name| {
            vm.setErrorDetail("'{s}': expected at least {d} arguments, got {d}", .{ name, func.arity, args.len });
        } else {
            vm.setErrorDetail("expected at least {d} arguments, got {d}", .{ func.arity, args.len });
        }
        return VMError.ArityMismatch;
    }

    // Build the rest list from the caller's own `args` before writing any
    // register: `base` sits past the topmost frame's marking window, so a
    // value staged there is not yet a GC root (markVMRoots walks
    // [f.base, f.base + frameWindow) per live frame). Nothing allocates
    // between the build and the stores below, so `rest` needs no root.
    const vm_dispatch = @import("vm_dispatch.zig");
    const rest = try vm_dispatch.buildRestList(vm.gc, args[func.arity..]);
    for (args[0..func.arity], 0..) |a, i| vm.registers[base + i] = a;
    vm.registers[base + func.arity] = rest;
}

fn callReentrant(vm: *VM, closure: *types.Closure, base: u32, args: []const Value, dst: u8, returns_to_native: bool) VMError!Value {
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
    // Room for the callee's locals *and* for every slot bindReentrantArgs is
    // about to write. The compiler counts a variadic rest parameter among the
    // locals, so `used` is normally the smaller of the two — but a register
    // write past the end of the file is memory unsafety, so derive the bound
    // from what is actually written rather than trusting that.
    try vm.ensureRegisterCapacity(@as(usize, base) + @max(@as(usize, func.locals_count), used) + 1);
    try bindReentrantArgs(vm, func, base, args);

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
            // Preserve error detail: after-thunks that make native
            // calls (e.g. display) clear last_error_detail.
            const saved_detail_len = vm.last_error_detail_len;
            var saved_detail: [256]u8 = undefined;
            @memcpy(saved_detail[0..saved_detail_len], vm.last_error_detail[0..saved_detail_len]);
            while (vm.wind_count > saved_wind_count) {
                vm.wind_count -= 1;
                _ = vm.callThunk(vm.wind_stack[vm.wind_count].after) catch {};
            }
            @memcpy(vm.last_error_detail[0..saved_detail_len], saved_detail[0..saved_detail_len]);
            vm.last_error_detail_len = saved_detail_len;
        }
        return err;
    };
}

pub fn callHandler(vm: *VM, handler_val: Value, arg: Value, return_dst: u8) VMError!Value {
    if (types.isContinuation(handler_val)) {
        const cont = types.toObject(handler_val).as(types.Continuation);
        try vm_continuations.checkContinuationOwner(vm, cont);
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
        return callReentrant(vm, closure, computeReentrantBase(vm), &[_]Value{arg}, return_dst, false);
    } else if (types.isNativeFn(handler_val)) {
        const native = types.toObject(handler_val).as(types.NativeFn);
        try checkNativeArity(vm, native, 1);
        const args = [1]Value{arg};
        vm.last_error_detail_len = 0;
        vm.native_call_was_tail = false; // SRFI 248: re-entrant, not a tail call
        const result = native.func(&args) catch |err| {
            return mapNativeError(vm, err, native.name, &args);
        };
        return result;
    } else if (types.isNativeClosure(handler_val)) {
        const nc = types.toObject(handler_val).as(types.NativeClosure);
        return callNativeClosure(vm, nc, &[_]Value{arg});
    } else {
        vm.setErrorDetail("not a procedure", .{});
        return VMError.NotAProcedure;
    }
}

pub fn callThunk(vm: *VM, thunk_val: Value) VMError!Value {
    if (types.isClosure(thunk_val)) {
        const closure = types.toObject(thunk_val).as(types.Closure);
        return callReentrant(vm, closure, computeReentrantBase(vm), &.{}, 0, false);
    } else if (types.isNativeFn(thunk_val)) {
        const native = types.toObject(thunk_val).as(types.NativeFn);
        try checkNativeArity(vm, native, 0);
        const empty_args: []const Value = &.{};
        vm.native_call_was_tail = false; // SRFI 248: re-entrant, not a tail call
        const result = native.func(empty_args) catch |err| {
            return mapNativeError(vm, err, native.name, empty_args);
        };
        return result;
    } else if (types.isNativeClosure(thunk_val)) {
        const nc = types.toObject(thunk_val).as(types.NativeClosure);
        return callNativeClosure(vm, nc, &.{});
    } else {
        return VMError.NotAProcedure;
    }
}

pub fn callWithArgs(vm: *VM, proc: Value, args: []const Value) VMError!Value {
    vm.native_call_was_tail = false; // SRFI 248: apply-style call, not a tail call
    if (types.isFfiFunction(proc)) {
        const ffi_fn = types.toObject(proc).as(types.FfiFunction);
        if (args.len != ffi_fn.param_count) {
            vm.setErrorDetail("'{s}': expected {d} arguments, got {d}", .{ ffi_fn.name, ffi_fn.param_count, args.len });
            return VMError.ArityMismatch;
        }
        const ffi_mod = @import("ffi.zig");
        return ffi_mod.callFfi(ffi_fn, args, vm.gc, vm) catch |err|
            return mapFfiError(vm, err, ffi_fn);
    }
    // #1933: everything below runs bytecode (a closure via callReentrant, a
    // continuation resume, a converter/callback re-entry), so a collecting
    // parent must see `.running` and wait for a safepoint instead of marking
    // mid-execution. The one case that needs the save/restore is entering
    // from a `.in_native` FFI call (an ffi-callback trampoline); the common
    // case is already `.running` and costs a single atomic load on child
    // VMs only (the root VM, owns_globals, never reports a state). Both the
    // flip to `.running` and the restore go through the guarded helpers, so
    // a callback cannot start bytecode during a mark (setCollectionRunning
    // spins on collection_stop first) and the restore cannot race one either.
    const saved_state: ?vm_mod.CollectionState = if (!vm.owns_globals and vm.collection_state.load(.monotonic) != .running)
        vm.collection_state.load(.monotonic)
    else
        null;
    if (saved_state != null) vm.setCollectionRunning();
    defer if (saved_state) |s| vm.setCollectionState(s);
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
    if (types.isGuardian(proc)) {
        return invokeGuardian(vm, proc, args);
    }
    if (types.isContinuation(proc)) {
        const cont = types.toObject(proc).as(types.Continuation);
        try vm_continuations.checkContinuationOwner(vm, cont);
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
        // 255 arguments is the ISA's maximum, so a longer call cannot be
        // expressed as a frame at all; arity itself is bindReentrantArgs's.
        if (args.len > std.math.maxInt(u8)) {
            vm.setErrorDetail("too many arguments: {d} (maximum {d})", .{ args.len, std.math.maxInt(u8) });
            return VMError.ArityMismatch;
        }
        return callReentrant(vm, closure, computeReentrantBase(vm), args, 0, true);
    } else if (types.isNativeClosure(proc)) {
        const nc = types.toObject(proc).as(types.NativeClosure);
        return callNativeClosure(vm, nc, args);
    } else if (types.isNativeFn(proc)) {
        const native = types.toObject(proc).as(types.NativeFn);
        try checkNativeArity(vm, native, args.len);
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
