const std = @import("std");
const types = @import("types.zig");
const memory_mod = @import("memory.zig");
const hashtable = @import("primitives_hashtable.zig");
const shared_channel = @import("shared_channel.zig");

const GC = memory_mod.GC;
const Value = types.Value;

/// Explicit (not inferred) so shared_channel.zig's Envelope.create ->
/// GC.deepCopy -> gc_deep_copy.deepCopy -> deepCopyValue ->
/// shared_channel.promoteChannel -> Envelope.create call chain doesn't form
/// an unresolvable inferred-error-set cycle: promoteChannel/Envelope.create
/// need to know deepCopy's error set before deepCopy's own inference (which
/// recurses into promoteChannel for the .channel arm) can complete.
pub const DeepCopyError = error{ OutOfMemory, UncopyableType };

pub fn deepCopy(gc: *GC, src: Value) DeepCopyError!Value {
    if (!types.isPointer(src)) return src;
    var visited = std.AutoHashMap(usize, Value).init(gc.allocator);
    defer visited.deinit();
    return deepCopyValue(gc, src, &visited);
}

fn deepCopyValue(gc: *GC, src: Value, visited: *std.AutoHashMap(usize, Value)) DeepCopyError!Value {
    if (!types.isPointer(src)) return src;

    const src_ptr = @intFromPtr(types.toObject(src));
    if (visited.get(src_ptr)) |already| return already;

    gc.no_collect += 1;
    defer gc.no_collect -= 1;

    const obj = types.toObject(src);
    return switch (obj.tag) {
        .pair => {
            // Iterate the cdr spine in a loop rather than recursing on it, so
            // copying a flat list of N elements uses O(1) native stack frames
            // instead of N (issue #801). Only the car branch recurses, bounding
            // native recursion by structural nesting depth, not list length.
            // The GC marker was fixed the same way for issue #864.
            const head_new = try gc.allocPair(types.NIL, types.NIL);
            try visited.put(src_ptr, head_new);

            var src_pair = obj.as(types.Pair);
            var dst_pair = types.toObject(head_new).as(types.Pair);
            while (true) {
                dst_pair.car = try deepCopyValue(gc, src_pair.car, visited);

                const cdr = src_pair.cdr;
                if (!types.isPointer(cdr)) {
                    // Immediate tail (nil for a proper list, or a non-pointer
                    // improper tail) -- copy directly, no allocation.
                    dst_pair.cdr = cdr;
                    break;
                }
                const cdr_obj = types.toObject(cdr);
                if (cdr_obj.tag != .pair) {
                    // Improper list ending in a heap object -- recurse once.
                    dst_pair.cdr = try deepCopyValue(gc, cdr, visited);
                    break;
                }
                const cdr_ptr = @intFromPtr(cdr_obj);
                if (visited.get(cdr_ptr)) |already| {
                    // Shared or cyclic cdr already copied -- reuse it.
                    dst_pair.cdr = already;
                    break;
                }
                // Extend the spine: allocate the next pair, register it in
                // `visited` before copying its car so cycles resolve correctly.
                const next_new = try gc.allocPair(types.NIL, types.NIL);
                dst_pair.cdr = next_new;
                try visited.put(cdr_ptr, next_new);
                src_pair = cdr_obj.as(types.Pair);
                dst_pair = types.toObject(next_new).as(types.Pair);
            }
            return head_new;
        },
        .symbol => try gc.allocSymbol(obj.as(types.Symbol).name),
        .string => {
            const s = obj.as(types.SchemeString);
            const new_val = try gc.allocString(s.data[0..s.len]);
            try visited.put(src_ptr, new_val);
            return new_val;
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
        .bytevector => {
            const new_val = try gc.allocBytevector(obj.as(types.Bytevector).data);
            try visited.put(src_ptr, new_val);
            return new_val;
        },
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
            new_func.env_val = types.NIL;
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
            new_ht.compare_mode = ht.compare_mode;
            new_ht.equiv_fn = try deepCopyValue(gc, ht.equiv_fn, visited);
            new_ht.hash_fn = try deepCopyValue(gc, ht.hash_fn, visited);
            if (ht.compare_mode == .custom) {
                // Preserve slot positions for custom hash tables since we
                // can't call the custom hash_fn during deep copy.
                for (ht.entries[0..ht.capacity], 0..) |entry, i| {
                    if (entry.state == .occupied) {
                        new_ht.entries[i] = .{
                            .key = try deepCopyValue(gc, entry.key, visited),
                            .value = try deepCopyValue(gc, entry.value, visited),
                            .state = .occupied,
                        };
                        new_ht.count += 1;
                    } else {
                        new_ht.entries[i].state = entry.state;
                    }
                }
            } else {
                for (ht.entries[0..ht.capacity]) |entry| {
                    if (entry.state == .occupied) {
                        const nk = try deepCopyValue(gc, entry.key, visited);
                        const nv = try deepCopyValue(gc, entry.value, visited);
                        var idx = hashtable.hashForMode(new_ht.compare_mode, nk) & (new_ht.capacity - 1);
                        while (new_ht.entries[idx].state == .occupied) {
                            idx = (idx + 1) & (new_ht.capacity - 1);
                        }
                        new_ht.entries[idx] = .{ .key = nk, .value = nv, .state = .occupied };
                        new_ht.count += 1;
                    }
                }
            }
            return new_val;
        },
        .promise => {
            const p = obj.as(types.Promise);
            const new_val = try gc.allocPromise(p.forced, types.NIL);
            try visited.put(src_ptr, new_val);
            const new_p = types.toObject(new_val).as(types.Promise);
            new_p.value = try deepCopyValue(gc, p.value, visited);
            return new_val;
        },
        .parameter => {
            const p = obj.as(types.ParameterObject);
            const new_val = try gc.allocParameter(types.NIL, types.NIL);
            try visited.put(src_ptr, new_val);
            const new_p = types.toObject(new_val).as(types.ParameterObject);
            new_p.value = try deepCopyValue(gc, p.value, visited);
            new_p.converter = try deepCopyValue(gc, p.converter, visited);
            return new_val;
        },
        .error_object => {
            const e = obj.as(types.ErrorObject);
            const new_val = try gc.allocErrorObject(types.NIL, types.NIL);
            try visited.put(src_ptr, new_val);
            const new_e = types.toObject(new_val).as(types.ErrorObject);
            new_e.error_type = e.error_type;
            new_e.message = try deepCopyValue(gc, e.message, visited);
            new_e.irritants = try deepCopyValue(gc, e.irritants, visited);
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
            const new_val = try gc.allocMultipleValues(mv.values);
            try visited.put(src_ptr, new_val);
            const new_mv = types.toObject(new_val).as(types.MultipleValues);
            for (mv.values, 0..) |v, i| {
                new_mv.values[i] = try deepCopyValue(gc, v, visited);
            }
            return new_val;
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
            new_tx.def_env_val = t.def_env_val;
            if (t.let_syntax_peer_vals.len > 0) {
                const peer_vals = try gc.allocator.alloc(Value, t.let_syntax_peer_vals.len);
                errdefer gc.allocator.free(peer_vals);
                for (t.let_syntax_peer_vals, 0..) |v, i| peer_vals[i] = try deepCopyValue(gc, v, visited);
                const peer_names = gc.allocator.dupe([]const u8, t.let_syntax_peer_names) catch return error.OutOfMemory;
                new_tx.let_syntax_peer_vals = peer_vals;
                new_tx.let_syntax_peer_names = peer_names;
            }
            return new_val;
        },
        .native_fn => {
            // The fn pointer and name are static (registered with string
            // literals, or rodata in a native binary), but the NativeFn object
            // itself lives in the source heap. Copy it so a thread result
            // survives the child heap being freed after thread-join!.
            const nf = obj.as(types.NativeFn);
            const new_val = try gc.allocNativeFn(nf.name, nf.func, nf.arity);
            try visited.put(src_ptr, new_val);
            return new_val;
        },
        .native_closure => {
            // fn_ptr and name are static (code and rodata of a native binary),
            // but the object and its upvalues live in the source heap.
            const nc = obj.as(types.NativeClosure);
            const placeholders = try gc.allocator.alloc(Value, nc.upvalues.len);
            defer gc.allocator.free(placeholders);
            @memset(placeholders, types.VOID);
            const new_val = try gc.allocNativeClosure(nc.fn_ptr, placeholders, nc.arity, nc.name);
            try visited.put(src_ptr, new_val);
            const new_nc = types.toObject(new_val).as(types.NativeClosure);
            for (nc.upvalues, 0..) |uv, i| {
                new_nc.upvalues[i] = try deepCopyValue(gc, uv, visited);
            }
            return new_val;
        },
        // FFI objects wrap process-global dlopen handles that cannot be
        // duplicated per-heap, so they are aliased. Known limitation: an FFI
        // handle created inside a child thread and returned through
        // thread-join! dangles once the child heap is freed.
        .ffi_library, .ffi_function => src,
        .srfi18_time => {
            const t = obj.as(types.Srfi18Time);
            return try gc.allocSrfi18Time(t.seconds, t.nanoseconds, t.time_type);
        },
        .random_source => {
            const rs = obj.as(types.RandomSource);
            const new_val = try gc.allocRandomSource(0);
            const new_rs = types.toObject(new_val).as(types.RandomSource);
            new_rs.prng = rs.prng;
            return new_val;
        },
        // KEP-0002 §2: a channel is promoted (if not already) and aliased,
        // never rejected outright. `gc` here is the *destination* heap, not
        // the channel's owner -- ownership (invariant 4: promotion is legal
        // only for the thread that owns the channel) is checked against
        // `memory_mod.gc_instance`, the threadlocal for whichever thread is
        // actually executing this copy. A foreign, not-yet-promoted channel
        // reuses UncopyableType rather than a new error class, so
        // thread-start!/thread-join! (primitives_srfi18.zig) -- whose
        // deepCopy calls run on the destination thread, never the channel's
        // owner, until KEP-0002 Phase 2 moves the thunk copy to the parent
        // thread -- keep today's exact behavior and error message.
        .channel => {
            const ch = obj.as(types.Channel);
            // Aliasing an already-promoted stub needs no ownership check
            // (and no memory_mod.gc_instance at all) -- any thread that
            // legitimately holds a stub Value may pass it along further.
            // Only a not-yet-promoted channel needs the current-thread
            // check, since promoting is the operation invariant 4 restricts.
            const sc = if (ch.shared) |s|
                @as(*shared_channel.SharedChannel, @ptrCast(@alignCast(s)))
            else blk: {
                const current_gc = memory_mod.gc_instance orelse return error.UncopyableType;
                if (obj.owner != current_gc.id) return error.UncopyableType;
                break :blk try shared_channel.promoteChannel(current_gc, ch);
            };
            sc.retain();
            const new_val = try gc.allocChannelStub(sc);
            try visited.put(src_ptr, new_val);
            return new_val;
        },
        .port,
        .continuation,
        .fiber,
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
