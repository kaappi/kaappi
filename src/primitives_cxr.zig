const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;

pub fn registerCxr(vm: *vm_mod.VM) !void {
    // Three-level compositions (8 total)
    try primitives.reg(vm, "caaar", &caaarFn, .{ .exact = 1 });
    try primitives.reg(vm, "caadr", &caadrFn, .{ .exact = 1 });
    try primitives.reg(vm, "cadar", &cadarFn, .{ .exact = 1 });
    try primitives.reg(vm, "caddr", &caddrFn, .{ .exact = 1 });
    try primitives.reg(vm, "cdaar", &cdaarFn, .{ .exact = 1 });
    try primitives.reg(vm, "cdadr", &cdadrFn, .{ .exact = 1 });
    try primitives.reg(vm, "cddar", &cddarFn, .{ .exact = 1 });
    try primitives.reg(vm, "cdddr", &cdddrFn, .{ .exact = 1 });

    // Four-level compositions (16 total)
    try primitives.reg(vm, "caaaar", &caaaarFn, .{ .exact = 1 });
    try primitives.reg(vm, "caaadr", &caaadrFn, .{ .exact = 1 });
    try primitives.reg(vm, "caadar", &caadarFn, .{ .exact = 1 });
    try primitives.reg(vm, "caaddr", &caaddrFn, .{ .exact = 1 });
    try primitives.reg(vm, "cadaar", &cadaarFn, .{ .exact = 1 });
    try primitives.reg(vm, "cadadr", &cadadrFn, .{ .exact = 1 });
    try primitives.reg(vm, "caddar", &caddarFn, .{ .exact = 1 });
    try primitives.reg(vm, "cadddr", &cadddrFn, .{ .exact = 1 });
    try primitives.reg(vm, "cdaaar", &cdaaarFn, .{ .exact = 1 });
    try primitives.reg(vm, "cdaadr", &cdaadrFn, .{ .exact = 1 });
    try primitives.reg(vm, "cdadar", &cdadarFn, .{ .exact = 1 });
    try primitives.reg(vm, "cdaddr", &cdaddrFn, .{ .exact = 1 });
    try primitives.reg(vm, "cddaar", &cddaarFn, .{ .exact = 1 });
    try primitives.reg(vm, "cddadr", &cddadrFn, .{ .exact = 1 });
    try primitives.reg(vm, "cdddar", &cdddarFn, .{ .exact = 1 });
    try primitives.reg(vm, "cddddr", &cddddrFn, .{ .exact = 1 });
}

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
