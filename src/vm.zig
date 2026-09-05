const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const platform = @import("platform.zig");

const diagnostics = @import("diagnostics.zig");
const library_mod = @import("library.zig");
const reactor_mod = @import("reactor.zig");
pub const globals_mod = @import("globals.zig");
const Value = types.Value;
const OpCode = types.OpCode;

pub const vm_library = @import("vm_library.zig");
pub const vm_records = @import("vm_records.zig");
pub const vm_continuations = @import("vm_continuations.zig");
pub const vm_bootstrap = @import("vm_bootstrap.zig");
pub const vm_library_cache = @import("vm_library_cache.zig");
const bytecode_file = @import("bytecode_file.zig");
const vm_shims = @import("vm_shims.zig");
const vm_roots = @import("vm_roots.zig");
const vm_errors = @import("vm_errors.zig");
const vm_debug = @import("vm_debug.zig");

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

/// The compiler/expander bridge lives in vm_shims.zig; re-exported so the
/// ~20 `vm_mod.setVMInstance(vm)` call sites keep working.
pub const setVMInstance = vm_shims.setVMInstance;

pub const GlobalsRwLock = globals_mod.GlobalsRwLock;
pub const acquireGlobalsWrite = globals_mod.acquireGlobalsWrite;
pub const releaseGlobalsWrite = globals_mod.releaseGlobalsWrite;
pub const acquireGlobalsRead = globals_mod.acquireGlobalsRead;
pub const releaseGlobalsRead = globals_mod.releaseGlobalsRead;

/// GC root marking lives in vm_roots.zig (markVMRoots is wired there
/// directly as the GC's root_marker); markVmRoots is re-exported for
/// primitives_srfi18's markLiveChildRoots.
pub const markVmRoots = vm_roots.markVmRoots;

pub const ExceptionHandler = types.ExceptionHandler;

pub const writeStderr = @import("reporting.zig").writeStderr;

pub const CallFrame = types.CallFrame;

pub const StepMode = vm_debug.StepMode;
pub const Breakpoint = vm_debug.Breakpoint;
pub const WatchEntry = vm_debug.WatchEntry;
pub const ProfileTimeEntry = vm_debug.ProfileTimeEntry;

/// #2510 rollback journal entry; lives next to the library machinery that
/// appends/resolves the records (vm_library.zig).
pub const LibRollbackEntry = vm_library.LibRollbackEntry;

/// #1933 (stop-the-world): a child VM's reported execution state; see
/// vm_roots.zig, where the marking side that consumes it lives.
pub const CollectionState = vm_roots.CollectionState;

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
    /// The map's generation counter (`GlobalsRwLock.version`, read via
    /// `globalVersion`) rides on the same shared lock object, so every
    /// thread's per-function global caches are invalidated by every
    /// thread's rebindings (kaappi#2483).
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
    /// `.sld` cache state (kaappi#1888): one frame per file-backed library
    /// load in flight. The innermost frame is written by compileLibExpr /
    /// evalIncludedForm / openIncludeFile / evalLibFeatureReq to record what a
    /// cold load did (compiled functions, transformer registrations, include
    /// hashes, dependency identities), or — when `warm` is set — replayed from
    /// instead of compiling. See vm_library_cache.zig.
    lib_cache_stack: [8]vm_library_cache.LibCollector = @splat(.{}),
    lib_cache_depth: u8 = 0,
    /// #2510: rollback bookkeeping for failed library loads.
    /// `loadLibrarySource` dispatches each top-level datum as it is read, so
    /// a well-formed `define-library` is REGISTERED before the reader reaches
    /// a later read error (trailing garbage, malformed datum) in the same
    /// .sld — and the second import's registry short-circuit then served
    /// that half-loaded library as a success. `lib_rollback_frames` holds
    /// one mark per in-flight `tryLoadLibraryFromFile` invocation (the
    /// length of `lib_rollback_regs` when it started) — the whole load, not
    /// just `loadLibrarySource`, so a failure AFTER a successful load (the
    /// warm replay's `endWarmLoad` desync) also rolls back (#2518 review);
    /// `handleDefineLibrary` appends one record per library it registers
    /// while any frame exists. A failed load unwinds every record above its
    /// mark — restoring a displaced prior where the registration replaced
    /// one, unregistering where it created the entry (#2518 review); a
    /// successful one commits the registrations and merely forgets the
    /// records — nested loads pushed their own, deeper marks and resolved
    /// their own fate before returning, so their committed registrations are
    /// never above a still-live outer mark. The name strings are owned
    /// (duped) so the list never borrows from a Library it is about to
    /// remove; a `prior` is a Library detached from the registry map, kept
    /// GC-reachable by markVMRoots until its frame resolves. Per-VM, like
    /// the collector stack (the shared `libraries` map is what gets rolled
    /// back).
    lib_rollback_regs: std.ArrayList(LibRollbackEntry) = .empty,
    lib_rollback_frames: std.ArrayList(usize) = .empty,
    /// Per-run include/dependency records for the MAIN file's cache entry
    /// (kaappi#1888 review): a program's compiled slots embed imported-macro
    /// expansions, so its entry stales on the same edits a library's does.
    /// Owned by vm_library_cache's run recorder; cleared/freed there.
    run_cache_deps: std.ArrayList(bytecode_file.DepRecord) = .empty,
    run_cache_includes: std.ArrayList(bytecode_file.IncludeRecord) = .empty,
    /// False once any dependency of the run proved unrecordable (a library
    /// that declined caching or could not write its entry): a program entry
    /// would serve stale compiled slots forever, so runFile declines.
    run_cache_ok: bool = true,
    /// > 0 while the loader walks *structural* forms (a .sld's top-level
    /// datums, a library begin/include body) as opposed to forms a running
    /// program eval'd mid-flight. Only structure-walk include forms become
    /// cache events — a runtime `(eval "(include …)")` inside a library body
    /// is body execution, not structure, and replaying it from the event log
    /// would desync (kaappi#1888).
    lib_structure_depth: u8 = 0,
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
    profile_mode: bool = false,
    coverage_mode: bool = false,
    coverage_xml_path: ?[]const u8 = null,
    profile_last_ns: u64 = 0,
    profile_time_stack: [256]ProfileTimeEntry = undefined,
    profile_time_depth: usize = 0,
    sandbox_mode: bool = false,
    /// Set by the `kaappi test` worker path: when true, `(exit code)` and
    /// `(emergency-exit code)` record the request and return instead of
    /// terminating the process, so the worker always reaches its
    /// result-emission step even when a test file's SRFI-64 epilogue calls
    /// `(exit 1)` on failure. Inherited by every SRFI-18 child VM
    /// (`initForThread`), because a child's `(exit)` is the same
    /// `std.process.exit` and killed the worker just the same (kaappi#2525).
    /// `exit_requested`/`exit_code` capture the last such request — always
    /// on the ROOT VM, whichever thread made it, since the root is the only
    /// VM the worker's `emitResult` reads; a child records through
    /// `root_vm`, with atomic stores because the root may be emitting while
    /// an unjoined child is still running. No effect on normal runs.
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
    /// Lazily built by `channel-comparator` (kaappi#2394): the
    /// `(make-comparator channel? channel=? #f channel-hash)` record. A
    /// per-VM constant -- cached like default_random_source so repeat calls
    /// don't re-enter (srfi 128)'s make-comparator. Each VM builds its own
    /// (a child's lives on the child heap; VM.initForThread does not copy
    /// this field), and markVmRoots marks it unconditionally -- markValue
    /// skips foreign-heap values, same as thread_handle.
    default_channel_comparator: Value = types.VOID,
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
        ignoreSigpipe();
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
        gc.root_marker = &vm_roots.markVMRoots;
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

    /// KEP-0022 Phase 1: SIGPIPE must be ignored process-wide, explicitly.
    /// The canonical subprocess failure -- writing to the stdin of a child
    /// that has already exited -- must surface as an ordinary catchable I/O
    /// error carrying EPIPE, never as process death by signal. Kaappi's own
    /// binary already gets this from Zig's std.start (keep_sigpipe == false
    /// defaults to SIG_IGN), but an embedder linking the runtime as a
    /// library gets no std.start: their first write to a dead child's pipe
    /// would kill the host. Idempotent, cheap, and safe to call per VM (the
    /// signal disposition is process-wide; child-thread VMs re-run it
    /// harmlessly). Not applicable on Windows (no SIGPIPE) or WASI (no
    /// signals).
    fn ignoreSigpipe() void {
        const builtin = @import("builtin");
        if (comptime builtin.os.tag == .windows or builtin.os.tag == .wasi) return;
        // Only upgrade the DEFAULT disposition (die by signal) to SIG_IGN.
        // An embedder that deliberately installed its own SIGPIPE handler
        // keeps it — their handler runs and the write still returns EPIPE,
        // which is all the KEP-0022 contract needs (kaappi#2442 review).
        var old: std.posix.Sigaction = undefined;
        std.posix.sigaction(std.posix.SIG.PIPE, null, &old);
        if (old.handler.handler != std.posix.SIG.DFL) return;
        var act: std.posix.Sigaction = .{
            .handler = .{ .handler = std.posix.SIG.IGN },
            .mask = std.posix.sigemptyset(),
            .flags = 0,
        };
        std.posix.sigaction(std.posix.SIG.PIPE, &act, null);
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
            // A `kaappi test` worker's suppression must reach every thread:
            // a child's `(exit …)` is the same std.process.exit and used to
            // kill the worker before it emitted (kaappi#2525). The request
            // itself is recorded on the root (see `suppress_exit`).
            .suppress_exit = parent.suppress_exit,
            // Shared reference, not a copy: SRFI 59/193 want a thread's
            // `program-vicinity`/`script-file` to still answer for the
            // top-level script, not #f. Never freed by the child -- see the
            // field doc.
            .script_path = parent.script_path,
        };
        @memset(vm.registers, types.UNDEFINED);
        gc.root_marker = &vm_roots.markVMRoots;
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
        // Any rollback records still present mean a load errored out
        // mid-flight (endLibSourceLoad frees them on its own paths); free
        // any stragglers so a failed load doesn't leak (#2510). The
        // registry — and its retired_envs — is already torn down by now, so
        // a detached prior is freed directly: the whole heap is being
        // dismantled, nothing can still hold its env.
        for (self.lib_rollback_regs.items) |*rec| {
            self.gc.allocator.free(rec.name);
            if (rec.prior) |*prior| prior.deinit();
        }
        self.lib_rollback_regs.deinit(self.gc.allocator);
        self.lib_rollback_frames.deinit(self.gc.allocator);
        self.param_overrides.deinit();
        // Any collectors still on the stack mean a load errored out mid-flight
        // (endColdLoad/endWarmLoad always pop on their own paths); free their
        // recordings so a failed load doesn't leak.
        vm_library_cache.deinitStack(self);
        vm_library_cache.deinitRunRecords(self);
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
            // #1961: belt-and-braces, matching the other fiber-field
            // barriers. The authoritative mechanism for a resident fiber's
            // override map is FiberScheduler.markRoots' unconditional
            // markFiberState pass (see gc_collect.zig's .fiber arm of
            // referencesYoung, which states this invariant); this barrier
            // keeps the remembered set complete for the non-resident window
            // — a retired fiber whose slot was reused — the same way
            // saveCurrentFiber's enrollment does for the bulk snapshot.
            self.gc.writeBarrier(&fiber.header, val);
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
        // Spin, then yield, then sleep -- never a pure spin: the parent's
        // mark phase runs for milliseconds, and every stopped child that
        // keeps spinning competes with the collector for the CPU it needs
        // to finish (kaappi#2446; see platform.spinBackoff).
        var spins: u32 = 0;
        while (self.collection_stop.load(.acquire)) : (spins +|= 1) platform.spinBackoff(spins);
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

    // -- Error reporting and stack traces (implementations in vm_errors.zig) --

    pub fn setErrorDetail(self: *VM, comptime fmt: []const u8, args: anytype) void {
        vm_errors.setErrorDetail(self, fmt, args);
    }

    pub fn findSimilarName(self: *VM, name: []const u8) ?[]const u8 {
        return vm_errors.findSimilarName(self, name);
    }

    pub fn getErrorDetail(self: *VM) []const u8 {
        return vm_errors.getErrorDetail(self);
    }

    /// #1962 untraced-env-map invariant check; implementation in
    /// vm_roots.zig next to the marking side it reasons about.
    pub fn isGcRootedEnvMap(self: *VM, map: *std.StringHashMap(Value)) bool {
        return vm_roots.isGcRootedEnvMap(self, map);
    }

    /// Called from execute()'s error path, before resetExecutionState()
    /// discards the pending exception (see vm_errors.noteUncaughtException).
    pub fn noteUncaughtException(self: *VM, err: anyerror) void {
        vm_errors.noteUncaughtException(self, err);
    }

    pub const StackFrame = vm_errors.StackFrame;

    pub fn getStackTrace(self: *VM, buf: []StackFrame) usize {
        return vm_errors.getStackTrace(self, buf);
    }

    pub fn getLastStackTrace(self: *VM) []const StackFrame {
        return vm_errors.getLastStackTrace(self);
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
    /// Does not bump the global version — use defineGlobal for definition
    /// semantics.
    pub fn globalsPut(self: *VM, name: []const u8, value: Value) !void {
        self.globals_lock.lock();
        defer self.globals_lock.unlock();
        try self.globals.put(name, value);
    }

    pub fn defineGlobal(self: *VM, name: []const u8, value: Value) !void {
        self.globals_lock.lock();
        defer self.globals_lock.unlock();
        try self.globals.put(name, value);
        _ = self.bumpGlobalVersion();
    }

    /// The generation of the shared globals map (`GlobalsRwLock.version`,
    /// kaappi#2483) — one counter for the root and every child VM chained to
    /// its map. A per-function global cache is valid only while its
    /// `cache_version` equals this. Callers that go on to read the map and
    /// fill a cache must snapshot this ONCE, before the read, and stamp the
    /// snapshot: stamping a fresh load taken after the read would re-bless
    /// a value another thread has rebound in between.
    pub inline fn globalVersion(self: *const VM) u32 {
        return self.globals_lock.version.load(.acquire);
    }

    /// Advance the shared generation after a rebinding, returning the new
    /// value. A writer that then re-validates its own cache slot must stamp
    /// exactly this value (not a fresh `globalVersion`): a concurrent
    /// rebinding by another thread may already have moved the counter past
    /// it, and stamping the later value would bless the writer's slot
    /// against a map it no longer matches. Call it inside the same locked
    /// region as the store, so the store and its bump are ordered together.
    pub inline fn bumpGlobalVersion(self: *VM) u32 {
        return self.globals_lock.version.fetchAdd(1, .acq_rel) +% 1;
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

    pub fn callHandler(self: *VM, handler_val: Value, arg: Value, return_dst: u8) VMError!Value {
        return vm_calls.callHandler(self, handler_val, arg, return_dst);
    }

    pub fn callThunk(self: *VM, thunk_val: Value) VMError!Value {
        return vm_calls.callThunk(self, thunk_val);
    }

    /// callThunk variant for thunks owned by a native caller: the closure
    /// frame carries returns_to_native, so a late continuation resume past the
    /// returned native raises KP3000 instead of mis-delivering (kaappi#2453).
    pub fn callThunkReturningToNative(self: *VM, thunk_val: Value) VMError!Value {
        return vm_calls.callThunkReturningToNative(self, thunk_val);
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
