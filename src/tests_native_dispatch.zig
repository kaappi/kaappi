const std = @import("std");
const types = @import("types.zig");
const th = @import("testing_helpers.zig");
const Value = types.Value;

// -- NativeClosure dispatch tests (#1376) --
// Since #1374 map/for-each/dynamic-wind/force are bytecode closures
// (vm_bootstrap.zig), so bytecode must be able to invoke natively-compiled
// callbacks (NativeClosure) from every call path in the dispatch loop.
// These build a NativeClosure by hand (as kaappi_create_native_closure
// would) and drive it through each opcode/helper.

fn ncDouble(_: ?*th.VM, args: [*]const Value, nargs: u64, _: [*]const Value) callconv(.c) u64 {
    std.debug.assert(nargs == 1);
    return types.makeFixnum(types.toFixnum(args[0]) * 2);
}

fn ncAddUpvalue(_: ?*th.VM, args: [*]const Value, nargs: u64, upvalues: [*]const Value) callconv(.c) u64 {
    std.debug.assert(nargs == 1);
    return types.makeFixnum(types.toFixnum(args[0]) + types.toFixnum(upvalues[0]));
}

fn ncFortyTwo(_: ?*th.VM, _: [*]const Value, _: u64, _: [*]const Value) callconv(.c) u64 {
    return types.makeFixnum(42);
}

fn ncIgnoreArg(_: ?*th.VM, _: [*]const Value, nargs: u64, _: [*]const Value) callconv(.c) u64 {
    std.debug.assert(nargs == 1);
    return types.makeFixnum(7);
}

fn setupNativeClosures(ctx: *th.TestContext) !void {
    try ctx.vm.defineGlobal("nc-double", try ctx.gc.allocNativeClosure(&ncDouble, &.{}, 1, "nc-double"));
    try ctx.vm.defineGlobal("nc-42", try ctx.gc.allocNativeClosure(&ncFortyTwo, &.{}, 0, "nc-42"));
    try ctx.vm.defineGlobal("nc-ignore", try ctx.gc.allocNativeClosure(&ncIgnoreArg, &.{}, 1, "nc-ignore"));
}

test "bootstrapped map calls a NativeClosure callback (call opcode)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try setupNativeClosures(&ctx);
    const result = try ctx.vm.eval("(equal? (map nc-double (list 1 2 3)) (list 2 4 6))");
    try std.testing.expectEqual(types.TRUE, result);
}

test "bootstrapped dynamic-wind calls NativeClosure thunks" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try setupNativeClosures(&ctx);
    const result = try ctx.vm.eval("(dynamic-wind nc-42 nc-42 nc-42)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "NativeClosure upvalues survive the dispatch-loop call path" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const upvals = [_]Value{types.makeFixnum(100)};
    try ctx.vm.defineGlobal("nc-add100", try ctx.gc.allocNativeClosure(&ncAddUpvalue, &upvals, 1, "nc-add100"));
    const result = try ctx.vm.eval("(equal? (map nc-add100 (list 1 2)) (list 101 102))");
    try std.testing.expectEqual(types.TRUE, result);
}

test "bytecode tail-calls a NativeClosure (tail_call opcode)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try setupNativeClosures(&ctx);
    const result = try ctx.vm.eval("((lambda (f) (f 21)) nc-double)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "bytecode tail-applies a NativeClosure (tail_apply opcode)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try setupNativeClosures(&ctx);
    const result = try ctx.vm.eval("((lambda (f) (apply f (list 21))) nc-double)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "bytecode tail-calls a NativeClosure global (tail_call_global opcode)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try setupNativeClosures(&ctx);
    const result = try ctx.vm.eval("((lambda () (nc-double 21)))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "call/cc with a NativeClosure receiver (callHandler / tail_call_cc)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try setupNativeClosures(&ctx);
    const non_tail = try ctx.vm.eval("(+ 0 (call-with-current-continuation nc-ignore))");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(non_tail));
    const tail = try ctx.vm.eval("((lambda () (call-with-current-continuation nc-ignore)))");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(tail));
}

test "with-exception-handler NativeClosure thunk and handler (callThunk/callHandler)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try setupNativeClosures(&ctx);
    const thunk_res = try ctx.vm.eval("(with-exception-handler (lambda (e) 0) nc-42)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(thunk_res));
    const handler_res = try ctx.vm.eval("(with-exception-handler nc-ignore (lambda () (raise-continuable 1)))");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(handler_res));
}

test "NativeClosure arity mismatch raises a catchable error" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try setupNativeClosures(&ctx);
    const result = try ctx.vm.eval("(guard (e (#t 99)) (nc-double 1 2))");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}
