const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const jit_mem = @import("jit_mem.zig");
const x64 = @import("jit_x86_64.zig");
const jit = @import("jit.zig");

// Re-import from jit.zig with local aliases
const VM = jit.VM;
const CallFrame = jit.CallFrame;
const JitCode = jit.JitCode;
const PendingBranch = jit.PendingBranch;
const PendingSideExit = jit.PendingSideExit;
const RegCache = jit.RegCache;
const CacheSnapshot = jit.CacheSnapshot;
const CacheEntry = jit.CacheEntry;
const SpecializedOp = jit.SpecializedOp;

// Offset constants
const OFF_REGISTERS = jit.OFF_REGISTERS;
const OFF_FRAME_COUNT = jit.OFF_FRAME_COUNT;
const OFF_FRAMES = jit.OFF_FRAMES;
const SIZEOF_CALLFRAME = jit.SIZEOF_CALLFRAME;
const OFF_FRAME_IP = jit.OFF_FRAME_IP;
const OFF_CLOSURE_UPVALUES = jit.OFF_CLOSURE_UPVALUES;
const OFF_CLOSURE_FUNC = jit.OFF_CLOSURE_FUNC;
const OFF_FUNC_GLOBAL_CACHE = jit.OFF_FUNC_GLOBAL_CACHE;
const OFF_FUNC_CACHE_VERSION = jit.OFF_FUNC_CACHE_VERSION;
const OFF_VM_GLOBAL_VERSION = jit.OFF_VM_GLOBAL_VERSION;
const OFF_WIND_COUNT = jit.OFF_WIND_COUNT;
const OFF_VM_JIT_ERROR = jit.OFF_VM_JIT_ERROR;
const OFF_FRAME_CLOSURE = jit.OFF_FRAME_CLOSURE;
const OFF_FRAME_NATIVE = jit.OFF_FRAME_NATIVE;
const OFF_FRAME_CODE = jit.OFF_FRAME_CODE;
const OFF_FRAME_BASE = jit.OFF_FRAME_BASE;
const OFF_FRAME_DST = jit.OFF_FRAME_DST;
const OFF_FRAME_SAVED_WIND = jit.OFF_FRAME_SAVED_WIND;
const OFF_FUNC_ARITY = jit.OFF_FUNC_ARITY;
const OFF_FUNC_IS_VARIADIC = jit.OFF_FUNC_IS_VARIADIC;
const OFF_FUNC_JIT_CODE = jit.OFF_FUNC_JIT_CODE;
const OFF_FUNC_CODE = jit.OFF_FUNC_CODE;
const OFF_FUNC_CALL_COUNT = jit.OFF_FUNC_CALL_COUNT;
const OFF_FUNC_CONSTANTS = jit.OFF_FUNC_CONSTANTS;
const OFF_JIT_CODE_ENTRY = jit.OFF_JIT_CODE_ENTRY;
const OFF_OBJECT_TAG = jit.OFF_OBJECT_TAG;
const OFF_PAIR_CAR = jit.OFF_PAIR_CAR;
const OFF_PAIR_CDR = jit.OFF_PAIR_CDR;
const MAX_FRAMES = jit.MAX_FRAMES;
const CACHE_REGS = jit.CACHE_REGS;

// Helper function imports
const readU16 = jit.readU16;
const readI16 = jit.readI16;
const isSelfCall = jit.isSelfCall;
const recognizeArithPrimitive = jit.recognizeArithPrimitive;
const safeJumpTarget = jit.safeJumpTarget;

// Callback function references
const jitCreateClosure = jit.jitCreateClosure;
const jitTailCallNative = jit.jitTailCallNative;
const jitAllocPair = jit.jitAllocPair;
const jitFinishCallee = jit.jitFinishCallee;
const jitSetGlobal = jit.jitSetGlobal;

// x86_64 register aliases
const X64 = x64.Reg;
const X_VM_PTR = x64.Reg.r13;
const X_REG_BASE = x64.Reg.r14;
const X_BASE_OFF = x64.Reg.r15;
const X_FRAME_PTR = x64.Reg.rbx;
const X_CONST_PTR = x64.Reg.r12;
const X_CLOSURE_PTR = x64.Reg.rbp;

pub fn compile(func: *types.Function, vm: *VM, allocator: std.mem.Allocator) !*JitCode {
    // Track which get_global symbol was last loaded into each register
    var reg_global_sym: [256]?u16 = .{null} ** 256;

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
    // 6 pushes + return address = 56 bytes; align to 16 for C ABI calls
    try asm_ctx.emitSubImm(.rsp, .rsp, 8);

    // rdi=VM*, rsi=base, rdx=constants, rcx=closure (System V ABI)
    try asm_ctx.emitMovReg(X_VM_PTR, .rdi);
    try x64EmitAddLargeOffset(&asm_ctx, X_REG_BASE, X_VM_PTR, OFF_REGISTERS);
    try asm_ctx.emitLslImm(X_BASE_OFF, .rsi, 3);
    try asm_ctx.emitAddReg(X_FRAME_PTR, X_REG_BASE, X_BASE_OFF);
    try asm_ctx.emitMovReg(X_CONST_PTR, .rdx);
    try asm_ctx.emitMovReg(X_CLOSURE_PTR, .rcx);

    // --- Register cache and branch-target pre-scan ---
    const code = func.code.items;
    var cache = RegCache{};

    // Pre-scan bytecode to find branch targets where cache must be invalidated
    var branch_targets = std.AutoHashMap(usize, void).init(allocator);
    defer branch_targets.deinit();
    {
        var scan_ip: usize = 0;
        while (scan_ip < code.len) {
            const scan_raw = code[scan_ip];
            const scan_op: types.OpCode = @enumFromInt(scan_raw);
            scan_ip += 1;
            switch (scan_op) {
                .jump => {
                    const off = readI16(code, scan_ip);
                    scan_ip += 2;
                    const target = safeJumpTarget(scan_ip, off, code.len) orelse return error.InvalidBytecode;
                    try branch_targets.put(target, {});
                },
                .jump_false, .jump_true => {
                    scan_ip += 2;
                    const off = readI16(code, scan_ip);
                    scan_ip += 2;
                    const target = safeJumpTarget(scan_ip, off, code.len) orelse return error.InvalidBytecode;
                    try branch_targets.put(target, {});
                },
                .self_tail_call => {
                    scan_ip += 3;
                    try branch_targets.put(0, {});
                },
                else => {
                    const skip: usize = switch (scan_op) {
                        .load_const, .get_global, .jump_false, .jump_true => 4,
                        .set_global, .define_global => 4,
                        .cons => 6,
                        .move, .get_local, .set_local, .get_upvalue, .set_upvalue, .get_box_local, .set_box_local => 4,
                        .call, .tail_call, .self_tail_call => 3,
                        .call_global, .tail_call_global => 5,
                        .load_nil, .load_true, .load_false, .load_void => 2,
                        .box_local => 2,
                        .@"return" => 2,
                        .jump => 2,
                        else => 0,
                    };
                    scan_ip += skip;
                },
            }
        }
    }

    // --- Bytecode walk ---
    var ip: usize = 0;
    while (ip < code.len) {
        // Invalidate cache at branch targets
        if (branch_targets.contains(ip)) {
            try cache.invalidateAll(&asm_ctx);
        }

        try bc_to_native.put(ip, asm_ctx.pos());

        const raw = code[ip];
        const op: types.OpCode = @enumFromInt(raw);
        ip += 1;

        switch (op) {
            .load_nil => {
                const dst = readU16(code, ip);
                ip += 2;
                try asm_ctx.emitLoadImm64(.rax, types.NIL);
                try cachedStore(&asm_ctx, &cache, dst, .rax);
            },
            .load_true => {
                const dst = readU16(code, ip);
                ip += 2;
                try asm_ctx.emitLoadImm64(.rax, types.TRUE);
                try cachedStore(&asm_ctx, &cache, dst, .rax);
            },
            .load_false => {
                const dst = readU16(code, ip);
                ip += 2;
                try asm_ctx.emitLoadImm64(.rax, types.FALSE);
                try cachedStore(&asm_ctx, &cache, dst, .rax);
            },
            .load_void => {
                const dst = readU16(code, ip);
                ip += 2;
                try asm_ctx.emitLoadImm64(.rax, types.VOID);
                try cachedStore(&asm_ctx, &cache, dst, .rax);
            },
            .load_const => {
                const dst = readU16(code, ip);
                const idx = readU16(code, ip + 2);
                ip += 4;
                const offset: u32 = @as(u32, idx) * 8;
                if (offset <= 32760) {
                    try asm_ctx.emitLdrImm(.rax, X_CONST_PTR, @intCast(offset));
                } else {
                    try asm_ctx.emitLoadImm64(.rax, offset);
                    try asm_ctx.emitAddReg(.rax, X_CONST_PTR, .rax);
                    try asm_ctx.emitLdrImm(.rax, .rax, 0);
                }
                try cachedStore(&asm_ctx, &cache, dst, .rax);
            },
            .move, .get_local, .set_local => {
                const dst = readU16(code, ip);
                const src = readU16(code, ip + 2);
                ip += 4;
                try cachedLoad(&asm_ctx, &cache, .rax, src);
                try cachedStore(&asm_ctx, &cache, dst, .rax);
            },
            // box_local, get_box_local, set_box_local: side-exit to interpreter
            // (handled by the else case below)
            .@"return" => {
                const src = readU16(code, ip);
                ip += 2;
                const ret_bc_ip = ip - 3;
                // Flush cache before return sequence
                try cache.flushAll(&asm_ctx);
                // Guard: wind_count must be 0
                try x64EmitLoadFromVmField(&asm_ctx, .rcx, OFF_WIND_COUNT);
                try asm_ctx.emitCmpImm(.rcx, 0);
                try x64EmitCondSideExit(&asm_ctx, &pending_exits, allocator, ret_bc_ip, x64.Cond.ne, &cache);
                // Store result at registers[base-1]: [FRAME_PTR - 8]
                try x64EmitLoadReg(&asm_ctx, .rax, src);
                // MOV [rbx-8], rax — use raw encoding for negative offset
                try asm_ctx.emit(0x48); // REX.W
                try asm_ctx.emit(0x89); // MOV r/m64, r64
                try asm_ctx.emit(0x43); // ModRM: mod=01, reg=rax(0), rm=rbx(3)
                try asm_ctx.emit(0xF8); // disp8 = -8
                // Decrement frame_count
                try asm_ctx.emitLdrImm(.rcx, X_VM_PTR, @intCast(@offsetOf(VM, "frame_count")));
                try asm_ctx.emitSubImm(.rcx, .rcx, 1);
                try asm_ctx.emitStrImm(.rcx, X_VM_PTR, @intCast(@offsetOf(VM, "frame_count")));
                const patch_idx = asm_ctx.pos();
                try asm_ctx.emit(0xE9); // JMP rel32
                try asm_ctx.emit32(0);
                try pending_returns.append(allocator, patch_idx + 1);
            },
            .self_tail_call => {
                const base_reg = readU16(code, ip);
                const stc_nargs = code[ip + 2];
                ip += 3;
                try cache.invalidateAll(&asm_ctx);
                var i: u16 = 0;
                while (i < stc_nargs) : (i += 1) {
                    const src_off: u16 = (base_reg + 1 + i) * 8;
                    const dst_off: u16 = i * 8;
                    try asm_ctx.emitLdrImm(.rax, X_FRAME_PTR, src_off);
                    try asm_ctx.emitStrImm(.rax, X_FRAME_PTR, dst_off);
                }
                const patch_idx = asm_ctx.pos();
                try asm_ctx.emit(0xE9); // JMP rel32
                try asm_ctx.emit32(0);
                try pending_branches.append(allocator, .{
                    .native_idx = patch_idx + 1,
                    .target_bc_ip = 0,
                    .cond = null,
                });
            },
            .get_global => {
                const dst_g = readU16(code, ip);
                const sym_idx_g = readU16(code, ip + 2);
                ip += 4;
                try x64EmitGetGlobal(&asm_ctx, dst_g, sym_idx_g, &pending_exits, allocator, ip - 5, &cache);
                if (dst_g < 256) reg_global_sym[dst_g] = sym_idx_g;
            },
            .set_global, .define_global => {
                const sym_idx_s = readU16(code, ip);
                const src_s = readU16(code, ip + 2);
                ip += 4;
                try x64EmitSetGlobal(&asm_ctx, src_s, sym_idx_s, &pending_exits, allocator, ip - 5, &cache);
            },
            .get_upvalue => {
                const dst_uv = readU16(code, ip);
                const idx_uv = readU16(code, ip + 2);
                ip += 4;
                try x64EmitGetUpvalue(&asm_ctx, dst_uv, idx_uv, &pending_exits, allocator, ip - 5, &cache);
            },
            .set_upvalue => {
                const idx_uv2 = readU16(code, ip);
                const src_uv = readU16(code, ip + 2);
                ip += 4;
                try x64EmitSetUpvalue(&asm_ctx, src_uv, idx_uv2, &pending_exits, allocator, ip - 5, &cache);
            },
            .cons => {
                const dst_c = readU16(code, ip);
                const car_reg = readU16(code, ip + 2);
                const cdr_reg = readU16(code, ip + 4);
                ip += 6;
                try x64EmitCons(&asm_ctx, dst_c, car_reg, cdr_reg, &pending_exits, allocator, ip - 7, &cache);
            },
            .closure => {
                const dst_cl = readU16(code, ip);
                const sym_idx_cl = readU16(code, ip + 2);
                ip += 4;
                const bc_ip_cl = ip - 5;
                const inner_func = types.toObject(func.constants.items[sym_idx_cl]).as(types.Function);
                const n_upvalues: usize = inner_func.upvalue_count;
                const descs_ptr = @intFromPtr(code.ptr) + ip;
                ip += n_upvalues * 3;
                try cache.invalidateAll(&asm_ctx);
                // Load func value from constants
                const const_off: u32 = @as(u32, sym_idx_cl) * 8;
                if (const_off <= 32760) {
                    try asm_ctx.emitLdrImm(.rsi, X_CONST_PTR, @intCast(const_off));
                } else {
                    try asm_ctx.emitLoadImm64(.rsi, const_off);
                    try asm_ctx.emitAddReg(.rsi, X_CONST_PTR, .rsi);
                    try asm_ctx.emitLdrImm(.rsi, .rsi, 0);
                }
                try asm_ctx.emitLoadImm64(.rdx, descs_ptr);
                try asm_ctx.emitLoadImm64(.rcx, n_upvalues);
                try asm_ctx.emitMovReg(.rdi, X_VM_PTR);
                try asm_ctx.emitLoadImm64(.rax, @intFromPtr(&jitCreateClosure));
                try asm_ctx.emitBlr(.rax);
                try asm_ctx.emitCmpImm(.rax, 0);
                try x64EmitCondSideExit(&asm_ctx, &pending_exits, allocator, bc_ip_cl, x64.Cond.eq, &cache);
                try asm_ctx.emitStrImm(.rax, X_FRAME_PTR, dst_cl * 8);
            },
            .close_upvalue => {
                ip += 2;
            },
            .call_global => {
                const base_reg_cg = readU16(code, ip);
                const sym_idx_cg = readU16(code, ip + 2);
                const nargs_cg = code[ip + 4];
                ip += 5;
                const bc_ip_cg = ip - 6;
                const spec = recognizeArithPrimitive(func, sym_idx_cg, vm);
                if (spec != .none and nargs_cg == 2 and (spec == .add or spec == .sub or spec == .mul or spec == .lt or spec == .gt or spec == .le or spec == .ge or spec == .eq)) {
                    try x64EmitSpecializedArith(&asm_ctx, base_reg_cg, spec, &pending_exits, allocator, bc_ip_cg, &cache);
                } else if (spec != .none and nargs_cg == 1 and (spec == .zero_p or spec == .null_p or spec == .pair_p or spec == .not_op or spec == .car or spec == .cdr)) {
                    try x64EmitSpecializedPredicate(&asm_ctx, base_reg_cg, spec, &pending_exits, allocator, bc_ip_cg, &cache);
                } else if (isSelfCall(func, sym_idx_cg, nargs_cg)) {
                    try x64EmitSelfCallSequence(&asm_ctx, base_reg_cg, nargs_cg, &pending_exits, &pending_returns, &pending_quick_exits, allocator, bc_ip_cg, ip, &cache);
                } else {
                    try x64EmitCallGlobal(&asm_ctx, base_reg_cg, sym_idx_cg, nargs_cg, &pending_exits, &pending_returns, &pending_quick_exits, allocator, bc_ip_cg, ip, &cache);
                }
            },
            .tail_call_global => {
                const base_reg_tcg = readU16(code, ip);
                const sym_idx_tcg = readU16(code, ip + 2);
                const nargs_tcg = code[ip + 4];
                ip += 5;
                const bc_ip_tcg = ip - 6;
                const spec_t = recognizeArithPrimitive(func, sym_idx_tcg, vm);
                if (spec_t != .none and nargs_tcg == 2 and (spec_t == .add or spec_t == .sub or spec_t == .mul or spec_t == .lt or spec_t == .gt or spec_t == .le or spec_t == .ge or spec_t == .eq)) {
                    try x64EmitSpecializedArith(&asm_ctx, base_reg_tcg, spec_t, &pending_exits, allocator, bc_ip_tcg, &cache);
                } else if (spec_t != .none and nargs_tcg == 1 and (spec_t == .zero_p or spec_t == .null_p or spec_t == .pair_p or spec_t == .not_op or spec_t == .car or spec_t == .cdr)) {
                    try x64EmitSpecializedPredicate(&asm_ctx, base_reg_tcg, spec_t, &pending_exits, allocator, bc_ip_tcg, &cache);
                } else {
                    try cache.invalidateAll(&asm_ctx);
                    try x64EmitUnconditionalSideExit(&asm_ctx, &pending_exits, allocator, bc_ip_tcg, &cache);
                }
            },
            .call => {
                const base_reg_c = readU16(code, ip);
                const nargs_c = code[ip + 2];
                ip += 3;
                try x64EmitCall(&asm_ctx, base_reg_c, nargs_c, &pending_exits, &pending_returns, &pending_quick_exits, allocator, ip - 4, ip, &cache);
            },
            .tail_call => {
                const base_reg_tc = readU16(code, ip);
                const nargs_tc = code[ip + 2];
                ip += 3;
                try x64EmitTailCall(&asm_ctx, base_reg_tc, nargs_tc, &pending_exits, &pending_returns, allocator, ip - 4, if (base_reg_tc < 256) reg_global_sym[base_reg_tc] else null, func, vm, &cache);
            },
            .jump => {
                const off = readI16(code, ip);
                ip += 2;
                const target = safeJumpTarget(ip, off, code.len) orelse return error.InvalidBytecode;
                try cache.invalidateAll(&asm_ctx);
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
                const cond_reg = readU16(code, ip);
                const off = readI16(code, ip + 2);
                ip += 4;
                const target = safeJumpTarget(ip, off, code.len) orelse return error.InvalidBytecode;
                try cachedLoad(&asm_ctx, &cache, .rax, cond_reg);
                try cache.flushAll(&asm_ctx);
                try asm_ctx.emitLoadImm64(.rcx, types.FALSE);
                try asm_ctx.emitCmpReg(.rax, .rcx);
                const patch_idx = asm_ctx.pos();
                try asm_ctx.emit(0x0F); // JE rel32
                try asm_ctx.emit(0x84);
                try asm_ctx.emit32(0);
                try pending_branches.append(allocator, .{
                    .native_idx = patch_idx + 2,
                    .target_bc_ip = target,
                    .cond = x64.Cond.e,
                });
            },
            .jump_true => {
                const cond_reg = readU16(code, ip);
                const off = readI16(code, ip + 2);
                ip += 4;
                const target = safeJumpTarget(ip, off, code.len) orelse return error.InvalidBytecode;
                try cachedLoad(&asm_ctx, &cache, .rax, cond_reg);
                try cache.flushAll(&asm_ctx);
                try asm_ctx.emitLoadImm64(.rcx, types.FALSE);
                try asm_ctx.emitCmpReg(.rax, .rcx);
                const patch_idx = asm_ctx.pos();
                try asm_ctx.emit(0x0F); // JNE rel32
                try asm_ctx.emit(0x85);
                try asm_ctx.emit32(0);
                try pending_branches.append(allocator, .{
                    .native_idx = patch_idx + 2,
                    .target_bc_ip = target,
                    .cond = x64.Cond.ne,
                });
            },
            else => {
                // Side-exit for unhandled opcodes
                const operand_bytes: usize = switch (op) {
                    .box_local => 2,
                    .get_box_local, .set_box_local => 4,
                    else => 0,
                };
                const side_exit_ip = ip - 1;
                ip += operand_bytes;
                try cache.invalidateAll(&asm_ctx);
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
    try asm_ctx.emitAddImm(.rsp, .rsp, 8);
    try asm_ctx.emitPop(.r15);
    try asm_ctx.emitPop(.r14);
    try asm_ctx.emitPop(.r13);
    try asm_ctx.emitPop(.r12);
    try asm_ctx.emitPop(.rbp);
    try asm_ctx.emitPop(.rbx);
    try asm_ctx.emitRet();

    // Patch return/quick-exit to epilogue (patch at +1 to skip E9 opcode)
    x64PatchJmp(&asm_ctx, ret_to_epi + 1, epilogue);
    x64PatchJmp(&asm_ctx, qe_to_epi + 1, epilogue);

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

    // Patch side-exits (flush dirty cached registers before exiting to interpreter)
    for (pending_exits.items) |pe| {
        const stub_pos = asm_ctx.pos();
        // Flush dirty cache entries from the snapshot taken at the side-exit point
        for (pe.cache_snapshot.entries, 0..) |entry_opt, i| {
            if (entry_opt) |entry| {
                if (entry.dirty) {
                    try asm_ctx.emitStrImm(CACHE_REGS[i], X_FRAME_PTR, entry.slot * 8);
                }
            }
        }
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

fn x64EmitLoadImmediate(asm_ctx: *x64.Assembler, dst: u16, value: u64) !void {
    try asm_ctx.emitLoadImm64(.rax, value);
    try x64EmitStoreReg(asm_ctx, dst, .rax);
}

fn x64EmitLoadReg(asm_ctx: *x64.Assembler, rd: X64, src_slot: u16) !void {
    const offset: u16 = src_slot * 8;
    try asm_ctx.emitLdrImm(rd, X_FRAME_PTR, offset);
}

fn x64EmitStoreReg(asm_ctx: *x64.Assembler, dst_slot: u16, rs: X64) !void {
    const offset: u16 = dst_slot * 8;
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

fn x64EmitLoadFromField(asm_ctx: *x64.Assembler, rd: X64, base: X64, offset: usize) !void {
    if (offset <= 32760) {
        try asm_ctx.emitLdrImm(rd, base, @intCast(offset));
    } else {
        try asm_ctx.emitLoadImm64(rd, offset);
        try asm_ctx.emitAddReg(rd, base, rd);
        try asm_ctx.emitLdrImm(rd, rd, 0);
    }
}

fn x64EmitLoadWFromField(asm_ctx: *x64.Assembler, rd: X64, base: X64, offset: usize) !void {
    if (offset <= 32760) {
        try asm_ctx.emitLdrWImm(rd, base, @intCast(offset));
    } else {
        try asm_ctx.emitLoadImm64(.r11, offset);
        try asm_ctx.emitAddReg(.r11, base, .r11);
        try asm_ctx.emitLdrWImm(rd, .r11, 0);
    }
}

fn x64EmitLoadFromVmField(asm_ctx: *x64.Assembler, rd: X64, field_offset: usize) !void {
    try x64EmitLoadFromField(asm_ctx, rd, X_VM_PTR, field_offset);
}

fn x64EmitStoreAtOffset(asm_ctx: *x64.Assembler, rt: X64, rn: X64, offset: usize) !void {
    if (offset <= 32760) {
        try asm_ctx.emitStrImm(rt, rn, @intCast(offset));
    } else {
        try asm_ctx.emitLoadImm64(.r11, offset);
        try asm_ctx.emitAddReg(.r11, rn, .r11);
        try asm_ctx.emitStrImm(rt, .r11, 0);
    }
}

fn x64EmitStoreHalfAtOffset(asm_ctx: *x64.Assembler, rt: X64, rn: X64, offset: usize) !void {
    if (offset <= 32760) {
        try asm_ctx.emitStrhImm(rt, rn, @intCast(offset));
    } else {
        try asm_ctx.emitLoadImm64(.r11, offset);
        try asm_ctx.emitAddReg(.r11, rn, .r11);
        try asm_ctx.emitStrhImm(rt, .r11, 0);
    }
}

fn x64EmitStoreByteValue(asm_ctx: *x64.Assembler, value: u8, rn: X64, offset: usize) !void {
    try asm_ctx.emitLoadImm64(.r11, value);
    if (offset <= 4095) {
        try asm_ctx.emitStrbImm(.r11, rn, @intCast(offset));
    } else {
        try asm_ctx.emitLoadImm64(.r10, offset);
        try asm_ctx.emitAddReg(.r10, rn, .r10);
        try asm_ctx.emitStrbImm(.r11, .r10, 0);
    }
}

fn x64EmitStoreWAtOffset(asm_ctx: *x64.Assembler, rt: X64, rn: X64, offset: usize) !void {
    if (offset <= 32760) {
        try asm_ctx.emitStrWImm(rt, rn, @intCast(offset));
    } else {
        try asm_ctx.emitLoadImm64(.r11, offset);
        try asm_ctx.emitAddReg(.r11, rn, .r11);
        try asm_ctx.emitStrWImm(rt, .r11, 0);
    }
}

fn x64EmitMulConst(asm_ctx: *x64.Assembler, rd: X64, rn: X64, constant: usize) !void {
    if (constant == 0) {
        try asm_ctx.emitLoadImm64(rd, 0);
        return;
    }
    if (std.math.isPowerOfTwo(constant)) {
        const shift: u6 = @intCast(std.math.log2(constant));
        try asm_ctx.emitLslImm(rd, rn, shift);
        return;
    }
    try asm_ctx.emitLoadImm64(.r11, constant);
    try asm_ctx.emitMovReg(rd, rn);
    try asm_ctx.emitImulReg(rd, .r11);
}

fn x64EmitTailCall(asm_ctx: *x64.Assembler, base_reg: u16, nargs: u8, pending_exits: *std.ArrayList(PendingSideExit), pending_returns: *std.ArrayList(u32), allocator: std.mem.Allocator, bc_ip: usize, sym_idx: ?u16, func_ctx: *const types.Function, vm_ctx: *const VM, cache: *RegCache) !void {
    // Peephole: if base_reg was loaded via get_global for a known primitive,
    // emit specialized inline arithmetic/predicate + tail-return.
    if (sym_idx) |si| {
        const spec = recognizeArithPrimitive(func_ctx, si, vm_ctx);
        if (spec != .none and nargs == 2 and (spec == .add or spec == .sub or spec == .mul or spec == .lt or spec == .gt or spec == .le or spec == .ge or spec == .eq)) {
            try x64EmitSpecializedArith(asm_ctx, base_reg, spec, pending_exits, allocator, bc_ip, cache);
            try x64EmitTailReturn(asm_ctx, base_reg, pending_returns, allocator, cache);
            return;
        }
        if (spec != .none and nargs == 1 and (spec == .zero_p or spec == .null_p or spec == .pair_p or spec == .not_op or spec == .car or spec == .cdr)) {
            try x64EmitSpecializedPredicate(asm_ctx, base_reg, spec, pending_exits, allocator, bc_ip, cache);
            try x64EmitTailReturn(asm_ctx, base_reg, pending_returns, allocator, cache);
            return;
        }
    }
    // Fallback: call helper — flush cache before C call
    try cache.invalidateAll(asm_ctx);
    try asm_ctx.emitLdrImm(.rsi, X_FRAME_PTR, base_reg * 8);
    try asm_ctx.emitMovReg(.rdi, X_VM_PTR);
    try asm_ctx.emitLoadImm64(.rdx, base_reg);
    try asm_ctx.emitLoadImm64(.rcx, nargs);
    try asm_ctx.emitLoadImm64(.rax, @intFromPtr(&jitTailCallNative));
    try asm_ctx.emitBlr(.rax);
    // rax: 0 = unhandled, 1 = NativeFn completed, 2 = Closure frame rewritten
    try asm_ctx.emitCmpImm(.rax, 0);
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.eq, cache);
    try asm_ctx.emitCmpImm(.rax, 2);
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, 0, x64.Cond.eq, cache);
    // NativeFn succeeded (rax == 1) — return normally
    const ok_patch = try asm_ctx.emitJmpRel32();
    try pending_returns.append(allocator, ok_patch);
}

fn x64EmitCall(asm_ctx: *x64.Assembler, base_reg: u16, nargs: u8, pending_exits: *std.ArrayList(PendingSideExit), pending_returns: *std.ArrayList(u32), pending_quick_exits: *std.ArrayList(u32), allocator: std.mem.Allocator, bc_ip: usize, ip_after: usize, cache: *RegCache) !void {
    try cache.invalidateAll(asm_ctx);
    try asm_ctx.emitLdrImm(.rax, X_FRAME_PTR, base_reg * 8);
    try x64EmitCallSequence(asm_ctx, base_reg, nargs, pending_exits, pending_returns, pending_quick_exits, allocator, bc_ip, ip_after, cache);
}

fn x64EmitCallGlobal(asm_ctx: *x64.Assembler, base_reg: u16, sym_idx: u16, nargs: u8, pending_exits: *std.ArrayList(PendingSideExit), pending_returns: *std.ArrayList(u32), pending_quick_exits: *std.ArrayList(u32), allocator: std.mem.Allocator, bc_ip: usize, ip_after: usize, cache: *RegCache) !void {
    try cache.invalidateAll(asm_ctx);
    try x64EmitGetGlobal(asm_ctx, base_reg, sym_idx, pending_exits, allocator, bc_ip, cache);
    try asm_ctx.emitLdrImm(.rax, X_FRAME_PTR, base_reg * 8);
    try x64EmitCallSequence(asm_ctx, base_reg, nargs, pending_exits, pending_returns, pending_quick_exits, allocator, bc_ip, ip_after, cache);
}

fn x64EmitCallSequence(asm_ctx: *x64.Assembler, base_reg: u16, nargs: u8, pending_exits: *std.ArrayList(PendingSideExit), pending_returns: *std.ArrayList(u32), pending_quick_exits: *std.ArrayList(u32), allocator: std.mem.Allocator, bc_ip: usize, ip_after: usize, cache: *RegCache) !void {
    _ = pending_quick_exits;
    // rax = callee value

    // --- Pointer check: upper 16 bits must be 0xFFFC (NaN-boxed pointer) ---
    try x64EmitPointerGuard(asm_ctx, .rax, pending_exits, allocator, bc_ip, cache);
    // Extract raw pointer for subsequent dereferences
    try x64EmitExtractPointer(asm_ctx, .rax, .rax);

    // --- Tag check: object tag must be closure (3) ---
    try asm_ctx.emitLdrbImm(.rcx, .rax, @intCast(OFF_OBJECT_TAG));
    try asm_ctx.emitAndImm(.rcx, .rcx, 0x3F);
    try asm_ctx.emitCmpImm(.rcx, @intFromEnum(types.ObjectTag.closure));
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.ne, cache);

    // --- Load closure.func, check arity/variadic/frame_count/jit_code ---
    try x64EmitLoadFromField(asm_ctx, .r8, .rax, OFF_CLOSURE_FUNC); // r8 = func*

    try asm_ctx.emitLdrbImm(.rcx, .r8, @intCast(OFF_FUNC_ARITY));
    try asm_ctx.emitCmpImm(.rcx, nargs);
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.ne, cache);

    try asm_ctx.emitLdrbImm(.rcx, .r8, @intCast(OFF_FUNC_IS_VARIADIC));
    try asm_ctx.emitCmpImm(.rcx, 0);
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.ne, cache);

    try x64EmitLoadFromVmField(asm_ctx, .rcx, OFF_FRAME_COUNT);
    try asm_ctx.emitLoadImm64(.rdx, MAX_FRAMES);
    try asm_ctx.emitCmpReg(.rcx, .rdx);
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.ae, cache);

    try x64EmitLoadFromField(asm_ctx, .r9, .r8, OFF_FUNC_JIT_CODE); // r9 = jit_code*
    try asm_ctx.emitCmpImm(.r9, 0);
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.eq, cache);

    // --- Save caller's frame IP ---
    // rcx still has frame_count from the check above
    try asm_ctx.emitSubImm(.rcx, .rcx, 1);
    try x64EmitMulConst(asm_ctx, .rdx, .rcx, SIZEOF_CALLFRAME);
    try x64EmitAddLargeOffset(asm_ctx, .rsi, X_VM_PTR, OFF_FRAMES);
    try asm_ctx.emitAddReg(.rsi, .rsi, .rdx); // rsi = &frames[frame_count-1]
    try asm_ctx.emitLoadImm64(.rdi, ip_after);
    try x64EmitStoreAtOffset(asm_ctx, .rdi, .rsi, OFF_FRAME_IP);

    // --- Push new frame ---
    try asm_ctx.emitLoadImm64(.rdi, SIZEOF_CALLFRAME);
    try asm_ctx.emitAddReg(.rsi, .rsi, .rdi); // rsi = &frames[frame_count]

    // new_base = BASE_OFF/8 + base_reg + 1
    try asm_ctx.emitAsrImm(.rdi, X_BASE_OFF, 3); // rdi = frame.base
    try asm_ctx.emitLoadImm64(.r11, @as(u64, base_reg) + 1);
    try asm_ctx.emitAddReg(.rdi, .rdi, .r11); // rdi = new_base

    // Store frame fields
    try x64EmitStoreAtOffset(asm_ctx, .rax, .rsi, OFF_FRAME_CLOSURE); // closure
    try asm_ctx.emitLoadImm64(.rcx, 0);
    try x64EmitStoreAtOffset(asm_ctx, .rcx, .rsi, OFF_FRAME_NATIVE); // native = null

    // code = func.code.items (ptr + len)
    try x64EmitLoadFromField(asm_ctx, .rcx, .r8, OFF_FUNC_CODE);
    try x64EmitStoreAtOffset(asm_ctx, .rcx, .rsi, OFF_FRAME_CODE);
    try x64EmitLoadFromField(asm_ctx, .rcx, .r8, OFF_FUNC_CODE + 8);
    try x64EmitStoreAtOffset(asm_ctx, .rcx, .rsi, OFF_FRAME_CODE + 8);

    // ip = 0
    try asm_ctx.emitLoadImm64(.rcx, 0);
    try x64EmitStoreAtOffset(asm_ctx, .rcx, .rsi, OFF_FRAME_IP);

    // base = new_base (u16)
    try x64EmitStoreHalfAtOffset(asm_ctx, .rdi, .rsi, OFF_FRAME_BASE);

    // dst = base_reg (u8)
    try asm_ctx.emitLoadImm64(.r11, base_reg);
    try x64EmitStoreHalfAtOffset(asm_ctx, .r11, .rsi, OFF_FRAME_DST);

    // saved_wind_count
    try x64EmitLoadFromVmField(asm_ctx, .rcx, OFF_WIND_COUNT);
    try x64EmitStoreHalfAtOffset(asm_ctx, .rcx, .rsi, OFF_FRAME_SAVED_WIND);

    // Increment frame_count
    try x64EmitLoadFromVmField(asm_ctx, .rcx, OFF_FRAME_COUNT);
    try asm_ctx.emitAddImm(.rcx, .rcx, 1);
    try x64EmitStoreAtOffset(asm_ctx, .rcx, X_VM_PTR, OFF_FRAME_COUNT);

    // Increment call_count (u32, wrapping)
    try x64EmitLoadWFromField(asm_ctx, .rcx, .r8, OFF_FUNC_CALL_COUNT);
    try asm_ctx.emitAddImm(.rcx, .rcx, 1);
    try x64EmitStoreWAtOffset(asm_ctx, .rcx, .r8, OFF_FUNC_CALL_COUNT);

    // --- Call callee's JIT entry ---
    try x64EmitLoadFromField(asm_ctx, .r10, .r9, OFF_JIT_CODE_ENTRY); // r10 = entry fn ptr

    // Save callee closure before setting up args
    try asm_ctx.emitMovReg(.r11, .rax); // r11 = callee closure*
    // System V ABI: rdi=VM*, rsi=new_base, rdx=constants, rcx=closure
    try x64EmitLoadFromField(asm_ctx, .rdx, .r8, OFF_FUNC_CONSTANTS); // rdx = constants.items.ptr
    try asm_ctx.emitMovReg(.rcx, .r11); // rcx = callee closure*
    try asm_ctx.emitMovReg(.rsi, .rdi); // rsi = new_base (rdi computed above)
    try asm_ctx.emitMovReg(.rdi, X_VM_PTR); // rdi = VM*

    try asm_ctx.emitBlr(.r10);

    // --- Handle result ---
    try asm_ctx.emitCmpImm(.rax, 0);
    const callee_ok = try asm_ctx.emitJccRel32(x64.Cond.eq); // JE → callee completed

    // Callee side-exited: call jitFinishCallee(VM*, 0, dst_abs_idx)
    try asm_ctx.emitAsrImm(.rdx, X_BASE_OFF, 3); // rdx = frame.base
    try asm_ctx.emitLoadImm64(.r11, base_reg);
    try asm_ctx.emitAddReg(.rdx, .rdx, .r11); // rdx = dst_abs_idx
    try asm_ctx.emitLoadImm64(.rsi, 0); // unused arg
    try asm_ctx.emitMovReg(.rdi, X_VM_PTR);
    try asm_ctx.emitLoadImm64(.rax, @intFromPtr(&jitFinishCallee));
    try asm_ctx.emitBlr(.rax);

    // Helper result: 1 = success, 0 = error
    try asm_ctx.emitCmpImm(.rax, 0);
    const ok_patch = try asm_ctx.emitJccRel32(x64.Cond.ne); // JNE → skip error

    // Error → return via return trampoline
    const err_patch = try asm_ctx.emitJmpRel32();
    try pending_returns.append(allocator, err_patch);

    // Patch ok_patch and callee_ok to here
    const final_ok = asm_ctx.pos();
    x64PatchJmp(asm_ctx, callee_ok, final_ok);
    x64PatchJmp(asm_ctx, ok_patch, final_ok);
}

fn x64EmitSelfCallSequence(asm_ctx: *x64.Assembler, base_reg: u16, nargs: u8, pending_exits: *std.ArrayList(PendingSideExit), pending_returns: *std.ArrayList(u32), pending_quick_exits: *std.ArrayList(u32), allocator: std.mem.Allocator, bc_ip: usize, ip_after: usize, cache: *RegCache) !void {
    _ = nargs;
    _ = pending_quick_exits;
    try cache.invalidateAll(asm_ctx);

    // Frame count overflow check
    try x64EmitLoadFromVmField(asm_ctx, .rcx, OFF_FRAME_COUNT);
    try asm_ctx.emitMovReg(.r9, .rcx); // save frame_count in r9
    try asm_ctx.emitLoadImm64(.rdx, MAX_FRAMES);
    try asm_ctx.emitCmpReg(.rcx, .rdx);
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.ae, cache);

    // Save caller's frame IP
    try asm_ctx.emitSubImm(.rcx, .r9, 1);
    try x64EmitMulConst(asm_ctx, .rdx, .rcx, SIZEOF_CALLFRAME);
    try x64EmitAddLargeOffset(asm_ctx, .rsi, X_VM_PTR, OFF_FRAMES);
    try asm_ctx.emitAddReg(.rsi, .rsi, .rdx);
    try asm_ctx.emitLoadImm64(.rdi, ip_after);
    try x64EmitStoreAtOffset(asm_ctx, .rdi, .rsi, OFF_FRAME_IP);

    // Advance to new frame
    try asm_ctx.emitLoadImm64(.rdi, SIZEOF_CALLFRAME);
    try asm_ctx.emitAddReg(.rsi, .rsi, .rdi);

    // new_base
    try asm_ctx.emitAsrImm(.rdi, X_BASE_OFF, 3);
    try asm_ctx.emitLoadImm64(.r11, @as(u64, base_reg) + 1);
    try asm_ctx.emitAddReg(.rdi, .rdi, .r11);

    // Load func once
    try x64EmitLoadFromField(asm_ctx, .r8, X_CLOSURE_PTR, OFF_CLOSURE_FUNC);

    // Store frame fields
    try x64EmitStoreAtOffset(asm_ctx, X_CLOSURE_PTR, .rsi, OFF_FRAME_CLOSURE);
    try asm_ctx.emitLoadImm64(.rcx, 0);
    try x64EmitStoreAtOffset(asm_ctx, .rcx, .rsi, OFF_FRAME_NATIVE);

    try x64EmitLoadFromField(asm_ctx, .rax, .r8, OFF_FUNC_CODE);
    try x64EmitStoreAtOffset(asm_ctx, .rax, .rsi, OFF_FRAME_CODE);
    try x64EmitLoadFromField(asm_ctx, .rax, .r8, OFF_FUNC_CODE + 8);
    try x64EmitStoreAtOffset(asm_ctx, .rax, .rsi, OFF_FRAME_CODE + 8);

    try asm_ctx.emitLoadImm64(.rcx, 0);
    try x64EmitStoreAtOffset(asm_ctx, .rcx, .rsi, OFF_FRAME_IP);
    try x64EmitStoreHalfAtOffset(asm_ctx, .rdi, .rsi, OFF_FRAME_BASE);
    try asm_ctx.emitLoadImm64(.r11, base_reg);
    try x64EmitStoreHalfAtOffset(asm_ctx, .r11, .rsi, OFF_FRAME_DST);
    try x64EmitLoadFromVmField(asm_ctx, .rcx, OFF_WIND_COUNT);
    try x64EmitStoreHalfAtOffset(asm_ctx, .rcx, .rsi, OFF_FRAME_SAVED_WIND);

    // Increment frame_count
    try asm_ctx.emitAddImm(.rcx, .r9, 1);
    try x64EmitStoreAtOffset(asm_ctx, .rcx, X_VM_PTR, OFF_FRAME_COUNT);

    // Call self's JIT entry
    try x64EmitLoadFromField(asm_ctx, .r9, .r8, OFF_FUNC_JIT_CODE);
    try x64EmitLoadFromField(asm_ctx, .r10, .r9, OFF_JIT_CODE_ENTRY);

    // System V: rdi=VM*, rsi=new_base, rdx=constants, rcx=closure
    try x64EmitLoadFromField(asm_ctx, .rdx, .r8, OFF_FUNC_CONSTANTS);
    try asm_ctx.emitMovReg(.rcx, X_CLOSURE_PTR);
    try asm_ctx.emitMovReg(.rsi, .rdi); // new_base
    try asm_ctx.emitMovReg(.rdi, X_VM_PTR);

    try asm_ctx.emitBlr(.r10);

    // Handle result
    try asm_ctx.emitCmpImm(.rax, 0);
    const callee_ok = try asm_ctx.emitJccRel32(x64.Cond.eq);

    // Side-exited: call jitFinishCallee
    try asm_ctx.emitAsrImm(.rdx, X_BASE_OFF, 3);
    try asm_ctx.emitLoadImm64(.r11, base_reg);
    try asm_ctx.emitAddReg(.rdx, .rdx, .r11);
    try asm_ctx.emitLoadImm64(.rsi, 0);
    try asm_ctx.emitMovReg(.rdi, X_VM_PTR);
    try asm_ctx.emitLoadImm64(.rax, @intFromPtr(&jitFinishCallee));
    try asm_ctx.emitBlr(.rax);

    try asm_ctx.emitCmpImm(.rax, 0);
    const ok_patch = try asm_ctx.emitJccRel32(x64.Cond.ne);
    const err_patch = try asm_ctx.emitJmpRel32();
    try pending_returns.append(allocator, err_patch);

    const final_ok = asm_ctx.pos();
    x64PatchJmp(asm_ctx, callee_ok, final_ok);
    x64PatchJmp(asm_ctx, ok_patch, final_ok);
}

fn x64EmitGetUpvalue(asm_ctx: *x64.Assembler, dst: u16, idx: u16, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize, cache: *RegCache) !void {
    try x64EmitLoadFromField(asm_ctx, .rax, X_CLOSURE_PTR, OFF_CLOSURE_UPVALUES);
    const uv_offset: u32 = @as(u32, idx) * 8;
    if (uv_offset <= 32760) {
        try asm_ctx.emitLdrImm(.rax, .rax, @intCast(uv_offset));
    } else {
        try asm_ctx.emitLoadImm64(.rcx, uv_offset);
        try asm_ctx.emitAddReg(.rax, .rax, .rcx);
        try asm_ctx.emitLdrImm(.rax, .rax, 0);
    }
    // If value is a pointer (upper 16 bits == 0xFFFC), side-exit
    try asm_ctx.emitMovReg(.r11, .rax);
    try asm_ctx.emitLsrImm(.r11, .r11, 48);
    try asm_ctx.emitLoadImm64(.r10, 0xFFFC);
    try asm_ctx.emitCmpReg(.r11, .r10);
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.eq, cache);
    try cachedStore(asm_ctx, cache, dst, .rax);
}

fn x64EmitSetUpvalue(asm_ctx: *x64.Assembler, src: u16, idx: u16, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize, cache: *RegCache) !void {
    try x64EmitLoadFromField(asm_ctx, .rax, X_CLOSURE_PTR, OFF_CLOSURE_UPVALUES);
    const uv_offset: u32 = @as(u32, idx) * 8;
    // Load current upvalue value to check type
    if (uv_offset <= 32760) {
        try asm_ctx.emitLdrImm(.rcx, .rax, @intCast(uv_offset));
    } else {
        try asm_ctx.emitLoadImm64(.rcx, uv_offset);
        try asm_ctx.emitAddReg(.rcx, .rax, .rcx);
        try asm_ctx.emitLdrImm(.rcx, .rcx, 0);
    }
    // If current value is a pointer (upper 16 bits == 0xFFFC), side-exit for write barrier
    try asm_ctx.emitMovReg(.r11, .rcx);
    try asm_ctx.emitLsrImm(.r11, .r11, 48);
    try asm_ctx.emitLoadImm64(.r10, 0xFFFC);
    try asm_ctx.emitCmpReg(.r11, .r10);
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.eq, cache);
    // Non-pointer → direct store
    try cachedLoad(asm_ctx, cache, .rcx, src);
    try x64EmitLoadFromField(asm_ctx, .rax, X_CLOSURE_PTR, OFF_CLOSURE_UPVALUES);
    if (uv_offset <= 32760) {
        try asm_ctx.emitStrImm(.rcx, .rax, @intCast(uv_offset));
    } else {
        try asm_ctx.emitLoadImm64(.rdx, uv_offset);
        try asm_ctx.emitAddReg(.rax, .rax, .rdx);
        try asm_ctx.emitStrImm(.rcx, .rax, 0);
    }
}

fn x64EmitFixnumGuard(asm_ctx: *x64.Assembler, reg: x64.Reg, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize, cache: *const RegCache) !void {
    try asm_ctx.emitMovReg(.r11, reg);
    try asm_ctx.emitLsrImm(.r11, .r11, 48);
    try asm_ctx.emitLoadImm64(.r10, 0xFFFD);
    try asm_ctx.emitCmpReg(.r11, .r10);
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.ne, cache);
}

fn x64EmitUntagFixnum(asm_ctx: *x64.Assembler, dst: x64.Reg, src: x64.Reg) !void {
    if (dst != src) try asm_ctx.emitMovReg(dst, src);
    try asm_ctx.emitLslImm(dst, dst, 16);
    try asm_ctx.emitAsrImm(dst, dst, 16);
}

fn x64EmitTagFixnum(asm_ctx: *x64.Assembler, dst: x64.Reg, src: x64.Reg) !void {
    if (dst != src) try asm_ctx.emitMovReg(dst, src);
    try asm_ctx.emitLslImm(dst, dst, 16);
    try asm_ctx.emitLsrImm(dst, dst, 16);
    try asm_ctx.emitLoadImm64(.r11, 0xFFFD000000000000);
    try asm_ctx.emitOrrReg(dst, dst, .r11);
}

fn x64EmitI48OverflowCheck(asm_ctx: *x64.Assembler, reg: x64.Reg, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize, cache: *const RegCache) !void {
    try asm_ctx.emitAsrImm(.r11, reg, 47);
    try asm_ctx.emitAddImm(.r11, .r11, 1);
    try asm_ctx.emitCmpImm(.r11, 2);
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.ae, cache);
}

fn x64EmitExtractPointer(asm_ctx: *x64.Assembler, dst: x64.Reg, src: x64.Reg) !void {
    if (dst != src) try asm_ctx.emitMovReg(dst, src);
    try asm_ctx.emitLslImm(dst, dst, 16);
    try asm_ctx.emitLsrImm(dst, dst, 16);
}

fn x64EmitPointerGuard(asm_ctx: *x64.Assembler, reg: x64.Reg, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize, cache: *const RegCache) !void {
    try asm_ctx.emitMovReg(.r11, reg);
    try asm_ctx.emitLsrImm(.r11, .r11, 48);
    try asm_ctx.emitLoadImm64(.r10, 0xFFFC);
    try asm_ctx.emitCmpReg(.r11, .r10);
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.ne, cache);
}

fn x64EmitSpecializedArith(asm_ctx: *x64.Assembler, base_reg: u16, spec: SpecializedOp, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize, cache: *RegCache) !void {
    try cachedLoad(asm_ctx, cache, .rax, base_reg + 1);
    try cachedLoad(asm_ctx, cache, .rcx, base_reg + 2);

    // Type guard: both must be NaN-boxed fixnums (upper 16 bits == 0xFFFD)
    try x64EmitFixnumGuard(asm_ctx, .rax, pending_exits, allocator, bc_ip, cache);
    try x64EmitFixnumGuard(asm_ctx, .rcx, pending_exits, allocator, bc_ip, cache);

    switch (spec) {
        .add => {
            try x64EmitUntagFixnum(asm_ctx, .rdi, .rax);
            try x64EmitUntagFixnum(asm_ctx, .rsi, .rcx);
            try asm_ctx.emitAddReg(.rdi, .rdi, .rsi);
            try x64EmitI48OverflowCheck(asm_ctx, .rdi, pending_exits, allocator, bc_ip, cache);
            try x64EmitTagFixnum(asm_ctx, .rdi, .rdi);
            try cachedStore(asm_ctx, cache, base_reg, .rdi);
        },
        .sub => {
            try x64EmitUntagFixnum(asm_ctx, .rdi, .rax);
            try x64EmitUntagFixnum(asm_ctx, .rsi, .rcx);
            try asm_ctx.emitSubReg(.rdi, .rdi, .rsi);
            try x64EmitI48OverflowCheck(asm_ctx, .rdi, pending_exits, allocator, bc_ip, cache);
            try x64EmitTagFixnum(asm_ctx, .rdi, .rdi);
            try cachedStore(asm_ctx, cache, base_reg, .rdi);
        },
        .mul => {
            try x64EmitUntagFixnum(asm_ctx, .rax, .rax);
            try x64EmitUntagFixnum(asm_ctx, .rcx, .rcx);
            try asm_ctx.emitImulOneOp(.rcx);
            // i64 overflow: RDX must be sign-extension of RAX
            try asm_ctx.emitAsrImm(.rsi, .rax, 63);
            try asm_ctx.emitCmpReg(.rdx, .rsi);
            try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.ne, cache);
            // i48 range check
            try x64EmitI48OverflowCheck(asm_ctx, .rax, pending_exits, allocator, bc_ip, cache);
            try x64EmitTagFixnum(asm_ctx, .rax, .rax);
            try cachedStore(asm_ctx, cache, base_reg, .rax);
        },
        .lt, .gt, .le, .ge, .eq => {
            // Untag both for correct signed comparison
            try x64EmitUntagFixnum(asm_ctx, .rdi, .rax);
            try x64EmitUntagFixnum(asm_ctx, .rsi, .rcx);
            try asm_ctx.emitCmpReg(.rdi, .rsi);
            try asm_ctx.emitLoadImm64(.rdx, types.FALSE);
            try asm_ctx.emitLoadImm64(.rsi, types.TRUE);
            const cond: x64.Cond = switch (spec) {
                .lt => x64.Cond.lt,
                .gt => x64.Cond.gt,
                .le => x64.Cond.le,
                .ge => x64.Cond.ge,
                .eq => x64.Cond.eq,
                else => unreachable,
            };
            try asm_ctx.emitCsel(.rdi, .rsi, .rdx, cond);
            try cachedStore(asm_ctx, cache, base_reg, .rdi);
        },
        else => unreachable,
    }
}

fn x64EmitSpecializedPredicate(asm_ctx: *x64.Assembler, base_reg: u16, spec: SpecializedOp, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize, cache: *RegCache) !void {
    try cachedLoad(asm_ctx, cache, .rax, base_reg + 1);

    switch (spec) {
        .zero_p => {
            try asm_ctx.emitLoadImm64(.rcx, types.makeFixnum(0));
            try asm_ctx.emitCmpReg(.rax, .rcx);
            try asm_ctx.emitLoadImm64(.rcx, types.FALSE);
            try asm_ctx.emitLoadImm64(.rdx, types.TRUE);
            try asm_ctx.emitCsel(.rsi, .rdx, .rcx, x64.Cond.eq);
            try cachedStore(asm_ctx, cache, base_reg, .rsi);
        },
        .null_p => {
            try asm_ctx.emitLoadImm64(.rcx, types.NIL);
            try asm_ctx.emitCmpReg(.rax, .rcx);
            try asm_ctx.emitLoadImm64(.rdx, types.FALSE);
            try asm_ctx.emitLoadImm64(.rsi, types.TRUE);
            try asm_ctx.emitCsel(.rdi, .rsi, .rdx, x64.Cond.eq);
            try cachedStore(asm_ctx, cache, base_reg, .rdi);
        },
        .pair_p => {
            // Check upper 16 bits == 0xFFFC (NaN-boxed pointer)
            try asm_ctx.emitMovReg(.rcx, .rax);
            try asm_ctx.emitLsrImm(.rcx, .rcx, 48);
            try asm_ctx.emitLoadImm64(.rdx, 0xFFFC);
            try asm_ctx.emitLoadImm64(.rdi, types.FALSE);
            try asm_ctx.emitCmpReg(.rcx, .rdx);
            const not_ptr_patch = try asm_ctx.emitJccRel32(x64.Cond.ne);
            // Extract raw pointer and check object tag
            try x64EmitExtractPointer(asm_ctx, .rcx, .rax);
            try asm_ctx.emitLdrbImm(.rcx, .rcx, @intCast(OFF_OBJECT_TAG));
            try asm_ctx.emitAndImm(.rcx, .rcx, 0x3F);
            try asm_ctx.emitCmpImm(.rcx, @intFromEnum(types.ObjectTag.pair));
            try asm_ctx.emitLoadImm64(.rsi, types.TRUE);
            try asm_ctx.emitCsel(.rdi, .rsi, .rdi, x64.Cond.eq);
            const store_pos = asm_ctx.pos();
            try cachedStore(asm_ctx, cache, base_reg, .rdi);
            x64PatchJmp(asm_ctx, not_ptr_patch, store_pos);
        },
        .not_op => {
            try asm_ctx.emitLoadImm64(.rcx, types.FALSE);
            try asm_ctx.emitCmpReg(.rax, .rcx);
            try asm_ctx.emitLoadImm64(.rdx, types.TRUE);
            try asm_ctx.emitCsel(.rsi, .rdx, .rcx, x64.Cond.eq);
            try cachedStore(asm_ctx, cache, base_reg, .rsi);
        },
        .car => {
            try x64EmitPairGuard(asm_ctx, .rax, pending_exits, allocator, bc_ip, cache);
            try x64EmitLoadFromField(asm_ctx, .rcx, .rax, OFF_PAIR_CAR);
            try cachedStore(asm_ctx, cache, base_reg, .rcx);
        },
        .cdr => {
            try x64EmitPairGuard(asm_ctx, .rax, pending_exits, allocator, bc_ip, cache);
            try x64EmitLoadFromField(asm_ctx, .rcx, .rax, OFF_PAIR_CDR);
            try cachedStore(asm_ctx, cache, base_reg, .rcx);
        },
        else => unreachable,
    }
}

fn x64EmitPairGuard(asm_ctx: *x64.Assembler, val_reg: X64, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize, cache: *const RegCache) !void {
    // Check NaN-boxed pointer (upper 16 bits == 0xFFFC)
    try x64EmitPointerGuard(asm_ctx, val_reg, pending_exits, allocator, bc_ip, cache);
    // Extract raw pointer in-place
    try x64EmitExtractPointer(asm_ctx, val_reg, val_reg);
    // Check object tag == pair
    try asm_ctx.emitLdrbImm(.rcx, val_reg, @intCast(OFF_OBJECT_TAG));
    try asm_ctx.emitAndImm(.rcx, .rcx, 0x3F);
    try asm_ctx.emitCmpImm(.rcx, @intFromEnum(types.ObjectTag.pair));
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.ne, cache);
}

fn x64EmitCons(asm_ctx: *x64.Assembler, dst: u16, car_reg: u16, cdr_reg: u16, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize, cache: *RegCache) !void {
    try cache.invalidateAll(asm_ctx);
    // System V ABI: rdi=VM*, rsi=car, rdx=cdr
    try asm_ctx.emitLdrImm(.rsi, X_FRAME_PTR, car_reg * 8);
    try asm_ctx.emitLdrImm(.rdx, X_FRAME_PTR, cdr_reg * 8);
    try asm_ctx.emitMovReg(.rdi, X_VM_PTR);
    try asm_ctx.emitLoadImm64(.rax, @intFromPtr(&jitAllocPair));
    try asm_ctx.emitBlr(.rax);
    try asm_ctx.emitCmpImm(.rax, 0);
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.eq, cache);
    try x64EmitStoreReg(asm_ctx, dst, .rax);
}

fn x64EmitGetGlobal(asm_ctx: *x64.Assembler, dst: u16, sym_idx: u16, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize, cache: *RegCache) !void {
    // Load func from closure
    try x64EmitLoadFromField(asm_ctx, .rax, X_CLOSURE_PTR, OFF_CLOSURE_FUNC);
    // Load global_cache.ptr (first word of ?[]Value)
    try x64EmitLoadFromField(asm_ctx, .rcx, .rax, OFF_FUNC_GLOBAL_CACHE);
    // Null check
    try asm_ctx.emitCmpImm(.rcx, 0);
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.eq, cache);
    // Check cache_version == global_version
    try x64EmitLoadWFromField(asm_ctx, .rdx, .rax, OFF_FUNC_CACHE_VERSION);
    try x64EmitLoadWFromField(asm_ctx, .rsi, X_VM_PTR, OFF_VM_GLOBAL_VERSION);
    try asm_ctx.emitCmpReg(.rdx, .rsi);
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.ne, cache);
    // Bounds check: cache.len > sym_idx
    try x64EmitLoadFromField(asm_ctx, .rdx, .rax, OFF_FUNC_GLOBAL_CACHE + 8);
    try asm_ctx.emitLoadImm64(.rsi, sym_idx);
    try asm_ctx.emitCmpReg(.rdx, .rsi);
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.ls, cache);
    // Load cached value
    const gc_offset: u32 = @as(u32, sym_idx) * 8;
    if (gc_offset <= 32760) {
        try asm_ctx.emitLdrImm(.rdx, .rcx, @intCast(gc_offset));
    } else {
        try asm_ctx.emitLoadImm64(.rdx, gc_offset);
        try asm_ctx.emitAddReg(.rdx, .rcx, .rdx);
        try asm_ctx.emitLdrImm(.rdx, .rdx, 0);
    }
    // Check != VOID
    try asm_ctx.emitLoadImm64(.rsi, types.VOID);
    try asm_ctx.emitCmpReg(.rdx, .rsi);
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.eq, cache);
    // Store to dst
    try cachedStore(asm_ctx, cache, dst, .rdx);
}

fn x64EmitSetGlobal(asm_ctx: *x64.Assembler, src: u16, sym_idx: u16, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize, cache: *RegCache) !void {
    try cache.invalidateAll(asm_ctx);
    // System V ABI: rdi=VM*, rsi=symbol, rdx=value
    const sym_offset: u32 = @as(u32, sym_idx) * 8;
    if (sym_offset <= 32760) {
        try asm_ctx.emitLdrImm(.rsi, X_CONST_PTR, @intCast(sym_offset));
    } else {
        try asm_ctx.emitLoadImm64(.rsi, sym_offset);
        try asm_ctx.emitAddReg(.rsi, X_CONST_PTR, .rsi);
        try asm_ctx.emitLdrImm(.rsi, .rsi, 0);
    }
    try x64EmitLoadReg(asm_ctx, .rdx, src);
    try asm_ctx.emitMovReg(.rdi, X_VM_PTR);
    try asm_ctx.emitLoadImm64(.rax, @intFromPtr(&jitSetGlobal));
    try asm_ctx.emitBlr(.rax);
    // Check result
    try asm_ctx.emitCmpImm(.rax, 0);
    try x64EmitCondSideExit(asm_ctx, pending_exits, allocator, bc_ip, x64.Cond.eq, cache);
}

fn x64EmitTailReturn(asm_ctx: *x64.Assembler, base_reg: u16, pending_returns: *std.ArrayList(u32), allocator: std.mem.Allocator, cache: *RegCache) !void {
    // Result is at frame[base_reg]; store at FRAME_PTR[-8], decrement frame_count, return
    try cachedLoad(asm_ctx, cache, .rax, base_reg);
    // MOV [rbx-8], rax
    try asm_ctx.emit(0x48);
    try asm_ctx.emit(0x89);
    try asm_ctx.emit(0x43);
    try asm_ctx.emit(0xF8);
    // Decrement frame_count
    try x64EmitLoadFromVmField(asm_ctx, .rcx, OFF_FRAME_COUNT);
    try asm_ctx.emitSubImm(.rcx, .rcx, 1);
    try x64EmitStoreAtOffset(asm_ctx, .rcx, X_VM_PTR, OFF_FRAME_COUNT);
    const ret_patch = try asm_ctx.emitJmpRel32();
    try pending_returns.append(allocator, ret_patch);
}

fn cachedLoad(asm_ctx: *x64.Assembler, cache: *RegCache, rd: X64, slot: u16) !void {
    if (cache.find(slot)) |i| {
        const mreg = CACHE_REGS[i];
        if (rd != mreg) try asm_ctx.emitMovReg(rd, mreg);
        return;
    }
    try asm_ctx.emitLdrImm(rd, X_FRAME_PTR, slot * 8);
}

fn cachedStore(asm_ctx: *x64.Assembler, cache: *RegCache, slot: u16, rs: X64) !void {
    const i = try cache.allocate(asm_ctx, slot);
    const mreg = CACHE_REGS[i];
    if (rs != mreg) try asm_ctx.emitMovReg(mreg, rs);
    cache.entries[i] = .{ .slot = slot, .dirty = true };
}

fn x64EmitCondSideExit(asm_ctx: *x64.Assembler, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize, cond: x64.Cond, cache: *const RegCache) !void {
    const patch_pos = try asm_ctx.emitJccRel32(cond);
    try pending_exits.append(allocator, .{ .native_idx = patch_pos, .bc_ip = bc_ip, .cache_snapshot = cache.snapshot() });
}

fn x64EmitUnconditionalSideExit(asm_ctx: *x64.Assembler, pending_exits: *std.ArrayList(PendingSideExit), allocator: std.mem.Allocator, bc_ip: usize, cache: *const RegCache) !void {
    const patch_pos = try asm_ctx.emitJmpRel32();
    try pending_exits.append(allocator, .{ .native_idx = patch_pos, .bc_ip = bc_ip, .cache_snapshot = cache.snapshot() });
}
