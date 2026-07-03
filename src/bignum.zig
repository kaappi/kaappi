const std = @import("std");
const types = @import("types.zig");
const memory = @import("memory.zig");
const Value = types.Value;
const Bignum = types.Bignum;

// ---------------------------------------------------------------------------
// Limb-level arithmetic helpers (u128 intermediate for safety)
// ---------------------------------------------------------------------------

fn addLimb(a: u64, b: u64, carry_in: u1) struct { result: u64, carry: u1 } {
    const sum: u128 = @as(u128, a) + @as(u128, b) + @as(u128, carry_in);
    return .{
        .result = @truncate(sum),
        .carry = @truncate(sum >> 64),
    };
}

fn subLimb(a: u64, b: u64, borrow_in: u1) struct { result: u64, borrow: u1 } {
    const wide_a: u128 = @as(u128, a);
    const wide_b: u128 = @as(u128, b) + @as(u128, borrow_in);
    if (wide_a >= wide_b) {
        return .{ .result = @truncate(wide_a - wide_b), .borrow = 0 };
    } else {
        // Underflow: result = (2^64 + a) - b - borrow_in
        const diff: u128 = (@as(u128, 1) << 64) + wide_a - wide_b;
        return .{ .result = @truncate(diff), .borrow = 1 };
    }
}

fn mulLimb(a: u64, b: u64) struct { lo: u64, hi: u64 } {
    const product: u128 = @as(u128, a) * @as(u128, b);
    return .{ .lo = @truncate(product), .hi = @truncate(product >> 64) };
}

// ---------------------------------------------------------------------------
// Unsigned magnitude operations
// ---------------------------------------------------------------------------

/// Compare magnitudes. Returns -1, 0, or 1.
fn compareMagnitude(a_limbs: []const u64, a_len: usize, b_limbs: []const u64, b_len: usize) i8 {
    if (a_len != b_len) {
        return if (a_len > b_len) @as(i8, 1) else @as(i8, -1);
    }
    // Same length: compare from most significant limb
    var i: usize = a_len;
    while (i > 0) {
        i -= 1;
        if (a_limbs[i] != b_limbs[i]) {
            return if (a_limbs[i] > b_limbs[i]) @as(i8, 1) else @as(i8, -1);
        }
    }
    return 0;
}

/// Add magnitudes. Caller must free result.limbs.
fn addMagnitude(allocator: std.mem.Allocator, a_limbs: []const u64, a_len: usize, b_limbs: []const u64, b_len: usize) !struct { limbs: []u64, len: usize } {
    const max_len = @max(a_len, b_len);
    var result = try allocator.alloc(u64, max_len + 1);
    var carry: u1 = 0;
    for (0..max_len) |i| {
        const a: u64 = if (i < a_len) a_limbs[i] else 0;
        const b: u64 = if (i < b_len) b_limbs[i] else 0;
        const r = addLimb(a, b, carry);
        result[i] = r.result;
        carry = r.carry;
    }
    var len = max_len;
    if (carry != 0) {
        result[max_len] = carry;
        len = max_len + 1;
    }
    return .{ .limbs = result, .len = len };
}

/// Subtract magnitudes (a >= b assumed). Caller must free result.limbs.
fn subMagnitude(allocator: std.mem.Allocator, a_limbs: []const u64, a_len: usize, b_limbs: []const u64, b_len: usize) !struct { limbs: []u64, len: usize } {
    var result = try allocator.alloc(u64, a_len);
    var borrow: u1 = 0;
    for (0..a_len) |i| {
        const a: u64 = a_limbs[i];
        const b: u64 = if (i < b_len) b_limbs[i] else 0;
        const r = subLimb(a, b, borrow);
        result[i] = r.result;
        borrow = r.borrow;
    }
    // Normalize: find actual length
    var len = a_len;
    while (len > 0 and result[len - 1] == 0) {
        len -= 1;
    }
    return .{ .limbs = result, .len = len };
}

/// Schoolbook multiply. Caller must free result.limbs.
fn mulMagnitude(allocator: std.mem.Allocator, a_limbs: []const u64, a_len: usize, b_limbs: []const u64, b_len: usize) !struct { limbs: []u64, len: usize } {
    if (a_len == 0 or b_len == 0) {
        var result = try allocator.alloc(u64, 1);
        result[0] = 0;
        return .{ .limbs = result, .len = 0 };
    }
    const max_len = a_len + b_len;
    var result = try allocator.alloc(u64, max_len);
    @memset(result, 0);

    for (0..a_len) |i| {
        var carry: u64 = 0;
        for (0..b_len) |j| {
            const m = mulLimb(a_limbs[i], b_limbs[j]);
            // result[i+j] += m.lo + carry
            const sum1: u128 = @as(u128, result[i + j]) + @as(u128, m.lo) + @as(u128, carry);
            result[i + j] = @truncate(sum1);
            carry = m.hi + @as(u64, @truncate(sum1 >> 64));
        }
        if (carry != 0) {
            result[i + b_len] += carry;
        }
    }

    // Normalize
    var len = max_len;
    while (len > 0 and result[len - 1] == 0) {
        len -= 1;
    }
    return .{ .limbs = result, .len = len };
}

/// Divide magnitude by a single u64 divisor. Returns quotient and remainder.
/// Caller must free quotient.limbs.
fn divMagnitudeBySingleLimb(allocator: std.mem.Allocator, a_limbs: []const u64, a_len: usize, divisor: u64) !struct { limbs: []u64, len: usize, remainder: u64 } {
    if (a_len == 0) {
        var result = try allocator.alloc(u64, 1);
        result[0] = 0;
        return .{ .limbs = result, .len = 0, .remainder = 0 };
    }
    var result = try allocator.alloc(u64, a_len);
    @memset(result, 0);
    var rem: u128 = 0;
    var i: usize = a_len;
    while (i > 0) {
        i -= 1;
        rem = (rem << 64) | @as(u128, a_limbs[i]);
        result[i] = @truncate(rem / @as(u128, divisor));
        rem = rem % @as(u128, divisor);
    }
    // Normalize
    var len = a_len;
    while (len > 0 and result[len - 1] == 0) {
        len -= 1;
    }
    return .{ .limbs = result, .len = len, .remainder = @truncate(rem) };
}

// ---------------------------------------------------------------------------
// Helpers: extract limbs from a Value
// ---------------------------------------------------------------------------

const FixnumLimbs = struct {
    buf: [1]u64,
    len: usize,
    positive: bool,
};

fn fixnumToLimbs(v: Value) FixnumLimbs {
    const n = types.toFixnum(v);
    const mag: u64 = if (n < 0) @intCast(-@as(i128, n)) else @intCast(n);
    return .{
        .buf = .{mag},
        .len = if (mag == 0) 0 else 1,
        .positive = n >= 0,
    };
}

const LimbsView = struct {
    limbs: []const u64,
    len: usize,
    positive: bool,
};

fn isValueZero(v: Value) bool {
    if (types.isFixnum(v)) return types.toFixnum(v) == 0;
    if (types.isBignum(v)) return types.toBignum(v).len == 0;
    return false;
}

/// Extract a LimbsView from a Value. For fixnums, provide a pointer to
/// a FixnumLimbs struct that will be used as backing storage.
fn viewOf(v: Value, fix_storage: *FixnumLimbs) LimbsView {
    if (types.isFixnum(v)) {
        fix_storage.* = fixnumToLimbs(v);
        return .{
            .limbs = &fix_storage.buf,
            .len = fix_storage.len,
            .positive = fix_storage.positive,
        };
    }
    const bn = types.toBignum(v);
    return .{ .limbs = bn.limbs, .len = bn.len, .positive = bn.positive };
}

// ---------------------------------------------------------------------------
// Public API: signed bignum arithmetic producing Value results
// ---------------------------------------------------------------------------

/// Add two Values (fixnum or bignum), return a Value (bignum or fixnum).
pub fn add(gc: *memory.GC, a: Value, b: Value) !Value {
    var fa: FixnumLimbs = undefined;
    var fb: FixnumLimbs = undefined;
    const la = viewOf(a, &fa);
    const lb = viewOf(b, &fb);

    if (la.positive == lb.positive) {
        // Same sign: add magnitudes
        const r = try addMagnitude(gc.allocator, la.limbs, la.len, lb.limbs, lb.len);
        defer gc.allocator.free(r.limbs);
        return makeBignumValue(gc, r.limbs, r.len, la.positive);
    } else {
        // Different signs: subtract smaller from larger
        const cmp = compareMagnitude(la.limbs, la.len, lb.limbs, lb.len);
        if (cmp == 0) return types.makeFixnum(0);
        if (cmp > 0) {
            const r = try subMagnitude(gc.allocator, la.limbs, la.len, lb.limbs, lb.len);
            defer gc.allocator.free(r.limbs);
            return makeBignumValue(gc, r.limbs, r.len, la.positive);
        } else {
            const r = try subMagnitude(gc.allocator, lb.limbs, lb.len, la.limbs, la.len);
            defer gc.allocator.free(r.limbs);
            return makeBignumValue(gc, r.limbs, r.len, lb.positive);
        }
    }
}

/// Subtract b from a.
pub fn sub(gc: *memory.GC, a: Value, b: Value) !Value {
    var fa: FixnumLimbs = undefined;
    var fb: FixnumLimbs = undefined;
    const la = viewOf(a, &fa);
    const lb = viewOf(b, &fb);
    // a - b = a + (-b)
    const neg_b_positive = !lb.positive;

    if (la.positive == neg_b_positive) {
        const r = try addMagnitude(gc.allocator, la.limbs, la.len, lb.limbs, lb.len);
        defer gc.allocator.free(r.limbs);
        return makeBignumValue(gc, r.limbs, r.len, la.positive);
    } else {
        const cmp = compareMagnitude(la.limbs, la.len, lb.limbs, lb.len);
        if (cmp == 0) return types.makeFixnum(0);
        if (cmp > 0) {
            const r = try subMagnitude(gc.allocator, la.limbs, la.len, lb.limbs, lb.len);
            defer gc.allocator.free(r.limbs);
            return makeBignumValue(gc, r.limbs, r.len, la.positive);
        } else {
            const r = try subMagnitude(gc.allocator, lb.limbs, lb.len, la.limbs, la.len);
            defer gc.allocator.free(r.limbs);
            return makeBignumValue(gc, r.limbs, r.len, neg_b_positive);
        }
    }
}

/// Negate a Value.
pub fn negate(gc: *memory.GC, v: Value) !Value {
    if (types.isFixnum(v)) {
        const n = types.toFixnum(v);
        // -minInt(i48) overflows the fixnum range, promote to bignum
        if (n == std.math.minInt(i48)) {
            const mag: u64 = @intCast(-@as(i128, n));
            var limbs = [1]u64{mag};
            return gc.allocBignumFromLimbs(&limbs, 1, true);
        }
        return types.makeFixnum(-n);
    }
    const bn = types.toBignum(v);
    if (bn.len == 0) return types.makeFixnum(0);
    return gc.allocBignumFromLimbs(bn.limbs, bn.len, !bn.positive);
}

/// Multiply two Values.
pub fn mul(gc: *memory.GC, a: Value, b: Value) !Value {
    var fa: FixnumLimbs = undefined;
    var fb: FixnumLimbs = undefined;
    const la = viewOf(a, &fa);
    const lb = viewOf(b, &fb);

    if (la.len == 0 or lb.len == 0) return types.makeFixnum(0);

    const r = try mulMagnitude(gc.allocator, la.limbs, la.len, lb.limbs, lb.len);
    defer gc.allocator.free(r.limbs);
    const positive = (la.positive == lb.positive);
    return makeBignumValue(gc, r.limbs, r.len, positive);
}

/// Compare two Values (fixnum or bignum). Returns -1, 0, or 1.
pub fn compare(a: Value, b: Value) i8 {
    var fa: FixnumLimbs = undefined;
    var fb: FixnumLimbs = undefined;
    const la = viewOf(a, &fa);
    const lb = viewOf(b, &fb);

    // Handle zeros
    if (la.len == 0 and lb.len == 0) return 0;
    if (la.len == 0) return if (lb.positive) @as(i8, -1) else @as(i8, 1);
    if (lb.len == 0) return if (la.positive) @as(i8, 1) else @as(i8, -1);

    // Different signs
    if (la.positive and !lb.positive) return 1;
    if (!la.positive and lb.positive) return -1;

    // Same sign: compare magnitudes
    const mag_cmp = compareMagnitude(la.limbs, la.len, lb.limbs, lb.len);
    if (la.positive) return mag_cmp else return -mag_cmp;
}

/// Integer quotient (truncated toward zero). Supports single-limb divisors efficiently,
/// and falls back to a schoolbook method for multi-limb divisors.
pub fn quotient(gc: *memory.GC, a: Value, b: Value) !Value {
    var fa: FixnumLimbs = undefined;
    var fb: FixnumLimbs = undefined;
    const la = viewOf(a, &fa);
    const lb = viewOf(b, &fb);

    if (lb.len == 0) return error.OutOfMemory; // division by zero handled by caller

    const positive = (la.positive == lb.positive);

    if (lb.len == 1) {
        const r = try divMagnitudeBySingleLimb(gc.allocator, la.limbs, la.len, lb.limbs[0]);
        defer gc.allocator.free(r.limbs);
        return makeBignumValue(gc, r.limbs, r.len, positive);
    }

    // Multi-limb division: compare magnitudes first
    const cmp = compareMagnitude(la.limbs, la.len, lb.limbs, lb.len);
    if (cmp < 0) return types.makeFixnum(0); // |a| < |b| => quotient is 0
    if (cmp == 0) return types.makeFixnum(if (positive) @as(i64, 1) else @as(i64, -1));

    // General multi-limb division (schoolbook, Knuth Algorithm D simplified)
    const r = try divMagnitudeMulti(gc.allocator, la.limbs, la.len, lb.limbs, lb.len);
    defer gc.allocator.free(r.q_limbs);
    defer gc.allocator.free(r.r_limbs);
    return makeBignumValue(gc, r.q_limbs, r.q_len, positive);
}

/// Integer remainder (truncated toward zero).
pub fn remainder(gc: *memory.GC, a: Value, b: Value) !Value {
    var fa: FixnumLimbs = undefined;
    var fb: FixnumLimbs = undefined;
    const la = viewOf(a, &fa);
    const lb = viewOf(b, &fb);

    if (lb.len == 0) return error.OutOfMemory;

    if (lb.len == 1) {
        const r = try divMagnitudeBySingleLimb(gc.allocator, la.limbs, la.len, lb.limbs[0]);
        defer gc.allocator.free(r.limbs);
        if (r.remainder == 0) return types.makeFixnum(0);
        var rem_limbs = [1]u64{r.remainder};
        return makeBignumValue(gc, &rem_limbs, 1, la.positive);
    }

    const cmp = compareMagnitude(la.limbs, la.len, lb.limbs, lb.len);
    if (cmp < 0) {
        // |a| < |b| => remainder is a
        return makeBignumValue(gc, la.limbs, la.len, la.positive);
    }
    if (cmp == 0) return types.makeFixnum(0);

    const r = try divMagnitudeMulti(gc.allocator, la.limbs, la.len, lb.limbs, lb.len);
    defer gc.allocator.free(r.q_limbs);
    defer gc.allocator.free(r.r_limbs);
    return makeBignumValue(gc, r.r_limbs, r.r_len, la.positive);
}

/// Multi-limb division (simplified schoolbook). Returns quotient and remainder.
fn divMagnitudeMulti(allocator: std.mem.Allocator, a_limbs: []const u64, a_len: usize, b_limbs: []const u64, b_len: usize) !struct {
    q_limbs: []u64,
    q_len: usize,
    r_limbs: []u64,
    r_len: usize,
} {
    // Simple approach: binary long division
    // Count total bits in a
    const total_bits = (a_len) * 64;

    var q = try allocator.alloc(u64, a_len);
    @memset(q, 0);
    var r = try allocator.alloc(u64, b_len + 1);
    @memset(r, 0);
    var r_len: usize = 0;

    // Process each bit from most significant to least significant
    var bit_idx: usize = total_bits;
    while (bit_idx > 0) {
        bit_idx -= 1;
        // Left-shift remainder by 1
        var carry: u1 = 0;
        for (0..r.len) |i| {
            const new_carry: u1 = @truncate(r[i] >> 63);
            r[i] = (r[i] << 1) | @as(u64, carry);
            carry = new_carry;
        }
        // Update r_len
        while (r_len < r.len and r_len > 0 and r[r_len] != 0) r_len += 1;
        if (r_len == 0 and r[0] != 0) r_len = 1;

        // Bring down the next bit from a
        const limb_idx = bit_idx / 64;
        const bit_pos: u6 = @truncate(bit_idx % 64);
        if (limb_idx < a_len) {
            r[0] |= (a_limbs[limb_idx] >> bit_pos) & 1;
            if (r_len == 0 and r[0] != 0) r_len = 1;
        }

        // Recalculate r_len
        var new_r_len: usize = 0;
        for (0..r.len) |i| {
            if (r[i] != 0) new_r_len = i + 1;
        }
        r_len = new_r_len;

        // Compare r >= b
        if (compareMagnitude(r, r_len, b_limbs, b_len) >= 0) {
            // Subtract b from r
            var borrow: u1 = 0;
            for (0..r.len) |i| {
                const bv: u64 = if (i < b_len) b_limbs[i] else 0;
                const s = subLimb(r[i], bv, borrow);
                r[i] = s.result;
                borrow = s.borrow;
            }
            // Recalculate r_len
            new_r_len = 0;
            for (0..r.len) |i| {
                if (r[i] != 0) new_r_len = i + 1;
            }
            r_len = new_r_len;
            // Set quotient bit
            q[limb_idx] |= @as(u64, 1) << bit_pos;
        }
    }

    // Normalize q_len
    var q_len: usize = q.len;
    while (q_len > 0 and q[q_len - 1] == 0) q_len -= 1;

    return .{ .q_limbs = q, .q_len = q_len, .r_limbs = r, .r_len = r_len };
}

/// Integer exponentiation (base^exp where exp >= 0).
pub fn expt(gc: *memory.GC, base_val: Value, exp_val: Value) !Value {
    // exp must be a non-negative fixnum for this path
    if (!types.isFixnum(exp_val)) return error.OutOfMemory;
    const exp = types.toFixnum(exp_val);
    if (exp < 0) return error.OutOfMemory; // negative exponent => rational, not supported here

    if (exp == 0) return types.makeFixnum(1);
    if (exp == 1) return base_val;

    // Binary exponentiation
    var result: Value = types.makeFixnum(1);
    var b = base_val;
    var e: u64 = @intCast(exp);

    // Root both intermediates — result and the squared base
    const roots_base = gc.extra_roots.items.len;
    gc.extra_roots.append(gc.allocator, result) catch return error.OutOfMemory;
    gc.extra_roots.append(gc.allocator, b) catch return error.OutOfMemory;
    defer gc.extra_roots.shrinkRetainingCapacity(roots_base);

    while (e > 0) {
        if (e & 1 == 1) {
            result = try mul(gc, result, b);
            gc.extra_roots.items[roots_base] = result;
        }
        e >>= 1;
        if (e > 0) {
            b = try mul(gc, b, b);
            gc.extra_roots.items[roots_base + 1] = b;
        }
    }
    return result;
}

/// Convert a bignum Value to f64 (may lose precision for large values).
pub fn toF64(v: Value) f64 {
    if (types.isFixnum(v)) return @floatFromInt(types.toFixnum(v));
    const bn = types.toBignum(v);
    if (bn.len == 0) return 0.0;

    if (bn.len == 1) {
        const r: f64 = @floatFromInt(bn.limbs[0]);
        return if (bn.positive) r else -r;
    }
    const hi = bn.limbs[bn.len - 1];
    const lo = bn.limbs[bn.len - 2];
    var sticky: u64 = 0;
    for (bn.limbs[0 .. bn.len - 2]) |limb| sticky |= limb;
    const lo_adj: u64 = if (sticky != 0 and lo & 1 == 0) lo | 1 else lo;
    const combined: u128 = (@as(u128, hi) << 64) | @as(u128, lo_adj);
    var result: f64 = @floatFromInt(combined);
    const remaining: u32 = @intCast((bn.len - 2) * 64);
    const scale: f64 = std.math.scalbn(@as(f64, 1.0), @as(i32, @intCast(remaining)));
    result *= scale;
    if (!bn.positive) result = -result;
    return result;
}

// ---------------------------------------------------------------------------
// Decimal string conversion
// ---------------------------------------------------------------------------

/// Convert a bignum Value to a decimal string.
pub fn toString(allocator: std.mem.Allocator, v: Value) ![]u8 {
    if (types.isFixnum(v)) {
        var buf: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{types.toFixnum(v)}) catch return error.OutOfMemory;
        return allocator.dupe(u8, s) catch return error.OutOfMemory;
    }

    const bn = types.toBignum(v);
    if (bn.len == 0) {
        return allocator.dupe(u8, "0") catch return error.OutOfMemory;
    }

    // Repeated division by 10^18 (largest power of 10 fitting in u64)
    const CHUNK: u64 = 1_000_000_000_000_000_000; // 10^18
    const CHUNK_DIGITS: usize = 18;

    // Copy limbs since we'll modify them
    var work = try allocator.alloc(u64, bn.len);
    defer allocator.free(work);
    @memcpy(work, bn.limbs[0..bn.len]);
    var work_len = bn.len;

    // Collect chunks (groups of up to 18 digits)
    var chunks: std.ArrayList(u64) = .empty;
    defer chunks.deinit(allocator);

    while (work_len > 0) {
        // Divide work by CHUNK
        var rem: u128 = 0;
        var i: usize = work_len;
        while (i > 0) {
            i -= 1;
            rem = (rem << 64) | @as(u128, work[i]);
            work[i] = @truncate(rem / @as(u128, CHUNK));
            rem = rem % @as(u128, CHUNK);
        }
        chunks.append(allocator, @truncate(rem)) catch return error.OutOfMemory;
        // Normalize work_len
        while (work_len > 0 and work[work_len - 1] == 0) work_len -= 1;
    }

    // Build string from chunks (most significant chunk first)
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    if (!bn.positive) {
        result.append(allocator, '-') catch return error.OutOfMemory;
    }

    // Most significant chunk: no leading zeros
    var i: usize = chunks.items.len;
    if (i > 0) {
        i -= 1;
        var buf: [CHUNK_DIGITS]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{chunks.items[i]}) catch return error.OutOfMemory;
        result.appendSlice(allocator, s) catch return error.OutOfMemory;

        // Remaining chunks: zero-padded to CHUNK_DIGITS
        while (i > 0) {
            i -= 1;
            const s2 = std.fmt.bufPrint(&buf, "{d:0>18}", .{chunks.items[i]}) catch return error.OutOfMemory;
            result.appendSlice(allocator, s2) catch return error.OutOfMemory;
        }
    }

    return (result.toOwnedSlice(allocator) catch return error.OutOfMemory);
}

pub fn toStringRadix(allocator: std.mem.Allocator, v: Value, radix: u8) ![]u8 {
    if (radix == 10) return toString(allocator, v);
    if (types.isFixnum(v)) {
        var buf: [68]u8 = undefined;
        var n = types.toFixnum(v);
        const neg = n < 0;
        if (neg) n = -n;
        var pos: usize = buf.len;
        if (n == 0) {
            pos -= 1;
            buf[pos] = '0';
        } else {
            const r: i64 = @intCast(radix);
            while (n > 0) {
                pos -= 1;
                const digit: u8 = @intCast(@as(u64, @bitCast(@rem(n, r))));
                buf[pos] = if (digit < 10) '0' + digit else 'a' + digit - 10;
                n = @divTrunc(n, r);
            }
        }
        if (neg) {
            pos -= 1;
            buf[pos] = '-';
        }
        return allocator.dupe(u8, buf[pos..]) catch return error.OutOfMemory;
    }

    const bn = types.toBignum(v);
    if (bn.len == 0) {
        return allocator.dupe(u8, "0") catch return error.OutOfMemory;
    }

    const r64: u64 = @intCast(radix);
    var work = try allocator.alloc(u64, bn.len);
    defer allocator.free(work);
    @memcpy(work, bn.limbs[0..bn.len]);
    var work_len = bn.len;

    var digits_list: std.ArrayList(u8) = .empty;
    defer digits_list.deinit(allocator);

    while (work_len > 0) {
        var rem: u128 = 0;
        var i: usize = work_len;
        while (i > 0) {
            i -= 1;
            rem = (rem << 64) | @as(u128, work[i]);
            work[i] = @truncate(rem / @as(u128, r64));
            rem = rem % @as(u128, r64);
        }
        const digit: u8 = @intCast(@as(u64, @truncate(rem)));
        digits_list.append(allocator, if (digit < 10) '0' + digit else 'a' + digit - 10) catch return error.OutOfMemory;
        while (work_len > 0 and work[work_len - 1] == 0) work_len -= 1;
    }

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    if (!bn.positive) {
        result.append(allocator, '-') catch return error.OutOfMemory;
    }

    var i: usize = digits_list.items.len;
    while (i > 0) {
        i -= 1;
        result.append(allocator, digits_list.items[i]) catch return error.OutOfMemory;
    }

    return (result.toOwnedSlice(allocator) catch return error.OutOfMemory);
}

// max d such that radix^d <= u64 max, indexed by radix (2..36)
//  radix 2:63  3:40  4:31  5:27  6:24  7:22  8:21  9:20  10:19
// 11:18 12:17 13:17 14:16 15:16 16:15 17:15 18:15 19:14 20:14
// 21:14 22:14 23:13 24:13 25:13 26:13 27:13 28:13 29:12 30:12
// 31:12 32:12 33:12 34:12 35:12 36:12
const max_chunk_digits = [37]u8{
    0,  0,  63, 40, 31, 27, 24, 22, 21, 20,
    19, 18, 17, 17, 16, 16, 15, 15, 15, 14,
    14, 14, 14, 13, 13, 13, 13, 13, 13, 12,
    12, 12, 12, 12, 12, 12, 12,
};

/// Parse a decimal string into a bignum Value.
pub fn parseBignumString(gc: *memory.GC, digits: []const u8, radix: u8) !Value {
    if (digits.len == 0) return types.makeFixnum(0);

    var start: usize = 0;
    var positive: bool = true;
    if (digits[0] == '-') {
        positive = false;
        start = 1;
    } else if (digits[0] == '+') {
        start = 1;
    }

    const num_digits = digits[start..];
    if (num_digits.len == 0) return types.makeFixnum(0);

    const CHUNK_DIGITS: usize = max_chunk_digits[radix];
    const radix_u64: u64 = radix;

    var limbs = try gc.allocator.alloc(u64, 1);
    limbs[0] = 0;
    var len: usize = 0;

    var pos: usize = 0;
    while (pos < num_digits.len) {
        // Take up to CHUNK_DIGITS digits
        const remaining = num_digits.len - pos;
        const chunk_size = @min(remaining, CHUNK_DIGITS);
        const chunk_str = num_digits[pos .. pos + chunk_size];

        // Parse the chunk
        const chunk_val = std.fmt.parseInt(u64, chunk_str, radix) catch |e| switch (e) {
            error.InvalidCharacter => return error.InvalidCharacter,
            else => return error.OutOfMemory,
        };

        // Compute the multiplier (radix^chunk_size)
        var multiplier: u64 = 1;
        for (0..chunk_size) |_| multiplier *= radix_u64;

        // Multiply existing number by multiplier and add chunk_val
        // Multiply
        var carry: u64 = 0;
        for (0..len) |j| {
            const m = mulLimb(limbs[j], multiplier);
            const sum: u128 = @as(u128, m.lo) + @as(u128, carry);
            limbs[j] = @truncate(sum);
            carry = m.hi + @as(u64, @truncate(sum >> 64));
        }
        if (carry != 0) {
            limbs = try gc.allocator.realloc(limbs, len + 1);
            limbs[len] = carry;
            len += 1;
        }

        // Add chunk_val
        var add_carry: u128 = chunk_val;
        for (0..len) |j| {
            add_carry += @as(u128, limbs[j]);
            limbs[j] = @truncate(add_carry);
            add_carry >>= 64;
        }
        if (add_carry != 0) {
            limbs = try gc.allocator.realloc(limbs, len + 1);
            limbs[len] = @truncate(add_carry);
            len += 1;
        }
        if (len == 0 and limbs.len > 0 and limbs[0] != 0) len = 1;

        pos += chunk_size;
    }

    // Check if it fits in a fixnum
    if (len == 0) return types.makeFixnum(0);
    if (len == 1 and limbs[0] <= @as(u64, @intCast(std.math.maxInt(i48)))) {
        const n: i64 = @intCast(limbs[0]);
        gc.allocator.free(limbs);
        return types.makeFixnum(if (positive) n else -n);
    }

    // Create bignum (transfer ownership of limbs)
    const bn = try gc.allocator.create(Bignum);
    bn.* = .{
        .header = .{ .tag = .bignum },
        .limbs = limbs,
        .len = len,
        .positive = positive,
    };
    gc.trackObject(&bn.header);
    gc.bytes_allocated += @sizeOf(Bignum) + limbs.len * @sizeOf(u64);
    return types.makePointer(@ptrCast(bn));
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Check if a bignum value fits in a fixnum (i48 range).
pub fn fitsFixnum(v: Value) bool {
    if (types.isFixnum(v)) return true;
    if (!types.isBignum(v)) return false;
    const bn = types.toBignum(v);
    if (bn.len == 0) return true;
    if (bn.len > 1) return false;
    if (bn.positive) {
        return bn.limbs[0] <= @as(u64, @intCast(std.math.maxInt(i48)));
    } else {
        // minInt(i48) = -(2^47) = -140737488355328
        return bn.limbs[0] <= @as(u64, @intCast(-@as(i64, std.math.minInt(i48))));
    }
}

/// Convert bignum to fixnum if it fits, otherwise return as-is.
pub fn demote(v: Value) Value {
    if (!types.isBignum(v)) return v;
    const bn = types.toBignum(v);
    if (bn.len == 0) return types.makeFixnum(0);
    if (bn.len == 1 and bn.limbs[0] <= @as(u64, @intCast(std.math.maxInt(i48)))) {
        const n: i64 = @intCast(bn.limbs[0]);
        return types.makeFixnum(if (bn.positive) n else -n);
    }
    // Check negative case: minInt(i48)
    if (bn.len == 1 and !bn.positive and bn.limbs[0] == @as(u64, @intCast(-@as(i64, std.math.minInt(i48))))) {
        return types.makeFixnum(std.math.minInt(i48));
    }
    return v;
}

/// Build a Value from limbs, demoting to fixnum if possible.
fn makeBignumValue(gc: *memory.GC, limbs: []const u64, len: usize, positive: bool) !Value {
    if (len == 0) return types.makeFixnum(0);
    if (len == 1) {
        if (positive and limbs[0] <= @as(u64, @intCast(std.math.maxInt(i48)))) {
            return types.makeFixnum(@intCast(limbs[0]));
        }
        if (!positive and limbs[0] <= @as(u64, @intCast(-@as(i64, std.math.minInt(i48))))) {
            const n: i64 = @intCast(limbs[0]);
            return types.makeFixnum(-n);
        }
    }
    return gc.allocBignumFromLimbs(limbs, len, positive);
}

/// Check if a Value is zero (works for fixnum and bignum).
pub fn isZero(v: Value) bool {
    return isValueZero(v);
}

/// Check if a Value is positive.
pub fn isPositive(v: Value) bool {
    if (types.isFixnum(v)) return types.toFixnum(v) > 0;
    if (types.isBignum(v)) {
        const bn = types.toBignum(v);
        return bn.positive and bn.len > 0;
    }
    return false;
}

/// Check if a Value is negative.
pub fn isNegative(v: Value) bool {
    if (types.isFixnum(v)) return types.toFixnum(v) < 0;
    if (types.isBignum(v)) {
        const bn = types.toBignum(v);
        return !bn.positive and bn.len > 0;
    }
    return false;
}

/// Check if a Value is even (works for bignum).
pub fn isEven(v: Value) bool {
    if (types.isFixnum(v)) return @rem(types.toFixnum(v), 2) == 0;
    if (types.isBignum(v)) {
        const bn = types.toBignum(v);
        if (bn.len == 0) return true; // zero is even
        return (bn.limbs[0] & 1) == 0;
    }
    return false;
}

/// Absolute value.
pub fn absVal(gc: *memory.GC, v: Value) !Value {
    if (types.isFixnum(v)) {
        const n = types.toFixnum(v);
        if (n == std.math.minInt(i48)) {
            // -minInt(i48) overflows the fixnum range, promote to bignum
            const mag: u64 = @intCast(-@as(i128, n));
            var limbs = [1]u64{mag};
            return gc.allocBignumFromLimbs(&limbs, 1, true);
        }
        return types.makeFixnum(if (n < 0) -n else n);
    }
    if (types.isBignum(v)) {
        const bn = types.toBignum(v);
        if (bn.positive) return v;
        return gc.allocBignumFromLimbs(bn.limbs, bn.len, true);
    }
    return v;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

test "bignum add two small" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const a = types.makeFixnum(100);
    const b = types.makeFixnum(200);
    const result = try add(&gc, a, b);
    try std.testing.expect(types.isFixnum(result));
    try std.testing.expectEqual(@as(i64, 300), types.toFixnum(result));
}

test "bignum multiply overflow" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    // maxInt(i48) * 2 should overflow fixnum and produce bignum
    const large = types.makeFixnum(std.math.maxInt(i48));
    const two = types.makeFixnum(2);
    const result = try mul(&gc, large, two);
    // Should be a bignum (too large for fixnum)
    try std.testing.expect(types.isBignum(result));
    const f = toF64(result);
    try std.testing.expect(f > 2.8e14);
}

test "bignum toString" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const val = types.makeFixnum(12345);
    const s = try toString(std.testing.allocator, val);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("12345", s);
}

test "bignum parseBignumString small" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const val = try parseBignumString(&gc, "42", 10);
    try std.testing.expect(types.isFixnum(val));
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(val));
}

test "bignum parseBignumString large" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const val = try parseBignumString(&gc, "99999999999999999999999999999999", 10);
    try std.testing.expect(types.isBignum(val));
    const s = try toString(std.testing.allocator, val);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("99999999999999999999999999999999", s);
}

test "bignum compare" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const a = try parseBignumString(&gc, "99999999999999999999999999999999", 10);
    const b = try parseBignumString(&gc, "99999999999999999999999999999998", 10);
    try std.testing.expectEqual(@as(i8, 1), compare(a, b));
    try std.testing.expectEqual(@as(i8, -1), compare(b, a));
    try std.testing.expectEqual(@as(i8, 0), compare(a, a));
}

test "bignum negate" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const pos = try parseBignumString(&gc, "99999999999999999999999999999999", 10);
    const neg = try negate(&gc, pos);
    try std.testing.expect(types.isBignum(neg));
    const s = try toString(std.testing.allocator, neg);
    defer std.testing.allocator.free(s);
    try std.testing.expectEqualStrings("-99999999999999999999999999999999", s);
}

test "bignum add with carry propagation" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    const max_limb = try gc.allocBignumFromLimbs(&[_]u64{std.math.maxInt(u64)}, 1, true);
    const one = types.makeFixnum(1);
    const result = try add(&gc, max_limb, one);
    try std.testing.expect(types.isBignum(result));
    const bn = types.toBignum(result);
    try std.testing.expectEqual(@as(usize, 2), bn.len);
}

test "bignum add different signs (positive + negative)" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    const pos = try gc.allocBignumFromLimbs(&[_]u64{ 100, 1 }, 2, true);
    const neg = try gc.allocBignumFromLimbs(&[_]u64{50}, 1, false);
    const result = try add(&gc, pos, neg);
    try std.testing.expect(!isValueZero(result));
}

test "bignum add different signs cancellation" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    const pos = try gc.allocBignumFromLimbs(&[_]u64{42}, 1, true);
    const neg = try gc.allocBignumFromLimbs(&[_]u64{42}, 1, false);
    const result = try add(&gc, pos, neg);
    try std.testing.expect(isValueZero(result));
}

test "bignum add negative larger magnitude" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    const small_pos = try gc.allocBignumFromLimbs(&[_]u64{10}, 1, true);
    const large_neg = try gc.allocBignumFromLimbs(&[_]u64{100}, 1, false);
    const result = try add(&gc, small_pos, large_neg);
    try std.testing.expect(isNegative(result));
}

test "bignum multiply by zero" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    const big = try gc.allocBignumFromLimbs(&[_]u64{ 1, 2, 3 }, 3, true);
    const zero = types.makeFixnum(0);
    const result = try mul(&gc, big, zero);
    try std.testing.expect(isValueZero(result));
}

test "bignum isPositive and isNegative" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    const pos = try gc.allocBignumFromLimbs(&[_]u64{42}, 1, true);
    const neg = try gc.allocBignumFromLimbs(&[_]u64{42}, 1, false);
    try std.testing.expect(isPositive(pos));
    try std.testing.expect(!isNegative(pos));
    try std.testing.expect(isNegative(neg));
    try std.testing.expect(!isPositive(neg));
    try std.testing.expect(isPositive(types.makeFixnum(1)));
    try std.testing.expect(isNegative(types.makeFixnum(-1)));
    try std.testing.expect(!isPositive(types.makeFixnum(0)));
    try std.testing.expect(!isNegative(types.makeFixnum(0)));
}

test "bignum isEven" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    const even_bn = try gc.allocBignumFromLimbs(&[_]u64{42}, 1, true);
    const odd_bn = try gc.allocBignumFromLimbs(&[_]u64{43}, 1, true);
    try std.testing.expect(isEven(even_bn));
    try std.testing.expect(!isEven(odd_bn));
}

test "bignum absVal" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    const neg = try gc.allocBignumFromLimbs(&[_]u64{42}, 1, false);
    const result = try absVal(&gc, neg);
    try std.testing.expect(isPositive(result));
    const pos = try gc.allocBignumFromLimbs(&[_]u64{42}, 1, true);
    const result2 = try absVal(&gc, pos);
    try std.testing.expect(isPositive(result2));
    const fix_neg = types.makeFixnum(-5);
    const result3 = try absVal(&gc, fix_neg);
    try std.testing.expectEqual(@as(i64, 5), types.toFixnum(result3));
}

test "bignum demote" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();

    const big = try gc.allocBignumFromI64(42);
    const result = demote(big);
    try std.testing.expect(types.isFixnum(result));
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}
