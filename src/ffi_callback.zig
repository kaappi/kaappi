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

fn makeTrampoline(comptime idx: usize) *const fn (?*anyopaque, ?*anyopaque) callconv(.c) c_int {
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

const trampolines: [NUM_SLOTS]*const fn (?*anyopaque, ?*anyopaque) callconv(.c) c_int = blk: {
    var t: [NUM_SLOTS]*const fn (?*anyopaque, ?*anyopaque) callconv(.c) c_int = undefined;
    for (0..NUM_SLOTS) |i| {
        t[i] = makeTrampoline(i);
    }
    break :blk t;
};

pub const SlotInfo = struct {
    index: u8,
    fn_ptr: *anyopaque,
};

pub fn allocSlot(closure: Value) ?SlotInfo {
    for (&callback_slots, 0..) |*slot, i| {
        if (!slot.active) {
            slot.closure = closure;
            slot.active = true;
            return .{
                .index = @intCast(i),
                .fn_ptr = @ptrCast(@constCast(trampolines[i])),
            };
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
