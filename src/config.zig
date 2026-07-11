const std = @import("std");
const kaappi_paths = @import("kaappi_paths.zig");
const file_utils = @import("file_utils.zig");

pub const Theme = struct {
    keyword: []const u8 = "\x1b[95m",
    string: []const u8 = "\x1b[92m",
    number: []const u8 = "\x1b[93m",
    comment: []const u8 = "\x1b[90m",
    boolean: []const u8 = "\x1b[96m",
    paren: []const u8 = "\x1b[90m",
    match_paren: []const u8 = "\x1b[1;93m",
    prompt: []const u8 = "\x1b[92m",
    continuation: []const u8 = "\x1b[90m",
    reset: []const u8 = "\x1b[0m",

    pub const dark: Theme = .{};

    pub const light: Theme = .{
        .keyword = "\x1b[35m",
        .string = "\x1b[32m",
        .number = "\x1b[31m",
        .comment = "\x1b[90m",
        .boolean = "\x1b[36m",
        .paren = "\x1b[90m",
        .match_paren = "\x1b[1;31m",
        .prompt = "\x1b[34m",
        .continuation = "\x1b[90m",
    };

    pub const no_color: Theme = .{
        .keyword = "",
        .string = "",
        .number = "",
        .comment = "",
        .boolean = "",
        .paren = "",
        .match_paren = "",
        .prompt = "",
        .continuation = "",
        .reset = "",
    };
};

pub const Config = struct {
    theme: Theme = .{},
    prompt_buf: [64:0]u8 = initPromptBuf("kaappi> "),
    prompt_len: u8 = 8,
    history_length: c_int = 1000,
    highlight: bool = true,

    pub fn prompt(self: *const Config) [*:0]const u8 {
        return @ptrCast(&self.prompt_buf);
    }

    fn initPromptBuf(comptime default: []const u8) [64:0]u8 {
        var buf: [64:0]u8 = @splat(0);
        @memcpy(buf[0..default.len], default);
        return buf;
    }
};

pub fn load() Config {
    var cfg: Config = .{};
    const no_color = std.c.getenv("NO_COLOR") != null;
    if (no_color) {
        cfg.theme = Theme.no_color;
        cfg.highlight = false;
    }

    var home_buf: [256]u8 = undefined;
    const kaappi_home = kaappi_paths.getHome(&home_buf) orelse return cfg;
    var path_buf: [512]u8 = undefined;
    const path = std.fmt.bufPrint(&path_buf, "{s}/config", .{kaappi_home}) catch return cfg;
    const data = file_utils.readWholeFile(std.heap.c_allocator, path, 64 * 1024) catch return cfg;
    defer std.heap.c_allocator.free(data);

    var line_num: usize = 0;
    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |line| {
        line_num += 1;
        parseLine(&cfg, line, line_num, no_color);
    }

    return cfg;
}

fn parseLine(cfg: *Config, line: []const u8, line_num: usize, no_color: bool) void {
    const stripped = std.mem.trimEnd(u8, line, "\r\n");
    const trimmed = std.mem.trimStart(u8, stripped, " \t");
    if (trimmed.len == 0 or trimmed[0] == '#') return;

    const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse {
        warnLine(line_num, "missing ':'");
        return;
    };
    const key = std.mem.trimEnd(u8, trimmed[0..colon], " \t");
    const raw_value = std.mem.trimStart(u8, trimmed[colon + 1 ..], " \t");
    const value = std.mem.trimEnd(u8, raw_value, " \t");

    if (std.mem.eql(u8, key, "repl.theme")) {
        if (std.mem.eql(u8, value, "dark")) {
            if (!no_color) cfg.theme = Theme.dark;
        } else if (std.mem.eql(u8, value, "light")) {
            if (!no_color) cfg.theme = Theme.light;
        } else {
            warnLine(line_num, "repl.theme must be 'dark' or 'light'");
        }
        return;
    } else if (std.mem.eql(u8, key, "repl.color.keyword")) {
        if (!no_color) cfg.theme.keyword = colorToAnsi(value) orelse return warnColor(line_num, key, value);
    } else if (std.mem.eql(u8, key, "repl.color.string")) {
        if (!no_color) cfg.theme.string = colorToAnsi(value) orelse return warnColor(line_num, key, value);
    } else if (std.mem.eql(u8, key, "repl.color.number")) {
        if (!no_color) cfg.theme.number = colorToAnsi(value) orelse return warnColor(line_num, key, value);
    } else if (std.mem.eql(u8, key, "repl.color.comment")) {
        if (!no_color) cfg.theme.comment = colorToAnsi(value) orelse return warnColor(line_num, key, value);
    } else if (std.mem.eql(u8, key, "repl.color.boolean")) {
        if (!no_color) cfg.theme.boolean = colorToAnsi(value) orelse return warnColor(line_num, key, value);
    } else if (std.mem.eql(u8, key, "repl.color.paren")) {
        if (!no_color) cfg.theme.paren = colorToAnsi(value) orelse return warnColor(line_num, key, value);
    } else if (std.mem.eql(u8, key, "repl.color.match-paren")) {
        if (!no_color) cfg.theme.match_paren = colorToAnsi(value) orelse return warnColor(line_num, key, value);
    } else if (std.mem.eql(u8, key, "repl.color.prompt")) {
        if (!no_color) cfg.theme.prompt = colorToAnsi(value) orelse return warnColor(line_num, key, value);
    } else if (std.mem.eql(u8, key, "repl.color.continuation")) {
        if (!no_color) cfg.theme.continuation = colorToAnsi(value) orelse return warnColor(line_num, key, value);
    } else if (std.mem.eql(u8, key, "repl.prompt")) {
        if (raw_value.len > 63) {
            warnLine(line_num, "prompt too long (max 63 chars)");
            return;
        }
        @memcpy(cfg.prompt_buf[0..raw_value.len], raw_value);
        cfg.prompt_buf[raw_value.len] = 0;
        cfg.prompt_len = @intCast(raw_value.len);
    } else if (std.mem.eql(u8, key, "repl.history-length")) {
        cfg.history_length = std.fmt.parseInt(c_int, value, 10) catch {
            warnLine(line_num, "invalid number for repl.history-length");
            return;
        };
        if (cfg.history_length < 0) {
            warnLine(line_num, "repl.history-length must be non-negative");
            cfg.history_length = 1000;
        }
    } else if (std.mem.eql(u8, key, "repl.highlight")) {
        if (std.mem.eql(u8, value, "true")) {
            if (!no_color) cfg.highlight = true;
        } else if (std.mem.eql(u8, value, "false")) {
            cfg.highlight = false;
        } else {
            warnLine(line_num, "repl.highlight must be 'true' or 'false'");
        }
    } else {
        warnKey(line_num, key);
    }
}

fn colorToAnsi(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "none")) return "";

    if (std.mem.startsWith(u8, name, "bold ")) {
        const base = baseColorCode(std.mem.trim(u8, name[5..], " ")) orelse return null;
        return switch (base[0]) {
            '0' => "\x1b[1;30m",
            '1' => "\x1b[1;31m",
            '2' => "\x1b[1;32m",
            '3' => "\x1b[1;33m",
            '4' => "\x1b[1;34m",
            '5' => "\x1b[1;35m",
            '6' => "\x1b[1;36m",
            '7' => "\x1b[1;37m",
            '9' => switch (base[1]) {
                '0' => "\x1b[1;90m",
                '1' => "\x1b[1;91m",
                '2' => "\x1b[1;92m",
                '3' => "\x1b[1;93m",
                '4' => "\x1b[1;94m",
                '5' => "\x1b[1;95m",
                '6' => "\x1b[1;96m",
                '7' => "\x1b[1;97m",
                else => null,
            },
            else => null,
        };
    }

    const code = baseColorCode(name) orelse return null;
    return switch (code[0]) {
        '0' => "\x1b[30m",
        '1' => "\x1b[31m",
        '2' => "\x1b[32m",
        '3' => "\x1b[33m",
        '4' => "\x1b[34m",
        '5' => "\x1b[35m",
        '6' => "\x1b[36m",
        '7' => "\x1b[37m",
        '9' => switch (code[1]) {
            '0' => "\x1b[90m",
            '1' => "\x1b[91m",
            '2' => "\x1b[92m",
            '3' => "\x1b[93m",
            '4' => "\x1b[94m",
            '5' => "\x1b[95m",
            '6' => "\x1b[96m",
            '7' => "\x1b[97m",
            else => null,
        },
        else => null,
    };
}

fn baseColorCode(name: []const u8) ?*const [2]u8 {
    const map = .{
        .{ "black", "0_" },
        .{ "red", "1_" },
        .{ "green", "2_" },
        .{ "yellow", "3_" },
        .{ "blue", "4_" },
        .{ "magenta", "5_" },
        .{ "cyan", "6_" },
        .{ "white", "7_" },
        .{ "bright-black", "90" },
        .{ "bright-red", "91" },
        .{ "bright-green", "92" },
        .{ "bright-yellow", "93" },
        .{ "bright-blue", "94" },
        .{ "bright-magenta", "95" },
        .{ "bright-cyan", "96" },
        .{ "bright-white", "97" },
    };
    inline for (map) |entry| {
        if (std.mem.eql(u8, name, entry[0])) return entry[1];
    }
    return null;
}

fn warnLine(line_num: usize, msg: []const u8) void {
    var buf: [128]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "config: {s} (line {d})\n", .{ msg, line_num }) catch return;
    _ = std.posix.system.write(2, out.ptr, out.len);
}

fn warnColor(line_num: usize, key: []const u8, value: []const u8) void {
    var buf: [192]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "config: unknown color '{s}' for {s} (line {d})\n", .{ value, key, line_num }) catch return;
    _ = std.posix.system.write(2, out.ptr, out.len);
}

fn warnKey(line_num: usize, key: []const u8) void {
    var buf: [128]u8 = undefined;
    const out = std.fmt.bufPrint(&buf, "config: unknown key '{s}' (line {d})\n", .{ key, line_num }) catch return;
    _ = std.posix.system.write(2, out.ptr, out.len);
}

// --- Tests ---

test "colorToAnsi basic colors" {
    try std.testing.expectEqualStrings("\x1b[31m", colorToAnsi("red").?);
    try std.testing.expectEqualStrings("\x1b[32m", colorToAnsi("green").?);
    try std.testing.expectEqualStrings("\x1b[35m", colorToAnsi("magenta").?);
    try std.testing.expectEqualStrings("\x1b[90m", colorToAnsi("bright-black").?);
    try std.testing.expectEqualStrings("\x1b[93m", colorToAnsi("bright-yellow").?);
}

test "colorToAnsi bold" {
    try std.testing.expectEqualStrings("\x1b[1;31m", colorToAnsi("bold red").?);
    try std.testing.expectEqualStrings("\x1b[1;93m", colorToAnsi("bold bright-yellow").?);
}

test "colorToAnsi none" {
    try std.testing.expectEqualStrings("", colorToAnsi("none").?);
}

test "colorToAnsi invalid" {
    try std.testing.expectEqual(@as(?[]const u8, null), colorToAnsi("purrple"));
    try std.testing.expectEqual(@as(?[]const u8, null), colorToAnsi("bold purrple"));
    try std.testing.expectEqual(@as(?[]const u8, null), colorToAnsi(""));
}

test "Config defaults match dark preset" {
    const cfg: Config = .{};
    try std.testing.expectEqualStrings("\x1b[95m", cfg.theme.keyword);
    try std.testing.expectEqualStrings("\x1b[92m", cfg.theme.string);
    try std.testing.expectEqualStrings("\x1b[93m", cfg.theme.number);
    try std.testing.expectEqualStrings("\x1b[90m", cfg.theme.comment);
    try std.testing.expectEqualStrings("\x1b[96m", cfg.theme.boolean);
    try std.testing.expectEqualStrings("\x1b[90m", cfg.theme.paren);
    try std.testing.expectEqualStrings("\x1b[1;93m", cfg.theme.match_paren);
    try std.testing.expectEqualStrings("\x1b[0m", cfg.theme.reset);
    try std.testing.expectEqual(true, cfg.highlight);
    try std.testing.expectEqual(@as(c_int, 1000), cfg.history_length);
}

test "light preset uses standard colors" {
    const t = Theme.light;
    try std.testing.expectEqualStrings("\x1b[35m", t.keyword);
    try std.testing.expectEqualStrings("\x1b[32m", t.string);
    try std.testing.expectEqualStrings("\x1b[31m", t.number);
    try std.testing.expectEqualStrings("\x1b[36m", t.boolean);
    try std.testing.expectEqualStrings("\x1b[1;31m", t.match_paren);
}

test "parseLine repl.theme selects preset" {
    var cfg: Config = .{};
    parseLine(&cfg, "repl.theme: light", 1, false);
    try std.testing.expectEqualStrings("\x1b[31m", cfg.theme.number);
    try std.testing.expectEqualStrings("\x1b[35m", cfg.theme.keyword);
}

test "parseLine color overrides preset" {
    var cfg: Config = .{};
    parseLine(&cfg, "repl.theme: light", 1, false);
    parseLine(&cfg, "repl.color.number: blue", 2, false);
    try std.testing.expectEqualStrings("\x1b[34m", cfg.theme.number);
    try std.testing.expectEqualStrings("\x1b[35m", cfg.theme.keyword);
}

test "parseLine color key" {
    var cfg: Config = .{};
    parseLine(&cfg, "repl.color.keyword: red", 1, false);
    try std.testing.expectEqualStrings("\x1b[31m", cfg.theme.keyword);
}

test "parseLine skips color when no_color" {
    var cfg: Config = .{};
    cfg.theme = Theme.no_color;
    parseLine(&cfg, "repl.color.keyword: red", 1, true);
    try std.testing.expectEqualStrings("", cfg.theme.keyword);
}

test "parseLine prompt" {
    var cfg: Config = .{};
    parseLine(&cfg, "repl.prompt: λ> ", 1, false);
    const expected = "λ> ";
    try std.testing.expectEqualStrings(expected, cfg.prompt_buf[0..cfg.prompt_len]);
}

test "parseLine history-length" {
    var cfg: Config = .{};
    parseLine(&cfg, "repl.history-length: 500", 1, false);
    try std.testing.expectEqual(@as(c_int, 500), cfg.history_length);
}

test "parseLine highlight" {
    var cfg: Config = .{};
    parseLine(&cfg, "repl.highlight: false", 1, false);
    try std.testing.expectEqual(false, cfg.highlight);
}

test "parseLine skips comments and blanks" {
    var cfg: Config = .{};
    parseLine(&cfg, "# this is a comment", 1, false);
    parseLine(&cfg, "", 2, false);
    parseLine(&cfg, "  ", 3, false);
    try std.testing.expectEqualStrings("\x1b[95m", cfg.theme.keyword);
}

test "Theme.no_color has all empty strings" {
    const t = Theme.no_color;
    try std.testing.expectEqualStrings("", t.keyword);
    try std.testing.expectEqualStrings("", t.reset);
    try std.testing.expectEqualStrings("", t.match_paren);
}
