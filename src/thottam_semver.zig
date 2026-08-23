const std = @import("std");

/// Parse one dot-separated version component under SemVer 2.0.0 §2: digits
/// only, no leading zeroes. This is deliberately NOT `std.fmt.parseInt`,
/// which implements Zig's integer-literal grammar and would accept a leading
/// '+' sign and '_' digit separators (`v1_0.0.0` parsing as 10.0.0 was
/// kaappi#2130).
fn parseComponent(s: []const u8) ?u32 {
    if (s.len == 0) return null;
    if (s.len > 1 and s[0] == '0') return null; // SemVer 2.0.0 §2: no leading zeroes
    var n: u64 = 0;
    for (s) |c| {
        if (c < '0' or c > '9') return null;
        n = n * 10 + (c - '0');
        if (n > std.math.maxInt(u32)) return null;
    }
    return @intCast(n);
}

pub const Semver = struct {
    major: u32,
    minor: u32,
    patch: u32,
    /// How many dot-separated components the author actually wrote (1–3).
    /// Omitted trailing components are filled with 0, but for `^`/`~`
    /// ranges node-semver's meaning depends on how much was written, not on
    /// the filled value — `~1` is `>=1.0.0 <2.0.0` while `~1.0.0` is
    /// `>=1.0.0 <1.1.0` (kaappi#2131). Defaults to 3 so a hand-built
    /// `.{ .major, .minor, .patch }` literal is the fully-spelled form.
    written: u8 = 3,

    pub fn parse(s: []const u8) ?Semver {
        const ver = if (s.len > 0 and s[0] == 'v') s[1..] else s;
        if (ver.len == 0) return null;
        var it = std.mem.splitScalar(u8, ver, '.');
        const major_str = it.next() orelse return null;
        const minor_str = it.next();
        const patch_str = it.next();
        // SemVer 2.0.0 §2: a normal version is exactly X.Y.Z. A fourth (or
        // later) component means this is some other kind of tag — a nightly
        // marker, a build id — and must not become a release candidate
        // (kaappi#2130). Rejecting is safe: an unparsed tag is simply not a
        // candidate.
        if (it.next() != null) return null;
        const major = parseComponent(major_str) orelse return null;
        // `splitScalar` yields "" for consecutive dots ("1..3") and a null
        // next only for a genuine trailing omission ("1.2"). Only the latter
        // is lenient — an empty intermediate component is not a version.
        if (minor_str == null) return .{ .major = major, .minor = 0, .patch = 0, .written = 1 };
        const minor = parseComponent(minor_str.?) orelse return null;
        if (patch_str == null) return .{ .major = major, .minor = minor, .patch = 0, .written = 2 };
        const patch = parseComponent(patch_str.?) orelse return null;
        return .{ .major = major, .minor = minor, .patch = patch, .written = 3 };
    }

    pub fn order(a: Semver, b: Semver) std.math.Order {
        if (a.major != b.major) return std.math.order(a.major, b.major);
        if (a.minor != b.minor) return std.math.order(a.minor, b.minor);
        return std.math.order(a.patch, b.patch);
    }
};

pub const ConstraintOp = enum { gte, gt, lte, lt, eq, caret, tilde };

pub const Constraint = struct {
    op: ConstraintOp,
    ver: Semver,

    pub fn matches(self: Constraint, v: Semver) bool {
        return switch (self.op) {
            .gte => Semver.order(v, self.ver) != .lt,
            .gt => Semver.order(v, self.ver) == .gt,
            .lte => Semver.order(v, self.ver) != .gt,
            .lt => Semver.order(v, self.ver) == .lt,
            .eq => Semver.order(v, self.ver) == .eq,
            .caret => blk: {
                if (Semver.order(v, self.ver) == .lt) break :blk false;
                switch (self.ver.written) {
                    // `^1` := `>=1.0.0 <2.0.0` (node-semver Ranges).
                    1 => break :blk v.major == self.ver.major,
                    // `^1.2` locks major; `^0.2` locks minor: `>=0.2.0 <0.3.0`.
                    // `^0.0` is `>=0.0.0 <0.1.0` — the whole 0.0.x line, NOT
                    // exactly 0.0.0 (kaappi#2131).
                    2 => {
                        if (self.ver.major != 0) break :blk v.major == self.ver.major;
                        break :blk v.major == 0 and v.minor == self.ver.minor;
                    },
                    else => {
                        if (self.ver.major != 0) break :blk v.major == self.ver.major;
                        if (self.ver.minor != 0) break :blk v.major == 0 and v.minor == self.ver.minor;
                        break :blk v.major == 0 and v.minor == 0 and v.patch == self.ver.patch;
                    },
                }
            },
            .tilde => blk: {
                if (self.ver.written <= 1)
                    // `~1` is `>=1.0.0 <2.0.0` — "allows minor-level changes
                    // when only the major version is specified" — not
                    // `~1.0.0`'s `>=1.0.0 <1.1.0` (kaappi#2131).
                    break :blk v.major == self.ver.major and Semver.order(v, self.ver) != .lt;
                break :blk v.major == self.ver.major and v.minor == self.ver.minor and Semver.order(v, self.ver) != .lt;
            },
        };
    }
};

/// Why a range spec failed to parse. `resolveVersion` uses this to tell the
/// user "your constraint is malformed" apart from "no tag satisfies it",
/// which used to be one indistinguishable message (kaappi#2132).
pub const ConstraintParseError = struct {
    kind: enum {
        /// One comma-separated part is not a valid `<op><version>`.
        bad_part,
        /// More comma-separated parts than the fixed ceiling of 4.
        too_many_parts,
    },
    /// Zero-based index of the offending part.
    part_index: usize,
};

pub fn parseConstraintsDiag(spec: []const u8, diag: *ConstraintParseError) ?[4]?Constraint {
    var result: [4]?Constraint = .{ null, null, null, null };
    const clean = std.mem.trim(u8, spec, "\"");
    var it = std.mem.splitScalar(u8, clean, ',');
    var i: usize = 0;
    while (it.next()) |part| {
        if (i >= 4) {
            diag.* = .{ .kind = .too_many_parts, .part_index = i };
            return null;
        }
        const trimmed = std.mem.trim(u8, part, " ");
        result[i] = parseSingleConstraint(trimmed) orelse {
            diag.* = .{ .kind = .bad_part, .part_index = i };
            return null;
        };
        i += 1;
    }
    if (i == 0) {
        diag.* = .{ .kind = .bad_part, .part_index = 0 };
        return null;
    }
    return result;
}

pub fn parseConstraints(spec: []const u8) ?[4]?Constraint {
    var diag: ConstraintParseError = undefined;
    return parseConstraintsDiag(spec, &diag);
}

/// node-semver allows whitespace between an operator and its version
/// (`>= 1.0.0` is the same range as `>=1.0.0`); without this the space was
/// handed to Semver.parse and the whole range was reported as "no version
/// matching" (kaappi#2132).
fn afterOp(s: []const u8, op_len: usize) []const u8 {
    return std.mem.trim(u8, s[op_len..], " \t");
}

pub fn parseSingleConstraint(s: []const u8) ?Constraint {
    if (s.len == 0) return null;
    if (s[0] == '^') {
        const ver = Semver.parse(afterOp(s, 1)) orelse return null;
        return .{ .op = .caret, .ver = ver };
    }
    if (s[0] == '~') {
        const ver = Semver.parse(afterOp(s, 1)) orelse return null;
        return .{ .op = .tilde, .ver = ver };
    }
    if (std.mem.startsWith(u8, s, ">=")) {
        const ver = Semver.parse(afterOp(s, 2)) orelse return null;
        return .{ .op = .gte, .ver = ver };
    }
    if (std.mem.startsWith(u8, s, "<=")) {
        const ver = Semver.parse(afterOp(s, 2)) orelse return null;
        return .{ .op = .lte, .ver = ver };
    }
    if (s[0] == '>') {
        const ver = Semver.parse(afterOp(s, 1)) orelse return null;
        return .{ .op = .gt, .ver = ver };
    }
    if (s[0] == '<') {
        const ver = Semver.parse(afterOp(s, 1)) orelse return null;
        return .{ .op = .lt, .ver = ver };
    }
    const ver = Semver.parse(s) orelse return null;
    return .{ .op = .eq, .ver = ver };
}

pub fn matchesAllConstraints(v: Semver, constraints: [4]?Constraint) bool {
    for (constraints) |mc| {
        const c = mc orelse continue;
        if (!c.matches(v)) return false;
    }
    return true;
}

pub fn isConstraintSpec(ver: []const u8) bool {
    if (ver.len == 0) return false;
    const clean = std.mem.trim(u8, ver, "\"");
    if (clean.len == 0) return false;
    return clean[0] == '>' or clean[0] == '<' or clean[0] == '^' or clean[0] == '~';
}

test "caret constraint: major > 0 locks major" {
    const c = Constraint{ .op = .caret, .ver = .{ .major = 1, .minor = 2, .patch = 3 } };
    try std.testing.expect(c.matches(.{ .major = 1, .minor = 2, .patch = 3 }));
    try std.testing.expect(c.matches(.{ .major = 1, .minor = 9, .patch = 0 }));
    try std.testing.expect(!c.matches(.{ .major = 2, .minor = 0, .patch = 0 }));
    try std.testing.expect(!c.matches(.{ .major = 1, .minor = 2, .patch = 2 }));
}

test "caret constraint: major=0 minor>0 locks minor" {
    const c = Constraint{ .op = .caret, .ver = .{ .major = 0, .minor = 2, .patch = 3 } };
    try std.testing.expect(c.matches(.{ .major = 0, .minor = 2, .patch = 3 }));
    try std.testing.expect(c.matches(.{ .major = 0, .minor = 2, .patch = 9 }));
    try std.testing.expect(!c.matches(.{ .major = 0, .minor = 3, .patch = 0 }));
    try std.testing.expect(!c.matches(.{ .major = 0, .minor = 2, .patch = 2 }));
    try std.testing.expect(!c.matches(.{ .major = 1, .minor = 0, .patch = 0 }));
}

test "caret constraint: major=0 minor=0 locks patch" {
    const c = Constraint{ .op = .caret, .ver = .{ .major = 0, .minor = 0, .patch = 3 } };
    try std.testing.expect(c.matches(.{ .major = 0, .minor = 0, .patch = 3 }));
    try std.testing.expect(!c.matches(.{ .major = 0, .minor = 0, .patch = 4 }));
    try std.testing.expect(!c.matches(.{ .major = 0, .minor = 0, .patch = 2 }));
    try std.testing.expect(!c.matches(.{ .major = 0, .minor = 1, .patch = 0 }));
}
