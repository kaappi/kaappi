const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;
const OpCode = types.OpCode;

const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const CallFrame = vm_mod.CallFrame;

const memory = @import("memory.zig");
const vm_calls = @import("vm_calls.zig");
const vm_continuations = @import("vm_continuations.zig");
const vm_debug = @import("vm_debug.zig");
const vm_library = @import("vm_library.zig");
const vm_records = @import("vm_records.zig");

/// True when a just-restored (or escape-unwound) frame stack should resume in
/// THIS dispatch loop: the new stack must still contain the loop's scope-root
/// frame, identified by birth id — frame depth alone can't distinguish "these
/// frames extend this loop's scope" from "these frames jump to an unrelated
/// program point that happens to be deeper". The outermost loop (target 0)
/// has no re-entrant Zig callers left to corrupt, so it accepts any stack.
fn resumesHere(self: *VM, target_frame_count: usize, scope_root_seq: u64) bool {
    if (self.frame_count <= target_frame_count) return false;
    if (target_frame_count == 0) return true;
    return self.frames[target_frame_count].seq == scope_root_seq;
}

/// A blocking primitive parked the current fiber and asked for a retry
/// (vm.yield_retry + error.Yielded): rewind ip to the start of the call
/// instruction so the primitive re-executes when the fiber is rescheduled.
/// Must run at the dispatch site that directly invoked the native, where the
/// instruction length (opcode byte + fixed operands) is known; the flag is
/// cleared so outer frames propagating the same Yielded do not rewind again.
fn maybeRewindRetry(self: *VM, instr_len: usize) void {
    if (!self.yield_retry) return;
    self.yield_retry = false;
    const f = &self.frames[self.frame_count - 1];
    if (f.ip >= instr_len) f.ip -= instr_len;
}

/// A frame with returns_to_native set (pushed by vm.callWithArgs) delivers its
/// result via its own runUntil session's return value; its dst is a
/// placeholder. When such a frame returns while frame_count is still above
/// the dispatching loop's target, that session — the native Zig caller (map,
/// for-each, sort, apply, ...) that owned the result — has already returned:
/// a continuation captured under the native call was resumed after the call
/// ended. There is no register to deliver into and the native's iteration
/// state is gone, so raise a catchable Scheme error instead of silently
/// writing the value into an unrelated caller register.
noinline fn raiseDeadNativeReturn(self: *VM) VMError {
    var msg = self.gc.allocString("continuation cannot resume across a returned native call") catch
        return VMError.OutOfMemory;
    self.gc.pushRoot(&msg);
    const err_obj = self.gc.allocErrorObject(msg, types.NIL) catch {
        self.gc.popRoot();
        return VMError.OutOfMemory;
    };
    self.gc.popRoot();
    self.current_exception = err_obj;
    return VMError.ExceptionRaised;
}

/// Continuation-invoked handling: after a restore/escape delivers its value,
/// execution must resume in the innermost dispatch loop whose scope-root
/// frame is still live (checked by frame birth id, see resumesHere). Loops
/// whose scope frames were discarded propagate ContinuationInvoked instead,
/// so the re-entrant Zig callers (callThunk/callHandler in natives like
/// with-exception-handler or dynamic-wind) between that loop and the resume
/// point unwind and keep their pending result-register writes consistent.
pub fn runUntil(self: *VM, target_frame_count: usize, target_wind_count: usize) VMError!Value {
    // Birth id of this loop's scope-root frame (the frame whose return ends
    // the loop). Tail calls reuse the frame and keep the id, so it is stable
    // for the loop's lifetime.
    const scope_root_seq: u64 = if (target_frame_count < self.frame_count)
        self.frames[target_frame_count].seq
    else
        0;
    // Blocking primitives may park the current fiber (yield_retry) only when
    // this loop was entered directly from a scheduler loop; nested runUntil
    // calls (map/for-each callbacks, eval) clear the marker for their extent.
    const from_scheduler = self.sched_dispatch_pending;
    self.sched_dispatch_pending = false;
    const saved_from_scheduler = self.dispatched_from_scheduler;
    self.dispatched_from_scheduler = from_scheduler;
    defer self.dispatched_from_scheduler = saved_from_scheduler;
    while (self.frame_count > target_frame_count) {
        if (self.yielded) {
            self.yielded = false;
            return VMError.Yielded;
        }

        self.instruction_counter +%= 1;
        if (self.instruction_counter & 0x3FF == 0) {
            if (self.terminate_flag) |flag| {
                if (@atomicLoad(bool, flag, .monotonic)) {
                    self.setErrorDetail("thread terminated", .{});
                    return VMError.Terminated;
                }
            }
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
        if (raw_op > @intFromEnum(OpCode.tail_eval)) return VMError.InvalidBytecode;
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
            .get_upvalue, .set_upvalue => 4,
            .call, .tail_call => 3,
            .@"return" => 2,
            .jump => 2,
            .jump_false, .jump_true => 4,
            .closure => 4,
            .cons => 6,
            .push_handler => 2,
            .pop_handler, .halt => 0,
            .call_global, .tail_call_global => 5,
            .box_local => 2,
            .get_box_local, .set_box_local => 4,
            .self_tail_call => 3,
            .tail_call_cc => 4,
            .tail_eval => 3,
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
                const env: *std.StringHashMap(Value) = func.env orelse self.globals;
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
                // Map reads under the child-thread shared lock; the error
                // path runs after release (findSimilarName locks internally).
                self.lockGlobalsShared();
                const found: ?Value = env.get(name) orelse blk: {
                    if (func.env != null) {
                        if (self.globals.get(name)) |gval| break :blk gval;
                    }
                    const base = types.stripHygienicPrefix(name);
                    if (base.len != name.len) {
                        if (env.get(base)) |bval| break :blk bval;
                        if (env != self.globals) {
                            if (self.globals.get(base)) |gval| break :blk gval;
                        }
                    }
                    break :blk null;
                };
                self.unlockGlobalsShared();
                const val = found orelse return raiseUndefinedVariable(self, name);
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
                const env: *std.StringHashMap(Value) = func.env orelse self.globals;
                const sym = try constantAt(self, func, sym_idx);
                if (!types.isSymbol(sym)) return VMError.InvalidBytecode;
                const name = types.symbolName(sym);
                const val = self.registers[src_idx];
                // Mirror get_global's hygienic-prefix fallback: a template
                // set! to a definition-site global compiles as set_global on
                // the renamed name (__hyg_N_foo); writes must reach the same
                // binding reads resolve to.
                //
                // Both the getPtr and the store through it stay inside the
                // locked region: a parent-side rehash between them would
                // leave `ptr` dangling on a child thread. The store itself
                // is an in-place update (no rehash), so the shared lock is
                // sufficient.
                self.lockGlobalsShared();
                const ptr: ?*Value = env.getPtr(name) orelse blk: {
                    const base = types.stripHygienicPrefix(name);
                    if (base.len != name.len) {
                        if (env.getPtr(base)) |bptr| break :blk bptr;
                        if (env != self.globals) {
                            if (self.globals.getPtr(base)) |gptr| break :blk gptr;
                        }
                    }
                    break :blk null;
                };
                if (ptr) |p| p.* = val;
                self.unlockGlobalsShared();
                if (ptr == null) {
                    self.setErrorDetail("set!: unbound variable '{s}'", .{name});
                    return VMError.UndefinedVariable;
                }
                if (func.env == null) {
                    self.global_version +%= 1;
                    if (func.global_cache) |cache| {
                        // Bumping global_version invalidates every function's
                        // cache, including this one's other entries. Clear the
                        // whole cache before revalidating the written slot —
                        // stamping cache_version without the memset would
                        // re-bless entries cached before an unrelated rebinding,
                        // serving them stale (issue #812). Mirrors get_global.
                        @memset(cache, types.VOID);
                        if (sym_idx < cache.len) cache[sym_idx] = val;
                        func.cache_version = self.global_version;
                    }
                }
            },
            .define_global => {
                const sym_idx = readU16(self, frame);
                const src = readU16(self, frame);
                const closure = frame.closure orelse return VMError.InvalidBytecode;
                const func = closure.func;
                const src_idx = try registerIndex(self, frame.base, src);
                const env: *std.StringHashMap(Value) = func.env orelse self.globals;
                const sym = try constantAt(self, func, sym_idx);
                if (!types.isSymbol(sym)) return VMError.InvalidBytecode;
                const name = types.symbolName(sym);
                const val = self.registers[src_idx];
                if (env == self.globals) {
                    // Structural mutation of the shared globals map: may
                    // rehash, so it must exclude child-thread readers.
                    self.globals_lock.lock();
                    defer self.globals_lock.unlock();
                    env.put(name, val) catch return VMError.OutOfMemory;
                } else {
                    env.put(name, val) catch return VMError.OutOfMemory;
                }
                if (func.env == null) {
                    self.global_version +%= 1;
                    if (func.global_cache) |cache| {
                        // See set_global: clear the whole cache before
                        // revalidating so unrelated stale entries aren't
                        // re-blessed by the version stamp (issue #812).
                        @memset(cache, types.VOID);
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
                self.registers[dst_idx] = if (types.isBox(uv))
                    types.boxGet(uv)
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
                if (types.isBox(uv)) {
                    self.gc.writeBarrier(types.toObject(uv), self.registers[src_idx]);
                    types.boxSet(uv, self.registers[src_idx]);
                } else {
                    self.gc.writeBarrier(&closure.header, self.registers[src_idx]);
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
                const base_wide = @as(usize, frame.base) + @as(usize, base_reg);
                try ensureCallWindow(self, base_wide, nargs);
                const base: u32 = try toBase(base_wide);
                const callee = self.registers[base];
                if (types.isClosure(callee)) {
                    vm_calls.callClosure(self, types.toObject(callee).as(types.Closure), base, nargs) catch |err| return err;
                } else {
                    vm_calls.callValue(self, callee, base, nargs) catch |err| {
                        if (err == VMError.ContinuationInvoked) {
                            if (resumesHere(self, target_frame_count, scope_root_seq)) {
                                continue;
                            }
                            return VMError.ContinuationInvoked;
                        }
                        if (err == VMError.Yielded) maybeRewindRetry(self, 1 + fixed_operand_bytes);
                        return err;
                    };
                }
            },
            .tail_call => {
                const base_reg = readU16(self, frame);
                const nargs = readU8(self, frame);
                const abs_base_wide = @as(usize, frame.base) + @as(usize, base_reg);
                try ensureCallWindow(self, abs_base_wide, nargs);
                const abs_base: u32 = try toBase(abs_base_wide);
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
                        if (@as(usize, abs_base) + @as(usize, rest_start) + 1 >= self.registers.len) {
                            return VMError.InvalidBytecode;
                        }
                        self.registers[abs_base + 1 + rest_start] = try buildRestList(self.gc, self.registers[abs_base + 1 + rest_start .. abs_base + 1 + nargs]);
                    }

                    const arg_count = if (func.is_variadic) func.arity + 1 else nargs;
                    for (0..arg_count) |i| {
                        const dst_idx = @as(usize, frame.base) + i;
                        const src_idx = @as(usize, abs_base) + 1 + i;
                        if (dst_idx >= self.registers.len or src_idx >= self.registers.len) {
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
                    // native.func may re-enter the VM and grow self.frames,
                    // invalidating `frame` — read dst before the call.
                    const return_dst = frame.dst;
                    const from_native_call = frame.returns_to_native;
                    const result = native.func(nargs_slice) catch |err| {
                        if (self.profile_mode) {
                            native.profile_time_ns +%= vm_calls.clockNs() -% native_start;
                            self.profile_last_ns = vm_calls.clockNs();
                            self.gc.profile_alloc_target = saved_alloc_target;
                        }
                        if (err == error.ContinuationInvoked) {
                            if (resumesHere(self, target_frame_count, scope_root_seq)) {
                                continue;
                            }
                            return VMError.ContinuationInvoked;
                        }
                        if (err == error.Yielded) maybeRewindRetry(self, 1 + fixed_operand_bytes);
                        return vm_calls.mapNativeError(self, err, native.name, nargs_slice);
                    };
                    if (self.profile_mode) {
                        native.profile_time_ns +%= vm_calls.clockNs() -% native_start;
                        self.profile_last_ns = vm_calls.clockNs();
                        self.gc.profile_alloc_target = saved_alloc_target;
                    }
                    self.frame_count -= 1;
                    if (self.profile_mode) vm_calls.profilePopReturn(self);
                    if (self.frame_count <= target_frame_count) return result;
                    if (from_native_call) return raiseDeadNativeReturn(self);
                    const caller = &self.frames[self.frame_count - 1];
                    const ret_idx = try registerIndex(self, caller.base, return_dst);
                    self.registers[ret_idx] = result;
                } else if (types.isContinuation(callee)) {
                    const cont = types.toObject(callee).as(types.Continuation);
                    const value = try vm_calls.continuationArgValue(self.gc, self.registers[abs_base + 1 .. abs_base + 1 + @as(usize, nargs)]);
                    if (cont.is_escape) {
                        try self.invokeEscape(cont, value);
                    } else {
                        try self.performWindTransition(cont.wind_records[0..cont.wind_count], cont.wind_count);
                        try self.restoreContinuation(cont, value);
                    }
                    if (resumesHere(self, target_frame_count, scope_root_seq)) {
                        continue;
                    }
                    return VMError.ContinuationInvoked;
                } else if (types.isFfiFunction(callee)) {
                    const ffi_fn = types.toObject(callee).as(types.FfiFunction);
                    if (nargs != ffi_fn.param_count) return VMError.ArityMismatch;
                    const ffi_mod = @import("ffi.zig");
                    const return_dst = frame.dst;
                    const from_native_call = frame.returns_to_native;
                    const result = ffi_mod.callFfi(ffi_fn, self.registers[abs_base + 1 .. abs_base + 1 + nargs], self.gc) catch return VMError.TypeError;
                    self.frame_count -= 1;
                    if (self.frame_count <= target_frame_count) return result;
                    if (from_native_call) return raiseDeadNativeReturn(self);
                    const caller = &self.frames[self.frame_count - 1];
                    const ret_idx = try registerIndex(self, caller.base, return_dst);
                    self.registers[ret_idx] = result;
                } else if (types.isParameter(callee)) {
                    const param = types.toObject(callee).as(types.ParameterObject);
                    const return_dst = frame.dst;
                    const from_native_call = frame.returns_to_native;
                    const result = if (nargs == 0) self.getParameterValue(param) else blk: {
                        var new_val = self.registers[abs_base + 1];
                        if (param.converter != types.NIL) {
                            new_val = self.callWithArgs(param.converter, &[_]Value{new_val}) catch |err| return err;
                        }
                        try self.setParameterValue(param, new_val);
                        break :blk types.VOID;
                    };
                    self.frame_count -= 1;
                    if (self.frame_count <= target_frame_count) return result;
                    if (from_native_call) return raiseDeadNativeReturn(self);
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
                const abs_base_wide = @as(usize, frame.base) + @as(usize, base_reg);
                try ensureCallWindow(self, abs_base_wide, nargs);
                const abs_base: u32 = try toBase(abs_base_wide);
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
                        flat_args[rest_start] = try buildRestList(self.gc, flat_args[rest_start..total_nargs]);
                    }

                    const arg_count: u8 = if (func.is_variadic) func.arity + 1 else total_nargs;
                    for (0..arg_count) |i| {
                        const dst_idx = @as(usize, frame.base) + i;
                        if (dst_idx >= self.registers.len) return VMError.InvalidBytecode;
                        self.registers[dst_idx] = flat_args[i];
                    }

                    frame.closure = closure;
                    frame.code = func.code.items;
                    frame.ip = 0;
                } else if (types.isNativeFn(proc)) {
                    const native = types.toObject(proc).as(types.NativeFn);
                    switch (native.arity) {
                        .exact => |expected| {
                            if (count != expected) {
                                self.setErrorDetail("'{s}': expected {d} arguments, got {d}", .{ native.name, expected, count });
                                return VMError.ArityMismatch;
                            }
                        },
                        .variadic => |min| {
                            if (count < min) {
                                self.setErrorDetail("'{s}': expected at least {d} arguments, got {d}", .{ native.name, min, count });
                                return VMError.ArityMismatch;
                            }
                        },
                    }
                    // native.func may re-enter the VM and grow self.frames,
                    // invalidating `frame` — read dst before the call.
                    const return_dst = frame.dst;
                    const from_native_call = frame.returns_to_native;
                    const result = native.func(flat_args[0..count]) catch |err| {
                        if (err == error.ContinuationInvoked) {
                            if (resumesHere(self, target_frame_count, scope_root_seq)) continue;
                            return VMError.ContinuationInvoked;
                        }
                        if (err == error.Yielded) maybeRewindRetry(self, 1 + fixed_operand_bytes);
                        return vm_calls.mapNativeError(self, err, native.name, flat_args[0..count]);
                    };
                    self.frame_count -= 1;
                    if (self.frame_count <= target_frame_count) return result;
                    if (from_native_call) return raiseDeadNativeReturn(self);
                    const caller = &self.frames[self.frame_count - 1];
                    const ret_idx = try registerIndex(self, caller.base, return_dst);
                    self.registers[ret_idx] = result;
                } else if (types.isContinuation(proc)) {
                    const cont = types.toObject(proc).as(types.Continuation);
                    const value = try vm_calls.continuationArgValue(self.gc, flat_args[0..count]);
                    if (cont.is_escape) {
                        try self.invokeEscape(cont, value);
                    } else {
                        try self.performWindTransition(cont.wind_records[0..cont.wind_count], cont.wind_count);
                        try self.restoreContinuation(cont, value);
                    }
                    if (resumesHere(self, target_frame_count, scope_root_seq)) continue;
                    return VMError.ContinuationInvoked;
                } else if (types.isFfiFunction(proc)) {
                    const ffi_fn = types.toObject(proc).as(types.FfiFunction);
                    if (count != ffi_fn.param_count) return VMError.ArityMismatch;
                    const ffi_mod = @import("ffi.zig");
                    // FFI callbacks may re-enter the VM and grow self.frames,
                    // invalidating `frame` — read dst before the call.
                    const return_dst = frame.dst;
                    const from_native_call = frame.returns_to_native;
                    const result = ffi_mod.callFfi(ffi_fn, flat_args[0..count], self.gc) catch return VMError.TypeError;
                    self.frame_count -= 1;
                    if (self.frame_count <= target_frame_count) return result;
                    if (from_native_call) return raiseDeadNativeReturn(self);
                    const caller = &self.frames[self.frame_count - 1];
                    const ret_idx = try registerIndex(self, caller.base, return_dst);
                    self.registers[ret_idx] = result;
                } else if (types.isParameter(proc)) {
                    const param = types.toObject(proc).as(types.ParameterObject);
                    // callWithArgs on the converter re-enters the VM and may
                    // grow self.frames, invalidating `frame` — read dst first.
                    const return_dst = frame.dst;
                    const from_native_call = frame.returns_to_native;
                    const result = if (count == 0) self.getParameterValue(param) else blk: {
                        var new_val = flat_args[0];
                        if (param.converter != types.NIL) {
                            new_val = self.callWithArgs(param.converter, &[_]Value{new_val}) catch |err| return err;
                        }
                        try self.setParameterValue(param, new_val);
                        break :blk types.VOID;
                    };
                    self.frame_count -= 1;
                    if (self.frame_count <= target_frame_count) return result;
                    if (from_native_call) return raiseDeadNativeReturn(self);
                    const caller = &self.frames[self.frame_count - 1];
                    const ret_idx = try registerIndex(self, caller.base, return_dst);
                    self.registers[ret_idx] = result;
                } else {
                    self.setErrorDetail("apply: not a procedure", .{});
                    return VMError.NotAProcedure;
                }
            },
            .@"return" => {
                const src = readU16(self, frame);
                const src_idx = try registerIndex(self, frame.base, src);
                var result = self.registers[src_idx];
                self.gc.pushRoot(&result);
                defer self.gc.popRoot();
                const return_dst = frame.dst;
                const from_native_call = frame.returns_to_native;
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
                if (from_native_call) return raiseDeadNativeReturn(self);
                // Also unwind any winds that were pushed by native
                // functions (e.g. dynamic-wind) between this frame
                // and the caller. After a continuation restore the
                // native function isn't on the Zig stack, so its
                // cleanup won't run. The caller's saved_wind_count
                // tells us the correct wind level to unwind to.
                // callThunk may re-enter the VM and grow self.frames — copy
                // the caller's fields instead of holding a pointer across it.
                const caller_wind_count = self.frames[self.frame_count - 1].saved_wind_count;
                const caller_base = self.frames[self.frame_count - 1].base;
                while (self.wind_count > caller_wind_count) {
                    self.wind_count -= 1;
                    _ = self.callThunk(self.wind_stack[self.wind_count].after) catch {};
                }
                const ret_idx = try registerIndex(self, caller_base, return_dst);
                self.registers[ret_idx] = result;
            },
            .closure => {
                const dst = readU16(self, frame);
                const idx = readU16(self, frame);
                const parent_closure = frame.closure orelse return VMError.InvalidBytecode;
                const func_val = try constantAt(self, parent_closure.func, idx);
                if (!types.isFunction(func_val)) return VMError.InvalidBytecode;
                const func = types.toObject(func_val).as(types.Function);

                var cls_val = self.gc.allocClosure(func) catch return VMError.OutOfMemory;
                self.gc.pushRoot(&cls_val);
                var cls = types.toObject(cls_val).as(types.Closure);

                for (cls.upvalues, 0..) |_, i| {
                    try ensureOperands(self, frame, 3);
                    const is_local = frame.code[frame.ip] == 1;
                    frame.ip += 1;
                    const index = readU16(self, frame);

                    if (is_local) {
                        const local_idx = try registerIndex(self, frame.base, index);
                        var val = self.registers[local_idx];
                        if (!types.isBox(val)) {
                            const box = self.gc.allocPair(val, types.VOID) catch return VMError.OutOfMemory;
                            cls = types.toObject(cls_val).as(types.Closure);
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

                self.gc.popRoot();
                const dst_idx = try registerIndex(self, frame.base, dst);
                self.registers[dst_idx] = cls_val;
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
                const env: *std.StringHashMap(Value) = the_func.env orelse self.globals;
                const base_wide = @as(usize, frame.base) + @as(usize, base_reg);
                try ensureCallWindow(self, base_wide, nargs);
                const base: u32 = try toBase(base_wide);

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
                            const val = lookupGlobalLocked(self, env, name) orelse return raiseUndefinedVariable(self, name);
                            self.registers[base] = val;
                            if (types.isClosure(val) or types.isNativeFn(val)) {
                                if (sym_idx < cache.len) cache[sym_idx] = val;
                            }
                        }
                    } else {
                        const sym = try constantAt(self, the_func, sym_idx);
                        if (!types.isSymbol(sym)) return VMError.InvalidBytecode;
                        const name = types.symbolName(sym);
                        const val = lookupGlobalLocked(self, env, name) orelse return raiseUndefinedVariable(self, name);
                        self.registers[base] = val;
                        if (types.isClosure(val) or types.isNativeFn(val)) {
                            const cache = self.gc.allocator.alloc(Value, the_func.constants.items.len) catch {
                                vm_calls.callValue(self, val, base, nargs) catch |err| {
                                    if (err == VMError.ContinuationInvoked) {
                                        if (resumesHere(self, target_frame_count, scope_root_seq)) continue;
                                        return VMError.ContinuationInvoked;
                                    }
                                    if (err == VMError.Yielded) maybeRewindRetry(self, 1 + fixed_operand_bytes);
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
                    self.lockGlobalsShared();
                    const found = env.get(name);
                    self.unlockGlobalsShared();
                    const val = found orelse return raiseUndefinedVariable(self, name);
                    self.registers[base] = val;
                }

                const callee = self.registers[base];
                if (types.isNativeFn(callee)) {
                    const native = types.toObject(callee).as(types.NativeFn);
                    const arity_ok = switch (native.arity) {
                        .exact => |expected| nargs == expected,
                        .variadic => |min| nargs >= min,
                    };
                    if (arity_ok and base + @as(u16, nargs) + 1 < self.registers.len) {
                        const args = self.registers[base + 1 .. base + 1 + nargs];
                        const result = native.func(args) catch |err| {
                            if (err == error.ContinuationInvoked) {
                                if (resumesHere(self, target_frame_count, scope_root_seq)) continue;
                                return VMError.ContinuationInvoked;
                            }
                            if (err == error.Yielded) maybeRewindRetry(self, 1 + fixed_operand_bytes);
                            return vm_calls.mapNativeError(self, err, native.name, args);
                        };
                        self.registers[base] = result;
                    } else {
                        vm_calls.callNative(self, native, base, nargs) catch |err| {
                            if (err == VMError.ContinuationInvoked) {
                                if (resumesHere(self, target_frame_count, scope_root_seq)) continue;
                                return VMError.ContinuationInvoked;
                            }
                            if (err == VMError.Yielded) maybeRewindRetry(self, 1 + fixed_operand_bytes);
                            return err;
                        };
                    }
                } else if (types.isClosure(callee)) {
                    vm_calls.callClosure(self, types.toObject(callee).as(types.Closure), base, nargs) catch |err| return err;
                } else {
                    vm_calls.callValue(self, callee, base, nargs) catch |err| {
                        if (err == VMError.ContinuationInvoked) {
                            if (resumesHere(self, target_frame_count, scope_root_seq)) continue;
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
                const env: *std.StringHashMap(Value) = func.env orelse self.globals;
                const abs_base_wide = @as(usize, frame.base) + @as(usize, base_reg);
                try ensureCallWindow(self, abs_base_wide, nargs);
                const abs_base: u32 = try toBase(abs_base_wide);

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
                    callee = lookupGlobalLocked(self, env, name) orelse return raiseUndefinedVariable(self, name);
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
                        if (@as(usize, abs_base) + @as(usize, rest_start) + 1 >= self.registers.len) {
                            return VMError.InvalidBytecode;
                        }
                        self.registers[abs_base + 1 + rest_start] = try buildRestList(self.gc, self.registers[abs_base + 1 + rest_start .. abs_base + 1 + nargs]);
                    }
                    const arg_count = if (tfunc.is_variadic) tfunc.arity + 1 else nargs;
                    for (0..arg_count) |ai| {
                        const dst_idx = @as(usize, frame.base) + ai;
                        const src_idx = @as(usize, abs_base) + 1 + ai;
                        if (dst_idx >= self.registers.len or src_idx >= self.registers.len) {
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
                    // native.func may re-enter the VM and grow self.frames,
                    // invalidating `frame` — read dst before the call.
                    const return_dst = frame.dst;
                    const from_native_call = frame.returns_to_native;
                    const result = if (!self.profile_mode)
                        native.func(args) catch |err| {
                            if (err == error.ContinuationInvoked) {
                                if (resumesHere(self, target_frame_count, scope_root_seq)) continue;
                                return VMError.ContinuationInvoked;
                            }
                            if (err == error.Yielded) maybeRewindRetry(self, 1 + fixed_operand_bytes);
                            return vm_calls.mapNativeError(self, err, native.name, args);
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
                            if (err == error.ContinuationInvoked) {
                                if (resumesHere(self, target_frame_count, scope_root_seq)) continue;
                                return VMError.ContinuationInvoked;
                            }
                            if (err == error.Yielded) maybeRewindRetry(self, 1 + fixed_operand_bytes);
                            return vm_calls.mapNativeError(self, err, native.name, args);
                        };
                        native.profile_time_ns +%= vm_calls.clockNs() -% native_start;
                        self.profile_last_ns = vm_calls.clockNs();
                        self.gc.profile_alloc_target = saved_alloc_target;
                        break :blk r;
                    };
                    self.frame_count -= 1;
                    if (self.profile_mode) vm_calls.profilePopReturn(self);
                    if (self.frame_count <= target_frame_count) return result;
                    if (from_native_call) return raiseDeadNativeReturn(self);
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
                // Idempotent: leave existing boxes alone (issue #803).
                if (!types.isBox(val)) {
                    const box = self.gc.allocPair(val, types.VOID) catch return VMError.OutOfMemory;
                    self.registers[reg_idx] = box;
                }
            },
            .get_box_local => {
                const dst_r = readU16(self, frame);
                const reg = readU16(self, frame);
                const dst_idx = try registerIndex(self, frame.base, dst_r);
                const reg_idx = try registerIndex(self, frame.base, reg);
                const val = self.registers[reg_idx];
                if (types.isBox(val)) {
                    self.registers[dst_idx] = types.boxGet(val);
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
                if (types.isBox(val)) {
                    self.gc.writeBarrier(types.toObject(val), self.registers[src_idx]);
                    types.boxSet(val, self.registers[src_idx]);
                } else {
                    const box = self.gc.allocPair(self.registers[src_idx], types.VOID) catch return VMError.OutOfMemory;
                    self.registers[reg_idx] = box;
                }
            },
            .self_tail_call => {
                const base_reg = readU16(self, frame);
                const nargs = readU8(self, frame);
                const abs_base_wide = @as(usize, frame.base) + @as(usize, base_reg);
                try ensureCallWindow(self, abs_base_wide, nargs);
                const abs_base: u32 = try toBase(abs_base_wide);
                for (0..nargs) |i| {
                    const dst_idx = @as(usize, frame.base) + i;
                    const src_idx = @as(usize, abs_base) + 1 + i;
                    if (dst_idx >= self.registers.len or src_idx >= self.registers.len) {
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
            .tail_call_cc => {
                const base_reg = readU16(self, frame);
                const dst_reg = readU16(self, frame);
                const abs_base_wide = @as(usize, frame.base) + @as(usize, base_reg);
                try ensureCallWindow(self, abs_base_wide, 1);
                const abs_base: u32 = try toBase(abs_base_wide);
                const receiver = self.registers[abs_base];

                var cont_val = try vm_continuations.captureContinuation(self, dst_reg, frame.base);
                self.gc.pushRoot(&cont_val);
                defer self.gc.popRoot();

                if (types.isClosure(receiver)) {
                    const closure = types.toObject(receiver).as(types.Closure);
                    const func = closure.func;
                    if (!func.is_variadic and func.arity != 1) {
                        self.setErrorDetail("call/cc receiver: expected 1 argument, got arity {d}", .{func.arity});
                        return VMError.ArityMismatch;
                    }
                    if (func.is_variadic and func.arity > 1) {
                        self.setErrorDetail("call/cc receiver: expected at most 1 required argument, got {d}", .{func.arity});
                        return VMError.ArityMismatch;
                    }
                    self.registers[frame.base] = cont_val;
                    if (func.is_variadic and func.arity == 0) {
                        self.registers[frame.base] = try buildRestList(self.gc, self.registers[frame.base .. frame.base + 1]);
                    } else if (func.is_variadic) {
                        if (@as(usize, frame.base) + 1 >= self.registers.len) try self.ensureRegisterCapacity(@as(usize, frame.base) + 2);
                        self.registers[frame.base + 1] = types.NIL;
                    }
                    if (self.profile_mode) func.profile_calls += 1;
                    frame.closure = closure;
                    frame.code = func.code.items;
                    frame.ip = 0;
                } else if (types.isNativeFn(receiver)) {
                    const native = types.toObject(receiver).as(types.NativeFn);
                    const nargs_slice = &[_]Value{cont_val};
                    const return_dst = frame.dst;
                    const from_native_call = frame.returns_to_native;
                    const result = native.func(nargs_slice) catch |err| {
                        if (err == error.ContinuationInvoked) {
                            if (resumesHere(self, target_frame_count, scope_root_seq)) continue;
                            return VMError.ContinuationInvoked;
                        }
                        return vm_calls.mapNativeError(self, err, native.name, nargs_slice);
                    };
                    self.frame_count -= 1;
                    if (self.frame_count <= target_frame_count) return result;
                    if (from_native_call) return raiseDeadNativeReturn(self);
                    const caller = &self.frames[self.frame_count - 1];
                    const ret_idx = try registerIndex(self, caller.base, return_dst);
                    self.registers[ret_idx] = result;
                } else if (types.isContinuation(receiver)) {
                    const cont = types.toObject(receiver).as(types.Continuation);
                    if (cont.is_escape) {
                        try self.invokeEscape(cont, cont_val);
                    } else {
                        try self.performWindTransition(cont.wind_records[0..cont.wind_count], cont.wind_count);
                        try self.restoreContinuation(cont, cont_val);
                    }
                    if (resumesHere(self, target_frame_count, scope_root_seq)) continue;
                    return VMError.ContinuationInvoked;
                } else {
                    return VMError.NotAProcedure;
                }
            },
            .tail_eval => {
                const base_reg = readU16(self, frame);
                const nargs = readU8(self, frame);
                const abs_base_wide = @as(usize, frame.base) + @as(usize, base_reg);
                try ensureCallWindow(self, abs_base_wide, nargs);
                const abs_base: u32 = try toBase(abs_base_wide);
                const expr_val = self.registers[abs_base];

                const compiler_mod = @import("compiler.zig");
                const func_val = blk: {
                    if (nargs >= 2 and types.isEnvironment(self.registers[abs_base + 1])) {
                        const se = types.toEnvironment(self.registers[abs_base + 1]);
                        break :blk compiler_mod.compileExpressionInEnv(self.gc, expr_val, &self.macros, se.env, self.registers[abs_base + 1]) catch return VMError.CompileError;
                    }
                    break :blk compiler_mod.compileExpressionWithMacros(self.gc, expr_val, &self.macros, self.globals) catch return VMError.CompileError;
                };
                var closure_val = self.gc.allocClosure(func_val) catch return VMError.OutOfMemory;
                compiler_mod.Compiler.unrootFunction(self.gc, func_val);
                self.gc.pushRoot(&closure_val);
                defer self.gc.popRoot();

                const closure = types.toObject(closure_val).as(types.Closure);
                const func = closure.func;
                if (self.profile_mode) func.profile_calls += 1;
                frame.closure = closure;
                frame.code = func.code.items;
                frame.ip = 0;
            },
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

pub fn registerIndex(vm: *VM, base: u32, reg: u16) VMError!usize {
    const idx = @as(usize, base) + @as(usize, reg);
    if (idx >= vm.registers.len) return VMError.InvalidBytecode;
    return idx;
}

pub fn ensureCallWindow(vm: *VM, base: usize, nargs: u8) VMError!void {
    const hi = base + @as(usize, nargs) + 1;
    if (hi > vm.registers.len) try vm.ensureRegisterCapacity(hi);
}

fn toBase(base_wide: usize) VMError!u32 {
    if (base_wide > std.math.maxInt(u32)) return VMError.StackOverflow;
    return @intCast(base_wide);
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

noinline fn raiseUndefinedVariable(self: *VM, name: []const u8) VMError {
    if (self.findSimilarName(name)) |suggestion| {
        self.setErrorDetail("undefined variable '{s}'. Did you mean '{s}'?", .{ name, suggestion });
    } else {
        self.setErrorDetail("undefined variable '{s}'", .{name});
    }
    return VMError.UndefinedVariable;
}

inline fn lookupGlobalLocked(self: *VM, env: *std.StringHashMap(Value), name: []const u8) ?Value {
    self.lockGlobalsShared();
    const found: ?Value = env.get(name) orelse blk: {
        const b = types.stripHygienicPrefix(name);
        if (b.len != name.len) {
            if (env.get(b)) |bval| break :blk bval;
        }
        break :blk null;
    };
    self.unlockGlobalsShared();
    return found;
}

pub fn buildRestList(gc: *memory.GC, args: []const Value) VMError!Value {
    var rest_list: Value = types.NIL;
    gc.pushRoot(&rest_list);
    var i: usize = args.len;
    while (i > 0) {
        i -= 1;
        rest_list = gc.allocPair(args[i], rest_list) catch {
            gc.popRoot();
            return VMError.OutOfMemory;
        };
    }
    gc.popRoot();
    return rest_list;
}
