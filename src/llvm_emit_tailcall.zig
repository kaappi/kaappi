// Forward-reference plumbing for guaranteed mutual tail calls (#1499).
//
// Mutual recursion needs a *forward* tail call — a callee defined later in the
// program — to lower to a direct `musttail`, but `native_fns` is populated in
// emission order. `preScanReserve` runs once over all top-level nodes and
// reserves a stable `@r{i}`/`@r{i}.fast` name pair for every top-level function
// define that is fast-entry eligible, so a forward call can target `@r{i}.fast`
// before the define is emitted. `emitForwardStubs` then defines any reserved
// `@r{i}.fast` that never got a real native body (its define fell back to the
// interpreter), so every `musttail` target links.
//
// The register-argument fast-call emission itself (`emitFastCall`) and the
// fast-entry function emission (`emitLambdaFunction`, `emitFastTrampoline`) live
// next to the call/lambda emitters they belong with, in llvm_emit.zig and
// llvm_emit_lambda.zig respectively. This file is only the reservation +
// finalization-stub half.

const std = @import("std");
const ir = @import("ir.zig");
const types = @import("types.zig");

const llvm_emit = @import("llvm_emit.zig");
const LLVMEmitter = llvm_emit.LLVMEmitter;
const EmitError = llvm_emit.EmitError;
const ReservedFast = llvm_emit.ReservedFast;

const Value = types.Value;

// True if `expr` is a list whose head is the symbol `kw`.
fn isFormNamed(expr: Value, kw: []const u8) bool {
    if (!types.isPair(expr)) return false;
    const head = types.car(expr);
    return types.isSymbol(head) and std.mem.eql(u8, types.symbolName(head), kw);
}

// A top-level define seen by the pre-scan (#1499). `formals` is non-null only
// for a *function* define — `(define (f . formals) …)` or
// `(define f (lambda formals …))` — the only shape a fast entry can apply to.
const TopDefine = struct { name: []const u8, formals: ?Value };

// Recognize a top-level define node in any of its lowered shapes and extract the
// defined name (+ formals, for function defines). `(define (f x) …)` lowers to a
// `.passthrough` (ir.zig lowerDefine), `(define f v)` / `(define f (lambda …))`
// to a `.define` node.
fn topLevelDefine(node: *const ir.Node) ?TopDefine {
    switch (node.tag) {
        .define => {
            if (!types.isSymbol(node.data.define.name)) return null;
            const name = types.symbolName(node.data.define.name);
            const value = node.data.define.value;
            if (isFormNamed(value, "lambda")) {
                const after = types.cdr(value);
                if (types.isPair(after)) return .{ .name = name, .formals = types.car(after) };
            }
            return .{ .name = name, .formals = null };
        },
        .passthrough => {
            const expr = node.data.passthrough;
            if (!isFormNamed(expr, "define")) return null;
            const rest = types.cdr(expr);
            if (!types.isPair(rest)) return null;
            const target = types.car(rest);
            if (types.isPair(target) and types.isSymbol(types.car(target)))
                return .{ .name = types.symbolName(types.car(target)), .formals = types.cdr(target) };
            if (types.isSymbol(target))
                return .{ .name = types.symbolName(target), .formals = null };
            return null;
        },
        else => return null,
    }
}

// A top-level `(set! name …)` target name, if any.
fn topLevelSetName(node: *const ir.Node) ?[]const u8 {
    if (node.tag != .set_form) return null;
    if (!types.isSymbol(node.data.set_form.name)) return null;
    return types.symbolName(node.data.set_form.name);
}

// Count of a proper list of symbol formals (fixed arity ≤ max_fast_arity), or
// null for a dotted/variadic list, a non-symbol formal, or too many params —
// none of which are fast-entry eligible.
fn parseFixedArity(formals: Value) ?u8 {
    var n: usize = 0;
    var cur = formals;
    while (cur != types.NIL) {
        if (!types.isPair(cur)) return null; // dotted ⇒ variadic
        if (!types.isSymbol(types.car(cur))) return null;
        n += 1;
        if (n > llvm_emit.max_fast_arity) return null;
        cur = types.cdr(cur);
    }
    return @intCast(n);
}

// Reserve a stable @r{i}/@r{i}.fast name pair for each top-level function define
// that is fast-entry eligible, so a *forward* mutual tail call (a callee defined
// later in the program) still lowers to a direct `musttail`. Conservative,
// syntactic, and sound: only names defined exactly once at top level, never a
// top-level `set!` target, with a proper list of symbol formals within
// max_fast_arity are reserved. The real body (if the define compiles natively)
// or a finalization stub (if it falls back to the interpreter) defines the
// @r{i}.fast symbol, so the musttail always links.
pub fn preScanReserve(self: *LLVMEmitter, nodes: []const *ir.Node) EmitError!void {
    if (!llvm_emit.fast_tailcalls_supported) return;

    var def_count = std.StringHashMap(u32).init(self.allocator());
    var set_targets = std.StringHashMap(void).init(self.allocator());
    for (nodes) |node| {
        if (topLevelDefine(node)) |td| {
            const gop = def_count.getOrPut(td.name) catch return error.OutOfMemory;
            gop.value_ptr.* = if (gop.found_existing) gop.value_ptr.* + 1 else 1;
        }
        if (topLevelSetName(node)) |sname| {
            set_targets.put(sname, {}) catch return error.OutOfMemory;
        }
    }

    for (nodes) |node| {
        const td = topLevelDefine(node) orelse continue;
        const formals = td.formals orelse continue;
        const arity = parseFixedArity(formals) orelse continue;
        if ((def_count.get(td.name) orelse 0) != 1) continue; // redefined
        if (set_targets.contains(td.name)) continue; // rebound by set!
        if (self.reserved_fast.contains(td.name)) continue;

        const id = self.reserved_counter;
        self.reserved_counter += 1;
        const base = std.fmt.allocPrint(self.allocator(), "@r{d}", .{id}) catch return error.OutOfMemory;
        const fast = std.fmt.allocPrint(self.allocator(), "@r{d}.fast", .{id}) catch return error.OutOfMemory;
        self.reserved_fast.put(td.name, .{ .base = base, .fast = fast, .arity = arity }) catch return error.OutOfMemory;
    }
}

// Emit a forwarding stub for every reserved name a `musttail` targeted that
// never got a real native @r{i}.fast body (the define fell back to the
// interpreter). The stub is a `tailcc` shell around the ordinary indirect call —
// it looks the name up as a global and dispatches through kaappi_call_scheme —
// so the symbol resolves at link time. Correct, though not itself constant-stack,
// for that one non-native edge of a cycle.
pub fn emitForwardStubs(self: *LLVMEmitter) EmitError!void {
    var it = self.forward_referenced.keyIterator();
    while (it.next()) |name_ptr| {
        const name = name_ptr.*;
        if (self.fulfilled_fast.contains(name)) continue;
        const rf = self.reserved_fast.get(name) orelse continue;
        try emitForwardStub(self, name, rf);
    }
}

fn emitForwardStub(self: *LLVMEmitter, name: []const u8, rf: ReservedFast) EmitError!void {
    // Intern the symbol now, while running before the module's symbol constants
    // are emitted (see emitProgram), so @.sym.N exists for it.
    const sym_name = try self.internSymbol(name);

    const saved_buf = self.buf;
    const saved_tmp = self.tmp_counter;
    self.buf = .empty;
    self.tmp_counter = 0;
    defer {
        self.buf = saved_buf;
        self.tmp_counter = saved_tmp;
    }

    try self.print("; forward-ref stub: {s}\ndefine internal tailcc i64 {s}(ptr %vm", .{ name, rf.fast });
    var i: usize = 0;
    while (i < rf.arity) : (i += 1) try self.print(", i64 %a{d}", .{i});
    try self.write(", ptr %upvalues) {\nentry:\n");

    var args_ref: []const u8 = "null";
    if (rf.arity > 0) {
        const args_alloca = try self.freshTemp();
        try self.print("  {s} = alloca [{d} x i64], align 8\n", .{ args_alloca, rf.arity });
        i = 0;
        while (i < rf.arity) : (i += 1) {
            const gep = try self.freshTemp();
            try self.print("  {s} = getelementptr i64, ptr {s}, i64 {d}\n", .{ gep, args_alloca, i });
            try self.print("  store i64 %a{d}, ptr {s}\n", .{ i, gep });
        }
        args_ref = args_alloca;
    }
    const callee = try self.freshTemp();
    try self.print("  {s} = call i64 @kaappi_global_lookup(ptr %vm, ptr {s}, i64 {d})\n", .{ callee, sym_name, name.len });
    const result = try self.freshTemp();
    try self.print("  {s} = call i64 @kaappi_call_scheme(ptr %vm, i64 {s}, ptr {s}, i64 {d})\n", .{ result, callee, args_ref, rf.arity });
    try self.print("  ret i64 {s}\n}}\n", .{result});

    const def = self.buf.toOwnedSlice(self.backing_alloc) catch return error.OutOfMemory;
    self.lambda_defs.append(self.backing_alloc, def) catch return error.OutOfMemory;
}
