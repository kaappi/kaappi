const std = @import("std");
const ir = @import("ir.zig");
const types = @import("types.zig");
const printer = @import("printer.zig");

const Value = types.Value;

pub const LLVMEmitter = struct {
    buf: std.ArrayList(u8),
    symbols: std.StringHashMap(u32),
    string_decls: std.ArrayList([]const u8),
    tmp_counter: u32,
    label_counter: u32,
    string_counter: u32,
    sym_counter: u32,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) LLVMEmitter {
        return .{
            .buf = .empty,
            .symbols = std.StringHashMap(u32).init(allocator),
            .string_decls = .empty,
            .tmp_counter = 0,
            .label_counter = 0,
            .string_counter = 0,
            .sym_counter = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LLVMEmitter) void {
        self.buf.deinit(self.allocator);
        self.symbols.deinit();
        self.string_decls.deinit(self.allocator);
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
            .passthrough => try self.emitEvalExpr(node.data.passthrough),
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
            return self.emitEvalExpr(value);
        }
        const tmp = try self.freshTemp();
        const signed: i64 = @bitCast(value);
        try self.print("  {s} = add i64 0, {d}\n", .{ tmp, signed });
        return tmp;
    }

    fn emitGlobalRef(self: *LLVMEmitter, sym: Value) EmitError![]const u8 {
        if (!types.isSymbol(sym)) return error.UnsupportedNodeType;
        const name = types.symbolName(sym);
        const sym_name = try self.internSymbol(name);
        const tmp = try self.freshTemp();
        try self.print("  {s} = call i64 @kaappi_global_lookup(ptr %vm, ptr {s}, i64 {d})\n", .{ tmp, sym_name, name.len });
        return tmp;
    }

    fn emitCall(self: *LLVMEmitter, call: ir.CallData) EmitError![]const u8 {
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

    fn emitDefine(self: *LLVMEmitter, data: ir.DefineData) EmitError![]const u8 {
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

    fn emitLambda(self: *LLVMEmitter, data: ir.LambdaData) EmitError![]const u8 {
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

    fn emitEvalExpr(self: *LLVMEmitter, value: Value) EmitError![]const u8 {
        const source = printer.valueToString(self.allocator, value, .write) catch return error.OutOfMemory;
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

pub const EmitError = error{
    UnsupportedNodeType,
    OutOfMemory,
};
