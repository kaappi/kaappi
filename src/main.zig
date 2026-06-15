const std = @import("std");
pub const types = @import("types.zig");
pub const memory = @import("memory.zig");
pub const reader = @import("reader.zig");
pub const compiler = @import("compiler.zig");
pub const vm_mod = @import("vm.zig");
pub const primitives = @import("primitives.zig");
pub const printer = @import("printer.zig");
pub const expander = @import("expander.zig");
pub const library = @import("library.zig");

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
                return;
            };
            if (result != types.VOID) {
                const s = printer.valueToString(allocator, result, .write) catch continue;
                defer allocator.free(s);
                writeStdout(s);
                writeStdout("\n");
            }
            continue;
        }

        const func = compiler.compileExpressionWithMacros(vm.gc, expr, &vm.macros) catch |err| {
            std.debug.print("Compile error: {}\n", .{err});
            return;
        };

        // Root the function to prevent GC from collecting it before execute wraps it in a closure
        var func_val = types.makePointer(@ptrCast(func));
        vm.gc.pushRoot(&func_val);

        const result = vm.execute(func) catch |err| {
            vm.gc.popRoot();
            std.debug.print("Runtime error: {}\n", .{err});
            return;
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

fn repl(vm: *vm_mod.VM) !void {
    const allocator = vm.gc.allocator;

    writeStdout("Kaappi Scheme v0.1.0\n");
    writeStdout("Type (exit) to quit.\n\n");

    var line_buf: [4096]u8 = undefined;

    while (true) {
        writeStdout("kaappi> ");
        const line = readLine(&line_buf) orelse return;

        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0) continue;
        if (std.mem.eql(u8, trimmed, "(exit)")) return;

        var r = reader.Reader.init(vm.gc, trimmed);
        defer r.deinit();

        while (r.hasMore()) {
            const expr = r.readDatum() catch |err| {
                var errbuf: [256]u8 = undefined;
                var ew: std.Io.Writer = .fixed(&errbuf);
                ew.print("Read error: {}\n", .{err}) catch {};
                writeStdout(ew.buffered());
                break;
            };

            // Check for special top-level forms (import, define-library)
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

            const func = compiler.compileExpressionWithMacros(vm.gc, expr, &vm.macros) catch |err| {
                var errbuf: [256]u8 = undefined;
                var ew: std.Io.Writer = .fixed(&errbuf);
                ew.print("Compile error: {}\n", .{err}) catch {};
                writeStdout(ew.buffered());
                break;
            };

            // Root the function to prevent GC from collecting it before execute wraps it in a closure
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
}

test {
    _ = types;
    _ = memory;
    _ = reader;
    _ = compiler;
    _ = vm_mod;
    _ = printer;
    _ = expander;
    _ = library;
}
