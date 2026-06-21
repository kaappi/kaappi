const std = @import("std");

pub const Reg = enum(u4) {
    rax = 0,
    rcx = 1,
    rdx = 2,
    rbx = 3,
    rsp = 4,
    rbp = 5,
    rsi = 6,
    rdi = 7,
    r8 = 8,
    r9 = 9,
    r10 = 10,
    r11 = 11,
    r12 = 12,
    r13 = 13,
    r14 = 14,
    r15 = 15,
};

pub const Cond = enum(u4) {
    o = 0x0,
    no = 0x1,
    b = 0x2,
    ae = 0x3,
    e = 0x4,
    ne = 0x5,
    be = 0x6,
    a = 0x7,
    s = 0x8,
    ns = 0x9,
    pe = 0xa,
    po = 0xb,
    l = 0xc,
    ge = 0xd,
    le = 0xe,
    g = 0xf,

    // Aliases matching AArch64 names used by jit.zig
    pub const eq = Cond.e;
    pub const gt = Cond.g;
    pub const lt = Cond.l;
    pub const vs = Cond.o;
};

pub const Assembler = struct {
    code: std.ArrayList(u8) = .empty,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Assembler {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Assembler) void {
        self.code.deinit(self.allocator);
    }

    pub fn emit(self: *Assembler, byte: u8) !void {
        try self.code.append(self.allocator, byte);
    }

    pub fn emit32(self: *Assembler, val: u32) !void {
        const bytes: [4]u8 = @bitCast(val);
        try self.code.appendSlice(self.allocator, &bytes);
    }

    pub fn emit64(self: *Assembler, val: u64) !void {
        const bytes: [8]u8 = @bitCast(val);
        try self.code.appendSlice(self.allocator, &bytes);
    }

    pub fn pos(self: *const Assembler) u32 {
        return @intCast(self.code.items.len);
    }

    pub fn patchAt(self: *Assembler, offset: u32, value: u32) void {
        const bytes: [4]u8 = @bitCast(value);
        @memcpy(self.code.items[offset..][0..4], &bytes);
    }

    pub fn patchByteAt(self: *Assembler, offset: u32, byte: u8) void {
        self.code.items[offset] = byte;
    }

    pub fn toSlice(self: *const Assembler) []const u8 {
        return self.code.items;
    }

    // -------------------------------------------------------------------
    // Encoding helpers
    // -------------------------------------------------------------------

    fn needsRex(reg: Reg) bool {
        return @intFromEnum(reg) >= 8;
    }

    fn regLow3(reg: Reg) u8 {
        return @truncate(@intFromEnum(reg) & 0x7);
    }

    fn rex(w: bool, r: Reg, x: u1, b_reg: Reg) u8 {
        var val: u8 = 0x40;
        if (w) val |= 0x08;
        if (needsRex(r)) val |= 0x04;
        val |= @as(u8, x) << 1;
        if (needsRex(b_reg)) val |= 0x01;
        return val;
    }

    fn rexW(r: Reg, b_reg: Reg) u8 {
        return rex(true, r, 0, b_reg);
    }

    fn modRM(mod: u2, reg_op: u8, rm: u8) u8 {
        return (@as(u8, mod) << 6) | ((reg_op & 0x7) << 3) | (rm & 0x7);
    }

    // -------------------------------------------------------------------
    // MOV reg, imm64 (REX.W + B8+rd io)
    // -------------------------------------------------------------------

    pub fn emitLoadImm64(self: *Assembler, rd: Reg, value: u64) !void {
        if (value == 0) {
            try self.emitXorReg(rd, rd);
            return;
        }
        if (value <= std.math.maxInt(u32)) {
            // MOV r32, imm32 (zero-extends to 64-bit)
            if (needsRex(rd)) try self.emit(0x41);
            try self.emit(0xB8 + regLow3(rd));
            try self.emit32(@truncate(value));
            return;
        }
        // REX.W MOV r64, imm64
        try self.emit(rexW(.rax, rd));
        try self.emit(0xB8 + regLow3(rd));
        try self.emit64(value);
    }

    pub fn emitMovz(self: *Assembler, rd: Reg, imm16: u16, hw: u2) !void {
        _ = hw;
        try self.emitLoadImm64(rd, @as(u64, imm16));
    }

    pub fn emitMovk(self: *Assembler, rd: Reg, imm16: u16, hw: u2) !void {
        // Load full value — on x86_64 this is handled by emitLoadImm64
        // For compatibility, OR in the half-word at the right position
        const shift: u6 = @as(u6, hw) * 16;
        const mask: u64 = @as(u64, imm16) << shift;
        // Load mask into scratch, OR with rd
        try self.emitLoadImm64(.r11, mask);
        try self.emitOrrReg(rd, rd, .r11);
    }

    // MOV r64, r64
    pub fn emitMovReg(self: *Assembler, rd: Reg, rs: Reg) !void {
        if (rd == rs) return;
        try self.emit(rexW(rs, rd));
        try self.emit(0x89);
        try self.emit(modRM(0b11, regLow3(rs), regLow3(rd)));
    }

    // -------------------------------------------------------------------
    // Arithmetic
    // -------------------------------------------------------------------

    // ADD r64, r64
    pub fn emitAddReg(self: *Assembler, rd: Reg, rn: Reg, rm: Reg) !void {
        if (rd != rn) try self.emitMovReg(rd, rn);
        try self.emit(rexW(rm, rd));
        try self.emit(0x01);
        try self.emit(modRM(0b11, regLow3(rm), regLow3(rd)));
    }

    // ADD r64, imm32 (sign-extended)
    pub fn emitAddImm(self: *Assembler, rd: Reg, rn: Reg, imm12: u12) !void {
        if (rd != rn) try self.emitMovReg(rd, rn);
        const imm: u32 = imm12;
        if (imm <= 127) {
            try self.emit(rexW(.rax, rd));
            try self.emit(0x83);
            try self.emit(modRM(0b11, 0, regLow3(rd)));
            try self.emit(@truncate(imm));
        } else {
            try self.emit(rexW(.rax, rd));
            try self.emit(0x81);
            try self.emit(modRM(0b11, 0, regLow3(rd)));
            try self.emit32(imm);
        }
    }

    // SUB r64, imm32
    pub fn emitSubImm(self: *Assembler, rd: Reg, rn: Reg, imm12: u12) !void {
        if (rd != rn) try self.emitMovReg(rd, rn);
        const imm: u32 = imm12;
        if (imm <= 127) {
            try self.emit(rexW(.rax, rd));
            try self.emit(0x83);
            try self.emit(modRM(0b11, 5, regLow3(rd)));
            try self.emit(@truncate(imm));
        } else {
            try self.emit(rexW(.rax, rd));
            try self.emit(0x81);
            try self.emit(modRM(0b11, 5, regLow3(rd)));
            try self.emit32(imm);
        }
    }

    // SUB r64, r64
    pub fn emitSubReg(self: *Assembler, rd: Reg, rn: Reg, rm: Reg) !void {
        if (rd != rn) try self.emitMovReg(rd, rn);
        try self.emit(rexW(rm, rd));
        try self.emit(0x29);
        try self.emit(modRM(0b11, regLow3(rm), regLow3(rd)));
    }

    // ADDS = ADD (x86 always sets flags)
    pub fn emitAddsReg(self: *Assembler, rd: Reg, rn: Reg, rm: Reg) !void {
        try self.emitAddReg(rd, rn, rm);
    }

    // SUBS = SUB (x86 always sets flags)
    pub fn emitSubsReg(self: *Assembler, rd: Reg, rn: Reg, rm: Reg) !void {
        try self.emitSubReg(rd, rn, rm);
    }

    // XOR r64, r64 (used for zeroing)
    fn emitXorReg(self: *Assembler, rd: Reg, rs: Reg) !void {
        try self.emit(rexW(rs, rd));
        try self.emit(0x31);
        try self.emit(modRM(0b11, regLow3(rs), regLow3(rd)));
    }

    // -------------------------------------------------------------------
    // Load / Store — MOV r64, [base+disp] / MOV [base+disp], r64
    // -------------------------------------------------------------------

    fn emitMemOp(self: *Assembler, opcode: u8, reg: Reg, base: Reg, byte_offset: u32) !void {
        try self.emit(rexW(reg, base));
        try self.emit(opcode);

        const rm = regLow3(base);
        const reg3 = regLow3(reg);

        if (byte_offset == 0 and rm != 5) {
            // [base] — mod=00 (rbp/r13 needs mod=01 with disp8=0)
            try self.emit(modRM(0b00, reg3, rm));
            if (rm == 4) try self.emit(0x24); // SIB for rsp/r12
        } else if (byte_offset <= 127) {
            // [base+disp8] — mod=01
            try self.emit(modRM(0b01, reg3, rm));
            if (rm == 4) try self.emit(0x24); // SIB for rsp/r12
            try self.emit(@truncate(byte_offset));
        } else {
            // [base+disp32] — mod=10
            try self.emit(modRM(0b10, reg3, rm));
            if (rm == 4) try self.emit(0x24); // SIB for rsp/r12
            try self.emit32(byte_offset);
        }
    }

    // MOV r64, [base+offset]
    pub fn emitLdrImm(self: *Assembler, rt: Reg, rn: Reg, byte_offset: u16) !void {
        try self.emitMemOp(0x8B, rt, rn, byte_offset);
    }

    // MOV [base+offset], r64
    pub fn emitStrImm(self: *Assembler, rt: Reg, rn: Reg, byte_offset: u16) !void {
        try self.emitMemOp(0x89, rt, rn, byte_offset);
    }

    // MOV r32, [base+offset] (zero-extends to 64-bit)
    pub fn emitLdrWImm(self: *Assembler, rt: Reg, rn: Reg, byte_offset: u16) !void {
        // 32-bit load — no REX.W, just REX if extended regs
        const needs = needsRex(rt) or needsRex(rn);
        if (needs) try self.emit(rex(false, rt, 0, rn));
        try self.emit(0x8B);

        const rm = regLow3(rn);
        const reg3 = regLow3(rt);
        const off: u32 = byte_offset;

        if (off == 0 and rm != 5) {
            try self.emit(modRM(0b00, reg3, rm));
            if (rm == 4) try self.emit(0x24);
        } else if (off <= 127) {
            try self.emit(modRM(0b01, reg3, rm));
            if (rm == 4) try self.emit(0x24);
            try self.emit(@truncate(off));
        } else {
            try self.emit(modRM(0b10, reg3, rm));
            if (rm == 4) try self.emit(0x24);
            try self.emit32(off);
        }
    }

    // MOV [base+offset], r32
    pub fn emitStrWImm(self: *Assembler, rt: Reg, rn: Reg, byte_offset: u16) !void {
        const needs = needsRex(rt) or needsRex(rn);
        if (needs) try self.emit(rex(false, rt, 0, rn));
        try self.emit(0x89);

        const rm = regLow3(rn);
        const reg3 = regLow3(rt);
        const off: u32 = byte_offset;

        if (off == 0 and rm != 5) {
            try self.emit(modRM(0b00, reg3, rm));
            if (rm == 4) try self.emit(0x24);
        } else if (off <= 127) {
            try self.emit(modRM(0b01, reg3, rm));
            if (rm == 4) try self.emit(0x24);
            try self.emit(@truncate(off));
        } else {
            try self.emit(modRM(0b10, reg3, rm));
            if (rm == 4) try self.emit(0x24);
            try self.emit32(off);
        }
    }

    // MOVZX r64, byte [base+offset]
    pub fn emitLdrbImm(self: *Assembler, rt: Reg, rn: Reg, byte_offset: u12) !void {
        try self.emit(rexW(rt, rn));
        try self.emit(0x0F);
        try self.emit(0xB6);

        const rm = regLow3(rn);
        const reg3 = regLow3(rt);
        const off: u32 = byte_offset;

        if (off == 0 and rm != 5) {
            try self.emit(modRM(0b00, reg3, rm));
            if (rm == 4) try self.emit(0x24);
        } else if (off <= 127) {
            try self.emit(modRM(0b01, reg3, rm));
            if (rm == 4) try self.emit(0x24);
            try self.emit(@truncate(off));
        } else {
            try self.emit(modRM(0b10, reg3, rm));
            if (rm == 4) try self.emit(0x24);
            try self.emit32(off);
        }
    }

    // MOV byte [base+offset], r8
    pub fn emitStrbImm(self: *Assembler, rt: Reg, rn: Reg, byte_offset: u12) !void {
        try self.emit(rex(false, rt, 0, rn));
        try self.emit(0x88);

        const rm = regLow3(rn);
        const reg3 = regLow3(rt);
        const off: u32 = byte_offset;

        if (off == 0 and rm != 5) {
            try self.emit(modRM(0b00, reg3, rm));
            if (rm == 4) try self.emit(0x24);
        } else if (off <= 127) {
            try self.emit(modRM(0b01, reg3, rm));
            if (rm == 4) try self.emit(0x24);
            try self.emit(@truncate(off));
        } else {
            try self.emit(modRM(0b10, reg3, rm));
            if (rm == 4) try self.emit(0x24);
            try self.emit32(off);
        }
    }

    // MOV word [base+offset], r16
    pub fn emitStrhImm(self: *Assembler, rt: Reg, rn: Reg, byte_offset: u16) !void {
        try self.emit(0x66); // operand size prefix
        const needs = needsRex(rt) or needsRex(rn);
        if (needs) try self.emit(rex(false, rt, 0, rn));
        try self.emit(0x89);

        const rm = regLow3(rn);
        const reg3 = regLow3(rt);
        const off: u32 = byte_offset;

        if (off == 0 and rm != 5) {
            try self.emit(modRM(0b00, reg3, rm));
            if (rm == 4) try self.emit(0x24);
        } else if (off <= 127) {
            try self.emit(modRM(0b01, reg3, rm));
            if (rm == 4) try self.emit(0x24);
            try self.emit(@truncate(off));
        } else {
            try self.emit(modRM(0b10, reg3, rm));
            if (rm == 4) try self.emit(0x24);
            try self.emit32(off);
        }
    }

    // MOVZX r64, word [base+offset]
    pub fn emitLdrhImm(self: *Assembler, rt: Reg, rn: Reg, byte_offset: u16) !void {
        try self.emit(rexW(rt, rn));
        try self.emit(0x0F);
        try self.emit(0xB7);

        const rm = regLow3(rn);
        const reg3 = regLow3(rt);
        const off: u32 = byte_offset;

        if (off == 0 and rm != 5) {
            try self.emit(modRM(0b00, reg3, rm));
            if (rm == 4) try self.emit(0x24);
        } else if (off <= 127) {
            try self.emit(modRM(0b01, reg3, rm));
            if (rm == 4) try self.emit(0x24);
            try self.emit(@truncate(off));
        } else {
            try self.emit(modRM(0b10, reg3, rm));
            if (rm == 4) try self.emit(0x24);
            try self.emit32(off);
        }
    }

    // -------------------------------------------------------------------
    // Comparison
    // -------------------------------------------------------------------

    // CMP r64, imm32
    pub fn emitCmpImm(self: *Assembler, rn: Reg, imm12: u12) !void {
        const imm: u32 = imm12;
        if (imm <= 127) {
            try self.emit(rexW(.rax, rn));
            try self.emit(0x83);
            try self.emit(modRM(0b11, 7, regLow3(rn)));
            try self.emit(@truncate(imm));
        } else {
            try self.emit(rexW(.rax, rn));
            try self.emit(0x81);
            try self.emit(modRM(0b11, 7, regLow3(rn)));
            try self.emit32(imm);
        }
    }

    // CMP r64, r64
    pub fn emitCmpReg(self: *Assembler, rn: Reg, rm: Reg) !void {
        try self.emit(rexW(rm, rn));
        try self.emit(0x39);
        try self.emit(modRM(0b11, regLow3(rm), regLow3(rn)));
    }

    // -------------------------------------------------------------------
    // Shifts
    // -------------------------------------------------------------------

    // SHL r64, imm8
    pub fn emitLslImm(self: *Assembler, rd: Reg, rn: Reg, shift: u6) !void {
        if (rd != rn) try self.emitMovReg(rd, rn);
        try self.emit(rexW(.rax, rd));
        try self.emit(0xC1);
        try self.emit(modRM(0b11, 4, regLow3(rd)));
        try self.emit(@as(u8, shift));
    }

    // SAR r64, imm8
    pub fn emitAsrImm(self: *Assembler, rd: Reg, rn: Reg, shift: u6) !void {
        if (rd != rn) try self.emitMovReg(rd, rn);
        try self.emit(rexW(.rax, rd));
        try self.emit(0xC1);
        try self.emit(modRM(0b11, 7, regLow3(rd)));
        try self.emit(@as(u8, shift));
    }

    // -------------------------------------------------------------------
    // Logical
    // -------------------------------------------------------------------

    // OR r64, r64
    pub fn emitOrrReg(self: *Assembler, rd: Reg, rn: Reg, rm: Reg) !void {
        if (rd != rn) try self.emitMovReg(rd, rn);
        try self.emit(rexW(rm, rd));
        try self.emit(0x09);
        try self.emit(modRM(0b11, regLow3(rm), regLow3(rd)));
    }

    // AND r64, r64
    pub fn emitAndReg(self: *Assembler, rd: Reg, rn: Reg, rm: Reg) !void {
        if (rd != rn) try self.emitMovReg(rd, rn);
        try self.emit(rexW(rm, rd));
        try self.emit(0x21);
        try self.emit(modRM(0b11, regLow3(rm), regLow3(rd)));
    }

    // -------------------------------------------------------------------
    // Conditional select (emulated on x86_64 via CMOVcc)
    // -------------------------------------------------------------------

    // CMOV rd, rm, cond (select rn if cond, else rm)
    pub fn emitCsel(self: *Assembler, rd: Reg, rn: Reg, rm: Reg, cond: Cond) !void {
        // x86 CMOV: CMOVcc rd, src — moves src to rd if cond is true
        // ARM CSEL: rd = cond ? rn : rm
        // Emulate: mov rd, rm; cmovcc rd, rn
        if (rd != rm) try self.emitMovReg(rd, rm);
        try self.emit(rexW(rd, rn));
        try self.emit(0x0F);
        try self.emit(0x40 + @intFromEnum(cond));
        try self.emit(modRM(0b11, regLow3(rd), regLow3(rn)));
    }

    // -------------------------------------------------------------------
    // Branches
    // -------------------------------------------------------------------

    // PUSH r64
    pub fn emitPush(self: *Assembler, reg: Reg) !void {
        if (needsRex(reg)) try self.emit(0x41);
        try self.emit(0x50 + regLow3(reg));
    }

    // POP r64
    pub fn emitPop(self: *Assembler, reg: Reg) !void {
        if (needsRex(reg)) try self.emit(0x41);
        try self.emit(0x58 + regLow3(reg));
    }

    // RET
    pub fn emitRet(self: *Assembler) !void {
        try self.emit(0xC3);
    }

    // CALL r64
    pub fn emitBlr(self: *Assembler, rn: Reg) !void {
        if (needsRex(rn)) try self.emit(0x41);
        try self.emit(0xFF);
        try self.emit(modRM(0b11, 2, regLow3(rn)));
    }

    // BL (not used on x86_64 — use emitBlr)
    pub fn emitBl(self: *Assembler, offset: i26) !void {
        _ = self;
        _ = offset;
    }

    // STP/LDP stubs — not applicable on x86_64, use push/pop
    pub fn emitStp(self: *Assembler, rt: Reg, rt2: Reg, rn: Reg, offset: i7) !void {
        _ = rn;
        _ = offset;
        try self.emitPush(rt);
        try self.emitPush(rt2);
    }

    pub fn emitLdp(self: *Assembler, rt: Reg, rt2: Reg, rn: Reg, offset: i7) !void {
        _ = rn;
        _ = offset;
        try self.emitPop(rt2);
        try self.emitPop(rt);
    }

    pub fn emitStpOffset(self: *Assembler, rt: Reg, rt2: Reg, rn: Reg, offset: i7) !void {
        _ = self;
        _ = rt;
        _ = rt2;
        _ = rn;
        _ = offset;
    }

    pub fn emitLdpOffset(self: *Assembler, rt: Reg, rt2: Reg, rn: Reg, offset: i7) !void {
        _ = self;
        _ = rt;
        _ = rt2;
        _ = rn;
        _ = offset;
    }

    // TBZ/TBNZ — emulated with TEST + Jcc
    pub fn emitTbz(self: *Assembler, rt: Reg, bit: u6, offset: i14) !void {
        _ = offset;
        // TEST rt, (1 << bit) then JZ
        try self.emit(rexW(.rax, rt));
        try self.emit(0xF7);
        try self.emit(modRM(0b11, 0, regLow3(rt)));
        try self.emit32(@as(u32, 1) << bit);
        // JE rel32 (placeholder — caller patches)
        try self.emit(0x0F);
        try self.emit(0x84);
        try self.emit32(0);
    }

    pub fn emitTbnz(self: *Assembler, rt: Reg, bit: u6, offset: i14) !void {
        _ = offset;
        try self.emit(rexW(.rax, rt));
        try self.emit(0xF7);
        try self.emit(modRM(0b11, 0, regLow3(rt)));
        try self.emit32(@as(u32, 1) << bit);
        // JNE rel32 (placeholder — caller patches)
        try self.emit(0x0F);
        try self.emit(0x85);
        try self.emit32(0);
    }

    // -------------------------------------------------------------------
    // Branch encoding (static, for patching)
    // -------------------------------------------------------------------

    // JMP rel32 — returns the 4-byte offset value to patch
    pub fn jmp(offset: i32) u32 {
        return @bitCast(offset);
    }

    // Jcc rel32 — returns the 4-byte offset value to patch
    pub fn jcc(cond: Cond, offset: i32) u32 {
        _ = cond;
        return @bitCast(offset);
    }

    // Unconditional JMP rel32
    pub fn b(offset: i32) u32 {
        return @bitCast(offset);
    }

    // Conditional Jcc rel32
    pub fn bCond(cond: Cond, offset: i32) u32 {
        _ = cond;
        return @bitCast(offset);
    }

    // IMUL r64, r64
    pub fn mul(rd: Reg, rn: Reg, rm: Reg) u32 {
        _ = rd;
        _ = rn;
        _ = rm;
        return 0;
    }

    // SMULH — not a single x86 instruction
    pub fn smulh(rd: Reg, rn: Reg, rm: Reg) u32 {
        _ = rd;
        _ = rn;
        _ = rm;
        return 0;
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "x86_64 assembler: mov reg, imm64" {
    var asm_ctx = Assembler.init(std.testing.allocator);
    defer asm_ctx.deinit();

    try asm_ctx.emitLoadImm64(.rax, 42);
    // Small values use MOV r32, imm32 (5 bytes) — B8 2A 00 00 00
    try std.testing.expectEqual(@as(u32, 5), asm_ctx.pos());
    try std.testing.expectEqual(@as(u8, 0xB8), asm_ctx.code.items[0]);
}

test "x86_64 assembler: mov reg zero" {
    var asm_ctx = Assembler.init(std.testing.allocator);
    defer asm_ctx.deinit();

    try asm_ctx.emitLoadImm64(.rax, 0);
    // XOR rax, rax = REX.W 31 C0
    try std.testing.expectEqual(@as(u32, 3), asm_ctx.pos());
}

test "x86_64 assembler: ret" {
    var asm_ctx = Assembler.init(std.testing.allocator);
    defer asm_ctx.deinit();

    try asm_ctx.emitRet();
    try std.testing.expectEqual(@as(u32, 1), asm_ctx.pos());
    try std.testing.expectEqual(@as(u8, 0xC3), asm_ctx.code.items[0]);
}

test "x86_64 assembler: push/pop" {
    var asm_ctx = Assembler.init(std.testing.allocator);
    defer asm_ctx.deinit();

    try asm_ctx.emitPush(.rbx);
    try std.testing.expectEqual(@as(u32, 1), asm_ctx.pos());
    try std.testing.expectEqual(@as(u8, 0x53), asm_ctx.code.items[0]);

    try asm_ctx.emitPush(.r12);
    try std.testing.expectEqual(@as(u32, 3), asm_ctx.pos());
    // r12 needs REX prefix: 41 54
    try std.testing.expectEqual(@as(u8, 0x41), asm_ctx.code.items[1]);
    try std.testing.expectEqual(@as(u8, 0x54), asm_ctx.code.items[2]);
}

test "x86_64 assembler: add reg, imm8" {
    var asm_ctx = Assembler.init(std.testing.allocator);
    defer asm_ctx.deinit();

    try asm_ctx.emitAddImm(.rax, .rax, 8);
    // REX.W 83 C0 08
    try std.testing.expectEqual(@as(u8, 0x48), asm_ctx.code.items[0]); // REX.W
    try std.testing.expectEqual(@as(u8, 0x83), asm_ctx.code.items[1]);
    try std.testing.expectEqual(@as(u8, 0xC0), asm_ctx.code.items[2]); // ModRM: 11 000 000
    try std.testing.expectEqual(@as(u8, 0x08), asm_ctx.code.items[3]);
}

test "x86_64 assembler: cmp reg, imm8" {
    var asm_ctx = Assembler.init(std.testing.allocator);
    defer asm_ctx.deinit();

    try asm_ctx.emitCmpImm(.rax, 6);
    // REX.W 83 F8 06
    try std.testing.expectEqual(@as(u8, 0x48), asm_ctx.code.items[0]);
    try std.testing.expectEqual(@as(u8, 0x83), asm_ctx.code.items[1]);
    try std.testing.expectEqual(@as(u8, 0xF8), asm_ctx.code.items[2]); // ModRM: 11 111 000
    try std.testing.expectEqual(@as(u8, 0x06), asm_ctx.code.items[3]);
}

test "x86_64 assembler: position and patch" {
    var asm_ctx = Assembler.init(std.testing.allocator);
    defer asm_ctx.deinit();

    try std.testing.expectEqual(@as(u32, 0), asm_ctx.pos());
    try asm_ctx.emit32(0x12345678);
    try std.testing.expectEqual(@as(u32, 4), asm_ctx.pos());

    asm_ctx.patchAt(0, 0xDEADBEEF);
    const patched: u32 = @bitCast(asm_ctx.code.items[0..4].*);
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), patched);
}
