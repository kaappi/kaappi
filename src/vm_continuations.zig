const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const MAX_HANDLERS = vm_mod.MAX_HANDLERS;
const MAX_WINDS = vm_mod.MAX_WINDS;

/// Capture the current continuation state.
/// dst_reg is the register offset within the caller's frame where the result of call/cc will go.
/// dst_base is the base register of the caller's frame.
pub fn captureContinuation(vm: *VM, dst_reg: u16, dst_base: u32) VMError!Value {
    // Determine how many registers are actually in use. Each frame's live
    // register window is [base, base + locals_count): locals_count is the
    // compiler-recorded high-water mark of registers the function can touch.
    // Taking the max over all frames gives the exact top of the live register
    // stack, far tighter than the old conservative `base + 256` per frame.
    var max_reg: usize = 0;
    for (vm.frames[0..vm.frame_count]) |f| {
        const window: usize = if (f.closure) |cls| blk: {
            const lc = cls.func.locals_count;
            break :blk if (lc == 0) 256 else lc; // 0 => unknown, stay safe
        } else 256; // native/closure-less frame: conservative fallback
        const frame_end = @as(usize, f.base) + window;
        if (frame_end > max_reg) max_reg = frame_end;
    }
    if (max_reg > vm.registers.len) max_reg = vm.registers.len;
    // At minimum, save up to dst_base + dst_reg + 1
    const min_needed = @as(usize, dst_base) + @as(usize, dst_reg) + 1;
    if (min_needed > max_reg) max_reg = min_needed;

    // Convert frames to SavedFrames (heap-allocated for growable stacks)
    const saved_frames = vm.gc.allocator.alloc(types.SavedFrame, vm.frame_count) catch
        return VMError.OutOfMemory;
    defer vm.gc.allocator.free(saved_frames);
    for (vm.frames[0..vm.frame_count], 0..) |f, i| {
        saved_frames[i] = .{
            .closure = f.closure,
            .native = f.native,
            .code = f.code,
            .ip = f.ip,
            .base = f.base,
            .dst = f.dst,
            .saved_wind_count = f.saved_wind_count,
            .returns_to_native = f.returns_to_native,
            .seq = f.seq,
        };
    }

    // Convert handlers to SavedHandlers
    var saved_handlers: [MAX_HANDLERS]types.SavedHandler = undefined;
    for (vm.handler_stack[0..vm.handler_count], 0..) |h, i| {
        saved_handlers[i] = .{
            .handler = h.handler,
            .frame_count = h.frame_count,
        };
    }

    const cont_val = vm.gc.allocContinuation(
        vm.registers[0..max_reg],
        saved_frames[0..vm.frame_count],
        vm.frame_count,
        saved_handlers[0..vm.handler_count],
        vm.handler_count,
        vm.wind_stack[0..vm.wind_count],
        vm.wind_count,
        dst_reg,
        dst_base,
    ) catch return VMError.OutOfMemory;

    return cont_val;
}

/// Capture an escape continuation (call/ec). Records only the stack depths to
/// unwind back to — no register/frame snapshot — so capture is O(1).
pub fn captureEscape(vm: *VM, dst_reg: u16, dst_base: u32) VMError!Value {
    return vm.gc.allocEscapeContinuation(
        vm.frame_count,
        vm.wind_count,
        vm.handler_count,
        dst_reg,
        dst_base,
    ) catch return VMError.OutOfMemory;
}

/// Invoke an escape continuation: unwind the live stack back to the call/ec
/// point, running any dynamic-wind after-thunks entered since capture, and
/// deliver `value` to the call/ec result register. The caller then returns
/// VMError.ContinuationInvoked to unwind the Zig stack to the dispatch loop.
pub fn invokeEscape(vm: *VM, cont: *types.Continuation, value: Value) VMError!void {
    if (!cont.valid) {
        // Invoked after its call/ec call already returned — no live target.
        var msg = vm.gc.allocString("escape continuation invoked outside its dynamic extent") catch
            return VMError.OutOfMemory;
        try vm.gc.pushRoot(&msg);
        const err = vm.gc.allocErrorObject(msg, types.NIL) catch {
            vm.gc.popRoot();
            return VMError.OutOfMemory;
        };
        vm.gc.popRoot();
        vm.current_exception = err;
        return VMError.ExceptionRaised;
    }

    // Run after-thunks for winds entered since capture (we only go outward, so
    // the common prefix is exactly [0, target_wind_count)).
    var i = vm.wind_count;
    while (i > cont.target_wind_count) {
        i -= 1;
        _ = try vm.callThunk(vm.wind_stack[i].after);
    }
    vm.wind_count = cont.target_wind_count;

    // Discard exception handlers established within the extent.
    if (cont.target_handler_count <= vm.handler_count) {
        vm.handler_count = cont.target_handler_count;
    }

    // Truncate the live stack back to the call/ec point and deliver the value.
    vm.frame_count = cont.target_frame_count;
    const dst_idx = @as(usize, cont.dst_base) + @as(usize, cont.dst_reg);
    if (dst_idx < vm.registers.len) {
        vm.registers[dst_idx] = value;
    }
    vm.continuation_value = value;
}

/// Perform dynamic-wind transition from current wind stack to target wind stack.
/// Calls after thunks for unwinding and before thunks for rewinding.
pub fn performWindTransition(vm: *VM, target_winds: []const types.WindRecord, target_count: usize) VMError!void {
    // Find the common prefix length
    const min_len = @min(vm.wind_count, target_count);
    var common: usize = 0;
    while (common < min_len) {
        // Compare by identity (thunk values)
        if (vm.wind_stack[common].before != target_winds[common].before or
            vm.wind_stack[common].after != target_winds[common].after)
        {
            break;
        }
        common += 1;
    }

    // Unwind: call after thunks from current top down to common.
    // Decrement wind_count before each call so re-entrant wind
    // transitions (from exceptions in after-thunks) don't re-run it.
    while (vm.wind_count > common) {
        vm.wind_count -= 1;
        const after = vm.wind_stack[vm.wind_count].after;
        _ = try vm.callThunk(after);
    }

    // Rewind: call before thunks from common up to target
    var j = common;
    while (j < target_count) {
        const before = target_winds[j].before;
        _ = try vm.callThunk(before);
        if (vm.wind_count >= MAX_WINDS) return VMError.StackOverflow;
        vm.wind_stack[vm.wind_count] = target_winds[j];
        vm.wind_count += 1;
        j += 1;
    }
}

/// Restore a captured continuation, replacing the VM state and placing
/// the given value at the continuation's destination register.
pub fn restoreContinuation(vm: *VM, cont: *types.Continuation, value: Value) VMError!void {
    if (cont.handler_count > MAX_HANDLERS) return VMError.StackOverflow;
    if (cont.wind_count > MAX_WINDS) return VMError.StackOverflow;
    if (cont.frames.len < cont.frame_count) return VMError.InvalidBytecode;
    if (cont.handlers.len < cont.handler_count) return VMError.InvalidBytecode;
    if (cont.wind_records.len < cont.wind_count) return VMError.InvalidBytecode;
    if (cont.is_escape) return VMError.InvalidArgument;

    // Grow VM capacity to fit the captured state
    try vm.ensureRegisterCapacity(cont.registers.len);
    try vm.ensureFrameCapacity(cont.frame_count);

    // Restore saved VM state
    @memcpy(vm.registers[0..cont.registers.len], cont.registers[0..cont.registers.len]);
    for (cont.frames[0..cont.frame_count], 0..) |saved_frame, i| {
        vm.frames[i] = .{
            .closure = saved_frame.closure,
            .native = saved_frame.native,
            .code = saved_frame.code,
            .ip = saved_frame.ip,
            .base = saved_frame.base,
            .dst = saved_frame.dst,
            .saved_wind_count = saved_frame.saved_wind_count,
            .returns_to_native = saved_frame.returns_to_native,
            .seq = saved_frame.seq,
        };
    }
    vm.frame_count = cont.frame_count;

    // Restore handler stack
    for (cont.handlers[0..cont.handler_count], 0..) |saved_handler, i| {
        vm.handler_stack[i] = .{
            .handler = saved_handler.handler,
            .frame_count = saved_handler.frame_count,
        };
    }
    vm.handler_count = cont.handler_count;

    // Restore wind stack
    for (cont.wind_records[0..cont.wind_count], 0..) |wr, i| {
        vm.wind_stack[i] = wr;
    }
    vm.wind_count = cont.wind_count;

    // Clear any pending exception from before the continuation was invoked
    vm.current_exception = null;

    // Place the result value where call/cc was waiting for it
    const dst_idx = @as(usize, cont.dst_base) + @as(usize, cont.dst_reg);
    if (dst_idx >= vm.registers.len) return VMError.StackOverflow;
    vm.registers[dst_idx] = value;
    vm.continuation_value = value;
    vm.continuation_invoked = true;
    vm.continuation_generation +%= 1;
}
