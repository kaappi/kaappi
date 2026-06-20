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
    if (ip >= code.len) return code.len;
    const raw_op = code[ip];
    ip += 1;

    const off_str = std.fmt.bufPrint(&buf, "  {d:0>4}  ", .{offset}) catch "  ????  ";
    writeStderr(off_str);

    if (raw_op > @intFromEnum(OpCode.self_tail_call)) {
        const s = std.fmt.bufPrint(&buf, "<invalid opcode 0x{x:0>2}>\n", .{raw_op}) catch "<invalid opcode>\n";
        writeStderr(s);
        return ip;
    }
    const op: OpCode = @enumFromInt(raw_op);

    const fixed_operand_bytes: usize = switch (op) {
        .load_const => 3,
        .load_nil, .load_true, .load_false, .load_void => 1,
        .move => 2,
        .get_global => 3,
        .set_global, .define_global => 3,
        .tail_apply => 2,
        .get_local, .set_local, .get_upvalue, .set_upvalue => 2,
        .call, .tail_call => 2,
        .@"return" => 1,
        .jump => 2,
        .jump_false, .jump_true => 3,
        .closure => 3,
        .close_upvalue => 1,
        .cons => 3,
        .push_handler => 1,
        .pop_handler, .halt => 0,
        .call_global, .tail_call_global => 4,
        .box_local => 1,
        .get_box_local, .set_box_local => 2,
        .self_tail_call => 2,
    };
    if (ip + fixed_operand_bytes > code.len) {
        writeStderr("<truncated instruction>\n");
        return code.len;
    }

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
            const target = @as(i64, @intCast(ip)) + @as(i64, off);
            const s = if (target < 0 or target > code.len)
                std.fmt.bufPrint(&buf, "jump            -> <invalid {d}>\n", .{target}) catch "jump\n"
            else
                std.fmt.bufPrint(&buf, "jump            -> {d:0>4}\n", .{@as(usize, @intCast(target))}) catch "jump\n";
            writeStderr(s);
        },
        .jump_false => {
            const test_reg = code[ip];
            ip += 1;
            const off = readI16(code, &ip);
            const target = @as(i64, @intCast(ip)) + @as(i64, off);
            const s = if (target < 0 or target > code.len)
                std.fmt.bufPrint(&buf, "jump_false      r{d}, -> <invalid {d}>\n", .{ test_reg, target }) catch "jump_false\n"
            else
                std.fmt.bufPrint(&buf, "jump_false      r{d}, -> {d:0>4}\n", .{ test_reg, @as(usize, @intCast(target)) }) catch "jump_false\n";
            writeStderr(s);
        },
        .jump_true => {
            const test_reg = code[ip];
            ip += 1;
            const off = readI16(code, &ip);
            const target = @as(i64, @intCast(ip)) + @as(i64, off);
            const s = if (target < 0 or target > code.len)
                std.fmt.bufPrint(&buf, "jump_true       r{d}, -> <invalid {d}>\n", .{ test_reg, target }) catch "jump_true\n"
            else
                std.fmt.bufPrint(&buf, "jump_true       r{d}, -> {d:0>4}\n", .{ test_reg, @as(usize, @intCast(target)) }) catch "jump_true\n";
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
                            if (ip + 2 > code.len) {
                                writeStderr("          <truncated capture descriptors>\n");
                                return code.len;
                            }
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

test "disassemble all opcodes" {
    const allocator = std.testing.allocator;
    var gc = memory.GC.init(allocator);
    defer gc.deinit();

    const func = try gc.allocFunction();
    func.name = "test-all-opcodes";

    const sym = try gc.allocSymbol("test-sym");
    func.constants.append(allocator, sym) catch unreachable;
    func.constants.append(allocator, types.makeFixnum(42)) catch unreachable;

    const emit = struct {
        fn op(f: *types.Function, a: std.mem.Allocator, opcode: OpCode) void {
            f.code.append(a, @intFromEnum(opcode)) catch unreachable;
        }
        fn byte(f: *types.Function, a: std.mem.Allocator, b: u8) void {
            f.code.append(a, b) catch unreachable;
        }
    };

    // load_const r0, const[0]
    emit.op(func, allocator, .load_const); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0);
    // load_nil r0
    emit.op(func, allocator, .load_nil); emit.byte(func, allocator, 0);
    // load_true r0
    emit.op(func, allocator, .load_true); emit.byte(func, allocator, 0);
    // load_false r0
    emit.op(func, allocator, .load_false); emit.byte(func, allocator, 0);
    // load_void r0
    emit.op(func, allocator, .load_void); emit.byte(func, allocator, 0);
    // move r0, r1
    emit.op(func, allocator, .move); emit.byte(func, allocator, 0); emit.byte(func, allocator, 1);
    // get_global r0, const[0]
    emit.op(func, allocator, .get_global); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0);
    // set_global const[0], r0
    emit.op(func, allocator, .set_global); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0);
    // define_global const[0], r0
    emit.op(func, allocator, .define_global); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0);
    // tail_apply r0, 2
    emit.op(func, allocator, .tail_apply); emit.byte(func, allocator, 0); emit.byte(func, allocator, 2);
    // get_local r0, r1
    emit.op(func, allocator, .get_local); emit.byte(func, allocator, 0); emit.byte(func, allocator, 1);
    // set_local r0, r1
    emit.op(func, allocator, .set_local); emit.byte(func, allocator, 0); emit.byte(func, allocator, 1);
    // get_upvalue r0, uv0
    emit.op(func, allocator, .get_upvalue); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0);
    // set_upvalue uv0, r0
    emit.op(func, allocator, .set_upvalue); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0);
    // call r0, 1
    emit.op(func, allocator, .call); emit.byte(func, allocator, 0); emit.byte(func, allocator, 1);
    // tail_call r0, 1
    emit.op(func, allocator, .tail_call); emit.byte(func, allocator, 0); emit.byte(func, allocator, 1);
    // return r0
    emit.op(func, allocator, .@"return"); emit.byte(func, allocator, 0);
    // jump +0
    emit.op(func, allocator, .jump); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0);
    // jump_false r0, +0
    emit.op(func, allocator, .jump_false); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0);
    // jump_true r0, +0
    emit.op(func, allocator, .jump_true); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0);
    // closure r0, const[0]
    emit.op(func, allocator, .closure); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0);
    // close_upvalue r0
    emit.op(func, allocator, .close_upvalue); emit.byte(func, allocator, 0);
    // cons r0, r1, r2
    emit.op(func, allocator, .cons); emit.byte(func, allocator, 0); emit.byte(func, allocator, 1); emit.byte(func, allocator, 2);
    // push_handler r0
    emit.op(func, allocator, .push_handler); emit.byte(func, allocator, 0);
    // pop_handler
    emit.op(func, allocator, .pop_handler);
    // halt
    emit.op(func, allocator, .halt);
    // call_global r0, const[0], 1
    emit.op(func, allocator, .call_global); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0); emit.byte(func, allocator, 1);
    // tail_call_global r0, const[0], 1
    emit.op(func, allocator, .tail_call_global); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0); emit.byte(func, allocator, 0); emit.byte(func, allocator, 1);
    // box_local r0
    emit.op(func, allocator, .box_local); emit.byte(func, allocator, 0);
    // get_box_local r0, r1
    emit.op(func, allocator, .get_box_local); emit.byte(func, allocator, 0); emit.byte(func, allocator, 1);
    // set_box_local r0, r1
    emit.op(func, allocator, .set_box_local); emit.byte(func, allocator, 0); emit.byte(func, allocator, 1);
    // self_tail_call r0, 1
    emit.op(func, allocator, .self_tail_call); emit.byte(func, allocator, 0); emit.byte(func, allocator, 1);

    disassemble(func, allocator);
    try std.testing.expect(func.code.items.len > 0);
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
