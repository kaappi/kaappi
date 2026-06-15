const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const compiler_mod = @import("compiler.zig");
const library_mod = @import("library.zig");
const Value = types.Value;
const OpCode = types.OpCode;

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

const MAX_FRAMES = 256;
const MAX_REGISTERS = 1024;
const MAX_HANDLERS = 64;
const MAX_WINDS = 64;

pub var vm_instance: ?*VM = null;

pub fn setVMInstance(vm: *VM) void {
    vm_instance = vm;
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

fn writeStderr(bytes: []const u8) void {
    writeToFd(2, bytes);
}

const CallFrame = struct {
    closure: ?*types.Closure,
    native: ?*types.NativeFn = null,
    code: []const u8,
    ip: usize,
    base: u16,
    dst: u8,
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
    stdin_port: Value = types.VOID,
    stdout_port: Value = types.VOID,
    stderr_port: Value = types.VOID,

    pub fn init(gc: *memory.GC) VM {
        var vm = VM{
            .gc = gc,
            .globals = std.StringHashMap(Value).init(gc.allocator),
            .macros = std.StringHashMap(Value).init(gc.allocator),
            .output = .empty,
            .libraries = library_mod.LibraryRegistry.init(gc.allocator),
        };
        @memset(&vm.registers, types.UNDEFINED);
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
    }

    pub fn defineGlobal(self: *VM, name: []const u8, value: Value) !void {
        try self.globals.put(name, value);
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
    pub fn callHandler(self: *VM, handler_val: Value, arg: Value) VMError!Value {
        if (types.isContinuation(handler_val)) {
            const cont = types.toObject(handler_val).as(types.Continuation);
            self.performWindTransition(cont.wind_records[0..cont.wind_count], cont.wind_count) catch return VMError.OutOfMemory;
            self.restoreContinuation(cont, arg);
            return VMError.ContinuationInvoked;
        }
        if (types.isClosure(handler_val)) {
            const closure = types.toObject(handler_val).as(types.Closure);
            const func = closure.func;

            // Find a safe base register
            const base: u16 = if (self.frame_count > 0)
                self.frames[self.frame_count - 1].base + 200
            else
                0;

            // Set up the argument
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
                .dst = 0,
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

    /// Call a thunk (0-argument procedure), using the VM's call machinery.
    pub fn callThunk(self: *VM, thunk_val: Value) VMError!Value {
        if (types.isClosure(thunk_val)) {
            const closure = types.toObject(thunk_val).as(types.Closure);
            const func = closure.func;

            // Find a safe base register
            const base: u16 = if (self.frame_count > 0)
                self.frames[self.frame_count - 1].base + 200
            else
                0;

            // Handle variadic thunks
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
        if (types.isContinuation(proc)) {
            const cont = types.toObject(proc).as(types.Continuation);
            const value = if (args.len == 0) types.VOID else args[0];
            self.performWindTransition(cont.wind_records[0..cont.wind_count], cont.wind_count) catch return VMError.OutOfMemory;
            self.restoreContinuation(cont, value);
            return VMError.ContinuationInvoked;
        }
        if (types.isClosure(proc)) {
            const closure = types.toObject(proc).as(types.Closure);
            const func = closure.func;

            const base: u16 = if (self.frame_count > 0)
                self.frames[self.frame_count - 1].base + 200
            else
                0;

            // Set up arguments
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
                    if (args.len != expected) return VMError.ArityMismatch;
                },
                .variadic => |min| {
                    if (args.len < min) return VMError.ArityMismatch;
                },
            }
            const result = native.func(args) catch |err| {
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

    /// Capture the current continuation state.
    /// dst_reg is the register offset within the caller's frame where the result of call/cc will go.
    /// dst_base is the base register of the caller's frame.
    pub fn captureContinuation(self: *VM, dst_reg: u8, dst_base: u16) VMError!Value {
        // Determine how many registers are actually in use
        var max_reg: usize = 0;
        for (self.frames[0..self.frame_count]) |f| {
            const frame_end = @as(usize, f.base) + 256; // conservative upper bound
            if (frame_end > max_reg) max_reg = frame_end;
        }
        if (max_reg > MAX_REGISTERS) max_reg = MAX_REGISTERS;
        // At minimum, save up to dst_base + dst_reg + 1
        const min_needed = @as(usize, dst_base) + @as(usize, dst_reg) + 1;
        if (min_needed > max_reg) max_reg = min_needed;

        // Convert frames to SavedFrames
        var saved_frames: [MAX_FRAMES]types.SavedFrame = undefined;
        for (self.frames[0..self.frame_count], 0..) |f, i| {
            saved_frames[i] = .{
                .closure = f.closure,
                .native = f.native,
                .code = f.code,
                .ip = f.ip,
                .base = f.base,
                .dst = f.dst,
            };
        }

        // Convert handlers to SavedHandlers
        var saved_handlers: [MAX_HANDLERS]types.SavedHandler = undefined;
        for (self.handler_stack[0..self.handler_count], 0..) |h, i| {
            saved_handlers[i] = .{
                .handler = h.handler,
                .frame_count = h.frame_count,
            };
        }

        const cont_val = self.gc.allocContinuation(
            self.registers[0..max_reg],
            saved_frames[0..self.frame_count],
            self.frame_count,
            saved_handlers[0..self.handler_count],
            self.handler_count,
            self.wind_stack[0..self.wind_count],
            self.wind_count,
            dst_reg,
            dst_base,
        ) catch return VMError.OutOfMemory;

        return cont_val;
    }

    /// Call a procedure with the current continuation (call/cc).
    /// proc is the one-argument procedure to call with the continuation.
    /// base is the register containing the callee (call/cc itself),
    /// and the result of call/cc will be stored at base.
    pub fn callWithCC(self: *VM, proc: Value, base: u16) VMError!void {
        // The caller's frame is at self.frame_count - 1.
        // After call/cc returns, the result goes into base (relative to caller's frame).
        const caller_frame = &self.frames[self.frame_count - 1];
        const dst_reg: u8 = @intCast(base - caller_frame.base);

        // Capture the continuation. The continuation, when invoked,
        // will restore state and place the value at base (which is
        // caller_frame.base + dst_reg).
        const cont = try self.captureContinuation(dst_reg, caller_frame.base);

        // Now call proc with cont as the argument.
        // We set up: registers[base] = proc, registers[base+1] = cont
        self.registers[base + 1] = cont;

        // Call proc(cont) — just like a normal 1-arg call
        try self.callValue(proc, base, 1);
    }

    /// Perform dynamic-wind transition from current wind stack to target wind stack.
    /// Calls after thunks for unwinding and before thunks for rewinding.
    fn performWindTransition(self: *VM, target_winds: []const types.WindRecord, target_count: usize) !void {
        // Find the common prefix length
        const min_len = @min(self.wind_count, target_count);
        var common: usize = 0;
        while (common < min_len) {
            // Compare by identity (thunk values)
            if (self.wind_stack[common].before != target_winds[common].before or
                self.wind_stack[common].after != target_winds[common].after)
            {
                break;
            }
            common += 1;
        }

        // Unwind: call after thunks from current top down to common
        var i = self.wind_count;
        while (i > common) {
            i -= 1;
            const after = self.wind_stack[i].after;
            _ = self.callThunk(after) catch {};
        }
        self.wind_count = common;

        // Rewind: call before thunks from common up to target
        var j = common;
        while (j < target_count) {
            const before = target_winds[j].before;
            _ = self.callThunk(before) catch {};
            if (self.wind_count < MAX_WINDS) {
                self.wind_stack[self.wind_count] = target_winds[j];
                self.wind_count += 1;
            }
            j += 1;
        }
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
                    const sym = closure.func.constants.items[sym_idx];
                    const name = types.symbolName(sym);
                    self.registers[frame.base + dst] = self.globals.get(name) orelse return VMError.UndefinedVariable;
                },
                .set_global => {
                    const sym_idx = self.readU16(frame);
                    const src = self.readU8(frame);
                    const closure = frame.closure orelse return VMError.InvalidBytecode;
                    const sym = closure.func.constants.items[sym_idx];
                    const name = types.symbolName(sym);
                    self.globals.put(name, self.registers[frame.base + src]) catch return VMError.OutOfMemory;
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

                    if (types.isContinuation(callee)) {
                        const cont = types.toObject(callee).as(types.Continuation);
                        const value = if (nargs == 0) types.VOID else self.registers[abs_base + 1];
                        self.performWindTransition(cont.wind_records[0..cont.wind_count], cont.wind_count) catch return VMError.OutOfMemory;
                        self.restoreContinuation(cont, value);
                        if (target_frame_count == 0) {
                            continue;
                        }
                        return VMError.ContinuationInvoked;
                    } else if (types.isClosure(callee)) {
                        const closure = types.toObject(callee).as(types.Closure);
                        const func = closure.func;

                        if (!func.is_variadic) {
                            if (nargs != func.arity) return VMError.ArityMismatch;
                        } else {
                            if (nargs < func.arity) return VMError.ArityMismatch;
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
                                if (nargs != expected) return VMError.ArityMismatch;
                            },
                            .variadic => |min| {
                                if (nargs < min) return VMError.ArityMismatch;
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
                                error.TypeError => VMError.TypeError,
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
                    } else {
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

    fn restoreContinuation(self: *VM, cont: *types.Continuation, value: Value) void {
        // Restore saved VM state
        @memcpy(self.registers[0..cont.registers.len], cont.registers);
        for (cont.frames[0..cont.frame_count], 0..) |saved_frame, i| {
            self.frames[i] = .{
                .closure = saved_frame.closure,
                .native = saved_frame.native,
                .code = saved_frame.code,
                .ip = saved_frame.ip,
                .base = saved_frame.base,
                .dst = saved_frame.dst,
            };
        }
        self.frame_count = cont.frame_count;

        // Restore handler stack
        for (cont.handlers[0..cont.handler_count], 0..) |saved_handler, i| {
            self.handler_stack[i] = .{
                .handler = saved_handler.handler,
                .frame_count = saved_handler.frame_count,
            };
        }
        self.handler_count = cont.handler_count;

        // Restore wind stack
        for (cont.wind_records[0..cont.wind_count], 0..) |wr, i| {
            self.wind_stack[i] = wr;
        }
        self.wind_count = cont.wind_count;

        // Place the result value where call/cc was waiting for it
        self.registers[cont.dst_base + cont.dst_reg] = value;
    }

    fn callValue(self: *VM, callee: Value, base: u16, nargs: u8) VMError!void {
        if (types.isContinuation(callee)) {
            const cont = types.toObject(callee).as(types.Continuation);
            // Get the value to pass (0 args => void, 1 arg => that arg)
            const value = if (nargs == 0) types.VOID else self.registers[base + 1];

            // Handle dynamic-wind: unwind current, rewind to saved
            self.performWindTransition(cont.wind_records[0..cont.wind_count], cont.wind_count) catch return VMError.OutOfMemory;

            // Restore state and place result
            self.restoreContinuation(cont, value);

            // Signal to ALL callers that state was replaced
            return VMError.ContinuationInvoked;
        }
        if (types.isClosure(callee)) {
            const closure = types.toObject(callee).as(types.Closure);
            const func = closure.func;

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
        } else if (types.isNativeFn(callee)) {
            const native = types.toObject(callee).as(types.NativeFn);
            switch (native.arity) {
                .exact => |expected| {
                    if (nargs != expected) return VMError.ArityMismatch;
                },
                .variadic => |min| {
                    if (nargs < min) return VMError.ArityMismatch;
                },
            }

            const args = self.registers[base + 1 .. base + 1 + nargs];
            const result = native.func(args) catch |err| {
                return switch (err) {
                    error.TypeError => VMError.TypeError,
                    error.DivisionByZero => VMError.DivisionByZero,
                    error.OutOfMemory => VMError.OutOfMemory,
                    error.ExceptionRaised => VMError.ExceptionRaised,
                    error.ContinuationInvoked => VMError.ContinuationInvoked,
                    else => VMError.InvalidBytecode,
                };
            };

            // Store result in the callee's register (base_reg from the call instruction).
            // The compiler emits `call base nargs` and expects the result back in base.
            self.registers[base] = result;
        } else {
            return VMError.NotAProcedure;
        }
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

    // -- High-level eval --

    pub fn eval(self: *VM, source: []const u8) VMError!Value {
        const reader_mod = @import("reader.zig");
        var reader = reader_mod.Reader.init(self.gc, source);
        defer reader.deinit();

        var last_result: Value = types.VOID;
        while (reader.hasMore()) {
            const expr = reader.readDatum() catch return VMError.CompileError;

            // Check for special top-level forms handled by the VM directly
            if (self.handleTopLevelForm(expr)) |result| {
                last_result = result catch |err| return err;
                continue;
            }

            const func = compiler_mod.compileExpressionWithMacros(self.gc, expr, &self.macros) catch return VMError.CompileError;
            // Root the function to prevent GC from collecting it before execute wraps it in a closure
            var func_val = types.makePointer(@ptrCast(func));
            self.gc.pushRoot(&func_val);
            last_result = self.execute(func) catch |err| {
                self.gc.popRoot();
                return err;
            };
            self.gc.popRoot();
        }
        return last_result;
    }

    /// Check if expr is a special top-level form (import, define-library).
    /// Returns null if the form should be compiled normally.
    pub fn handleTopLevelForm(self: *VM, expr: Value) ?VMError!Value {
        if (!types.isPair(expr)) return null;
        const head = types.car(expr);
        if (!types.isSymbol(head)) return null;
        const name = types.symbolName(head);

        if (std.mem.eql(u8, name, "import")) {
            return self.handleImport(types.cdr(expr));
        }
        if (std.mem.eql(u8, name, "define-library")) {
            return self.handleDefineLibrary(types.cdr(expr));
        }
        if (std.mem.eql(u8, name, "define-record-type")) {
            return self.handleDefineRecordType(types.cdr(expr));
        }
        return null;
    }

    /// Handle (import import-set ...)
    /// Each import-set is one of:
    ///   (lib-name ...)          — import all exports
    ///   (only (lib) id ...)     — import only named ids
    ///   (except (lib) id ...)   — import all except named ids
    ///   (prefix (lib) prefix)   — prefix all imported names
    ///   (rename (lib) (old new) ...) — rename on import
    fn handleImport(self: *VM, args: Value) VMError!Value {
        var current = args;
        while (current != types.NIL) {
            if (!types.isPair(current)) return VMError.CompileError;
            const import_set = types.car(current);
            self.processImportSet(import_set) catch return VMError.CompileError;
            current = types.cdr(current);
        }
        return types.VOID;
    }

    fn processImportSet(self: *VM, import_set: Value) !void {
        if (!types.isPair(import_set)) return error.InvalidSyntax;

        const first = types.car(import_set);

        // Check for import modifiers
        if (types.isSymbol(first)) {
            const modifier = types.symbolName(first);

            if (std.mem.eql(u8, modifier, "only")) {
                return self.processImportOnly(types.cdr(import_set));
            }
            if (std.mem.eql(u8, modifier, "except")) {
                return self.processImportExcept(types.cdr(import_set));
            }
            if (std.mem.eql(u8, modifier, "prefix")) {
                return self.processImportPrefix(types.cdr(import_set));
            }
            if (std.mem.eql(u8, modifier, "rename")) {
                return self.processImportRename(types.cdr(import_set));
            }
        }

        // Plain library name: (scheme base) etc.
        const lib_name = library_mod.libraryNameToString(self.gc.allocator, import_set) catch return error.InvalidSyntax;
        defer self.gc.allocator.free(lib_name);

        const lib = self.libraries.get(lib_name) orelse return error.UndefinedVariable;
        var it = lib.exports.iterator();
        while (it.next()) |entry| {
            self.globals.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.OutOfMemory;
        }
    }

    fn processImportOnly(self: *VM, args: Value) !void {
        // (only (lib-name) id ...)
        if (!types.isPair(args)) return error.InvalidSyntax;
        const lib_spec = types.car(args);
        const ids = types.cdr(args);

        const lib_name = library_mod.libraryNameToString(self.gc.allocator, lib_spec) catch return error.InvalidSyntax;
        defer self.gc.allocator.free(lib_name);

        const lib = self.libraries.get(lib_name) orelse return error.UndefinedVariable;

        var id_list = ids;
        while (id_list != types.NIL) {
            if (!types.isPair(id_list)) return error.InvalidSyntax;
            const id = types.car(id_list);
            if (!types.isSymbol(id)) return error.InvalidSyntax;
            const id_name = types.symbolName(id);
            if (lib.exports.get(id_name)) |val| {
                self.globals.put(id_name, val) catch return error.OutOfMemory;
            }
            id_list = types.cdr(id_list);
        }
    }

    fn processImportExcept(self: *VM, args: Value) !void {
        // (except (lib-name) id ...)
        if (!types.isPair(args)) return error.InvalidSyntax;
        const lib_spec = types.car(args);
        const ids = types.cdr(args);

        const lib_name = library_mod.libraryNameToString(self.gc.allocator, lib_spec) catch return error.InvalidSyntax;
        defer self.gc.allocator.free(lib_name);

        const lib = self.libraries.get(lib_name) orelse return error.UndefinedVariable;

        // Collect excluded names
        var excluded: [64][]const u8 = undefined;
        var excluded_count: usize = 0;
        var id_list = ids;
        while (id_list != types.NIL) {
            if (!types.isPair(id_list)) return error.InvalidSyntax;
            const id = types.car(id_list);
            if (!types.isSymbol(id)) return error.InvalidSyntax;
            if (excluded_count < 64) {
                excluded[excluded_count] = types.symbolName(id);
                excluded_count += 1;
            }
            id_list = types.cdr(id_list);
        }

        // Import all except excluded
        var it = lib.exports.iterator();
        while (it.next()) |entry| {
            var is_excluded = false;
            for (excluded[0..excluded_count]) |exc| {
                if (std.mem.eql(u8, entry.key_ptr.*, exc)) {
                    is_excluded = true;
                    break;
                }
            }
            if (!is_excluded) {
                self.globals.put(entry.key_ptr.*, entry.value_ptr.*) catch return error.OutOfMemory;
            }
        }
    }

    fn processImportPrefix(self: *VM, args: Value) !void {
        // (prefix (lib-name) prefix-id)
        if (!types.isPair(args)) return error.InvalidSyntax;
        const lib_spec = types.car(args);
        const rest = types.cdr(args);
        if (!types.isPair(rest)) return error.InvalidSyntax;
        const prefix_sym = types.car(rest);
        if (!types.isSymbol(prefix_sym)) return error.InvalidSyntax;
        const prefix = types.symbolName(prefix_sym);

        const lib_name = library_mod.libraryNameToString(self.gc.allocator, lib_spec) catch return error.InvalidSyntax;
        defer self.gc.allocator.free(lib_name);

        const lib = self.libraries.get(lib_name) orelse return error.UndefinedVariable;

        var it = lib.exports.iterator();
        while (it.next()) |entry| {
            // Create prefixed name by interning a symbol through the GC.
            // This ensures the name string is owned by the GC and won't leak.
            const prefixed_buf = std.fmt.allocPrint(self.gc.allocator, "{s}{s}", .{ prefix, entry.key_ptr.* }) catch return error.OutOfMemory;
            defer self.gc.allocator.free(prefixed_buf);
            // Intern via allocSymbol so the name persists in the symbol table
            const sym = self.gc.allocSymbol(prefixed_buf) catch return error.OutOfMemory;
            const interned_name = types.symbolName(sym);
            self.globals.put(interned_name, entry.value_ptr.*) catch return error.OutOfMemory;
        }
    }

    fn processImportRename(self: *VM, args: Value) !void {
        // (rename (lib-name) (old new) ...)
        if (!types.isPair(args)) return error.InvalidSyntax;
        const lib_spec = types.car(args);
        const renames = types.cdr(args);

        const lib_name = library_mod.libraryNameToString(self.gc.allocator, lib_spec) catch return error.InvalidSyntax;
        defer self.gc.allocator.free(lib_name);

        const lib = self.libraries.get(lib_name) orelse return error.UndefinedVariable;

        // Collect rename mappings
        var rename_old: [32][]const u8 = undefined;
        var rename_new: [32][]const u8 = undefined;
        var rename_count: usize = 0;
        var rename_list = renames;
        while (rename_list != types.NIL) {
            if (!types.isPair(rename_list)) return error.InvalidSyntax;
            const pair = types.car(rename_list);
            if (!types.isPair(pair)) return error.InvalidSyntax;
            const old_sym = types.car(pair);
            const new_rest = types.cdr(pair);
            if (!types.isPair(new_rest)) return error.InvalidSyntax;
            const new_sym = types.car(new_rest);
            if (!types.isSymbol(old_sym) or !types.isSymbol(new_sym)) return error.InvalidSyntax;
            if (rename_count < 32) {
                rename_old[rename_count] = types.symbolName(old_sym);
                rename_new[rename_count] = types.symbolName(new_sym);
                rename_count += 1;
            }
            rename_list = types.cdr(rename_list);
        }

        // Import all exports, applying renames
        var it = lib.exports.iterator();
        while (it.next()) |entry| {
            var imported_name = entry.key_ptr.*;
            for (0..rename_count) |i| {
                if (std.mem.eql(u8, entry.key_ptr.*, rename_old[i])) {
                    imported_name = rename_new[i];
                    break;
                }
            }
            self.globals.put(imported_name, entry.value_ptr.*) catch return error.OutOfMemory;
        }
    }

    /// Handle (define-record-type name (ctor field ...) pred (field accessor [mutator]) ...)
    /// Desugars into define forms using internal record primitives.
    fn handleDefineRecordType(self: *VM, args: Value) VMError!Value {
        // Parse: name
        if (!types.isPair(args)) return VMError.CompileError;
        const type_name_sym = types.car(args);
        if (!types.isSymbol(type_name_sym)) return VMError.CompileError;
        const type_name = types.symbolName(type_name_sym);

        // Parse: (constructor field ...)
        const rest1 = types.cdr(args);
        if (!types.isPair(rest1)) return VMError.CompileError;
        const ctor_spec = types.car(rest1);
        if (!types.isPair(ctor_spec)) return VMError.CompileError;
        const ctor_name_sym = types.car(ctor_spec);
        if (!types.isSymbol(ctor_name_sym)) return VMError.CompileError;
        const ctor_name = types.symbolName(ctor_name_sym);

        // Collect constructor field names (order matters: these are the args to the constructor)
        var ctor_fields: [32][]const u8 = undefined;
        var ctor_field_count: usize = 0;
        var cf = types.cdr(ctor_spec);
        while (cf != types.NIL) {
            if (!types.isPair(cf)) return VMError.CompileError;
            const field_sym = types.car(cf);
            if (!types.isSymbol(field_sym)) return VMError.CompileError;
            if (ctor_field_count >= 32) return VMError.CompileError;
            ctor_fields[ctor_field_count] = types.symbolName(field_sym);
            ctor_field_count += 1;
            cf = types.cdr(cf);
        }

        // Parse: predicate name
        const rest2 = types.cdr(rest1);
        if (!types.isPair(rest2)) return VMError.CompileError;
        const pred_name_sym = types.car(rest2);
        if (!types.isSymbol(pred_name_sym)) return VMError.CompileError;
        const pred_name = types.symbolName(pred_name_sym);

        // Collect all field specs to determine field_names and total field count
        // Field specs: (field-name accessor [mutator])
        var all_field_names: [32][]const u8 = undefined;
        var all_field_count: usize = 0;
        var accessor_names: [32][]const u8 = undefined;
        var mutator_names: [32]?[]const u8 = undefined;

        var field_specs = types.cdr(rest2);
        while (field_specs != types.NIL) {
            if (!types.isPair(field_specs)) return VMError.CompileError;
            const spec = types.car(field_specs);
            if (!types.isPair(spec)) return VMError.CompileError;

            // (field-name accessor [mutator])
            const fname_sym = types.car(spec);
            if (!types.isSymbol(fname_sym)) return VMError.CompileError;
            if (all_field_count >= 32) return VMError.CompileError;
            all_field_names[all_field_count] = types.symbolName(fname_sym);

            const spec_rest = types.cdr(spec);
            if (!types.isPair(spec_rest)) return VMError.CompileError;
            const acc_sym = types.car(spec_rest);
            if (!types.isSymbol(acc_sym)) return VMError.CompileError;
            accessor_names[all_field_count] = types.symbolName(acc_sym);

            // Optional mutator
            const spec_rest2 = types.cdr(spec_rest);
            if (spec_rest2 != types.NIL and types.isPair(spec_rest2)) {
                const mut_sym = types.car(spec_rest2);
                if (!types.isSymbol(mut_sym)) return VMError.CompileError;
                mutator_names[all_field_count] = types.symbolName(mut_sym);
            } else {
                mutator_names[all_field_count] = null;
            }

            all_field_count += 1;
            field_specs = types.cdr(field_specs);
        }

        const num_fields: u8 = @intCast(all_field_count);

        // Create the RecordType value
        var rt_val = self.gc.allocRecordType(type_name, num_fields) catch return VMError.OutOfMemory;
        self.gc.pushRoot(&rt_val);
        defer self.gc.popRoot();

        // Store in a global with an internal name
        const internal_name_buf = std.fmt.allocPrint(self.gc.allocator, "__record_type_{s}", .{type_name}) catch return VMError.OutOfMemory;
        defer self.gc.allocator.free(internal_name_buf);
        // Intern the name via allocSymbol so it persists
        const internal_sym = self.gc.allocSymbol(internal_name_buf) catch return VMError.OutOfMemory;
        const internal_name = types.symbolName(internal_sym);
        self.globals.put(internal_name, rt_val) catch return VMError.OutOfMemory;

        // Map constructor field names to their indices in the all_fields array
        var ctor_field_indices: [32]usize = undefined;
        for (0..ctor_field_count) |ci| {
            var found = false;
            for (0..all_field_count) |fi| {
                if (std.mem.eql(u8, ctor_fields[ci], all_field_names[fi])) {
                    ctor_field_indices[ci] = fi;
                    found = true;
                    break;
                }
            }
            if (!found) return VMError.CompileError;
        }

        // Generate constructor:
        // (define (make-point x y) (%make-record __record_type_point x y))
        // But we need to handle field ordering: constructor args may be in a different order
        // than the field specs. The constructor always creates fields in the field_spec order.
        {
            // Build the body: (%make-record <type> <fields-in-field-order>)
            // For each field in all_fields order, find it in the constructor args
            // Actually: %make-record takes type + field values in order.
            // The constructor needs to map its parameters to field positions.
            // We'll generate:
            //   (define (ctor p1 p2 ...) (%make-record type p_for_field0 p_for_field1 ...))
            // where p_for_fieldN is the constructor param corresponding to field N.

            var body_args: [34]Value = undefined;
            // body_args[0] = %make-record symbol
            body_args[0] = self.gc.allocSymbol("%make-record") catch return VMError.OutOfMemory;
            // body_args[1] = internal_name (the record type reference)
            body_args[1] = self.gc.allocSymbol(internal_name) catch return VMError.OutOfMemory;

            // For each field in order, find its constructor param
            for (0..all_field_count) |fi| {
                var found_in_ctor = false;
                for (0..ctor_field_count) |ci| {
                    if (ctor_field_indices[ci] == fi) {
                        body_args[2 + fi] = self.gc.allocSymbol(ctor_fields[ci]) catch return VMError.OutOfMemory;
                        found_in_ctor = true;
                        break;
                    }
                }
                if (!found_in_ctor) {
                    // Field not provided by constructor. We truncate the args list
                    // here and rely on allocRecordInstance filling remaining slots
                    // with UNDEFINED. This works because we process fields in order
                    // and %make-record handles partial arg lists.
                    // For now, use a quote of void: (quote <void>)
                    // Actually, we can just pass fewer args — allocRecordInstance
                    // handles that. But we need contiguous args, so if a gap exists
                    // in the middle this won't work. For R7RS compliance, constructors
                    // typically initialize all their declared fields.
                    // Simple solution: pre-define __undefined__ global
                    if (!self.globals.contains("__undefined__")) {
                        self.globals.put("__undefined__", types.UNDEFINED) catch return VMError.OutOfMemory;
                    }
                    body_args[2 + fi] = self.gc.allocSymbol("__undefined__") catch return VMError.OutOfMemory;
                }
            }

            const body_list = self.gc.makeList(body_args[0 .. 2 + all_field_count]) catch return VMError.OutOfMemory;

            // Build parameter list
            var param_syms: [32]Value = undefined;
            for (0..ctor_field_count) |ci| {
                param_syms[ci] = self.gc.allocSymbol(ctor_fields[ci]) catch return VMError.OutOfMemory;
            }
            const params = self.gc.makeList(param_syms[0..ctor_field_count]) catch return VMError.OutOfMemory;

            // Build: (define (ctor-name params...) body)
            const define_sym = self.gc.allocSymbol("define") catch return VMError.OutOfMemory;
            const name_and_params = self.gc.allocPair(
                self.gc.allocSymbol(ctor_name) catch return VMError.OutOfMemory,
                params,
            ) catch return VMError.OutOfMemory;
            const define_expr = self.gc.makeList(&[_]Value{ define_sym, name_and_params, body_list }) catch return VMError.OutOfMemory;

            const func = compiler_mod.compileExpressionWithMacros(self.gc, define_expr, &self.macros) catch return VMError.CompileError;
            var func_val = types.makePointer(@ptrCast(func));
            self.gc.pushRoot(&func_val);
            _ = self.execute(func) catch |err| {
                self.gc.popRoot();
                return err;
            };
            self.gc.popRoot();
        }

        // Generate predicate: (define (pred? v) (%record? v __record_type_point))
        {
            const define_sym = self.gc.allocSymbol("define") catch return VMError.OutOfMemory;
            const v_sym = self.gc.allocSymbol("v") catch return VMError.OutOfMemory;
            const pred_sym = self.gc.allocSymbol(pred_name) catch return VMError.OutOfMemory;
            const record_check_sym = self.gc.allocSymbol("%record?") catch return VMError.OutOfMemory;
            const type_ref = self.gc.allocSymbol(internal_name) catch return VMError.OutOfMemory;

            const body = self.gc.makeList(&[_]Value{ record_check_sym, v_sym, type_ref }) catch return VMError.OutOfMemory;
            const name_and_params = self.gc.makeList(&[_]Value{ pred_sym, v_sym }) catch return VMError.OutOfMemory;
            const define_expr = self.gc.makeList(&[_]Value{ define_sym, name_and_params, body }) catch return VMError.OutOfMemory;

            const func = compiler_mod.compileExpressionWithMacros(self.gc, define_expr, &self.macros) catch return VMError.CompileError;
            var func_val = types.makePointer(@ptrCast(func));
            self.gc.pushRoot(&func_val);
            _ = self.execute(func) catch |err| {
                self.gc.popRoot();
                return err;
            };
            self.gc.popRoot();
        }

        // Generate accessors and mutators for each field
        for (0..all_field_count) |fi| {
            // Accessor: (define (accessor p) (%record-ref p <index>))
            {
                const define_sym = self.gc.allocSymbol("define") catch return VMError.OutOfMemory;
                const p_sym = self.gc.allocSymbol("p") catch return VMError.OutOfMemory;
                const acc_sym = self.gc.allocSymbol(accessor_names[fi]) catch return VMError.OutOfMemory;
                const record_ref_sym = self.gc.allocSymbol("%record-ref") catch return VMError.OutOfMemory;
                const idx_val = types.makeFixnum(@intCast(fi));

                const body = self.gc.makeList(&[_]Value{ record_ref_sym, p_sym, idx_val }) catch return VMError.OutOfMemory;
                const name_and_params = self.gc.makeList(&[_]Value{ acc_sym, p_sym }) catch return VMError.OutOfMemory;
                const define_expr = self.gc.makeList(&[_]Value{ define_sym, name_and_params, body }) catch return VMError.OutOfMemory;

                const func = compiler_mod.compileExpressionWithMacros(self.gc, define_expr, &self.macros) catch return VMError.CompileError;
                var func_val = types.makePointer(@ptrCast(func));
                self.gc.pushRoot(&func_val);
                _ = self.execute(func) catch |err| {
                    self.gc.popRoot();
                    return err;
                };
                self.gc.popRoot();
            }

            // Mutator (if specified): (define (mutator p v) (%record-set! p <index> v))
            if (mutator_names[fi]) |mut_name| {
                const define_sym = self.gc.allocSymbol("define") catch return VMError.OutOfMemory;
                const p_sym = self.gc.allocSymbol("p") catch return VMError.OutOfMemory;
                const v_sym = self.gc.allocSymbol("v") catch return VMError.OutOfMemory;
                const mut_sym = self.gc.allocSymbol(mut_name) catch return VMError.OutOfMemory;
                const record_set_sym = self.gc.allocSymbol("%record-set!") catch return VMError.OutOfMemory;
                const idx_val = types.makeFixnum(@intCast(fi));

                const body = self.gc.makeList(&[_]Value{ record_set_sym, p_sym, idx_val, v_sym }) catch return VMError.OutOfMemory;
                const name_and_params = self.gc.makeList(&[_]Value{ mut_sym, p_sym, v_sym }) catch return VMError.OutOfMemory;
                const define_expr = self.gc.makeList(&[_]Value{ define_sym, name_and_params, body }) catch return VMError.OutOfMemory;

                const func = compiler_mod.compileExpressionWithMacros(self.gc, define_expr, &self.macros) catch return VMError.CompileError;
                var func_val = types.makePointer(@ptrCast(func));
                self.gc.pushRoot(&func_val);
                _ = self.execute(func) catch |err| {
                    self.gc.popRoot();
                    return err;
                };
                self.gc.popRoot();
            }
        }

        return types.VOID;
    }

    /// Handle (define-library (name ...) decl ...)
    /// Declarations can be:
    ///   (export id ...)
    ///   (import import-set ...)
    ///   (begin expr ...)
    fn handleDefineLibrary(self: *VM, args: Value) VMError!Value {
        if (!types.isPair(args)) return VMError.CompileError;
        const name_list = types.car(args);
        const decls = types.cdr(args);

        // Convert library name list to canonical string
        const lib_name = library_mod.libraryNameToString(self.gc.allocator, name_list) catch return VMError.CompileError;
        // lib_name is owned by allocator; we need it to persist in the registry.
        // The registry key will reference this string.

        // Collect export names and process declarations
        var export_names: [128][]const u8 = undefined;
        var export_count: usize = 0;

        // First pass: collect exports and process imports/begin
        var decl = decls;
        while (decl != types.NIL) {
            if (!types.isPair(decl)) {
                self.gc.allocator.free(lib_name);
                return VMError.CompileError;
            }
            const declaration = types.car(decl);
            if (!types.isPair(declaration)) {
                self.gc.allocator.free(lib_name);
                return VMError.CompileError;
            }

            const decl_head = types.car(declaration);
            if (!types.isSymbol(decl_head)) {
                self.gc.allocator.free(lib_name);
                return VMError.CompileError;
            }
            const decl_name = types.symbolName(decl_head);

            if (std.mem.eql(u8, decl_name, "export")) {
                // (export id ...)
                var id_list = types.cdr(declaration);
                while (id_list != types.NIL) {
                    if (!types.isPair(id_list)) {
                        self.gc.allocator.free(lib_name);
                        return VMError.CompileError;
                    }
                    const id = types.car(id_list);
                    if (!types.isSymbol(id)) {
                        self.gc.allocator.free(lib_name);
                        return VMError.CompileError;
                    }
                    if (export_count < 128) {
                        export_names[export_count] = types.symbolName(id);
                        export_count += 1;
                    }
                    id_list = types.cdr(id_list);
                }
            } else if (std.mem.eql(u8, decl_name, "import")) {
                // (import import-set ...)
                // Process imports into the current globals (which the begin body will use)
                _ = self.handleImport(types.cdr(declaration)) catch {
                    self.gc.allocator.free(lib_name);
                    return VMError.CompileError;
                };
            } else if (std.mem.eql(u8, decl_name, "begin")) {
                // (begin expr ...)
                // Evaluate expressions in the current environment
                var body = types.cdr(declaration);
                while (body != types.NIL) {
                    if (!types.isPair(body)) {
                        self.gc.allocator.free(lib_name);
                        return VMError.CompileError;
                    }
                    const body_expr = types.car(body);

                    // Check for top-level forms in begin body
                    if (self.handleTopLevelForm(body_expr)) |result| {
                        _ = result catch {
                            self.gc.allocator.free(lib_name);
                            return VMError.CompileError;
                        };
                    } else {
                        const func = compiler_mod.compileExpressionWithMacros(self.gc, body_expr, &self.macros) catch {
                            self.gc.allocator.free(lib_name);
                            return VMError.CompileError;
                        };
                        var func_val = types.makePointer(@ptrCast(func));
                        self.gc.pushRoot(&func_val);
                        _ = self.execute(func) catch |err| {
                            self.gc.popRoot();
                            self.gc.allocator.free(lib_name);
                            return err;
                        };
                        self.gc.popRoot();
                    }

                    body = types.cdr(body);
                }
            }
            // Ignore unknown declarations (include, include-ci, cond-expand, etc.)

            decl = types.cdr(decl);
        }

        // Create the library with exported bindings.
        // Use initOwned so the library takes ownership of lib_name.
        var lib = library_mod.Library.initOwned(self.gc.allocator, lib_name);
        for (export_names[0..export_count]) |exp_name| {
            if (self.globals.get(exp_name)) |val| {
                lib.addExport(exp_name, val) catch {
                    lib.deinit();
                    return VMError.OutOfMemory;
                };
            }
        }

        self.libraries.register(lib) catch {
            lib.deinit();
            return VMError.OutOfMemory;
        };

        return types.VOID;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

const primitives_mod = @import("primitives.zig");

fn makeTestVM(gc: *memory.GC) !VM {
    var vm = VM.init(gc);
    primitives_mod.setGCInstance(gc);
    try primitives_mod.registerAll(&vm);
    try library_mod.registerStandardLibraries(&vm.libraries, &vm.globals);
    return vm;
}

test "eval integer literal" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("42");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "eval boolean" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("#t"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("#f"));
}

test "eval arithmetic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(+ 1 2)");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}

test "eval if true" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(if #t 1 2)");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(result));
}

test "eval if false" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(if #f 1 2)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
}

test "eval define and reference" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define x 42)");
    const result = try vm.eval("x");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "eval lambda and call" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("((lambda (x) (+ x 1)) 41)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "eval define function and call" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define add1 (lambda (x) (+ x 1)))");
    const result = try vm.eval("(add1 10)");
    try std.testing.expectEqual(@as(i64, 11), types.toFixnum(result));
}

test "eval quote" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("'(1 2 3)");
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(result)));
}

test "eval set!" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define x 1)");
    _ = try vm.eval("(set! x 99)");
    const result = try vm.eval("x");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

test "eval begin" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define a 0)");
    _ = try vm.eval("(define b 0)");
    _ = try vm.eval("(begin (set! a 1) (set! b 2))");
    const result = try vm.eval("(+ a b)");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}

test "eval nested arithmetic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(+ (* 2 3) (- 10 4))");
    try std.testing.expectEqual(@as(i64, 12), types.toFixnum(result));
}

test "tail-recursive loop does not overflow" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (loop n) (if (= n 0) (quote done) (loop (- n 1))))");
    const result = try vm.eval("(loop 1000000)");
    try std.testing.expect(types.isSymbol(result));
    try std.testing.expectEqualStrings("done", types.symbolName(result));
}

test "tail-recursive factorial with accumulator" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (fact n acc) (if (= n 0) acc (fact (- n 1) (* n acc))))");
    const result = try vm.eval("(fact 10 1)");
    try std.testing.expectEqual(@as(i64, 3628800), types.toFixnum(result));
}

test "mutual tail recursion" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (my-even? n) (if (= n 0) #t (my-odd? (- n 1))))");
    _ = try vm.eval("(define (my-odd? n) (if (= n 0) #f (my-even? (- n 1))))");
    const result = try vm.eval("(my-even? 10000)");
    try std.testing.expectEqual(types.TRUE, result);
}

test "non-tail recursion still works" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (fib n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))");
    const result = try vm.eval("(fib 10)");
    try std.testing.expectEqual(@as(i64, 55), types.toFixnum(result));
}

test "tail call in begin" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define (count n) (if (= n 0) 0 (begin (count (- n 1)))))");
    const result = try vm.eval("(count 100000)");
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(result));
}

// ---------------------------------------------------------------------------
// Phase 3: Derived expression forms
// ---------------------------------------------------------------------------

test "eval and" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(and)"));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(try vm.eval("(and 1 2 3)")));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(and 1 #f 3)"));
}

test "eval or" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.FALSE, try vm.eval("(or)"));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try vm.eval("(or 1 2)")));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(try vm.eval("(or #f #f 3)")));
}

test "eval when and unless" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.VOID, try vm.eval("(when #t 42)"));
    try std.testing.expectEqual(types.VOID, try vm.eval("(when #f 42)"));
    try std.testing.expectEqual(types.VOID, try vm.eval("(unless #f 42)"));
    try std.testing.expectEqual(types.VOID, try vm.eval("(unless #t 42)"));
}

test "eval cond" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try vm.eval("(cond (#t 1))")));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try vm.eval("(cond (#f 1) (else 2))")));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try vm.eval("(cond (#f 1) (#t 2) (else 3))")));
}

test "eval let" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(try vm.eval("(let ((x 1) (y 2)) (+ x y))")));
}

test "eval let*" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try vm.eval("(let* ((x 1) (y (+ x 1))) y)")));
}

test "eval letrec" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(letrec ((f (lambda (n) (if (= n 0) 1 (* n (f (- n 1))))))) (f 5))");
    try std.testing.expectEqual(@as(i64, 120), types.toFixnum(result));
}

test "eval named let" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(let loop ((i 0) (s 0)) (if (= i 5) s (loop (+ i 1) (+ s i))))");
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(result));
}

test "eval do" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Simple do: just counting - void result
    const r0 = try vm.eval("(do ((i 0 (+ i 1))) ((= i 3)))");
    try std.testing.expectEqual(types.VOID, r0);

    // Simple do: just counting
    const r1 = try vm.eval("(do ((i 0 (+ i 1))) ((= i 3) i))");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(r1));

    // Two variables with accumulation
    const result = try vm.eval("(do ((i 0 (+ i 1)) (s 0 (+ s i))) ((= i 5) s))");
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(result));
}

// ---------------------------------------------------------------------------
// Phase 4: Numeric Tower (flonums)
// ---------------------------------------------------------------------------

test "eval float literal" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("3.14");
    try std.testing.expect(types.isFlonum(result));
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), types.toFlonum(result), 1e-10);
}

test "eval float with exponent" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("1e10");
    try std.testing.expect(types.isFlonum(result));
    try std.testing.expectApproxEqAbs(@as(f64, 1e10), types.toFlonum(result), 1.0);
}

test "eval mixed arithmetic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval("(+ 1 2.0)");
    try std.testing.expect(types.isFlonum(r1));
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), types.toFlonum(r1), 1e-10);

    const r2 = try vm.eval("(* 2 3.5)");
    try std.testing.expect(types.isFlonum(r2));
    try std.testing.expectApproxEqAbs(@as(f64, 7.0), types.toFlonum(r2), 1e-10);

    const r3 = try vm.eval("(- 10.0 3)");
    try std.testing.expect(types.isFlonum(r3));
    try std.testing.expectApproxEqAbs(@as(f64, 7.0), types.toFlonum(r3), 1e-10);
}

test "eval division" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Exact division stays fixnum
    const r1 = try vm.eval("(/ 10 2)");
    try std.testing.expect(types.isFixnum(r1));
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(r1));

    // Inexact division returns flonum
    const r2 = try vm.eval("(/ 10 3)");
    try std.testing.expect(types.isFlonum(r2));
    try std.testing.expectApproxEqAbs(@as(f64, 10.0 / 3.0), types.toFlonum(r2), 1e-10);

    // Unary division
    const r3 = try vm.eval("(/ 4)");
    try std.testing.expect(types.isFlonum(r3));
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), types.toFlonum(r3), 1e-10);
}

test "eval rounding" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval("(floor 3.7)");
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), types.toFlonum(r1), 1e-10);

    const r2 = try vm.eval("(ceiling 3.2)");
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), types.toFlonum(r2), 1e-10);

    const r3 = try vm.eval("(truncate -3.7)");
    try std.testing.expectApproxEqAbs(@as(f64, -3.0), types.toFlonum(r3), 1e-10);

    // floor on fixnum returns fixnum
    const r4 = try vm.eval("(floor 42)");
    try std.testing.expect(types.isFixnum(r4));
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(r4));
}

test "eval exactness" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(exact? 42)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(exact? 3.14)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(inexact? 3.14)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(inexact? 42)"));

    // exact converts flonum to fixnum
    const r1 = try vm.eval("(exact 3.0)");
    try std.testing.expect(types.isFixnum(r1));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(r1));

    // inexact converts fixnum to flonum
    const r2 = try vm.eval("(inexact 42)");
    try std.testing.expect(types.isFlonum(r2));
    try std.testing.expectApproxEqAbs(@as(f64, 42.0), types.toFlonum(r2), 1e-10);
}

test "eval sqrt" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Perfect square returns fixnum
    const r1 = try vm.eval("(sqrt 4)");
    try std.testing.expect(types.isFixnum(r1));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(r1));

    // Non-perfect square returns flonum
    const r2 = try vm.eval("(sqrt 2.0)");
    try std.testing.expect(types.isFlonum(r2));
    try std.testing.expectApproxEqAbs(@as(f64, 1.4142135623730951), types.toFlonum(r2), 1e-10);
}

test "eval expt" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval("(expt 2 10)");
    try std.testing.expect(types.isFixnum(r1));
    try std.testing.expectEqual(@as(i64, 1024), types.toFixnum(r1));

    const r2 = try vm.eval("(expt 2.0 0.5)");
    try std.testing.expect(types.isFlonum(r2));
    try std.testing.expectApproxEqAbs(@as(f64, 1.4142135623730951), types.toFlonum(r2), 1e-10);
}

test "eval trig" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval("(sin 0)");
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), types.toFlonum(r1), 1e-10);

    const r2 = try vm.eval("(cos 0)");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), types.toFlonum(r2), 1e-10);

    const r3 = try vm.eval("(atan 1.0)");
    try std.testing.expectApproxEqAbs(@as(f64, 0.7853981633974483), types.toFlonum(r3), 1e-10);
}

test "eval special float values" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval("+inf.0");
    try std.testing.expect(types.isFlonum(r1));
    try std.testing.expect(std.math.isInf(types.toFlonum(r1)));

    const r2 = try vm.eval("-inf.0");
    try std.testing.expect(types.isFlonum(r2));
    try std.testing.expect(std.math.isInf(types.toFlonum(r2)));
    try std.testing.expect(types.toFlonum(r2) < 0);

    const r3 = try vm.eval("+nan.0");
    try std.testing.expect(types.isFlonum(r3));
    try std.testing.expect(std.math.isNan(types.toFlonum(r3)));

    try std.testing.expectEqual(types.TRUE, try vm.eval("(infinite? +inf.0)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(nan? +nan.0)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(finite? 1)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(finite? +inf.0)"));
}

test "eval gcd and lcm" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval("(gcd 32 -36)");
    try std.testing.expectEqual(@as(i64, 4), types.toFixnum(r1));

    const r2 = try vm.eval("(lcm 4 6)");
    try std.testing.expectEqual(@as(i64, 12), types.toFixnum(r2));

    const r3 = try vm.eval("(gcd)");
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(r3));

    const r4 = try vm.eval("(lcm)");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(r4));
}

test "eval comparisons with mixed types" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(= 1 1.0)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(< 1 2.5)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(> 3.5 2)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(<= 1 1.0)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(>= 2.0 2)"));
}

test "eval number predicates with flonums" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(number? 3.14)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(integer? 3.0)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(integer? 3.5)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(zero? 0.0)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(positive? 1.5)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(negative? -2.3)"));
}

test "eval string->number" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval("(string->number \"42\")");
    try std.testing.expect(types.isFixnum(r1));
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(r1));

    const r2 = try vm.eval("(string->number \"3.14\")");
    try std.testing.expect(types.isFlonum(r2));
    try std.testing.expectApproxEqAbs(@as(f64, 3.14), types.toFlonum(r2), 1e-10);

    const r3 = try vm.eval("(string->number \"hello\")");
    try std.testing.expectEqual(types.FALSE, r3);
}

// ---------------------------------------------------------------------------
// Phase 5: Hygienic Macros (syntax-rules, define-syntax)
// ---------------------------------------------------------------------------

test "define-syntax simple alias" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Define my-if as an alias for if
    _ = try vm.eval("(define-syntax my-if (syntax-rules () ((my-if test then else) (if test then else))))");
    const r1 = try vm.eval("(my-if #t 1 2)");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(r1));
    const r2 = try vm.eval("(my-if #f 1 2)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(r2));
}

test "define-syntax constant macro" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define-syntax my-const (syntax-rules () ((my-const) 42)))");
    const result = try vm.eval("(my-const)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "define-syntax with multiple patterns" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // A macro with two rules
    _ = try vm.eval("(define-syntax my-op (syntax-rules () ((my-op a) a) ((my-op a b) (+ a b))))");
    const r1 = try vm.eval("(my-op 5)");
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(r1));
    const r2 = try vm.eval("(my-op 3 4)");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(r2));
}

test "syntax-rules with ellipsis" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // my-begin using ellipsis
    _ = try vm.eval("(define-syntax my-begin (syntax-rules () ((my-begin e1 e2 ...) (begin e1 e2 ...))))");
    const result = try vm.eval("(my-begin 1 2 3)");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}

test "syntax-rules list construction" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // my-list using ellipsis
    _ = try vm.eval("(define-syntax my-list (syntax-rules () ((my-list e ...) (list e ...))))");
    const result = try vm.eval("(my-list 1 2 3)");
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(result)));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.car(types.cdr(result))));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(types.car(types.cdr(types.cdr(result)))));
}

test "syntax-rules with literals" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // A macro that uses a literal keyword
    _ = try vm.eval("(define-syntax my-case (syntax-rules (is) ((my-case x is y) (if (= x y) #t #f))))");
    const r1 = try vm.eval("(my-case 3 is 3)");
    try std.testing.expectEqual(types.TRUE, r1);
    const r2 = try vm.eval("(my-case 3 is 4)");
    try std.testing.expectEqual(types.FALSE, r2);
}

test "syntax-rules zero ellipsis matches" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // my-begin with zero varargs
    _ = try vm.eval("(define-syntax my-begin (syntax-rules () ((my-begin e1 e2 ...) (begin e1 e2 ...))))");
    const result = try vm.eval("(my-begin 42)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "let-syntax basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(let-syntax ((my-const (syntax-rules () ((my-const) 42)))) (my-const))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "let-syntax scoping" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Define a macro at top level
    _ = try vm.eval("(define-syntax outer (syntax-rules () ((outer) 1)))");
    // Override inside let-syntax
    const result = try vm.eval("(let-syntax ((outer (syntax-rules () ((outer) 2)))) (outer))");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
    // After let-syntax, original should be restored
    const result2 = try vm.eval("(outer)");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(result2));
}

test "letrec-syntax basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(letrec-syntax ((my-const (syntax-rules () ((my-const) 99)))) (my-const))");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

test "define-syntax nested expansion" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Define swap that uses let
    _ = try vm.eval(
        \\(define-syntax my-swap
        \\  (syntax-rules ()
        \\    ((my-swap a b)
        \\     (let ((tmp a))
        \\       (set! a b)
        \\       (set! b tmp)))))
    );
    _ = try vm.eval("(define x 1)");
    _ = try vm.eval("(define y 2)");
    _ = try vm.eval("(my-swap x y)");
    const rx = try vm.eval("x");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(rx));
    const ry = try vm.eval("y");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(ry));
}

test "syntax-rules underscore" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Use _ as a wildcard in pattern
    _ = try vm.eval("(define-syntax second (syntax-rules () ((second _ x) x)))");
    const result = try vm.eval("(second 1 2)");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
}

test "syntax-rules define-syntax my-and" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Classic recursive-style my-and with multiple rules
    _ = try vm.eval(
        \\(define-syntax my-and
        \\  (syntax-rules ()
        \\    ((my-and) #t)
        \\    ((my-and x) x)
        \\    ((my-and x y) (if x y #f))))
    );
    try std.testing.expectEqual(types.TRUE, try vm.eval("(my-and)"));
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(try vm.eval("(my-and 5)")));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(try vm.eval("(my-and 2 3)")));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(my-and #f 3)"));
}

// ---------------------------------------------------------------------------
// Phase 6: Libraries (import, define-library, export)
// ---------------------------------------------------------------------------

test "import scheme base" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // (import (scheme base)) should make + available
    _ = try vm.eval("(import (scheme base))");
    const result = try vm.eval("(+ 1 2)");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}

test "import only" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (only (scheme base) + -))");
    const r1 = try vm.eval("(+ 10 5)");
    try std.testing.expectEqual(@as(i64, 15), types.toFixnum(r1));
    const r2 = try vm.eval("(- 10 3)");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(r2));
}

test "import except" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // Create a fresh VM without pre-loaded globals to verify except works
    var vm = VM.init(&gc);
    defer vm.deinit();
    primitives_mod.setGCInstance(&gc);
    try primitives_mod.registerAll(&vm);
    try library_mod.registerStandardLibraries(&vm.libraries, &vm.globals);

    // Import everything except +
    _ = try vm.eval("(import (except (scheme base) +))");
    // - should work
    const r1 = try vm.eval("(- 10 3)");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(r1));
}

test "import rename" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (rename (scheme base) (+ add) (- subtract)))");
    const r1 = try vm.eval("(add 3 4)");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(r1));
    const r2 = try vm.eval("(subtract 10 3)");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(r2));
}

test "import prefix" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (prefix (scheme base) my:))");
    const result = try vm.eval("(my:+ 3 4)");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(result));
}

test "import scheme write" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // After importing (scheme write), display/write/newline should be available
    // We test availability by checking they are procedures
    _ = try vm.eval("(import (scheme write))");
    const result = try vm.eval("(procedure? display)");
    try std.testing.expectEqual(types.TRUE, result);
}

test "import scheme inexact" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (scheme inexact))");
    const result = try vm.eval("(sin 0)");
    try std.testing.expect(types.isFlonum(result));
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), types.toFlonum(result), 1e-10);
}

test "import multiple libraries" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (scheme base) (scheme inexact))");
    const r1 = try vm.eval("(+ 1 2)");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(r1));
    const r2 = try vm.eval("(cos 0)");
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), types.toFlonum(r2), 1e-10);
}

test "define-library and import" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Define a custom library
    _ = try vm.eval(
        \\(define-library (mylib)
        \\  (import (scheme base))
        \\  (export double)
        \\  (begin
        \\    (define (double x) (* x 2))))
    );

    // Import and use it
    _ = try vm.eval("(import (mylib))");
    const result = try vm.eval("(double 21)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "define-library with multiple exports" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-library (math-utils)
        \\  (import (scheme base))
        \\  (export square cube)
        \\  (begin
        \\    (define (square x) (* x x))
        \\    (define (cube x) (* x x x))))
    );

    _ = try vm.eval("(import (math-utils))");
    const r1 = try vm.eval("(square 5)");
    try std.testing.expectEqual(@as(i64, 25), types.toFixnum(r1));
    const r2 = try vm.eval("(cube 3)");
    try std.testing.expectEqual(@as(i64, 27), types.toFixnum(r2));
}

test "define-library with dotted name" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-library (my utils math)
        \\  (import (scheme base))
        \\  (export add5)
        \\  (begin
        \\    (define (add5 x) (+ x 5))))
    );

    _ = try vm.eval("(import (my utils math))");
    const result = try vm.eval("(add5 10)");
    try std.testing.expectEqual(@as(i64, 15), types.toFixnum(result));
}

// ---------------------------------------------------------------------------
// Phase 7: Exceptions (R7RS 6.11)
// ---------------------------------------------------------------------------

test "guard basic catch" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(guard (e (#t e)) (raise 42))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "guard with error-object" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(guard (e ((error-object? e) (error-object-message e)))
        \\  (error "oops" 1 2))
    );
    try std.testing.expect(types.isString(result));
    const str = types.toObject(result).as(types.SchemeString);
    try std.testing.expectEqualStrings("oops", str.data[0..str.len]);
}

test "guard with else clause" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(guard (e (else 99))
        \\  (error "test"))
    );
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

test "guard no exception" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(guard (e (else 99)) (+ 1 2))");
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}

test "with-exception-handler basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(with-exception-handler
        \\  (lambda (e) 42)
        \\  (lambda () (raise "boom")))
    );
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "with-exception-handler normal return" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(with-exception-handler
        \\  (lambda (e) 99)
        \\  (lambda () (+ 1 2)))
    );
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}

test "error-object predicates" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const r1 = try vm.eval(
        \\(guard (e (#t (error-object? e)))
        \\  (error "msg"))
    );
    try std.testing.expectEqual(types.TRUE, r1);

    // Non-error-object
    const r2 = try vm.eval(
        \\(guard (e (#t (error-object? e)))
        \\  (raise 42))
    );
    try std.testing.expectEqual(types.FALSE, r2);
}

test "error-object-irritants" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(guard (e ((error-object? e) (error-object-irritants e)))
        \\  (error "msg" 1 2 3))
    );
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(result)));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.car(types.cdr(result))));
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(types.car(types.cdr(types.cdr(result)))));
}

test "file-error? and read-error?" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.FALSE, try vm.eval("(file-error? 42)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(read-error? 42)"));
}

test "raise without handler is error" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = vm.eval("(raise 42)");
    try std.testing.expectError(VMError.ExceptionRaised, result);
}

test "guard with multiple clauses" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // First clause doesn't match, second does
    const result = try vm.eval(
        \\(guard (e
        \\         ((string? e) 1)
        \\         ((number? e) 2)
        \\         (else 3))
        \\  (raise 42))
    );
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(result));
}

test "nested guard" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(guard (outer (#t (+ outer 100)))
        \\  (guard (inner (#t (+ inner 10)))
        \\    (raise 1)))
    );
    try std.testing.expectEqual(@as(i64, 11), types.toFixnum(result));
}

// ---------------------------------------------------------------------------
// Phase 8: Records (R7RS 5.5 define-record-type)
// ---------------------------------------------------------------------------

test "define-record-type basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-record-type point
        \\  (make-point x y)
        \\  point?
        \\  (x point-x)
        \\  (y point-y))
    );
    const p = try vm.eval("(make-point 1 2)");
    try std.testing.expect(types.isRecordInstance(p));
}

test "record predicate" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-record-type point
        \\  (make-point x y)
        \\  point?
        \\  (x point-x)
        \\  (y point-y))
    );
    _ = try vm.eval("(define p (make-point 1 2))");
    try std.testing.expectEqual(types.TRUE, try vm.eval("(point? p)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(point? 42)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(point? #t)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(point? '())"));
}

test "record accessors" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-record-type point
        \\  (make-point x y)
        \\  point?
        \\  (x point-x)
        \\  (y point-y))
    );
    _ = try vm.eval("(define p (make-point 1 2))");
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(try vm.eval("(point-x p)")));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try vm.eval("(point-y p)")));
}

test "record mutator" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-record-type point
        \\  (make-point x y)
        \\  point?
        \\  (x point-x)
        \\  (y point-y point-y-set!))
    );
    _ = try vm.eval("(define p (make-point 1 2))");
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(try vm.eval("(point-y p)")));
    _ = try vm.eval("(point-y-set! p 99)");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(try vm.eval("(point-y p)")));
}

test "record type distinction" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-record-type point
        \\  (make-point x y)
        \\  point?
        \\  (x point-x)
        \\  (y point-y))
    );
    _ = try vm.eval(
        \\(define-record-type color
        \\  (make-color r g b)
        \\  color?
        \\  (r color-r)
        \\  (g color-g)
        \\  (b color-b))
    );

    _ = try vm.eval("(define p (make-point 1 2))");
    _ = try vm.eval("(define c (make-color 255 128 0))");

    // Type checking works correctly
    try std.testing.expectEqual(types.TRUE, try vm.eval("(point? p)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(point? c)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(color? p)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(color? c)"));

    // Accessors work on the correct types
    try std.testing.expectEqual(@as(i64, 255), types.toFixnum(try vm.eval("(color-r c)")));
    try std.testing.expectEqual(@as(i64, 128), types.toFixnum(try vm.eval("(color-g c)")));
    try std.testing.expectEqual(@as(i64, 0), types.toFixnum(try vm.eval("(color-b c)")));
}

test "record with mixed field types" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-record-type person
        \\  (make-person name age)
        \\  person?
        \\  (name person-name)
        \\  (age person-age person-set-age!))
    );

    _ = try vm.eval("(define bob (make-person \"Bob\" 30))");
    try std.testing.expectEqual(types.TRUE, try vm.eval("(person? bob)"));

    // Check string field
    const name_val = try vm.eval("(person-name bob)");
    try std.testing.expect(types.isString(name_val));

    // Check fixnum field
    try std.testing.expectEqual(@as(i64, 30), types.toFixnum(try vm.eval("(person-age bob)")));

    // Mutate age
    _ = try vm.eval("(person-set-age! bob 31)");
    try std.testing.expectEqual(@as(i64, 31), types.toFixnum(try vm.eval("(person-age bob)")));
}

test "record in define-library" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define-library (shapes)
        \\  (import (scheme base))
        \\  (export make-rect rect? rect-width rect-height)
        \\  (begin
        \\    (define-record-type rect
        \\      (make-rect width height)
        \\      rect?
        \\      (width rect-width)
        \\      (height rect-height))))
    );

    _ = try vm.eval("(import (shapes))");
    _ = try vm.eval("(define r (make-rect 10 20))");
    try std.testing.expectEqual(types.TRUE, try vm.eval("(rect? r)"));
    try std.testing.expectEqual(@as(i64, 10), types.toFixnum(try vm.eval("(rect-width r)")));
    try std.testing.expectEqual(@as(i64, 20), types.toFixnum(try vm.eval("(rect-height r)")));
}

// ---------------------------------------------------------------------------
// Phase 9: Ports and I/O (R7RS 6.13)
// ---------------------------------------------------------------------------

test "current-output-port returns a port" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(port? (current-output-port))"));
}

test "current-input-port returns an input port" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(input-port? (current-input-port))"));
}

test "current-output-port is an output port" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(output-port? (current-output-port))"));
}

test "current-error-port is an output port" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(output-port? (current-error-port))"));
}

test "port predicates on non-port values" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.FALSE, try vm.eval("(port? 42)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(port? #t)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(port? '())"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(input-port? 42)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(output-port? \"hello\")"));
}

test "input-port-open? and output-port-open?" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(input-port-open? (current-input-port))"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(output-port-open? (current-output-port))"));
}

test "textual-port? returns true for ports" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(textual-port? (current-output-port))"));
}

test "eof-object and eof-object?" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    try std.testing.expectEqual(types.TRUE, try vm.eval("(eof-object? (eof-object))"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(eof-object? 42)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(eof-object? #f)"));
}

test "write to file and read back with read-line" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Write to a temp file
    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-readline.txt"))
    );
    _ = try vm.eval(
        \\(write-string "hello world" p)
    );
    _ = try vm.eval("(newline p)");
    _ = try vm.eval("(close-port p)");

    // Read it back
    _ = try vm.eval(
        \\(define p2 (open-input-file "/tmp/kaappi-test-readline.txt"))
    );
    const result = try vm.eval("(read-line p2)");
    _ = try vm.eval("(close-port p2)");

    try std.testing.expect(types.isString(result));
    const str = types.toObject(result).as(types.SchemeString);
    try std.testing.expectEqualStrings("hello world", str.data[0..str.len]);
}

test "write-char and read-char" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Write chars to a temp file
    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-char.txt"))
    );
    _ = try vm.eval("(write-char #\\A p)");
    _ = try vm.eval("(write-char #\\B p)");
    _ = try vm.eval("(write-char #\\C p)");
    _ = try vm.eval("(close-port p)");

    // Read chars back
    _ = try vm.eval(
        \\(define p2 (open-input-file "/tmp/kaappi-test-char.txt"))
    );
    const r1 = try vm.eval("(read-char p2)");
    try std.testing.expect(types.isChar(r1));
    try std.testing.expectEqual(@as(u21, 'A'), types.toChar(r1));

    const r2 = try vm.eval("(read-char p2)");
    try std.testing.expectEqual(@as(u21, 'B'), types.toChar(r2));

    const r3 = try vm.eval("(read-char p2)");
    try std.testing.expectEqual(@as(u21, 'C'), types.toChar(r3));

    // Should get EOF
    const r4 = try vm.eval("(read-char p2)");
    try std.testing.expectEqual(types.EOF, r4);

    _ = try vm.eval("(close-port p2)");
}

test "peek-char does not consume" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-peek.txt"))
    );
    _ = try vm.eval("(write-char #\\X p)");
    _ = try vm.eval("(close-port p)");

    _ = try vm.eval(
        \\(define p2 (open-input-file "/tmp/kaappi-test-peek.txt"))
    );
    // Peek should return X without consuming
    const r1 = try vm.eval("(peek-char p2)");
    try std.testing.expect(types.isChar(r1));
    try std.testing.expectEqual(@as(u21, 'X'), types.toChar(r1));

    // Read should also return X (peeked byte)
    const r2 = try vm.eval("(read-char p2)");
    try std.testing.expectEqual(@as(u21, 'X'), types.toChar(r2));

    // Now should get EOF
    const r3 = try vm.eval("(read-char p2)");
    try std.testing.expectEqual(types.EOF, r3);

    _ = try vm.eval("(close-port p2)");
}

test "close-port marks port as closed" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-close.txt"))
    );
    try std.testing.expectEqual(types.TRUE, try vm.eval("(output-port-open? p)"));
    _ = try vm.eval("(close-port p)");
    try std.testing.expectEqual(types.FALSE, try vm.eval("(output-port-open? p)"));
}

test "file-exists?" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Create a file first
    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-exists.txt"))
    );
    _ = try vm.eval("(close-port p)");

    try std.testing.expectEqual(types.TRUE, try vm.eval(
        \\(file-exists? "/tmp/kaappi-test-exists.txt")
    ));
    try std.testing.expectEqual(types.FALSE, try vm.eval(
        \\(file-exists? "/tmp/kaappi-nonexistent-file-12345.txt")
    ));
}

test "read datum from file" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Write a Scheme expression to a file
    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-read.txt"))
    );
    _ = try vm.eval(
        \\(write-string "(+ 1 2)" p)
    );
    _ = try vm.eval("(close-port p)");

    // Read it back as a datum
    _ = try vm.eval(
        \\(define p2 (open-input-file "/tmp/kaappi-test-read.txt"))
    );
    const result = try vm.eval("(read p2)");
    _ = try vm.eval("(close-port p2)");

    // Result should be the list (+ 1 2)
    try std.testing.expect(types.isPair(result));
    try std.testing.expect(types.isSymbol(types.car(result)));
    try std.testing.expectEqualStrings("+", types.symbolName(types.car(result)));
}

test "display and write with port argument" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Write using display with port argument
    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-display.txt"))
    );
    _ = try vm.eval(
        \\(display "hello" p)
    );
    _ = try vm.eval("(display 42 p)");
    _ = try vm.eval("(close-port p)");

    // Read back
    _ = try vm.eval(
        \\(define p2 (open-input-file "/tmp/kaappi-test-display.txt"))
    );
    const result = try vm.eval("(read-line p2)");
    _ = try vm.eval("(close-port p2)");

    try std.testing.expect(types.isString(result));
    const str = types.toObject(result).as(types.SchemeString);
    try std.testing.expectEqualStrings("hello42", str.data[0..str.len]);
}

test "open-input-file on port is an input port" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Create a file
    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-iport.txt"))
    );
    _ = try vm.eval("(close-port p)");

    _ = try vm.eval(
        \\(define p2 (open-input-file "/tmp/kaappi-test-iport.txt"))
    );
    try std.testing.expectEqual(types.TRUE, try vm.eval("(port? p2)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(input-port? p2)"));
    try std.testing.expectEqual(types.FALSE, try vm.eval("(output-port? p2)"));
    _ = try vm.eval("(close-port p2)");
}

test "read-line returns eof on empty file" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Create an empty file
    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-empty.txt"))
    );
    _ = try vm.eval("(close-port p)");

    _ = try vm.eval(
        \\(define p2 (open-input-file "/tmp/kaappi-test-empty.txt"))
    );
    const result = try vm.eval("(read-line p2)");
    try std.testing.expectEqual(types.EOF, result);
    _ = try vm.eval("(close-port p2)");
}

test "read-line with multiple lines" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Write multiple lines
    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-multiline.txt"))
    );
    _ = try vm.eval(
        \\(write-string "line1" p)
    );
    _ = try vm.eval("(newline p)");
    _ = try vm.eval(
        \\(write-string "line2" p)
    );
    _ = try vm.eval("(newline p)");
    _ = try vm.eval("(close-port p)");

    // Read lines
    _ = try vm.eval(
        \\(define p2 (open-input-file "/tmp/kaappi-test-multiline.txt"))
    );

    const r1 = try vm.eval("(read-line p2)");
    try std.testing.expect(types.isString(r1));
    const s1 = types.toObject(r1).as(types.SchemeString);
    try std.testing.expectEqualStrings("line1", s1.data[0..s1.len]);

    const r2 = try vm.eval("(read-line p2)");
    try std.testing.expect(types.isString(r2));
    const s2 = types.toObject(r2).as(types.SchemeString);
    try std.testing.expectEqualStrings("line2", s2.data[0..s2.len]);

    _ = try vm.eval("(close-port p2)");
}

test "write to port with write procedure" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval(
        \\(define p (open-output-file "/tmp/kaappi-test-write.txt"))
    );
    _ = try vm.eval(
        \\(write "quoted" p)
    );
    _ = try vm.eval("(close-port p)");

    _ = try vm.eval(
        \\(define p2 (open-input-file "/tmp/kaappi-test-write.txt"))
    );
    const result = try vm.eval("(read-line p2)");
    _ = try vm.eval("(close-port p2)");

    try std.testing.expect(types.isString(result));
    const str = types.toObject(result).as(types.SchemeString);
    // write should produce quoted output
    try std.testing.expectEqualStrings("\"quoted\"", str.data[0..str.len]);
}

test "import scheme file" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(import (scheme file))");
    // After import, open-input-file should be available
    try std.testing.expectEqual(types.TRUE, try vm.eval("(procedure? open-input-file)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(procedure? open-output-file)"));
    try std.testing.expectEqual(types.TRUE, try vm.eval("(procedure? file-exists?)"));
}

// ---------------------------------------------------------------------------
// Phase 10: Continuations (R7RS 6.10)
// ---------------------------------------------------------------------------

test "call/cc basic — proc returns normally" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call-with-current-continuation (lambda (k) 42))");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "call/cc escape continuation" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(+ 1 (call/cc (lambda (k) (+ 2 (k 10)))))");
    try std.testing.expectEqual(@as(i64, 11), types.toFixnum(result));
}

test "call/cc alias" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call/cc (lambda (k) (k 99)))");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

test "call/cc continuation is a procedure" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call/cc (lambda (k) (procedure? k)))");
    try std.testing.expectEqual(types.TRUE, result);
}

test "call/cc nested escape" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Escape from nested computation
    const result = try vm.eval(
        \\(* 10 (call/cc (lambda (k)
        \\  (+ 1 (+ 2 (k 5))))))
    );
    try std.testing.expectEqual(@as(i64, 50), types.toFixnum(result));
}

test "call/cc with no invocation of continuation" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Continuation is never invoked — proc returns normally
    const result = try vm.eval("(call/cc (lambda (k) (+ 3 4)))");
    try std.testing.expectEqual(@as(i64, 7), types.toFixnum(result));
}

test "dynamic-wind basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define log '())");
    _ = try vm.eval(
        \\(dynamic-wind
        \\  (lambda () (set! log (cons 'in log)))
        \\  (lambda () (set! log (cons 'body log)))
        \\  (lambda () (set! log (cons 'out log))))
    );
    const result = try vm.eval("(reverse log)");
    // Should be (in body out)
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqualStrings("in", types.symbolName(types.car(result)));
    try std.testing.expectEqualStrings("body", types.symbolName(types.car(types.cdr(result))));
    try std.testing.expectEqualStrings("out", types.symbolName(types.car(types.cdr(types.cdr(result)))));
}

test "dynamic-wind returns thunk result" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval(
        \\(dynamic-wind
        \\  (lambda () #f)
        \\  (lambda () 42)
        \\  (lambda () #f))
    );
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "values single value" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(values 42)");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}

test "call-with-values basic" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call-with-values (lambda () (values 1 2 3)) +)");
    try std.testing.expectEqual(@as(i64, 6), types.toFixnum(result));
}

test "call-with-values with list" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.eval("(call-with-values (lambda () (values 1 2)) list)");
    try std.testing.expect(types.isPair(result));
    try std.testing.expectEqual(@as(i64, 1), types.toFixnum(types.car(result)));
    try std.testing.expectEqual(@as(i64, 2), types.toFixnum(types.car(types.cdr(result))));
}

test "call-with-values single value" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // Single value should work like a normal call
    const result = try vm.eval("(call-with-values (lambda () 42) (lambda (x) (+ x 1)))");
    try std.testing.expectEqual(@as(i64, 43), types.toFixnum(result));
}

test "values with zero values" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    // (values) produces multiple values with zero elements
    const result = try vm.eval("(call-with-values (lambda () (values)) (lambda () 99))");
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(result));
}

test "dynamic-wind with escape continuation" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();

    _ = try vm.eval("(define log '())");
    const result = try vm.eval(
        \\(call/cc (lambda (k)
        \\  (dynamic-wind
        \\    (lambda () (set! log (cons 'in log)))
        \\    (lambda () (k 42))
        \\    (lambda () (set! log (cons 'out log))))))
    );
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
    // After should have been called even though we escaped
    const log = try vm.eval("(reverse log)");
    try std.testing.expect(types.isPair(log));
    try std.testing.expectEqualStrings("in", types.symbolName(types.car(log)));
    try std.testing.expectEqualStrings("out", types.symbolName(types.car(types.cdr(log))));
}
