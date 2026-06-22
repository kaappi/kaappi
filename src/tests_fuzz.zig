const std = @import("std");
const memory = @import("memory.zig");
const reader_mod = @import("reader.zig");
const bytecode_file = @import("bytecode_file.zig");

const Context = @TypeOf(.{});

test "fuzz reader" {
    try std.testing.fuzz(Context{}, struct {
        fn testOne(_: Context, smith: *std.testing.Smith) anyerror!void {
            var buf: [256]u8 = undefined;
            const len = smith.sliceWithHash(&buf, 0);
            const input = buf[0..len];
            var gc = memory.GC.init(std.testing.allocator);
            defer gc.deinit();
            var r = reader_mod.Reader.init(&gc, input);
            while (true) {
                _ = r.readDatum() catch break;
            }
        }
    }.testOne, .{});
}

test "fuzz bytecode loader" {
    try std.testing.fuzz(Context{}, struct {
        fn testOne(_: Context, smith: *std.testing.Smith) anyerror!void {
            var buf: [512]u8 = undefined;
            const len = smith.sliceWithHash(&buf, 0);
            const input = buf[0..len];
            var gc = memory.GC.init(std.testing.allocator);
            defer gc.deinit();
            _ = bytecode_file.readFromBuffer(&gc, input) catch return;
        }
    }.testOne, .{});
}
