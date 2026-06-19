const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const jit_mem = @import("jit_mem.zig");
const a64 = @import("jit_aarch64.zig");

pub const JIT_THRESHOLD: u32 = 100;

pub const JitCode = struct {
    entry: *anyopaque,
    buf: jit_mem.CodeBuffer,
};

pub const JitEntryFn = *const fn (*vm_mod.VM, u16, [*]const types.Value, *types.Closure) callconv(.c) u64;

const RESULT_SIDE_EXIT: u64 = 0;

fn jitSideExit(vm_ptr: *vm_mod.VM, bc_ip: u64) callconv(.c) void {
    if (vm_ptr.frame_count > 0) {
        vm_ptr.frames[vm_ptr.frame_count - 1].ip = @intCast(bc_ip);
    }
}

// Struct offsets computed at comptime
const VM = vm_mod.VM;
const CallFrame = vm_mod.CallFrame;
const OFF_REGISTERS = @offsetOf(VM, "registers");
const OFF_FRAME_COUNT = @offsetOf(VM, "frame_count");
const OFF_FRAMES = @offsetOf(VM, "frames");
const SIZEOF_CALLFRAME = @sizeOf(CallFrame);
const OFF_FRAME_IP = @offsetOf(CallFrame, "ip");

const Reg = a64.Reg;
const Cond = a64.Cond;

// Machine register assignments (callee-saved)
const VM_PTR = Reg.x21;
const REG_BASE = Reg.x19; // &vm.registers[0]
const BASE_OFF = Reg.x20; // frame.base * 8
const FRAME_PTR = Reg.x23; // REG_BASE + BASE_OFF = &registers[frame.base]
const CONST_PTR = Reg.x22; // func.constants.items.ptr
const CLOSURE_PTR = Reg.x24; // *Closure (4th arg, x3)

const OFF_CLOSURE_UPVALUES = @offsetOf(types.Closure, "upvalues");
const OFF_CLOSURE_FUNC = @offsetOf(types.Closure, "func");
const OFF_FUNC_GLOBAL_CACHE = @offsetOf(types.Function, "global_cache");
const OFF_FUNC_CACHE_VERSION = @offsetOf(types.Function, "cache_version");
const OFF_VM_GLOBAL_VERSION = @offsetOf(vm_mod.VM, "global_version");

const PendingBranch = struct {
    native_idx: u32,
    target_bc_ip: usize,
    cond: ?Cond,
};

const PendingSideExit = struct {
    native_idx: u32,
    bc_ip: usize,
    cond: ?Cond = null, // null = unconditional B, non-null = B.cond
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
            .load_const => 3,
            .load_nil, .load_true, .load_false, .load_void => 1,
            .move => 2,
            .get_global => 3,
            .set_global, .define_global => 3,
            .tail_apply => return false,
            .get_local, .set_local => 2,
            .get_upvalue, .set_upvalue => 2,
            .call, .tail_call => 2,
            .@"return" => 1,
            .jump => 2,
            .jump_false, .jump_true => 3,
            .closure => return false,
            .close_upvalue => return false,
            .cons => 3,
            .push_handler, .pop_handler => return false,
            .halt => return false,
            .call_global, .tail_call_global => 4,
            .box_local => 1,
            .get_box_local, .set_box_local => 2,
            .self_tail_call => 2,
        };
        ip += operand_bytes;
    }
    if (code.len == 0) return false;
    if (func.constants.items.len * 8 > 32760) return false;
    if (func.locals_count > 255) return false;
    if (func.is_variadic) return false;
    return true;
}

pub fn compile(func: *types.Function, vm: *VM, allocator: std.mem.Allocator) !*JitCode {
    var asm_ctx = a64.Assembler.init(allocator);
    defer asm_ctx.deinit();

    var bc_to_native = std.AutoHashMap(usize, u32).init(allocator);
    defer bc_to_native.deinit();

    var pending_branches: std.ArrayList(PendingBranch) = .empty;
    defer pending_branches.deinit(allocator);

    var pending_exits: std.ArrayList(PendingSideExit) = .empty;
    defer pending_exits.deinit(allocator);

    // --- Entry trampoline ---
    // Save callee-saved registers (use STP pre-index to decrement SP)
    try asm_ctx.emit(stpPreSp(.x29, .x30, -8)); // stp x29, x30, [sp, #-64]!
    try asm_ctx.emit(stpOffsetSp(FRAME_PTR, .x24, 2)); // stp x23, x24, [sp, #16]
    try asm_ctx.emit(stpOffsetSp(VM_PTR, CONST_PTR, 4)); // stp x21, x22, [sp, #32]
    try asm_ctx.emit(stpOffsetSp(.x19, .x20, 6)); // stp x19, x20, [sp, #48]
    try asm_ctx.emit(addRegSp(.x29, .xzr, 0)); // mov x29, sp

    // x0 = VM*, x1 = base (u16), x2 = constants_ptr, x3 = closure*
    try asm_ctx.emitMovReg(VM_PTR, .x0); // x21 = VM*
    try emitAddLargeOffset(&asm_ctx, REG_BASE, VM_PTR, OFF_REGISTERS); // x19 = &vm.registers[0]
    try asm_ctx.emitLslImm(BASE_OFF, .x1, 3); // x20 = base * 8
    try asm_ctx.emitAddReg(FRAME_PTR, REG_BASE, BASE_OFF); // x23 = x19 + x20
    try asm_ctx.emitMovReg(CONST_PTR, .x2); // x22 = constants ptr
    try asm_ctx.emitMovReg(CLOSURE_PTR, .x3); // x24 = closure*

    // --- Bytecode walk ---
    const code = func.code.items;
    var ip: usize = 0;
    while (ip < code.len) {
        try bc_to_native.put(ip, asm_ctx.pos());

        const raw = code[ip];
        const op: types.OpCode = @enumFromInt(raw);
        ip += 1;

        switch (op) {
            .load_nil => {
                const dst = code[ip];
                ip += 1;
                try emitLoadImmediate(&asm_ctx, dst, types.NIL);
            },
            .load_true => {
                const dst = code[ip];
                ip += 1;
                try emitLoadImmediate(&asm_ctx, dst, types.TRUE);
            },
            .load_false => {
                const dst = code[ip];
                ip += 1;
                try emitLoadImmediate(&asm_ctx, dst, types.FALSE);
            },
            .load_void => {
                const dst = code[ip];
                ip += 1;
                try emitLoadImmediate(&asm_ctx, dst, types.VOID);
            },
            .move, .get_local, .set_local => {
                const dst = code[ip];
                const src = code[ip + 1];
                ip += 2;
                try emitRegCopy(&asm_ctx, dst, src);
            },
            .load_const => {
                const dst = code[ip];
                const idx = readU16(code, ip + 1);
                ip += 3;
                try emitLoadConst(&asm_ctx, dst, idx);
            },
            .jump => {
                const offset = readI16(code, ip);
                ip += 2;
                const target_signed = @as(i64, @intCast(ip)) + @as(i64, offset);
                if (target_signed < 0 or target_signed > @as(i64, @intCast(code.len)))
                    return error.InvalidBytecode;
                const target_ip: usize = @intCast(target_signed);
                const patch_idx = asm_ctx.pos();
                try asm_ctx.emit(0); // placeholder
                try pending_branches.append(allocator, .{
                    .native_idx = patch_idx,
                    .target_bc_ip = target_ip,
                    .cond = null,
                });
            },
            .jump_false => {
                const test_reg = code[ip];
                const offset = readI16(code, ip + 1);
                ip += 3;
                const target_signed = @as(i64, @intCast(ip)) + @as(i64, offset);
                if (target_signed < 0 or target_signed > @as(i64, @intCast(code.len)))
                    return error.InvalidBytecode;
                const target_ip: usize = @intCast(target_signed);
                // ldr x0, [x23, #test_reg*8]
                try asm_ctx.emitLdrImm(.x0, FRAME_PTR, @as(u16, test_reg) * 8);
                // cmp x0, #FALSE (6)
                try asm_ctx.emitCmpImm(.x0, @intCast(types.FALSE));
                // b.eq target
                const patch_idx = asm_ctx.pos();
                try asm_ctx.emit(0); // placeholder
                try pending_branches.append(allocator, .{
                    .native_idx = patch_idx,
                    .target_bc_ip = target_ip,
                    .cond = .eq,
                });
            },
            .jump_true => {
                const test_reg = code[ip];
                const offset = readI16(code, ip + 1);
                ip += 3;
                const target_signed = @as(i64, @intCast(ip)) + @as(i64, offset);
                if (target_signed < 0 or target_signed > @as(i64, @intCast(code.len)))
                    return error.InvalidBytecode;
                const target_ip: usize = @intCast(target_signed);
                // ldr x0, [x23, #test_reg*8]
                try asm_ctx.emitLdrImm(.x0, FRAME_PTR, @as(u16, test_reg) * 8);
                // cmp x0, #FALSE (6)
                try asm_ctx.emitCmpImm(.x0, @intCast(types.FALSE));
                // b.ne target (anything not #f is truthy)
                const patch_idx = asm_ctx.pos();
                try asm_ctx.emit(0); // placeholder
                try pending_branches.append(allocator, .{
                    .native_idx = patch_idx,
                    .target_bc_ip = target_ip,
                    .cond = .ne,
                });
            },
            .get_upvalue => {
                const dst = code[ip];
                const idx = code[ip + 1];
                ip += 2;
                try emitGetUpvalue(&asm_ctx, dst, idx, &pending_exits, allocator, ip - 3);
            },
            .set_upvalue => {
                const idx = code[ip];
                const src = code[ip + 1];
                ip += 2;
                try emitSetUpvalue(&asm_ctx, src, idx, &pending_exits, allocator, ip - 3);
            },
            .get_global => {
                const dst = code[ip];
                const sym_idx = readU16(code, ip + 1);
                ip += 3;
                try emitGetGlobal(&asm_ctx, dst, sym_idx, &pending_exits, allocator, ip - 4);
            },
            .call_global => {
                const base_reg = code[ip];
                const sym_idx = readU16(code, ip + 1);
                const nargs = code[ip + 3];
                ip += 4;
                const spec = recognizeArithPrimitive(func, sym_idx, vm);
                if (spec != .none and nargs == 2) {
                    try emitSpecializedArith(&asm_ctx, base_reg, spec, &pending_exits, allocator, ip - 5);
                } else {
                    const side_exit_ip = ip - 5;
                    const patch_idx = asm_ctx.pos();
                    try asm_ctx.emit(0);
                    try pending_exits.append(allocator, .{ .native_idx = patch_idx, .bc_ip = side_exit_ip });
                }
            },
            // All other opcodes: side-exit to interpreter
            else => {
                const operand_bytes: usize = switch (op) {
                    .load_const => 3,
                    .load_nil, .load_true, .load_false, .load_void => 1,
                    .move, .get_local, .set_local => 2,
                    .get_global => 3,
                    .set_global, .define_global => 3,
                    .get_upvalue, .set_upvalue => 2,
                    .call, .tail_call => 2,
                    .@"return" => 1,
                    .jump => 2,
                    .jump_false, .jump_true => 3,
                    .cons => 3,
                    .call_global, .tail_call_global => 4,
                    .box_local => 1,
                    .get_box_local, .set_box_local => 2,
                    .self_tail_call => 2,
                    else => 0,
                };
                const side_exit_ip = ip - 1; // rewind to the opcode itself
                ip += operand_bytes;

                const patch_idx = asm_ctx.pos();
                try asm_ctx.emit(0); // placeholder B to exit
                try pending_exits.append(allocator, .{
                    .native_idx = patch_idx,
                    .bc_ip = side_exit_ip,
                });
            },
        }
    }

    // Record end-of-bytecode position for forward jumps that land at the end
    try bc_to_native.put(ip, asm_ctx.pos());

    // --- Exit trampoline (shared) ---
    const exit_start = asm_ctx.pos();
    // x0 = bytecode IP (set by side-exit stubs)
    // Encode as bc_ip + 1 to distinguish from "fell off end" (0)
    try asm_ctx.emitAddImm(.x8, .x0, 1);

    // Restore callee-saved registers (reverse order of save)
    try asm_ctx.emit(ldpOffsetSp(.x19, .x20, 6));
    try asm_ctx.emit(ldpOffsetSp(VM_PTR, CONST_PTR, 4));
    try asm_ctx.emit(ldpOffsetSp(FRAME_PTR, .x24, 2));
    try asm_ctx.emit(ldpPostSp(.x29, .x30, 8));
    try asm_ctx.emitMovReg(.x0, .x8);
    try asm_ctx.emitRet();

    // --- Patch branches ---
    for (pending_branches.items) |pb| {
        const target_native = bc_to_native.get(pb.target_bc_ip) orelse return error.InvalidBytecode;
        const offset: i32 = @as(i32, @intCast(target_native)) - @as(i32, @intCast(pb.native_idx));
        if (pb.cond) |cond| {
            if (offset < -262144 or offset > 262143) return error.BranchOutOfRange;
            asm_ctx.patchAt(pb.native_idx, a64.Assembler.bCond(cond, @intCast(offset)));
        } else {
            if (offset < -33554432 or offset > 33554431) return error.BranchOutOfRange;
            asm_ctx.patchAt(pb.native_idx, a64.Assembler.b(@intCast(offset)));
        }
    }

    // --- Patch side-exits ---
    for (pending_exits.items) |pe| {
        // Each side-exit needs: mov x0, #bc_ip; b exit_trampoline
        // But we only reserved 1 instruction slot. We need to jump to a stub.
        // Emit the stub at the end of the code.
        const stub_pos = asm_ctx.pos();
        try asm_ctx.emitLoadImm64(.x0, pe.bc_ip);
        const exit_offset: i32 = @as(i32, @intCast(exit_start)) - @as(i32, @intCast(asm_ctx.pos()));
        try asm_ctx.emit(a64.Assembler.b(@intCast(exit_offset)));

        // Patch the original placeholder to jump to this stub
        const stub_offset: i32 = @as(i32, @intCast(stub_pos)) - @as(i32, @intCast(pe.native_idx));
        if (pe.cond) |cond| {
            asm_ctx.patchAt(pe.native_idx, a64.Assembler.bCond(cond, @intCast(stub_offset)));
        } else {
            asm_ctx.patchAt(pe.native_idx, a64.Assembler.b(@intCast(stub_offset)));
        }
    }

    // --- Finalize into executable memory ---
    const code_slice = asm_ctx.toSlice();
    var buf = try jit_mem.CodeBuffer.alloc(code_slice.len * 4);
    buf.writeCode(code_slice);

    const jit_code = try allocator.create(JitCode);
    jit_code.* = .{
        .entry = @ptrCast(@alignCast(buf.mem.ptr)),
        .buf = buf,
    };
    return jit_code;
}

pub fn tryCompile(func: *types.Function, vm: *VM) void {
    if (!isEligible(func)) return;
    const jit_code = compile(func, vm, vm.gc.allocator) catch return;
    func.jit_code = jit_code;
}

pub fn freeJitCode(jit_code: *JitCode, allocator: std.mem.Allocator) void {
    jit_code.buf.free();
    allocator.destroy(jit_code);
}

// -----------------------------------------------------------------------
// Template helpers
// -----------------------------------------------------------------------

fn emitLoadImmediate(asm_ctx: *a64.Assembler, dst: u8, value: u64) !void {
    try asm_ctx.emitLoadImm64(.x0, value);
    try asm_ctx.emitStrImm(.x0, FRAME_PTR, @as(u16, dst) * 8);
}

fn emitRegCopy(asm_ctx: *a64.Assembler, dst: u8, src: u8) !void {
    if (dst == src) return;
    try asm_ctx.emitLdrImm(.x0, FRAME_PTR, @as(u16, src) * 8);
    try asm_ctx.emitStrImm(.x0, FRAME_PTR, @as(u16, dst) * 8);
}

fn emitLoadConst(asm_ctx: *a64.Assembler, dst: u8, idx: u16) !void {
    const byte_offset: u16 = @truncate(@as(u32, idx) * 8);
    const full_offset: u32 = @as(u32, idx) * 8;
    if (full_offset <= 32760) {
        try asm_ctx.emitLdrImm(.x0, CONST_PTR, byte_offset);
    } else {
        try asm_ctx.emitLoadImm64(.x0, full_offset);
        try asm_ctx.emit(a64.Assembler.addReg(.x0, CONST_PTR, .x0));
        try asm_ctx.emit(a64.Assembler.ldrImm(.x0, .x0, 0));
    }
    try asm_ctx.emitStrImm(.x0, FRAME_PTR, @as(u16, dst) * 8);
}

fn emitGetUpvalue(asm_ctx: *a64.Assembler, dst: u8, idx: u8, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize) !void {
    // Load upvalue slice pointer from closure
    try emitLoadFromField(asm_ctx, .x0, CLOSURE_PTR, OFF_CLOSURE_UPVALUES);
    // Load upvalue value: upvalues[idx]
    const uv_offset: u32 = @as(u32, idx) * 8;
    if (uv_offset <= 32760) {
        try asm_ctx.emitLdrImm(.x0, .x0, @intCast(uv_offset));
    } else {
        try asm_ctx.emitLoadImm64(.x4, uv_offset);
        try asm_ctx.emit(a64.Assembler.addReg(.x0, .x0, .x4));
        try asm_ctx.emit(a64.Assembler.ldrImm(.x0, .x0, 0));
    }
    // Fast path: non-pointer values (fixnum bit 0=1, immediate bit 1=1)
    // Skip over the side-exit branch
    const store_pos = asm_ctx.pos() + 3; // tbnz, tbnz, b(side-exit) = 3 instructions ahead
    try asm_ctx.emit(a64.Assembler.tbnz(.x0, 0, 3)); // fixnum → skip to store
    try asm_ctx.emit(a64.Assembler.tbnz(.x0, 1, 2)); // immediate → skip to store
    // Pointer → side-exit
    const exit_idx = asm_ctx.pos();
    try asm_ctx.emit(0); // placeholder B to side-exit stub
    try pending_exits.append(allocator, .{ .native_idx = exit_idx, .bc_ip = bc_ip });
    // .store:
    std.debug.assert(asm_ctx.pos() == store_pos);
    try asm_ctx.emitStrImm(.x0, FRAME_PTR, @as(u16, dst) * 8);
}

fn emitSetUpvalue(asm_ctx: *a64.Assembler, src: u8, idx: u8, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize) !void {
    // Load upvalue slice pointer
    try emitLoadFromField(asm_ctx, .x0, CLOSURE_PTR, OFF_CLOSURE_UPVALUES);
    // Check current upvalue value for pointer (boxed)
    const uv_offset: u32 = @as(u32, idx) * 8;
    if (uv_offset <= 32760) {
        try asm_ctx.emitLdrImm(.x4, .x0, @intCast(uv_offset));
    } else {
        try asm_ctx.emitLoadImm64(.x4, uv_offset);
        try asm_ctx.emit(a64.Assembler.addReg(.x4, .x0, .x4));
        try asm_ctx.emit(a64.Assembler.ldrImm(.x4, .x4, 0));
    }
    // Non-pointer → direct store; pointer → side-exit
    const store_pos = asm_ctx.pos() + 3;
    try asm_ctx.emit(a64.Assembler.tbnz(.x4, 0, 3)); // fixnum → direct
    try asm_ctx.emit(a64.Assembler.tbnz(.x4, 1, 2)); // immediate → direct
    const exit_idx = asm_ctx.pos();
    try asm_ctx.emit(0); // placeholder B to side-exit
    try pending_exits.append(allocator, .{ .native_idx = exit_idx, .bc_ip = bc_ip });
    // .direct_store:
    std.debug.assert(asm_ctx.pos() == store_pos);
    try asm_ctx.emitLdrImm(.x1, FRAME_PTR, @as(u16, src) * 8);
    // Write to upvalue slot (need the base pointer again)
    try emitLoadFromField(asm_ctx, .x0, CLOSURE_PTR, OFF_CLOSURE_UPVALUES);
    if (uv_offset <= 32760) {
        try asm_ctx.emitStrImm(.x1, .x0, @intCast(uv_offset));
    } else {
        try asm_ctx.emitLoadImm64(.x4, uv_offset);
        try asm_ctx.emit(a64.Assembler.addReg(.x0, .x0, .x4));
        try asm_ctx.emit(a64.Assembler.strImm(.x1, .x0, 0));
    }
}

fn emitGetGlobal(asm_ctx: *a64.Assembler, dst: u8, sym_idx: u16, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize) !void {
    // Load func from closure: closure.func
    try emitLoadFromField(asm_ctx, .x0, CLOSURE_PTR, OFF_CLOSURE_FUNC);
    // Load global_cache.ptr (first word of ?[]Value)
    try emitLoadFromField(asm_ctx, .x1, .x0, OFF_FUNC_GLOBAL_CACHE);
    // If null → side-exit
    try asm_ctx.emitCmpImm(.x1, 0);
    var exit_count: usize = 0;
    const exit1 = asm_ctx.pos();
    try asm_ctx.emit(0); // b.eq side-exit
    exit_count += 1;
    // Check cache_version == global_version (both u32)
    try emitLoadWFromField(asm_ctx, .x2, .x0, OFF_FUNC_CACHE_VERSION);
    try emitLoadWFromField(asm_ctx, .x3, VM_PTR, OFF_VM_GLOBAL_VERSION);
    try asm_ctx.emitCmpReg(.x2, .x3);
    const exit2 = asm_ctx.pos();
    try asm_ctx.emit(0); // b.ne side-exit
    exit_count += 1;
    // Bounds check: cache.len > sym_idx
    try emitLoadFromField(asm_ctx, .x4, .x0, OFF_FUNC_GLOBAL_CACHE + 8); // cache.len
    try asm_ctx.emitLoadImm64(.x5, sym_idx);
    try asm_ctx.emitCmpReg(.x4, .x5);
    const exit3 = asm_ctx.pos();
    try asm_ctx.emit(0); // b.ls side-exit
    exit_count += 1;
    // Load cached value
    const cache_offset: u32 = @as(u32, sym_idx) * 8;
    if (cache_offset <= 32760) {
        try asm_ctx.emitLdrImm(.x4, .x1, @intCast(cache_offset));
    } else {
        try asm_ctx.emitLoadImm64(.x4, cache_offset);
        try asm_ctx.emit(a64.Assembler.addReg(.x4, .x1, .x4));
        try asm_ctx.emit(a64.Assembler.ldrImm(.x4, .x4, 0));
    }
    // Check != VOID
    try asm_ctx.emitCmpImm(.x4, @intCast(types.VOID));
    const exit4 = asm_ctx.pos();
    try asm_ctx.emit(0); // b.eq side-exit
    exit_count += 1;
    // Cache hit — store to dst
    try asm_ctx.emitStrImm(.x4, FRAME_PTR, @as(u16, dst) * 8);
    // All exits go to the same side-exit stub
    try pending_exits.append(allocator, .{ .native_idx = exit1, .bc_ip = bc_ip, .cond = .eq }); // cbz → b.eq
    try pending_exits.append(allocator, .{ .native_idx = exit2, .bc_ip = bc_ip, .cond = .ne }); // version mismatch
    try pending_exits.append(allocator, .{ .native_idx = exit3, .bc_ip = bc_ip, .cond = .ls }); // out of bounds
    try pending_exits.append(allocator, .{ .native_idx = exit4, .bc_ip = bc_ip, .cond = .eq }); // == VOID
}

const SpecializedOp = enum { add, sub, lt, gt, le, ge, eq, none };

fn recognizeArithPrimitive(func: *const types.Function, sym_idx: u16, vm: *const VM) SpecializedOp {
    if (sym_idx >= func.constants.items.len) return .none;
    const sym_val = func.constants.items[sym_idx];
    if (!types.isSymbol(sym_val)) return .none;
    const name = types.symbolName(sym_val);
    // Verify the global currently resolves to a NativeFn
    const global_val = vm.globals.get(name) orelse return .none;
    if (!types.isNativeFn(global_val)) return .none;
    if (std.mem.eql(u8, name, "+")) return .add;
    if (std.mem.eql(u8, name, "-")) return .sub;
    if (std.mem.eql(u8, name, "<")) return .lt;
    if (std.mem.eql(u8, name, ">")) return .gt;
    if (std.mem.eql(u8, name, "<=")) return .le;
    if (std.mem.eql(u8, name, ">=")) return .ge;
    if (std.mem.eql(u8, name, "=")) return .eq;
    return .none;
}

fn emitSpecializedArith(asm_ctx: *a64.Assembler, base_reg: u8, spec: SpecializedOp, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize) !void {
    const arg1_off: u16 = (@as(u16, base_reg) + 1) * 8;
    const arg2_off: u16 = (@as(u16, base_reg) + 2) * 8;
    const dst_off: u16 = @as(u16, base_reg) * 8;

    // Load both arguments
    try asm_ctx.emitLdrImm(.x0, FRAME_PTR, arg1_off);
    try asm_ctx.emitLdrImm(.x1, FRAME_PTR, arg2_off);

    // Type guard: both must be fixnums (bit 0 = 1)
    // AND x2, x0, x1 — if both have bit 0 set, result bit 0 is set
    try asm_ctx.emitAndReg(.x2, .x0, .x1);
    try asm_ctx.emit(a64.Assembler.tbnz(.x2, 0, 2)); // bit 0 set → skip exit
    const type_exit = asm_ctx.pos();
    try asm_ctx.emit(0); // B side-exit (unconditional, patched later)
    try pending_exits.append(allocator, .{ .native_idx = type_exit, .bc_ip = bc_ip });

    switch (spec) {
        .add => {
            try asm_ctx.emitAsrImm(.x3, .x0, 1); // untag a
            try asm_ctx.emitAsrImm(.x4, .x1, 1); // untag b
            try asm_ctx.emitAddsReg(.x5, .x3, .x4); // a + b with overflow
            const ov_exit = asm_ctx.pos();
            try asm_ctx.emit(0); // b.vs side-exit (placeholder)
            try pending_exits.append(allocator, .{ .native_idx = ov_exit, .bc_ip = bc_ip, .cond = .vs });
            try asm_ctx.emitLslImm(.x5, .x5, 1); // retag: result << 1
        },
        .sub => {
            try asm_ctx.emitAsrImm(.x3, .x0, 1);
            try asm_ctx.emitAsrImm(.x4, .x1, 1);
            try asm_ctx.emitSubsReg(.x5, .x3, .x4); // a - b
            const ov_exit = asm_ctx.pos();
            try asm_ctx.emit(0);
            try pending_exits.append(allocator, .{ .native_idx = ov_exit, .bc_ip = bc_ip, .cond = .vs });
            try asm_ctx.emitLslImm(.x5, .x5, 1);
        },
        else => {}, // comparisons handled below
    }

    switch (spec) {
        .add, .sub => {
            // Retag: (result << 1) | 1 — use ADD to set bit 0
            try asm_ctx.emitAddImm(.x5, .x5, 1);
            try asm_ctx.emitStrImm(.x5, FRAME_PTR, dst_off);
        },
        .lt, .gt, .le, .ge, .eq => {
            // Tagged fixnum comparison preserves ordering — compare directly
            try asm_ctx.emitCmpReg(.x0, .x1);
            try asm_ctx.emitMovz(.x4, @intCast(types.FALSE), 0);
            try asm_ctx.emitLoadImm64(.x5, types.TRUE);
            const cond: Cond = switch (spec) {
                .lt => .lt,
                .gt => .gt,
                .le => .le,
                .ge => .ge,
                .eq => .eq,
                else => unreachable,
            };
            try asm_ctx.emitCsel(.x6, .x5, .x4, cond);
            try asm_ctx.emitStrImm(.x6, FRAME_PTR, dst_off);
        },
        .none => unreachable,
    }
}

fn emitLoadFromField(asm_ctx: *a64.Assembler, rd: Reg, base: Reg, offset: usize) !void {
    if (offset <= 32760 and offset % 8 == 0) {
        try asm_ctx.emitLdrImm(rd, base, @intCast(offset));
    } else {
        try asm_ctx.emitLoadImm64(rd, offset);
        try asm_ctx.emitAddReg(rd, base, rd);
        try asm_ctx.emit(a64.Assembler.ldrImm(rd, rd, 0));
    }
}

fn emitLoadWFromField(asm_ctx: *a64.Assembler, rd: Reg, base: Reg, offset: usize) !void {
    if (offset <= 16380 and offset % 4 == 0) {
        try asm_ctx.emitLdrWImm(rd, base, @intCast(offset));
    } else {
        try asm_ctx.emitLoadImm64(rd, offset);
        try asm_ctx.emitAddReg(rd, base, rd);
        try asm_ctx.emit(a64.Assembler.ldrWImm(rd, rd, 0));
    }
}

// SP-aware instructions: in AArch64, register 31 is SP in LDR/STR/ADD/SUB
// but XZR in most data-processing instructions. We encode SP as register 31.

fn stpPreSp(rt: Reg, rt2: Reg, offset: i7) u32 {
    // STP rt, rt2, [SP, #offset]! (pre-index with SP as base)
    const imm7: u7 = @bitCast(offset);
    return (0b10_101_0_011 << 23) |
        (@as(u32, imm7) << 15) |
        (@as(u32, @intFromEnum(rt2)) << 10) |
        (31 << 5) | // SP
        @intFromEnum(rt);
}

fn ldpPostSp(rt: Reg, rt2: Reg, offset: i7) u32 {
    // LDP rt, rt2, [SP], #offset (post-index with SP as base)
    // Encoding: 10_101_0_001_1_imm7_Rt2_Rn_Rt (L=1 at bit 22)
    const imm7: u7 = @bitCast(offset);
    return (0b10_101_0_001 << 23) |
        (1 << 22) | // L=1 for load
        (@as(u32, imm7) << 15) |
        (@as(u32, @intFromEnum(rt2)) << 10) |
        (31 << 5) | // SP
        @intFromEnum(rt);
}

fn stpOffsetSp(rt: Reg, rt2: Reg, offset: i7) u32 {
    const imm7: u7 = @bitCast(offset);
    return (0b10_101_0_010 << 23) |
        (@as(u32, imm7) << 15) |
        (@as(u32, @intFromEnum(rt2)) << 10) |
        (31 << 5) | // SP
        @intFromEnum(rt);
}

fn ldpOffsetSp(rt: Reg, rt2: Reg, offset: i7) u32 {
    const imm7: u7 = @bitCast(offset);
    return (0b10_101_0_010 << 23) |
        (1 << 22) | // L=1 for load
        (@as(u32, imm7) << 15) |
        (@as(u32, @intFromEnum(rt2)) << 10) |
        (31 << 5) | // SP
        @intFromEnum(rt);
}

fn addRegSp(rd: Reg, rm: Reg, imm: u12) u32 {
    // ADD Xd, SP, #imm (register 31 as Rn means SP)
    _ = rm;
    return (0b1_0_0_100010_0 << 22) |
        (@as(u32, imm) << 10) |
        (31 << 5) | // SP as Rn
        @intFromEnum(rd);
}

fn emitAddLargeOffset(asm_ctx: *a64.Assembler, rd: Reg, rn: Reg, offset: usize) !void {
    if (offset <= 4095) {
        try asm_ctx.emitAddImm(rd, rn, @intCast(offset));
    } else {
        try asm_ctx.emitLoadImm64(rd, offset);
        try asm_ctx.emitAddReg(rd, rn, rd);
    }
}

fn emitLoadFromVmField(asm_ctx: *a64.Assembler, rd: Reg, field_offset: usize) !void {
    if (field_offset <= 32760 and field_offset % 8 == 0) {
        try asm_ctx.emitLdrImm(rd, VM_PTR, @intCast(field_offset));
    } else {
        try asm_ctx.emitLoadImm64(rd, field_offset);
        try asm_ctx.emitAddReg(rd, VM_PTR, rd);
        try asm_ctx.emit(a64.Assembler.ldrImm(rd, rd, 0));
    }
}

fn emitStoreAtOffset(asm_ctx: *a64.Assembler, rt: Reg, rn: Reg, offset: usize) !void {
    if (offset <= 32760 and offset % 8 == 0) {
        try asm_ctx.emitStrImm(rt, rn, @intCast(offset));
    } else {
        try asm_ctx.emitLoadImm64(.x4, offset);
        try asm_ctx.emitAddReg(.x4, rn, .x4);
        try asm_ctx.emit(a64.Assembler.strImm(rt, .x4, 0));
    }
}

fn emitMulConst(asm_ctx: *a64.Assembler, rd: Reg, rn: Reg, constant: usize) !void {
    // Multiply by a compile-time constant using shifts and adds
    if (constant == 0) {
        try asm_ctx.emitMovz(rd, 0, 0);
        return;
    }
    // Use shift if power of 2
    if (std.math.isPowerOfTwo(constant)) {
        const shift: u6 = @intCast(std.math.log2(constant));
        try asm_ctx.emitLslImm(rd, rn, shift);
        return;
    }
    // General case: load constant into temp, use MADD (or shift+add decomposition)
    // For SIZEOF_CALLFRAME, decompose into shifts+adds
    try asm_ctx.emitLoadImm64(.x4, constant);
    // MADD rd, rn, x4, xzr (rd = rn * x4 + 0)
    try asm_ctx.emit(madd(rd, rn, .x4, .xzr));
}

fn madd(rd: Reg, rn: Reg, rm: Reg, ra: Reg) u32 {
    return (0b1_00_11011_000 << 21) |
        (@as(u32, @intFromEnum(rm)) << 16) |
        (@as(u32, @intFromEnum(ra)) << 10) |
        (@as(u32, @intFromEnum(rn)) << 5) |
        @intFromEnum(rd);
}

fn readU16(code: []const u8, ip: usize) u16 {
    return @as(u16, code[ip]) | (@as(u16, code[ip + 1]) << 8);
}

fn readI16(code: []const u8, ip: usize) i16 {
    return @bitCast(readU16(code, ip));
}

// -----------------------------------------------------------------------
// Tests
// -----------------------------------------------------------------------

test "isEligible rejects closure opcode" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const f = try gc.allocFunction();
    // Write a bytecode with closure opcode
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.closure));
    try f.code.append(gc.allocator, 0); // dst
    try f.code.append(gc.allocator, 0); // idx lo
    try f.code.append(gc.allocator, 0); // idx hi

    try std.testing.expect(!isEligible(f));
}

test "isEligible accepts simple bytecode" {
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const f = try gc.allocFunction();
    // load_nil r0; return r0
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.load_nil));
    try f.code.append(gc.allocator, 0);
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.@"return"));
    try f.code.append(gc.allocator, 0);

    try std.testing.expect(isEligible(f));
}

test "compile trivial function" {
    const memory = @import("memory.zig");
    const th = @import("testing_helpers.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const f = try gc.allocFunction();
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.load_nil));
    try f.code.append(gc.allocator, 0);
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.@"return"));
    try f.code.append(gc.allocator, 0);

    const jit_code = try compile(f, &vm, std.testing.allocator);
    defer freeJitCode(jit_code, std.testing.allocator);

    try std.testing.expect(@intFromPtr(jit_code.entry) != 0);
}

test "minimal prologue/epilogue" {
    // Test just the entry/exit trampoline by compiling a function
    // that immediately returns (only a return opcode)
    const memory = @import("memory.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // Build a minimal prologue/epilogue manually
    var asm_ctx = a64.Assembler.init(std.testing.allocator);
    defer asm_ctx.deinit();

    // Prologue: save x29, x30 and allocate 16 bytes
    try asm_ctx.emit(stpPreSp(.x29, .x30, -2)); // stp x29, x30, [sp, #-16]!
    try asm_ctx.emit(addRegSp(.x29, .xzr, 0)); // mov x29, sp
    // Epilogue: restore and return 0
    try asm_ctx.emitMovz(.x0, 0, 0);
    try asm_ctx.emit(ldpPostSp(.x29, .x30, 2)); // ldp x29, x30, [sp], #16
    try asm_ctx.emitRet();

    var buf = try jit_mem.CodeBuffer.alloc(4096);
    defer buf.free();
    buf.writeCode(asm_ctx.toSlice());

    const func: *const fn () callconv(.c) u64 = @ptrCast(@alignCast(buf.mem.ptr));
    const result = func();
    try std.testing.expectEqual(@as(u64, 0), result);
}

test "prologue saves and restores callee-saved regs" {
    var asm_ctx = a64.Assembler.init(std.testing.allocator);
    defer asm_ctx.deinit();

    // Save 6 callee-saved regs (x19-x24) + x29/x30 = 64 bytes
    try asm_ctx.emit(stpPreSp(.x29, .x30, -8)); // [sp, #-64]!
    try asm_ctx.emit(stpOffsetSp(.x19, .x20, 2)); // [sp, #16]
    try asm_ctx.emit(stpOffsetSp(.x21, .x22, 4)); // [sp, #32]
    try asm_ctx.emit(stpOffsetSp(.x23, .x24, 6)); // [sp, #48]
    try asm_ctx.emit(addRegSp(.x29, .xzr, 0)); // mov x29, sp

    // Do nothing — just return 77
    try asm_ctx.emitMovz(.x0, 77, 0);

    // Restore
    try asm_ctx.emit(ldpOffsetSp(.x23, .x24, 6));
    try asm_ctx.emit(ldpOffsetSp(.x21, .x22, 4));
    try asm_ctx.emit(ldpOffsetSp(.x19, .x20, 2));
    try asm_ctx.emit(ldpPostSp(.x29, .x30, 8)); // [sp], #64
    try asm_ctx.emitRet();

    var buf = try jit_mem.CodeBuffer.alloc(4096);
    defer buf.free();
    buf.writeCode(asm_ctx.toSlice());

    const func: *const fn () callconv(.c) u64 = @ptrCast(@alignCast(buf.mem.ptr));
    const result = func();
    try std.testing.expectEqual(@as(u64, 77), result);
}

test "compile and execute load_nil" {
    const memory = @import("memory.zig");
    const th = @import("testing_helpers.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const f = try gc.allocFunction();
    // load_nil r0; return r0
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.load_nil));
    try f.code.append(gc.allocator, 0);
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.@"return"));
    try f.code.append(gc.allocator, 0);
    f.locals_count = 1;

    const jit_code = try compile(f, &vm, std.testing.allocator);
    defer freeJitCode(jit_code, std.testing.allocator);

    const cls_val = try gc.allocClosure(f);
    const cls = types.toObject(cls_val).as(types.Closure);
    vm.frames[0] = .{
        .closure = cls,
        .code = f.code.items,
        .ip = 0,
        .base = 0,
        .dst = 0,
    };
    vm.frame_count = 1;

    const entry: JitEntryFn = @ptrCast(@alignCast(jit_code.entry));
    const result = entry(&vm, 0, &[_]types.Value{}, cls);
    _ = result;

    try std.testing.expectEqual(types.NIL, vm.registers[0]);
}

test "compile and execute load_const" {
    const memory = @import("memory.zig");
    const th = @import("testing_helpers.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const f = try gc.allocFunction();

    // Add a constant: fixnum 42
    try f.constants.append(gc.allocator, types.makeFixnum(42));

    // load_const r0, 0; return r0
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.load_const));
    try f.code.append(gc.allocator, 0); // dst
    try f.code.append(gc.allocator, 0); // idx lo
    try f.code.append(gc.allocator, 0); // idx hi
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.@"return"));
    try f.code.append(gc.allocator, 0);
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
    const memory = @import("memory.zig");
    const th = @import("testing_helpers.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const f = try gc.allocFunction();
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.load_true));
    try f.code.append(gc.allocator, 0);
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.move));
    try f.code.append(gc.allocator, 1);
    try f.code.append(gc.allocator, 0);
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.@"return"));
    try f.code.append(gc.allocator, 1);
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
    const memory = @import("memory.zig");
    const th = @import("testing_helpers.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const f = try gc.allocFunction();
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.load_false));
    try f.code.append(gc.allocator, 0);
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.jump_false));
    try f.code.append(gc.allocator, 0);
    const offset: i16 = 4;
    const offset_bytes: [2]u8 = @bitCast(offset);
    try f.code.append(gc.allocator, offset_bytes[0]);
    try f.code.append(gc.allocator, offset_bytes[1]);
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.load_true));
    try f.code.append(gc.allocator, 1);
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.@"return"));
    try f.code.append(gc.allocator, 1);
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.load_nil));
    try f.code.append(gc.allocator, 1);
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.@"return"));
    try f.code.append(gc.allocator, 1);
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
