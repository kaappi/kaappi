const std = @import("std");

const page_align = std.heap.page_size_min;

const is_macos = @import("builtin").os.tag == .macos;

pub const CodeBuffer = struct {
    mem: []align(page_align) u8,
    len: usize,

    pub fn alloc(code_size: usize) !CodeBuffer {
        const size = std.mem.alignForward(usize, @max(code_size, page_align), page_align);

        const map_flags = if (@import("builtin").os.tag == .macos)
            std.posix.MAP{ .TYPE = .PRIVATE, .ANONYMOUS = true, .JIT = true }
        else
            std.posix.MAP{ .TYPE = .PRIVATE, .ANONYMOUS = true };

        const mem = try std.posix.mmap(
            null,
            size,
            .{ .READ = true, .WRITE = true, .EXEC = true },
            map_flags,
            -1,
            0,
        );

        return .{ .mem = mem, .len = 0 };
    }

    pub fn writeCode(self: *CodeBuffer, code: []const u32) void {
        const bytes = std.mem.sliceAsBytes(code);
        self.writeCodeBytes(bytes);
    }

    pub fn writeCodeBytes(self: *CodeBuffer, bytes: []const u8) void {
        if (bytes.len > self.mem.len) return;

        if (comptime is_macos) {
            const jit_wp = @extern(*const fn (c_int) callconv(.c) void, .{ .name = "pthread_jit_write_protect_np" });
            jit_wp(0);
        }
        @memcpy(self.mem[0..bytes.len], bytes);
        self.len = bytes.len;
        if (comptime is_macos) {
            const jit_wp = @extern(*const fn (c_int) callconv(.c) void, .{ .name = "pthread_jit_write_protect_np" });
            const icache_inv = @extern(*const fn (*anyopaque, usize) callconv(.c) void, .{ .name = "sys_icache_invalidate" });
            jit_wp(1);
            icache_inv(@ptrCast(self.mem.ptr), self.len);
        }
    }

    pub fn getEntryPoint(self: *const CodeBuffer) *const fn () callconv(.c) u64 {
        return @ptrCast(@alignCast(self.mem.ptr));
    }

    pub fn free(self: *CodeBuffer) void {
        std.posix.munmap(self.mem);
        self.* = undefined;
    }
};

test "mmap executable memory and run trivial function" {
    if (@import("builtin").cpu.arch != .aarch64) return error.SkipZigTest;
    var buf = try CodeBuffer.alloc(4096);
    defer buf.free();

    // AArch64: mov x0, #42; ret
    const code = [_]u32{
        0xD2800540, // movz x0, #42
        0xD65F03C0, // ret
    };
    buf.writeCode(&code);

    const func = buf.getEntryPoint();
    const result = func();
    try std.testing.expectEqual(@as(u64, 42), result);
}

test "mmap code buffer with addition" {
    if (@import("builtin").cpu.arch != .aarch64) return error.SkipZigTest;
    var buf = try CodeBuffer.alloc(4096);
    defer buf.free();

    // AArch64: mov x0, #10; add x0, x0, #32; ret
    const code = [_]u32{
        0xD2800140, // movz x0, #10
        0x91008000, // add x0, x0, #32
        0xD65F03C0, // ret
    };
    buf.writeCode(&code);

    const func = buf.getEntryPoint();
    const result = func();
    try std.testing.expectEqual(@as(u64, 42), result);
}
