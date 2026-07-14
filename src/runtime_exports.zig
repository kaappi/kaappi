const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const vm_mod = @import("vm.zig");
const primitives = @import("primitives.zig");
const library = @import("library.zig");

const Value = types.Value;

var rt_gc: memory.GC = undefined;

pub export fn kaappi_runtime_init() callconv(.c) ?*vm_mod.VM {
    const allocator = std.heap.c_allocator;

    rt_gc = memory.GC.init(allocator);

    if (std.c.getenv("KAAPPI_GC_THRESHOLD")) |env_ptr| {
        const env = std.mem.span(env_ptr);
        if (std.fmt.parseInt(usize, env, 10)) |threshold| {
            rt_gc.gc_threshold = threshold;
        } else |_| {}
    }

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
    memory.setGCInstance(&rt_gc);
    vm_mod.vm_bootstrap.install(vm) catch {
        vm.deinit();
        allocator.destroy(vm);
        return null;
    };
    library.registerStandardLibraries(&vm.libraries, vm.globals) catch {
        vm.deinit();
        allocator.destroy(vm);
        return null;
    };

    return vm;
}

pub export fn kaappi_runtime_deinit(vm: ?*vm_mod.VM) callconv(.c) void {
    if (vm) |v| {
        v.deinit();
        std.heap.c_allocator.destroy(v);
    }
    rt_gc.deinit();
}

pub export fn kaappi_global_lookup(vm: ?*vm_mod.VM, name_ptr: [*]const u8, name_len: u64) callconv(.c) u64 {
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

pub export fn kaappi_define_global(vm: ?*vm_mod.VM, name_ptr: [*]const u8, name_len: u64, val: u64) callconv(.c) void {
    const v = vm orelse return;
    const len: usize = @intCast(name_len);
    const name = name_ptr[0..len];
    v.defineGlobal(name, val) catch {
        _ = std.posix.system.write(2, "failed to define global\n", 24);
        std.process.exit(1);
    };
}

// set! on a global variable: mutate an existing binding, or error if the
// variable is unbound (matching the interpreter's set! semantics). Distinct
// from kaappi_define_global, which always creates/overwrites a binding.
pub export fn kaappi_set_global(vm: ?*vm_mod.VM, name_ptr: [*]const u8, name_len: u64, val: u64) callconv(.c) void {
    const v = vm orelse return;
    const len: usize = @intCast(name_len);
    const name = name_ptr[0..len];
    if (v.globals.getPtr(name)) |ptr| {
        ptr.* = val;
    } else {
        _ = std.posix.system.write(2, "set!: unbound variable '", 24);
        _ = std.posix.system.write(2, name_ptr, len);
        _ = std.posix.system.write(2, "'\n", 2);
        std.process.exit(1);
    }
}

pub export fn kaappi_make_string(vm: ?*vm_mod.VM, str_ptr: [*]const u8, str_len: u64) callconv(.c) u64 {
    const v = vm orelse return 0;
    const len: usize = @intCast(str_len);
    const data = str_ptr[0..len];
    const result = v.gc.allocString(data) catch {
        _ = std.posix.system.write(2, "failed to allocate string\n", 26);
        std.process.exit(1);
    };
    return result;
}

pub export fn kaappi_intern_symbol(vm: ?*vm_mod.VM, name_ptr: [*]const u8, name_len: u64) callconv(.c) u64 {
    const v = vm orelse return 0;
    const len: usize = @intCast(name_len);
    const name = name_ptr[0..len];
    const result = v.gc.allocSymbol(name) catch {
        _ = std.posix.system.write(2, "failed to intern symbol\n", 24);
        std.process.exit(1);
    };
    return result;
}

pub export fn kaappi_create_native_closure(vm: ?*vm_mod.VM, fn_ptr: ?*anyopaque, upvalues_ptr: ?[*]const u64, n_upvalues: u64, arity: u64, name_ptr: [*]const u8, name_len: u64) callconv(.c) u64 {
    const v = vm orelse return 0;
    const n: usize = @intCast(n_upvalues);
    const uv: []const u64 = if (n > 0 and upvalues_ptr != null) upvalues_ptr.?[0..n] else &.{};
    const a: u8 = @intCast(arity);
    const name = name_ptr[0..@as(usize, @intCast(name_len))];
    const nc_fn: types.NativeClosureFnType = @ptrCast(@alignCast(fn_ptr));
    const result = v.gc.allocNativeClosure(nc_fn, uv, a, name) catch {
        _ = std.posix.system.write(2, "OOM: failed to allocate native closure\n", 39);
        std.process.exit(1);
    };
    return result;
}

/// Report a VM error that escaped to natively-compiled code and exit.
/// Formats an uncaught Scheme exception into vm.last_error_detail first so
/// the message names the actual failure instead of just the error class.
fn fatalVMError(vm: *vm_mod.VM, context: []const u8, err: anyerror) noreturn {
    vm.noteUncaughtException(err);
    const detail = vm.getErrorDetail();
    _ = std.posix.system.write(2, context.ptr, context.len);
    if (detail.len > 0) {
        _ = std.posix.system.write(2, ": ", 2);
        _ = std.posix.system.write(2, detail.ptr, detail.len);
    }
    const name = @errorName(err);
    _ = std.posix.system.write(2, " (", 2);
    _ = std.posix.system.write(2, name.ptr, name.len);
    _ = std.posix.system.write(2, ")\n", 2);
    std.process.exit(1);
}

pub export fn kaappi_eval(vm: ?*vm_mod.VM, src_ptr: [*]const u8, src_len: u64) callconv(.c) u64 {
    const v = vm orelse return 0;
    const len: usize = @intCast(src_len);
    const source = src_ptr[0..len];
    const result = v.eval(source) catch |err| fatalVMError(v, "eval error", err);
    return result;
}

fn callPrimitive(name: []const u8, a: u64, b: u64) u64 {
    const vm = vm_mod.vm_instance orelse {
        _ = std.posix.system.write(2, "runtime: no VM instance\n", 24);
        std.process.exit(1);
    };
    const proc = vm.globals.get(name) orelse {
        _ = std.posix.system.write(2, "runtime: undefined primitive\n", 29);
        std.process.exit(1);
    };
    const args = [_]u64{ a, b };
    return vm.callWithArgs(proc, &args) catch |err|
        fatalVMError(vm, "runtime error in primitive", err);
}

pub export fn kaappi_fixnum_add(a: u64, b: u64) callconv(.c) u64 {
    if (types.isFixnum(a) and types.isFixnum(b)) {
        const va = types.toFixnum(a);
        const vb = types.toFixnum(b);
        const result = @addWithOverflow(va, vb);
        if (result[1] == 0 and result[0] >= std.math.minInt(i48) and result[0] <= std.math.maxInt(i48)) {
            return types.makeFixnum(result[0]);
        }
    }
    return callPrimitive("+", a, b);
}

pub export fn kaappi_fixnum_sub(a: u64, b: u64) callconv(.c) u64 {
    if (types.isFixnum(a) and types.isFixnum(b)) {
        const va = types.toFixnum(a);
        const vb = types.toFixnum(b);
        const result = @subWithOverflow(va, vb);
        if (result[1] == 0 and result[0] >= std.math.minInt(i48) and result[0] <= std.math.maxInt(i48)) {
            return types.makeFixnum(result[0]);
        }
    }
    return callPrimitive("-", a, b);
}

pub export fn kaappi_fixnum_mul(a: u64, b: u64) callconv(.c) u64 {
    if (types.isFixnum(a) and types.isFixnum(b)) {
        const va = types.toFixnum(a);
        const vb = types.toFixnum(b);
        const result = @mulWithOverflow(va, vb);
        if (result[1] == 0 and result[0] >= std.math.minInt(i48) and result[0] <= std.math.maxInt(i48)) {
            return types.makeFixnum(result[0]);
        }
    }
    return callPrimitive("*", a, b);
}

pub export fn kaappi_fixnum_lt(a: u64, b: u64) callconv(.c) u64 {
    if (types.isFixnum(a) and types.isFixnum(b))
        return if (types.toFixnum(a) < types.toFixnum(b)) types.TRUE else types.FALSE;
    return callPrimitive("<", a, b);
}

pub export fn kaappi_fixnum_eq(a: u64, b: u64) callconv(.c) u64 {
    if (types.isFixnum(a) and types.isFixnum(b))
        return if (a == b) types.TRUE else types.FALSE;
    return callPrimitive("=", a, b);
}

pub export fn kaappi_car(v: u64) callconv(.c) u64 {
    if (types.isPair(v)) return types.car(v);
    _ = std.posix.system.write(2, "car: not a pair\n", 16);
    std.process.exit(1);
}

pub export fn kaappi_cdr(v: u64) callconv(.c) u64 {
    if (types.isPair(v)) return types.cdr(v);
    _ = std.posix.system.write(2, "cdr: not a pair\n", 16);
    std.process.exit(1);
}

pub export fn kaappi_cons(a: u64, b: u64) callconv(.c) u64 {
    const gc = memory.gc_instance orelse {
        _ = std.posix.system.write(2, "cons: no GC instance\n", 21);
        std.process.exit(1);
    };
    var val_a = a;
    var val_b = b;
    gc.pushRoot(&val_a);
    gc.pushRoot(&val_b);
    const result = gc.allocPair(val_a, val_b) catch {
        _ = std.posix.system.write(2, "OOM: failed to allocate pair\n", 29);
        std.process.exit(1);
    };
    gc.popRoot();
    gc.popRoot();
    return result;
}

pub export fn kaappi_is_null(v: u64) callconv(.c) u64 {
    return if (v == types.NIL) types.TRUE else types.FALSE;
}

// --- Boxed mutable variables (assignment conversion, #1497) ---
//
// The native backend represents a captured-and-mutated variable as a heap
// "box": closures capture the box POINTER by value, and every read/write goes
// through the box, so a mutation is visible to all closures that share the
// binding — matching the interpreter's by-location closure semantics.
//
// A box is a one-slot cell represented as a pair (value . '()). Boxes never
// escape to Scheme code (they are an internal codegen artifact), so reusing the
// pair type keeps the GC's existing marking, write barrier, and sweeping
// correct for free.

pub export fn kaappi_make_box(vm: ?*vm_mod.VM, init: u64) callconv(.c) u64 {
    const v = vm orelse {
        _ = std.posix.system.write(2, "make-box: null vm\n", 18);
        std.process.exit(1);
    };
    // allocPair roots `init` internally before it may collect, so a young
    // initial value survives a GC triggered by this very allocation.
    return v.gc.allocPair(init, types.NIL) catch {
        _ = std.posix.system.write(2, "OOM: failed to allocate box\n", 28);
        std.process.exit(1);
    };
}

pub export fn kaappi_box_ref(box: u64) callconv(.c) u64 {
    return types.car(box);
}

pub export fn kaappi_box_set(box: u64, val: u64) callconv(.c) void {
    // Write barrier before the store: a box promoted to the old generation
    // that starts pointing at a young value must be recorded, or the young
    // value is swept out from under it on the next minor collection.
    if (memory.gc_instance) |gc| gc.writeBarrier(types.toObject(box), val);
    types.setCar(box, val);
}

pub export fn kaappi_call_scheme(vm: ?*vm_mod.VM, callee: u64, args_ptr: ?[*]const u64, nargs: u64) callconv(.c) u64 {
    const v = vm orelse {
        _ = std.posix.system.write(2, "null vm\n", 8);
        std.process.exit(1);
    };
    const n: usize = @intCast(nargs);
    const args: []const Value = if (n > 0 and args_ptr != null) args_ptr.?[0..n] else &.{};
    const result = v.callWithArgs(callee, args) catch |err|
        fatalVMError(v, "runtime error in call", err);
    return result;
}

// Shadow-stack GC rooting for natively compiled code.
// The LLVM emitter stores intermediate Values in alloca slots and registers
// them here so the GC can see them during collection.

pub export fn kaappi_gc_push_root(slot: *Value) callconv(.c) void {
    const gc = memory.gc_instance orelse return;
    gc.pushRoot(slot);
}

pub export fn kaappi_gc_pop_roots(n: u64) callconv(.c) void {
    const gc = memory.gc_instance orelse return;
    var i: u64 = 0;
    while (i < n) : (i += 1) {
        gc.popRoot();
    }
}
