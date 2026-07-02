const std = @import("std");
const types = @import("types.zig");
const memory_mod = @import("memory.zig");
const hashtable = @import("primitives_hashtable.zig");

const GC = memory_mod.GC;
const Value = types.Value;

pub fn deepCopy(gc: *GC, src: Value) !Value {
    if (!types.isPointer(src)) return src;
    var visited = std.AutoHashMap(usize, Value).init(gc.allocator);
    defer visited.deinit();
    return deepCopyValue(gc, src, &visited);
}

fn deepCopyValue(gc: *GC, src: Value, visited: *std.AutoHashMap(usize, Value)) !Value {
    if (!types.isPointer(src)) return src;

    const src_ptr = @intFromPtr(types.toObject(src));
    if (visited.get(src_ptr)) |already| return already;

    gc.no_collect += 1;
    defer gc.no_collect -= 1;

    const obj = types.toObject(src);
    return switch (obj.tag) {
        .pair => {
            const pair = obj.as(types.Pair);
            const new_val = try gc.allocPair(types.NIL, types.NIL);
            try visited.put(src_ptr, new_val);
            const new_pair = types.toObject(new_val).as(types.Pair);
            new_pair.car = try deepCopyValue(gc, pair.car, visited);
            new_pair.cdr = try deepCopyValue(gc, pair.cdr, visited);
            return new_val;
        },
        .symbol => try gc.allocSymbol(obj.as(types.Symbol).name),
        .string => {
            const s = obj.as(types.SchemeString);
            return try gc.allocString(s.data[0..s.len]);
        },
        .vector => {
            const vec = obj.as(types.Vector);
            const new_val = try gc.allocVectorFill(vec.data.len, types.VOID);
            try visited.put(src_ptr, new_val);
            const new_vec = types.toObject(new_val).as(types.Vector);
            for (vec.data, 0..) |elem, i| {
                new_vec.data[i] = try deepCopyValue(gc, elem, visited);
            }
            return new_val;
        },
        .bytevector => try gc.allocBytevector(obj.as(types.Bytevector).data),
        .flonum => try gc.allocFlonum(obj.as(types.Flonum).value),
        .complex => {
            const c = obj.as(types.Complex);
            return try gc.allocComplexEx(c.real, c.imag, c.exact_real, c.exact_imag);
        },
        .bignum => {
            const bn = obj.as(types.Bignum);
            return try gc.allocBignumFromLimbs(bn.limbs[0..bn.len], bn.len, bn.positive);
        },
        .rational => {
            const r = obj.as(types.Rational);
            const num = try deepCopyValue(gc, r.numerator, visited);
            const den = try deepCopyValue(gc, r.denominator, visited);
            return try gc.allocRational(num, den);
        },
        .closure => {
            const cl = obj.as(types.Closure);
            const func_val = types.makePointer(@ptrCast(cl.func));
            const new_func_val = try deepCopyValue(gc, func_val, visited);
            const new_func = types.toObject(new_func_val).as(types.Function);
            const new_val = try gc.allocClosure(new_func);
            try visited.put(src_ptr, new_val);
            const new_cl = types.toObject(new_val).as(types.Closure);
            for (cl.upvalues, 0..) |uv, i| {
                new_cl.upvalues[i] = try deepCopyValue(gc, uv, visited);
            }
            return new_val;
        },
        .function => {
            const func = obj.as(types.Function);
            const new_func = try gc.allocFunction();
            const new_val = types.makePointer(@ptrCast(new_func));
            try visited.put(src_ptr, new_val);
            new_func.arity = func.arity;
            new_func.locals_count = func.locals_count;
            new_func.upvalue_count = func.upvalue_count;
            new_func.is_variadic = func.is_variadic;
            new_func.source_line = func.source_line;
            new_func.source_name = func.source_name;
            new_func.global_cache = null;
            new_func.env = null;
            if (func.name) |name| {
                if (func.owns_name) {
                    const dup = try gc.allocator.alloc(u8, name.len);
                    @memcpy(dup, name);
                    new_func.name = dup;
                    new_func.owns_name = true;
                } else {
                    new_func.name = name;
                }
            }
            new_func.code.appendSlice(gc.allocator, func.code.items) catch return error.OutOfMemory;
            for (func.constants.items) |c| {
                const nc = try deepCopyValue(gc, c, visited);
                new_func.constants.append(gc.allocator, nc) catch return error.OutOfMemory;
            }
            if (func.debug_locals.len > 0) {
                const dl = try gc.allocator.alloc(types.DebugLocal, func.debug_locals.len);
                @memcpy(dl, func.debug_locals);
                new_func.debug_locals = dl;
            }
            for (func.line_table.items) |entry| {
                new_func.line_table.append(gc.allocator, entry) catch {};
            }
            return new_val;
        },
        .hash_table => {
            const ht = obj.as(types.HashTable);
            const new_val = try gc.allocHashTable(ht.capacity);
            try visited.put(src_ptr, new_val);
            const new_ht = types.toObject(new_val).as(types.HashTable);
            for (ht.entries[0..ht.capacity]) |entry| {
                if (entry.state == .occupied) {
                    const nk = try deepCopyValue(gc, entry.key, visited);
                    const nv = try deepCopyValue(gc, entry.value, visited);
                    var idx = hashtable.valueHash(nk) & (new_ht.capacity - 1);
                    while (new_ht.entries[idx].state == .occupied) {
                        idx = (idx + 1) & (new_ht.capacity - 1);
                    }
                    new_ht.entries[idx] = .{ .key = nk, .value = nv, .state = .occupied };
                    new_ht.count += 1;
                }
            }
            return new_val;
        },
        .promise => {
            const p = obj.as(types.Promise);
            const nv = try deepCopyValue(gc, p.value, visited);
            return try gc.allocPromise(p.forced, nv);
        },
        .parameter => {
            const p = obj.as(types.ParameterObject);
            const val = try deepCopyValue(gc, p.value, visited);
            const conv = try deepCopyValue(gc, p.converter, visited);
            return try gc.allocParameter(val, conv);
        },
        .error_object => {
            const e = obj.as(types.ErrorObject);
            const msg = try deepCopyValue(gc, e.message, visited);
            const irr = try deepCopyValue(gc, e.irritants, visited);
            const new_val = try gc.allocErrorObject(msg, irr);
            const new_e = types.toObject(new_val).as(types.ErrorObject);
            new_e.error_type = e.error_type;
            new_e.uncaught_reason = try deepCopyValue(gc, e.uncaught_reason, visited);
            return new_val;
        },
        .record_type => {
            const rt = obj.as(types.RecordType);
            const new_val = try gc.allocRecordType(rt.name, rt.num_fields);
            try visited.put(src_ptr, new_val);
            return new_val;
        },
        .record_instance => {
            const ri = obj.as(types.RecordInstance);
            const rt_val = types.makePointer(@ptrCast(ri.record_type));
            const new_rt_val = try deepCopyValue(gc, rt_val, visited);
            const new_rt = types.toObject(new_rt_val).as(types.RecordType);
            const new_val = try gc.allocRecordInstance(new_rt, &.{});
            try visited.put(src_ptr, new_val);
            const new_ri = types.toObject(new_val).as(types.RecordInstance);
            for (ri.fields, 0..) |f, i| {
                new_ri.fields[i] = try deepCopyValue(gc, f, visited);
            }
            return new_val;
        },
        .multiple_values => {
            const mv = obj.as(types.MultipleValues);
            const vals = try gc.allocator.alloc(Value, mv.values.len);
            for (mv.values, 0..) |v, i| {
                vals[i] = try deepCopyValue(gc, v, visited);
            }
            const new_mv = try gc.allocator.create(types.MultipleValues);
            new_mv.* = .{ .header = .{ .tag = .multiple_values }, .values = vals };
            gc.trackObject(&new_mv.header);
            return types.makePointer(@ptrCast(new_mv));
        },
        .transformer => {
            const t = obj.as(types.Transformer);
            const tmp_lits = try gc.allocator.alloc(Value, t.literals.len);
            defer gc.allocator.free(tmp_lits);
            for (t.literals, 0..) |v, i| tmp_lits[i] = try deepCopyValue(gc, v, visited);
            const tmp_pats = try gc.allocator.alloc(Value, t.patterns.len);
            defer gc.allocator.free(tmp_pats);
            for (t.patterns, 0..) |v, i| tmp_pats[i] = try deepCopyValue(gc, v, visited);
            const tmp_tmpls = try gc.allocator.alloc(Value, t.templates.len);
            defer gc.allocator.free(tmp_tmpls);
            for (t.templates, 0..) |v, i| tmp_tmpls[i] = try deepCopyValue(gc, v, visited);
            const new_val = try gc.allocTransformer(tmp_lits, tmp_pats, tmp_tmpls);
            try visited.put(src_ptr, new_val);
            const new_tx = types.toObject(new_val).as(types.Transformer);
            if (t.custom_ellipsis) |ce| {
                new_tx.custom_ellipsis = gc.allocator.dupe(u8, ce) catch null;
            }
            if (t.captured_locals.len > 0) {
                new_tx.captured_locals = gc.allocator.dupe(types.CapturedLocal, t.captured_locals) catch &.{};
            }
            new_tx.def_env = t.def_env;
            return new_val;
        },
        .native_fn, .native_closure, .ffi_library, .ffi_function => src,
        .srfi18_time => try gc.allocSrfi18Time(obj.as(types.Srfi18Time).seconds),
        .random_source => {
            const rs = obj.as(types.RandomSource);
            const new_val = try gc.allocRandomSource(0);
            const new_rs = types.toObject(new_val).as(types.RandomSource);
            new_rs.prng = rs.prng;
            return new_val;
        },
        .port,
        .continuation,
        .fiber,
        .channel,
        .mutex,
        .condition_variable,
        .ffi_callback,
        .file_info,
        .user_info,
        .group_info,
        .directory_object,
        .scheme_environment,
        => return error.UncopyableType,
    };
}
