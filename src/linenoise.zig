const std = @import("std");

pub const c = @cImport({
    @cInclude("linenoise.h");
});

pub fn linenoise(prompt: [*:0]const u8) ?[*:0]u8 {
    const result = c.linenoise(prompt);
    return @as(?[*:0]u8, @ptrCast(result));
}

pub fn free(ptr: *anyopaque) void {
    c.linenoiseFree(ptr);
}

pub fn historyAdd(line: [*:0]const u8) void {
    _ = c.linenoiseHistoryAdd(line);
}

pub fn historyLoad(path: [*:0]const u8) void {
    _ = c.linenoiseHistoryLoad(path);
}

pub fn historySave(path: [*:0]const u8) void {
    _ = c.linenoiseHistorySave(path);
}

pub fn historySetMaxLen(len: c_int) void {
    _ = c.linenoiseHistorySetMaxLen(len);
}

pub fn setMultiLine(ml: bool) void {
    c.linenoiseSetMultiLine(if (ml) @as(c_int, 1) else @as(c_int, 0));
}

pub fn clearScreen() void {
    c.linenoiseClearScreen();
}

pub fn setCompletionCallback(cb: ?*const fn ([*c]const u8, [*c]c.linenoiseCompletions) callconv(.c) void) void {
    c.linenoiseSetCompletionCallback(cb);
}

pub fn addCompletion(lc: ?*c.linenoiseCompletions, str: [*:0]const u8) void {
    c.linenoiseAddCompletion(lc, str);
}

pub fn setHighlightCallback(cb: ?*const fn ([*c]const u8, usize, [*c]usize) callconv(.c) [*c]u8) void {
    c.linenoiseSetHighlightCallback(cb);
}
