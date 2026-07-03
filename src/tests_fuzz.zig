const std = @import("std");
const memory = @import("memory.zig");
const reader_mod = @import("reader.zig");
const bytecode_file = @import("bytecode_file.zig");
const compiler_mod = @import("compiler.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const library = @import("library.zig");
const types = @import("types.zig");

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
            defer r.deinit();
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

test "fuzz compiler" {
    try std.testing.fuzz(Context{}, struct {
        fn testOne(_: Context, smith: *std.testing.Smith) anyerror!void {
            var buf: [256]u8 = undefined;
            const len = smith.sliceWithHash(&buf, 0);
            const input = buf[0..len];
            var gc = memory.GC.init(std.testing.allocator);
            defer gc.deinit();
            var r = reader_mod.Reader.init(&gc, input);
            defer r.deinit();
            const expr = r.readDatum() catch return;
            var macros = std.StringHashMap(types.Value).init(std.testing.allocator);
            defer macros.deinit();
            var globals = std.StringHashMap(types.Value).init(std.testing.allocator);
            defer globals.deinit();
            _ = compiler_mod.compileExpressionWithMacros(&gc, expr, &macros, &globals) catch return;
        }
    }.testOne, .{});
}

test "fuzz eval" {
    try std.testing.fuzz(Context{}, struct {
        fn testOne(_: Context, smith: *std.testing.Smith) anyerror!void {
            var buf: [128]u8 = undefined;
            const len = smith.sliceWithHash(&buf, 0);
            const input = buf[0..len];
            var gc = memory.GC.init(std.testing.allocator);
            defer gc.deinit();
            const vm = std.testing.allocator.create(vm_mod.VM) catch return;
            vm.* = vm_mod.VM.init(&gc) catch {
                std.testing.allocator.destroy(vm);
                return;
            };
            defer {
                vm.deinit();
                std.testing.allocator.destroy(vm);
            }
            vm_mod.setVMInstance(vm);
            primitives.registerAll(vm) catch return;
            primitives.setGCInstance(&gc);
            library.registerStandardLibraries(&vm.libraries, vm.globals) catch return;
            vm.timeout_deadline_ns = @import("vm_calls.zig").clockNs() + 100_000_000;
            _ = vm.eval(input) catch return;
        }
    }.testOne, .{});
}
