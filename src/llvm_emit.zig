const std = @import("std");
const ir = @import("ir.zig");
const types = @import("types.zig");
const printer = @import("printer.zig");

const Value = types.Value;

const NativeLambda = struct {
    llvm_name: []const u8,
    arity: u8,
    is_variadic: bool,
};

pub const LLVMEmitter = struct {
    buf: std.ArrayList(u8),
    symbols: std.StringHashMap(u32),
    string_decls: std.ArrayList([]const u8),
    lambda_defs: std.ArrayList([]const u8),
    native_fns: std.StringHashMap(NativeLambda),
    rebound_globals: std.StringHashMap(void),
    params: ?std.StringHashMap(u8),
    upvalues: ?std.StringHashMap(u8),
    tmp_counter: u32,
    label_counter: u32,
    string_counter: u32,
    sym_counter: u32,
    lambda_counter: u32,
    allocator: std.mem.Allocator,
    current_fn_name: ?[]const u8 = null,
    body_label: ?[]const u8 = null,
    current_block: []const u8 = "entry",
    rest_param_alloca: ?[]const u8 = null,
    rest_param_name: ?[]const u8 = null,
    locals: ?std.StringHashMap([]const u8) = null,

    pub fn init(allocator: std.mem.Allocator) LLVMEmitter {
        return .{
            .buf = .empty,
            .symbols = std.StringHashMap(u32).init(allocator),
            .string_decls = .empty,
            .lambda_defs = .empty,
            .native_fns = std.StringHashMap(NativeLambda).init(allocator),
            .rebound_globals = std.StringHashMap(void).init(allocator),
            .params = null,
            .upvalues = null,
            .tmp_counter = 0,
            .label_counter = 0,
            .string_counter = 0,
            .sym_counter = 0,
            .lambda_counter = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LLVMEmitter) void {
        self.buf.deinit(self.allocator);
        self.symbols.deinit();
        self.string_decls.deinit(self.allocator);
        self.lambda_defs.deinit(self.allocator);
        self.native_fns.deinit();
        self.rebound_globals.deinit();
    }

    pub fn emitProgram(self: *LLVMEmitter, nodes: []const *ir.Node) EmitError!void {
        // Emit body into a separate buffer to collect string decls
        var body: std.ArrayList(u8) = .empty;
        defer body.deinit(self.allocator);
        const saved_buf = self.buf;
        self.buf = body;

        self.write("  %vm = call ptr @kaappi_runtime_init()\n") catch return error.OutOfMemory;
        for (nodes) |node| {
            _ = self.emitNode(node) catch return error.OutOfMemory;
        }

        body = self.buf;
        self.buf = saved_buf;

        // Now emit preamble + symbols + string decls + body
        try self.emitPreamble();

        // Emit all symbol constants collected during body emission
        var sym_iter = self.symbols.iterator();
        try self.write("\n");
        while (sym_iter.next()) |entry| {
            const name = entry.key_ptr.*;
            const id = entry.value_ptr.*;
            try self.print("@.sym.{d} = private unnamed_addr constant [{d} x i8] c\"", .{ id, name.len });
            for (name) |byte| {
                if (byte >= 0x20 and byte < 0x7F and byte != '"' and byte != '\\') {
                    try self.print("{c}", .{byte});
                } else {
                    try self.print("\\{X:0>2}", .{byte});
                }
            }
            try self.write("\"\n");
        }

        for (self.string_decls.items) |decl| {
            try self.write(decl);
        }

        for (self.lambda_defs.items) |def| {
            try self.write("\n");
            try self.write(def);
        }

        try self.write("\ndefine i32 @main() {\nentry:\n");
        try self.write(body.items);

        try self.write("\n  call void @kaappi_runtime_deinit(ptr %vm)\n");
        try self.write("  ret i32 0\n}\n");
    }

    pub fn emitNode(self: *LLVMEmitter, node: *const ir.Node) EmitError![]const u8 {
        return switch (node.tag) {
            .constant => try self.emitConstant(node.data.constant),
            .global_ref => try self.emitGlobalRef(node.data.global_ref),
            .call => try self.emitCallNode(node),
            .begin => try self.emitBegin(node.data.begin),
            .@"if" => try self.emitIf(node.data.@"if"),
            .and_form => try self.emitAnd(node.data.and_form),
            .or_form => try self.emitOr(node.data.or_form),
            .when_form => try self.emitWhen(node.data.when_form),
            .unless_form => try self.emitUnless(node.data.unless_form),
            .define => try self.emitDefine(node.data.define),
            .set_form => try self.emitSet(node.data.set_form),
            .lambda => try self.emitLambda(node.data.lambda),
            .let_form => try self.emitLet(node.data.let_form.args, false, node.ann.is_tail),
            .let_star => try self.emitLet(node.data.let_star.args, true, node.ann.is_tail),
            .letrec, .letrec_star, .named_let => try self.emitSexprEval(node),
            .do_form, .delay, .delay_force, .cond, .case_form, .case_lambda, .guard => try self.emitSexprEval(node),
            .quasiquote, .parameterize, .define_values, .let_values, .let_star_values => try self.emitSexprEval(node),
            .define_syntax, .let_syntax, .letrec_syntax, .cond_expand => try self.emitSexprEval(node),
            .passthrough => try self.emitPassthrough(node.data.passthrough),
        };
    }

    fn emitConstant(self: *LLVMEmitter, value: Value) EmitError![]const u8 {
        if (types.isString(value)) {
            const str_data = types.toObject(value).as(types.SchemeString).data;
            const str_name = try self.internString(str_data);
            const tmp = try self.freshTemp();
            try self.print("  {s} = call i64 @kaappi_make_string(ptr %vm, ptr {s}, i64 {d})\n", .{ tmp, str_name, str_data.len });
            return tmp;
        }
        if (types.isSymbol(value)) {
            const sym_data = types.symbolName(value);
            const str_name = try self.internString(sym_data);
            const tmp = try self.freshTemp();
            try self.print("  {s} = call i64 @kaappi_intern_symbol(ptr %vm, ptr {s}, i64 {d})\n", .{ tmp, str_name, sym_data.len });
            return tmp;
        }
        if (types.isPointer(value)) {
            return self.emitQuotedEvalExpr(value);
        }
        const tmp = try self.freshTemp();
        const signed: i64 = @bitCast(value);
        try self.print("  {s} = add i64 0, {d}\n", .{ tmp, signed });
        return tmp;
    }

    fn isNameShadowed(self: *LLVMEmitter, name: []const u8) bool {
        if (self.locals) |loc| {
            if (loc.get(name) != null) return true;
        }
        if (self.rest_param_name) |rp_name| {
            if (std.mem.eql(u8, name, rp_name)) return true;
        }
        if (self.params) |p| {
            if (p.get(name) != null) return true;
        }
        if (self.upvalues) |uv| {
            if (uv.get(name) != null) return true;
        }
        return false;
    }

    fn emitGlobalRef(self: *LLVMEmitter, sym: Value) EmitError![]const u8 {
        if (!types.isSymbol(sym)) return error.UnsupportedNodeType;
        const name = types.symbolName(sym);

        if (self.locals) |loc| {
            if (loc.get(name)) |alloca_name| {
                const tmp = try self.freshTemp();
                try self.print("  {s} = load i64, ptr {s}\n", .{ tmp, alloca_name });
                return tmp;
            }
        }

        if (self.rest_param_name) |rp_name| {
            if (std.mem.eql(u8, name, rp_name)) {
                const tmp = try self.freshTemp();
                try self.print("  {s} = load i64, ptr {s}\n", .{ tmp, self.rest_param_alloca.? });
                return tmp;
            }
        }

        if (self.params) |p| {
            if (p.get(name)) |idx| {
                const tmp = try self.freshTemp();
                const gep = try self.freshTemp();
                try self.print("  {s} = getelementptr i64, ptr %args, i64 {d}\n", .{ gep, idx });
                try self.print("  {s} = load i64, ptr {s}\n", .{ tmp, gep });
                return tmp;
            }
        }

        if (self.upvalues) |uv| {
            if (uv.get(name)) |idx| {
                const tmp = try self.freshTemp();
                const gep = try self.freshTemp();
                try self.print("  {s} = getelementptr i64, ptr %upvalues, i64 {d}\n", .{ gep, idx });
                try self.print("  {s} = load i64, ptr {s}\n", .{ tmp, gep });
                return tmp;
            }
        }

        const sym_name = try self.internSymbol(name);
        const tmp = try self.freshTemp();
        try self.print("  {s} = call i64 @kaappi_global_lookup(ptr %vm, ptr {s}, i64 {d})\n", .{ tmp, sym_name, name.len });
        return tmp;
    }

    fn emitCallNode(self: *LLVMEmitter, node: *const ir.Node) EmitError![]const u8 {
        const call = node.data.call;
        const is_tail = node.ann.is_tail;

        if (call.operator.tag == .global_ref and types.isSymbol(call.operator.data.global_ref)) {
            const op_name = types.symbolName(call.operator.data.global_ref);

            const is_shadowed = self.isNameShadowed(op_name);

            if (!is_shadowed and is_tail) {
                if (self.current_fn_name) |fn_name| {
                    if (self.body_label) |body_lbl| {
                        if (std.mem.eql(u8, op_name, fn_name)) {
                            if (self.native_fns.get(fn_name)) |self_fn| {
                                if (call.args.len == self_fn.arity) {
                                    return self.emitSelfTailCall(call.args, body_lbl);
                                }
                            }
                        }
                    }
                }
            }

            if (!is_shadowed) {
                if (self.native_fns.get(op_name)) |native| {
                    const arity_ok = if (native.is_variadic)
                        call.args.len >= native.arity
                    else
                        call.args.len == native.arity;
                    if (arity_ok) {
                        return self.emitDirectCall(native.llvm_name, call.args, is_tail);
                    }
                }
            }
            if (!is_shadowed and !self.rebound_globals.contains(op_name)) {
                if (call.args.len == 2) {
                    if (self.tryEmitInlineBinary(op_name, call.args)) |result| return result;
                }
                if (call.args.len == 1) {
                    if (self.tryEmitInlineUnary(op_name, call.args[0])) |result| return result;
                }
            }
        }

        const callee = try self.emitNode(call.operator);
        const nargs = call.args.len;

        var arg_tmps: [256][]const u8 = undefined;
        for (call.args, 0..) |arg, i| {
            arg_tmps[i] = try self.emitNode(arg);
        }

        const result = try self.freshTemp();

        if (nargs == 0) {
            const call_prefix: []const u8 = if (is_tail) "tail call" else "call";
            try self.print("  {s} = {s} i64 @kaappi_call_scheme(ptr %vm, i64 {s}, ptr null, i64 0)\n", .{ result, call_prefix, callee });
        } else {
            const args_alloca = try self.freshTemp();
            try self.print("  {s} = alloca [{d} x i64], align 8\n", .{ args_alloca, nargs });

            for (0..nargs) |i| {
                const gep = try self.freshTemp();
                try self.print("  {s} = getelementptr [1 x i64], ptr {s}, i64 {d}\n", .{ gep, args_alloca, i });
                try self.print("  store i64 {s}, ptr {s}\n", .{ arg_tmps[i], gep });
            }

            try self.print("  {s} = call i64 @kaappi_call_scheme(ptr %vm, i64 {s}, ptr {s}, i64 {d})\n", .{ result, callee, args_alloca, nargs });
        }

        if (is_tail) {
            try self.print("  ret i64 {s}\n", .{result});
            const after_label = try std.fmt.allocPrint(self.allocator, "after_tail_{d}", .{self.label_counter});
            self.label_counter += 1;
            try self.print("{s}:\n", .{after_label});
            self.current_block = after_label;
        }

        return result;
    }

    fn emitSelfTailCall(self: *LLVMEmitter, args: []const *ir.Node, body_lbl: []const u8) EmitError![]const u8 {
        var arg_tmps: [256][]const u8 = undefined;
        for (args, 0..) |arg, i| {
            arg_tmps[i] = try self.emitNode(arg);
        }

        for (0..args.len) |i| {
            const gep = try self.freshTemp();
            try self.print("  {s} = getelementptr i64, ptr %args, i64 {d}\n", .{ gep, i });
            try self.print("  store i64 {s}, ptr {s}\n", .{ arg_tmps[i], gep });
        }

        try self.print("  br label %{s}\n", .{body_lbl});

        const after_label = try std.fmt.allocPrint(self.allocator, "after_tail_{d}", .{self.label_counter});
        self.label_counter += 1;
        try self.print("{s}:\n", .{after_label});
        self.current_block = after_label;

        const void_val: i64 = @bitCast(types.VOID);
        const dummy = try self.freshTemp();
        try self.print("  {s} = add i64 0, {d}\n", .{ dummy, void_val });
        return dummy;
    }

    fn emitBegin(self: *LLVMEmitter, exprs: []const *ir.Node) EmitError![]const u8 {
        var last: []const u8 = "";
        for (exprs) |expr| {
            last = try self.emitNode(expr);
        }
        return last;
    }

    fn emitLetFallback(self: *LLVMEmitter, args: Value, sequential: bool) EmitError![]const u8 {
        const keyword = if (sequential) "let*" else "let";
        const printed = printer.valueToString(self.allocator, args, .write) catch return error.OutOfMemory;
        defer self.allocator.free(printed);
        const source = std.fmt.allocPrint(self.allocator, "({s} {s})", .{ keyword, printed }) catch return error.OutOfMemory;
        defer self.allocator.free(source);
        const str_name = try self.internString(source);
        const tmp = try self.freshTemp();
        try self.print("  {s} = call i64 @kaappi_eval(ptr %vm, ptr {s}, i64 {d})\n", .{ tmp, str_name, source.len });
        return tmp;
    }

    fn emitLet(self: *LLVMEmitter, args: Value, sequential: bool, is_tail: bool) EmitError![]const u8 {
        const bindings = types.car(args);
        const body_list = types.cdr(args);

        const saved_locals = self.locals;
        self.locals = if (saved_locals) |existing|
            existing.clone() catch return error.OutOfMemory
        else
            std.StringHashMap([]const u8).init(self.allocator);

        if (!sequential) {
            var init_vals: [32][]const u8 = undefined;
            var var_names: [32][]const u8 = undefined;
            var count: usize = 0;
            var blist = bindings;
            while (blist != types.NIL and types.isPair(blist)) {
                if (count >= 32) {
                    self.locals.?.deinit();
                    self.locals = saved_locals;
                    return self.emitLetFallback(args, sequential);
                }
                const binding = types.car(blist);
                const var_sym = types.car(binding);
                const init_expr = types.car(types.cdr(binding));
                if (!types.isSymbol(var_sym)) {
                    self.locals.?.deinit();
                    self.locals = saved_locals;
                    return self.emitLetFallback(args, sequential);
                }

                const node = ir.lowerSingleExpr(self.allocator, init_expr) catch {
                    self.locals.?.deinit();
                    self.locals = saved_locals;
                    return self.emitLetFallback(args, sequential);
                };
                init_vals[count] = try self.emitNode(node);
                var_names[count] = types.symbolName(var_sym);
                count += 1;
                blist = types.cdr(blist);
            }

            for (0..count) |i| {
                const alloca = try self.freshTemp();
                try self.print("  {s} = alloca i64, align 8\n", .{alloca});
                try self.print("  store i64 {s}, ptr {s}\n", .{ init_vals[i], alloca });
                self.locals.?.put(var_names[i], alloca) catch return error.OutOfMemory;
            }
        } else {
            var blist = bindings;
            while (blist != types.NIL and types.isPair(blist)) {
                const binding = types.car(blist);
                const var_sym = types.car(binding);
                const init_expr = types.car(types.cdr(binding));
                if (!types.isSymbol(var_sym)) {
                    self.locals.?.deinit();
                    self.locals = saved_locals;
                    return self.emitLetFallback(args, sequential);
                }

                const node = ir.lowerSingleExpr(self.allocator, init_expr) catch {
                    self.locals.?.deinit();
                    self.locals = saved_locals;
                    return self.emitLetFallback(args, sequential);
                };
                const val = try self.emitNode(node);
                const alloca = try self.freshTemp();
                try self.print("  {s} = alloca i64, align 8\n", .{alloca});
                try self.print("  store i64 {s}, ptr {s}\n", .{ val, alloca });
                self.locals.?.put(types.symbolName(var_sym), alloca) catch return error.OutOfMemory;
                blist = types.cdr(blist);
            }
        }

        var last: []const u8 = "";
        var body_expr = body_list;
        while (body_expr != types.NIL and types.isPair(body_expr)) {
            const rest = types.cdr(body_expr);
            const expr_is_tail = is_tail and (rest == types.NIL or !types.isPair(rest));
            const node = ir.lowerSingleExprTail(self.allocator, types.car(body_expr), expr_is_tail) catch {
                self.locals.?.deinit();
                self.locals = saved_locals;
                return error.UnsupportedNodeType;
            };
            last = try self.emitNode(node);
            body_expr = rest;
        }

        self.locals.?.deinit();
        self.locals = saved_locals;
        return last;
    }

    fn emitSexprEvalValue(self: *LLVMEmitter, args: Value) EmitError![]const u8 {
        return self.emitEvalExpr(args);
    }

    fn emitIf(self: *LLVMEmitter, data: ir.IfData) EmitError![]const u8 {
        const test_val = try self.emitNode(data.test_expr);

        const false_val: i64 = @bitCast(types.FALSE);
        const cmp = try self.freshTemp();
        try self.print("  {s} = icmp ne i64 {s}, {d}\n", .{ cmp, test_val, false_val });

        const label_id = self.label_counter;
        self.label_counter += 1;

        const then_label = try std.fmt.allocPrint(self.allocator, "then{d}", .{label_id});
        const else_label = try std.fmt.allocPrint(self.allocator, "else{d}", .{label_id});
        const merge_label = try std.fmt.allocPrint(self.allocator, "merge{d}", .{label_id});
        const pre_label = try std.fmt.allocPrint(self.allocator, "pre{d}", .{label_id});

        // Name the current block so phi can reference it
        try self.print("  br label %{s}\n{s}:\n", .{ pre_label, pre_label });
        self.current_block = pre_label;

        if (data.alternate != null) {
            try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cmp, then_label, else_label });
        } else {
            try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cmp, then_label, merge_label });
        }

        try self.print("{s}:\n", .{then_label});
        self.current_block = then_label;
        const then_val = try self.emitNode(data.consequent);
        const then_end_block = self.current_block;
        try self.print("  br label %{s}\n", .{merge_label});

        if (data.alternate) |alt| {
            try self.print("{s}:\n", .{else_label});
            self.current_block = else_label;
            const else_val = try self.emitNode(alt);
            const else_end_block = self.current_block;
            try self.print("  br label %{s}\n", .{merge_label});

            try self.print("{s}:\n", .{merge_label});
            self.current_block = merge_label;
            const result = try self.freshTemp();
            try self.print("  {s} = phi i64 [ {s}, %{s} ], [ {s}, %{s} ]\n", .{ result, then_val, then_end_block, else_val, else_end_block });
            return result;
        } else {
            const void_val: i64 = @bitCast(types.VOID);
            try self.print("{s}:\n", .{merge_label});
            self.current_block = merge_label;
            const result = try self.freshTemp();
            try self.print("  {s} = phi i64 [ {s}, %{s} ], [ {d}, %{s} ]\n", .{ result, then_val, then_end_block, void_val, pre_label });
            return result;
        }
    }

    fn emitAnd(self: *LLVMEmitter, exprs: []const *ir.Node) EmitError![]const u8 {
        if (exprs.len == 0) {
            const tmp = try self.freshTemp();
            const true_val: i64 = @bitCast(types.TRUE);
            try self.print("  {s} = add i64 0, {d}\n", .{ tmp, true_val });
            return tmp;
        }
        if (exprs.len == 1) return try self.emitNode(exprs[0]);

        const false_val: i64 = @bitCast(types.FALSE);
        const label_id = self.label_counter;
        self.label_counter += 1;
        const merge_label = try std.fmt.allocPrint(self.allocator, "and_merge{d}", .{label_id});

        var prev_val = try self.emitNode(exprs[0]);
        for (exprs[1..], 0..) |expr, i| {
            const next_label = try std.fmt.allocPrint(self.allocator, "and_next{d}_{d}", .{ label_id, i });
            const cmp = try self.freshTemp();
            try self.print("  {s} = icmp ne i64 {s}, {d}\n", .{ cmp, prev_val, false_val });
            const short_label = try std.fmt.allocPrint(self.allocator, "and_short{d}_{d}", .{ label_id, i });
            try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cmp, next_label, short_label });
            try self.print("{s}:\n", .{short_label});
            try self.print("  br label %{s}\n", .{merge_label});
            try self.print("{s}:\n", .{next_label});
            prev_val = try self.emitNode(expr);
        }
        const last_next = try std.fmt.allocPrint(self.allocator, "and_done{d}", .{label_id});
        try self.print("  br label %{s}\n{s}:\n", .{ last_next, last_next });
        try self.print("  br label %{s}\n", .{merge_label});
        try self.print("{s}:\n", .{merge_label});
        self.current_block = merge_label;

        const result = try self.freshTemp();
        try self.print("  {s} = phi i64 [ {s}, %{s} ]", .{ result, prev_val, last_next });
        for (0..exprs.len - 1) |i| {
            const short_false = try self.freshTemp();
            _ = short_false;
            try self.print(", [ {d}, %and_short{d}_{d} ]", .{ false_val, label_id, i });
        }
        try self.write("\n");
        return result;
    }

    fn emitOr(self: *LLVMEmitter, exprs: []const *ir.Node) EmitError![]const u8 {
        if (exprs.len == 0) {
            const tmp = try self.freshTemp();
            const false_val: i64 = @bitCast(types.FALSE);
            try self.print("  {s} = add i64 0, {d}\n", .{ tmp, false_val });
            return tmp;
        }
        if (exprs.len == 1) return try self.emitNode(exprs[0]);

        const false_val: i64 = @bitCast(types.FALSE);
        const label_id = self.label_counter;
        self.label_counter += 1;
        const merge_label = try std.fmt.allocPrint(self.allocator, "or_merge{d}", .{label_id});

        var vals: [256][]const u8 = undefined;
        var labels: [256][]const u8 = undefined;
        var count: usize = 0;

        for (exprs[0 .. exprs.len - 1], 0..) |expr, i| {
            const val = try self.emitNode(expr);
            vals[count] = val;
            labels[count] = try std.fmt.allocPrint(self.allocator, "or_check{d}_{d}", .{ label_id, i });
            count += 1;
            const next_label = try std.fmt.allocPrint(self.allocator, "or_next{d}_{d}", .{ label_id, i });
            const pre_label = labels[count - 1];
            try self.print("  br label %{s}\n{s}:\n", .{ pre_label, pre_label });
            const cmp = try self.freshTemp();
            try self.print("  {s} = icmp ne i64 {s}, {d}\n", .{ cmp, val, false_val });
            try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cmp, merge_label, next_label });
            try self.print("{s}:\n", .{next_label});
        }

        const last_val = try self.emitNode(exprs[exprs.len - 1]);
        const last_label = try std.fmt.allocPrint(self.allocator, "or_last{d}", .{label_id});
        try self.print("  br label %{s}\n{s}:\n", .{ last_label, last_label });
        try self.print("  br label %{s}\n", .{merge_label});
        try self.print("{s}:\n", .{merge_label});
        self.current_block = merge_label;

        const result = try self.freshTemp();
        try self.print("  {s} = phi i64 [ {s}, %{s} ]", .{ result, last_val, last_label });
        for (0..count) |i| {
            try self.print(", [ {s}, %{s} ]", .{ vals[i], labels[i] });
        }
        try self.write("\n");
        return result;
    }

    fn emitWhen(self: *LLVMEmitter, data: ir.CondBodyData) EmitError![]const u8 {
        const test_val = try self.emitNode(data.test_expr);
        const false_val: i64 = @bitCast(types.FALSE);
        const cmp = try self.freshTemp();
        try self.print("  {s} = icmp ne i64 {s}, {d}\n", .{ cmp, test_val, false_val });

        const label_id = self.label_counter;
        self.label_counter += 1;
        const body_label = try std.fmt.allocPrint(self.allocator, "when_body{d}", .{label_id});
        const merge_label = try std.fmt.allocPrint(self.allocator, "when_merge{d}", .{label_id});
        const pre_label = try std.fmt.allocPrint(self.allocator, "when_pre{d}", .{label_id});

        try self.print("  br label %{s}\n{s}:\n", .{ pre_label, pre_label });
        try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cmp, body_label, merge_label });
        try self.print("{s}:\n", .{body_label});
        self.current_block = body_label;

        var last: []const u8 = "";
        for (data.body) |expr| {
            last = try self.emitNode(expr);
        }
        const body_end_block = self.current_block;
        try self.print("  br label %{s}\n", .{merge_label});
        try self.print("{s}:\n", .{merge_label});
        self.current_block = merge_label;

        const void_val: i64 = @bitCast(types.VOID);
        const result = try self.freshTemp();
        try self.print("  {s} = phi i64 [ {s}, %{s} ], [ {d}, %{s} ]\n", .{ result, last, body_end_block, void_val, pre_label });
        return result;
    }

    fn emitUnless(self: *LLVMEmitter, data: ir.CondBodyData) EmitError![]const u8 {
        const test_val = try self.emitNode(data.test_expr);
        const false_val: i64 = @bitCast(types.FALSE);
        const cmp = try self.freshTemp();
        try self.print("  {s} = icmp eq i64 {s}, {d}\n", .{ cmp, test_val, false_val });

        const label_id = self.label_counter;
        self.label_counter += 1;
        const body_label = try std.fmt.allocPrint(self.allocator, "unless_body{d}", .{label_id});
        const merge_label = try std.fmt.allocPrint(self.allocator, "unless_merge{d}", .{label_id});
        const pre_label = try std.fmt.allocPrint(self.allocator, "unless_pre{d}", .{label_id});

        try self.print("  br label %{s}\n{s}:\n", .{ pre_label, pre_label });
        try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cmp, body_label, merge_label });
        try self.print("{s}:\n", .{body_label});
        self.current_block = body_label;

        var last: []const u8 = "";
        for (data.body) |expr| {
            last = try self.emitNode(expr);
        }
        const body_end_block = self.current_block;
        try self.print("  br label %{s}\n", .{merge_label});
        try self.print("{s}:\n", .{merge_label});
        self.current_block = merge_label;

        const void_val: i64 = @bitCast(types.VOID);
        const result = try self.freshTemp();
        try self.print("  {s} = phi i64 [ {s}, %{s} ], [ {d}, %{s} ]\n", .{ result, last, body_end_block, void_val, pre_label });
        return result;
    }

    fn emitSet(self: *LLVMEmitter, data: ir.SetData) EmitError![]const u8 {
        if (!types.isSymbol(data.name)) return error.UnsupportedNodeType;
        const name = types.symbolName(data.name);
        // Evaluate the new value with lexical scope respected, then store it
        // into whichever slot `name` resolves to (local alloca, parameter,
        // rest parameter, upvalue, or global). The old code always evaluated
        // the value in the global environment and rebound a global (#819).
        const val = try self.emitScopedValue(data.value);
        try self.emitStoreToVariable(name, val);

        // When set! targets a global, invalidate the native_fns entry so
        // later call sites fall back to kaappi_global_lookup (#822).
        if (!self.isNameShadowed(name)) {
            _ = self.native_fns.fetchRemove(name);
            self.rebound_globals.put(name, {}) catch {};
        }

        return self.emitVoid();
    }

    fn inLexicalScope(self: *LLVMEmitter) bool {
        return self.params != null or self.locals != null or
            self.rest_param_name != null or self.upvalues != null;
    }

    // Emit a value expression, resolving variable references against the
    // current lexical scope (params, locals, upvalues) rather than assuming
    // the global environment.
    fn emitScopedValue(self: *LLVMEmitter, value: Value) EmitError![]const u8 {
        if (types.isSymbol(value)) return self.emitGlobalRef(value);
        if (!types.isPair(value)) return self.emitConstant(value);
        // At the top level there are no lexical bindings, so evaluate the value
        // in the global environment via kaappi_eval. That also expands macro
        // calls correctly; the standalone IR lowering below runs without a
        // macro table and would mis-lower a top-level (set! x (some-macro ...)).
        if (!self.inLexicalScope()) return self.emitEvalExpr(value);
        const node = ir.lowerSingleExpr(self.allocator, value) catch return self.emitEvalExpr(value);
        return self.emitNode(node);
    }

    // Store `val` into the slot that `name` denotes in the current scope.
    // Resolution order mirrors emitGlobalRef's read path so writes and reads
    // reach the same binding.
    fn emitStoreToVariable(self: *LLVMEmitter, name: []const u8, val: []const u8) EmitError!void {
        if (self.locals) |loc| {
            if (loc.get(name)) |alloca_name| {
                try self.print("  store i64 {s}, ptr {s}\n", .{ val, alloca_name });
                return;
            }
        }
        if (self.rest_param_name) |rp_name| {
            if (std.mem.eql(u8, name, rp_name)) {
                try self.print("  store i64 {s}, ptr {s}\n", .{ val, self.rest_param_alloca.? });
                return;
            }
        }
        if (self.params) |p| {
            if (p.get(name)) |idx| {
                const gep = try self.freshTemp();
                try self.print("  {s} = getelementptr i64, ptr %args, i64 {d}\n", .{ gep, idx });
                try self.print("  store i64 {s}, ptr {s}\n", .{ val, gep });
                return;
            }
        }
        if (self.upvalues) |uv| {
            if (uv.get(name)) |idx| {
                const gep = try self.freshTemp();
                try self.print("  {s} = getelementptr i64, ptr %upvalues, i64 {d}\n", .{ gep, idx });
                try self.print("  store i64 {s}, ptr {s}\n", .{ val, gep });
                return;
            }
        }
        // Not a lexical binding: set! an existing global, erroring if unbound.
        const sym_name = try self.internSymbol(name);
        try self.print("  call void @kaappi_set_global(ptr %vm, ptr {s}, i64 {d}, i64 {s})\n", .{ sym_name, name.len, val });
    }

    // Emit an SSA temp holding the unspecified/void value (the result of set!
    // and define).
    fn emitVoid(self: *LLVMEmitter) EmitError![]const u8 {
        const result = try self.freshTemp();
        const void_val: i64 = @bitCast(types.VOID);
        try self.print("  {s} = add i64 0, {d}\n", .{ result, void_val });
        return result;
    }

    fn emitSexprEval(self: *LLVMEmitter, node: *const ir.Node) EmitError![]const u8 {
        const args = switch (node.tag) {
            .let_form => node.data.let_form.args,
            .let_star => node.data.let_star.args,
            .letrec => node.data.letrec.args,
            .letrec_star => node.data.letrec_star.args,
            .named_let => node.data.named_let.args,
            .do_form => node.data.do_form.args,
            .delay => node.data.delay.args,
            .delay_force => node.data.delay_force.args,
            .cond => node.data.cond.args,
            .case_form => node.data.case_form.args,
            .case_lambda => node.data.case_lambda.args,
            .guard => node.data.guard.args,
            .quasiquote => node.data.quasiquote.args,
            .parameterize => node.data.parameterize.args,
            .define_values => node.data.define_values.args,
            .let_values => node.data.let_values.args,
            .let_star_values => node.data.let_star_values.args,
            .define_syntax => node.data.define_syntax.args,
            .let_syntax => node.data.let_syntax.args,
            .letrec_syntax => node.data.letrec_syntax.args,
            .cond_expand => node.data.cond_expand.args,
            else => return error.UnsupportedNodeType,
        };
        const form_name = switch (node.tag) {
            .let_form => "let",
            .let_star => "let*",
            .letrec => "letrec",
            .letrec_star => "letrec*",
            .named_let => "let",
            .do_form => "do",
            .delay => "delay",
            .delay_force => "delay-force",
            .cond => "cond",
            .case_form => "case",
            .case_lambda => "case-lambda",
            .guard => "guard",
            .quasiquote => "quasiquote",
            .parameterize => "parameterize",
            .define_values => "define-values",
            .let_values => "let-values",
            .let_star_values => "let*-values",
            .define_syntax => "define-syntax",
            .let_syntax => "let-syntax",
            .letrec_syntax => "letrec-syntax",
            .cond_expand => "cond-expand",
            else => return error.UnsupportedNodeType,
        };

        try lambda.bindParamsAsGlobals(self);

        var source_buf: std.ArrayList(u8) = .empty;
        defer source_buf.deinit(self.allocator);
        source_buf.appendSlice(self.allocator, "(") catch return error.OutOfMemory;
        source_buf.appendSlice(self.allocator, form_name) catch return error.OutOfMemory;

        var current = args;
        while (current != types.NIL and types.isPair(current)) {
            source_buf.append(self.allocator, ' ') catch return error.OutOfMemory;
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

    fn emitPassthrough(self: *LLVMEmitter, expr: Value) EmitError![]const u8 {
        if (types.isPair(expr)) {
            const head = types.car(expr);
            if (types.isSymbol(head) and std.mem.eql(u8, types.symbolName(head), "define")) {
                const rest = types.cdr(expr);
                if (rest != types.NIL and types.isPair(rest)) {
                    const target = types.car(rest);
                    if (types.isPair(target) and types.isSymbol(types.car(target))) {
                        const fn_name = types.symbolName(types.car(target));
                        const formals = types.cdr(target);
                        const body = types.cdr(rest);
                        _ = self.native_fns.fetchRemove(fn_name);
                        self.rebound_globals.put(fn_name, {}) catch {};
                        if (self.tryCompileDefineFunction(fn_name, formals, body) != null) {
                            _ = self.rebound_globals.fetchRemove(fn_name);
                        }
                    }
                }
            }
        }
        return self.emitEvalExpr(expr);
    }

    fn emitDefine(self: *LLVMEmitter, data: ir.DefineData) EmitError![]const u8 {
        if (!types.isSymbol(data.name)) return error.UnsupportedNodeType;
        const name = types.symbolName(data.name);

        // Internal define inside a natively compiled lexical scope (a `let`
        // body). self.locals is only populated while emitLet emits a body, so
        // top-level and lambda-body defines fall through to the global path.
        // Create a fresh local binding so the define shadows any global of the
        // same name for the rest of the body, instead of overwriting it (#819).
        if (self.locals != null) {
            const alloca = try self.freshTemp();
            try self.print("  {s} = alloca i64, align 8\n", .{alloca});
            // Register before emitting the value so a self/mutual reference in
            // the initializer resolves to this binding (letrec*-style).
            self.locals.?.put(name, alloca) catch return error.OutOfMemory;
            const val = try self.emitScopedValue(data.value);
            try self.print("  store i64 {s}, ptr {s}\n", .{ val, alloca });
            return self.emitVoid();
        }

        const sym_name = try self.internSymbol(name);

        // Remove any stale native_fns entry before attempting native
        // compilation; tryCompileLambdaNative re-registers if it succeeds.
        // Mark the name rebound so inline primitive dispatch is suppressed
        // for later call sites (#822).
        _ = self.native_fns.fetchRemove(name);
        self.rebound_globals.put(name, {}) catch {};

        if (types.isPair(data.value)) {
            const head = types.car(data.value);
            if (types.isSymbol(head) and std.mem.eql(u8, types.symbolName(head), "lambda")) {
                const lambda_data = ir.LambdaData{ .args = types.cdr(data.value), .name = name };
                if (self.tryCompileLambdaNative(lambda_data) != null) {
                    _ = self.rebound_globals.fetchRemove(name);
                }
            }
        }

        const val = if (types.isPair(data.value))
            try self.emitEvalExpr(data.value)
        else if (types.isSymbol(data.value))
            try self.emitGlobalRef(data.value)
        else
            try self.emitConstant(data.value);

        try self.print("  call void @kaappi_define_global(ptr %vm, ptr {s}, i64 {d}, i64 {s})\n", .{ sym_name, name.len, val });

        return self.emitVoid();
    }

    const lambda = @import("llvm_emit_lambda.zig");

    fn emitLambda(self: *LLVMEmitter, data: ir.LambdaData) EmitError![]const u8 {
        return lambda.emitLambda(self, data);
    }

    pub fn tryCompileDefineFunction(self: *LLVMEmitter, name: []const u8, formals: Value, body: Value) ?[]const u8 {
        return lambda.tryCompileDefineFunction(self, name, formals, body);
    }

    fn tryCompileLambdaNative(self: *LLVMEmitter, data: ir.LambdaData) ?[]const u8 {
        return lambda.tryCompileLambdaNative(self, data);
    }

    fn tryEmitInlineBinary(self: *LLVMEmitter, name: []const u8, args: []const *ir.Node) ?[]const u8 {
        const fn_name: ?[]const u8 = if (std.mem.eql(u8, name, "+"))
            "@kaappi_fixnum_add"
        else if (std.mem.eql(u8, name, "-"))
            "@kaappi_fixnum_sub"
        else if (std.mem.eql(u8, name, "*"))
            "@kaappi_fixnum_mul"
        else if (std.mem.eql(u8, name, "<"))
            "@kaappi_fixnum_lt"
        else if (std.mem.eql(u8, name, "="))
            "@kaappi_fixnum_eq"
        else if (std.mem.eql(u8, name, "cons"))
            "@kaappi_cons"
        else
            null;

        const target = fn_name orelse return null;
        const a = self.emitNode(args[0]) catch return null;
        const b = self.emitNode(args[1]) catch return null;
        const result = self.freshTemp() catch return null;
        self.print("  {s} = call i64 {s}(i64 {s}, i64 {s})\n", .{ result, target, a, b }) catch return null;
        return result;
    }

    fn tryEmitInlineUnary(self: *LLVMEmitter, name: []const u8, arg: *const ir.Node) ?[]const u8 {
        const fn_name: ?[]const u8 = if (std.mem.eql(u8, name, "car"))
            "@kaappi_car"
        else if (std.mem.eql(u8, name, "cdr"))
            "@kaappi_cdr"
        else if (std.mem.eql(u8, name, "null?"))
            "@kaappi_is_null"
        else
            null;

        const target = fn_name orelse return null;
        const v = self.emitNode(arg) catch return null;
        const result = self.freshTemp() catch return null;
        self.print("  {s} = call i64 {s}(i64 {s})\n", .{ result, target, v }) catch return null;
        return result;
    }

    fn emitDirectCall(self: *LLVMEmitter, fn_name: []const u8, args: []const *ir.Node, is_tail: bool) EmitError![]const u8 {
        const nargs = args.len;
        var arg_tmps: [256][]const u8 = undefined;
        for (args, 0..) |arg, i| {
            arg_tmps[i] = try self.emitNode(arg);
        }

        const result = try self.freshTemp();

        if (nargs == 0) {
            const call_prefix: []const u8 = if (is_tail) "tail call" else "call";
            try self.print("  {s} = {s} i64 {s}(ptr %vm, ptr null, i64 0, ptr null)\n", .{ result, call_prefix, fn_name });
        } else {
            const args_alloca = try self.freshTemp();
            try self.print("  {s} = alloca [{d} x i64], align 8\n", .{ args_alloca, nargs });

            for (0..nargs) |i| {
                const gep = try self.freshTemp();
                try self.print("  {s} = getelementptr i64, ptr {s}, i64 {d}\n", .{ gep, args_alloca, i });
                try self.print("  store i64 {s}, ptr {s}\n", .{ arg_tmps[i], gep });
            }

            try self.print("  {s} = call i64 {s}(ptr %vm, ptr {s}, i64 {d}, ptr null)\n", .{ result, fn_name, args_alloca, nargs });
        }

        if (is_tail) {
            try self.print("  ret i64 {s}\n", .{result});
            const after_label = try std.fmt.allocPrint(self.allocator, "after_tail_{d}", .{self.label_counter});
            self.label_counter += 1;
            try self.print("{s}:\n", .{after_label});
            self.current_block = after_label;
        }

        return result;
    }

    fn emitEvalExpr(self: *LLVMEmitter, value: Value) EmitError![]const u8 {
        const source = printer.valueToString(self.allocator, value, .write) catch return error.OutOfMemory;
        defer self.allocator.free(source);
        const str_name = try self.internString(source);
        const tmp = try self.freshTemp();
        try self.print("  {s} = call i64 @kaappi_eval(ptr %vm, ptr {s}, i64 {d})\n", .{ tmp, str_name, source.len });
        return tmp;
    }

    fn emitQuotedEvalExpr(self: *LLVMEmitter, value: Value) EmitError![]const u8 {
        const printed = printer.valueToString(self.allocator, value, .write) catch return error.OutOfMemory;
        defer self.allocator.free(printed);
        const source = std.fmt.allocPrint(self.allocator, "(quote {s})", .{printed}) catch return error.OutOfMemory;
        defer self.allocator.free(source);
        const str_name = try self.internString(source);
        const tmp = try self.freshTemp();
        try self.print("  {s} = call i64 @kaappi_eval(ptr %vm, ptr {s}, i64 {d})\n", .{ tmp, str_name, source.len });
        return tmp;
    }

    pub fn internSymbol(self: *LLVMEmitter, name: []const u8) EmitError![]const u8 {
        if (!self.symbols.contains(name)) {
            const id = self.sym_counter;
            self.sym_counter += 1;
            self.symbols.put(name, id) catch return error.OutOfMemory;
        }
        const id = self.symbols.get(name).?;
        return std.fmt.allocPrint(self.allocator, "@.sym.{d}", .{id}) catch return error.OutOfMemory;
    }

    pub fn internString(self: *LLVMEmitter, data: []const u8) EmitError![]const u8 {
        const id = self.string_counter;
        self.string_counter += 1;
        const global_name = std.fmt.allocPrint(self.allocator, "@.str.{d}", .{id}) catch return error.OutOfMemory;

        var escaped: std.ArrayList(u8) = .empty;
        defer escaped.deinit(self.allocator);
        for (data) |byte| {
            if (byte >= 0x20 and byte < 0x7F and byte != '"' and byte != '\\') {
                escaped.append(self.allocator, byte) catch return error.OutOfMemory;
            } else {
                const hex = std.fmt.allocPrint(self.allocator, "\\{X:0>2}", .{byte}) catch return error.OutOfMemory;
                defer self.allocator.free(hex);
                escaped.appendSlice(self.allocator, hex) catch return error.OutOfMemory;
            }
        }

        const decl = std.fmt.allocPrint(self.allocator, "{s} = private unnamed_addr constant [{d} x i8] c\"{s}\"\n", .{ global_name, data.len, escaped.items }) catch return error.OutOfMemory;
        self.string_decls.append(self.allocator, decl) catch return error.OutOfMemory;

        return global_name;
    }

    fn emitPreamble(self: *LLVMEmitter) EmitError!void {
        const arch = @import("builtin").cpu.arch;
        const os = @import("builtin").os.tag;
        const triple = switch (arch) {
            .aarch64 => switch (os) {
                .macos => "aarch64-apple-macosx",
                .linux => "aarch64-unknown-linux-gnu",
                else => "aarch64-unknown-unknown",
            },
            .x86_64 => switch (os) {
                .macos => "x86_64-apple-macosx",
                .linux => "x86_64-unknown-linux-gnu",
                else => "x86_64-unknown-unknown",
            },
            else => "unknown-unknown-unknown",
        };

        try self.print("; Generated by Kaappi Scheme LLVM backend\ntarget triple = \"{s}\"\n\n", .{triple});
        try self.write("declare ptr @kaappi_runtime_init()\n");
        try self.write("declare void @kaappi_runtime_deinit(ptr)\n");
        try self.write("declare i64 @kaappi_global_lookup(ptr, ptr, i64)\n");
        try self.write("declare i64 @kaappi_call_scheme(ptr, i64, ptr, i64)\n");
        try self.write("declare void @kaappi_define_global(ptr, ptr, i64, i64)\n");
        try self.write("declare void @kaappi_set_global(ptr, ptr, i64, i64)\n");
        try self.write("declare i64 @kaappi_make_string(ptr, ptr, i64)\n");
        try self.write("declare i64 @kaappi_intern_symbol(ptr, ptr, i64)\n");
        try self.write("declare i64 @kaappi_fixnum_add(i64, i64)\n");
        try self.write("declare i64 @kaappi_fixnum_sub(i64, i64)\n");
        try self.write("declare i64 @kaappi_fixnum_mul(i64, i64)\n");
        try self.write("declare i64 @kaappi_fixnum_lt(i64, i64)\n");
        try self.write("declare i64 @kaappi_fixnum_eq(i64, i64)\n");
        try self.write("declare i64 @kaappi_car(i64)\n");
        try self.write("declare i64 @kaappi_cdr(i64)\n");
        try self.write("declare i64 @kaappi_cons(i64, i64)\n");
        try self.write("declare i64 @kaappi_is_null(i64)\n");
        try self.write("declare i64 @kaappi_create_native_closure(ptr, ptr, ptr, i64, i64, ptr, i64)\n");
        try self.write("declare i64 @kaappi_eval(ptr, ptr, i64)\n");
    }

    pub fn freshTemp(self: *LLVMEmitter) EmitError![]const u8 {
        const n = self.tmp_counter;
        self.tmp_counter += 1;
        const s = std.fmt.allocPrint(self.allocator, "%t{d}", .{n}) catch return error.OutOfMemory;
        return s;
    }

    pub fn write(self: *LLVMEmitter, s: []const u8) EmitError!void {
        self.buf.appendSlice(self.allocator, s) catch return error.OutOfMemory;
    }

    pub fn print(self: *LLVMEmitter, comptime fmt: []const u8, args: anytype) EmitError!void {
        const s = std.fmt.allocPrint(self.allocator, fmt, args) catch return error.OutOfMemory;
        defer self.allocator.free(s);
        try self.write(s);
    }

    pub fn toSlice(self: *LLVMEmitter) []const u8 {
        return self.buf.items;
    }
};

pub const EmitError = error{
    UnsupportedNodeType,
    OutOfMemory,
};
