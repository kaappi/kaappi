const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const reader_mod = @import("reader.zig");
const Value = types.Value;

/// Numeric vectors store multi-byte elements in host-native byte order --
/// there's no reader syntax to round-trip and no cross-process persistence
/// (bytecode serialization is out of scope, see docs/dev/srfi-exclusions
/// equivalent notes), so native order avoids needless byte-swaps on
/// big-endian hosts (s390x, ppc64le) for zero portability cost.
const native_endian = builtin.cpu.arch.endian();

pub const PrintMode = enum {
    write, // machine-readable, strings quoted
    display, // human-readable, strings unquoted
    shared, // write with datum labels for shared/circular structures
};

/// REPL pretty-printer (moved out under the 1500-line policy; re-exported so
/// callers keep the `printer.prettyPrint` spelling).
pub const prettyPrint = @import("printer_pretty.zig").prettyPrint;

// ---------------------------------------------------------------------------
// Structural traversal
// ---------------------------------------------------------------------------
//
// The printer recurses into exactly SEVEN heap containers. Cycle/sharing
// detection and the print engine below both enumerate children through
// `childAt`, so the two can never disagree about which edges exist -- a
// container the printer walked but detection did not is exactly the
// four-procedure hang of kaappi#1954 (error-object irritants, mutex and
// condition-variable names were printed recursively but invisible to the
// pre-pass, so a cycle through them was never labelled).
//
// `.rational` is deliberately NOT here: its numerator/denominator are always
// exact integers (fixnum or bignum), so the `.rational` print arm renders
// them inline as atoms. That also removes the depth seam that made a
// rational at bounded-printer depth 1023 render as `.../...` -- a legal
// symbol datum with the wrong value (kaappi#1953).
//
// `.hash_table` holds Values but prints only its size, so it has no print
// edges and does not belong here either.

fn isTraversable(obj: *types.Object) bool {
    return switch (obj.tag) {
        .pair, .vector, .record_instance, .error_object, .multiple_values, .mutex, .condition_variable => true,
        else => false,
    };
}

/// Child Values of a traversable container in print order; null past the end.
fn childAt(v: Value, obj: *types.Object, idx: usize) ?Value {
    switch (obj.tag) {
        .pair => return switch (idx) {
            0 => types.car(v),
            1 => types.cdr(v),
            else => null,
        },
        .vector => {
            const data = obj.as(types.Vector).data;
            return if (idx < data.len) data[idx] else null;
        },
        .record_instance => {
            const fields = obj.as(types.RecordInstance).fields;
            return if (idx < fields.len) fields[idx] else null;
        },
        .error_object => {
            const eo = obj.as(types.ErrorObject);
            return switch (idx) {
                0 => eo.message,
                1 => eo.irritants,
                else => null,
            };
        },
        .multiple_values => {
            const vals = obj.as(types.MultipleValues).values;
            return if (idx < vals.len) vals[idx] else null;
        },
        .mutex => return if (idx == 0) obj.as(types.Mutex).name else null,
        .condition_variable => return if (idx == 0) obj.as(types.ConditionVariable).name else null,
        else => return null,
    }
}

// ---------------------------------------------------------------------------
// Label detection (cycles for write/display, all sharing for write-shared)
// ---------------------------------------------------------------------------

/// Values that need a datum label, mapped to their assigned label number.
/// Detection stores -1; the print engine assigns numbers lazily in print
/// order, so label numbering is independent of traversal order.
const Labels = struct {
    map: std.AutoHashMap(Value, i32),
    next: i32 = 0,

    fn init(allocator: std.mem.Allocator) Labels {
        return .{ .map = std.AutoHashMap(Value, i32).init(allocator) };
    }
    fn deinit(self: *Labels) void {
        self.map.deinit();
    }
};

/// Record every back-edge target of a DFS from `root` -- the objects that
/// close a cycle. Only those need datum labels for `write`/`display` to
/// terminate; acyclic sharing prints in full per R7RS ("Datum labels must
/// not be used if there are no cycles").
///
/// Fully iterative: the DFS stack, visited sets and result all live on the
/// heap, so detection has no depth limit and uses no native stack -- the
/// depth-848 wasm32 module abort of kaappi#2107 and the depth-1024 label
/// loss of kaappi#1902 (D4) were both artifacts of the old native-stack
/// recursion and its MAX_PRINT_DEPTH guard.
fn findCycleTargets(allocator: std.mem.Allocator, root: Value, labels: *Labels) !void {
    if (!types.isPointer(root)) return;
    if (!isTraversable(types.toObject(root))) return;

    const Frame = struct { v: Value, idx: usize };
    var stack: std.ArrayList(Frame) = .empty;
    defer stack.deinit(allocator);
    var on_stack = std.AutoHashMap(Value, void).init(allocator);
    defer on_stack.deinit();
    var done = std.AutoHashMap(Value, void).init(allocator);
    defer done.deinit();

    try stack.append(allocator, .{ .v = root, .idx = 0 });
    try on_stack.put(root, {});

    while (stack.items.len > 0) {
        const top = stack.items.len - 1;
        const v = stack.items[top].v;
        const idx = stack.items[top].idx;
        const obj = types.toObject(v);
        if (childAt(v, obj, idx)) |child| {
            stack.items[top].idx = idx + 1;
            if (!types.isPointer(child)) continue;
            if (!isTraversable(types.toObject(child))) continue;
            if (on_stack.contains(child)) {
                try labels.map.put(child, -1);
            } else if (!done.contains(child)) {
                try on_stack.put(child, {});
                try stack.append(allocator, .{ .v = child, .idx = 0 });
            }
        } else {
            _ = stack.pop();
            _ = on_stack.remove(v);
            try done.put(v, {});
        }
    }
}

/// Record every traversable container encountered more than once from
/// `root` (write-shared). R7RS mandates labels for repeated pairs and
/// vectors; repeated instances of the other traversable containers are
/// labelled too -- they print as unreadable `#<...>` forms either way, and
/// a cycle whose revisited node is one of them must carry the label for
/// printing to terminate.
///
/// Iterative worklist with hash sets: no capacity cap and no depth cap, so
/// none of kaappi#1902's three cliffs exist (D1: sharing across a >=1024
/// spine, D2: first occurrence past 1024 distinct nodes, D3: >1023 labels).
fn findSharedNodes(allocator: std.mem.Allocator, root: Value, labels: *Labels) !void {
    if (!types.isPointer(root)) return;
    if (!isTraversable(types.toObject(root))) return;

    var seen = std.AutoHashMap(Value, void).init(allocator);
    defer seen.deinit();
    var work: std.ArrayList(Value) = .empty;
    defer work.deinit(allocator);

    try work.append(allocator, root);
    while (work.pop()) |v| {
        if (!types.isPointer(v)) continue;
        const obj = types.toObject(v);
        if (!isTraversable(obj)) continue;
        const gop = try seen.getOrPut(v);
        if (gop.found_existing) {
            // Second encounter: needs a label; children were already queued
            // the first time.
            try labels.map.put(v, -1);
            continue;
        }
        if (obj.tag == .pair) {
            // cdr first, car second: the car pops first and drains before the
            // spine advances, so a flat list keeps the worklist O(1) deep.
            try work.append(allocator, types.cdr(v));
            try work.append(allocator, types.car(v));
        } else {
            var i: usize = 0;
            while (childAt(v, obj, i)) |child| : (i += 1) {
                try work.append(allocator, child);
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Iterative print engine
// ---------------------------------------------------------------------------

/// Depth budget for the exact printer: effectively none. Structural nesting
/// (and spine length, which also ticks the counter) cannot reach 2^32 on any
/// real heap, so `write`/`display`/`write-shared` output is never truncated
/// -- truncated-but-successful output was kaappi#1902, and the truncation
/// sentinel reading back as a symbol was kaappi#1953.
const NO_DEPTH_LIMIT: u32 = std.math.maxInt(u32);

/// Depth cap for the bounded DIAGNOSTIC printer (`printValue`): compiler
/// diagnostics and the REPL pretty-printer's layout probes, whose output is
/// human-facing and never re-read. Bounded output uses the `...` sentinel.
pub const MAX_PRINT_DEPTH: u32 = 1024;

const PrintTask = union(enum) {
    /// Print one value (label-aware).
    value: ValDepth,
    /// Emit literal text (static lifetime).
    text: []const u8,
    /// Inside an open '(': print the rest of a list from this tail.
    list_tail: ValDepth,
    /// Inside an open "#<error ...": print remaining irritants, then '>'.
    irritants_tail: ValDepth,
    /// Elements of a vector / record instance / multiple-values from `idx`.
    seq: Seq,
};
const ValDepth = struct { v: Value, depth: u32 };
const Seq = struct { v: Value, idx: usize, depth: u32 };

fn labelPending(labels: ?*Labels, v: Value) bool {
    const lbl = labels orelse return false;
    return lbl.map.contains(v);
}

/// The single print loop behind every mode. Fully iterative -- the work
/// stack lives on the heap, so printing consumes no native stack regardless
/// of nesting depth (kaappi#2107: 848 frames of the old recursion exhausted
/// the wasm32 shadow stack before the old depth guard could fire).
///
/// `labels` non-null makes it label-aware (datum labels assigned lazily in
/// print order). With `max_depth` == NO_DEPTH_LIMIT output is exact at any
/// depth; a real cap (diagnostic printer) truncates values with `...`, and
/// counts spine elements toward the cap so even an UNlabelled cyclic list
/// terminates -- the old spine walk had no such tick, which is why a cycle
/// reached through a container detection didn't cover hung forever
/// (kaappi#1954) instead of truncating.
fn printStructured(
    allocator: std.mem.Allocator,
    writer: anytype,
    root: Value,
    mode: PrintMode,
    labels: ?*Labels,
    max_depth: u32,
) anyerror!void {
    var tasks: std.ArrayList(PrintTask) = .empty;
    defer tasks.deinit(allocator);
    try tasks.append(allocator, .{ .value = .{ .v = root, .depth = 0 } });

    while (tasks.pop()) |task| {
        switch (task) {
            .text => |s| try writer.writeAll(s),
            .value => |vd| {
                if (labels) |lbl| {
                    if (types.isPointer(vd.v)) {
                        if (lbl.map.getPtr(vd.v)) |slot| {
                            if (slot.* >= 0) {
                                // Later occurrence -- emit back-reference #N#.
                                try writer.print("#{d}#", .{slot.*});
                                continue;
                            }
                            // First occurrence -- assign a label, emit #N=,
                            // and fall through to print the value itself.
                            slot.* = lbl.next;
                            lbl.next += 1;
                            try writer.print("#{d}=", .{slot.*});
                        }
                    }
                }
                if (vd.depth >= max_depth) {
                    try writer.writeAll("...");
                    continue;
                }
                try printValueOnce(allocator, writer, vd.v, vd.depth, mode, &tasks);
            },
            .list_tail => |vd| {
                const t = vd.v;
                if (t == types.NIL) {
                    try writer.writeByte(')');
                    continue;
                }
                if (vd.depth >= max_depth) {
                    try writer.writeAll(" ...)");
                    continue;
                }
                if (types.isPair(t) and !labelPending(labels, t)) {
                    try writer.writeByte(' ');
                    try tasks.append(allocator, .{ .list_tail = .{ .v = types.cdr(t), .depth = vd.depth + 1 } });
                    try tasks.append(allocator, .{ .value = .{ .v = types.car(t), .depth = vd.depth } });
                } else {
                    // Dotted tail: either a non-pair, or a labelled pair that
                    // must restart as ". #N=(..." / ". #N#".
                    try writer.writeAll(" . ");
                    try tasks.append(allocator, .{ .text = ")" });
                    try tasks.append(allocator, .{ .value = .{ .v = t, .depth = vd.depth } });
                }
            },
            .irritants_tail => |vd| {
                const t = vd.v;
                if (t == types.NIL) {
                    try writer.writeByte('>');
                    continue;
                }
                if (vd.depth >= max_depth) {
                    try writer.writeAll(" ...>");
                    continue;
                }
                if (types.isPair(t) and !labelPending(labels, t)) {
                    try writer.writeByte(' ');
                    try tasks.append(allocator, .{ .irritants_tail = .{ .v = types.cdr(t), .depth = vd.depth + 1 } });
                    try tasks.append(allocator, .{ .value = .{ .v = types.car(t), .depth = vd.depth } });
                } else if (types.isPair(t)) {
                    // A labelled irritants tail restarts as a fresh datum;
                    // mark it dotted so the spine break is visible.
                    try writer.writeAll(" . ");
                    try tasks.append(allocator, .{ .text = ">" });
                    try tasks.append(allocator, .{ .value = .{ .v = t, .depth = vd.depth } });
                } else {
                    // Improper irritants tail prints like one more irritant.
                    try writer.writeByte(' ');
                    try tasks.append(allocator, .{ .text = ">" });
                    try tasks.append(allocator, .{ .value = .{ .v = t, .depth = vd.depth } });
                }
            },
            .seq => |sq| {
                const obj = types.toObject(sq.v);
                switch (obj.tag) {
                    .vector => {
                        const data = obj.as(types.Vector).data;
                        if (sq.idx >= data.len) {
                            try writer.writeByte(')');
                        } else {
                            if (sq.idx > 0) try writer.writeByte(' ');
                            try tasks.append(allocator, .{ .seq = .{ .v = sq.v, .idx = sq.idx + 1, .depth = sq.depth } });
                            try tasks.append(allocator, .{ .value = .{ .v = data[sq.idx], .depth = sq.depth } });
                        }
                    },
                    .record_instance => {
                        const fields = obj.as(types.RecordInstance).fields;
                        if (sq.idx >= fields.len) {
                            try writer.writeByte('>');
                        } else {
                            try writer.writeByte(' ');
                            try tasks.append(allocator, .{ .seq = .{ .v = sq.v, .idx = sq.idx + 1, .depth = sq.depth } });
                            try tasks.append(allocator, .{ .value = .{ .v = fields[sq.idx], .depth = sq.depth } });
                        }
                    },
                    .multiple_values => {
                        const vals = obj.as(types.MultipleValues).values;
                        if (sq.idx >= vals.len) {
                            try writer.writeByte('>');
                        } else {
                            try writer.writeByte(' ');
                            try tasks.append(allocator, .{ .seq = .{ .v = sq.v, .idx = sq.idx + 1, .depth = sq.depth } });
                            try tasks.append(allocator, .{ .value = .{ .v = vals[sq.idx], .depth = sq.depth } });
                        }
                    },
                    else => unreachable,
                }
            },
        }
    }
}

/// Numerator/denominator of a rational -- always an exact integer.
fn writeExactIntPart(writer: anytype, v: Value) anyerror!void {
    if (types.isFixnum(v)) {
        try writer.print("{d}", .{types.toFixnum(v)});
        return;
    }
    if (types.isPointer(v) and types.toObject(v).tag == .bignum) {
        try writeBignum(writer, v);
        return;
    }
    try writer.writeAll("#<unknown>");
}

fn writeBignum(writer: anytype, v: Value) anyerror!void {
    const bignum_mod = @import("bignum.zig");
    const allocator = std.heap.page_allocator;
    const s = bignum_mod.toString(allocator, v) catch {
        try writer.writeAll("?bignum?");
        return;
    };
    defer allocator.free(s);
    try writer.writeAll(s);
}

/// Emit one value's own rendering. Containers write their opening text and
/// push continuation tasks; everything else is a leaf written in full.
fn printValueOnce(
    allocator: std.mem.Allocator,
    writer: anytype,
    value: Value,
    depth: u32,
    mode: PrintMode,
    tasks: *std.ArrayList(PrintTask),
) anyerror!void {
    if (types.isFixnum(value)) {
        try writer.print("{d}", .{types.toFixnum(value)});
    } else if (value == types.NIL) {
        try writer.writeAll("()");
    } else if (value == types.TRUE) {
        try writer.writeAll("#t");
    } else if (value == types.FALSE) {
        try writer.writeAll("#f");
    } else if (value == types.VOID) {
        // void prints nothing
    } else if (value == types.EOF) {
        try writer.writeAll("#<eof>");
    } else if (value == types.UNDEFINED) {
        try writer.writeAll("#<undefined>");
    } else if (types.isChar(value)) {
        const cp = types.toChar(value);
        if (mode == .write) {
            try writer.writeAll("#\\");
            switch (cp) {
                0x00 => try writer.writeAll("null"),
                0x07 => try writer.writeAll("alarm"),
                0x08 => try writer.writeAll("backspace"),
                0x09 => try writer.writeAll("tab"),
                0x0A => try writer.writeAll("newline"),
                0x0D => try writer.writeAll("return"),
                0x1B => try writer.writeAll("escape"),
                0x20 => try writer.writeAll("space"),
                0x7F => try writer.writeAll("delete"),
                else => {
                    if (cp < 0x20 or (cp >= 0x7F and cp <= 0x9F)) {
                        var hex_buf: [8]u8 = undefined;
                        var hw: std.Io.Writer = .fixed(&hex_buf);
                        hw.print("x{x}", .{cp}) catch {};
                        try writer.writeAll(hw.buffered());
                    } else {
                        var buf: [4]u8 = undefined;
                        const len = std.unicode.utf8Encode(cp, &buf) catch 0;
                        try writer.writeAll(buf[0..len]);
                    }
                },
            }
        } else {
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(cp, &buf) catch 0;
            try writer.writeAll(buf[0..len]);
        }
    } else if (types.isFlonum(value)) {
        var buf: [64]u8 = undefined;
        try writer.writeAll(formatFlonum(&buf, types.toFlonum(value)));
    } else if (types.isPointer(value)) {
        const obj = types.toObject(value);
        switch (obj.tag) {
            .pair => {
                try writer.writeByte('(');
                try tasks.append(allocator, .{ .list_tail = .{ .v = types.cdr(value), .depth = depth + 1 } });
                try tasks.append(allocator, .{ .value = .{ .v = types.car(value), .depth = depth + 1 } });
            },
            .symbol => {
                const sym = obj.as(types.Symbol);
                if (!sym.interned and mode != .display) {
                    // SRFI 258: an uninterned symbol has no readable external
                    // representation. Writing it in this `#<…>` form makes
                    // `read` reject it (the reader errors on `#<`), deliberately
                    // breaking write/read invariance (R7RS 6.5). `display` still
                    // shows the bare name for human-readable output.
                    try writer.writeAll("#<uninterned-symbol ");
                    try writer.writeAll(sym.name);
                    try writer.writeByte('>');
                } else if (mode != .display and symbolNeedsBars(sym.name)) {
                    try writer.writeByte('|');
                    for (sym.name) |c| {
                        if (c == '|' or c == '\\') {
                            try writer.writeByte('\\');
                            try writer.writeByte(c);
                        } else if (c < 0x20 or c == 0x7F) {
                            try writer.writeAll("\\x");
                            const hex = "0123456789abcdef";
                            try writer.writeByte(hex[c >> 4]);
                            try writer.writeByte(hex[c & 0x0F]);
                            try writer.writeByte(';');
                        } else {
                            try writer.writeByte(c);
                        }
                    }
                    try writer.writeByte('|');
                } else {
                    try writer.writeAll(sym.name);
                }
            },
            .string => {
                const str = obj.as(types.SchemeString);
                if (mode == .write) {
                    try writer.writeByte('"');
                    for (str.data) |c| {
                        switch (c) {
                            '"' => try writer.writeAll("\\\""),
                            '\\' => try writer.writeAll("\\\\"),
                            '\n' => try writer.writeAll("\\n"),
                            '\r' => try writer.writeAll("\\r"),
                            '\t' => try writer.writeAll("\\t"),
                            0x07 => try writer.writeAll("\\a"),
                            0x08 => try writer.writeAll("\\b"),
                            else => {
                                if (c < 0x20 or c == 0x7F) {
                                    try writer.writeAll("\\x");
                                    const hex = "0123456789abcdef";
                                    try writer.writeByte(hex[c >> 4]);
                                    try writer.writeByte(hex[c & 0x0F]);
                                    try writer.writeByte(';');
                                } else {
                                    try writer.writeByte(c);
                                }
                            },
                        }
                    }
                    try writer.writeByte('"');
                } else {
                    try writer.writeAll(str.data);
                }
            },
            .flonum => {
                const flo = obj.as(types.Flonum);
                var buf: [64]u8 = undefined;
                try writer.writeAll(formatFlonum(&buf, flo.value));
            },
            .closure => {
                const cls = obj.as(types.Closure);
                if (cls.func.name) |name| {
                    try writer.print("#<procedure {s}>", .{name});
                } else {
                    try writer.writeAll("#<procedure>");
                }
            },
            .native_fn => {
                const nf = obj.as(types.NativeFn);
                try writer.print("#<builtin {s}>", .{nf.name});
            },
            .native_closure => {
                // A native closure is the LLVM backend's representation of a
                // Scheme procedure; print it exactly like an interpreter closure
                // so native output matches the interpreter (#1500). Native
                // closures never exist in interpreter mode, so this only affects
                // native binaries — where a define'd function's value is now a
                // native closure rather than an eval'd interpreter closure.
                const nc = obj.as(types.NativeClosure);
                try writer.print("#<procedure {s}>", .{nc.name});
            },
            .function => {
                try writer.writeAll("#<function>");
            },
            .transformer => {
                try writer.writeAll("#<transformer>");
            },
            .error_object => {
                const eo = obj.as(types.ErrorObject);
                try writer.writeAll("#<error ");
                try tasks.append(allocator, .{ .irritants_tail = .{ .v = eo.irritants, .depth = depth + 1 } });
                try tasks.append(allocator, .{ .value = .{ .v = eo.message, .depth = depth + 1 } });
            },
            .port => {
                const port = obj.as(types.Port);
                if (port.is_input and port.is_output) {
                    try writer.print("#<input/output-port {s}>", .{port.name});
                } else if (port.is_input) {
                    try writer.print("#<input-port {s}>", .{port.name});
                } else {
                    try writer.print("#<output-port {s}>", .{port.name});
                }
            },
            .record_type => {
                const rt = obj.as(types.RecordType);
                try writer.print("#<record-type {s}>", .{rt.name});
            },
            .record_instance => {
                const ri = obj.as(types.RecordInstance);
                try writer.print("#<{s}", .{ri.record_type.name});
                try tasks.append(allocator, .{ .seq = .{ .v = value, .idx = 0, .depth = depth + 1 } });
            },
            .complex => {
                const c = obj.as(types.Complex);
                var buf: [64]u8 = undefined;
                if (c.imag == 0.0 and !std.math.signbit(c.imag)) {
                    try writer.writeAll(formatFlonum(&buf, c.real));
                } else {
                    const has_real = c.real != 0.0 or std.math.signbit(c.real);
                    if (has_real) try writeComplexPart(writer, c.real, c.exact_real);
                    const im = c.imag;
                    if (std.math.isNan(im)) {
                        try writer.writeAll("+nan.0i");
                    } else if (std.math.isInf(im)) {
                        try writer.writeAll(if (im > 0) "+inf.0i" else "-inf.0i");
                    } else {
                        try writer.writeByte(if (im < 0 or std.math.signbit(im)) '-' else '+');
                        const mag = @abs(im);
                        if (mag != 1.0 or has_real) try writeComplexPart(writer, mag, c.exact_imag);
                        try writer.writeByte('i');
                    }
                }
            },
            .vector => {
                try writer.writeAll("#(");
                try tasks.append(allocator, .{ .seq = .{ .v = value, .idx = 0, .depth = depth + 1 } });
            },
            .bytevector => {
                const bv = obj.as(types.Bytevector);
                try writer.writeAll("#u8(");
                for (bv.data, 0..) |byte, i| {
                    if (i > 0) try writer.writeByte(' ');
                    try writer.print("{d}", .{byte});
                }
                try writer.writeByte(')');
            },
            .numeric_vector => {
                const nv = obj.as(types.NumericVector);
                try writer.print("#<{s}vector", .{@tagName(nv.kind)});
                const width = nv.kind.elementWidth();
                var buf: [64]u8 = undefined;
                var i: usize = 0;
                while (i < nv.data.len) : (i += width) {
                    try writer.writeByte(' ');
                    switch (nv.kind) {
                        .s8 => try writer.print("{d}", .{@as(i8, @bitCast(nv.data[i]))}),
                        .u16 => try writer.print("{d}", .{std.mem.readInt(u16, nv.data[i..][0..2], native_endian)}),
                        .s16 => try writer.print("{d}", .{std.mem.readInt(i16, nv.data[i..][0..2], native_endian)}),
                        .u32 => try writer.print("{d}", .{std.mem.readInt(u32, nv.data[i..][0..4], native_endian)}),
                        .s32 => try writer.print("{d}", .{std.mem.readInt(i32, nv.data[i..][0..4], native_endian)}),
                        .u64 => try writer.print("{d}", .{std.mem.readInt(u64, nv.data[i..][0..8], native_endian)}),
                        .s64 => try writer.print("{d}", .{std.mem.readInt(i64, nv.data[i..][0..8], native_endian)}),
                        .f32 => {
                            const bits = std.mem.readInt(u32, nv.data[i..][0..4], native_endian);
                            try writer.writeAll(formatFlonum(&buf, @as(f32, @bitCast(bits))));
                        },
                        .f64 => {
                            const bits = std.mem.readInt(u64, nv.data[i..][0..8], native_endian);
                            try writer.writeAll(formatFlonum(&buf, @as(f64, @bitCast(bits))));
                        },
                        .c64 => {
                            const re_bits = std.mem.readInt(u32, nv.data[i..][0..4], native_endian);
                            const im_bits = std.mem.readInt(u32, nv.data[i + 4 ..][0..4], native_endian);
                            const im: f32 = @bitCast(im_bits);
                            try writer.writeAll(formatFlonum(&buf, @as(f32, @bitCast(re_bits))));
                            try writeImaginaryPart(writer, &buf, im);
                        },
                        .c128 => {
                            const re_bits = std.mem.readInt(u64, nv.data[i..][0..8], native_endian);
                            const im_bits = std.mem.readInt(u64, nv.data[i + 8 ..][0..8], native_endian);
                            const im: f64 = @bitCast(im_bits);
                            try writer.writeAll(formatFlonum(&buf, @as(f64, @bitCast(re_bits))));
                            try writeImaginaryPart(writer, &buf, im);
                        },
                    }
                }
                try writer.writeByte('>');
            },
            .promise => {
                try writer.writeAll("#<promise>");
            },
            .continuation => {
                try writer.writeAll("#<continuation>");
            },
            .parameter => {
                try writer.writeAll("#<parameter>");
            },
            .multiple_values => {
                try writer.writeAll("#<values");
                try tasks.append(allocator, .{ .seq = .{ .v = value, .idx = 0, .depth = depth + 1 } });
            },
            .hash_table => {
                const ht = obj.as(types.HashTable);
                try writer.print("#<hash-table size={d}>", .{ht.count});
            },
            .ffi_library => {
                const lib = obj.as(types.FfiLibrary);
                try writer.print("#<ffi-library \"{s}\">", .{lib.name});
            },
            .ffi_function => {
                const ffi_fn = obj.as(types.FfiFunction);
                try writer.print("#<ffi-function \"{s}\">", .{ffi_fn.name});
            },
            .ffi_callback => {
                const cb = obj.as(types.FfiCallback);
                if (cb.active) {
                    try writer.print("#<ffi-callback slot={d}>", .{cb.slot_index});
                } else {
                    try writer.writeAll("#<ffi-callback released>");
                }
            },
            .fiber => {
                const fiber_mod = @import("fiber.zig");
                const fiber = obj.as(fiber_mod.Fiber);
                const status_str: []const u8 = switch (fiber.status) {
                    .created => "created",
                    .running => "running",
                    .suspended => "suspended",
                    .completed => "completed",
                    .errored => "errored",
                    .waiting => "waiting",
                    .io_waiting => "io-waiting",
                };
                try writer.print("#<fiber {d} {s}>", .{ fiber.id, status_str });
            },
            .channel => {
                try writer.writeAll("#<channel>");
            },
            .mutex => {
                const m = obj.as(types.Mutex);
                try writer.writeAll("#<mutex");
                if (m.name != types.VOID) {
                    try writer.writeAll(" ");
                    try tasks.append(allocator, .{ .text = ">" });
                    try tasks.append(allocator, .{ .value = .{ .v = m.name, .depth = depth + 1 } });
                } else {
                    try writer.writeAll(">");
                }
            },
            .condition_variable => {
                const cv = obj.as(types.ConditionVariable);
                try writer.writeAll("#<condition-variable");
                if (cv.name != types.VOID) {
                    try writer.writeAll(" ");
                    try tasks.append(allocator, .{ .text = ">" });
                    try tasks.append(allocator, .{ .value = .{ .v = cv.name, .depth = depth + 1 } });
                } else {
                    try writer.writeAll(">");
                }
            },
            .srfi18_time => {
                const t = obj.as(types.Srfi18Time);
                const type_name: []const u8 = switch (t.time_type) {
                    .utc => "time-utc",
                    .tai => "time-tai",
                    .monotonic => "time-monotonic",
                    .duration => "time-duration",
                };
                const ns: u64 = if (t.nanoseconds >= 0) @intCast(t.nanoseconds) else 0;
                try writer.print("#<time {s} {d}.{d:0>9}>", .{ type_name, t.seconds, ns });
            },
            .bignum => {
                try writeBignum(writer, value);
            },
            .rational => {
                // Rendered atomically: both parts are always exact integers,
                // so no depth accounting can split this leaf into the
                // symbol-shaped `.../...` of kaappi#1953.
                const rat = obj.as(types.Rational);
                try writeExactIntPart(writer, rat.numerator);
                try writer.writeByte('/');
                try writeExactIntPart(writer, rat.denominator);
            },
            .file_info => {
                const fi = obj.as(types.FileInfo);
                const kind = switch (fi.file_type) {
                    .regular => "regular",
                    .directory => "directory",
                    .symlink => "symlink",
                    .fifo => "fifo",
                    .socket => "socket",
                    .char_device => "char-device",
                    .block_device => "block-device",
                    .other => "other",
                };
                try writer.print("#<file-info {s} size={d} mode={o}>", .{ kind, fi.size, fi.mode });
            },
            .user_info => {
                const ui = obj.as(types.UserInfo);
                try writer.print("#<user-info \"{s}\" uid={d}>", .{ ui.name, ui.uid });
            },
            .group_info => {
                const gi = obj.as(types.GroupInfo);
                try writer.print("#<group-info \"{s}\" gid={d}>", .{ gi.name, gi.gid });
            },
            .directory_object => {
                try writer.writeAll("#<directory-object>");
            },
            .random_source => {
                try writer.writeAll("#<random-source>");
            },
            .scheme_environment => {
                try writer.writeAll("#<environment>");
            },
            .ephemeron => {
                const eph = obj.as(types.Ephemeron);
                try writer.writeAll(if (eph.broken) "#<ephemeron broken>" else "#<ephemeron>");
            },
            .guardian => {
                const g = obj.as(types.Guardian);
                try writer.writeAll(if (g.is_transport) "#<transport-cell-guardian>" else "#<guardian>");
            },
            .transport_cell => {
                const tc = obj.as(types.TransportCell);
                try writer.writeAll(if (tc.broken) "#<transport-cell broken>" else "#<transport-cell>");
            },
        }
    } else {
        try writer.writeAll("#<unknown>");
    }
}

// ---------------------------------------------------------------------------
// Atom helpers (shared by the engine and the numeric printers)
// ---------------------------------------------------------------------------

fn startsWithIgnoreCase(s: []const u8, prefix: []const u8) bool {
    return s.len >= prefix.len and std.ascii.eqlIgnoreCase(s[0..prefix.len], prefix);
}

/// Whether a symbol must be written with `|...|` bars so it reads back as the
/// same symbol: empty names, a lone `.`, names containing delimiters/special
/// characters, and names that would otherwise read as a number.
fn symbolNeedsBars(name: []const u8) bool {
    if (name.len == 0) return true;
    var i: usize = 0;
    while (i < name.len) {
        const c = name[i];
        switch (c) {
            0...' ', 0x7F, '(', ')', '[', ']', '{', '}', '"', ';', '|', '\\', '\'', '`', ',', '#' => return true,
            0x80...0xFF => {
                const seq_len = std.unicode.utf8ByteSequenceLength(c) catch return true;
                if (i + seq_len > name.len) return true;
                const cp = std.unicode.utf8Decode(name[i..][0..seq_len]) catch return true;
                if (cp >= 0x80 and cp <= 0x9F) return true;
                if (!reader_mod.Reader.isUnicodeLetter(cp)) return true;
                i += seq_len;
                continue;
            },
            else => {},
        }
        i += 1;
    }
    if (name.len == 1 and name[0] == '.') return true;

    const c0 = name[0];
    if (std.ascii.isDigit(c0)) return true;
    if (c0 == '+' or c0 == '-') {
        if (name.len == 1) return false; // bare + / - are identifiers
        const c1 = name[1];
        if (std.ascii.isDigit(c1)) return true;
        if (c1 == '.' and name.len > 2 and std.ascii.isDigit(name[2])) return true;
        const rest = name[1..];
        if (std.ascii.eqlIgnoreCase(rest, "i")) return true;
        if (startsWithIgnoreCase(rest, "inf.0") or startsWithIgnoreCase(rest, "nan.0")) return true;
        return false;
    }
    if (c0 == '.' and name.len > 1 and std.ascii.isDigit(name[1])) return true;
    return false;
}

/// Write the exact decimal digits of `mantissa << shift` (unsigned). Any
/// finite f64 decomposes into such a pair (mantissa < 2^53, shift <= 971 for
/// integers; 2^k denominators use mantissa 1, k <= 1074), so this covers up
/// to ~325 digits -- far past any fixed format buffer, which is why exact
/// complex parts beyond i64 used to print as the unreadable `0/0` (#1910).
fn writeBigPowerOfTwoDecimal(writer: anytype, mantissa: u64, shift: u16) !void {
    // Callers pass f64 decompositions: mantissa < 2^53 with shift <= 971
    // (integers), or mantissa 1 with shift <= 1074 (2^k denominators).
    // 20 digits of u64 + 1100 doublings adding at most one digit each
    // stays under 360.
    var digits: [360]u8 = undefined; // little-endian, values 0..9
    var len: usize = 0;
    var m = mantissa;
    while (m > 0) : (m /= 10) {
        digits[len] = @intCast(m % 10);
        len += 1;
    }
    if (len == 0) {
        digits[0] = 0;
        len = 1;
    }
    var i: u16 = 0;
    while (i < shift) : (i += 1) {
        var carry: u8 = 0;
        for (digits[0..len]) |*d| {
            const v = d.* * 2 + carry;
            d.* = v % 10;
            carry = v / 10;
        }
        if (carry > 0 and len < digits.len) {
            digits[len] = carry;
            len += 1;
        }
    }
    var out: [360]u8 = undefined;
    for (0..len) |j| out[j] = '0' + digits[len - 1 - j];
    try writer.writeAll(out[0..len]);
}

/// Write one part of a complex number. Inexact parts print as flonums. An
/// exact-flagged part prints its exact value, never a value-destroying
/// collapse: plain integer digits when integral (bignum-wide past i64), the
/// small-rational form when it reproduces the f64 exactly, and the f64's own
/// mantissa/2^k value otherwise. The first two spellings read back with the
/// exact flag intact; the mantissa/2^k fallback is exact but does NOT read
/// back yet -- the reader's complex grammar stops at i64 rational parts
/// (kaappi#2182), and closing that needs the scaled rational->f64
/// conversion first or tiny components would read back as a silent 0.0
/// (kaappi#2183).
fn writeComplexPart(writer: anytype, f: f64, exact: bool) !void {
    var buf: [64]u8 = undefined;
    if (!exact or std.math.isNan(f) or std.math.isInf(f)) {
        try writer.writeAll(formatFlonum(&buf, f));
        return;
    }
    if (f == @trunc(f)) {
        // 2^63 spelled as a literal: maxInt(i64) is not representable as
        // f64 and @floatFromInt would round the bound up to admit 2^63
        // itself -- the exact off-by-one behind #1907's reader panic.
        if (f >= -9223372036854775808.0 and f < 9223372036854775808.0) {
            const i: i64 = @intFromFloat(f);
            try writer.writeAll(std.fmt.bufPrint(&buf, "{d}", .{i}) catch unreachable);
            return;
        }
        // Integral beyond i64: |f| >= 2^63 with a 53-bit mantissa forces a
        // strictly positive binary exponent.
        if (f < 0) try writer.writeByte('-');
        const bits: u64 = @bitCast(@abs(f));
        const mantissa = (bits & 0x000FFFFFFFFFFFFF) | 0x0010000000000000;
        const exp: u16 = @intCast(@as(i16, @intCast((bits >> 52) & 0x7FF)) - 1023 - 52);
        try writeBigPowerOfTwoDecimal(writer, mantissa, exp);
        return;
    }
    // Exact non-integer: prefer the small-rational spelling, but only when
    // it reads back to this exact f64 -- the search collapses magnitudes
    // below its granularity to 0/1, which silently destroys the value.
    const numeric = @import("primitives_numeric.zig");
    const rat = numeric.floatToRational(f);
    if (rat.den > 0 and
        @as(f64, @floatFromInt(rat.num)) / @as(f64, @floatFromInt(rat.den)) == f)
    {
        try writer.print("{d}/{d}", .{ rat.num, rat.den });
        return;
    }
    // Fall back to the f64's own exact value: odd-mantissa / 2^k.
    if (f < 0) try writer.writeByte('-');
    const bits: u64 = @bitCast(@abs(f));
    const raw_exp: u11 = @intCast((bits >> 52) & 0x7FF);
    var m: u64 = if (raw_exp == 0)
        bits & 0x000FFFFFFFFFFFFF
    else
        (bits & 0x000FFFFFFFFFFFFF) | 0x0010000000000000;
    var k: u16 = if (raw_exp == 0) 1074 else 1075 - @as(u16, raw_exp);
    while (m & 1 == 0 and k > 0) {
        m >>= 1;
        k -= 1;
    }
    try writeBigPowerOfTwoDecimal(writer, m, 0);
    try writer.writeByte('/');
    try writeBigPowerOfTwoDecimal(writer, 1, k);
}

pub fn formatFlonum(buf: []u8, f: f64) []const u8 {
    if (std.math.isNan(f)) return "+nan.0";
    if (std.math.isInf(f)) return if (f > 0) "+inf.0" else "-inf.0";

    const abs = @abs(f);
    const use_sci = abs != 0 and (abs < 1e-10 or abs >= 1e21);
    const s = if (use_sci)
        (std.fmt.bufPrint(buf, "{e}", .{f}) catch return "+nan.0")
    else
        (std.fmt.bufPrint(buf, "{d}", .{f}) catch
            (std.fmt.bufPrint(buf, "{e}", .{f}) catch return "+nan.0"));

    // Post-process scientific notation
    var has_dot = false;
    var e_pos: ?usize = null;
    for (s, 0..) |c, idx| {
        if (c == '.') has_dot = true;
        if (c == 'e' or c == 'E') e_pos = idx;
    }
    if (e_pos) |ep| {
        var result_len = s.len;
        // Insert '.0' before 'e' if no decimal point (e.g., 5e-324 -> 5.0e-324)
        if (!has_dot and result_len + 2 <= buf.len) {
            var j: usize = result_len + 1;
            while (j > ep + 1) {
                buf[j] = buf[j - 2];
                j -= 1;
            }
            buf[ep] = '.';
            buf[ep + 1] = '0';
            result_len += 2;
            // Update e_pos after insertion
            const new_ep = ep + 2;
            // Ensure positive exponents have '+' sign
            if (new_ep + 1 < result_len and buf[new_ep + 1] != '+' and buf[new_ep + 1] != '-') {
                if (result_len + 1 <= buf.len) {
                    j = result_len;
                    while (j > new_ep + 1) {
                        buf[j] = buf[j - 1];
                        j -= 1;
                    }
                    buf[new_ep + 1] = '+';
                    result_len += 1;
                }
            }
            return buf[0..result_len];
        }
        // Ensure positive exponents have '+' sign: e308 -> e+308
        if (ep + 1 < result_len and s[ep + 1] != '+' and s[ep + 1] != '-') {
            if (result_len + 1 <= buf.len) {
                var j: usize = result_len;
                while (j > ep + 1) {
                    buf[j] = buf[j - 1];
                    j -= 1;
                }
                buf[ep + 1] = '+';
                return buf[0 .. result_len + 1];
            }
        }
        return s;
    }
    for (s) |c| {
        if (c == '.') return s;
    }
    if (s.len + 2 <= buf.len) {
        buf[s.len] = '.';
        buf[s.len + 1] = '0';
        return buf[0 .. s.len + 2];
    }
    return s;
}

/// Write the `[+-]<magnitude>i` suffix for a numeric-vector c64/c128
/// element's imaginary part. Mirrors the `.complex` printer arm's own
/// NaN/Inf/signbit handling below -- unlike a standalone `Complex` Value,
/// a numeric-vector element is always inexact, so this always calls
/// `formatFlonum` directly rather than `formatComplexPart`.
fn writeImaginaryPart(writer: anytype, buf: []u8, im: f64) !void {
    if (std.math.isNan(im)) {
        try writer.writeAll("+nan.0i");
    } else if (std.math.isInf(im)) {
        try writer.writeAll(if (im > 0) "+inf.0i" else "-inf.0i");
    } else {
        try writer.writeByte(if (std.math.signbit(im)) '-' else '+');
        try writer.writeAll(formatFlonum(buf, @abs(im)));
        try writer.writeByte('i');
    }
}

// ---------------------------------------------------------------------------
// Public entry points
// ---------------------------------------------------------------------------

/// Bounded DIAGNOSTIC printer: no cycle pre-pass, no labels, output truncated
/// with `...` at MAX_PRINT_DEPTH (spine elements count toward the cap, so
/// even an unlabelled cyclic list terminates). For compiler diagnostics and
/// the REPL pretty-printer's layout probes ONLY -- output that a program
/// could `read` back must go through `valueToString`, whose output is exact
/// and label-correct at any depth.
pub fn printValue(writer: anytype, value: Value, mode: PrintMode) anyerror!void {
    var sfb = std.heap.stackFallback(2048, std.heap.page_allocator);
    const atom_mode: PrintMode = if (mode == .shared) .write else mode;
    try printStructured(sfb.get(), writer, value, atom_mode, null, MAX_PRINT_DEPTH);
}

/// Render `value` exactly. `write`/`display` label only structure that forms
/// a cycle (acyclic sharing prints in full, per R7RS); `.shared` labels every
/// repeated container. Output is never truncated: any depth, any number of
/// labels, and every container the printer recurses into is covered by the
/// pre-pass, so printing always terminates.
pub fn valueToString(allocator: std.mem.Allocator, value: Value, mode: PrintMode) ![]u8 {
    var labels = Labels.init(allocator);
    defer labels.deinit();
    switch (mode) {
        .write, .display => try findCycleTargets(allocator, value, &labels),
        .shared => try findSharedNodes(allocator, value, &labels),
    }

    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();
    const atom_mode: PrintMode = if (mode == .shared) .write else mode;
    const lbl: ?*Labels = if (labels.map.count() > 0) &labels else null;
    try printStructured(allocator, &aw.writer, value, atom_mode, lbl, NO_DEPTH_LIMIT);
    return aw.toOwnedSlice();
}

/// `write-simple` (R7RS 6.13.3): "shared structure is never represented
/// using datum labels". Acyclic input renders exactly like `write`; cyclic
/// input has no finite label-free representation, so rather than the
/// non-termination the spec anticipates, this reports CircularStructure and
/// the primitive raises a catchable error.
pub fn valueToStringSimple(allocator: std.mem.Allocator, value: Value) ![]u8 {
    var labels = Labels.init(allocator);
    defer labels.deinit();
    try findCycleTargets(allocator, value, &labels);
    if (labels.map.count() > 0) return error.CircularStructure;

    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();
    try printStructured(allocator, &aw.writer, value, .write, null, NO_DEPTH_LIMIT);
    return aw.toOwnedSlice();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "print fixnums" {
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try printValue(&w, types.makeFixnum(42), .write);
    try std.testing.expectEqualStrings("42", w.buffered());

    w = .fixed(&buf);
    try printValue(&w, types.makeFixnum(-7), .write);
    try std.testing.expectEqualStrings("-7", w.buffered());
}

test "print booleans and nil" {
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try printValue(&w, types.TRUE, .write);
    try std.testing.expectEqualStrings("#t", w.buffered());

    w = .fixed(&buf);
    try printValue(&w, types.FALSE, .write);
    try std.testing.expectEqualStrings("#f", w.buffered());

    w = .fixed(&buf);
    try printValue(&w, types.NIL, .write);
    try std.testing.expectEqualStrings("()", w.buffered());
}

test "print pair and list" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const items = [_]Value{ types.makeFixnum(1), types.makeFixnum(2), types.makeFixnum(3) };
    const list_val = try gc.makeList(&items);

    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    try printValue(&w, list_val, .write);
    try std.testing.expectEqualStrings("(1 2 3)", w.buffered());

    // Improper list
    w = .fixed(&buf);
    const dotted = try gc.allocPair(types.makeFixnum(1), types.makeFixnum(2));
    try printValue(&w, dotted, .write);
    try std.testing.expectEqualStrings("(1 . 2)", w.buffered());
}

test "print character" {
    var buf: [64]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    try printValue(&w, types.makeChar('a'), .write);
    try std.testing.expectEqualStrings("#\\a", w.buffered());

    w = .fixed(&buf);
    try printValue(&w, types.makeChar(' '), .write);
    try std.testing.expectEqualStrings("#\\space", w.buffered());

    w = .fixed(&buf);
    try printValue(&w, types.makeChar('\n'), .write);
    try std.testing.expectEqualStrings("#\\newline", w.buffered());

    w = .fixed(&buf);
    try printValue(&w, types.makeChar('a'), .display);
    try std.testing.expectEqualStrings("a", w.buffered());
}

test "write-shared non-shared list" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const items = [_]Value{ types.makeFixnum(1), types.makeFixnum(2), types.makeFixnum(3) };
    const list_val = try gc.makeList(&items);

    const s = try valueToString(std.testing.allocator, list_val, .shared);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(1 2 3)", s);
}

test "write-shared circular list" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // Build (1 . <self>)
    const pair = try gc.allocPair(types.makeFixnum(1), types.NIL);
    types.setCdr(pair, pair);

    const s = try valueToString(std.testing.allocator, pair, .shared);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("#0=(1 . #0#)", s);
}

test "write-shared shared substructure" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // Build a list where one pair is shared: (X X)
    const shared = try gc.allocPair(types.makeFixnum(1), types.NIL);
    const outer = try gc.allocPair(shared, try gc.allocPair(shared, types.NIL));

    const s = try valueToString(std.testing.allocator, outer, .shared);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("(#0=(1) #0#)", s);
}

// Regression tests for #1713: record instances were invisible to both the
// `write`/`display` cycle-detection pre-pass and the `write-shared`
// shared-structure pre-pass, so a self-referential record fell through to
// the plain depth-limited recursive printer instead of getting a datum
// label. A single direct self-reference "only" recurses ~1024 times before
// hitting the depth cap, but a fan-out cycle (a record field that's a
// vector of records each pointing back) blows up combinatorially at every
// level of that recursion -- see the Scheme-level regression test
// tests/scheme/smoke/cyclic-record-printer-1713.scm for that shape.

test "write circular record instance" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // Build a "cell" record whose only field points back to itself.
    const rt_val = try gc.allocRecordType("cell", 1);
    const rt = types.toObject(rt_val).as(types.RecordType);
    const placeholder = [_]Value{types.NIL};
    const ri = try gc.allocRecordInstance(rt, &placeholder);
    types.toObject(ri).as(types.RecordInstance).fields[0] = ri;

    const s = try valueToString(std.testing.allocator, ri, .write);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("#0=#<cell #0#>", s);
}

test "write-shared circular record instance" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const rt_val = try gc.allocRecordType("cell", 1);
    const rt = types.toObject(rt_val).as(types.RecordType);
    const placeholder = [_]Value{types.NIL};
    const ri = try gc.allocRecordInstance(rt, &placeholder);
    types.toObject(ri).as(types.RecordInstance).fields[0] = ri;

    const s = try valueToString(std.testing.allocator, ri, .shared);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("#0=#<cell #0#>", s);
}
