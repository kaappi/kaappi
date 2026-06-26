const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const primitives_io = @import("primitives_io.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    return primitives.reg(vm, name, func, arity);
}

pub fn registerBytevector(vm: *vm_mod.VM) !void {
    try reg(vm, "bytevector?", &bytevectorP, .{ .exact = 1 });
    try reg(vm, "make-bytevector", &makeBytevector, .{ .variadic = 1 });
    try reg(vm, "bytevector", &bytevectorFn, .{ .variadic = 0 });
    try reg(vm, "bytevector-length", &bytevectorLength, .{ .exact = 1 });
    try reg(vm, "bytevector-u8-ref", &bytevectorU8Ref, .{ .exact = 2 });
    try reg(vm, "bytevector-u8-set!", &bytevectorU8Set, .{ .exact = 3 });
    try reg(vm, "bytevector-copy", &bytevectorCopy, .{ .variadic = 1 });
    try reg(vm, "bytevector-copy!", &bytevectorCopyBang, .{ .variadic = 3 });
    try reg(vm, "bytevector-append", &bytevectorAppend, .{ .variadic = 0 });
    try reg(vm, "utf8->string", &utf8ToString, .{ .variadic = 1 });
    try reg(vm, "string->utf8", &stringToUtf8, .{ .variadic = 1 });
    // Binary I/O
    try reg(vm, "read-u8", &readU8Fn, .{ .variadic = 0 });
    try reg(vm, "peek-u8", &peekU8Fn, .{ .variadic = 0 });
    try reg(vm, "write-u8", &writeU8Fn, .{ .variadic = 1 });
    try reg(vm, "u8-ready?", &u8ReadyP, .{ .variadic = 0 });
    try reg(vm, "read-bytevector", &readBytevectorFn, .{ .variadic = 1 });
    try reg(vm, "write-bytevector", &writeBytevectorFn, .{ .variadic = 1 });
    // Bytevector ports (R7RS 6.13)
    try reg(vm, "open-input-bytevector", &openInputBytevector, .{ .exact = 1 });
    try reg(vm, "open-output-bytevector", &openOutputBytevector, .{ .exact = 0 });
    try reg(vm, "get-output-bytevector", &getOutputBytevector, .{ .exact = 1 });
    try reg(vm, "read-bytevector!", &readBytevectorMut, .{ .variadic = 1 });
}

// ---------------------------------------------------------------------------
// Bytevector procedures (R7RS 6.9)
// ---------------------------------------------------------------------------

fn bytevectorP(args: []const Value) PrimitiveError!Value {
    return if (types.isBytevector(args[0])) types.TRUE else types.FALSE;
}

fn makeBytevector(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return primitives.typeError("make-bytevector", "non-negative integer", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const k = types.toFixnum(args[0]);
    if (k < 0) return primitives.typeError("make-bytevector", "non-negative integer", args[0]);
    const size: usize = @intCast(k);
    const fill: u8 = if (args.len > 1) blk: {
        if (!types.isFixnum(args[1])) return primitives.typeError("make-bytevector", "exact integer 0-255", args[1]);
        const f = types.toFixnum(args[1]);
        if (f < 0 or f > 255) return primitives.typeError("make-bytevector", "exact integer 0-255", args[1]);
        break :blk @intCast(@as(u64, @bitCast(f)));
    } else 0;
    return gc.allocBytevectorFill(size, fill) catch return PrimitiveError.OutOfMemory;
}

fn bytevectorFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const data = gc.allocator.alloc(u8, args.len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(data);
    for (args, 0..) |a, i| {
        if (!types.isFixnum(a)) return primitives.typeError("bytevector", "exact integer 0-255", a);
        const n = types.toFixnum(a);
        if (n < 0 or n > 255) return primitives.typeError("bytevector", "exact integer 0-255", a);
        data[i] = @intCast(@as(u64, @bitCast(n)));
    }
    return gc.allocBytevector(data) catch return PrimitiveError.OutOfMemory;
}

fn bytevectorLength(args: []const Value) PrimitiveError!Value {
    if (!types.isBytevector(args[0])) return primitives.typeError("bytevector-length", "bytevector", args[0]);
    const bv = types.toBytevector(args[0]);
    return types.makeFixnum(@intCast(bv.data.len));
}

fn bytevectorU8Ref(args: []const Value) PrimitiveError!Value {
    if (!types.isBytevector(args[0])) return primitives.typeError("bytevector-u8-ref", "bytevector", args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("bytevector-u8-ref", "exact integer", args[1]);
    const bv = types.toBytevector(args[0]);
    const idx = types.toFixnum(args[1]);
    if (idx < 0 or @as(usize, @intCast(idx)) >= bv.data.len) return primitives.typeError("bytevector-u8-ref", "valid index", args[1]);
    return types.makeFixnum(@intCast(bv.data[@intCast(@as(u64, @bitCast(idx)))]));
}

fn bytevectorU8Set(args: []const Value) PrimitiveError!Value {
    if (!types.isBytevector(args[0])) return primitives.typeError("bytevector-u8-set!", "bytevector", args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("bytevector-u8-set!", "exact integer", args[1]);
    if (!types.isFixnum(args[2])) return primitives.typeError("bytevector-u8-set!", "exact integer 0-255", args[2]);
    const bv = types.toBytevector(args[0]);
    const idx = types.toFixnum(args[1]);
    const val = types.toFixnum(args[2]);
    if (idx < 0 or @as(usize, @intCast(idx)) >= bv.data.len) return primitives.typeError("bytevector-u8-set!", "valid index", args[1]);
    if (val < 0 or val > 255) return primitives.typeError("bytevector-u8-set!", "exact integer 0-255", args[2]);
    bv.data[@intCast(@as(u64, @bitCast(idx)))] = @intCast(@as(u64, @bitCast(val)));
    return types.VOID;
}

fn bytevectorCopy(args: []const Value) PrimitiveError!Value {
    if (!types.isBytevector(args[0])) return primitives.typeError("bytevector-copy", "bytevector", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const bv = types.toBytevector(args[0]);

    var start: usize = 0;
    var end: usize = bv.data.len;

    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return primitives.typeError("bytevector-copy", "exact integer", args[1]);
        const s = types.toFixnum(args[1]);
        if (s < 0) return primitives.typeError("bytevector-copy", "non-negative integer", args[1]);
        start = @intCast(@as(u64, @bitCast(s)));
    }
    if (args.len > 2) {
        if (!types.isFixnum(args[2])) return primitives.typeError("bytevector-copy", "exact integer", args[2]);
        const e = types.toFixnum(args[2]);
        if (e < 0) return primitives.typeError("bytevector-copy", "non-negative integer", args[2]);
        end = @intCast(@as(u64, @bitCast(e)));
    }
    if (start > end or end > bv.data.len) return primitives.typeError("bytevector-copy", "valid range", args[0]);
    return gc.allocBytevector(bv.data[start..end]) catch return PrimitiveError.OutOfMemory;
}

fn bytevectorCopyBang(args: []const Value) PrimitiveError!Value {
    // (bytevector-copy! to at from [start [end]])
    if (!types.isBytevector(args[0])) return primitives.typeError("bytevector-copy!", "bytevector", args[0]);
    if (!types.isFixnum(args[1])) return primitives.typeError("bytevector-copy!", "exact integer", args[1]);
    if (!types.isBytevector(args[2])) return primitives.typeError("bytevector-copy!", "bytevector", args[2]);

    const to = types.toBytevector(args[0]);
    const at_val = types.toFixnum(args[1]);
    if (at_val < 0) return primitives.typeError("bytevector-copy!", "non-negative integer", args[1]);
    const at: usize = @intCast(@as(u64, @bitCast(at_val)));
    const from = types.toBytevector(args[2]);

    var start: usize = 0;
    var end: usize = from.data.len;

    if (args.len > 3) {
        if (!types.isFixnum(args[3])) return primitives.typeError("bytevector-copy!", "exact integer", args[3]);
        const s = types.toFixnum(args[3]);
        if (s < 0) return primitives.typeError("bytevector-copy!", "non-negative integer", args[3]);
        start = @intCast(@as(u64, @bitCast(s)));
    }
    if (args.len > 4) {
        if (!types.isFixnum(args[4])) return primitives.typeError("bytevector-copy!", "exact integer", args[4]);
        const e = types.toFixnum(args[4]);
        if (e < 0) return primitives.typeError("bytevector-copy!", "non-negative integer", args[4]);
        end = @intCast(@as(u64, @bitCast(e)));
    }
    if (start > end or end > from.data.len) return primitives.typeError("bytevector-copy!", "valid range", args[2]);
    const count = end - start;
    if (at + count > to.data.len) return primitives.typeError("bytevector-copy!", "valid range", args[0]);

    // Use memmove semantics for overlapping regions
    if (at <= start) {
        for (0..count) |i| {
            to.data[at + i] = from.data[start + i];
        }
    } else {
        var i = count;
        while (i > 0) {
            i -= 1;
            to.data[at + i] = from.data[start + i];
        }
    }
    return types.VOID;
}

fn bytevectorAppend(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    var total_len: usize = 0;
    for (args) |a| {
        if (!types.isBytevector(a)) return primitives.typeError("bytevector-append", "bytevector", a);
        total_len += types.toBytevector(a).data.len;
    }
    const result = gc.allocator.alloc(u8, total_len) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(result);
    var pos: usize = 0;
    for (args) |a| {
        const bv = types.toBytevector(a);
        @memcpy(result[pos .. pos + bv.data.len], bv.data);
        pos += bv.data.len;
    }
    return gc.allocBytevector(result) catch return PrimitiveError.OutOfMemory;
}

fn utf8ToString(args: []const Value) PrimitiveError!Value {
    if (!types.isBytevector(args[0])) return primitives.typeError("utf8->string", "bytevector", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const bv = types.toBytevector(args[0]);

    var start: usize = 0;
    var end: usize = bv.data.len;
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return primitives.typeError("utf8->string", "exact integer", args[1]);
        const s = types.toFixnum(args[1]);
        if (s < 0) return primitives.typeError("utf8->string", "non-negative integer", args[1]);
        start = @intCast(@as(u64, @bitCast(s)));
    }
    if (args.len > 2) {
        if (!types.isFixnum(args[2])) return primitives.typeError("utf8->string", "exact integer", args[2]);
        const e = types.toFixnum(args[2]);
        if (e < 0) return primitives.typeError("utf8->string", "non-negative integer", args[2]);
        end = @intCast(@as(u64, @bitCast(e)));
    }
    if (start > end or end > bv.data.len) return primitives.typeError("utf8->string", "valid range", args[0]);
    return gc.allocString(bv.data[start..end]) catch return PrimitiveError.OutOfMemory;
}

fn stringToUtf8(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return primitives.typeError("string->utf8", "string", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const string_mod = @import("primitives_string.zig");

    const cp_count = string_mod.utf8CodepointCount(str.data[0..str.len]);
    var start_cp: usize = 0;
    var end_cp: usize = cp_count;
    if (args.len > 1) {
        if (!types.isFixnum(args[1])) return primitives.typeError("string->utf8", "exact integer", args[1]);
        const s = types.toFixnum(args[1]);
        if (s < 0) return primitives.typeError("string->utf8", "non-negative integer", args[1]);
        start_cp = @intCast(@as(u64, @bitCast(s)));
    }
    if (args.len > 2) {
        if (!types.isFixnum(args[2])) return primitives.typeError("string->utf8", "exact integer", args[2]);
        const e = types.toFixnum(args[2]);
        if (e < 0) return primitives.typeError("string->utf8", "non-negative integer", args[2]);
        end_cp = @intCast(@as(u64, @bitCast(e)));
    }
    if (start_cp > end_cp or end_cp > cp_count) return primitives.typeError("string->utf8", "valid range", args[0]);
    const byte_start = string_mod.utf8IndexToByteOffset(str.data[0..str.len], start_cp) orelse return primitives.typeError("string->utf8", "valid index", args[0]);
    const byte_end = string_mod.utf8IndexToByteOffset(str.data[0..str.len], end_cp) orelse return primitives.typeError("string->utf8", "valid index", args[0]);
    return gc.allocBytevector(str.data[byte_start..byte_end]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Binary I/O (R7RS 6.13.3)
// ---------------------------------------------------------------------------

fn getInputPort(args: []const Value, arg_idx: usize) PrimitiveError!*types.Port {
    if (args.len > arg_idx) {
        if (!types.isPort(args[arg_idx])) return primitives.typeError("read-u8", "input port", args[arg_idx]);
        const port = types.toObject(args[arg_idx]).as(types.Port);
        if (!port.is_input) return primitives.typeError("read-u8", "input port", args[arg_idx]);
        if (!port.is_open) return primitives.typeError("read-u8", "open port", args[arg_idx]);
        return port;
    }
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    if (!types.isPort(vm.stdin_port)) return primitives.typeError("read-u8", "input port", vm.stdin_port);
    return types.toObject(vm.stdin_port).as(types.Port);
}

fn getOutputPort(args: []const Value, arg_idx: usize) PrimitiveError!*types.Port {
    if (args.len > arg_idx) {
        if (!types.isPort(args[arg_idx])) return primitives.typeError("write-u8", "output port", args[arg_idx]);
        const port = types.toObject(args[arg_idx]).as(types.Port);
        if (!port.is_output) return primitives.typeError("write-u8", "output port", args[arg_idx]);
        if (!port.is_open) return primitives.typeError("write-u8", "open port", args[arg_idx]);
        return port;
    }
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    if (!types.isPort(vm.stdout_port)) return primitives.typeError("write-u8", "output port", vm.stdout_port);
    return types.toObject(vm.stdout_port).as(types.Port);
}

fn portReadOneByte(port: *types.Port) ?u8 {
    if (port.peek_byte) |b| {
        port.peek_byte = null;
        return b;
    }
    if (port.is_string_port) {
        const data = port.string_data orelse return null;
        if (port.string_pos >= data.len) return null;
        const b = data[port.string_pos];
        port.string_pos += 1;
        return b;
    }
    var buf: [1]u8 = undefined;
    const raw = std.posix.system.read(port.fd, &buf, buf.len);
    if (raw <= 0) return null;
    return buf[0];
}

fn readU8Fn(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0);
    const byte = portReadOneByte(port) orelse return types.EOF;
    return types.makeFixnum(@intCast(byte));
}

fn peekU8Fn(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0);
    if (port.peek_byte) |b| {
        return types.makeFixnum(@intCast(b));
    }
    const byte = portReadOneByte(port) orelse return types.EOF;
    port.peek_byte = byte;
    return types.makeFixnum(@intCast(byte));
}

fn writeU8Fn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return primitives.typeError("write-u8", "exact integer 0-255", args[0]);
    const n = types.toFixnum(args[0]);
    if (n < 0 or n > 255) return primitives.typeError("write-u8", "exact integer 0-255", args[0]);
    const port = try getOutputPort(args, 1);
    const byte: u8 = @intCast(@as(u64, @bitCast(n)));
    if (port.is_string_port) {
        portWriteBytes(port, &[_]u8{byte});
    } else {
        primitives_io.writeToFd(port.fd, &[_]u8{byte});
    }
    return types.VOID;
}

fn portWriteBytes(port: *types.Port, bytes: []const u8) void {
    if (!port.is_string_port) {
        primitives_io.writeToFd(port.fd, bytes);
        return;
    }
    // String output port: grow buffer as needed
    const gc = primitives.gc_instance orelse return;
    var buf = port.string_out_buf orelse return;
    const len = port.string_out_len;
    const cap = port.string_out_cap;
    if (len + bytes.len > cap) {
        const new_cap = @max(cap * 2, len + bytes.len);
        const new_buf = gc.allocator.realloc(buf, new_cap) catch return;
        port.string_out_buf = new_buf;
        buf = new_buf;
        port.string_out_cap = new_cap;
    }
    @memcpy(buf[len .. len + bytes.len], bytes);
    port.string_out_len = len + bytes.len;
}

fn u8ReadyP(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0);
    if (port.peek_byte != null) return types.TRUE;
    if (port.is_string_port) {
        const data = port.string_data orelse return types.TRUE;
        return if (port.string_pos < data.len) types.TRUE else types.TRUE;
    }
    return types.TRUE; // simplified
}

fn readBytevectorFn(args: []const Value) PrimitiveError!Value {
    // (read-bytevector k [port])
    if (!types.isFixnum(args[0])) return primitives.typeError("read-bytevector", "exact integer", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const k = types.toFixnum(args[0]);
    if (k < 0) return primitives.typeError("read-bytevector", "non-negative integer", args[0]);
    const count: usize = @intCast(@as(u64, @bitCast(k)));
    const port = try getInputPort(args, 1);

    const buf = gc.allocator.alloc(u8, count) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(buf);

    var read_count: usize = 0;
    while (read_count < count) {
        const byte = portReadOneByte(port) orelse break;
        buf[read_count] = byte;
        read_count += 1;
    }
    if (read_count == 0) return types.EOF;
    return gc.allocBytevector(buf[0..read_count]) catch return PrimitiveError.OutOfMemory;
}

fn writeBytevectorFn(args: []const Value) PrimitiveError!Value {
    // (write-bytevector bv [port [start [end]]])
    if (!types.isBytevector(args[0])) return primitives.typeError("write-bytevector", "bytevector", args[0]);
    const bv = types.toBytevector(args[0]);
    const port = try getOutputPort(args, 1);

    var start: usize = 0;
    var end: usize = bv.data.len;
    if (args.len > 2) {
        if (!types.isFixnum(args[2])) return primitives.typeError("write-bytevector", "exact integer", args[2]);
        const s = types.toFixnum(args[2]);
        if (s < 0) return primitives.typeError("write-bytevector", "non-negative integer", args[2]);
        start = @intCast(@as(u64, @bitCast(s)));
    }
    if (args.len > 3) {
        if (!types.isFixnum(args[3])) return primitives.typeError("write-bytevector", "exact integer", args[3]);
        const e = types.toFixnum(args[3]);
        if (e < 0) return primitives.typeError("write-bytevector", "non-negative integer", args[3]);
        end = @intCast(@as(u64, @bitCast(e)));
    }
    if (start > end or end > bv.data.len) return primitives.typeError("write-bytevector", "valid range", args[0]);

    if (port.is_string_port) {
        portWriteBytes(port, bv.data[start..end]);
    } else {
        primitives_io.writeToFd(port.fd, bv.data[start..end]);
    }
    return types.VOID;
}

// ---------------------------------------------------------------------------
// Bytevector ports (R7RS 6.13)
// ---------------------------------------------------------------------------

fn openInputBytevector(args: []const Value) PrimitiveError!Value {
    if (!types.isBytevector(args[0])) return primitives.typeError("open-input-bytevector", "bytevector", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port_val = gc.allocStringInputPort(bv_data: {
        const bv = types.toBytevector(args[0]);
        break :bv_data bv.data;
    }) catch return PrimitiveError.OutOfMemory;
    types.toObject(port_val).as(types.Port).is_binary = true;
    return port_val;
}

fn openOutputBytevector(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port_val = gc.allocStringOutputPort() catch return PrimitiveError.OutOfMemory;
    types.toObject(port_val).as(types.Port).is_binary = true;
    return port_val;
}

fn getOutputBytevector(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return primitives.typeError("get-output-bytevector", "output bytevector port", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = types.toObject(args[0]).as(types.Port);
    if (!port.is_string_port or !port.is_output) return primitives.typeError("get-output-bytevector", "output bytevector port", args[0]);
    const data = if (port.string_out_buf) |buf| buf[0..port.string_out_len] else &[_]u8{};
    return gc.allocBytevector(data) catch return PrimitiveError.OutOfMemory;
}

fn readBytevectorMut(args: []const Value) PrimitiveError!Value {
    // (read-bytevector! bv port [start [end]])
    if (!types.isBytevector(args[0])) return primitives.typeError("read-bytevector!", "bytevector", args[0]);
    const bv = types.toBytevector(args[0]);
    const port = try getInputPort(args, 1);
    const len = bv.data.len;

    var start: usize = 0;
    var end: usize = len;
    if (args.len > 2) {
        if (!types.isFixnum(args[2])) return primitives.typeError("read-bytevector!", "exact integer", args[2]);
        start = @intCast(types.toFixnum(args[2]));
    }
    if (args.len > 3) {
        if (!types.isFixnum(args[3])) return primitives.typeError("read-bytevector!", "exact integer", args[3]);
        end = @intCast(types.toFixnum(args[3]));
    }
    if (start > end or end > len) return primitives.typeError("read-bytevector!", "valid range", args[0]);

    var read_count: usize = 0;
    while (start + read_count < end) {
        const byte = portReadOneByte(port) orelse break;
        bv.data[start + read_count] = byte;
        read_count += 1;
    }
    if (read_count == 0 and start == end and len > 0) return types.makeFixnum(0);
    if (read_count == 0) return types.EOF;
    return types.makeFixnum(@intCast(read_count));
}
