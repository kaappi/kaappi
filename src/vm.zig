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
pub const jit = @import("jit.zig");

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
};

pub const MAX_FRAMES = 256;
pub const MAX_REGISTERS = 1024;
pub const MAX_HANDLERS = 64;
pub const MAX_WINDS = 64;

pub var vm_instance: ?*VM = null;

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
        const end: usize = @min(@as(usize, f.base) + window, MAX_REGISTERS);
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

    var git = vm.globals.valueIterator();
    while (git.next()) |v| gc.markValue(v.*);
    var mit = vm.macros.valueIterator();
    while (mit.next()) |v| gc.markValue(v.*);

    var pit = vm.param_overrides.valueIterator();
    while (pit.next()) |v| gc.markValue(v.*);

    // Mark library export values and per-library environments
    var lit = vm.libraries.libraries.valueIterator();
    while (lit.next()) |lib| {
        var eit = lib.exports.valueIterator();
        while (eit.next()) |v| gc.markValue(v.*);
        if (lib.lib_env) |env| {
            var eit2 = env.valueIterator();
            while (eit2.next()) |v| gc.markValue(v.*);
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
        const written: usize = @intCast(result);
        if (written == 0) break;
        total += written;
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
    base: u16,
    dst: u8,
    saved_wind_count: u16 = 0,
};

pub const StepMode = enum { none, step, next, continue_to_break };

pub const ProfileTimeEntry = struct {
    func: ?*types.Function,
    entry_ns: u64,
};

pub const VM = struct {
    gc: *memory.GC,
    registers: [MAX_REGISTERS]Value = undefined,
    frames: [MAX_FRAMES]CallFrame = undefined,
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
    breakpoints: [16][]const u8 = undefined,
    breakpoint_count: usize = 0,
    step_mode: StepMode = .none,
    step_frame: usize = 0,
    global_version: u32 = 0,
    profile_mode: bool = false,
    profile_last_ns: u64 = 0,
    profile_time_stack: [256]ProfileTimeEntry = undefined,
    profile_time_depth: usize = 0,
    sandbox_mode: bool = false,
    /// Virtual filesystem for standalone binary: maps file paths → source content.
    /// Populated from .sbc bundled files section; checked before disk reads.
    bundled_files: ?*std.StringHashMap([]const u8) = null,
    /// When non-null, record files read during library loading for bundling.
    compile_collect_files: ?*std.StringHashMap([]const u8) = null,
    jit_disabled: bool = false,
    jit_error: ?VMError = null,
    param_overrides: std.AutoHashMap(usize, Value) = undefined,
    scheduler: ?*@import("fiber.zig").FiberScheduler = null,
    current_fiber: ?*@import("fiber.zig").Fiber = null,
    yielded: bool = false,

    pub fn init(gc: *memory.GC) !VM {
        var vm = VM{
            .gc = gc,
            .globals = std.StringHashMap(Value).init(gc.allocator),
            .macros = std.StringHashMap(Value).init(gc.allocator),
            .output = .empty,
            .libraries = library_mod.LibraryRegistry.init(gc.allocator),
            .loading_libs = std.StringHashMap(void).init(gc.allocator),
            .param_overrides = std.AutoHashMap(usize, Value).init(gc.allocator),
        };
        @memset(&vm.registers, types.UNDEFINED);
        // Teach the GC how to find roots held in the VM (registers, frames,
        // handlers, winds, globals, macros) so collections during execution
        // don't free in-flight objects.
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

    pub fn deinit(self: *VM) void {
        if (self.scheduler) |sched| {
            self.gc.allocator.destroy(sched);
            self.scheduler = null;
        }
        self.globals.deinit();
        self.macros.deinit();
        self.output.deinit(self.gc.allocator);
        self.libraries.deinit();
        self.loading_libs.deinit();
        self.param_overrides.deinit();
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

    pub fn setParameterValue(self: *VM, param: *types.ParameterObject, val: Value) void {
        const key = @intFromPtr(param);
        if (self.current_fiber) |fiber| {
            fiber.param_overrides.put(key, val) catch {};
        } else {
            self.param_overrides.put(key, val) catch {};
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

            const base: u16 = if (self.frame_count > 0)
                blk: {
                    const prev = self.frames[self.frame_count - 1];
                    const stride: u16 = if (prev.closure) |c|
                        @max(16, @as(u16, c.func.locals_count) + 2)
                    else 32;
                    break :blk prev.base + stride;
                }
            else
                0;
            if (base + func.locals_count >= MAX_REGISTERS) return VMError.StackOverflow;

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

            if (self.frame_count >= MAX_FRAMES) return VMError.StackOverflow;

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

            const base: u16 = if (self.frame_count > 0)
                blk: {
                    const prev = self.frames[self.frame_count - 1];
                    const stride: u16 = if (prev.closure) |c|
                        @max(16, @as(u16, c.func.locals_count) + 2)
                    else 32;
                    break :blk prev.base + stride;
                }
            else
                0;
            if (base + @as(u16, func.locals_count) >= MAX_REGISTERS) return VMError.StackOverflow;

            if (func.is_variadic and func.arity == 0) {
                self.registers[base] = types.NIL;
            }

            if (self.frame_count >= MAX_FRAMES) return VMError.StackOverflow;

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
                self.setParameterValue(param, new_val);
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

            const base: u16 = if (self.frame_count > 0)
                blk: {
                    const prev = self.frames[self.frame_count - 1];
                    const stride: u16 = if (prev.closure) |c|
                        @max(16, @as(u16, c.func.locals_count) + 2)
                    else 32;
                    break :blk prev.base + stride;
                }
            else
                0;
            if (base + args.len + 1 >= MAX_REGISTERS) return VMError.StackOverflow;

            const nargs: u8 = @intCast(args.len);
            if (!func.is_variadic) {
                if (nargs != func.arity) return VMError.ArityMismatch;
            } else {
                if (nargs < func.arity) return VMError.ArityMismatch;
                // Collect rest args into a list
                const rest_start = func.arity;
                var rest_list: Value = types.NIL;
                var i: u8 = nargs;
                while (i > rest_start) {
                    i -= 1;
                    rest_list = self.gc.allocPair(args[i], rest_list) catch return VMError.OutOfMemory;
                }
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

            if (self.frame_count >= MAX_FRAMES) return VMError.StackOverflow;

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
    pub fn captureContinuation(self: *VM, dst_reg: u8, dst_base: u16) VMError!Value {
        return vm_continuations.captureContinuation(self, dst_reg, dst_base);
    }

    /// Call a procedure with the current continuation (delegates to vm_continuations).
    pub fn callWithCC(self: *VM, proc: Value, base: u16) VMError!void {
        return vm_continuations.callWithCC(self, proc, base);
    }

    /// Capture an escape continuation (delegates to vm_continuations).
    pub fn captureEscape(self: *VM, dst_reg: u8, dst_base: u16) VMError!Value {
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
    pub fn runUntil(self: *VM, target_frame_count: usize, target_wind_count: usize) VMError!Value {
        while (self.frame_count > target_frame_count) {
            if (self.yielded) {
                self.yielded = false;
                return VMError.Yielded;
            }

            const frame = &self.frames[self.frame_count - 1];
            if (frame.ip >= frame.code.len) return VMError.InvalidBytecode;

            const raw_op = frame.code[frame.ip];
            if (raw_op > @intFromEnum(OpCode.self_tail_call)) return VMError.InvalidBytecode;
            const op: OpCode = @enumFromInt(raw_op);
            frame.ip += 1;

            const fixed_operand_bytes: usize = switch (op) {
                .load_const => 3,
                .load_nil, .load_true, .load_false, .load_void => 1,
                .move => 2,
                .get_global => 3,
                .set_global => 3,
                .define_global => 3,
                .tail_apply => 2,
                .get_local, .set_local => 2,
                .get_upvalue, .set_upvalue => 2,
                .call, .tail_call => 2,
                .@"return" => 1,
                .jump => 2,
                .jump_false, .jump_true => 3,
                .closure => 3,
                .close_upvalue => 1,
                .cons => 3,
                .push_handler => 1,
                .pop_handler, .halt => 0,
                .call_global, .tail_call_global => 4,
                .box_local => 1,
                .get_box_local, .set_box_local => 2,
                .self_tail_call => 2,
            };
            try self.ensureOperands(frame, fixed_operand_bytes);

            // Debug hook -- check if we should pause
            if (self.debug_mode) {
                if (self.shouldDebugPause(frame)) {
                    self.debugPause(frame) catch {};
                }
            }

            if (self.profile_mode) {
                if (frame.closure) |cl| {
                    cl.func.profile_instrs += 1;
                }
            }

            switch (op) {
                .load_const => {
                    const dst = self.readU8(frame);
                    const idx = self.readU16(frame);
                    const closure = frame.closure orelse return VMError.InvalidBytecode;
                    const dst_idx = try self.registerIndex(frame.base, dst);
                    self.registers[dst_idx] = try self.constantAt(closure.func, idx);
                },
                .load_nil => {
                    const dst = self.readU8(frame);
                    const dst_idx = try self.registerIndex(frame.base, dst);
                    self.registers[dst_idx] = types.NIL;
                },
                .load_true => {
                    const dst = self.readU8(frame);
                    const dst_idx = try self.registerIndex(frame.base, dst);
                    self.registers[dst_idx] = types.TRUE;
                },
                .load_false => {
                    const dst = self.readU8(frame);
                    const dst_idx = try self.registerIndex(frame.base, dst);
                    self.registers[dst_idx] = types.FALSE;
                },
                .load_void => {
                    const dst = self.readU8(frame);
                    const dst_idx = try self.registerIndex(frame.base, dst);
                    self.registers[dst_idx] = types.VOID;
                },
                .move => {
                    const dst = self.readU8(frame);
                    const src = self.readU8(frame);
                    const dst_idx = try self.registerIndex(frame.base, dst);
                    const src_idx = try self.registerIndex(frame.base, src);
                    self.registers[dst_idx] = self.registers[src_idx];
                },
                .get_global => {
                    const dst = self.readU8(frame);
                    const sym_idx = self.readU16(frame);
                    const closure = frame.closure orelse return VMError.InvalidBytecode;
                    const func = closure.func;
                    const dst_idx = try self.registerIndex(frame.base, dst);
                    const env: *std.StringHashMap(Value) = func.env orelse &self.globals;
                    if (func.env == null) {
                        if (func.global_cache) |cache| {
                            if (func.cache_version == self.global_version and
                                sym_idx < cache.len and cache[sym_idx] != types.VOID)
                            {
                                self.registers[dst_idx] = cache[sym_idx];
                                continue;
                            }
                            if (func.cache_version != self.global_version) {
                                @memset(cache, types.VOID);
                                func.cache_version = self.global_version;
                            }
                        }
                    }
                    const sym = try self.constantAt(func, sym_idx);
                    if (!types.isSymbol(sym)) return VMError.InvalidBytecode;
                    const name = types.symbolName(sym);
                    const val = env.get(name) orelse blk: {
                        if (func.env != null) {
                            if (self.globals.get(name)) |gval| break :blk gval;
                        }
                        self.setErrorDetail("undefined variable '{s}'", .{name});
                        return VMError.UndefinedVariable;
                    };
                    self.registers[dst_idx] = val;
                    if (func.env == null and (types.isClosure(val) or types.isNativeFn(val))) {
                        if (func.global_cache) |cache| {
                            if (sym_idx < cache.len) cache[sym_idx] = val;
                        } else {
                            const cache = self.gc.allocator.alloc(Value, func.constants.items.len) catch continue;
                            @memset(cache, types.VOID);
                            cache[sym_idx] = val;
                            func.global_cache = cache;
                            func.cache_version = self.global_version;
                        }
                    }
                },
                .set_global => {
                    const sym_idx = self.readU16(frame);
                    const src = self.readU8(frame);
                    const closure = frame.closure orelse return VMError.InvalidBytecode;
                    const func = closure.func;
                    const src_idx = try self.registerIndex(frame.base, src);
                    const env: *std.StringHashMap(Value) = func.env orelse &self.globals;
                    const sym = try self.constantAt(func, sym_idx);
                    if (!types.isSymbol(sym)) return VMError.InvalidBytecode;
                    const name = types.symbolName(sym);
                    if (env.getPtr(name)) |ptr| {
                        const val = self.registers[src_idx];
                        ptr.* = val;
                        if (func.env == null) {
                            self.global_version +%= 1;
                            if (func.global_cache) |cache| {
                                if (sym_idx < cache.len) cache[sym_idx] = val;
                                func.cache_version = self.global_version;
                            }
                        }
                    } else {
                        self.setErrorDetail("set!: unbound variable '{s}'", .{name});
                        return VMError.UndefinedVariable;
                    }
                },
                .define_global => {
                    const sym_idx = self.readU16(frame);
                    const src = self.readU8(frame);
                    const closure = frame.closure orelse return VMError.InvalidBytecode;
                    const func = closure.func;
                    const src_idx = try self.registerIndex(frame.base, src);
                    const env: *std.StringHashMap(Value) = func.env orelse &self.globals;
                    const sym = try self.constantAt(func, sym_idx);
                    if (!types.isSymbol(sym)) return VMError.InvalidBytecode;
                    const name = types.symbolName(sym);
                    const val = self.registers[src_idx];
                    env.put(name, val) catch return VMError.OutOfMemory;
                    if (func.env == null) {
                        self.global_version +%= 1;
                        if (func.global_cache) |cache| {
                            if (sym_idx < cache.len) cache[sym_idx] = val;
                            func.cache_version = self.global_version;
                        }
                    }
                },
                .get_upvalue => {
                    const dst = self.readU8(frame);
                    const idx = self.readU8(frame);
                    const closure = frame.closure orelse return VMError.InvalidBytecode;
                    if (idx >= closure.upvalues.len) return VMError.InvalidBytecode;
                    const uv = closure.upvalues[idx];
                    const dst_idx = try self.registerIndex(frame.base, dst);
                    self.registers[dst_idx] = if (types.isPair(uv) and types.cdr(uv) == types.VOID)
                        types.car(uv)
                    else
                        uv;
                },
                .set_upvalue => {
                    const idx = self.readU8(frame);
                    const src = self.readU8(frame);
                    const closure = frame.closure orelse return VMError.InvalidBytecode;
                    if (idx >= closure.upvalues.len) return VMError.InvalidBytecode;
                    const src_idx = try self.registerIndex(frame.base, src);
                    const uv = closure.upvalues[idx];
                    if (types.isPair(uv) and types.cdr(uv) == types.VOID) {
                        types.setCar(uv, self.registers[src_idx]);
                    } else {
                        closure.upvalues[idx] = self.registers[src_idx];
                    }
                },
                .jump => {
                    const offset = self.readI16(frame);
                    const new_ip = @as(isize, @intCast(frame.ip)) + offset;
                    if (new_ip < 0) return VMError.InvalidBytecode;
                    const target: usize = @intCast(new_ip);
                    if (target > frame.code.len) return VMError.InvalidBytecode;
                    frame.ip = target;
                },
                .jump_false => {
                    const test_reg = self.readU8(frame);
                    const offset = self.readI16(frame);
                    const test_idx = try self.registerIndex(frame.base, test_reg);
                    if (!types.isTruthy(self.registers[test_idx])) {
                        const new_ip = @as(isize, @intCast(frame.ip)) + offset;
                        if (new_ip < 0) return VMError.InvalidBytecode;
                        const target: usize = @intCast(new_ip);
                        if (target > frame.code.len) return VMError.InvalidBytecode;
                        frame.ip = target;
                    }
                },
                .jump_true => {
                    const test_reg = self.readU8(frame);
                    const offset = self.readI16(frame);
                    const test_idx = try self.registerIndex(frame.base, test_reg);
                    if (types.isTruthy(self.registers[test_idx])) {
                        const new_ip = @as(isize, @intCast(frame.ip)) + offset;
                        if (new_ip < 0) return VMError.InvalidBytecode;
                        const target: usize = @intCast(new_ip);
                        if (target > frame.code.len) return VMError.InvalidBytecode;
                        frame.ip = target;
                    }
                },
                .call => {
                    const base_reg = self.readU8(frame);
                    const nargs = self.readU8(frame);
                    const base = frame.base + base_reg;
                    try self.ensureCallWindow(base, nargs);
                    const callee = self.registers[base];
                    if (types.isClosure(callee)) {
                        self.callClosure(types.toObject(callee).as(types.Closure), base, nargs) catch |err| return err;
                    } else {
                        self.callValue(callee, base, nargs) catch |err| {
                            if (err == VMError.ContinuationInvoked) {
                                if (self.frame_count > target_frame_count) {
                                    continue;
                                }
                                return VMError.ContinuationInvoked;
                            }
                            return err;
                        };
                    }
                },
                .tail_call => {
                    const base_reg = self.readU8(frame);
                    const nargs = self.readU8(frame);
                    const abs_base = frame.base + base_reg;
                    try self.ensureCallWindow(abs_base, nargs);
                    const callee = self.registers[abs_base];

                    if (types.isClosure(callee)) {
                        const closure = types.toObject(callee).as(types.Closure);
                        const func = closure.func;

                        if (!func.is_variadic) {
                            if (nargs != func.arity) {
                                self.setErrorDetail("expected {d} arguments, got {d}", .{ func.arity, nargs });
                                return VMError.ArityMismatch;
                            }
                        } else {
                            if (nargs < func.arity) {
                                self.setErrorDetail("expected at least {d} arguments, got {d}", .{ func.arity, nargs });
                                return VMError.ArityMismatch;
                            }
                            const rest_start = func.arity;
                            if (@as(usize, abs_base) + @as(usize, rest_start) + 1 >= MAX_REGISTERS) {
                                return VMError.InvalidBytecode;
                            }
                            var rest_list: Value = types.NIL;
                            var ri: u8 = nargs;
                            while (ri > rest_start) {
                                ri -= 1;
                                rest_list = self.gc.allocPair(
                                    self.registers[abs_base + 1 + ri],
                                    rest_list,
                                ) catch return VMError.OutOfMemory;
                            }
                            self.registers[abs_base + 1 + rest_start] = rest_list;
                        }

                        const arg_count = if (func.is_variadic) func.arity + 1 else nargs;
                        for (0..arg_count) |i| {
                            const dst_idx = @as(usize, frame.base) + i;
                            const src_idx = @as(usize, abs_base) + 1 + i;
                            if (dst_idx >= MAX_REGISTERS or src_idx >= MAX_REGISTERS) {
                                return VMError.InvalidBytecode;
                            }
                            self.registers[dst_idx] = self.registers[src_idx];
                        }

                        if (self.profile_mode) {
                            func.profile_calls += 1;
                            self.profileTailCall(func);
                        }
                        frame.closure = closure;
                        frame.code = func.code.items;
                        frame.ip = 0;
                    } else if (types.isNativeFn(callee)) {
                        const native = types.toObject(callee).as(types.NativeFn);
                        if (self.profile_mode) native.profile_calls += 1;
                        switch (native.arity) {
                            .exact => |expected| {
                                if (nargs != expected) {
                                    self.setErrorDetail("'{s}': expected {d} arguments, got {d}", .{ native.name, expected, nargs });
                                    return VMError.ArityMismatch;
                                }
                            },
                            .variadic => |min| {
                                if (nargs < min) {
                                    self.setErrorDetail("'{s}': expected at least {d} arguments, got {d}", .{ native.name, min, nargs });
                                    return VMError.ArityMismatch;
                                }
                            },
                        }
                        const saved_alloc_target = self.gc.profile_alloc_target;
                        if (self.profile_mode) {
                            self.profileCreditSelf();
                            self.gc.profile_alloc_target = &native.profile_alloc_bytes;
                        }
                        const native_start = if (self.profile_mode) clockNs() else 0;
                        const nargs_slice = self.registers[abs_base + 1 .. abs_base + 1 + nargs];
                        self.last_error_detail_len = 0;
                        const result = native.func(nargs_slice) catch |err| {
                            if (self.profile_mode) {
                                native.profile_time_ns +%= clockNs() -% native_start;
                                self.profile_last_ns = clockNs();
                                self.gc.profile_alloc_target = saved_alloc_target;
                            }
                            if (err == error.ContinuationInvoked) {
                                if (target_frame_count == 0) {
                                    continue;
                                }
                                return VMError.ContinuationInvoked;
                            }
                            return switch (err) {
                                error.TypeError => blk: {
                                    if (self.last_error_detail_len == 0)
                                        self.setErrorDetail("type error in '{s}'", .{native.name});
                                    break :blk VMError.TypeError;
                                },
                                error.DivisionByZero => VMError.DivisionByZero,
                                error.OutOfMemory => VMError.OutOfMemory,
                                error.ExceptionRaised => VMError.ExceptionRaised,
                                error.ContinuationInvoked => VMError.ContinuationInvoked,
                                else => VMError.InvalidBytecode,
                            };
                        };
                        if (self.profile_mode) {
                            native.profile_time_ns +%= clockNs() -% native_start;
                            self.profile_last_ns = clockNs();
                            self.gc.profile_alloc_target = saved_alloc_target;
                        }
                        const return_dst = frame.dst;
                        self.frame_count -= 1;
                        if (self.profile_mode) self.profilePopReturn();
                        if (self.frame_count <= target_frame_count) {
                            return result;
                        }
                        const caller = &self.frames[self.frame_count - 1];
                        const ret_idx = try self.registerIndex(caller.base, return_dst);
                        self.registers[ret_idx] = result;
                    } else if (types.isContinuation(callee)) {
                        const cont = types.toObject(callee).as(types.Continuation);
                        const value = if (nargs == 0) types.VOID else self.registers[abs_base + 1];
                        if (cont.is_escape) {
                            try self.invokeEscape(cont, value);
                        } else {
                            try self.performWindTransition(cont.wind_records[0..cont.wind_count], cont.wind_count);
                            try self.restoreContinuation(cont, value);
                        }
                        if (target_frame_count == 0) {
                            continue;
                        }
                        return VMError.ContinuationInvoked;
                    } else if (types.isFfiFunction(callee)) {
                        const ffi_fn = types.toObject(callee).as(types.FfiFunction);
                        if (nargs != ffi_fn.param_count) return VMError.ArityMismatch;
                        const ffi_mod = @import("ffi.zig");
                        const result = ffi_mod.callFfi(ffi_fn, self.registers[abs_base + 1 .. abs_base + 1 + nargs], self.gc) catch return VMError.TypeError;
                        const return_dst = frame.dst;
                        self.frame_count -= 1;
                        if (self.frame_count <= target_frame_count) {
                            return result;
                        }
                        const caller = &self.frames[self.frame_count - 1];
                        const ret_idx = try self.registerIndex(caller.base, return_dst);
                        self.registers[ret_idx] = result;
                    } else if (types.isParameter(callee)) {
                        const param = types.toObject(callee).as(types.ParameterObject);
                        const result = if (nargs == 0) self.getParameterValue(param) else blk: {
                            var new_val = self.registers[abs_base + 1];
                            if (param.converter != types.NIL) {
                                new_val = self.callWithArgs(param.converter, &[_]Value{new_val}) catch |err| return err;
                            }
                            self.setParameterValue(param, new_val);
                            break :blk types.VOID;
                        };
                        const return_dst = frame.dst;
                        self.frame_count -= 1;
                        if (self.frame_count <= target_frame_count) {
                            return result;
                        }
                        const caller = &self.frames[self.frame_count - 1];
                        const ret_idx = try self.registerIndex(caller.base, return_dst);
                        self.registers[ret_idx] = result;
                    } else {
                        self.setErrorDetail("not a procedure", .{});
                        return VMError.NotAProcedure;
                    }
                },
                .tail_apply => {
                    const base_reg = self.readU8(frame);
                    const nargs = self.readU8(frame);
                    if (nargs == 0) return VMError.InvalidBytecode;
                    const abs_base = frame.base + @as(u16, base_reg);
                    try self.ensureCallWindow(abs_base, nargs);
                    const proc = self.registers[abs_base];

                    var flat_args: [256]Value = undefined;
                    var count: usize = 0;

                    // Copy fixed args (all except last, which is the list)
                    if (nargs > 1) {
                        var fi: u8 = 0;
                        while (fi < nargs - 1) : (fi += 1) {
                            if (count >= 255) return VMError.StackOverflow;
                            flat_args[count] = self.registers[abs_base + 1 + fi];
                            count += 1;
                        }
                    }

                    // Unpack trailing list
                    var rest = self.registers[abs_base + @as(u16, nargs)];
                    while (rest != types.NIL) {
                        if (!types.isPair(rest)) {
                            self.setErrorDetail("apply: last argument must be a list", .{});
                            return VMError.TypeError;
                        }
                        if (count >= 255) return VMError.StackOverflow;
                        flat_args[count] = types.car(rest);
                        count += 1;
                        rest = types.cdr(rest);
                    }

                    if (types.isClosure(proc)) {
                        const closure = types.toObject(proc).as(types.Closure);
                        const func = closure.func;
                        if (count > std.math.maxInt(u8)) return VMError.StackOverflow;
                        const total_nargs: u8 = @intCast(count);

                        if (!func.is_variadic) {
                            if (total_nargs != func.arity) {
                                self.setErrorDetail("expected {d} arguments, got {d}", .{ func.arity, total_nargs });
                                return VMError.ArityMismatch;
                            }
                        } else {
                            if (total_nargs < func.arity) {
                                self.setErrorDetail("expected at least {d} arguments, got {d}", .{ func.arity, total_nargs });
                                return VMError.ArityMismatch;
                            }
                            const rest_start = func.arity;
                            var rest_list: Value = types.NIL;
                            var ri: u8 = total_nargs;
                            while (ri > rest_start) {
                                ri -= 1;
                                rest_list = self.gc.allocPair(flat_args[ri], rest_list) catch return VMError.OutOfMemory;
                            }
                            flat_args[rest_start] = rest_list;
                        }

                        const arg_count: u8 = if (func.is_variadic) func.arity + 1 else total_nargs;
                        for (0..arg_count) |i| {
                            const dst_idx = @as(usize, frame.base) + i;
                            if (dst_idx >= MAX_REGISTERS) return VMError.InvalidBytecode;
                            self.registers[dst_idx] = flat_args[i];
                        }

                        frame.closure = closure;
                        frame.code = func.code.items;
                        frame.ip = 0;
                    } else if (types.isNativeFn(proc)) {
                        const native = types.toObject(proc).as(types.NativeFn);
                        const result = native.func(flat_args[0..count]) catch |err| {
                            if (err == error.ContinuationInvoked) {
                                if (target_frame_count == 0) continue;
                                return VMError.ContinuationInvoked;
                            }
                            return switch (err) {
                                error.TypeError => VMError.TypeError,
                                error.OutOfMemory => VMError.OutOfMemory,
                                error.ExceptionRaised => VMError.ExceptionRaised,
                                else => VMError.InvalidBytecode,
                            };
                        };
                        const return_dst = frame.dst;
                        self.frame_count -= 1;
                        if (self.frame_count <= target_frame_count) return result;
                        const caller = &self.frames[self.frame_count - 1];
                        const ret_idx = try self.registerIndex(caller.base, return_dst);
                        self.registers[ret_idx] = result;
                    } else if (types.isContinuation(proc)) {
                        const cont = types.toObject(proc).as(types.Continuation);
                        const value = if (count == 0) types.VOID else flat_args[0];
                        if (cont.is_escape) {
                            try self.invokeEscape(cont, value);
                        } else {
                            try self.performWindTransition(cont.wind_records[0..cont.wind_count], cont.wind_count);
                            try self.restoreContinuation(cont, value);
                        }
                        if (target_frame_count == 0) continue;
                        return VMError.ContinuationInvoked;
                    } else {
                        self.setErrorDetail("apply: not a procedure", .{});
                        return VMError.NotAProcedure;
                    }
                },
                .@"return" => {
                    const src = self.readU8(frame);
                    const src_idx = try self.registerIndex(frame.base, src);
                    const result = self.registers[src_idx];
                    const return_dst = frame.dst;
                    const frame_wind = frame.saved_wind_count;
                    self.frame_count -= 1;
                    if (self.profile_mode) self.profilePopReturn();
                    // Unwind dynamic-wind records established in this frame
                    while (self.wind_count > frame_wind) {
                        self.wind_count -= 1;
                        _ = self.callThunk(self.wind_stack[self.wind_count].after) catch {};
                    }
                    if (self.frame_count <= target_frame_count) {
                        while (self.wind_count > target_wind_count) {
                            self.wind_count -= 1;
                            _ = self.callThunk(self.wind_stack[self.wind_count].after) catch {};
                        }
                        return result;
                    }
                    // Also unwind any winds that were pushed by native
                    // functions (e.g. dynamic-wind) between this frame
                    // and the caller. After a continuation restore the
                    // native function isn't on the Zig stack, so its
                    // cleanup won't run. The caller's saved_wind_count
                    // tells us the correct wind level to unwind to.
                    const caller = &self.frames[self.frame_count - 1];
                    while (self.wind_count > caller.saved_wind_count) {
                        self.wind_count -= 1;
                        _ = self.callThunk(self.wind_stack[self.wind_count].after) catch {};
                    }
                    const ret_idx = try self.registerIndex(caller.base, return_dst);
                    self.registers[ret_idx] = result;
                },
                .closure => {
                    const dst = self.readU8(frame);
                    const idx = self.readU16(frame);
                    const parent_closure = frame.closure orelse return VMError.InvalidBytecode;
                    const func_val = try self.constantAt(parent_closure.func, idx);
                    if (!types.isFunction(func_val)) return VMError.InvalidBytecode;
                    const func = types.toObject(func_val).as(types.Function);

                    const cls_val = self.gc.allocClosure(func) catch return VMError.OutOfMemory;
                    const cls = types.toObject(cls_val).as(types.Closure);

                    for (cls.upvalues, 0..) |_, i| {
                        try self.ensureOperands(frame, 2);
                        const is_local = frame.code[frame.ip] == 1;
                        frame.ip += 1;
                        const index = frame.code[frame.ip];
                        frame.ip += 1;

                        if (is_local) {
                            const local_idx = try self.registerIndex(frame.base, index);
                            var val = self.registers[local_idx];
                            if (!types.isPair(val) or types.cdr(val) != types.VOID) {
                                const box = self.gc.allocPair(val, types.VOID) catch return VMError.OutOfMemory;
                                self.registers[local_idx] = box;
                                val = box;
                            }
                            cls.upvalues[i] = val;
                        } else {
                            const pc = parent_closure;
                            if (index >= pc.upvalues.len) return VMError.InvalidBytecode;
                            cls.upvalues[i] = pc.upvalues[index];
                        }
                    }

                    const dst_idx = try self.registerIndex(frame.base, dst);
                    self.registers[dst_idx] = cls_val;
                },
                .close_upvalue => {
                    _ = self.readU8(frame);
                },
                .cons => {
                    const dst = self.readU8(frame);
                    const car_reg = self.readU8(frame);
                    const cdr_reg = self.readU8(frame);
                    const dst_idx = try self.registerIndex(frame.base, dst);
                    const car_idx = try self.registerIndex(frame.base, car_reg);
                    const cdr_idx = try self.registerIndex(frame.base, cdr_reg);
                    const pair = self.gc.allocPair(
                        self.registers[car_idx],
                        self.registers[cdr_idx],
                    ) catch return VMError.OutOfMemory;
                    self.registers[dst_idx] = pair;
                },
                .push_handler => {
                    const handler_reg = self.readU8(frame);
                    const handler_idx = try self.registerIndex(frame.base, handler_reg);
                    const handler_val = self.registers[handler_idx];
                    try self.pushHandler(handler_val);
                },
                .pop_handler => {
                    self.popHandler();
                },
                .halt => {
                    return types.VOID;
                },
                .call_global => {
                    const base_reg = self.readU8(frame);
                    const sym_idx = self.readU16(frame);
                    const nargs = self.readU8(frame);
                    const the_closure = frame.closure orelse return VMError.InvalidBytecode;
                    const the_func = the_closure.func;
                    const env: *std.StringHashMap(Value) = the_func.env orelse &self.globals;
                    const base = frame.base + base_reg;
                    try self.ensureCallWindow(base, nargs);

                    if (the_func.env == null) {
                        if (the_func.global_cache) |cache| {
                            if (the_func.cache_version == self.global_version and
                                sym_idx < cache.len and cache[sym_idx] != types.VOID)
                            {
                                self.registers[base] = cache[sym_idx];
                            } else {
                                const sym = try self.constantAt(the_func, sym_idx);
                                if (!types.isSymbol(sym)) return VMError.InvalidBytecode;
                                const name = types.symbolName(sym);
                                const val = env.get(name) orelse {
                                    self.setErrorDetail("undefined variable '{s}'", .{name});
                                    return VMError.UndefinedVariable;
                                };
                                self.registers[base] = val;
                                if (types.isClosure(val) or types.isNativeFn(val)) {
                                    if (sym_idx < cache.len) cache[sym_idx] = val;
                                }
                            }
                        } else {
                            const sym = try self.constantAt(the_func, sym_idx);
                            if (!types.isSymbol(sym)) return VMError.InvalidBytecode;
                            const name = types.symbolName(sym);
                            const val = env.get(name) orelse {
                                self.setErrorDetail("undefined variable '{s}'", .{name});
                                return VMError.UndefinedVariable;
                            };
                            self.registers[base] = val;
                            if (types.isClosure(val) or types.isNativeFn(val)) {
                                const cache = self.gc.allocator.alloc(Value, the_func.constants.items.len) catch {
                                    self.callValue(val, base, nargs) catch |err| {
                                        if (err == VMError.ContinuationInvoked) {
                                            if (target_frame_count == 0) continue;
                                            return VMError.ContinuationInvoked;
                                        }
                                        return err;
                                    };
                                    continue;
                                };
                                @memset(cache, types.VOID);
                                cache[sym_idx] = val;
                                the_func.global_cache = cache;
                            }
                        }
                    } else {
                        const sym = try self.constantAt(the_func, sym_idx);
                        if (!types.isSymbol(sym)) return VMError.InvalidBytecode;
                        const name = types.symbolName(sym);
                        const val = env.get(name) orelse {
                            self.setErrorDetail("undefined variable '{s}'", .{name});
                            return VMError.UndefinedVariable;
                        };
                        self.registers[base] = val;
                    }

                    const callee = self.registers[base];
                    if (types.isNativeFn(callee)) {
                        const native = types.toObject(callee).as(types.NativeFn);
                        const arity_ok = switch (native.arity) {
                            .exact => |expected| nargs == expected,
                            .variadic => |min| nargs >= min,
                        };
                        if (arity_ok and base + @as(u16, nargs) + 1 < MAX_REGISTERS) {
                            const args = self.registers[base + 1 .. base + 1 + nargs];
                            const result = native.func(args) catch |err| {
                                return self.handleNativeError(err, base, nargs);
                            };
                            self.registers[base] = result;
                        } else {
                            self.callNative(native, base, nargs) catch |err| {
                                if (err == VMError.ContinuationInvoked) {
                                    if (target_frame_count == 0) continue;
                                    return VMError.ContinuationInvoked;
                                }
                                return err;
                            };
                        }
                    } else if (types.isClosure(callee)) {
                        self.callClosure(types.toObject(callee).as(types.Closure), base, nargs) catch |err| return err;
                    } else {
                        self.callValue(callee, base, nargs) catch |err| {
                            if (err == VMError.ContinuationInvoked) {
                                if (target_frame_count == 0) continue;
                                return VMError.ContinuationInvoked;
                            }
                            return err;
                        };
                    }
                },
                .tail_call_global => {
                    const base_reg = self.readU8(frame);
                    const sym_idx = self.readU16(frame);
                    const nargs = self.readU8(frame);
                    const closure = frame.closure orelse return VMError.InvalidBytecode;
                    const func = closure.func;
                    const env: *std.StringHashMap(Value) = func.env orelse &self.globals;
                    const abs_base = frame.base + base_reg;
                    try self.ensureCallWindow(abs_base, nargs);

                    var callee: Value = types.VOID;
                    if (func.env == null) {
                        if (func.global_cache) |cache| {
                            if (func.cache_version == self.global_version and
                                sym_idx < cache.len and cache[sym_idx] != types.VOID)
                            {
                                callee = cache[sym_idx];
                            }
                        }
                    }
                    if (callee == types.VOID) {
                        const sym = try self.constantAt(func, sym_idx);
                        if (!types.isSymbol(sym)) return VMError.InvalidBytecode;
                        const name = types.symbolName(sym);
                        callee = env.get(name) orelse {
                            self.setErrorDetail("undefined variable '{s}'", .{name});
                            return VMError.UndefinedVariable;
                        };
                        if (func.env == null and (types.isClosure(callee) or types.isNativeFn(callee))) {
                            if (func.global_cache) |cache| {
                                if (sym_idx < cache.len) cache[sym_idx] = callee;
                            } else {
                                const cache = self.gc.allocator.alloc(Value, func.constants.items.len) catch {
                                    return VMError.OutOfMemory;
                                };
                                @memset(cache, types.VOID);
                                cache[sym_idx] = callee;
                                func.global_cache = cache;
                            }
                        }
                    }

                    self.registers[abs_base] = callee;

                    // Reuse tail_call logic for closures
                    if (types.isClosure(callee)) {
                        const tclosure = types.toObject(callee).as(types.Closure);
                        const tfunc = tclosure.func;
                        if (!tfunc.is_variadic) {
                            if (nargs != tfunc.arity) {
                                self.setErrorDetail("expected {d} arguments, got {d}", .{ tfunc.arity, nargs });
                                return VMError.ArityMismatch;
                            }
                        } else {
                            if (nargs < tfunc.arity) return VMError.ArityMismatch;
                            const rest_start = tfunc.arity;
                            if (@as(usize, abs_base) + @as(usize, rest_start) + 1 >= MAX_REGISTERS) {
                                return VMError.InvalidBytecode;
                            }
                            var rest_list: Value = types.NIL;
                            var ri: u8 = nargs;
                            while (ri > rest_start) {
                                ri -= 1;
                                rest_list = self.gc.allocPair(
                                    self.registers[abs_base + 1 + ri], rest_list,
                                ) catch return VMError.OutOfMemory;
                            }
                            self.registers[abs_base + 1 + rest_start] = rest_list;
                        }
                        const arg_count = if (tfunc.is_variadic) tfunc.arity + 1 else nargs;
                        for (0..arg_count) |ai| {
                            const dst_idx = @as(usize, frame.base) + ai;
                            const src_idx = @as(usize, abs_base) + 1 + ai;
                            if (dst_idx >= MAX_REGISTERS or src_idx >= MAX_REGISTERS) {
                                return VMError.InvalidBytecode;
                            }
                            self.registers[dst_idx] = self.registers[src_idx];
                        }
                        if (self.profile_mode) {
                            tfunc.profile_calls += 1;
                            self.profileTailCall(tfunc);
                        }
                        frame.closure = tclosure;
                        frame.code = tfunc.code.items;
                        frame.ip = 0;
                    } else if (types.isNativeFn(callee)) {
                        const native = types.toObject(callee).as(types.NativeFn);
                        const args = self.registers[abs_base + 1 .. abs_base + 1 + nargs];
                        const result = if (!self.profile_mode)
                            native.func(args) catch |err| {
                                return self.handleNativeError(err, abs_base, nargs);
                            }
                        else blk: {
                            native.profile_calls += 1;
                            const saved_alloc_target = self.gc.profile_alloc_target;
                            self.profileCreditSelf();
                            self.gc.profile_alloc_target = &native.profile_alloc_bytes;
                            const native_start = clockNs();
                            self.last_error_detail_len = 0;
                            const r = native.func(args) catch |err| {
                                native.profile_time_ns +%= clockNs() -% native_start;
                                self.profile_last_ns = clockNs();
                                self.gc.profile_alloc_target = saved_alloc_target;
                                return switch (err) {
                                    error.TypeError => b2: {
                                        if (self.last_error_detail_len == 0)
                                            self.setErrorDetail("type error in '{s}'", .{native.name});
                                        break :b2 VMError.TypeError;
                                    },
                                    error.OutOfMemory => VMError.OutOfMemory,
                                    error.ExceptionRaised => VMError.ExceptionRaised,
                                    error.ContinuationInvoked => VMError.ContinuationInvoked,
                                    else => VMError.InvalidBytecode,
                                };
                            };
                            native.profile_time_ns +%= clockNs() -% native_start;
                            self.profile_last_ns = clockNs();
                            self.gc.profile_alloc_target = saved_alloc_target;
                            break :blk r;
                        };
                        const return_dst = frame.dst;
                        self.frame_count -= 1;
                        if (self.profile_mode) self.profilePopReturn();
                        if (self.frame_count <= target_frame_count) return result;
                        const caller = &self.frames[self.frame_count - 1];
                        const ret_idx = try self.registerIndex(caller.base, return_dst);
                        self.registers[ret_idx] = result;
                    } else {
                        self.setErrorDetail("not a procedure", .{});
                        return VMError.NotAProcedure;
                    }
                },
                .box_local => {
                    const reg = self.readU8(frame);
                    const reg_idx = try self.registerIndex(frame.base, reg);
                    const val = self.registers[reg_idx];
                    const box = self.gc.allocPair(val, types.VOID) catch return VMError.OutOfMemory;
                    self.registers[reg_idx] = box;
                },
                .get_box_local => {
                    const dst_r = self.readU8(frame);
                    const reg = self.readU8(frame);
                    const dst_idx = try self.registerIndex(frame.base, dst_r);
                    const reg_idx = try self.registerIndex(frame.base, reg);
                    const val = self.registers[reg_idx];
                    if (types.isPair(val) and types.cdr(val) == types.VOID) {
                        self.registers[dst_idx] = types.car(val);
                    } else {
                        const box = self.gc.allocPair(val, types.VOID) catch return VMError.OutOfMemory;
                        self.registers[reg_idx] = box;
                        self.registers[dst_idx] = val;
                    }
                },
                .set_box_local => {
                    const reg = self.readU8(frame);
                    const src = self.readU8(frame);
                    const reg_idx = try self.registerIndex(frame.base, reg);
                    const src_idx = try self.registerIndex(frame.base, src);
                    const val = self.registers[reg_idx];
                    if (types.isPair(val) and types.cdr(val) == types.VOID) {
                        types.setCar(val, self.registers[src_idx]);
                    } else {
                        const box = self.gc.allocPair(self.registers[src_idx], types.VOID) catch return VMError.OutOfMemory;
                        self.registers[reg_idx] = box;
                    }
                },
                .self_tail_call => {
                    const base_reg = self.readU8(frame);
                    const nargs = self.readU8(frame);
                    const abs_base = frame.base + base_reg;
                    try self.ensureCallWindow(abs_base, nargs);
                    // Copy args to frame base (no callee register to skip)
                    for (0..nargs) |i| {
                        const dst_idx = @as(usize, frame.base) + i;
                        const src_idx = @as(usize, abs_base) + 1 + i;
                        if (dst_idx >= MAX_REGISTERS or src_idx >= MAX_REGISTERS) {
                            return VMError.InvalidBytecode;
                        }
                        self.registers[dst_idx] = self.registers[src_idx];
                    }
                    if (self.profile_mode) {
                        if (frame.closure) |cl| {
                            cl.func.profile_calls += 1;
                        }
                        self.profileCreditSelf();
                    }
                    frame.ip = 0;
                },
                else => return VMError.InvalidBytecode,
            }
        }
        return types.VOID;
    }


    pub fn resetExecutionState(self: *VM) void {
        self.frame_count = 0;
        self.handler_count = 0;
        self.wind_count = 0;
        self.current_exception = null;
        self.continuation_invoked = false;
        self.continuation_value = types.VOID;
    }

    fn clockNs() u64 {
        var ts: std.c.timespec = undefined;
        _ = std.c.clock_gettime(.MONOTONIC, &ts);
        return @intCast(@as(i128, ts.sec) * 1_000_000_000 + ts.nsec);
    }

    fn profileCreditSelf(self: *VM) void {
        const now = clockNs();
        const elapsed = now -% self.profile_last_ns;
        if (self.profile_time_depth > 0) {
            if (self.profile_time_stack[self.profile_time_depth - 1].func) |f| {
                f.profile_time_ns +%= elapsed;
            }
        }
        self.profile_last_ns = now;
    }

    fn profilePushCall(self: *VM, func: *types.Function) void {
        const now = clockNs();
        const elapsed = now -% self.profile_last_ns;
        if (self.profile_time_depth > 0) {
            if (self.profile_time_stack[self.profile_time_depth - 1].func) |f| {
                f.profile_time_ns +%= elapsed;
            }
        }
        if (self.profile_time_depth < self.profile_time_stack.len) {
            self.profile_time_stack[self.profile_time_depth] = .{
                .func = func,
                .entry_ns = now,
            };
            self.profile_time_depth += 1;
        }
        self.profile_last_ns = now;
        self.gc.profile_alloc_target = &func.profile_alloc_bytes;
    }

    fn profilePopReturn(self: *VM) void {
        const now = clockNs();
        const elapsed = now -% self.profile_last_ns;
        if (self.profile_time_depth > 0) {
            const entry = &self.profile_time_stack[self.profile_time_depth - 1];
            if (entry.func) |f| {
                f.profile_time_ns +%= elapsed;
                f.profile_inclusive_ns +%= now -% entry.entry_ns;
            }
            self.profile_time_depth -= 1;
        }
        self.profile_last_ns = now;
        if (self.profile_time_depth > 0) {
            if (self.profile_time_stack[self.profile_time_depth - 1].func) |f| {
                self.gc.profile_alloc_target = &f.profile_alloc_bytes;
            } else {
                self.gc.profile_alloc_target = null;
            }
        } else {
            self.gc.profile_alloc_target = null;
        }
    }

    fn profileTailCall(self: *VM, new_func: *types.Function) void {
        const now = clockNs();
        const elapsed = now -% self.profile_last_ns;
        if (self.profile_time_depth > 0) {
            const entry = &self.profile_time_stack[self.profile_time_depth - 1];
            if (entry.func) |f| {
                f.profile_time_ns +%= elapsed;
                f.profile_inclusive_ns +%= now -% entry.entry_ns;
            }
            entry.func = new_func;
            entry.entry_ns = now;
        }
        self.profile_last_ns = now;
        self.gc.profile_alloc_target = &new_func.profile_alloc_bytes;
    }

    pub fn execute(self: *VM, func: *types.Function) VMError!Value {
        vm_instance = self;
        self.resetExecutionState();

        // Create a top-level closure
        const closure_val = self.gc.allocClosure(func) catch return VMError.OutOfMemory;
        const closure = types.toObject(closure_val).as(types.Closure);

        // Push initial frame
        self.frames[0] = .{
            .closure = closure,
            .code = func.code.items,
            .ip = 0,
            .base = 0,
            .dst = 0,
            .saved_wind_count = 0,
        };
        self.frame_count = 1;

        if (self.profile_mode) {
            self.profile_time_depth = 1;
            self.profile_time_stack[0] = .{ .func = func, .entry_ns = clockNs() };
            self.profile_last_ns = self.profile_time_stack[0].entry_ns;
            self.gc.profile_alloc_target = &func.profile_alloc_bytes;
        }

        const result = self.run() catch |err| {
            self.last_stack_trace_len = self.getStackTrace(&self.last_stack_trace);
            if (self.profile_mode) {
                self.profile_time_depth = 0;
                self.gc.profile_alloc_target = null;
            }
            self.resetExecutionState();
            return err;
        };
        if (self.profile_mode) {
            self.profileCreditSelf();
            self.profile_time_depth = 0;
            self.gc.profile_alloc_target = null;
        }
        self.last_stack_trace_len = 0;
        self.resetExecutionState();
        return result;
    }

    pub fn run(self: *VM) VMError!Value {
        if (self.scheduler) |sched| {
            return self.runWithScheduler(sched);
        }
        return self.runUntil(0, 0);
    }

    fn runWithScheduler(self: *VM, sched: *@import("fiber.zig").FiberScheduler) VMError!Value {
        while (true) {
            const result = self.runUntil(0, 0) catch |err| {
                if (err == VMError.Yielded) {
                    const current = sched.fibers[sched.current_idx] orelse return VMError.InvalidBytecode;
                    sched.saveCurrentFiber();

                    if (current.status == .running) current.status = .suspended;

                    if (current.status == .completed or current.status == .errored) {
                        sched.wakeWaiters(current);
                    }

                    if (sched.schedule()) |next_idx| {
                        sched.switchTo(next_idx);
                        continue;
                    }
                    if (sched.fibers[0]) |main_fiber| {
                        if (main_fiber.status == .completed) return main_fiber.result;
                        if (main_fiber.status == .waiting) {
                            const target_val = main_fiber.waiting_on;
                            if (types.isFiber(target_val)) {
                                const target = types.toObject(target_val).as(@import("fiber.zig").Fiber);
                                if (target.status == .completed) {
                                    main_fiber.result = target.result;
                                    main_fiber.status = .suspended;
                                    sched.restoreFiber(0);
                                    sched.current_idx = 0;
                                    self.current_fiber = main_fiber;
                                    main_fiber.status = .running;
                                    continue;
                                }
                            }
                        }
                    }
                    return types.VOID;
                }
                return err;
            };

            const current = sched.fibers[sched.current_idx] orelse return result;
            current.status = .completed;
            current.result = result;
            sched.saveCurrentFiber();
            sched.wakeWaiters(current);

            if (sched.current_idx == 0) return result;

            if (sched.schedule()) |next_idx| {
                sched.switchTo(next_idx);
                continue;
            }
            return result;
        }
    }

    /// Restore a captured continuation (delegates to vm_continuations).
    pub fn restoreContinuation(self: *VM, cont: *types.Continuation, value: Value) VMError!void {
        try vm_continuations.restoreContinuation(self, cont, value);
    }

    fn handleNativeError(self: *VM, err: anyerror, base: u16, nargs: u8) VMError {
        _ = base;
        _ = nargs;
        return switch (err) {
            error.TypeError => VMError.TypeError,
            error.OutOfMemory => VMError.OutOfMemory,
            error.ExceptionRaised => VMError.ExceptionRaised,
            error.ContinuationInvoked => VMError.ContinuationInvoked,
            else => blk: {
                self.setErrorDetail("native function error", .{});
                break :blk VMError.TypeError;
            },
        };
    }

    fn callValue(self: *VM, callee: Value, base: u16, nargs: u8) VMError!void {
        // Check closure first — by far the most common case in Scheme programs
        if (types.isClosure(callee)) {
            return self.callClosure(types.toObject(callee).as(types.Closure), base, nargs);
        }
        if (types.isNativeFn(callee)) {
            return self.callNative(types.toObject(callee).as(types.NativeFn), base, nargs);
        }
        if (types.isFfiFunction(callee)) {
            const ffi_fn = types.toObject(callee).as(types.FfiFunction);
            if (nargs != ffi_fn.param_count) return VMError.ArityMismatch;
            const ffi_mod = @import("ffi.zig");
            const result = ffi_mod.callFfi(ffi_fn, self.registers[base + 1 .. base + 1 + nargs], self.gc) catch return VMError.TypeError;
            self.registers[base] = result;
            return;
        }
        if (types.isParameter(callee)) {
            const param = types.toObject(callee).as(types.ParameterObject);
            if (nargs == 0) {
                self.registers[base] = self.getParameterValue(param);
            } else {
                var new_val = self.registers[base + 1];
                if (param.converter != types.NIL) {
                    new_val = self.callWithArgs(param.converter, &[_]Value{new_val}) catch |err| return err;
                }
                self.setParameterValue(param, new_val);
                self.registers[base] = types.VOID;
            }
            return;
        }
        if (types.isContinuation(callee)) {
            const cont = types.toObject(callee).as(types.Continuation);
            // Get the value to pass (0 args => void, 1 arg => that arg)
            const value = if (nargs == 0) types.VOID else self.registers[base + 1];

            if (cont.is_escape) {
                // Escape continuation: unwind the live stack, no snapshot restore.
                try self.invokeEscape(cont, value);
                return VMError.ContinuationInvoked;
            }

            // Handle dynamic-wind: unwind current, rewind to saved
            try self.performWindTransition(cont.wind_records[0..cont.wind_count], cont.wind_count);

            // Restore state and place result
            try self.restoreContinuation(cont, value);

            // Signal to ALL callers that state was replaced
            return VMError.ContinuationInvoked;
        }
        // Remaining cases handled by the closure/native fast paths above
        self.setErrorDetail("not a procedure", .{});
        return VMError.NotAProcedure;
    }

    fn callClosure(self: *VM, closure: *types.Closure, base: u16, nargs: u8) VMError!void {
            const func = closure.func;

            if (base + @as(u16, @max(nargs + 1, func.locals_count)) >= MAX_REGISTERS)
                return VMError.StackOverflow;

            if (!func.is_variadic) {
                if (nargs != func.arity) {
                    self.setErrorDetail("expected {d} arguments, got {d}", .{ func.arity, nargs });
                    return VMError.ArityMismatch;
                }
            } else {
                if (nargs < func.arity) {
                    self.setErrorDetail("expected at least {d} arguments, got {d}", .{ func.arity, nargs });
                    return VMError.ArityMismatch;
                }
                // Collect rest args into a list
                const rest_start = func.arity;
                var rest_list: Value = types.NIL;
                var i: u8 = nargs;
                while (i > rest_start) {
                    i -= 1;
                    rest_list = self.gc.allocPair(
                        self.registers[base + 1 + i],
                        rest_list,
                    ) catch return VMError.OutOfMemory;
                }
                self.registers[base + 1 + rest_start] = rest_list;
            }

            if (self.frame_count >= MAX_FRAMES) return VMError.StackOverflow;

            // The callee is in base, args are in base+1..base+nargs
            // New frame's registers start at base (callee reg becomes r0 for the function)
            const new_base = base + 1; // skip the callee register
            self.frames[self.frame_count] = .{
                .closure = closure,
                .code = func.code.items,
                .ip = 0,
                .base = new_base,
                .dst = @intCast(base - self.frames[self.frame_count - 1].base),
                .saved_wind_count = @intCast(self.wind_count),
            };
            self.frame_count += 1;

            if (self.profile_mode) {
                closure.func.profile_calls += 1;
                self.profilePushCall(closure.func);
            }

            // Breakpoint check: pause if entering a function with a matching name
            if (self.debug_mode and self.breakpoint_count > 0) {
                if (func.name) |fname| {
                    for (self.breakpoints[0..self.breakpoint_count]) |bp| {
                        if (std.mem.eql(u8, bp, fname)) {
                            self.step_mode = .step;
                            break;
                        }
                    }
                }
            }

            // JIT: compile hot functions, execute via native code
            if (!self.debug_mode and !self.jit_disabled) {
                func.call_count +%= 1;
                if (func.jit_code == null and func.call_count == jit.JIT_THRESHOLD) {
                    jit.tryCompile(func, self);
                }
                if (func.jit_code) |jit_code| {
                    const entry: jit.JitEntryFn = @ptrCast(@alignCast(jit_code.entry));
                    const result = entry(self, new_base, func.constants.items.ptr, closure);
                    if (self.jit_error) |err| {
                        self.jit_error = null;
                        return err;
                    }
                    if (result > 0 and result != 0xFFFFFFFF) {
                        self.frames[self.frame_count - 1].ip = result - 1;
                    }
                    return;
                }
            }
    }

    fn callNative(self: *VM, native: *types.NativeFn, base: u16, nargs: u8) VMError!void {
            if (self.profile_mode) {
                native.profile_calls += 1;
            }

            if (base + @as(u16, nargs) + 1 >= MAX_REGISTERS)
                return VMError.StackOverflow;

            switch (native.arity) {
                .exact => |expected| {
                    if (nargs != expected) {
                        self.setErrorDetail("'{s}': expected {d} arguments, got {d}", .{ native.name, expected, nargs });
                        return VMError.ArityMismatch;
                    }
                },
                .variadic => |min| {
                    if (nargs < min) {
                        self.setErrorDetail("'{s}': expected at least {d} arguments, got {d}", .{ native.name, min, nargs });
                        return VMError.ArityMismatch;
                    }
                },
            }

            const saved_alloc_target = self.gc.profile_alloc_target;
            if (self.profile_mode) {
                self.profileCreditSelf();
                self.gc.profile_alloc_target = &native.profile_alloc_bytes;
            }

            const args = self.registers[base + 1 .. base + 1 + nargs];
            self.last_error_detail_len = 0;

            const native_start = if (self.profile_mode) clockNs() else 0;

            const result = native.func(args) catch |err| {
                if (self.profile_mode) {
                    native.profile_time_ns +%= clockNs() -% native_start;
                    self.profile_last_ns = clockNs();
                    self.gc.profile_alloc_target = saved_alloc_target;
                }
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
                        if (self.last_error_detail_len == 0)
                            self.setErrorDetail("invalid argument in '{s}'", .{native.name});
                        break :blk_ia VMError.InvalidArgument;
                    },
                    error.OutOfMemory => VMError.OutOfMemory,
                    error.ExceptionRaised => VMError.ExceptionRaised,
                    error.ContinuationInvoked => VMError.ContinuationInvoked,
                    error.Yielded => VMError.Yielded,
                    else => VMError.InvalidBytecode,
                };
            };

            if (self.profile_mode) {
                native.profile_time_ns +%= clockNs() -% native_start;
                self.profile_last_ns = clockNs();
                self.gc.profile_alloc_target = saved_alloc_target;
            }

            self.registers[base] = result;
    }

    const vm_debug = @import("vm_debug.zig");

    fn shouldDebugPause(self: *VM, frame: *CallFrame) bool {
        return vm_debug.shouldDebugPause(self, frame);
    }

    fn debugPause(self: *VM, frame: *CallFrame) !void {
        return vm_debug.debugPause(self, frame);
    }

    fn ensureOperands(self: *VM, frame: *CallFrame, operand_bytes: usize) VMError!void {
        _ = self;
        if (frame.ip + operand_bytes > frame.code.len) return VMError.InvalidBytecode;
    }

    fn registerIndex(self: *VM, base: u16, reg: u8) VMError!usize {
        _ = self;
        const idx = @as(usize, base) + @as(usize, reg);
        if (idx >= MAX_REGISTERS) return VMError.InvalidBytecode;
        return idx;
    }

    fn ensureCallWindow(self: *VM, base: u16, nargs: u8) VMError!void {
        _ = self;
        const hi = @as(usize, base) + @as(usize, nargs) + 1;
        if (hi > MAX_REGISTERS) return VMError.InvalidBytecode;
    }

    fn constantAt(self: *VM, func: *types.Function, idx: u16) VMError!Value {
        _ = self;
        if (idx >= func.constants.items.len) return VMError.InvalidBytecode;
        return func.constants.items[idx];
    }

    fn readU8(self: *VM, frame: *CallFrame) u8 {
        _ = self;
        const val = frame.code[frame.ip];
        frame.ip += 1;
        return val;
    }

    fn readU16(self: *VM, frame: *CallFrame) u16 {
        _ = self;
        const hi: u16 = frame.code[frame.ip];
        const lo: u16 = frame.code[frame.ip + 1];
        frame.ip += 2;
        return (hi << 8) | lo;
    }

    fn readI16(self: *VM, frame: *CallFrame) i16 {
        return @bitCast(self.readU16(frame));
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
