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
const VM = vm_mod.VM;
const CallFrame = vm_mod.CallFrame;
const OFF_REGISTERS = @offsetOf(VM, "registers");
const OFF_FRAME_COUNT = @offsetOf(VM, "frame_count");
const OFF_FRAMES = @offsetOf(VM, "frames");
const SIZEOF_CALLFRAME = @sizeOf(CallFrame);
const OFF_FRAME_IP = @offsetOf(CallFrame, "ip");

const Reg = if (@import("builtin").cpu.arch == .x86_64) x64.Reg else a64.Reg;
const Cond = if (@import("builtin").cpu.arch == .x86_64) x64.Cond else a64.Cond;

// Machine register assignments
const VM_PTR = if (@import("builtin").cpu.arch == .x86_64) Reg.rbx else Reg.x21;
const REG_BASE = if (@import("builtin").cpu.arch == .x86_64) Reg.r12 else Reg.x19;
const BASE_OFF = if (@import("builtin").cpu.arch == .x86_64) Reg.r13 else Reg.x20;
const FRAME_PTR = if (@import("builtin").cpu.arch == .x86_64) Reg.r14 else Reg.x23;
const CONST_PTR = if (@import("builtin").cpu.arch == .x86_64) Reg.r15 else Reg.x22;
const CLOSURE_PTR = if (@import("builtin").cpu.arch == .x86_64) Reg.rbp else Reg.x24;

const OFF_CLOSURE_UPVALUES = @offsetOf(types.Closure, "upvalues");
const OFF_CLOSURE_FUNC = @offsetOf(types.Closure, "func");
const OFF_FUNC_GLOBAL_CACHE = @offsetOf(types.Function, "global_cache");
const OFF_FUNC_CACHE_VERSION = @offsetOf(types.Function, "cache_version");
const OFF_VM_GLOBAL_VERSION = @offsetOf(vm_mod.VM, "global_version");
const OFF_WIND_COUNT = @offsetOf(VM, "wind_count");
const OFF_VM_JIT_ERROR = @offsetOf(VM, "jit_error");

// CallFrame field offsets
const OFF_FRAME_CLOSURE = @offsetOf(CallFrame, "closure");
const OFF_FRAME_NATIVE = @offsetOf(CallFrame, "native");
const OFF_FRAME_CODE = @offsetOf(CallFrame, "code");
const OFF_FRAME_BASE = @offsetOf(CallFrame, "base");
const OFF_FRAME_DST = @offsetOf(CallFrame, "dst");
const OFF_FRAME_SAVED_WIND = @offsetOf(CallFrame, "saved_wind_count");

// Function field offsets for call type checks
const OFF_FUNC_ARITY = @offsetOf(types.Function, "arity");
const OFF_FUNC_IS_VARIADIC = @offsetOf(types.Function, "is_variadic");
const OFF_FUNC_JIT_CODE = @offsetOf(types.Function, "jit_code");
const OFF_FUNC_CODE = @offsetOf(types.Function, "code");
const OFF_FUNC_CALL_COUNT = @offsetOf(types.Function, "call_count");
const OFF_FUNC_CONSTANTS = @offsetOf(types.Function, "constants");
const OFF_JIT_CODE_ENTRY = @offsetOf(JitCode, "entry");
const OFF_OBJECT_TAG = @offsetOf(types.Object, "tag");
const OFF_PAIR_CAR = @offsetOf(types.Pair, "car");
const OFF_PAIR_CDR = @offsetOf(types.Pair, "cdr");
const MAX_FRAMES = vm_mod.MAX_FRAMES;

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
    if (!jit_supported) return error.InvalidBytecode;
    if (is_x86_64) return compileX86_64(func, vm, allocator);
    var asm_ctx = a64.Assembler.init(allocator);
    defer asm_ctx.deinit();

    var bc_to_native = std.AutoHashMap(usize, u32).init(allocator);
    defer bc_to_native.deinit();

    var pending_branches: std.ArrayList(PendingBranch) = .empty;
    defer pending_branches.deinit(allocator);

    var pending_exits: std.ArrayList(PendingSideExit) = .empty;
    defer pending_exits.deinit(allocator);

    var pending_returns: std.ArrayList(u32) = .empty;
    defer pending_returns.deinit(allocator);

    var pending_quick_exits: std.ArrayList(u32) = .empty;
    defer pending_quick_exits.deinit(allocator);

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
            .@"return" => {
                const src = code[ip];
                ip += 1;
                try emitReturn(&asm_ctx, src, &pending_exits, &pending_returns, allocator, ip - 2);
            },
            .call => {
                const base_reg = code[ip];
                const nargs = code[ip + 1];
                ip += 2;
                try emitCall(&asm_ctx, base_reg, nargs, &pending_exits, &pending_returns, &pending_quick_exits, allocator, ip - 3, ip, func);
            },
            .call_global => {
                const base_reg = code[ip];
                const sym_idx = readU16(code, ip + 1);
                const nargs = code[ip + 3];
                ip += 4;
                const bc_ip_cg = ip - 5;
                const spec = recognizeArithPrimitive(func, sym_idx, vm);
                if (spec != .none and nargs == 2 and (spec == .add or spec == .sub or spec == .mul or spec == .lt or spec == .gt or spec == .le or spec == .ge or spec == .eq)) {
                    try emitSpecializedArith(&asm_ctx, base_reg, spec, &pending_exits, allocator, bc_ip_cg);
                } else if (spec != .none and nargs == 1 and (spec == .zero_p or spec == .null_p or spec == .pair_p or spec == .not_op or spec == .car or spec == .cdr)) {
                    try emitSpecializedPredicate(&asm_ctx, base_reg, spec, &pending_exits, allocator, bc_ip_cg);
                } else if (isSelfCall(func, sym_idx, nargs)) {
                    try emitSelfCallSequence(&asm_ctx, base_reg, nargs, &pending_exits, &pending_returns, &pending_quick_exits, allocator, bc_ip_cg, ip);
                } else {
                    try emitCallGlobal(&asm_ctx, base_reg, sym_idx, nargs, &pending_exits, &pending_returns, &pending_quick_exits, allocator, bc_ip_cg, ip, func);
                }
            },
            .tail_call_global => {
                const base_reg = code[ip];
                const sym_idx = readU16(code, ip + 1);
                const nargs = code[ip + 3];
                ip += 4;
                const bc_ip_tcg = ip - 5;
                const spec = recognizeArithPrimitive(func, sym_idx, vm);
                if (spec != .none and nargs == 2 and (spec == .add or spec == .sub or spec == .mul or spec == .lt or spec == .gt or spec == .le or spec == .ge or spec == .eq)) {
                    try emitSpecializedArith(&asm_ctx, base_reg, spec, &pending_exits, allocator, bc_ip_tcg);
                } else if (spec != .none and nargs == 1 and (spec == .zero_p or spec == .null_p or spec == .pair_p or spec == .not_op or spec == .car or spec == .cdr)) {
                    try emitSpecializedPredicate(&asm_ctx, base_reg, spec, &pending_exits, allocator, bc_ip_tcg);
                } else {
                    // Side-exit for non-specialized tail_call_global
                    const patch_idx = asm_ctx.pos();
                    try asm_ctx.emit(0);
                    try pending_exits.append(allocator, .{
                        .native_idx = patch_idx,
                        .bc_ip = bc_ip_tcg,
                    });
                }
            },
            .cons => {
                const dst = code[ip];
                const car_reg = code[ip + 1];
                const cdr_reg = code[ip + 2];
                ip += 3;
                try emitCons(&asm_ctx, dst, car_reg, cdr_reg, &pending_exits, allocator, ip - 4);
            },
            .set_global => {
                const sym_idx = readU16(code, ip);
                const src = code[ip + 2];
                ip += 3;
                try emitSetGlobal(&asm_ctx, src, sym_idx, &pending_exits, allocator, ip - 4);
            },
            .define_global => {
                const sym_idx = readU16(code, ip);
                const src = code[ip + 2];
                ip += 3;
                try emitSetGlobal(&asm_ctx, src, sym_idx, &pending_exits, allocator, ip - 4);
            },
            .box_local => {
                const reg = code[ip];
                ip += 1;
                // box_local is a no-op in our register VM — values are already in registers
                // The box concept exists for closure capture; here just skip
                _ = reg;
            },
            .get_box_local => {
                const dst = code[ip];
                const src = code[ip + 1];
                ip += 2;
                try emitRegCopy(&asm_ctx, dst, src);
            },
            .set_box_local => {
                const dst = code[ip];
                const src = code[ip + 1];
                ip += 2;
                try emitRegCopy(&asm_ctx, dst, src);
            },
            .self_tail_call => {
                const base_reg = code[ip];
                const stc_nargs = code[ip + 1];
                ip += 2;
                // Copy args from call window to frame base: registers[frame.base+i] = registers[frame.base+base_reg+1+i]
                var i: u8 = 0;
                while (i < stc_nargs) : (i += 1) {
                    const src_off: u16 = (@as(u16, base_reg) + 1 + i) * 8;
                    const dst_off: u16 = @as(u16, i) * 8;
                    try asm_ctx.emitLdrImm(.x0, FRAME_PTR, src_off);
                    try asm_ctx.emitStrImm(.x0, FRAME_PTR, dst_off);
                }
                // Jump back to bytecode IP 0 (the beginning of the function)
                const target_native = bc_to_native.get(0) orelse return error.InvalidBytecode;
                const patch_idx = asm_ctx.pos();
                try asm_ctx.emit(0); // placeholder B
                try pending_branches.append(allocator, .{
                    .native_idx = patch_idx,
                    .target_bc_ip = 0,
                    .cond = null,
                });
                _ = target_native;
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

    // --- Return trampoline: normal function completion ---
    const return_trampoline = asm_ctx.pos();
    try asm_ctx.emitMovz(.x8, 0, 0); // return 0

    // B to epilogue (skip quick_exit + exit trampoline)
    const ret_to_epi = asm_ctx.pos();
    try asm_ctx.emit(0); // placeholder

    // --- Quick exit: return non-zero without encoding bc_ip ---
    const quick_exit = asm_ctx.pos();
    try asm_ctx.emitLoadImm64(.x8, 0xFFFFFFFF); // sentinel
    const qe_to_epi = asm_ctx.pos();
    try asm_ctx.emit(0); // placeholder

    // --- Exit trampoline: encode bc_ip+1 as return value ---
    const exit_start = asm_ctx.pos();
    // x0 = bytecode IP (set by side-exit stubs)
    try asm_ctx.emitAddImm(.x8, .x0, 1);

    // --- Shared epilogue ---
    const epilogue = asm_ctx.pos();
    try asm_ctx.emit(ldpOffsetSp(.x19, .x20, 6));
    try asm_ctx.emit(ldpOffsetSp(VM_PTR, CONST_PTR, 4));
    try asm_ctx.emit(ldpOffsetSp(FRAME_PTR, .x24, 2));
    try asm_ctx.emit(ldpPostSp(.x29, .x30, 8));
    try asm_ctx.emitMovReg(.x0, .x8);
    try asm_ctx.emitRet();

    // Patch return/quick-exit branches to epilogue
    {
        const off1: i32 = @as(i32, @intCast(epilogue)) - @as(i32, @intCast(ret_to_epi));
        asm_ctx.patchAt(ret_to_epi, a64.Assembler.b(@intCast(off1)));
        const off2: i32 = @as(i32, @intCast(epilogue)) - @as(i32, @intCast(qe_to_epi));
        asm_ctx.patchAt(qe_to_epi, a64.Assembler.b(@intCast(off2)));
    }

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

    // --- Patch return branches ---
    for (pending_returns.items) |pr| {
        const offset: i32 = @as(i32, @intCast(return_trampoline)) - @as(i32, @intCast(pr));
        asm_ctx.patchAt(pr, a64.Assembler.b(@intCast(offset)));
    }

    // --- Patch quick-exit branches ---
    for (pending_quick_exits.items) |pq| {
        const offset: i32 = @as(i32, @intCast(quick_exit)) - @as(i32, @intCast(pq));
        asm_ctx.patchAt(pq, a64.Assembler.b(@intCast(offset)));
    }

    // --- Patch side-exits ---
    for (pending_exits.items) |pe| {
        const stub_pos = asm_ctx.pos();
        try asm_ctx.emitLoadImm64(.x0, pe.bc_ip);
        const exit_offset: i32 = @as(i32, @intCast(exit_start)) - @as(i32, @intCast(asm_ctx.pos()));
        try asm_ctx.emit(a64.Assembler.b(@intCast(exit_offset)));

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

// ---------------------------------------------------------------------------
// x86_64 backend
// ---------------------------------------------------------------------------

const X64 = x64.Reg;

const X_VM_PTR = X64.r13;
const X_REG_BASE = X64.r14;
const X_BASE_OFF = X64.r15;
const X_FRAME_PTR = X64.rbx;
const X_CONST_PTR = X64.r12;
const X_CLOSURE_PTR = X64.rbp;

fn compileX86_64(func: *types.Function, vm: *VM, allocator: std.mem.Allocator) !*JitCode {
    _ = vm;
    var asm_ctx = x64.Assembler.init(allocator);
    defer asm_ctx.deinit();

    var bc_to_native = std.AutoHashMap(usize, u32).init(allocator);
    defer bc_to_native.deinit();

    var pending_branches: std.ArrayList(PendingBranch) = .empty;
    defer pending_branches.deinit(allocator);

    var pending_exits: std.ArrayList(PendingSideExit) = .empty;
    defer pending_exits.deinit(allocator);

    var pending_returns: std.ArrayList(u32) = .empty;
    defer pending_returns.deinit(allocator);

    var pending_quick_exits: std.ArrayList(u32) = .empty;
    defer pending_quick_exits.deinit(allocator);

    // --- Entry trampoline: save callee-saved, set up state registers ---
    try asm_ctx.emitPush(.rbx);
    try asm_ctx.emitPush(.rbp);
    try asm_ctx.emitPush(.r12);
    try asm_ctx.emitPush(.r13);
    try asm_ctx.emitPush(.r14);
    try asm_ctx.emitPush(.r15);

    // rdi=VM*, rsi=base, rdx=constants, rcx=closure (System V ABI)
    try asm_ctx.emitMovReg(X_VM_PTR, .rdi);
    try x64EmitAddLargeOffset(&asm_ctx, X_REG_BASE, X_VM_PTR, OFF_REGISTERS);
    try asm_ctx.emitLslImm(X_BASE_OFF, .rsi, 3);
    try asm_ctx.emitAddReg(X_FRAME_PTR, X_REG_BASE, X_BASE_OFF);
    try asm_ctx.emitMovReg(X_CONST_PTR, .rdx);
    try asm_ctx.emitMovReg(X_CLOSURE_PTR, .rcx);

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
                try x64EmitLoadImmediate(&asm_ctx, dst, types.NIL);
            },
            .load_true => {
                const dst = code[ip];
                ip += 1;
                try x64EmitLoadImmediate(&asm_ctx, dst, types.TRUE);
            },
            .load_false => {
                const dst = code[ip];
                ip += 1;
                try x64EmitLoadImmediate(&asm_ctx, dst, types.FALSE);
            },
            .load_void => {
                const dst = code[ip];
                ip += 1;
                try x64EmitLoadImmediate(&asm_ctx, dst, types.VOID);
            },
            .load_const => {
                const dst = code[ip];
                const idx = readU16(code, ip + 1);
                ip += 3;
                const offset: u32 = @as(u32, idx) * 8;
                if (offset <= 32760) {
                    try asm_ctx.emitLdrImm(.rax, X_CONST_PTR, @intCast(offset));
                } else {
                    try asm_ctx.emitLoadImm64(.rax, offset);
                    try asm_ctx.emitAddReg(.rax, X_CONST_PTR, .rax);
                    try asm_ctx.emitLdrImm(.rax, .rax, 0);
                }
                try x64EmitStoreReg(&asm_ctx, dst, .rax);
            },
            .move => {
                const dst = code[ip];
                const src = code[ip + 1];
                ip += 2;
                try x64EmitLoadReg(&asm_ctx, .rax, src);
                try x64EmitStoreReg(&asm_ctx, dst, .rax);
            },
            .@"return" => {
                const src = code[ip];
                ip += 1;
                try x64EmitLoadReg(&asm_ctx, .rax, src);
                try x64EmitStoreReg(&asm_ctx, 0, .rax);
                const patch_idx = asm_ctx.pos();
                try asm_ctx.emit(0xE9); // JMP rel32
                try asm_ctx.emit32(0);
                try pending_returns.append(allocator, patch_idx + 1);
            },
            .jump => {
                const off = readI16(code, ip);
                ip += 2;
                const target: usize = @intCast(@as(i64, @intCast(ip)) + @as(i64, off));
                const patch_idx = asm_ctx.pos();
                try asm_ctx.emit(0xE9); // JMP rel32
                try asm_ctx.emit32(0);
                try pending_branches.append(allocator, .{
                    .native_idx = patch_idx + 1,
                    .target_bc_ip = target,
                    .cond = null,
                });
            },
            .jump_false => {
                const cond_reg = code[ip];
                const off = readI16(code, ip + 1);
                ip += 3;
                const target: usize = @intCast(@as(i64, @intCast(ip)) + @as(i64, off));
                try x64EmitLoadReg(&asm_ctx, .rax, cond_reg);
                try asm_ctx.emitLoadImm64(.rcx, types.FALSE);
                try asm_ctx.emitCmpReg(.rax, .rcx);
                const patch_idx = asm_ctx.pos();
                try asm_ctx.emit(0x0F); // JE rel32
                try asm_ctx.emit(0x84);
                try asm_ctx.emit32(0);
                try pending_branches.append(allocator, .{
                    .native_idx = patch_idx + 2,
                    .target_bc_ip = target,
                    .cond = Cond.e,
                });
            },
            .jump_true => {
                const cond_reg = code[ip];
                const off = readI16(code, ip + 1);
                ip += 3;
                const target: usize = @intCast(@as(i64, @intCast(ip)) + @as(i64, off));
                try x64EmitLoadReg(&asm_ctx, .rax, cond_reg);
                try asm_ctx.emitLoadImm64(.rcx, types.FALSE);
                try asm_ctx.emitCmpReg(.rax, .rcx);
                const patch_idx = asm_ctx.pos();
                try asm_ctx.emit(0x0F); // JNE rel32
                try asm_ctx.emit(0x85);
                try asm_ctx.emit32(0);
                try pending_branches.append(allocator, .{
                    .native_idx = patch_idx + 2,
                    .target_bc_ip = target,
                    .cond = Cond.ne,
                });
            },
            else => {
                // Side-exit for unhandled opcodes
                const operand_bytes: usize = switch (op) {
                    .get_global, .set_global, .define_global => 3,
                    .get_local, .set_local, .get_upvalue, .set_upvalue => 2,
                    .call, .tail_call => 2,
                    .cons => 3,
                    .call_global, .tail_call_global => 4,
                    .box_local => 1,
                    .get_box_local, .set_box_local => 2,
                    .self_tail_call => 2,
                    else => 0,
                };
                const side_exit_ip = ip - 1;
                ip += operand_bytes;
                const patch_idx = asm_ctx.pos();
                try asm_ctx.emit(0xE9); // JMP rel32
                try asm_ctx.emit32(0);
                try pending_exits.append(allocator, .{
                    .native_idx = patch_idx + 1,
                    .bc_ip = side_exit_ip,
                });
            },
        }
    }

    try bc_to_native.put(ip, asm_ctx.pos());

    // --- Return trampoline ---
    const return_trampoline = asm_ctx.pos();
    try asm_ctx.emitLoadImm64(.rax, 0);
    const ret_to_epi = asm_ctx.pos();
    try asm_ctx.emit(0xE9);
    try asm_ctx.emit32(0);

    // --- Quick exit ---
    const quick_exit = asm_ctx.pos();
    try asm_ctx.emitLoadImm64(.rax, 0xFFFFFFFF);
    const qe_to_epi = asm_ctx.pos();
    try asm_ctx.emit(0xE9);
    try asm_ctx.emit32(0);

    // --- Exit trampoline: rax = bc_ip, add 1 ---
    const exit_start = asm_ctx.pos();
    try asm_ctx.emitAddImm(.rax, .rax, 1);

    // --- Shared epilogue ---
    const epilogue = asm_ctx.pos();
    try asm_ctx.emitPop(.r15);
    try asm_ctx.emitPop(.r14);
    try asm_ctx.emitPop(.r13);
    try asm_ctx.emitPop(.r12);
    try asm_ctx.emitPop(.rbp);
    try asm_ctx.emitPop(.rbx);
    try asm_ctx.emitRet();

    // Patch return/quick-exit to epilogue
    x64PatchJmp(&asm_ctx, ret_to_epi, epilogue);
    x64PatchJmp(&asm_ctx, qe_to_epi, epilogue);

    // Patch branches
    for (pending_branches.items) |pb| {
        const target_native = bc_to_native.get(pb.target_bc_ip) orelse return error.InvalidBytecode;
        x64PatchJmp(&asm_ctx, pb.native_idx, target_native);
    }

    // Patch returns
    for (pending_returns.items) |pr| {
        x64PatchJmp(&asm_ctx, pr, return_trampoline);
    }

    // Patch quick exits
    for (pending_quick_exits.items) |pq| {
        x64PatchJmp(&asm_ctx, pq, quick_exit);
    }

    // Patch side-exits
    for (pending_exits.items) |pe| {
        const stub_pos = asm_ctx.pos();
        try asm_ctx.emitLoadImm64(.rax, pe.bc_ip);
        const after_load = asm_ctx.pos();
        try asm_ctx.emit(0xE9);
        try asm_ctx.emit32(0);
        x64PatchJmp(&asm_ctx, after_load + 1, exit_start);
        x64PatchJmp(&asm_ctx, pe.native_idx, stub_pos);
    }

    // --- Finalize ---
    const code_bytes = asm_ctx.toSlice();
    var buf = try jit_mem.CodeBuffer.alloc(code_bytes.len);
    buf.writeCodeBytes(code_bytes);

    const jit_code = try allocator.create(JitCode);
    jit_code.* = .{
        .entry = @ptrCast(@alignCast(buf.mem.ptr)),
        .buf = buf,
    };
    return jit_code;
}

fn x64PatchJmp(asm_ctx: *x64.Assembler, patch_offset: u32, target: u32) void {
    const rel: i32 = @as(i32, @intCast(target)) - @as(i32, @intCast(patch_offset + 4));
    asm_ctx.patchAt(patch_offset, @bitCast(rel));
}

fn x64EmitLoadImmediate(asm_ctx: *x64.Assembler, dst: u8, value: u64) !void {
    try asm_ctx.emitLoadImm64(.rax, value);
    try x64EmitStoreReg(asm_ctx, dst, .rax);
}

fn x64EmitLoadReg(asm_ctx: *x64.Assembler, rd: X64, src_slot: u8) !void {
    const offset: u16 = @as(u16, src_slot) * 8;
    try asm_ctx.emitLdrImm(rd, X_FRAME_PTR, offset);
}

fn x64EmitStoreReg(asm_ctx: *x64.Assembler, dst_slot: u8, rs: X64) !void {
    const offset: u16 = @as(u16, dst_slot) * 8;
    try asm_ctx.emitStrImm(rs, X_FRAME_PTR, offset);
}

fn x64EmitAddLargeOffset(asm_ctx: *x64.Assembler, rd: X64, rn: X64, offset: usize) !void {
    if (offset <= 4095) {
        try asm_ctx.emitAddImm(rd, rn, @intCast(offset));
    } else {
        try asm_ctx.emitLoadImm64(rd, offset);
        try asm_ctx.emitAddReg(rd, rn, rd);
    }
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

const SpecializedOp = enum { add, sub, mul, lt, gt, le, ge, eq, zero_p, null_p, pair_p, not_op, car, cdr, none };

fn recognizeArithPrimitive(func: *const types.Function, sym_idx: u16, vm: *const VM) SpecializedOp {
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
        .mul => {
            // Untag both: a >> 1, b >> 1, then multiply
            try asm_ctx.emitAsrImm(.x3, .x0, 1); // untag a
            try asm_ctx.emitAsrImm(.x4, .x1, 1); // untag b
            // SMULH x5, x3, x4 — high 64 bits of signed 64×64 multiply
            try asm_ctx.emit(a64.Assembler.smulh(.x5, .x3, .x4));
            // MUL x6, x3, x4 — low 64 bits
            try asm_ctx.emit(a64.Assembler.mul(.x6, .x3, .x4));
            // Overflow check: SMULH result must be sign-extension of MUL result
            // CMP x5, x6, ASR #63
            try asm_ctx.emitAsrImm(.x7, .x6, 63);
            try asm_ctx.emitCmpReg(.x5, .x7);
            const ov_exit = asm_ctx.pos();
            try asm_ctx.emit(0); // b.ne side-exit
            try pending_exits.append(allocator, .{ .native_idx = ov_exit, .bc_ip = bc_ip, .cond = .ne });
            // Also check result fits in 63-bit signed (fixnum range)
            try asm_ctx.emitMovz(.x5, 0, 0); // clear x5
            try asm_ctx.emitMovk(.x5, 0x4000, 3); // x5 = 0x4000_0000_0000_0000 = 2^62
            try asm_ctx.emitCmpReg(.x6, .x5);
            const range_exit = asm_ctx.pos();
            try asm_ctx.emit(0); // b.ge side-exit
            try pending_exits.append(allocator, .{ .native_idx = range_exit, .bc_ip = bc_ip, .cond = .ge });
            // Retag: result << 1
            try asm_ctx.emitLslImm(.x5, .x6, 1);
        },
        .lt, .gt, .le, .ge, .eq => {},
        .zero_p, .null_p, .pair_p, .not_op, .car, .cdr, .none => unreachable,
    }

    switch (spec) {
        .add, .sub, .mul => {
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
        .zero_p, .null_p, .pair_p, .not_op, .car, .cdr => unreachable,
        .none => unreachable,
    }
}

fn emitPairGuard(asm_ctx: *a64.Assembler, val_reg: Reg, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize) !void {
    // Check val_reg is a pointer (bits 0-2 = 000) and non-null
    try asm_ctx.emitMovz(.x9, 7, 0);
    try asm_ctx.emitAndReg(.x9, val_reg, .x9);
    try asm_ctx.emitCmpImm(.x9, 0);
    const ptr_exit = asm_ctx.pos();
    try asm_ctx.emit(0); // b.ne side-exit
    try pending_exits.append(allocator, .{ .native_idx = ptr_exit, .bc_ip = bc_ip, .cond = .ne });
    // Check tag == pair (0)
    try asm_ctx.emitLdrbImm(.x9, val_reg, @intCast(OFF_OBJECT_TAG));
    try asm_ctx.emitMovz(.x10, 0x3F, 0);
    try asm_ctx.emitAndReg(.x9, .x9, .x10);
    try asm_ctx.emitCmpImm(.x9, @intFromEnum(types.ObjectTag.pair));
    const tag_exit = asm_ctx.pos();
    try asm_ctx.emit(0); // b.ne side-exit
    try pending_exits.append(allocator, .{ .native_idx = tag_exit, .bc_ip = bc_ip, .cond = .ne });
}

fn emitSpecializedPredicate(asm_ctx: *a64.Assembler, base_reg: u8, spec: SpecializedOp, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize) !void {
    const arg_off: u16 = (@as(u16, base_reg) + 1) * 8;
    const dst_off: u16 = @as(u16, base_reg) * 8;

    try asm_ctx.emitLdrImm(.x0, FRAME_PTR, arg_off);

    switch (spec) {
        .zero_p => {
            try asm_ctx.emitCmpImm(.x0, 1); // tagged 0
            try asm_ctx.emitMovz(.x1, @intCast(types.FALSE), 0);
            try asm_ctx.emitLoadImm64(.x2, types.TRUE);
            try asm_ctx.emitCsel(.x3, .x2, .x1, .eq);
            try asm_ctx.emitStrImm(.x3, FRAME_PTR, dst_off);
        },
        .null_p => {
            try asm_ctx.emitLoadImm64(.x1, types.NIL);
            try asm_ctx.emitCmpReg(.x0, .x1);
            try asm_ctx.emitMovz(.x2, @intCast(types.FALSE), 0);
            try asm_ctx.emitLoadImm64(.x3, types.TRUE);
            try asm_ctx.emitCsel(.x4, .x3, .x2, .eq);
            try asm_ctx.emitStrImm(.x4, FRAME_PTR, dst_off);
        },
        .pair_p => {
            // Check pointer (low 3 bits = 0) AND tag == pair (0)
            try asm_ctx.emitMovz(.x1, 7, 0);
            try asm_ctx.emitAndReg(.x1, .x0, .x1);
            try asm_ctx.emitMovz(.x4, @intCast(types.FALSE), 0);
            try asm_ctx.emitCmpImm(.x1, 0);
            // Not a pointer → #f
            try asm_ctx.emit(a64.Assembler.bCond(.ne, 6)); // skip to store #f
            // Is a pointer — check tag byte
            try asm_ctx.emitLdrbImm(.x1, .x0, @intCast(OFF_OBJECT_TAG));
            try asm_ctx.emitMovz(.x2, 0x3F, 0);
            try asm_ctx.emitAndReg(.x1, .x1, .x2);
            try asm_ctx.emitCmpImm(.x1, @intFromEnum(types.ObjectTag.pair));
            try asm_ctx.emitLoadImm64(.x5, types.TRUE);
            try asm_ctx.emitCsel(.x4, .x5, .x4, .eq); // tag==pair → TRUE, else FALSE
            try asm_ctx.emitStrImm(.x4, FRAME_PTR, dst_off);
        },
        .not_op => {
            try asm_ctx.emitMovz(.x1, @intCast(types.FALSE), 0);
            try asm_ctx.emitCmpReg(.x0, .x1);
            try asm_ctx.emitLoadImm64(.x2, types.TRUE);
            try asm_ctx.emitCsel(.x3, .x2, .x1, .eq);
            try asm_ctx.emitStrImm(.x3, FRAME_PTR, dst_off);
        },
        .car => {
            // Type guard: must be a pair
            try emitPairGuard(asm_ctx, .x0, pending_exits, allocator, bc_ip);
            // Load car field
            try emitLoadFromField(asm_ctx, .x1, .x0, OFF_PAIR_CAR);
            try asm_ctx.emitStrImm(.x1, FRAME_PTR, dst_off);
        },
        .cdr => {
            // Type guard: must be a pair
            try emitPairGuard(asm_ctx, .x0, pending_exits, allocator, bc_ip);
            // Load cdr field
            try emitLoadFromField(asm_ctx, .x1, .x0, OFF_PAIR_CDR);
            try asm_ctx.emitStrImm(.x1, FRAME_PTR, dst_off);
        },
        else => unreachable,
    }
}

fn emitCons(asm_ctx: *a64.Assembler, dst: u8, car_reg: u8, cdr_reg: u8, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize) !void {
    // Load car and cdr values
    try asm_ctx.emitLdrImm(.x1, FRAME_PTR, @as(u16, car_reg) * 8);
    try asm_ctx.emitLdrImm(.x2, FRAME_PTR, @as(u16, cdr_reg) * 8);
    // Call jitAllocPair(VM*, car, cdr)
    try asm_ctx.emitMovReg(.x0, VM_PTR);
    try asm_ctx.emitLoadImm64(.x8, @intFromPtr(&jitAllocPair));
    try asm_ctx.emitBlr(.x8);
    // Check result (0 = OOM)
    try asm_ctx.emitCmpImm(.x0, 0);
    const oom_exit = asm_ctx.pos();
    try asm_ctx.emit(0); // b.eq side-exit
    try pending_exits.append(allocator, .{ .native_idx = oom_exit, .bc_ip = bc_ip, .cond = .eq });
    // Store result
    try asm_ctx.emitStrImm(.x0, FRAME_PTR, @as(u16, dst) * 8);
}

fn emitSetGlobal(asm_ctx: *a64.Assembler, src: u8, sym_idx: u16, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize) !void {
    // Load symbol from constants
    const byte_offset: u16 = @truncate(@as(u32, sym_idx) * 8);
    try asm_ctx.emitLdrImm(.x1, CONST_PTR, byte_offset);
    // Load value from register
    try asm_ctx.emitLdrImm(.x2, FRAME_PTR, @as(u16, src) * 8);
    // Call jitSetGlobal(VM*, sym_val, value)
    try asm_ctx.emitMovReg(.x0, VM_PTR);
    try asm_ctx.emitLoadImm64(.x8, @intFromPtr(&jitSetGlobal));
    try asm_ctx.emitBlr(.x8);
    // Check result (0 = error)
    try asm_ctx.emitCmpImm(.x0, 0);
    const err_exit = asm_ctx.pos();
    try asm_ctx.emit(0);
    try pending_exits.append(allocator, .{ .native_idx = err_exit, .bc_ip = bc_ip, .cond = .eq });
}

fn emitReturn(asm_ctx: *a64.Assembler, src: u8, pending_exits: *std.ArrayList(PendingSideExit), pending_returns: *std.ArrayList(u32), allocator: std.mem.Allocator, bc_ip: usize) !void {
    // Load return value from source register
    try asm_ctx.emitLdrImm(.x0, FRAME_PTR, @as(u16, src) * 8);

    // Guard: side-exit if wind_count > 0 (dynamic-wind needs interpreter)
    try emitLoadFromVmField(asm_ctx, .x1, OFF_WIND_COUNT);
    try asm_ctx.emitCmpImm(.x1, 0);
    const wind_exit = asm_ctx.pos();
    try asm_ctx.emit(0); // b.ne side-exit
    try pending_exits.append(allocator, .{ .native_idx = wind_exit, .bc_ip = bc_ip, .cond = .ne });

    // Store return value at registers[frame.base - 1] = FRAME_PTR[-8]
    try asm_ctx.emitSubImm(.x1, FRAME_PTR, 8);
    try asm_ctx.emitStrImm(.x0, .x1, 0);

    // Decrement frame_count
    try emitLoadFromVmField(asm_ctx, .x1, OFF_FRAME_COUNT);
    try asm_ctx.emitSubImm(.x1, .x1, 1);
    try emitStoreAtOffset(asm_ctx, .x1, VM_PTR, OFF_FRAME_COUNT);

    // Branch to return trampoline (patched later)
    const ret_br = asm_ctx.pos();
    try asm_ctx.emit(0);
    try pending_returns.append(allocator, ret_br);
}

fn emitCall(asm_ctx: *a64.Assembler, base_reg: u8, nargs: u8, pending_exits: *std.ArrayList(PendingSideExit), pending_returns: *std.ArrayList(u32), pending_quick_exits: *std.ArrayList(u32), allocator: std.mem.Allocator, bc_ip: usize, ip_after: usize, caller_func: *const types.Function) !void {
    _ = caller_func;
    // Load callee value from frame register
    try asm_ctx.emitLdrImm(.x0, FRAME_PTR, @as(u16, base_reg) * 8);
    // Emit the shared call sequence
    try emitCallSequence(asm_ctx, base_reg, nargs, .x0, pending_exits, pending_returns, pending_quick_exits, allocator, bc_ip, ip_after);
}

fn emitCallGlobal(asm_ctx: *a64.Assembler, base_reg: u8, sym_idx: u16, nargs: u8, pending_exits: *std.ArrayList(PendingSideExit), pending_returns: *std.ArrayList(u32), pending_quick_exits: *std.ArrayList(u32), allocator: std.mem.Allocator, bc_ip: usize, ip_after: usize, caller_func: *const types.Function) !void {
    _ = caller_func;
    // Resolve global from cache into frame[base_reg], then load it
    try emitGetGlobal(asm_ctx, base_reg, sym_idx, pending_exits, allocator, bc_ip);
    try asm_ctx.emitLdrImm(.x0, FRAME_PTR, @as(u16, base_reg) * 8);
    // Emit the shared call sequence
    try emitCallSequence(asm_ctx, base_reg, nargs, .x0, pending_exits, pending_returns, pending_quick_exits, allocator, bc_ip, ip_after);
}

fn emitCallSequence(asm_ctx: *a64.Assembler, base_reg: u8, nargs: u8, callee_reg: Reg, pending_exits: *std.ArrayList(PendingSideExit), pending_returns: *std.ArrayList(u32), pending_quick_exits: *std.ArrayList(u32), allocator: std.mem.Allocator, bc_ip: usize, ip_after: usize) !void {
    _ = callee_reg; // always .x0
    _ = pending_quick_exits;

    // --- Pointer check: bits 0-1 must be 0 and value must be non-zero ---
    // Layout: [0]tbnz, [1]tbnz, [2]cmp, [3]b.eq, [4]b(skip), [5]side_exit_B, [6]...
    try asm_ctx.emit(a64.Assembler.tbnz(.x0, 0, 5)); // fixnum → side-exit at [5]
    try asm_ctx.emit(a64.Assembler.tbnz(.x0, 1, 4)); // immediate → side-exit at [5]
    try asm_ctx.emitCmpImm(.x0, 0);
    try asm_ctx.emit(a64.Assembler.bCond(.eq, 2)); // null → side-exit at [5]
    try asm_ctx.emit(a64.Assembler.b(2)); // success → skip to [6]
    const se_b = asm_ctx.pos();
    try asm_ctx.emit(0);
    try pending_exits.append(allocator, .{ .native_idx = se_b, .bc_ip = bc_ip });

    // --- Tag check: object tag must be closure (3) ---
    // x0 is a valid pointer to a heap Object
    try asm_ctx.emitLdrbImm(.x1, .x0, @intCast(OFF_OBJECT_TAG));
    // Mask to 6 bits (ObjectTag is u6, might share byte with marked bit)
    try asm_ctx.emitMovz(.x2, 0x3F, 0);
    try asm_ctx.emitAndReg(.x1, .x1, .x2);
    try asm_ctx.emitCmpImm(.x1, @intFromEnum(types.ObjectTag.closure));
    const tag_exit = asm_ctx.pos();
    try asm_ctx.emit(0); // b.ne side-exit
    try pending_exits.append(allocator, .{ .native_idx = tag_exit, .bc_ip = bc_ip, .cond = .ne });

    // --- Load closure.func, check arity, variadic, frame_count, jit_code ---
    // x0 = Closure*, load func pointer
    try emitLoadFromField(asm_ctx, .x5, .x0, OFF_CLOSURE_FUNC); // x5 = func*

    // Check arity == nargs
    try asm_ctx.emitLdrbImm(.x1, .x5, @intCast(OFF_FUNC_ARITY));
    try asm_ctx.emitCmpImm(.x1, nargs);
    const arity_exit = asm_ctx.pos();
    try asm_ctx.emit(0); // b.ne side-exit
    try pending_exits.append(allocator, .{ .native_idx = arity_exit, .bc_ip = bc_ip, .cond = .ne });

    // Check !is_variadic
    try asm_ctx.emitLdrbImm(.x1, .x5, @intCast(OFF_FUNC_IS_VARIADIC));
    try asm_ctx.emitCmpImm(.x1, 0);
    const var_exit = asm_ctx.pos();
    try asm_ctx.emit(0); // b.ne side-exit
    try pending_exits.append(allocator, .{ .native_idx = var_exit, .bc_ip = bc_ip, .cond = .ne });

    // Check frame_count < MAX_FRAMES
    try emitLoadFromVmField(asm_ctx, .x1, OFF_FRAME_COUNT);
    try asm_ctx.emitLoadImm64(.x2, MAX_FRAMES);
    try asm_ctx.emitCmpReg(.x1, .x2);
    const fc_exit = asm_ctx.pos();
    try asm_ctx.emit(0); // b.hs side-exit (unsigned >=)
    try pending_exits.append(allocator, .{ .native_idx = fc_exit, .bc_ip = bc_ip, .cond = .hs });

    // Check func.jit_code != null
    try emitLoadFromField(asm_ctx, .x6, .x5, OFF_FUNC_JIT_CODE); // x6 = jit_code*
    try asm_ctx.emitCmpImm(.x6, 0);
    const jit_exit = asm_ctx.pos();
    try asm_ctx.emit(0); // b.eq side-exit
    try pending_exits.append(allocator, .{ .native_idx = jit_exit, .bc_ip = bc_ip, .cond = .eq });

    // --- Save caller's frame IP (pointing past the call instruction) ---
    // Compute caller's frame address: &frames[frame_count - 1]
    // x1 still has frame_count from the check above
    try asm_ctx.emitSubImm(.x1, .x1, 1); // x1 = frame_count - 1
    try emitMulConst(asm_ctx, .x2, .x1, SIZEOF_CALLFRAME);
    try emitAddLargeOffset(asm_ctx, .x3, VM_PTR, OFF_FRAMES);
    try asm_ctx.emitAddReg(.x3, .x3, .x2); // x3 = &frames[frame_count-1] (caller frame)
    try asm_ctx.emitLoadImm64(.x4, ip_after);
    try emitStoreAtOffset(asm_ctx, .x4, .x3, OFF_FRAME_IP);

    // --- Push new frame ---
    // New frame address = x3 + SIZEOF_CALLFRAME = &frames[frame_count]
    try asm_ctx.emitLoadImm64(.x4, SIZEOF_CALLFRAME);
    try asm_ctx.emitAddReg(.x3, .x3, .x4); // x3 = &frames[frame_count] (new frame)

    // new_base = frame.base + base_reg + 1
    // frame.base = BASE_OFF / 8
    try asm_ctx.emit(a64.Assembler.asrImm(.x7, BASE_OFF, 3)); // x7 = frame.base (not really ASR, it's LSR since BASE_OFF is unsigned)
    // Actually BASE_OFF = frame.base * 8 and is always positive, so LSR is correct.
    // But asrImm is arithmetic shift. For unsigned values this works fine (no sign extension needed for small values).
    // Use the raw LSR encoding via lslImm? No, LSR is a different alias.
    // Let me just divide: x7 = BASE_OFF >> 3
    try asm_ctx.emitLoadImm64(.x4, @as(u16, base_reg) + 1);
    try asm_ctx.emitAddReg(.x7, .x7, .x4); // x7 = frame.base + base_reg + 1 = new_base

    // Store frame fields:
    // closure (x0) at OFF_FRAME_CLOSURE
    try emitStoreAtOffset(asm_ctx, .x0, .x3, OFF_FRAME_CLOSURE);

    // native = null (0)
    try asm_ctx.emitMovz(.x4, 0, 0);
    try emitStoreAtOffset(asm_ctx, .x4, .x3, OFF_FRAME_NATIVE);

    // code = func.code.items (ptr at OFF_FUNC_CODE, len at OFF_FUNC_CODE+8)
    try emitLoadFromField(asm_ctx, .x4, .x5, OFF_FUNC_CODE); // items.ptr
    try emitStoreAtOffset(asm_ctx, .x4, .x3, OFF_FRAME_CODE);
    try emitLoadFromField(asm_ctx, .x4, .x5, OFF_FUNC_CODE + 8); // items.len
    try emitStoreAtOffset(asm_ctx, .x4, .x3, OFF_FRAME_CODE + 8);

    // ip = 0
    try asm_ctx.emitMovz(.x4, 0, 0);
    try emitStoreAtOffset(asm_ctx, .x4, .x3, OFF_FRAME_IP);

    // base = new_base (u16)
    try emitStoreHalfAtOffset(asm_ctx, .x7, .x3, OFF_FRAME_BASE);

    // dst = base_reg (u8)
    try emitStoreByteAtOffset(asm_ctx, base_reg, .x3, OFF_FRAME_DST, .x4);

    // saved_wind_count = vm.wind_count (u16, but wind_count is usize)
    try emitLoadFromVmField(asm_ctx, .x4, OFF_WIND_COUNT);
    try emitStoreHalfAtOffset(asm_ctx, .x4, .x3, OFF_FRAME_SAVED_WIND);

    // Increment frame_count
    try emitLoadFromVmField(asm_ctx, .x1, OFF_FRAME_COUNT);
    try asm_ctx.emitAddImm(.x1, .x1, 1);
    try emitStoreAtOffset(asm_ctx, .x1, VM_PTR, OFF_FRAME_COUNT);

    // Increment call_count (wrapping)
    try emitLoadWFromField(asm_ctx, .x1, .x5, OFF_FUNC_CALL_COUNT);
    try asm_ctx.emitAddImm(.x1, .x1, 1);
    try emitStoreWAtOffset(asm_ctx, .x1, .x5, OFF_FUNC_CALL_COUNT);

    // --- Call callee's JIT entry ---
    // Load entry point: jit_code.entry
    try emitLoadFromField(asm_ctx, .x8, .x6, OFF_JIT_CODE_ENTRY); // x8 = entry fn ptr

    // Set up arguments:
    // x0 = VM* (from VM_PTR = x21)
    // x1 = new_base (from x7)
    // x2 = callee func.constants.items.ptr
    // x3 = callee closure* (from x0, but x0 will be overwritten)

    // Save closure pointer before setting up args
    try asm_ctx.emitMovReg(.x9, .x0); // x9 = callee closure*
    // Load callee constants
    try emitLoadFromField(asm_ctx, .x2, .x5, OFF_FUNC_CONSTANTS); // x2 = constants.items.ptr
    try asm_ctx.emitMovReg(.x3, .x9); // x3 = callee closure*
    try asm_ctx.emitMovReg(.x1, .x7); // x1 = new_base
    try asm_ctx.emitMovReg(.x0, VM_PTR); // x0 = VM*

    try asm_ctx.emitBlr(.x8);

    // --- Handle result ---
    // x0 = callee's JIT result (0 = normal completion, >0 = exit IP + 1)
    // Our callee-saved registers (FRAME_PTR, CONST_PTR, etc.) are restored by C ABI.

    try asm_ctx.emitCmpImm(.x0, 0);
    const callee_ok = asm_ctx.pos();
    try asm_ctx.emit(0); // b.eq → callee completed, skip fixup

    // Callee side-exited: frame IP already set by callee's exit trampoline.
    // Call jitFinishCallee(VM*, 0, dst_abs_idx) to run callee to completion.
    try asm_ctx.emit(a64.Assembler.asrImm(.x2, BASE_OFF, 3)); // x2 = frame.base
    try asm_ctx.emitAddImm(.x2, .x2, base_reg); // x2 = dst_abs_idx
    try asm_ctx.emitMovz(.x1, 0, 0); // unused arg
    try asm_ctx.emitMovReg(.x0, VM_PTR);
    try asm_ctx.emitLoadImm64(.x8, @intFromPtr(&jitFinishCallee));
    try asm_ctx.emitBlr(.x8);

    // Helper result: 1 = success, 0 = error (jit_error set)
    try asm_ctx.emitCmpImm(.x0, 0);
    try asm_ctx.emit(a64.Assembler.bCond(.ne, 2)); // success → skip error branch
    const err_br = asm_ctx.pos();
    try asm_ctx.emit(0); // placeholder B to return_trampoline
    try pending_returns.append(allocator, err_br);

    // Patch callee_ok to point to here (success continuation)
    const final_ok = asm_ctx.pos();
    const final_ok_off: i32 = @as(i32, @intCast(final_ok)) - @as(i32, @intCast(callee_ok));
    asm_ctx.patchAt(callee_ok, a64.Assembler.bCond(.eq, @intCast(final_ok_off)));
}

fn isSelfCall(func: *const types.Function, sym_idx: u16, nargs: u8) bool {
    if (func.name == null or func.is_variadic) return false;
    if (nargs != func.arity) return false;
    if (sym_idx >= func.constants.items.len) return false;
    const sym_val = func.constants.items[sym_idx];
    if (!types.isSymbol(sym_val)) return false;
    return std.mem.eql(u8, types.symbolName(sym_val), func.name.?);
}

fn emitSelfCallSequence(asm_ctx: *a64.Assembler, base_reg: u8, nargs: u8, pending_exits: *std.ArrayList(PendingSideExit), pending_returns: *std.ArrayList(u32), pending_quick_exits: *std.ArrayList(u32), allocator: std.mem.Allocator, bc_ip: usize, ip_after: usize) !void {
    _ = nargs;
    _ = pending_quick_exits;

    // Optimized self-call: skip all guard checks (pointer, tag, arity, variadic,
    // jit_code) and call_count increment — all invariants for self-recursive calls.

    // Load frame_count ONCE, reuse for overflow check + caller frame + increment
    try emitLoadFromVmField(asm_ctx, .x1, OFF_FRAME_COUNT);
    try asm_ctx.emitMovReg(.x6, .x1); // x6 = saved frame_count

    // frame_count < MAX_FRAMES check
    try asm_ctx.emitLoadImm64(.x2, MAX_FRAMES);
    try asm_ctx.emitCmpReg(.x1, .x2);
    const fc_exit = asm_ctx.pos();
    try asm_ctx.emit(0);
    try pending_exits.append(allocator, .{ .native_idx = fc_exit, .bc_ip = bc_ip, .cond = .hs });

    // Save caller's frame IP: frames[frame_count - 1].ip = ip_after
    try asm_ctx.emitSubImm(.x1, .x6, 1);
    try emitMulConst(asm_ctx, .x2, .x1, SIZEOF_CALLFRAME);
    try emitAddLargeOffset(asm_ctx, .x3, VM_PTR, OFF_FRAMES);
    try asm_ctx.emitAddReg(.x3, .x3, .x2);
    try asm_ctx.emitLoadImm64(.x4, ip_after);
    try emitStoreAtOffset(asm_ctx, .x4, .x3, OFF_FRAME_IP);

    // Advance to new frame: x3 = &frames[frame_count]
    try asm_ctx.emitLoadImm64(.x4, SIZEOF_CALLFRAME);
    try asm_ctx.emitAddReg(.x3, .x3, .x4);

    // new_base = frame.base + base_reg + 1
    try asm_ctx.emit(a64.Assembler.asrImm(.x7, BASE_OFF, 3));
    try asm_ctx.emitLoadImm64(.x4, @as(u16, base_reg) + 1);
    try asm_ctx.emitAddReg(.x7, .x7, .x4);

    // Load func pointer once — used for code, jit_code
    try emitLoadFromField(asm_ctx, .x5, CLOSURE_PTR, OFF_CLOSURE_FUNC);

    // STP: store closure + native=null together (offsets 0, 8)
    try asm_ctx.emitMovz(.x4, 0, 0);
    if (OFF_FRAME_CLOSURE == 0 and @offsetOf(CallFrame, "native") == 8) {
        try asm_ctx.emitStp(CLOSURE_PTR, .x4, .x3, 0);
    } else {
        try emitStoreAtOffset(asm_ctx, CLOSURE_PTR, .x3, OFF_FRAME_CLOSURE);
        try emitStoreAtOffset(asm_ctx, .x4, .x3, @offsetOf(CallFrame, "native"));
    }

    // STP: store code.ptr + code.len together (offsets 16, 24)
    try emitLoadFromField(asm_ctx, .x1, .x5, OFF_FUNC_CODE);
    try emitLoadFromField(asm_ctx, .x2, .x5, OFF_FUNC_CODE + 8);
    if (OFF_FRAME_CODE == 16) {
        try asm_ctx.emitStp(.x1, .x2, .x3, 2); // offset 2 * 8 = 16
    } else {
        try emitStoreAtOffset(asm_ctx, .x1, .x3, OFF_FRAME_CODE);
        try emitStoreAtOffset(asm_ctx, .x2, .x3, OFF_FRAME_CODE + 8);
    }

    // ip = 0 (reuse x4 which is still 0)
    try emitStoreAtOffset(asm_ctx, .x4, .x3, OFF_FRAME_IP);

    // base, dst, saved_wind_count
    try emitStoreHalfAtOffset(asm_ctx, .x7, .x3, OFF_FRAME_BASE);
    try emitStoreByteAtOffset(asm_ctx, base_reg, .x3, OFF_FRAME_DST, .x4);
    try emitLoadFromVmField(asm_ctx, .x4, OFF_WIND_COUNT);
    try emitStoreHalfAtOffset(asm_ctx, .x4, .x3, OFF_FRAME_SAVED_WIND);

    // Increment frame_count (reuse saved value in x6)
    try asm_ctx.emitAddImm(.x1, .x6, 1);
    try emitStoreAtOffset(asm_ctx, .x1, VM_PTR, OFF_FRAME_COUNT);

    // Call self's JIT entry (skip call_count — already JIT-compiled)
    try emitLoadFromField(asm_ctx, .x6, .x5, OFF_FUNC_JIT_CODE);
    try emitLoadFromField(asm_ctx, .x8, .x6, OFF_JIT_CODE_ENTRY);

    // Args: x0=VM*, x1=new_base, x2=CONST_PTR, x3=CLOSURE_PTR
    try asm_ctx.emitMovReg(.x2, CONST_PTR);
    try asm_ctx.emitMovReg(.x3, CLOSURE_PTR);
    try asm_ctx.emitMovReg(.x1, .x7);
    try asm_ctx.emitMovReg(.x0, VM_PTR);

    try asm_ctx.emitBlr(.x8);

    // Handle result
    try asm_ctx.emitCmpImm(.x0, 0);
    const callee_ok = asm_ctx.pos();
    try asm_ctx.emit(0);

    // Callee side-exited — call jitFinishCallee
    try asm_ctx.emit(a64.Assembler.asrImm(.x2, BASE_OFF, 3));
    try asm_ctx.emitAddImm(.x2, .x2, base_reg);
    try asm_ctx.emitMovz(.x1, 0, 0);
    try asm_ctx.emitMovReg(.x0, VM_PTR);
    try asm_ctx.emitLoadImm64(.x8, @intFromPtr(&jitFinishCallee));
    try asm_ctx.emitBlr(.x8);

    try asm_ctx.emitCmpImm(.x0, 0);
    try asm_ctx.emit(a64.Assembler.bCond(.ne, 2));
    const err_br = asm_ctx.pos();
    try asm_ctx.emit(0);
    try pending_returns.append(allocator, err_br);

    const final_ok = asm_ctx.pos();
    const final_ok_off: i32 = @as(i32, @intCast(final_ok)) - @as(i32, @intCast(callee_ok));
    asm_ctx.patchAt(callee_ok, a64.Assembler.bCond(.eq, @intCast(final_ok_off)));
}

fn emitStoreHalfAtOffset(asm_ctx: *a64.Assembler, rt: Reg, rn: Reg, offset: usize) !void {
    if (offset <= 8190 and offset % 2 == 0) {
        try asm_ctx.emitStrhImm(rt, rn, @intCast(offset));
    } else {
        try asm_ctx.emitLoadImm64(.x4, offset);
        try asm_ctx.emitAddReg(.x4, rn, .x4);
        try asm_ctx.emit(a64.Assembler.strhImm(.x4, .x4, 0));
    }
}

fn emitStoreByteAtOffset(asm_ctx: *a64.Assembler, value: u8, rn: Reg, offset: usize, tmp: Reg) !void {
    try asm_ctx.emitMovz(tmp, value, 0);
    if (offset <= 4095) {
        try asm_ctx.emitStrbImm(tmp, rn, @intCast(offset));
    } else {
        try asm_ctx.emitLoadImm64(.x4, offset);
        try asm_ctx.emitAddReg(.x4, rn, .x4);
        try asm_ctx.emit(a64.Assembler.strbImm(tmp, .x4, 0));
    }
}

fn emitStoreWAtOffset(asm_ctx: *a64.Assembler, rt: Reg, rn: Reg, offset: usize) !void {
    if (offset <= 16380 and offset % 4 == 0) {
        try asm_ctx.emit(a64.Assembler.strWImm(rt, rn, @intCast(offset)));
    } else {
        try asm_ctx.emitLoadImm64(.x4, offset);
        try asm_ctx.emitAddReg(.x4, rn, .x4);
        try asm_ctx.emit(a64.Assembler.strWImm(rt, .x4, 0));
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
    if (@import("builtin").cpu.arch != .aarch64) return error.SkipZigTest;
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
    if (@import("builtin").cpu.arch != .aarch64) return error.SkipZigTest;
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

test "native return stores result and pops frame" {
    const memory = @import("memory.zig");
    const th = @import("testing_helpers.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const f = try gc.allocFunction();
    // load_const r0, 0; return r0
    try f.constants.append(gc.allocator, types.makeFixnum(99));
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.load_const));
    try f.code.append(gc.allocator, 0); // dst r0
    try f.code.append(gc.allocator, 0); // idx lo
    try f.code.append(gc.allocator, 0); // idx hi
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.@"return"));
    try f.code.append(gc.allocator, 0); // src r0
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
    const memory = @import("memory.zig");
    const th = @import("testing_helpers.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const f = try gc.allocFunction();
    // Constants: symbol "*"
    const sym = try gc.allocSymbol("*");
    try f.constants.append(gc.allocator, sym);
    // Bytecode: call_global r0, const[0]("*"), 2; return r0
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.call_global));
    try f.code.append(gc.allocator, 0); // base r0
    try f.code.append(gc.allocator, 0); // sym idx high
    try f.code.append(gc.allocator, 0); // sym idx low
    try f.code.append(gc.allocator, 2); // nargs
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.@"return"));
    try f.code.append(gc.allocator, 0); // src r0
    f.arity = 2;
    f.locals_count = 3;

    try std.testing.expect(isEligible(f));
    const jit_code = try compile(f, &vm, std.testing.allocator);
    defer freeJitCode(jit_code, std.testing.allocator);
    try std.testing.expect(jit_code.buf.len > 0);
}

test "compile call_global with zero? predicate" {
    const memory = @import("memory.zig");
    const th = @import("testing_helpers.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const f = try gc.allocFunction();
    const sym = try gc.allocSymbol("zero?");
    try f.constants.append(gc.allocator, sym);
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.call_global));
    try f.code.append(gc.allocator, 0);
    try f.code.append(gc.allocator, 0);
    try f.code.append(gc.allocator, 0);
    try f.code.append(gc.allocator, 1); // 1 arg
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.@"return"));
    try f.code.append(gc.allocator, 0);
    f.arity = 1;
    f.locals_count = 2;

    try std.testing.expect(isEligible(f));
    const jit_code = try compile(f, &vm, std.testing.allocator);
    defer freeJitCode(jit_code, std.testing.allocator);
    try std.testing.expect(jit_code.buf.len > 0);
}

test "compile tail_call_global with add" {
    const memory = @import("memory.zig");
    const th = @import("testing_helpers.zig");
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const f = try gc.allocFunction();
    const sym = try gc.allocSymbol("+");
    try f.constants.append(gc.allocator, sym);
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.tail_call_global));
    try f.code.append(gc.allocator, 0);
    try f.code.append(gc.allocator, 0);
    try f.code.append(gc.allocator, 0);
    try f.code.append(gc.allocator, 2);
    try f.code.append(gc.allocator, @intFromEnum(types.OpCode.@"return"));
    try f.code.append(gc.allocator, 0);
    f.arity = 2;
    f.locals_count = 3;

    try std.testing.expect(isEligible(f));
    const jit_code = try compile(f, &vm, std.testing.allocator);
    defer freeJitCode(jit_code, std.testing.allocator);
    try std.testing.expect(jit_code.buf.len > 0);
}
