const std = @import("std");
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const compiler_mod = @import("compiler.zig");
const reporting = @import("reporting.zig");
const diagnostics = @import("diagnostics.zig");
const lsp_diagnostic = @import("lsp_diagnostic.zig");

const writeStderr = reporting.writeStderr;

pub const Location = struct {
    source: []const u8,
    line: u32,
    /// 1-based column of the failing instruction, or 0 when unknown (older
    /// functions with only a `source_line`, or a top-level form line). Rendered
    /// as `file:line:col` when known (kaappi#1506).
    col: u32 = 0,
};

/// How top-level diagnostics are rendered. `text` is the default human format
/// (unchanged); `json` emits one LSP `Diagnostic` object per line on stderr for
/// agents and editors (`--diagnostics=json`, kaappi#1505). Both formats share
/// the same codes, messages, and reporting funnel — only the rendering differs.
pub const DiagnosticFormat = enum { text, json };

// A process-wide setting (like `ir_mod.optimize_enabled`): set once from the
// parsed CLI options before anything runs, then read by every report function.
// The REPL, file runner, and stdin runner all funnel through here, so one
// switch covers every surface.
var diagnostic_format: DiagnosticFormat = .text;

pub fn setDiagnosticFormat(fmt: DiagnosticFormat) void {
    diagnostic_format = fmt;
}

pub fn diagnosticFormat() DiagnosticFormat {
    return diagnostic_format;
}

/// Serialize one diagnostic and write it as a single line to stderr. On the
/// rare overflow of the fixed buffer (a pathologically long detail message),
/// emit a minimal valid object instead of a truncated one so the JSON Lines
/// stream stays parseable end to end.
fn emitJsonLine(diag: lsp_diagnostic.Diagnostic) void {
    var buf: [2048]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);
    diag.writeJson(&w) catch {
        writeStderr("{\"severity\":1,\"source\":\"kaappi\",\"message\":\"diagnostic too large to serialize\"}\n");
        return;
    };
    writeStderr(w.buffered());
    writeStderr("\n");
}

fn lspSeverity(code: diagnostics.Code) lsp_diagnostic.Severity {
    return lsp_diagnostic.severityOf(code.info().severity);
}

// Every diagnostic Kaappi prints carries a stable KP code (KEP-0005, #1504).
// The leading digit encodes the stage: KP1xxx read, KP2xxx compile, KP3xxx
// runtime. The stage word ("read error" / "compile error" / runtime "error")
// is kept for the human reader; the bracketed code is the machine handle. The
// registry also supplies the fallback message that replaces the raw
// `error.XxxYyy` Zig-enum names these paths used to leak.

pub fn reportReadError(source_name: []const u8, line: u32, col: u32, err: anyerror) void {
    const code = diagnostics.readErrorCode(err);
    var cbuf: [diagnostics.Code.render_width]u8 = undefined;
    if (diagnostic_format == .json) {
        emitJsonLine(.{
            .range = lsp_diagnostic.pointRange(line, col),
            .severity = lspSeverity(code),
            .code = code.render(&cbuf),
            .message = code.message(),
        });
        return;
    }
    var buf: [256]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{s}:{d}:{d}: read error[{s}]: {s}\n", .{
        source_name, line, col, code.render(&cbuf), code.message(),
    }) catch "read error\n";
    writeStderr(s);
}

pub fn reportCompileError(source_name: []const u8, line: u32, col: u32, err: anyerror) void {
    var cbuf: [diagnostics.Code.render_width]u8 = undefined;
    const detail = compiler_mod.getSyntaxErrorDetail();
    // A macro/syntax-rules rejection carries a detail string and is the "expand"
    // stage; a plain compile failure has none. Both are KP2xxx.
    const code = if (detail.len > 0) diagnostics.Code.syntax_error else diagnostics.compileErrorCode(err);
    const msg = if (detail.len > 0) detail else code.message();

    // Prefer the precise span the compiler recorded for the failing form; fall
    // back to the top-level datum position the caller passed (kaappi#1506).
    const span = compiler_mod.getCompileErrorSpan() orelse
        types.Span{ .line = line, .col = col };
    const eff_line = if (span.line > 0) span.line else line;
    const eff_col = if (span.line > 0) span.col else col;
    defer compiler_mod.resetCompileErrorSpan();

    if (diagnostic_format == .json) {
        emitJsonLine(.{
            .range = lsp_diagnostic.spanRange(span),
            .severity = lspSeverity(code),
            .code = code.render(&cbuf),
            .message = msg,
        });
        if (detail.len > 0) compiler_mod.syntax_error_detail_len = 0;
        return;
    }

    if (detail.len > 0) {
        var buf: [256]u8 = undefined;
        const prefix = if (eff_col > 0)
            std.fmt.bufPrint(&buf, "{s}:{d}:{d}: syntax-error[{s}]: ", .{ source_name, eff_line, eff_col, code.render(&cbuf) }) catch "syntax-error: "
        else
            std.fmt.bufPrint(&buf, "{s}:{d}: syntax-error[{s}]: ", .{ source_name, eff_line, code.render(&cbuf) }) catch "syntax-error: ";
        writeStderr(prefix);
        writeStderr(detail);
        writeStderr("\n");
        compiler_mod.syntax_error_detail_len = 0;
    } else {
        var buf: [256]u8 = undefined;
        const s = if (eff_col > 0)
            std.fmt.bufPrint(&buf, "{s}:{d}:{d}: compile error[{s}]: {s}\n", .{ source_name, eff_line, eff_col, code.render(&cbuf), code.message() }) catch "compile error\n"
        else
            std.fmt.bufPrint(&buf, "{s}:{d}: compile error[{s}]: {s}\n", .{ source_name, eff_line, code.render(&cbuf), code.message() }) catch "compile error\n";
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

    if (diagnostic_format == .json) {
        // A "did you mean" hint is carried structurally (set at the raise site,
        // kaappi#1505) so a tool can apply the rename directly; the message is
        // then the clean form, with the redundant prose stripped.
        var sug_buf: [1]lsp_diagnostic.Suggestion = undefined;
        var suggestions: []const lsp_diagnostic.Suggestion = &.{};
        var clean_msg = msg;
        if (vm.last_error_suggestion) |replacement| {
            sug_buf[0] = .{ .kind = "rename", .replacement = replacement };
            suggestions = sug_buf[0..1];
            clean_msg = messageWithoutSuggestion(msg, replacement);
        }
        emitJsonLine(.{
            .range = lsp_diagnostic.pointRange(
                if (location) |loc| loc.line else 0,
                if (location) |loc| loc.col else 0,
            ),
            .severity = lspSeverity(code),
            .code = code_str,
            .message = clean_msg,
            .suggestions = suggestions,
        });
        vm.last_error_detail_len = 0;
        vm.last_error_code = .uncategorized;
        vm.last_error_suggestion = null;
        return;
    }

    if (location) |loc| {
        var buf: [512]u8 = undefined;
        const s = if (loc.line > 0 and loc.col > 0)
            std.fmt.bufPrint(&buf, "{s}:{d}:{d}: error[{s}]: {s}\n", .{ loc.source, loc.line, loc.col, code_str, msg }) catch "runtime error\n"
        else if (loc.line > 0)
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
    vm.last_error_suggestion = null;
}

/// Return `detail` without the exact "did you mean" suffix that
/// `raiseUndefinedVariable` appended for `replacement`. Deterministic: we rebuild
/// the same suffix we produced and strip it only on an exact match, so this is
/// not prose-scraping. Used to keep the JSON message clean when the hint is
/// already present in `data.suggestions`.
fn messageWithoutSuggestion(detail: []const u8, replacement: []const u8) []const u8 {
    var buf: [80]u8 = undefined;
    const suffix = std.fmt.bufPrint(&buf, ". Did you mean '{s}'?", .{replacement}) catch return detail;
    if (std.mem.endsWith(u8, detail, suffix)) return detail[0 .. detail.len - suffix.len];
    return detail;
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
    const have_precise = vm.last_error_line > 0;
    return .{
        .source = vm.last_error_source orelse fallback_source,
        .line = if (have_precise) vm.last_error_line else fallback_line,
        // Only trust the column when it pairs with the precise line; a fallback
        // line has no matching column.
        .col = if (have_precise) vm.last_error_col else 0,
    };
}

pub fn printStackTrace(vm: *vm_mod.VM) void {
    // These human-oriented extras would corrupt the one-object-per-line JSON
    // stream, so suppress them in JSON mode (a future phase may surface frames
    // as LSP `relatedInformation`).
    if (diagnostic_format == .json) return;
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
    if (diagnostic_format == .json) return;
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
