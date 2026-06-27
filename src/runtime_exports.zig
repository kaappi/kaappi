const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const library = @import("library.zig");

const Value = types.Value;

var rt_gc: memory.GC = undefined;

export fn kaappi_runtime_init() callconv(.c) ?*vm_mod.VM {
    const allocator = std.heap.c_allocator;

    rt_gc = memory.GC.init(allocator);

    const vm = allocator.create(vm_mod.VM) catch return null;
    vm.* = vm_mod.VM.init(&rt_gc) catch {
        allocator.destroy(vm);
        return null;
    };
    vm_mod.setVMInstance(vm);

    primitives.registerAll(vm) catch {
        vm.deinit();
        allocator.destroy(vm);
        return null;
    };
    primitives.setGCInstance(&rt_gc);
    library.registerStandardLibraries(&vm.libraries, &vm.globals) catch {
        vm.deinit();
        allocator.destroy(vm);
        return null;
    };

    return vm;
}

export fn kaappi_runtime_deinit(vm: ?*vm_mod.VM) callconv(.c) void {
    if (vm) |v| {
        v.deinit();
        std.heap.c_allocator.destroy(v);
    }
    rt_gc.deinit();
}

export fn kaappi_global_lookup(vm: ?*vm_mod.VM, name_ptr: [*]const u8, name_len: u64) callconv(.c) u64 {
    const v = vm orelse return 0;
    const len: usize = @intCast(name_len);
    const name = name_ptr[0..len];
    return v.globals.get(name) orelse {
        _ = std.posix.system.write(2, "undefined variable: ", 20);
        _ = std.posix.system.write(2, name_ptr, len);
        _ = std.posix.system.write(2, "\n", 1);
        std.process.exit(1);
    };
}

export fn kaappi_call_scheme(vm: ?*vm_mod.VM, callee: u64, args_ptr: ?[*]const u64, nargs: u64) callconv(.c) u64 {
    _ = vm;
    const n: usize = @intCast(nargs);
    const args: []const Value = if (n > 0 and args_ptr != null) args_ptr.?[0..n] else &.{};

    if (!types.isPointer(callee)) {
        _ = std.posix.system.write(2, "not a procedure\n", 16);
        std.process.exit(1);
    }
    const obj = types.toObject(callee);
    if (obj.tag != .native_fn) {
        _ = std.posix.system.write(2, "not a procedure\n", 16);
        std.process.exit(1);
    }
    const native = obj.as(types.NativeFn);
    const result = native.func(args) catch {
        _ = std.posix.system.write(2, "runtime error\n", 14);
        std.process.exit(1);
    };
    return result;
}
