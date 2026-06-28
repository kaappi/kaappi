const std = @import("std");
const ir = @import("ir.zig");
const types = @import("types.zig");
const printer = @import("printer.zig");

const Value = types.Value;

const NativeLambda = struct {
    llvm_name: []const u8,
    arity: u8,
};

pub const LLVMEmitter = struct {
    buf: std.ArrayList(u8),
    symbols: std.StringHashMap(u32),
    string_decls: std.ArrayList([]const u8),
    lambda_defs: std.ArrayList([]const u8),
    native_fns: std.StringHashMap(NativeLambda),
    params: ?std.StringHashMap(u8),
    upvalues: ?std.StringHashMap(u8),
    tmp_counter: u32,
    label_counter: u32,
    string_counter: u32,
    sym_counter: u32,
    lambda_counter: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) LLVMEmitter {
        return .{
            .buf = .empty,
            .symbols = std.StringHashMap(u32).init(allocator),
            .string_decls = .empty,
            .lambda_defs = .empty,
            .native_fns = std.StringHashMap(NativeLambda).init(allocator),
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
            try self.print("@.sym.{d} = private unnamed_addr constant [{d} x i8] c\"{s}\"\n", .{ id, name.len, name });
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

    fn emitNode(self: *LLVMEmitter, node: *const ir.Node) EmitError![]const u8 {
        return switch (node.tag) {
            .constant => try self.emitConstant(node.data.constant),
            .global_ref => try self.emitGlobalRef(node.data.global_ref),
            .call => try self.emitCall(node.data.call),
            .begin => try self.emitBegin(node.data.begin),
            .@"if" => try self.emitIf(node.data.@"if"),
            .and_form => try self.emitAnd(node.data.and_form),
            .or_form => try self.emitOr(node.data.or_form),
            .when_form => try self.emitWhen(node.data.when_form),
            .unless_form => try self.emitUnless(node.data.unless_form),
            .define => try self.emitDefine(node.data.define),
            .set_form => try self.emitSet(node.data.set_form),
            .lambda => try self.emitLambda(node.data.lambda),
            .let_form, .let_star, .letrec, .letrec_star, .named_let => try self.emitSexprEval(node),
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

    fn emitGlobalRef(self: *LLVMEmitter, sym: Value) EmitError![]const u8 {
        if (!types.isSymbol(sym)) return error.UnsupportedNodeType;
        const name = types.symbolName(sym);

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

    fn emitCall(self: *LLVMEmitter, call: ir.CallData) EmitError![]const u8 {
        if (call.operator.tag == .global_ref and types.isSymbol(call.operator.data.global_ref)) {
            const op_name = types.symbolName(call.operator.data.global_ref);
            if (self.native_fns.get(op_name)) |native| {
                return self.emitDirectCall(native.llvm_name, call.args);
            }
            if (call.args.len == 2) {
                if (self.tryEmitInlineBinary(op_name, call.args)) |result| return result;
            }
            if (call.args.len == 1) {
                if (self.tryEmitInlineUnary(op_name, call.args[0])) |result| return result;
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
            try self.print("  {s} = call i64 @kaappi_call_scheme(ptr %vm, i64 {s}, ptr null, i64 0)\n", .{ result, callee });
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

        return result;
    }

    fn emitBegin(self: *LLVMEmitter, exprs: []const *ir.Node) EmitError![]const u8 {
        var last: []const u8 = "";
        for (exprs) |expr| {
            last = try self.emitNode(expr);
        }
        return last;
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

        if (data.alternate != null) {
            try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cmp, then_label, else_label });
        } else {
            try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cmp, then_label, merge_label });
        }

        try self.print("{s}:\n", .{then_label});
        const then_val = try self.emitNode(data.consequent);
        try self.print("  br label %{s}\n", .{merge_label});

        if (data.alternate) |alt| {
            try self.print("{s}:\n", .{else_label});
            const else_val = try self.emitNode(alt);
            try self.print("  br label %{s}\n", .{merge_label});

            try self.print("{s}:\n", .{merge_label});
            const result = try self.freshTemp();
            try self.print("  {s} = phi i64 [ {s}, %{s} ], [ {s}, %{s} ]\n", .{ result, then_val, then_label, else_val, else_label });
            return result;
        } else {
            const void_val: i64 = @bitCast(types.VOID);
            try self.print("{s}:\n", .{merge_label});
            const result = try self.freshTemp();
            try self.print("  {s} = phi i64 [ {s}, %{s} ], [ {d}, %{s} ]\n", .{ result, then_val, then_label, void_val, pre_label });
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

        var last: []const u8 = "";
        for (data.body) |expr| {
            last = try self.emitNode(expr);
        }
        try self.print("  br label %{s}\n", .{merge_label});
        try self.print("{s}:\n", .{merge_label});

        const void_val: i64 = @bitCast(types.VOID);
        const result = try self.freshTemp();
        try self.print("  {s} = phi i64 [ {s}, %{s} ], [ {d}, %{s} ]\n", .{ result, last, body_label, void_val, pre_label });
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

        var last: []const u8 = "";
        for (data.body) |expr| {
            last = try self.emitNode(expr);
        }
        try self.print("  br label %{s}\n", .{merge_label});
        try self.print("{s}:\n", .{merge_label});

        const void_val: i64 = @bitCast(types.VOID);
        const result = try self.freshTemp();
        try self.print("  {s} = phi i64 [ {s}, %{s} ], [ {d}, %{s} ]\n", .{ result, last, body_label, void_val, pre_label });
        return result;
    }

    fn emitSet(self: *LLVMEmitter, data: ir.SetData) EmitError![]const u8 {
        if (!types.isSymbol(data.name)) return error.UnsupportedNodeType;
        const name = types.symbolName(data.name);
        const sym_name = try self.internSymbol(name);

        const val = if (types.isPair(data.value))
            try self.emitEvalExpr(data.value)
        else
            try self.emitConstant(data.value);

        try self.print("  call void @kaappi_define_global(ptr %vm, ptr {s}, i64 {d}, i64 {s})\n", .{ sym_name, name.len, val });

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

        try self.bindParamsAsGlobals();

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
                        if (self.tryCompileDefineFunction(fn_name, formals, body)) |native_fn_name| {
                            self.native_fns.put(fn_name, .{ .llvm_name = native_fn_name, .arity = 0 }) catch {};
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
        const sym_name = try self.internSymbol(name);

        if (types.isPair(data.value)) {
            const head = types.car(data.value);
            if (types.isSymbol(head) and std.mem.eql(u8, types.symbolName(head), "lambda")) {
                const lambda_data = ir.LambdaData{ .args = types.cdr(data.value), .name = name };
                if (self.tryCompileLambdaNative(lambda_data)) |fn_name| {
                    self.native_fns.put(name, .{ .llvm_name = fn_name, .arity = 0 }) catch {};
                }
            }
        }

        const val = if (types.isPair(data.value))
            try self.emitEvalExpr(data.value)
        else
            try self.emitConstant(data.value);

        try self.print("  call void @kaappi_define_global(ptr %vm, ptr {s}, i64 {d}, i64 {s})\n", .{ sym_name, name.len, val });

        const result = try self.freshTemp();
        const void_val: i64 = @bitCast(types.VOID);
        try self.print("  {s} = add i64 0, {d}\n", .{ result, void_val });
        return result;
    }

    fn emitLambda(self: *LLVMEmitter, data: ir.LambdaData) EmitError![]const u8 {
        if (self.params != null) {
            if (self.tryCompileNativeClosure(data)) |result| return result;
        }
        return self.emitLambdaViaEval(data);
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
        self.buf = fn_buf;
        self.tmp_counter = 0;
        self.label_counter = 0;

        var p = std.StringHashMap(u8).init(self.allocator);
        for (param_names[0..arity], 0..) |pname, i| {
            p.put(pname, @intCast(i)) catch {
                self.buf = saved_buf;
                self.params = saved_params;
                self.tmp_counter = saved_tmp;
                self.label_counter = saved_label;
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

    fn bindParamsAsGlobals(self: *LLVMEmitter) EmitError!void {
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
        try self.bindParamsAsGlobals();

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

    fn tryCompileLambdaNative(self: *LLVMEmitter, data: ir.LambdaData) ?[]const u8 {
        const formals = types.car(data.args);
        const body_list = types.cdr(data.args);
        if (body_list == types.NIL) return null;
        if (!types.isPair(formals) and formals != types.NIL) return null;
        return self.tryCompileDefineFunction(data.name orelse "(lambda)", formals, body_list);
    }

    fn tryCompileDefineFunction(self: *LLVMEmitter, name: []const u8, formals: Value, body: Value) ?[]const u8 {
        if (body == types.NIL) return null;

        var param_names: [16][]const u8 = undefined;
        var arity: u8 = 0;
        var param_list = formals;
        while (param_list != types.NIL) {
            if (!types.isPair(param_list)) return null;
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

        var allowed: [17][]const u8 = undefined;
        @memcpy(allowed[0..arity], param_names[0..arity]);
        allowed[arity] = name;
        if (hasFreeVars(body_nodes[0..body_count], allowed[0 .. arity + 1])) return null;

        return self.emitLambdaFunction(name, param_names[0..arity], body_nodes[0..body_count]);
    }

    fn emitLambdaFunction(self: *LLVMEmitter, name: ?[]const u8, param_names: []const []const u8, body_nodes: []const *ir.Node) ?[]const u8 {
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
        self.buf = fn_buf;
        self.tmp_counter = 0;
        self.label_counter = 0;

        var p = std.StringHashMap(u8).init(self.allocator);
        for (param_names, 0..) |pname, i| {
            p.put(pname, @intCast(i)) catch {
                self.buf = saved_buf;
                self.params = saved_params;
                self.tmp_counter = saved_tmp;
                self.label_counter = saved_label;
                return null;
            };
        }
        self.params = p;

        const header = std.fmt.allocPrint(self.allocator, "; {s}\ndefine i64 {s}(ptr %vm, ptr %args, i64 %nargs) {{\nentry:\n", .{ name orelse "(lambda)", fn_name }) catch {
            self.buf = saved_buf;
            self.params = saved_params;
            self.tmp_counter = saved_tmp;
            self.label_counter = saved_label;
            p.deinit();
            return null;
        };
        defer self.allocator.free(header);
        self.write(header) catch {
            self.buf = saved_buf;
            self.params = saved_params;
            self.tmp_counter = saved_tmp;
            self.label_counter = saved_label;
            p.deinit();
            return null;
        };

        var last_val: []const u8 = "";
        for (body_nodes) |node| {
            last_val = self.emitNode(node) catch {
                self.buf = saved_buf;
                self.params = saved_params;
                self.tmp_counter = saved_tmp;
                self.label_counter = saved_label;
                p.deinit();
                fn_buf.deinit(self.allocator);
                return null;
            };
        }

        self.print("  ret i64 {s}\n}}\n", .{last_val}) catch {
            self.buf = saved_buf;
            self.params = saved_params;
            self.tmp_counter = saved_tmp;
            self.label_counter = saved_label;
            p.deinit();
            fn_buf.deinit(self.allocator);
            return null;
        };

        fn_buf = self.buf;
        self.buf = saved_buf;
        self.params = saved_params;
        self.tmp_counter = saved_tmp;
        self.label_counter = saved_label;
        p.deinit();

        const fn_def = fn_buf.toOwnedSlice(self.allocator) catch return null;
        self.lambda_defs.append(self.allocator, fn_def) catch return null;

        return fn_name;
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

    fn emitDirectCall(self: *LLVMEmitter, fn_name: []const u8, args: []const *ir.Node) EmitError![]const u8 {
        const nargs = args.len;
        var arg_tmps: [256][]const u8 = undefined;
        for (args, 0..) |arg, i| {
            arg_tmps[i] = try self.emitNode(arg);
        }

        const result = try self.freshTemp();

        if (nargs == 0) {
            try self.print("  {s} = call i64 {s}(ptr %vm, ptr null, i64 0)\n", .{ result, fn_name });
        } else {
            const args_alloca = try self.freshTemp();
            try self.print("  {s} = alloca [{d} x i64], align 8\n", .{ args_alloca, nargs });

            for (0..nargs) |i| {
                const gep = try self.freshTemp();
                try self.print("  {s} = getelementptr i64, ptr {s}, i64 {d}\n", .{ gep, args_alloca, i });
                try self.print("  store i64 {s}, ptr {s}\n", .{ arg_tmps[i], gep });
            }

            try self.print("  {s} = call i64 {s}(ptr %vm, ptr {s}, i64 {d})\n", .{ result, fn_name, args_alloca, nargs });
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

    fn internSymbol(self: *LLVMEmitter, name: []const u8) EmitError![]const u8 {
        if (!self.symbols.contains(name)) {
            const id = self.sym_counter;
            self.sym_counter += 1;
            self.symbols.put(name, id) catch return error.OutOfMemory;
        }
        const id = self.symbols.get(name).?;
        return std.fmt.allocPrint(self.allocator, "@.sym.{d}", .{id}) catch return error.OutOfMemory;
    }

    fn internString(self: *LLVMEmitter, data: []const u8) EmitError![]const u8 {
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

    fn freshTemp(self: *LLVMEmitter) EmitError![]const u8 {
        const n = self.tmp_counter;
        self.tmp_counter += 1;
        const s = std.fmt.allocPrint(self.allocator, "%t{d}", .{n}) catch return error.OutOfMemory;
        return s;
    }

    fn write(self: *LLVMEmitter, s: []const u8) EmitError!void {
        self.buf.appendSlice(self.allocator, s) catch return error.OutOfMemory;
    }

    fn print(self: *LLVMEmitter, comptime fmt: []const u8, args: anytype) EmitError!void {
        const s = std.fmt.allocPrint(self.allocator, fmt, args) catch return error.OutOfMemory;
        defer self.allocator.free(s);
        try self.write(s);
    }

    pub fn toSlice(self: *LLVMEmitter) []const u8 {
        return self.buf.items;
    }
};

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

pub const EmitError = error{
    UnsupportedNodeType,
    OutOfMemory,
};
