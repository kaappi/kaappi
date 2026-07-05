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
    if (hasFreeVars(body_nodes[0..body_count], allowed[0..arity])) return null;

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
    collectFreeVars(body_nodes[0..body_count], param_names[0..arity], &free_vars, &free_count);
    if (free_count == 0) return null;

    const outer_params = self.params orelse return null;
    for (free_vars[0..free_count]) |fv| {
        if (!outer_params.contains(fv) and !ir.isKnownGlobal(fv)) return null;
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

        var p = std.StringHashMap(u8).init(self.backing_alloc);
        defer p.deinit();
        for (param_names[0..arity], 0..) |pname, i| {
            p.put(pname, @intCast(i)) catch return null;
        }

        var uv_map = std.StringHashMap(u8).init(self.backing_alloc);
        defer uv_map.deinit();
        for (free_vars[0..free_count], 0..) |fv, i| {
            if (outer_params.contains(fv)) {
                uv_map.put(fv, @intCast(i)) catch return null;
            }
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
        if (outer_params.get(fv)) |idx| {
            const gep_src = self.freshTemp() catch return null;
            self.print("  {s} = getelementptr i64, ptr %args, i64 {d}\n", .{ gep_src, idx }) catch return null;
            const val = self.freshTemp() catch return null;
            self.print("  {s} = load i64, ptr {s}\n", .{ val, gep_src }) catch return null;
            const gep_dst = self.freshTemp() catch return null;
            self.print("  {s} = getelementptr i64, ptr {s}, i64 {d}\n", .{ gep_dst, uv_alloca, i }) catch return null;
            self.print("  store i64 {s}, ptr {s}\n", .{ val, gep_dst }) catch return null;
        }
    }

    const name_str = self.internString(closure_name) catch return null;
    const result = self.freshTemp() catch return null;
    self.print("  {s} = call i64 @kaappi_create_native_closure(ptr %vm, ptr {s}, ptr {s}, i64 {d}, i64 {d}, ptr {s}, i64 {d})\n", .{ result, fn_name, uv_alloca, free_count, arity, name_str, closure_name.len }) catch return null;
    return result;
}

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
    if (hasFreeVars(body_nodes[0..body_count], allowed[0 .. arity + extra + 1])) return null;

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

// --- Free variable analysis helpers (standalone, no self) ---

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

fn hasFreeVars(nodes: []const *ir.Node, params: []const []const u8) bool {
    for (nodes) |node| {
        if (nodeHasFreeVars(node, params)) return true;
    }
    return false;
}

fn nodeHasFreeVars(node: *const ir.Node, params: []const []const u8) bool {
    switch (node.tag) {
        .global_ref => {
            if (!types.isSymbol(node.data.global_ref)) return false;
            const name = types.symbolName(node.data.global_ref);
            for (params) |p| {
                if (std.mem.eql(u8, name, p)) return false;
            }
            if (ir.isKnownGlobal(name)) return false;
            return true;
        },
        .call => {
            if (nodeHasFreeVars(node.data.call.operator, params)) return true;
            for (node.data.call.args) |arg| {
                if (nodeHasFreeVars(arg, params)) return true;
            }
            return false;
        },
        .@"if" => {
            if (nodeHasFreeVars(node.data.@"if".test_expr, params)) return true;
            if (nodeHasFreeVars(node.data.@"if".consequent, params)) return true;
            if (node.data.@"if".alternate) |alt| {
                if (nodeHasFreeVars(alt, params)) return true;
            }
            return false;
        },
        .begin => return hasFreeVars(node.data.begin, params),
        .and_form => return hasFreeVars(node.data.and_form, params),
        .or_form => return hasFreeVars(node.data.or_form, params),
        .when_form => {
            if (nodeHasFreeVars(node.data.when_form.test_expr, params)) return true;
            return hasFreeVars(node.data.when_form.body, params);
        },
        .unless_form => {
            if (nodeHasFreeVars(node.data.unless_form.test_expr, params)) return true;
            return hasFreeVars(node.data.unless_form.body, params);
        },
        .set_form => {
            // A set! is safe to compile in a body with no upvalues only when
            // both the target and the value stay within our params/globals.
            // Otherwise it mutates (or reads) a captured lexical variable that
            // the native slot-store cannot reach, so disqualify and let the
            // interpreter handle it. The value is a raw S-expr; a compound
            // value is treated conservatively as possibly capturing (#819).
            if (!types.isSymbol(node.data.set_form.name)) return true;
            if (!valueIsBoundOrLiteral(node.data.set_form.name, params)) return true;
            if (!valueIsBoundOrLiteral(node.data.set_form.value, params)) return true;
            return false;
        },
        // An internal define introduces a binding that the native lambda-body
        // emitter cannot install (it has no locals map), so it would leak to a
        // global. Disqualify and fall back to the interpreter.
        .define => return true,
        .constant => return false,
        .lambda, .passthrough, .let_form, .let_star => return false,
        inline else => |tag| {
            comptime {
                if (ir.llvmCapability(tag) != .eval_fallback)
                    @compileError("unhandled native tag in nodeHasFreeVars: " ++ @tagName(tag));
            }
            return false;
        },
    }
}

// A raw S-expr value that is trivially safe to reference inside a natively
// compiled body with no upvalues: a literal, or a symbol that names one of our
// params or a known global. Anything else (a compound expression, or a symbol
// naming a captured lexical variable) is treated as unsafe.
fn valueIsBoundOrLiteral(value: types.Value, params: []const []const u8) bool {
    if (types.isSymbol(value)) {
        const name = types.symbolName(value);
        for (params) |p| {
            if (std.mem.eql(u8, name, p)) return true;
        }
        return ir.isKnownGlobal(name);
    }
    return !types.isPair(value);
}

fn collectFreeVars(nodes: []const *ir.Node, params: []const []const u8, buf: *[16][]const u8, count: *usize) void {
    for (nodes) |node| {
        collectNodeFreeVars(node, params, buf, count);
    }
}

fn collectNodeFreeVars(node: *const ir.Node, params: []const []const u8, buf: *[16][]const u8, count: *usize) void {
    switch (node.tag) {
        .global_ref => {
            if (!types.isSymbol(node.data.global_ref)) return;
            const name = types.symbolName(node.data.global_ref);
            for (params) |p| {
                if (std.mem.eql(u8, name, p)) return;
            }
            if (ir.isKnownGlobal(name)) return;
            for (buf[0..count.*]) |existing| {
                if (std.mem.eql(u8, name, existing)) return;
            }
            if (count.* < 16) {
                buf[count.*] = name;
                count.* += 1;
            }
        },
        .call => {
            collectNodeFreeVars(node.data.call.operator, params, buf, count);
            for (node.data.call.args) |arg| collectNodeFreeVars(arg, params, buf, count);
        },
        .@"if" => {
            collectNodeFreeVars(node.data.@"if".test_expr, params, buf, count);
            collectNodeFreeVars(node.data.@"if".consequent, params, buf, count);
            if (node.data.@"if".alternate) |alt| collectNodeFreeVars(alt, params, buf, count);
        },
        .begin => collectFreeVars(node.data.begin, params, buf, count),
        .and_form => collectFreeVars(node.data.and_form, params, buf, count),
        .or_form => collectFreeVars(node.data.or_form, params, buf, count),
        .when_form => {
            collectNodeFreeVars(node.data.when_form.test_expr, params, buf, count);
            collectFreeVars(node.data.when_form.body, params, buf, count);
        },
        .unless_form => {
            collectNodeFreeVars(node.data.unless_form.test_expr, params, buf, count);
            collectFreeVars(node.data.unless_form.body, params, buf, count);
        },
        .constant, .define, .set_form, .lambda, .passthrough, .let_form, .let_star => {},
        inline else => |tag| {
            comptime {
                if (ir.llvmCapability(tag) != .eval_fallback)
                    @compileError("unhandled native tag in collectNodeFreeVars: " ++ @tagName(tag));
            }
        },
    }
}
