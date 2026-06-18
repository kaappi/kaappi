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
pub const ffi = @import("ffi.zig");
pub const primitives_ffi = @import("primitives_ffi.zig");
pub const primitives_srfi1 = @import("primitives_srfi1.zig");
pub const primitives_hashtable = @import("primitives_hashtable.zig");
pub const primitives_random = @import("primitives_random.zig");
pub const bytecode_file = @import("bytecode_file.zig");

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

fn writeStderr(bytes: []const u8) void {
    writeToFd(2, bytes);
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
    vm_mod.setVMInstance(&vm);
    try primitives.registerAll(&vm);
    primitives.setGCInstance(&gc);
    try library.registerStandardLibraries(&vm.libraries, &vm.globals);

    var args = init.args.iterate();
    _ = args.skip(); // skip program name

    var lib_paths: [16][]const u8 = undefined;
    var lib_path_count: usize = 0;
    var file_path: ?[]const u8 = null;
    var compile_mode = false;

    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--lib-path")) {
            if (args.next()) |lp| {
                if (lib_path_count < 16) {
                    lib_paths[lib_path_count] = lp;
                    lib_path_count += 1;
                }
            }
        } else if (std.mem.eql(u8, arg, "--compile")) {
            compile_mode = true;
        } else if (std.mem.eql(u8, arg, "--no-cache")) {
            // future: disable caching
        } else {
            file_path = arg;
            break;
        }
    }

    // Collect remaining args after the file path for (command-line).
    var script_args: [64][]const u8 = undefined;
    var script_arg_count: usize = 0;
    if (file_path) |fp| {
        script_args[0] = fp;
        script_arg_count = 1;
        while (args.next()) |extra| {
            if (script_arg_count < 64) {
                script_args[script_arg_count] = extra;
                script_arg_count += 1;
            }
        }
    }
    vm.command_line_args = script_args[0..script_arg_count];

    vm.lib_paths = lib_paths[0..lib_path_count];

    if (compile_mode) {
        if (file_path) |fp| {
            try compileFile(&vm, fp);
        } else {
            writeStdout("Usage: kaappi --compile <file.scm>\n");
        }
    } else if (file_path) |fp| {
        try runFile(&vm, fp);
    } else {
        try repl(&vm);
    }
}

fn getSbcPath(allocator: std.mem.Allocator, scm_path: []const u8) ![]u8 {
    return bytecode_file.getSbcPath(allocator, scm_path);
}

fn runFile(vm: *vm_mod.VM, path: []const u8) !void {
    const allocator = vm.gc.allocator;

    // Resolve top-level `(include ...)` paths relative to the program's directory.
    const saved_lib_dir = vm.current_lib_dir;
    vm.current_lib_dir = if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| path[0 .. pos + 1] else "";
    defer vm.current_lib_dir = saved_lib_dir;

    const source = readFileContents(allocator, path) catch {
        return;
    };
    defer allocator.free(source);

    const source_hash = bytecode_file.sourceHash(source);

    // Try loading cached bytecode
    const sbc_path = getSbcPath(allocator, path) catch null;
    defer if (sbc_path) |p| allocator.free(p);

    if (sbc_path) |sp| {
        if (bytecode_file.readFileWithTopLevel(vm.gc, source_hash, sp) catch null) |loaded| {
            defer allocator.free(loaded.funcs);
            const top_count = @min(loaded.top_level_count, @as(u32, @intCast(loaded.funcs.len)));
            for (loaded.funcs[0..top_count]) |func| {
                var func_val = types.makePointer(@ptrCast(func));
                vm.gc.pushRoot(&func_val);
                const result = vm.execute(func) catch |err| {
                    vm.gc.popRoot();
                    const detail = vm.getErrorDetail();
                    if (detail.len > 0) {
                        var errbuf: [256]u8 = undefined;
                        const s = std.fmt.bufPrint(&errbuf, "{s}: error: {s}\n", .{ path, detail }) catch "runtime error\n";
                        writeStderr(s);
                    } else {
                        var errbuf: [256]u8 = undefined;
                        const s = std.fmt.bufPrint(&errbuf, "{s}: runtime error: {}\n", .{ path, err }) catch "runtime error\n";
                        writeStderr(s);
                    }
                    vm.last_error_detail_len = 0;
                    continue;
                };
                vm.gc.popRoot();

                var display_result = result;
                if (types.isMultipleValues(display_result)) {
                    const mv = types.toObject(display_result).as(types.MultipleValues);
                    display_result = if (mv.values.len > 0) mv.values[0] else types.VOID;
                }
                if (display_result != types.VOID) {
                    const s = printer.valueToString(allocator, display_result, .write) catch continue;
                    defer allocator.free(s);
                    writeStdout(s);
                    writeStdout("\n");
                }
            }
            return;
        }
    }

    // No cache — compile from source
    var compiled_funcs: std.ArrayList(*types.Function) = .empty;
    defer compiled_funcs.deinit(allocator);
    var has_imports = false;

    var r = reader.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    while (r.hasMore()) {
        const datum_lc = r.getLineCol();
        const expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error: {}\n", .{ path, lc.line, lc.col, err }) catch "read error\n";
            writeStderr(s);
            return;
        };

        // Check for special top-level forms (import, define-library)
        if (vm.handleTopLevelForm(expr)) |top_result| {
            has_imports = true;
            const result = top_result catch |err| {
                const detail = vm.getErrorDetail();
                if (detail.len > 0) {
                    var errbuf: [256]u8 = undefined;
                    const s = std.fmt.bufPrint(&errbuf, "{s}:{d}: error: {s}\n", .{ path, datum_lc.line, detail }) catch "runtime error\n";
                    writeStderr(s);
                } else {
                    var errbuf: [256]u8 = undefined;
                    const s = std.fmt.bufPrint(&errbuf, "{s}:{d}: runtime error: {}\n", .{ path, datum_lc.line, err }) catch "runtime error\n";
                    writeStderr(s);
                }
                vm.last_error_detail_len = 0;
                continue;
            };
            var dr = result;
            if (types.isMultipleValues(dr)) {
                const mv = types.toObject(dr).as(types.MultipleValues);
                dr = if (mv.values.len > 0) mv.values[0] else types.VOID;
            }
            if (dr != types.VOID) {
                const s = printer.valueToString(allocator, dr, .write) catch continue;
                defer allocator.free(s);
                writeStdout(s);
                writeStdout("\n");
            }
            continue;
        }

        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, &vm.globals, datum_lc.line, path) catch |err| {
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "{s}:{d}: compile error: {}\n", .{ path, datum_lc.line, err }) catch "compile error\n";
            writeStderr(s);
            continue;
        };

        // Collect for caching. Keep each collected function rooted for the rest
        // of the run: the .sbc cache writer walks compiled_funcs at the end, so
        // these pointers must survive GC triggered while executing later forms.
        // (A plain ArrayList of *Function is not a GC root.)
        compiled_funcs.append(allocator, func) catch {};
        vm.gc.extra_roots.append(allocator, types.makePointer(@ptrCast(func))) catch {};

        // Root the function to prevent GC from collecting it before execute wraps it in a closure
        var func_val = types.makePointer(@ptrCast(func));
        vm.gc.pushRoot(&func_val);

        const result = vm.execute(func) catch |err| {
            vm.gc.popRoot();
            const detail = vm.getErrorDetail();
            const err_line = if (vm.last_error_line > 0) vm.last_error_line else datum_lc.line;
            const err_source = vm.last_error_source orelse path;
            if (detail.len > 0) {
                var errbuf: [512]u8 = undefined;
                const s = std.fmt.bufPrint(&errbuf, "{s}:{d}: error: {s}\n", .{ err_source, err_line, detail }) catch "runtime error\n";
                writeStderr(s);
            } else {
                var errbuf: [512]u8 = undefined;
                const s = std.fmt.bufPrint(&errbuf, "{s}:{d}: runtime error: {}\n", .{ err_source, err_line, err }) catch "runtime error\n";
                writeStderr(s);
            }
            // Print stack trace for file execution
            var trace_buf: [8]vm_mod.VM.StackFrame = undefined;
            const trace_len = vm.getStackTrace(&trace_buf);
            if (trace_len > 1) {
                for (trace_buf[1..trace_len]) |frame| {
                    var tbuf: [256]u8 = undefined;
                    if (frame.name) |name| {
                        const ts = std.fmt.bufPrint(&tbuf, "  in {s} ({s}:{d})\n", .{ name, frame.source orelse "?", frame.line }) catch continue;
                        writeStderr(ts);
                    } else if (frame.line > 0) {
                        const ts = std.fmt.bufPrint(&tbuf, "  called from {s}:{d}\n", .{ frame.source orelse "?", frame.line }) catch continue;
                        writeStderr(ts);
                    }
                }
            }
            vm.last_error_detail_len = 0;
            continue;
        };
        vm.gc.popRoot();

        // Unwrap MultipleValues for display (extract first value)
        var display_result = result;
        if (types.isMultipleValues(display_result)) {
            const mv = types.toObject(display_result).as(types.MultipleValues);
            display_result = if (mv.values.len > 0) mv.values[0] else types.VOID;
        }
        if (display_result != types.VOID) {
            const s = printer.valueToString(allocator, display_result, .write) catch continue;
            defer allocator.free(s);
            writeStdout(s);
            writeStdout("\n");
        }
    }

    // Cache compiled bytecode (skip when imports are used — GC may have freed
    // collected function pointers during library loading)
    if (!has_imports and compiled_funcs.items.len > 0) {
        if (sbc_path) |sp| {
            bytecode_file.writeFileWithTopLevel(allocator, compiled_funcs.items, source_hash, sp) catch {};
        }
    }
}

fn compileFile(vm: *vm_mod.VM, path: []const u8) !void {
    const allocator = vm.gc.allocator;
    const source = readFileContents(allocator, path) catch {
        return;
    };
    defer allocator.free(source);

    const source_hash = bytecode_file.sourceHash(source);

    var compiled_funcs: std.ArrayList(*types.Function) = .empty;
    defer compiled_funcs.deinit(allocator);

    var r = reader.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    while (r.hasMore()) {
        const datum_lc = r.getLineCol();
        const expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error: {}\n", .{ path, lc.line, lc.col, err }) catch "read error\n";
            writeStderr(s);
            return;
        };

        // Skip special top-level forms for compilation — they need runtime
        if (vm.handleTopLevelForm(expr)) |_| {
            continue;
        }

        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, &vm.globals, datum_lc.line, path) catch |err| {
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "{s}:{d}: compile error: {}\n", .{ path, datum_lc.line, err }) catch "compile error\n";
            writeStderr(s);
            continue;
        };

        compiled_funcs.append(allocator, func) catch {};
    }

    if (compiled_funcs.items.len > 0) {
        const sbc_path = getSbcPath(allocator, path) catch {
            std.debug.print("Error creating output path\n", .{});
            return;
        };
        defer allocator.free(sbc_path);

        bytecode_file.writeFileWithTopLevel(allocator, compiled_funcs.items, source_hash, sbc_path) catch {
            std.debug.print("Error writing bytecode file\n", .{});
            return;
        };

        writeStdout("Compiled ");
        writeStdout(path);
        writeStdout(" -> ");
        writeStdout(sbc_path);
        writeStdout("\n");
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
        const debug_trimmed = std.mem.trim(u8, full_input, " \t\r\n");

        // Debug commands (comma-prefixed)
        if (std.mem.startsWith(u8, debug_trimmed, ",break ")) {
            const bp_name = std.mem.trim(u8, debug_trimmed[7..], " ");
            if (vm.breakpoint_count < 16) {
                vm.breakpoints[vm.breakpoint_count] = bp_name;
                vm.breakpoint_count += 1;
                vm.debug_mode = true;
                vm.step_mode = .continue_to_break;
            }
            writeStdout("Breakpoint set on ");
            writeStdout(bp_name);
            writeStdout("\n");
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",breakpoints")) {
            for (vm.breakpoints[0..vm.breakpoint_count], 0..) |bp, idx| {
                var dbuf: [32]u8 = undefined;
                const s = std.fmt.bufPrint(&dbuf, "  [{d}] ", .{idx}) catch "";
                writeStdout(s);
                writeStdout(bp);
                writeStdout("\n");
            }
            if (vm.breakpoint_count == 0) {
                writeStdout("  (no breakpoints)\n");
            }
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",delete all")) {
            vm.breakpoint_count = 0;
            vm.debug_mode = false;
            vm.step_mode = .none;
            writeStdout("All breakpoints deleted\n");
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",step ")) {
            const step_expr = debug_trimmed[6..];
            vm.debug_mode = true;
            vm.step_mode = .step;
            evalInput(vm, allocator, step_expr);
            vm.debug_mode = false;
            vm.step_mode = .none;
            input_buf.clearRetainingCapacity();
            continue;
        }

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
    var r = reader.Reader.initWithName(vm.gc, input, "<repl>");
    defer r.deinit();

    while (r.hasMore()) {
        const expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "<repl>:{d}:{d}: read error: {}\n", .{ lc.line, lc.col, err }) catch "read error\n";
            writeStderr(s);
            break;
        };

        if (vm.handleTopLevelForm(expr)) |top_result| {
            const result = top_result catch |err| {
                const detail = vm.getErrorDetail();
                if (detail.len > 0) {
                    writeStderr("error: ");
                    writeStderr(detail);
                    writeStderr("\n");
                } else {
                    var errbuf: [256]u8 = undefined;
                    const s = std.fmt.bufPrint(&errbuf, "runtime error: {}\n", .{err}) catch "runtime error\n";
                    writeStderr(s);
                }
                vm.last_error_detail_len = 0;
                break;
            };
            var dr = result;
            if (types.isMultipleValues(dr)) {
                const mv = types.toObject(dr).as(types.MultipleValues);
                dr = if (mv.values.len > 0) mv.values[0] else types.VOID;
            }
            if (dr != types.VOID) {
                const s = printer.valueToString(allocator, dr, .write) catch continue;
                defer allocator.free(s);
                writeStdout(s);
                writeStdout("\n");
            }
            continue;
        }

        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, &vm.globals, 0, "<repl>") catch |err| {
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "compile error: {}\n", .{err}) catch "compile error\n";
            writeStderr(s);
            break;
        };

        var func_val = types.makePointer(@ptrCast(func));
        vm.gc.pushRoot(&func_val);

        const result = vm.execute(func) catch |err| {
            vm.gc.popRoot();
            const detail = vm.getErrorDetail();
            if (detail.len > 0) {
                writeStderr("error: ");
                writeStderr(detail);
                writeStderr("\n");
            } else {
                var errbuf: [256]u8 = undefined;
                const s = std.fmt.bufPrint(&errbuf, "runtime error: {}\n", .{err}) catch "runtime error\n";
                writeStderr(s);
            }
            vm.last_error_detail_len = 0;
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
    _ = ffi;
    _ = primitives_ffi;
    _ = primitives_srfi1;
    _ = primitives_hashtable;
    _ = primitives_random;
    _ = bytecode_file;
}
