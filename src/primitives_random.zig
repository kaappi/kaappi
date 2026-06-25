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

fn freshSeed() u64 {
    if (@import("builtin").os.tag == .linux) {
        var buf: [8]u8 = undefined;
        const rc = std.os.linux.getrandom(&buf, buf.len, 0);
        if (rc == buf.len) return @bitCast(buf);
    } else {
        const arc4 = @extern(*const fn () callconv(.c) u32, .{ .name = "arc4random" });
        const lo: u64 = arc4();
        const hi: u64 = arc4();
        return (hi << 32) | lo;
    }
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @as(u64, @bitCast(ts.sec)) ^ @as(u64, @bitCast(ts.nsec));
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

fn getRS(proc: []const u8, v: Value) PrimitiveError!*types.RandomSource {
    if (!types.isRandomSource(v)) return primitives.typeError(proc, "random-source", v);
    return types.toObject(v).as(types.RandomSource);
}

fn randomIntegerFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return primitives.typeError("random-integer", "integer", args[0]);
    const n = types.toFixnum(args[0]);
    if (n <= 0) return primitives.typeError("random-integer", "positive integer", args[0]);
    const rs = try getRS("random-integer", default_rs_val);
    const r = rs.prng.random();
    return types.makeFixnum(r.intRangeLessThan(i64, 0, n));
}

fn randomRealFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    const rs = try getRS("random-real", default_rs_val);
    const r = rs.prng.random();
    return types.makeFlonum(r.float(f64));
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
    const rs = try getRS("random-source-randomize!", args[0]);
    rs.prng = std.Random.DefaultPrng.init(freshSeed());
    return types.VOID;
}

fn randomSourcePseudoRandomizeFn(args: []const Value) PrimitiveError!Value {
    const rs = try getRS("random-source-pseudo-randomize!", args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("random-source-pseudo-randomize!", "integer", args[1]);
    if (!types.isFixnum(args[2])) return primitives.typeError("random-source-pseudo-randomize!", "integer", args[2]);
    const i: u64 = @intCast(types.toFixnum(args[1]));
    const j: u64 = @intCast(types.toFixnum(args[2]));
    rs.prng = std.Random.DefaultPrng.init(i *% 2654435761 +% j *% 2246822519);
    return types.VOID;
}

fn randomSourceStateRefFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const rs = try getRS("random-source-state-ref", args[0]);
    var result: Value = types.NIL;
    gc.pushRoot(&result) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    var i: usize = 4;
    while (i > 0) {
        i -= 1;
        const word: i64 = @bitCast(rs.prng.s[i]);
        result = gc.allocPair(types.makeFixnum(word), result) catch return PrimitiveError.OutOfMemory;
    }
    return result;
}

fn randomSourceStateSetFn(args: []const Value) PrimitiveError!Value {
    const rs = try getRS("random-source-state-set!", args[0]);
    var state_list = args[1];
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        if (!types.isPair(state_list)) return primitives.typeError("random-source-state-set!", "list of 4 integers", state_list);
        const word = types.car(state_list);
        if (!types.isFixnum(word)) return primitives.typeError("random-source-state-set!", "integer", word);
        rs.prng.s[i] = @bitCast(types.toFixnum(word));
        state_list = types.cdr(state_list);
    }
    return types.VOID;
}

// (%rs-next-int rs n) — used by random-source-make-integers closure
fn rsNextIntFn(args: []const Value) PrimitiveError!Value {
    const rs = try getRS("%rs-next-int", args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("%rs-next-int", "integer", args[1]);
    const n = types.toFixnum(args[1]);
    if (n <= 0) return primitives.typeError("%rs-next-int", "positive integer", args[1]);
    const r = rs.prng.random();
    return types.makeFixnum(r.intRangeLessThan(i64, 0, n));
}

// (%rs-next-real rs) — used by random-source-make-reals closure
fn rsNextRealFn(args: []const Value) PrimitiveError!Value {
    const rs = try getRS("%rs-next-real", args[0]);
    const r = rs.prng.random();
    return types.makeFlonum(r.float(f64));
}
