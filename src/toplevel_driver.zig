const std = @import("std");
const vm_mod = @import("vm.zig");
const compiler_mod = @import("compiler.zig");
const reporting = @import("reporting.zig");
const diagnostics = @import("diagnostics.zig");

const writeStderr = reporting.writeStderr;

pub const Location = struct {
    source: []const u8,
    line: u32,
};

// Every diagnostic Kaappi prints carries a stable KP code (KEP-0005, #1504).
// The leading digit encodes the stage: KP1xxx read, KP2xxx compile, KP3xxx
// runtime. The stage word ("read error" / "compile error" / runtime "error")
// is kept for the human reader; the bracketed code is the machine handle. The
// registry also supplies the fallback message that replaces the raw
// `error.XxxYyy` Zig-enum names these paths used to leak.

pub fn reportReadError(source_name: []const u8, line: u32, col: u32, err: anyerror) void {
    const code = diagnostics.readErrorCode(err);
    var cbuf: [diagnostics.Code.render_width]u8 = undefined;
    var buf: [256]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{s}:{d}:{d}: read error[{s}]: {s}\n", .{
        source_name, line, col, code.render(&cbuf), code.message(),
    }) catch "read error\n";
    writeStderr(s);
}

pub fn reportCompileError(source_name: []const u8, line: u32, err: anyerror) void {
    var cbuf: [diagnostics.Code.render_width]u8 = undefined;
    const detail = compiler_mod.getSyntaxErrorDetail();
    if (detail.len > 0) {
        const code = diagnostics.Code.syntax_error;
        var buf: [256]u8 = undefined;
        const prefix = std.fmt.bufPrint(&buf, "{s}:{d}: syntax-error[{s}]: ", .{ source_name, line, code.render(&cbuf) }) catch "syntax-error: ";
        writeStderr(prefix);
        writeStderr(detail);
        writeStderr("\n");
        compiler_mod.syntax_error_detail_len = 0;
    } else {
        const code = diagnostics.compileErrorCode(err);
        var buf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{s}:{d}: compile error[{s}]: {s}\n", .{ source_name, line, code.render(&cbuf), code.message() }) catch "compile error\n";
        writeStderr(s);
    }
}

pub fn reportRuntimeError(vm: *vm_mod.VM, err: anyerror, location: ?Location) void {
    const detail = vm.getErrorDetail();
    const code = runtimeCode(vm, err);
    // A raise-site detail (e.g. "type error in 'car': ...") is richer than the
    // registry template, so prefer it when present; the code rides along either
    // way and the template is the no-detail fallback that killed the Zig leak.
    const msg = if (detail.len > 0) detail else code.message();
    var cbuf: [diagnostics.Code.render_width]u8 = undefined;
    const code_str = code.render(&cbuf);
    if (location) |loc| {
        var buf: [512]u8 = undefined;
        const s = if (loc.line > 0)
            std.fmt.bufPrint(&buf, "{s}:{d}: error[{s}]: {s}\n", .{ loc.source, loc.line, code_str, msg }) catch "runtime error\n"
        else
            std.fmt.bufPrint(&buf, "{s}: error[{s}]: {s}\n", .{ loc.source, code_str, msg }) catch "runtime error\n";
        writeStderr(s);
    } else {
        var buf: [512]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "error[{s}]: {s}\n", .{ code_str, msg }) catch "runtime error\n";
        writeStderr(s);
    }
    vm.last_error_detail_len = 0;
    vm.last_error_code = .uncategorized;
}

/// The diagnostic code for a runtime error: the code carried on the raised
/// error object if any (set in noteUncaughtException), else one derived from the
/// escaping Zig error. Callers outside `reportRuntimeError` (the bundled-binary
/// and include paths) use this so every runtime-error surface agrees.
pub fn runtimeCode(vm: *vm_mod.VM, err: anyerror) diagnostics.Code {
    return if (vm.last_error_code != .uncategorized)
        vm.last_error_code
    else
        diagnostics.runtimeErrorCode(err);
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
