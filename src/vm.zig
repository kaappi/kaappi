const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");
const library_mod = @import("library.zig");
const Value = types.Value;
const OpCode = types.OpCode;

pub const vm_library = @import("vm_library.zig");
pub const vm_records = @import("vm_records.zig");
pub const vm_continuations = @import("vm_continuations.zig");

pub const VMError = error{
    StackOverflow,
    TypeError,
    ArityMismatch,
    UndefinedVariable,
    NotAProcedure,
    OutOfMemory,
    InvalidBytecode,
    DivisionByZero,
    CompileError,
    ExceptionRaised,
    ContinuationInvoked,
    IndexOutOfBounds,
    InvalidArgument,
    Yielded,
    ExecutionTimeout,
};

const build_options = @import("build_options");
pub const INITIAL_FRAME_CAPACITY: usize = build_options.max_frames;
pub const INITIAL_REGISTER_CAPACITY: usize = build_options.max_registers;
pub const MAX_FRAME_LIMIT: usize = 32768;
pub const MAX_REGISTER_LIMIT: usize = 65536;
pub const MAX_HANDLERS = 64;
pub const MAX_WINDS = 64;

pub threadlocal var vm_instance: ?*VM = null;

pub fn setVMInstance(vm: *VM) void {
    vm_instance = vm;
}

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
        // Conservatively mark the frame's whole register window. locals_count
        // is the compiler-recorded high-water mark of registers the function
        // can touch; a closure-less frame falls back to a safe upper bound.
        const window: usize = if (f.closure) |cls| blk: {
            const lc = cls.func.locals_count;
            break :blk if (lc == 0) 256 else @as(usize, lc);
        } else 256;
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

pub const ExceptionHandler = struct {
    handler: Value, // the handler procedure
    frame_count: usize, // saved call stack depth for unwinding
};

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

pub const CallFrame = struct {
    closure: ?*types.Closure,
    native: ?*types.NativeFn = null,
    code: []const u8,
    ip: usize,
    base: u32,
    dst: u16,
    saved_wind_count: u16 = 0,
};

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
    globals: std.StringHashMap(Value),
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
    stdin_port: Value = types.VOID,
    stdout_port: Value = types.VOID,
    stderr_port: Value = types.VOID,
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

    pub fn init(gc: *memory.GC) !VM {
        const frames = try gc.allocator.alloc(CallFrame, INITIAL_FRAME_CAPACITY);
        errdefer gc.allocator.free(frames);
        const registers = try gc.allocator.alloc(Value, INITIAL_REGISTER_CAPACITY);
        errdefer gc.allocator.free(registers);
        var vm = VM{
            .gc = gc,
            .frames = frames,
            .registers = registers,
            .globals = std.StringHashMap(Value).init(gc.allocator),
            .macros = std.StringHashMap(Value).init(gc.allocator),
            .output = .empty,
            .libraries = library_mod.LibraryRegistry.init(gc.allocator),
            .loading_libs = std.StringHashMap(void).init(gc.allocator),
            .param_overrides = std.AutoHashMap(usize, Value).init(gc.allocator),
        };
        @memset(vm.registers, types.UNDEFINED);
        gc.root_marker = &markVMRoots;
        // Pre-allocate standard ports
        vm.stdin_port = gc.allocPort(0, true, false, "stdin", false) catch types.VOID;
        vm.stdout_port = gc.allocPort(1, false, true, "stdout", false) catch types.VOID;
        vm.stderr_port = gc.allocPort(2, false, true, "stderr", false) catch types.VOID;
        // Root the standard ports so GC never collects them
        if (vm.stdin_port != types.VOID) try gc.extra_roots.append(gc.allocator, vm.stdin_port);
        if (vm.stdout_port != types.VOID) try gc.extra_roots.append(gc.allocator, vm.stdout_port);
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
            .globals = parent.globals,
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
        return vm;
    }

    pub fn deinit(self: *VM) void {
        if (self.scheduler) |sched| {
            self.gc.allocator.destroy(sched);
            self.scheduler = null;
        }
        if (self.owns_globals) {
            self.globals.deinit();
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
        } else {
            if (self.param_overrides.get(key)) |val| return val;
        }
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

    pub fn defineGlobal(self: *VM, name: []const u8, value: Value) !void {
        try self.globals.put(name, value);
        self.global_version +%= 1;
    }

    // -- Exception handling --

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

    /// Call a handler procedure with a single argument, using the VM's call machinery.
    /// Used by with-exception-handler when an exception is caught.
    /// Call a 1-argument procedure re-entrantly from native code.
    /// `return_dst` is the register offset (relative to the *caller's* base)
    /// where the procedure's result should land if its frame ever returns via
    /// the normal RETURN path — which happens when the frame is captured in a
    /// continuation and later restored (the re-entrant runUntil that would
    /// otherwise capture the return value is gone by then). In the normal,
    /// non-captured path the result is delivered via runUntil's return value and
    /// `return_dst` is unused, so callers that never expose the frame to capture
    /// (e.g. exception handlers) can pass 0.
    pub fn callHandler(self: *VM, handler_val: Value, arg: Value, return_dst: u8) VMError!Value {
        if (types.isContinuation(handler_val)) {
            const cont = types.toObject(handler_val).as(types.Continuation);
            if (cont.is_escape) {
                try vm_continuations.invokeEscape(self, cont, arg);
                return VMError.ContinuationInvoked;
            }
            try vm_continuations.performWindTransition(self, cont.wind_records[0..cont.wind_count], cont.wind_count);
            try vm_continuations.restoreContinuation(self, cont, arg);
            return VMError.ContinuationInvoked;
        }
        if (types.isClosure(handler_val)) {
            const closure = types.toObject(handler_val).as(types.Closure);
            const func = closure.func;

            const base: u32 = if (self.frame_count > 0) blk: {
                const prev = self.frames[self.frame_count - 1];
                const stride: u32 = if (prev.closure) |c|
                    @max(16, @as(u16, c.func.locals_count) + 2)
                else
                    32;
                break :blk prev.base + stride;
            } else 0;
            try self.ensureRegisterCapacity(@as(usize, base) + @as(usize, func.locals_count) + 1);

            if (func.is_variadic and func.arity == 0) {
                // (lambda args ...) — wrap arg in a list
                self.registers[base] = self.gc.allocPair(arg, types.NIL) catch return VMError.OutOfMemory;
            } else if (func.is_variadic and func.arity == 1) {
                // (lambda (x . rest) ...) — x=arg, rest=()
                self.registers[base] = arg;
                self.registers[base + 1] = types.NIL;
            } else {
                self.registers[base] = arg;
            }

            try self.ensureFrameCapacity(self.frame_count + 1);

            const saved_frame_count = self.frame_count;
            const saved_handler_count = self.handler_count;
            const saved_wind_count = self.wind_count;
            self.frames[self.frame_count] = .{
                .closure = closure,
                .code = func.code.items,
                .ip = 0,
                .base = base,
                .dst = return_dst,
                .saved_wind_count = @intCast(self.wind_count),
            };
            self.frame_count += 1;

            const result = self.runUntil(saved_frame_count, saved_wind_count) catch |err| {
                if (err == VMError.ContinuationInvoked) {
                    if (self.frame_count >= saved_frame_count) return self.continuation_value;
                    return err;
                }
                self.frame_count = saved_frame_count;
                self.handler_count = saved_handler_count;
                self.wind_count = saved_wind_count;
                return err;
            };
            return result;
        } else if (types.isNativeFn(handler_val)) {
            const native = types.toObject(handler_val).as(types.NativeFn);
            const args = [1]Value{arg};
            self.last_error_detail_len = 0;
            const result = native.func(&args) catch |err| {
                return switch (err) {
                    error.TypeError => blk: {
                        if (self.last_error_detail_len == 0) {
                            if (args.len > 0) {
                                const p = @import("printer.zig");
                                const s = p.valueToString(self.gc.allocator, args[0], .write) catch "";
                                defer if (s.len > 0) self.gc.allocator.free(s);
                                self.setErrorDetail("type error in '{s}': got {s}", .{ native.name, s });
                            } else {
                                self.setErrorDetail("type error in '{s}'", .{native.name});
                            }
                        }
                        break :blk VMError.TypeError;
                    },
                    error.DivisionByZero => VMError.DivisionByZero,
                    error.IndexOutOfBounds => blk_iob: {
                        if (self.last_error_detail_len == 0)
                            self.setErrorDetail("index out of bounds in '{s}'", .{native.name});
                        break :blk_iob VMError.IndexOutOfBounds;
                    },
                    error.InvalidArgument => blk_ia: {
                        self.setErrorDetail("invalid argument in '{s}'", .{native.name});
                        break :blk_ia VMError.InvalidArgument;
                    },
                    error.OutOfMemory => VMError.OutOfMemory,
                    error.ExceptionRaised => VMError.ExceptionRaised,
                    error.ContinuationInvoked => VMError.ContinuationInvoked,
                    else => VMError.InvalidBytecode,
                };
            };
            return result;
        } else {
            self.setErrorDetail("not a procedure", .{});
            return VMError.NotAProcedure;
        }
    }

    /// Call a thunk (0-argument procedure), using the VM's call machinery.
    pub fn callThunk(self: *VM, thunk_val: Value) VMError!Value {
        if (types.isClosure(thunk_val)) {
            const closure = types.toObject(thunk_val).as(types.Closure);
            const func = closure.func;

            const base: u32 = if (self.frame_count > 0) blk: {
                const prev = self.frames[self.frame_count - 1];
                const stride: u32 = if (prev.closure) |c|
                    @max(16, @as(u16, c.func.locals_count) + 2)
                else
                    32;
                break :blk prev.base + stride;
            } else 0;
            try self.ensureRegisterCapacity(@as(usize, base) + @as(usize, func.locals_count) + 1);

            if (func.is_variadic and func.arity == 0) {
                self.registers[base] = types.NIL;
            }

            try self.ensureFrameCapacity(self.frame_count + 1);

            const saved_frame_count = self.frame_count;
            const saved_handler_count = self.handler_count;
            const saved_wind_count = self.wind_count;
            self.frames[self.frame_count] = .{
                .closure = closure,
                .code = func.code.items,
                .ip = 0,
                .base = base,
                .dst = 0,
                .saved_wind_count = @intCast(self.wind_count),
            };
            self.frame_count += 1;

            const result = self.runUntil(saved_frame_count, saved_wind_count) catch |err| {
                if (err == VMError.ContinuationInvoked) {
                    // If the escape continuation targeted a frame within our
                    // scope, the value has been delivered — return it.
                    if (self.frame_count >= saved_frame_count) {
                        return self.continuation_value;
                    }
                    return err;
                }
                // On error, unwind any frames that were pushed during the thunk
                self.frame_count = saved_frame_count;
                self.handler_count = saved_handler_count;
                self.wind_count = saved_wind_count;
                return err;
            };
            return result;
        } else if (types.isNativeFn(thunk_val)) {
            const native = types.toObject(thunk_val).as(types.NativeFn);
            const empty_args: []const Value = &.{};
            const result = native.func(empty_args) catch |err| {
                return switch (err) {
                    error.TypeError => VMError.TypeError,
                    error.DivisionByZero => VMError.DivisionByZero,
                    error.IndexOutOfBounds => blk_iob: {
                        self.setErrorDetail("index out of bounds in '{s}'", .{native.name});
                        break :blk_iob VMError.IndexOutOfBounds;
                    },
                    error.InvalidArgument => blk_ia: {
                        self.setErrorDetail("invalid argument in '{s}'", .{native.name});
                        break :blk_ia VMError.InvalidArgument;
                    },
                    error.OutOfMemory => VMError.OutOfMemory,
                    error.ExceptionRaised => VMError.ExceptionRaised,
                    error.ContinuationInvoked => VMError.ContinuationInvoked,
                    else => VMError.InvalidBytecode,
                };
            };
            return result;
        } else {
            return VMError.NotAProcedure;
        }
    }

    /// Call a procedure with multiple arguments using the VM's call machinery.
    pub fn callWithArgs(self: *VM, proc: Value, args: []const Value) VMError!Value {
        if (types.isFfiFunction(proc)) {
            const ffi_fn = types.toObject(proc).as(types.FfiFunction);
            if (args.len != ffi_fn.param_count) return VMError.ArityMismatch;
            const ffi_mod = @import("ffi.zig");
            return ffi_mod.callFfi(ffi_fn, args, self.gc) catch return VMError.TypeError;
        }
        if (types.isParameter(proc)) {
            const param = types.toObject(proc).as(types.ParameterObject);
            if (args.len == 0) {
                return self.getParameterValue(param);
            } else {
                var new_val = args[0];
                if (param.converter != types.NIL) {
                    new_val = try self.callWithArgs(param.converter, &[_]Value{new_val});
                }
                try self.setParameterValue(param, new_val);
                return types.VOID;
            }
        }
        if (types.isContinuation(proc)) {
            const cont = types.toObject(proc).as(types.Continuation);
            const value = if (args.len == 0) types.VOID else args[0];
            if (cont.is_escape) {
                try vm_continuations.invokeEscape(self, cont, value);
                return VMError.ContinuationInvoked;
            }
            try vm_continuations.performWindTransition(self, cont.wind_records[0..cont.wind_count], cont.wind_count);
            try vm_continuations.restoreContinuation(self, cont, value);
            return VMError.ContinuationInvoked;
        }
        if (types.isClosure(proc)) {
            const closure = types.toObject(proc).as(types.Closure);
            const func = closure.func;

            const base: u32 = if (self.frame_count > 0) blk: {
                const prev = self.frames[self.frame_count - 1];
                const stride: u32 = if (prev.closure) |c|
                    @max(16, @as(u16, c.func.locals_count) + 2)
                else
                    32;
                break :blk prev.base + stride;
            } else 0;
            try self.ensureRegisterCapacity(@as(usize, base) + @as(usize, func.locals_count) + 1);

            if (args.len > std.math.maxInt(u8)) return VMError.ArityMismatch;
            const nargs: u8 = @intCast(args.len);
            if (!func.is_variadic) {
                if (nargs != func.arity) return VMError.ArityMismatch;
            } else {
                if (nargs < func.arity) return VMError.ArityMismatch;
                // Collect rest args into a list
                const rest_start = func.arity;
                var rest_list: Value = types.NIL;
                self.gc.pushRoot(&rest_list) catch return VMError.OutOfMemory;
                var i: u8 = nargs;
                while (i > rest_start) {
                    i -= 1;
                    rest_list = self.gc.allocPair(args[i], rest_list) catch {
                        self.gc.popRoot();
                        return VMError.OutOfMemory;
                    };
                }
                self.gc.popRoot();
                // Place fixed args and rest list
                for (0..rest_start) |ri| {
                    self.registers[base + ri] = args[ri];
                }
                self.registers[base + rest_start] = rest_list;
            }

            if (!func.is_variadic) {
                for (args, 0..) |arg, i| {
                    self.registers[base + i] = arg;
                }
            }

            try self.ensureFrameCapacity(self.frame_count + 1);

            const saved_frame_count = self.frame_count;
            const saved_handler_count = self.handler_count;
            const saved_wind_count = self.wind_count;
            self.frames[self.frame_count] = .{
                .closure = closure,
                .code = func.code.items,
                .ip = 0,
                .base = base,
                .dst = 0,
                .saved_wind_count = @intCast(self.wind_count),
            };
            self.frame_count += 1;

            const result = self.runUntil(saved_frame_count, saved_wind_count) catch |err| {
                if (err == VMError.ContinuationInvoked) {
                    if (self.frame_count >= saved_frame_count) return self.continuation_value;
                    return err;
                }
                self.frame_count = saved_frame_count;
                self.handler_count = saved_handler_count;
                self.wind_count = saved_wind_count;
                return err;
            };
            return result;
        } else if (types.isNativeClosure(proc)) {
            const nc = types.toObject(proc).as(types.NativeClosure);
            if (args.len != nc.arity) {
                self.setErrorDetail("'{s}': expected {d} arguments, got {d}", .{ nc.name, nc.arity, args.len });
                return VMError.ArityMismatch;
            }
            const result = nc.fn_ptr(self, args.ptr, args.len, nc.upvalues.ptr);
            return result;
        } else if (types.isNativeFn(proc)) {
            const native = types.toObject(proc).as(types.NativeFn);
            switch (native.arity) {
                .exact => |expected| {
                    if (args.len != expected) {
                        self.setErrorDetail("'{s}': expected {d} arguments, got {d}", .{ native.name, expected, args.len });
                        return VMError.ArityMismatch;
                    }
                },
                .variadic => |min| {
                    if (args.len < min) {
                        self.setErrorDetail("'{s}': expected at least {d} arguments, got {d}", .{ native.name, min, args.len });
                        return VMError.ArityMismatch;
                    }
                },
            }
            self.last_error_detail_len = 0;
            const result = native.func(args) catch |err| {
                return switch (err) {
                    error.TypeError => blk: {
                        if (self.last_error_detail_len == 0) {
                            if (args.len > 0) {
                                const p = @import("printer.zig");
                                const s = p.valueToString(self.gc.allocator, args[0], .write) catch "";
                                defer if (s.len > 0) self.gc.allocator.free(s);
                                self.setErrorDetail("type error in '{s}': got {s}", .{ native.name, s });
                            } else {
                                self.setErrorDetail("type error in '{s}'", .{native.name});
                            }
                        }
                        break :blk VMError.TypeError;
                    },
                    error.DivisionByZero => VMError.DivisionByZero,
                    error.IndexOutOfBounds => blk_iob: {
                        if (self.last_error_detail_len == 0)
                            self.setErrorDetail("index out of bounds in '{s}'", .{native.name});
                        break :blk_iob VMError.IndexOutOfBounds;
                    },
                    error.InvalidArgument => blk_ia: {
                        self.setErrorDetail("invalid argument in '{s}'", .{native.name});
                        break :blk_ia VMError.InvalidArgument;
                    },
                    error.OutOfMemory => VMError.OutOfMemory,
                    error.ExceptionRaised => VMError.ExceptionRaised,
                    error.ContinuationInvoked => VMError.ContinuationInvoked,
                    else => VMError.InvalidBytecode,
                };
            };
            return result;
        } else {
            self.setErrorDetail("not a procedure", .{});
            return VMError.NotAProcedure;
        }
    }

    /// Capture the current continuation state (delegates to vm_continuations).
    pub fn captureContinuation(self: *VM, dst_reg: u8, dst_base: u32) VMError!Value {
        return vm_continuations.captureContinuation(self, dst_reg, dst_base);
    }

    /// Call a procedure with the current continuation (delegates to vm_continuations).
    pub fn callWithCC(self: *VM, proc: Value, base: u16) VMError!void {
        return vm_continuations.callWithCC(self, proc, base);
    }

    /// Capture an escape continuation (delegates to vm_continuations).
    pub fn captureEscape(self: *VM, dst_reg: u8, dst_base: u32) VMError!Value {
        return vm_continuations.captureEscape(self, dst_reg, dst_base);
    }

    /// Invoke an escape continuation (delegates to vm_continuations).
    pub fn invokeEscape(self: *VM, cont: *types.Continuation, value: Value) VMError!void {
        return vm_continuations.invokeEscape(self, cont, value);
    }

    /// Perform dynamic-wind transition (delegates to vm_continuations).
    pub fn performWindTransition(self: *VM, target_winds: []const types.WindRecord, target_count: usize) VMError!void {
        return vm_continuations.performWindTransition(self, target_winds, target_count);
    }

    /// Run the VM until frame_count drops to target_frame_count.
    /// This is used by callThunk/callHandler to avoid executing past
    /// the caller's frame. target_wind_count specifies the wind level
    /// to unwind to on exit (ensures dynamic-wind after-thunks run
    /// even when the native function that pushed them is no longer on
    /// the Zig call stack after a continuation restore).
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
    }

    const vm_calls = @import("vm_calls.zig");

    fn clockNs() u64 {
        return vm_calls.clockNs();
    }

    fn profileCreditSelf(self: *VM) void {
        vm_calls.profileCreditSelf(self);
    }

    fn profilePushCall(self: *VM, func: *types.Function) void {
        vm_calls.profilePushCall(self, func);
    }

    fn profilePopReturn(self: *VM) void {
        vm_calls.profilePopReturn(self);
    }

    fn profileTailCall(self: *VM, new_func: *types.Function) void {
        vm_calls.profileTailCall(self, new_func);
    }

    pub fn execute(self: *VM, func: *types.Function) VMError!Value {
        return vm_calls.execute(self, func);
    }

    pub fn run(self: *VM) VMError!Value {
        return vm_calls.run(self);
    }

    fn handleNativeError(self: *VM, err: anyerror, base: u16, nargs: u8) VMError {
        return vm_calls.handleNativeError(self, err, base, nargs);
    }

    fn callValue(self: *VM, callee: Value, base: u16, nargs: u8) VMError!void {
        return vm_calls.callValue(self, callee, base, nargs);
    }

    fn callClosure(self: *VM, closure: *types.Closure, base: u16, nargs: u8) VMError!void {
        return vm_calls.callClosure(self, closure, base, nargs);
    }

    fn callNative(self: *VM, native: *types.NativeFn, base: u16, nargs: u8) VMError!void {
        return vm_calls.callNative(self, native, base, nargs);
    }

    pub fn restoreContinuation(self: *VM, cont: *types.Continuation, value: Value) VMError!void {
        try vm_continuations.restoreContinuation(self, cont, value);
    }

    const vm_debug = @import("vm_debug.zig");

    fn shouldDebugPause(self: *VM, frame: *CallFrame) bool {
        return vm_dispatch.shouldDebugPause(self, frame);
    }

    fn debugPause(self: *VM, frame: *CallFrame) !void {
        return vm_dispatch.debugPause(self, frame);
    }

    fn ensureOperands(self: *VM, frame: *CallFrame, operand_bytes: usize) VMError!void {
        return vm_dispatch.ensureOperands(self, frame, operand_bytes);
    }

    pub fn registerIndex(self: *VM, base: u16, reg: u8) VMError!usize {
        return vm_dispatch.registerIndex(self, base, reg);
    }

    fn ensureCallWindow(self: *VM, base: usize, nargs: u8) VMError!void {
        return vm_dispatch.ensureCallWindow(self, base, nargs);
    }

    fn constantAt(self: *VM, func: *types.Function, idx: u16) VMError!Value {
        return vm_dispatch.constantAt(self, func, idx);
    }

    fn readU8(self: *VM, frame: *CallFrame) u8 {
        return vm_dispatch.readU8(self, frame);
    }

    fn readU16(self: *VM, frame: *CallFrame) u16 {
        return vm_dispatch.readU16(self, frame);
    }

    fn readI16(self: *VM, frame: *CallFrame) i16 {
        return vm_dispatch.readI16(self, frame);
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
