const std = @import("std");
const vm_mod = @import("vm.zig");
const reporting = @import("reporting.zig");

const writeStderr = reporting.writeStderr;

pub const Location = struct {
    source: []const u8,
    line: u32,
};

pub fn reportReadError(source_name: []const u8, line: u32, col: u32, err: anyerror) void {
    var buf: [256]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{s}:{d}:{d}: read error: {}\n", .{ source_name, line, col, err }) catch "read error\n";
    writeStderr(s);
}

pub fn reportCompileError(source_name: []const u8, line: u32, err: anyerror) void {
    var buf: [256]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{s}:{d}: compile error: {}\n", .{ source_name, line, err }) catch "compile error\n";
    writeStderr(s);
}

pub fn reportRuntimeError(vm: *vm_mod.VM, err: anyerror, location: ?Location) void {
    const detail = vm.getErrorDetail();
    if (location) |loc| {
        if (detail.len > 0) {
            var buf: [512]u8 = undefined;
            const s = if (loc.line > 0)
                std.fmt.bufPrint(&buf, "{s}:{d}: error: {s}\n", .{ loc.source, loc.line, detail }) catch "runtime error\n"
            else
                std.fmt.bufPrint(&buf, "{s}: error: {s}\n", .{ loc.source, detail }) catch "runtime error\n";
            writeStderr(s);
        } else {
            var buf: [512]u8 = undefined;
            const s = if (loc.line > 0)
                std.fmt.bufPrint(&buf, "{s}:{d}: runtime error: {}\n", .{ loc.source, loc.line, err }) catch "runtime error\n"
            else
                std.fmt.bufPrint(&buf, "{s}: runtime error: {}\n", .{ loc.source, err }) catch "runtime error\n";
            writeStderr(s);
        }
    } else {
        if (detail.len > 0) {
            writeStderr("error: ");
            writeStderr(detail);
            writeStderr("\n");
        } else {
            var buf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "runtime error: {}\n", .{err}) catch "runtime error\n";
            writeStderr(s);
        }
    }
    vm.last_error_detail_len = 0;
}

pub fn vmErrorLocation(vm: *vm_mod.VM, fallback_source: []const u8, fallback_line: u32) Location {
    return .{
        .source = vm.last_error_source orelse fallback_source,
        .line = if (vm.last_error_line > 0) vm.last_error_line else fallback_line,
    };
}

pub fn printStackTrace(vm: *vm_mod.VM) void {
    const trace = vm.getLastStackTrace();
    if (trace.len > 1) {
        for (trace[1..]) |frame| {
            var buf: [256]u8 = undefined;
            if (frame.name) |name| {
                const s = std.fmt.bufPrint(&buf, "  in {s} ({s}:{d})\n", .{ name, frame.source orelse "?", frame.line }) catch continue;
                writeStderr(s);
            } else if (frame.line > 0) {
                const s = std.fmt.bufPrint(&buf, "  called from {s}:{d}\n", .{ frame.source orelse "?", frame.line }) catch continue;
                writeStderr(s);
            }
        }
    }
}

pub fn printSourceSnippet(source: []const u8, line: u32) void {
    if (line == 0 or source.len == 0) return;
    var current_line: u32 = 1;
    var line_start: usize = 0;
    for (source, 0..) |c, i| {
        if (current_line == line) {
            var line_end = i;
            while (line_end < source.len and source[line_end] != '\n') : (line_end += 1) {}
            const snippet = source[line_start..line_end];
            if (snippet.len > 0) {
                writeStderr("    ");
                writeStderr(snippet);
                writeStderr("\n");
            }
            return;
        }
        if (c == '\n') {
            current_line += 1;
            line_start = i + 1;
        }
    }
    if (current_line == line and line_start < source.len) {
        writeStderr("    ");
        writeStderr(source[line_start..]);
        writeStderr("\n");
    }
}
