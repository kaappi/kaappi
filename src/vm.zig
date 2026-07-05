const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");
const library_mod = @import("library.zig");
pub const globals_mod = @import("globals.zig");
const Value = types.Value;
const OpCode = types.OpCode;

pub const vm_library = @import("vm_library.zig");
pub const vm_records = @import("vm_records.zig");
pub const vm_continuations = @import("vm_continuations.zig");

pub const VMError = @import("errors.zig").KaappiError;

pub const INITIAL_FRAME_CAPACITY = types.INITIAL_FRAME_CAPACITY;
pub const INITIAL_REGISTER_CAPACITY = types.INITIAL_REGISTER_CAPACITY;
pub const MAX_FRAME_LIMIT = types.MAX_FRAME_LIMIT;
pub const MAX_REGISTER_LIMIT = types.MAX_REGISTER_LIMIT;
pub const MAX_HANDLERS = types.MAX_HANDLERS;
pub const MAX_WINDS = types.MAX_WINDS;

pub threadlocal var vm_instance: ?*VM = null;

pub fn setVMInstance(vm: *VM) void {
    vm_instance = vm;
    globals_mod.setGlobalsContext(.{
        .globals = vm.globals,
        .globals_lock = vm.globals_lock,
        .owns_globals = vm.owns_globals,
    });
    globals_mod.library_exists_checker = &checkLibraryExists;
}

fn checkLibraryExists(lib_name: []const u8, lib_name_list: Value) bool {
    const vm = vm_instance orelse return false;
    if (vm.libraries.get(lib_name) != null) return true;
    return vm_library.libraryFileExists(vm, lib_name_list);
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

    for (vm.frames[0..vm.frame_count]) |f| {
        if (f.closure) |cls| gc.markValue(types.makePointer(@ptrCast(cls)));
        if (f.native) |nf| gc.markValue(types.makePointer(@ptrCast(nf)));
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
    gc.markValue(vm.continuation_value);
    gc.markValue(vm.default_random_source);

    // Only mark globals/macros when this VM owns them. Child threads
    // share the parent's maps — the parent GC keeps those values alive.
    // Marking them here would write mark bits on parent-heap objects
    // without synchronization (data race).
    if (vm.owns_globals) {
        var git = vm.globals.valueIterator();
        while (git.next()) |v| gc.markValue(v.*);
        var mit = vm.macros.valueIterator();
        while (mit.next()) |v| gc.markValue(v.*);
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
}

pub const ExceptionHandler = types.ExceptionHandler;

fn writeToFd(fd: std.posix.fd_t, bytes: []const u8) void {
    var total: usize = 0;
    while (total < bytes.len) {
        const result = std.posix.system.write(fd, bytes.ptr + total, bytes.len - total);
        if (result < 0) {
            if (std.posix.errno(result) == .INTR) continue;
            break;
        }
        if (result == 0) break;
        total += @as(usize, @intCast(result));
    }
}

pub fn writeStderr(bytes: []const u8) void {
    writeToFd(2, bytes);
}

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
    output: std.ArrayList(u8),
    libraries: library_mod.LibraryRegistry,
    handler_stack: [MAX_HANDLERS]ExceptionHandler = undefined,
    handler_count: usize = 0,
    current_exception: ?Value = null,
    wind_stack: [MAX_WINDS]types.WindRecord = undefined,
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
    last_error_detail: [256]u8 = [_]u8{0} ** 256,
    last_error_detail_len: usize = 0,
    last_error_line: u32 = 0,
    last_error_source: ?[]const u8 = null,
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
    timeout_deadline_ns: ?u64 = null,
    instruction_counter: u64 = 0,
    owns_globals: bool = true,
    /// Virtual filesystem for standalone binary: maps file paths → source content.
    /// Populated from .sbc bundled files section; checked before disk reads.
    bundled_files: ?*std.StringHashMap([]const u8) = null,
    /// When non-null, record files read during library loading for bundling.
    compile_collect_files: ?*std.StringHashMap([]const u8) = null,
    param_overrides: std.AutoHashMap(usize, Value) = undefined,
    default_random_source: Value = types.VOID,
    scheduler: ?*@import("fiber.zig").FiberScheduler = null,
    current_fiber: ?*@import("fiber.zig").Fiber = null,
    yielded: bool = false,
    /// Set by a blocking primitive (channel-receive, fiber-join) together with
    /// error.Yielded: the dispatch loop must rewind ip to the start of the
    /// calling instruction so the primitive re-executes when the fiber is
    /// rescheduled, instead of resuming with an unwritten result register.
    yield_retry: bool = false,
    /// Set by a scheduler loop immediately before its runUntil(0, 0) call;
    /// consumed by runUntil on entry into dispatched_from_scheduler.
    sched_dispatch_pending: bool = false,
    /// True while the innermost active runUntil was invoked directly by a
    /// fiber scheduler loop. Blocking primitives may only park the current
    /// fiber with yield_retry when this is set — otherwise Zig-native frames
    /// (map/for-each callbacks, eval) sit between the fiber's bytecode and
    /// the scheduler, and a retry would corrupt them.
    dispatched_from_scheduler: bool = false,
    /// For child OS threads (SRFI-18): points at the parent-heap fiber's
    /// `terminated` flag. Checked at the periodic dispatch-loop safepoint so
    /// thread-terminate! from another thread can stop this VM. Written by the
    /// parent thread, read here — access must be atomic.
    terminate_flag: ?*bool = null,

    pub fn init(gc: *memory.GC) !VM {
        const frames = try gc.allocator.alloc(CallFrame, INITIAL_FRAME_CAPACITY);
        errdefer gc.allocator.free(frames);
        const registers = try gc.allocator.alloc(Value, INITIAL_REGISTER_CAPACITY);
        errdefer gc.allocator.free(registers);
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
            .globals = globals_map,
            .globals_lock = globals_lock,
            .macros = std.StringHashMap(Value).init(gc.allocator),
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
        var vm = VM{
            .gc = gc,
            .frames = frames,
            .registers = registers,
            // Shared by pointer: the child sees the parent's map through
            // every rehash. Reads on this VM take the shared lock (see the
            // `globals` field doc); a struct copy here would leave the child
            // on a freed bucket array after the first parent-side rehash.
            .globals = parent.globals,
            .globals_lock = parent.globals_lock,
            .macros = parent.macros,
            .output = .empty,
            .libraries = parent.libraries,
            .loading_libs = std.StringHashMap(void).init(gc.allocator),
            .lib_paths = parent.lib_paths,
            .param_overrides = std.AutoHashMap(usize, Value).init(gc.allocator),
            .owns_globals = false,
        };
        @memset(vm.registers, types.UNDEFINED);
        gc.root_marker = &markVMRoots;
        vm.stdin_port = gc.allocPort(0, true, false, "stdin", false) catch types.VOID;
        vm.stdout_port = gc.allocPort(1, false, true, "stdout", false) catch types.VOID;
        vm.stderr_port = gc.allocPort(2, false, true, "stderr", false) catch types.VOID;
        if (vm.stdin_port != types.VOID) try gc.extra_roots.append(gc.allocator, vm.stdin_port);
        if (vm.stdout_port != types.VOID) try gc.extra_roots.append(gc.allocator, vm.stdout_port);
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
            self.gc.allocator.destroy(sched);
            self.scheduler = null;
        }
        if (self.owns_globals) {
            self.globals.deinit();
            self.gc.allocator.destroy(self.globals);
            self.gc.allocator.destroy(self.globals_lock);
            self.macros.deinit();
            self.libraries.deinit();
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
        self.gc.allocator.free(self.frames);
        self.gc.allocator.free(self.registers);
    }

    pub fn ensureFrameCapacity(self: *VM, needed: usize) VMError!void {
        if (needed <= self.frames.len) return;
        if (needed > MAX_FRAME_LIMIT) return VMError.StackOverflow;
        var new_cap = self.frames.len;
        while (new_cap < needed) new_cap *= 2;
        if (new_cap > MAX_FRAME_LIMIT) new_cap = MAX_FRAME_LIMIT;
        const new_frames = self.gc.allocator.alloc(CallFrame, new_cap) catch return VMError.OutOfMemory;
        @memcpy(new_frames[0..self.frame_count], self.frames[0..self.frame_count]);
        self.gc.allocator.free(self.frames);
        self.frames = new_frames;
    }

    pub fn ensureRegisterCapacity(self: *VM, needed: usize) VMError!void {
        if (needed <= self.registers.len) return;
        if (needed > MAX_REGISTER_LIMIT) return VMError.StackOverflow;
        var new_cap = self.registers.len;
        while (new_cap < needed) new_cap *= 2;
        if (new_cap > MAX_REGISTER_LIMIT) new_cap = MAX_REGISTER_LIMIT;
        const new_regs = self.gc.allocator.alloc(Value, new_cap) catch return VMError.OutOfMemory;
        @memcpy(new_regs[0..self.registers.len], self.registers);
        @memset(new_regs[self.registers.len..], types.UNDEFINED);
        self.gc.allocator.free(self.registers);
        self.registers = new_regs;
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
        self.last_error_source = null;
        if (self.frame_count == 0) return;
        var i = self.frame_count;
        while (i > 0) {
            i -= 1;
            if (self.frames[i].closure) |cls| {
                const func = cls.func;
                if (func.line_table.items.len > 0) {
                    const ip = if (self.frames[i].ip > 0) self.frames[i].ip - 1 else 0;
                    const line = func.lineForOffset(ip);
                    if (line > 0) {
                        self.last_error_line = line;
                        self.last_error_source = func.source_name;
                        return;
                    }
                }
                if (func.source_line > 0) {
                    self.last_error_line = func.source_line;
                    self.last_error_source = func.source_name;
                    return;
                }
            }
        }
    }

    pub fn getErrorDetail(self: *VM) []const u8 {
        return self.last_error_detail[0..self.last_error_detail_len];
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
        if (self.last_error_detail_len != 0) return;

        const printer = @import("printer.zig");
        const allocator = self.gc.allocator;
        var w: std.Io.Writer = .fixed(&self.last_error_detail);
        if (types.isErrorObject(exc)) {
            const eo = types.toObject(exc).as(types.ErrorObject);
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
        if (self.handler_count >= MAX_HANDLERS) return VMError.StackOverflow;
        self.handler_stack[self.handler_count] = .{
            .handler = handler,
            .frame_count = self.frame_count,
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

    const vm_dispatch = @import("vm_dispatch.zig");

    pub fn runUntil(self: *VM, target_frame_count: usize, target_wind_count: usize) VMError!Value {
        return vm_dispatch.runUntil(self, target_frame_count, target_wind_count);
    }

    pub fn resetExecutionState(self: *VM) void {
        self.frame_count = 0;
        self.handler_count = 0;
        self.wind_count = 0;
        self.current_exception = null;
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
};

test {
    _ = @import("vm_tests.zig");
    _ = vm_library;
    _ = vm_records;
    _ = vm_continuations;
}
