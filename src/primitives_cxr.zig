const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

const cxr_libs = LS.initMany(&.{ .scheme_cxr, .scheme_r5rs });

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "caaar", .func = &caaarFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "caadr", .func = &caadrFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "cadar", .func = &cadarFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "caddr", .func = &caddrFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "cdaar", .func = &cdaarFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "cdadr", .func = &cdadrFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "cddar", .func = &cddarFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "cdddr", .func = &cdddrFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "caaaar", .func = &caaaarFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "caaadr", .func = &caaadrFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "caadar", .func = &caadarFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "caaddr", .func = &caaddrFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "cadaar", .func = &cadaarFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "cadadr", .func = &cadadrFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "caddar", .func = &caddarFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "cadddr", .func = &cadddrFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "cdaaar", .func = &cdaaarFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "cdaadr", .func = &cdaadrFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "cdadar", .func = &cdadarFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "cdaddr", .func = &cdaddrFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "cddaar", .func = &cddaarFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "cddadr", .func = &cddadrFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "cdddar", .func = &cdddarFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
    .{ .name = "cddddr", .func = &cddddrFn, .arity = .{ .exact = 1 }, .libs = cxr_libs },
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn docar(v: Value) PrimitiveError!Value {
    if (!types.isPair(v)) return primitives.typeError("car", "pair", v);
    return types.car(v);
}

fn docdr(v: Value) PrimitiveError!Value {
    if (!types.isPair(v)) return primitives.typeError("cdr", "pair", v);
    return types.cdr(v);
}

// ---------------------------------------------------------------------------
// Three-level compositions
// ---------------------------------------------------------------------------

fn caaarFn(args: []const Value) PrimitiveError!Value {
    return docar(try docar(try docar(args[0])));
}

fn caadrFn(args: []const Value) PrimitiveError!Value {
    return docar(try docar(try docdr(args[0])));
}

fn cadarFn(args: []const Value) PrimitiveError!Value {
    return docar(try docdr(try docar(args[0])));
}

fn caddrFn(args: []const Value) PrimitiveError!Value {
    return docar(try docdr(try docdr(args[0])));
}

fn cdaarFn(args: []const Value) PrimitiveError!Value {
    return docdr(try docar(try docar(args[0])));
}

fn cdadrFn(args: []const Value) PrimitiveError!Value {
    return docdr(try docar(try docdr(args[0])));
}

fn cddarFn(args: []const Value) PrimitiveError!Value {
    return docdr(try docdr(try docar(args[0])));
}

fn cdddrFn(args: []const Value) PrimitiveError!Value {
    return docdr(try docdr(try docdr(args[0])));
}

// ---------------------------------------------------------------------------
// Four-level compositions
// ---------------------------------------------------------------------------

fn caaaarFn(args: []const Value) PrimitiveError!Value {
    return docar(try docar(try docar(try docar(args[0]))));
}

fn caaadrFn(args: []const Value) PrimitiveError!Value {
    return docar(try docar(try docar(try docdr(args[0]))));
}

fn caadarFn(args: []const Value) PrimitiveError!Value {
    return docar(try docar(try docdr(try docar(args[0]))));
}

fn caaddrFn(args: []const Value) PrimitiveError!Value {
    return docar(try docar(try docdr(try docdr(args[0]))));
}

fn cadaarFn(args: []const Value) PrimitiveError!Value {
    return docar(try docdr(try docar(try docar(args[0]))));
}

fn cadadrFn(args: []const Value) PrimitiveError!Value {
    return docar(try docdr(try docar(try docdr(args[0]))));
}

fn caddarFn(args: []const Value) PrimitiveError!Value {
    return docar(try docdr(try docdr(try docar(args[0]))));
}

fn cadddrFn(args: []const Value) PrimitiveError!Value {
    return docar(try docdr(try docdr(try docdr(args[0]))));
}

fn cdaaarFn(args: []const Value) PrimitiveError!Value {
    return docdr(try docar(try docar(try docar(args[0]))));
}

fn cdaadrFn(args: []const Value) PrimitiveError!Value {
    return docdr(try docar(try docar(try docdr(args[0]))));
}

fn cdadarFn(args: []const Value) PrimitiveError!Value {
    return docdr(try docar(try docdr(try docar(args[0]))));
}

fn cdaddrFn(args: []const Value) PrimitiveError!Value {
    return docdr(try docar(try docdr(try docdr(args[0]))));
}

fn cddaarFn(args: []const Value) PrimitiveError!Value {
    return docdr(try docdr(try docar(try docar(args[0]))));
}

fn cddadrFn(args: []const Value) PrimitiveError!Value {
    return docdr(try docdr(try docar(try docdr(args[0]))));
}

fn cdddarFn(args: []const Value) PrimitiveError!Value {
    return docdr(try docdr(try docdr(try docar(args[0]))));
}

fn cddddrFn(args: []const Value) PrimitiveError!Value {
    return docdr(try docdr(try docdr(try docdr(args[0]))));
}
