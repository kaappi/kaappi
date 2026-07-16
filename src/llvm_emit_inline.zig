// Inline fixnum fast-path emission for the LLVM backend (kaappi#1493).
//
// Arithmetic (+, -, *), ordering/equality (<, =), and null? operate purely on
// NaN-boxed Value bits, so their fixnum cases can be lowered to inline IR that
// calls the runtime only on the slow path (non-fixnum operands, or an
// arithmetic result outside the i48 fixnum range → bignum promotion). This
// removes the per-operation cross-module call that -O2 alone cannot eliminate.
//
// `tryEmitInlineBinary` / `tryEmitInlineUnary` are the entry points, dispatched
// from emitCallNode in llvm_emit.zig: they return null when the operator is not
// one of the inlinable primitives, so the caller falls through to a normal
// call. Everything else here (the NaN-box constants, the branch/phi helpers)
// is file-private machinery for those two.
//
// cons and car/cdr deliberately stay direct runtime calls: cons always
// allocates (no call-free fast path) and both touch the auto-layout Pair
// struct, whose field offsets are NOT encoded here (see the nanbox note).

const std = @import("std");
const ir = @import("ir.zig");
const types = @import("types.zig");
const native_decls = @import("native_decls.zig");

const llvm_emit = @import("llvm_emit.zig");
const LLVMEmitter = llvm_emit.LLVMEmitter;
const EmitError = llvm_emit.EmitError;

// NaN-box encoding constants for inline primitive emission. Derived at comptime
// from types.zig so the emitted IR always matches the runtime's value
// representation — no hand-transcribed magic numbers to drift out of sync.
// These describe only the immediate Value bit layout (fixnum tag, payload, nil,
// booleans), which is stable; heap-object field offsets (auto-layout structs)
// are deliberately NOT encoded here, so car/cdr/cons stay as runtime calls.
const nanbox = struct {
    // High 16 bits (v >> 48) that mark a fixnum: 0xFFFD.
    const fix_tag_hi: u64 = types.makeFixnum(0) >> 48;
    // Base fixnum tag bits, OR'd with a 48-bit payload to box an integer.
    const fix_base: i64 = @bitCast(types.makeFixnum(0));
    // Mask selecting the 48-bit fixnum payload.
    const payload_mask: i64 = std.math.maxInt(u48);
    // Inclusive range of integers representable as a fixnum (i48).
    const fix_min: i64 = std.math.minInt(i48);
    const fix_max: i64 = std.math.maxInt(i48);
    const nil: i64 = @bitCast(types.NIL);
    const true_val: i64 = @bitCast(types.TRUE);
    const false_val: i64 = @bitCast(types.FALSE);
};

const ArithOp = enum {
    add,
    sub,
    mul,

    // LLVM checked-arithmetic intrinsic that mirrors the runtime's
    // @addWithOverflow / @subWithOverflow / @mulWithOverflow fast path.
    fn overflowIntrinsic(self: ArithOp) []const u8 {
        return switch (self) {
            .add => "@llvm.sadd.with.overflow.i64",
            .sub => "@llvm.ssub.with.overflow.i64",
            .mul => "@llvm.smul.with.overflow.i64",
        };
    }

    fn fromName(name: []const u8) ?ArithOp {
        if (std.mem.eql(u8, name, "+")) return .add;
        if (std.mem.eql(u8, name, "-")) return .sub;
        if (std.mem.eql(u8, name, "*")) return .mul;
        return null;
    }
};

const CompareKind = enum { lt, eq };

// Conservative "evaluating this node might allocate (and therefore trigger a
// GC)". Used to elide the shadow-stack rooting that only exists to keep an
// already-computed operand alive while a *later* operand is evaluated: if the
// later operand cannot allocate, nothing can collect, so the root push/pop pair
// (two cross-module runtime calls) is pure overhead. Errs toward `true` — only
// leaves whose emission is provably allocation-free return `false`:
//   - immediate constants (fixnum/bool/char/nil) lower to a bare `add i64 0, K`;
//     heap constants (string/symbol/pair) call make_string/intern_symbol/eval.
//   - variable references (global_ref) always lower to a load or a
//     non-allocating runtime call (global_lookup / box_ref).
// Every compound form may allocate, so it stays `true`.
fn nodeMayAllocate(node: *const ir.Node) bool {
    return switch (node.tag) {
        .constant => types.isPointer(node.data.constant),
        .global_ref => false,
        else => true,
    };
}

pub fn tryEmitInlineBinary(self: *LLVMEmitter, name: []const u8, args: []const *ir.Node) ?[]const u8 {
    const export_name = native_decls.findInline(.binary, name) orelse return null;
    const a = self.emitNode(args[0]) catch return null;
    // Root the first operand across the second's evaluation only when that
    // evaluation could actually collect. For the common hot-loop shapes
    // `(op var const)` and `(op var var)` the second operand is a leaf, so
    // this drops two runtime calls (push_root/pop_roots) per operation.
    const root_a = nodeMayAllocate(args[1]);
    if (root_a) self.emitRootPush(a) catch return null;
    const b = self.emitNode(args[1]) catch return null;
    if (root_a) self.emitPopRoots(1) catch return null;

    // Arithmetic and comparison operate purely on NaN-boxed Value bits, so
    // their fixnum fast paths lower to inline IR with a call to the runtime
    // only on the slow path (non-fixnum operands, or overflow out of the
    // i48 fixnum range → bignum promotion). This removes the per-operation
    // cross-module call that -O2 alone cannot eliminate (#1493). cons falls
    // through to a direct specialized call: it always allocates, so there is
    // no call-free fast path, and its Pair layout is not encodable here.
    if (ArithOp.fromName(name)) |op|
        return emitInlineArith(self, op, a, b, export_name) catch return null;
    if (std.mem.eql(u8, name, "<"))
        return emitInlineCompare(self, .lt, a, b, export_name) catch return null;
    if (std.mem.eql(u8, name, "="))
        return emitInlineCompare(self, .eq, a, b, export_name) catch return null;

    const result = self.freshTemp() catch return null;
    self.print("  {s} = call i64 @{s}(i64 {s}, i64 {s})\n", .{ result, export_name, a, b }) catch return null;
    return result;
}

pub fn tryEmitInlineUnary(self: *LLVMEmitter, name: []const u8, arg: *const ir.Node) ?[]const u8 {
    const export_name = native_decls.findInline(.unary, name) orelse return null;
    const v = self.emitNode(arg) catch return null;

    // null? is a single Value comparison against the nil immediate — no
    // heap access, no fallback needed. car/cdr touch the (auto-layout) Pair
    // struct and raise on a non-pair, so they stay as direct runtime calls.
    if (std.mem.eql(u8, name, "null?"))
        return emitInlineNullCheck(self, v) catch return null;

    const result = self.freshTemp() catch return null;
    self.print("  {s} = call i64 @{s}(i64 {s})\n", .{ result, export_name, v }) catch return null;
    return result;
}

// Emit `%dst = <sign-extended i48 payload of %boxed>`. Shifting the tag bits
// out to the left and arithmetic-shifting back sign-extends bit 47, matching
// types.toFixnum. Caller must have already checked %boxed is a fixnum.
fn emitUnboxFixnum(self: *LLVMEmitter, boxed: []const u8) EmitError![]const u8 {
    const shifted = try self.freshTemp();
    try self.print("  {s} = shl i64 {s}, 16\n", .{ shifted, boxed });
    const val = try self.freshTemp();
    try self.print("  {s} = ashr i64 {s}, 16\n", .{ val, shifted });
    return val;
}

// Emit `%dst = i1` that is true iff %boxed carries the fixnum tag
// (`(boxed >> 48) == 0xFFFD`), matching types.isFixnum.
fn emitIsFixnum(self: *LLVMEmitter, boxed: []const u8) EmitError![]const u8 {
    const hi = try self.freshTemp();
    try self.print("  {s} = lshr i64 {s}, 48\n", .{ hi, boxed });
    const is_fix = try self.freshTemp();
    try self.print("  {s} = icmp eq i64 {s}, {d}\n", .{ is_fix, hi, nanbox.fix_tag_hi });
    return is_fix;
}

// Compute `i1` = both operands are fixnums, then branch to the caller's
// fixnum fast-path block or its runtime slow-path block accordingly.
fn emitBothFixnumBranch(self: *LLVMEmitter, a: []const u8, b: []const u8, fast: []const u8, slow: []const u8) EmitError!void {
    const a_fix = try emitIsFixnum(self, a);
    const b_fix = try emitIsFixnum(self, b);
    const both = try self.freshTemp();
    try self.print("  {s} = and i1 {s}, {s}\n", .{ both, a_fix, b_fix });
    try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ both, fast, slow });
}

// Fixnum fast path for +, -, *. On non-fixnum operands or a result outside
// the i48 fixnum range (overflow → bignum), fall back to the runtime.
fn emitInlineArith(self: *LLVMEmitter, op: ArithOp, a: []const u8, b: []const u8, export_name: []const u8) EmitError![]const u8 {
    const id = self.label_counter;
    self.label_counter += 1;
    const fast = try std.fmt.allocPrint(self.allocator(), "arith_fast{d}", .{id});
    const box = try std.fmt.allocPrint(self.allocator(), "arith_box{d}", .{id});
    const slow = try std.fmt.allocPrint(self.allocator(), "arith_slow{d}", .{id});
    const done = try std.fmt.allocPrint(self.allocator(), "arith_done{d}", .{id});

    try emitBothFixnumBranch(self, a, b, fast, slow);

    try self.startBlock(fast);
    const va = try emitUnboxFixnum(self, a);
    const vb = try emitUnboxFixnum(self, b);
    const ov = try self.freshTemp();
    try self.print("  {s} = call {{ i64, i1 }} {s}(i64 {s}, i64 {s})\n", .{ ov, op.overflowIntrinsic(), va, vb });
    const raw = try self.freshTemp();
    try self.print("  {s} = extractvalue {{ i64, i1 }} {s}, 0\n", .{ raw, ov });
    const ovf = try self.freshTemp();
    try self.print("  {s} = extractvalue {{ i64, i1 }} {s}, 1\n", .{ ovf, ov });
    const ge = try self.freshTemp();
    try self.print("  {s} = icmp sge i64 {s}, {d}\n", .{ ge, raw, nanbox.fix_min });
    const le = try self.freshTemp();
    try self.print("  {s} = icmp sle i64 {s}, {d}\n", .{ le, raw, nanbox.fix_max });
    const in_range = try self.freshTemp();
    try self.print("  {s} = and i1 {s}, {s}\n", .{ in_range, ge, le });
    const not_ovf = try self.freshTemp();
    try self.print("  {s} = xor i1 {s}, true\n", .{ not_ovf, ovf });
    const ok = try self.freshTemp();
    try self.print("  {s} = and i1 {s}, {s}\n", .{ ok, in_range, not_ovf });
    try self.print("  br i1 {s}, label %{s}, label %{s}\n", .{ ok, box, slow });

    try self.startBlock(box);
    const masked = try self.freshTemp();
    try self.print("  {s} = and i64 {s}, {d}\n", .{ masked, raw, nanbox.payload_mask });
    const boxed = try self.freshTemp();
    try self.print("  {s} = or i64 {s}, {d}\n", .{ boxed, masked, nanbox.fix_base });
    try self.print("  br label %{s}\n", .{done});

    try self.startBlock(slow);
    const slow_res = try self.freshTemp();
    try self.print("  {s} = call i64 @{s}(i64 {s}, i64 {s})\n", .{ slow_res, export_name, a, b });
    try self.print("  br label %{s}\n", .{done});

    try self.startBlock(done);
    const result = try self.freshTemp();
    try self.print("  {s} = phi i64 [ {s}, %{s} ], [ {s}, %{s} ]\n", .{ result, boxed, box, slow_res, slow });
    return result;
}

// Fixnum fast path for < and =. Non-fixnum operands fall back to the
// runtime, which handles the full numeric tower.
fn emitInlineCompare(self: *LLVMEmitter, kind: CompareKind, a: []const u8, b: []const u8, export_name: []const u8) EmitError![]const u8 {
    const id = self.label_counter;
    self.label_counter += 1;
    const fast = try std.fmt.allocPrint(self.allocator(), "cmp_fast{d}", .{id});
    const slow = try std.fmt.allocPrint(self.allocator(), "cmp_slow{d}", .{id});
    const done = try std.fmt.allocPrint(self.allocator(), "cmp_done{d}", .{id});

    try emitBothFixnumBranch(self, a, b, fast, slow);

    try self.startBlock(fast);
    const cond = try self.freshTemp();
    switch (kind) {
        // Fixnums have a canonical encoding, so equal integers have equal
        // bits — the raw compare matches the runtime's `a == b`.
        .eq => try self.print("  {s} = icmp eq i64 {s}, {s}\n", .{ cond, a, b }),
        // Ordering needs the sign-extended payloads (raw compare would
        // mis-order negatives).
        .lt => {
            const va = try emitUnboxFixnum(self, a);
            const vb = try emitUnboxFixnum(self, b);
            try self.print("  {s} = icmp slt i64 {s}, {s}\n", .{ cond, va, vb });
        },
    }
    const fast_res = try self.freshTemp();
    try self.print("  {s} = select i1 {s}, i64 {d}, i64 {d}\n", .{ fast_res, cond, nanbox.true_val, nanbox.false_val });
    try self.print("  br label %{s}\n", .{done});

    try self.startBlock(slow);
    const slow_res = try self.freshTemp();
    try self.print("  {s} = call i64 @{s}(i64 {s}, i64 {s})\n", .{ slow_res, export_name, a, b });
    try self.print("  br label %{s}\n", .{done});

    try self.startBlock(done);
    const result = try self.freshTemp();
    try self.print("  {s} = phi i64 [ {s}, %{s} ], [ {s}, %{s} ]\n", .{ result, fast_res, fast, slow_res, slow });
    return result;
}

// null? — a single comparison against the nil immediate, no heap access.
fn emitInlineNullCheck(self: *LLVMEmitter, v: []const u8) EmitError![]const u8 {
    const cond = try self.freshTemp();
    try self.print("  {s} = icmp eq i64 {s}, {d}\n", .{ cond, v, nanbox.nil });
    const result = try self.freshTemp();
    try self.print("  {s} = select i1 {s}, i64 {d}, i64 {d}\n", .{ result, cond, nanbox.true_val, nanbox.false_val });
    return result;
}
