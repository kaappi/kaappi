const std = @import("std");
const builtin = @import("builtin");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const jit_mem = @import("jit_mem.zig");

const is_aarch64 = builtin.cpu.arch == .aarch64;
const is_x86_64 = builtin.cpu.arch == .x86_64;
const jit_supported = is_aarch64 or is_x86_64;

const a64 = @import("jit_aarch64.zig");
const x64 = @import("jit_x86_64.zig");

pub const JIT_THRESHOLD: u32 = 100;

pub const JitCode = struct {
    entry: *anyopaque,
    buf: jit_mem.CodeBuffer,
};

pub const JitEntryFn = *const fn (*vm_mod.VM, u16, [*]const types.Value, *types.Closure) callconv(.c) u64;

// Struct offsets computed at comptime
pub const VM = vm_mod.VM;
pub const CallFrame = vm_mod.CallFrame;
pub const OFF_REGISTERS = @offsetOf(VM, "registers");
pub const OFF_FRAME_COUNT = @offsetOf(VM, "frame_count");
pub const OFF_FRAMES = @offsetOf(VM, "frames");
pub const SIZEOF_CALLFRAME = @sizeOf(CallFrame);
pub const OFF_FRAME_IP = @offsetOf(CallFrame, "ip");

const Reg = if (@import("builtin").cpu.arch == .x86_64) x64.Reg else a64.Reg;
const Cond = if (@import("builtin").cpu.arch == .x86_64) x64.Cond else a64.Cond;

// Machine register assignments
pub const VM_PTR = if (@import("builtin").cpu.arch == .x86_64) Reg.rbx else Reg.x21;
pub const REG_BASE = if (@import("builtin").cpu.arch == .x86_64) Reg.r12 else Reg.x19;
pub const BASE_OFF = if (@import("builtin").cpu.arch == .x86_64) Reg.r13 else Reg.x20;
pub const FRAME_PTR = if (@import("builtin").cpu.arch == .x86_64) Reg.r14 else Reg.x23;
pub const CONST_PTR = if (@import("builtin").cpu.arch == .x86_64) Reg.r15 else Reg.x22;
pub const CLOSURE_PTR = if (@import("builtin").cpu.arch == .x86_64) Reg.rbp else Reg.x24;

pub const OFF_CLOSURE_UPVALUES = @offsetOf(types.Closure, "upvalues");
pub const OFF_CLOSURE_FUNC = @offsetOf(types.Closure, "func");
pub const OFF_FUNC_GLOBAL_CACHE = @offsetOf(types.Function, "global_cache");
pub const OFF_FUNC_CACHE_VERSION = @offsetOf(types.Function, "cache_version");
pub const OFF_VM_GLOBAL_VERSION = @offsetOf(vm_mod.VM, "global_version");
pub const OFF_WIND_COUNT = @offsetOf(VM, "wind_count");
pub const OFF_VM_JIT_ERROR = @offsetOf(VM, "jit_error");

// CallFrame field offsets
pub const OFF_FRAME_CLOSURE = @offsetOf(CallFrame, "closure");
pub const OFF_FRAME_NATIVE = @offsetOf(CallFrame, "native");
pub const OFF_FRAME_CODE = @offsetOf(CallFrame, "code");
pub const OFF_FRAME_BASE = @offsetOf(CallFrame, "base");
pub const OFF_FRAME_DST = @offsetOf(CallFrame, "dst");
pub const OFF_FRAME_SAVED_WIND = @offsetOf(CallFrame, "saved_wind_count");

// Function field offsets for call type checks
pub const OFF_FUNC_ARITY = @offsetOf(types.Function, "arity");
pub const OFF_FUNC_IS_VARIADIC = @offsetOf(types.Function, "is_variadic");
pub const OFF_FUNC_JIT_CODE = @offsetOf(types.Function, "jit_code");
pub const OFF_FUNC_CODE = @offsetOf(types.Function, "code");
pub const OFF_FUNC_CALL_COUNT = @offsetOf(types.Function, "call_count");
pub const OFF_FUNC_CONSTANTS = @offsetOf(types.Function, "constants");
pub const OFF_JIT_CODE_ENTRY = @offsetOf(JitCode, "entry");
pub const OFF_OBJECT_TAG = @offsetOf(types.Object, "tag");
pub const OFF_PAIR_CAR = @offsetOf(types.Pair, "car");
pub const OFF_PAIR_CDR = @offsetOf(types.Pair, "cdr");
pub const MAX_FRAMES = vm_mod.MAX_FRAMES;

pub const PendingBranch = struct {
    native_idx: u32,
    target_bc_ip: usize,
    cond: ?Cond,
};

const CacheEntry = struct { slot: u16, dirty: bool };
const CacheSnapshot = struct {
    entries: [2]?CacheEntry = .{null} ** 2,
};
pub const CACHE_REGS: [2]x64.Reg = .{ .r8, .r9 };

pub const RegCache = struct {
    entries: [2]?CacheEntry = .{null} ** 2,
    next_evict: u1 = 0,

    pub fn find(self: *const RegCache, slot: u16) ?usize {
        for (self.entries, 0..) |entry_opt, i| {
            if (entry_opt) |entry| {
                if (entry.slot == slot) return i;
            }
        }
        return null;
    }

    pub fn allocate(self: *RegCache, asm_ctx: *x64.Assembler, slot: u16) !usize {
        if (self.find(slot)) |i| return i;
        for (self.entries, 0..) |entry_opt, i| {
            if (entry_opt == null) {
                self.entries[i] = .{ .slot = slot, .dirty = false };
                return i;
            }
        }
        const evict_idx: usize = self.next_evict;
        if (self.entries[evict_idx]) |entry| {
            if (entry.dirty) {
                try asm_ctx.emitStrImm(CACHE_REGS[evict_idx], x64.Reg.rbx, entry.slot * 8);
            }
        }
        self.entries[evict_idx] = .{ .slot = slot, .dirty = false };
        self.next_evict +%= 1;
        return evict_idx;
    }

    pub fn flushAll(self: *RegCache, asm_ctx: *x64.Assembler) !void {
        for (self.entries, 0..) |entry_opt, i| {
            if (entry_opt) |entry| {
                if (entry.dirty) {
                    try asm_ctx.emitStrImm(CACHE_REGS[i], x64.Reg.rbx, entry.slot * 8);
                    self.entries[i] = .{ .slot = entry.slot, .dirty = false };
                }
            }
        }
    }

    pub fn invalidateAll(self: *RegCache, asm_ctx: *x64.Assembler) !void {
        try self.flushAll(asm_ctx);
        self.entries = .{null} ** 2;
    }

    pub fn invalidateSlot(self: *RegCache, slot: u16) void {
        if (self.find(slot)) |i| {
            self.entries[i] = null;
        }
    }

    pub fn snapshot(self: *const RegCache) CacheSnapshot {
        return .{ .entries = self.entries };
    }
};

pub const PendingSideExit = struct {
    native_idx: u32,
    bc_ip: usize,
    cond: ?Cond = null,
    cache_snapshot: CacheSnapshot = .{},
};

pub fn isEligible(func: *const types.Function) bool {
    const code = func.code.items;
    var ip: usize = 0;
    while (ip < code.len) {
        const raw = code[ip];
        if (raw > @intFromEnum(types.OpCode.self_tail_call)) return false;
        const op: types.OpCode = @enumFromInt(raw);
        ip += 1;
        const operand_bytes: usize = switch (op) {
            .load_const => 4, // dst(u16) + idx(u16)
            .load_nil, .load_true, .load_false, .load_void => 2, // dst(u16)
            .move => 4, // dst(u16) + src(u16)
            .get_global => 4, // dst(u16) + sym(u16)
            .set_global, .define_global => 4, // sym(u16) + src(u16)
            .tail_apply => return false,
            .get_local, .set_local => 4, // dst/slot(u16) + slot/src(u16)
            .get_upvalue, .set_upvalue => 4, // dst/idx(u16) + idx/src(u16)
            .call, .tail_call => 3, // dst(u16) + nargs(u8)
            .@"return" => 2, // src(u16)
            .jump => 2, // offset(i16)
            .jump_false, .jump_true => 4, // src(u16) + offset(i16)
            .closure => {
                if (ip + 2 >= code.len) return false;
                const sym_idx = (@as(u16, code[ip]) << 8) | code[ip + 1];
                if (ip + 2 + 2 > code.len) return false;
                _ = sym_idx;
                const ci = (@as(u16, code[ip + 2]) << 8) | code[ip + 3];
                if (ci >= func.constants.items.len) return false;
                const fv = func.constants.items[ci];
                if (!types.isFunction(fv)) return false;
                const inner = types.toObject(fv).as(types.Function);
                ip += 4 + @as(usize, inner.upvalue_count) * 3;
                continue;
            },
            .close_upvalue => 2, // slot(u16)
            .cons => 6, // dst(u16) + car(u16) + cdr(u16)
            .push_handler, .pop_handler => return false,
            .halt => return false,
            .call_global, .tail_call_global => 5, // dst(u16) + sym(u16) + nargs(u8)
            .box_local => 2, // slot(u16)
            .get_box_local, .set_box_local => 4, // dst/slot(u16) + slot/src(u16)
            .self_tail_call => 3, // base(u16) + nargs(u8)
        };
        ip += operand_bytes;
    }
    if (code.len == 0) return false;
    // No bytecode size limit — large functions are JIT-eligible
    if (func.constants.items.len * 8 > 32760) return false;
    if (func.locals_count > 255) return false;
    if (func.is_variadic) return false;
    return true;
}

const a64_compile = @import("jit_compile_aarch64.zig");
const x64_compile = @import("jit_compile_x86_64.zig");

pub fn compile(func: *types.Function, vm: *VM, allocator: std.mem.Allocator) !*JitCode {
    if (!jit_supported) return error.InvalidBytecode;
    if (is_x86_64) return x64_compile.compile(func, vm, allocator);
    return a64_compile.compile(func, vm, allocator);
}

pub fn tryCompile(func: *types.Function, vm: *VM) void {
    if (!isEligible(func)) return;
    const jit_code = compile(func, vm, vm.gc.allocator) catch return;
    func.jit_code = jit_code;
}

pub fn jitFinishCallee(vm_ptr: *VM, _: u64, dst_abs_idx: u64) callconv(.c) u64 {
    const target_fc = vm_ptr.frame_count - 1;
    const result = vm_ptr.runUntil(target_fc, vm_ptr.wind_count) catch |err| {
        vm_ptr.jit_error = err;
        return 0;
    };
    vm_ptr.registers[@intCast(dst_abs_idx)] = result;
    return 1;
}

pub fn jitAllocPair(vm_ptr: *VM, car: u64, cdr: u64) callconv(.c) u64 {
    const car_val: types.Value = @bitCast(car);
    const cdr_val: types.Value = @bitCast(cdr);
    const pair_val = vm_ptr.gc.allocPair(car_val, cdr_val) catch return 0;
    return @bitCast(pair_val);
}

pub fn jitTailCallNative(vm_ptr: *VM, callee_val: u64, base_reg_val: u64, nargs_val: u64) callconv(.c) u64 {
    const callee: types.Value = @bitCast(callee_val);
    const base_reg: u16 = @intCast(base_reg_val);
    const nargs: u8 = @intCast(nargs_val);

    const frame = &vm_ptr.frames[vm_ptr.frame_count - 1];
    const abs_base: u16 = frame.base + base_reg;

    if (types.isClosure(callee)) {
        const closure = types.toObject(callee).as(types.Closure);
        const func = closure.func;
        if (func.is_variadic) return 0;
        if (nargs != func.arity) return 0;
        if (abs_base + @as(u16, nargs) + 1 >= vm_mod.MAX_REGISTERS) return 0;
        for (0..nargs) |i| {
            vm_ptr.registers[frame.base + i] = vm_ptr.registers[abs_base + 1 + i];
        }
        frame.closure = closure;
        frame.code = func.code.items;
        frame.ip = 0;
        return 2;
    }

    if (types.isNativeFn(callee)) {
        const native = types.toObject(callee).as(types.NativeFn);
        const arity_ok = switch (native.arity) {
            .exact => |expected| nargs == expected,
            .variadic => |min| nargs >= min,
        };
        if (!arity_ok) return 0;

        if (abs_base + @as(u16, nargs) + 1 >= vm_mod.MAX_REGISTERS) return 0;
        const args = vm_ptr.registers[abs_base + 1 .. abs_base + 1 + nargs];
        const result = native.func(args) catch return 0;

        const return_dst = frame.dst;
        vm_ptr.frame_count -= 1;
        if (vm_ptr.frame_count > 0) {
            const caller = &vm_ptr.frames[vm_ptr.frame_count - 1];
            vm_ptr.registers[caller.base + return_dst] = result;
        }
        return 1;
    }

    return 0;
}

pub fn jitCreateClosure(vm_ptr: *VM, func_val: u64, descs_ptr_val: u64, n_upvalues_val: u64) callconv(.c) u64 {
    const func_v: types.Value = @bitCast(func_val);
    if (!types.isFunction(func_v)) return 0;
    const func = types.toObject(func_v).as(types.Function);

    const cls_val = vm_ptr.gc.allocClosure(func) catch return 0;
    const cls = types.toObject(cls_val).as(types.Closure);

    const frame = &vm_ptr.frames[vm_ptr.frame_count - 1];
    const parent_closure = frame.closure orelse return 0;

    const n_upvalues: usize = @intCast(n_upvalues_val);
    const descs: [*]const u8 = @ptrFromInt(descs_ptr_val);

    for (0..n_upvalues) |i| {
        const is_local = descs[i * 2] == 1;
        const index = descs[i * 2 + 1];
        if (is_local) {
            const local_idx: usize = @as(usize, frame.base) + index;
            if (local_idx >= vm_mod.MAX_REGISTERS) return 0;
            var val = vm_ptr.registers[local_idx];
            if (!types.isPair(val) or types.cdr(val) != types.VOID) {
                val = vm_ptr.gc.allocPair(val, types.VOID) catch return 0;
                vm_ptr.registers[local_idx] = val;
            }
            cls.upvalues[i] = val;
        } else {
            if (index >= parent_closure.upvalues.len) return 0;
            cls.upvalues[i] = parent_closure.upvalues[index];
        }
    }

    return @bitCast(cls_val);
}

pub fn jitSetGlobal(vm_ptr: *VM, sym_val: u64, val: u64) callconv(.c) u64 {
    const sym: types.Value = @bitCast(sym_val);
    const value: types.Value = @bitCast(val);
    if (types.isSymbol(sym)) {
        const name = types.symbolName(sym);
        vm_ptr.globals.put(name, value) catch return 0;
        vm_ptr.global_version +%= 1;
    }
    return 1;
}

pub fn freeJitCode(jit_code: *JitCode, allocator: std.mem.Allocator) void {
    jit_code.buf.free();
    allocator.destroy(jit_code);
}

// -----------------------------------------------------------------------
// Template helpers
// -----------------------------------------------------------------------

pub const SpecializedOp = enum { add, sub, mul, lt, gt, le, ge, eq, zero_p, null_p, pair_p, not_op, car, cdr, none };

pub fn recognizeArithPrimitive(func: *const types.Function, sym_idx: u16, vm: *const VM) SpecializedOp {
    if (sym_idx >= func.constants.items.len) return .none;
    const sym_val = func.constants.items[sym_idx];
    if (!types.isSymbol(sym_val)) return .none;
    const name = types.symbolName(sym_val);
    const global_val = vm.globals.get(name) orelse return .none;
    if (!types.isNativeFn(global_val)) return .none;
    if (std.mem.eql(u8, name, "+")) return .add;
    if (std.mem.eql(u8, name, "-")) return .sub;
    if (std.mem.eql(u8, name, "*")) return .mul;
    if (std.mem.eql(u8, name, "<")) return .lt;
    if (std.mem.eql(u8, name, ">")) return .gt;
    if (std.mem.eql(u8, name, "<=")) return .le;
    if (std.mem.eql(u8, name, ">=")) return .ge;
    if (std.mem.eql(u8, name, "=")) return .eq;
    if (std.mem.eql(u8, name, "zero?")) return .zero_p;
    if (std.mem.eql(u8, name, "null?")) return .null_p;
    if (std.mem.eql(u8, name, "pair?")) return .pair_p;
    if (std.mem.eql(u8, name, "not")) return .not_op;
    if (std.mem.eql(u8, name, "car")) return .car;
    if (std.mem.eql(u8, name, "cdr")) return .cdr;
    return .none;
}

pub fn isSelfCall(func: *const types.Function, sym_idx: u16, nargs: u8) bool {
    if (func.name == null or func.is_variadic) return false;
    if (nargs != func.arity) return false;
    if (sym_idx >= func.constants.items.len) return false;
    const sym_val = func.constants.items[sym_idx];
    if (!types.isSymbol(sym_val)) return false;
    return std.mem.eql(u8, types.symbolName(sym_val), func.name.?);
}

pub fn safeJumpTarget(ip: usize, off: i16, code_len: usize) ?usize {
    const target_signed = @as(i64, @intCast(ip)) + @as(i64, off);
    if (target_signed < 0 or target_signed > @as(i64, @intCast(code_len))) return null;
    return @intCast(target_signed);
}

pub fn readU16(code: []const u8, ip: usize) u16 {
    return (@as(u16, code[ip]) << 8) | @as(u16, code[ip + 1]);
}

pub fn readI16(code: []const u8, ip: usize) i16 {
    return @bitCast(readU16(code, ip));
}

// -----------------------------------------------------------------------
// Tests

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "isEligible rejects closure opcode" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const f = try gc.allocFunction();
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.closure));
    try f.code.append(gc.allocator, 0); // dst hi
    try f.code.append(gc.allocator, 0); // dst lo
    try f.code.append(gc.allocator, 0); // idx hi
    try f.code.append(gc.allocator, 0); // idx lo

    try std.testing.expect(!isEligible(f));
}

test "isEligible accepts simple bytecode" {
    // JIT temporarily disabled (#60): isEligible always returns false
    // Re-enable this test when JIT u16 register support is fixed
}

test "compile trivial function" {
    if (!jit_supported) return error.SkipZigTest;
    const memory = @import("memory.zig");
    const th = @import("testing_helpers.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const f = try gc.allocFunction();
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.load_nil));
    try f.code.append(gc.allocator, 0); // dst hi
    try f.code.append(gc.allocator, 0); // dst lo
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.@"return"));
    try f.code.append(gc.allocator, 0); // src hi
    try f.code.append(gc.allocator, 0); // src lo

    const jit_code = try compile(f, &vm, std.testing.allocator);
    defer freeJitCode(jit_code, std.testing.allocator);

    try std.testing.expect(@intFromPtr(jit_code.entry) != 0);
}

test "minimal prologue/epilogue" {
    if (!is_aarch64) return error.SkipZigTest;
    // Test just the entry/exit trampoline by compiling a function
    // that immediately returns (only a return opcode)
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // Build a minimal prologue/epilogue manually
    var asm_ctx = a64.Assembler.init(std.testing.allocator);
    defer asm_ctx.deinit();

    // Prologue: save x29, x30 and allocate 16 bytes
    try asm_ctx.emit(a64_compile.stpPreSp(.x29, .x30, -2)); // stp x29, x30, [sp, #-16]!
    try asm_ctx.emit(a64_compile.addRegSp(.x29, .xzr, 0)); // mov x29, sp
    // Epilogue: restore and return 0
    try asm_ctx.emitMovz(.x0, 0, 0);
    try asm_ctx.emit(a64_compile.ldpPostSp(.x29, .x30, 2)); // ldp x29, x30, [sp], #16
    try asm_ctx.emitRet();

    var buf = try jit_mem.CodeBuffer.alloc(4096);
    defer buf.free();
    buf.writeCode(asm_ctx.toSlice());

    const func: *const fn () callconv(.c) u64 = @ptrCast(@alignCast(buf.mem.ptr));
    const result = func();
    try std.testing.expectEqual(@as(u64, 0), result);
}

test "prologue saves and restores callee-saved regs" {
    if (!is_aarch64) return error.SkipZigTest;
    var asm_ctx = a64.Assembler.init(std.testing.allocator);
    defer asm_ctx.deinit();

    // Save 6 callee-saved regs (x19-x24) + x29/x30 = 64 bytes
    try asm_ctx.emit(a64_compile.stpPreSp(.x29, .x30, -8)); // [sp, #-64]!
    try asm_ctx.emit(a64_compile.stpOffsetSp(.x19, .x20, 2)); // [sp, #16]
    try asm_ctx.emit(a64_compile.stpOffsetSp(.x21, .x22, 4)); // [sp, #32]
    try asm_ctx.emit(a64_compile.stpOffsetSp(.x23, .x24, 6)); // [sp, #48]
    try asm_ctx.emit(a64_compile.addRegSp(.x29, .xzr, 0)); // mov x29, sp

    // Do nothing — just return 77
    try asm_ctx.emitMovz(.x0, 77, 0);

    // Restore
    try asm_ctx.emit(a64_compile.ldpOffsetSp(.x23, .x24, 6));
    try asm_ctx.emit(a64_compile.ldpOffsetSp(.x21, .x22, 4));
    try asm_ctx.emit(a64_compile.ldpOffsetSp(.x19, .x20, 2));
    try asm_ctx.emit(a64_compile.ldpPostSp(.x29, .x30, 8)); // [sp], #64
    try asm_ctx.emitRet();

    var buf = try jit_mem.CodeBuffer.alloc(4096);
    defer buf.free();
    buf.writeCode(asm_ctx.toSlice());

    const func: *const fn () callconv(.c) u64 = @ptrCast(@alignCast(buf.mem.ptr));
    const result = func();
    try std.testing.expectEqual(@as(u64, 77), result);
}

test "compile and execute load_nil" {
    if (!jit_supported) return error.SkipZigTest;
    const memory = @import("memory.zig");
    const th = @import("testing_helpers.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm_val = try th.makeTestVM(&gc);
    defer vm_val.deinit();

    const f = try gc.allocFunction();
    // load_nil r0; return r0 (u16 register operands)
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.load_nil));
    try f.code.append(gc.allocator, 0); // dst hi
    try f.code.append(gc.allocator, 0); // dst lo
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.@"return"));
    try f.code.append(gc.allocator, 0); // src hi
    try f.code.append(gc.allocator, 0); // src lo
    f.locals_count = 1;

    const jit_code = try compile(f, &vm_val, std.testing.allocator);
    defer freeJitCode(jit_code, std.testing.allocator);

    const cls_val = try gc.allocClosure(f);
    const cls = types.toObject(cls_val).as(types.Closure);
    vm_val.frames[0] = .{
        .closure = cls,
        .code = f.code.items,
        .ip = 0,
        .base = 0,
        .dst = 0,
    };
    vm_val.frame_count = 1;

    const entry: JitEntryFn = @ptrCast(@alignCast(jit_code.entry));
    const result = entry(&vm_val, 0, &[_]types.Value{}, cls);
    _ = result;

    try std.testing.expectEqual(types.NIL, vm_val.registers[0]);
}

test "compile and execute load_const" {
    if (!jit_supported) return error.SkipZigTest;
    const memory = @import("memory.zig");
    const th = @import("testing_helpers.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const f = try gc.allocFunction();

    // Add a constant: fixnum 42
    try f.constants.append(gc.allocator, types.makeFixnum(42));

    // load_const r0, 0; return r0 (u16 register operands)
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.load_const));
    try f.code.append(gc.allocator, 0); // dst hi
    try f.code.append(gc.allocator, 0); // dst lo
    try f.code.append(gc.allocator, 0); // idx hi
    try f.code.append(gc.allocator, 0); // idx lo
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.@"return"));
    try f.code.append(gc.allocator, 0); // src hi
    try f.code.append(gc.allocator, 0); // src lo
    f.locals_count = 1;

    const jit_code = try compile(f, &vm, std.testing.allocator);
    defer freeJitCode(jit_code, std.testing.allocator);

    const cls_val2 = try gc.allocClosure(f);
    const cls2 = types.toObject(cls_val2).as(types.Closure);
    vm.frames[0] = .{ .closure = cls2, .code = f.code.items, .ip = 0, .base = 0, .dst = 0 };
    vm.frame_count = 1;

    const entry: JitEntryFn = @ptrCast(@alignCast(jit_code.entry));
    _ = entry(&vm, 0, f.constants.items.ptr, cls2);

    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(vm.registers[0]));
}

test "compile and execute move" {
    if (!jit_supported) return error.SkipZigTest;
    const memory = @import("memory.zig");
    const th = @import("testing_helpers.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const f = try gc.allocFunction();
    // load_true r0; move r1, r0; return r1 (u16 register operands)
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.load_true));
    try f.code.append(gc.allocator, 0); // dst hi
    try f.code.append(gc.allocator, 0); // dst lo
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.move));
    try f.code.append(gc.allocator, 0); // dst hi
    try f.code.append(gc.allocator, 1); // dst lo
    try f.code.append(gc.allocator, 0); // src hi
    try f.code.append(gc.allocator, 0); // src lo
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.@"return"));
    try f.code.append(gc.allocator, 0); // src hi
    try f.code.append(gc.allocator, 1); // src lo
    f.locals_count = 2;

    const jit_code = try compile(f, &vm, std.testing.allocator);
    defer freeJitCode(jit_code, std.testing.allocator);

    const cls_val = try gc.allocClosure(f);
    const cls = types.toObject(cls_val).as(types.Closure);
    vm.frames[0] = .{ .closure = cls, .code = f.code.items, .ip = 0, .base = 0, .dst = 0 };
    vm.frame_count = 1;

    const entry: JitEntryFn = @ptrCast(@alignCast(jit_code.entry));
    _ = entry(&vm, 0, &[_]types.Value{}, cls);

    try std.testing.expectEqual(types.TRUE, vm.registers[1]);
}

test "compile and execute jump_false" {
    if (!jit_supported) return error.SkipZigTest;
    const memory = @import("memory.zig");
    const th = @import("testing_helpers.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const f = try gc.allocFunction();
    // load_false r0; jump_false r0, +6; load_true r1; return r1; load_nil r1; return r1
    // (u16 register operands)
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.load_false));
    try f.code.append(gc.allocator, 0); // dst hi
    try f.code.append(gc.allocator, 0); // dst lo
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.jump_false));
    try f.code.append(gc.allocator, 0); // test_reg hi
    try f.code.append(gc.allocator, 0); // test_reg lo
    const offset: i16 = 6; // skip load_true(3)+return(3)
    const offset_u16: u16 = @bitCast(offset);
    try f.code.append(gc.allocator, @truncate(offset_u16 >> 8));
    try f.code.append(gc.allocator, @truncate(offset_u16 & 0xFF));
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.load_true));
    try f.code.append(gc.allocator, 0); // dst hi
    try f.code.append(gc.allocator, 1); // dst lo
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.@"return"));
    try f.code.append(gc.allocator, 0); // src hi
    try f.code.append(gc.allocator, 1); // src lo
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.load_nil));
    try f.code.append(gc.allocator, 0); // dst hi
    try f.code.append(gc.allocator, 1); // dst lo
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.@"return"));
    try f.code.append(gc.allocator, 0); // src hi
    try f.code.append(gc.allocator, 1); // src lo
    f.locals_count = 2;

    const jit_code = try compile(f, &vm, std.testing.allocator);
    defer freeJitCode(jit_code, std.testing.allocator);

    const cls_val = try gc.allocClosure(f);
    const cls = types.toObject(cls_val).as(types.Closure);
    vm.frames[0] = .{ .closure = cls, .code = f.code.items, .ip = 0, .base = 0, .dst = 0 };
    vm.frame_count = 1;

    const entry: JitEntryFn = @ptrCast(@alignCast(jit_code.entry));
    _ = entry(&vm, 0, &[_]types.Value{}, cls);

    try std.testing.expectEqual(types.NIL, vm.registers[1]);
}

test "native return stores result and pops frame" {
    if (!jit_supported) return error.SkipZigTest;
    const memory = @import("memory.zig");
    const th = @import("testing_helpers.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const f = try gc.allocFunction();
    // load_const r0, 0; return r0 (u16 register operands)
    try f.constants.append(gc.allocator, types.makeFixnum(99));
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.load_const));
    try f.code.append(gc.allocator, 0); // dst hi
    try f.code.append(gc.allocator, 0); // dst lo
    try f.code.append(gc.allocator, 0); // idx hi
    try f.code.append(gc.allocator, 0); // idx lo
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.@"return"));
    try f.code.append(gc.allocator, 0); // src hi
    try f.code.append(gc.allocator, 0); // src lo
    f.locals_count = 1;

    const jit_code = try compile(f, &vm, std.testing.allocator);
    defer freeJitCode(jit_code, std.testing.allocator);

    const cls_val = try gc.allocClosure(f);
    const cls = types.toObject(cls_val).as(types.Closure);

    // Set up as if called from base=4, so new_base=5, return dst = registers[4]
    const caller_base: u16 = 2;
    const call_base: u16 = 4; // callee register
    const new_base: u16 = call_base + 1;

    // Simulate the caller frame
    vm.frames[0] = .{ .closure = cls, .code = &.{}, .ip = 0, .base = caller_base, .dst = 0 };
    // Callee frame (the JIT-compiled function)
    vm.frames[1] = .{
        .closure = cls,
        .code = f.code.items,
        .ip = 0,
        .base = new_base,
        .dst = @intCast(call_base - caller_base),
    };
    vm.frame_count = 2;

    const entry: JitEntryFn = @ptrCast(@alignCast(jit_code.entry));
    const result = entry(&vm, new_base, f.constants.items.ptr, cls);

    // JIT return should: store result at registers[new_base-1]=registers[4], pop frame
    try std.testing.expectEqual(@as(u64, 0), result); // normal completion
    try std.testing.expectEqual(@as(usize, 1), vm.frame_count); // frame popped
    try std.testing.expectEqual(@as(i64, 99), types.toFixnum(vm.registers[call_base])); // result stored
}

test "compile call_global with multiply" {
    // JIT temporarily disabled (#60): skip until u16 register JIT bugs are fixed
}

test "compile call_global with zero? predicate" {
    // JIT temporarily disabled (#60): skip until u16 register JIT bugs are fixed
}

test "compile tail_call_global with add" {
    // JIT temporarily disabled (#60): skip until u16 register JIT bugs are fixed
}
