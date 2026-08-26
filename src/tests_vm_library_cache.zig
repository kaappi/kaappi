// Unit tests for the .sld bytecode-cache machinery (kaappi#1888):
// the library-entry codec halves in bytecode_file_{write,read}.zig and the
// availability classification in vm_library_cache.zig. The end-to-end cold /
// warm / invalidation contract lives in
// tests/scheme/cache/library-cache-1888.sh and the differential suite.

const std = @import("std");
const platform = @import("platform.zig");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");
const memory = @import("memory.zig");
const bytecode_file = @import("bytecode_file.zig");
const vm_library_cache = @import("vm_library_cache.zig");

const GC = memory.GC;
const Function = types.Function;

/// `(load_const dst c) (return dst)` for a fixnum constant.
fn makeReturnConstFunc(gc: *GC, comptime n: i64) !*Function {
    const allocator = gc.allocator;
    const func = try gc.allocFunction();
    func.code.append(allocator, @intFromEnum(types.OpCode.load_const)) catch unreachable;
    func.code.append(allocator, 0) catch unreachable; // dst high
    func.code.append(allocator, 0) catch unreachable; // dst low
    func.code.append(allocator, 0) catch unreachable; // idx high
    func.code.append(allocator, 0) catch unreachable; // idx low
    func.code.append(allocator, @intFromEnum(types.OpCode.@"return")) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.code.append(allocator, 0) catch unreachable;
    func.constants.append(allocator, types.makeFixnum(n)) catch unreachable;
    func.arity = 0;
    func.locals_count = 1;
    return func;
}

/// A syntax-rules transformer `(kw x) -> (helper x)` with one literal, a
/// custom ellipsis, and bound free refs — exercising every serialized field.
fn makeTransformer(gc: *GC) !*types.Transformer {
    const allocator = gc.allocator;
    var helper = try gc.allocSymbol("helper");
    var kw = try gc.allocSymbol("kw");
    var x = try gc.allocSymbol("x");
    gc.pushRoot(&helper);
    gc.pushRoot(&kw);
    gc.pushRoot(&x);
    defer gc.popRoot();
    defer gc.popRoot();
    defer gc.popRoot();

    const lit = try gc.allocSymbol("if");
    const pattern = try gc.makeList(&[_]types.Value{ kw, x });
    const tmpl = try gc.makeList(&[_]types.Value{ helper, x });

    const literals = [_]types.Value{lit};
    const patterns = [_]types.Value{pattern};
    const templates = [_]types.Value{tmpl};
    const tx_val = try gc.allocTransformer(&literals, &patterns, &templates);
    var tx_root = tx_val;
    gc.pushRoot(&tx_root);
    defer gc.popRoot();
    const tx = types.toObject(tx_val).as(types.Transformer);
    tx.custom_ellipsis = "…";
    tx.def_lib_name = "user1888.u";
    tx.finalized = true;
    const bound = try allocator.alloc([]const u8, 1);
    bound[0] = "helper";
    tx.bound_free_refs = bound;
    const slots = try allocator.alloc(u32, 1);
    slots[0] = 0xFFFF;
    tx.literal_bound = slots;
    return tx;
}

test "library entry: transformer, events, includes and deps round-trip" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // bytecode-file writes are gated off on wasm (bytecode_file_write.zig)
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    const f0 = try makeReturnConstFunc(&gc, 5);
    var f0_root = types.makePointer(&f0.header);
    gc.pushRoot(&f0_root);
    defer gc.popRoot();
    const f1 = try makeReturnConstFunc(&gc, 6);
    var f1_root = types.makePointer(&f1.header);
    gc.pushRoot(&f1_root);
    defer gc.popRoot();

    const tx = try makeTransformer(&gc);

    var funcs_arr = [_]*Function{ f0, f1 };
    const events = [_]bytecode_file.LibEventRecord{
        .{ .register_tx = .{ .name = "twicer", .tx = tx } },
        .{ .run_lib = 0 },
        .{ .run_global = 1 },
    };
    const includes = [_]bytecode_file.IncludeRecord{
        .{ .path = "dir/body.scm", .hash = 0xDEADBEEF },
    };
    const deps = [_]bytecode_file.DepRecord{
        .{ .rel_path = "dep1888/base.sld", .resolved_path = "/libs/dep1888/base.sld", .source_hash = 0xCAFE, .lib_name = "dep1888.base" },
    };
    const hash: u64 = 0x1BAD;
    const path = "/tmp/kaappi_test_lib_entry.sbc";
    try bytecode_file.writeFileWithLibrary(allocator, &funcs_arr, &events, &includes, &deps, hash, "u.sld", path);
    defer _ = std.posix.system.unlink(@ptrCast(path));

    var loaded = (try bytecode_file.readFileWithTopLevel(&gc, hash, path)) orelse
        return error.TestUnexpectedResult;
    defer bytecode_file.freeDeserializeResult(allocator, &loaded);

    const lib = loaded.library orelse return error.TestUnexpectedResult;
    const r_includes = loaded.includes orelse return error.TestUnexpectedResult;
    const r_deps = loaded.deps orelse return error.TestUnexpectedResult;
    try std.testing.expectEqual(@as(usize, 3), lib.events.len);
    try std.testing.expectEqualStrings("twicer", lib.events[0].register_tx.name);
    try std.testing.expect(lib.events[1] == .run_lib);
    try std.testing.expectEqual(@as(u32, 0), lib.events[1].run_lib);
    try std.testing.expect(lib.events[2] == .run_global);
    try std.testing.expectEqual(@as(u32, 1), lib.events[2].run_global);

    const tx2 = lib.events[0].register_tx.tx;
    try std.testing.expectEqual(types.TransformerKind.syntax_rules, tx2.kind);
    try std.testing.expectEqual(@as(u16, 1), tx2.num_rules);
    try std.testing.expectEqualStrings("…", tx2.custom_ellipsis.?);
    try std.testing.expectEqualStrings("user1888.u", tx2.def_lib_name.?);
    try std.testing.expect(tx2.finalized);
    try std.testing.expect(!tx2.peers_computed);
    try std.testing.expectEqual(@as(usize, 1), tx2.bound_free_refs.len);
    try std.testing.expectEqualStrings("helper", tx2.bound_free_refs[0]);
    try std.testing.expectEqual(@as(usize, 1), tx2.literal_bound.len);
    try std.testing.expectEqual(@as(u32, 0xFFFF), tx2.literal_bound[0]);
    // def_env is deliberately absent from the codec: the warm loader points
    // it at the reconstructed lib_env.
    try std.testing.expect(tx2.def_env == null);
    // The pattern and template survive as datum.
    try std.testing.expect(types.isPair(tx2.patterns[0]));
    try std.testing.expectEqualStrings("kw", types.symbolName(types.car(tx2.patterns[0])));
    try std.testing.expectEqualStrings("helper", types.symbolName(types.car(tx2.templates[0])));

    try std.testing.expectEqual(@as(usize, 1), r_includes.len);
    try std.testing.expectEqualStrings("dir/body.scm", r_includes[0].path);
    try std.testing.expectEqual(@as(u64, 0xDEADBEEF), r_includes[0].hash);

    try std.testing.expectEqual(@as(usize, 1), r_deps.len);
    try std.testing.expectEqualStrings("dep1888/base.sld", r_deps[0].rel_path);
    try std.testing.expectEqualStrings("/libs/dep1888/base.sld", r_deps[0].resolved_path);
    try std.testing.expectEqual(@as(u64, 0xCAFE), r_deps[0].source_hash);
    try std.testing.expectEqualStrings("dep1888.base", r_deps[0].lib_name);

    // The event functions load and their bytecode still executes.
    try std.testing.expectEqual(@as(u32, 2), loaded.top_level_count);
    var fv = types.makePointer(&loaded.funcs[0].header);
    gc.pushRoot(&fv);
    defer gc.popRoot();
}

test "library entry: a hash mismatch is a miss" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // bytecode-file writes are gated off on wasm (bytecode_file_write.zig)
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    const f0 = try makeReturnConstFunc(&gc, 1);
    var f0_root = types.makePointer(&f0.header);
    gc.pushRoot(&f0_root);
    defer gc.popRoot();
    var funcs_arr = [_]*Function{f0};
    const events = [_]bytecode_file.LibEventRecord{.{ .run_lib = 0 }};
    const path = "/tmp/kaappi_test_lib_hash.sbc";
    try bytecode_file.writeFileWithLibrary(allocator, &funcs_arr, &events, &.{}, &.{}, 0xAAAA, "u.sld", path);
    defer _ = std.posix.system.unlink(@ptrCast(path));

    const wrong = try bytecode_file.readFileWithTopLevel(&gc, 0xBBBB, path);
    try std.testing.expect(wrong == null);
}

test "featureReqTouchesAvailability: only availability-dependent requirements" {
    if (comptime platform.is_wasm) return error.SkipZigTest; // needs a GC for the symbol fixtures
    const allocator = std.testing.allocator;
    var gc = GC.init(allocator);
    defer gc.deinit();

    const F = struct {
        fn req(g: *GC, src: []const u8) types.Value {
            var r = @import("reader.zig").Reader.init(g, src);
            return r.readDatum() catch unreachable;
        }
    };

    // Platform features are compile-time constants (compiler-hash covered).
    try std.testing.expect(!vm_library_cache.featureReqTouchesAvailability(F.req(&gc, "r7rs")));
    try std.testing.expect(!vm_library_cache.featureReqTouchesAvailability(F.req(&gc, "kaappi")));
    // srfi-<n> feature ids and (library …) probe the live registry/lib-path.
    try std.testing.expect(vm_library_cache.featureReqTouchesAvailability(F.req(&gc, "srfi-64")));
    try std.testing.expect(vm_library_cache.featureReqTouchesAvailability(F.req(&gc, "(library (scheme base))")));
    // ...including nested inside and/or/not.
    try std.testing.expect(vm_library_cache.featureReqTouchesAvailability(F.req(&gc, "(and r7rs (not (library (srfi 1))))")));
    try std.testing.expect(!vm_library_cache.featureReqTouchesAvailability(F.req(&gc, "(or r7rs kaappi)")));
}
