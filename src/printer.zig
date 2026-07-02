const std = @import("std");
const types = @import("types.zig");
const reader_mod = @import("reader.zig");
const Value = types.Value;

pub const PrintMode = enum {
    write, // machine-readable, strings quoted
    display, // human-readable, strings unquoted
    shared, // write with datum labels for shared/circular structures
};

// ---------------------------------------------------------------------------
// Shared-structure detection (write-shared support)
// ---------------------------------------------------------------------------

const MAX_SHARED = 1024;
const MAX_PRINT_DEPTH: u32 = 1024;

const SharedState = struct {
    seen: [MAX_SHARED]Value = undefined,
    seen_count: usize = 0,
    shared: [MAX_SHARED]Value = undefined, // objects seen more than once
    shared_count: usize = 0,
    labels: [MAX_SHARED]i32 = undefined, // -1 = not yet labeled, >= 0 = label number
    next_label: i32 = 0,
    depth: u32 = 0,

    fn isShared(self: *SharedState, val: Value) bool {
        for (self.shared[0..self.shared_count]) |sh| {
            if (sh == val) return true;
        }
        return false;
    }

    fn getOrAssignLabel(self: *SharedState, val: Value) ?i32 {
        for (self.shared[0..self.shared_count], 0..) |sh, i| {
            if (sh == val) {
                if (self.labels[i] == -1) {
                    self.labels[i] = self.next_label;
                    self.next_label += 1;
                }
                return self.labels[i];
            }
        }
        return null;
    }

    fn getLabel(self: *SharedState, val: Value) ?i32 {
        for (self.shared[0..self.shared_count], 0..) |sh, i| {
            if (sh == val) {
                return if (self.labels[i] >= 0) self.labels[i] else null;
            }
        }
        return null;
    }
};

/// Pass 1: Walk the datum and record which heap objects are referenced
/// more than once (shared structures). Uses a simple two-state approach:
/// first encounter adds to "seen", second encounter adds to "shared".
/// We only recurse on first encounter to avoid infinite loops on cycles.
fn markShared(value: Value, state: *SharedState) void {
    if (!types.isPointer(value)) return;
    if (state.depth >= MAX_PRINT_DEPTH) return;
    state.depth += 1;
    defer state.depth -= 1;
    const obj = types.toObject(value);
    switch (obj.tag) {
        .pair, .vector => {
            // Check if already seen
            for (state.seen[0..state.seen_count]) |s| {
                if (s == value) {
                    // Second encounter: mark as shared, don't recurse
                    for (state.shared[0..state.shared_count]) |sh| {
                        if (sh == value) return; // already shared
                    }
                    if (state.shared_count < MAX_SHARED) {
                        state.shared[state.shared_count] = value;
                        state.labels[state.shared_count] = -1;
                        state.shared_count += 1;
                    }
                    return;
                }
            }
            // First encounter: add to seen and recurse into children
            if (state.seen_count < MAX_SHARED) {
                state.seen[state.seen_count] = value;
                state.seen_count += 1;
            }
            if (obj.tag == .pair) {
                markShared(types.car(value), state);
                markShared(types.cdr(value), state);
            } else {
                const vec = obj.as(types.Vector);
                for (vec.data) |elem| {
                    markShared(elem, state);
                }
            }
        },
        else => {},
    }
}

/// Pass 2: Print with datum labels for the objects recorded in `state.shared`.
/// `atom_mode` selects write vs display rendering for leaf atoms (strings,
/// chars); list/vector structure renders identically in both.
fn printValueShared(writer: anytype, value: Value, state: *SharedState, atom_mode: PrintMode) anyerror!void {
    if (state.depth >= MAX_PRINT_DEPTH) {
        try writer.writeAll("#<deep>");
        return;
    }
    state.depth += 1;
    defer state.depth -= 1;
    // Check if this value has a label assigned (shared/cyclic reference)
    if (types.isPointer(value) and state.isShared(value)) {
        if (state.getLabel(value)) |label| {
            // Already labeled -- emit back-reference #N#
            try writer.print("#{d}#", .{label});
            return;
        }
        // First occurrence -- assign label and emit #N=
        if (state.getOrAssignLabel(value)) |label| {
            try writer.print("#{d}=", .{label});
        }
    }
    // Print the value itself
    if (types.isPair(value)) {
        try printListShared(writer, value, state, atom_mode);
    } else if (types.isPointer(value) and types.toObject(value).tag == .vector) {
        const vec = types.toObject(value).as(types.Vector);
        try writer.writeAll("#(");
        for (vec.data, 0..) |elem, i| {
            if (i > 0) try writer.writeByte(' ');
            try printValueShared(writer, elem, state, atom_mode);
        }
        try writer.writeByte(')');
    } else {
        try printValue(writer, value, atom_mode);
    }
}

fn printListShared(writer: anytype, value: Value, state: *SharedState, atom_mode: PrintMode) anyerror!void {
    try writer.writeByte('(');
    try printValueShared(writer, types.car(value), state, atom_mode);

    var rest = types.cdr(value);
    while (rest != types.NIL) {
        if (types.isPair(rest)) {
            // If this cdr is shared, print as ". #N#" or ". #N=(...)"
            if (state.isShared(rest)) {
                try writer.writeAll(" . ");
                try printValueShared(writer, rest, state, atom_mode);
                break;
            }
            try writer.writeByte(' ');
            try printValueShared(writer, types.car(rest), state, atom_mode);
            rest = types.cdr(rest);
        } else {
            try writer.writeAll(" . ");
            try printValueShared(writer, rest, state, atom_mode);
            break;
        }
    }
    try writer.writeByte(')');
}

/// Record `value` as a node that needs a datum label (it closes a cycle).
fn recordSharedNode(state: *SharedState, value: Value) void {
    if (state.isShared(value)) return;
    if (state.shared_count < MAX_SHARED) {
        state.shared[state.shared_count] = value;
        state.labels[state.shared_count] = -1;
        state.shared_count += 1;
    }
}

/// Detect heap objects that lie on a cycle (the target of a DFS back-edge) and
/// record them in `state.shared`. Only cycles need datum labels for `write`/
/// `display` to terminate; acyclic sharing is printed in full per R7RS.
///
/// The list spine is walked iteratively (recursing only into cars and a dotted
/// tail) so deep proper lists don't overflow the native stack. Traversal sets
/// live on the heap, so detection terminates on structures of any size.
fn markCycles(allocator: std.mem.Allocator, value: Value, state: *SharedState) void {
    var on_stack = std.AutoHashMap(Value, void).init(allocator);
    defer on_stack.deinit();
    var done = std.AutoHashMap(Value, void).init(allocator);
    defer done.deinit();
    markCyclesRec(allocator, value, state, &on_stack, &done, 0);
}

fn markCyclesRec(
    allocator: std.mem.Allocator,
    value: Value,
    state: *SharedState,
    on_stack: *std.AutoHashMap(Value, void),
    done: *std.AutoHashMap(Value, void),
    depth: u32,
) void {
    if (depth >= MAX_PRINT_DEPTH) return;
    if (!types.isPointer(value)) return;
    const obj = types.toObject(value);

    if (obj.tag == .vector) {
        if (on_stack.contains(value)) return recordSharedNode(state, value);
        if (done.contains(value)) return;
        on_stack.put(value, {}) catch return;
        const vec = obj.as(types.Vector);
        for (vec.data) |elem| markCyclesRec(allocator, elem, state, on_stack, done, depth + 1);
        _ = on_stack.remove(value);
        done.put(value, {}) catch {};
        return;
    }

    if (obj.tag != .pair) return;

    // Walk the cdr spine iteratively; the spine pairs stay on the DFS stack
    // until the whole spine is processed, then unwind together.
    var spine: std.ArrayList(Value) = .empty;
    defer spine.deinit(allocator);

    var cur = value;
    while (types.isPointer(cur)) {
        const o = types.toObject(cur);
        if (o.tag != .pair) {
            markCyclesRec(allocator, cur, state, on_stack, done, depth + 1);
            break;
        }
        if (on_stack.contains(cur)) {
            recordSharedNode(state, cur);
            break;
        }
        if (done.contains(cur)) break;
        on_stack.put(cur, {}) catch break;
        spine.append(allocator, cur) catch {};
        markCyclesRec(allocator, types.car(cur), state, on_stack, done, depth + 1);
        cur = types.cdr(cur);
    }

    var i = spine.items.len;
    while (i > 0) {
        i -= 1;
        _ = on_stack.remove(spine.items[i]);
        done.put(spine.items[i], {}) catch {};
    }
}

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

/// Format a flonum in Scheme syntax into `buf`, returning the slice. Uses
/// scientific notation for very large/small magnitudes so the output stays
/// bounded (plain `{d}` expands denormals/huge values to hundreds of decimal
/// digits, overflowing fixed buffers). Always includes a `.`/`e` so the result
/// reads back as inexact.
fn formatComplexPart(buf: []u8, f: f64, exact: bool) []const u8 {
    if (std.math.isNan(f) or std.math.isInf(f)) return formatFlonum(buf, f);
    if (exact) {
        const trunc = @trunc(f);
        if (f == trunc and @abs(f) < 4.5e18) {
            const i: i64 = @intFromFloat(trunc);
            return std.fmt.bufPrint(buf, "{d}", .{i}) catch return formatFlonum(buf, f);
        }
        // Exact non-integer: try rational notation
        const numeric = @import("primitives_numeric.zig");
        const rat = numeric.floatToRational(f);
        if (rat.den != 1) {
            return std.fmt.bufPrint(buf, "{d}/{d}", .{ rat.num, rat.den }) catch return formatFlonum(buf, f);
        }
        return std.fmt.bufPrint(buf, "{d}", .{rat.num}) catch return formatFlonum(buf, f);
    }
    return formatFlonum(buf, f);
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

pub fn printValue(writer: anytype, value: Value, mode: PrintMode) anyerror!void {
    return printValueWithDepth(writer, value, mode, 0);
}

fn printValueWithDepth(writer: anytype, value: Value, mode: PrintMode, depth: u32) anyerror!void {
    if (mode == .shared) {
        var state = SharedState{};
        markShared(value, &state);
        try printValueShared(writer, value, &state, .write);
        return;
    }
    if (depth >= MAX_PRINT_DEPTH) {
        try writer.writeAll("...");
        return;
    }
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
                        hw.print("x{x};", .{cp}) catch {};
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
            .pair => try printListWithDepth(writer, value, mode, depth),
            .symbol => {
                const sym = obj.as(types.Symbol);
                if (mode != .display and symbolNeedsBars(sym.name)) {
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
                const nc = obj.as(types.NativeClosure);
                try writer.print("#<native-closure {s}>", .{nc.name});
            },
            .function => {
                try writer.writeAll("#<function>");
            },
            .transformer => {
                try writer.writeAll("#<transformer>");
            },
            .error_object => {
                const err = obj.as(types.ErrorObject);
                try writer.writeAll("#<error ");
                try printValueWithDepth(writer, err.message, mode, depth + 1);
                if (err.irritants != types.NIL) {
                    try writer.writeByte(' ');
                    var irr = err.irritants;
                    while (irr != types.NIL) {
                        if (types.isPair(irr)) {
                            try printValueWithDepth(writer, types.car(irr), mode, depth + 1);
                            irr = types.cdr(irr);
                            if (irr != types.NIL) try writer.writeByte(' ');
                        } else {
                            try printValueWithDepth(writer, irr, mode, depth + 1);
                            break;
                        }
                    }
                }
                try writer.writeByte('>');
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
                for (ri.fields) |field| {
                    try writer.writeByte(' ');
                    try printValueWithDepth(writer, field, mode, depth + 1);
                }
                try writer.writeByte('>');
            },
            .complex => {
                const c = obj.as(types.Complex);
                var buf: [64]u8 = undefined;
                if (c.imag == 0.0 and !std.math.signbit(c.imag)) {
                    try writer.writeAll(formatFlonum(&buf, c.real));
                } else {
                    const has_real = c.real != 0.0 or std.math.signbit(c.real);
                    if (has_real) try writer.writeAll(formatComplexPart(&buf, c.real, c.exact_real));
                    const im = c.imag;
                    if (std.math.isNan(im)) {
                        try writer.writeAll("+nan.0i");
                    } else if (std.math.isInf(im)) {
                        try writer.writeAll(if (im > 0) "+inf.0i" else "-inf.0i");
                    } else {
                        try writer.writeByte(if (im < 0 or std.math.signbit(im)) '-' else '+');
                        const mag = @abs(im);
                        if (mag != 1.0 or has_real) try writer.writeAll(formatComplexPart(&buf, mag, c.exact_imag));
                        try writer.writeByte('i');
                    }
                }
            },
            .vector => {
                const vec = obj.as(types.Vector);
                try writer.writeAll("#(");
                for (vec.data, 0..) |elem, i| {
                    if (i > 0) try writer.writeByte(' ');
                    try printValueWithDepth(writer, elem, mode, depth + 1);
                }
                try writer.writeByte(')');
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
                const mv = obj.as(types.MultipleValues);
                try writer.writeAll("#<values");
                for (mv.values) |val| {
                    try writer.writeByte(' ');
                    try printValueWithDepth(writer, val, mode, depth + 1);
                }
                try writer.writeByte('>');
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
                    try printValueWithDepth(writer, m.name, mode, depth + 1);
                }
                try writer.writeAll(">");
            },
            .condition_variable => {
                const cv = obj.as(types.ConditionVariable);
                try writer.writeAll("#<condition-variable");
                if (cv.name != types.VOID) {
                    try writer.writeAll(" ");
                    try printValueWithDepth(writer, cv.name, mode, depth + 1);
                }
                try writer.writeAll(">");
            },
            .srfi18_time => {
                const t = obj.as(types.Srfi18Time);
                try writer.print("#<time {d:.6}>", .{t.seconds});
            },
            .bignum => {
                const bignum_mod = @import("bignum.zig");
                const allocator = std.heap.page_allocator;
                const s = bignum_mod.toString(allocator, value) catch {
                    try writer.writeAll("?bignum?");
                    return;
                };
                defer allocator.free(s);
                try writer.writeAll(s);
            },
            .rational => {
                const rat = obj.as(types.Rational);
                try printValueWithDepth(writer, rat.numerator, mode, depth + 1);
                try writer.writeByte('/');
                try printValueWithDepth(writer, rat.denominator, mode, depth + 1);
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
        }
    } else {
        try writer.writeAll("#<unknown>");
    }
}

fn printList(writer: anytype, value: Value, mode: PrintMode) anyerror!void {
    return printListWithDepth(writer, value, mode, 0);
}

fn printListWithDepth(writer: anytype, value: Value, mode: PrintMode, depth: u32) anyerror!void {
    try writer.writeByte('(');
    try printValueWithDepth(writer, types.car(value), mode, depth + 1);

    var rest = types.cdr(value);
    while (rest != types.NIL) {
        if (types.isPair(rest)) {
            try writer.writeByte(' ');
            try printValueWithDepth(writer, types.car(rest), mode, depth + 1);
            rest = types.cdr(rest);
        } else {
            try writer.writeAll(" . ");
            try printValueWithDepth(writer, rest, mode, depth + 1);
            break;
        }
    }
    try writer.writeByte(')');
}

pub fn prettyPrint(allocator: std.mem.Allocator, value: Value, width: u16) ![]u8 {
    const flat = try valueToString(allocator, value, .write);
    if (flat.len <= width) return flat;
    allocator.free(flat);
    var aw: std.Io.Writer.Allocating = .init(allocator);
    try ppValue(&aw.writer, value, 0, width);
    return aw.toOwnedSlice();
}

fn ppValue(writer: anytype, value: Value, indent: u16, width: u16) anyerror!void {
    if (!types.isPair(value) and !types.isVector(value)) {
        try printValue(writer, value, .write);
        return;
    }
    if (types.isVector(value)) {
        const vec = types.toObject(value).as(types.Vector);
        try writer.writeAll("#(");
        for (vec.data, 0..) |elem, i| {
            if (i > 0) try writer.writeByte(' ');
            try ppValue(writer, elem, indent + 2, width);
        }
        try writer.writeByte(')');
        return;
    }
    // Check if the list fits on one line
    const flat_len = estimateLen(value);
    if (indent + flat_len <= width) {
        try printValue(writer, value, .write);
        return;
    }
    try writer.writeByte('(');
    const new_indent = indent + 2;
    var first = true;
    var cur = value;
    while (cur != types.NIL) {
        if (!types.isPair(cur)) {
            if (!first) {
                try writer.writeByte('\n');
                var sp: u16 = 0;
                while (sp < new_indent) : (sp += 1) try writer.writeByte(' ');
            }
            try writer.writeAll(". ");
            try ppValue(writer, cur, new_indent, width);
            break;
        }
        if (!first) {
            try writer.writeByte('\n');
            var sp: u16 = 0;
            while (sp < new_indent) : (sp += 1) try writer.writeByte(' ');
        }
        try ppValue(writer, types.car(cur), new_indent, width);
        first = false;
        cur = types.cdr(cur);
    }
    try writer.writeByte(')');
}

fn estimateLen(value: Value) u16 {
    if (types.isFixnum(value)) return if (types.toFixnum(value) < 0) 5 else 3;
    if (types.isFlonum(value)) return 10;
    if (types.isSymbol(value)) {
        const name = types.symbolName(value);
        return @intCast(@min(name.len, 60));
    }
    if (value == types.NIL) return 2;
    if (value == types.TRUE) return 2;
    if (value == types.FALSE) return 2;
    if (types.isString(value)) {
        const s = types.toObject(value).as(types.SchemeString);
        return @intCast(@min(s.len + 2, 60));
    }
    if (types.isPair(value)) {
        var len: u16 = 2; // parens
        var cur = value;
        var count: u16 = 0;
        while (cur != types.NIL and types.isPair(cur) and count < 20) {
            len += estimateLen(types.car(cur)) + 1;
            cur = types.cdr(cur);
            count += 1;
        }
        return len;
    }
    return 10;
}

pub fn valueToString(allocator: std.mem.Allocator, value: Value, mode: PrintMode) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);

    // For `write`/`display`, R7RS requires labeling only structure that forms a
    // cycle (so output terminates) while leaving acyclic sharing in full. Detect
    // cycles up front; if none exist, take the plain fast path so non-cyclic
    // output is byte-for-byte unchanged.
    if (mode == .write or mode == .display) {
        var state = SharedState{};
        markCycles(allocator, value, &state);
        if (state.shared_count > 0) {
            try printValueShared(&aw.writer, value, &state, mode);
            return aw.toOwnedSlice();
        }
    }

    try printValue(&aw.writer, value, mode);
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
