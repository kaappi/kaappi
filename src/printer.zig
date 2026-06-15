const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

pub const PrintMode = enum {
    write, // machine-readable, strings quoted
    display, // human-readable, strings unquoted
};

pub fn printValue(writer: anytype, value: Value, mode: PrintMode) anyerror!void {
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
                    var buf: [4]u8 = undefined;
                    const len = std.unicode.utf8Encode(cp, &buf) catch 0;
                    try writer.writeAll(buf[0..len]);
                },
            }
        } else {
            var buf: [4]u8 = undefined;
            const len = std.unicode.utf8Encode(cp, &buf) catch 0;
            try writer.writeAll(buf[0..len]);
        }
    } else if (types.isPointer(value)) {
        const obj = types.toObject(value);
        switch (obj.tag) {
            .pair => try printList(writer, value, mode),
            .symbol => {
                const sym = obj.as(types.Symbol);
                try writer.writeAll(sym.name);
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
                            else => try writer.writeByte(c),
                        }
                    }
                    try writer.writeByte('"');
                } else {
                    try writer.writeAll(str.data);
                }
            },
            .flonum => {
                const flo = obj.as(types.Flonum);
                const f = flo.value;
                if (std.math.isNan(f)) {
                    try writer.writeAll("+nan.0");
                } else if (std.math.isInf(f)) {
                    if (f > 0) try writer.writeAll("+inf.0") else try writer.writeAll("-inf.0");
                } else {
                    var buf: [64]u8 = undefined;
                    const s = std.fmt.bufPrint(&buf, "{d}", .{f}) catch "?";
                    try writer.writeAll(s);
                    // Ensure at least one decimal point for inexact display
                    if (std.mem.indexOfScalar(u8, s, '.') == null and
                        std.mem.indexOfScalar(u8, s, 'e') == null and
                        std.mem.indexOfScalar(u8, s, 'E') == null)
                    {
                        try writer.writeAll(".0");
                    }
                }
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
            .function => {
                try writer.writeAll("#<function>");
            },
            .transformer => {
                try writer.writeAll("#<transformer>");
            },
            .error_object => {
                const err = obj.as(types.ErrorObject);
                try writer.writeAll("#<error ");
                try printValue(writer, err.message, mode);
                // Print irritants if non-empty
                if (err.irritants != types.NIL) {
                    try writer.writeByte(' ');
                    var irr = err.irritants;
                    while (irr != types.NIL) {
                        if (types.isPair(irr)) {
                            try printValue(writer, types.car(irr), mode);
                            irr = types.cdr(irr);
                            if (irr != types.NIL) try writer.writeByte(' ');
                        } else {
                            try printValue(writer, irr, mode);
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
                for (ri.fields, 0..) |field, i| {
                    _ = i;
                    try writer.writeByte(' ');
                    try printValue(writer, field, mode);
                }
                try writer.writeByte('>');
            },
            .complex => {
                const c = obj.as(types.Complex);
                // Print real part (skip if zero, unless imag is also zero)
                if (c.real != 0.0 or c.imag == 0.0) {
                    var buf: [64]u8 = undefined;
                    const s = std.fmt.bufPrint(&buf, "{d}", .{c.real}) catch "?";
                    try writer.writeAll(s);
                    // Ensure decimal point
                    if (std.mem.indexOfScalar(u8, s, '.') == null and
                        std.mem.indexOfScalar(u8, s, 'e') == null)
                    {
                        try writer.writeAll(".0");
                    }
                }
                // Print imaginary part
                if (c.imag != 0.0) {
                    if (c.imag > 0.0 and (c.real != 0.0 or c.imag == 0.0)) {
                        try writer.writeByte('+');
                    }
                    if (c.imag == 1.0) {
                        // nothing, just +i
                    } else if (c.imag == -1.0) {
                        try writer.writeByte('-');
                    } else {
                        var buf: [64]u8 = undefined;
                        const s = std.fmt.bufPrint(&buf, "{d}", .{c.imag}) catch "?";
                        try writer.writeAll(s);
                        if (std.mem.indexOfScalar(u8, s, '.') == null and
                            std.mem.indexOfScalar(u8, s, 'e') == null)
                        {
                            try writer.writeAll(".0");
                        }
                    }
                    try writer.writeByte('i');
                }
            },
            .vector => {
                const vec = obj.as(types.Vector);
                try writer.writeAll("#(");
                for (vec.data, 0..) |elem, i| {
                    if (i > 0) try writer.writeByte(' ');
                    try printValue(writer, elem, mode);
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
                    try printValue(writer, val, mode);
                }
                try writer.writeByte('>');
            },
        }
    } else {
        try writer.writeAll("#<unknown>");
    }
}

fn printList(writer: anytype, value: Value, mode: PrintMode) anyerror!void {
    try writer.writeByte('(');
    try printValue(writer, types.car(value), mode);

    var rest = types.cdr(value);
    while (rest != types.NIL) {
        if (types.isPair(rest)) {
            try writer.writeByte(' ');
            try printValue(writer, types.car(rest), mode);
            rest = types.cdr(rest);
        } else {
            try writer.writeAll(" . ");
            try printValue(writer, rest, mode);
            break;
        }
    }
    try writer.writeByte(')');
}

pub fn valueToString(allocator: std.mem.Allocator, value: Value, mode: PrintMode) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
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
