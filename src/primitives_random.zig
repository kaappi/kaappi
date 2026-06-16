const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    return primitives.reg(vm, name, func, arity);
}

// Use arc4random from libc (linked by the build) for seeding
extern fn arc4random() u32;

var prng: std.Random.DefaultPrng = undefined;
var prng_initialized: bool = false;

fn ensureInit() void {
    if (!prng_initialized) {
        const lo: u64 = arc4random();
        const hi: u64 = arc4random();
        const seed: u64 = (hi << 32) | lo;
        prng = std.Random.DefaultPrng.init(seed);
        prng_initialized = true;
    }
}

pub fn registerRandom(vm: *vm_mod.VM) !void {
    try reg(vm, "random-integer", &randomIntegerFn, .{ .exact = 1 });
    try reg(vm, "random-real", &randomRealFn, .{ .exact = 0 });
}

// (random-integer n) -> random integer in [0, n)
fn randomIntegerFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    const n = types.toFixnum(args[0]);
    if (n <= 0) return PrimitiveError.TypeError;
    ensureInit();
    const r = prng.random();
    const result = r.intRangeLessThan(i64, 0, n);
    return types.makeFixnum(result);
}

// (random-real) -> random real in [0.0, 1.0)
fn randomRealFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    ensureInit();
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const r = prng.random();
    const f = r.float(f64);
    return gc.allocFlonum(f) catch return PrimitiveError.OutOfMemory;
}
