const std = @import("std");
const platform = @import("platform.zig");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

fn freshSeed() u64 {
    return platform.randomSeed64();
}

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "random-integer", .func = &randomIntegerFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "random-real", .func = &randomRealFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "%default-random-source", .func = &defaultRandomSourceFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "random-source?", .func = &randomSourcePFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "make-random-source", .func = &makeRandomSourceFn, .arity = .{ .exact = 0 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "random-source-randomize!", .func = &randomSourceRandomizeFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "random-source-pseudo-randomize!", .func = &randomSourcePseudoRandomizeFn, .arity = .{ .exact = 3 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "random-source-state-ref", .func = &randomSourceStateRefFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "random-source-state-set!", .func = &randomSourceStateSetFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "%rs-next-int", .func = &rsNextIntFn, .arity = .{ .exact = 2 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "%rs-next-real", .func = &rsNextRealFn, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
};

pub fn initDefaultRS(vm: *vm_mod.VM) void {
    vm.default_random_source = vm.gc.allocRandomSource(freshSeed()) catch return;
}

pub fn ensureDefaultRS() void {
    const vm = vm_mod.vm_instance orelse return;
    if (vm.default_random_source == types.VOID) {
        vm.default_random_source = vm.gc.allocRandomSource(freshSeed()) catch return;
    }
}

fn getRS(proc: []const u8, v: Value) PrimitiveError!*types.RandomSource {
    if (!types.isRandomSource(v)) return primitives.typeError(proc, "random-source", v);
    return types.toObject(v).as(types.RandomSource);
}

fn randomIntegerFn(args: []const Value) PrimitiveError!Value {
    ensureDefaultRS();
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const rs = try getRS("random-integer", vm.default_random_source);
    return randomBelow("random-integer", rs, args[0]);
}

fn randomRealFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    ensureDefaultRS();
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    const rs = try getRS("random-real", vm.default_random_source);
    return types.makeFlonum(openUnitReal(rs));
}

fn defaultRandomSourceFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    ensureDefaultRS();
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    return vm.default_random_source;
}

fn randomSourcePFn(args: []const Value) PrimitiveError!Value {
    return if (types.isRandomSource(args[0])) types.TRUE else types.FALSE;
}

fn makeRandomSourceFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocRandomSource(0) catch return PrimitiveError.OutOfMemory;
}

fn randomSourceRandomizeFn(args: []const Value) PrimitiveError!Value {
    const rs = try getRS("random-source-randomize!", args[0]);
    rs.prng = std.Random.DefaultPrng.init(freshSeed());
    return types.VOID;
}

fn randomSourcePseudoRandomizeFn(args: []const Value) PrimitiveError!Value {
    const proc = "random-source-pseudo-randomize!";
    const rs = try getRS(proc, args[0]);
    const i = try intToSeedU64(proc, args[1]);
    const j = try intToSeedU64(proc, args[2]);
    rs.prng = std.Random.DefaultPrng.init(i *% 2654435761 +% j *% 2246822519);
    return types.VOID;
}

fn randomSourceStateRefFn(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const rs = try getRS("random-source-state-ref", args[0]);
    var result: Value = types.NIL;
    gc.pushRoot(&result);
    defer gc.popRoot();
    var i: usize = 4;
    while (i > 0) {
        i -= 1;
        const limb = [1]u64{rs.prng.s[i]};
        const word = gc.allocBignumFromLimbs(&limb, 1, true) catch return PrimitiveError.OutOfMemory;
        result = gc.allocPair(word, result) catch return PrimitiveError.OutOfMemory;
    }
    return result;
}

fn stateWordToU64(v: Value) ?u64 {
    if (types.isFixnum(v)) {
        const n = types.toFixnum(v);
        return @bitCast(n);
    }
    if (types.isBignum(v)) {
        const bn = types.toBignum(v);
        if (bn.len == 0) return 0;
        if (bn.len > 1) return null;
        return bn.limbs[0];
    }
    return null;
}

fn randomSourceStateSetFn(args: []const Value) PrimitiveError!Value {
    const rs = try getRS("random-source-state-set!", args[0]);
    var state_list = args[1];
    var new_state: [4]u64 = undefined;
    var i: usize = 0;
    while (i < 4) : (i += 1) {
        if (!types.isPair(state_list)) return primitives.typeError("random-source-state-set!", "list of 4 integers", state_list);
        const word = types.car(state_list);
        new_state[i] = stateWordToU64(word) orelse return primitives.typeError("random-source-state-set!", "integer", word);
        state_list = types.cdr(state_list);
    }
    if (new_state[0] == 0 and new_state[1] == 0 and new_state[2] == 0 and new_state[3] == 0) {
        return primitives.typeError("random-source-state-set!", "non-all-zero state", args[1]);
    }
    rs.prng.s = new_state;
    return types.VOID;
}

// (%rs-next-int rs n) — used by random-source-make-integers closure
fn rsNextIntFn(args: []const Value) PrimitiveError!Value {
    const rs = try getRS("%rs-next-int", args[0]);
    return randomBelow("%rs-next-int", rs, args[1]);
}

// (%rs-next-real rs) — used by random-source-make-reals closure
fn rsNextRealFn(args: []const Value) PrimitiveError!Value {
    const rs = try getRS("%rs-next-real", args[0]);
    return types.makeFlonum(openUnitReal(rs));
}

// SRFI-27 requires 0 < x < 1 (open interval); Zig's float(f64) returns [0, 1).
fn openUnitReal(rs: *types.RandomSource) f64 {
    var x = rs.prng.random().float(f64);
    while (x == 0.0) x = rs.prng.random().float(f64);
    return x;
}

fn randomBelow(proc: []const u8, rs: *types.RandomSource, bound: Value) PrimitiveError!Value {
    if (types.isFixnum(bound)) {
        const n = types.toFixnum(bound);
        if (n <= 0) return primitives.typeError(proc, "positive integer", bound);
        const r = rs.prng.random();
        return types.makeFixnum(r.intRangeLessThan(i64, 0, n));
    }
    if (types.isBignum(bound)) {
        const bn = types.toBignum(bound);
        if (!bn.positive or bn.len == 0) return primitives.typeError(proc, "positive integer", bound);
        return randomBignumBelow(rs, bn);
    }
    return primitives.typeError(proc, "integer", bound);
}

fn randomBignumBelow(rs: *types.RandomSource, bn: *const types.Bignum) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const n_len = bn.len;
    const top_limb = bn.limbs[n_len - 1];
    const top_bits: u7 = @intCast(64 - @clz(top_limb));
    const mask: u64 = if (top_bits >= 64) std.math.maxInt(u64) else (@as(u64, 1) << @as(u6, @intCast(top_bits))) - 1;
    const r = rs.prng.random();

    var stack_buf: [16]u64 = undefined;
    const limbs = if (n_len <= 16)
        stack_buf[0..n_len]
    else
        gc.allocator.alloc(u64, n_len) catch return PrimitiveError.OutOfMemory;
    defer if (n_len > 16) gc.allocator.free(limbs);

    var attempts: usize = 0;
    while (attempts < 1000) : (attempts += 1) {
        for (limbs) |*l| l.* = r.int(u64);
        limbs[n_len - 1] &= mask;
        if (limbsLessThan(limbs, bn.limbs, n_len)) {
            var actual_len = n_len;
            while (actual_len > 0 and limbs[actual_len - 1] == 0) actual_len -= 1;
            if (actual_len == 0) return types.makeFixnum(0);
            if (actual_len == 1 and limbs[0] <= @as(u64, @intCast(std.math.maxInt(i48)))) {
                return types.makeFixnum(@intCast(limbs[0]));
            }
            return gc.allocBignumFromLimbs(limbs[0..actual_len], actual_len, true) catch
                return PrimitiveError.OutOfMemory;
        }
    }
    return PrimitiveError.OutOfMemory;
}

fn limbsLessThan(a: []const u64, b: []const u64, len: usize) bool {
    var i: usize = len;
    while (i > 0) {
        i -= 1;
        if (a[i] < b[i]) return true;
        if (a[i] > b[i]) return false;
    }
    return false;
}

fn intToSeedU64(proc: []const u8, v: Value) PrimitiveError!u64 {
    if (types.isFixnum(v)) {
        const n = types.toFixnum(v);
        if (n < 0) return primitives.typeError(proc, "non-negative integer", v);
        return @intCast(n);
    }
    if (types.isBignum(v)) {
        const bn = types.toBignum(v);
        if (!bn.positive) return primitives.typeError(proc, "non-negative integer", v);
        if (bn.len == 0) return 0;
        var result: u64 = 0;
        for (bn.limbs[0..bn.len]) |limb| result ^= limb;
        return result;
    }
    return primitives.typeError(proc, "integer", v);
}
