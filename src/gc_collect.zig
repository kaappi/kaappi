const std = @import("std");
const types = @import("types.zig");
const memory_mod = @import("memory.zig");
const GC = memory_mod.GC;

const Value = types.Value;
const Object = types.Object;
const Pair = types.Pair;
const Vector = types.Vector;
const Closure = types.Closure;
const Function = types.Function;
const Symbol = types.Symbol;
const SchemeString = types.SchemeString;
const NativeFn = types.NativeFn;
const Flonum = types.Flonum;
const Bytevector = types.Bytevector;
const Transformer = types.Transformer;
const RecordType = types.RecordType;
const RecordInstance = types.RecordInstance;
const Port = types.Port;
const Continuation = types.Continuation;
const MultipleValues = types.MultipleValues;
const Promise = types.Promise;
const HashTable = types.HashTable;
const FfiLibrary = types.FfiLibrary;
const FfiFunction = types.FfiFunction;
const FfiCallback = types.FfiCallback;
const Bignum = types.Bignum;
const Rational = types.Rational;
const RandomSource = types.RandomSource;

const build_options = @import("build_options");
const GC_THRESHOLD: usize = build_options.gc_initial_threshold;

fn clockNs() u64 {
    var ts: std.c.timespec = undefined;
    _ = std.c.clock_gettime(.MONOTONIC, &ts);
    return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
}

pub fn collect(gc: *GC) void {
    gc.stats.collections += 1;
    gc.minor_cycle_count += 1;

    const mark_start = clockNs();
    if (gc.minor_cycle_count >= 8) {
        gc.minor_cycle_count = 0;
        fullCollect(gc);
    } else {
        minorCollect(gc);
    }
    const mark_end = clockNs();
    gc.stats.total_mark_ns +%= mark_end -% mark_start;
    gc.gc_threshold = @max(GC_THRESHOLD, gc.object_count * 4);
}

fn minorCollect(gc: *GC) void {
    clearOldMarks(gc);
    markRoots(gc);
    for (gc.remembered_set.items) |obj| {
        markObjectContents(gc, obj);
    }
    sweepYoung(gc);
    pruneRememberedSet(gc);
}

fn clearOldMarks(gc: *GC) void {
    var obj = gc.old_objects;
    while (obj) |o| {
        o.marked = false;
        obj = o.next;
    }
}

fn pruneRememberedSet(gc: *GC) void {
    var write_idx: usize = 0;
    for (gc.remembered_set.items) |obj| {
        if (referencesYoung(obj)) {
            gc.remembered_set.items[write_idx] = obj;
            write_idx += 1;
        }
    }
    gc.remembered_set.shrinkRetainingCapacity(write_idx);
}

fn referencesYoung(obj: *Object) bool {
    switch (obj.tag) {
        .pair => {
            const pair = obj.as(Pair);
            if (isYoungPointer(pair.car) or isYoungPointer(pair.cdr)) return true;
        },
        .vector => {
            const vec = obj.as(types.Vector);
            for (vec.data) |item| {
                if (isYoungPointer(item)) return true;
            }
        },
        .record_instance => {
            const ri = obj.as(RecordInstance);
            if (isYoungPointer(types.makePointer(@ptrCast(ri.record_type)))) return true;
            for (ri.fields) |field| {
                if (isYoungPointer(field)) return true;
            }
        },
        .hash_table => {
            const ht = obj.as(HashTable);
            for (ht.entries[0..ht.capacity]) |entry| {
                if (entry.state == .occupied) {
                    if (isYoungPointer(entry.key) or isYoungPointer(entry.value)) return true;
                }
            }
        },
        .closure => {
            const cls = obj.as(Closure);
            if (isYoungPointer(types.makePointer(@ptrCast(cls.func)))) return true;
            for (cls.upvalues) |uv| {
                if (isYoungPointer(uv)) return true;
            }
        },
        .promise => {
            if (isYoungPointer(obj.as(Promise).value)) return true;
        },
        .parameter => {
            const param = obj.as(types.ParameterObject);
            if (isYoungPointer(param.value) or isYoungPointer(param.converter)) return true;
        },
        .transformer => {
            const tx = obj.as(Transformer);
            for (tx.literals) |lit| {
                if (isYoungPointer(lit)) return true;
            }
            for (tx.patterns) |pat| {
                if (isYoungPointer(pat)) return true;
            }
            for (tx.templates) |tmpl| {
                if (isYoungPointer(tmpl)) return true;
            }
            if (isYoungPointer(tx.def_env_val)) return true;
        },
        .error_object => {
            const err = obj.as(types.ErrorObject);
            if (isYoungPointer(err.message) or isYoungPointer(err.irritants) or isYoungPointer(err.uncaught_reason)) return true;
        },
        .continuation => {
            const cont = obj.as(Continuation);
            for (cont.registers) |reg| {
                if (isYoungPointer(reg)) return true;
            }
            for (cont.frames[0..cont.frame_count]) |frame| {
                if (frame.closure) |cls| {
                    if (isYoungPointer(types.makePointer(@ptrCast(cls)))) return true;
                }
                if (frame.native) |nf| {
                    if (isYoungPointer(types.makePointer(@ptrCast(nf)))) return true;
                }
            }
            for (cont.handlers[0..cont.handler_count]) |handler| {
                if (isYoungPointer(handler.handler)) return true;
            }
            for (cont.wind_records[0..cont.wind_count]) |wr| {
                if (isYoungPointer(wr.before) or isYoungPointer(wr.after)) return true;
            }
        },
        .multiple_values => {
            const mv = obj.as(MultipleValues);
            for (mv.values) |val| {
                if (isYoungPointer(val)) return true;
            }
        },
        .rational => {
            const rat = obj.as(Rational);
            if (isYoungPointer(rat.numerator) or isYoungPointer(rat.denominator)) return true;
        },
        .ffi_function => {
            if (isYoungPointer(obj.as(FfiFunction).library)) return true;
        },
        .ffi_callback => {
            if (isYoungPointer(obj.as(FfiCallback).closure)) return true;
        },
        .fiber => {
            const fiber_mod = @import("fiber.zig");
            const fiber = obj.as(fiber_mod.Fiber);
            if (isYoungPointer(fiber.thunk) or isYoungPointer(fiber.result) or
                isYoungPointer(fiber.waiting_on) or isYoungPointer(fiber.name) or
                isYoungPointer(fiber.specific)) return true;
            if (fiber.current_exception) |exc| {
                if (isYoungPointer(exc)) return true;
            }
            if (isYoungPointer(fiber.continuation_value)) return true;
            for (fiber.frames[0..fiber.frame_count]) |f| {
                if (f.closure) |cls| {
                    if (isYoungPointer(types.makePointer(@ptrCast(cls)))) return true;
                }
                if (f.native) |nf| {
                    if (isYoungPointer(types.makePointer(@ptrCast(nf)))) return true;
                }
                const window: usize = if (f.closure) |cls| blk: {
                    const lc = cls.func.locals_count;
                    break :blk if (lc == 0) 256 else @as(usize, lc);
                } else 256;
                const end: usize = @min(@as(usize, f.base) + window, fiber.registers.len);
                var r: usize = f.base;
                while (r < end) : (r += 1) {
                    if (isYoungPointer(fiber.registers[r])) return true;
                }
            }
            for (fiber.handler_stack[0..fiber.handler_count]) |h| {
                if (isYoungPointer(h.handler)) return true;
            }
            for (fiber.wind_stack[0..fiber.wind_count]) |wr| {
                if (isYoungPointer(wr.before) or isYoungPointer(wr.after)) return true;
            }
            var pit = fiber.param_overrides.valueIterator();
            while (pit.next()) |v| {
                if (isYoungPointer(v.*)) return true;
            }
        },
        .channel => {
            const ch = obj.as(types.Channel);
            if (isYoungPointer(ch.head) or isYoungPointer(ch.tail)) return true;
        },
        .mutex => {
            const m = obj.as(types.Mutex);
            if (isYoungPointer(m.name) or isYoungPointer(m.owner) or isYoungPointer(m.specific)) return true;
        },
        .condition_variable => {
            const cv = obj.as(types.ConditionVariable);
            if (isYoungPointer(cv.name) or isYoungPointer(cv.specific)) return true;
        },
        .function => {
            const func = obj.as(Function);
            for (func.constants.items) |c| {
                if (isYoungPointer(c)) return true;
            }
            if (func.global_cache) |cache| {
                for (cache) |c| {
                    if (isYoungPointer(c)) return true;
                }
            }
            if (isYoungPointer(func.env_val)) return true;
        },
        .native_closure => {
            const nc = obj.as(types.NativeClosure);
            for (nc.upvalues) |uv| {
                if (isYoungPointer(uv)) return true;
            }
        },
        .scheme_environment => {
            const se = obj.as(types.SchemeEnvironment);
            var vit = se.env.valueIterator();
            while (vit.next()) |val| {
                if (isYoungPointer(val.*)) return true;
            }
        },
        .symbol, .string, .native_fn, .flonum, .port, .complex, .bytevector, .bignum, .record_type, .ffi_library, .file_info, .user_info, .group_info, .directory_object, .random_source, .srfi18_time => {},
    }
    return false;
}

fn isYoungPointer(val: Value) bool {
    if (!types.isPointer(val)) return false;
    return types.toObject(val).generation == 0;
}

fn fullCollect(gc: *GC) void {
    clearOldMarks(gc);
    markRoots(gc);
    sweep(gc);
    sweepOld(gc);
    gc.remembered_set.clearRetainingCapacity();
}

fn sweepYoung(gc: *GC) void {
    var prev: ?*Object = null;
    var obj = gc.objects;
    while (obj) |o| {
        if (o.marked) {
            o.marked = false;
            o.survive_count +|= 1;
            if (o.survive_count >= 2) {
                const next = o.next;
                if (prev) |p| {
                    p.next = next;
                } else {
                    gc.objects = next;
                }
                o.generation = 1;
                o.survive_count = 0;
                o.next = gc.old_objects;
                gc.old_objects = o;
                obj = next;
            } else {
                prev = o;
                obj = o.next;
            }
        } else {
            const next = o.next;
            if (prev) |p| {
                p.next = next;
            } else {
                gc.objects = next;
            }
            const freed = objectSize(o);
            gc.stats.objects_freed += 1;
            gc.stats.bytes_freed += freed;
            if (gc.bytes_allocated >= freed)
                gc.bytes_allocated -= freed;
            freeObject(gc, o);
            gc.object_count -= 1;
            obj = next;
        }
    }
}

fn sweepOld(gc: *GC) void {
    var prev: ?*Object = null;
    var obj = gc.old_objects;
    while (obj) |o| {
        if (o.marked) {
            o.marked = false;
            prev = o;
            obj = o.next;
        } else {
            const next = o.next;
            if (prev) |p| {
                p.next = next;
            } else {
                gc.old_objects = next;
            }
            const freed = objectSize(o);
            gc.stats.objects_freed += 1;
            gc.stats.bytes_freed += freed;
            if (gc.bytes_allocated >= freed)
                gc.bytes_allocated -= freed;
            freeObject(gc, o);
            gc.object_count -= 1;
            obj = next;
        }
    }
}

fn markObjectContents(gc: *GC, obj: *Object) void {
    switch (obj.tag) {
        .pair => {
            const pair = obj.as(Pair);
            markValue(gc, pair.car);
            markValue(gc, pair.cdr);
        },
        .vector => {
            const vec = obj.as(Vector);
            for (vec.data) |v| markValue(gc, v);
        },
        .closure => {
            const cls = obj.as(Closure);
            markValue(gc, types.makePointer(@ptrCast(cls.func)));
            for (cls.upvalues) |uv| markValue(gc, uv);
        },
        .hash_table => {
            const ht = obj.as(HashTable);
            for (ht.entries[0..ht.capacity]) |entry| {
                if (entry.state == .occupied) {
                    markValue(gc, entry.key);
                    markValue(gc, entry.value);
                }
            }
        },
        .record_instance => {
            const ri = obj.as(RecordInstance);
            markValue(gc, types.makePointer(@ptrCast(ri.record_type)));
            for (ri.fields) |field| markValue(gc, field);
        },
        .promise => {
            const p = obj.as(Promise);
            markValue(gc, p.value);
        },
        .parameter => {
            const param = obj.as(types.ParameterObject);
            markValue(gc, param.value);
            markValue(gc, param.converter);
        },
        .transformer => {
            const tx = obj.as(Transformer);
            for (tx.literals) |lit| markValue(gc, lit);
            for (tx.patterns) |pat| markValue(gc, pat);
            for (tx.templates) |tmpl| markValue(gc, tmpl);
            markValue(gc, tx.def_env_val);
        },
        .error_object => {
            const err = obj.as(types.ErrorObject);
            markValue(gc, err.message);
            markValue(gc, err.irritants);
            markValue(gc, err.uncaught_reason);
        },
        .continuation => {
            const cont = obj.as(Continuation);
            for (cont.registers) |reg| markValue(gc, reg);
            for (cont.frames[0..cont.frame_count]) |frame| {
                if (frame.closure) |cls| markValue(gc, types.makePointer(@ptrCast(cls)));
                if (frame.native) |nf| markValue(gc, types.makePointer(@ptrCast(nf)));
            }
            for (cont.handlers[0..cont.handler_count]) |handler| markValue(gc, handler.handler);
            for (cont.wind_records[0..cont.wind_count]) |wr| {
                markValue(gc, wr.before);
                markValue(gc, wr.after);
            }
        },
        .multiple_values => {
            const mv = obj.as(MultipleValues);
            for (mv.values) |val| markValue(gc, val);
        },
        .rational => {
            const rat = obj.as(Rational);
            markValue(gc, rat.numerator);
            markValue(gc, rat.denominator);
        },
        .ffi_function => {
            const ffi_fn = obj.as(FfiFunction);
            markValue(gc, ffi_fn.library);
        },
        .ffi_callback => {
            const cb = obj.as(FfiCallback);
            markValue(gc, cb.closure);
        },
        .fiber => {
            const fiber_mod = @import("fiber.zig");
            const fiber = obj.as(fiber_mod.Fiber);
            fiber_mod.markFiberState(gc, fiber);
        },
        .channel => {
            const ch = obj.as(types.Channel);
            markValue(gc, ch.head);
            markValue(gc, ch.tail);
        },
        .mutex => {
            const m = obj.as(types.Mutex);
            markValue(gc, m.name);
            markValue(gc, m.owner);
            markValue(gc, m.specific);
        },
        .condition_variable => {
            const cv = obj.as(types.ConditionVariable);
            markValue(gc, cv.name);
            markValue(gc, cv.specific);
        },
        .function => {
            const func = obj.as(Function);
            for (func.constants.items) |c| markValue(gc, c);
            if (func.global_cache) |cache| {
                for (cache) |c| markValue(gc, c);
            }
            markValue(gc, func.env_val);
        },
        .native_closure => {
            const nc = obj.as(types.NativeClosure);
            for (nc.upvalues) |uv| markValue(gc, uv);
        },
        .scheme_environment => {
            const se = obj.as(types.SchemeEnvironment);
            var vit = se.env.valueIterator();
            while (vit.next()) |val| markValue(gc, val.*);
        },
        .symbol, .string, .native_fn, .flonum, .port, .complex, .bytevector, .bignum, .record_type, .ffi_library, .file_info, .user_info, .group_info, .directory_object, .random_source, .srfi18_time => {},
    }
}

fn markRoots(gc: *GC) void {
    for (gc.roots.items) |root| {
        markValue(gc, root.*);
    }
    for (gc.extra_roots.items) |v| {
        markValue(gc, v);
    }
    // Mark active FFI callback closures
    const ffi_cb = @import("ffi_callback.zig");
    ffi_cb.markCallbackRoots(gc);
    // Mark interned symbols. Use a blocking lock to prevent iterating
    // while another thread's put() rehashes the HashMap. Deadlock is not
    // possible: allocSymbol — the only other acquirer of symbol_mutex, taken
    // unconditionally by parent and child alike — never calls maybeCollect,
    // so a thread can never enter GC marking (which takes this same lock)
    // while already holding it in allocSymbol.
    memory_mod.spinLock(&memory_mod.symbol_mutex);
    defer memory_mod.spinUnlock(&memory_mod.symbol_mutex);
    var it = gc.symbols.valueIterator();
    while (it.next()) |v| {
        markValue(gc, v.*);
    }
    // Mark VM-owned roots (live registers, call frames, handlers, winds).
    if (gc.root_marker) |mark| mark(gc);
}

pub fn markValue(gc: *GC, v: Value) void {
    // Use an explicit worklist to avoid native stack overflow on deeply
    // nested pair/vector structures (issue #864). Values that would
    // previously be handled by a recursive markValue call are pushed
    // onto the worklist and processed iteratively.
    var worklist: std.ArrayList(Value) = .empty;
    defer worklist.deinit(gc.allocator);

    markValueInner(gc, v, &worklist);

    while (worklist.items.len > 0) {
        const item = worklist.pop().?;
        markValueInner(gc, item, &worklist);
    }
}

fn markValueInner(gc: *GC, v: Value, worklist: *std.ArrayList(Value)) void {
    var cur = v;
    while (true) {
        if (!types.isPointer(cur)) return;
        const obj = types.toObject(cur);
        if (obj.marked) return;
        obj.marked = true;

        if (obj.tag == .pair) {
            const pair = obj.as(Pair);
            const car = pair.car;
            const cdr = pair.cdr;
            const car_is_ptr = types.isPointer(car);
            const cdr_is_ptr = types.isPointer(cdr);
            if (car_is_ptr and cdr_is_ptr) {
                // Push car onto worklist instead of recursing -- this is
                // the key change that prevents stack overflow on deep
                // structures like (((((...)))))).
                worklist.append(gc.allocator, car) catch {};
                cur = cdr;
            } else if (cdr_is_ptr) {
                cur = cdr;
            } else {
                cur = car;
            }
            continue;
        }
        break;
    }

    // Non-pair heap object -- already marked above, now trace its fields.
    const obj = types.toObject(cur);
    switch (obj.tag) {
        .pair => unreachable,
        .closure => {
            const cls = obj.as(Closure);
            worklist.append(gc.allocator, types.makePointer(@ptrCast(cls.func))) catch {};
            for (cls.upvalues) |uv| {
                worklist.append(gc.allocator, uv) catch {};
            }
        },
        .function => {
            const func = obj.as(Function);
            for (func.constants.items) |c| {
                worklist.append(gc.allocator, c) catch {};
            }
            if (func.global_cache) |cache| {
                for (cache) |c| worklist.append(gc.allocator, c) catch {};
            }
            worklist.append(gc.allocator, func.env_val) catch {};
        },
        .transformer => {
            const tx = obj.as(Transformer);
            for (tx.literals) |lit| {
                worklist.append(gc.allocator, lit) catch {};
            }
            for (tx.patterns) |pat| {
                worklist.append(gc.allocator, pat) catch {};
            }
            for (tx.templates) |tmpl| {
                worklist.append(gc.allocator, tmpl) catch {};
            }
            worklist.append(gc.allocator, tx.def_env_val) catch {};
        },
        .error_object => {
            const err = obj.as(types.ErrorObject);
            worklist.append(gc.allocator, err.message) catch {};
            worklist.append(gc.allocator, err.irritants) catch {};
            worklist.append(gc.allocator, err.uncaught_reason) catch {};
        },
        .record_type => {},
        .record_instance => {
            const ri = obj.as(RecordInstance);
            worklist.append(gc.allocator, types.makePointer(@ptrCast(ri.record_type))) catch {};
            for (ri.fields) |field| {
                worklist.append(gc.allocator, field) catch {};
            }
        },
        .continuation => {
            const cont = obj.as(Continuation);
            for (cont.registers) |reg| {
                worklist.append(gc.allocator, reg) catch {};
            }
            for (cont.frames[0..cont.frame_count]) |frame| {
                if (frame.closure) |cls| {
                    worklist.append(gc.allocator, types.makePointer(@ptrCast(cls))) catch {};
                }
                if (frame.native) |nf| {
                    worklist.append(gc.allocator, types.makePointer(@ptrCast(nf))) catch {};
                }
            }
            for (cont.handlers[0..cont.handler_count]) |handler| {
                worklist.append(gc.allocator, handler.handler) catch {};
            }
            for (cont.wind_records[0..cont.wind_count]) |wr| {
                worklist.append(gc.allocator, wr.before) catch {};
                worklist.append(gc.allocator, wr.after) catch {};
            }
        },
        .multiple_values => {
            const mv = obj.as(MultipleValues);
            for (mv.values) |val| {
                worklist.append(gc.allocator, val) catch {};
            }
        },
        .vector => {
            const vec = obj.as(Vector);
            // Push all elements except the last onto the worklist;
            // iterate the last element directly via tail call.
            if (vec.data.len > 0) {
                for (vec.data[0 .. vec.data.len - 1]) |elem| {
                    worklist.append(gc.allocator, elem) catch {};
                }
                markValueInner(gc, vec.data[vec.data.len - 1], worklist);
            }
        },
        .promise => {
            const p = obj.as(Promise);
            worklist.append(gc.allocator, p.value) catch {};
        },
        .parameter => {
            const param = obj.as(types.ParameterObject);
            worklist.append(gc.allocator, param.value) catch {};
            worklist.append(gc.allocator, param.converter) catch {};
        },
        .hash_table => {
            const ht = obj.as(HashTable);
            for (ht.entries[0..ht.capacity]) |entry| {
                if (entry.state == .occupied) {
                    worklist.append(gc.allocator, entry.key) catch {};
                    worklist.append(gc.allocator, entry.value) catch {};
                }
            }
        },
        .rational => {
            const rat = obj.as(Rational);
            worklist.append(gc.allocator, rat.numerator) catch {};
            worklist.append(gc.allocator, rat.denominator) catch {};
        },
        .ffi_library => {},
        .ffi_function => {
            const ffi_fn = obj.as(FfiFunction);
            worklist.append(gc.allocator, ffi_fn.library) catch {};
        },
        .ffi_callback => {
            const cb = obj.as(FfiCallback);
            worklist.append(gc.allocator, cb.closure) catch {};
        },
        .fiber => {
            const fiber_mod = @import("fiber.zig");
            const fiber = obj.as(fiber_mod.Fiber);
            fiber_mod.markFiberState(gc, fiber);
        },
        .channel => {
            const ch = obj.as(types.Channel);
            worklist.append(gc.allocator, ch.head) catch {};
            worklist.append(gc.allocator, ch.tail) catch {};
        },
        .mutex => {
            const m = obj.as(types.Mutex);
            worklist.append(gc.allocator, m.name) catch {};
            worklist.append(gc.allocator, m.owner) catch {};
            worklist.append(gc.allocator, m.specific) catch {};
        },
        .condition_variable => {
            const cv = obj.as(types.ConditionVariable);
            worklist.append(gc.allocator, cv.name) catch {};
            worklist.append(gc.allocator, cv.specific) catch {};
        },
        .native_closure => {
            const nc = obj.as(types.NativeClosure);
            for (nc.upvalues) |uv| worklist.append(gc.allocator, uv) catch {};
        },
        .scheme_environment => {
            const se = obj.as(types.SchemeEnvironment);
            var vit = se.env.valueIterator();
            while (vit.next()) |val| worklist.append(gc.allocator, val.*) catch {};
        },
        .symbol, .string, .native_fn, .flonum, .port, .complex, .bytevector, .bignum, .file_info, .user_info, .group_info, .directory_object, .random_source, .srfi18_time => {},
    }
}

fn sweep(gc: *GC) void {
    var prev: ?*Object = null;
    var obj = gc.objects;
    while (obj) |o| {
        if (o.marked) {
            o.marked = false;
            prev = o;
            obj = o.next;
        } else {
            const next = o.next;
            if (prev) |p| {
                p.next = next;
            } else {
                gc.objects = next;
            }
            const freed = objectSize(o);
            gc.stats.objects_freed += 1;
            gc.stats.bytes_freed += freed;
            if (gc.bytes_allocated >= freed)
                gc.bytes_allocated -= freed;
            freeObject(gc, o);
            gc.object_count -= 1;
            obj = next;
        }
    }
}

fn objectSize(obj: *Object) usize {
    return switch (obj.tag) {
        .pair => @sizeOf(Pair),
        .symbol => @sizeOf(Symbol) + obj.as(Symbol).name.len,
        .string => @sizeOf(SchemeString) + obj.as(SchemeString).data.len,
        .closure => @sizeOf(Closure) + obj.as(Closure).upvalues.len * @sizeOf(Value),
        .function => blk: {
            const f = obj.as(Function);
            var s: usize = @sizeOf(Function);
            s += f.code.capacity;
            s += f.constants.capacity * @sizeOf(Value);
            if (f.global_cache) |c| s += c.len * @sizeOf(Value);
            break :blk s;
        },
        .native_fn => @sizeOf(NativeFn),
        .native_closure => @sizeOf(types.NativeClosure) + obj.as(types.NativeClosure).upvalues.len * @sizeOf(Value),
        .flonum => @sizeOf(Flonum),
        .vector => @sizeOf(Vector) + obj.as(Vector).data.len * @sizeOf(Value),
        .bytevector => @sizeOf(Bytevector) + obj.as(Bytevector).data.len,
        .transformer => blk: {
            const t = obj.as(Transformer);
            break :blk @sizeOf(Transformer) + t.literals.len * @sizeOf(Value) +
                t.patterns.len * @sizeOf(Value) + t.templates.len * @sizeOf(Value);
        },
        .error_object => @sizeOf(types.ErrorObject),
        .record_type => @sizeOf(RecordType) + obj.as(RecordType).name.len,
        .record_instance => @sizeOf(RecordInstance) + obj.as(RecordInstance).fields.len * @sizeOf(Value),
        .port => blk: {
            const port = obj.as(Port);
            var s: usize = @sizeOf(Port);
            if (port.owns_name) s += port.name.len;
            if (port.string_data) |sd| s += sd.len;
            if (port.string_out_buf) |_| s += port.string_out_cap;
            if (port.read_buf) |rb| s += rb.len;
            break :blk s;
        },
        .continuation => @sizeOf(Continuation) + obj.as(Continuation).backing.len * @sizeOf(Value),
        .multiple_values => @sizeOf(MultipleValues) + obj.as(MultipleValues).values.len * @sizeOf(Value),
        .complex => @sizeOf(types.Complex),
        .promise => @sizeOf(Promise),
        .parameter => @sizeOf(types.ParameterObject),
        .hash_table => @sizeOf(HashTable) + obj.as(HashTable).entries.len * @sizeOf(types.HashEntry),
        .ffi_library => @sizeOf(FfiLibrary) + obj.as(FfiLibrary).name.len,
        .ffi_function => blk: {
            const f = obj.as(FfiFunction);
            break :blk @sizeOf(FfiFunction) + f.name.len + f.param_types.len * @sizeOf(types.FfiType);
        },
        .ffi_callback => @sizeOf(FfiCallback),
        .bignum => @sizeOf(Bignum) + obj.as(Bignum).limbs.len * @sizeOf(u64),
        .rational => @sizeOf(Rational),
        .file_info => @sizeOf(types.FileInfo),
        .user_info => blk: {
            const ui = obj.as(types.UserInfo);
            break :blk @sizeOf(types.UserInfo) + ui.name.len + ui.home_dir.len + ui.shell.len + ui.full_name.len;
        },
        .group_info => @sizeOf(types.GroupInfo) + obj.as(types.GroupInfo).name.len,
        .directory_object => @sizeOf(types.DirectoryObject),
        .random_source => @sizeOf(RandomSource),
        .fiber => blk: {
            const fiber = obj.as(@import("fiber.zig").Fiber);
            break :blk @sizeOf(@import("fiber.zig").Fiber) +
                fiber.registers.len * @sizeOf(Value) +
                fiber.frames.len * @sizeOf(@import("vm.zig").CallFrame);
        },
        .channel => @sizeOf(types.Channel),
        .mutex => @sizeOf(types.Mutex),
        .condition_variable => @sizeOf(types.ConditionVariable),
        .srfi18_time => @sizeOf(types.Srfi18Time),
        .scheme_environment => @sizeOf(types.SchemeEnvironment),
    };
}

pub fn freeObject(gc: *GC, obj: *Object) void {
    switch (obj.tag) {
        .pair => {
            const pair = obj.as(Pair);
            gc.allocator.destroy(pair);
        },
        .symbol => {
            const sym = obj.as(Symbol);
            gc.allocator.free(sym.name);
            gc.allocator.destroy(sym);
        },
        .string => {
            const str = obj.as(SchemeString);
            gc.allocator.free(str.data);
            gc.allocator.destroy(str);
        },
        .closure => {
            const cls = obj.as(Closure);
            gc.allocator.free(cls.upvalues);
            gc.allocator.destroy(cls);
        },
        .function => {
            const func = obj.as(Function);
            func.code.deinit(gc.allocator);
            func.constants.deinit(gc.allocator);
            func.line_table.deinit(gc.allocator);
            if (func.global_cache) |cache| {
                gc.allocator.free(cache);
            }
            if (func.debug_locals.len > 0) {
                gc.allocator.free(func.debug_locals);
            }
            if (func.owns_name) {
                if (func.name) |n| gc.allocator.free(n);
            }
            gc.allocator.destroy(func);
        },
        .native_fn => {
            const nf = obj.as(NativeFn);
            gc.allocator.destroy(nf);
        },
        .native_closure => {
            const nc = obj.as(types.NativeClosure);
            gc.allocator.free(nc.upvalues);
            gc.allocator.destroy(nc);
        },
        .flonum => {
            const flo = obj.as(Flonum);
            gc.allocator.destroy(flo);
        },
        .vector => {
            const vec = obj.as(Vector);
            gc.allocator.free(vec.data);
            gc.allocator.destroy(vec);
        },
        .transformer => {
            const tx = obj.as(Transformer);
            gc.allocator.free(tx.literals);
            gc.allocator.free(tx.patterns);
            gc.allocator.free(tx.templates);
            if (tx.captured_locals.len > 0) gc.allocator.free(tx.captured_locals);
            gc.allocator.destroy(tx);
        },
        .error_object => {
            const err = obj.as(types.ErrorObject);
            gc.allocator.destroy(err);
        },
        .record_type => {
            const rt = obj.as(RecordType);
            gc.allocator.free(rt.name);
            gc.allocator.destroy(rt);
        },
        .record_instance => {
            const ri = obj.as(RecordInstance);
            gc.allocator.free(ri.fields);
            gc.allocator.destroy(ri);
        },
        .bytevector => {
            const bv = obj.as(Bytevector);
            gc.allocator.free(bv.data);
            gc.allocator.destroy(bv);
        },
        .promise => {
            const p = obj.as(Promise);
            gc.allocator.destroy(p);
        },
        .port => {
            const port = obj.as(Port);
            // Close the fd if still open and not stdin/stdout/stderr
            if (port.is_open and port.fd > 2 and !port.is_string_port) {
                _ = std.posix.system.close(port.fd);
            }
            if (port.owns_name) {
                gc.allocator.free(port.name);
            }
            if (port.read_buf) |rb| {
                gc.allocator.free(rb);
            }
            // Free string port buffers
            if (port.string_data) |sd| {
                gc.allocator.free(sd);
            }
            if (port.string_out_buf) |sb| {
                gc.allocator.free(sb);
            }
            gc.allocator.destroy(port);
        },
        .continuation => {
            const cont = obj.as(Continuation);
            // registers/frames/handlers/wind_records are all views into
            // the single backing allocation; free it once. Escape
            // continuations have no backing (empty slice).
            if (cont.backing.len > 0) gc.allocator.free(cont.backing);
            gc.allocator.destroy(cont);
        },
        .multiple_values => {
            const mv = obj.as(MultipleValues);
            gc.allocator.free(mv.values);
            gc.allocator.destroy(mv);
        },
        .complex => {
            const c = obj.as(types.Complex);
            gc.allocator.destroy(c);
        },
        .parameter => {
            const p = obj.as(types.ParameterObject);
            gc.allocator.destroy(p);
        },
        .hash_table => {
            const ht = obj.as(HashTable);
            gc.allocator.free(ht.entries);
            gc.allocator.destroy(ht);
        },
        .ffi_library => {
            const lib = obj.as(FfiLibrary);
            // Do NOT dlclose here -- let ffi-close handle that explicitly
            gc.allocator.free(lib.name);
            gc.allocator.destroy(lib);
        },
        .ffi_function => {
            const ffi_fn = obj.as(FfiFunction);
            gc.allocator.free(ffi_fn.name);
            gc.allocator.free(ffi_fn.param_types);
            gc.allocator.destroy(ffi_fn);
        },
        .ffi_callback => {
            const cb = obj.as(FfiCallback);
            if (cb.active) {
                const ffi_cb = @import("ffi_callback.zig");
                ffi_cb.releaseSlot(cb.slot_index);
            }
            gc.allocator.destroy(cb);
        },
        .bignum => {
            const bn = obj.as(Bignum);
            gc.allocator.free(bn.limbs);
            gc.allocator.destroy(bn);
        },
        .rational => {
            const rat = obj.as(Rational);
            gc.allocator.destroy(rat);
        },
        .file_info => {
            const fi = obj.as(types.FileInfo);
            gc.allocator.destroy(fi);
        },
        .user_info => {
            const ui = obj.as(types.UserInfo);
            gc.allocator.free(ui.name);
            gc.allocator.free(ui.home_dir);
            gc.allocator.free(ui.shell);
            gc.allocator.free(ui.full_name);
            gc.allocator.destroy(ui);
        },
        .group_info => {
            const gi = obj.as(types.GroupInfo);
            gc.allocator.free(gi.name);
            gc.allocator.destroy(gi);
        },
        .directory_object => {
            const d = obj.as(types.DirectoryObject);
            if (d.dir) |dir| {
                _ = std.c.closedir(@ptrCast(@alignCast(dir)));
                d.dir = null;
            }
            gc.allocator.destroy(d);
        },
        .random_source => {
            gc.allocator.destroy(obj.as(RandomSource));
        },
        .fiber => {
            const fiber = obj.as(@import("fiber.zig").Fiber);
            fiber.param_overrides.deinit();
            gc.allocator.free(fiber.frames);
            gc.allocator.free(fiber.registers);
            gc.allocator.destroy(fiber);
        },
        .channel => {
            gc.allocator.destroy(obj.as(types.Channel));
        },
        .mutex => {
            gc.allocator.destroy(obj.as(types.Mutex));
        },
        .condition_variable => {
            gc.allocator.destroy(obj.as(types.ConditionVariable));
        },
        .srfi18_time => {
            gc.allocator.destroy(obj.as(types.Srfi18Time));
        },
        .scheme_environment => {
            const se = obj.as(types.SchemeEnvironment);
            if (se.owned) {
                se.env.deinit();
                gc.allocator.destroy(se.env);
            }
            gc.allocator.destroy(se);
        },
    }
}
