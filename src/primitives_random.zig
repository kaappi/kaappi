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

extern fn arc4random() u32;

fn freshSeed() u64 {
    const lo: u64 = arc4random();
    const hi: u64 = arc4random();
    return (hi << 32) | lo;
}

var default_rs_val: Value = types.VOID;

pub fn registerRandom(vm: *vm_mod.VM) !void {
    default_rs_val = vm.gc.allocRandomSource(freshSeed()) catch return error.OutOfMemory;
    vm.gc.extra_roots.append(vm.gc.allocator, default_rs_val) catch return error.OutOfMemory;

    try reg(vm, "random-integer", &randomIntegerFn, .{ .exact = 1 });
    try reg(vm, "random-real", &randomRealFn, .{ .exact = 0 });
    try reg(vm, "default-random-source", &defaultRandomSourceFn, .{ .exact = 0 });
    try reg(vm, "random-source?", &randomSourcePFn, .{ .exact = 1 });
    try reg(vm, "make-random-source", &makeRandomSourceFn, .{ .exact = 0 });
    try reg(vm, "random-source-randomize!", &randomSourceRandomizeFn, .{ .exact = 1 });
    try reg(vm, "random-source-pseudo-randomize!", &randomSourcePseudoRandomizeFn, .{ .exact = 3 });
    try reg(vm, "random-source-state-ref", &randomSourceStateRefFn, .{ .exact = 1 });
    try reg(vm, "random-source-state-set!", &randomSourceStateSetFn, .{ .exact = 2 });
    try reg(vm, "%rs-next-int", &rsNextIntFn, .{ .exact = 2 });
    try reg(vm, "%rs-next-real", &rsNextRealFn, .{ .exact = 1 });
}

fn getRS(v: Value) PrimitiveError!*types.RandomSource {
    if (!types.isRandomSource(v)) return PrimitiveError.TypeError;
    return types.toObject(v).as(types.RandomSource);
}

fn randomIntegerFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    const n = types.toFixnum(args[0]);
    if (n <= 0) return PrimitiveError.TypeError;
    const rs = try getRS(default_rs_val);
    const r = rs.prng.random();
    return types.makeFixnum(r.intRangeLessThan(i64, 0, n));
}

fn randomRealFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const rs = try getRS(default_rs_val);
    const r = rs.prng.random();
    return gc.allocFlonum(r.float(f64)) catch return PrimitiveError.OutOfMemory;
}

fn defaultRandomSourceFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    return default_rs_val;
}

fn randomSourcePFn(args: []const Value) PrimitiveError!Value {
    return if (types.isRandomSource(args[0])) types.TRUE else types.FALSE;
}

fn makeRandomSourceFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocRandomSource(freshSeed()) catch return PrimitiveError.OutOfMemory;
}

fn randomSourceRandomizeFn(args: []const Value) PrimitiveError!Value {
    const rs = try getRS(args[0]);
    rs.prng = std.Random.DefaultPrng.init(freshSeed());
    return types.VOID;
}

fn randomSourcePseudoRandomizeFn(args: []const Value) PrimitiveError!Value {
    const rs = try getRS(args[0]);
    if (!types.isFixnum(args[1]) or !types.isFixnum(args[2])) return PrimitiveError.TypeError;
    const i: u64 = @intCast(types.toFixnum(args[1]));
    const j: u64 = @intCast(types.toFixnum(args[2]));
    rs.prng = std.Random.DefaultPrng.init(i *% 2654435761 +% j *% 2246822519);
    return types.VOID;
}

fn randomSourceStateRefFn(args: []const Value) PrimitiveError!Value {
    const rs = try getRS(args[0]);
    const state: i64 = @bitCast(rs.prng.s[0]);
    return types.makeFixnum(state);
}

fn randomSourceStateSetFn(args: []const Value) PrimitiveError!Value {
    const rs = try getRS(args[0]);
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const state: u64 = @bitCast(types.toFixnum(args[1]));
    rs.prng.s[0] = state;
    return types.VOID;
}

// (%rs-next-int rs n) — used by random-source-make-integers closure
fn rsNextIntFn(args: []const Value) PrimitiveError!Value {
    const rs = try getRS(args[0]);
    if (!types.isFixnum(args[1])) return PrimitiveError.TypeError;
    const n = types.toFixnum(args[1]);
    if (n <= 0) return PrimitiveError.TypeError;
    const r = rs.prng.random();
    return types.makeFixnum(r.intRangeLessThan(i64, 0, n));
}

// (%rs-next-real rs) — used by random-source-make-reals closure
fn rsNextRealFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const rs = try getRS(args[0]);
    const r = rs.prng.random();
    return gc.allocFlonum(r.float(f64)) catch return PrimitiveError.OutOfMemory;
}
