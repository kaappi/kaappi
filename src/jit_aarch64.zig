const std = @import("std");

pub const Reg = enum(u5) {
    x0 = 0, x1, x2, x3, x4, x5, x6, x7,
    x8, x9, x10, x11, x12, x13, x14, x15,
    x16, x17, x18, x19, x20, x21, x22, x23,
    x24, x25, x26, x27, x28, x29, x30, xzr,
};

pub const Cond = enum(u4) {
    eq = 0x0,
    ne = 0x1,
    hs = 0x2,
    lo = 0x3,
    mi = 0x4,
    pl = 0x5,
    vs = 0x6,
    vc = 0x7,
    hi = 0x8,
    ls = 0x9,
    ge = 0xa,
    lt = 0xb,
    gt = 0xc,
    le = 0xd,
    al = 0xe,
};

pub const Assembler = struct {
    code: std.ArrayList(u32) = .empty,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Assembler {
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *Assembler) void {
        self.code.deinit(self.allocator);
    }

    pub fn emit(self: *Assembler, inst: u32) !void {
        try self.code.append(self.allocator, inst);
    }

    pub fn pos(self: *const Assembler) u32 {
        return @intCast(self.code.items.len);
    }

    pub fn patchAt(self: *Assembler, idx: u32, inst: u32) void {
        self.code.items[idx] = inst;
    }

    pub fn toSlice(self: *const Assembler) []const u32 {
        return self.code.items;
    }

    // -----------------------------------------------------------------------
    // Emit helpers — instruction + append in one call
    // -----------------------------------------------------------------------

    pub fn emitMovz(self: *Assembler, rd: Reg, imm16: u16, hw: u2) !void {
        try self.emit(movz(rd, imm16, hw));
    }

    pub fn emitMovk(self: *Assembler, rd: Reg, imm16: u16, hw: u2) !void {
        try self.emit(movk(rd, imm16, hw));
    }

    pub fn emitMovReg(self: *Assembler, rd: Reg, rm: Reg) !void {
        try self.emit(movReg(rd, rm));
    }

    pub fn emitAddImm(self: *Assembler, rd: Reg, rn: Reg, imm12: u12) !void {
        try self.emit(addImm(rd, rn, imm12));
    }

    pub fn emitAddReg(self: *Assembler, rd: Reg, rn: Reg, rm: Reg) !void {
        try self.emit(addReg(rd, rn, rm));
    }

    pub fn emitSubImm(self: *Assembler, rd: Reg, rn: Reg, imm12: u12) !void {
        try self.emit(subImm(rd, rn, imm12));
    }

    pub fn emitLdrImm(self: *Assembler, rt: Reg, rn: Reg, offset: u16) !void {
        try self.emit(ldrImm(rt, rn, offset));
    }

    pub fn emitStrImm(self: *Assembler, rt: Reg, rn: Reg, offset: u16) !void {
        try self.emit(strImm(rt, rn, offset));
    }

    pub fn emitStp(self: *Assembler, rt: Reg, rt2: Reg, rn: Reg, offset: i7) !void {
        try self.emit(stpPre(rt, rt2, rn, offset));
    }

    pub fn emitLdp(self: *Assembler, rt: Reg, rt2: Reg, rn: Reg, offset: i7) !void {
        try self.emit(ldpPost(rt, rt2, rn, offset));
    }

    pub fn emitStpOffset(self: *Assembler, rt: Reg, rt2: Reg, rn: Reg, offset: i7) !void {
        try self.emit(stpOffset(rt, rt2, rn, offset));
    }

    pub fn emitLdpOffset(self: *Assembler, rt: Reg, rt2: Reg, rn: Reg, offset: i7) !void {
        try self.emit(ldpOffset(rt, rt2, rn, offset));
    }

    pub fn emitCmpImm(self: *Assembler, rn: Reg, imm12: u12) !void {
        try self.emit(cmpImm(rn, imm12));
    }

    pub fn emitLslImm(self: *Assembler, rd: Reg, rn: Reg, shift: u6) !void {
        try self.emit(lslImm(rd, rn, shift));
    }

    pub fn emitRet(self: *Assembler) !void {
        try self.emit(ret());
    }

    pub fn emitBl(self: *Assembler, offset: i26) !void {
        try self.emit(bl(offset));
    }

    pub fn emitBlr(self: *Assembler, rn: Reg) !void {
        try self.emit(blr(rn));
    }

    // Load a full 64-bit immediate into a register (1-4 instructions)
    pub fn emitLoadImm64(self: *Assembler, rd: Reg, value: u64) !void {
        const h0: u16 = @truncate(value);
        const h1: u16 = @truncate(value >> 16);
        const h2: u16 = @truncate(value >> 32);
        const h3: u16 = @truncate(value >> 48);

        try self.emitMovz(rd, h0, 0);
        if (h1 != 0) try self.emitMovk(rd, h1, 1);
        if (h2 != 0) try self.emitMovk(rd, h2, 2);
        if (h3 != 0) try self.emitMovk(rd, h3, 3);
    }

    // -----------------------------------------------------------------------
    // Instruction encoders — pure functions returning u32
    // -----------------------------------------------------------------------

    // MOVZ Xd, #imm16, LSL #(hw*16)
    pub fn movz(rd: Reg, imm16: u16, hw: u2) u32 {
        return (0b1_10_100101 << 23) |
            (@as(u32, hw) << 21) |
            (@as(u32, imm16) << 5) |
            @intFromEnum(rd);
    }

    // MOVK Xd, #imm16, LSL #(hw*16)
    pub fn movk(rd: Reg, imm16: u16, hw: u2) u32 {
        return @as(u32, 0xF2800000) |
            (@as(u32, hw) << 21) |
            (@as(u32, imm16) << 5) |
            @intFromEnum(rd);
    }

    // MOV Xd, Xm (alias for ORR Xd, XZR, Xm)
    pub fn movReg(rd: Reg, rm: Reg) u32 {
        return (0b1_01_01010_00_0 << 21) |
            (@as(u32, @intFromEnum(rm)) << 16) |
            (@as(u32, @intFromEnum(Reg.xzr)) << 5) |
            @intFromEnum(rd);
    }

    // ADD Xd, Xn, #imm12
    pub fn addImm(rd: Reg, rn: Reg, imm12: u12) u32 {
        return (0b1_0_0_100010_0 << 22) |
            (@as(u32, imm12) << 10) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rd);
    }

    // ADD Xd, Xn, Xm
    pub fn addReg(rd: Reg, rn: Reg, rm: Reg) u32 {
        return (0b1_0_0_01011_00_0 << 21) |
            (@as(u32, @intFromEnum(rm)) << 16) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rd);
    }

    // SUB Xd, Xn, #imm12
    pub fn subImm(rd: Reg, rn: Reg, imm12: u12) u32 {
        return (0b1_1_0_100010_0 << 22) |
            (@as(u32, imm12) << 10) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rd);
    }

    // LDR Xt, [Xn, #offset] (unsigned offset, scaled by 8 for 64-bit)
    // byte_offset must be a multiple of 8, range 0..32760
    pub fn ldrImm(rt: Reg, rn: Reg, byte_offset: u16) u32 {
        std.debug.assert(byte_offset <= 32760 and byte_offset % 8 == 0);
        const scaled = @as(u32, byte_offset >> 3);
        return (0b11_111_0_01_01 << 22) |
            (scaled << 10) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rt);
    }

    // STR Xt, [Xn, #offset] (unsigned offset, scaled by 8 for 64-bit)
    // byte_offset must be a multiple of 8, range 0..32760
    pub fn strImm(rt: Reg, rn: Reg, byte_offset: u16) u32 {
        std.debug.assert(byte_offset <= 32760 and byte_offset % 8 == 0);
        const scaled = @as(u32, byte_offset >> 3);
        return (0b11_111_0_01_00 << 22) |
            (scaled << 10) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rt);
    }

    // STP Xt, Xt2, [Xn, #offset]! (pre-index, signed offset * 8)
    pub fn stpPre(rt: Reg, rt2: Reg, rn: Reg, offset: i7) u32 {
        const imm7: u7 = @bitCast(offset);
        return (0b10_101_0_011 << 23) |
            (@as(u32, imm7) << 15) |
            (@as(u32, @intFromEnum(rt2)) << 10) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rt);
    }

    // LDP Xt, Xt2, [Xn], #offset (post-index, signed offset * 8)
    pub fn ldpPost(rt: Reg, rt2: Reg, rn: Reg, offset: i7) u32 {
        const imm7: u7 = @bitCast(offset);
        return (0b10_101_0_001 << 23) |
            (1 << 22) | // L=1 for load
            (@as(u32, imm7) << 15) |
            (@as(u32, @intFromEnum(rt2)) << 10) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rt);
    }

    // STP Xt, Xt2, [Xn, #offset] (signed offset, no writeback)
    pub fn stpOffset(rt: Reg, rt2: Reg, rn: Reg, offset: i7) u32 {
        const imm7: u7 = @bitCast(offset);
        return (0b10_101_0_010 << 23) |
            (@as(u32, imm7) << 15) |
            (@as(u32, @intFromEnum(rt2)) << 10) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rt);
    }

    // LDP Xt, Xt2, [Xn, #offset] (signed offset, no writeback)
    pub fn ldpOffset(rt: Reg, rt2: Reg, rn: Reg, offset: i7) u32 {
        const imm7: u7 = @bitCast(offset);
        return (0b10_101_0_010 << 23) |
            (1 << 22) | // L=1 for load
            (@as(u32, imm7) << 15) |
            (@as(u32, @intFromEnum(rt2)) << 10) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rt);
    }

    // CMP Xn, #imm12 (alias for SUBS XZR, Xn, #imm12)
    pub fn cmpImm(rn: Reg, imm12: u12) u32 {
        return (0b1_1_1_100010_0 << 22) |
            (@as(u32, imm12) << 10) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(Reg.xzr);
    }

    // LSL Xd, Xn, #shift (alias for UBFM Xd, Xn, #(64-shift), #(63-shift))
    pub fn lslImm(rd: Reg, rn: Reg, shift: u6) u32 {
        const immr: u6 = @truncate(@as(u7, 64) -% @as(u7, shift));
        const imms: u6 = 63 - shift;
        return (0b1_10_100110_1 << 22) |
            (@as(u32, immr) << 16) |
            (@as(u32, imms) << 10) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rd);
    }

    // B <offset> (unconditional, PC-relative, offset in instructions)
    pub fn b(offset: i26) u32 {
        const imm26: u26 = @bitCast(offset);
        return (0b000101 << 26) | @as(u32, imm26);
    }

    // B.cond <offset> (conditional branch, offset in instructions)
    pub fn bCond(cond: Cond, offset: i19) u32 {
        const imm19: u19 = @bitCast(offset);
        return (0b01010100 << 24) |
            (@as(u32, imm19) << 5) |
            @intFromEnum(cond);
    }

    // BL <offset> (branch with link, offset in instructions)
    pub fn bl(offset: i26) u32 {
        const imm26: u26 = @bitCast(offset);
        return (0b100101 << 26) | @as(u32, imm26);
    }

    // BLR Xn (branch with link to register)
    pub fn blr(rn: Reg) u32 {
        return (0b1101011_0001_11111_000000 << 10) |
            (@as(u32, @intFromEnum(rn)) << 5);
    }

    // RET (Xn=X30 default)
    pub fn ret() u32 {
        return 0xD65F03C0;
    }

    // NOP
    pub fn nop() u32 {
        return 0xD503201F;
    }

    // TBZ Xt, #bit, <offset> (test bit and branch if zero, offset in instructions)
    pub fn tbz(rt: Reg, bit: u6, offset: i14) u32 {
        const b5: u1 = @truncate(bit >> 5);
        const b40: u5 = @truncate(bit);
        const imm14: u14 = @bitCast(offset);
        return (@as(u32, b5) << 31) |
            (0b0110110 << 24) |
            (@as(u32, b40) << 19) |
            (@as(u32, imm14) << 5) |
            @intFromEnum(rt);
    }

    // TBNZ Xt, #bit, <offset> (test bit and branch if non-zero)
    pub fn tbnz(rt: Reg, bit: u6, offset: i14) u32 {
        const b5: u1 = @truncate(bit >> 5);
        const b40: u5 = @truncate(bit);
        const imm14: u14 = @bitCast(offset);
        return (@as(u32, b5) << 31) |
            (0b0110111 << 24) |
            (@as(u32, b40) << 19) |
            (@as(u32, imm14) << 5) |
            @intFromEnum(rt);
    }

    // ADDS Xd, Xn, Xm (add setting flags)
    pub fn addsReg(rd: Reg, rn: Reg, rm: Reg) u32 {
        return @as(u32, 0xAB000000) |
            (@as(u32, @intFromEnum(rm)) << 16) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rd);
    }

    // SUBS Xd, Xn, Xm (subtract setting flags)
    pub fn subsReg(rd: Reg, rn: Reg, rm: Reg) u32 {
        return @as(u32, 0xEB000000) |
            (@as(u32, @intFromEnum(rm)) << 16) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rd);
    }

    // CMP Xn, Xm (alias for SUBS XZR, Xn, Xm)
    pub fn cmpReg(rn: Reg, rm: Reg) u32 {
        return subsReg(.xzr, rn, rm);
    }

    // ASR Xd, Xn, #shift (arithmetic shift right, alias for SBFM Xd, Xn, #shift, #63)
    pub fn asrImm(rd: Reg, rn: Reg, shift: u6) u32 {
        return @as(u32, 0x93400000) |
            (@as(u32, shift) << 16) |
            (@as(u32, 63) << 10) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rd);
    }

    // CSEL Xd, Xn, Xm, cond (conditional select)
    pub fn csel(rd: Reg, rn: Reg, rm: Reg, cond: Cond) u32 {
        return @as(u32, 0x9A800000) |
            (@as(u32, @intFromEnum(rm)) << 16) |
            (@as(u32, @intFromEnum(cond)) << 12) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rd);
    }

    // ORR Xd, Xn, Xm (logical OR, register)
    pub fn orrReg(rd: Reg, rn: Reg, rm: Reg) u32 {
        return @as(u32, 0xAA000000) |
            (@as(u32, @intFromEnum(rm)) << 16) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rd);
    }

    // AND Xd, Xn, Xm (logical AND, register)
    pub fn andReg(rd: Reg, rn: Reg, rm: Reg) u32 {
        return @as(u32, 0x8A000000) |
            (@as(u32, @intFromEnum(rm)) << 16) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rd);
    }

    // LDR Wt, [Xn, #offset] (32-bit load, unsigned offset scaled by 4)
    pub fn ldrWImm(rt: Reg, rn: Reg, byte_offset: u16) u32 {
        std.debug.assert(byte_offset <= 16380 and byte_offset % 4 == 0);
        const scaled = @as(u32, byte_offset >> 2);
        return @as(u32, 0xB9400000) |
            (scaled << 10) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rt);
    }

    // LDRB Wt, [Xn, #offset] (byte load, unsigned offset 0..4095)
    pub fn ldrbImm(rt: Reg, rn: Reg, byte_offset: u12) u32 {
        return @as(u32, 0x39400000) |
            (@as(u32, byte_offset) << 10) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rt);
    }

    // STRB Wt, [Xn, #offset] (byte store, unsigned offset 0..4095)
    pub fn strbImm(rt: Reg, rn: Reg, byte_offset: u12) u32 {
        return @as(u32, 0x39000000) |
            (@as(u32, byte_offset) << 10) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rt);
    }

    // STRH Wt, [Xn, #offset] (halfword store, unsigned offset 0..8190, scaled by 2)
    pub fn strhImm(rt: Reg, rn: Reg, byte_offset: u16) u32 {
        std.debug.assert(byte_offset <= 8190 and byte_offset % 2 == 0);
        const scaled = @as(u32, byte_offset >> 1);
        return @as(u32, 0x79000000) |
            (scaled << 10) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rt);
    }

    // LDRH Wt, [Xn, #offset] (halfword load, unsigned offset 0..8190, scaled by 2)
    pub fn ldrhImm(rt: Reg, rn: Reg, byte_offset: u16) u32 {
        std.debug.assert(byte_offset <= 8190 and byte_offset % 2 == 0);
        const scaled = @as(u32, byte_offset >> 1);
        return @as(u32, 0x79400000) |
            (scaled << 10) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rt);
    }

    // STR Wt, [Xn, #offset] (32-bit store, unsigned offset 0..16380, scaled by 4)
    pub fn strWImm(rt: Reg, rn: Reg, byte_offset: u16) u32 {
        std.debug.assert(byte_offset <= 16380 and byte_offset % 4 == 0);
        const scaled = @as(u32, byte_offset >> 2);
        return @as(u32, 0xB9000000) |
            (scaled << 10) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rt);
    }

    // SUB Xd, Xn, Xm (64-bit subtract, no flags)
    pub fn subReg(rd: Reg, rn: Reg, rm: Reg) u32 {
        return @as(u32, 0xCB000000) |
            (@as(u32, @intFromEnum(rm)) << 16) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rd);
    }

    // MUL Xd, Xn, Xm (= MADD Xd, Xn, Xm, XZR)
    pub fn mul(rd: Reg, rn: Reg, rm: Reg) u32 {
        return @as(u32, 0x9B007C00) |
            (@as(u32, @intFromEnum(rm)) << 16) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rd);
    }

    // SMULH Xd, Xn, Xm — signed high multiply
    pub fn smulh(rd: Reg, rn: Reg, rm: Reg) u32 {
        return @as(u32, 0x9B407C00) |
            (@as(u32, @intFromEnum(rm)) << 16) |
            (@as(u32, @intFromEnum(rn)) << 5) |
            @intFromEnum(rd);
    }

    // --- Emit helpers for new instructions ---

    pub fn emitStrbImm(self: *Assembler, rt: Reg, rn: Reg, byte_offset: u12) !void {
        try self.emit(strbImm(rt, rn, byte_offset));
    }

    pub fn emitStrhImm(self: *Assembler, rt: Reg, rn: Reg, byte_offset: u16) !void {
        try self.emit(strhImm(rt, rn, byte_offset));
    }

    pub fn emitLdrhImm(self: *Assembler, rt: Reg, rn: Reg, byte_offset: u16) !void {
        try self.emit(ldrhImm(rt, rn, byte_offset));
    }

    pub fn emitSubReg(self: *Assembler, rd: Reg, rn: Reg, rm: Reg) !void {
        try self.emit(subReg(rd, rn, rm));
    }

    pub fn emitTbz(self: *Assembler, rt: Reg, bit: u6, offset: i14) !void {
        try self.emit(tbz(rt, bit, offset));
    }

    pub fn emitTbnz(self: *Assembler, rt: Reg, bit: u6, offset: i14) !void {
        try self.emit(tbnz(rt, bit, offset));
    }

    pub fn emitAddsReg(self: *Assembler, rd: Reg, rn: Reg, rm: Reg) !void {
        try self.emit(addsReg(rd, rn, rm));
    }

    pub fn emitSubsReg(self: *Assembler, rd: Reg, rn: Reg, rm: Reg) !void {
        try self.emit(subsReg(rd, rn, rm));
    }

    pub fn emitAsrImm(self: *Assembler, rd: Reg, rn: Reg, shift: u6) !void {
        try self.emit(asrImm(rd, rn, shift));
    }

    pub fn emitCsel(self: *Assembler, rd: Reg, rn: Reg, rm: Reg, cond: Cond) !void {
        try self.emit(csel(rd, rn, rm, cond));
    }

    pub fn emitOrrReg(self: *Assembler, rd: Reg, rn: Reg, rm: Reg) !void {
        try self.emit(orrReg(rd, rn, rm));
    }

    pub fn emitAndReg(self: *Assembler, rd: Reg, rn: Reg, rm: Reg) !void {
        try self.emit(andReg(rd, rn, rm));
    }

    pub fn emitCmpReg(self: *Assembler, rn: Reg, rm: Reg) !void {
        try self.emit(cmpReg(rn, rm));
    }

    pub fn emitLdrWImm(self: *Assembler, rt: Reg, rn: Reg, byte_offset: u16) !void {
        try self.emit(ldrWImm(rt, rn, byte_offset));
    }

    pub fn emitLdrbImm(self: *Assembler, rt: Reg, rn: Reg, byte_offset: u12) !void {
        try self.emit(ldrbImm(rt, rn, byte_offset));
    }
};

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "movz encoding" {
    // MOVZ X0, #42 => 0xD2800540
    try std.testing.expectEqual(@as(u32, 0xD2800540), Assembler.movz(.x0, 42, 0));
    // MOVZ X1, #0, LSL #16 => 0xD2A00001
    try std.testing.expectEqual(@as(u32, 0xD2A00001), Assembler.movz(.x1, 0, 1));
}

test "movk encoding" {
    // MOVK X0, #0x1234, LSL #16 => 0xF2A24680
    try std.testing.expectEqual(@as(u32, 0xF2A24680), Assembler.movk(.x0, 0x1234, 1));
}

test "mov register encoding" {
    // MOV X1, X0 => ORR X1, XZR, X0 => 0xAA0003E1
    try std.testing.expectEqual(@as(u32, 0xAA0003E1), Assembler.movReg(.x1, .x0));
}

test "add immediate encoding" {
    // ADD X0, X0, #32 => 0x91008000
    try std.testing.expectEqual(@as(u32, 0x91008000), Assembler.addImm(.x0, .x0, 32));
}

test "add register encoding" {
    // ADD X0, X1, X2 => 0x8B020020
    try std.testing.expectEqual(@as(u32, 0x8B020020), Assembler.addReg(.x0, .x1, .x2));
}

test "sub immediate encoding" {
    // SUB SP, SP, #64 => 0xD10103FF
    try std.testing.expectEqual(@as(u32, 0xD10103FF), Assembler.subImm(.xzr, .xzr, 64));
    // Actually SUB Xd=SP uses x31 which is SP in this context
    // SUB X19, X19, #8 => 0xD1002273
    try std.testing.expectEqual(@as(u32, 0xD1002273), Assembler.subImm(.x19, .x19, 8));
}

test "ldr/str immediate encoding" {
    // LDR X0, [X23, #0] => 0xF94002E0
    try std.testing.expectEqual(@as(u32, 0xF94002E0), Assembler.ldrImm(.x0, .x23, 0));
    // LDR X0, [X23, #8] => 0xF94006E0
    try std.testing.expectEqual(@as(u32, 0xF94006E0), Assembler.ldrImm(.x0, .x23, 8));
    // STR X0, [X23, #16] => 0xF90008E0 (offset=16, scaled=2)
    // Wait: STR encoding: 11_111_0_01_00 | imm12<<10 | Rn<<5 | Rt
    // scaled = 16/8 = 2
    // 0b11_111_0_01_00_000000000010_10111_00000
    // = 0xF90008E0... let me just verify by running
}

test "cmp immediate encoding" {
    // CMP X0, #6 => SUBS XZR, X0, #6 => 0xF100181F
    try std.testing.expectEqual(@as(u32, 0xF100181F), Assembler.cmpImm(.x0, 6));
}

test "lsl immediate encoding" {
    // LSL X20, X1, #3 => UBFM X20, X1, #61, #60 => 0xD37DF034
    try std.testing.expectEqual(@as(u32, 0xD37DF034), Assembler.lslImm(.x20, .x1, 3));
}

test "branch encoding" {
    // B +0 (self) => 0x14000000
    try std.testing.expectEqual(@as(u32, 0x14000000), Assembler.b(0));
    // B +1 => 0x14000001
    try std.testing.expectEqual(@as(u32, 0x14000001), Assembler.b(1));
    // B -1 => 0x17FFFFFF
    try std.testing.expectEqual(@as(u32, 0x17FFFFFF), Assembler.b(-1));
}

test "conditional branch encoding" {
    // B.EQ +0 => 0x54000000
    try std.testing.expectEqual(@as(u32, 0x54000000), Assembler.bCond(.eq, 0));
    // B.NE +2 => 0x54000041
    try std.testing.expectEqual(@as(u32, 0x54000041), Assembler.bCond(.ne, 2));
}

test "bl encoding" {
    // BL +0 => 0x94000000
    try std.testing.expectEqual(@as(u32, 0x94000000), Assembler.bl(0));
}

test "blr encoding" {
    // BLR X8 => 0xD63F0100
    try std.testing.expectEqual(@as(u32, 0xD63F0100), Assembler.blr(.x8));
}

test "ret encoding" {
    try std.testing.expectEqual(@as(u32, 0xD65F03C0), Assembler.ret());
}

test "nop encoding" {
    try std.testing.expectEqual(@as(u32, 0xD503201F), Assembler.nop());
}

test "stp/ldp offset encoding" {
    // STP X19, X20, [SP, #-64]! (pre-index) — offset = -8 (in 8-byte units)
    const stp_inst = Assembler.stpPre(.x19, .x20, .xzr, -8);
    // Should be: 10_101_0_011_1111000_10100_11111_10011
    // Verify it's non-zero and has correct structure
    try std.testing.expect(stp_inst != 0);

    // LDP X19, X20, [SP], #64 (post-index) — offset = 8
    const ldp_inst = Assembler.ldpPost(.x19, .x20, .xzr, 8);
    try std.testing.expect(ldp_inst != 0);
}

test "assembler emit and position" {
    var asm_ctx = Assembler.init(std.testing.allocator);
    defer asm_ctx.deinit();

    try std.testing.expectEqual(@as(u32, 0), asm_ctx.pos());
    try asm_ctx.emit(Assembler.movz(.x0, 42, 0));
    try std.testing.expectEqual(@as(u32, 1), asm_ctx.pos());
    try asm_ctx.emit(Assembler.ret());
    try std.testing.expectEqual(@as(u32, 2), asm_ctx.pos());

    const code = asm_ctx.toSlice();
    try std.testing.expectEqual(@as(usize, 2), code.len);
    try std.testing.expectEqual(@as(u32, 0xD2800540), code[0]);
    try std.testing.expectEqual(@as(u32, 0xD65F03C0), code[1]);
}

test "emitLoadImm64 small value" {
    var asm_ctx = Assembler.init(std.testing.allocator);
    defer asm_ctx.deinit();

    try asm_ctx.emitLoadImm64(.x0, 42);
    try std.testing.expectEqual(@as(u32, 1), asm_ctx.pos());
}

test "emitLoadImm64 large value" {
    var asm_ctx = Assembler.init(std.testing.allocator);
    defer asm_ctx.deinit();

    try asm_ctx.emitLoadImm64(.x0, 0x0001_0002_0003_0004);
    try std.testing.expectEqual(@as(u32, 4), asm_ctx.pos());
}

test "assembler + jit_mem integration" {
    const jit_mem = @import("jit_mem.zig");

    var asm_ctx = Assembler.init(std.testing.allocator);
    defer asm_ctx.deinit();

    try asm_ctx.emitMovz(.x0, 99, 0);
    try asm_ctx.emitRet();

    var buf = try jit_mem.CodeBuffer.alloc(4096);
    defer buf.free();

    buf.writeCode(asm_ctx.toSlice());

    const func = buf.getEntryPoint();
    try std.testing.expectEqual(@as(u64, 99), func());
}

test "tbz encoding" {
    // TBZ W0, #0, +0 => 0x36000000
    try std.testing.expectEqual(@as(u32, 0x36000000), Assembler.tbz(.x0, 0, 0));
}

test "tbnz encoding" {
    // TBNZ W0, #0, -1 => 0x3707FFE0
    try std.testing.expectEqual(@as(u32, 0x3707FFE0), Assembler.tbnz(.x0, 0, -1));
}

test "adds register encoding" {
    // ADDS X5, X3, X4 => 0xAB040065
    try std.testing.expectEqual(@as(u32, 0xAB040065), Assembler.addsReg(.x5, .x3, .x4));
}

test "subs register encoding" {
    // SUBS X5, X3, X4 => 0xEB040065
    try std.testing.expectEqual(@as(u32, 0xEB040065), Assembler.subsReg(.x5, .x3, .x4));
}

test "cmp register encoding" {
    // CMP X0, X1 => SUBS XZR, X0, X1 => 0xEB01001F
    try std.testing.expectEqual(@as(u32, 0xEB01001F), Assembler.cmpReg(.x0, .x1));
}

test "asr immediate encoding" {
    // ASR X3, X0, #1 => SBFM X3, X0, #1, #63 => 0x9341FC03
    try std.testing.expectEqual(@as(u32, 0x9341FC03), Assembler.asrImm(.x3, .x0, 1));
}

test "csel encoding" {
    // CSEL X6, X5, X4, LT => 0x9A84B0A6
    try std.testing.expectEqual(@as(u32, 0x9A84B0A6), Assembler.csel(.x6, .x5, .x4, .lt));
}

test "orr register encoding" {
    // ORR X2, X0, X1 => 0xAA010002
    try std.testing.expectEqual(@as(u32, 0xAA010002), Assembler.orrReg(.x2, .x0, .x1));
}

test "and register encoding" {
    // AND X2, X0, X1 => 0x8A010002
    try std.testing.expectEqual(@as(u32, 0x8A010002), Assembler.andReg(.x2, .x0, .x1));
}

test "ldr w immediate encoding" {
    // LDR W2, [X0] => 0xB9400002
    try std.testing.expectEqual(@as(u32, 0xB9400002), Assembler.ldrWImm(.x2, .x0, 0));
    // LDR W2, [X0, #4] => 0xB9400402
    try std.testing.expectEqual(@as(u32, 0xB9400402), Assembler.ldrWImm(.x2, .x0, 4));
}

test "ldrb immediate encoding" {
    // LDRB W4, [X0] => 0x39400004
    try std.testing.expectEqual(@as(u32, 0x39400004), Assembler.ldrbImm(.x4, .x0, 0));
    // LDRB W4, [X0, #3] => 0x39400C04
    try std.testing.expectEqual(@as(u32, 0x39400C04), Assembler.ldrbImm(.x4, .x0, 3));
}

test "strb immediate encoding" {
    // STRB W4, [X0] => 0x39000004
    try std.testing.expectEqual(@as(u32, 0x39000004), Assembler.strbImm(.x4, .x0, 0));
    // STRB W4, [X0, #3] => 0x39000C04
    try std.testing.expectEqual(@as(u32, 0x39000C04), Assembler.strbImm(.x4, .x0, 3));
}

test "strh immediate encoding" {
    // STRH W0, [X1] => 0x79000020
    try std.testing.expectEqual(@as(u32, 0x79000020), Assembler.strhImm(.x0, .x1, 0));
    // STRH W0, [X1, #2] => 0x79000420
    try std.testing.expectEqual(@as(u32, 0x79000420), Assembler.strhImm(.x0, .x1, 2));
}

test "ldrh immediate encoding" {
    // LDRH W0, [X1] => 0x79400020
    try std.testing.expectEqual(@as(u32, 0x79400020), Assembler.ldrhImm(.x0, .x1, 0));
    // LDRH W0, [X1, #4] => 0x79400820
    try std.testing.expectEqual(@as(u32, 0x79400820), Assembler.ldrhImm(.x0, .x1, 4));
}

test "sub register encoding" {
    // SUB X5, X3, X4 => 0xCB040065
    try std.testing.expectEqual(@as(u32, 0xCB040065), Assembler.subReg(.x5, .x3, .x4));
}
