const std = @import("std");
const ir = @import("ir.zig");
const types = @import("types.zig");
const printer = @import("printer.zig");

const LLVMEmitter = @import("llvm_emit.zig").LLVMEmitter;
const EmitError = @import("llvm_emit.zig").EmitError;

const Value = types.Value;

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

    var param_names: [16][]const u8 = undefined;
    var arity: u8 = 0;
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
        if (arity >= 16) return null;
        param_names[arity] = types.symbolName(p);
        arity += 1;
        plist = types.cdr(plist);
    }

    if (rest_name != null) return null;

    // #1422: reject if a param is both set! and captured by a nested lambda.
    if (bodyHasConflictingSetCapture(body_list, param_names[0..arity], null)) return null;

    var body_ir = ir.IR.init(self.allocator());
    defer body_ir.deinit();
    // Parameters shadow primitives of the same name; don't fold calls to them
    // using the built-in's semantics (issue #790).
    body_ir.bound_names = param_names[0..arity];
    var body_nodes: [64]*ir.Node = undefined;
    var body_count: usize = 0;
    var body_expr = body_list;
    while (body_expr != types.NIL and types.isPair(body_expr)) {
        if (body_count >= 64) return null;
        const expr = types.car(body_expr);
        const opt = ir.lowerAndOptimize(&body_ir, expr, null, types.cdr(body_expr) == types.NIL) catch return null;
        body_nodes[body_count] = opt;
        body_count += 1;
        body_expr = types.cdr(body_expr);
    }
    if (body_count == 0) return null;

    var allowed: [17][]const u8 = undefined;
    @memcpy(allowed[0..arity], param_names[0..arity]);
    if (hasFreeVars(self, body_nodes[0..body_count], allowed[0..arity])) return null;

    const fn_name = emitLambdaFunction(self, data.name, param_names[0..arity], body_nodes[0..body_count], rest_name) orelse return null;

    const closure_name = data.name orelse "(lambda)";
    const name_str = self.internString(closure_name) catch return null;
    const result = self.freshTemp() catch return null;
    self.print("  {s} = call i64 @kaappi_create_native_closure(ptr %vm, ptr {s}, ptr null, i64 0, i64 {d}, ptr {s}, i64 {d})\n", .{ result, fn_name, arity, name_str, closure_name.len }) catch return null;
    return result;
}

fn tryCompileNativeClosure(self: *LLVMEmitter, data: ir.LambdaData) ?[]const u8 {
    const formals_val = types.car(data.args);
    const body_list = types.cdr(data.args);
    if (body_list == types.NIL) return null;
    if (!types.isPair(formals_val) and formals_val != types.NIL) return null;

    // A closure copies its captured variables by value into an upvalue array,
    // so a set! (or internal define) that mutates a captured binding cannot be
    // represented natively. Reject any body containing set!/define and let the
    // interpreter handle it (#819).
    {
        var be = body_list;
        while (be != types.NIL and types.isPair(be)) : (be = types.cdr(be)) {
            if (sexprContainsSetOrDefine(types.car(be))) return null;
        }
    }

    // #827: reject if body contains forms needing interpreter eval fallback
    {
        var be2 = body_list;
        while (be2 != types.NIL and types.isPair(be2)) : (be2 = types.cdr(be2)) {
            if (sexprNeedsEvalFallback(types.car(be2))) return null;
        }
    }

    var param_names: [16][]const u8 = undefined;
    var arity: u8 = 0;
    var plist = formals_val;
    while (plist != types.NIL) {
        if (!types.isPair(plist)) return null;
        const p = types.car(plist);
        if (!types.isSymbol(p)) return null;
        if (arity >= 16) return null;
        param_names[arity] = types.symbolName(p);
        arity += 1;
        plist = types.cdr(plist);
    }

    var body_ir = ir.IR.init(self.allocator());
    defer body_ir.deinit();
    // Parameters shadow primitives of the same name; don't fold calls to them
    // using the built-in's semantics (issue #790).
    body_ir.bound_names = param_names[0..arity];
    var body_nodes: [64]*ir.Node = undefined;
    var body_count: usize = 0;
    var body_expr = body_list;
    while (body_expr != types.NIL and types.isPair(body_expr)) {
        if (body_count >= 64) return null;
        const expr = types.car(body_expr);
        const opt = ir.lowerAndOptimize(&body_ir, expr, null, types.cdr(body_expr) == types.NIL) catch return null;
        body_nodes[body_count] = opt;
        body_count += 1;
        body_expr = types.cdr(body_expr);
    }
    if (body_count == 0) return null;

    var free_vars: [16][]const u8 = undefined;
    var free_count: usize = 0;
    if (!collectFreeVars(self, body_nodes[0..body_count], param_names[0..arity], &free_vars, &free_count)) return null;
    if (free_count == 0) return null;

    const outer_params = self.params orelse return null;
    const outer_upvalues = self.upvalues;
    for (free_vars[0..free_count]) |fv| {
        // Captures are copied out of the enclosing frame at closure-creation
        // time: params from its %args, and — when this lambda sits inside
        // another native closure — chained captures from that closure's own
        // %upvalues array (#1410). A name bound by an enclosing let-local or
        // rest parameter (which outrank params in emitGlobalRef's resolution
        // order) has no capturable slot, and any other name is unknown here;
        // reject those and let the eval fallback handle the lambda.
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
        for (param_names[0..arity], 0..) |pname, i| {
            p.put(pname, @intCast(i)) catch return null;
        }

        // Every collected free variable passed the capture check above, so
        // each one has a slot in the upvalue array this closure is created
        // with (params-sourced and chained captures alike).
        var uv_map = std.StringHashMap(u8).init(self.backing_alloc);
        defer uv_map.deinit();
        for (free_vars[0..free_count], 0..) |fv, i| {
            uv_map.put(fv, @intCast(i)) catch return null;
        }
        self.params = p;
        self.upvalues = uv_map;

        const header = std.fmt.allocPrint(self.allocator(), "; closure: {s}\ndefine i64 {s}(ptr %vm, ptr %args, i64 %nargs, ptr %upvalues) {{\nentry:\n", .{ closure_name, fn_name }) catch return null;
        defer self.allocator().free(header);
        self.write(header) catch return null;

        var last_val: []const u8 = "";
        for (body_nodes[0..body_count]) |node| {
            last_val = self.emitNode(node) catch return null;
        }

        self.print("  ret i64 {s}\n}}\n", .{last_val}) catch return null;

        fn_buf = self.buf;
    }

    const fn_def = fn_buf.toOwnedSlice(self.backing_alloc) catch return null;
    self.lambda_defs.append(self.backing_alloc, fn_def) catch return null;

    const uv_alloca = self.freshTemp() catch return null;
    self.print("  {s} = alloca [{d} x i64], align 8\n", .{ uv_alloca, free_count }) catch return null;
    for (free_vars[0..free_count], 0..) |fv, i| {
        const val = blk: {
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
    self.print("  {s} = call i64 @kaappi_create_native_closure(ptr %vm, ptr {s}, ptr {s}, i64 {d}, i64 {d}, ptr {s}, i64 {d})\n", .{ result, fn_name, uv_alloca, free_count, arity, name_str, closure_name.len }) catch return null;
    return result;
}

// Bind every name reachable in the current native frame — fixed params, the
// rest parameter, and captured upvalues — as globals, so a form that falls
// back to kaappi_eval (which runs in the global environment) still resolves
// them. Leaving any of them out surfaces as "undefined variable" (or a
// silently wrong value when a same-named global exists) at run time (#1410).
pub fn bindParamsAsGlobals(self: *LLVMEmitter) EmitError!void {
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

    const str_name = try self.internString(source_buf.items);
    const tmp = try self.freshTemp();
    try self.print("  {s} = call i64 @kaappi_eval(ptr %vm, ptr {s}, i64 {d})\n", .{ tmp, str_name, source_buf.items.len });
    return tmp;
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

    var param_names: [16][]const u8 = undefined;
    var arity: u8 = 0;
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
        if (arity >= 16) return null;
        param_names[arity] = types.symbolName(param);
        arity += 1;
        param_list = types.cdr(param_list);
    }

    // #1422: reject if a param is both set! and captured by a nested lambda.
    if (bodyHasConflictingSetCapture(body, param_names[0..arity], rest_name)) return null;

    var body_ir = ir.IR.init(self.allocator());
    defer body_ir.deinit();
    // Parameters (including a rest parameter) shadow primitives of the same
    // name; don't fold calls to them using the built-in's semantics (#790).
    if (rest_name) |rn| {
        if (arity < param_names.len) {
            param_names[arity] = rn;
            body_ir.bound_names = param_names[0 .. arity + 1];
        } else {
            body_ir.bound_names = param_names[0..arity];
        }
    } else {
        body_ir.bound_names = param_names[0..arity];
    }

    var body_nodes: [64]*ir.Node = undefined;
    var body_count: usize = 0;
    var body_expr = body;
    while (body_expr != types.NIL and types.isPair(body_expr)) {
        if (body_count >= 64) return null;
        const expr = types.car(body_expr);
        const opt = ir.lowerAndOptimize(&body_ir, expr, null, types.cdr(body_expr) == types.NIL) catch return null;
        body_nodes[body_count] = opt;
        body_count += 1;
        body_expr = types.cdr(body_expr);
    }
    if (body_count == 0) return null;

    const extra: u8 = if (rest_name != null) 1 else 0;
    var allowed: [18][]const u8 = undefined;
    @memcpy(allowed[0..arity], param_names[0..arity]);
    if (rest_name) |rn| {
        allowed[arity] = rn;
    }
    allowed[arity + extra] = name;
    if (hasFreeVars(self, body_nodes[0..body_count], allowed[0 .. arity + extra + 1])) return null;

    return emitLambdaFunction(self, name, param_names[0..arity], body_nodes[0..body_count], rest_name);
}

fn emitLambdaFunction(self: *LLVMEmitter, name: ?[]const u8, param_names: []const []const u8, body_nodes: []const *ir.Node, rest_name: ?[]const u8) ?[]const u8 {
    const id = self.lambda_counter;
    self.lambda_counter += 1;
    const fn_name = std.fmt.allocPrint(self.allocator(), "@lambda_{d}", .{id}) catch return null;

    if (name) |n| {
        self.native_fns.put(n, .{ .llvm_name = fn_name, .arity = @intCast(param_names.len), .is_variadic = rest_name != null }) catch {};
    }

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

        var p = std.StringHashMap(u8).init(self.backing_alloc);
        defer p.deinit();
        for (param_names, 0..) |pname, i| {
            p.put(pname, @intCast(i)) catch return null;
        }
        self.params = p;

        const body_lbl = std.fmt.allocPrint(self.allocator(), "body_{d}", .{id}) catch return null;

        self.current_fn_name = if (rest_name == null) name else null;
        self.body_label = if (rest_name == null) body_lbl else null;
        self.current_block = body_lbl;
        self.rest_param_name = rest_name;
        self.rest_param_alloca = null;

        const header = std.fmt.allocPrint(self.allocator(), "; {s}\ndefine i64 {s}(ptr %vm, ptr %args, i64 %nargs, ptr %upvalues) {{\nentry:\n  br label %{s}\n{s}:\n", .{ name orelse "(lambda)", fn_name, body_lbl, body_lbl }) catch return null;
        defer self.allocator().free(header);
        self.write(header) catch return null;

        if (rest_name != null) {
            emitRestListBuilder(self, param_names.len) catch return null;
        }

        var last_val: []const u8 = "";
        for (body_nodes) |node| {
            last_val = self.emitNode(node) catch return null;
        }

        self.print("  ret i64 {s}\n}}\n", .{last_val}) catch return null;

        fn_buf = self.buf;
    }

    const fn_def = fn_buf.toOwnedSlice(self.backing_alloc) catch return null;
    self.lambda_defs.append(self.backing_alloc, fn_def) catch return null;

    return fn_name;
}

fn emitRestListBuilder(self: *LLVMEmitter, fixed_arity: usize) EmitError!void {
    const rest_alloca = try self.freshTemp();
    try self.print("  {s} = alloca i64, align 8\n", .{rest_alloca});
    self.rest_param_alloca = rest_alloca;

    const nil_tmp = try self.emitImm(@bitCast(types.NIL));
    try self.print("  store i64 {s}, ptr {s}\n", .{ nil_tmp, rest_alloca });

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
pub fn bodyHasCapturingLambda(body_list: Value, local_names: []const []const u8) bool {
    var expr = body_list;
    while (expr != types.NIL and types.isPair(expr)) : (expr = types.cdr(expr)) {
        if (exprHasCapturingLambda(types.car(expr), local_names)) return true;
    }
    return false;
}

fn exprHasCapturingLambda(expr: Value, local_names: []const []const u8) bool {
    if (!types.isPair(expr)) return false;
    const head = types.car(expr);
    if (types.isSymbol(head)) {
        const name = types.symbolName(head);
        if (std.mem.eql(u8, name, "lambda")) {
            const rest = types.cdr(expr);
            if (rest != types.NIL and types.isPair(rest)) {
                const formals = types.car(rest);
                const body = types.cdr(rest);
                var formal_names: [32][]const u8 = undefined;
                var formal_count: usize = 0;
                var flist = formals;
                while (types.isPair(flist)) : (flist = types.cdr(flist)) {
                    const f = types.car(flist);
                    if (types.isSymbol(f) and formal_count < 32) {
                        formal_names[formal_count] = types.symbolName(f);
                        formal_count += 1;
                    }
                }
                // Rest-param symbol after dotted pair or bare symbol formals.
                if (types.isSymbol(flist) and formal_count < 32) {
                    formal_names[formal_count] = types.symbolName(flist);
                    formal_count += 1;
                }
                if (types.isSymbol(formals) and formal_count < 32) {
                    formal_names[formal_count] = types.symbolName(formals);
                    formal_count += 1;
                }
                if (sexprReferencesNames(body, local_names, formal_names[0..formal_count])) return true;
            }
            return false;
        }
        if (std.mem.eql(u8, name, "quote")) return false;
    }
    var cur = expr;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        if (exprHasCapturingLambda(types.car(cur), local_names)) return true;
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

// True if the raw S-expression contains a set! or define form anywhere (not
// descending into quoted data). Used to reject closure bodies that mutate or
// rebind captured state, which the native upvalue-copy model cannot express.
fn sexprContainsSetOrDefine(expr: types.Value) bool {
    if (!types.isPair(expr)) return false;
    const head = types.car(expr);
    if (types.isSymbol(head)) {
        const h = types.symbolName(head);
        if (std.mem.eql(u8, h, "set!") or std.mem.eql(u8, h, "define")) return true;
        if (std.mem.eql(u8, h, "quote")) return false;
    }
    var cur = expr;
    while (types.isPair(cur)) : (cur = types.cdr(cur)) {
        if (sexprContainsSetOrDefine(types.car(cur))) return true;
    }
    return false;
}

// True if the function body has a parameter that is both targeted by set!
// and captured by a nested lambda.  The native upvalue-copy model snapshots
// at closure creation, so a later set! of the same param is invisible to
// the closure — diverging from the VM's by-location semantics (#1422).
fn bodyHasConflictingSetCapture(body_list: Value, param_names: []const []const u8, rest_name: ?[]const u8) bool {
    const total = param_names.len + @as(usize, if (rest_name != null) 1 else 0);
    if (total == 0) return false;
    var set_flags: [17]bool = @splat(false);

    var expr = body_list;
    while (expr != types.NIL and types.isPair(expr)) : (expr = types.cdr(expr)) {
        sexprCollectSetTargets(types.car(expr), param_names, rest_name, &set_flags);
    }

    var any = false;
    for (set_flags[0..total]) |f| {
        if (f) {
            any = true;
            break;
        }
    }
    if (!any) return false;

    var flagged: [17][]const u8 = undefined;
    var flagged_count: usize = 0;
    for (param_names, 0..) |p, i| {
        if (set_flags[i]) {
            flagged[flagged_count] = p;
            flagged_count += 1;
        }
    }
    if (rest_name) |rn| {
        if (set_flags[param_names.len]) {
            flagged[flagged_count] = rn;
            flagged_count += 1;
        }
    }

    return bodyHasCapturingLambda(body_list, flagged[0..flagged_count]);
}

fn sexprCollectSetTargets(expr: Value, param_names: []const []const u8, rest_name: ?[]const u8, flags: *[17]bool) void {
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
            if (ir.isKnownGlobal(name)) return false;
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
            // A set! is safe to compile in a body with no upvalues only when
            // both the target and the value stay within our params/globals.
            // Otherwise it mutates (or reads) a captured lexical variable that
            // the native slot-store cannot reach, so disqualify and let the
            // interpreter handle it. The value is a raw S-expr; a compound
            // value is treated conservatively as possibly capturing (#819).
            if (!types.isSymbol(node.data.set_form.name)) return true;
            if (!valueIsBoundOrLiteral(self, node.data.set_form.name, params)) return true;
            if (!valueIsBoundOrLiteral(self, node.data.set_form.value, params)) return true;
            return false;
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
        .passthrough, .sexpr_form => return false,
        .letrec, .letrec_star => return false,
    }
}

// A raw S-expr value that is trivially safe to reference inside a natively
// compiled body with no upvalues: a literal, or a symbol that names one of our
// params or a known global. Anything else (a compound expression, or a symbol
// naming a captured lexical variable) is treated as unsafe.
fn valueIsBoundOrLiteral(self: *LLVMEmitter, value: types.Value, params: []const []const u8) bool {
    if (types.isSymbol(value)) {
        const name = types.symbolName(value);
        for (params) |p| {
            if (std.mem.eql(u8, name, p)) return true;
        }
        // A name shadowed by an enclosing lexical binding is a capture,
        // not the known global it would otherwise resolve to.
        if (self.isNameShadowed(name)) return false;
        return ir.isKnownGlobal(name);
    }
    return !types.isPair(value);
}

// Both collectors return false when the analysis could not stay exact (a
// name buffer overflowed, or a let walk met a form it cannot scope). Callers
// must then reject native closure compilation — emitting with an incomplete
// free-variable set would leave the missed name to resolve as a global.
fn collectFreeVars(self: *LLVMEmitter, nodes: []const *ir.Node, params: []const []const u8, buf: *[16][]const u8, count: *usize) bool {
    for (nodes) |node| {
        if (!collectNodeFreeVars(self, node, params, buf, count)) return false;
    }
    return true;
}

fn collectNodeFreeVars(self: *LLVMEmitter, node: *const ir.Node, params: []const []const u8, buf: *[16][]const u8, count: *usize) bool {
    switch (node.tag) {
        .global_ref => {
            if (!types.isSymbol(node.data.global_ref)) return true;
            const name = types.symbolName(node.data.global_ref);
            for (params) |p| {
                if (std.mem.eql(u8, name, p)) return true;
            }
            // A shadowed known global is a capture; only an unshadowed one
            // may be skipped as a genuine global reference.
            if (ir.isKnownGlobal(name) and !self.isNameShadowed(name)) return true;
            for (buf[0..count.*]) |existing| {
                if (std.mem.eql(u8, name, existing)) return true;
            }
            if (count.* >= buf.len) return false;
            buf[count.*] = name;
            count.* += 1;
            return true;
        },
        .call => {
            if (!collectNodeFreeVars(self, node.data.call.operator, params, buf, count)) return false;
            for (node.data.call.args) |arg| {
                if (!collectNodeFreeVars(self, arg, params, buf, count)) return false;
            }
            return true;
        },
        .@"if" => {
            if (!collectNodeFreeVars(self, node.data.@"if".test_expr, params, buf, count)) return false;
            if (!collectNodeFreeVars(self, node.data.@"if".consequent, params, buf, count)) return false;
            if (node.data.@"if".alternate) |alt| {
                if (!collectNodeFreeVars(self, alt, params, buf, count)) return false;
            }
            return true;
        },
        .begin => return collectFreeVars(self, node.data.begin, params, buf, count),
        .and_form => return collectFreeVars(self, node.data.and_form, params, buf, count),
        .or_form => return collectFreeVars(self, node.data.or_form, params, buf, count),
        .when_form => {
            if (!collectNodeFreeVars(self, node.data.when_form.test_expr, params, buf, count)) return false;
            return collectFreeVars(self, node.data.when_form.body, params, buf, count);
        },
        .unless_form => {
            if (!collectNodeFreeVars(self, node.data.unless_form.test_expr, params, buf, count)) return false;
            return collectFreeVars(self, node.data.unless_form.body, params, buf, count);
        },
        // See nodeHasFreeVars: let/let* and nested lambda contents are raw
        // S-expressions and must be walked with binder scoping, or captures
        // hidden inside them are silently compiled as global lookups
        // (#1407, #1410).
        .let_form => return collectLetSexprFreeVars(self, node.data.let_form.args, false, params, buf, count),
        .let_star => return collectLetSexprFreeVars(self, node.data.let_star.args, true, params, buf, count),
        .lambda => return collectLambdaSexprFreeVars(self, node.data.lambda.args, params, buf, count),
        .constant, .define, .set_form, .passthrough, .sexpr_form => return true,
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
    bound: [64][]const u8 = undefined,
    bound_count: usize = 0,
    // When non-null, free names are appended here, deduplicated.
    buf: ?*[16][]const u8 = null,
    count: ?*usize = null,
    found: bool = false,
    inexact: bool = false,

    fn pushBound(w: *FreeNameWalk, name: []const u8) void {
        if (w.bound_count >= w.bound.len) {
            w.inexact = true;
            return;
        }
        w.bound[w.bound_count] = name;
        w.bound_count += 1;
    }

    fn noteRef(w: *FreeNameWalk, name: []const u8) void {
        for (w.params) |p| {
            if (std.mem.eql(u8, name, p)) return;
        }
        for (w.bound[0..w.bound_count]) |b| {
            if (std.mem.eql(u8, name, b)) return;
        }
        // A shadowed known global is a capture; only an unshadowed one is a
        // genuine global reference (see the section comment above).
        if (ir.isKnownGlobal(name) and !w.emitter.isNameShadowed(name)) return;
        w.found = true;
        if (w.buf) |buf| {
            const count = w.count.?;
            for (buf[0..count.*]) |existing| {
                if (std.mem.eql(u8, name, existing)) return;
            }
            if (count.* >= buf.len) {
                w.inexact = true;
                return;
            }
            buf[count.*] = name;
            count.* += 1;
        }
    }
};

fn letSexprHasFreeVars(self: *LLVMEmitter, args: Value, sequential: bool, params: []const []const u8) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params };
    walkLetSexpr(&w, args, sequential);
    return w.found or w.inexact;
}

fn collectLetSexprFreeVars(self: *LLVMEmitter, args: Value, sequential: bool, params: []const []const u8, buf: *[16][]const u8, count: *usize) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params, .buf = buf, .count = count };
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

fn collectLambdaSexprFreeVars(self: *LLVMEmitter, args: Value, params: []const []const u8, buf: *[16][]const u8, count: *usize) bool {
    var w = FreeNameWalk{ .emitter = self, .params = params, .buf = buf, .count = count };
    walkLambdaSexpr(&w, args);
    return !w.inexact;
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
    const saved = w.bound_count;
    defer w.bound_count = saved;

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
    const saved = w.bound_count;
    defer w.bound_count = saved;

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
