const std = @import("std");

const page_align = std.heap.page_size_min;

extern "c" fn pthread_jit_write_protect_np(enabled: c_int) void;
extern "c" fn sys_icache_invalidate(addr: *anyopaque, size: usize) void;

pub const CodeBuffer = struct {
    mem: []align(page_align) u8,
    len: usize,

    pub fn alloc(code_size: usize) !CodeBuffer {
        const size = std.mem.alignForward(usize, @max(code_size, page_align), page_align);

        const mem = try std.posix.mmap(
            null,
            size,
            .{ .READ = true, .WRITE = true, .EXEC = true },
            .{ .TYPE = .PRIVATE, .ANONYMOUS = true, .JIT = true },
            -1,
            0,
        );

        return .{ .mem = mem, .len = 0 };
    }

    pub fn writeCode(self: *CodeBuffer, code: []const u32) void {
        const bytes = std.mem.sliceAsBytes(code);
        if (bytes.len > self.mem.len) return;

        pthread_jit_write_protect_np(0);
        @memcpy(self.mem[0..bytes.len], bytes);
        self.len = bytes.len;
        pthread_jit_write_protect_np(1);

        sys_icache_invalidate(@ptrCast(self.mem.ptr), self.len);
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
