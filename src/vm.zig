const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");

const diagnostics = @import("diagnostics.zig");
const compiler_mod = @import("compiler.zig");
const library_mod = @import("library.zig");
const reactor_mod = @import("reactor.zig");
pub const globals_mod = @import("globals.zig");
const Value = types.Value;
const OpCode = types.OpCode;

pub const vm_library = @import("vm_library.zig");
pub const vm_records = @import("vm_records.zig");
pub const vm_continuations = @import("vm_continuations.zig");
pub const vm_bootstrap = @import("vm_bootstrap.zig");

pub const VMError = @import("errors.zig").KaappiError;

pub const INITIAL_FRAME_CAPACITY = types.INITIAL_FRAME_CAPACITY;
pub const INITIAL_REGISTER_CAPACITY = types.INITIAL_REGISTER_CAPACITY;
pub const MAX_FRAME_LIMIT = types.MAX_FRAME_LIMIT;
pub const MAX_REGISTER_LIMIT = types.MAX_REGISTER_LIMIT;
pub const INITIAL_HANDLER_CAPACITY = types.INITIAL_HANDLER_CAPACITY;
pub const INITIAL_WIND_CAPACITY = types.INITIAL_WIND_CAPACITY;
pub const MAX_HANDLER_LIMIT = types.MAX_HANDLER_LIMIT;
pub const MAX_WIND_LIMIT = types.MAX_WIND_LIMIT;

pub threadlocal var vm_instance: ?*VM = null;

pub fn setVMInstance(vm: *VM) void {
    vm_instance = vm;
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
    globals_mod.syntax_property_set = &syntaxPropertySet;
    globals_mod.syntax_property_get = &syntaxPropertyGet;
}

/// SRFI 211: evaluate a datum at macro-expansion time in the global
/// environment (the transformer-spec RHS of er-macro-transformer/
/// lisp-transformer, or a define-property value expression). Same
/// compile-and-run discipline as primitives_r7rs.evalFn's plain path.
fn evalDatumForMacro(expr: Value) anyerror!Value {
    const vm = vm_instance orelse return VMError.InvalidBytecode;
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
    const vm = vm_instance orelse return VMError.InvalidBytecode;
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
    const vm = vm_instance orelse return "";
    return vm.getErrorDetail();
}

/// SRFI 213: store a property value under the composite key
/// "<id>\x1f<key>". Overwriting an existing property replaces its value
/// (the SRFI's post-finalization note on repeated definition).
fn syntaxPropertySet(id: []const u8, key: []const u8, val: Value) anyerror!void {
    const vm = vm_instance orelse return VMError.InvalidBytecode;
    const gpa = vm.gc.allocator;
    const composite = try std.fmt.allocPrint(gpa, "{s}\x1f{s}", .{ id, key });
    const gop = try vm.syntax_properties.getOrPut(composite);
    if (gop.found_existing) gpa.free(composite);
    gop.value_ptr.* = val;
}

fn syntaxPropertyGet(id: []const u8, key: []const u8) ?Value {
    const vm = vm_instance orelse return null;
    const gpa = vm.gc.allocator;
    const composite = std.fmt.allocPrint(gpa, "{s}\x1f{s}", .{ id, key }) catch return null;
    defer gpa.free(composite);
    return vm.syntax_properties.get(composite);
}

fn checkLibraryExists(lib_name: []const u8, lib_name_list: Value) bool {
    const vm = vm_instance orelse return false;
    return vm_library.libraryIsAvailableSrfi261(vm, lib_name, lib_name_list);
}

fn checkSrfiFeature(name: []const u8) bool {
    const vm = vm_instance orelse return false;
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
    const vm = vm_instance orelse return null;
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
    const vm = vm_instance orelse return null;
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
    const vm = vm_instance orelse return null;
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
    const vm = vm_instance orelse return false;
    const lib = vm.libraries.get(libname) orelse return false;
    const env = lib.lib_env orelse return false;
    vm.lockGlobalsShared();
    defer vm.unlockGlobalsShared();
    const ptr = env.getPtr(origname) orelse return false;
    ptr.* = val;
    return true;
}

pub const GlobalsRwLock = globals_mod.GlobalsRwLock;
pub const acquireGlobalsWrite = globals_mod.acquireGlobalsWrite;
pub const releaseGlobalsWrite = globals_mod.releaseGlobalsWrite;
pub const acquireGlobalsRead = globals_mod.acquireGlobalsRead;
pub const releaseGlobalsRead = globals_mod.releaseGlobalsRead;

/// Mark the VM's live roots during a GC cycle: the register window of every
/// active call frame, the frame closures, the exception-handler stack,
/// dynamic-wind thunks, the in-flight exception, and the global/macro tables.
///
/// Without this, a collection triggered mid-execution (e.g. while capturing a
/// continuation in a tight loop) would free objects reachable only through the
/// VM — including the closures and bytecode currently executing — leading to
/// use-after-free. Registered as the GC's `root_marker`.
fn markVMRoots(gc: *memory.GC) void {
    const vm = vm_instance orelse return;
    if (vm.gc != gc) return; // only mark the VM that owns this GC
    markVmRoots(gc, vm);
}

/// Mark every Value `vm` keeps live: the register window of every active call
/// frame, the frame closures, the exception-handler stack, dynamic-wind
/// thunks, the in-flight exception, the parameter overrides, the thread
/// handle, and — when this VM owns the shared tables — the global/macro/
/// library values. Called with the VM's OWN gc by its own markVMRoots, and
/// with the ROOT gc by markLiveChildRoots for each live child VM: in the
/// latter case the child is quiescent (stopped at a safepoint or parked, see
/// CollectionState), so reading its frames/registers races nothing, and
/// markValue's foreign-owner skip keeps the parent's collector off the
/// child's own heap objects (kaappi#1933).
pub fn markVmRoots(gc: *memory.GC, vm: *VM) void {
    for (vm.frames[0..vm.frame_count]) |f| {
        if (f.closure) |cls| gc.markValue(types.makePointer(&cls.header));
        if (f.native) |nf| gc.markValue(types.makePointer(&nf.header));
        const window = f.frameWindow();
        const end: usize = @min(@as(usize, f.base) + window, vm.registers.len);
        var r: usize = f.base;
        while (r < end) : (r += 1) gc.markValue(vm.registers[r]);
    }

    for (vm.handler_stack[0..vm.handler_count]) |h| gc.markValue(h.handler);

    for (vm.wind_stack[0..vm.wind_count]) |wr| {
        gc.markValue(wr.before);
        gc.markValue(wr.after);
    }

    if (vm.current_exception) |exc| gc.markValue(exc);
    if (vm.callback_error_value) |exc| gc.markValue(exc);
    gc.markValue(vm.continuation_value);
    gc.markValue(vm.default_random_source);
    // Foreign (parent-heap) for a child thread, so markValue skips it; the
    // parent roots the handle. Marked here for the same reason every other
    // Value field is: a same-heap value would be kept alive by it (#2125).
    if (vm.thread_handle) |h| gc.markValue(h);

    // Only mark globals/macros when this VM owns them. Child threads
    // share the parent's maps — the parent GC keeps those values alive.
    // Marking them here would write mark bits on parent-heap objects
    // without synchronization (data race).
    if (vm.owns_globals) {
        var git = vm.globals.valueIterator();
        while (git.next()) |v| gc.markValue(v.*);
        var mit = vm.macros.valueIterator();
        while (mit.next()) |v| gc.markValue(v.*);
        var uit = vm.record_uid_registry.valueIterator();
        while (uit.next()) |v| gc.markValue(v.*);
        var spit = vm.syntax_properties.valueIterator();
        while (spit.next()) |v| gc.markValue(v.*);
    }

    var pit = vm.param_overrides.valueIterator();
    while (pit.next()) |v| gc.markValue(v.*);

    if (vm.owns_globals) {
        var lit = vm.libraries.libraries.valueIterator();
        while (lit.next()) |lib| {
            var eit = lib.exports.valueIterator();
            while (eit.next()) |v| gc.markValue(v.*);
            if (lib.lib_env) |env| {
                var eit2 = env.valueIterator();
                while (eit2.next()) |v| gc.markValue(v.*);
            }
        }
        // Envs of replaced libraries stay reachable through closures that
        // were compiled against them (#820).
        for (vm.libraries.retired_envs.items) |env| {
            var eit = env.valueIterator();
            while (eit.next()) |v| gc.markValue(v.*);
        }
        // The pristine `.internal` primitives (#1856): only compiler-
        // synthesized references reach them, so a user `define` of the same
        // name is all it takes for globals to stop holding them.
        var iit = vm.libraries.internal_bindings.valueIterator();
        while (iit.next()) |v| gc.markValue(v.*);
    }

    // Mark library environments being built by handleDefineLibrary
    for (vm.pending_lib_envs[0..vm.pending_lib_env_count]) |maybe_env| {
        if (maybe_env) |env| {
            var eit = env.valueIterator();
            while (eit.next()) |v| gc.markValue(v.*);
        }
    }

    // Mark fiber scheduler state (suspended fibers' execution state)
    if (vm.scheduler) |sched| {
        sched.markRoots(gc);
    }
    // Belt-and-braces: see Reactor.markRoots's doc comment.
    if (vm.reactor) |r| {
        r.markRoots(gc);
    }
}

pub const ExceptionHandler = types.ExceptionHandler;

pub const writeStderr = @import("reporting.zig").writeStderr;

pub const CallFrame = types.CallFrame;

pub const StepMode = enum { none, step, next, step_out, continue_to_break };

pub const Breakpoint = struct {
    name: []const u8,
    condition: ?[]const u8 = null,
};

pub const WatchEntry = struct {
    name: []const u8,
    last_value: Value = types.VOID,
};

pub const ProfileTimeEntry = struct {
    func: ?*types.Function,
    entry_ns: u64,
};

/// #1933 (stop-the-world): a child VM's reported execution state, read by
/// the collecting parent (markLiveChildRoots) to decide whether the VM's
/// registers/frames are quiescent enough to mark:
///
///   .running   — bytecode is (or may resume) executing; registers/frames
///                can change at any moment. The parent must wait for a
///                safepoint or a park. This is also the state inside a
///                bounded native call (a primitive, a nested dispatch), which
///                returns to the dispatch loop promptly and hits the safepoint
///                within 1024 instructions.
///   .stopped   — at the dispatch-loop safepoint, between instructions, with
///                `collection_stop` set. Quiescent; the parent marks and then
///                clears `collection_stop` to let the child resume.
///   .parked    — blocked in a wait (reactor poll, the capped cross-thread
///                polling loops). Quiescent while reported; the resume path
///                (setCollectionRunning) re-checks `collection_stop` before
///                letting bytecode run, so a parent that observed this state
///                can always mark it frozen.
///   .in_native — inside an FFI call (callFfi) or a raw thread join
///                (reapOsThread): may block indefinitely and never reaches
///                the safepoint. Quiescent while reported; the FFI callbacks
///                that re-enter Scheme switch back to `.running` for their
///                extent (see callWithArgs), and the resume path re-checks
///                `collection_stop` the same way.
///
/// Transitions are plain atomics on the child side and are never observed
/// by the parent except while the child's own GC is guaranteed not to be
/// touching these objects — see the safepoint/park protocol in
/// markLiveChildRoots.
pub const CollectionState = enum(u8) { running, parked, stopped, in_native };

pub const VM = struct {
    gc: *memory.GC,
    registers: []Value,
    frames: []CallFrame,
    frame_count: usize = 0,
    /// Heap-allocated and shared BY POINTER with SRFI-18 child-thread VMs
    /// (initForThread), so a parent-side rehash is seen by children instead
    /// of leaving them on a freed bucket array (#958). Access protocol
    /// (globals_lock):
    ///   - structural mutation (put/remove — may rehash and free the bucket
    ///     array) takes the exclusive lock, on any thread;
    ///   - child threads (owns_globals == false) take the shared lock for
    ///     every map read;
    ///   - the owner thread reads lock-free: it is the only thread expected
    ///     to structurally mutate the map, so its own reads cannot race.
    /// Known gap: a child that defines globals via `eval` takes the exclusive
    /// lock (protecting other children), but the owner's lock-free reads can
    /// still race such writes — same limitation PR #968 documented for child
    /// writes. The `macros` and `libraries` maps are still shared by struct
    /// copy and have the analogous (much rarer) staleness hazard.
    globals: *std.StringHashMap(Value),
    globals_lock: *GlobalsRwLock,
    macros: std.StringHashMap(Value),
    /// SRFI 237 `(nongenerative <uid>)`: maps a uid string to the RecordType
    /// Value first defined with it, so a later `define-record-type` using
    /// the same uid reuses the existing type instead of allocating a new,
    /// non-interoperable one. Shared across threads the same way as
    /// `macros` (struct-copy in initForThread, owning-VM-only deinit/mark
    /// below) -- nongenerative identity is scoped to a single owning VM's
    /// lifetime, same rarer-staleness tradeoff already accepted for macros.
    record_uid_registry: std.StringHashMap(Value),
    /// SRFI 213 identifier properties: "<id>\x1f<key>" (both effective,
    /// hygiene-stripped names; owned strings) -> the property value,
    /// evaluated at macro-expansion time by `define-property`. Shared
    /// across threads the same way as `record_uid_registry` (struct-copy in
    /// initForThread, owning-VM-only deinit/mark below), with the same
    /// rarer-staleness tradeoff.
    syntax_properties: std.StringHashMap(Value),
    output: std.ArrayList(u8),
    libraries: library_mod.LibraryRegistry,
    /// Growable, like `frames`/`registers` (#1886). Never a fixed array: 64
    /// dynamically nested `guard`s is ordinary in recursive code, and the old
    /// inline `[64]` cap turned depth 65 into a silently wrong answer.
    handler_stack: []ExceptionHandler,
    handler_count: usize = 0,
    native_reentry_depth: u16 = 0,
    current_exception: ?Value = null,
    // SRFI 248 empty-continuation?: set by the bytecode dispatch loop just
    // before it enters a native via a *tail* call, cleared before a regular
    // call. When a sticky (unwind) handler catches, raise/raise-continuable
    // combine it with the handler's frame_count baseline to decide whether the
    // delimited continuation is empty, latched into `pending_raise_empty` for
    // `%unwind-raise-empty?` to read.
    native_call_was_tail: bool = false,
    pending_raise_empty: bool = false,
    /// Growable, for the same reason as `handler_stack` above (#1886).
    wind_stack: []types.WindRecord,
    wind_count: usize = 0,
    continuation_invoked: bool = false,
    continuation_value: Value = types.VOID,
    continuation_generation: u32 = 0,
    /// Monotonic counter backing CallFrame.seq (0 is never a valid seq).
    frame_seq: u64 = 0,
    stdin_port: Value = types.VOID,
    stdout_port: Value = types.VOID,
    stderr_port: Value = types.VOID,
    current_input_port_param: Value = types.VOID,
    current_output_port_param: Value = types.VOID,
    current_error_port_param: Value = types.VOID,
    lib_paths: []const []const u8 = &.{},
    command_line_args: []const []const u8 = &.{},
    /// SRFI 59/193: the absolute path of the top-level script currently
    /// running, resolved once at startup (runFile) -- `.`/`..` are
    /// lexically normalized but symlinks are never followed, matching
    /// SRFI 193's own "absolute pathname ... symbolic links are not
    /// resolved" text. `null` when not running a script (REPL, stdin, or a
    /// `load`ed/imported file -- this is the top-level script's own path,
    /// not whatever happens to be loading right now, unlike the transient
    /// per-load `current_lib_dir` below). Owned by the root VM only (freed
    /// in `deinit` under the same `owns_globals` guard as `globals`); child
    /// threads (`initForThread`) share the parent's reference read-only,
    /// same as `globals`/`macros`/`libraries`, and must never free it.
    script_path: ?[]const u8 = null,
    loading_libs: std.StringHashMap(void),
    /// Directory of the .sld file currently being loaded, for resolving include paths.
    current_lib_dir: ?[]const u8 = null,
    current_lib_env: ?*std.StringHashMap(Value) = null,
    /// Library environments being built by handleDefineLibrary. Traced by
    /// markVMRoots so closures defined in begin blocks survive GC before
    /// the library is registered. Supports nesting (e.g. SRFI 64 importing
    /// SRFI 35 triggers a recursive handleDefineLibrary).
    pending_lib_envs: [8]?*std.StringHashMap(Value) = .{null} ** 8,
    pending_lib_env_count: u8 = 0,
    /// When non-null, handleDefineLibrary collects compiled functions here
    /// for .sbc cache writing. Set by tryLoadLibraryFromFile.
    lib_compile_collect: ?*std.ArrayList(*types.Function) = null,
    last_callback_error: bool = false,
    /// Scheme exception stashed by an FFI callback trampoline when the
    /// callback raises (ffi_callback.zig): the C frames between the FFI call
    /// and the trampoline cannot be unwound, so callFfi re-raises this after
    /// the enclosing FFI call returns. Traced by markVMRoots.
    callback_error_value: ?Value = null,
    /// True when the VM struct itself was heap-allocated by its creator and
    /// deinit() should destroy it (testing_helpers.makeTestVM). The struct
    /// must live at a stable address: `vm_instance` and the GC root marker
    /// reach it by pointer, so a by-value move would leave them dangling —
    /// under -Dgc-stress=true that means every collection during construction
    /// misses the globals and frees live objects (#1401).
    heap_owned: bool = false,
    last_error_detail: [256]u8 = [_]u8{0} ** 256,
    last_error_detail_len: usize = 0,
    last_error_line: u32 = 0,
    last_error_col: u32 = 0,
    last_error_source: ?[]const u8 = null,
    /// Dotted name of the library whose declarations are currently being
    /// processed (nested loads save/restore it), or null at top level.
    /// Error locations point at the top-level form that triggered the load,
    /// so diagnostics raised from inside a library's own declarations — the
    /// import-collision check especially — use this to name the library the
    /// problem actually lives in.
    loading_library_name: ?[]const u8 = null,
    // Diagnostic code of the escaping error (KEP-0005, #1504). Set by
    // noteUncaughtException from the raised error object; reset per top-level
    // form in resetExecutionState. When `.uncategorized`, the reporting layer
    // derives a code from the Zig error instead.
    last_error_code: diagnostics.Code = .uncategorized,
    // A structured fix suggestion for the escaping error (kaappi#1505): the
    // nearest defined name for an undefined-variable error, surfaced as
    // `data.suggestions` in `--diagnostics=json`. Borrowed from the globals
    // key table (stable for the VM's lifetime), read by reportRuntimeError
    // immediately after the error, and cleared alongside last_error_code (at
    // execute() entry and after each report) so it never goes stale.
    last_error_suggestion: ?[]const u8 = null,
    last_stack_trace: [16]StackFrame = undefined,
    last_stack_trace_len: usize = 0,
    // Debugger state
    debug_mode: bool = false,
    breakpoints: [16]Breakpoint = undefined,
    breakpoint_count: usize = 0,
    step_mode: StepMode = .none,
    step_frame: usize = 0,
    watches: [16]WatchEntry = undefined,
    watch_count: usize = 0,
    inspect_frame: usize = 0,
    global_version: u32 = 0,
    profile_mode: bool = false,
    coverage_mode: bool = false,
    coverage_xml_path: ?[]const u8 = null,
    profile_last_ns: u64 = 0,
    profile_time_stack: [256]ProfileTimeEntry = undefined,
    profile_time_depth: usize = 0,
    sandbox_mode: bool = false,
    /// Set by the `kaappi test` worker path: when true, `(exit code)` records
    /// the request and returns instead of terminating the process, so the
    /// worker always reaches its result-emission step even when a test file's
    /// SRFI-64 epilogue calls `(exit 1)` on failure. `exit_requested`/
    /// `exit_code` capture the last such request. No effect on normal runs.
    suppress_exit: bool = false,
    exit_requested: bool = false,
    exit_code: u8 = 0,
    timeout_deadline_ns: ?u64 = null,
    instruction_counter: u64 = 0,
    /// Optional speed-independent execution bound: when set, `runUntil` aborts
    /// with ExecutionTimeout once `instruction_counter` reaches it. A wall-clock
    /// deadline is meaningless under a gc-stress build (a full collection on
    /// every allocation slows execution by orders of magnitude while the program
    /// runs the same number of instructions), so the fuzz eval harness bounds by
    /// instruction count there instead. See src/tests_fuzz.zig.
    instruction_limit: ?u64 = null,
    owns_globals: bool = true,
    /// Virtual filesystem for standalone binary: maps file paths → source content.
    /// Populated from .sbc bundled files section; checked before disk reads.
    bundled_files: ?*std.StringHashMap([]const u8) = null,
    /// When non-null, record files read during library loading for bundling.
    compile_collect_files: ?*std.StringHashMap([]const u8) = null,
    param_overrides: std.AutoHashMap(usize, Value) = undefined,
    default_random_source: Value = types.VOID,
    /// Set by the pthread_atfork child handler (primitives_random.zig): this
    /// process inherited the default source's PRNG state from its parent at
    /// fork(2), and the next use must reseed it in place before drawing.
    default_rs_needs_reseed: bool = false,
    scheduler: ?*@import("fiber.zig").FiberScheduler = null,
    current_fiber: ?*@import("fiber.zig").Fiber = null,
    /// Per-OS-thread I/O readiness/timer multiplexer (KEP-0001). Lazily
    /// created together with `scheduler` by fiber.ensureScheduler.
    reactor: ?*reactor_mod.Reactor = null,
    yielded: bool = false,
    /// Set by a blocking primitive (channel-receive, fiber-join) together with
    /// error.Yielded: the dispatch loop must rewind ip to the start of the
    /// calling instruction so the primitive re-executes when the fiber is
    /// rescheduled, instead of resuming with an unwritten result register.
    yield_retry: bool = false,
    // ----- Bounded-step execution (kaappi#2283) -----------------------------
    // A resumable, safepoint-driven entry point (vm_step.zig) so a host — the
    // browser playground foremost — can run Scheme code in instruction-budgeted
    // chunks, handing control back between chunks, instead of blocking until the
    // program completes. Reuses the machinery the SRFI-18 scheduler and GC
    // already need: the dispatch-loop safepoint, error.Yielded, and frames that
    // live in the VM struct rather than on the host C stack across a yield.
    //
    /// Instruction-counter value at which the safepoint pauses. Null disables
    /// bounded stepping (every ordinary run). Consulted only while `step_active`.
    step_deadline: ?u64 = null,
    /// True only inside the outermost, driver-entered runUntil — the one loop
    /// where no re-entrant native Zig frame sits between the safepoint and the
    /// stepper, so returning error.Yielded cannot strand a half-finished native
    /// primitive. runUntil consumes `step_dispatch_pending` into this and
    /// save/restores it, exactly as it does `dispatched_from_scheduler`, so a
    /// nested runUntil (eval, a native higher-order driver's callback, a
    /// scheduler fiber slice, a file-backed library load) never pauses.
    step_active: bool = false,
    /// Set by beginStep/resumeStep immediately before their run() call and
    /// consumed by the next runUntil into `step_active`. Only set when no
    /// scheduler exists, so a fibered program's scheduler slices run to
    /// completion within a step rather than pausing mid-fiber.
    step_dispatch_pending: bool = false,
    /// Set by the safepoint when it pauses for the step budget; distinguishes a
    /// bounded-step pause from a fiber park (both surface as error.Yielded). A
    /// step pause needs no ip rewind (it happens between instructions, not mid
    /// native call) and must not be routed through the scheduler as a yield.
    step_paused: bool = false,
    /// Root-stack depth captured by beginStep so a resumeStep whose form raises
    /// can truncate the root stack back to where the form began — the #1855
    /// boundary a single execute() captures at entry, persisted across the pause.
    step_root_depth: u32 = 0,
    /// Set by a scheduler loop immediately before its runUntil(0, 0) call;
    /// consumed by runUntil on entry into dispatched_from_scheduler.
    sched_dispatch_pending: bool = false,
    /// True while the innermost active runUntil was invoked directly by a
    /// fiber scheduler loop. Blocking primitives may only park the current
    /// fiber with yield_retry when this is set — otherwise Zig-native frames
    /// (a native higher-order driver's callback, with-exception-handler's
    /// thunk, eval) sit between the fiber's bytecode and the scheduler, and
    /// a retry would corrupt them. `map`/`for-each` and `dynamic-wind` are
    /// *not* examples: they are bootstrapped Scheme (vm_bootstrap.zig), so
    /// their bodies and callbacks stay in this loop and a fiber parks
    /// inside them (#1959). Only the wind before/after thunks re-entered
    /// via callThunk are native frames — by a continuation transition
    /// (vm_continuations.zig) or by an unwind, either a frame return
    /// leaving its own extent (vm_dispatch.zig) or an error unwinding
    /// execute (vm_calls.zig).
    dispatched_from_scheduler: bool = false,
    /// SRFI 181: incremented/decremented (via defer) only around the
    /// callWithArgs calls into a custom port's read!/write!/get-position/
    /// set-position!/close/flush. Since those calls always run with
    /// dispatched_from_scheduler forced false (nested runUntil, see above),
    /// a callback that blocks — on another port's fd, on thread-sleep!, on a
    /// channel, on a fiber/thread join, on a mutex or condition variable —
    /// would otherwise fall into an unbounded recursive scheduler drive
    /// (fiber.waitForFd's park-vs-drive branch, or fiber.runSchedulerStep
    /// directly) with a confirmed native-stack-overflow risk under
    /// concurrent fibers. This narrow counter (not the broader
    /// native_reentry_depth, which is incremented for every reentrant call —
    /// with-exception-handler thunks, native higher-order drivers'
    /// callbacks, apply — and would wrongly reject those already-working
    /// patterns too) lets those sites raise a specific, catchable error
    /// instead, only for the case this SRFI introduces.
    ///
    /// Three sites read it. fiber.runSchedulerStep is the general one: every
    /// in-place drive passes through it, so a newly added blocking primitive
    /// is covered without touching anything (#2000 was exactly that gap —
    /// channel-receive/channel-send/fiber-join and SRFI-18's thread-join!/
    /// mutex-lock!/condition-variable-wait each drove the scheduler
    /// recursively, and enough nesting killed the process with SIGBUS well
    /// before callReentrant's max_native_depth could fire, since a level
    /// here is a nested runUntil *plus* a drive). fiber.waitForFd and
    /// primitives_srfi18.threadSleepFn additionally check for themselves,
    /// earlier: each has state (a registered fd, an armed timer) it is
    /// cheaper never to arm than to unwind.
    in_custom_port_callback: u16 = 0,
    /// For child OS threads (SRFI-18): points at the parent-heap fiber's
    /// `terminated` flag. Checked at the periodic dispatch-loop safepoint so
    /// thread-terminate! from another thread can stop this VM. Written by the
    /// parent thread, read here — access must be atomic.
    terminate_flag: ?*bool = null,
    /// For child OS threads (SRFI-18): the thread handle (the fiber value
    /// make-thread returned, in the parent's heap) this VM was started for,
    /// so mutex-state can report the owner as the thread the caller holds
    /// rather than this child's internal current fiber (#2125). Set
    /// unconditionally by threadEntryFn, whatever heap the handle lives in:
    /// threadStartImpl reads it to maintain the fiber's live-descendant
    /// count for every thread, and the #2129 retirement protocol keeps the
    /// handle's heap alive until this thread's whole descendant subtree has
    /// drained. mutex-lock!'s owner_thread reporting re-checks
    /// root-ownership before publishing the handle (reportableOwnerHandle),
    /// so a middle-heap handle never escapes into a mutex that can outlive
    /// the middle's join. Null for the main VM and for local fibers -- there
    /// the current fiber IS the thread. The handle is foreign to this GC and
    /// is rooted by the parent while the child runs, so markValue skips it.
    thread_handle: ?Value = null,
    /// The root VM (the one with owns_globals == true, never freed): what a
    /// child thread's threadEntryFn prologue must dereference, not the
    /// immediate parent's VM, whose struct and tables a grandchild's parent
    /// join can free underneath it (#2129). Resolved at initForThread by
    /// walking the parent chain; null on the root itself.
    root_vm: ?*VM = null,
    /// #1933 (stop-the-world): a child VM's participation in the collecting
    /// parent's stop-the-world dance. `collection_stop` is set by
    /// markLiveChildRoots (primitives_srfi18.zig) before it waits; the child
    /// polls it at the dispatch-loop safepoint and parks in `stopForCollection`
    /// (spinning between instructions, where its registers/frames are
    /// consistent) until the parent has marked and clears it. `collection_state`
    /// reports whether the VM is safe to mark: `.running` (bytecode executing,
    /// registers may change — never mark), `.parked`/`.stopped`/`.in_native`
    /// (quiescent — mark). Only meaningful on child VMs (owns_globals ==
    /// false); the root VM collects and is never stopped.
    collection_stop: std.atomic.Value(bool) = .init(false),
    collection_state: std.atomic.Value(CollectionState) = .init(.running),

    pub fn init(gc: *memory.GC) !VM {
        const frames = try gc.allocator.alloc(CallFrame, INITIAL_FRAME_CAPACITY);
        errdefer gc.allocator.free(frames);
        const registers = try gc.allocator.alloc(Value, INITIAL_REGISTER_CAPACITY);
        errdefer gc.allocator.free(registers);
        const handler_stack = try gc.allocator.alloc(ExceptionHandler, INITIAL_HANDLER_CAPACITY);
        errdefer gc.allocator.free(handler_stack);
        const wind_stack = try gc.allocator.alloc(types.WindRecord, INITIAL_WIND_CAPACITY);
        errdefer gc.allocator.free(wind_stack);
        const globals_map = try gc.allocator.create(std.StringHashMap(Value));
        errdefer gc.allocator.destroy(globals_map);
        globals_map.* = std.StringHashMap(Value).init(gc.allocator);
        const globals_lock = try gc.allocator.create(GlobalsRwLock);
        errdefer gc.allocator.destroy(globals_lock);
        globals_lock.* = .{};
        var vm = VM{
            .gc = gc,
            .frames = frames,
            .registers = registers,
            .handler_stack = handler_stack,
            .wind_stack = wind_stack,
            .globals = globals_map,
            .globals_lock = globals_lock,
            .macros = std.StringHashMap(Value).init(gc.allocator),
            .record_uid_registry = std.StringHashMap(Value).init(gc.allocator),
            .syntax_properties = std.StringHashMap(Value).init(gc.allocator),
            .output = .empty,
            .libraries = library_mod.LibraryRegistry.init(gc.allocator),
            .loading_libs = std.StringHashMap(void).init(gc.allocator),
            .param_overrides = std.AutoHashMap(usize, Value).init(gc.allocator),
        };
        @memset(vm.registers, types.UNDEFINED);
        gc.root_marker = &markVMRoots;
        // Pre-allocate standard ports — root each immediately so GC
        // triggered by the next allocPort cannot collect it (#1013).
        vm.stdin_port = gc.allocPort(0, true, false, "stdin", false) catch types.VOID;
        if (vm.stdin_port != types.VOID) try gc.extra_roots.append(gc.allocator, vm.stdin_port);
        vm.stdout_port = gc.allocPort(1, false, true, "stdout", false) catch types.VOID;
        if (vm.stdout_port != types.VOID) try gc.extra_roots.append(gc.allocator, vm.stdout_port);
        vm.stderr_port = gc.allocPort(2, false, true, "stderr", false) catch types.VOID;
        if (vm.stderr_port != types.VOID) try gc.extra_roots.append(gc.allocator, vm.stderr_port);
        return vm;
    }

    pub fn initForThread(gc: *memory.GC, parent: *VM) !VM {
        const frames = try gc.allocator.alloc(CallFrame, INITIAL_FRAME_CAPACITY);
        errdefer gc.allocator.free(frames);
        const registers = try gc.allocator.alloc(Value, INITIAL_REGISTER_CAPACITY);
        errdefer gc.allocator.free(registers);
        const handler_stack = try gc.allocator.alloc(ExceptionHandler, INITIAL_HANDLER_CAPACITY);
        errdefer gc.allocator.free(handler_stack);
        const wind_stack = try gc.allocator.alloc(types.WindRecord, INITIAL_WIND_CAPACITY);
        errdefer gc.allocator.free(wind_stack);
        var vm = VM{
            .gc = gc,
            .frames = frames,
            .registers = registers,
            .handler_stack = handler_stack,
            .wind_stack = wind_stack,
            // Shared by pointer: the child sees the parent's map through
            // every rehash. Reads on this VM take the shared lock (see the
            // `globals` field doc); a struct copy here would leave the child
            // on a freed bucket array after the first parent-side rehash.
            .globals = parent.globals,
            .globals_lock = parent.globals_lock,
            .macros = parent.macros,
            .record_uid_registry = parent.record_uid_registry,
            .syntax_properties = parent.syntax_properties,
            .output = .empty,
            .libraries = parent.libraries,
            .loading_libs = std.StringHashMap(void).init(gc.allocator),
            .lib_paths = parent.lib_paths,
            .param_overrides = std.AutoHashMap(usize, Value).init(gc.allocator),
            .owns_globals = false,
            // Chain to the root VM (never freed), not the immediate parent:
            // threadEntryFn dereferences this for GC.initForThread's symbol
            // tables and for the shared maps, and a grandchild's parent join
            // frees the middle VM/GC underneath it (#2129).
            .root_vm = parent.root_vm orelse parent,
            // Shared reference, not a copy: SRFI 59/193 want a thread's
            // `program-vicinity`/`script-file` to still answer for the
            // top-level script, not #f. Never freed by the child -- see the
            // field doc.
            .script_path = parent.script_path,
        };
        @memset(vm.registers, types.UNDEFINED);
        gc.root_marker = &markVMRoots;
        // Root each port before allocating the next, exactly like init()
        // (#1013): the child thread's `vm_instance` is not registered yet, so
        // the root marker sees nothing — a collection triggered by the next
        // allocPort would sweep the unrooted earlier port (#1401).
        vm.stdin_port = gc.allocPort(0, true, false, "stdin", false) catch types.VOID;
        if (vm.stdin_port != types.VOID) try gc.extra_roots.append(gc.allocator, vm.stdin_port);
        vm.stdout_port = gc.allocPort(1, false, true, "stdout", false) catch types.VOID;
        if (vm.stdout_port != types.VOID) try gc.extra_roots.append(gc.allocator, vm.stdout_port);
        vm.stderr_port = gc.allocPort(2, false, true, "stderr", false) catch types.VOID;
        if (vm.stderr_port != types.VOID) try gc.extra_roots.append(gc.allocator, vm.stderr_port);
        // Share parent's port parameter objects; override with child's own ports
        // so getParameterValue returns child-heap objects.
        vm.current_input_port_param = parent.current_input_port_param;
        vm.current_output_port_param = parent.current_output_port_param;
        vm.current_error_port_param = parent.current_error_port_param;
        if (vm.current_input_port_param != types.VOID and vm.stdin_port != types.VOID)
            try vm.setParameterValue(types.toParameter(vm.current_input_port_param), vm.stdin_port);
        if (vm.current_output_port_param != types.VOID and vm.stdout_port != types.VOID)
            try vm.setParameterValue(types.toParameter(vm.current_output_port_param), vm.stdout_port);
        if (vm.current_error_port_param != types.VOID and vm.stderr_port != types.VOID)
            try vm.setParameterValue(types.toParameter(vm.current_error_port_param), vm.stderr_port);
        return vm;
    }

    pub fn deinit(self: *VM) void {
        // execute() registers the VM in the threadlocal; without this reset a
        // later VM on the same thread (e.g. the next unit test) would reach a
        // freed globals map through vm_instance during compile-time macro
        // expansion, before its own first execute() re-registers it.
        if (vm_instance == self) {
            vm_instance = null;
            globals_mod.clearGlobalsContext();
        }
        if (self.scheduler) |sched| {
            sched.deinit(self.gc.allocator);
            self.gc.allocator.destroy(sched);
            self.scheduler = null;
        }
        if (self.reactor) |r| {
            r.deinit();
            self.gc.allocator.destroy(r);
            self.reactor = null;
        }
        if (self.owns_globals) {
            self.globals.deinit();
            self.gc.allocator.destroy(self.globals);
            self.gc.allocator.destroy(self.globals_lock);
            self.macros.deinit();
            self.record_uid_registry.deinit();
            var spk = self.syntax_properties.keyIterator();
            while (spk.next()) |k| self.gc.allocator.free(k.*);
            self.syntax_properties.deinit();
            self.libraries.deinit();
            if (self.script_path) |sp| self.gc.allocator.free(sp);
        }
        self.output.deinit(self.gc.allocator);
        self.loading_libs.deinit();
        self.param_overrides.deinit();
        vm_debug.freeWatches(self);
        for (self.breakpoints[0..self.breakpoint_count]) |bp| {
            self.gc.allocator.free(bp.name);
            if (bp.condition) |cond| self.gc.allocator.free(cond);
        }
        self.breakpoint_count = 0;
        const allocator = self.gc.allocator;
        allocator.free(self.frames);
        allocator.free(self.registers);
        allocator.free(self.handler_stack);
        allocator.free(self.wind_stack);
        if (self.heap_owned) allocator.destroy(self);
    }

    pub fn ensureFrameCapacity(self: *VM, needed: usize) VMError!void {
        if (needed <= self.frames.len) return;
        if (needed > MAX_FRAME_LIMIT) return VMError.StackOverflow;
        var new_cap = self.frames.len;
        while (new_cap < needed) new_cap *= 2;
        if (new_cap > MAX_FRAME_LIMIT) new_cap = MAX_FRAME_LIMIT;
        const new_frames = memory.allocSliceNoFill(self.gc.allocator, CallFrame, new_cap) catch return VMError.OutOfMemory;
        @memcpy(new_frames[0..self.frame_count], self.frames[0..self.frame_count]);
        memory.freeSliceNoFill(self.gc.allocator, CallFrame, self.frames);
        self.frames = new_frames;
    }

    pub fn ensureRegisterCapacity(self: *VM, needed: usize) VMError!void {
        if (needed <= self.registers.len) return;
        if (needed > MAX_REGISTER_LIMIT) return VMError.StackOverflow;
        var new_cap = self.registers.len;
        while (new_cap < needed) new_cap *= 2;
        if (new_cap > MAX_REGISTER_LIMIT) new_cap = MAX_REGISTER_LIMIT;
        const new_regs = memory.allocSliceNoFill(self.gc.allocator, Value, new_cap) catch return VMError.OutOfMemory;
        @memcpy(new_regs[0..self.registers.len], self.registers);
        @memset(new_regs[self.registers.len..], types.UNDEFINED);
        memory.freeSliceNoFill(self.gc.allocator, Value, self.registers);
        self.registers = new_regs;
    }

    /// Grow the exception-handler stack, mirroring ensureFrameCapacity.
    /// Past MAX_HANDLER_LIMIT this is StackOverflow, which
    /// `errors.isUncatchable` keeps out of a user's `guard` (#1886) — a limit
    /// of the implementation is not a Scheme condition.
    pub fn ensureHandlerCapacity(self: *VM, needed: usize) VMError!void {
        if (needed <= self.handler_stack.len) return;
        if (needed > MAX_HANDLER_LIMIT) {
            // KP3008's own message is about runaway recursion, which would
            // send a reader looking in the wrong place: say which stack.
            self.setErrorDetail("too many nested exception handlers (limit {d})", .{MAX_HANDLER_LIMIT});
            return VMError.StackOverflow;
        }
        var new_cap = self.handler_stack.len;
        while (new_cap < needed) new_cap *= 2;
        if (new_cap > MAX_HANDLER_LIMIT) new_cap = MAX_HANDLER_LIMIT;
        const new_stack = memory.allocSliceNoFill(self.gc.allocator, ExceptionHandler, new_cap) catch
            return VMError.OutOfMemory;
        @memcpy(new_stack[0..self.handler_count], self.handler_stack[0..self.handler_count]);
        memory.freeSliceNoFill(self.gc.allocator, ExceptionHandler, self.handler_stack);
        self.handler_stack = new_stack;
    }

    /// Grow the dynamic-wind stack. See ensureHandlerCapacity.
    pub fn ensureWindCapacity(self: *VM, needed: usize) VMError!void {
        if (needed <= self.wind_stack.len) return;
        if (needed > MAX_WIND_LIMIT) {
            self.setErrorDetail("too many nested dynamic-wind forms (limit {d})", .{MAX_WIND_LIMIT});
            return VMError.StackOverflow;
        }
        var new_cap = self.wind_stack.len;
        while (new_cap < needed) new_cap *= 2;
        if (new_cap > MAX_WIND_LIMIT) new_cap = MAX_WIND_LIMIT;
        const new_stack = memory.allocSliceNoFill(self.gc.allocator, types.WindRecord, new_cap) catch
            return VMError.OutOfMemory;
        @memcpy(new_stack[0..self.wind_count], self.wind_stack[0..self.wind_count]);
        memory.freeSliceNoFill(self.gc.allocator, types.WindRecord, self.wind_stack);
        self.wind_stack = new_stack;
    }

    pub fn getParameterValue(self: *VM, param: *types.ParameterObject) Value {
        const key = @intFromPtr(param);
        if (self.current_fiber) |fiber| {
            if (fiber.param_overrides.get(key)) |val| return val;
        }
        // Fall through to the VM-level overrides even when a fiber is
        // current: values set before the scheduler existed live here, and
        // the lazily created main fiber starts with an empty override map.
        if (self.param_overrides.get(key)) |val| return val;
        return param.value;
    }

    pub fn setParameterValue(self: *VM, param: *types.ParameterObject, val: Value) VMError!void {
        const key = @intFromPtr(param);
        if (self.current_fiber) |fiber| {
            fiber.param_overrides.put(key, val) catch return VMError.OutOfMemory;
        } else {
            self.param_overrides.put(key, val) catch return VMError.OutOfMemory;
        }
    }

    // -- #1933 (stop-the-world): collection-state protocol --
    //
    // The collecting parent (primitives_srfi18.markLiveChildRoots) sets
    // `collection_stop` on every live child VM and waits for each to leave
    // `.running`; the child parks at its dispatch-loop safepoint
    // (vm_dispatch.zig) or reports a park/FFI state from the blocking sites
    // (fiber_wait.zig, ffi.zig). All transitions below are plain atomics on
    // the child's own thread; the parent only reads the state once the child
    // is quiescent, so there is never a torn write to race.

    /// Park at the safepoint until the collecting parent clears
    /// `collection_stop`, then resume. Runs between instructions, so the VM's
    /// registers/frames are consistent for the parent's mark pass.
    pub fn stopForCollection(self: *VM) void {
        self.collection_state.store(.stopped, .release);
        while (self.collection_stop.load(.acquire)) std.atomic.spinLoopHint();
        self.collection_state.store(.running, .release);
    }

    /// Report a blocked state (reactor poll, cross-thread polling loop): the
    /// VM is quiescent and may be marked. Paired with `setCollectionRunning`.
    pub inline fn setCollectionParked(self: *VM) void {
        self.collection_state.store(.parked, .release);
    }

    /// Resume from a quiescent state (park, FFI call, callback re-entry,
    /// startup handshake). If the collecting parent has armed `collection_stop`
    /// while we were quiescent, this must NOT publish `.running` and resume
    /// bytecode: the parent may already have observed us quiescent and be
    /// about to mark. Mirror the safepoint path instead — publish `.stopped`
    /// and spin until the parent clears the flag — so the parent's mark always
    /// finds us frozen. (The check-then-store race with the parent's arming
    /// is safe: if the parent arms after our check, we resume and the parent
    /// simply waits for our next safepoint, within 1024 instructions.)
    pub inline fn setCollectionRunning(self: *VM) void {
        if (self.collection_stop.load(.acquire)) {
            self.stopForCollection();
            return;
        }
        self.collection_state.store(.running, .release);
    }

    /// Restore a previously saved quiescent state (used by callWithArgs'
    /// FFI-callback guard). The state being restored is never `.running`, so
    /// no resume-vs-mark race is possible; the raw store is fine.
    pub inline fn setCollectionState(self: *VM, s: CollectionState) void {
        self.collection_state.store(s, .release);
    }

    /// Enter an FFI call: the VM is quiescent unless a callback re-enters
    /// Scheme (which callWithArgs flips back to `.running` for its extent).
    pub inline fn setCollectionInNative(self: *VM) void {
        self.collection_state.store(.in_native, .release);
    }

    pub fn setErrorDetail(self: *VM, comptime fmt: []const u8, args: anytype) void {
        const s = std.fmt.bufPrint(&self.last_error_detail, fmt, args) catch |err| switch (err) {
            error.NoSpaceLeft => {
                self.last_error_detail_len = self.last_error_detail.len;
                return;
            },
        };
        self.last_error_detail_len = s.len;
        self.captureErrorLocation();
    }

    pub fn findSimilarName(self: *VM, name: []const u8) ?[]const u8 {
        var best: ?[]const u8 = null;
        var best_dist: usize = 4;
        // Locks internally — callers (dispatch error paths) must not hold
        // the globals lock when calling this.
        self.lockGlobalsShared();
        defer self.unlockGlobalsShared();
        var iter = self.globals.keyIterator();
        while (iter.next()) |key| {
            const candidate = key.*;
            if (candidate.len == 0 or candidate[0] == '%') continue;
            const dist = editDistance(name, candidate);
            if (dist > 0 and dist < best_dist) {
                best_dist = dist;
                best = candidate;
            }
        }
        return best;
    }

    fn editDistance(a: []const u8, b: []const u8) usize {
        if (a.len > 32 or b.len > 32) return 99;
        var prev: [33]usize = undefined;
        var curr: [33]usize = undefined;
        for (0..b.len + 1) |j| prev[j] = j;
        for (a, 0..) |ca, i| {
            curr[0] = i + 1;
            for (b, 0..) |cb, j| {
                const cost: usize = if (ca == cb) 0 else 1;
                curr[j + 1] = @min(@min(curr[j] + 1, prev[j + 1] + 1), prev[j] + cost);
            }
            @memcpy(prev[0 .. b.len + 1], curr[0 .. b.len + 1]);
        }
        return prev[b.len];
    }

    fn captureErrorLocation(self: *VM) void {
        self.last_error_line = 0;
        self.last_error_col = 0;
        self.last_error_source = null;
        if (self.frame_count == 0) return;
        var i = self.frame_count;
        while (i > 0) {
            i -= 1;
            if (self.frames[i].closure) |cls| {
                const func = cls.func;
                if (func.line_table.items.len > 0) {
                    const ip = if (self.frames[i].ip > 0) self.frames[i].ip - 1 else 0;
                    const loc = func.locForOffset(ip);
                    if (loc.line > 0) {
                        self.last_error_line = loc.line;
                        self.last_error_col = loc.col;
                        self.last_error_source = func.source_name;
                        return;
                    }
                }
                if (func.source_line > 0) {
                    self.last_error_line = func.source_line;
                    self.last_error_col = 0;
                    self.last_error_source = func.source_name;
                    return;
                }
            }
        }
    }

    pub fn getErrorDetail(self: *VM) []const u8 {
        return self.last_error_detail[0..self.last_error_detail_len];
    }

    /// Writes `eo`'s own `message` + `irritants` (display mode for the
    /// message, write mode for each irritant, matching R7RS `error`'s
    /// display convention) to `w`. Shared by `noteUncaughtException`'s
    /// top-level object and its `uncaught_reason` unwrap loop below.
    fn writeErrorObjectMessage(w: *std.Io.Writer, allocator: std.mem.Allocator, eo: *types.ErrorObject) void {
        const printer = @import("printer.zig");
        if (printer.valueToString(allocator, eo.message, .display)) |msg| {
            defer allocator.free(msg);
            w.writeAll(msg) catch {};
        } else |_| {}
        var it = eo.irritants;
        while (types.isPair(it)) {
            const pair = types.toObject(it).as(types.Pair);
            if (printer.valueToString(allocator, pair.car, .write)) |s| {
                defer allocator.free(s);
                w.writeAll(" ") catch {};
                w.writeAll(s) catch {};
            } else |_| {}
            it = pair.cdr;
        }
    }

    /// Called from execute()'s error path, before resetExecutionState()
    /// discards the pending exception. If the escaping error is an uncaught
    /// Scheme exception and no native error detail was recorded, format the
    /// exception payload (message + irritants for error objects) into the
    /// detail buffer so top-level error printers show the message instead of
    /// the raw Zig error name. Consumes the pending exception.
    pub fn noteUncaughtException(self: *VM, err: anyerror) void {
        if (err != error.ExceptionRaised) return;
        const exc = self.current_exception orelse return;
        self.current_exception = null;
        // Carry the raised object's stable diagnostic code to the reporting
        // layer (KEP-0005), whether or not a native detail was already recorded.
        // `.uncategorized` here means "uncoded raise" and the reporter falls
        // back to the generic KP3000 uncaught-exception code.
        if (types.isErrorObject(exc)) {
            self.last_error_code = types.toObject(exc).as(types.ErrorObject).code;
        }
        if (self.last_error_detail_len != 0) return;

        const printer = @import("printer.zig");
        const allocator = self.gc.allocator;
        var w: std.Io.Writer = .fixed(&self.last_error_detail);
        if (types.isErrorObject(exc)) {
            var eo = types.toObject(exc).as(types.ErrorObject);
            writeErrorObjectMessage(&w, allocator, eo);
            // kaappi#1742: thread-join! wraps a child thread's failure in a
            // generic "uncaught exception in thread" ErrorObject and
            // stashes the real cause in uncaught_reason (see
            // primitives_srfi18.zig's threadJoinResult) -- a field the
            // message+irritants walk above never reaches, so the default
            // report used to stop at that uninformative wrapper text and
            // hide the one sentence that actually explains the failure,
            // otherwise reachable only via `(error-object-message
            // (uncaught-exception-reason e))` inside a guard. Unwrap it
            // here instead. Bounded: a chain of nested thread-join!s can
            // wrap this arbitrarily deep. Gated on this exact error_type --
            // the only production site that ever sets it is
            // threadJoinResult, so this never fires for the io_decoding/
            // io_encoding error types that reuse the same uncaught_reason
            // field slot for unrelated data (see types.ErrorObject's doc
            // comment).
            var depth: u8 = 0;
            while (eo.error_type == .uncaught_exception and eo.uncaught_reason != types.VOID and depth < 8) : (depth += 1) {
                w.writeAll(": ") catch {};
                if (types.isErrorObject(eo.uncaught_reason)) {
                    eo = types.toObject(eo.uncaught_reason).as(types.ErrorObject);
                    writeErrorObjectMessage(&w, allocator, eo);
                } else {
                    if (printer.valueToString(allocator, eo.uncaught_reason, .write)) |s| {
                        defer allocator.free(s);
                        w.writeAll(s) catch {};
                    } else |_| {}
                    break;
                }
            }
        } else {
            w.writeAll("uncaught exception: ") catch {};
            if (printer.valueToString(allocator, exc, .write)) |s| {
                defer allocator.free(s);
                w.writeAll(s) catch {};
            } else |_| {}
        }
        self.last_error_detail_len = w.buffered().len;
    }

    pub const StackFrame = struct {
        name: ?[]const u8,
        source: ?[]const u8,
        line: u32,
    };

    pub fn getStackTrace(self: *VM, buf: []StackFrame) usize {
        var count: usize = 0;
        if (self.frame_count == 0) return 0;
        var i = self.frame_count;
        while (i > 0 and count < buf.len) {
            i -= 1;
            if (self.frames[i].closure) |cls| {
                const func = cls.func;
                // Use instruction-level line number when available
                var line = func.source_line;
                if (func.line_table.items.len > 0) {
                    const ip = if (self.frames[i].ip > 0) self.frames[i].ip - 1 else 0;
                    const precise = func.lineForOffset(ip);
                    if (precise > 0) line = precise;
                }
                if (line > 0 or func.name != null) {
                    if (count > 0) {
                        const prev = buf[count - 1];
                        if (prev.line == line and
                            std.mem.eql(u8, prev.source orelse "", func.source_name orelse ""))
                            continue;
                    }
                    buf[count] = .{
                        .name = func.name,
                        .source = func.source_name,
                        .line = line,
                    };
                    count += 1;
                }
            }
        }
        return count;
    }

    pub fn getLastStackTrace(self: *VM) []const StackFrame {
        return self.last_stack_trace[0..self.last_stack_trace_len];
    }

    // -- Shared-globals locking (see the `globals` field doc) --

    /// Take the globals read lock if this VM shares another VM's globals
    /// (SRFI-18 child thread). The owner reads lock-free. Never nest: a
    /// second lockShared while a writer is queued can deadlock.
    pub inline fn lockGlobalsShared(self: *VM) void {
        if (!self.owns_globals) self.globals_lock.lockShared();
    }

    pub inline fn unlockGlobalsShared(self: *VM) void {
        if (!self.owns_globals) self.globals_lock.unlockShared();
    }

    /// Insert/overwrite a globals binding under the exclusive lock, so a
    /// concurrent child-thread reader never observes a rehash in progress.
    /// Does not bump global_version — use defineGlobal for definition
    /// semantics.
    pub fn globalsPut(self: *VM, name: []const u8, value: Value) !void {
        self.globals_lock.lock();
        defer self.globals_lock.unlock();
        try self.globals.put(name, value);
    }

    pub fn defineGlobal(self: *VM, name: []const u8, value: Value) !void {
        try self.globalsPut(name, value);
        self.global_version +%= 1;
    }

    // -- Exception handling --

    /// Allocate a fresh frame birth id (see CallFrame.seq).
    pub fn nextFrameSeq(self: *VM) u64 {
        self.frame_seq +%= 1;
        return self.frame_seq;
    }

    pub fn pushHandler(self: *VM, handler: Value) VMError!void {
        try self.ensureHandlerCapacity(self.handler_count + 1);
        self.handler_stack[self.handler_count] = .{
            .handler = handler,
            .frame_count = self.frame_count,
        };
        self.handler_count += 1;
    }

    /// SRFI 248: push a sticky (unwind) handler that raise/raise-continuable
    /// invoke without popping. See `types.ExceptionHandler.sticky`.
    pub fn pushHandlerSticky(self: *VM, handler: Value) VMError!void {
        try self.ensureHandlerCapacity(self.handler_count + 1);
        self.handler_stack[self.handler_count] = .{
            .handler = handler,
            .frame_count = self.frame_count,
            .sticky = true,
        };
        self.handler_count += 1;
    }

    pub fn popHandler(self: *VM) void {
        if (self.handler_count > 0) self.handler_count -= 1;
    }

    const vm_calls = @import("vm_calls.zig");
    const vm_debug = @import("vm_debug.zig");

    pub fn callHandler(self: *VM, handler_val: Value, arg: Value, return_dst: u8) VMError!Value {
        return vm_calls.callHandler(self, handler_val, arg, return_dst);
    }

    pub fn callThunk(self: *VM, thunk_val: Value) VMError!Value {
        return vm_calls.callThunk(self, thunk_val);
    }

    pub fn callWithArgs(self: *VM, proc: Value, args: []const Value) VMError!Value {
        return vm_calls.callWithArgs(self, proc, args);
    }

    pub fn captureContinuation(self: *VM, dst_reg: u8, dst_base: u32) VMError!Value {
        return vm_continuations.captureContinuation(self, dst_reg, dst_base);
    }

    pub fn captureEscape(self: *VM, dst_reg: u8, dst_base: u32) VMError!Value {
        return vm_continuations.captureEscape(self, dst_reg, dst_base);
    }

    pub fn invokeEscape(self: *VM, cont: *types.Continuation, value: Value) VMError!void {
        return vm_continuations.invokeEscape(self, cont, value);
    }

    pub fn performWindTransition(self: *VM, target_winds: []const types.WindRecord, target_count: usize) VMError!void {
        return vm_continuations.performWindTransition(self, target_winds, target_count);
    }

    /// Clear register slots in `[0, max_reg)` that no live frame window covers,
    /// setting each to UNDEFINED. Such gap slots are dead (no frame reads them),
    /// but one vacated by a returned call frame typically still holds that
    /// frame's last pointer. The GC root marker walks only per-frame windows, so
    /// those pointers keep nothing alive and a later collection frees their
    /// targets — which is why any copy of the contiguous `[0, max_reg)` range
    /// must not preserve them verbatim (#1464). Both call/cc continuation
    /// capture (`captureContinuation`) and fiber suspension
    /// (`FiberScheduler.saveCurrentFiber`, #1529) snapshot that contiguous range
    /// and later trace it, so both scrub the gaps through here first. Clearing is
    /// behavior-preserving: no frame ever reads a gap slot (a continuation/fiber
    /// restore copies them back but they stay dead).
    ///
    /// Frame bases are non-decreasing (every call places its callee's frame past
    /// the caller's own base, and continuation restore preserves that order), so
    /// a single ordered sweep that tracks the highest covered register finds the
    /// gaps with no scratch buffer — keeping call/cc capture allocation-free on
    /// the hot path (a bitmap here regressed the call_cc benchmark ~1.9x).
    pub fn clearGapRegisters(self: *VM, max_reg: usize) void {
        var covered_end: usize = 0;
        var prev_base: usize = 0;
        for (self.frames[0..self.frame_count]) |f| {
            const base: usize = f.base;
            std.debug.assert(base >= prev_base); // relied on for gap correctness
            prev_base = base;
            if (base > covered_end) {
                const gap_end = @min(base, max_reg);
                @memset(self.registers[covered_end..gap_end], types.UNDEFINED);
                if (gap_end == max_reg) return;
            }
            const win_end = base + f.frameWindow();
            if (win_end > covered_end) covered_end = win_end;
        }
        if (covered_end < max_reg)
            @memset(self.registers[covered_end..max_reg], types.UNDEFINED);
    }

    const vm_dispatch = @import("vm_dispatch.zig");

    pub fn runUntil(self: *VM, target_frame_count: usize, target_wind_count: usize) VMError!Value {
        return vm_dispatch.runUntil(self, target_frame_count, target_wind_count);
    }

    pub fn resetExecutionState(self: *VM) void {
        self.frame_count = 0;
        self.handler_count = 0;
        self.wind_count = 0;
        self.current_exception = null;
        self.last_callback_error = false;
        self.callback_error_value = null;
        self.continuation_invoked = false;
        self.continuation_value = types.VOID;
        self.yield_retry = false;
        self.sched_dispatch_pending = false;
        self.dispatched_from_scheduler = false;
    }

    pub fn execute(self: *VM, func: *types.Function) VMError!Value {
        return vm_calls.execute(self, func);
    }

    pub fn run(self: *VM) VMError!Value {
        return vm_calls.run(self);
    }

    /// Bounded-step execution (kaappi#2283). Begin running a compiled top-level
    /// form, stopping at the safepoint once `instruction_counter` reaches
    /// `deadline` and returning `.paused` with all VM state left intact for a
    /// later `resumeStep`; `.done` (result in `out`) means the form completed.
    pub fn beginStep(self: *VM, func: *types.Function, deadline: u64, out: *Value) VMError!vm_calls.StepStatus {
        return vm_calls.beginStep(self, func, deadline, out);
    }

    /// Resume the form a prior `beginStep`/`resumeStep` left paused, under a new
    /// `deadline`. Same return contract as `beginStep`.
    pub fn resumeStep(self: *VM, deadline: u64, out: *Value) VMError!vm_calls.StepStatus {
        return vm_calls.resumeStep(self, deadline, out);
    }

    pub fn restoreContinuation(self: *VM, cont: *types.Continuation, value: Value) VMError!void {
        try vm_continuations.restoreContinuation(self, cont, value);
    }

    pub fn registerIndex(self: *VM, base: u16, reg: u8) VMError!usize {
        return vm_dispatch.registerIndex(self, base, reg);
    }

    const vm_eval = @import("vm_eval.zig");

    pub fn eval(self: *VM, source: []const u8) VMError!Value {
        return vm_eval.eval(self, source);
    }

    pub fn handleTopLevelForm(self: *VM, expr: Value) ?VMError!Value {
        return vm_eval.handleTopLevelForm(self, expr);
    }

    pub fn topLevelHead(self: *VM, expr: Value) ?vm_eval.TopLevelHead {
        return vm_eval.topLevelHead(self, expr);
    }

    pub fn runTopLevelHead(self: *VM, head: vm_eval.TopLevelHead, expr: Value) VMError!Value {
        return vm_eval.runTopLevelHead(self, head, expr);
    }

    pub fn topLevelSpliceBody(self: *VM, expr: Value) ?VMError!Value {
        return vm_eval.topLevelSpliceBody(self, expr);
    }

    pub fn compileCachedForm(self: *VM, source: []const u8) VMError!Value {
        return vm_eval.compileCachedForm(self, source);
    }

    pub fn runCachedForm(self: *VM, func_val: Value) VMError!Value {
        return vm_eval.runCachedForm(self, func_val);
    }

    /// Run a compiled top-level Function, re-entrant-safely: at true top
    /// level (frame_count == 0) this is `execute`; while an outer execution
    /// is suspended (a file-backed library load, define-record-type
    /// expansion, eval re-entry, ...) it pushes a frame above the live ones
    /// instead of resetExecutionState-ing them away (#2012). `func` must
    /// already be GC-rooted by the caller.
    pub fn runTopLevelFunction(self: *VM, func: *types.Function) VMError!Value {
        return vm_eval.runTopLevelFunction(self, func);
    }
};

test {
    _ = @import("vm_tests.zig");
    _ = vm_library;
    _ = vm_records;
    _ = vm_continuations;
    _ = @import("vm_step.zig");
}
