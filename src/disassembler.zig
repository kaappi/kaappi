const std = @import("std");
const types = @import("types.zig");
const OpCode = types.OpCode;
const Value = types.Value;
const printer = @import("printer.zig");
const memory = @import("memory.zig");

pub fn disassemble(func: *types.Function, allocator: std.mem.Allocator) void {
    printHeader(func, allocator);
    const code = func.code.items;
    var ip: usize = 0;
    while (ip < code.len) {
        ip = disassembleInstruction(func, code, ip, allocator);
    }
    writeStderr("\n");
}

fn printHeader(func: *types.Function, allocator: std.mem.Allocator) void {
    var buf: [512]u8 = undefined;
    if (func.name) |name| {
        const s = std.fmt.bufPrint(&buf, "; Function: {s}\n", .{name}) catch return;
        writeStderr(s);
    } else {
        writeStderr("; Function: <lambda>\n");
    }
    if (func.source_name) |src| {
        if (func.source_line > 0) {
            const s = std.fmt.bufPrint(&buf, "; Source: {s}:{d}\n", .{ src, func.source_line }) catch return;
            writeStderr(s);
        } else {
            const s = std.fmt.bufPrint(&buf, "; Source: {s}\n", .{src}) catch return;
            writeStderr(s);
        }
    }
    {
        const variadic_str: []const u8 = if (func.is_variadic) "+" else "";
        const s = std.fmt.bufPrint(&buf, "; Arity: {d}{s}, Locals: {d}, Upvalues: {d}\n", .{ func.arity, variadic_str, func.locals_count, func.upvalue_count }) catch return;
        writeStderr(s);
    }
    if (func.constants.items.len > 0) {
        writeStderr("; Constants:");
        for (func.constants.items, 0..) |c, i| {
            if (i > 0) writeStderr(",");
            writeStderr(" ");
            const cs = printer.valueToString(allocator, c, .write) catch "?";
            defer if (cs.len > 0) allocator.free(cs);
            writeStderr(cs);
        }
        writeStderr("\n");
    }
    writeStderr(";\n");
}

fn disassembleInstruction(func: *types.Function, code: []const u8, offset: usize, allocator: std.mem.Allocator) usize {
    var buf: [256]u8 = undefined;
    var ip = offset;
    const op: OpCode = @enumFromInt(code[ip]);
    ip += 1;

    const off_str = std.fmt.bufPrint(&buf, "  {d:0>4}  ", .{offset}) catch "  ????  ";
    writeStderr(off_str);

    switch (op) {
        .load_const => {
            const dst = code[ip];
            ip += 1;
            const idx = readU16(code, &ip);
            const name = constName(func, idx, allocator);
            defer if (name.len > 0) allocator.free(name);
            const s = std.fmt.bufPrint(&buf, "load_const      r{d}, {s}\n", .{ dst, name }) catch "load_const\n";
            writeStderr(s);
        },
        .load_nil => {
            const dst = code[ip];
            ip += 1;
            const s = std.fmt.bufPrint(&buf, "load_nil        r{d}\n", .{dst}) catch "load_nil\n";
            writeStderr(s);
        },
        .load_true => {
            const dst = code[ip];
            ip += 1;
            const s = std.fmt.bufPrint(&buf, "load_true       r{d}\n", .{dst}) catch "load_true\n";
            writeStderr(s);
        },
        .load_false => {
            const dst = code[ip];
            ip += 1;
            const s = std.fmt.bufPrint(&buf, "load_false      r{d}\n", .{dst}) catch "load_false\n";
            writeStderr(s);
        },
        .load_void => {
            const dst = code[ip];
            ip += 1;
            const s = std.fmt.bufPrint(&buf, "load_void       r{d}\n", .{dst}) catch "load_void\n";
            writeStderr(s);
        },
        .move => {
            const dst = code[ip];
            ip += 1;
            const src = code[ip];
            ip += 1;
            const s = std.fmt.bufPrint(&buf, "move            r{d}, r{d}\n", .{ dst, src }) catch "move\n";
            writeStderr(s);
        },
        .get_global => {
            const dst = code[ip];
            ip += 1;
            const idx = readU16(code, &ip);
            const name = constName(func, idx, allocator);
            defer if (name.len > 0) allocator.free(name);
            const s = std.fmt.bufPrint(&buf, "get_global      r{d}, {s}\n", .{ dst, name }) catch "get_global\n";
            writeStderr(s);
        },
        .set_global => {
            const idx = readU16(code, &ip);
            const src = code[ip];
            ip += 1;
            const name = constName(func, idx, allocator);
            defer if (name.len > 0) allocator.free(name);
            const s = std.fmt.bufPrint(&buf, "set_global      {s}, r{d}\n", .{ name, src }) catch "set_global\n";
            writeStderr(s);
        },
        .define_global => {
            const idx = readU16(code, &ip);
            const src = code[ip];
            ip += 1;
            const name = constName(func, idx, allocator);
            defer if (name.len > 0) allocator.free(name);
            const s = std.fmt.bufPrint(&buf, "define_global   {s}, r{d}\n", .{ name, src }) catch "define_global\n";
            writeStderr(s);
        },
        .tail_apply => {
            const base = code[ip];
            ip += 1;
            const nargs = code[ip];
            ip += 1;
            const s = std.fmt.bufPrint(&buf, "tail_apply      r{d}, {d}\n", .{ base, nargs }) catch "tail_apply\n";
            writeStderr(s);
        },
        .get_local, .set_local => {
            const a = code[ip];
            ip += 1;
            const b = code[ip];
            ip += 1;
            const oname = @tagName(op);
            const s = std.fmt.bufPrint(&buf, "{s: <16}r{d}, r{d}\n", .{ oname, a, b }) catch "get/set_local\n";
            writeStderr(s);
        },
        .get_upvalue => {
            const dst = code[ip];
            ip += 1;
            const idx = code[ip];
            ip += 1;
            const s = std.fmt.bufPrint(&buf, "get_upvalue     r{d}, uv{d}\n", .{ dst, idx }) catch "get_upvalue\n";
            writeStderr(s);
        },
        .set_upvalue => {
            const idx = code[ip];
            ip += 1;
            const src = code[ip];
            ip += 1;
            const s = std.fmt.bufPrint(&buf, "set_upvalue     uv{d}, r{d}\n", .{ idx, src }) catch "set_upvalue\n";
            writeStderr(s);
        },
        .call => {
            const base = code[ip];
            ip += 1;
            const nargs = code[ip];
            ip += 1;
            const s = std.fmt.bufPrint(&buf, "call            r{d}, {d}\n", .{ base, nargs }) catch "call\n";
            writeStderr(s);
        },
        .tail_call => {
            const base = code[ip];
            ip += 1;
            const nargs = code[ip];
            ip += 1;
            const s = std.fmt.bufPrint(&buf, "tail_call       r{d}, {d}\n", .{ base, nargs }) catch "tail_call\n";
            writeStderr(s);
        },
        .@"return" => {
            const src = code[ip];
            ip += 1;
            const s = std.fmt.bufPrint(&buf, "return          r{d}\n", .{src}) catch "return\n";
            writeStderr(s);
        },
        .jump => {
            const off = readI16(code, &ip);
            const target: usize = @intCast(@as(i32, @intCast(ip)) + off);
            const s = std.fmt.bufPrint(&buf, "jump            -> {d:0>4}\n", .{target}) catch "jump\n";
            writeStderr(s);
        },
        .jump_false => {
            const test_reg = code[ip];
            ip += 1;
            const off = readI16(code, &ip);
            const target: usize = @intCast(@as(i32, @intCast(ip)) + off);
            const s = std.fmt.bufPrint(&buf, "jump_false      r{d}, -> {d:0>4}\n", .{ test_reg, target }) catch "jump_false\n";
            writeStderr(s);
        },
        .jump_true => {
            const test_reg = code[ip];
            ip += 1;
            const off = readI16(code, &ip);
            const target: usize = @intCast(@as(i32, @intCast(ip)) + off);
            const s = std.fmt.bufPrint(&buf, "jump_true       r{d}, -> {d:0>4}\n", .{ test_reg, target }) catch "jump_true\n";
            writeStderr(s);
        },
        .closure => {
            const dst = code[ip];
            ip += 1;
            const idx = readU16(code, &ip);
            const name = constName(func, idx, allocator);
            defer if (name.len > 0) allocator.free(name);
            const s = std.fmt.bufPrint(&buf, "closure         r{d}, {s}\n", .{ dst, name }) catch "closure\n";
            writeStderr(s);
            // Skip upvalue capture descriptors
            if (idx < func.constants.items.len) {
                const val = func.constants.items[idx];
                if (types.isPointer(val)) {
                    const obj = types.toObject(val);
                    if (obj.tag == .function) {
                        const inner = obj.as(types.Function);
                        var ui: usize = 0;
                        while (ui < inner.upvalue_count) : (ui += 1) {
                            const is_local = code[ip];
                            ip += 1;
                            const uv_idx = code[ip];
                            ip += 1;
                            const loc_str: []const u8 = if (is_local == 1) "local" else "upvalue";
                            const us = std.fmt.bufPrint(&buf, "          capture {s} {d}\n", .{ loc_str, uv_idx }) catch "";
                            writeStderr(us);
                        }
                    }
                }
            }
        },
        .close_upvalue => {
            const slot = code[ip];
            ip += 1;
            const s = std.fmt.bufPrint(&buf, "close_upvalue   r{d}\n", .{slot}) catch "close_upvalue\n";
            writeStderr(s);
        },
        .cons => {
            const dst = code[ip];
            ip += 1;
            const car = code[ip];
            ip += 1;
            const cdr = code[ip];
            ip += 1;
            const s = std.fmt.bufPrint(&buf, "cons            r{d}, r{d}, r{d}\n", .{ dst, car, cdr }) catch "cons\n";
            writeStderr(s);
        },
        .push_handler => {
            const handler = code[ip];
            ip += 1;
            const s = std.fmt.bufPrint(&buf, "push_handler    r{d}\n", .{handler}) catch "push_handler\n";
            writeStderr(s);
        },
        .pop_handler => {
            writeStderr("pop_handler\n");
        },
        .halt => {
            writeStderr("halt\n");
        },
        .call_global => {
            const base = code[ip];
            ip += 1;
            const idx = readU16(code, &ip);
            const nargs = code[ip];
            ip += 1;
            const name = constName(func, idx, allocator);
            defer if (name.len > 0) allocator.free(name);
            const s = std.fmt.bufPrint(&buf, "call_global     r{d}, {s}, {d}\n", .{ base, name, nargs }) catch "call_global\n";
            writeStderr(s);
        },
        .tail_call_global => {
            const base = code[ip];
            ip += 1;
            const idx = readU16(code, &ip);
            const nargs = code[ip];
            ip += 1;
            const name = constName(func, idx, allocator);
            defer if (name.len > 0) allocator.free(name);
            const s = std.fmt.bufPrint(&buf, "tail_call_global r{d}, {s}, {d}\n", .{ base, name, nargs }) catch "tail_call_global\n";
            writeStderr(s);
        },
        .box_local => {
            const reg = code[ip];
            ip += 1;
            const s = std.fmt.bufPrint(&buf, "box_local       r{d}\n", .{reg}) catch "box_local\n";
            writeStderr(s);
        },
        .get_box_local => {
            const dst = code[ip];
            ip += 1;
            const reg = code[ip];
            ip += 1;
            const s = std.fmt.bufPrint(&buf, "get_box_local   r{d}, r{d}\n", .{ dst, reg }) catch "get_box_local\n";
            writeStderr(s);
        },
        .set_box_local => {
            const reg = code[ip];
            ip += 1;
            const src = code[ip];
            ip += 1;
            const s = std.fmt.bufPrint(&buf, "set_box_local   r{d}, r{d}\n", .{ reg, src }) catch "set_box_local\n";
            writeStderr(s);
        },
        .self_tail_call => {
            const base = code[ip];
            ip += 1;
            const nargs = code[ip];
            ip += 1;
            const s = std.fmt.bufPrint(&buf, "self_tail_call  r{d}, {d}\n", .{ base, nargs }) catch "self_tail_call\n";
            writeStderr(s);
        },
    }
    return ip;
}

fn readU16(code: []const u8, ip: *usize) u16 {
    const hi: u16 = code[ip.*];
    const lo: u16 = code[ip.* + 1];
    ip.* += 2;
    return (hi << 8) | lo;
}

fn readI16(code: []const u8, ip: *usize) i16 {
    return @bitCast(readU16(code, ip));
}

fn constName(func: *types.Function, idx: u16, allocator: std.mem.Allocator) []const u8 {
    if (idx >= func.constants.items.len) return "";
    const val = func.constants.items[idx];
    return printer.valueToString(allocator, val, .write) catch "";
}

fn writeStderr(bytes: []const u8) void {
    var total: usize = 0;
    while (total < bytes.len) {
        const result: isize = std.posix.system.write(2, bytes.ptr + total, bytes.len - total);
        if (result > 0) {
            total += @intCast(result);
        } else break;
    }
}
