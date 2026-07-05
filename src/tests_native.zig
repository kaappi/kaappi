const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const ir_mod = @import("ir.zig");
const llvm_emit = @import("llvm_emit.zig");
const reader_mod = @import("reader.zig");
const native_decls = @import("native_decls.zig");

// The LLVMEmitter stores lambda function defs via toOwnedSlice that aren't
// individually freed on deinit (by design — production uses an arena).
// Use page_allocator for the emitter to avoid false leak reports.
const emitter_alloc = std.heap.page_allocator;

const EmitResult = struct {
    gc: memory.GC,
    ir_instance: ir_mod.IR,
    emitter: llvm_emit.LLVMEmitter,

    fn toSlice(self: *EmitResult) []const u8 {
        return self.emitter.toSlice();
    }

    fn deinit(self: *EmitResult) void {
        self.emitter.deinit();
        self.ir_instance.deinit();
        self.gc.deinit();
    }
};

fn emitSourceResult(source: []const u8) !EmitResult {
    var gc = memory.GC.init(emitter_alloc);
    errdefer gc.deinit();

    var reader = reader_mod.Reader.init(&gc, source);
    defer reader.deinit();
    const expr = try reader.readDatum();

    var ir_instance = ir_mod.IR.init(emitter_alloc);
    errdefer ir_instance.deinit();

    var root = try ir_mod.lower(&ir_instance, expr);
    ir_mod.markTailPositions(root, false);
    ir_mod.identifyPrimitives(root);
    ir_mod.markConstants(root);
    root = ir_mod.foldConstants(&ir_instance, root);
    root = ir_mod.eliminateDeadBranches(&ir_instance, root);
    root = ir_mod.simplifyBooleans(&ir_instance, root);
    root = ir_mod.eliminateIdentity(&ir_instance, root);
    root = ir_mod.simplifyBegin(&ir_instance, root);

    var nodes = [_]*ir_mod.Node{root};
    var emitter = llvm_emit.LLVMEmitter.init(emitter_alloc);
    errdefer emitter.deinit();
    try emitter.emitProgram(&nodes);

    return .{ .gc = gc, .ir_instance = ir_instance, .emitter = emitter };
}

fn emitMultiResult(source: []const u8) !EmitResult {
    var gc = memory.GC.init(emitter_alloc);
    errdefer gc.deinit();

    var reader = reader_mod.Reader.init(&gc, source);
    defer reader.deinit();

    var ir_instance = ir_mod.IR.init(emitter_alloc);
    errdefer ir_instance.deinit();

    var ir_nodes: std.ArrayList(*ir_mod.Node) = .empty;
    defer ir_nodes.deinit(emitter_alloc);

    while (try reader.hasMore()) {
        const expr = try reader.readDatum();
        var root = try ir_mod.lower(&ir_instance, expr);
        ir_mod.markTailPositions(root, false);
        ir_mod.identifyPrimitives(root);
        ir_mod.markConstants(root);
        root = ir_mod.foldConstants(&ir_instance, root);
        root = ir_mod.eliminateDeadBranches(&ir_instance, root);
        root = ir_mod.simplifyBooleans(&ir_instance, root);
        root = ir_mod.eliminateIdentity(&ir_instance, root);
        root = ir_mod.simplifyBegin(&ir_instance, root);
        try ir_nodes.append(emitter_alloc, root);
    }

    var emitter = llvm_emit.LLVMEmitter.init(emitter_alloc);
    errdefer emitter.deinit();
    try emitter.emitProgram(ir_nodes.items);

    return .{ .gc = gc, .ir_instance = ir_instance, .emitter = emitter };
}

fn expectContains(haystack: []const u8, needle: []const u8) !void {
    if (std.mem.indexOf(u8, haystack, needle) == null) {
        std.debug.print("\n--- Expected to find ---\n{s}\n--- in output (len={d}) ---\n", .{ needle, haystack.len });
        return error.TestExpectedEqual;
    }
}

// -- Preamble and structure --

test "LLVM emit: preamble has target triple and runtime calls" {
    var res = try emitSourceResult("42");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "target triple");
    try expectContains(ll, "define i32 @main()");
    try expectContains(ll, "@kaappi_runtime_init");
    try expectContains(ll, "@kaappi_runtime_deinit");
    try expectContains(ll, "ret i32 0");
}

test "LLVM emit: preamble declares runtime functions" {
    var res = try emitSourceResult("42");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "declare ptr @kaappi_runtime_init()");
    try expectContains(ll, "declare i64 @kaappi_global_lookup(ptr, ptr, i64)");
    try expectContains(ll, "declare i64 @kaappi_call_scheme(ptr, i64, ptr, i64)");
    try expectContains(ll, "declare i64 @kaappi_fixnum_add(i64, i64)");
    try expectContains(ll, "declare i64 @kaappi_cons(i64, i64)");
    try expectContains(ll, "declare i64 @kaappi_car(i64)");
    try expectContains(ll, "declare i64 @kaappi_cdr(i64)");
}

// -- Constants --

test "LLVM emit: fixnum constant" {
    var res = try emitSourceResult("42");
    defer res.deinit();
    try expectContains(res.toSlice(), "add i64 0,");
}

test "LLVM emit: string constant" {
    var res = try emitSourceResult(
        \\"hello"
    );
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "@kaappi_make_string");
    try expectContains(ll, "hello");
}

test "LLVM emit: boolean constants" {
    var res_t = try emitSourceResult("#t");
    defer res_t.deinit();
    try expectContains(res_t.toSlice(), "add i64 0,");

    var res_f = try emitSourceResult("#f");
    defer res_f.deinit();
    try expectContains(res_f.toSlice(), "add i64 0,");
}

// -- Global references --

test "LLVM emit: global reference" {
    var res = try emitSourceResult("display");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "@kaappi_global_lookup");
    try expectContains(ll, "display");
}

// -- Calls --

test "LLVM emit: general call emits kaappi_call_scheme" {
    var res = try emitSourceResult("(f 1 2)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_call_scheme");
}

test "LLVM emit: inline add" {
    var res = try emitSourceResult("(+ a b)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_fixnum_add");
}

test "LLVM emit: inline sub" {
    var res = try emitSourceResult("(- a b)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_fixnum_sub");
}

test "LLVM emit: inline mul" {
    var res = try emitSourceResult("(* a b)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_fixnum_mul");
}

test "LLVM emit: inline car" {
    var res = try emitSourceResult("(car x)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_car");
}

test "LLVM emit: inline cdr" {
    var res = try emitSourceResult("(cdr x)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_cdr");
}

test "LLVM emit: inline cons" {
    var res = try emitSourceResult("(cons a b)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_cons");
}

test "LLVM emit: inline null?" {
    var res = try emitSourceResult("(null? x)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_is_null");
}

// -- Control flow --

test "LLVM emit: if with else" {
    var res = try emitSourceResult("(if x 1 2)");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "br i1");
    try expectContains(ll, "then");
    try expectContains(ll, "else");
    try expectContains(ll, "phi i64");
}

test "LLVM emit: if without else" {
    var res = try emitSourceResult("(if x 1)");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "br i1");
    try expectContains(ll, "phi i64");
}

test "LLVM emit: and short-circuit" {
    var res = try emitSourceResult("(and x y)");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "and_merge");
    try expectContains(ll, "phi i64");
}

test "LLVM emit: or short-circuit" {
    var res = try emitSourceResult("(or x y)");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "or_merge");
    try expectContains(ll, "phi i64");
}

test "LLVM emit: when form" {
    var res = try emitSourceResult("(when x 42)");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "when_body");
    try expectContains(ll, "when_merge");
    try expectContains(ll, "phi i64");
}

test "LLVM emit: unless form" {
    var res = try emitSourceResult("(unless x 42)");
    defer res.deinit();
    const ll = res.toSlice();
    try expectContains(ll, "unless_body");
    try expectContains(ll, "unless_merge");
    try expectContains(ll, "phi i64");
}

// -- Definitions --

test "LLVM emit: define global" {
    var res = try emitSourceResult("(define x 42)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_define_global");
}

test "LLVM emit: set! global" {
    var res = try emitMultiResult("(define y 0) (set! y 1)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_set_global");
}

// -- Lambda --

test "LLVM emit: lambda as native closure" {
    var res = try emitSourceResult("(lambda (x) x)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_create_native_closure");
}

// -- Let --

test "LLVM emit: let binding" {
    var res = try emitSourceResult("(let ((x 1)) x)");
    defer res.deinit();
    try expectContains(res.toSlice(), "alloca i64");
}

test "LLVM emit: let* sequential" {
    var res = try emitSourceResult("(let* ((x 1) (y x)) y)");
    defer res.deinit();
    try expectContains(res.toSlice(), "alloca i64");
}

// -- Begin --

test "LLVM emit: begin sequence" {
    var res = try emitSourceResult("(begin a b c)");
    defer res.deinit();
    const ll = res.toSlice();
    const count = std.mem.count(u8, ll, "@kaappi_global_lookup");
    try std.testing.expect(count >= 3);
}

// -- Comparisons --

test "LLVM emit: inline less-than" {
    var res = try emitSourceResult("(< a b)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_fixnum_lt");
}

test "LLVM emit: inline equal" {
    var res = try emitSourceResult("(= a b)");
    defer res.deinit();
    try expectContains(res.toSlice(), "@kaappi_fixnum_eq");
}

// -- Declare table drift test --
// The comptime block in native_decls.zig validates that the table matches
// the actual Zig signatures in runtime_exports.zig. This test verifies
// the emitted preamble contains every declare from the table.

test "native declare table covers all runtime exports in preamble" {
    var res = try emitSourceResult("42");
    defer res.deinit();
    const ll = res.toSlice();
    for (native_decls.decls) |d| {
        if (std.mem.indexOf(u8, ll, d.export_name) == null) {
            std.debug.print("\nmissing declare for {s}\n", .{d.export_name});
            return error.TestExpectedEqual;
        }
    }
    try std.testing.expectEqual(@as(usize, 21), native_decls.decls.len);
}
