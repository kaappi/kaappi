const std = @import("std");

/// Returns the kaappi home directory path written into `buf`.
/// Checks `KAAPPI_HOME` env var first; falls back to `$HOME/.kaappi`.
/// Returns null if neither env var is available or the path exceeds `buf`.
pub fn getHome(buf: []u8) ?[]const u8 {
    if (std.c.getenv("KAAPPI_HOME")) |kh| {
        const home = std.mem.sliceTo(kh, 0);
        if (home.len > 0 and home.len <= buf.len) {
            @memcpy(buf[0..home.len], home);
            return buf[0..home.len];
        }
    }
    const home_ptr = std.c.getenv("HOME") orelse return null;
    const home = std.mem.sliceTo(home_ptr, 0);
    const suffix = "/.kaappi";
    const total = home.len + suffix.len;
    if (total > buf.len) return null;
    @memcpy(buf[0..home.len], home);
    @memcpy(buf[home.len..][0..suffix.len], suffix);
    return buf[0..total];
}

test "getHome falls back to HOME/.kaappi" {
    var buf: [512]u8 = undefined;
    if (getHome(&buf)) |home| {
        try std.testing.expect(home.len > 0);
        try std.testing.expect(std.mem.endsWith(u8, home, "/.kaappi") or
            std.c.getenv("KAAPPI_HOME") != null);
    }
}
