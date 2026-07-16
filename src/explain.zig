//! `kaappi explain <code>` — embedded documentation for every diagnostic code
//! (kaappi#1507, part of the machine-legibility epic kaappi#1503).
//!
//! Modelled on `rustc --explain`: the binary is its own diagnostic reference —
//! offline, version-matched, and identical for a human reading prose and an
//! agent parsing JSON. Everything printed here comes from the single registry
//! in `diagnostics.zig`, so `kaappi explain`, the `--diagnostics=json` stream,
//! and the generated website page can never disagree about what a code means.
//!
//! Forms:
//!   kaappi explain KP3001            prose + example + fix for one code
//!   kaappi explain undefined-variable   (the kebab name works too)
//!   kaappi explain --json KP3001     one JSON object for structured use
//!   kaappi explain --all             the full reference, every code
//!   kaappi explain --all --json      the full reference as a JSON array
//!                                    (the source a docs generator consumes)

const std = @import("std");
const platform = @import("platform.zig");
const diagnostics = @import("diagnostics.zig");
const lsp_diagnostic = @import("lsp_diagnostic.zig");
const reporting = @import("reporting.zig");

const writeStdout = reporting.writeStdout;
const writeStderr = reporting.writeStderr;
const Diagnostic = diagnostics.Diagnostic;

pub const USAGE_ERROR_EXIT: u8 = 2;

/// A parsed `kaappi explain …` invocation.
pub const Request = struct {
    /// The `<code>` argument (KP number or kebab name); null when `--all`.
    query: ?[]const u8 = null,
    json: bool = false,
    all: bool = false,
};

/// If `args` is a `kaappi explain …` invocation, handle it fully and return the
/// process exit code; otherwise return null so normal CLI dispatch proceeds.
/// `explain` is a pure query over the static registry — it needs no VM, GC, or
/// library setup, so main dispatches it before any of that is created.
pub fn maybeRun(allocator: std.mem.Allocator, args: std.process.Args) ?u8 {
    var it = platform.argsIterate(args);
    _ = it.skip(); // argv[0]
    const first = it.next() orelse return null;
    if (!std.mem.eql(u8, first, "explain")) return null;

    var req: Request = .{};
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "--json")) {
            req.json = true;
        } else if (std.mem.eql(u8, arg, "--all")) {
            req.all = true;
        } else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            printUsage();
            return 0;
        } else if (arg.len > 1 and arg[0] == '-') {
            writeStderr("kaappi explain: unknown option '");
            writeStderr(arg);
            writeStderr("'\nUsage: kaappi explain [--json] [--all] <code>\n");
            return USAGE_ERROR_EXIT;
        } else if (req.query == null) {
            req.query = arg;
        } else {
            writeStderr("kaappi explain: unexpected extra argument '");
            writeStderr(arg);
            writeStderr("'\nUsage: kaappi explain [--json] [--all] <code>\n");
            return USAGE_ERROR_EXIT;
        }
    }
    return run(allocator, req);
}

/// Execute a parsed request; returns the process exit code.
pub fn run(allocator: std.mem.Allocator, req: Request) u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    defer aw.deinit();
    const w = &aw.writer;

    if (req.all) {
        // `<code>` alongside `--all` is meaningless; flag it rather than
        // silently ignore, so an agent's mistaken invocation is visible.
        if (req.query) |q| {
            writeStderr("kaappi explain: give a code or --all, not both (got '");
            writeStderr(q);
            writeStderr("')\n");
            return USAGE_ERROR_EXIT;
        }
        (if (req.json) renderAllJson(w) else renderAllText(w)) catch return reportOom();
        writeStdout(aw.written());
        return 0;
    }

    const query = req.query orelse {
        writeStderr("kaappi explain: missing <code> argument (e.g. 'kaappi explain KP3001')\n");
        return USAGE_ERROR_EXIT;
    };

    const code = diagnostics.Code.fromString(query) orelse {
        writeStderr("kaappi explain: unknown diagnostic code '");
        writeStderr(query);
        writeStderr("'\nRun 'kaappi explain --all' to list every code.\n");
        return USAGE_ERROR_EXIT;
    };

    (if (req.json) renderJson(w, code.info()) else renderText(w, code.info())) catch return reportOom();
    writeStdout(aw.written());
    return 0;
}

fn reportOom() u8 {
    writeStderr("kaappi explain: out of memory\n");
    return 1;
}

// ── Rendering ──────────────────────────────────────────────────────────

/// Human-readable form: header, one-line summary, prose (which carries the
/// fix), then the triggering example.
fn renderText(w: *std.Io.Writer, d: Diagnostic) std.Io.Writer.Error!void {
    var cbuf: [diagnostics.Code.render_width]u8 = undefined;
    try w.print("{s}  {s}\n", .{ d.code.render(&cbuf), d.name });
    try w.print("{s} · {s}\n\n", .{ d.code.stage().label(), d.severity.label() });

    try w.print("{s}\n\n", .{d.template});

    try w.writeAll(d.explanation);
    try w.writeByte('\n'); // registry prose has no trailing newline

    try w.writeAll("\nExample:\n");
    try writeIndented(w, d.example);
}

/// Structured form: one JSON object. `code`/`name`/`stage` are the stable
/// machine handles; `message`/`explanation`/`example` are the human prose and
/// are free to be reworded, exactly like the `--diagnostics=json` contract.
fn renderJson(w: *std.Io.Writer, d: Diagnostic) std.Io.Writer.Error!void {
    var cbuf: [diagnostics.Code.render_width]u8 = undefined;
    try w.writeAll("{\"code\":");
    try lsp_diagnostic.writeJsonString(w, d.code.render(&cbuf));
    try w.writeAll(",\"name\":");
    try lsp_diagnostic.writeJsonString(w, d.name);
    try w.writeAll(",\"stage\":");
    try lsp_diagnostic.writeJsonString(w, d.code.stage().label());
    try w.writeAll(",\"severity\":");
    try lsp_diagnostic.writeJsonString(w, d.severity.label());
    try w.writeAll(",\"message\":");
    try lsp_diagnostic.writeJsonString(w, d.template);
    try w.writeAll(",\"explanation\":");
    try lsp_diagnostic.writeJsonString(w, d.explanation);
    try w.writeAll(",\"example\":");
    try lsp_diagnostic.writeJsonString(w, d.example);
    try w.writeByte('}');
}

fn renderAllText(w: *std.Io.Writer) std.Io.Writer.Error!void {
    for (diagnostics.table, 0..) |d, i| {
        if (i > 0) try w.writeAll("\n────────────────────────────────────────\n\n");
        try renderText(w, d);
    }
}

/// A single JSON array — one document a docs generator parses in one call.
fn renderAllJson(w: *std.Io.Writer) std.Io.Writer.Error!void {
    try w.writeByte('[');
    for (diagnostics.table, 0..) |d, i| {
        if (i > 0) try w.writeByte(',');
        try renderJson(w, d);
    }
    try w.writeAll("]\n");
}

/// Write `text` with every line indented four spaces, always newline-terminated.
fn writeIndented(w: *std.Io.Writer, text: []const u8) std.Io.Writer.Error!void {
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        try w.writeAll("    ");
        try w.writeAll(line);
        try w.writeByte('\n');
    }
}

fn printUsage() void {
    writeStdout(
        \\Usage: kaappi explain [--json] [--all] <code>
        \\
        \\Print the registry entry — meaning, example, and fix — for a diagnostic
        \\code. <code> is a KP number ("KP3001", "3001") or its kebab name
        \\("undefined-variable").
        \\
        \\  --json   Emit a JSON object (or a JSON array with --all).
        \\  --all    Print every registered code (the full diagnostic reference).
        \\
    );
}

// ── Tests ──────────────────────────────────────────────────────────────

const testing = std.testing;

fn renderTextToOwned(allocator: std.mem.Allocator, code: diagnostics.Code) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();
    try renderText(&aw.writer, code.info());
    return aw.toOwnedSlice();
}

fn renderJsonToOwned(allocator: std.mem.Allocator, code: diagnostics.Code) ![]u8 {
    var aw: std.Io.Writer.Allocating = .init(allocator);
    errdefer aw.deinit();
    try renderJson(&aw.writer, code.info());
    return aw.toOwnedSlice();
}

test "text render carries code, name, message, explanation, and example" {
    const out = try renderTextToOwned(testing.allocator, .undefined_variable);
    defer testing.allocator.free(out);
    try testing.expect(std.mem.indexOf(u8, out, "KP3001") != null);
    try testing.expect(std.mem.indexOf(u8, out, "undefined-variable") != null);
    try testing.expect(std.mem.indexOf(u8, out, "runtime") != null);
    try testing.expect(std.mem.indexOf(u8, out, "undefined variable") != null);
    try testing.expect(std.mem.indexOf(u8, out, "Example:") != null);
    // the example snippet, indented
    try testing.expect(std.mem.indexOf(u8, out, "    (display undefined-name)") != null);
    // some of the explanation prose
    try testing.expect(std.mem.indexOf(u8, out, "no binding in scope") != null);
}

test "json render is a single object with the expected fields" {
    const out = try renderJsonToOwned(testing.allocator, .division_by_zero);
    defer testing.allocator.free(out);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, out, .{});
    defer parsed.deinit();
    const obj = parsed.value.object;

    try testing.expectEqualStrings("KP3004", obj.get("code").?.string);
    try testing.expectEqualStrings("division-by-zero", obj.get("name").?.string);
    try testing.expectEqualStrings("runtime", obj.get("stage").?.string);
    try testing.expectEqualStrings("error", obj.get("severity").?.string);
    try testing.expect(obj.get("message") != null);
    try testing.expect(obj.get("explanation") != null);
    try testing.expectEqualStrings("(/ 1 0)", obj.get("example").?.string);
}

test "json escapes newlines in multi-line examples and explanations" {
    // The stack-overflow example is a two-line snippet; a raw newline would be
    // invalid JSON, so a successful parse proves it is escaped.
    const out = try renderJsonToOwned(testing.allocator, .stack_overflow);
    defer testing.allocator.free(out);
    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, out, .{});
    defer parsed.deinit();
    try testing.expect(std.mem.indexOf(u8, parsed.value.object.get("example").?.string, "\n") != null);
}

test "--all json is one valid array covering every registered code" {
    var aw: std.Io.Writer.Allocating = .init(testing.allocator);
    defer aw.deinit();
    try renderAllJson(&aw.writer);

    const parsed = try std.json.parseFromSlice(std.json.Value, testing.allocator, aw.written(), .{});
    defer parsed.deinit();
    try testing.expectEqual(diagnostics.table.len, parsed.value.array.items.len);
}

test "fromString resolves KP number, bare number, and kebab name" {
    try testing.expectEqual(diagnostics.Code.undefined_variable, diagnostics.Code.fromString("KP3001").?);
    try testing.expectEqual(diagnostics.Code.undefined_variable, diagnostics.Code.fromString("kp3001").?);
    try testing.expectEqual(diagnostics.Code.undefined_variable, diagnostics.Code.fromString("3001").?);
    try testing.expectEqual(diagnostics.Code.undefined_variable, diagnostics.Code.fromString("undefined-variable").?);
    try testing.expectEqual(diagnostics.Code.undefined_variable, diagnostics.Code.fromString("UNDEFINED-VARIABLE").?);
    try testing.expect(diagnostics.Code.fromString("KP9999") == null);
    try testing.expect(diagnostics.Code.fromString("nope") == null);
    try testing.expect(diagnostics.Code.fromString("") == null);
    try testing.expect(diagnostics.Code.fromString("kp") == null);
}
