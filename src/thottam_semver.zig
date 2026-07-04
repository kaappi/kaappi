const std = @import("std");

pub const Semver = struct {
    major: u32,
    minor: u32,
    patch: u32,

    pub fn parse(s: []const u8) ?Semver {
        const ver = if (s.len > 0 and s[0] == 'v') s[1..] else s;
        var it = std.mem.splitScalar(u8, ver, '.');
        const major = std.fmt.parseInt(u32, it.next() orelse return null, 10) catch return null;
        const minor = std.fmt.parseInt(u32, it.next() orelse "0", 10) catch return null;
        const patch = std.fmt.parseInt(u32, it.next() orelse "0", 10) catch return null;
        return .{ .major = major, .minor = minor, .patch = patch };
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
                if (self.ver.major != 0) break :blk v.major == self.ver.major;
                if (self.ver.minor != 0) break :blk v.major == 0 and v.minor == self.ver.minor;
                break :blk v.major == 0 and v.minor == 0 and v.patch == self.ver.patch;
            },
            .tilde => v.major == self.ver.major and v.minor == self.ver.minor and Semver.order(v, self.ver) != .lt,
        };
    }
};

pub fn parseConstraints(spec: []const u8) ?[4]?Constraint {
    var result: [4]?Constraint = .{ null, null, null, null };
    const clean = std.mem.trim(u8, spec, "\"");
    var it = std.mem.splitScalar(u8, clean, ',');
    var i: usize = 0;
    while (it.next()) |part| {
        if (i >= 4) return null;
        const trimmed = std.mem.trim(u8, part, " ");
        result[i] = parseSingleConstraint(trimmed) orelse return null;
        i += 1;
    }
    if (i == 0) return null;
    return result;
}

pub fn parseSingleConstraint(s: []const u8) ?Constraint {
    if (s.len == 0) return null;
    if (s[0] == '^') {
        const ver = Semver.parse(s[1..]) orelse return null;
        return .{ .op = .caret, .ver = ver };
    }
    if (s[0] == '~') {
        const ver = Semver.parse(s[1..]) orelse return null;
        return .{ .op = .tilde, .ver = ver };
    }
    if (std.mem.startsWith(u8, s, ">=")) {
        const ver = Semver.parse(s[2..]) orelse return null;
        return .{ .op = .gte, .ver = ver };
    }
    if (std.mem.startsWith(u8, s, "<=")) {
        const ver = Semver.parse(s[2..]) orelse return null;
        return .{ .op = .lte, .ver = ver };
    }
    if (s[0] == '>') {
        const ver = Semver.parse(s[1..]) orelse return null;
        return .{ .op = .gt, .ver = ver };
    }
    if (s[0] == '<') {
        const ver = Semver.parse(s[1..]) orelse return null;
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
