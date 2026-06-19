const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const memory = @import("memory.zig");
const Value = types.Value;

const NUM_SLOTS = 16;

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
};

// ---------------------------------------------------------------------------
// Trampoline generators — one per supported C callback signature
// ---------------------------------------------------------------------------

fn makeTrampolinePPI(comptime idx: usize) *const fn (?*anyopaque, ?*anyopaque) callconv(.c) c_int {
    const S = struct {
        fn trampoline(a: ?*anyopaque, b: ?*anyopaque) callconv(.c) c_int {
            const slot = &callback_slots[idx];
            if (!slot.active) return 0;
            const vm = vm_mod.vm_instance orelse return 0;
            const arg0 = types.makeFixnum(@intCast(@intFromPtr(a orelse return 0)));
            const arg1 = types.makeFixnum(@intCast(@intFromPtr(b orelse return 0)));
            const args = [2]Value{ arg0, arg1 };
            const result = vm.callWithArgs(slot.closure, &args) catch {
                vm.last_callback_error = true;
                return 0;
            };
            if (types.isFixnum(result)) {
                const v = types.toFixnum(result);
                if (v >= std.math.minInt(c_int) and v <= std.math.maxInt(c_int))
                    return @intCast(v);
            }
            return 0;
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
            _ = vm.callWithArgs(slot.closure, &.{}) catch {
                vm.last_callback_error = true;
            };
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
            const arg0 = types.makeFixnum(@intCast(@intFromPtr(a orelse return)));
            const args = [1]Value{arg0};
            _ = vm.callWithArgs(slot.closure, &args) catch {
                vm.last_callback_error = true;
            };
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
            const arg0 = types.makeFixnum(@intCast(@intFromPtr(a orelse return 0)));
            const args = [1]Value{arg0};
            const result = vm.callWithArgs(slot.closure, &args) catch {
                vm.last_callback_error = true;
                return 0;
            };
            if (types.isFixnum(result)) {
                const v = types.toFixnum(result);
                if (v >= std.math.minInt(c_int) and v <= std.math.maxInt(c_int))
                    return @intCast(v);
            }
            return 0;
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
