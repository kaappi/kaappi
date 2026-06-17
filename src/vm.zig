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

    var git = vm.globals.valueIterator();
    while (git.next()) |v| gc.markValue(v.*);
    var mit = vm.macros.valueIterator();
    while (mit.next()) |v| gc.markValue(v.*);

    // Mark library export values (loaded .sld libraries store heap objects)
    var lit = vm.libraries.libraries.valueIterator();
    while (lit.next()) |lib| {
        var eit = lib.exports.valueIterator();
        while (eit.next()) |v| gc.markValue(v.*);
    }
}

const ExceptionHandler = struct {
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
};

pub const StepMode = enum { none, step, next, continue_to_break };

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
    stdin_port: Value = types.VOID,
    stdout_port: Value = types.VOID,
    stderr_port: Value = types.VOID,
    lib_paths: []const []const u8 = &.{},
    loading_libs: std.StringHashMap(void),
    /// Directory of the .sld file currently being loaded, for resolving include paths.
    current_lib_dir: ?[]const u8 = null,
    /// When non-null, handleDefineLibrary collects compiled functions here
    /// for .sbc cache writing. Set by tryLoadLibraryFromFile.
    lib_compile_collect: ?*std.ArrayList(*types.Function) = null,
    last_error_detail: [256]u8 = [_]u8{0} ** 256,
    last_error_detail_len: usize = 0,
    // Debugger state
    debug_mode: bool = false,
    breakpoints: [16][]const u8 = undefined,
    breakpoint_count: usize = 0,
    step_mode: StepMode = .none,
    step_frame: usize = 0,
    global_version: u32 = 0,

    pub fn init(gc: *memory.GC) VM {
        var vm = VM{
            .gc = gc,
            .globals = std.StringHashMap(Value).init(gc.allocator),
            .macros = std.StringHashMap(Value).init(gc.allocator),
            .output = .empty,
            .libraries = library_mod.LibraryRegistry.init(gc.allocator),
            .loading_libs = std.StringHashMap(void).init(gc.allocator),
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
        gc.extra_roots.append(gc.allocator, vm.stdin_port) catch {};
        gc.extra_roots.append(gc.allocator, vm.stdout_port) catch {};
        gc.extra_roots.append(gc.allocator, vm.stderr_port) catch {};
        return vm;
    }

    pub fn deinit(self: *VM) void {
        self.globals.deinit();
        self.macros.deinit();
        self.output.deinit(self.gc.allocator);
        self.libraries.deinit();
        self.loading_libs.deinit();
    }

    pub fn setErrorDetail(self: *VM, comptime fmt: []const u8, args: anytype) void {
        const s = std.fmt.bufPrint(&self.last_error_detail, fmt, args) catch |err| switch (err) {
            error.NoSpaceLeft => {
                self.last_error_detail_len = self.last_error_detail.len;
                return;
            },
        };
        self.last_error_detail_len = s.len;
    }

    pub fn getErrorDetail(self: *VM) []const u8 {
        return self.last_error_detail[0..self.last_error_detail_len];
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
            vm_continuations.performWindTransition(self, cont.wind_records[0..cont.wind_count], cont.wind_count) catch return VMError.OutOfMemory;
            vm_continuations.restoreContinuation(self, cont, arg);
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
            self.frames[self.frame_count] = .{
                .closure = closure,
                .code = func.code.items,
                .ip = 0,
                .base = base,
                .dst = return_dst,
            };
            self.frame_count += 1;

            const result = self.runUntil(saved_frame_count) catch |err| {
                if (err == VMError.ContinuationInvoked) return err;
                self.frame_count = saved_frame_count;
                return err;
            };
            return result;
        } else if (types.isNativeFn(handler_val)) {
            const native = types.toObject(handler_val).as(types.NativeFn);
            const args = [1]Value{arg};
            const result = native.func(&args) catch |err| {
                return switch (err) {
                    error.TypeError => blk: {
                        if (args.len > 0) {
                            const p = @import("printer.zig");
                            const s = p.valueToString(self.gc.allocator, args[0], .write) catch "";
                            defer if (s.len > 0) self.gc.allocator.free(s);
                            self.setErrorDetail("type error in '{s}': got {s}", .{ native.name, s });
                        } else {
                            self.setErrorDetail("type error in '{s}'", .{native.name});
                        }
                        break :blk VMError.TypeError;
                    },
                    error.DivisionByZero => VMError.DivisionByZero,
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
            if (base >= MAX_REGISTERS) return VMError.StackOverflow;

            if (func.is_variadic and func.arity == 0) {
                self.registers[base] = types.NIL;
            }

            if (self.frame_count >= MAX_FRAMES) return VMError.StackOverflow;

            const saved_frame_count = self.frame_count;
            self.frames[self.frame_count] = .{
                .closure = closure,
                .code = func.code.items,
                .ip = 0,
                .base = base,
                .dst = 0,
            };
            self.frame_count += 1;

            const result = self.runUntil(saved_frame_count) catch |err| {
                if (err == VMError.ContinuationInvoked) return err;
                // On error, unwind any frames that were pushed during the thunk
                self.frame_count = saved_frame_count;
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
                return param.value;
            } else {
                var new_val = args[0];
                if (param.converter != types.NIL) {
                    new_val = try self.callWithArgs(param.converter, &[_]Value{new_val});
                }
                param.value = new_val;
                return types.VOID;
            }
        }
        if (types.isContinuation(proc)) {
            const cont = types.toObject(proc).as(types.Continuation);
            const value = if (args.len == 0) types.VOID else args[0];
            vm_continuations.performWindTransition(self, cont.wind_records[0..cont.wind_count], cont.wind_count) catch return VMError.OutOfMemory;
            vm_continuations.restoreContinuation(self, cont, value);
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
            self.frames[self.frame_count] = .{
                .closure = closure,
                .code = func.code.items,
                .ip = 0,
                .base = base,
                .dst = 0,
            };
            self.frame_count += 1;

            const result = self.runUntil(saved_frame_count) catch |err| {
                if (err == VMError.ContinuationInvoked) return err;
                self.frame_count = saved_frame_count;
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
            const result = native.func(args) catch |err| {
                return switch (err) {
                    error.TypeError => blk: {
                        if (args.len > 0) {
                            const p = @import("printer.zig");
                            const s = p.valueToString(self.gc.allocator, args[0], .write) catch "";
                            defer if (s.len > 0) self.gc.allocator.free(s);
                            self.setErrorDetail("type error in '{s}': got {s}", .{ native.name, s });
                        } else {
                            self.setErrorDetail("type error in '{s}'", .{native.name});
                        }
                        break :blk VMError.TypeError;
                    },
                    error.DivisionByZero => VMError.DivisionByZero,
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
    pub fn performWindTransition(self: *VM, target_winds: []const types.WindRecord, target_count: usize) !void {
        return vm_continuations.performWindTransition(self, target_winds, target_count);
    }

    /// Run the VM until frame_count drops to target_frame_count.
    /// This is used by callThunk/callHandler to avoid executing past
    /// the caller's frame.
    fn runUntil(self: *VM, target_frame_count: usize) VMError!Value {
        while (self.frame_count > target_frame_count) {
            const frame = &self.frames[self.frame_count - 1];
            if (frame.ip >= frame.code.len) return VMError.InvalidBytecode;

            const op: OpCode = @enumFromInt(frame.code[frame.ip]);
            frame.ip += 1;

            // Debug hook -- check if we should pause
            if (self.debug_mode) {
                if (self.shouldDebugPause(frame)) {
                    self.debugPause(frame) catch {};
                }
            }

            switch (op) {
                .load_const => {
                    const dst = self.readU8(frame);
                    const idx = self.readU16(frame);
                    const closure = frame.closure orelse return VMError.InvalidBytecode;
                    self.registers[frame.base + dst] = closure.func.constants.items[idx];
                },
                .load_nil => {
                    const dst = self.readU8(frame);
                    self.registers[frame.base + dst] = types.NIL;
                },
                .load_true => {
                    const dst = self.readU8(frame);
                    self.registers[frame.base + dst] = types.TRUE;
                },
                .load_false => {
                    const dst = self.readU8(frame);
                    self.registers[frame.base + dst] = types.FALSE;
                },
                .load_void => {
                    const dst = self.readU8(frame);
                    self.registers[frame.base + dst] = types.VOID;
                },
                .move => {
                    const dst = self.readU8(frame);
                    const src = self.readU8(frame);
                    self.registers[frame.base + dst] = self.registers[frame.base + src];
                },
                .get_global => {
                    const dst = self.readU8(frame);
                    const sym_idx = self.readU16(frame);
                    const closure = frame.closure orelse return VMError.InvalidBytecode;
                    const func = closure.func;
                    if (func.global_cache) |cache| {
                        if (func.cache_version == self.global_version and
                            sym_idx < cache.len and cache[sym_idx] != types.VOID)
                        {
                            self.registers[frame.base + dst] = cache[sym_idx];
                            continue;
                        }
                        // Version mismatch: clear entire cache to avoid stale entries
                        if (func.cache_version != self.global_version) {
                            @memset(cache, types.VOID);
                            func.cache_version = self.global_version;
                        }
                    }
                    const sym = func.constants.items[sym_idx];
                    const name = types.symbolName(sym);
                    const val = self.globals.get(name) orelse {
                        self.setErrorDetail("undefined variable '{s}'", .{name});
                        return VMError.UndefinedVariable;
                    };
                    self.registers[frame.base + dst] = val;
                    if (types.isClosure(val) or types.isNativeFn(val)) {
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
                    const sym = func.constants.items[sym_idx];
                    const name = types.symbolName(sym);
                    const val = self.registers[frame.base + src];
                    self.globals.put(name, val) catch return VMError.OutOfMemory;
                    self.global_version +%= 1;
                    if (func.global_cache) |cache| {
                        if (sym_idx < cache.len) cache[sym_idx] = val;
                        func.cache_version = self.global_version;
                    }
                },
                .get_upvalue => {
                    const dst = self.readU8(frame);
                    const idx = self.readU8(frame);
                    const closure = frame.closure orelse return VMError.InvalidBytecode;
                    self.registers[frame.base + dst] = closure.upvalues[idx];
                },
                .set_upvalue => {
                    const idx = self.readU8(frame);
                    const src = self.readU8(frame);
                    const closure = frame.closure orelse return VMError.InvalidBytecode;
                    closure.upvalues[idx] = self.registers[frame.base + src];
                },
                .jump => {
                    const offset = self.readI16(frame);
                    const new_ip = @as(isize, @intCast(frame.ip)) + offset;
                    frame.ip = @intCast(new_ip);
                },
                .jump_false => {
                    const test_reg = self.readU8(frame);
                    const offset = self.readI16(frame);
                    if (!types.isTruthy(self.registers[frame.base + test_reg])) {
                        const new_ip = @as(isize, @intCast(frame.ip)) + offset;
                        frame.ip = @intCast(new_ip);
                    }
                },
                .jump_true => {
                    const test_reg = self.readU8(frame);
                    const offset = self.readI16(frame);
                    if (types.isTruthy(self.registers[frame.base + test_reg])) {
                        const new_ip = @as(isize, @intCast(frame.ip)) + offset;
                        frame.ip = @intCast(new_ip);
                    }
                },
                .call => {
                    const base_reg = self.readU8(frame);
                    const nargs = self.readU8(frame);
                    const callee = self.registers[frame.base + base_reg];
                    self.callValue(callee, frame.base + base_reg, nargs) catch |err| {
                        if (err == VMError.ContinuationInvoked) {
                            // State was replaced. If we're the outermost runUntil
                            // (target=0), restart the dispatch loop with new state.
                            // Otherwise, propagate up so all nested runUntils unwind.
                            if (target_frame_count == 0) {
                                continue;
                            }
                            return VMError.ContinuationInvoked;
                        }
                        return err;
                    };
                },
                .tail_call => {
                    const base_reg = self.readU8(frame);
                    const nargs = self.readU8(frame);
                    const abs_base = frame.base + base_reg;
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
                            self.registers[frame.base + i] = self.registers[abs_base + 1 + i];
                        }

                        frame.closure = closure;
                        frame.code = func.code.items;
                        frame.ip = 0;
                    } else if (types.isNativeFn(callee)) {
                        const native = types.toObject(callee).as(types.NativeFn);
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
                        const nargs_slice = self.registers[abs_base + 1 .. abs_base + 1 + nargs];
                        const result = native.func(nargs_slice) catch |err| {
                            if (err == error.ContinuationInvoked) {
                                if (target_frame_count == 0) {
                                    continue;
                                }
                                return VMError.ContinuationInvoked;
                            }
                            return switch (err) {
                                error.TypeError => blk: {
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
                        const return_dst = frame.dst;
                        self.frame_count -= 1;
                        if (self.frame_count <= target_frame_count) {
                            return result;
                        }
                        const caller = &self.frames[self.frame_count - 1];
                        self.registers[caller.base + return_dst] = result;
                    } else if (types.isContinuation(callee)) {
                        const cont = types.toObject(callee).as(types.Continuation);
                        const value = if (nargs == 0) types.VOID else self.registers[abs_base + 1];
                        if (cont.is_escape) {
                            try self.invokeEscape(cont, value);
                        } else {
                            self.performWindTransition(cont.wind_records[0..cont.wind_count], cont.wind_count) catch return VMError.OutOfMemory;
                            self.restoreContinuation(cont, value);
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
                        self.registers[caller.base + return_dst] = result;
                    } else if (types.isParameter(callee)) {
                        const param = types.toObject(callee).as(types.ParameterObject);
                        const result = if (nargs == 0) param.value else blk: {
                            var new_val = self.registers[abs_base + 1];
                            if (param.converter != types.NIL) {
                                new_val = self.callWithArgs(param.converter, &[_]Value{new_val}) catch |err| return err;
                            }
                            param.value = new_val;
                            break :blk types.VOID;
                        };
                        const return_dst = frame.dst;
                        self.frame_count -= 1;
                        if (self.frame_count <= target_frame_count) {
                            return result;
                        }
                        const caller = &self.frames[self.frame_count - 1];
                        self.registers[caller.base + return_dst] = result;
                    } else {
                        self.setErrorDetail("not a procedure", .{});
                        return VMError.NotAProcedure;
                    }
                },
                .@"return" => {
                    const src = self.readU8(frame);
                    const result = self.registers[frame.base + src];
                    const return_dst = frame.dst;
                    self.frame_count -= 1;
                    if (self.frame_count <= target_frame_count) {
                        return result;
                    }
                    const caller = &self.frames[self.frame_count - 1];
                    self.registers[caller.base + return_dst] = result;
                },
                .closure => {
                    const dst = self.readU8(frame);
                    const idx = self.readU16(frame);
                    const parent_closure = frame.closure orelse return VMError.InvalidBytecode;
                    const func_val = parent_closure.func.constants.items[idx];
                    const func = types.toObject(func_val).as(types.Function);

                    const cls_val = self.gc.allocClosure(func) catch return VMError.OutOfMemory;
                    const cls = types.toObject(cls_val).as(types.Closure);

                    for (cls.upvalues, 0..) |_, i| {
                        const is_local = frame.code[frame.ip] == 1;
                        frame.ip += 1;
                        const index = frame.code[frame.ip];
                        frame.ip += 1;

                        if (is_local) {
                            cls.upvalues[i] = self.registers[frame.base + index];
                        } else {
                            const pc = parent_closure;
                            cls.upvalues[i] = pc.upvalues[index];
                        }
                    }

                    self.registers[frame.base + dst] = cls_val;
                },
                .close_upvalue => {
                    _ = self.readU8(frame);
                },
                .cons => {
                    const dst = self.readU8(frame);
                    const car_reg = self.readU8(frame);
                    const cdr_reg = self.readU8(frame);
                    const pair = self.gc.allocPair(
                        self.registers[frame.base + car_reg],
                        self.registers[frame.base + cdr_reg],
                    ) catch return VMError.OutOfMemory;
                    self.registers[frame.base + dst] = pair;
                },
                .push_handler => {
                    const handler_reg = self.readU8(frame);
                    const handler_val = self.registers[frame.base + handler_reg];
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
                    const base = frame.base + base_reg;

                    // Resolve global with cache (single dispatch instead of get_global + call)
                    if (the_func.global_cache) |cache| {
                        if (the_func.cache_version == self.global_version and
                            sym_idx < cache.len and cache[sym_idx] != types.VOID)
                        {
                            self.registers[base] = cache[sym_idx];
                        } else {
                            const sym = the_func.constants.items[sym_idx];
                            const name = types.symbolName(sym);
                            const val = self.globals.get(name) orelse {
                                self.setErrorDetail("undefined variable '{s}'", .{name});
                                return VMError.UndefinedVariable;
                            };
                            self.registers[base] = val;
                            if (types.isClosure(val) or types.isNativeFn(val)) {
                                if (sym_idx < cache.len) cache[sym_idx] = val;
                            }
                        }
                    } else {
                        const sym = the_func.constants.items[sym_idx];
                        const name = types.symbolName(sym);
                        const val = self.globals.get(name) orelse {
                            self.setErrorDetail("undefined variable '{s}'", .{name});
                            return VMError.UndefinedVariable;
                        };
                        self.registers[base] = val;
                        if (types.isClosure(val) or types.isNativeFn(val)) {
                            const cache = self.gc.allocator.alloc(Value, the_func.constants.items.len) catch {
                                // Skip caching, still call
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

                    const callee = self.registers[base];
                    self.callValue(callee, base, nargs) catch |err| {
                        if (err == VMError.ContinuationInvoked) {
                            if (target_frame_count == 0) continue;
                            return VMError.ContinuationInvoked;
                        }
                        return err;
                    };
                },
                .tail_call_global => {
                    const base_reg = self.readU8(frame);
                    const sym_idx = self.readU16(frame);
                    const nargs = self.readU8(frame);
                    const closure = frame.closure orelse return VMError.InvalidBytecode;
                    const func = closure.func;
                    const abs_base = frame.base + base_reg;

                    var callee: Value = types.VOID;
                    if (func.global_cache) |cache| {
                        if (func.cache_version == self.global_version and
                            sym_idx < cache.len and cache[sym_idx] != types.VOID)
                        {
                            callee = cache[sym_idx];
                        }
                    }
                    if (callee == types.VOID) {
                        const sym = func.constants.items[sym_idx];
                        const name = types.symbolName(sym);
                        callee = self.globals.get(name) orelse {
                            self.setErrorDetail("undefined variable '{s}'", .{name});
                            return VMError.UndefinedVariable;
                        };
                        if (types.isClosure(callee) or types.isNativeFn(callee)) {
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
                            self.registers[frame.base + ai] = self.registers[abs_base + 1 + ai];
                        }
                        frame.closure = tclosure;
                        frame.code = tfunc.code.items;
                        frame.ip = 0;
                    } else if (types.isNativeFn(callee)) {
                        const native = types.toObject(callee).as(types.NativeFn);
                        const args = self.registers[abs_base + 1 .. abs_base + 1 + nargs];
                        const result = native.func(args) catch |err| {
                            return switch (err) {
                                error.TypeError => blk: {
                                    self.setErrorDetail("type error in '{s}'", .{native.name});
                                    break :blk VMError.TypeError;
                                },
                                error.OutOfMemory => VMError.OutOfMemory,
                                error.ExceptionRaised => VMError.ExceptionRaised,
                                error.ContinuationInvoked => VMError.ContinuationInvoked,
                                else => VMError.InvalidBytecode,
                            };
                        };
                        const return_dst = frame.dst;
                        self.frame_count -= 1;
                        if (self.frame_count <= target_frame_count) return result;
                        const caller = &self.frames[self.frame_count - 1];
                        self.registers[caller.base + return_dst] = result;
                    } else {
                        self.setErrorDetail("not a procedure", .{});
                        return VMError.NotAProcedure;
                    }
                },
                else => return VMError.InvalidBytecode,
            }
        }
        return types.VOID;
    }


    pub fn execute(self: *VM, func: *types.Function) VMError!Value {
        vm_instance = self;

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
        };
        self.frame_count = 1;

        return self.run();
    }

    pub fn run(self: *VM) VMError!Value {
        return self.runUntil(0);
    }

    /// Restore a captured continuation (delegates to vm_continuations).
    pub fn restoreContinuation(self: *VM, cont: *types.Continuation, value: Value) void {
        vm_continuations.restoreContinuation(self, cont, value);
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
                // Get value
                self.registers[base] = param.value;
            } else {
                // Set value (apply converter if present)
                var new_val = self.registers[base + 1];
                if (param.converter != types.NIL) {
                    new_val = self.callWithArgs(param.converter, &[_]Value{new_val}) catch |err| return err;
                }
                param.value = new_val;
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
            self.performWindTransition(cont.wind_records[0..cont.wind_count], cont.wind_count) catch return VMError.OutOfMemory;

            // Restore state and place result
            self.restoreContinuation(cont, value);

            // Signal to ALL callers that state was replaced
            return VMError.ContinuationInvoked;
        }
        // Remaining cases handled by the closure/native fast paths above
        self.setErrorDetail("not a procedure", .{});
        return VMError.NotAProcedure;
    }

    fn callClosure(self: *VM, closure: *types.Closure, base: u16, nargs: u8) VMError!void {
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
            };
            self.frame_count += 1;

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
    }

    fn callNative(self: *VM, native: *types.NativeFn, base: u16, nargs: u8) VMError!void {
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

            const args = self.registers[base + 1 .. base + 1 + nargs];
            const result = native.func(args) catch |err| {
                return switch (err) {
                    error.TypeError => blk: {
                        if (args.len > 0) {
                            const p = @import("printer.zig");
                            const s = p.valueToString(self.gc.allocator, args[0], .write) catch "";
                            defer if (s.len > 0) self.gc.allocator.free(s);
                            self.setErrorDetail("type error in '{s}': got {s}", .{ native.name, s });
                        } else {
                            self.setErrorDetail("type error in '{s}'", .{native.name});
                        }
                        break :blk VMError.TypeError;
                    },
                    error.DivisionByZero => VMError.DivisionByZero,
                    error.OutOfMemory => VMError.OutOfMemory,
                    error.ExceptionRaised => VMError.ExceptionRaised,
                    error.ContinuationInvoked => VMError.ContinuationInvoked,
                    else => VMError.InvalidBytecode,
                };
            };

            self.registers[base] = result;
    }

    const vm_debug = @import("vm_debug.zig");

    fn shouldDebugPause(self: *VM, frame: *CallFrame) bool {
        return vm_debug.shouldDebugPause(self, frame);
    }

    fn debugPause(self: *VM, frame: *CallFrame) !void {
        return vm_debug.debugPause(self, frame);
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
