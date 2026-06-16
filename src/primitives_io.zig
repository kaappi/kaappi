const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const printer = @import("printer.zig");
const reader_mod = @import("reader.zig");
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
    try reg(vm, "open-binary-input-file", &openInputFile, .{ .exact = 1 });
    try reg(vm, "open-binary-output-file", &openOutputFile, .{ .exact = 1 });
    // Binary I/O
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
        const written: usize = @intCast(result);
        if (written == 0) break;
        total += written;
    }
}

pub fn writeStdout(bytes: []const u8) void {
    writeToFd(1, bytes);
}

pub fn writeStderr(bytes: []const u8) void {
    writeToFd(2, bytes);
}

/// Get the output port: use args[arg_idx] if provided, else current-output-port.
fn getOutputPort(args: []const Value, arg_idx: usize) PrimitiveError!*types.Port {
    if (args.len > arg_idx) {
        if (!types.isPort(args[arg_idx])) return PrimitiveError.TypeError;
        const port = types.toObject(args[arg_idx]).as(types.Port);
        if (!port.is_output) return PrimitiveError.TypeError;
        if (!port.is_open) return PrimitiveError.TypeError;
        return port;
    }
    // Use current-output-port from VM
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    if (!types.isPort(vm.stdout_port)) return PrimitiveError.TypeError;
    return types.toObject(vm.stdout_port).as(types.Port);
}

/// Get the input port: use args[arg_idx] if provided, else current-input-port.
fn getInputPort(args: []const Value, arg_idx: usize) PrimitiveError!*types.Port {
    if (args.len > arg_idx) {
        if (!types.isPort(args[arg_idx])) return PrimitiveError.TypeError;
        const port = types.toObject(args[arg_idx]).as(types.Port);
        if (!port.is_input) return PrimitiveError.TypeError;
        if (!port.is_open) return PrimitiveError.TypeError;
        return port;
    }
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
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
    const port = try getOutputPort(args, 1);
    const s = printer.valueToString(gc.allocator, args[0], .display) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(s);
    writeToPort(port, s);
    return types.VOID;
}

fn write(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = try getOutputPort(args, 1);
    const s = printer.valueToString(gc.allocator, args[0], .write) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(s);
    writeToPort(port, s);
    return types.VOID;
}

fn writeShared(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = try getOutputPort(args, 1);
    const s = printer.valueToString(gc.allocator, args[0], .shared) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(s);
    writeToPort(port, s);
    return types.VOID;
}

fn newline(args: []const Value) PrimitiveError!Value {
    const port = try getOutputPort(args, 0);
    writeToPort(port, "\n");
    return types.VOID;
}

// ---------------------------------------------------------------------------
// Port procedures (R7RS 6.13)
// ---------------------------------------------------------------------------

fn currentInputPort(args: []const Value) PrimitiveError!Value {
    _ = args;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    return vm.stdin_port;
}

fn currentOutputPort(args: []const Value) PrimitiveError!Value {
    _ = args;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    return vm.stdout_port;
}

fn currentErrorPort(args: []const Value) PrimitiveError!Value {
    _ = args;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
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
    // All our ports are textual
    return if (types.isPort(args[0])) types.TRUE else types.FALSE;
}

fn binaryPortP(args: []const Value) PrimitiveError!Value {
    // We don't have binary ports yet
    _ = args;
    return types.FALSE;
}

fn inputPortOpenP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return PrimitiveError.TypeError;
    const port = types.toObject(args[0]).as(types.Port);
    return if (port.is_input and port.is_open) types.TRUE else types.FALSE;
}

fn outputPortOpenP(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return PrimitiveError.TypeError;
    const port = types.toObject(args[0]).as(types.Port);
    return if (port.is_output and port.is_open) types.TRUE else types.FALSE;
}

fn raiseFileError(gc: *@import("memory.zig").GC, msg_text: []const u8, irritant: Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const msg = gc.allocString(msg_text) catch return PrimitiveError.OutOfMemory;
    const irritants = gc.allocPair(irritant, types.NIL) catch return PrimitiveError.OutOfMemory;
    const err_obj = gc.allocErrorObject(msg, irritants) catch return PrimitiveError.OutOfMemory;
    // Mark as file error
    types.toObject(err_obj).as(types.ErrorObject).error_type = .file;
    vm.current_exception = err_obj;
    return PrimitiveError.ExceptionRaised;
}

fn openInputFile(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const path = str.data[0..str.len];

    // We need a null-terminated path for openat
    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    const fd = std.posix.openat(std.posix.AT.FDCWD, path_z, .{}, 0) catch {
        return raiseFileError(gc, "cannot open input file", args[0]);
    };

    // Dup the name for the port
    const owned_name = gc.allocator.dupe(u8, path) catch return PrimitiveError.OutOfMemory;
    return gc.allocPort(fd, true, false, owned_name, true) catch return PrimitiveError.OutOfMemory;
}

fn openOutputFile(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
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

    const owned_name = gc.allocator.dupe(u8, path) catch return PrimitiveError.OutOfMemory;
    return gc.allocPort(fd, false, true, owned_name, true) catch return PrimitiveError.OutOfMemory;
}

fn closePort(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return PrimitiveError.TypeError;
    const port = types.toObject(args[0]).as(types.Port);
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
    // String input port
    if (port.is_string_port) {
        const data = port.string_data orelse return null;
        if (port.string_pos >= data.len) return null;
        const byte = data[port.string_pos];
        port.string_pos += 1;
        return byte;
    }
    var buf: [1]u8 = undefined;
    const n = std.posix.read(port.fd, &buf) catch return null;
    if (n == 0) return null; // EOF
    return buf[0];
}

fn readCharFn(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0);
    const byte = readOneByte(port) orelse return types.EOF;
    return types.makeChar(@intCast(byte));
}

fn peekCharFn(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0);
    if (port.peek_byte) |b| {
        return types.makeChar(@intCast(b));
    }
    // Use readOneByte which handles string ports
    const byte = readOneByte(port) orelse return types.EOF;
    port.peek_byte = byte;
    return types.makeChar(@intCast(byte));
}

fn readLineFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = try getInputPort(args, 0);

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
    const port = try getInputPort(args, 0);
    if (port.peek_byte != null) return types.TRUE;
    // For simplicity, always return #t (non-blocking check not worth the complexity)
    return types.TRUE;
}

fn writeCharFn(args: []const Value) PrimitiveError!Value {
    if (!types.isChar(args[0])) return PrimitiveError.TypeError;
    const port = try getOutputPort(args, 1);
    const cp = types.toChar(args[0]);
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(cp, &buf) catch return PrimitiveError.TypeError;
    writeToPort(port, buf[0..len]);
    return types.VOID;
}

fn writeStringFn(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const port = try getOutputPort(args, 1);
    const str = types.toObject(args[0]).as(types.SchemeString);
    writeToPort(port, str.data[0..str.len]);
    return types.VOID;
}

fn readDatumFn(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = try getInputPort(args, 0);

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
        const datum = reader.readDatum() catch return types.EOF;
        // Advance string_pos by amount consumed
        port.string_pos += reader.pos;
        if (combined.items.len > 0 and reader.pos > 0) {
            // Adjust for the prefix byte
            port.string_pos -= 1;
        }
        return datum;
    }

    // Read the entire remaining content from the port into a buffer
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gc.allocator);

    // First consume any peeked byte
    if (port.peek_byte) |b| {
        buf.append(gc.allocator, b) catch return PrimitiveError.OutOfMemory;
        port.peek_byte = null;
    }

    // Read all remaining data from the fd
    var tmp: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(port.fd, &tmp) catch break;
        if (n == 0) break;
        buf.appendSlice(gc.allocator, tmp[0..n]) catch return PrimitiveError.OutOfMemory;
    }

    if (buf.items.len == 0) return types.EOF;

    // Parse one datum from the buffer
    var reader = reader_mod.Reader.init(gc, buf.items);
    defer reader.deinit();
    const datum = reader.readDatum() catch return types.EOF;

    // Any remaining data after the datum stays unconsumed.
    // For file ports, this is fine since read is typically used to
    // parse the entire file content sequentially.
    return datum;
}

fn fileExistsP(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const path = str.data[0..str.len];

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    // Try to open the file read-only to check existence
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
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
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
    if (!types.isPort(args[0])) return PrimitiveError.TypeError;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const port = types.toObject(args[0]).as(types.Port);
    if (!port.is_string_port or !port.is_output) return PrimitiveError.TypeError;
    const buf = port.string_out_buf orelse return gc.allocString("") catch return PrimitiveError.OutOfMemory;
    return gc.allocString(buf[0..port.string_out_len]) catch return PrimitiveError.OutOfMemory;
}

// ---------------------------------------------------------------------------
// Additional I/O procedures
// ---------------------------------------------------------------------------

fn readStringFn(args: []const Value) PrimitiveError!Value {
    // (read-string k [port]) -- read k characters
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const k = types.toFixnum(args[0]);
    if (k < 0) return PrimitiveError.TypeError;
    const count: usize = @intCast(@as(u64, @bitCast(k)));
    const port = try getInputPort(args, 1);

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(gc.allocator);

    var chars_read: usize = 0;
    while (chars_read < count) {
        const byte = readOneByte(port) orelse break;
        result.append(gc.allocator, byte) catch return PrimitiveError.OutOfMemory;
        chars_read += 1;
    }
    if (result.items.len == 0) return types.EOF;
    return gc.allocString(result.items) catch return PrimitiveError.OutOfMemory;
}

fn flushOutputPort(args: []const Value) PrimitiveError!Value {
    // For our implementation, flushing is a no-op since we write directly
    if (args.len > 0) {
        if (!types.isPort(args[0])) return PrimitiveError.TypeError;
    }
    return types.VOID;
}

fn deleteFile(args: []const Value) PrimitiveError!Value {
    if (!types.isString(args[0])) return PrimitiveError.TypeError;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const str = types.toObject(args[0]).as(types.SchemeString);
    const path = str.data[0..str.len];

    const path_z = gc.allocator.dupeZ(u8, path) catch return PrimitiveError.OutOfMemory;
    defer gc.allocator.free(path_z);

    _ = std.posix.system.unlink(path_z);
    return types.VOID;
}

// ---------------------------------------------------------------------------
// File I/O wrappers (R7RS 6.13)
// ---------------------------------------------------------------------------

/// (call-with-input-file string proc)
fn callWithInputFile(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
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
            else => PrimitiveError.TypeError,
        };
    };
    // Close port
    _ = try closePort(&[_]Value{port_val});
    return result;
}

/// (call-with-output-file string proc)
fn callWithOutputFile(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const port_val = try openOutputFile(&[_]Value{args[0]});
    const result = vm.callWithArgs(args[1], &[_]Value{port_val}) catch |err| {
        _ = closePort(&[_]Value{port_val}) catch {};
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError,
        };
    };
    _ = try closePort(&[_]Value{port_val});
    return result;
}

/// (call-with-port port proc)
fn callWithPort(args: []const Value) PrimitiveError!Value {
    if (!types.isPort(args[0])) return PrimitiveError.TypeError;
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
    const result = vm.callWithArgs(args[1], &[_]Value{args[0]}) catch |err| {
        _ = closePort(&[_]Value{args[0]}) catch {};
        return switch (err) {
            vm_mod.VMError.ContinuationInvoked => PrimitiveError.ContinuationInvoked,
            vm_mod.VMError.ExceptionRaised => PrimitiveError.ExceptionRaised,
            vm_mod.VMError.OutOfMemory => PrimitiveError.OutOfMemory,
            else => PrimitiveError.TypeError,
        };
    };
    _ = try closePort(&[_]Value{args[0]});
    return result;
}

/// (with-input-from-file string thunk)
fn withInputFromFile(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
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
            else => PrimitiveError.TypeError,
        };
    };
    vm.stdin_port = saved;
    _ = try closePort(&[_]Value{port_val});
    return result;
}

/// (with-output-to-file string thunk)
fn withOutputToFile(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.TypeError;
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
            else => PrimitiveError.TypeError,
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
    const port = try getInputPort(args, 0);
    const byte = readOneByte(port) orelse return types.EOF;
    return types.makeFixnum(@intCast(byte));
}

fn peekU8Fn(args: []const Value) PrimitiveError!Value {
    const port = try getInputPort(args, 0);
    if (port.peek_byte) |b| {
        return types.makeFixnum(@intCast(b));
    }
    const byte = readOneByte(port) orelse return types.EOF;
    port.peek_byte = byte;
    return types.makeFixnum(@intCast(byte));
}

fn writeU8Fn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    const port = try getOutputPort(args, 1);
    const val = types.toFixnum(args[0]);
    if (val < 0 or val > 255) return PrimitiveError.TypeError;
    const byte: u8 = @intCast(@as(u64, @bitCast(val)));
    const buf = [1]u8{byte};
    writeToPort(port, &buf);
    return types.VOID;
}

fn readBytevectorFn(args: []const Value) PrimitiveError!Value {
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    const gc = primitives.gc_instance orelse return PrimitiveError.OutOfMemory;
    const k = types.toFixnum(args[0]);
    if (k < 0) return PrimitiveError.TypeError;
    const count: usize = @intCast(@as(u64, @bitCast(k)));
    const port = try getInputPort(args, 1);

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
    if (!types.isBytevector(args[0])) return PrimitiveError.TypeError;
    const port = try getOutputPort(args, 1);
    const bv = types.toBytevector(args[0]);
    writeToPort(port, bv.data);
    return types.VOID;
}
