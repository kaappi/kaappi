const std = @import("std");
const memory = @import("memory.zig");
const types = @import("types.zig");
const ffi = @import("ffi.zig");
const platform = @import("platform.zig");
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
    const r2 = try ffi.callFfi(&fn_int, &.{types.makeFixnum(2)}, &ctx.gc, ctx.vm);
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(r2));

    // Any nonzero value is true (C truthiness); zero is false.
    const rneg = try ffi.callFfi(&fn_int, &.{types.makeFixnum(-5)}, &ctx.gc, ctx.vm);
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(rneg));

    const r0 = try ffi.callFfi(&fn_int, &.{types.makeFixnum(0)}, &ctx.gc, ctx.vm);
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(r0));

    // #t / #f keep working as before (#418).
    const rt = try ffi.callFfi(&fn_int, &.{types.TRUE}, &ctx.gc, ctx.vm);
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(rt));

    const rf = try ffi.callFfi(&fn_int, &.{types.FALSE}, &ctx.gc, ctx.vm);
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
    const rbig = try ffi.callFfi(&fn_int, &.{big}, &ctx.gc, ctx.vm);
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(rbig));
}

test "ffi bool arg with bool return normalizes both directions (#796)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var ptypes = [_]types.FfiType{.bool_type};
    var fn_bool = makeBoolFn(ptypes[0..], .bool_type);

    try std.testing.expectEqual(types.TRUE, try ffi.callFfi(&fn_bool, &.{types.makeFixnum(2)}, &ctx.gc, ctx.vm));
    try std.testing.expectEqual(types.FALSE, try ffi.callFfi(&fn_bool, &.{types.makeFixnum(0)}, &ctx.gc, ctx.vm));
    try std.testing.expectEqual(types.TRUE, try ffi.callFfi(&fn_bool, &.{types.TRUE}, &ctx.gc, ctx.vm));
    try std.testing.expectEqual(types.FALSE, try ffi.callFfi(&fn_bool, &.{types.FALSE}, &ctx.gc, ctx.vm));
}

// ---------------------------------------------------------------------------
// Callback error propagation (#1185)
// ---------------------------------------------------------------------------

// A C-ABI function that drives a qsort-style (pointer, pointer) -> int
// comparator callback twice and combines the results — stands in for a C
// library invoking Scheme in the middle of an FFI call, without depending
// on an external shared library.
fn driveCmp(cmp: ?*anyopaque) callconv(.c) c_int {
    const f: *const fn (?*anyopaque, ?*anyopaque) callconv(.c) c_int = @ptrCast(@alignCast(cmp.?));
    return f(null, null) + f(null, null);
}

// Bind driveCmp as the global Scheme procedure `drive-cmp`.
fn defineDriveCmp(ctx: *th.TestContext) !void {
    const fn_val = try ctx.gc.allocFfiFunction(
        @ptrFromInt(@intFromPtr(&driveCmp)),
        types.FALSE,
        "drive_cmp",
        &.{.pointer},
        .int,
    );
    try ctx.vm.defineGlobal("drive-cmp", fn_val);
}

fn expectStringValue(expected: []const u8, v: types.Value) !void {
    try std.testing.expect(types.isString(v));
    const s = types.toObject(v).as(types.SchemeString);
    try std.testing.expectEqualStrings(expected, s.data[0..s.len]);
}

test "ffi callback error is re-raised after the C call returns (#1185)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try defineDriveCmp(&ctx);

    // The raise cannot unwind the C frame, so it must surface when
    // drive-cmp returns — catchable, with the original condition object.
    _ = try ctx.vm.eval("(define cb (ffi-callback (lambda (a b) (error \"cb-boom\")) '(pointer pointer) 'int))");
    const caught = try ctx.vm.eval(
        "(guard (e (#t (error-object-message e))) (drive-cmp cb) 'no-error)",
    );
    try expectStringValue("cb-boom", caught);
    _ = try ctx.vm.eval("(ffi-callback-release cb)");
}

test "ffi callback non-integer return raises instead of coercing to 0 (#1185)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try defineDriveCmp(&ctx);

    _ = try ctx.vm.eval("(define cb (ffi-callback (lambda (a b) 'not-an-int) '(pointer pointer) 'int))");
    const caught = try ctx.vm.eval(
        "(guard (e (#t (and (error-object? e) 'caught))) (drive-cmp cb) 'no-error)",
    );
    try std.testing.expect(types.isSymbol(caught));
    try std.testing.expectEqualStrings("caught", types.symbolName(caught));
    _ = try ctx.vm.eval("(ffi-callback-release cb)");
}

test "ffi callback error state is consumed by the failing call (#1185)" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    try defineDriveCmp(&ctx);

    _ = try ctx.vm.eval("(define bad (ffi-callback (lambda (a b) (error \"cb-boom\")) '(pointer pointer) 'int))");
    _ = try ctx.vm.eval("(guard (e (#t 'caught)) (drive-cmp bad))");

    // The stash was consumed by the re-raise: a well-behaved callback
    // through the same FFI function now succeeds and delivers its result.
    _ = try ctx.vm.eval("(define good (ffi-callback (lambda (a b) 3) '(pointer pointer) 'int))");
    const sum = try ctx.vm.eval("(drive-cmp good)");
    try std.testing.expectEqual(@as(i64, 6), types.toFixnum(sum));

    _ = try ctx.vm.eval("(ffi-callback-release bad)");
    _ = try ctx.vm.eval("(ffi-callback-release good)");
}

// ---------------------------------------------------------------------------
// ffi-open failure diagnostics: report the load error of the candidate that
// exists (or the name the user asked for), never the "no such file" of
// whichever fallback probe happened to run last
// ---------------------------------------------------------------------------

/// Evals `(ffi-open "<target>")` under a guard and returns the raised error
/// message. The slice points into ctx's heap — assert on it before
/// evaluating anything else.
fn ffiOpenErrorMessage(ctx: *th.TestContext, target: []const u8) ![]const u8 {
    var src_buf: [1400]u8 = undefined;
    const src = try std.fmt.bufPrint(
        &src_buf,
        "(guard (e (#t (error-object-message e))) (ffi-open \"{s}\") 'no-error)",
        .{target},
    );
    const caught = try ctx.vm.eval(src);
    try std.testing.expect(types.isString(caught));
    const s = types.toObject(caught).as(types.SchemeString);
    return s.data[0..s.len];
}

test "ffi-open: existing unloadable file's own error is reported, not a probe's" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "garbage-lib", .data = "not a shared library" });
    const dir_path = try th.tmpDirRealPathAlloc(&tmp, std.testing.allocator);
    defer std.testing.allocator.free(dir_path);

    var target_buf: [1200]u8 = undefined;
    const target = try std.fmt.bufPrint(&target_buf, "{s}/garbage-lib", .{dir_path});
    // Backslashes would be escape characters inside the Scheme string
    // literal; Win32 accepts forward slashes.
    std.mem.replaceScalar(u8, target, '\\', '/');

    const msg = try ffiOpenErrorMessage(&ctx, target);
    // The report is about the file that exists…
    try std.testing.expect(std.mem.indexOf(u8, msg, "garbage-lib") != null);
    // …not about a suffixed or home-prefixed candidate that never existed.
    try std.testing.expect(std.mem.indexOf(u8, msg, "garbage-lib.so") == null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "garbage-lib.dylib") == null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "garbage-lib.dll") == null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "lib//") == null);
}

test "ffi-open: bare name hitting an unloadable file under KAAPPI_HOME/lib reports that file's error" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.createDirPath(std.testing.io, "lib");
    try tmp.dir.writeFile(std.testing.io, .{ .sub_path = "lib/kaappi-test-home-garbage", .data = "not a shared library" });
    const dir_path = try th.tmpDirRealPathAlloc(&tmp, std.testing.allocator);
    defer std.testing.allocator.free(dir_path);

    // Point getHome's KAAPPI_HOME override at the tmp dir for the duration.
    var old_buf: [1024]u8 = undefined;
    const old_home: ?[]const u8 = if (platform.getenv("KAAPPI_HOME")) |v| blk: {
        const s = std.mem.sliceTo(v, 0);
        if (s.len > old_buf.len) break :blk null;
        @memcpy(old_buf[0..s.len], s);
        break :blk old_buf[0..s.len];
    } else null;
    try platform.setEnv(std.testing.allocator, "KAAPPI_HOME", dir_path);
    defer if (old_home) |v| {
        platform.setEnv(std.testing.allocator, "KAAPPI_HOME", v) catch {};
    } else {
        platform.unsetEnv(std.testing.allocator, "KAAPPI_HOME") catch {};
    };

    const msg = try ffiOpenErrorMessage(&ctx, "kaappi-test-home-garbage");
    // The middle-of-probe-order candidate that exists is the subject…
    try std.testing.expect(std.mem.indexOf(u8, msg, "kaappi-test-home-garbage") != null);
    // …not the .dylib/.so/.dll probes that ran (and missed) after it.
    try std.testing.expect(std.mem.indexOf(u8, msg, "kaappi-test-home-garbage.") == null);
}

test "ffi-open: name not found anywhere reports the requested name plus probe note" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const msg = try ffiOpenErrorMessage(&ctx, "kaappi-no-such-lib-zz");
    try std.testing.expect(std.mem.indexOf(u8, msg, "kaappi-no-such-lib-zz") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "also tried") != null);
}

test "ffi-open: a path with separators is not re-searched under home lib" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();

    const msg = try ffiOpenErrorMessage(&ctx, "/kaappi-no-such-dir/libnope");
    try std.testing.expect(std.mem.indexOf(u8, msg, "libnope") != null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "also tried") != null);
    // The note must not claim a home-dir probe, and no doubled
    // "<home>/lib/<path>" mashup may appear anywhere in the message.
    try std.testing.expect(std.mem.indexOf(u8, msg, "/lib/)") == null);
    try std.testing.expect(std.mem.indexOf(u8, msg, "lib//") == null);
}
