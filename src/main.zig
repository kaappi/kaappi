const std = @import("std");
pub const types = @import("types.zig");
pub const memory = @import("memory.zig");
pub const reader = @import("reader.zig");
pub const compiler = @import("compiler.zig");
pub const compiler_forms = @import("compiler_forms.zig");
pub const vm_mod = @import("vm.zig");
pub const primitives = @import("primitives.zig");
pub const primitives_arithmetic = @import("primitives_arithmetic.zig");
pub const primitives_io = @import("primitives_io.zig");
pub const primitives_control = @import("primitives_control.zig");
pub const primitives_vector = @import("primitives_vector.zig");
pub const primitives_string = @import("primitives_string.zig");
pub const primitives_char = @import("primitives_char.zig");
pub const primitives_cxr = @import("primitives_cxr.zig");
pub const primitives_bytevector = @import("primitives_bytevector.zig");
pub const primitives_lazy = @import("primitives_lazy.zig");
pub const primitives_r7rs = @import("primitives_r7rs.zig");
pub const printer = @import("printer.zig");
pub const expander = @import("expander.zig");
pub const library = @import("library.zig");
pub const ln = @import("linenoise.zig");

var repl_vm: ?*vm_mod.VM = null;

fn writeToFd(fd: std.posix.fd_t, bytes: []const u8) void {
    var total: usize = 0;
    while (total < bytes.len) {
        const result = std.posix.system.write(fd, bytes.ptr + total, bytes.len - total);
        const written: usize = @intCast(result);
        if (written == 0) break;
        total += written;
    }
}

fn writeStdout(bytes: []const u8) void {
    writeToFd(1, bytes);
}

fn readLine(buf: []u8) ?[]const u8 {
    const fd: std.posix.fd_t = 0;
    var i: usize = 0;
    while (i < buf.len) {
        const result = std.posix.system.read(fd, buf.ptr + i, 1);
        const n: usize = @intCast(result);
        if (n == 0) {
            if (i == 0) return null;
            return buf[0..i];
        }
        if (buf[i] == '\n') return buf[0..i];
        i += 1;
    }
    return buf[0..i];
}

fn readFileContents(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{}, 0) catch |err| {
        std.debug.print("Error opening file '{s}': {}\n", .{ path, err });
        return err;
    };
    defer _ = std.posix.system.close(fd);

    // Read file contents into a buffer
    const max_size: usize = 1024 * 1024;
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    var tmp: [4096]u8 = undefined;
    while (true) {
        const bytes_read = std.posix.read(fd, &tmp) catch |err| {
            std.debug.print("Error reading file: {}\n", .{err});
            return err;
        };
        if (bytes_read == 0) break;
        if (result.items.len + bytes_read > max_size) {
            std.debug.print("File too large\n", .{});
            return error.StreamTooLong;
        }
        result.appendSlice(allocator, tmp[0..bytes_read]) catch |err| return err;
    }

    return result.toOwnedSlice(allocator);
}

pub fn main(init: std.process.Init.Minimal) !void {
    var da = std.heap.DebugAllocator(.{}).init;
    defer _ = da.deinit();
    const allocator = da.allocator();

    var gc = memory.GC.init(allocator);
    defer gc.deinit();

    var vm = vm_mod.VM.init(&gc);
    defer vm.deinit();
    try primitives.registerAll(&vm);
    primitives.setGCInstance(&gc);
    try library.registerStandardLibraries(&vm.libraries, &vm.globals);

    var args = init.args.iterate();
    _ = args.skip(); // skip program name
    if (args.next()) |path| {
        try runFile(&vm, path);
    } else {
        try repl(&vm);
    }
}

fn runFile(vm: *vm_mod.VM, path: []const u8) !void {
    const allocator = vm.gc.allocator;
    const source = readFileContents(allocator, path) catch {
        return;
    };
    defer allocator.free(source);

    var r = reader.Reader.init(vm.gc, source);
    defer r.deinit();

    while (r.hasMore()) {
        const expr = r.readDatum() catch |err| {
            std.debug.print("Read error: {}\n", .{err});
            return;
        };

        // Check for special top-level forms (import, define-library)
        if (vm.handleTopLevelForm(expr)) |top_result| {
            const result = top_result catch |err| {
                std.debug.print("Runtime error: {}\n", .{err});
                continue;
            };
            if (result != types.VOID) {
                const s = printer.valueToString(allocator, result, .write) catch continue;
                defer allocator.free(s);
                writeStdout(s);
                writeStdout("\n");
            }
            continue;
        }

        const func = compiler.compileExpressionWithMacros(vm.gc, expr, &vm.macros, &vm.globals) catch |err| {
            std.debug.print("Compile error: {}\n", .{err});
            continue;
        };

        // Root the function to prevent GC from collecting it before execute wraps it in a closure
        var func_val = types.makePointer(@ptrCast(func));
        vm.gc.pushRoot(&func_val);

        const result = vm.execute(func) catch |err| {
            vm.gc.popRoot();
            std.debug.print("Runtime error: {}\n", .{err});
            continue;
        };
        vm.gc.popRoot();

        if (result != types.VOID) {
            const s = printer.valueToString(allocator, result, .write) catch continue;
            defer allocator.free(s);
            writeStdout(s);
            writeStdout("\n");
        }
    }
}

fn completionCallback(buf: [*c]const u8, lc: [*c]ln.c.linenoiseCompletions) callconv(.c) void {
    const vm = repl_vm orelse return;
    const b: ?[*:0]const u8 = @ptrCast(buf);
    const prefix = if (b) |bp| std.mem.span(bp) else return;
    if (prefix.len == 0) return;

    var it = vm.globals.keyIterator();
    while (it.next()) |key| {
        if (std.mem.startsWith(u8, key.*, prefix)) {
            ln.addCompletion(lc, @ptrCast(key.*.ptr));
        }
    }
}

fn parenDepth(src: []const u8) i32 {
    var depth: i32 = 0;
    var in_string = false;
    var in_escape = false;
    var in_line_comment = false;
    for (src) |ch| {
        if (in_line_comment) {
            if (ch == '\n') in_line_comment = false;
            continue;
        }
        if (in_escape) {
            in_escape = false;
            continue;
        }
        if (in_string) {
            if (ch == '\\') in_escape = true else if (ch == '"') in_string = false;
            continue;
        }
        switch (ch) {
            '"' => in_string = true,
            ';' => in_line_comment = true,
            '(' => depth += 1,
            ')' => depth -= 1,
            else => {},
        }
    }
    return depth;
}

fn repl(vm: *vm_mod.VM) !void {
    const allocator = vm.gc.allocator;

    writeStdout("Kaappi Scheme v0.1.0\n");
    writeStdout("Type (exit) to quit.\n\n");

    repl_vm = vm;
    ln.setMultiLine(true);
    ln.historySetMaxLen(1000);
    ln.historyLoad(".kaappi_history");
    ln.setCompletionCallback(&completionCallback);

    var input_buf: std.ArrayList(u8) = .empty;
    defer input_buf.deinit(allocator);

    while (true) {
        const prompt: [*:0]const u8 = if (input_buf.items.len > 0) "  ... " else "kaappi> ";
        const line_ptr = ln.linenoise(prompt) orelse {
            if (input_buf.items.len > 0) {
                input_buf.clearRetainingCapacity();
                writeStdout("\n");
                continue;
            }
            break;
        };
        defer ln.free(@ptrCast(line_ptr));

        const line = std.mem.span(line_ptr);
        const trimmed = std.mem.trim(u8, line, " \t\r");

        if (input_buf.items.len == 0 and trimmed.len == 0) continue;
        if (input_buf.items.len == 0 and std.mem.eql(u8, trimmed, "(exit)")) break;

        // If pasted text contains newlines, echo it clearly
        const has_newlines = std.mem.indexOf(u8, line, "\n") != null;
        if (has_newlines and input_buf.items.len == 0) {
            writeStdout(line);
            writeStdout("\n");
        }

        if (input_buf.items.len > 0) {
            input_buf.append(allocator, '\n') catch continue;
        }
        input_buf.appendSlice(allocator, line) catch continue;

        if (parenDepth(input_buf.items) > 0) continue;

        const full_input = input_buf.items;

        // Add to history with newlines replaced by spaces for clean display
        var hist_buf: std.ArrayList(u8) = .empty;
        defer hist_buf.deinit(allocator);
        hist_buf.appendSlice(allocator, full_input) catch {};
        for (hist_buf.items) |*ch| {
            if (ch.* == '\n') ch.* = ' ';
        }
        hist_buf.append(allocator, 0) catch {};
        ln.historyAdd(@ptrCast(hist_buf.items.ptr));

        evalInput(vm, allocator, full_input);

        input_buf.clearRetainingCapacity();
    }

    ln.historySave(".kaappi_history");
    repl_vm = null;
}

fn evalInput(vm: *vm_mod.VM, allocator: std.mem.Allocator, input: []const u8) void {
    var r = reader.Reader.init(vm.gc, input);
    defer r.deinit();

    while (r.hasMore()) {
        const expr = r.readDatum() catch |err| {
            var errbuf: [256]u8 = undefined;
            var ew: std.Io.Writer = .fixed(&errbuf);
            ew.print("Read error: {}\n", .{err}) catch {};
            writeStdout(ew.buffered());
            break;
        };

        if (vm.handleTopLevelForm(expr)) |top_result| {
            const result = top_result catch |err| {
                var errbuf: [256]u8 = undefined;
                var ew: std.Io.Writer = .fixed(&errbuf);
                ew.print("Runtime error: {}\n", .{err}) catch {};
                writeStdout(ew.buffered());
                break;
            };
            if (result != types.VOID) {
                const s = printer.valueToString(allocator, result, .write) catch continue;
                defer allocator.free(s);
                writeStdout(s);
                writeStdout("\n");
            }
            continue;
        }

        const func = compiler.compileExpressionWithMacros(vm.gc, expr, &vm.macros, &vm.globals) catch |err| {
            var errbuf: [256]u8 = undefined;
            var ew: std.Io.Writer = .fixed(&errbuf);
            ew.print("Compile error: {}\n", .{err}) catch {};
            writeStdout(ew.buffered());
            break;
        };

        var func_val = types.makePointer(@ptrCast(func));
        vm.gc.pushRoot(&func_val);

        const result = vm.execute(func) catch |err| {
            vm.gc.popRoot();
            var errbuf: [256]u8 = undefined;
            var ew: std.Io.Writer = .fixed(&errbuf);
            ew.print("Runtime error: {}\n", .{err}) catch {};
            writeStdout(ew.buffered());
            break;
        };
        vm.gc.popRoot();

        if (result != types.VOID) {
            const s = printer.valueToString(allocator, result, .write) catch continue;
            defer allocator.free(s);
            writeStdout(s);
            writeStdout("\n");
        }
    }
}

test {
    _ = types;
    _ = memory;
    _ = reader;
    _ = compiler;
    _ = compiler_forms;
    _ = vm_mod;
    _ = primitives;
    _ = primitives_arithmetic;
    _ = primitives_io;
    _ = primitives_control;
    _ = primitives_vector;
    _ = primitives_string;
    _ = primitives_char;
    _ = primitives_cxr;
    _ = primitives_bytevector;
    _ = primitives_lazy;
    _ = primitives_r7rs;
    _ = printer;
    _ = expander;
    _ = library;
    _ = ln;
}
