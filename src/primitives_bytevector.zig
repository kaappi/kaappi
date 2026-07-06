const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const memory = @import("memory.zig");
const primitives_io = @import("primitives_io.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;
const LS = primitives.LibSet;

pub const specs = [_]primitives.PrimSpec{
    .{ .name = "bytevector?", .func = &bytevectorP, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "make-bytevector", .func = &makeBytevector, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "bytevector", .func = &bytevectorFn, .arity = .{ .variadic = 0 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "bytevector-length", .func = &bytevectorLength, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "bytevector-u8-ref", .func = &bytevectorU8Ref, .arity = .{ .exact = 2 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "bytevector-u8-set!", .func = &bytevectorU8Set, .arity = .{ .exact = 3 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "bytevector-copy", .func = &bytevectorCopy, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "bytevector-copy!", .func = &bytevectorCopyBang, .arity = .{ .variadic = 3 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "bytevector-append", .func = &bytevectorAppend, .arity = .{ .variadic = 0 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "utf8->string", .func = &utf8ToString, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "string->utf8", .func = &stringToUtf8, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "read-u8", .func = &readU8Fn, .arity = .{ .variadic = 0 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "peek-u8", .func = &peekU8Fn, .arity = .{ .variadic = 0 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "write-u8", .func = &writeU8Fn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "u8-ready?", .func = &u8ReadyP, .arity = .{ .variadic = 0 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "read-bytevector", .func = &readBytevectorFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "write-bytevector", .func = &writeBytevectorFn, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "open-input-bytevector", .func = &openInputBytevector, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "open-output-bytevector", .func = &openOutputBytevector, .arity = .{ .exact = 0 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "get-output-bytevector", .func = &getOutputBytevector, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
    .{ .name = "read-bytevector!", .func = &readBytevectorMut, .arity = .{ .variadic = 1 }, .libs = LS.initOne(.scheme_base) },
};

// ---------------------------------------------------------------------------
// Bytevector procedures (R7RS 6.9)
// ---------------------------------------------------------------------------

fn bytevectorP(args: []const Value) PrimitiveError!Value {
    return if (types.isBytevector(args[0])) types.TRUE else types.FALSE;
}

fn makeBytevector(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return primitives.typeError("make-bytevector", "non-negative integer", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const bv = types.toBytevector(args[0]);

    const range = try primitives.parseOptionalRange(args, 1, bv.data.len, "bytevector-copy");
    const start = range.start;
    const end = range.end;
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

    const range = try primitives.parseOptionalRange(args, 3, from.data.len, "bytevector-copy!");
    const start = range.start;
    const end = range.end;
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const bv = types.toBytevector(args[0]);

    const range = try primitives.parseOptionalRange(args, 1, bv.data.len, "utf8->string");
    const start = range.start;
    const end = range.end;
    return gc.allocString(bv.data[start..end]) catch return PrimitiveError.OutOfMemory;
}

fn stringToUtf8(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return primitives.typeError("string->utf8", "string", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const string_mod = @import("primitives_string.zig");

    const cp_count = string_mod.utf8CodepointCount(str.data[0..str.len]);
    const range = try primitives.parseOptionalRange(args, 1, cp_count, "string->utf8");
    const start_cp = range.start;
    const end_cp = range.end;
    const byte_start = string_mod.utf8IndexToByteOffset(str.data[0..str.len], start_cp) orelse return primitives.typeError("string->utf8", "valid index", args[0]);
    const byte_end = string_mod.utf8IndexToByteOffset(str.data[0..str.len], end_cp) orelse return primitives.typeError("string->utf8", "valid index", args[0]);
    return gc.allocBytevector(str.data[byte_start..byte_end]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Binary I/O (R7RS 6.13.3)
// ---------------------------------------------------------------------------

fn getInputPort(args: []const Value, arg_idx: usize, proc_name: []const u8) PrimitiveError!*types.Port {
    if (args.len > arg_idx) {
        if (!types.isPort(args[arg_idx])) return primitives.typeError(proc_name, "input port", args[arg_idx]);
        const port = types.toObject(args[arg_idx]).as(types.Port);
        if (!port.is_input) return primitives.typeError(proc_name, "input port", args[arg_idx]);
        if (!port.is_open) return primitives.typeError(proc_name, "open port", args[arg_idx]);
        return port;
    }
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const port_val = if (vm.current_input_port_param != types.VOID)
        vm.getParameterValue(types.toParameter(vm.current_input_port_param))
    else
        vm.stdin_port;
    if (!types.isPort(port_val)) return primitives.typeError(proc_name, "input port", port_val);
    return types.toObject(port_val).as(types.Port);
}

fn getOutputPort(args: []const Value, arg_idx: usize, proc_name: []const u8) PrimitiveError!*types.Port {
    if (args.len > arg_idx) {
        if (!types.isPort(args[arg_idx])) return primitives.typeError(proc_name, "output port", args[arg_idx]);
        const port = types.toObject(args[arg_idx]).as(types.Port);
        if (!port.is_output) return primitives.typeError(proc_name, "output port", args[arg_idx]);
        if (!port.is_open) return primitives.typeError(proc_name, "open port", args[arg_idx]);
        return port;
    }
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const port_val = if (vm.current_output_port_param != types.VOID)
        vm.getParameterValue(types.toParameter(vm.current_output_port_param))
    else
        vm.stdout_port;
    if (!types.isPort(port_val)) return primitives.typeError(proc_name, "output port", port_val);
    return types.toObject(port_val).as(types.Port);
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
    while (true) {
        const raw = std.posix.system.read(port.fd, &buf, buf.len);
        if (raw < 0) {
            if (std.posix.errno(raw) == .INTR) continue;
            return null;
        }
        if (raw == 0) return null;
        return buf[0];
    }
}

fn readU8Fn(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0, "read-u8");
    const byte = portReadOneByte(port) orelse return types.EOF;
    return types.makeFixnum(@intCast(byte));
}

fn peekU8Fn(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0, "peek-u8");
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
    const port = try getOutputPort(args, 1, "write-u8");
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
    const gc = memory.gc_instance orelse return;
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
    // For simplicity, always return #t (non-blocking check not worth the complexity)
    _ = try getInputPort(args, 0, "u8-ready?");
    return types.TRUE;
}

fn readBytevectorFn(args: []const Value) PrimitiveError!Value {
    // (read-bytevector k [port])
    if (!types.isFixnum(args[0])) return primitives.typeError("read-bytevector", "exact integer", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const k = types.toFixnum(args[0]);
    if (k < 0) return primitives.typeError("read-bytevector", "non-negative integer", args[0]);
    const count: usize = @intCast(@as(u64, @bitCast(k)));
    const port = try getInputPort(args, 1, "read-bytevector");

    if (count == 0) return gc.allocBytevector(&.{}) catch return PrimitiveError.OutOfMemory;

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
    const port = try getOutputPort(args, 1, "write-bytevector");

    const range = try primitives.parseOptionalRange(args, 2, bv.data.len, "write-bytevector");
    const start = range.start;
    const end = range.end;

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
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port_val = gc.allocStringInputPort(bv_data: {
        const bv = types.toBytevector(args[0]);
        break :bv_data bv.data;
    }) catch return PrimitiveError.OutOfMemory;
    types.toObject(port_val).as(types.Port).is_binary = true;
    return port_val;
}

fn openOutputBytevector(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port_val = gc.allocStringOutputPort() catch return PrimitiveError.OutOfMemory;
    types.toObject(port_val).as(types.Port).is_binary = true;
    return port_val;
}

fn getOutputBytevector(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return primitives.typeError("get-output-bytevector", "output bytevector port", args[0]);
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = types.toObject(args[0]).as(types.Port);
    if (!port.is_string_port or !port.is_output or !port.is_binary) return primitives.typeError("get-output-bytevector", "output bytevector port", args[0]);
    const data = if (port.string_out_buf) |buf| buf[0..port.string_out_len] else &[_]u8{};
    return gc.allocBytevector(data) catch return PrimitiveError.OutOfMemory;
}

fn readBytevectorMut(args: []const Value) PrimitiveError!Value {
    // (read-bytevector! bv port [start [end]])
    if (!types.isBytevector(args[0])) return primitives.typeError("read-bytevector!", "bytevector", args[0]);
    const bv = types.toBytevector(args[0]);
    const port = try getInputPort(args, 1, "read-bytevector!");
    const len = bv.data.len;

    const range = try primitives.parseOptionalRange(args, 2, len, "read-bytevector!");
    const start = range.start;
    const end = range.end;

    var read_count: usize = 0;
    while (start + read_count < end) {
        const byte = portReadOneByte(port) orelse break;
        bv.data[start + read_count] = byte;
        read_count += 1;
    }
    if (start == end) return types.makeFixnum(0);
    if (read_count == 0) return types.EOF;
    return types.makeFixnum(@intCast(read_count));
}
