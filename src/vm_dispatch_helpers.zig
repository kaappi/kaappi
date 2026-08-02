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

pub fn registerIndex(vm: *VM, base: u32, reg: u16) VMError!usize {
    const idx = @as(usize, base) + @as(usize, reg);
    if (idx >= vm.registers.len) return VMError.InvalidBytecode;
    return idx;
}

pub fn ensureCallWindow(vm: *VM, base: usize, nargs: u8) VMError!void {
    const hi = base + @as(usize, nargs) + 1;
    if (hi > vm.registers.len) try vm.ensureRegisterCapacity(hi);
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
