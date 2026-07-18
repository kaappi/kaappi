//! Post-link ELF patcher that marks a binary PT_OPENBSD_NOBTCFI so OpenBSD's
//! `ld.so`/kernel skip Branch Target CFI (BTCFI) enforcement on it.
//!
//! Why this exists: OpenBSD on arm64 enforces BTCFI — an indirect branch
//! (`BLR`/`BR`) must land on a `bti` instruction, or the CPU raises
//! `SIGILL`/`ILL_BTCFI`. Its base clang emits those landing pads by default;
//! Zig 0.16 cannot (no `-mbranch-protection`, no `bti` CPU feature), so a
//! Zig-built binary traps on its first function-pointer call. OpenBSD's own
//! opt-out is the linker flag `-z nobtcfi`, which emits a `PT_OPENBSD_NOBTCFI`
//! program header — a pure marker (type only; zero offset/size). Zig's CLI
//! rejects that `-z` flag, so we add the marker after the fact.
//!
//! How: the program header table sits immediately before `.interp` with no
//! room to append an entry, so instead of growing the table we repurpose the
//! `PT_GNU_STACK` entry in place. OpenBSD ignores `PT_GNU_STACK` (it enforces
//! W^X independently and sizes the main stack from `RLIMIT_STACK`), so
//! overwriting its 56 bytes with the NOBTCFI marker is a no-op for stack
//! handling and gains the opt-out. Idempotent: a binary already carrying the
//! marker is left untouched.
//!
//! The `kaappi compile` native backend takes the honest path instead — the
//! system cc/ld accepts `-z nobtcfi` directly (native_compiler.zig). This
//! tool is only for the Zig-linked binaries (kaappi, thottam, kaappi-lsp, and
//! the unit-test executables). See docs/dev/openbsd.md.

const std = @import("std");

const PT_GNU_STACK: u32 = 0x6474e551;
const PT_OPENBSD_NOBTCFI: u32 = 0x65a3dbe8;
const PF_X: u32 = 1;

pub fn main(init: std.process.Init.Minimal) !void {
    var it = init.args.iterate();
    _ = it.next(); // skip argv[0]
    var any = false;
    while (it.next()) |path| {
        any = true;
        patch(path) catch |err| {
            std.debug.print("openbsd_nobtcfi: {s}: {s}\n", .{ path, @errorName(err) });
            std.process.exit(1);
        };
    }
    if (!any) {
        std.debug.print("usage: openbsd_nobtcfi <elf-file> [<elf-file>...]\n", .{});
        std.process.exit(2);
    }
}

fn patch(path: [:0]const u8) !void {
    const fd = try std.posix.openatZ(std.posix.AT.FDCWD, path, .{ .ACCMODE = .RDWR }, 0);
    defer _ = std.c.close(fd);

    var ehdr: [64]u8 = undefined;
    try preadExact(fd, &ehdr, 0);
    if (!std.mem.eql(u8, ehdr[0..4], "\x7fELF")) return error.NotElf;
    if (ehdr[4] != 2) return error.NotElf64; // EI_CLASS != ELFCLASS64
    if (ehdr[5] != 1) return error.NotLittleEndian; // EI_DATA != ELFDATA2LSB — every openbsd target Kaappi builds is LE

    const e_phoff = std.mem.readInt(u64, ehdr[0x20..0x28], .little);
    const e_phentsize = std.mem.readInt(u16, ehdr[0x36..0x38], .little);
    const e_phnum = std.mem.readInt(u16, ehdr[0x38..0x3a], .little);
    if (e_phentsize < 56) return error.BadPhdrEntSize;

    var i: u16 = 0;
    while (i < e_phnum) : (i += 1) {
        const off = e_phoff + @as(u64, i) * e_phentsize;
        var ent: [56]u8 = undefined;
        try preadExact(fd, &ent, off);
        const p_type = std.mem.readInt(u32, ent[0..4], .little);
        if (p_type == PT_OPENBSD_NOBTCFI) return; // idempotent — already marked
        if (p_type == PT_GNU_STACK) {
            var repl = [_]u8{0} ** 56;
            std.mem.writeInt(u32, repl[0..4], PT_OPENBSD_NOBTCFI, .little); // p_type
            std.mem.writeInt(u32, repl[4..8], PF_X, .little); // p_flags (marker only)
            try pwriteExact(fd, &repl, off);
            return;
        }
    }
    return error.NoGnuStackPhdr;
}

fn preadExact(fd: std.posix.fd_t, buf: []u8, offset: u64) !void {
    var n: usize = 0;
    while (n < buf.len) {
        const r = std.c.pread(fd, buf[n..].ptr, buf.len - n, @intCast(offset + n));
        if (r < 0) return error.ReadFailed;
        if (r == 0) return error.UnexpectedEof;
        n += @intCast(r);
    }
}

fn pwriteExact(fd: std.posix.fd_t, buf: []const u8, offset: u64) !void {
    var n: usize = 0;
    while (n < buf.len) {
        const r = std.c.pwrite(fd, buf[n..].ptr, buf.len - n, @intCast(offset + n));
        if (r < 0) return error.WriteFailed;
        n += @intCast(r);
    }
}
