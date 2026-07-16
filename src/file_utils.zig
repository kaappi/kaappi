const std = @import("std");
const platform = @import("platform.zig");
const builtin_os = @import("builtin").os;
const is_wasm = builtin_os.tag == .wasi;

pub fn readWholeFile(allocator: std.mem.Allocator, path: []const u8, max_size: usize) ![]u8 {
    const fd = if (comptime is_wasm) blk: {
        var result_fd: std.os.wasi.fd_t = undefined;
        const rc = std.os.wasi.path_open(3, .{ .SYMLINK_FOLLOW = true }, path.ptr, path.len, .{}, .{ .FD_READ = true, .FD_SEEK = true }, .{ .FD_READ = true }, .{}, &result_fd);
        if (rc != .SUCCESS) return error.FileNotFound;
        break :blk @as(c_int, @intCast(result_fd));
    } else blk: {
        const path_z = allocator.dupeZ(u8, path) catch return error.OutOfMemory;
        defer allocator.free(path_z);
        break :blk platform.openRead(path_z) catch return error.FileNotFound;
    };
    defer platform.close(fd);

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    var tmp: [4096]u8 = undefined;
    while (true) {
        const raw = platform.read(fd, &tmp, tmp.len);
        if (raw == 0) break;
        if (raw < 0) {
            if (platform.errno(raw) == .INTR) continue;
            return error.InputOutput;
        }
        const bytes_read: usize = @intCast(raw);
        if (result.items.len + bytes_read > max_size) return error.StreamTooLong;
        result.appendSlice(allocator, tmp[0..bytes_read]) catch |err| return err;
    }

    return result.toOwnedSlice(allocator);
}
