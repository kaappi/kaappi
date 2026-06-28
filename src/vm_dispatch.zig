const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const OpCode = types.OpCode;

const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const CallFrame = vm_mod.CallFrame;
const MAX_REGISTERS = vm_mod.MAX_REGISTERS;
const MAX_FRAMES = vm_mod.MAX_FRAMES;

const vm_calls = @import("vm_calls.zig");
const vm_continuations = @import("vm_continuations.zig");
const vm_debug = @import("vm_debug.zig");
const vm_library = @import("vm_library.zig");
const vm_records = @import("vm_records.zig");

pub fn runUntil(self: *VM, target_frame_count: usize, target_wind_count: usize) VMError!Value {
    while (self.frame_count > target_frame_count) {
        if (self.yielded) {
            self.yielded = false;
            return VMError.Yielded;
        }

        self.instruction_counter +%= 1;
        if (self.instruction_counter & 0x3FF == 0) {
            if (self.timeout_deadline_ns) |deadline| {
                if (vm_calls.clockNs() >= deadline) {
                    self.setErrorDetail("execution timed out", .{});
                    return VMError.ExecutionTimeout;
                }
            }
        }

        const frame = &self.frames[self.frame_count - 1];
        if (frame.ip >= frame.code.len) return VMError.InvalidBytecode;

        const raw_op = frame.code[frame.ip];
        if (raw_op > @intFromEnum(OpCode.self_tail_call)) return VMError.InvalidBytecode;
        const op: OpCode = @enumFromInt(raw_op);
        frame.ip += 1;

        const fixed_operand_bytes: usize = switch (op) {
            .load_const => 4,
            .load_nil, .load_true, .load_false, .load_void => 2,
            .move => 4,
            .get_global => 4,
            .set_global => 4,
            .define_global => 4,
            .tail_apply => 3,
            .get_local, .set_local => 4,
            .get_upvalue, .set_upvalue => 4,
            .call, .tail_call => 3,
            .@"return" => 2,
            .jump => 2,
            .jump_false, .jump_true => 4,
            .closure => 4,
            .close_upvalue => 2,
            .cons => 6,
            .push_handler => 2,
            .pop_handler, .halt => 0,
            .call_global, .tail_call_global => 5,
            .box_local => 2,
            .get_box_local, .set_box_local => 4,
            .self_tail_call => 3,
        };
        try ensureOperands(self, frame, fixed_operand_bytes);

        // Debug hook -- check if we should pause
        if (self.debug_mode) {
            if (shouldDebugPause(self, frame)) {
                debugPause(self, frame) catch {};
            }
        }

        if (self.profile_mode) {
            if (frame.closure) |cl| {
                cl.func.profile_instrs += 1;
            }
        }

        switch (op) {
            .load_const => {
                const dst = readU16(self, frame);
                const idx = readU16(self, frame);
                const closure = frame.closure orelse return VMError.InvalidBytecode;
                const dst_idx = try registerIndex(self, frame.base, dst);
                self.registers[dst_idx] = try constantAt(self, closure.func, idx);
            },
            .load_nil => {
                const dst = readU16(self, frame);
                const dst_idx = try registerIndex(self, frame.base, dst);
                self.registers[dst_idx] = types.NIL;
            },
            .load_true => {
                const dst = readU16(self, frame);
                const dst_idx = try registerIndex(self, frame.base, dst);
                self.registers[dst_idx] = types.TRUE;
            },
            .load_false => {
                const dst = readU16(self, frame);
                const dst_idx = try registerIndex(self, frame.base, dst);
                self.registers[dst_idx] = types.FALSE;
            },
            .load_void => {
                const dst = readU16(self, frame);
                const dst_idx = try registerIndex(self, frame.base, dst);
                self.registers[dst_idx] = types.VOID;
            },
            .move => {
                const dst = readU16(self, frame);
                const src = readU16(self, frame);
                const dst_idx = try registerIndex(self, frame.base, dst);
                const src_idx = try registerIndex(self, frame.base, src);
                self.registers[dst_idx] = self.registers[src_idx];
            },
            .get_global => {
                const dst = readU16(self, frame);
                const sym_idx = readU16(self, frame);
                const closure = frame.closure orelse return VMError.InvalidBytecode;
                const func = closure.func;
                const dst_idx = try registerIndex(self, frame.base, dst);
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
                const sym = try constantAt(self, func, sym_idx);
                if (!types.isSymbol(sym)) return VMError.InvalidBytecode;
                const name = types.symbolName(sym);
                const val = env.get(name) orelse blk: {
                    if (func.env != null) {
                        if (self.globals.get(name)) |gval| break :blk gval;
                    }
                    if (self.findSimilarName(name)) |suggestion| {
                        self.setErrorDetail("undefined variable '{s}'. Did you mean '{s}'?", .{ name, suggestion });
                    } else {
                        if (self.findSimilarName(name)) |sug| {
                            self.setErrorDetail("undefined variable '{s}'. Did you mean '{s}'?", .{ name, sug });
                        } else {
                            self.setErrorDetail("undefined variable '{s}'", .{name});
                        }
                    }
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
                const sym_idx = readU16(self, frame);
                const src = readU16(self, frame);
                const closure = frame.closure orelse return VMError.InvalidBytecode;
                const func = closure.func;
                const src_idx = try registerIndex(self, frame.base, src);
                const env: *std.StringHashMap(Value) = func.env orelse &self.globals;
                const sym = try constantAt(self, func, sym_idx);
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
                const sym_idx = readU16(self, frame);
                const src = readU16(self, frame);
                const closure = frame.closure orelse return VMError.InvalidBytecode;
                const func = closure.func;
                const src_idx = try registerIndex(self, frame.base, src);
                const env: *std.StringHashMap(Value) = func.env orelse &self.globals;
                const sym = try constantAt(self, func, sym_idx);
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
                const dst = readU16(self, frame);
                const idx = readU16(self, frame);
                const closure = frame.closure orelse return VMError.InvalidBytecode;
                if (idx >= closure.upvalues.len) return VMError.InvalidBytecode;
                const uv = closure.upvalues[idx];
                const dst_idx = try registerIndex(self, frame.base, dst);
                self.registers[dst_idx] = if (types.isPair(uv) and types.cdr(uv) == types.VOID)
                    types.car(uv)
                else
                    uv;
            },
            .set_upvalue => {
                const idx = readU16(self, frame);
                const src = readU16(self, frame);
                const closure = frame.closure orelse return VMError.InvalidBytecode;
                if (idx >= closure.upvalues.len) return VMError.InvalidBytecode;
                const src_idx = try registerIndex(self, frame.base, src);
                const uv = closure.upvalues[idx];
                if (types.isPair(uv) and types.cdr(uv) == types.VOID) {
                    types.setCar(uv, self.registers[src_idx]);
                } else {
                    closure.upvalues[idx] = self.registers[src_idx];
                }
            },
            .jump => {
                const offset = readI16(self, frame);
                const new_ip = @as(isize, @intCast(frame.ip)) + offset;
                if (new_ip < 0) return VMError.InvalidBytecode;
                const target: usize = @intCast(new_ip);
                if (target > frame.code.len) return VMError.InvalidBytecode;
                frame.ip = target;
            },
            .jump_false => {
                const test_reg = readU16(self, frame);
                const offset = readI16(self, frame);
                const test_idx = try registerIndex(self, frame.base, test_reg);
                if (!types.isTruthy(self.registers[test_idx])) {
                    const new_ip = @as(isize, @intCast(frame.ip)) + offset;
                    if (new_ip < 0) return VMError.InvalidBytecode;
                    const target: usize = @intCast(new_ip);
                    if (target > frame.code.len) return VMError.InvalidBytecode;
                    frame.ip = target;
                }
            },
            .jump_true => {
                const test_reg = readU16(self, frame);
                const offset = readI16(self, frame);
                const test_idx = try registerIndex(self, frame.base, test_reg);
                if (types.isTruthy(self.registers[test_idx])) {
                    const new_ip = @as(isize, @intCast(frame.ip)) + offset;
                    if (new_ip < 0) return VMError.InvalidBytecode;
                    const target: usize = @intCast(new_ip);
                    if (target > frame.code.len) return VMError.InvalidBytecode;
                    frame.ip = target;
                }
            },
            .call => {
                const base_reg = readU16(self, frame);
                const nargs = readU8(self, frame);
                const base = frame.base + base_reg;
                try ensureCallWindow(self, base, nargs);
                const callee = self.registers[base];
                if (types.isClosure(callee)) {
                    vm_calls.callClosure(self, types.toObject(callee).as(types.Closure), base, nargs) catch |err| return err;
                } else {
                    vm_calls.callValue(self, callee, base, nargs) catch |err| {
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
                const base_reg = readU16(self, frame);
                const nargs = readU8(self, frame);
                const abs_base = frame.base + base_reg;
                try ensureCallWindow(self, abs_base, nargs);
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
                        vm_calls.profileTailCall(self, func);
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
                        vm_calls.profileCreditSelf(self);
                        self.gc.profile_alloc_target = &native.profile_alloc_bytes;
                    }
                    const native_start = if (self.profile_mode) vm_calls.clockNs() else 0;
                    const nargs_slice = self.registers[abs_base + 1 .. abs_base + 1 + nargs];
                    self.last_error_detail_len = 0;
                    const result = native.func(nargs_slice) catch |err| {
                        if (self.profile_mode) {
                            native.profile_time_ns +%= vm_calls.clockNs() -% native_start;
                            self.profile_last_ns = vm_calls.clockNs();
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
                        native.profile_time_ns +%= vm_calls.clockNs() -% native_start;
                        self.profile_last_ns = vm_calls.clockNs();
                        self.gc.profile_alloc_target = saved_alloc_target;
                    }
                    const return_dst = frame.dst;
                    self.frame_count -= 1;
                    if (self.profile_mode) vm_calls.profilePopReturn(self);
                    if (self.frame_count <= target_frame_count) {
                        return result;
                    }
                    const caller = &self.frames[self.frame_count - 1];
                    const ret_idx = try registerIndex(self, caller.base, return_dst);
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
                    const ret_idx = try registerIndex(self, caller.base, return_dst);
                    self.registers[ret_idx] = result;
                } else if (types.isParameter(callee)) {
                    const param = types.toObject(callee).as(types.ParameterObject);
                    const result = if (nargs == 0) self.getParameterValue(param) else blk: {
                        var new_val = self.registers[abs_base + 1];
                        if (param.converter != types.NIL) {
                            new_val = self.callWithArgs(param.converter, &[_]Value{new_val}) catch |err| return err;
                        }
                        try self.setParameterValue(param, new_val);
                        break :blk types.VOID;
                    };
                    const return_dst = frame.dst;
                    self.frame_count -= 1;
                    if (self.frame_count <= target_frame_count) {
                        return result;
                    }
                    const caller = &self.frames[self.frame_count - 1];
                    const ret_idx = try registerIndex(self, caller.base, return_dst);
                    self.registers[ret_idx] = result;
                } else {
                    self.setErrorDetail("not a procedure", .{});
                    return VMError.NotAProcedure;
                }
            },
            .tail_apply => {
                const base_reg = readU16(self, frame);
                const nargs = readU8(self, frame);
                if (nargs == 0) return VMError.InvalidBytecode;
                const abs_base = frame.base + base_reg;
                try ensureCallWindow(self, abs_base, nargs);
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
                var rest = self.registers[abs_base + nargs];
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
                            error.DivisionByZero => VMError.DivisionByZero,
                            error.IndexOutOfBounds => VMError.IndexOutOfBounds,
                            error.InvalidArgument => VMError.InvalidArgument,
                            error.OutOfMemory => VMError.OutOfMemory,
                            error.ExceptionRaised => VMError.ExceptionRaised,
                            error.Yielded => VMError.Yielded,
                            else => VMError.InvalidBytecode,
                        };
                    };
                    const return_dst = frame.dst;
                    self.frame_count -= 1;
                    if (self.frame_count <= target_frame_count) return result;
                    const caller = &self.frames[self.frame_count - 1];
                    const ret_idx = try registerIndex(self, caller.base, return_dst);
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
                const src = readU16(self, frame);
                const src_idx = try registerIndex(self, frame.base, src);
                var result = self.registers[src_idx];
                self.gc.pushRoot(&result) catch return VMError.OutOfMemory;
                defer self.gc.popRoot();
                const return_dst = frame.dst;
                const frame_wind = frame.saved_wind_count;
                self.frame_count -= 1;
                if (self.profile_mode) vm_calls.profilePopReturn(self);
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
                const ret_idx = try registerIndex(self, caller.base, return_dst);
                self.registers[ret_idx] = result;
            },
            .closure => {
                const dst = readU16(self, frame);
                const idx = readU16(self, frame);
                const parent_closure = frame.closure orelse return VMError.InvalidBytecode;
                const func_val = try constantAt(self, parent_closure.func, idx);
                if (!types.isFunction(func_val)) return VMError.InvalidBytecode;
                const func = types.toObject(func_val).as(types.Function);

                const cls_val = self.gc.allocClosure(func) catch return VMError.OutOfMemory;
                const cls = types.toObject(cls_val).as(types.Closure);

                for (cls.upvalues, 0..) |_, i| {
                    try ensureOperands(self, frame, 3);
                    const is_local = frame.code[frame.ip] == 1;
                    frame.ip += 1;
                    const index = readU16(self, frame);

                    if (is_local) {
                        const local_idx = try registerIndex(self, frame.base, index);
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

                const dst_idx = try registerIndex(self, frame.base, dst);
                self.registers[dst_idx] = cls_val;
            },
            .close_upvalue => {
                _ = readU16(self, frame);
            },
            .cons => {
                const dst = readU16(self, frame);
                const car_reg = readU16(self, frame);
                const cdr_reg = readU16(self, frame);
                const dst_idx = try registerIndex(self, frame.base, dst);
                const car_idx = try registerIndex(self, frame.base, car_reg);
                const cdr_idx = try registerIndex(self, frame.base, cdr_reg);
                const pair = self.gc.allocPair(
                    self.registers[car_idx],
                    self.registers[cdr_idx],
                ) catch return VMError.OutOfMemory;
                self.registers[dst_idx] = pair;
            },
            .push_handler => {
                const handler_reg = readU16(self, frame);
                const handler_idx = try registerIndex(self, frame.base, handler_reg);
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
                const base_reg = readU16(self, frame);
                const sym_idx = readU16(self, frame);
                const nargs = readU8(self, frame);
                const the_closure = frame.closure orelse return VMError.InvalidBytecode;
                const the_func = the_closure.func;
                const env: *std.StringHashMap(Value) = the_func.env orelse &self.globals;
                const base = frame.base + base_reg;
                try ensureCallWindow(self, base, nargs);

                if (the_func.env == null) {
                    if (the_func.global_cache) |cache| {
                        if (the_func.cache_version == self.global_version and
                            sym_idx < cache.len and cache[sym_idx] != types.VOID)
                        {
                            self.registers[base] = cache[sym_idx];
                        } else {
                            const sym = try constantAt(self, the_func, sym_idx);
                            if (!types.isSymbol(sym)) return VMError.InvalidBytecode;
                            const name = types.symbolName(sym);
                            const val = env.get(name) orelse {
                                if (self.findSimilarName(name)) |sug| {
                                    self.setErrorDetail("undefined variable '{s}'. Did you mean '{s}'?", .{ name, sug });
                                } else {
                                    self.setErrorDetail("undefined variable '{s}'", .{name});
                                }
                                return VMError.UndefinedVariable;
                            };
                            self.registers[base] = val;
                            if (types.isClosure(val) or types.isNativeFn(val)) {
                                if (sym_idx < cache.len) cache[sym_idx] = val;
                            }
                        }
                    } else {
                        const sym = try constantAt(self, the_func, sym_idx);
                        if (!types.isSymbol(sym)) return VMError.InvalidBytecode;
                        const name = types.symbolName(sym);
                        const val = env.get(name) orelse {
                            if (self.findSimilarName(name)) |sug| {
                                self.setErrorDetail("undefined variable '{s}'. Did you mean '{s}'?", .{ name, sug });
                            } else {
                                self.setErrorDetail("undefined variable '{s}'", .{name});
                            }
                            return VMError.UndefinedVariable;
                        };
                        self.registers[base] = val;
                        if (types.isClosure(val) or types.isNativeFn(val)) {
                            const cache = self.gc.allocator.alloc(Value, the_func.constants.items.len) catch {
                                vm_calls.callValue(self, val, base, nargs) catch |err| {
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
                    const sym = try constantAt(self, the_func, sym_idx);
                    if (!types.isSymbol(sym)) return VMError.InvalidBytecode;
                    const name = types.symbolName(sym);
                    const val = env.get(name) orelse {
                        if (self.findSimilarName(name)) |sug| {
                            self.setErrorDetail("undefined variable '{s}'. Did you mean '{s}'?", .{ name, sug });
                        } else {
                            self.setErrorDetail("undefined variable '{s}'", .{name});
                        }
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
                            return vm_calls.handleNativeError(self, err, base, nargs);
                        };
                        self.registers[base] = result;
                    } else {
                        vm_calls.callNative(self, native, base, nargs) catch |err| {
                            if (err == VMError.ContinuationInvoked) {
                                if (target_frame_count == 0) continue;
                                return VMError.ContinuationInvoked;
                            }
                            return err;
                        };
                    }
                } else if (types.isClosure(callee)) {
                    vm_calls.callClosure(self, types.toObject(callee).as(types.Closure), base, nargs) catch |err| return err;
                } else {
                    vm_calls.callValue(self, callee, base, nargs) catch |err| {
                        if (err == VMError.ContinuationInvoked) {
                            if (target_frame_count == 0) continue;
                            return VMError.ContinuationInvoked;
                        }
                        return err;
                    };
                }
            },
            .tail_call_global => {
                const base_reg = readU16(self, frame);
                const sym_idx = readU16(self, frame);
                const nargs = readU8(self, frame);
                const closure = frame.closure orelse return VMError.InvalidBytecode;
                const func = closure.func;
                const env: *std.StringHashMap(Value) = func.env orelse &self.globals;
                const abs_base = frame.base + base_reg;
                try ensureCallWindow(self, abs_base, nargs);

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
                    const sym = try constantAt(self, func, sym_idx);
                    if (!types.isSymbol(sym)) return VMError.InvalidBytecode;
                    const name = types.symbolName(sym);
                    callee = env.get(name) orelse {
                        if (self.findSimilarName(name)) |sug| {
                            self.setErrorDetail("undefined variable '{s}'. Did you mean '{s}'?", .{ name, sug });
                        } else {
                            self.setErrorDetail("undefined variable '{s}'", .{name});
                        }
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
                                self.registers[abs_base + 1 + ri],
                                rest_list,
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
                        vm_calls.profileTailCall(self, tfunc);
                    }
                    frame.closure = tclosure;
                    frame.code = tfunc.code.items;
                    frame.ip = 0;
                } else if (types.isNativeFn(callee)) {
                    const native = types.toObject(callee).as(types.NativeFn);
                    const args = self.registers[abs_base + 1 .. abs_base + 1 + nargs];
                    const result = if (!self.profile_mode)
                        native.func(args) catch |err| {
                            return vm_calls.handleNativeError(self, err, abs_base, nargs);
                        }
                    else blk: {
                        native.profile_calls += 1;
                        const saved_alloc_target = self.gc.profile_alloc_target;
                        vm_calls.profileCreditSelf(self);
                        self.gc.profile_alloc_target = &native.profile_alloc_bytes;
                        const native_start = vm_calls.clockNs();
                        self.last_error_detail_len = 0;
                        const r = native.func(args) catch |err| {
                            native.profile_time_ns +%= vm_calls.clockNs() -% native_start;
                            self.profile_last_ns = vm_calls.clockNs();
                            self.gc.profile_alloc_target = saved_alloc_target;
                            return switch (err) {
                                error.TypeError => b2: {
                                    if (self.last_error_detail_len == 0)
                                        self.setErrorDetail("type error in '{s}'", .{native.name});
                                    break :b2 VMError.TypeError;
                                },
                                error.DivisionByZero => VMError.DivisionByZero,
                                error.IndexOutOfBounds => b_iob: {
                                    if (self.last_error_detail_len == 0)
                                        self.setErrorDetail("index out of bounds in '{s}'", .{native.name});
                                    break :b_iob VMError.IndexOutOfBounds;
                                },
                                error.InvalidArgument => b_ia: {
                                    if (self.last_error_detail_len == 0)
                                        self.setErrorDetail("invalid argument in '{s}'", .{native.name});
                                    break :b_ia VMError.InvalidArgument;
                                },
                                error.OutOfMemory => VMError.OutOfMemory,
                                error.ExceptionRaised => VMError.ExceptionRaised,
                                error.ContinuationInvoked => VMError.ContinuationInvoked,
                                error.Yielded => VMError.Yielded,
                                else => VMError.InvalidBytecode,
                            };
                        };
                        native.profile_time_ns +%= vm_calls.clockNs() -% native_start;
                        self.profile_last_ns = vm_calls.clockNs();
                        self.gc.profile_alloc_target = saved_alloc_target;
                        break :blk r;
                    };
                    const return_dst = frame.dst;
                    self.frame_count -= 1;
                    if (self.profile_mode) vm_calls.profilePopReturn(self);
                    if (self.frame_count <= target_frame_count) return result;
                    const caller = &self.frames[self.frame_count - 1];
                    const ret_idx = try registerIndex(self, caller.base, return_dst);
                    self.registers[ret_idx] = result;
                } else {
                    self.setErrorDetail("not a procedure", .{});
                    return VMError.NotAProcedure;
                }
            },
            .box_local => {
                const reg = readU16(self, frame);
                const reg_idx = try registerIndex(self, frame.base, reg);
                const val = self.registers[reg_idx];
                const box = self.gc.allocPair(val, types.VOID) catch return VMError.OutOfMemory;
                self.registers[reg_idx] = box;
            },
            .get_box_local => {
                const dst_r = readU16(self, frame);
                const reg = readU16(self, frame);
                const dst_idx = try registerIndex(self, frame.base, dst_r);
                const reg_idx = try registerIndex(self, frame.base, reg);
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
                const reg = readU16(self, frame);
                const src = readU16(self, frame);
                const reg_idx = try registerIndex(self, frame.base, reg);
                const src_idx = try registerIndex(self, frame.base, src);
                const val = self.registers[reg_idx];
                if (types.isPair(val) and types.cdr(val) == types.VOID) {
                    types.setCar(val, self.registers[src_idx]);
                } else {
                    const box = self.gc.allocPair(self.registers[src_idx], types.VOID) catch return VMError.OutOfMemory;
                    self.registers[reg_idx] = box;
                }
            },
            .self_tail_call => {
                const base_reg = readU16(self, frame);
                const nargs = readU8(self, frame);
                const abs_base = frame.base + base_reg;
                try ensureCallWindow(self, abs_base, nargs);
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
                    vm_calls.profileCreditSelf(self);
                }
                frame.ip = 0;
            },
            else => return VMError.InvalidBytecode,
        }
    }
    return types.VOID;
}

pub fn shouldDebugPause(vm: *VM, frame: *CallFrame) bool {
    return vm_debug.shouldDebugPause(vm, frame);
}

pub fn debugPause(vm: *VM, frame: *CallFrame) !void {
    return vm_debug.debugPause(vm, frame);
}

pub fn ensureOperands(vm: *VM, frame: *CallFrame, operand_bytes: usize) VMError!void {
    _ = vm;
    if (frame.ip + operand_bytes > frame.code.len) return VMError.InvalidBytecode;
}

pub fn registerIndex(vm: *VM, base: u16, reg: u16) VMError!usize {
    _ = vm;
    const idx = @as(usize, base) + @as(usize, reg);
    if (idx >= MAX_REGISTERS) return VMError.InvalidBytecode;
    return idx;
}

pub fn ensureCallWindow(vm: *VM, base: u16, nargs: u8) VMError!void {
    _ = vm;
    const hi = @as(usize, base) + @as(usize, nargs) + 1;
    if (hi > MAX_REGISTERS) return VMError.InvalidBytecode;
}

pub fn constantAt(vm: *VM, func: *types.Function, idx: u16) VMError!Value {
    _ = vm;
    if (idx >= func.constants.items.len) return VMError.InvalidBytecode;
    return func.constants.items[idx];
}

pub fn readU8(vm: *VM, frame: *CallFrame) u8 {
    _ = vm;
    const val = frame.code[frame.ip];
    frame.ip += 1;
    return val;
}

pub fn readU16(vm: *VM, frame: *CallFrame) u16 {
    _ = vm;
    const hi: u16 = frame.code[frame.ip];
    const lo: u16 = frame.code[frame.ip + 1];
    frame.ip += 2;
    return (hi << 8) | lo;
}

pub fn readI16(vm: *VM, frame: *CallFrame) i16 {
    return @bitCast(readU16(vm, frame));
}
