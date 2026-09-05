//! Compiler/expander callback shims: the bridge the compiler and expander
//! reach the VM through. `setVMInstance` wires each of these into a
//! function pointer on `globals.zig` (which cannot import vm.zig), and the
//! rest are the implementations behind those pointers — macro-expansion-time
//! eval and transformer calls, syntax-property storage, library/feature
//! queries, and the binding lookups the compiled global-resolution paths use.

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

const compiler_mod = @import("compiler.zig");
const globals_mod = @import("globals.zig");
const vm_library = @import("vm_library.zig");

const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;

pub fn setVMInstance(vm: *VM) void {
    vm_mod.vm_instance = vm;
    globals_mod.setGlobalsContext(.{
        .globals = vm.globals,
        .globals_lock = vm.globals_lock,
        .owns_globals = vm.owns_globals,
    });
    globals_mod.library_exists_checker = &checkLibraryExists;
    globals_mod.srfi_feature_checker = &checkSrfiFeature;
    globals_mod.base_binding_lookup = &lookupBaseBinding;
    globals_mod.current_lib_name_lookup = &getCurrentLibName;
    globals_mod.def_env_binding_lookup = &lookupDefEnvBinding;
    globals_mod.def_env_binding_set = &setDefEnvBinding;
    globals_mod.eval_datum_for_macro = &evalDatumForMacro;
    globals_mod.call_proc_for_macro = &callProcForMacro;
    globals_mod.error_detail_for_macro = &errorDetailForMacro;
    globals_mod.set_error_detail_for_macro = &setErrorDetailForMacro;
    globals_mod.syntax_property_set = &syntaxPropertySet;
    globals_mod.syntax_property_get = &syntaxPropertyGet;
    globals_mod.env_map_rooted_lookup = &envMapIsGcRooted;
}

/// #1962: whether `map` is one of the environment maps `markVmRoots` traces
/// unconditionally, exposed to the compiler through
/// `globals.env_map_rooted_lookup` so it can enforce the untraced-env-map
/// invariant (see `VM.isGcRootedEnvMap`). Returns false when no VM is live,
/// which is safe: without a VM no collection can observe the field.
fn envMapIsGcRooted(map: *std.StringHashMap(Value)) bool {
    const vm = vm_mod.vm_instance orelse return false;
    return vm.isGcRootedEnvMap(map);
}

/// SRFI 211: evaluate a datum at macro-expansion time in the global
/// environment (the transformer-spec RHS of er-macro-transformer/
/// lisp-transformer, or a define-property value expression). Same
/// compile-and-run discipline as primitives_r7rs.evalFn's plain path.
fn evalDatumForMacro(expr: Value) anyerror!Value {
    const vm = vm_mod.vm_instance orelse return VMError.InvalidBytecode;
    const gc = vm.gc;
    var expr_root = expr;
    gc.pushRoot(&expr_root);
    defer gc.popRoot();
    const func = try compiler_mod.compileExpressionWithMacros(gc, expr_root, &vm.macros, vm.globals);
    var closure_val = try gc.allocClosure(func);
    compiler_mod.Compiler.unrootFunction(gc, func);
    gc.pushRoot(&closure_val);
    defer gc.popRoot();
    return vm.callWithArgs(closure_val, &[_]Value{});
}

/// SRFI 211: invoke a procedural macro transformer (or a SRFI 213
/// capture-lookup re-entry procedure) from inside the expander. On failure,
/// formats an escaping Scheme-level exception into last_error_detail exactly
/// as a top-level form's own uncaught exception would (#1846): callReentrant
/// (used here for a Closure transformer.proc) only preserves last_error_detail
/// across its own cleanup, it doesn't populate it from current_exception the
/// way execute()'s top-level boundary does via noteUncaughtException. Without
/// this, `(error "msg" irritant)` raised inside a transformer leaves
/// current_exception set but last_error_detail empty, and errorDetailForMacro
/// below would have nothing to report. A primitive's own direct type error
/// (e.g. `(car 7)`) already sets last_error_detail itself and is unaffected
/// (noteUncaughtException no-ops for anything other than ExceptionRaised).
fn callProcForMacro(proc: Value, args: []const Value) anyerror!Value {
    const vm = vm_mod.vm_instance orelse return VMError.InvalidBytecode;
    return vm.callWithArgs(proc, args) catch |err| {
        vm.noteUncaughtException(err);
        return err;
    };
}

/// #1846: expose the VM's last recorded error detail to the expander/compiler
/// (which cannot import vm.zig) so a procedural macro transformer's real
/// failure -- the message above, or a primitive's own type-error text --
/// reaches compiler_macro.zig's error.TransformerFailed arms instead of being
/// discarded.
fn errorDetailForMacro() []const u8 {
    const vm = vm_mod.vm_instance orelse return "";
    return vm.getErrorDetail();
}

/// #2403: let the expander's native procedures record a precise rejection
/// message in the VM's error detail (see globals.set_error_detail_for_macro).
/// No-ops without a VM: mapNativeError then supplies its generic fallback.
fn setErrorDetailForMacro(msg: []const u8) void {
    const vm = vm_mod.vm_instance orelse return;
    vm.setErrorDetail("{s}", .{msg});
}

/// SRFI 213: store a property value under the composite key
/// "<id>\x1f<key>". Overwriting an existing property replaces its value
/// (the SRFI's post-finalization note on repeated definition).
fn syntaxPropertySet(id: []const u8, key: []const u8, val: Value) anyerror!void {
    const vm = vm_mod.vm_instance orelse return VMError.InvalidBytecode;
    const gpa = vm.gc.allocator;
    const composite = try std.fmt.allocPrint(gpa, "{s}\x1f{s}", .{ id, key });
    const gop = try vm.syntax_properties.getOrPut(composite);
    if (gop.found_existing) gpa.free(composite);
    gop.value_ptr.* = val;
}

fn syntaxPropertyGet(id: []const u8, key: []const u8) ?Value {
    const vm = vm_mod.vm_instance orelse return null;
    const gpa = vm.gc.allocator;
    const composite = std.fmt.allocPrint(gpa, "{s}\x1f{s}", .{ id, key }) catch return null;
    defer gpa.free(composite);
    return vm.syntax_properties.get(composite);
}

fn checkLibraryExists(lib_name: []const u8, lib_name_list: Value) bool {
    const vm = vm_mod.vm_instance orelse return false;
    return vm_library.libraryIsAvailableSrfi261(vm, lib_name, lib_name_list);
}

fn checkSrfiFeature(name: []const u8) bool {
    const vm = vm_mod.vm_instance orelse return false;
    return vm_library.srfiFeatureAvailable(vm, name);
}

/// Look up `name` in `(scheme base)`'s own export table — populated once at
/// startup from vm.globals and never touched again afterward — rather than
/// vm.globals itself, which a later top-level `define` (or a library like
/// SRFI 101 redefining `list`) freely overwrites (#1715).
///
/// Falls back to the `.internal` primitives' snapshot, which has the same
/// write-once-at-startup property but hangs off no `(scheme …)` library
/// (#1856). Compiler-synthesized code reaches
/// `%make-record`/`%record-ref`/`%parameter-set!`/… through here, so a user
/// program is free to bind those names itself without breaking
/// `define-record-type`, `parameterize`, or `delay` in the same scope. The two
/// tables have disjoint key sets — a `%`-prefixed name is never a `scheme.*`
/// export (comptime-enforced in primitives.zig) — so the order is immaterial.
fn lookupBaseBinding(name: []const u8) ?Value {
    const vm = vm_mod.vm_instance orelse return null;
    if (vm.libraries.get("scheme.base")) |lib| {
        if (lib.exports.get(name)) |val| return val;
    }
    return vm.libraries.internal_bindings.get(name);
}

/// The canonical name of the library currently being compiled, live for the
/// whole duration handleDefineLibrary spends processing its declarations
/// (including any define-syntax within them) -- null outside library
/// compilation, e.g. a top-level/REPL define-syntax (#1812).
fn getCurrentLibName() ?[]const u8 {
    const vm = vm_mod.vm_instance orelse return null;
    return vm.loading_library_name;
}

/// Look up `origname` in the library named `libname`'s own lib_env -- the
/// full internal environment (exported or not), unlike lookupBaseBinding's
/// `exports`, since a macro's free reference is as likely to hit a private
/// helper as an exported name. Unlocked, matching lookupBaseBinding's own
/// unlocked `lib.exports.get` above: both rely on a library's environment
/// being effectively read-only once the library has finished loading and
/// been registered (#1812).
fn lookupDefEnvBinding(libname: []const u8, origname: []const u8) ?Value {
    const vm = vm_mod.vm_instance orelse return null;
    const lib = vm.libraries.get(libname) orelse return null;
    const env = lib.lib_env orelse return null;
    return env.get(origname);
}

/// Store `val` into the library named `libname`'s own lib_env binding
/// `origname` -- a macro's expansion assigning to a library-internal
/// variable it references. Locked like set_global's own env.getPtr/store
/// (vm_dispatch.zig): a library's lib_env is shared across SRFI-18 threads
/// exactly like vm.globals is (#1812).
fn setDefEnvBinding(libname: []const u8, origname: []const u8, val: Value) bool {
    const vm = vm_mod.vm_instance orelse return false;
    const lib = vm.libraries.get(libname) orelse return false;
    const env = lib.lib_env orelse return false;
    vm.lockGlobalsShared();
    defer vm.unlockGlobalsShared();
    const ptr = env.getPtr(origname) orelse return false;
    ptr.* = val;
    return true;
}
