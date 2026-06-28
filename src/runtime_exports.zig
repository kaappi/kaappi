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

export fn kaappi_define_global(vm: ?*vm_mod.VM, name_ptr: [*]const u8, name_len: u64, val: u64) callconv(.c) void {
    const v = vm orelse return;
    const len: usize = @intCast(name_len);
    const name = name_ptr[0..len];
    v.defineGlobal(name, val) catch {
        _ = std.posix.system.write(2, "failed to define global\n", 24);
        std.process.exit(1);
    };
}

export fn kaappi_make_string(vm: ?*vm_mod.VM, str_ptr: [*]const u8, str_len: u64) callconv(.c) u64 {
    const v = vm orelse return 0;
    const len: usize = @intCast(str_len);
    const data = str_ptr[0..len];
    const result = v.gc.allocString(data) catch {
        _ = std.posix.system.write(2, "failed to allocate string\n", 26);
        std.process.exit(1);
    };
    return result;
}

export fn kaappi_intern_symbol(vm: ?*vm_mod.VM, name_ptr: [*]const u8, name_len: u64) callconv(.c) u64 {
    const v = vm orelse return 0;
    const len: usize = @intCast(name_len);
    const name = name_ptr[0..len];
    const result = v.gc.allocSymbol(name) catch {
        _ = std.posix.system.write(2, "failed to intern symbol\n", 24);
        std.process.exit(1);
    };
    return result;
}

export fn kaappi_eval(vm: ?*vm_mod.VM, src_ptr: [*]const u8, src_len: u64) callconv(.c) u64 {
    const v = vm orelse return 0;
    const len: usize = @intCast(src_len);
    const source = src_ptr[0..len];
    const result = v.eval(source) catch {
        _ = std.posix.system.write(2, "eval error\n", 11);
        std.process.exit(1);
    };
    return result;
}

export fn kaappi_fixnum_add(a: u64, b: u64) callconv(.c) u64 {
    if (types.isFixnum(a) and types.isFixnum(b)) {
        const va = types.toFixnum(a);
        const vb = types.toFixnum(b);
        const result = @addWithOverflow(va, vb);
        if (result[1] == 0 and result[0] >= std.math.minInt(i48) and result[0] <= std.math.maxInt(i48)) {
            return types.makeFixnum(result[0]);
        }
    }
    return 0;
}

export fn kaappi_fixnum_sub(a: u64, b: u64) callconv(.c) u64 {
    if (types.isFixnum(a) and types.isFixnum(b)) {
        const va = types.toFixnum(a);
        const vb = types.toFixnum(b);
        const result = @subWithOverflow(va, vb);
        if (result[1] == 0 and result[0] >= std.math.minInt(i48) and result[0] <= std.math.maxInt(i48)) {
            return types.makeFixnum(result[0]);
        }
    }
    return 0;
}

export fn kaappi_fixnum_mul(a: u64, b: u64) callconv(.c) u64 {
    if (types.isFixnum(a) and types.isFixnum(b)) {
        const va = types.toFixnum(a);
        const vb = types.toFixnum(b);
        const result = @mulWithOverflow(va, vb);
        if (result[1] == 0 and result[0] >= std.math.minInt(i48) and result[0] <= std.math.maxInt(i48)) {
            return types.makeFixnum(result[0]);
        }
    }
    return 0;
}

export fn kaappi_fixnum_lt(a: u64, b: u64) callconv(.c) u64 {
    if (types.isFixnum(a) and types.isFixnum(b))
        return if (types.toFixnum(a) < types.toFixnum(b)) types.TRUE else types.FALSE;
    return types.FALSE;
}

export fn kaappi_fixnum_eq(a: u64, b: u64) callconv(.c) u64 {
    if (types.isFixnum(a) and types.isFixnum(b))
        return if (a == b) types.TRUE else types.FALSE;
    return types.FALSE;
}

export fn kaappi_car(v: u64) callconv(.c) u64 {
    if (types.isPair(v)) return types.car(v);
    return 0;
}

export fn kaappi_cdr(v: u64) callconv(.c) u64 {
    if (types.isPair(v)) return types.cdr(v);
    return 0;
}

export fn kaappi_cons(a: u64, b: u64) callconv(.c) u64 {
    const gc = primitives.gc_instance orelse return 0;
    return gc.allocPair(a, b) catch return 0;
}

export fn kaappi_is_null(v: u64) callconv(.c) u64 {
    return if (v == types.NIL) types.TRUE else types.FALSE;
}

export fn kaappi_call_scheme(vm: ?*vm_mod.VM, callee: u64, args_ptr: ?[*]const u64, nargs: u64) callconv(.c) u64 {
    const v = vm orelse {
        _ = std.posix.system.write(2, "null vm\n", 8);
        std.process.exit(1);
    };
    const n: usize = @intCast(nargs);
    const args: []const Value = if (n > 0 and args_ptr != null) args_ptr.?[0..n] else &.{};
    const result = v.callWithArgs(callee, args) catch {
        _ = std.posix.system.write(2, "runtime error in call\n", 22);
        std.process.exit(1);
    };
    return result;
}
