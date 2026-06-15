const std = @import("std");

pub fn main() !void {
    // Placeholder — will be implemented after build works
    const stdout = std.io.getStdOut().writer();
    try stdout.writeAll("Scheme test runner: not yet implemented\n");
}
