const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const memory = @import("memory.zig");
const Value = types.Value;

const NUM_SLOTS = 32;

const CallbackSlot = struct {
    closure: Value,
    active: bool,
};

var callback_slots: [NUM_SLOTS]CallbackSlot = [_]CallbackSlot{.{ .closure = types.VOID, .active = false }} ** NUM_SLOTS;

pub const CallbackSig = enum {
    pp_int, // (pointer, pointer) -> int
    p_void, // (pointer) -> void
    v_void, // () -> void
    p_int, // (pointer) -> int
    ip_int, // (int, pointer) -> int
    i_void, // (int) -> void
    pp_void, // (pointer, pointer) -> void
};

const MAX_FIXNUM: i64 = 0x7FFF_FFFF_FFFF;

fn marshalPtrArg(ptr: ?*anyopaque, gc: *memory.GC) ?Value {
    const addr: usize = if (ptr) |p| @intFromPtr(p) else return types.makeFixnum(0);
    const signed: i64 = @bitCast(@as(u64, addr));
    if (signed >= 0 and signed <= MAX_FIXNUM)
        return types.makeFixnum(signed);
    const limbs_buf = [1]u64{addr};
    return gc.allocBignumFromLimbs(&limbs_buf, 1, true) catch return null;
}

/// A Scheme error escaped a callback invoked from C. The C frames between
/// the enclosing FFI call and this trampoline cannot be unwound, so stash
/// the exception on the VM and hand a default value back to C; callFfi
/// re-raises the stash after the C call returns (#1185). First error wins:
/// C may keep invoking the callback after the failure, but those runs
/// happen on already-poisoned state.
fn noteCallbackError(vm: *vm_mod.VM, err: anyerror) void {
    switch (err) {
        // Control-flow signals, not callback failures. The dispatch loop
        // re-detects Terminated/ExecutionTimeout on its next check; resuming
        // a continuation or parking a fiber across live C frames is
        // unsupported (same class as the native-frame continuation limit).
        error.ContinuationInvoked, error.Yielded, error.Terminated, error.ExecutionTimeout => return,
        else => {},
    }
    vm.last_callback_error = true;
    var pending: ?Value = null;
    if (err == error.ExceptionRaised) {
        pending = vm.current_exception;
        vm.current_exception = null;
    }
    if (vm.callback_error_value != null) return;
    if (pending) |exc| {
        vm.callback_error_value = exc;
        return;
    }
    // VM-level error (TypeError, ArityMismatch, ...): synthesize an error
    // object from the recorded detail so the re-raise carries a message.
    // On allocation failure the flag alone still forces callFfi to raise.
    const detail = vm.getErrorDetail();
    var msg = vm.gc.allocString(if (detail.len > 0) detail else "error in FFI callback") catch return;
    vm.gc.pushRoot(&msg);
    const err_obj = vm.gc.allocErrorObject(msg, types.NIL) catch {
        vm.gc.popRoot();
        return;
    };
    vm.gc.popRoot();
    vm.callback_error_value = err_obj;
}

/// Marshal a callback's Scheme return value to the C `int` the signature
/// declares. A non-integer or out-of-range value is stashed as an error
/// like a raise (#1185) — silently coercing it to 0 hands garbage to C.
fn marshalIntReturn(vm: *vm_mod.VM, result: Value) c_int {
    if (types.isFixnum(result)) {
        const v = types.toFixnum(result);
        if (v >= std.math.minInt(c_int) and v <= std.math.maxInt(c_int))
            return @intCast(v);
    }
    vm.last_callback_error = true;
    if (vm.callback_error_value == null) {
        var result_root = result;
        vm.gc.pushRoot(&result_root);
        defer vm.gc.popRoot();
        const printer = @import("printer.zig");
        const shown = printer.valueToString(vm.gc.allocator, result_root, .write) catch null;
        defer if (shown) |s| vm.gc.allocator.free(s);
        var buf: [256]u8 = undefined;
        const text = std.fmt.bufPrint(&buf, "FFI callback must return a C int, got {s}", .{shown orelse "a non-integer value"}) catch "FFI callback must return a C int";
        var msg = vm.gc.allocString(text) catch return 0;
        vm.gc.pushRoot(&msg);
        const err_obj = vm.gc.allocErrorObject(msg, types.NIL) catch {
            vm.gc.popRoot();
            return 0;
        };
        vm.gc.popRoot();
        vm.callback_error_value = err_obj;
    }
    return 0;
}

// ---------------------------------------------------------------------------
// Trampoline generators — one per supported C callback signature
// ---------------------------------------------------------------------------

fn makeTrampolinePPI(comptime idx: usize) *const fn (?*anyopaque, ?*anyopaque) callconv(.c) c_int {
    const S = struct {
        fn trampoline(a: ?*anyopaque, b: ?*anyopaque) callconv(.c) c_int {
            const slot = &callback_slots[idx];
            if (!slot.active) return 0;
            const vm = vm_mod.vm_instance orelse return 0;
            const arg0 = marshalPtrArg(a, vm.gc) orelse return 0;
            const arg1 = marshalPtrArg(b, vm.gc) orelse return 0;
            const args = [2]Value{ arg0, arg1 };
            const result = vm.callWithArgs(slot.closure, &args) catch |err| {
                noteCallbackError(vm, err);
                return 0;
            };
            return marshalIntReturn(vm, result);
        }
    };
    return &S.trampoline;
}

fn makeTrampolineVV(comptime idx: usize) *const fn () callconv(.c) void {
    const S = struct {
        fn trampoline() callconv(.c) void {
            const slot = &callback_slots[idx];
            if (!slot.active) return;
            const vm = vm_mod.vm_instance orelse return;
            _ = vm.callWithArgs(slot.closure, &.{}) catch |err| noteCallbackError(vm, err);
        }
    };
    return &S.trampoline;
}

fn makeTrampolinePV(comptime idx: usize) *const fn (?*anyopaque) callconv(.c) void {
    const S = struct {
        fn trampoline(a: ?*anyopaque) callconv(.c) void {
            const slot = &callback_slots[idx];
            if (!slot.active) return;
            const vm = vm_mod.vm_instance orelse return;
            const arg0 = marshalPtrArg(a, vm.gc) orelse return;
            const args = [1]Value{arg0};
            _ = vm.callWithArgs(slot.closure, &args) catch |err| noteCallbackError(vm, err);
        }
    };
    return &S.trampoline;
}

fn makeTrampolinePI(comptime idx: usize) *const fn (?*anyopaque) callconv(.c) c_int {
    const S = struct {
        fn trampoline(a: ?*anyopaque) callconv(.c) c_int {
            const slot = &callback_slots[idx];
            if (!slot.active) return 0;
            const vm = vm_mod.vm_instance orelse return 0;
            const arg0 = marshalPtrArg(a, vm.gc) orelse return 0;
            const args = [1]Value{arg0};
            const result = vm.callWithArgs(slot.closure, &args) catch |err| {
                noteCallbackError(vm, err);
                return 0;
            };
            return marshalIntReturn(vm, result);
        }
    };
    return &S.trampoline;
}

fn makeTrampolineIPI(comptime idx: usize) *const fn (c_int, ?*anyopaque) callconv(.c) c_int {
    const S = struct {
        fn trampoline(a: c_int, b: ?*anyopaque) callconv(.c) c_int {
            const slot = &callback_slots[idx];
            if (!slot.active) return 0;
            const vm = vm_mod.vm_instance orelse return 0;
            const arg0 = types.makeFixnum(@intCast(a));
            const arg1 = marshalPtrArg(b, vm.gc) orelse return 0;
            const args = [2]Value{ arg0, arg1 };
            const result = vm.callWithArgs(slot.closure, &args) catch |err| {
                noteCallbackError(vm, err);
                return 0;
            };
            return marshalIntReturn(vm, result);
        }
    };
    return &S.trampoline;
}

fn makeTrampolineIV(comptime idx: usize) *const fn (c_int) callconv(.c) void {
    const S = struct {
        fn trampoline(a: c_int) callconv(.c) void {
            const slot = &callback_slots[idx];
            if (!slot.active) return;
            const vm = vm_mod.vm_instance orelse return;
            const arg0 = types.makeFixnum(@intCast(a));
            const args = [1]Value{arg0};
            _ = vm.callWithArgs(slot.closure, &args) catch |err| noteCallbackError(vm, err);
        }
    };
    return &S.trampoline;
}

fn makeTrampolinePPV(comptime idx: usize) *const fn (?*anyopaque, ?*anyopaque) callconv(.c) void {
    const S = struct {
        fn trampoline(a: ?*anyopaque, b: ?*anyopaque) callconv(.c) void {
            const slot = &callback_slots[idx];
            if (!slot.active) return;
            const vm = vm_mod.vm_instance orelse return;
            const arg0 = marshalPtrArg(a, vm.gc) orelse return;
            const arg1 = marshalPtrArg(b, vm.gc) orelse return;
            const args = [2]Value{ arg0, arg1 };
            _ = vm.callWithArgs(slot.closure, &args) catch |err| noteCallbackError(vm, err);
        }
    };
    return &S.trampoline;
}

// ---------------------------------------------------------------------------
// Trampoline arrays — one per signature, NUM_SLOTS entries each
// ---------------------------------------------------------------------------

fn generateTrampolines(comptime T: type, comptime maker: fn (comptime usize) T) [NUM_SLOTS]T {
    var t: [NUM_SLOTS]T = undefined;
    for (0..NUM_SLOTS) |i| {
        t[i] = maker(i);
    }
    return t;
}

const trampolines_pp_int = generateTrampolines(
    *const fn (?*anyopaque, ?*anyopaque) callconv(.c) c_int,
    makeTrampolinePPI,
);
const trampolines_v_void = generateTrampolines(
    *const fn () callconv(.c) void,
    makeTrampolineVV,
);
const trampolines_p_void = generateTrampolines(
    *const fn (?*anyopaque) callconv(.c) void,
    makeTrampolinePV,
);
const trampolines_p_int = generateTrampolines(
    *const fn (?*anyopaque) callconv(.c) c_int,
    makeTrampolinePI,
);
const trampolines_ip_int = generateTrampolines(
    *const fn (c_int, ?*anyopaque) callconv(.c) c_int,
    makeTrampolineIPI,
);
const trampolines_i_void = generateTrampolines(
    *const fn (c_int) callconv(.c) void,
    makeTrampolineIV,
);
const trampolines_pp_void = generateTrampolines(
    *const fn (?*anyopaque, ?*anyopaque) callconv(.c) void,
    makeTrampolinePPV,
);

// ---------------------------------------------------------------------------
// Slot management
// ---------------------------------------------------------------------------

pub const SlotInfo = struct {
    index: u8,
    fn_ptr: *anyopaque,
};

pub fn allocSlot(closure: Value, sig: CallbackSig) ?SlotInfo {
    for (&callback_slots, 0..) |*slot, i| {
        if (!slot.active) {
            slot.closure = closure;
            slot.active = true;
            const fn_ptr: *anyopaque = switch (sig) {
                .pp_int => @ptrCast(@constCast(trampolines_pp_int[i])),
                .p_void => @ptrCast(@constCast(trampolines_p_void[i])),
                .v_void => @ptrCast(@constCast(trampolines_v_void[i])),
                .p_int => @ptrCast(@constCast(trampolines_p_int[i])),
                .ip_int => @ptrCast(@constCast(trampolines_ip_int[i])),
                .i_void => @ptrCast(@constCast(trampolines_i_void[i])),
                .pp_void => @ptrCast(@constCast(trampolines_pp_void[i])),
            };
            return .{ .index = @intCast(i), .fn_ptr = fn_ptr };
        }
    }
    return null;
}

pub fn releaseSlot(index: u8) void {
    if (index >= NUM_SLOTS) return;
    callback_slots[index].closure = types.VOID;
    callback_slots[index].active = false;
}

pub fn markCallbackRoots(gc: *memory.GC) void {
    for (&callback_slots) |*slot| {
        if (slot.active) {
            gc.markValue(slot.closure);
        }
    }
}

test "marshalPtrArg: null returns fixnum zero" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    const val = marshalPtrArg(null, &gc).?;
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(val));
}

test "marshalPtrArg: small address returns fixnum" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    const addr: usize = 0x1000;
    const ptr: *anyopaque = @ptrFromInt(addr);
    const val = marshalPtrArg(ptr, &gc).?;
    try std.testing.expect(types.isFixnum(val));
    try std.testing.expectEqual(@as(i64, @intCast(addr)), types.toFixnum(val));
}

test "marshalPtrArg: large address returns bignum" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    const addr: usize = 0x0001_0000_0000_0000;
    const ptr: *anyopaque = @ptrFromInt(addr);
    const val = marshalPtrArg(ptr, &gc).?;
    try std.testing.expect(types.isBignum(val));
}
