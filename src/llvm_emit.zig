const std = @import("std");
const ir = @import("ir.zig");
const types = @import("types.zig");

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
            .define => try self.emitDefine(node.data.define),
            .passthrough => return error.UnsupportedNodeType,
            else => error.UnsupportedNodeType,
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

    fn emitDefine(self: *LLVMEmitter, data: ir.DefineData) EmitError![]const u8 {
        if (!types.isSymbol(data.name)) return error.UnsupportedNodeType;
        const name = types.symbolName(data.name);
        const sym_name = try self.internSymbol(name);

        // DefineData.value is a raw S-expression Value, not an IR node.
        // Handle literal constants directly.
        const val = try self.emitConstant(data.value);

        try self.print("  call void @kaappi_define_global(ptr %vm, ptr {s}, i64 {d}, i64 {s})\n", .{ sym_name, name.len, val });

        const result = try self.freshTemp();
        const void_val: i64 = @bitCast(types.VOID);
        try self.print("  {s} = add i64 0, {d}\n", .{ result, void_val });
        return result;
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
