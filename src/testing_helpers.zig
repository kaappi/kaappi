const std = @import("std");
const types = @import("types.zig");
pub const memory = @import("memory.zig");
const library_mod = @import("library.zig");
const primitives_mod = @import("primitives.zig");
const vm_mod = @import("vm.zig");
pub const VM = vm_mod.VM;
pub const VMError = vm_mod.VMError;
pub const Value = types.Value;

pub fn makeTestVM(gc: *memory.GC) !VM {
    var vm = try VM.init(gc);
    memory.setGCInstance(gc);
    try primitives_mod.registerAll(&vm);
    try library_mod.registerStandardLibraries(&vm.libraries, vm.globals);
    return vm;
}

pub const TestContext = struct {
    gc: memory.GC,
    vm: VM,

    pub fn init(self: *TestContext) !void {
        self.gc = memory.GC.init(std.testing.allocator);
        self.vm = makeTestVM(&self.gc) catch |err| {
            self.gc.deinit();
            return err;
        };
    }

    pub fn deinit(self: *TestContext) void {
        self.vm.deinit();
        self.gc.deinit();
    }
};

pub fn expectEval(source: []const u8, expected: i64) !void {
    var ctx: TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = try ctx.vm.eval(source);
    try std.testing.expectEqual(expected, types.toFixnum(result));
}

pub fn expectEvalTrue(source: []const u8) !void {
    var ctx: TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = try ctx.vm.eval(source);
    try std.testing.expectEqual(types.TRUE, result);
}

pub fn expectEvalBool(source: []const u8, expected: bool) !void {
    var ctx: TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = try ctx.vm.eval(source);
    try std.testing.expectEqual(if (expected) types.TRUE else types.FALSE, result);
}

pub fn expectEvalVoid(source: []const u8) !void {
    var ctx: TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    const result = try ctx.vm.eval(source);
    try std.testing.expectEqual(types.VOID, result);
}
