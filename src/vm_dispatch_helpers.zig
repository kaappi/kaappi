//! Support layer for the bytecode dispatch loop (vm_dispatch.zig): operand
//! readers, register-window validation, constant access, the shared
//! global-resolution helper every global-reference opcode routes through
//! (kaappi#1831/#1860), the noinline error raisers those paths delegate to,
//! and rest-argument list building. vm_dispatch.zig re-exports each name, so
//! the loop's call sites and external vm_dispatch.X references are unchanged.

const std = @import("std");
const types = @import("types.zig");
const Value = types.Value;

const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const VMError = vm_mod.VMError;
const CallFrame = vm_mod.CallFrame;

const memory = @import("memory.zig");
const library = @import("library.zig");

/// kaappi#1924: the catchable error a bytecode store (set_upvalue,
/// set_box_local, set_global, define_global) raises when it would install a
/// pointer to the running thread's own heap object into an object shared
/// with another thread. Mirrors the primitive-level raiseCrossHeapStore
/// (primitives.zig); the store is rejected before it happens.
pub noinline fn raiseCrossHeapStoreVM(self: *VM, comptime proc: []const u8) VMError {
    var buf: [320]u8 = undefined;
    const msg = std.fmt.bufPrint(
        &buf,
        "{s}: cannot store an object created on this thread into a heap object shared with another thread (it would dangle once this thread's heap is freed); pass values through the thread thunk, a channel message, or a join result instead",
        .{proc},
    ) catch "cross-heap store rejected";
    var message = self.gc.allocString(msg) catch return VMError.OutOfMemory;
    self.gc.pushRoot(&message);
    const err_obj = self.gc.allocErrorObject(message, types.NIL) catch {
        self.gc.popRoot();
        return VMError.OutOfMemory;
    };
    self.gc.popRoot();
    self.current_exception = err_obj;
    return VMError.ExceptionRaised;
}

/// A frame with returns_to_native set (pushed by vm.callWithArgs) delivers its
/// result via its own runUntil session's return value; its dst is a
/// placeholder. When such a frame returns while frame_count is still above
/// the dispatching loop's target, that session — the native Zig caller
/// (apply, a native higher-order driver like SRFI-1 fold or
/// hash-table-update!, eval, a wind thunk, ...) that owned the result — has
/// already returned:
/// a continuation captured under the native call was resumed after the call
/// ended. There is no register to deliver into and the native's iteration
/// state is gone, so raise a catchable Scheme error instead of silently
/// writing the value into an unrelated caller register.
pub noinline fn raiseDeadNativeReturn(self: *VM) VMError {
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

pub fn ensureOperands(vm: *VM, frame: *CallFrame, operand_bytes: usize) VMError!void {
    _ = vm;
    if (frame.ip + operand_bytes > frame.code.len) return VMError.InvalidBytecode;
}

/// Resolve `base + reg` to an absolute register index. Past the end of the
/// register file this is `StackOverflow`, not `InvalidBytecode`: the file is
/// the stack resource, and `ensureRegisterCapacity` already reports running
/// off its end as StackOverflow. Reporting it as KP9001 "internal error"
/// misdirected a reader and — because InvalidBytecode is not in
/// `errors.isUncatchable` — let a `guard` swallow the limit as a bare
/// `#<error "error">` (#2035). A tail-position call's locals can exceed the
/// replaced frame's window, and the tail-call paths re-ensure it via
/// `ensureTailWindow`; every fresh frame is ensured at creation. What is left
/// to trip this check is either the genuine MAX_REGISTER_LIMIT (a runaway
/// program, which must not be catchable) or bytecode so corrupt that no
/// meaningful diagnostic survives anyway.
pub fn registerIndex(vm: *VM, base: u32, reg: u16) VMError!usize {
    const idx = @as(usize, base) + @as(usize, reg);
    if (idx >= vm.registers.len) return VMError.StackOverflow;
    return idx;
}

pub fn ensureCallWindow(vm: *VM, base: usize, nargs: u8) VMError!void {
    const hi = base + @as(usize, nargs) + 1;
    if (hi > vm.registers.len) try vm.ensureRegisterCapacity(hi);
}

/// A tail-position call (tail_call, tail_apply, tail_call_global) and a
/// call/cc receiver in tail position replace the current frame's code in
/// place: the frame's base and register window are unchanged, but the new
/// function's `locals_count` may exceed the replaced frame's window. Without
/// a fresh ensure, the register file silently stops growing at the replaced
/// frame's smaller bound, and a register read a few slots past it aborts an
/// ordinary program at a fraction of the documented MAX_REGISTER_LIMIT with
/// a catchable KP9001 (#2035). This re-ensures the same bound callClosure
/// guarantees when it builds a fresh frame — `base + max(arg_count,
/// locals_count) + 1`, so a variadic callee's rest slot is covered too — and
/// past the cap `ensureRegisterCapacity` reports StackOverflow like every
/// other VM stack.
pub fn ensureTailWindow(vm: *VM, base: usize, arg_count: usize, locals_count: u16) VMError!void {
    try vm.ensureRegisterCapacity(base + @max(arg_count, @as(usize, locals_count)) + 1);
}

pub fn toBase(base_wide: usize) VMError!u32 {
    if (base_wide > std.math.maxInt(u32)) return VMError.StackOverflow;
    return @intCast(base_wide);
}

/// A tail-position `apply` flattened more arguments than this opcode's u8
/// `nargs` can encode. That is a limit on one call's argument list, not on the
/// stack, so it is InvalidArgument (KP3007) and stays catchable — unlike
/// genuine stack exhaustion, which #1886 made uncatchable.
///
/// Catchable is load-bearing, not just tidier: this same bound is what ends
/// the flattening walk of a *circular* argument list, and
/// `tests/scheme/audit/primitives_core-audit.scm` pins `(apply + <circular>)`
/// as recoverable. Reporting StackOverflow both sent readers hunting for
/// runaway recursion and, once limits stopped being catchable, would have
/// made a bad argument list unrecoverable.
/// The non-tail `apply` opcode's type errors, worded exactly like the native
/// `applyFn`'s (`primitives.typeError("apply", ...)`) rather than like
/// `tail_apply`'s terser in-loop texts (kaappi#2451).
///
/// The wording is load-bearing, not cosmetic: non-tail position is where
/// `tests/scheme/compile/native-apply-lowering-1803.sh` pins the interpreter's
/// diagnostics against the LLVM backend's, which reaches `applyFn`'s texts
/// through `@kaappi_apply`. Tail position is deliberately exempt there — its
/// texts have always differed — so only this opcode has parity to keep.
pub noinline fn raiseApplyTypeError(vm: *VM, expected: []const u8, got: Value) VMError {
    var buf: [128]u8 = undefined;
    const primitives = @import("primitives.zig");
    const desc = primitives.safeValueDescription(&buf, got);
    vm.setErrorDetail("type error in 'apply': expected {s}, got {s}", .{ expected, desc });
    return VMError.TypeError; // bare-ok: detail set above, matching primitives.typeError
}

/// The whole body of the non-tail `apply` opcode (kaappi#2451): validate the
/// operands, stage the flattened arguments, and make the call. Lives here
/// rather than in the dispatch arm because `vm_dispatch.zig` is at the
/// 1500-line policy ceiling, and because operand validation and argument
/// staging are what this file already holds for every other opcode.
///
/// The caller keeps exactly what a helper cannot express: the `continue` that
/// resumes a restored continuation in *that* dispatch loop, and the ip rewind
/// for a parked fiber's retry.
///
/// `registers[abs_base]` receives the result, matching the `call` opcode.
pub fn dispatchApply(vm: *VM, frame_base: u32, base_reg: u16, nargs: u8) VMError!void {
    const vm_calls = @import("vm_calls.zig");
    if (nargs == 0) return VMError.InvalidBytecode;
    const abs_base_wide = @as(usize, frame_base) + @as(usize, base_reg);
    try ensureCallWindow(vm, abs_base_wide, nargs);
    const abs_base: u32 = try toBase(abs_base_wide);
    const proc = vm.registers[abs_base];

    // applyFn's order and wording, both deliberate: the callee is rejected
    // before the operand list is walked, and the texts are the native ones
    // (see raiseApplyTypeError).
    if (!types.isProcedure(proc) and !types.isNativeFn(proc))
        return raiseApplyTypeError(vm, "procedure", proc);

    const operand_list = vm.registers[abs_base + nargs];
    const count = @as(usize, nargs - 1) + try properListLength(vm, operand_list);

    if (count > std.math.maxInt(u8)) {
        // More arguments than a call frame's u8 `nargs` can encode. #649
        // settled that non-tail `apply` has no such ceiling — `(apply + (mk
        // 500))` is a supported program — so this stays on applyFn's own
        // route: stage the arguments on the heap and re-enter through
        // `callWithArgs`. That route is exactly the one whose Zig frame makes
        // a captured continuation unresumable, so a >255-argument apply keeps
        // the restriction this opcode lifts for every other call. Tail
        // position instead *rejects* the call (tooManyApplyArgs), because
        // `tail_apply` has nowhere to put the overflow.
        var big: std.ArrayList(Value) = .empty;
        defer big.deinit(vm.gc.allocator);
        big.ensureTotalCapacity(vm.gc.allocator, count) catch return VMError.OutOfMemory;
        var fi: u8 = 0;
        while (fi + 1 < nargs) : (fi += 1) big.appendAssumeCapacity(vm.registers[abs_base + 1 + fi]);
        // Every staged Value is still reachable from a register (the fixed
        // operands) or from the operand list (itself in a register), so the
        // slice needs no rooting of its own. This path never overwrites the
        // operand list's register, so it needs no repair below.
        var walk = operand_list;
        while (walk != types.NIL) : (walk = types.cdr(walk)) big.appendAssumeCapacity(types.car(walk));

        vm.registers[abs_base] = try vm.callWithArgs(proc, big.items);
        return;
    }

    var flat: [256]Value = undefined;
    {
        var fi: u8 = 0;
        while (fi + 1 < nargs) : (fi += 1) flat[fi] = vm.registers[abs_base + 1 + fi];
        var i: usize = nargs - 1;
        var walk = operand_list;
        while (walk != types.NIL) : (walk = types.cdr(walk)) {
            flat[i] = types.car(walk);
            i += 1;
        }
    }

    const total: u8 = @intCast(count);
    try ensureCallWindow(vm, abs_base_wide, total);
    // This overwrites abs_base + nargs — the operand list's own register — as
    // soon as the list is non-empty.
    for (0..count) |i| vm.registers[abs_base + 1 + i] = flat[i];

    vm_calls.callValue(vm, proc, abs_base, total) catch |err| {
        // A parked fiber's retry rewinds ip and re-executes the whole
        // instruction, which re-reads the register just overwritten. Repair it
        // here, where the invariant was broken, rather than making every
        // caller remember to.
        if (err == VMError.Yielded and vm.yield_retry) vm.registers[abs_base + nargs] = operand_list;
        return err;
    };
}

/// The length of `list`, rejecting an improper or circular one with applyFn's
/// own text. The tortoise-and-hare is applyFn's too: a circular final list
/// must be named as an improper list, not walked forever (nor counted up to
/// the 255-argument limit and reported as one).
fn properListLength(vm: *VM, list: Value) VMError!usize {
    var len: usize = 0;
    var rest = list;
    var slow = rest;
    var step: bool = false;
    while (rest != types.NIL) {
        if (!types.isPair(rest)) return raiseApplyTypeError(vm, "proper list", rest);
        len += 1;
        rest = types.cdr(rest);
        if (step) {
            slow = types.cdr(slow);
            if (slow == rest) return raiseApplyTypeError(vm, "proper list", rest);
        }
        step = !step;
    }
    return len;
}

pub fn tooManyApplyArgs(vm: *VM) VMError {
    vm.setErrorDetail("apply: too many arguments (limit 255)", .{});
    return VMError.InvalidArgument;
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

pub noinline fn rejectImmutableEnv(self: *VM, func: *types.Function, name: []const u8, comptime verb: []const u8) ?VMError {
    if (types.isEnvironment(func.env_val) and types.toEnvironment(func.env_val).immutable) {
        self.setErrorDetail(verb ++ " '{s}' in immutable environment", .{name});
        return VMError.InvalidArgument;
    }
    return null;
}

pub noinline fn raiseUndefinedVariable(self: *VM, name: []const u8) VMError {
    if (self.findSimilarName(name)) |suggestion| {
        self.setErrorDetail("undefined variable '{s}'. Did you mean '{s}'?", .{ name, suggestion });
        // Carry the correction structurally so --diagnostics=json can emit it as
        // a `data.suggestions` rename (kaappi#1505). `suggestion` is a globals
        // key, stable for the VM's lifetime.
        self.last_error_suggestion = suggestion;
    } else {
        self.setErrorDetail("undefined variable '{s}'", .{name});
    }
    return VMError.UndefinedVariable;
}

/// Resolve a global reference made by `func`: its own environment first, then
/// the VM globals when `func` runs in a library (or `eval`) environment, then
/// both again with any hygienic rename prefix stripped.
///
/// The three global-reference opcodes must all resolve through here.
/// `get_global`, `call_global`, and `tail_call_global` describe the *same*
/// reference — which one the compiler emits depends only on syntactic position
/// (operand vs. operator, tail vs. non-tail) — so a name that resolves under
/// one has to resolve under the others. They disagreed: only `get_global`
/// carried the vm.globals fallback library code needs (455f5cc2), so a library
/// body calling a global it hadn't imported (`cadar`, a `%`-prefixed internal
/// primitive) worked in tail position, where the compiler emits get_global plus
/// a plain tail_call, and raised "undefined variable" in every other position,
/// where it emits call_global (kaappi#1831).
///
/// `restricted_globals` had the same defect one level up: it was derived
/// per-function, so it landed on the outer function of a form and on none of
/// the closures inside it. A library body — which must *not* be restricted —
/// therefore failed at its own top level and worked inside a lambda, while a
/// restricted environment — which must be — blocked its top level and leaked
/// through one. It is now a property of the environment, set by
/// compiler.EnvKind and inherited by every nested function (kaappi#1860).
pub inline fn lookupGlobalLocked(self: *VM, func: *types.Function, name: []const u8) ?Value {
    const env: *std.StringHashMap(Value) = func.env orelse self.globals;
    if (vm_mod.globals_mod.stripBaseBindingPrefix(name)) |base_name| {
        return resolveBaseBindingLocked(self, env, base_name);
    }
    if (vm_mod.globals_mod.parseDefEnvBindingSymbolName(name)) |parts| {
        return vm_mod.globals_mod.lookupDefEnvBinding(parts.libname, parts.origname);
    }
    // Map reads under the child-thread shared lock; the error path runs after
    // release (findSimilarName locks internally).
    self.lockGlobalsShared();
    defer self.unlockGlobalsShared();
    return env.get(name) orelse blk: {
        if (func.env != null and !func.restricted_globals) {
            if (self.globals.get(name)) |gval| break :blk gval;
        }
        // Hygienic-prefix fallback is intentionally ungated by
        // restricted_globals: macro-introduced references must still resolve
        // through globals even in restricted envs.
        const base = types.stripHygienicPrefix(name);
        if (base.len != name.len) {
            if (env.get(base)) |bval| break :blk bval;
            if (env != self.globals) {
                if (self.globals.get(base)) |gval| break :blk gval;
            }
        }
        break :blk null;
    };
}

/// Resolve a `globals_mod.base_binding_prefix`-marked name (#1715): prefer
/// the true `(scheme base)` binding, immune to redefinition; degrade to an
/// ordinary lookup of the unprefixed name only in the bootstrap edge case
/// where that registry isn't populated yet (scheme.base not registered).
inline fn resolveBaseBindingLocked(self: *VM, env: *std.StringHashMap(Value), base_name: []const u8) ?Value {
    if (vm_mod.globals_mod.lookupBaseBinding(base_name)) |val| return val;
    self.lockGlobalsShared();
    defer self.unlockGlobalsShared();
    return env.get(base_name);
}

/// Resolve the global that constant `sym_idx` names, through `func`'s
/// per-function global cache when it has one — the read `get_global`
/// performs, shared with `guard_builtin` (kaappi#2469). A cache entry is
/// only ever a closure or native procedure resolved through the ordinary
/// (non-def-env, #1812) route, and the whole cache is dropped whenever
/// the shared global version moves, so a stale procedure can never be
/// served after a rebinding (#812) — by this thread or any other
/// (kaappi#2483). Raises the undefined-variable error for an unbound name.
pub fn lookupGlobalCached(self: *VM, func: *types.Function, sym_idx: u16) VMError!Value {
    // One snapshot, taken before the map read, stamps every cache fill
    // below: see VM.globalVersion for why a fresh load after the read would
    // re-bless a value another thread has since rebound.
    const gv = self.globalVersion();
    if (func.env == null) {
        if (func.global_cache) |cache| {
            if (func.cache_version == gv and
                sym_idx < cache.len and cache[sym_idx] != types.VOID)
            {
                return cache[sym_idx];
            }
            if (func.cache_version != gv) {
                @memset(cache, types.VOID);
                func.cache_version = gv;
            }
        }
    }
    const sym = try constantAt(self, func, sym_idx);
    if (!types.isSymbol(sym)) return VMError.InvalidBytecode;
    const name = types.symbolName(sym);
    // #1812: skip caching a def_env_binding_prefix reference — its
    // resolution isn't invalidated by the global version (a library's own
    // internal set! on its def_env doesn't bump it, since that mutation's
    // func.env isn't null), so caching it under that version could go stale.
    const def_env_parts = vm_mod.globals_mod.parseDefEnvBindingSymbolName(name);
    const val = lookupGlobalLocked(self, func, name) orelse
        return raiseUndefinedVariable(self, name);
    if (func.env == null and def_env_parts == null and (types.isClosure(val) or types.isNativeFn(val))) {
        if (func.global_cache) |cache| {
            if (sym_idx < cache.len) cache[sym_idx] = val;
        } else {
            // A cache is an optimization: no memory for one just means the
            // next reference resolves by name again.
            const cache = self.gc.allocator.alloc(Value, func.constants.items.len) catch return val;
            @memset(cache, types.VOID);
            cache[sym_idx] = val;
            func.global_cache = cache;
            func.cache_version = gv;
        }
        // #1961 (review): the cached value is root-marked right now (it is
        // also in the globals map), but a later rebinding by another
        // function orphans this slot — only this function's own next global
        // op clears it — and the generational minor mark reaches the
        // orphaned young value only through the remembered set. The function
        // itself may already be promoted, including on the fresh-cache path.
        self.gc.writeBarrier(&func.header, val);
    }
    return val;
}

/// `guard_builtin dst, sym_idx, kind, offset` (kaappi#2469): the run-time
/// half of the builtin-superinstruction gate. Resolves the operator's global
/// into `dst` exactly as `get_global` would, then lets execution fall through
/// to the superinstruction only while that value is still the pristine
/// primitive `library.fast_path_builtins[kind]`; anything else — a user
/// procedure, a non-procedure, a re-registered primitive — jumps `offset` to
/// the ordinary call the compiler emitted after the fast path, which calls
/// whatever `dst` now holds. R7RS 5.3.1 makes a top-level definition
/// essentially an assignment, so this is the only place the question can be
/// answered honestly: a compile-time read (#2033) or a whole-unit pre-scan
/// (#2457) is baked into bytecode that may run after a `load`, an `eval`, a
/// REPL form, or a macro-materialized `set!` rebinds the name.
///
/// A pristine slot left VOID (the primitive was never registered, e.g. a
/// sandbox that excludes `eval`) never matches, so such a guard always takes
/// the ordinary call — which is also where an unbound name reports its
/// undefined-variable error, from the lookup above.
pub fn guardBuiltin(self: *VM, frame: *CallFrame) VMError!void {
    const dst = readU16(self, frame);
    const sym_idx = readU16(self, frame);
    const kind = readU8(self, frame);
    const offset = readI16(self, frame);
    const closure = frame.closure orelse return VMError.InvalidBytecode;
    const dst_idx = try registerIndex(self, frame.base, dst);
    if (kind >= library.fast_path_builtins.len) return VMError.InvalidBytecode;
    const val = try lookupGlobalCached(self, closure.func, sym_idx);
    self.registers[dst_idx] = val;
    const pristine = self.libraries.fast_path_pristine[kind];
    if (pristine != types.VOID and val == pristine) return;
    const new_ip = @as(isize, @intCast(frame.ip)) + offset;
    if (new_ip < 0) return VMError.InvalidBytecode;
    const target: usize = @intCast(new_ip);
    if (target > frame.code.len) return VMError.InvalidBytecode;
    frame.ip = target;
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
