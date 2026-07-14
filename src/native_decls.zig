const std = @import("std");

pub const LLVMType = enum {
    ptr,
    i64,
    void_ty,

    pub fn toLLVM(self: LLVMType) []const u8 {
        return switch (self) {
            .ptr => "ptr",
            .i64 => "i64",
            .void_ty => "void",
        };
    }
};

pub const InlineKind = enum { not_inlined, unary, binary };

pub const Decl = struct {
    export_name: []const u8,
    scheme_name: ?[]const u8,
    param_types: []const LLVMType,
    ret: LLVMType,
    inline_kind: InlineKind,
};

pub const decls: []const Decl = &.{
    .{ .export_name = "kaappi_runtime_init", .scheme_name = null, .param_types = &.{}, .ret = .ptr, .inline_kind = .not_inlined },
    .{ .export_name = "kaappi_runtime_deinit", .scheme_name = null, .param_types = &.{.ptr}, .ret = .void_ty, .inline_kind = .not_inlined },
    .{ .export_name = "kaappi_global_lookup", .scheme_name = null, .param_types = &.{ .ptr, .ptr, .i64 }, .ret = .i64, .inline_kind = .not_inlined },
    .{ .export_name = "kaappi_call_scheme", .scheme_name = null, .param_types = &.{ .ptr, .i64, .ptr, .i64 }, .ret = .i64, .inline_kind = .not_inlined },
    .{ .export_name = "kaappi_define_global", .scheme_name = null, .param_types = &.{ .ptr, .ptr, .i64, .i64 }, .ret = .void_ty, .inline_kind = .not_inlined },
    .{ .export_name = "kaappi_set_global", .scheme_name = null, .param_types = &.{ .ptr, .ptr, .i64, .i64 }, .ret = .void_ty, .inline_kind = .not_inlined },
    .{ .export_name = "kaappi_make_string", .scheme_name = null, .param_types = &.{ .ptr, .ptr, .i64 }, .ret = .i64, .inline_kind = .not_inlined },
    .{ .export_name = "kaappi_intern_symbol", .scheme_name = null, .param_types = &.{ .ptr, .ptr, .i64 }, .ret = .i64, .inline_kind = .not_inlined },
    .{ .export_name = "kaappi_fixnum_add", .scheme_name = "+", .param_types = &.{ .i64, .i64 }, .ret = .i64, .inline_kind = .binary },
    .{ .export_name = "kaappi_fixnum_sub", .scheme_name = "-", .param_types = &.{ .i64, .i64 }, .ret = .i64, .inline_kind = .binary },
    .{ .export_name = "kaappi_fixnum_mul", .scheme_name = "*", .param_types = &.{ .i64, .i64 }, .ret = .i64, .inline_kind = .binary },
    .{ .export_name = "kaappi_fixnum_lt", .scheme_name = "<", .param_types = &.{ .i64, .i64 }, .ret = .i64, .inline_kind = .binary },
    .{ .export_name = "kaappi_fixnum_eq", .scheme_name = "=", .param_types = &.{ .i64, .i64 }, .ret = .i64, .inline_kind = .binary },
    .{ .export_name = "kaappi_car", .scheme_name = "car", .param_types = &.{.i64}, .ret = .i64, .inline_kind = .unary },
    .{ .export_name = "kaappi_cdr", .scheme_name = "cdr", .param_types = &.{.i64}, .ret = .i64, .inline_kind = .unary },
    .{ .export_name = "kaappi_cons", .scheme_name = "cons", .param_types = &.{ .i64, .i64 }, .ret = .i64, .inline_kind = .binary },
    .{ .export_name = "kaappi_is_null", .scheme_name = "null?", .param_types = &.{.i64}, .ret = .i64, .inline_kind = .unary },
    // Boxed mutable captures (#1497). Emitted directly by the closure tiers,
    // never resolved as Scheme globals, so scheme_name stays null.
    .{ .export_name = "kaappi_make_box", .scheme_name = null, .param_types = &.{ .ptr, .i64 }, .ret = .i64, .inline_kind = .not_inlined },
    .{ .export_name = "kaappi_box_ref", .scheme_name = null, .param_types = &.{.i64}, .ret = .i64, .inline_kind = .not_inlined },
    .{ .export_name = "kaappi_box_set", .scheme_name = null, .param_types = &.{ .i64, .i64 }, .ret = .void_ty, .inline_kind = .not_inlined },
    .{ .export_name = "kaappi_create_native_closure", .scheme_name = null, .param_types = &.{ .ptr, .ptr, .ptr, .i64, .i64, .ptr, .i64 }, .ret = .i64, .inline_kind = .not_inlined },
    .{ .export_name = "kaappi_eval", .scheme_name = null, .param_types = &.{ .ptr, .ptr, .i64 }, .ret = .i64, .inline_kind = .not_inlined },
    .{ .export_name = "kaappi_gc_push_root", .scheme_name = null, .param_types = &.{.ptr}, .ret = .void_ty, .inline_kind = .not_inlined },
    .{ .export_name = "kaappi_gc_pop_roots", .scheme_name = null, .param_types = &.{.i64}, .ret = .void_ty, .inline_kind = .not_inlined },
};

pub fn findInline(kind: InlineKind, scheme_name: []const u8) ?[]const u8 {
    for (decls) |d| {
        if (d.inline_kind == kind) {
            if (d.scheme_name) |sn| {
                if (std.mem.eql(u8, sn, scheme_name))
                    return d.export_name;
            }
        }
    }
    return null;
}

fn zigTypeToLLVM(comptime T: type) LLVMType {
    if (T == void) return .void_ty;
    if (T == u64) return .i64;
    return switch (@typeInfo(T)) {
        .pointer => .ptr,
        .optional => |opt| switch (@typeInfo(opt.child)) {
            .pointer => .ptr,
            else => @compileError("unsupported optional type in native export"),
        },
        else => @compileError("unsupported type in native export: " ++ @typeName(T)),
    };
}

comptime {
    const re = @import("runtime_exports.zig");
    for (decls) |d| {
        const info = @typeInfo(@TypeOf(@field(re, d.export_name))).@"fn";
        if (info.params.len != d.param_types.len)
            @compileError("parameter count mismatch for " ++ d.export_name);
        for (info.params, 0..) |param, i| {
            if (zigTypeToLLVM(param.type.?) != d.param_types[i])
                @compileError("parameter type mismatch for " ++ d.export_name);
        }
        if (zigTypeToLLVM(info.return_type.?) != d.ret)
            @compileError("return type mismatch for " ++ d.export_name);
    }
}
