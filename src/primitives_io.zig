const std = @import("std");
const is_wasm = @import("builtin").os.tag == .wasi;
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const printer = @import("printer.zig");
const reader_mod = @import("reader.zig");
const primitives_control = @import("primitives_control.zig");
const Value = types.Value;
const NativeFn = types.NativeFn;
const PrimitiveError = primitives.PrimitiveError;

fn reg(vm: *vm_mod.VM, name: []const u8, func: types.NativeFnType, arity: NativeFn.Arity) !void {
    return primitives.reg(vm, name, func, arity);
}

pub fn registerIO(vm: *vm_mod.VM) !void {
    // I/O (with optional port argument)
    try reg(vm, "display", &display, .{ .variadic = 1 });
    try reg(vm, "write", &write, .{ .variadic = 1 });
    try reg(vm, "newline", &newline, .{ .variadic = 0 });

    // Port procedures
    try reg(vm, "current-input-port", &currentInputPort, .{ .exact = 0 });
    try reg(vm, "current-output-port", &currentOutputPort, .{ .exact = 0 });
    try reg(vm, "current-error-port", &currentErrorPort, .{ .exact = 0 });
    try reg(vm, "port?", &portP, .{ .exact = 1 });
    try reg(vm, "input-port?", &inputPortP, .{ .exact = 1 });
    try reg(vm, "output-port?", &outputPortP, .{ .exact = 1 });
    try reg(vm, "textual-port?", &textualPortP, .{ .exact = 1 });
    try reg(vm, "binary-port?", &binaryPortP, .{ .exact = 1 });
    try reg(vm, "input-port-open?", &inputPortOpenP, .{ .exact = 1 });
    try reg(vm, "output-port-open?", &outputPortOpenP, .{ .exact = 1 });
    try reg(vm, "open-input-file", &openInputFile, .{ .exact = 1 });
    try reg(vm, "open-output-file", &openOutputFile, .{ .exact = 1 });
    try reg(vm, "close-port", &closePort, .{ .exact = 1 });
    try reg(vm, "close-input-port", &closePort, .{ .exact = 1 });
    try reg(vm, "close-output-port", &closePort, .{ .exact = 1 });
    try reg(vm, "read-char", &readCharFn, .{ .variadic = 0 });
    try reg(vm, "peek-char", &peekCharFn, .{ .variadic = 0 });
    try reg(vm, "read-line", &readLineFn, .{ .variadic = 0 });
    try reg(vm, "char-ready?", &charReadyP, .{ .variadic = 0 });
    try reg(vm, "write-char", &writeCharFn, .{ .variadic = 1 });
    try reg(vm, "write-string", &writeStringFn, .{ .variadic = 1 });
    try reg(vm, "read", &readDatumFn, .{ .variadic = 0 });
    try reg(vm, "file-exists?", &fileExistsP, .{ .exact = 1 });
    try reg(vm, "eof-object?", &eofObjectP, .{ .exact = 1 });
    try reg(vm, "eof-object", &eofObjectFn, .{ .exact = 0 });
    // String ports
    try reg(vm, "open-input-string", &openInputString, .{ .exact = 1 });
    try reg(vm, "open-output-string", &openOutputString, .{ .exact = 0 });
    try reg(vm, "get-output-string", &getOutputString, .{ .exact = 1 });
    // Additional I/O
    try reg(vm, "read-string", &readStringFn, .{ .variadic = 1 });
    try reg(vm, "flush-output-port", &flushOutputPort, .{ .variadic = 0 });
    try reg(vm, "delete-file", &deleteFile, .{ .exact = 1 });
    // (scheme write) completions
    try reg(vm, "write-shared", &writeShared, .{ .variadic = 1 });
    try reg(vm, "write-simple", &write, .{ .variadic = 1 });
    // File I/O wrappers (R7RS 6.13)
    try reg(vm, "call-with-input-file", &callWithInputFile, .{ .exact = 2 });
    try reg(vm, "call-with-output-file", &callWithOutputFile, .{ .exact = 2 });
    try reg(vm, "call-with-port", &callWithPort, .{ .exact = 2 });
    try reg(vm, "with-input-from-file", &withInputFromFile, .{ .exact = 2 });
    try reg(vm, "with-output-to-file", &withOutputToFile, .{ .exact = 2 });
    // Binary port aliases (we don't distinguish text/binary)
    try reg(vm, "open-binary-input-file", &openBinaryInputFile, .{ .exact = 1 });
    try reg(vm, "open-binary-output-file", &openBinaryOutputFile, .{ .exact = 1 });
    // Binary I/O
    try reg(vm, "read-u8", &readU8Fn, .{ .variadic = 0 });
    try reg(vm, "peek-u8", &peekU8Fn, .{ .variadic = 0 });
    try reg(vm, "u8-ready?", &charReadyP, .{ .variadic = 0 });
    try reg(vm, "write-u8", &writeU8Fn, .{ .variadic = 1 });
    try reg(vm, "read-bytevector", &readBytevectorFn, .{ .variadic = 1 });
    try reg(vm, "write-bytevector", &writeBytevectorFn, .{ .variadic = 1 });
}

pub fn registerIOSandboxed(vm: *vm_mod.VM) !void {
    try reg(vm, "display", &display, .{ .variadic = 1 });
    try reg(vm, "write", &write, .{ .variadic = 1 });
    try reg(vm, "newline", &newline, .{ .variadic = 0 });
    try reg(vm, "current-input-port", &currentInputPort, .{ .exact = 0 });
    try reg(vm, "current-output-port", &currentOutputPort, .{ .exact = 0 });
    try reg(vm, "current-error-port", &currentErrorPort, .{ .exact = 0 });
    try reg(vm, "port?", &portP, .{ .exact = 1 });
    try reg(vm, "input-port?", &inputPortP, .{ .exact = 1 });
    try reg(vm, "output-port?", &outputPortP, .{ .exact = 1 });
    try reg(vm, "textual-port?", &textualPortP, .{ .exact = 1 });
    try reg(vm, "binary-port?", &binaryPortP, .{ .exact = 1 });
    try reg(vm, "input-port-open?", &inputPortOpenP, .{ .exact = 1 });
    try reg(vm, "output-port-open?", &outputPortOpenP, .{ .exact = 1 });
    try reg(vm, "close-port", &closePort, .{ .exact = 1 });
    try reg(vm, "close-input-port", &closePort, .{ .exact = 1 });
    try reg(vm, "close-output-port", &closePort, .{ .exact = 1 });
    try reg(vm, "read-char", &readCharFn, .{ .variadic = 0 });
    try reg(vm, "peek-char", &peekCharFn, .{ .variadic = 0 });
    try reg(vm, "read-line", &readLineFn, .{ .variadic = 0 });
    try reg(vm, "char-ready?", &charReadyP, .{ .variadic = 0 });
    try reg(vm, "write-char", &writeCharFn, .{ .variadic = 1 });
    try reg(vm, "write-string", &writeStringFn, .{ .variadic = 1 });
    try reg(vm, "read", &readDatumFn, .{ .variadic = 0 });
    try reg(vm, "eof-object?", &eofObjectP, .{ .exact = 1 });
    try reg(vm, "eof-object", &eofObjectFn, .{ .exact = 0 });
    try reg(vm, "open-input-string", &openInputString, .{ .exact = 1 });
    try reg(vm, "open-output-string", &openOutputString, .{ .exact = 0 });
    try reg(vm, "get-output-string", &getOutputString, .{ .exact = 1 });
    try reg(vm, "read-string", &readStringFn, .{ .variadic = 1 });
    try reg(vm, "flush-output-port", &flushOutputPort, .{ .variadic = 0 });
    try reg(vm, "write-shared", &writeShared, .{ .variadic = 1 });
    try reg(vm, "write-simple", &write, .{ .variadic = 1 });
    try reg(vm, "call-with-port", &callWithPort, .{ .exact = 2 });
    try reg(vm, "read-u8", &readU8Fn, .{ .variadic = 0 });
    try reg(vm, "peek-u8", &peekU8Fn, .{ .variadic = 0 });
    try reg(vm, "u8-ready?", &charReadyP, .{ .variadic = 0 });
    try reg(vm, "write-u8", &writeU8Fn, .{ .variadic = 1 });
    try reg(vm, "read-bytevector", &readBytevectorFn, .{ .variadic = 1 });
    try reg(vm, "write-bytevector", &writeBytevectorFn, .{ .variadic = 1 });
}

// ---------------------------------------------------------------------------
// Port helpers
// ---------------------------------------------------------------------------

pub fn writeToFd(fd: std.posix.fd_t, bytes: []const u8) void {
    var total: usize = 0;
    while (total < bytes.len) {
        const result = std.posix.system.write(fd, bytes.ptr + total, bytes.len - total);
        if (result <= 0) break;
        total += @as(usize, @intCast(result));
    }
}

pub fn writeStdout(bytes: []const u8) void {
    writeToFd(1, bytes);
}

pub fn writeStderr(bytes: []const u8) void {
    writeToFd(2, bytes);
}

/// Get the output port: use args[arg_idx] if provided, else current-output-port.
fn getOutputPort(args: []const Value, arg_idx: usize, proc: []const u8) PrimitiveError!*types.Port {
    if (args.len > arg_idx) {
        if (!types.isPort(args[arg_idx])) return primitives.typeError(proc, "output port", args[arg_idx]);
        const port = types.toObject(args[arg_idx]).as(types.Port);
        if (!port.is_output) return primitives.typeError(proc, "output port", args[arg_idx]);
        if (!port.is_open) return primitives.typeError(proc, "open output port", args[arg_idx]);
        return port;
    }
    // Use current-output-port from VM
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    if (!types.isPort(vm.stdout_port)) return PrimitiveError.TypeError;
    return types.toObject(vm.stdout_port).as(types.Port);
}

/// Get the input port: use args[arg_idx] if provided, else current-input-port.
fn getInputPort(args: []const Value, arg_idx: usize, proc: []const u8) PrimitiveError!*types.Port {
    if (args.len > arg_idx) {
        if (!types.isPort(args[arg_idx])) return primitives.typeError(proc, "input port", args[arg_idx]);
        const port = types.toObject(args[arg_idx]).as(types.Port);
        if (!port.is_input) return primitives.typeError(proc, "input port", args[arg_idx]);
        if (!port.is_open) return primitives.typeError(proc, "open input port", args[arg_idx]);
        return port;
    }
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    if (!types.isPort(vm.stdin_port)) return PrimitiveError.TypeError;
    return types.toObject(vm.stdin_port).as(types.Port);
}

fn writeToPort(port: *types.Port, bytes: []const u8) void {
    if (port.is_string_port) {
        stringPortWrite(port, bytes);
        return;
    }
    writeToFd(port.fd, bytes);
}

fn stringPortWrite(port: *types.Port, bytes: []const u8) void {
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

// ---------------------------------------------------------------------------
// I/O -- Port-based (R7RS 6.13)
// ---------------------------------------------------------------------------

fn display(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = try getOutputPort(args, 1, "display");
    const s = printer.valueToString(gc.allocator, args[0], .display) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(s);
    writeToPort(port, s);
    return types.VOID;
}

fn write(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = try getOutputPort(args, 1, "write");
    const s = printer.valueToString(gc.allocator, args[0], .write) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(s);
    writeToPort(port, s);
    return types.VOID;
}

fn writeShared(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = try getOutputPort(args, 1, "write-shared");
    const s = printer.valueToString(gc.allocator, args[0], .shared) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(s);
    writeToPort(port, s);
    return types.VOID;
}

fn newline(args: []const Value) PrimitiveError!Value {
    const port = try getOutputPort(args, 0, "newline");
    writeToPort(port, "\n");
    return types.VOID;
}

// ---------------------------------------------------------------------------
// Port procedures (R7RS 6.13)
// ---------------------------------------------------------------------------

fn currentInputPort(args: []const Value) PrimitiveError!Value {
    _ = args;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    return vm.stdin_port;
}

fn currentOutputPort(args: []const Value) PrimitiveError!Value {
    _ = args;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    return vm.stdout_port;
}

fn currentErrorPort(args: []const Value) PrimitiveError!Value {
    _ = args;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    return vm.stderr_port;
}

fn portP(args: []const Value) PrimitiveError!Value {
    return if (types.isPort(args[0])) types.TRUE else types.FALSE;
}

fn inputPortP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return types.FALSE;
    const port = types.toObject(args[0]).as(types.Port);
    return if (port.is_input) types.TRUE else types.FALSE;
}

fn outputPortP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return types.FALSE;
    const port = types.toObject(args[0]).as(types.Port);
    return if (port.is_output) types.TRUE else types.FALSE;
}

fn textualPortP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return types.FALSE;
    const port = types.toObject(args[0]).as(types.Port);
    return if (!port.is_binary) types.TRUE else types.FALSE;
}

fn binaryPortP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return types.FALSE;
    const port = types.toObject(args[0]).as(types.Port);
    return if (port.is_binary) types.TRUE else types.FALSE;
}

fn inputPortOpenP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return primitives.typeError("input-port-open?", "port", args[0]);
    const port = types.toObject(args[0]).as(types.Port);
    return if (port.is_input and port.is_open) types.TRUE else types.FALSE;
}

fn outputPortOpenP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return primitives.typeError("output-port-open?", "port", args[0]);
    const port = types.toObject(args[0]).as(types.Port);
    return if (port.is_output and port.is_open) types.TRUE else types.FALSE;
}

fn raiseFileError(gc: *@import("memory.zig").GC, msg_text: []const u8, irritant: Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    var msg = gc.allocString(msg_text) catch return PrimitiveError.OutOfMemory;
    gc.pushRoot(&msg) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    const irritants = gc.allocPair(irritant, types.NIL) catch return PrimitiveError.OutOfMemory;
    var irritants_root = irritants;
    gc.pushRoot(&irritants_root) catch return PrimitiveError.OutOfMemory;
    defer gc.popRoot();
    const err_obj = gc.allocErrorObject(msg, irritants_root) catch return PrimitiveError.OutOfMemory;
    types.toObject(err_obj).as(types.ErrorObject).error_type = .file;
    vm.current_exception = err_obj;
    return PrimitiveError.ExceptionRaised;
}

fn openInputFile(args: []const Value) PrimitiveError!Value {
    if (comptime is_wasm) return PrimitiveError.TypeError;
    if (!types.isString(args[0])) return primitives.typeError("open-input-file", "string", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const path = str.data[0..str.len];

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const fd = std.posix.openat(std.posix.AT.FDCWD, path_z, .{}, 0) catch {
        return raiseFileError(gc, "cannot open input file", args[0]);
    };
    errdefer _ = std.posix.system.close(fd);

    const owned_name = gc.allocator.dupe(u8, path) catch return PrimitiveError.OutOfMemory;
    return gc.allocPort(fd, true, false, owned_name, true) catch {
        gc.allocator.free(owned_name);
        return PrimitiveError.OutOfMemory;
    };
}

fn openOutputFile(args: []const Value) PrimitiveError!Value {
    if (comptime is_wasm) return PrimitiveError.TypeError;
    if (!types.isString(args[0])) return primitives.typeError("open-output-file", "string", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const path = str.data[0..str.len];

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const fd = std.posix.openat(std.posix.AT.FDCWD, path_z, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644) catch {
        return raiseFileError(gc, "cannot open output file", args[0]);
    };
    errdefer _ = std.posix.system.close(fd);

    const owned_name = gc.allocator.dupe(u8, path) catch return PrimitiveError.OutOfMemory;
    return gc.allocPort(fd, false, true, owned_name, true) catch {
        gc.allocator.free(owned_name);
        return PrimitiveError.OutOfMemory;
    };
}

fn openBinaryInputFile(args: []const Value) PrimitiveError!Value {
    const result = try openInputFile(args);
    types.toObject(result).as(types.Port).is_binary = true;
    return result;
}

fn openBinaryOutputFile(args: []const Value) PrimitiveError!Value {
    const result = try openOutputFile(args);
    types.toObject(result).as(types.Port).is_binary = true;
    return result;
}

fn closePort(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return primitives.typeError("close-port", "port", args[0]);
    const port = types.toObject(args[0]).as(types.Port);
    if (port.read_buf) |rb| {
        if (primitives.gc_instance) |gc| {
            gc.allocator.free(rb);
        }
        port.read_buf = null;
        port.read_buf_len = 0;
    }
    if (port.is_open and port.fd > 2 and !port.is_string_port) {
        _ = std.posix.system.close(port.fd);
    }
    port.is_open = false;
    return types.VOID;
}

fn readOneByte(port: *types.Port) ?u8 {
    // Check peek buffer first
    if (port.peek_byte) |b| {
        port.peek_byte = null;
        return b;
    }
    // Check peek continuation bytes (from multi-byte peek-char)
    if (port.peek_extra_len > 0) {
        const b = port.peek_extra[0];
        port.peek_extra[0] = port.peek_extra[1];
        port.peek_extra[1] = port.peek_extra[2];
        port.peek_extra_len -= 1;
        return b;
    }
    // Check read buffer (from prior (read) that buffered excess)
    if (port.read_buf) |rb| {
        if (port.read_buf_len > 0) {
            const pos = rb.len - port.read_buf_len;
            const byte = rb[pos];
            port.read_buf_len -= 1;
            if (port.read_buf_len == 0) {
                if (primitives.gc_instance) |gc| {
                    gc.allocator.free(rb);
                }
                port.read_buf = null;
            }
            return byte;
        }
    }
    // String input port
    if (port.is_string_port) {
        const data = port.string_data orelse return null;
        if (port.string_pos >= data.len) return null;
        const byte = data[port.string_pos];
        port.string_pos += 1;
        return byte;
    }
    var buf: [1]u8 = undefined;
    const raw = std.posix.system.read(port.fd, &buf, buf.len);
    if (raw <= 0) return null;
    return buf[0];
}

fn readUtf8Char(port: *types.Port) ?u21 {
    const lead = readOneByte(port) orelse return null;
    const seq_len = std.unicode.utf8ByteSequenceLength(lead) catch return @intCast(lead);
    if (seq_len == 1) return @intCast(lead);
    var buf: [4]u8 = undefined;
    buf[0] = lead;
    for (1..seq_len) |i| {
        buf[i] = readOneByte(port) orelse return @intCast(lead);
    }
    return std.unicode.utf8Decode(buf[0..seq_len]) catch @intCast(lead);
}

fn readCharFn(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0, "read-char");
    const cp = readUtf8Char(port) orelse return types.EOF;
    return types.makeChar(cp);
}

fn peekCharFn(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0, "peek-char");
    if (port.peek_byte) |b| {
        const seq_len = std.unicode.utf8ByteSequenceLength(b) catch return types.makeChar(@intCast(b));
        if (seq_len == 1) return types.makeChar(@intCast(b));
        if (port.is_string_port) {
            const data = port.string_data orelse return types.EOF;
            const pos = port.string_pos;
            if (pos > 0) {
                const start = pos - 1;
                if (start + seq_len <= data.len) {
                    var buf: [4]u8 = undefined;
                    buf[0] = b;
                    for (1..seq_len) |i| buf[i] = data[start + i];
                    const cp = std.unicode.utf8Decode(buf[0..seq_len]) catch return types.makeChar(@intCast(b));
                    return types.makeChar(cp);
                }
            }
        } else if (port.peek_extra_len > 0) {
            var utf8_buf: [4]u8 = undefined;
            utf8_buf[0] = b;
            const avail: usize = @intCast(port.peek_extra_len);
            for (0..avail) |i| utf8_buf[i + 1] = port.peek_extra[i];
            if (avail >= seq_len - 1) {
                const cp = std.unicode.utf8Decode(utf8_buf[0..seq_len]) catch return types.makeChar(@intCast(b));
                return types.makeChar(cp);
            }
        }
        return types.makeChar(@intCast(b));
    }
    const port2 = port;
    const cp = readUtf8Char(port2) orelse return types.EOF;
    // Put back the encoded bytes for peeking — only store lead byte
    // and rewind string port position
    if (port2.is_string_port and port2.string_pos > 0) {
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &buf) catch 1;
        port2.string_pos -= len;
    } else {
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &buf) catch 1;
        port2.peek_byte = buf[0];
        if (len > 1) {
            for (1..len) |i| port2.peek_extra[i - 1] = buf[i];
            port2.peek_extra_len = @intCast(len - 1);
        }
    }
    return types.makeChar(cp);
}

fn readLineFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = try getInputPort(args, 0, "read-line");

    var line_buf: std.ArrayList(u8) = .empty;
    defer line_buf.deinit(gc.allocator);

    while (true) {
        const byte = readOneByte(port) orelse {
            // EOF
            if (line_buf.items.len == 0) return types.EOF;
            break;
        };
        if (byte == '\n') break;
        if (byte == '\r') {
            // Check for \r\n
            const next = readOneByte(port);
            if (next) |nb| {
                if (nb != '\n') {
                    port.peek_byte = nb; // put it back
                }
            }
            break;
        }
        line_buf.append(gc.allocator, byte) catch return PrimitiveError.OutOfMemory;
    }

    return gc.allocString(line_buf.items) catch return PrimitiveError.OutOfMemory;
}

fn charReadyP(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0, "char-ready?");
    if (port.peek_byte != null or port.peek_extra_len > 0) return types.TRUE;
    // For simplicity, always return #t (non-blocking check not worth the complexity)
    return types.TRUE;
}

fn writeCharFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return primitives.typeError("write-char", "character", args[0]);
    const port = try getOutputPort(args, 1, "write-char");
    const cp = types.toChar(args[0]);
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(cp, &buf) catch return primitives.typeError("write-char", "valid unicode character", args[0]);
    writeToPort(port, buf[0..len]);
    return types.VOID;
}

fn writeStringFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return primitives.typeError("write-string", "string", args[0]);
    const port = try getOutputPort(args, 1, "write-string");
    const str = types.toObject(args[0]).as(types.SchemeString);
    const data = str.data[0..str.len];
    const string_mod = @import("primitives_string.zig");
    const cp_count = string_mod.utf8CodepointCount(data);
    var start_cp: usize = 0;
    var end_cp: usize = cp_count;
    if (args.len > 2) {
        if (!types.isFixnum(args[2])) return primitives.typeError("write-string", "integer", args[2]);
        start_cp = @intCast(types.toFixnum(args[2]));
    }
    if (args.len > 3) {
        if (!types.isFixnum(args[3])) return primitives.typeError("write-string", "integer", args[3]);
        end_cp = @intCast(types.toFixnum(args[3]));
    }
    if (start_cp > end_cp or end_cp > cp_count) return primitives.typeError("write-string", "valid range", args[0]);
    const byte_start = string_mod.utf8IndexToByteOffset(data, start_cp) orelse return primitives.typeError("write-string", "valid start index", args[0]);
    const byte_end = string_mod.utf8IndexToByteOffset(data, end_cp) orelse return primitives.typeError("write-string", "valid end index", args[0]);
    writeToPort(port, data[byte_start..byte_end]);
    return types.VOID;
}

fn readDatumFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = try getInputPort(args, 0, "read");

    // For string ports, read directly from the string data
    if (port.is_string_port) {
        const data = port.string_data orelse return types.EOF;
        if (port.string_pos >= data.len) return types.EOF;

        // Handle any peeked byte
        var source: []const u8 = data[port.string_pos..];
        var prefix: [1]u8 = undefined;
        var combined: std.ArrayList(u8) = .empty;
        defer combined.deinit(gc.allocator);
        if (port.peek_byte) |b| {
            prefix[0] = b;
            port.peek_byte = null;
            combined.append(gc.allocator, prefix[0]) catch return PrimitiveError.OutOfMemory;
            combined.appendSlice(gc.allocator, source) catch return PrimitiveError.OutOfMemory;
            source = combined.items;
        }

        var reader = reader_mod.Reader.init(gc, source);
        defer reader.deinit();
        const datum = reader.readDatum() catch |err| {
            if (err == reader_mod.ReadError.UnexpectedEof or err == reader_mod.ReadError.OutOfMemory) return types.EOF;
            var msg = gc.allocString("read error") catch return PrimitiveError.OutOfMemory;
            gc.pushRoot(&msg) catch return PrimitiveError.OutOfMemory;
            defer gc.popRoot();
            const err_obj = gc.allocErrorObject(msg, types.NIL) catch return PrimitiveError.OutOfMemory;
            const errObj = types.toObject(err_obj).as(types.ErrorObject);
            errObj.error_type = .read;
            const raise_args = [1]Value{err_obj};
            return primitives_control.raiseFn(&raise_args);
        };
        // Advance string_pos by amount consumed
        port.string_pos += reader.pos;
        if (combined.items.len > 0 and reader.pos > 0) {
            // Adjust for the prefix byte
            port.string_pos -= 1;
        }
        return datum;
    }

    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gc.allocator);

    // Consume any existing read buffer first
    if (port.read_buf) |rb| {
        const pos = rb.len - port.read_buf_len;
        buf.appendSlice(gc.allocator, rb[pos .. pos + port.read_buf_len]) catch return PrimitiveError.OutOfMemory;
        gc.allocator.free(rb);
        port.read_buf = null;
        port.read_buf_len = 0;
    }

    // Consume any peeked bytes
    if (port.peek_byte) |b| {
        buf.append(gc.allocator, b) catch return PrimitiveError.OutOfMemory;
        port.peek_byte = null;
    }
    while (port.peek_extra_len > 0) {
        buf.append(gc.allocator, port.peek_extra[0]) catch return PrimitiveError.OutOfMemory;
        port.peek_extra[0] = port.peek_extra[1];
        port.peek_extra[1] = port.peek_extra[2];
        port.peek_extra_len -= 1;
    }

    // Read from fd (appends after any buffered data)
    var tmp: [4096]u8 = undefined;
    while (true) {
        const raw_n = std.posix.system.read(port.fd, &tmp, tmp.len);
        if (raw_n <= 0) break;
        const n: usize = @intCast(raw_n);
        if (n == 0) break;
        buf.appendSlice(gc.allocator, tmp[0..n]) catch return PrimitiveError.OutOfMemory;
    }

    if (buf.items.len == 0) return types.EOF;

    // Parse one datum
    var reader = reader_mod.Reader.init(gc, buf.items);
    defer reader.deinit();
    const datum = reader.readDatum() catch return types.EOF;

    // Save unconsumed bytes back to port buffer
    const remaining = buf.items[reader.pos..];
    if (remaining.len > 0) {
        const saved = gc.allocator.alloc(u8, remaining.len) catch return PrimitiveError.OutOfMemory;
        @memcpy(saved, remaining);
        port.read_buf = saved;
        port.read_buf_len = remaining.len;
    }

    return datum;
}

fn fileExistsP(args: []const Value) PrimitiveError!Value {
    if (comptime is_wasm) return types.FALSE;
    if (!types.isString(args[0])) return primitives.typeError("file-exists?", "string", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const path = str.data[0..str.len];

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const fd = std.posix.openat(std.posix.AT.FDCWD, path_z, .{}, 0) catch {
        return types.FALSE;
    };
    _ = std.posix.system.close(fd);
    return types.TRUE;
}

fn eofObjectP(args: []const Value) PrimitiveError!Value {
    return if (args[0] == types.EOF) types.TRUE else types.FALSE;
}

fn eofObjectFn(args: []const Value) PrimitiveError!Value {
    _ = args;
    return types.EOF;
}

// ---------------------------------------------------------------------------
// String ports (R7RS 6.13)
// ---------------------------------------------------------------------------

fn openInputString(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return primitives.typeError("open-input-string", "string", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    return gc.allocStringInputPort(str.data[0..str.len]) catch return PrimitiveError.OutOfMemory;
}

fn openOutputString(args: []const Value) PrimitiveError!Value {
    _ = args;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocStringOutputPort() catch return PrimitiveError.OutOfMemory;
}

fn getOutputString(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return primitives.typeError("get-output-string", "port", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = types.toObject(args[0]).as(types.Port);
    if (!port.is_string_port or !port.is_output) return primitives.typeError("get-output-string", "output string port", args[0]);
    const buf = port.string_out_buf orelse return gc.allocString("") catch return PrimitiveError.OutOfMemory;
    return gc.allocString(buf[0..port.string_out_len]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Additional I/O procedures
// ---------------------------------------------------------------------------

fn readStringFn(args: []const Value) PrimitiveError!Value {
    // (read-string k [port]) -- read k characters
    if (!types.isFixnum(args[0])) return primitives.typeError("read-string", "integer", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const k = types.toFixnum(args[0]);
    if (k < 0) return primitives.typeError("read-string", "non-negative integer", args[0]);
    const count: usize = @intCast(@as(u64, @bitCast(k)));
    const port = try getInputPort(args, 1, "read-string");

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(gc.allocator);

    var chars_read: usize = 0;
    while (chars_read < count) {
        const cp = readUtf8Char(port) orelse break;
        var buf: [4]u8 = undefined;
        const len = std.unicode.utf8Encode(cp, &buf) catch break;
        result.appendSlice(gc.allocator, buf[0..len]) catch return PrimitiveError.OutOfMemory;
        chars_read += 1;
    }
    if (result.items.len == 0) return types.EOF;
    return gc.allocString(result.items) catch return PrimitiveError.OutOfMemory;
}

fn flushOutputPort(args: []const Value) PrimitiveError!Value {
    // For our implementation, flushing is a no-op since we write directly
    if (args.len > 0) {
        if (!types.isPort(args[0])) return primitives.typeError("flush-output-port", "port", args[0]);
    }
    return types.VOID;
}

fn deleteFile(args: []const Value) PrimitiveError!Value {
    if (comptime is_wasm) return PrimitiveError.TypeError;
    if (!types.isString(args[0])) return primitives.typeError("delete-file", "string", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const path = str.data[0..str.len];

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const result = std.posix.system.unlink(path_z);
    if (result < 0) {
        var msg = gc.allocString("cannot delete file") catch return PrimitiveError.OutOfMemory;
        gc.pushRoot(&msg) catch return PrimitiveError.OutOfMemory;
        defer gc.popRoot();
        var irritant = gc.allocString(path) catch return PrimitiveError.OutOfMemory;
        gc.pushRoot(&irritant) catch return PrimitiveError.OutOfMemory;
        defer gc.popRoot();
        var irr_list = gc.allocPair(irritant, types.NIL) catch return PrimitiveError.OutOfMemory;
        gc.pushRoot(&irr_list) catch return PrimitiveError.OutOfMemory;
        defer gc.popRoot();
        const err_obj = gc.allocErrorObject(msg, irr_list) catch return PrimitiveError.OutOfMemory;
        types.toObject(err_obj).as(types.ErrorObject).error_type = .file;
        const raise_args = [1]Value{err_obj};
        return primitives_control.raiseFn(&raise_args);
    }
    return types.VOID;
}

// ---------------------------------------------------------------------------
// File I/O wrappers (R7RS 6.13)
// ---------------------------------------------------------------------------

/// (call-with-input-file string proc)
fn callWithInputFile(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    // Open file
    const port_val = try openInputFile(&[_]Value{args[0]});
    // Call proc with port
    const result = vm.callWithArgs(args[1], &[_]Value{port_val}) catch |err| {
        // Close port on error
        _ = closePort(&[_]Value{port_val}) catch {};
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError, // bare-ok: catch fallback
        };
    };
    // Close port
    _ = try closePort(&[_]Value{port_val});
    return result;
}

/// (call-with-output-file string proc)
fn callWithOutputFile(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const port_val = try openOutputFile(&[_]Value{args[0]});
    const result = vm.callWithArgs(args[1], &[_]Value{port_val}) catch |err| {
        _ = closePort(&[_]Value{port_val}) catch {};
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError, // bare-ok: catch fallback
        };
    };
    _ = try closePort(&[_]Value{port_val});
    return result;
}

/// (call-with-port port proc)
fn callWithPort(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return primitives.typeError("call-with-port", "port", args[0]);
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const result = vm.callWithArgs(args[1], &[_]Value{args[0]}) catch |err| {
        _ = closePort(&[_]Value{args[0]}) catch {};
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError, // bare-ok: catch fallback
        };
    };
    _ = try closePort(&[_]Value{args[0]});
    return result;
}

/// (with-input-from-file string thunk)
fn withInputFromFile(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const port_val = try openInputFile(&[_]Value{args[0]});
    // Save current input port
    const saved = vm.stdin_port;
    vm.stdin_port = port_val;
    const result = vm.callWithArgs(args[1], &[_]Value{}) catch |err| {
        vm.stdin_port = saved;
        _ = closePort(&[_]Value{port_val}) catch {};
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError, // bare-ok: catch fallback
        };
    };
    vm.stdin_port = saved;
    _ = try closePort(&[_]Value{port_val});
    return result;
}

/// (with-output-to-file string thunk)
fn withOutputToFile(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError; // bare-ok: no VM
    const port_val = try openOutputFile(&[_]Value{args[0]});
    const saved = vm.stdout_port;
    vm.stdout_port = port_val;
    const result = vm.callWithArgs(args[1], &[_]Value{}) catch |err| {
        vm.stdout_port = saved;
        _ = closePort(&[_]Value{port_val}) catch {};
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError, // bare-ok: catch fallback
        };
    };
    vm.stdout_port = saved;
    _ = try closePort(&[_]Value{port_val});
    return result;
}

// ---------------------------------------------------------------------------
// Binary I/O (R7RS 6.13.3)
// ---------------------------------------------------------------------------

fn readU8Fn(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0, "read-u8");
    const byte = readOneByte(port) orelse return types.EOF;
    return types.makeFixnum(@intCast(byte));
}

fn peekU8Fn(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0, "peek-u8");
    if (port.peek_byte) |b| {
        return types.makeFixnum(@intCast(b));
    }
    const byte = readOneByte(port) orelse return types.EOF;
    port.peek_byte = byte;
    return types.makeFixnum(@intCast(byte));
}

fn writeU8Fn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return primitives.typeError("write-u8", "integer", args[0]);
    const port = try getOutputPort(args, 1, "write-u8");
    const val = types.toFixnum(args[0]);
    if (val < 0 or val > 255) return primitives.typeError("write-u8", "exact integer 0-255", args[0]);
    const byte: u8 = @intCast(@as(u64, @bitCast(val)));
    const buf = [1]u8{byte};
    writeToPort(port, &buf);
    return types.VOID;
}

fn readBytevectorFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return primitives.typeError("read-bytevector", "integer", args[0]);
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const k = types.toFixnum(args[0]);
    if (k < 0) return primitives.typeError("read-bytevector", "non-negative integer", args[0]);
    const count: usize = @intCast(@as(u64, @bitCast(k)));
    const port = try getInputPort(args, 1, "read-bytevector");

    var result = gc.allocator.alloc(u8, count) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(result);
    var bytes_read: usize = 0;
    while (bytes_read < count) {
        const byte = readOneByte(port) orelse break;
        result[bytes_read] = byte;
        bytes_read += 1;
    }
    if (bytes_read == 0) return types.EOF;
    return gc.allocBytevector(result[0..bytes_read]) catch return PrimitiveError.OutOfMemory;
}

fn writeBytevectorFn(args: []const Value) PrimitiveError!Value {
    if (!types.isBytevector(args[0])) return primitives.typeError("write-bytevector", "bytevector", args[0]);
    const port = try getOutputPort(args, 1, "write-bytevector");
    const bv = types.toBytevector(args[0]);
    var start: usize = 0;
    var end: usize = bv.data.len;
    if (args.len > 2) {
        if (!types.isFixnum(args[2])) return primitives.typeError("write-bytevector", "integer", args[2]);
        const s = types.toFixnum(args[2]);
        if (s < 0) return primitives.typeError("write-bytevector", "non-negative integer", args[2]);
        start = @intCast(s);
    }
    if (args.len > 3) {
        if (!types.isFixnum(args[3])) return primitives.typeError("write-bytevector", "integer", args[3]);
        const e = types.toFixnum(args[3]);
        if (e < 0) return primitives.typeError("write-bytevector", "non-negative integer", args[3]);
        end = @intCast(e);
    }
    if (start > end or end > bv.data.len) return primitives.typeError("write-bytevector", "valid range", args[0]);
    writeToPort(port, bv.data[start..end]);
    return types.VOID;
}
