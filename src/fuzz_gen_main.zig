//! Standalone driver for the fuzz program generators: prints the program
//! for a given seed to stdout. Used by the offline differential harness
//! (tests/fuzz/native-diff.sh, issue #1395), which needs reproducible
//! programs from a shell script. Dev/CI tool only — built with
//! `zig build fuzz-gen`, never part of the default install or releases.

const std = @import("std");
const fuzz_gen = @import("fuzz_gen.zig");

fn fail(msg: []const u8) noreturn {
    _ = std.posix.system.write(2, msg.ptr, msg.len);
    std.process.exit(2);
}

fn usage() noreturn {
    fail("usage: kaappi-fuzz-gen <seed> [--native|--full]\n" ++
        "  --full    full R7RS grammar (default; fuzz_gen.zig)\n" ++
        "  --native  native-compilable subset for the VM-vs-native\n" ++
        "            differential harness (fuzz_gen_native.zig)\n");
}

pub fn main(init: std.process.Init.Minimal) !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const gpa = arena.allocator();

    var args = try init.args.iterateAllocator(gpa);
    defer args.deinit();
    _ = args.skip(); // argv[0]

    var seed: ?u64 = null;
    var native = false;
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--native")) {
            native = true;
        } else if (std.mem.eql(u8, arg, "--full")) {
            native = false;
        } else if (seed == null) {
            seed = std.fmt.parseInt(u64, arg, 10) catch usage();
        } else {
            usage();
        }
    }
    const s = seed orelse usage();

    const src = if (native)
        try fuzz_gen.generateNativeSeeded(s, gpa)
    else
        try fuzz_gen.generateSeeded(s, gpa);

    // reporting.writeToFd's loop, except failures are a hard non-zero exit:
    // the harness redirects stdout to a file, and a silently truncated
    // program would be diffed as if it were the real seed.
    var off: usize = 0;
    while (off < src.len) {
        const rc = std.posix.system.write(1, src.ptr + off, src.len - off);
        if (rc < 0) {
            if (std.posix.errno(rc) == .INTR) continue;
            std.process.exit(1);
        }
        if (rc == 0) std.process.exit(1);
        off += @as(usize, @intCast(rc));
    }
}
