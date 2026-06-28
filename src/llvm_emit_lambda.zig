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

    var body_ir = ir.IR.init(self.allocator);
    defer body_ir.deinit();
    var body_nodes: [64]*ir.Node = undefined;
    var body_count: usize = 0;
    var body_expr = body_list;
    while (body_expr != types.NIL and types.isPair(body_expr)) {
        if (body_count >= 64) return null;
        const expr = types.car(body_expr);
        const node = ir.lowerWithMacros(&body_ir, expr, null) catch return null;
        ir.markTailPositions(node, types.cdr(body_expr) == types.NIL);
        ir.identifyPrimitives(node);
        ir.markConstants(node);
        var opt = ir.foldConstants(&body_ir, node);
        opt = ir.eliminateDeadBranches(&body_ir, opt);
        opt = ir.simplifyBooleans(&body_ir, opt);
        opt = ir.eliminateIdentity(&body_ir, opt);
        opt = ir.simplifyBegin(&body_ir, opt);
        body_nodes[body_count] = opt;
        body_count += 1;
        body_expr = types.cdr(body_expr);
    }
    if (body_count == 0) return null;

    const extra: u8 = if (rest_name != null) 1 else 0;
    var allowed: [17][]const u8 = undefined;
    @memcpy(allowed[0..arity], param_names[0..arity]);
    if (rest_name) |rn| {
        allowed[arity] = rn;
    }
    if (hasFreeVars(body_nodes[0..body_count], allowed[0 .. arity + extra])) return null;

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

    var body_ir = ir.IR.init(self.allocator);
    defer body_ir.deinit();
    var body_nodes: [64]*ir.Node = undefined;
    var body_count: usize = 0;
    var body_expr = body_list;
    while (body_expr != types.NIL and types.isPair(body_expr)) {
        if (body_count >= 64) return null;
        const expr = types.car(body_expr);
        const node = ir.lowerWithMacros(&body_ir, expr, null) catch return null;
        ir.markTailPositions(node, types.cdr(body_expr) == types.NIL);
        ir.identifyPrimitives(node);
        ir.markConstants(node);
        var opt = ir.foldConstants(&body_ir, node);
        opt = ir.eliminateDeadBranches(&body_ir, opt);
        opt = ir.simplifyBooleans(&body_ir, opt);
        opt = ir.eliminateIdentity(&body_ir, opt);
        opt = ir.simplifyBegin(&body_ir, opt);
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
    const fn_name = std.fmt.allocPrint(self.allocator, "@closure_{d}", .{id}) catch return null;
    const closure_name = data.name orelse "(closure)";

    var fn_buf: std.ArrayList(u8) = .empty;
    const saved_buf = self.buf;
    const saved_params = self.params;
    const saved_tmp = self.tmp_counter;
    const saved_label = self.label_counter;
    const saved_fn_name = self.current_fn_name;
    const saved_body_label = self.body_label;
    const saved_block = self.current_block;
    self.buf = fn_buf;
    self.tmp_counter = 0;
    self.label_counter = 0;
    self.current_fn_name = null;
    self.body_label = null;
    self.current_block = "entry";

    var p = std.StringHashMap(u8).init(self.allocator);
    for (param_names[0..arity], 0..) |pname, i| {
        p.put(pname, @intCast(i)) catch {
            self.buf = saved_buf;
            self.params = saved_params;
            self.tmp_counter = saved_tmp;
            self.label_counter = saved_label;
            self.current_fn_name = saved_fn_name;
            self.body_label = saved_body_label;
            self.current_block = saved_block;
            return null;
        };
    }

    var uv_map = std.StringHashMap(u8).init(self.allocator);
    defer uv_map.deinit();
    for (free_vars[0..free_count], 0..) |fv, i| {
        if (outer_params.contains(fv)) {
            uv_map.put(fv, @intCast(i)) catch {
                self.buf = saved_buf;
                self.params = saved_params;
                self.tmp_counter = saved_tmp;
                self.label_counter = saved_label;
                self.current_fn_name = saved_fn_name;
                self.body_label = saved_body_label;
                self.current_block = saved_block;
                p.deinit();
                return null;
            };
        }
    }
    self.params = p;
    self.upvalues = uv_map;

    const header = std.fmt.allocPrint(self.allocator, "; closure: {s}\ndefine i64 {s}(ptr %vm, ptr %args, i64 %nargs, ptr %upvalues) {{\nentry:\n", .{ closure_name, fn_name }) catch {
        self.buf = saved_buf;
        self.params = saved_params;
        self.upvalues = null;
        self.tmp_counter = saved_tmp;
        self.label_counter = saved_label;
        self.current_fn_name = saved_fn_name;
        self.body_label = saved_body_label;
        self.current_block = saved_block;
        p.deinit();
        return null;
    };
    defer self.allocator.free(header);
    self.write(header) catch {
        self.buf = saved_buf;
        self.params = saved_params;
        self.upvalues = null;
        self.tmp_counter = saved_tmp;
        self.label_counter = saved_label;
        self.current_fn_name = saved_fn_name;
        self.body_label = saved_body_label;
        self.current_block = saved_block;
        p.deinit();
        return null;
    };

    var last_val: []const u8 = "";
    for (body_nodes[0..body_count]) |node| {
        last_val = self.emitNode(node) catch {
            self.buf = saved_buf;
            self.params = saved_params;
            self.upvalues = null;
            self.tmp_counter = saved_tmp;
            self.label_counter = saved_label;
            self.current_fn_name = saved_fn_name;
            self.body_label = saved_body_label;
            self.current_block = saved_block;
            p.deinit();
            fn_buf.deinit(self.allocator);
            return null;
        };
    }

    self.print("  ret i64 {s}\n}}\n", .{last_val}) catch {
        self.buf = saved_buf;
        self.params = saved_params;
        self.upvalues = null;
        self.tmp_counter = saved_tmp;
        self.label_counter = saved_label;
        self.current_fn_name = saved_fn_name;
        self.body_label = saved_body_label;
        self.current_block = saved_block;
        p.deinit();
        fn_buf.deinit(self.allocator);
        return null;
    };

    fn_buf = self.buf;
    self.buf = saved_buf;
    self.params = saved_params;
    self.upvalues = null;
    self.tmp_counter = saved_tmp;
    self.label_counter = saved_label;
    self.current_fn_name = saved_fn_name;
    self.body_label = saved_body_label;
    self.current_block = saved_block;
    p.deinit();

    const fn_def = fn_buf.toOwnedSlice(self.allocator) catch return null;
    self.lambda_defs.append(self.allocator, fn_def) catch return null;

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
    try bindParamsAsGlobals(self);

    var source_buf: std.ArrayList(u8) = .empty;
    defer source_buf.deinit(self.allocator);
    source_buf.appendSlice(self.allocator, "(lambda ") catch return error.OutOfMemory;

    var current = data.args;
    var first = true;
    while (current != types.NIL and types.isPair(current)) {
        if (!first) source_buf.append(self.allocator, ' ') catch return error.OutOfMemory;
        first = false;
        const elem = types.car(current);
        const elem_str = printer.valueToString(self.allocator, elem, .write) catch return error.OutOfMemory;
        defer self.allocator.free(elem_str);
        source_buf.appendSlice(self.allocator, elem_str) catch return error.OutOfMemory;
        current = types.cdr(current);
    }
    source_buf.append(self.allocator, ')') catch return error.OutOfMemory;

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

    var body_ir = ir.IR.init(self.allocator);
    defer body_ir.deinit();

    var body_nodes: [64]*ir.Node = undefined;
    var body_count: usize = 0;
    var body_expr = body;
    while (body_expr != types.NIL and types.isPair(body_expr)) {
        if (body_count >= 64) return null;
        const expr = types.car(body_expr);
        const node = ir.lowerWithMacros(&body_ir, expr, null) catch return null;
        ir.markTailPositions(node, types.cdr(body_expr) == types.NIL);
        ir.identifyPrimitives(node);
        ir.markConstants(node);
        var opt = ir.foldConstants(&body_ir, node);
        opt = ir.eliminateDeadBranches(&body_ir, opt);
        opt = ir.simplifyBooleans(&body_ir, opt);
        opt = ir.eliminateIdentity(&body_ir, opt);
        opt = ir.simplifyBegin(&body_ir, opt);
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
    const fn_name = std.fmt.allocPrint(self.allocator, "@lambda_{d}", .{id}) catch return null;

    if (name) |n| {
        self.native_fns.put(n, .{ .llvm_name = fn_name, .arity = @intCast(param_names.len) }) catch {};
    }

    var fn_buf: std.ArrayList(u8) = .empty;
    const saved_buf = self.buf;
    const saved_params = self.params;
    const saved_tmp = self.tmp_counter;
    const saved_label = self.label_counter;
    const saved_fn_name = self.current_fn_name;
    const saved_body_label = self.body_label;
    const saved_block = self.current_block;
    const saved_rest_alloca = self.rest_param_alloca;
    const saved_rest_name = self.rest_param_name;
    self.buf = fn_buf;
    self.tmp_counter = 0;
    self.label_counter = 0;

    var p = std.StringHashMap(u8).init(self.allocator);
    for (param_names, 0..) |pname, i| {
        p.put(pname, @intCast(i)) catch {
            restoreState(self, saved_buf, saved_params, saved_tmp, saved_label, saved_fn_name, saved_body_label, saved_block, saved_rest_alloca, saved_rest_name);
            return null;
        };
    }
    self.params = p;

    const body_lbl = std.fmt.allocPrint(self.allocator, "body_{d}", .{id}) catch {
        restoreState(self, saved_buf, saved_params, saved_tmp, saved_label, saved_fn_name, saved_body_label, saved_block, saved_rest_alloca, saved_rest_name);
        p.deinit();
        return null;
    };

    self.current_fn_name = if (rest_name == null) name else null;
    self.body_label = if (rest_name == null) body_lbl else null;
    self.current_block = body_lbl;
    self.rest_param_name = rest_name;

    const header = std.fmt.allocPrint(self.allocator, "; {s}\ndefine i64 {s}(ptr %vm, ptr %args, i64 %nargs, ptr %upvalues) {{\nentry:\n  br label %{s}\n{s}:\n", .{ name orelse "(lambda)", fn_name, body_lbl, body_lbl }) catch {
        restoreState(self, saved_buf, saved_params, saved_tmp, saved_label, saved_fn_name, saved_body_label, saved_block, saved_rest_alloca, saved_rest_name);
        p.deinit();
        return null;
    };
    defer self.allocator.free(header);
    self.write(header) catch {
        restoreState(self, saved_buf, saved_params, saved_tmp, saved_label, saved_fn_name, saved_body_label, saved_block, saved_rest_alloca, saved_rest_name);
        p.deinit();
        return null;
    };

    if (rest_name != null) {
        emitRestListBuilder(self, param_names.len) catch {
            restoreState(self, saved_buf, saved_params, saved_tmp, saved_label, saved_fn_name, saved_body_label, saved_block, saved_rest_alloca, saved_rest_name);
            p.deinit();
            fn_buf.deinit(self.allocator);
            return null;
        };
    }

    var last_val: []const u8 = "";
    for (body_nodes) |node| {
        last_val = self.emitNode(node) catch {
            restoreState(self, saved_buf, saved_params, saved_tmp, saved_label, saved_fn_name, saved_body_label, saved_block, saved_rest_alloca, saved_rest_name);
            p.deinit();
            fn_buf.deinit(self.allocator);
            return null;
        };
    }

    self.print("  ret i64 {s}\n}}\n", .{last_val}) catch {
        restoreState(self, saved_buf, saved_params, saved_tmp, saved_label, saved_fn_name, saved_body_label, saved_block, saved_rest_alloca, saved_rest_name);
        p.deinit();
        fn_buf.deinit(self.allocator);
        return null;
    };

    fn_buf = self.buf;
    restoreState(self, saved_buf, saved_params, saved_tmp, saved_label, saved_fn_name, saved_body_label, saved_block, saved_rest_alloca, saved_rest_name);
    p.deinit();

    const fn_def = fn_buf.toOwnedSlice(self.allocator) catch return null;
    self.lambda_defs.append(self.allocator, fn_def) catch return null;

    return fn_name;
}

fn restoreState(self: *LLVMEmitter, buf: std.ArrayList(u8), params: ?std.StringHashMap(u8), tmp: u32, label: u32, fn_name: ?[]const u8, body_label: ?[]const u8, block: []const u8, rest_alloca: ?[]const u8, rp_name: ?[]const u8) void {
    self.buf = buf;
    self.params = params;
    self.tmp_counter = tmp;
    self.label_counter = label;
    self.current_fn_name = fn_name;
    self.body_label = body_label;
    self.current_block = block;
    self.rest_param_alloca = rest_alloca;
    self.rest_param_name = rp_name;
}

fn emitRestListBuilder(self: *LLVMEmitter, fixed_arity: usize) EmitError!void {
    const nil_val: i64 = @bitCast(types.NIL);
    const rest_alloca = try self.freshTemp();
    try self.print("  {s} = alloca i64, align 8\n", .{rest_alloca});
    self.rest_param_alloca = rest_alloca;

    const nil_tmp = try self.freshTemp();
    try self.print("  {s} = add i64 0, {d}\n", .{ nil_tmp, nil_val });
    try self.print("  store i64 {s}, ptr {s}\n", .{ nil_tmp, rest_alloca });

    const lbl_id = self.label_counter;
    self.label_counter += 1;
    const check_lbl = try std.fmt.allocPrint(self.allocator, "rest_check_{d}", .{lbl_id});
    const body_lbl = try std.fmt.allocPrint(self.allocator, "rest_body_{d}", .{lbl_id});
    const done_lbl = try std.fmt.allocPrint(self.allocator, "rest_done_{d}", .{lbl_id});

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

// --- Free variable analysis helpers (standalone, no self) ---

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
        .constant => return false,
        else => return false,
    }
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
        else => {},
    }
}
