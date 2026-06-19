const std = @import("std");

fn writeStdout(msg: []const u8) void {
    _ = std.posix.system.write(1, msg.ptr, msg.len);
}

fn writeStderr(msg: []const u8) void {
    _ = std.posix.system.write(2, msg.ptr, msg.len);
}

fn readFileContents(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{}, 0) catch return error.FileNotFound;
    defer _ = std.posix.system.close(fd);

    const max_size: usize = 8 * 1024 * 1024;
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    var tmp: [4096]u8 = undefined;
    while (true) {
        const bytes_read = std.posix.read(fd, &tmp) catch return error.ReadError;
        if (bytes_read == 0) break;
        if (result.items.len + bytes_read > max_size) return error.StreamTooLong;
        result.appendSlice(allocator, tmp[0..bytes_read]) catch return error.OutOfMemory;
    }

    return result.toOwnedSlice(allocator);
}

fn parseExpectations(allocator: std.mem.Allocator, source: []const u8) !std.ArrayList([]u8) {
    var expected: std.ArrayList([]u8) = .empty;
    errdefer {
        for (expected.items) |line| allocator.free(line);
        expected.deinit(allocator);
    }

    const prefix = ";; expect:";
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trimStart(u8, line, " \t");
        if (!std.mem.startsWith(u8, trimmed, prefix)) continue;
        const wanted = std.mem.trim(u8, trimmed[prefix.len..], " \t\r");
        try expected.append(allocator, try allocator.dupe(u8, wanted));
    }
    return expected;
}

fn failWithOutput(path: []const u8, reason: []const u8, stdout_data: []const u8, stderr_data: []const u8) noreturn {
    var buf: [320]u8 = undefined;
    const header = std.fmt.bufPrint(&buf, "FAIL {s}: {s}\n", .{ path, reason }) catch "FAIL\n";
    writeStderr(header);
    if (stdout_data.len > 0) {
        writeStderr("--- stdout ---\n");
        writeStderr(stdout_data);
        if (stdout_data[stdout_data.len - 1] != '\n') writeStderr("\n");
    }
    if (stderr_data.len > 0) {
        writeStderr("--- stderr ---\n");
        writeStderr(stderr_data);
        if (stderr_data[stderr_data.len - 1] != '\n') writeStderr("\n");
    }
    std.process.exit(1);
}

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.skip();
    const scheme_path = args.next() orelse {
        writeStderr("Usage: zig run tests/run_scheme.zig -- <scheme-file>\n");
        std.process.exit(2);
    };
    if (args.next() != null) {
        writeStderr("Usage: zig run tests/run_scheme.zig -- <scheme-file>\n");
        std.process.exit(2);
    }

    const source = readFileContents(init.gpa, scheme_path) catch {
        failWithOutput(scheme_path, "cannot read test file", "", "");
    };
    defer init.gpa.free(source);

    var expected = parseExpectations(init.gpa, source) catch {
        failWithOutput(scheme_path, "cannot parse ;; expect: directives", "", "");
    };
    defer {
        for (expected.items) |line| init.gpa.free(line);
        expected.deinit(init.gpa);
    }

    const argv = [_][]const u8{
        "zig",
        "build",
        "run",
        "--",
        scheme_path,
    };
    const result = std.process.run(init.gpa, init.io, .{ .argv = &argv }) catch {
        failWithOutput(scheme_path, "failed to launch interpreter", "", "");
    };
    defer init.gpa.free(result.stdout);
    defer init.gpa.free(result.stderr);

    switch (result.term) {
        .exited => |code| {
            if (code != 0) {
                failWithOutput(scheme_path, "non-zero exit status", result.stdout, result.stderr);
            }
        },
        else => {
            failWithOutput(scheme_path, "interpreter terminated unexpectedly", result.stdout, result.stderr);
        },
    }

    if (expected.items.len > 0) {
        var actual_lines: std.ArrayList([]const u8) = .empty;
        defer actual_lines.deinit(init.gpa);

        var it = std.mem.splitScalar(u8, result.stdout, '\n');
        while (it.next()) |line| {
            const trimmed = std.mem.trimEnd(u8, line, "\r");
            if (trimmed.len == 0) continue;
            actual_lines.append(init.gpa, trimmed) catch {
                failWithOutput(scheme_path, "out of memory while checking output", result.stdout, result.stderr);
            };
        }

        if (actual_lines.items.len != expected.items.len) {
            failWithOutput(scheme_path, "output line count mismatch with ;; expect:", result.stdout, result.stderr);
        }
        for (expected.items, 0..) |want, i| {
            if (!std.mem.eql(u8, actual_lines.items[i], want)) {
                failWithOutput(scheme_path, "output mismatch against ;; expect:", result.stdout, result.stderr);
            }
        }
    }

    var msg_buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(
        &msg_buf,
        "PASS {s} ({d} expectation{s})\n",
        .{
            scheme_path,
            expected.items.len,
            if (expected.items.len == 1) "" else "s",
        },
    ) catch "PASS\n";
    writeStdout(msg);
}
