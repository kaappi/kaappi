const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const MAX_FRAMES = vm_mod.MAX_FRAMES;
const MAX_HANDLERS = vm_mod.MAX_HANDLERS;
const MAX_REGISTERS = vm_mod.MAX_REGISTERS;
const MAX_WINDS = vm_mod.MAX_WINDS;

/// Capture the current continuation state.
/// dst_reg is the register offset within the caller's frame where the result of call/cc will go.
/// dst_base is the base register of the caller's frame.
pub fn captureContinuation(vm: *VM, dst_reg: u8, dst_base: u16) VMError!Value {
    // Determine how many registers are actually in use
    var max_reg: usize = 0;
    for (vm.frames[0..vm.frame_count]) |f| {
        const frame_end = @as(usize, f.base) + 256; // conservative upper bound
        if (frame_end > max_reg) max_reg = frame_end;
    }
    if (max_reg > MAX_REGISTERS) max_reg = MAX_REGISTERS;
    // At minimum, save up to dst_base + dst_reg + 1
    const min_needed = @as(usize, dst_base) + @as(usize, dst_reg) + 1;
    if (min_needed > max_reg) max_reg = min_needed;

    // Convert frames to SavedFrames
    var saved_frames: [MAX_FRAMES]types.SavedFrame = undefined;
    for (vm.frames[0..vm.frame_count], 0..) |f, i| {
        saved_frames[i] = .{
            .closure = f.closure,
            .native = f.native,
            .code = f.code,
            .ip = f.ip,
            .base = f.base,
            .dst = f.dst,
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

/// Call a procedure with the current continuation (call/cc).
/// proc is the one-argument procedure to call with the continuation.
/// base is the register containing the callee (call/cc itself),
/// and the result of call/cc will be stored at base.
pub fn callWithCC(vm: *VM, proc: Value, base: u16) VMError!void {
    // The caller's frame is at vm.frame_count - 1.
    // After call/cc returns, the result goes into base (relative to caller's frame).
    const caller_frame = &vm.frames[vm.frame_count - 1];
    const dst_reg: u8 = @intCast(base - caller_frame.base);

    // Capture the continuation. The continuation, when invoked,
    // will restore state and place the value at base (which is
    // caller_frame.base + dst_reg).
    const cont = try captureContinuation(vm, dst_reg, caller_frame.base);

    // Now call proc with cont as the argument.
    // We set up: registers[base] = proc, registers[base+1] = cont
    vm.registers[base + 1] = cont;

    // Call proc(cont) — just like a normal 1-arg call
    try vm.callValue(proc, base, 1);
}

/// Perform dynamic-wind transition from current wind stack to target wind stack.
/// Calls after thunks for unwinding and before thunks for rewinding.
pub fn performWindTransition(vm: *VM, target_winds: []const types.WindRecord, target_count: usize) !void {
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

    // Unwind: call after thunks from current top down to common
    var i = vm.wind_count;
    while (i > common) {
        i -= 1;
        const after = vm.wind_stack[i].after;
        _ = vm.callThunk(after) catch {};
    }
    vm.wind_count = common;

    // Rewind: call before thunks from common up to target
    var j = common;
    while (j < target_count) {
        const before = target_winds[j].before;
        _ = vm.callThunk(before) catch {};
        if (vm.wind_count < MAX_WINDS) {
            vm.wind_stack[vm.wind_count] = target_winds[j];
            vm.wind_count += 1;
        }
        j += 1;
    }
}

/// Restore a captured continuation, replacing the VM state and placing
/// the given value at the continuation's destination register.
pub fn restoreContinuation(vm: *VM, cont: *types.Continuation, value: Value) void {
    // Restore saved VM state
    @memcpy(vm.registers[0..cont.registers.len], cont.registers);
    for (cont.frames[0..cont.frame_count], 0..) |saved_frame, i| {
        vm.frames[i] = .{
            .closure = saved_frame.closure,
            .native = saved_frame.native,
            .code = saved_frame.code,
            .ip = saved_frame.ip,
            .base = saved_frame.base,
            .dst = saved_frame.dst,
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

    // Place the result value where call/cc was waiting for it
    vm.registers[cont.dst_base + cont.dst_reg] = value;
}
