//! Shared LSP `Diagnostic` JSON serialization (kaappi#1505).
//!
//! One serializer, two surfaces. The `--diagnostics=json` CLI mode emits these
//! objects as JSON Lines (one per line) on stderr; the language server embeds
//! the same objects in a `textDocument/publishDiagnostics` array. Reusing the
//! LSP `Diagnostic` shape means agents and editors need no Kaappi-specific
//! schema — see docs/dev/diagnostics-json.md and the LSP specification
//! (`Diagnostic` under Language Features → Diagnostics).
//!
//! Only the per-object serialization lives here; framing differs by surface and
//! stays with each caller. This is the single implementation the acceptance
//! criterion asks for — the LSP must not grow a second one to drift against.

const std = @import("std");
const diagnostics = @import("diagnostics.zig");

/// A zero-based text position, as LSP defines it (both fields zero-based).
pub const Position = struct { line: u32, character: u32 };

/// A half-open `[start, end)` range in LSP zero-based coordinates.
pub const Range = struct { start: Position, end: Position };

/// LSP `DiagnosticSeverity`. The wire value is the enum's integer:
/// 1 = Error, 2 = Warning, 3 = Information, 4 = Hint.
pub const Severity = enum(u8) { err = 1, warning = 2, information = 3, hint = 4 };

/// Map a registry severity onto the LSP severity scale.
pub fn severityOf(sev: diagnostics.Severity) Severity {
    return switch (sev) {
        .err => .err,
        .warning => .warning,
    };
}

/// One suggested fix, serialized inside the diagnostic's `data.suggestions`
/// array. `data` is a free-form LSP field; `kind`/`replacement` mirror the
/// rename flavour of an LSP code action so a tool can apply the fix directly.
pub const Suggestion = struct {
    /// The kind of fix, e.g. "rename" for a "did you mean" correction.
    kind: []const u8,
    /// The text to substitute for the flagged token.
    replacement: []const u8,
};

/// An LSP `Diagnostic`. Fields are serialized in the order below, matching the
/// example in the issue and the field order the LSP spec lists.
pub const Diagnostic = struct {
    range: Range,
    severity: Severity = .err,
    /// The stable KP code (e.g. "KP3001"). `null` omits the field entirely.
    code: ?[]const u8 = null,
    /// Diagnostic origin; always "kaappi" for us. Lets an editor group ours
    /// apart from other providers' diagnostics on the same document.
    source: []const u8 = "kaappi",
    message: []const u8,
    /// Fix suggestions, emitted under `data.suggestions`. Empty omits `data`.
    suggestions: []const Suggestion = &.{},

    /// Append this diagnostic as one JSON object (no trailing newline) to `w`.
    pub fn writeJson(self: Diagnostic, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.writeAll("{\"range\":{\"start\":{\"line\":");
        try w.print("{d}", .{self.range.start.line});
        try w.writeAll(",\"character\":");
        try w.print("{d}", .{self.range.start.character});
        try w.writeAll("},\"end\":{\"line\":");
        try w.print("{d}", .{self.range.end.line});
        try w.writeAll(",\"character\":");
        try w.print("{d}", .{self.range.end.character});
        try w.writeAll("}},\"severity\":");
        try w.print("{d}", .{@intFromEnum(self.severity)});
        if (self.code) |c| {
            try w.writeAll(",\"code\":");
            try writeJsonString(w, c);
        }
        try w.writeAll(",\"source\":");
        try writeJsonString(w, self.source);
        try w.writeAll(",\"message\":");
        try writeJsonString(w, self.message);
        if (self.suggestions.len > 0) {
            try w.writeAll(",\"data\":{\"suggestions\":[");
            for (self.suggestions, 0..) |s, i| {
                if (i > 0) try w.writeByte(',');
                try w.writeAll("{\"kind\":");
                try writeJsonString(w, s.kind);
                try w.writeAll(",\"replacement\":");
                try writeJsonString(w, s.replacement);
                try w.writeByte('}');
            }
            try w.writeAll("]}");
        }
        try w.writeByte('}');
    }
};

/// Build a zero-width range at a position the reader reports as 1-based
/// `(line, col)`, converting to LSP's zero-based coordinates. A zero (unknown)
/// component maps to zero. Ranges stay points until span tracking lands
/// (kaappi#1506); this is the honest "position known today".
pub fn pointRange(line_1based: u32, col_1based: u32) Range {
    const p: Position = .{
        .line = if (line_1based > 0) line_1based - 1 else 0,
        .character = if (col_1based > 0) col_1based - 1 else 0,
    };
    return .{ .start = p, .end = p };
}

/// Write `s` as a JSON string literal (surrounding quotes included), escaping
/// the characters JSON requires. Control characters below 0x20 that lack a
/// short escape are emitted as `\uXXXX`. Shared with `kaappi explain --json`
/// (src/explain.zig) so both machine outputs escape identically.
pub fn writeJsonString(w: *std.Io.Writer, s: []const u8) std.Io.Writer.Error!void {
    try w.writeByte('"');
    for (s) |c| {
        switch (c) {
            '"' => try w.writeAll("\\\""),
            '\\' => try w.writeAll("\\\\"),
            '\n' => try w.writeAll("\\n"),
            '\r' => try w.writeAll("\\r"),
            '\t' => try w.writeAll("\\t"),
            0x00...0x08, 0x0B, 0x0C, 0x0E...0x1F => try w.print("\\u{x:0>4}", .{c}),
            else => try w.writeByte(c),
        }
    }
    try w.writeByte('"');
}

// -- Tests ------------------------------------------------------------------

const testing = std.testing;

fn renderToBuf(buf: []u8, diag: Diagnostic) []const u8 {
    var w: std.Io.Writer = .fixed(buf);
    diag.writeJson(&w) catch unreachable;
    return w.buffered();
}

test "writeJson: minimal diagnostic omits code and data" {
    var buf: [512]u8 = undefined;
    const out = renderToBuf(&buf, .{
        .range = pointRange(1, 1),
        .message = "boom",
    });
    try testing.expectEqualStrings(
        "{\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":0,\"character\":0}}," ++
            "\"severity\":1,\"source\":\"kaappi\",\"message\":\"boom\"}",
        out,
    );
}

test "writeJson: full diagnostic with code and a suggestion" {
    var buf: [512]u8 = undefined;
    const out = renderToBuf(&buf, .{
        .range = pointRange(2, 10),
        .code = "KP3001",
        .message = "undefined variable 'countr'",
        .suggestions = &.{.{ .kind = "rename", .replacement = "count" }},
    });
    try testing.expectEqualStrings(
        "{\"range\":{\"start\":{\"line\":1,\"character\":9},\"end\":{\"line\":1,\"character\":9}}," ++
            "\"severity\":1,\"code\":\"KP3001\",\"source\":\"kaappi\"," ++
            "\"message\":\"undefined variable 'countr'\"," ++
            "\"data\":{\"suggestions\":[{\"kind\":\"rename\",\"replacement\":\"count\"}]}}",
        out,
    );
}

test "writeJson: message is JSON-escaped" {
    var buf: [512]u8 = undefined;
    const out = renderToBuf(&buf, .{
        .range = pointRange(1, 1),
        .message = "bad \"quote\"\n\tand tab",
    });
    // The rendered object must parse back cleanly.
    try testing.expect(std.mem.indexOf(u8, out, "\\\"quote\\\"") != null);
    try testing.expect(std.mem.indexOf(u8, out, "\\n\\tand tab") != null);
}

test "pointRange: 1-based reader coordinates become 0-based, unknown clamps to 0" {
    const r = pointRange(3, 5);
    try testing.expectEqual(@as(u32, 2), r.start.line);
    try testing.expectEqual(@as(u32, 4), r.start.character);
    try testing.expectEqual(r.start, r.end);

    const unknown = pointRange(0, 0);
    try testing.expectEqual(@as(u32, 0), unknown.start.line);
    try testing.expectEqual(@as(u32, 0), unknown.start.character);
}

test "severityOf: registry severities map onto LSP scale" {
    try testing.expectEqual(Severity.err, severityOf(.err));
    try testing.expectEqual(Severity.warning, severityOf(.warning));
}
