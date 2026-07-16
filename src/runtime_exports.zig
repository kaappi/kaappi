const std = @import("std");
const platform = @import("platform.zig");
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

    if (platform.getenv("KAAPPI_GC_THRESHOLD")) |env_ptr| {
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
        _ = platform.write(2, "undefined variable: ", 20);
        _ = platform.write(2, name_ptr, len);
        _ = platform.write(2, "\n", 1);
        std.process.exit(1);
    };
}

pub export fn kaappi_define_global(vm: ?*vm_mod.VM, name_ptr: [*]const u8, name_len: u64, val: u64) callconv(.c) void {
    const v = vm orelse return;
    const len: usize = @intCast(name_len);
    const name = name_ptr[0..len];
    v.defineGlobal(name, val) catch {
        _ = platform.write(2, "failed to define global\n", 24);
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
        _ = platform.write(2, "set!: unbound variable '", 24);
        _ = platform.write(2, name_ptr, len);
        _ = platform.write(2, "'\n", 2);
        std.process.exit(1);
    }
}

pub export fn kaappi_make_string(vm: ?*vm_mod.VM, str_ptr: [*]const u8, str_len: u64) callconv(.c) u64 {
    const v = vm orelse return 0;
    const len: usize = @intCast(str_len);
    const data = str_ptr[0..len];
    const result = v.gc.allocString(data) catch {
        _ = platform.write(2, "failed to allocate string\n", 26);
        std.process.exit(1);
    };
    return result;
}

pub export fn kaappi_intern_symbol(vm: ?*vm_mod.VM, name_ptr: [*]const u8, name_len: u64) callconv(.c) u64 {
    const v = vm orelse return 0;
    const len: usize = @intCast(name_len);
    const name = name_ptr[0..len];
    const result = v.gc.allocSymbol(name) catch {
        _ = platform.write(2, "failed to intern symbol\n", 24);
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
        _ = platform.write(2, "OOM: failed to allocate native closure\n", 39);
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
    _ = platform.write(2, context.ptr, context.len);
    if (detail.len > 0) {
        _ = platform.write(2, ": ", 2);
        _ = platform.write(2, detail.ptr, detail.len);
    }
    const name = @errorName(err);
    _ = platform.write(2, " (", 2);
    _ = platform.write(2, name.ptr, name.len);
    _ = platform.write(2, ")\n", 2);
    std.process.exit(1);
}

pub export fn kaappi_eval(vm: ?*vm_mod.VM, src_ptr: [*]const u8, src_len: u64) callconv(.c) u64 {
    const v = vm orelse return 0;
    const len: usize = @intCast(src_len);
    const source = src_ptr[0..len];
    const result = v.eval(source) catch |err| fatalVMError(v, "eval error", err);
    return result;
}

// Caching entry point for the LLVM backend's eval fallbacks (#1494). Forms the
// native backend cannot lower (letrec, cond, case, do, guard, quasiquote, named
// let, and eval-fallback lambdas) are serialized to a source string; plain
// kaappi_eval re-parses and re-compiles that string every time the enclosing
// native code runs it — a severe cliff inside a loop or hot function.
//
// The emitter allocates one `slot` global per fallback call site. On the first
// execution the form is parsed and compiled once, the resulting Function is
// permanently rooted, and its Value is stashed in `slot`; every later execution
// reads `slot` and runs the cached Function directly. The compiled bytecode
// looks up globals by name at run time, so a fallback that first republishes
// the enclosing frame's params/upvalues as globals still observes the current
// values on each execution — behavior is identical to plain kaappi_eval.
pub export fn kaappi_eval_cached(vm: ?*vm_mod.VM, src_ptr: [*]const u8, src_len: u64, slot: *u64) callconv(.c) u64 {
    const v = vm orelse return 0;
    const len: usize = @intCast(src_len);
    const source = src_ptr[0..len];

    // Only the main runtime thread touches the cache — this check comes before
    // the slot is read OR written. A natively-compiled lambda that reaches an
    // eval fallback can run on a spawned SRFI-18 thread, which has its own VM
    // and GC. Two cross-heap hazards must both be avoided: populating the slot
    // with a Function compiled in a child heap (freed at thread-join, leaving a
    // dangling pointer), and executing a main-heap cached Function under a child
    // VM. Child threads therefore always take the plain, uncached path — exactly
    // the pre-caching behavior — so the shared slot stays main-thread-only and
    // race-free.
    if (v.gc != &rt_gc) {
        return v.eval(source) catch |err| fatalVMError(v, "eval error", err);
    }

    // Fast path: this call site has already compiled its form. `slot` holds the
    // cached Function value, kept alive by a permanent GC root created when it
    // was compiled; re-run it directly.
    if (slot.* != 0) {
        return v.runCachedForm(slot.*) catch |err| fatalVMError(v, "eval error", err);
    }

    // Slow path (first execution at this call site): compile once, permanently
    // root the Function, and cache it. A source that is not a single compilable
    // expression (e.g. a special top-level form) yields an error here; fall back
    // to a plain, uncached eval, which both handles those forms and reports any
    // genuine syntax error with full detail.
    const func_val = v.compileCachedForm(source) catch
        return v.eval(source) catch |err| fatalVMError(v, "eval error", err);
    slot.* = func_val;
    return v.runCachedForm(func_val) catch |err| fatalVMError(v, "eval error", err);
}

// Build-once cache for the LLVM backend's quoted heap constants (#1495). A
// quoted pair/vector literal has no immediate representation, so the emitter
// serializes it to a `(quote …)` source string. Plain kaappi_eval re-reads and
// re-builds that constant on every execution — both a hot-path cliff and a
// correctness divergence: the interpreter compiles a quote to a single
// constant-pool entry, so every evaluation of one literal returns the SAME
// object (`eq?`), whereas a fresh rebuild is `eq?` to nothing.
//
// The emitter allocates one `slot` global per quoted-literal call site. The
// first execution builds the constant, permanently roots it, and stashes it in
// `slot`; every later execution returns the cached object directly — matching
// the interpreter's per-call-site constant sharing. This is the data analogue
// of kaappi_eval_cached: that caches a compiled Function, this caches the built
// value itself.
pub export fn kaappi_quote_cached(vm: ?*vm_mod.VM, src_ptr: [*]const u8, src_len: u64, slot: *u64) callconv(.c) u64 {
    const v = vm orelse return 0;
    const len: usize = @intCast(src_len);
    const source = src_ptr[0..len];

    // Only the main runtime thread touches the shared slot — the guard precedes
    // both the read and the write, exactly as in kaappi_eval_cached. A natively
    // compiled body that evaluates a quoted literal can run on a spawned SRFI-18
    // thread, which has its own VM and GC; caching a child-heap constant (freed
    // at join) or returning a main-heap one under a child VM are cross-heap
    // hazards. Child threads therefore build the constant fresh on every
    // execution — exactly the pre-caching behavior — so the slot stays
    // main-thread-only and race-free.
    if (v.gc != &rt_gc) {
        return v.eval(source) catch |err| fatalVMError(v, "eval error", err);
    }

    // Fast path: already built. `slot` holds the cached constant, kept alive by
    // a permanent GC root created on first build.
    if (slot.* != 0) return slot.*;

    // Slow path (first execution at this call site): build once, permanently
    // root, and cache. rootedSlot only appends to the C-allocated extra_roots
    // list, so no Scheme-heap allocation runs between eval returning the fresh
    // constant and it becoming rooted — the young constant cannot be swept in
    // the gap. The root lives for the whole program (the slot is a module global
    // the collector never scans), so extra_roots — not the LIFO shadow stack —
    // is the right anchor.
    const val = v.eval(source) catch |err| fatalVMError(v, "eval error", err);
    _ = v.gc.rootedSlot(val) catch {
        _ = platform.write(2, "OOM: failed to root quoted constant\n", 36);
        std.process.exit(1);
    };
    slot.* = val;
    return val;
}

fn callPrimitive(name: []const u8, a: u64, b: u64) u64 {
    const vm = vm_mod.vm_instance orelse {
        _ = platform.write(2, "runtime: no VM instance\n", 24);
        std.process.exit(1);
    };
    const proc = vm.globals.get(name) orelse {
        _ = platform.write(2, "runtime: undefined primitive\n", 29);
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
    _ = platform.write(2, "car: not a pair\n", 16);
    std.process.exit(1);
}

pub export fn kaappi_cdr(v: u64) callconv(.c) u64 {
    if (types.isPair(v)) return types.cdr(v);
    _ = platform.write(2, "cdr: not a pair\n", 16);
    std.process.exit(1);
}

pub export fn kaappi_cons(a: u64, b: u64) callconv(.c) u64 {
    const gc = memory.gc_instance orelse {
        _ = platform.write(2, "cons: no GC instance\n", 21);
        std.process.exit(1);
    };
    var val_a = a;
    var val_b = b;
    gc.pushRoot(&val_a);
    gc.pushRoot(&val_b);
    const result = gc.allocPair(val_a, val_b) catch {
        _ = platform.write(2, "OOM: failed to allocate pair\n", 29);
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
        _ = platform.write(2, "make-box: null vm\n", 18);
        std.process.exit(1);
    };
    // allocPair roots `init` internally before it may collect, so a young
    // initial value survives a GC triggered by this very allocation.
    return v.gc.allocPair(init, types.NIL) catch {
        _ = platform.write(2, "OOM: failed to allocate box\n", 28);
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
        _ = platform.write(2, "null vm\n", 8);
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
