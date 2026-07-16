const std = @import("std");
const ir = @import("ir.zig");
const types = @import("types.zig");
const printer = @import("printer.zig");

const llvm_emit = @import("llvm_emit.zig");
const LLVMEmitter = llvm_emit.LLVMEmitter;
const EmitError = llvm_emit.EmitError;

const Value = types.Value;

// The runtime encodes a native closure's arity and each upvalue slot index as a
// u8 (see kaappi_create_native_closure and NativeLambda.arity), so 255 is a real
// ceiling — not an arbitrary buffer size. The per-function scratch arrays below
// grow on the emitter's arena instead of living in fixed stack buffers (#1498);
// a function past this many fixed params or captured upvalues still falls back
// to the interpreter, but only for a limit the runtime actually imposes.
const max_native_arity = std.math.maxInt(u8);

pub fn emitLambda(self: *LLVMEmitter, data: ir.LambdaData) EmitError![]const u8 {
    if (tryCompileNativeClosure(self, data)) |result| return result;
    if (tryCompilePureLambdaAsNativeClosure(self, data)) |result| return result;
    return emitLambdaViaEval(self, data);
}

fn tryCompilePureLambdaAsNativeClosure(self: *LLVMEmitter, data: ir.LambdaData) ?[]const u8 {
    const formals_val = types.car(data.args);
    const body_list = types.cdr(data.args);
    if (body_list == types.NIL) return null;
    if (!types.isPair(formals_val) and formals_val != types.NIL) return null;

    // #827: reject if body contains forms needing interpreter eval fallback
    {
        var be = body_list;
        while (be != types.NIL and types.isPair(be)) : (be = types.cdr(be)) {
            if (sexprNeedsEvalFallback(types.car(be))) return null;
        }
    }

    var param_names: std.ArrayList([]const u8) = .empty;
    var rest_name: ?[]const u8 = null;
    var plist = formals_val;
    while (plist != types.NIL) {
        if (!types.isPair(plist)) {
            if (types.isSymbol(plist)) {
                rest_name = types.symbolName(plist);
                break;
            }
            return null;
        }
        const p = types.car(plist);
        if (!types.isSymbol(p)) return null;
        param_names.append(self.allocator(), types.symbolName(p)) catch return null;
        plist = types.cdr(plist);
    }

    if (rest_name != null) return null;
    if (param_names.items.len > max_native_arity) return null;

    // #1497: a param that is both set! and captured by a nested lambda is
    // assignment-converted to a heap box rather than rejected.
    const boxed = analyzeBoxedParams(self, body_list, param_names.items, null) orelse return null;
    if (boxed.rest_conflict) return null;

    var body_ir = ir.IR.init(self.allocator());
    defer body_ir.deinit();
    // Parameters shadow primitives of the same name; don't fold calls to them
    // using the built-in's semantics (issue #790).
    body_ir.bound_names = param_names.items;
    var body_nodes: std.ArrayList(*ir.Node) = .empty;
    var body_expr = body_list;
    while (body_expr != types.NIL and types.isPair(body_expr)) {
        const expr = types.car(body_expr);
        // Boxed frames are lowered non-tail so box roots can be popped at a
        // single ret (see emitLambdaFunction).
        const is_tail = !boxed.any and types.cdr(body_expr) == types.NIL;
        const opt = ir.lowerAndOptimize(&body_ir, expr, null, is_tail) catch return null;
        body_nodes.append(self.allocator(), opt) catch return null;
        body_expr = types.cdr(body_expr);
    }
    if (body_nodes.items.len == 0) return null;

    if (hasFreeVars(self, body_nodes.items, param_names.items)) return null;

    const fn_name = emitLambdaFunction(self, data.name, param_names.items, body_nodes.items, rest_name, boxed) orelse return null;

    const closure_name = data.name orelse "(lambda)";
    const name_str = self.internString(closure_name) catch return null;
    const result = self.freshTemp() catch return null;
    self.print("  {s} = call i64 @kaappi_create_native_closure(ptr %vm, ptr {s}, ptr null, i64 0, i64 {d}, ptr {s}, i64 {d})\n", .{ result, fn_name, param_names.items.len, name_str, closure_name.len }) catch return null;
    return result;
}

fn tryCompileNativeClosure(self: *LLVMEmitter, data: ir.LambdaData) ?[]const u8 {
    const formals_val = types.car(data.args);
    const body_list = types.cdr(data.args);
    if (body_list == types.NIL) return null;
    if (!types.isPair(formals_val) and formals_val != types.NIL) return null;

    // An internal define in a closure body needs a locals scope the closure
    // tier does not set up, so reject it (#819). A set! is now allowed: a
    // captured binding it mutates is assignment-converted to a box by the
    // enclosing frame (#1497), and a set! of the closure's own param/local
    // resolves to that slot. The per-free-variable guard below refuses any
    // set! of a captured variable that was NOT boxed, so a by-value upvalue is
    // never mutated in place.
    {
        var be = body_list;
        while (be != types.NIL and types.isPair(be)) : (be = types.cdr(be)) {
            if (sexprContainsDefine(types.car(be))) return null;
        }
    }

    // #827: reject if body contains forms needing interpreter eval fallback
    {
        var be2 = body_list;
        while (be2 != types.NIL and types.isPair(be2)) : (be2 = types.cdr(be2)) {
            if (sexprNeedsEvalFallback(types.car(be2))) return null;
        }
    }

    var param_names: std.ArrayList([]const u8) = .empty;
    var plist = formals_val;
    while (plist != types.NIL) {
        if (!types.isPair(plist)) return null;
        const p = types.car(plist);
        if (!types.isSymbol(p)) return null;
        param_names.append(self.allocator(), types.symbolName(p)) catch return null;
        plist = types.cdr(plist);
    }
    if (param_names.items.len > max_native_arity) return null;

    // The closure's own params may themselves be captured+mutated by a lambda
    // nested inside this closure (double nesting), needing their own boxes.
    const own_boxed = analyzeBoxedParams(self, body_list, param_names.items, null) orelse return null;

    var body_ir = ir.IR.init(self.allocator());
    defer body_ir.deinit();
    // Parameters shadow primitives of the same name; don't fold calls to them
    // using the built-in's semantics (issue #790).
    body_ir.bound_names = param_names.items;
    var body_nodes: std.ArrayList(*ir.Node) = .empty;
    var body_expr = body_list;
    while (body_expr != types.NIL and types.isPair(body_expr)) {
        const expr = types.car(body_expr);
        // A closure with own boxed params lowers non-tail so its box roots pop
        // at a single ret (see the closure body emission below).
        const is_tail = !own_boxed.any and types.cdr(body_expr) == types.NIL;
        const opt = ir.lowerAndOptimize(&body_ir, expr, null, is_tail) catch return null;
        body_nodes.append(self.allocator(), opt) catch return null;
        body_expr = types.cdr(body_expr);
    }
    if (body_nodes.items.len == 0) return null;

    var free_vars: std.ArrayList([]const u8) = .empty;
    if (!collectFreeVars(self, body_nodes.items, param_names.items, &free_vars)) return null;
    if (free_vars.items.len == 0) return null;
    // Each capture becomes a u8-indexed upvalue slot (see uv_map below), so the
    // runtime's per-closure upvalue ceiling applies here too.
    if (free_vars.items.len > max_native_arity) return null;

    const outer_params = self.params orelse return null;
    const outer_upvalues = self.upvalues;
    const outer_boxes = self.boxes;
    // Classify each capture: a variable the enclosing frame boxed is captured
    // as the box POINTER (fv_boxed), so a set! from any sibling closure over
    // the same binding is visible here; everything else is captured by value.
    const fv_boxed = self.allocator().alloc(bool, free_vars.items.len) catch return null;
    @memset(fv_boxed, false);
    for (free_vars.items, 0..) |fv, i| {
        if (outer_boxes) |ob| {
            if (ob.contains(fv)) {
                fv_boxed[i] = true;
                continue;
            }
        }
        // A set! of a captured variable that was NOT boxed would mutate the
        // by-value upvalue copy alone, diverging from the interpreter's
        // by-location semantics (#1422). Refuse; the interpreter handles it.
        if (sexprBodySetsName(body_list, fv)) return null;
        // By-value captures are copied out of the enclosing frame at
        // closure-creation time: params from its %args, and — when this lambda
        // sits inside another native closure — chained captures from that
        // closure's own %upvalues array (#1410). A name bound by an enclosing
        // let-local or rest parameter has no capturable slot; reject those.
        if (localsOrRestShadows(self, fv)) return null;
        if (outer_params.contains(fv)) continue;
        if (outer_upvalues) |uv| {
            if (uv.contains(fv)) continue;
        }
        return null;
    }

    const id = self.lambda_counter;
    self.lambda_counter += 1;
    const fn_name = std.fmt.allocPrint(self.allocator(), "@closure_{d}", .{id}) catch return null;
    const closure_name = data.name orelse "(closure)";

    var fn_buf: std.ArrayList(u8) = .empty;
    {
        const saved = self.saveScope();
        defer self.restoreScope(saved);
        self.buf = .empty;
        self.tmp_counter = 0;
        self.label_counter = 0;
        self.current_fn_name = null;
        self.body_label = null;
        self.current_block = "entry";
        // The enclosing function's let-locals and rest parameter are not in
        // scope inside this closure's body; leaking them would misresolve
        // names against the wrong frame's allocas.
        self.locals = null;
        self.rest_param_name = null;
        self.rest_param_alloca = null;

        var p = std.StringHashMap(u8).init(self.backing_alloc);
        defer p.deinit();
        for (param_names.items, 0..) |pname, i| {
            p.put(pname, @intCast(i)) catch return null;
        }

        // Every collected free variable passed the capture check above, so
        // each one has a slot in the upvalue array this closure is created
        // with (params-sourced and chained captures alike).
        var uv_map = std.StringHashMap(u8).init(self.backing_alloc);
        defer uv_map.deinit();
        for (free_vars.items, 0..) |fv, i| {
            uv_map.put(fv, @intCast(i)) catch return null;
        }
        self.params = p;
        self.upvalues = uv_map;

        // Boxed captures and own boxed params get a fresh box map for this
        // frame; reads/writes go through kaappi_box_ref / kaappi_box_set.
        self.boxes = if (own_boxed.any or freeVarsAnyBoxed(fv_boxed))
            std.StringHashMap([]const u8).init(self.backing_alloc)
        else
            null;
        defer if (self.boxes) |*b| b.deinit();
        self.frame_entry_roots = 0;
        // A fresh frame starts with no let-binding roots (#1585); saveScope
        // restored the enclosing value on exit.
        self.body_scope_roots = 0;

        const header = std.fmt.allocPrint(self.allocator(), "; closure: {s}\ndefine i64 {s}(ptr %vm, ptr %args, i64 %nargs, ptr %upvalues) {{\nentry:\n", .{ closure_name, fn_name }) catch return null;
        defer self.allocator().free(header);
        self.write(header) catch return null;

        // A boxed captured variable's box pointer lives in its upvalue slot;
        // mirror it into a local alloca so name resolution reads/writes it
        // through the box. No GC root needed — the box stays reachable via the
        // live closure's upvalue array for the whole call.
        for (free_vars.items, 0..) |fv, i| {
            if (!fv_boxed[i]) continue;
            const box_alloca = self.freshTemp() catch return null;
            self.print("  {s} = alloca i64, align 8\n", .{box_alloca}) catch return null;
            const gep = self.freshTemp() catch return null;
            self.print("  {s} = getelementptr i64, ptr %upvalues, i64 {d}\n", .{ gep, i }) catch return null;
            const boxptr = self.freshTemp() catch return null;
            self.print("  {s} = load i64, ptr {s}\n", .{ boxptr, gep }) catch return null;
            self.print("  store i64 {s}, ptr {s}\n", .{ boxptr, box_alloca }) catch return null;
            (self.boxes orelse return null).put(fv, box_alloca) catch return null;
        }

        if (own_boxed.any and !emitBoxedParamSlots(self, param_names.items, own_boxed)) return null;

        var last_val: []const u8 = "";
        for (body_nodes.items) |node| {
            last_val = self.emitNode(node) catch return null;
        }

        if (self.frame_entry_roots > 0) {
            self.print("  call void @kaappi_gc_pop_roots(i64 {d})\n", .{self.frame_entry_roots}) catch return null;
        }
        self.print("  ret i64 {s}\n}}\n", .{last_val}) catch return null;

        fn_buf = self.buf;
    }

    const fn_def = fn_buf.toOwnedSlice(self.backing_alloc) catch return null;
    self.lambda_defs.append(self.backing_alloc, fn_def) catch return null;

    const uv_alloca = self.freshTemp() catch return null;
    self.print("  {s} = alloca [{d} x i64], align 8\n", .{ uv_alloca, free_vars.items.len }) catch return null;
    for (free_vars.items, 0..) |fv, i| {
        const val = blk: {
            // A boxed capture is stored as its box POINTER, loaded from the
            // enclosing frame's box slot; the box's contents (the live value)
            // are shared, so a set! from any closure over it is visible (#1497).
            if (fv_boxed[i]) {
                const box_alloca = outer_boxes.?.get(fv).?;
                const v = self.freshTemp() catch return null;
                self.print("  {s} = load i64, ptr {s}\n", .{ v, box_alloca }) catch return null;
                break :blk v;
            }
            if (outer_params.get(fv)) |idx| {
                const gep_src = self.freshTemp() catch return null;
                self.print("  {s} = getelementptr i64, ptr %args, i64 {d}\n", .{ gep_src, idx }) catch return null;
                const v = self.freshTemp() catch return null;
                self.print("  {s} = load i64, ptr {s}\n", .{ v, gep_src }) catch return null;
                break :blk v;
            }
            // Chained capture (#1410): the value lives in the enclosing
            // closure's own upvalue array, not in its %args.
            const idx = outer_upvalues.?.get(fv).?;
            const gep_src = self.freshTemp() catch return null;
            self.print("  {s} = getelementptr i64, ptr %upvalues, i64 {d}\n", .{ gep_src, idx }) catch return null;
            const v = self.freshTemp() catch return null;
            self.print("  {s} = load i64, ptr {s}\n", .{ v, gep_src }) catch return null;
            break :blk v;
        };
        const gep_dst = self.freshTemp() catch return null;
        self.print("  {s} = getelementptr i64, ptr {s}, i64 {d}\n", .{ gep_dst, uv_alloca, i }) catch return null;
        self.print("  store i64 {s}, ptr {s}\n", .{ val, gep_dst }) catch return null;
    }

    const name_str = self.internString(closure_name) catch return null;
    const result = self.freshTemp() catch return null;
    self.print("  {s} = call i64 @kaappi_create_native_closure(ptr %vm, ptr {s}, ptr {s}, i64 {d}, i64 {d}, ptr {s}, i64 {d})\n", .{ result, fn_name, uv_alloca, free_vars.items.len, param_names.items.len, name_str, closure_name.len }) catch return null;
    return result;
}

// Bind every name reachable in the current native frame — fixed params, the
// rest parameter, and captured upvalues — as globals, so a form that falls
// back to kaappi_eval (which runs in the global environment) still resolves
// them. Leaving any of them out surfaces as "undefined variable" (or a
// silently wrong value when a same-named global exists) at run time (#1410).
pub fn bindParamsAsGlobals(self: *LLVMEmitter) EmitError!void {
    // A boxed captured variable cannot be republished as a global: a global
    // holds a by-value snapshot, and re-reading a boxed param/upvalue here
    // would capture the value *before* a later set!, reintroducing the exact
    // #1422 divergence (seen when a captured+mutated variable is captured by a
    // lambda that itself falls back to eval — e.g. a variadic inner lambda).
    // Signal failure so the whole enclosing native frame aborts and the
    // interpreter, which honors by-location semantics, handles it (#1497).
    if (self.boxes) |bx| {
        if (bx.count() > 0) {
            if (self.params) |p| {
                var it = p.keyIterator();
                while (it.next()) |k| {
                    if (bx.contains(k.*)) return error.UnsupportedNodeType;
                }
            }
            if (self.upvalues) |uv| {
                var it = uv.keyIterator();
                while (it.next()) |k| {
                    if (bx.contains(k.*)) return error.UnsupportedNodeType;
                }
            }
        }
    }
    if (self.params) |p| {
        var iter = p.iterator();
        while (iter.next()) |entry| {
            const pname = entry.key_ptr.*;
            const idx = entry.value_ptr.*;
            const sym = try self.internSymbol(pname);
            const gep = try self.freshTemp();
            try self.print("  {s} = getelementptr i64, ptr %args, i64 {d}\n", .{ gep, idx });
            const val = try self.freshTemp();
            try self.print("  {s} = load i64, ptr {s}\n", .{ val, gep });
            try self.print("  call void @kaappi_define_global(ptr %vm, ptr {s}, i64 {d}, i64 {s})\n", .{ sym, pname.len, val });
        }
    }
    if (self.rest_param_name) |rp| {
        if (self.rest_param_alloca) |alloca| {
            const sym = try self.internSymbol(rp);
            const val = try self.freshTemp();
            try self.print("  {s} = load i64, ptr {s}\n", .{ val, alloca });
            try self.print("  call void @kaappi_define_global(ptr %vm, ptr {s}, i64 {d}, i64 {s})\n", .{ sym, rp.len, val });
        }
    }
    if (self.upvalues) |uv| {
        var iter = uv.iterator();
        while (iter.next()) |entry| {
            const uname = entry.key_ptr.*;
            const idx = entry.value_ptr.*;
            const sym = try self.internSymbol(uname);
            const gep = try self.freshTemp();
            try self.print("  {s} = getelementptr i64, ptr %upvalues, i64 {d}\n", .{ gep, idx });
            const val = try self.freshTemp();
            try self.print("  {s} = load i64, ptr {s}\n", .{ val, gep });
            try self.print("  call void @kaappi_define_global(ptr %vm, ptr {s}, i64 {d}, i64 {s})\n", .{ sym, uname.len, val });
        }
    }
}

fn emitLambdaViaEval(self: *LLVMEmitter, data: ir.LambdaData) EmitError![]const u8 {
    // #827: Inside a lexical scope with local bindings (a let body),
    // evaluating the lambda in the global environment would lose those
    // bindings.  Signal failure so the enclosing let falls back to the
    // interpreter, which handles scoping correctly.
    if (self.locals != null) return error.UnsupportedNodeType;

    try bindParamsAsGlobals(self);

    var source_buf: std.ArrayList(u8) = .empty;
    defer source_buf.deinit(self.backing_alloc);
    source_buf.appendSlice(self.backing_alloc, "(lambda ") catch return error.OutOfMemory;

    var current = data.args;
    var first = true;
    while (current != types.NIL and types.isPair(current)) {
        if (!first) source_buf.append(self.backing_alloc, ' ') catch return error.OutOfMemory;
        first = false;
        const elem = types.car(current);
        const elem_str = printer.valueToString(self.backing_alloc, elem, .write) catch return error.OutOfMemory;
        defer self.backing_alloc.free(elem_str);
        source_buf.appendSlice(self.backing_alloc, elem_str) catch return error.OutOfMemory;
        current = types.cdr(current);
    }
    source_buf.append(self.backing_alloc, ')') catch return error.OutOfMemory;

    return self.emitCachedEval(source_buf.items);
}

pub fn tryCompileLambdaNative(self: *LLVMEmitter, data: ir.LambdaData) ?[]const u8 {
    const formals = types.car(data.args);
    const body_list = types.cdr(data.args);
    if (body_list == types.NIL) return null;
    if (!types.isPair(formals) and formals != types.NIL) return null;
    return tryCompileDefineFunction(self, data.name orelse "(lambda)", formals, body_list);
}

pub fn tryCompileDefineFunction(self: *LLVMEmitter, name: []const u8, formals: Value, body: Value) ?[]const u8 {
    if (body == types.NIL) return null;

    // #827: reject if body contains forms needing interpreter eval fallback
    {
        var be = body;
        while (be != types.NIL and types.isPair(be)) : (be = types.cdr(be)) {
            if (sexprNeedsEvalFallback(types.car(be))) return null;
        }
    }

    var param_names: std.ArrayList([]const u8) = .empty;
    var rest_name: ?[]const u8 = null;
    var param_list = formals;
    while (param_list != types.NIL) {
        if (!types.isPair(param_list)) {
            if (types.isSymbol(param_list)) {
                rest_name = types.symbolName(param_list);
                break;
            }
            return null;
        }
        const param = types.car(param_list);
        if (!types.isSymbol(param)) return null;
        param_names.append(self.allocator(), types.symbolName(param)) catch return null;
        param_list = types.cdr(param_list);
    }
    if (param_names.items.len > max_native_arity) return null;

    // #1497: params that are both set! and captured by a nested lambda are
    // assignment-converted to heap boxes. A captured+mutated rest parameter
    // has no box model yet — fall back to the interpreter for it.
    const boxed = analyzeBoxedParams(self, body, param_names.items, rest_name) orelse return null;
    if (boxed.rest_conflict) return null;

    var body_ir = ir.IR.init(self.allocator());
    defer body_ir.deinit();
    // Parameters (including a rest parameter) shadow primitives of the same
    // name; don't fold calls to them using the built-in's semantics (#790).
    if (rest_name) |rn| {
        var bound_names: std.ArrayList([]const u8) = .empty;
        bound_names.appendSlice(self.allocator(), param_names.items) catch return null;
        bound_names.append(self.allocator(), rn) catch return null;
        body_ir.bound_names = bound_names.items;
    } else {
        body_ir.bound_names = param_names.items;
    }

    var body_nodes: std.ArrayList(*ir.Node) = .empty;
    var body_expr = body;
    while (body_expr != types.NIL and types.isPair(body_expr)) {
        const expr = types.car(body_expr);
        // Boxed frames lower non-tail so box roots pop at a single ret.
        const is_tail = !boxed.any and types.cdr(body_expr) == types.NIL;
        const opt = ir.lowerAndOptimize(&body_ir, expr, null, is_tail) catch return null;
        body_nodes.append(self.allocator(), opt) catch return null;
        body_expr = types.cdr(body_expr);
    }
    if (body_nodes.items.len == 0) return null;

    // Names that are NOT free in the body: the fixed params, the rest parameter
    // (if any), and the function's own name (a self-reference is a direct call,
    // not a capture).
    var allowed: std.ArrayList([]const u8) = .empty;
    allowed.appendSlice(self.allocator(), param_names.items) catch return null;
    if (rest_name) |rn| allowed.append(self.allocator(), rn) catch return null;
    allowed.append(self.allocator(), name) catch return null;
    if (hasFreeVars(self, body_nodes.items, allowed.items)) return null;

    return emitLambdaFunction(self, name, param_names.items, body_nodes.items, rest_name, boxed);
}

fn emitLambdaFunction(self: *LLVMEmitter, name: ?[]const u8, param_names: []const []const u8, body_nodes: []const *ir.Node, rest_name: ?[]const u8, boxed: BoxAnalysis) ?[]const u8 {
    const id = self.lambda_counter;
    self.lambda_counter += 1;

    // Snapshot the module-monotonic code-eval-fallback counter so we can tell,
    // after emitting this function's body, whether it reached one (its nested
    // lambdas emit into lambda_defs but share this counter). Recorded on the
    // native_fns entry as has_eval_fallback so the #1500 value materialization
    // can decline a function whose body's bindParamsAsGlobals would alias.
    const eval_cache_start = self.eval_cache_counter;

    // #1499: a fixed-arity, non-variadic, non-boxed *named* function within the
    // fast-arity bound gets a register-argument `tailcc` fast entry (holding the
    // body) plus a uniform C-ABI trampoline. Direct callers reach the fast entry
    // — and, in tail position from another fast entry, via a guaranteed
    // `musttail`. Everything else keeps the single uniform array-ABI entry.
    const use_fast = llvm_emit.fast_tailcalls_supported and
        name != null and
        rest_name == null and
        !boxed.any and
        param_names.len <= llvm_emit.max_fast_arity;

    // A reserved name (preScanReserve) gives forward mutual tail calls a stable
    // @r{i}.fast target. Use the reserved name pair for the first (only) define
    // of a reserved name; otherwise a fresh @lambda_{id} pair.
    var reserved: ?*llvm_emit.ReservedFast = if (name) |n| self.reserved_fast.getPtr(n) else null;
    if (reserved) |rp| {
        if (rp.consumed) reserved = null;
    }

    const base_name = if (reserved) |rp|
        rp.base
    else
        std.fmt.allocPrint(self.allocator(), "@lambda_{d}", .{id}) catch return null;
    const fast_name = if (reserved) |rp|
        rp.fast
    else
        std.fmt.allocPrint(self.allocator(), "@lambda_{d}.fast", .{id}) catch return null;

    if (name) |n| {
        self.native_fns.put(n, .{
            .llvm_name = base_name,
            .arity = @intCast(param_names.len),
            .is_variadic = rest_name != null,
            .fast_name = if (use_fast) fast_name else null,
        }) catch {};
    }

    // native_fns is registered up front so a self-recursive tail call in the
    // body can resolve to it, but body emission can still fail (e.g. an eval
    // fallback that captures a boxed variable, #1497). If it does, remove the
    // stale entry — otherwise a call site would emit a direct call to a function
    // that was never defined.
    var success = false;
    defer if (!success) {
        if (name) |n| _ = self.native_fns.fetchRemove(n);
    };

    var fn_buf: std.ArrayList(u8) = .empty;
    {
        const saved = self.saveScope();
        defer self.restoreScope(saved);
        self.buf = .empty;
        self.tmp_counter = 0;
        self.label_counter = 0;
        self.locals = null;
        // This function is closed — it receives null for %upvalues at run
        // time — so an upvalue map inherited from the enclosing emission
        // scope must not leak into body emission or bindParamsAsGlobals.
        self.upvalues = null;
        // A fresh box map for this frame's own boxed params (assignment
        // conversion, #1497). The enclosing frame's boxes are out of scope in
        // a closed function.
        self.boxes = if (boxed.any) std.StringHashMap([]const u8).init(self.backing_alloc) else null;
        defer if (self.boxes) |*b| b.deinit();
        self.frame_entry_roots = 0;
        // A fresh frame starts with no let-binding roots (#1585); saveScope
        // restored the enclosing value on exit.
        self.body_scope_roots = 0;
        // A tail call in this body may be a guaranteed `musttail` only from a
        // `tailcc` fast entry (#1499).
        self.in_fast_entry = use_fast;

        var p = std.StringHashMap(u8).init(self.backing_alloc);
        defer p.deinit();
        for (param_names, 0..) |pname, i| {
            p.put(pname, @intCast(i)) catch return null;
        }
        self.params = p;

        const body_lbl = std.fmt.allocPrint(self.allocator(), "body_{d}", .{id}) catch return null;

        // A boxed frame disables the self-tail-call loop: each activation needs
        // its own fresh boxes, and the body is lowered non-tail so there is a
        // single ret at which to pop the frame roots. A variadic frame keeps the
        // loop — its rest list is rebuilt per iteration by the self-tail-call
        // (see emitSelfTailCall), which is why the arity check there uses `>=`.
        self.current_fn_name = if (!boxed.any) name else null;
        self.body_label = if (!boxed.any) body_lbl else null;
        self.rest_param_name = rest_name;
        self.rest_param_alloca = null;

        // Function signature. The fast entry takes its arguments by value in
        // registers; the uniform entry takes the caller's args array. Both make
        // the body read parameters from `%args`, so body emission below is
        // identical — the fast entry just materializes that `%args` locally.
        if (use_fast) {
            self.print("; {s} (fast entry)\ndefine tailcc i64 {s}(ptr %vm", .{ name orelse "(lambda)", fast_name }) catch return null;
            for (0..param_names.len) |i| self.print(", i64 %a{d}", .{i}) catch return null;
            self.write(", ptr %upvalues) {\nentry:\n") catch return null;
        } else {
            const header = std.fmt.allocPrint(self.allocator(), "; {s}\ndefine i64 {s}(ptr %vm, ptr %args, i64 %nargs, ptr %upvalues) {{\nentry:\n", .{ name orelse "(lambda)", base_name }) catch return null;
            defer self.allocator().free(header);
            self.write(header) catch return null;
        }
        self.current_block = "entry";

        // Fast-entry prologue: copy the register arguments into a local %args
        // array so the rest of the body — param resolution, the self-tail loop's
        // in-place overwrite, bindParamsAsGlobals — reads/writes `%args`
        // unchanged. The array is this frame's own; outgoing tail calls pass
        // argument *values*, never a pointer into it, so `musttail` stays sound.
        if (use_fast and param_names.len > 0) {
            self.print("  %args = alloca [{d} x i64], align 8\n", .{param_names.len}) catch return null;
            for (0..param_names.len) |i| {
                const gep = self.freshTemp() catch return null;
                self.print("  {s} = getelementptr i64, ptr %args, i64 {d}\n", .{ gep, i }) catch return null;
                self.print("  store i64 %a{d}, ptr {s}\n", .{ i, gep }) catch return null;
            }
        }

        // Build the rest list once, in the entry block, BEFORE branching to the
        // body label. The self-tail loop branches back to body_lbl, so keeping
        // the builder out of that block stops it re-running each iteration — its
        // allocas would otherwise grow the stack per iteration and it would
        // clobber the rest list the self-call just rebuilt. (Never runs for a
        // fast entry, which is non-variadic.)
        if (rest_name != null) {
            emitRestListBuilder(self, param_names.len) catch return null;
        }

        self.print("  br label %{s}\n{s}:\n", .{ body_lbl, body_lbl }) catch return null;
        self.current_block = body_lbl;

        if (boxed.any and !emitBoxedParamSlots(self, param_names, boxed)) return null;

        var last_val: []const u8 = "";
        for (body_nodes) |node| {
            last_val = self.emitNode(node) catch return null;
        }

        if (self.frame_entry_roots > 0) {
            self.print("  call void @kaappi_gc_pop_roots(i64 {d})\n", .{self.frame_entry_roots}) catch return null;
        }
        self.print("  ret i64 {s}\n}}\n", .{last_val}) catch return null;

        fn_buf = self.buf;
    }

    const fn_def = fn_buf.toOwnedSlice(self.backing_alloc) catch return null;
    self.lambda_defs.append(self.backing_alloc, fn_def) catch return null;

    // Uniform C-ABI trampoline: unpacks the caller's args array and tail-calls
    // the fast entry. This is what kaappi_create_native_closure stores for
    // indirect dispatch (callNativeClosure invokes the uniform signature). It is
    // `internal`, so LLVM drops it when a define's value is materialized via the
    // interpreter and nothing takes its address (#1499).
    if (use_fast) {
        emitFastTrampoline(self, base_name, fast_name, param_names.len) catch return null;
    }

    if (reserved) |rp| {
        rp.consumed = true;
        // Record that this reserved name's @r{i}.fast got a real body, so no
        // forwarding stub is emitted for it at finalization.
        if (use_fast) self.fulfilled_fast.put(name.?, {}) catch {};
    }

    // Record whether the body reached a code eval fallback, for #1500's value
    // materialization gate. The entry was put before body emission (so a
    // self-call resolves); update it in place now that the counter delta is known.
    if (name) |n| {
        if (self.native_fns.getPtr(n)) |e| {
            e.has_eval_fallback = self.eval_cache_counter > eval_cache_start;
        }
    }

    success = true;
    return base_name;
}

// The uniform C-ABI shim (`@base`) around a fast entry (`@fast`): load each
// argument from the caller's %args array and tail-call the register-argument
// fast entry (#1499). Emitted into its own buffer and appended to lambda_defs.
fn emitFastTrampoline(self: *LLVMEmitter, base_name: []const u8, fast_name: []const u8, arity: usize) EmitError!void {
    const saved_buf = self.buf;
    const saved_tmp = self.tmp_counter;
    self.buf = .empty;
    self.tmp_counter = 0;
    defer {
        self.buf = saved_buf;
        self.tmp_counter = saved_tmp;
    }

    try self.print("; trampoline: {s}\ndefine internal i64 {s}(ptr %vm, ptr %args, i64 %nargs, ptr %upvalues) {{\nentry:\n", .{ base_name, base_name });
    const arg_tmps = self.allocator().alloc([]const u8, arity) catch return error.OutOfMemory;
    for (0..arity) |i| {
        const gep = try self.freshTemp();
        try self.print("  {s} = getelementptr i64, ptr %args, i64 {d}\n", .{ gep, i });
        const v = try self.freshTemp();
        try self.print("  {s} = load i64, ptr {s}\n", .{ v, gep });
        arg_tmps[i] = v;
    }
    const result = try self.freshTemp();
    try self.print("  {s} = call tailcc i64 {s}(ptr %vm", .{ result, fast_name });
    for (arg_tmps) |a| try self.print(", i64 {s}", .{a});
    try self.write(", ptr %upvalues)\n");
    try self.print("  ret i64 {s}\n}}\n", .{result});

    const def = self.buf.toOwnedSlice(self.backing_alloc) catch return error.OutOfMemory;
    self.lambda_defs.append(self.backing_alloc, def) catch return error.OutOfMemory;
}

fn emitRestListBuilder(self: *LLVMEmitter, fixed_arity: usize) EmitError!void {
    const rest_alloca = try self.freshTemp();
    try self.print("  {s} = alloca i64, align 8\n", .{rest_alloca});
    self.rest_param_alloca = rest_alloca;

    const nil_tmp = try self.emitImm(@bitCast(types.NIL));
    try self.print("  store i64 {s}, ptr {s}\n", .{ nil_tmp, rest_alloca });

    // GC-root the rest slot for the whole frame: the freshly-consed spine is not
    // reachable any other way (its elements are, via %args, but the pairs are
    // not), so an allocation in the body that does not itself mention the rest
    // list would otherwise collect it. Rooting the slot (not a snapshot) also
    // covers the variadic self-tail loop, which overwrites this slot each
    // iteration — GC always marks the current list. Popped before every `ret`
    // via frame_entry_roots (#1498).
    try self.print("  call void @kaappi_gc_push_root(ptr {s})\n", .{rest_alloca});
    self.frame_entry_roots += 1;

    const lbl_id = self.label_counter;
    self.label_counter += 1;
    const check_lbl = try std.fmt.allocPrint(self.allocator(), "rest_check_{d}", .{lbl_id});
    const body_lbl = try std.fmt.allocPrint(self.allocator(), "rest_body_{d}", .{lbl_id});
    const done_lbl = try std.fmt.allocPrint(self.allocator(), "rest_done_{d}", .{lbl_id});

    const idx_alloca = try self.freshTemp();
    try self.print("  {s} = alloca i64, align 8\n", .{idx_alloca});
    const nargs_minus_1 = try self.freshTemp();
    try self.print("  {s} = sub i64 %nargs, 1\n", .{nargs_minus_1});
    try self.print("  store i64 {s}, ptr {s}\n", .{ nargs_minus_1, idx_alloca });
    try self.print("  br label %{s}\n", .{check_lbl});

    try self.print("{s}:\n", .{check_lbl});
    self.current_block = check_lbl;
    const cur_idx = try self.freshTemp();
    try self.print("  {s} = load i64, ptr {s}\n", .{ cur_idx, idx_alloca });
    const cmp = try self.freshTemp();
    try self.print("  {s} = icmp sge i64 {s}, {d}\n", .{ cmp, cur_idx, fixed_arity });
    try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cmp, body_lbl, done_lbl });

    try self.print("{s}:\n", .{body_lbl});
    self.current_block = body_lbl;
    const gep = try self.freshTemp();
    try self.print("  {s} = getelementptr i64, ptr %args, i64 {s}\n", .{ gep, cur_idx });
    const val = try self.freshTemp();
    try self.print("  {s} = load i64, ptr {s}\n", .{ val, gep });
    const acc = try self.freshTemp();
    try self.print("  {s} = load i64, ptr {s}\n", .{ acc, rest_alloca });
    const new_pair = try self.freshTemp();
    try self.print("  {s} = call i64 @kaappi_cons(i64 {s}, i64 {s})\n", .{ new_pair, val, acc });
    try self.print("  store i64 {s}, ptr {s}\n", .{ new_pair, rest_alloca });
    const dec_idx = try self.freshTemp();
    try self.print("  {s} = sub i64 {s}, 1\n", .{ dec_idx, cur_idx });
    try self.print("  store i64 {s}, ptr {s}\n", .{ dec_idx, idx_alloca });
    try self.print("  br label %{s}\n", .{check_lbl});

    try self.print("{s}:\n", .{done_lbl});
    self.current_block = done_lbl;
}

// --- Eval-fallback detection helpers ---

// True if `expr` (a raw S-expression) contains any form that the LLVM native
// backend cannot compile and would dispatch to emitSexprEval.  Used by
// emitLet and emitLambdaFunction to reject native compilation of the
// enclosing scope when a sub-form would cross the native/interpreted boundary,
// losing lexical bindings (#827).
pub fn sexprNeedsEvalFallback(expr: Value) bool {
    if (!types.isPair(expr)) return false;
    const head = types.car(expr);
    if (types.isSymbol(head)) {
        const name = types.symbolName(head);
        if (isEvalFallbackForm(name)) return true;
        if (std.mem.eql(u8, name, "quote")) return false;
        // Named let: (let <symbol> ...) — not compiled natively.
        if (std.mem.eql(u8, name, "let")) {
            const rest = types.cdr(expr);
            if (rest != types.NIL and types.isPair(rest) and types.isSymbol(types.car(rest))) return true;
        }
    }
    var cur = expr;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        if (sexprNeedsEvalFallback(types.car(cur))) return true;
    }
    return false;
}

fn isEvalFallbackForm(name: []const u8) bool {
    for (ir.eval_fallback_form_names) |f| {
        if (std.mem.eql(u8, name, f)) return true;
    }
    return false;
}

// True if `body_list` (a cons list of body expressions) contains a lambda
// whose body references any name in `local_names` (let-bound variables) that
// is not shadowed by the lambda's own formals.  Such a lambda cannot be
// compiled natively inside a let scope: the native closure tiers
// (tryCompileNativeClosure / tryCompilePureLambdaAsNativeClosure) would
// reject it, and emitLambdaViaEval would evaluate it in the global
// environment where the let bindings are invisible (#827).
pub fn bodyHasCapturingLambda(self: *LLVMEmitter, body_list: Value, local_names: []const []const u8) bool {
    var expr = body_list;
    while (expr != types.NIL and types.isPair(expr)) : (expr = types.cdr(expr)) {
        if (exprHasCapturingLambda(self, types.car(expr), local_names)) return true;
    }
    return false;
}

fn exprHasCapturingLambda(self: *LLVMEmitter, expr: Value, local_names: []const []const u8) bool {
    if (!types.isPair(expr)) return false;
    const head = types.car(expr);
    if (types.isSymbol(head)) {
        const name = types.symbolName(head);
        if (std.mem.eql(u8, name, "lambda")) {
            const rest = types.cdr(expr);
            if (rest != types.NIL and types.isPair(rest)) {
                const formals = types.car(rest);
                const body = types.cdr(rest);
                // The nested lambda's formals shadow the outer locals: a
                // reference to one of them is not a capture. OOM while gathering
                // them is treated conservatively as "capturing" (fall back).
                var formal_names: std.ArrayList([]const u8) = .empty;
                var flist = formals;
                while (types.isPair(flist)) : (flist = types.cdr(flist)) {
                    const f = types.car(flist);
                    if (types.isSymbol(f)) formal_names.append(self.allocator(), types.symbolName(f)) catch return true;
                }
                // Rest-param symbol after dotted pair or bare symbol formals.
                if (types.isSymbol(flist)) formal_names.append(self.allocator(), types.symbolName(flist)) catch return true;
                if (types.isSymbol(formals)) formal_names.append(self.allocator(), types.symbolName(formals)) catch return true;
                if (sexprReferencesNames(body, local_names, formal_names.items)) return true;
            }
            return false;
        }
        if (std.mem.eql(u8, name, "quote")) return false;
    }
    var cur = expr;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        if (exprHasCapturingLambda(self, types.car(cur), local_names)) return true;
    }
    return false;
}

// True if the S-expression references any symbol in `target_names` that is
// not in `excluded_names`.  Does not descend into quoted data.
fn sexprReferencesNames(expr: Value, target_names: []const []const u8, excluded_names: []const []const u8) bool {
    if (types.isSymbol(expr)) {
        const name = types.symbolName(expr);
        for (excluded_names) |e| {
            if (std.mem.eql(u8, name, e)) return false;
        }
        for (target_names) |t| {
            if (std.mem.eql(u8, name, t)) return true;
        }
        return false;
    }
    if (!types.isPair(expr)) return false;
    if (types.isSymbol(types.car(expr)) and std.mem.eql(u8, types.symbolName(types.car(expr)), "quote")) return false;
    var cur = expr;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        if (sexprReferencesNames(types.car(cur), target_names, excluded_names)) return true;
    }
    return false;
}

// --- Free variable analysis helpers ---
//
// These take the emitter because classification must respect the enclosing
// emission scope: a name shadowed by an enclosing lexical binding (param,
// let-local, rest parameter, upvalue) is a capture even when a known global
// of the same name exists — `car` inside (lambda (car) ...) is the parameter,
// not the primitive. The shadow check must run before isKnownGlobal.

// Enclosing bindings that outrank the params array in emitGlobalRef's
// resolution order and cannot be copied out of %args into an upvalue buffer.
fn localsOrRestShadows(self: *LLVMEmitter, name: []const u8) bool {
    if (self.locals) |loc| {
        if (loc.get(name) != null) return true;
    }
    if (self.rest_param_name) |rp| {
        if (std.mem.eql(u8, name, rp)) return true;
    }
    return false;
}

// True if any of the parallel fv_boxed flags is set — i.e. this closure
// captures at least one boxed variable and therefore needs a box map.
fn freeVarsAnyBoxed(fv_boxed: []const bool) bool {
    for (fv_boxed) |b| {
        if (b) return true;
    }
    return false;
}

// True if the raw S-expression contains an internal define anywhere (not
// descending into quoted data). Used to reject closure bodies with an internal
// define, which needs a locals scope the closure tier does not set up. A set!
// is allowed — captured bindings it mutates are boxed by the enclosing frame
// (#1497).
fn sexprContainsDefine(expr: types.Value) bool {
    if (!types.isPair(expr)) return false;
    const head = types.car(expr);
    if (types.isSymbol(head)) {
        const h = types.symbolName(head);
        if (std.mem.eql(u8, h, "define")) return true;
        if (std.mem.eql(u8, h, "quote")) return false;
    }
    var cur = expr;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        if (sexprContainsDefine(types.car(cur))) return true;
    }
    return false;
}

// Per-frame assignment-conversion analysis (#1497). A native function's own
// binding needs boxing when it is BOTH mutated (a set! target somewhere in the
// body, including inside nested lambdas) AND captured by a nested lambda. Such
// a binding is materialized as a heap box so a later set! is visible through
// every closure that captured it — restoring the VM's by-location semantics.
// Bindings that are only mutated, or only captured, keep the by-value fast path.
pub const BoxAnalysis = struct {
    // Arena-allocated, parallel to the param_names passed to analyzeBoxedParams:
    // flags[i] true means fixed parameter i needs a box. Empty when the frame
    // has no fixed params.
    flags: []const bool = &.{},
    // A captured+mutated rest parameter cannot be boxed by the current model;
    // callers must reject native compilation (fall back to the interpreter).
    rest_conflict: bool = false,
    any: bool = false,
};

// Returns null on OOM (the arena allocations below can fail); callers treat that
// as "cannot compile natively" and fall back to the interpreter.
fn analyzeBoxedParams(self: *LLVMEmitter, body_list: Value, param_names: []const []const u8, rest_name: ?[]const u8) ?BoxAnalysis {
    if (param_names.len == 0 and rest_name == null) return BoxAnalysis{};

    // Which params / rest are assigned anywhere in the body. Indices 0..len map
    // to the fixed params; the trailing slot (index param_names.len) is the rest
    // parameter.
    const set_flags = self.allocator().alloc(bool, param_names.len + 1) catch return null;
    @memset(set_flags, false);
    var expr = body_list;
    while (expr != types.NIL and types.isPair(expr)) : (expr = types.cdr(expr)) {
        sexprCollectSetTargets(types.car(expr), param_names, rest_name, set_flags);
    }

    // A binding needs boxing only if it is also captured by a nested lambda.
    const flags = self.allocator().alloc(bool, param_names.len) catch return null;
    @memset(flags, false);
    var any = false;
    for (param_names, 0..) |p, i| {
        if (set_flags[i] and bodyHasCapturingLambda(self, body_list, &.{p})) {
            flags[i] = true;
            any = true;
        }
    }
    var result = BoxAnalysis{ .flags = flags, .any = any };
    if (rest_name) |rn| {
        if (set_flags[param_names.len] and bodyHasCapturingLambda(self, body_list, &.{rn})) {
            result.rest_conflict = true;
        }
    }
    return result;
}

// True if the body ever assigns `name` with (set! name ...), not descending
// into quoted data. Used by the closure tier to verify that a captured
// variable it mutates was actually boxed by the enclosing frame, and by
// emitLet to decide which captured let-locals to box (#1497).
pub fn sexprBodySetsName(body_list: Value, name: []const u8) bool {
    var expr = body_list;
    while (expr != types.NIL and types.isPair(expr)) : (expr = types.cdr(expr)) {
        if (sexprSetsName(types.car(expr), name)) return true;
    }
    return false;
}

fn sexprSetsName(expr: Value, name: []const u8) bool {
    if (!types.isPair(expr)) return false;
    const head = types.car(expr);
    if (types.isSymbol(head)) {
        const h = types.symbolName(head);
        if (std.mem.eql(u8, h, "quote")) return false;
        if (std.mem.eql(u8, h, "set!")) {
            const rest = types.cdr(expr);
            if (types.isPair(rest) and types.isSymbol(types.car(rest)) and
                std.mem.eql(u8, types.symbolName(types.car(rest)), name)) return true;
        }
    }
    var cur = expr;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        if (sexprSetsName(types.car(cur), name)) return true;
    }
    return false;
}

// Materialize box slots for the boxed fixed params of the current frame. Runs
// at function entry (params live in %args): loads each incoming value, boxes
// it, stores the box pointer in a fresh alloca, GC-roots the alloca, and
// registers the name in self.boxes. Increments self.frame_entry_roots so the
// caller pops the roots before the frame's ret. Returns false on OOM.
fn emitBoxedParamSlots(self: *LLVMEmitter, param_names: []const []const u8, analysis: BoxAnalysis) bool {
    var pushed: usize = 0;
    for (param_names, 0..) |pname, i| {
        if (!analysis.flags[i]) continue;
        const box_alloca = self.freshTemp() catch return false;
        self.print("  {s} = alloca i64, align 8\n", .{box_alloca}) catch return false;
        const gep = self.freshTemp() catch return false;
        self.print("  {s} = getelementptr i64, ptr %args, i64 {d}\n", .{ gep, i }) catch return false;
        const v = self.freshTemp() catch return false;
        self.print("  {s} = load i64, ptr {s}\n", .{ v, gep }) catch return false;
        const box = self.freshTemp() catch return false;
        self.print("  {s} = call i64 @kaappi_make_box(ptr %vm, i64 {s})\n", .{ box, v }) catch return false;
        self.print("  store i64 {s}, ptr {s}\n", .{ box, box_alloca }) catch return false;
        self.print("  call void @kaappi_gc_push_root(ptr {s})\n", .{box_alloca}) catch return false;
        (self.boxes orelse return false).put(pname, box_alloca) catch return false;
        pushed += 1;
    }
    self.frame_entry_roots += pushed;
    return true;
}

// flags has one slot per fixed param plus a trailing slot for the rest param
// (length param_names.len + 1), matching analyzeBoxedParams's set_flags.
fn sexprCollectSetTargets(expr: Value, param_names: []const []const u8, rest_name: ?[]const u8, flags: []bool) void {
    if (!types.isPair(expr)) return;
    const head = types.car(expr);
    if (types.isSymbol(head)) {
        const h = types.symbolName(head);
        if (std.mem.eql(u8, h, "quote")) return;
        if (std.mem.eql(u8, h, "set!")) {
            const rest = types.cdr(expr);
            if (types.isPair(rest)) {
                const target = types.car(rest);
                if (types.isSymbol(target)) {
                    const tname = types.symbolName(target);
                    for (param_names, 0..) |p, i| {
                        if (std.mem.eql(u8, tname, p)) {
                            flags[i] = true;
                            break;
                        }
                    }
                    if (rest_name) |rn| {
                        if (std.mem.eql(u8, tname, rn)) {
                            flags[param_names.len] = true;
                        }
                    }
                }
            }
        }
    }
    var cur = expr;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        sexprCollectSetTargets(types.car(cur), param_names, rest_name, flags);
    }
}

fn hasFreeVars(self: *LLVMEmitter, nodes: []const *ir.Node, params: []const []const u8) bool {
    for (nodes) |node| {
        if (nodeHasFreeVars(self, node, params)) return true;
    }
    return false;
}

fn nodeHasFreeVars(self: *LLVMEmitter, node: *const ir.Node, params: []const []const u8) bool {
    switch (node.tag) {
        .global_ref => {
            if (!types.isSymbol(node.data.global_ref)) return false;
            const name = types.symbolName(node.data.global_ref);
            for (params) |p| {
                if (std.mem.eql(u8, name, p)) return false;
            }
            // An enclosing lexical binding outranks a known global of the
            // same name: this reference is a capture, not the primitive.
            if (self.isNameShadowed(name)) return true;
            // A built-in, or a name reserved for a later top-level define, is a
            // global reference — not a free variable. The reserved case is what
            // lets a forward mutual-recursion call compile natively (#1499).
            if (self.isKnownOrReservedGlobal(name)) return false;
            return true;
        },
        .call => {
            if (nodeHasFreeVars(self, node.data.call.operator, params)) return true;
            for (node.data.call.args) |arg| {
                if (nodeHasFreeVars(self, arg, params)) return true;
            }
            return false;
        },
        .@"if" => {
            if (nodeHasFreeVars(self, node.data.@"if".test_expr, params)) return true;
            if (nodeHasFreeVars(self, node.data.@"if".consequent, params)) return true;
            if (node.data.@"if".alternate) |alt| {
                if (nodeHasFreeVars(self, alt, params)) return true;
            }
            return false;
        },
        .begin => return hasFreeVars(self, node.data.begin, params),
        .and_form => return hasFreeVars(self, node.data.and_form, params),
        .or_form => return hasFreeVars(self, node.data.or_form, params),
        .when_form => {
            if (nodeHasFreeVars(self, node.data.when_form.test_expr, params)) return true;
            return hasFreeVars(self, node.data.when_form.body, params);
        },
        .unless_form => {
            if (nodeHasFreeVars(self, node.data.unless_form.test_expr, params)) return true;
            return hasFreeVars(self, node.data.unless_form.body, params);
        },
        .set_form => {
            // The target and value are raw S-exprs; walk them with binder
            // scoping. A set! of a captured variable is a genuine free
            // reference — the enclosing frame boxes such variables so the
            // closure tier can capture the box pointer (#1497).
            if (sexprHasFreeVars(self, node.data.set_form.name, params)) return true;
            return sexprHasFreeVars(self, node.data.set_form.value, params);
        },
        // An internal define introduces a binding that the native lambda-body
        // emitter cannot install (it has no locals map), so it would leak to a
        // global. Disqualify and fall back to the interpreter.
        .define => return true,
        .constant => return false,
        // let/let* and nested lambdas keep their contents as a raw
        // S-expression, so references hidden inside them are invisible to
        // the node-level cases above. Walk the raw forms with proper binder
        // scoping (#1407, #1410).
        .let_form => return letSexprHasFreeVars(self, node.data.let_form.args, false, params),
        .let_star => return letSexprHasFreeVars(self, node.data.let_star.args, true, params),
        .lambda => return lambdaSexprHasFreeVars(self, node.data.lambda.args, params),
        // cond/case/do keep their clauses as a raw S-expression that the
        // backend now lowers natively (#1496); scope them like let/lambda so a
        // capture hidden in a clause is seen. Other sexpr forms are rejected
        // upstream and never reach a native body, so they report none.
        .sexpr_form => switch (node.data.sexpr_form.form) {
            .cond, .case_form, .do_form => return sexprFormHasFreeVars(self, node.data.sexpr_form.form, node.data.sexpr_form.args, params),
            else => return false,
        },
        .passthrough => return false,
        .letrec, .letrec_star => return false,
    }
}

// Walk a raw S-expression (a set! target or value) with binder scoping,
// reporting whether it references any free variable. Delegates to the shared
// FreeNameWalk so nested let/lambda binders are handled correctly (#1497).
fn sexprHasFreeVars(self: *LLVMEmitter, expr: types.Value, params: []const []const u8) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params };
    walkSexpr(&w, expr);
    return w.found or w.inexact;
}

fn collectSexprFreeVars(self: *LLVMEmitter, expr: types.Value, params: []const []const u8, list: *std.ArrayList([]const u8)) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params, .buf = list };
    walkSexpr(&w, expr);
    return !w.inexact;
}

// Both collectors return false when the analysis could not stay exact (an
// allocation failed, or a let walk met a form it cannot scope). Callers must
// then reject native closure compilation — emitting with an incomplete
// free-variable set would leave the missed name to resolve as a global.
fn collectFreeVars(self: *LLVMEmitter, nodes: []const *ir.Node, params: []const []const u8, list: *std.ArrayList([]const u8)) bool {
    for (nodes) |node| {
        if (!collectNodeFreeVars(self, node, params, list)) return false;
    }
    return true;
}

fn collectNodeFreeVars(self: *LLVMEmitter, node: *const ir.Node, params: []const []const u8, list: *std.ArrayList([]const u8)) bool {
    switch (node.tag) {
        .global_ref => {
            if (!types.isSymbol(node.data.global_ref)) return true;
            const name = types.symbolName(node.data.global_ref);
            for (params) |p| {
                if (std.mem.eql(u8, name, p)) return true;
            }
            // A shadowed known global is a capture; only an unshadowed one
            // may be skipped as a genuine global reference (incl. a name
            // reserved for a later top-level define, #1499).
            if (self.isKnownOrReservedGlobal(name) and !self.isNameShadowed(name)) return true;
            for (list.items) |existing| {
                if (std.mem.eql(u8, name, existing)) return true;
            }
            list.append(self.allocator(), name) catch return false;
            return true;
        },
        .call => {
            if (!collectNodeFreeVars(self, node.data.call.operator, params, list)) return false;
            for (node.data.call.args) |arg| {
                if (!collectNodeFreeVars(self, arg, params, list)) return false;
            }
            return true;
        },
        .@"if" => {
            if (!collectNodeFreeVars(self, node.data.@"if".test_expr, params, list)) return false;
            if (!collectNodeFreeVars(self, node.data.@"if".consequent, params, list)) return false;
            if (node.data.@"if".alternate) |alt| {
                if (!collectNodeFreeVars(self, alt, params, list)) return false;
            }
            return true;
        },
        .begin => return collectFreeVars(self, node.data.begin, params, list),
        .and_form => return collectFreeVars(self, node.data.and_form, params, list),
        .or_form => return collectFreeVars(self, node.data.or_form, params, list),
        .when_form => {
            if (!collectNodeFreeVars(self, node.data.when_form.test_expr, params, list)) return false;
            return collectFreeVars(self, node.data.when_form.body, params, list);
        },
        .unless_form => {
            if (!collectNodeFreeVars(self, node.data.unless_form.test_expr, params, list)) return false;
            return collectFreeVars(self, node.data.unless_form.body, params, list);
        },
        // See nodeHasFreeVars: let/let* and nested lambda contents are raw
        // S-expressions and must be walked with binder scoping, or captures
        // hidden inside them are silently compiled as global lookups
        // (#1407, #1410).
        .let_form => return collectLetSexprFreeVars(self, node.data.let_form.args, false, params, list),
        .let_star => return collectLetSexprFreeVars(self, node.data.let_star.args, true, params, list),
        .lambda => return collectLambdaSexprFreeVars(self, node.data.lambda.args, params, list),
        // A set! of a captured variable must be captured too, or a closure
        // that only writes (never reads) the binding would miss it (#1497).
        .set_form => {
            if (!collectSexprFreeVars(self, node.data.set_form.name, params, list)) return false;
            return collectSexprFreeVars(self, node.data.set_form.value, params, list);
        },
        // cond/case/do are lowered natively (#1496): collect captures hidden in
        // their clauses so a closure over such a variable gets its upvalue.
        // Other sexpr forms never reach a native body (rejected upstream).
        .sexpr_form => switch (node.data.sexpr_form.form) {
            .cond, .case_form, .do_form => return collectSexprFormFreeVars(self, node.data.sexpr_form.form, node.data.sexpr_form.args, params, list),
            else => return true,
        },
        .constant, .define, .passthrough => return true,
        .letrec, .letrec_star => return true,
    }
}

// --- Scope-aware free-name walk over raw let/let*/lambda forms (#1407, #1410) ---
//
// The IR keeps let/let* contents (ir.LetData.args) and lambda contents
// (ir.LambdaData.args) as raw S-expressions, so the node-level free-variable
// analysis cannot see references inside them. This walk descends into the
// raw form tracking binder scopes (let binders, nested lambda formals) and
// reports every referenced name that is neither bound nor a known global —
// the same rule the .global_ref arms apply.
// `inexact` is set when the walk meets something it cannot scope precisely
// (internal define, an eval-fallback form, malformed bindings, overflow);
// callers must then treat the analysis as failed and refuse to compile the
// enclosing lambda natively.

const FreeNameWalk = struct {
    emitter: *LLVMEmitter,
    params: []const []const u8,
    // Names bound by let/lambda binders currently in scope; grows on the arena.
    // A scope save/restore uses bound.items.len + shrinkRetainingCapacity.
    bound: std.ArrayList([]const u8) = .empty,
    // When non-null, free names are appended here, deduplicated.
    buf: ?*std.ArrayList([]const u8) = null,
    found: bool = false,
    inexact: bool = false,

    fn pushBound(w: *FreeNameWalk, name: []const u8) void {
        w.bound.append(w.emitter.allocator(), name) catch {
            w.inexact = true;
        };
    }

    fn noteRef(w: *FreeNameWalk, name: []const u8) void {
        for (w.params) |p| {
            if (std.mem.eql(u8, name, p)) return;
        }
        for (w.bound.items) |b| {
            if (std.mem.eql(u8, name, b)) return;
        }
        // A shadowed known global is a capture; only an unshadowed one is a
        // genuine global reference (see the section comment above), including a
        // name reserved for a later top-level define (#1499).
        if (w.emitter.isKnownOrReservedGlobal(name) and !w.emitter.isNameShadowed(name)) return;
        w.found = true;
        if (w.buf) |buf| {
            for (buf.items) |existing| {
                if (std.mem.eql(u8, name, existing)) return;
            }
            buf.append(w.emitter.allocator(), name) catch {
                w.inexact = true;
            };
        }
    }
};

fn letSexprHasFreeVars(self: *LLVMEmitter, args: Value, sequential: bool, params: []const []const u8) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params };
    walkLetSexpr(&w, args, sequential);
    return w.found or w.inexact;
}

fn collectLetSexprFreeVars(self: *LLVMEmitter, args: Value, sequential: bool, params: []const []const u8, list: *std.ArrayList([]const u8)) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params, .buf = list };
    walkLetSexpr(&w, args, sequential);
    return !w.inexact;
}

// args is the raw `(formals body ...)` tail of a nested lambda IR node
// (ir.LambdaData.args), the same shape walkLambdaSexpr consumes.
fn lambdaSexprHasFreeVars(self: *LLVMEmitter, args: Value, params: []const []const u8) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params };
    walkLambdaSexpr(&w, args);
    return w.found or w.inexact;
}

fn collectLambdaSexprFreeVars(self: *LLVMEmitter, args: Value, params: []const []const u8, list: *std.ArrayList([]const u8)) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params, .buf = list };
    walkLambdaSexpr(&w, args);
    return !w.inexact;
}

// args is the raw form tail (ir.SexprFormData.args) of a natively lowered
// cond/case/do (#1496). Walks it with the same binder scoping as let/lambda.
fn sexprFormHasFreeVars(self: *LLVMEmitter, form: ir.FormKind, args: Value, params: []const []const u8) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params };
    walkSexprForm(&w, form, args);
    return w.found or w.inexact;
}

fn collectSexprFormFreeVars(self: *LLVMEmitter, form: ir.FormKind, args: Value, params: []const []const u8, list: *std.ArrayList([]const u8)) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params, .buf = list };
    walkSexprForm(&w, form, args);
    return !w.inexact;
}

fn walkSexprForm(w: *FreeNameWalk, form: ir.FormKind, args: Value) void {
    switch (form) {
        .cond => walkCondSexpr(w, args),
        .case_form => walkCaseSexpr(w, args),
        .do_form => walkDoSexpr(w, args),
        else => w.inexact = true,
    }
}

// args is the raw `(bindings body ...)` tail of a let/let* form. For let the
// init expressions see only the enclosing scope; for let* each init also sees
// the binders before it. The binders are in scope for the body either way.
fn walkLetSexpr(w: *FreeNameWalk, args: Value, sequential: bool) void {
    if (!types.isPair(args)) {
        w.inexact = true;
        return;
    }
    const bindings = types.car(args);
    const saved = w.bound.items.len;
    defer w.bound.shrinkRetainingCapacity(saved);

    var blist = bindings;
    while (types.isPair(blist)) : (blist = types.cdr(blist)) {
        const binding = types.car(blist);
        if (!types.isPair(binding)) {
            w.inexact = true;
            return;
        }
        const var_sym = types.car(binding);
        const init_list = types.cdr(binding);
        if (!types.isSymbol(var_sym) or !types.isPair(init_list)) {
            w.inexact = true;
            return;
        }
        walkSexpr(w, types.car(init_list));
        if (sequential) w.pushBound(types.symbolName(var_sym));
    }
    if (blist != types.NIL) {
        w.inexact = true;
        return;
    }
    if (!sequential) {
        blist = bindings;
        while (types.isPair(blist)) : (blist = types.cdr(blist)) {
            w.pushBound(types.symbolName(types.car(types.car(blist))));
        }
    }
    var body_expr = types.cdr(args);
    while (types.isPair(body_expr)) : (body_expr = types.cdr(body_expr)) {
        walkSexpr(w, types.car(body_expr));
    }
}

// rest is the raw `(formals body ...)` tail of a lambda form.
fn walkLambdaSexpr(w: *FreeNameWalk, rest: Value) void {
    if (!types.isPair(rest)) {
        w.inexact = true;
        return;
    }
    const saved = w.bound.items.len;
    defer w.bound.shrinkRetainingCapacity(saved);

    var f = types.car(rest);
    while (types.isPair(f)) : (f = types.cdr(f)) {
        const p = types.car(f);
        if (!types.isSymbol(p)) {
            w.inexact = true;
            return;
        }
        w.pushBound(types.symbolName(p));
    }
    // Rest parameter: dotted tail, or bare-symbol formals.
    if (f != types.NIL) {
        if (!types.isSymbol(f)) {
            w.inexact = true;
            return;
        }
        w.pushBound(types.symbolName(f));
    }
    var body_expr = types.cdr(rest);
    while (types.isPair(body_expr)) : (body_expr = types.cdr(body_expr)) {
        walkSexpr(w, types.car(body_expr));
    }
}

// True if `v` is the symbol `name` — cond/case clause markers (else, =>) that
// the walks below must skip rather than treat as variable references.
fn sexprSymEql(v: Value, name: []const u8) bool {
    return types.isSymbol(v) and std.mem.eql(u8, types.symbolName(v), name);
}

// clauses is the raw tail of a `cond`: each clause is `(test body ...)`, with a
// leading `else` or `=> proc` handled structurally (the markers are not refs).
fn walkCondSexpr(w: *FreeNameWalk, clauses: Value) void {
    var cl = clauses;
    while (types.isPair(cl)) : (cl = types.cdr(cl)) {
        const clause = types.car(cl);
        if (!types.isPair(clause)) {
            w.inexact = true;
            return;
        }
        const test_expr = types.car(clause);
        if (!sexprSymEql(test_expr, "else")) walkSexpr(w, test_expr);
        var body = types.cdr(clause);
        if (types.isPair(body) and sexprSymEql(types.car(body), "=>")) body = types.cdr(body);
        while (types.isPair(body)) : (body = types.cdr(body)) {
            walkSexpr(w, types.car(body));
        }
    }
}

// args is the raw tail of a `case`: `(key clause ...)`. The datum list in each
// clause is quoted data (never referenced); only the key and bodies are refs.
fn walkCaseSexpr(w: *FreeNameWalk, args: Value) void {
    if (!types.isPair(args)) {
        w.inexact = true;
        return;
    }
    walkSexpr(w, types.car(args)); // key
    var cl = types.cdr(args);
    while (types.isPair(cl)) : (cl = types.cdr(cl)) {
        const clause = types.car(cl);
        if (!types.isPair(clause)) {
            w.inexact = true;
            return;
        }
        var body = types.cdr(clause); // car is the (literal) datum list
        if (types.isPair(body) and sexprSymEql(types.car(body), "=>")) body = types.cdr(body);
        while (types.isPair(body)) : (body = types.cdr(body)) {
            walkSexpr(w, types.car(body));
        }
    }
}

// args is the raw tail of a `do`: `(specs (test result ...) command ...)`. The
// loop variables are bound for the steps, test, results, and commands, but the
// init expressions are evaluated in the enclosing scope.
fn walkDoSexpr(w: *FreeNameWalk, args: Value) void {
    if (!types.isPair(args)) {
        w.inexact = true;
        return;
    }
    const specs = types.car(args);
    const rest = types.cdr(args);
    if (!types.isPair(rest) or !types.isPair(types.car(rest))) {
        w.inexact = true;
        return;
    }
    const test_clause = types.car(rest);
    const commands = types.cdr(rest);

    const saved = w.bound.items.len;
    defer w.bound.shrinkRetainingCapacity(saved);

    // Inits are evaluated before the loop variables are bound.
    var s = specs;
    while (types.isPair(s)) : (s = types.cdr(s)) {
        const spec = types.car(s);
        if (!types.isPair(spec) or !types.isSymbol(types.car(spec)) or !types.isPair(types.cdr(spec))) {
            w.inexact = true;
            return;
        }
        walkSexpr(w, types.car(types.cdr(spec)));
    }
    if (s != types.NIL) {
        w.inexact = true;
        return;
    }
    // Bind the loop variables for the rest of the form.
    s = specs;
    while (types.isPair(s)) : (s = types.cdr(s)) {
        w.pushBound(types.symbolName(types.car(types.car(s))));
    }
    // Steps see the loop bindings.
    s = specs;
    while (types.isPair(s)) : (s = types.cdr(s)) {
        const step_rest = types.cdr(types.cdr(types.car(s)));
        if (types.isPair(step_rest)) walkSexpr(w, types.car(step_rest));
    }
    walkSexpr(w, types.car(test_clause));
    var r = types.cdr(test_clause);
    while (types.isPair(r)) : (r = types.cdr(r)) walkSexpr(w, types.car(r));
    var c = commands;
    while (types.isPair(c)) : (c = types.cdr(c)) walkSexpr(w, types.car(c));
}

fn walkSexpr(w: *FreeNameWalk, expr: Value) void {
    if (w.inexact) return;
    if (types.isSymbol(expr)) {
        w.noteRef(types.symbolName(expr));
        return;
    }
    if (!types.isPair(expr)) return;
    const head = types.car(expr);
    if (types.isSymbol(head)) {
        const name = types.symbolName(head);
        if (std.mem.eql(u8, name, "quote")) return;
        if (std.mem.eql(u8, name, "lambda")) return walkLambdaSexpr(w, types.cdr(expr));
        const is_let = std.mem.eql(u8, name, "let");
        if (is_let or std.mem.eql(u8, name, "let*")) {
            const rest = types.cdr(expr);
            // Named let is rejected upstream by sexprNeedsEvalFallback; if
            // one shows up anyway, give up rather than mis-scope its binders.
            if (is_let and types.isPair(rest) and types.isSymbol(types.car(rest))) {
                w.inexact = true;
                return;
            }
            return walkLetSexpr(w, rest, !is_let);
        }
        // cond/case/do are natively lowered (#1496); scope their clauses so a
        // capture inside one is seen. (They are no longer isEvalFallbackForm.)
        if (std.mem.eql(u8, name, "cond")) return walkCondSexpr(w, types.cdr(expr));
        if (std.mem.eql(u8, name, "case")) return walkCaseSexpr(w, types.cdr(expr));
        if (std.mem.eql(u8, name, "do")) return walkDoSexpr(w, types.cdr(expr));
        // An internal define introduces a binding this walk does not model.
        if (std.mem.eql(u8, name, "define")) {
            w.inexact = true;
            return;
        }
        // Forms the backend sends to eval fallback (cond, do, letrec, ...)
        // are rejected upstream before this analysis runs; if one appears
        // anyway, its binder structure is unknown — give up.
        if (isEvalFallbackForm(name)) {
            w.inexact = true;
            return;
        }
    }
    // Everything else (calls, if/begin/and/or/when/unless/set!, ...) is a
    // plain expression tree: every symbol in it is a reference, and keyword
    // heads are filtered out by isKnownGlobal inside noteRef.
    var cur = expr;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        walkSexpr(w, types.car(cur));
    }
}
