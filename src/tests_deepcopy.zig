const std = @import("std");
const memory = @import("memory.zig");
const types = @import("types.zig");

test "deepCopy fixnum" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    const val = types.makeFixnum(42);
    const copied = try gc.deepCopy(val);
    try std.testing.expectEqual(val, copied);
}

test "deepCopy string" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const str = try gc1.allocString("hello");
    const copied = try gc2.deepCopy(str);

    try std.testing.expect(str != copied);
    const orig = types.toObject(str).as(types.SchemeString);
    const copy = types.toObject(copied).as(types.SchemeString);
    try std.testing.expectEqualSlices(u8, orig.data[0..orig.len], copy.data[0..copy.len]);
}

test "deepCopy pair" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const pair = try gc1.allocPair(types.makeFixnum(1), types.makeFixnum(2));
    const copied = try gc2.deepCopy(pair);

    try std.testing.expect(pair != copied);
    const orig_p = types.toObject(pair).as(types.Pair);
    const copy_p = types.toObject(copied).as(types.Pair);
    try std.testing.expectEqual(orig_p.car, copy_p.car);
    try std.testing.expectEqual(orig_p.cdr, copy_p.cdr);
}

test "deepCopy nested list" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const three = try gc1.allocPair(types.makeFixnum(3), types.NIL);
    const two = try gc1.allocPair(types.makeFixnum(2), three);
    const one = try gc1.allocPair(types.makeFixnum(1), two);
    const copied = try gc2.deepCopy(one);

    const p1 = types.toObject(copied).as(types.Pair);
    try std.testing.expectEqual(types.makeFixnum(1), p1.car);
    const p2 = types.toObject(p1.cdr).as(types.Pair);
    try std.testing.expectEqual(types.makeFixnum(2), p2.car);
    const p3 = types.toObject(p2.cdr).as(types.Pair);
    try std.testing.expectEqual(types.makeFixnum(3), p3.car);
    try std.testing.expectEqual(types.NIL, p3.cdr);
}

test "deepCopy long flat list does not overflow the stack (issue #801)" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    // Build a proper list (0 1 2 ... n-1) with n well past the ~15k element
    // native-stack-overflow threshold reported in #801. Before the fix, the
    // cdr-spine recursion in deepCopyValue crashed the process here.
    const n: i64 = 200_000;
    var lst = types.NIL;
    try gc1.pushRoot(&lst); // keep the partial list alive across collections
    defer gc1.popRoot();
    var i: i64 = n - 1;
    while (i >= 0) : (i -= 1) {
        lst = try gc1.allocPair(types.makeFixnum(i), lst);
    }

    const copied = try gc2.deepCopy(lst);
    try std.testing.expect(lst != copied);

    // Walk the copy: verify every element and the length, and confirm it is a
    // fresh structure (independent heap objects).
    var count: i64 = 0;
    var cur = copied;
    while (types.isPointer(cur) and types.toObject(cur).tag == .pair) {
        const p = types.toObject(cur).as(types.Pair);
        try std.testing.expectEqual(types.makeFixnum(count), p.car);
        count += 1;
        cur = p.cdr;
    }
    try std.testing.expectEqual(n, count);
    try std.testing.expectEqual(types.NIL, cur);
}

test "deepCopy long improper list preserves the tail (issue #801)" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    // Long list ending in a non-nil immediate tail exercises the loop's
    // "immediate cdr" break path at depth.
    const n: i64 = 100_000;
    var lst = types.makeFixnum(-1);
    try gc1.pushRoot(&lst);
    defer gc1.popRoot();
    var i: i64 = n - 1;
    while (i >= 0) : (i -= 1) {
        lst = try gc1.allocPair(types.makeFixnum(i), lst);
    }

    const copied = try gc2.deepCopy(lst);
    var count: i64 = 0;
    var cur = copied;
    while (types.isPointer(cur) and types.toObject(cur).tag == .pair) {
        const p = types.toObject(cur).as(types.Pair);
        try std.testing.expectEqual(types.makeFixnum(count), p.car);
        count += 1;
        cur = p.cdr;
    }
    try std.testing.expectEqual(n, count);
    try std.testing.expectEqual(types.makeFixnum(-1), cur);
}

test "deepCopy vector" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const vec = try gc1.allocVectorFill(3, types.VOID);
    const v = types.toObject(vec).as(types.Vector);
    v.data[0] = types.makeFixnum(10);
    v.data[1] = types.makeFixnum(20);
    v.data[2] = types.makeFixnum(30);

    const copied = try gc2.deepCopy(vec);
    try std.testing.expect(vec != copied);
    const cv = types.toObject(copied).as(types.Vector);
    try std.testing.expectEqual(@as(usize, 3), cv.data.len);
    try std.testing.expectEqual(types.makeFixnum(10), cv.data[0]);
    try std.testing.expectEqual(types.makeFixnum(20), cv.data[1]);
    try std.testing.expectEqual(types.makeFixnum(30), cv.data[2]);
}

test "deepCopy hash_table" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const ht_val = try gc1.allocHashTable(8);
    const ht = types.toObject(ht_val).as(types.HashTable);
    const key = types.makeFixnum(42);
    const value = types.makeFixnum(99);
    const hash = std.hash.Wyhash.hash(0, std.mem.asBytes(&key));
    const idx = hash & (ht.capacity - 1);
    ht.entries[idx] = .{ .key = key, .value = value, .state = .occupied };
    ht.count = 1;

    const copied = try gc2.deepCopy(ht_val);
    try std.testing.expect(ht_val != copied);
    const cht = types.toObject(copied).as(types.HashTable);
    try std.testing.expectEqual(@as(usize, 1), cht.count);
    var found = false;
    for (cht.entries[0..cht.capacity]) |entry| {
        if (entry.state == .occupied and entry.key == key) {
            try std.testing.expectEqual(value, entry.value);
            found = true;
        }
    }
    try std.testing.expect(found);
}

test "deepCopy closure with upvalues" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const func = try gc1.allocFunction();
    func.upvalue_count = 2;
    func.code.append(gc1.allocator, 0) catch unreachable;
    const cls = try gc1.allocClosure(func);
    const cl = types.toObject(cls).as(types.Closure);
    cl.upvalues[0] = types.makeFixnum(100);
    cl.upvalues[1] = types.makeFixnum(200);

    const copied = try gc2.deepCopy(cls);
    try std.testing.expect(cls != copied);
    const ccl = types.toObject(copied).as(types.Closure);
    try std.testing.expectEqual(types.makeFixnum(100), ccl.upvalues[0]);
    try std.testing.expectEqual(types.makeFixnum(200), ccl.upvalues[1]);
    try std.testing.expect(@intFromPtr(cl.func) != @intFromPtr(ccl.func));
}

test "deepCopy promise" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const prom = try gc1.allocPromise(false, types.makeFixnum(42));
    const copied = try gc2.deepCopy(prom);
    try std.testing.expect(prom != copied);
    const cp = types.toObject(copied).as(types.Promise);
    try std.testing.expectEqual(false, cp.forced);
    try std.testing.expectEqual(types.makeFixnum(42), cp.value);

    const forced = try gc1.allocPromise(true, types.makeFixnum(7));
    const copied2 = try gc2.deepCopy(forced);
    const cf = types.toObject(copied2).as(types.Promise);
    try std.testing.expectEqual(true, cf.forced);
    try std.testing.expectEqual(types.makeFixnum(7), cf.value);
}

test "deepCopy parameter" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const param = try gc1.allocParameter(types.makeFixnum(55), types.NIL);
    const copied = try gc2.deepCopy(param);
    try std.testing.expect(param != copied);
    const cp = types.toObject(copied).as(types.ParameterObject);
    try std.testing.expectEqual(types.makeFixnum(55), cp.value);
    try std.testing.expectEqual(types.NIL, cp.converter);
}

test "deepCopy error_object" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const msg = try gc1.allocString("test error");
    const err = try gc1.allocErrorObject(msg, types.NIL);
    const e = types.toObject(err).as(types.ErrorObject);
    e.error_type = .file;

    const copied = try gc2.deepCopy(err);
    try std.testing.expect(err != copied);
    const ce = types.toObject(copied).as(types.ErrorObject);
    try std.testing.expectEqual(types.ErrorObject.ErrorType.file, ce.error_type);
    const cm = types.toObject(ce.message).as(types.SchemeString);
    try std.testing.expectEqualSlices(u8, "test error", cm.data[0..cm.len]);
}

test "deepCopy record_type and instance" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const rt_val = try gc1.allocRecordType("point", 2);
    const rt = types.toObject(rt_val).as(types.RecordType);
    const fields = try gc1.allocator.alloc(types.Value, 2);
    defer gc1.allocator.free(fields);
    fields[0] = types.makeFixnum(10);
    fields[1] = types.makeFixnum(20);
    const ri = try gc1.allocRecordInstance(rt, fields);

    const copied = try gc2.deepCopy(ri);
    try std.testing.expect(ri != copied);
    const cri = types.toObject(copied).as(types.RecordInstance);
    try std.testing.expectEqual(types.makeFixnum(10), cri.fields[0]);
    try std.testing.expectEqual(types.makeFixnum(20), cri.fields[1]);
    try std.testing.expect(@intFromPtr(rt) != @intFromPtr(cri.record_type));
}

test "deepCopy rational" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const rat = try gc1.allocRational(types.makeFixnum(3), types.makeFixnum(4));
    const copied = try gc2.deepCopy(rat);
    try std.testing.expect(rat != copied);
    const cr = types.toObject(copied).as(types.Rational);
    try std.testing.expectEqual(types.makeFixnum(3), cr.numerator);
    try std.testing.expectEqual(types.makeFixnum(4), cr.denominator);
}

test "deepCopy complex" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const cplx = try gc1.allocComplexEx(1.5, 2.5, false, true);
    const copied = try gc2.deepCopy(cplx);
    try std.testing.expect(cplx != copied);
    const cc = types.toObject(copied).as(types.Complex);
    try std.testing.expectEqual(@as(f64, 1.5), cc.real);
    try std.testing.expectEqual(@as(f64, 2.5), cc.imag);
    try std.testing.expectEqual(false, cc.exact_real);
    try std.testing.expectEqual(true, cc.exact_imag);
}

test "deepCopy bignum" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const bn = try gc1.allocBignumFromI64(999999999999);
    const copied = try gc2.deepCopy(bn);
    try std.testing.expect(bn != copied);
    const orig = types.toObject(bn).as(types.Bignum);
    const cb = types.toObject(copied).as(types.Bignum);
    try std.testing.expectEqual(orig.len, cb.len);
    try std.testing.expectEqual(orig.positive, cb.positive);
    try std.testing.expectEqualSlices(u64, orig.limbs[0..orig.len], cb.limbs[0..cb.len]);
}

test "deepCopy transformer" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const lits = try gc1.allocator.alloc(types.Value, 1);
    defer gc1.allocator.free(lits);
    lits[0] = types.makeFixnum(1);
    const pats = try gc1.allocator.alloc(types.Value, 1);
    defer gc1.allocator.free(pats);
    pats[0] = types.makeFixnum(2);
    const tmpls = try gc1.allocator.alloc(types.Value, 1);
    defer gc1.allocator.free(tmpls);
    tmpls[0] = types.makeFixnum(3);
    const tx = try gc1.allocTransformer(lits, pats, tmpls);

    const copied = try gc2.deepCopy(tx);
    try std.testing.expect(tx != copied);
    const ct = types.toObject(copied).as(types.Transformer);
    try std.testing.expectEqual(types.makeFixnum(1), ct.literals[0]);
    try std.testing.expectEqual(types.makeFixnum(2), ct.patterns[0]);
    try std.testing.expectEqual(types.makeFixnum(3), ct.templates[0]);
}

test "deepCopy circular pair" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const pair = try gc1.allocPair(types.makeFixnum(1), types.NIL);
    types.toObject(pair).as(types.Pair).cdr = pair;

    const copied = try gc2.deepCopy(pair);
    try std.testing.expect(pair != copied);
    const cp = types.toObject(copied).as(types.Pair);
    try std.testing.expectEqual(types.makeFixnum(1), cp.car);
    try std.testing.expectEqual(copied, cp.cdr);
}

test "deepCopy shared structure" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const shared = try gc1.allocPair(types.makeFixnum(99), types.NIL);
    const vec = try gc1.allocVectorFill(2, types.VOID);
    const v = types.toObject(vec).as(types.Vector);
    v.data[0] = shared;
    v.data[1] = shared;

    const copied = try gc2.deepCopy(vec);
    const cv = types.toObject(copied).as(types.Vector);
    try std.testing.expect(cv.data[0] != shared);
    try std.testing.expectEqual(cv.data[0], cv.data[1]);
}

fn testAdd1(args: []const types.Value) anyerror!types.Value {
    return types.makeFixnum(types.toFixnum(args[0]) + 1);
}

fn testNativeClosureFn(_: ?*@import("vm.zig").VM, _: [*]const types.Value, _: u64, _: [*]const types.Value) callconv(.c) u64 {
    return types.NIL;
}

test "deepCopy native_fn is copied, not aliased" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const nf_val = try gc1.allocNativeFn("test-add1", &testAdd1, .{ .exact = 1 });
    const copied = try gc2.deepCopy(nf_val);

    try std.testing.expect(nf_val != copied);
    const copy = types.toObject(copied).as(types.NativeFn);
    try std.testing.expectEqualStrings("test-add1", copy.name);
    try std.testing.expectEqual(types.NativeFn.Arity{ .exact = 1 }, copy.arity);
    try std.testing.expectEqual(types.makeFixnum(42), try copy.func(&.{types.makeFixnum(41)}));
}

test "deepCopy native_closure copies upvalues into the target heap" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const pair = try gc1.allocPair(types.makeFixnum(7), types.NIL);
    const upvalues = [_]types.Value{ pair, types.makeFixnum(3) };
    const nc_val = try gc1.allocNativeClosure(&testNativeClosureFn, &upvalues, 2, "test-nc");
    const copied = try gc2.deepCopy(nc_val);

    try std.testing.expect(nc_val != copied);
    const copy = types.toObject(copied).as(types.NativeClosure);
    try std.testing.expectEqual(@as(u8, 2), copy.arity);
    try std.testing.expectEqualStrings("test-nc", copy.name);
    try std.testing.expect(copy.upvalues[0] != pair);
    const copied_pair = types.toObject(copy.upvalues[0]).as(types.Pair);
    try std.testing.expectEqual(types.makeFixnum(7), copied_pair.car);
    try std.testing.expectEqual(types.NIL, copied_pair.cdr);
    try std.testing.expectEqual(types.makeFixnum(3), copy.upvalues[1]);
}

test "deepCopy preserves sharing of native procedures within one structure" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const nf_val = try gc1.allocNativeFn("shared-fn", &testAdd1, .{ .exact = 1 });
    const tail = try gc1.allocPair(nf_val, types.NIL);
    const lst = try gc1.allocPair(nf_val, tail);

    const copied = try gc2.deepCopy(lst);
    const p1 = types.toObject(copied).as(types.Pair);
    const p2 = types.toObject(p1.cdr).as(types.Pair);
    try std.testing.expect(p1.car != nf_val);
    try std.testing.expectEqual(p1.car, p2.car);
}

// The thread-join! scenario from issue #958: the child GC is deinited right
// after the result is deep-copied to the parent. Before the fix, deepCopyValue
// returned the child-heap pointer for native_fn/native_closure, so the
// parent's result dangled into freed memory.
test "deepCopy native procedures survive freeing the source heap" {
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    var copied_fn: types.Value = undefined;
    var copied_nc: types.Value = undefined;
    {
        var gc1 = memory.GC.init(std.testing.allocator);
        defer gc1.deinit();
        const nf_val = try gc1.allocNativeFn("survive-add1", &testAdd1, .{ .exact = 1 });
        const upvalues = [_]types.Value{types.makeFixnum(5)};
        const nc_val = try gc1.allocNativeClosure(&testNativeClosureFn, &upvalues, 1, "survive-nc");
        copied_fn = try gc2.deepCopy(nf_val);
        copied_nc = try gc2.deepCopy(nc_val);
    }

    const nf = types.toObject(copied_fn).as(types.NativeFn);
    try std.testing.expectEqualStrings("survive-add1", nf.name);
    try std.testing.expectEqual(types.makeFixnum(42), try nf.func(&.{types.makeFixnum(41)}));

    const nc = types.toObject(copied_nc).as(types.NativeClosure);
    try std.testing.expectEqualStrings("survive-nc", nc.name);
    try std.testing.expectEqual(types.makeFixnum(5), nc.upvalues[0]);
}

test "deepCopy rejects port" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const port = try gc1.allocStringInputPort("test");
    try std.testing.expectError(error.UncopyableType, gc2.deepCopy(port));
}

test "deepCopy rejects continuation" {
    var gc1 = memory.GC.init(std.testing.allocator);
    defer gc1.deinit();
    var gc2 = memory.GC.init(std.testing.allocator);
    defer gc2.deinit();

    const cont = try gc1.allocEscapeContinuation(0, 0, 0, 0, 0);
    try std.testing.expectError(error.UncopyableType, gc2.deepCopy(cont));
}
