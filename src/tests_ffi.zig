const std = @import("std");
const memory = @import("memory.zig");
const types = @import("types.zig");
const ffi = @import("ffi.zig");
const th = @import("testing_helpers.zig");

// A C-ABI function with a real `_Bool` parameter. In safe builds (the default)
// the Zig compiler inserts a check that traps if the incoming byte is not 0 or
// 1 — exactly like a `zig cc`-built library with UBSan trap mode. This lets the
// test reproduce the process abort from #796 without an external shared library:
// before the fix, a raw fixnum like 2 reached this `_Bool` parameter and aborted.
fn recvBool(b: bool) callconv(.c) c_int {
    return if (b) 1 else 0;
}

// Build a stack FfiFunction pointing at recvBool. `library` is #f (not an
// FfiLibrary) so callFfi skips the shared-library handle check. The header is
// never inspected because nothing calls toObject() on the FfiFunction itself.
fn makeBoolFn(ptypes: []types.FfiType, ret: types.FfiType) types.FfiFunction {
    return .{
        .header = undefined,
        .symbol = @ptrFromInt(@intFromPtr(&recvBool)),
        .library = types.FALSE,
        .name = "recv_bool",
        .param_types = ptypes,
        .return_type = ret,
        .param_count = 1,
    };
}

test "ffi bool arg: non-0/1 integers coerced to 0/1, never trap (#796)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var ptypes = [_]types.FfiType{.bool_type};
    var fn_int = makeBoolFn(ptypes[0..], .int);

    // 2 must be coerced to 1 before reaching the _Bool parameter — passing it
    // through raw aborts the process under the safety check. Before the fix
    // this returned 2 (or trapped); the raw integer must never reach _Bool.
    const r2 = try ffi.callFfi(&fn_int, &.{types.makeFixnum(2)}, &ctx.gc, &ctx.vm);
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(r2));

    // Any nonzero value is true (C truthiness); zero is false.
    const rneg = try ffi.callFfi(&fn_int, &.{types.makeFixnum(-5)}, &ctx.gc, &ctx.vm);
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(rneg));

    const r0 = try ffi.callFfi(&fn_int, &.{types.makeFixnum(0)}, &ctx.gc, &ctx.vm);
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(r0));

    // #t / #f keep working as before (#418).
    const rt = try ffi.callFfi(&fn_int, &.{types.TRUE}, &ctx.gc, &ctx.vm);
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(rt));

    const rf = try ffi.callFfi(&fn_int, &.{types.FALSE}, &ctx.gc, &ctx.vm);
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(rf));
}

test "ffi bool arg: bignum coerced to 0/1 (#796)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var ptypes = [_]types.FfiType{.bool_type};
    var fn_int = makeBoolFn(ptypes[0..], .int);

    // A value too large for a fixnum arrives as a bignum; it is still just a
    // truthy value for a bool parameter and must coerce to 1.
    const big = try ctx.gc.allocBignumFromI64(0x1_0000_0000_0000);
    const rbig = try ffi.callFfi(&fn_int, &.{big}, &ctx.gc, &ctx.vm);
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(rbig));
}

test "ffi bool arg with bool return normalizes both directions (#796)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var ptypes = [_]types.FfiType{.bool_type};
    var fn_bool = makeBoolFn(ptypes[0..], .bool_type);

    try std.testing.expectEqual(types.TRUE, try ffi.callFfi(&fn_bool, &.{types.makeFixnum(2)}, &ctx.gc, &ctx.vm));
    try std.testing.expectEqual(types.FALSE, try ffi.callFfi(&fn_bool, &.{types.makeFixnum(0)}, &ctx.gc, &ctx.vm));
    try std.testing.expectEqual(types.TRUE, try ffi.callFfi(&fn_bool, &.{types.TRUE}, &ctx.gc, &ctx.vm));
    try std.testing.expectEqual(types.FALSE, try ffi.callFfi(&fn_bool, &.{types.FALSE}, &ctx.gc, &ctx.vm));
}
