const std = @import("std");
const types = @import("types.zig");
pub const memory = @import("memory.zig");
const library_mod = @import("library.zig");
const primitives_mod = @import("primitives.zig");
const vm_mod = @import("vm.zig");
pub const VM = vm_mod.VM;
pub const VMError = vm_mod.VMError;
pub const Value = types.Value;

/// Build a fully bootstrapped VM for a unit test. The VM is heap-allocated
/// and returned by pointer: `vm_instance` and the GC root marker reach the
/// VM by address, so it must never move. Returning the struct by value (as
/// this helper used to) left `vm_instance` pointing at a dead stack frame —
/// harmless while the GC threshold was never reached mid-test, but fatal
/// under -Dgc-stress=true, where every collection between construction and
/// the first execute() then failed to mark the globals and swept live
/// objects (#1401). `vm.deinit()` also destroys the struct (heap_owned).
pub fn makeTestVM(gc: *memory.GC) !*VM {
    const vm = try gc.allocator.create(VM);
    vm.* = VM.init(gc) catch |err| {
        gc.allocator.destroy(vm);
        return err;
    };
    vm.heap_owned = true;
    errdefer vm.deinit();
    memory.setGCInstance(gc);
    // Register before the first primitive allocation: under stress every
    // allocation collects, and only a registered vm_instance lets the root
    // marker keep the globals map alive while it is being populated.
    vm_mod.setVMInstance(vm);
    try primitives_mod.registerAll(vm);
    try vm_mod.vm_bootstrap.install(vm);
    try library_mod.registerStandardLibraries(&vm.libraries, vm.globals);
    return vm;
}

pub const TestContext = struct {
    gc: memory.GC,
    vm: *VM,

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
