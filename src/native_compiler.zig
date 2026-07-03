const std = @import("std");
const types = @import("types.zig");
const reader_mod = @import("reader.zig");
const compiler = @import("compiler.zig");
const vm_mod = @import("vm.zig");
const ir_mod = @import("ir.zig");
const llvm_emit = @import("llvm_emit.zig");

fn writeToFd(fd: std.posix.fd_t, bytes: []const u8) void {
    var total: usize = 0;
    while (total < bytes.len) {
        const result = std.posix.system.write(fd, bytes.ptr + total, bytes.len - total);
        if (result <= 0) {
            if (result < 0 and std.posix.errno(result) == .INTR) continue;
            break;
        }
        const written: usize = @intCast(result);
        total += written;
    }
}

fn writeStdout(bytes: []const u8) void {
    writeToFd(1, bytes);
}

fn writeStderr(bytes: []const u8) void {
    writeToFd(2, bytes);
}

fn readFileContents(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const path_z = allocator.dupeZ(u8, path) catch return error.OutOfMemory;
    defer allocator.free(path_z);

    const fd = std.c.open(path_z, .{});
    if (fd < 0) {
        std.debug.print("Error opening file '{s}'\n", .{path});
        return error.FileNotFound;
    }
    defer _ = std.c.close(fd);

    const max_size: usize = 1024 * 1024;
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    var tmp: [4096]u8 = undefined;
    while (true) {
        const raw = std.c.read(fd, &tmp, tmp.len);
        if (raw == 0) break;
        if (raw < 0) {
            if (std.posix.errno(raw) == .INTR) continue;
            break;
        }
        const bytes_read: usize = @intCast(raw);
        if (result.items.len + bytes_read > max_size) {
            std.debug.print("File too large\n", .{});
            return error.StreamTooLong;
        }
        result.appendSlice(allocator, tmp[0..bytes_read]) catch |err| return err;
    }

    return result.toOwnedSlice(allocator);
}

pub fn emitLlvmFile(vm: *vm_mod.VM, path: []const u8, output_path: ?[]const u8) !void {
    const allocator = vm.gc.allocator;
    const source = readFileContents(allocator, path) catch return;
    defer allocator.free(source);

    const saved_lib_dir = vm.current_lib_dir;
    vm.current_lib_dir = if (std.mem.lastIndexOfScalar(u8, path, '/')) |pos| path[0 .. pos + 1] else "";
    defer vm.current_lib_dir = saved_lib_dir;

    var r = reader_mod.Reader.initWithName(vm.gc, source, path);
    defer r.deinit();

    var ir_nodes: std.ArrayList(*ir_mod.Node) = .empty;
    defer ir_nodes.deinit(allocator);

    var ir_instance = ir_mod.IR.init(allocator);
    defer ir_instance.deinit();

    while (r.hasMore() catch |err| {
        const lc = r.getLineCol();
        var errbuf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error: {}\n", .{ path, lc.line, lc.col, err }) catch "read error\n";
        writeStderr(s);
        return;
    }) {
        const expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "{s}:{d}:{d}: read error: {}\n", .{ path, lc.line, lc.col, err }) catch "read error\n";
            writeStderr(s);
            return;
        };

        if (types.isPair(expr)) {
            const head = types.car(expr);
            if (types.isSymbol(head)) {
                const form_name = types.symbolName(head);
                if (std.mem.eql(u8, form_name, "import") or
                    std.mem.eql(u8, form_name, "define-library"))
                {
                    if (vm.handleTopLevelForm(expr)) |result| {
                        _ = result catch {};
                    }
                    const passthrough_node = ir_instance.makePassthrough(expr) catch continue;
                    ir_nodes.append(allocator, passthrough_node) catch continue;
                    continue;
                }
                if (std.mem.eql(u8, form_name, "define-syntax") or
                    std.mem.eql(u8, form_name, "define-record-type"))
                {
                    const func = compiler.compileExpressionWithMacros(vm.gc, expr, &vm.macros, vm.globals) catch continue;
                    _ = vm.execute(func) catch {};
                    const passthrough_node = ir_instance.makePassthrough(expr) catch continue;
                    ir_nodes.append(allocator, passthrough_node) catch continue;
                    continue;
                }
            }
        }

        var root = ir_mod.lowerWithMacros(&ir_instance, expr, &vm.macros) catch |err| {
            var errbuf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&errbuf, "IR lowering error: {}\n", .{err}) catch "IR error\n";
            writeStderr(s);
            return;
        };

        ir_mod.markTailPositions(root, false);
        ir_mod.identifyPrimitives(root);
        ir_mod.markConstants(root);
        root = ir_mod.foldConstants(&ir_instance, root);
        root = ir_mod.eliminateDeadBranches(&ir_instance, root);
        root = ir_mod.simplifyBooleans(&ir_instance, root);
        root = ir_mod.eliminateIdentity(&ir_instance, root);
        root = ir_mod.simplifyBegin(&ir_instance, root);

        ir_nodes.append(allocator, root) catch return;
    }

    var emitter = llvm_emit.LLVMEmitter.init(allocator);
    defer emitter.deinit();
    emitter.emitProgram(ir_nodes.items) catch |err| {
        var errbuf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&errbuf, "LLVM emit error: {}\n", .{err}) catch "emit error\n";
        writeStderr(s);
        return;
    };

    const out_path = output_path orelse blk: {
        if (std.mem.endsWith(u8, path, ".scm")) {
            const base = path[0 .. path.len - 4];
            break :blk std.fmt.allocPrint(allocator, "{s}.ll", .{base}) catch return;
        }
        break :blk std.fmt.allocPrint(allocator, "{s}.ll", .{path}) catch return;
    };
    const should_free = output_path == null;
    defer if (should_free) allocator.free(out_path);

    const fd = std.posix.openat(std.posix.AT.FDCWD, out_path, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644) catch {
        writeStderr("Failed to create output file\n");
        return;
    };
    defer _ = std.posix.system.close(fd);
    const data = emitter.toSlice();
    var total: usize = 0;
    while (total < data.len) {
        const result = std.posix.system.write(fd, data.ptr + total, data.len - total);
        if (result <= 0) {
            writeStderr("Failed to write output\n");
            return;
        }
        total += @as(usize, @intCast(result));
    }

    var msgbuf: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(&msgbuf, "Wrote {s}\n", .{out_path}) catch return;
    writeStdout(msg);
}

pub fn compileNative(vm: *vm_mod.VM, path: []const u8, output_path: ?[]const u8) !void {
    const allocator = vm.gc.allocator;

    const pid = std.c.getpid();
    var ll_buf: [64]u8 = undefined;
    var ll_w: std.Io.Writer = .fixed(&ll_buf);
    ll_w.print("/tmp/kaappi_native_{d}.ll", .{pid}) catch return;
    const ll_path = ll_w.buffered();
    ll_buf[ll_path.len] = 0;
    emitLlvmFile(vm, path, ll_path) catch return;
    defer _ = std.posix.system.unlink(@ptrCast(ll_path.ptr));

    const out_path = output_path orelse blk: {
        if (std.mem.endsWith(u8, path, ".scm")) {
            break :blk path[0 .. path.len - 4];
        }
        break :blk path;
    };

    const lib_dir = findLibDir(allocator) orelse {
        writeStderr("Cannot find libkaappi_rt.a. Build it with: zig build lib\n");
        return;
    };

    const lib_flag = std.fmt.allocPrint(allocator, "-L{s}", .{lib_dir}) catch return;
    defer allocator.free(lib_flag);

    const compilers = [_][]const u8{ "zig", "cc", "clang", "gcc" };
    for (compilers) |cc| {
        const cc_path = findInPath(allocator, cc) orelse continue;
        defer allocator.free(cc_path);
        if (tryLink(allocator, cc_path, ll_path, out_path, lib_flag, std.mem.eql(u8, cc, "zig"))) {
            return;
        }
    }

    writeStderr("No C compiler found. Install zig, clang, or gcc.\n");
}

fn findInPath(allocator: std.mem.Allocator, name: []const u8) ?[]const u8 {
    const path_env = std.c.getenv("PATH") orelse return null;
    const path_str = std.mem.span(path_env);
    var iter = std.mem.splitScalar(u8, path_str, ':');
    while (iter.next()) |dir| {
        const full = std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir, name }) catch continue;
        const full_z = allocator.dupeZ(u8, full) catch {
            allocator.free(full);
            continue;
        };
        allocator.free(full);
        const fd = std.posix.openat(std.posix.AT.FDCWD, full_z, .{ .ACCMODE = .RDONLY }, 0) catch {
            allocator.free(full_z);
            continue;
        };
        _ = std.posix.system.close(fd);
        return full_z;
    }
    return null;
}

fn findLibDir(allocator: std.mem.Allocator) ?[]const u8 {
    if (std.c.getenv("KAAPPI_LIB_DIR")) |env| {
        const dir = std.mem.span(env);
        if (checkLibDir(allocator, dir)) return dir;
    }

    if (getExeRelativeLibDir(allocator)) |dir| return dir;

    const candidates = [_][]const u8{
        "zig-out/lib",
        "/usr/local/lib",
    };

    for (candidates) |dir| {
        if (checkLibDir(allocator, dir)) return dir;
    }
    return null;
}

fn getExeRelativeLibDir(allocator: std.mem.Allocator) ?[]const u8 {
    var path_buf: [1024]u8 = undefined;
    const exe_path: []const u8 = blk: {
        if (comptime @import("builtin").os.tag == .linux) {
            const n: isize = std.posix.system.readlink(
                "/proc/self/exe",
                &path_buf,
                path_buf.len,
            );
            if (n > 0) break :blk path_buf[0..@intCast(n)];
        }

        if (comptime @import("builtin").os.tag == .macos) {
            var size: u32 = path_buf.len;
            const rc = std.c._NSGetExecutablePath(&path_buf, &size);
            if (rc == 0) {
                const len = std.mem.indexOfScalar(u8, &path_buf, 0) orelse path_buf.len;
                break :blk path_buf[0..len];
            }
        }

        break :blk "";
    };
    if (exe_path.len == 0) return null;

    const last_slash = std.mem.lastIndexOfScalar(u8, exe_path, '/') orelse return null;
    if (last_slash == 0) return null;
    const bin_dir = exe_path[0..last_slash];
    const parent_slash = std.mem.lastIndexOfScalar(u8, bin_dir, '/') orelse return null;
    const parent = exe_path[0..parent_slash];

    const lib_dir = std.fmt.allocPrint(allocator, "{s}/lib", .{parent}) catch return null;
    if (checkLibDir(allocator, lib_dir)) return lib_dir;
    allocator.free(lib_dir);
    return null;
}

fn checkLibDir(allocator: std.mem.Allocator, dir: []const u8) bool {
    const path = std.fmt.allocPrint(allocator, "{s}/libkaappi_rt.a", .{dir}) catch return false;
    defer allocator.free(path);
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0) catch return false;
    _ = std.posix.system.close(fd);
    return true;
}

fn tryLink(allocator: std.mem.Allocator, cc: []const u8, ll_path: []const u8, out_path: []const u8, lib_flag: []const u8, is_zig: bool) bool {
    var argv_buf: [16]?[*:0]const u8 = .{null} ** 16;
    var argc: usize = 0;

    const cc_z = allocator.dupeZ(u8, cc) catch return false;
    defer allocator.free(cc_z);
    argv_buf[argc] = cc_z;
    argc += 1;

    if (is_zig) {
        argv_buf[argc] = "cc";
        argc += 1;
    }

    argv_buf[argc] = "-w";
    argc += 1;

    const ll_z = allocator.dupeZ(u8, ll_path) catch return false;
    defer allocator.free(ll_z);
    argv_buf[argc] = ll_z;
    argc += 1;

    argv_buf[argc] = "-o";
    argc += 1;

    const out_z = allocator.dupeZ(u8, out_path) catch return false;
    defer allocator.free(out_z);
    argv_buf[argc] = out_z;
    argc += 1;

    const lib_z = allocator.dupeZ(u8, lib_flag) catch return false;
    defer allocator.free(lib_z);
    argv_buf[argc] = lib_z;
    argc += 1;

    argv_buf[argc] = "-lkaappi_rt";
    argc += 1;
    argv_buf[argc] = "-lc";
    argc += 1;
    argv_buf[argc] = "-lm";
    argc += 1;
    argv_buf[argc] = "-lpthread";
    argc += 1;
    argv_buf[argc] = null;

    const pid = std.posix.system.fork();
    if (pid < 0) return false;

    if (pid == 0) {
        _ = std.posix.system.execve(
            @ptrCast(argv_buf[0].?),
            @ptrCast(&argv_buf),
            @ptrCast(std.c.environ),
        );
        std.process.exit(127);
    }

    var status: c_int = 0;
    _ = std.c.waitpid(pid, &status, 0);
    const raw: c_uint = @bitCast(status);
    const exited = (raw & 0x7f) == 0;
    if (!exited) return false;
    const exit_code = (raw >> 8) & 0xff;
    if (exit_code == 0) {
        var msgbuf: [512]u8 = undefined;
        const msg = std.fmt.bufPrint(&msgbuf, "Compiled {s}\n", .{out_path}) catch return true;
        writeStdout(msg);
        return true;
    }
    return false;
}
