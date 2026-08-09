const std = @import("std");
const platform = @import("platform.zig");
const is_wasm = @import("builtin").os.tag == .wasi;
const types = @import("types.zig");
const vm_mod = @import("vm.zig");
const compiler = @import("compiler.zig");
const reader = @import("reader.zig");
const memory = @import("memory.zig");
const printer = @import("printer.zig");
const vm_library = @import("vm_library.zig");
const reporting = @import("reporting.zig");
const expander = @import("expander.zig");
const toplevel_driver = @import("toplevel_driver.zig");
const crash = @import("crash.zig");
const repl_sexp = @import("repl_sexp.zig");
/// isocline is the line editor (`vendor/isocline/`). It holds a whole form in
/// one buffer, so `ic.readline` returns a finished expression — newlines and
/// all — instead of one physical line, and every line of it stays editable
/// until submit. Kaappi's copy is patched with an input-completeness callback;
/// see `vendor/isocline/PATCHES.md`.
///
/// Windows included: isocline drives the console API directly there, so that
/// platform gets editing, history, and completion for the first time. Only
/// WASI falls back to the plain stdin loop below, and only to keep compiling —
/// main.zig never reaches the REPL on that target.
const use_isocline = !is_wasm;
const ic = if (use_isocline) @import("isocline.zig") else struct {};

const config_mod = @import("config.zig");
const version = @import("main.zig").version;

var repl_vm: ?*vm_mod.VM = null;
var terminal_width: u16 = 80;
var theme: config_mod.Theme = .{};
var highlight_enabled: bool = true;

fn getTerminalWidth() u16 {
    if (comptime is_wasm) return 80;
    return platform.terminalWidth() orelse 80;
}

/// One complete REPL input. Under isocline this is a whole expression, which
/// may span lines: the editor keeps prompting (via `isCompleteCallback`) until
/// the form closes, so the returned string can contain newlines. The WASI
/// fallback writes the prompt and reads a single plain line from fd 0, and its
/// caller still has to accumulate continuation lines itself.
///
/// Returns a NUL-terminated string owned by the editor, released by
/// `freeReplLine`. Null on EOF (ctrl-D on empty input). Note ctrl-C returns an
/// *empty string*, not null — a cancelled line, not end of input.
fn readReplLine(prompt: [*:0]const u8) ?[*:0]u8 {
    if (comptime use_isocline) return ic.readline(prompt);

    const prompt_s = std.mem.span(prompt);
    _ = platform.write(1, prompt_s.ptr, prompt_s.len);

    const allocator = std.heap.c_allocator;
    var line: std.ArrayList(u8) = .empty;
    defer line.deinit(allocator);
    while (true) {
        var byte: [1]u8 = undefined;
        const n = platform.read(0, &byte, 1);
        if (n < 0) {
            if (platform.errno(n) == .INTR) continue;
            return null;
        }
        if (n == 0) {
            if (line.items.len == 0) return null; // EOF at line start
            break; // EOF terminates a final unterminated line
        }
        if (byte[0] == '\n') break;
        line.append(allocator, byte[0]) catch return null;
    }
    if (line.items.len > 0 and line.items[line.items.len - 1] == '\r') {
        _ = line.pop();
    }
    line.append(allocator, 0) catch return null;
    const owned = line.toOwnedSlice(allocator) catch return null;
    return @ptrCast(owned.ptr);
}

fn freeReplLine(line_ptr: [*:0]u8) void {
    if (comptime use_isocline) {
        ic.free(@ptrCast(line_ptr));
        return;
    }
    // Mirror of readReplLine's c_allocator ownership: reconstruct the
    // allocation (bytes incl. the NUL) and free it.
    const len = std.mem.len(line_ptr);
    std.heap.c_allocator.free(line_ptr[0 .. len + 1]);
}

const writeStdout = reporting.writeStdout;
const writeStderr = reporting.writeStderr;

fn isIdentBreak(c: u8) bool {
    return switch (c) {
        '(', ')', '\'', '`', ',', '"', ';', '#', '[', ']', ' ', '\t', '\n', '\r' => true,
        else => false,
    };
}

const repl_commands = [_][*:0]const u8{
    ",time ",  ",type ",       ",describe ", ",apropos ",
    ",env ",   ",profile ",    ",expand ",   ",gc",
    ",break ", ",breakpoints", ",delete ",   ",step ",
    ",help",   ",quit",        ",exit",      ",version",
    ",load ",  ",import ",     ",dis ",      ",condition ",
};

/// Identifier characters, for isocline's word splitting. The inverse of
/// `isIdentBreak`: `-`, `?`, `!`, `->` stay *inside* a Scheme identifier
/// (kaappi#676), which is why the default separator class will not do.
fn isIdentChar(s: [*c]const u8, len: c_long) callconv(.c) bool {
    if (len != 1) return true; // any multi-byte utf8 char is an identifier char
    return !isIdentBreak(s[0]);
}

/// Completes the word at the cursor. Registered with isocline, which strips
/// the word out of the buffer for us and splices the chosen completion back
/// in — the old linenoise callback had to rebuild the whole line by hand, and
/// silently dropped any candidate that made it longer than 1024 bytes.
fn completeWordCallback(cenv: ?*ic.CompletionEnv, prefix: [*c]const u8) callconv(.c) void {
    const vm = repl_vm orelse return;
    const word = if (prefix) |p| std.mem.span(@as([*:0]const u8, @ptrCast(p))) else return;

    var buf: [512:0]u8 = undefined;
    var it = vm.globals.keyIterator();
    while (it.next()) |key| {
        if (!std.mem.startsWith(u8, key.*, word)) continue;
        if (key.*.len >= buf.len) continue;
        @memcpy(buf[0..key.*.len], key.*);
        buf[key.*.len] = 0;
        if (!ic.addCompletion(cenv, &buf)) return; // isocline has enough
    }
}

/// Word-char rule for comma-command names: only a space ends the "word", so
/// the leading ',' is included and `ic.completeWord` deletes the whole typed
/// command (not just the part after it) before splicing in the replacement.
fn isCommandChar(s: [*c]const u8, len: c_long) callconv(.c) bool {
    if (len != 1) return true;
    return s[0] != ' ';
}

fn completeCommandNameCallback(cenv: ?*ic.CompletionEnv, prefix: [*c]const u8) callconv(.c) void {
    const word = if (prefix) |p| std.mem.span(@as([*:0]const u8, @ptrCast(p))) else return;
    for (&repl_commands) |cmd| {
        if (std.mem.startsWith(u8, std.mem.span(cmd), word)) {
            if (!ic.addCompletion(cenv, cmd)) return;
        }
    }
}

fn completionCallback(cenv: ?*ic.CompletionEnv, prefix: [*c]const u8) callconv(.c) void {
    const line = if (prefix) |p| std.mem.span(@as([*:0]const u8, @ptrCast(p))) else return;

    // Comma commands match against the whole line, not a word: the leading
    // ',' is a separator, so word completion would never see it.
    if (line.len > 0 and line[0] == ',') {
        // After the command word, complete a path — `,load ` and `,import `
        // take one. Previously nothing was offered here at all.
        if (std.mem.indexOfScalar(u8, line, ' ')) |sp| {
            const cmd = line[0 .. sp + 1];
            if (std.mem.eql(u8, cmd, ",load ") or std.mem.eql(u8, cmd, ",import ")) {
                ic.completeFilename(cenv, prefix, 0, null, ".scm;.sld;.sbc");
            }
            return;
        }
        // Route through completeWord (rather than addCompletion directly) so
        // isocline computes delete_before from the word boundary and replaces
        // the typed prefix instead of appending after it (kaappi#2224: TAB
        // after ",h" produced ",h,help").
        ic.completeWord(cenv, prefix, &completeCommandNameCallback, &isCommandChar);
        return;
    }

    ic.completeWord(cenv, prefix, &completeWordCallback, &isIdentChar);
}

// Colors are configured via theme (loaded from ~/.kaappi/config)

fn isSchemeKeyword(word: []const u8) bool {
    const keywords = [_][]const u8{
        "define",         "lambda",             "if",            "cond",
        "let",            "let*",               "letrec",        "letrec*",
        "begin",          "set!",               "and",           "or",
        "when",           "unless",             "case",          "do",
        "define-syntax",  "syntax-rules",       "quote",         "quasiquote",
        "unquote",        "unquote-splicing",   "import",        "export",
        "define-library", "define-record-type", "define-values", "guard",
        "delay",          "delay-force",        "parameterize",  "include",
        "include-ci",     "else",               "=>",            "let-values",
        "let*-values",    "case-lambda",        "let-syntax",    "letrec-syntax",
        "syntax-error",
    };
    for (keywords) |kw| {
        if (std.mem.eql(u8, word, kw)) return true;
    }
    return false;
}

/// Where a token ends, for the highlighter. This is `Reader.isDelimiter` — not
/// a copy of it — so the colors cannot disagree with the parse. In particular
/// `[` and `]` are *not* delimiters: the reader gives them no meaning (`0]` is
/// KP1002), so `[i` and `0]` are one atom each, and painting them like parens
/// advertised a structure neither the reader nor `repl_sexp` believes in
/// (kaappi#2216).
const isDelimiter = reader.Reader.isDelimiter;

fn isNumberLike(word: []const u8) bool {
    if (word.len == 0) return false;
    if (std.ascii.isDigit(word[0])) return true;
    if (word.len > 1 and (word[0] == '+' or word[0] == '-') and std.ascii.isDigit(word[1])) return true;
    // +inf.0, -inf.0, +nan.0, -nan.0
    if (std.mem.eql(u8, word, "+inf.0") or std.mem.eql(u8, word, "-inf.0") or
        std.mem.eql(u8, word, "+nan.0") or std.mem.eql(u8, word, "-nan.0")) return true;
    return false;
}

// Style names registered with isocline at REPL start (see `applyTheme`).
// `ic-bracematch` and `ic-prompt` are isocline's own names, redefined so the
// user's theme drives them too.
const style_keyword = "kaappi-keyword";
const style_string = "kaappi-string";
const style_number = "kaappi-number";
const style_comment = "kaappi-comment";
const style_boolean = "kaappi-boolean";
const style_paren = "kaappi-paren";

/// Hands each styled span to isocline, which records it in an attribute buffer
/// and renders it. Nothing is allocated and no escape sequence is written by
/// hand — which is what made the old emitter's allocator mismatch possible
/// (kaappi#234).
const IsoclineEmitter = struct {
    henv: ?*ic.HighlightEnv,
    fn emit(self: @This(), start: usize, end: usize, style: [*:0]const u8) void {
        if (end <= start) return;
        ic.highlight(self.henv, @intCast(start), @intCast(end - start), style);
    }
};

/// isocline highlighter. Unlike the linenoise callback this replaced, it gets
/// the whole form — every line of it — rather than the current physical line,
/// so the `accumulated_input` splice that used to reach back across the
/// continuation seam is gone. It also gets no cursor position: matching-paren
/// highlighting is isocline's own job now (`ic_enable_brace_matching`), styled
/// through `ic-bracematch`.
fn highlightCallback(henv: ?*ic.HighlightEnv, input_c: [*c]const u8, arg: ?*anyopaque) callconv(.c) void {
    _ = arg;
    if (!highlight_enabled) return;
    const input = if (input_c) |p| std.mem.span(@as([*:0]const u8, @ptrCast(p))) else return;
    scanHighlight(input, IsoclineEmitter{ .henv = henv });
}

/// Splits `input` into styled spans, calling `ctx.emit(start, end, style)` for
/// each. Separated from the isocline call so the token rules can be tested
/// without a terminal — `ic_highlight` needs a live editor to write into.
fn scanHighlight(input: []const u8, ctx: anytype) void {
    if (input.len == 0) return;

    var i: usize = 0;
    while (i < input.len) {
        const ch = input[i];
        const start = i;

        if (ch == ';') {
            while (i < input.len and input[i] != '\n') : (i += 1) {}
            ctx.emit(start, i, style_comment);
            continue;
        }

        if (ch == '#' and i + 1 < input.len and input[i + 1] == '|') {
            i += 2;
            var depth: u32 = 1;
            while (i < input.len and depth > 0) {
                if (input[i] == '#' and i + 1 < input.len and input[i + 1] == '|') {
                    depth += 1;
                    i += 2;
                } else if (input[i] == '|' and i + 1 < input.len and input[i + 1] == '#') {
                    depth -= 1;
                    i += 2;
                } else {
                    i += 1;
                }
            }
            ctx.emit(start, i, style_comment);
            continue;
        }

        // #; datum comment prefix
        if (ch == '#' and i + 1 < input.len and input[i + 1] == ';') {
            i += 2;
            ctx.emit(start, i, style_comment);
            continue;
        }

        // #!fold-case / #!no-fold-case directives
        if (ch == '#' and i + 1 < input.len and input[i + 1] == '!') {
            while (i < input.len and !isDelimiter(input[i])) : (i += 1) {}
            ctx.emit(start, i, style_comment);
            continue;
        }

        // #u8( bytevector literal
        if (ch == '#' and i + 3 < input.len and input[i + 1] == 'u' and input[i + 2] == '8' and input[i + 3] == '(') {
            i += 4;
            ctx.emit(start, i, style_paren);
            continue;
        }

        // #( vector literal
        if (ch == '#' and i + 1 < input.len and input[i + 1] == '(') {
            i += 2;
            ctx.emit(start, i, style_paren);
            continue;
        }

        if (ch == '"') {
            i += 1;
            while (i < input.len) {
                if (input[i] == '\\' and i + 1 < input.len) {
                    i += 2;
                    continue;
                }
                if (input[i] == '"') {
                    i += 1;
                    break;
                }
                i += 1;
            }
            ctx.emit(start, i, style_string);
            continue;
        }

        if (ch == '(' or ch == ')') {
            i += 1;
            ctx.emit(start, i, style_paren);
            continue;
        }

        if (ch == '#' and i + 1 < input.len and input[i + 1] == '\\') {
            i += 2;
            if (i < input.len) {
                const first = input[i];
                if ((first >= 'a' and first <= 'z') or (first >= 'A' and first <= 'Z')) {
                    while (i < input.len and ((input[i] >= 'a' and input[i] <= 'z') or (input[i] >= 'A' and input[i] <= 'Z'))) : (i += 1) {}
                } else {
                    i += 1;
                }
            }
            ctx.emit(start, i, style_number);
            continue;
        }

        // #true / #false (R7RS extended boolean)
        if (ch == '#' and i + 4 < input.len) {
            if (std.mem.startsWith(u8, input[i..], "#true") and (i + 5 >= input.len or isDelimiter(input[i + 5]))) {
                i += 5;
                ctx.emit(start, i, style_boolean);
                continue;
            }
            if (i + 5 < input.len and std.mem.startsWith(u8, input[i..], "#false") and (i + 6 >= input.len or isDelimiter(input[i + 6]))) {
                i += 6;
                ctx.emit(start, i, style_boolean);
                continue;
            }
        }

        // #t / #f (short boolean)
        if (ch == '#' and i + 1 < input.len and (input[i + 1] == 't' or input[i + 1] == 'f')) {
            if (i + 2 >= input.len or isDelimiter(input[i + 2])) {
                i += 2;
                ctx.emit(start, i, style_boolean);
                continue;
            }
        }

        // #b #o #x #d #e #i number prefix
        if (ch == '#' and i + 1 < input.len) {
            const next = input[i + 1];
            if (next == 'b' or next == 'o' or next == 'x' or next == 'd' or next == 'e' or next == 'i') {
                while (i < input.len and !isDelimiter(input[i])) : (i += 1) {}
                ctx.emit(start, i, style_number);
                continue;
            }
        }

        // ,@ unquote-splicing
        if (ch == ',' and i + 1 < input.len and input[i + 1] == '@') {
            i += 2;
            ctx.emit(start, i, style_keyword);
            continue;
        }

        if (ch == '\'' or ch == '`' or ch == ',') {
            i += 1;
            ctx.emit(start, i, style_keyword);
            continue;
        }

        // |...| pipe-quoted symbol: left unstyled, as before
        if (ch == '|') {
            i += 1;
            while (i < input.len and input[i] != '|') {
                if (input[i] == '\\' and i + 1 < input.len) i += 1;
                i += 1;
            }
            if (i < input.len) i += 1;
            continue;
        }

        if (!isDelimiter(ch)) {
            while (i < input.len and !isDelimiter(input[i])) : (i += 1) {}
            const word = input[start..i];
            if (isSchemeKeyword(word)) {
                ctx.emit(start, i, style_keyword);
            } else if (isNumberLike(word)) {
                ctx.emit(start, i, style_number);
            }
            continue;
        }

        i += 1;
    }
}

/// True when `src` is a truncated prefix of a form, so the REPL should show the
/// continuation prompt instead of evaluating.
///
/// This asks the reader rather than counting parens: `Reader.incomplete_input`
/// (kaappi#1893/#1920/#1940/#1945) makes every proper prefix of a datum report
/// `UnexpectedEof`, which is exactly the question the prompt needs answered. It
/// is the same scanner the file path uses, so `#;`, `#|…|#`, `#\(`, `|sym|`,
/// strings, and line comments cannot disagree between the two.
///
/// A hand-written counter lived here until it had drifted from the reader
/// twice — kaappi#358 (char literals, pipe-quoted symbols) and #542 (`#;`
/// scanned as a line comment). Both were cases of the prompt and the reader
/// disagreeing about where a datum ended; deriving the answer from the reader
/// removes the class rather than the instances.
///
/// Only "needs more input" continues. A genuine syntax error returns false so
/// the form is submitted and the reader reports it at the prompt, unchanged.
fn inputIncomplete(gc: *memory.GC, src: []const u8) bool {
    // `src` has had its terminating newline stripped, so to the reader it ends
    // mid-token: in incomplete-input mode a trailing `42` or `foo` cannot be
    // finalized, since more bytes could extend it. Pressing Enter *is* that
    // delimiter, so probe with it restored — without this every atom typed at
    // the prompt reports UnexpectedEof and strands the user on "  ... ".
    const probe = std.mem.concat(gc.allocator, u8, &.{ src, "\n" }) catch return false;
    defer gc.allocator.free(probe);

    var r = reader.Reader.init(gc, probe);
    r.incomplete_input = true;
    // The datums below are discarded; don't record spans for them.
    r.record_spans = false;
    defer r.deinit();
    while (true) {
        const datum = r.readDatumOrEof() catch |err| {
            return err == reader.ReadError.UnexpectedEof;
        };
        // null = nothing left but whitespace/comments/directives: complete.
        if (datum == null) return false;
    }
}

/// isocline's Enter handler (Kaappi patch 1, `vendor/isocline/PATCHES.md`).
/// Returning false keeps the editor open and adds a newline, so the answer to
/// "is this form finished?" comes from the reader — the same scanner that will
/// parse it a moment later.
fn isCompleteCallback(input_c: [*c]const u8, arg: ?*anyopaque) callconv(.c) bool {
    _ = arg;
    const vm = repl_vm orelse return true;
    const input = if (input_c) |p| std.mem.span(@as([*:0]const u8, @ptrCast(p))) else return true;

    // A comma command is a REPL directive, not Scheme; it never continues.
    const trimmed = std.mem.trimStart(u8, input, " \t\r\n");
    if (trimmed.len > 0 and trimmed[0] == ',') return true;

    return !inputIncomplete(vm.gc, input);
}

/// isocline's structural-edit handler (Kaappi patch 3,
/// `vendor/isocline/PATCHES.md`). isocline owns the keys; `repl_sexp` owns the
/// syntax and does the rewriting, on the whole buffer rather than one physical
/// line — which is why kaappi#2216 waited for the isocline migration.
///
/// Returning null declines: isocline leaves the input exactly as it was, which
/// is what a command that does not apply here should do.
fn sexpEditCallback(
    cmd: ic.c.ic_sexp_command_t,
    input_c: [*c]const u8,
    pos: [*c]c_long,
    arg: ?*anyopaque,
) callconv(.c) [*c]u8 {
    _ = arg;
    const input = if (input_c) |p| std.mem.span(@as([*:0]const u8, @ptrCast(p))) else return null;
    const cursor: usize = if (pos.* < 0) 0 else @intCast(pos.*);
    // An unknown command id can only mean isocline and `repl_sexp.Command`
    // have drifted; decline rather than guess (see `ic.setSexpEdit`).
    const command: repl_sexp.Command = switch (cmd) {
        ic.c.IC_SEXP_SLURP => .slurp,
        ic.c.IC_SEXP_BARF => .barf,
        ic.c.IC_SEXP_RAISE => .raise,
        ic.c.IC_SEXP_ROTATE => .rotate,
        else => return null,
    };

    const allocator = std.heap.c_allocator;
    const edit = repl_sexp.apply(allocator, command, input, cursor) orelse return null;
    defer allocator.free(edit.text);

    // isocline frees what it is handed, so the result has to come from its
    // allocator, not ours.
    const buf = ic.alloc(edit.text.len + 1) orelse return null;
    @memcpy(buf[0..edit.text.len], edit.text);
    buf[edit.text.len] = 0;
    pos.* = @intCast(edit.pos);
    return @ptrCast(buf);
}

/// Translate one of `config.Theme`'s SGR escapes into an isocline style string.
///
/// The theme stores escapes because linenoise was handed raw bytes; isocline
/// takes style *names* and does its own rendering, which is what lets it
/// measure widths correctly and downsample color for the terminal. `config.zig`
/// only ever produces `\x1b[<n>m` or `\x1b[1;<n>m` (from a color name, via
/// `colorToAnsi`), or the empty string for `none`, so the mapping is total.
/// Anything unrecognized yields "" — isocline's default, i.e. unstyled.
fn ansiToIcStyle(escape: []const u8, buf: []u8) [:0]const u8 {
    const empty: [:0]const u8 = "";
    if (escape.len < 4) return empty;
    if (!std.mem.startsWith(u8, escape, "\x1b[")) return empty;
    if (escape[escape.len - 1] != 'm') return empty;
    var body = escape[2 .. escape.len - 1];

    var bold = false;
    if (std.mem.startsWith(u8, body, "1;")) {
        bold = true;
        body = body[2..];
    }
    const code = std.fmt.parseInt(u8, body, 10) catch return empty;
    const name: []const u8 = switch (code) {
        30 => "ansi-black",
        31 => "ansi-maroon",
        32 => "ansi-green",
        33 => "ansi-olive",
        34 => "ansi-navy",
        35 => "ansi-purple",
        36 => "ansi-teal",
        37 => "ansi-silver",
        90 => "ansi-darkgray",
        91 => "ansi-red",
        92 => "ansi-lime",
        93 => "ansi-yellow",
        94 => "ansi-blue",
        95 => "ansi-fuchsia",
        96 => "ansi-aqua",
        97 => "ansi-white",
        else => return empty,
    };
    const s = if (bold)
        std.fmt.bufPrintZ(buf, "bold {s}", .{name}) catch return empty
    else
        std.fmt.bufPrintZ(buf, "{s}", .{name}) catch return empty;
    return s;
}

/// Register the configured theme with isocline. `ic-prompt` and `ic-bracematch`
/// are isocline's own style names, redefined here so the user's `repl.color.*`
/// settings reach the prompt and the matching-paren highlight that isocline now
/// draws itself.
fn applyTheme(t: config_mod.Theme) void {
    var buf: [32]u8 = undefined;
    const pairs = [_]struct { name: [*:0]const u8, escape: []const u8 }{
        .{ .name = style_keyword, .escape = t.keyword },
        .{ .name = style_string, .escape = t.string },
        .{ .name = style_number, .escape = t.number },
        .{ .name = style_comment, .escape = t.comment },
        .{ .name = style_boolean, .escape = t.boolean },
        .{ .name = style_paren, .escape = t.paren },
        .{ .name = "ic-bracematch", .escape = t.match_paren },
        .{ .name = "ic-prompt", .escape = t.prompt },
    };
    for (pairs) |p| {
        ic.styleDef(p.name, ansiToIcStyle(p.escape, &buf));
    }
}

pub fn repl(vm: *vm_mod.VM) !void {
    const allocator = vm.gc.allocator;

    const cfg = config_mod.load();
    theme = cfg.theme;
    highlight_enabled = cfg.highlight;

    writeStdout("Kaappi Scheme v" ++ version ++ "\n");
    writeStdout("Type ,help for commands, ,quit to exit.\n\n");

    terminal_width = getTerminalWidth();
    repl_vm = vm;

    var hist_path_buf: [512]u8 = undefined;
    if (comptime use_isocline) {
        ic.init(false);
        ic.enableMultiline(true);
        ic.enableMultilineIndent(true);
        // Kaappi's reader gives `[` and `]` no meaning (`0]` is KP1002), so
        // pairing them would highlight a match that the reader rejects.
        ic.enableBraceMatching(true);
        ic.setMatchingBraces("()");
        // Auto-closing a paren makes every buffer balanced, which would make
        // `isCompleteCallback` submit the moment an opening paren is typed.
        ic.enableBraceInsertion(false);
        ic.enableHighlight(highlight_enabled);
        ic.enableHint(false); // no hint callback is wired up
        // Opt-in SGR mouse tracking: click inside the input to move the edit
        // cursor (kaappi#2264). Off by default — while tracking is on, the
        // terminal stops reporting drag-to-select to the application.
        ic.enableMouse(cfg.mouse);
        applyTheme(cfg.theme);

        ic.setIsComplete(&isCompleteCallback, null);
        ic.setSexpEdit(&sexpEditCallback, null);
        ic.setCompleter(&completionCallback, null);
        if (highlight_enabled) ic.setHighlighter(&highlightCallback, null);
        // The prompt text carries no escapes: isocline measures it to place the
        // cursor, and styles it via `ic-prompt`. Continuation lines are indented
        // under it rather than prefixed with "  ... ".
        ic.setPromptMarker("", null);

        const kaappi_paths = @import("kaappi_paths.zig");
        var home_buf: [256]u8 = undefined;
        if (kaappi_paths.getHome(&home_buf)) |kaappi_home| {
            if (std.fmt.bufPrintZ(hist_path_buf[0..500], "{s}", .{kaappi_home})) |dir| {
                _ = platform.mkdir(dir, 0o755);
                if (std.fmt.bufPrintZ(&hist_path_buf, "{s}/history", .{kaappi_home})) |path| {
                    // isocline loads, appends, and saves on every submit — a
                    // crash no longer loses the session (the old code saved
                    // only at exit).
                    ic.setHistory(path, cfg.history_length);
                } else |_| {}
            } else |_| {}
        }
    }

    // Prompt strings. Under isocline these stay unstyled (see above); the
    // fallback reader embeds the color itself since nothing else will.
    var primary_prompt_buf: [128:0]u8 = @splat(0);
    var cont_prompt_buf: [128:0]u8 = @splat(0);
    const primary_prompt: [*:0]const u8 = blk: {
        if (comptime use_isocline) break :blk cfg.prompt();
        const color = cfg.theme.prompt;
        const text = cfg.prompt_buf[0..cfg.prompt_len];
        const reset = cfg.theme.reset;
        const total = color.len + text.len + reset.len;
        if (total >= primary_prompt_buf.len) break :blk cfg.prompt();
        @memcpy(primary_prompt_buf[0..color.len], color);
        @memcpy(primary_prompt_buf[color.len..][0..text.len], text);
        @memcpy(primary_prompt_buf[color.len + text.len ..][0..reset.len], reset);
        primary_prompt_buf[total] = 0;
        break :blk @ptrCast(&primary_prompt_buf);
    };
    const continuation_prompt: [*:0]const u8 = blk: {
        const color = cfg.theme.continuation;
        const text = "  ... ";
        const reset = cfg.theme.reset;
        const total = color.len + text.len + reset.len;
        if (total >= cont_prompt_buf.len) break :blk "  ... ";
        @memcpy(cont_prompt_buf[0..color.len], color);
        @memcpy(cont_prompt_buf[color.len..][0..text.len], text);
        @memcpy(cont_prompt_buf[color.len + text.len ..][0..reset.len], reset);
        cont_prompt_buf[total] = 0;
        break :blk @ptrCast(&cont_prompt_buf);
    };

    var input_buf: std.ArrayList(u8) = .empty;
    defer input_buf.deinit(allocator);

    while (true) {
        // Under isocline `input_buf` is only ever a whole form — the editor
        // handles continuation internally, so it is empty at the top of every
        // iteration and the continuation prompt below is the fallback's.
        const prompt: [*:0]const u8 = if (input_buf.items.len > 0) continuation_prompt else primary_prompt;
        const line_ptr = readReplLine(prompt) orelse {
            // Null means EOF (ctrl-D on empty input). ctrl-C returns an empty
            // string instead, which falls through to the blank-input `continue`
            // below and redraws the prompt (kaappi#742).
            if (input_buf.items.len > 0) {
                input_buf.clearRetainingCapacity();
                writeStdout("\n");
                continue;
            }
            break;
        };
        defer freeReplLine(line_ptr);

        const line = std.mem.span(line_ptr);
        const trimmed = std.mem.trim(u8, line, " \t\r\n");

        if (input_buf.items.len == 0 and trimmed.len == 0) continue;
        if (input_buf.items.len == 0 and std.mem.eql(u8, trimmed, "(exit)")) break;

        if (comptime !use_isocline) {
            // Pasted multi-line text arrives in one read here without having
            // been drawn; isocline renders its own buffer, so echoing it there
            // would print the form twice.
            if (std.mem.indexOfScalar(u8, line, '\n') != null and input_buf.items.len == 0) {
                writeStdout(line);
                writeStdout("\n");
            }
        }

        if (input_buf.items.len > 0) {
            input_buf.append(allocator, '\n') catch continue;
        }
        input_buf.appendSlice(allocator, line) catch continue;

        // isocline already asked `isCompleteCallback` before returning, so the
        // buffer is a finished form. The fallback reads one raw line at a time
        // and has to accumulate until it is.
        if (comptime !use_isocline) {
            if (inputIncomplete(vm.gc, input_buf.items)) continue;
        }

        const full_input = input_buf.items;
        const debug_trimmed = std.mem.trim(u8, full_input, " \t\r\n");

        // Debug commands (comma-prefixed)
        if (std.mem.startsWith(u8, debug_trimmed, ",break ")) {
            const bp_name_src = std.mem.trim(u8, debug_trimmed[7..], " ");
            if (vm.breakpoint_count >= 16) {
                writeStdout("Too many breakpoints (max 16)\n");
                input_buf.clearRetainingCapacity();
                continue;
            }
            const bp_name = allocator.dupe(u8, bp_name_src) catch continue;
            vm.breakpoints[vm.breakpoint_count] = .{ .name = bp_name };
            vm.breakpoint_count += 1;
            vm.debug_mode = true;
            vm.step_mode = .continue_to_break;
            writeStdout("Breakpoint set on ");
            writeStdout(bp_name);
            writeStdout("\n");
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",condition ")) {
            const rest = std.mem.trim(u8, debug_trimmed[11..], " ");
            if (std.mem.indexOfScalar(u8, rest, ' ')) |space| {
                const id_str = rest[0..space];
                const expr = std.mem.trim(u8, rest[space + 1 ..], " ");
                const id = std.fmt.parseInt(usize, id_str, 10) catch {
                    writeStdout("Usage: ,condition <id> <expr>\n");
                    input_buf.clearRetainingCapacity();
                    continue;
                };
                if (id < vm.breakpoint_count) {
                    const owned_expr = allocator.dupe(u8, expr) catch continue;
                    if (vm.breakpoints[id].condition) |old_cond| allocator.free(old_cond);
                    vm.breakpoints[id].condition = owned_expr;
                    writeStdout("Condition set\n");
                } else {
                    writeStdout("Invalid breakpoint ID\n");
                }
            } else {
                writeStdout("Usage: ,condition <id> <expr>\n");
            }
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",breakpoints")) {
            for (vm.breakpoints[0..vm.breakpoint_count], 0..) |bp, idx| {
                var dbuf: [64]u8 = undefined;
                const s = std.fmt.bufPrint(&dbuf, "  [{d}] {s}", .{ idx, bp.name }) catch "";
                writeStdout(s);
                if (bp.condition) |cond| {
                    writeStdout(" if ");
                    writeStdout(cond);
                }
                writeStdout("\n");
            }
            if (vm.breakpoint_count == 0) {
                writeStdout("  (no breakpoints)\n");
            }
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",delete all")) {
            for (vm.breakpoints[0..vm.breakpoint_count]) |bp| {
                allocator.free(bp.name);
                if (bp.condition) |cond| allocator.free(cond);
            }
            vm.breakpoint_count = 0;
            vm.debug_mode = false;
            vm.step_mode = .none;
            writeStdout("All breakpoints deleted\n");
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",step ")) {
            const step_expr = debug_trimmed[6..];
            const saved_debug = vm.debug_mode;
            const saved_step = vm.step_mode;
            vm.debug_mode = true;
            vm.step_mode = .step;
            evalInput(vm, allocator, step_expr);
            vm.debug_mode = saved_debug;
            vm.step_mode = saved_step;
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",time ")) {
            const time_expr = debug_trimmed[6..];
            const t0 = platform.monotonicNs();
            evalInput(vm, allocator, time_expr);
            const t1 = platform.monotonicNs();
            const secs = @as(f64, @floatFromInt(t1 - t0)) / 1_000_000_000.0;
            var tbuf: [64]u8 = undefined;
            const ts_str = std.fmt.bufPrint(&tbuf, "; {d:.3} seconds\n", .{secs}) catch "; ? seconds\n";
            writeStdout(ts_str);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",profile ")) {
            const profile_expr = debug_trimmed[9..];
            reporting.resetProfileCounters(vm.gc);
            vm.profile_mode = true;
            evalInput(vm, allocator, profile_expr);
            vm.profile_mode = false;
            reporting.printProfileReport(vm.gc);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",gc")) {
            reporting.printGcStats(vm.gc);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",quit") or std.mem.eql(u8, debug_trimmed, ",exit")) {
            break;
        }
        if (std.mem.eql(u8, debug_trimmed, ",version")) {
            writeStdout("Kaappi Scheme v" ++ version ++ "\n");
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",load ")) {
            const load_path = std.mem.trim(u8, debug_trimmed[6..], " ");
            if (load_path.len == 0) {
                writeStderr(",load requires a file path\n");
            } else {
                var load_buf: [1024]u8 = undefined;
                const load_expr = std.fmt.bufPrint(&load_buf, "(load \"{s}\")", .{load_path}) catch {
                    writeStderr("path too long\n");
                    input_buf.clearRetainingCapacity();
                    continue;
                };
                evalInput(vm, allocator, load_expr);
            }
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",import ")) {
            const import_expr = debug_trimmed[8..];
            var ir = reader.Reader.init(vm.gc, import_expr);
            defer ir.deinit();
            var import_list = types.NIL;
            var import_root = import_list;
            vm.gc.pushRoot(&import_root);
            var read_ok = true;
            while (ir.hasMore() catch false) {
                var datum = ir.readDatum() catch {
                    writeStderr("read error in import spec\n");
                    read_ok = false;
                    break;
                };
                vm.gc.pushRoot(&datum);
                var pair = vm.gc.allocPair(datum, types.NIL) catch {
                    vm.gc.popRoot();
                    writeStderr("out of memory\n");
                    read_ok = false;
                    break;
                };
                vm.gc.popRoot();
                if (import_root == types.NIL) {
                    import_root = pair;
                    import_list = pair;
                } else {
                    types.toObject(import_list).as(types.Pair).cdr = pair;
                    import_list = pair;
                }
                _ = &pair;
            }
            if (read_ok and import_root != types.NIL) {
                _ = vm_library.handleImport(vm, import_root) catch {
                    const detail = vm.getErrorDetail();
                    if (detail.len > 0) {
                        writeStderr("import error: ");
                        writeStderr(detail);
                        writeStderr("\n");
                    } else {
                        writeStderr("import error\n");
                    }
                };
            }
            vm.gc.popRoot();
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",dis ")) {
            const dis_expr = debug_trimmed[5..];
            var dis_buf: [1024]u8 = undefined;
            const dis_call = std.fmt.bufPrint(&dis_buf, "(disassemble {s})", .{dis_expr}) catch {
                writeStderr("expression too long\n");
                input_buf.clearRetainingCapacity();
                continue;
            };
            evalInput(vm, allocator, dis_call);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",help")) {
            writeStdout(
                \\Commands:
                \\  ,help             Show this message
                \\  ,quit             Exit the REPL
                \\
                \\ -- Evaluation:
                \\  ,time <expr>      Measure execution time
                \\  ,type <expr>      Show result type
                \\  ,expand <expr>    Show macro expansion
                \\  ,profile <expr>   Profile timing, calls, and allocations
                \\  ,dis <expr>       Disassemble a procedure
                \\
                \\ -- Inspection:
                \\  ,describe <sym>   Show procedure arity and type
                \\  ,apropos <str>    Search bindings by substring
                \\  ,env [prefix]     List bindings (optionally filtered by prefix)
                \\
                \\ -- Debugging:
                \\  ,break <name>     Set breakpoint on function
                \\  ,breakpoints      List active breakpoints
                \\  ,delete all       Clear all breakpoints
                \\  ,step <expr>      Evaluate with single-stepping
                \\  ,condition <id> <expr>  Set breakpoint condition
                \\
                \\ -- Structural editing (moves a paren, not a character):
                \\  alt-shift-S       Slurp: pull the next datum into the form
                \\  alt-shift-B       Barf: push the last datum out of the form
                \\  alt-shift-R       Raise: replace the form with the datum at point
                \\  alt-y             Rotate the form's arguments
                \\  F1                All editor keys
                \\
                \\ -- System:
                \\  ,gc               Show GC statistics
                \\  ,version          Show Kaappi version
                \\  ,load <file>      Load and run a Scheme file
                \\  ,import <lib>     Import a library (e.g. ,import (srfi 1))
                \\
                \\The variable _ holds the last result.
                \\
            );
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",type ")) {
            const type_expr = debug_trimmed[6..];
            evalInputTyped(vm, allocator, type_expr, .show_type);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",describe ")) {
            const sym_name = std.mem.trim(u8, debug_trimmed[10..], " ");
            describeSymbol(vm, allocator, sym_name);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",apropos ")) {
            const needle = std.mem.trim(u8, debug_trimmed[9..], " ");
            var env_count: usize = 0;
            var git3 = vm.globals.keyIterator();
            while (git3.next()) |key| {
                if (needle.len == 0 or containsSubstring(key.*, needle)) {
                    writeStdout("  ");
                    writeStdout(key.*);
                    writeStdout("\n");
                    env_count += 1;
                }
            }
            var cbuf2: [64]u8 = undefined;
            const cs2 = std.fmt.bufPrint(&cbuf2, "; {d} matches\n", .{env_count}) catch "\n";
            writeStdout(cs2);
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.startsWith(u8, debug_trimmed, ",expand ")) {
            const expand_src = debug_trimmed[8..];
            var er = reader.Reader.init(vm.gc, expand_src);
            defer er.deinit();
            const expr = er.readDatum() catch {
                writeStderr("read error\n");
                input_buf.clearRetainingCapacity();
                continue;
            };
            if (types.isPair(expr) and types.isSymbol(types.car(expr))) {
                const ename = types.symbolName(types.car(expr));
                if (vm.macros.get(ename)) |transformer| {
                    const expanded = expander.expandMacro(vm.gc, expr, transformer, vm.globals, &vm.macros, .{}) catch {
                        writeStderr("expansion error\n");
                        input_buf.clearRetainingCapacity();
                        continue;
                    };
                    var expanded_stripped = expanded;
                    if (expander.isUsertextPair(expanded_stripped)) expanded_stripped = expander.unwrapUsertext(expanded_stripped);
                    if (types.isPair(expanded_stripped) or types.isVector(expanded_stripped)) expander.stripUsertextMarkers(vm.gc, expanded_stripped);
                    const s = printer.valueToString(allocator, expanded_stripped, .write) catch "";
                    defer if (s.len > 0) allocator.free(s);
                    writeStdout(s);
                    writeStdout("\n");
                } else {
                    writeStderr("not a macro: ");
                    writeStderr(ename);
                    writeStderr("\n");
                }
            } else {
                writeStderr("not a macro invocation\n");
            }
            input_buf.clearRetainingCapacity();
            continue;
        }
        if (std.mem.eql(u8, debug_trimmed, ",env") or std.mem.startsWith(u8, debug_trimmed, ",env ")) {
            const prefix = if (debug_trimmed.len > 5) std.mem.trim(u8, debug_trimmed[5..], " ") else "";
            var env_count: usize = 0;
            var git2 = vm.globals.keyIterator();
            while (git2.next()) |key| {
                if (prefix.len == 0 or std.mem.startsWith(u8, key.*, prefix)) {
                    writeStdout("  ");
                    writeStdout(key.*);
                    writeStdout("\n");
                    env_count += 1;
                }
            }
            var cbuf: [64]u8 = undefined;
            const cs = std.fmt.bufPrint(&cbuf, "; {d} bindings\n", .{env_count}) catch "\n";
            writeStdout(cs);
            input_buf.clearRetainingCapacity();
            continue;
        }

        // Catch-all for unrecognized or incomplete comma commands
        if (debug_trimmed.len > 0 and debug_trimmed[0] == ',') {
            const usage = getCommandUsage(debug_trimmed);
            if (usage) |msg| {
                writeStderr(msg);
            } else {
                writeStderr("unknown command: ");
                const end = std.mem.indexOfScalar(u8, debug_trimmed, ' ') orelse debug_trimmed.len;
                writeStderr(debug_trimmed[0..end]);
                writeStderr("\nType ,help for available commands.\n");
            }
            input_buf.clearRetainingCapacity();
            continue;
        }

        // isocline records and persists each submitted form itself, escaping
        // embedded newlines on the way to disk — so a multi-line entry comes
        // back as one editable entry rather than the old flattened line
        // (kaappi#821). Nothing to add here.
        evalInputTyped(vm, allocator, full_input, .store_last);

        input_buf.clearRetainingCapacity();
    }

    repl_vm = null;
}

fn getCommandUsage(input: []const u8) ?[]const u8 {
    const cmd = blk: {
        const end = std.mem.indexOfScalar(u8, input, ' ') orelse input.len;
        break :blk input[0..end];
    };
    const commands = [_]struct { name: []const u8, usage: []const u8 }{
        .{ .name = ",time", .usage = "usage: ,time <expr>\n" },
        .{ .name = ",type", .usage = "usage: ,type <expr>\n" },
        .{ .name = ",describe", .usage = "usage: ,describe <symbol>\n" },
        .{ .name = ",apropos", .usage = "usage: ,apropos <string>\n" },
        .{ .name = ",expand", .usage = "usage: ,expand <expr>\n" },
        .{ .name = ",profile", .usage = "usage: ,profile <expr>\n" },
        .{ .name = ",step", .usage = "usage: ,step <expr>\n" },
        .{ .name = ",break", .usage = "usage: ,break <name>\n" },
        .{ .name = ",load", .usage = "usage: ,load <file>\n" },
        .{ .name = ",import", .usage = "usage: ,import <lib>  (e.g. ,import (srfi 1))\n" },
        .{ .name = ",dis", .usage = "usage: ,dis <expr>\n" },
        .{ .name = ",delete", .usage = "usage: ,delete all\n" },
        .{ .name = ",condition", .usage = "usage: ,condition <id> <expr>\n" },
    };
    for (&commands) |entry| {
        if (std.mem.eql(u8, cmd, entry.name)) return entry.usage;
    }
    return null;
}

fn containsSubstring(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        if (std.mem.eql(u8, haystack[i..][0..needle.len], needle)) return true;
    }
    return false;
}

const getTypeName = types.typeName;

fn describeSymbol(vm: *vm_mod.VM, allocator: std.mem.Allocator, name: []const u8) void {
    const val_opt = vm.globals.get(name);
    if (val_opt == null) {
        writeStdout("  not found: ");
        writeStdout(name);
        writeStdout("\n");
        return;
    }
    const val = val_opt.?;
    writeStdout("  ");
    writeStdout(name);
    writeStdout("\n    type: ");
    writeStdout(getTypeName(val));
    writeStdout("\n");

    if (types.isPointer(val)) {
        const obj = types.toObject(val);
        if (obj.tag == .native_fn) {
            const nfn = obj.as(types.NativeFn);
            var abuf: [64]u8 = undefined;
            switch (nfn.arity) {
                .exact => |n| {
                    const s = std.fmt.bufPrint(&abuf, "    arity: {d}\n", .{n}) catch "";
                    writeStdout(s);
                },
                .variadic => |min| {
                    const s = std.fmt.bufPrint(&abuf, "    arity: {d}+\n", .{min}) catch "";
                    writeStdout(s);
                },
            }
        } else if (obj.tag == .closure) {
            const cls = obj.as(types.Closure);
            const func = cls.func;
            var abuf: [128]u8 = undefined;
            const s = std.fmt.bufPrint(&abuf, "    arity: {d}, locals: {d}\n", .{ func.arity, func.locals_count }) catch "";
            writeStdout(s);
            if (func.source_name) |src| {
                writeStdout("    source: ");
                writeStdout(src);
                var lbuf: [32]u8 = undefined;
                const ls = std.fmt.bufPrint(&lbuf, ":{d}\n", .{func.source_line}) catch "\n";
                writeStdout(ls);
            }
        } else if (obj.tag == .transformer) {
            writeStdout("    (syntax transformer)\n");
        }
    }
    _ = allocator;
}

const EvalMode = enum { normal, store_last, show_type };

// Multiple values print one per line, matching other Scheme REPLs
// (Chez, Guile, Racket, Chibi). Void values print nothing.
fn printValuesLines(allocator: std.mem.Allocator, values: []const types.Value) void {
    for (values) |val| {
        if (val == types.VOID) continue;
        const s = printer.prettyPrint(allocator, val, terminal_width) catch
            (printer.valueToString(allocator, val, .write) catch continue);
        defer allocator.free(s);
        writeStdout(s);
        writeStdout("\n");
    }
}

fn evalInputTyped(vm: *vm_mod.VM, allocator: std.mem.Allocator, input: []const u8, mode: EvalMode) void {
    evalInputInner(vm, allocator, input, mode);
}

fn evalInput(vm: *vm_mod.VM, allocator: std.mem.Allocator, input: []const u8) void {
    evalInputInner(vm, allocator, input, .normal);
}

/// `inputIncomplete` over a throwaway GC. Split so each case reads as the two
/// lines a user would actually type.
fn expectIncomplete(src: []const u8, want: bool) !void {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    try std.testing.expectEqual(want, inputIncomplete(&gc, src));
}

test "inputIncomplete — balanced form is complete" {
    try expectIncomplete("(+ 1 2)", false);
    try expectIncomplete("42", false);
    try expectIncomplete("", false);
}

test "inputIncomplete — a bare atom submits" {
    // The reader's incomplete-input mode will not finalize a token that ends
    // at end-of-buffer, so without the probe's restored newline each of these
    // reports UnexpectedEof and hangs the prompt forever.
    try expectIncomplete("42", false);
    try expectIncomplete("foo", false);
    try expectIncomplete("#t", false);
    try expectIncomplete("\"done\"", false);
    try expectIncomplete("#\\a", false);
    try expectIncomplete("1.5e3", false);
    try expectIncomplete("#x1f", false);
}

test "inputIncomplete — open form continues" {
    try expectIncomplete("(define (f x)", true);
    try expectIncomplete("(define (f x)\n  (+ x 1)", true);
    try expectIncomplete("(define (f x)\n  (+ x 1))", false);
}

test "inputIncomplete — brackets are not list syntax here" {
    // kaappi's reader gives `[` and `]` no special meaning (KP1002 on `0]`),
    // so a bracket binding is a syntax error, not an unfinished form — it must
    // submit and be reported, not sit at the continuation prompt.
    try expectIncomplete("(let loop ([i 0]) i)", false);
    // The enclosing parens still govern continuation.
    try expectIncomplete("(let loop ((i 0))", true);
    try expectIncomplete("(let loop ((i 0)) i)", false);
}

test "inputIncomplete — datum comment spanning lines (kaappi#542)" {
    try expectIncomplete("#;(a", true);
    try expectIncomplete("#;(a\nb) (+ 7 7)", false);
}

test "inputIncomplete — block comment spanning lines" {
    try expectIncomplete("(+ 1 #| still", true);
    try expectIncomplete("(+ 1 #| gone |# 2)", false);
}

test "inputIncomplete — line comment does not swallow the close (kaappi#821)" {
    try expectIncomplete("(+ 1 ; one", true);
    try expectIncomplete("(+ 1 ; one\n2)", false);
    // A comment alone is trivia, not an unfinished form.
    try expectIncomplete("; just a comment", false);
}

test "inputIncomplete — char literals and pipe symbols (kaappi#358)" {
    try expectIncomplete("(char=? #\\( x)", false);
    try expectIncomplete("(char=? #\\) x)", false);
    try expectIncomplete("(list '|foo(bar|)", false);
    try expectIncomplete("(list '|foo(bar", true);
}

test "inputIncomplete — unterminated string continues" {
    try expectIncomplete("(display \"ab", true);
    try expectIncomplete("(display \"ab\ncd\")", false);
}

test "inputIncomplete — several datums on one line" {
    try expectIncomplete("(+ 1 2) (+ 3 4)", false);
    try expectIncomplete("(+ 1 2) (+ 3", true);
}

test "inputIncomplete — a syntax error submits rather than hanging" {
    // Extra close paren: not "needs more input". Submitting lets the reader
    // report it; continuing would strand the user at the "  ... " prompt.
    try expectIncomplete("(+ 1 2))", false);
}

test "inputIncomplete — probe records no source spans" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    try std.testing.expectEqual(@as(usize, 0), gc.source_spans.count());
    _ = inputIncomplete(&gc, "(define (f x) (+ x 1))");
    try std.testing.expectEqual(@as(usize, 0), gc.source_spans.count());
}

/// Collects the spans `scanHighlight` emits, so the token rules can be checked
/// without a live isocline editor.
const SpanCollector = struct {
    styles: *std.ArrayList([]const u8),
    starts: *std.ArrayList(usize),
    ends: *std.ArrayList(usize),
    fn emit(self: @This(), start: usize, end: usize, style: [*:0]const u8) void {
        if (end <= start) return;
        self.styles.append(std.testing.allocator, std.mem.span(style)) catch {};
        self.starts.append(std.testing.allocator, start) catch {};
        self.ends.append(std.testing.allocator, end) catch {};
    }
};

/// Assert that `input[expect_start..expect_end]` is styled `style`.
fn expectSpan(input: []const u8, expect_start: usize, expect_end: usize, style: []const u8) !void {
    var styles: std.ArrayList([]const u8) = .empty;
    var starts: std.ArrayList(usize) = .empty;
    var ends: std.ArrayList(usize) = .empty;
    defer styles.deinit(std.testing.allocator);
    defer starts.deinit(std.testing.allocator);
    defer ends.deinit(std.testing.allocator);
    scanHighlight(input, SpanCollector{ .styles = &styles, .starts = &starts, .ends = &ends });
    for (styles.items, starts.items, ends.items) |st, a, b| {
        if (a == expect_start and b == expect_end and std.mem.eql(u8, st, style)) return;
    }
    std.debug.print("no {s} span at [{d},{d}) in \"{s}\"; got:\n", .{ style, expect_start, expect_end, input });
    for (styles.items, starts.items, ends.items) |st, a, b| {
        std.debug.print("  [{d},{d}) {s} = \"{s}\"\n", .{ a, b, st, input[a..b] });
    }
    return error.TestUnexpectedResult;
}

/// Assert no span of `style` covers any of `input`.
fn expectNoStyle(input: []const u8, style: []const u8) !void {
    var styles: std.ArrayList([]const u8) = .empty;
    var starts: std.ArrayList(usize) = .empty;
    var ends: std.ArrayList(usize) = .empty;
    defer styles.deinit(std.testing.allocator);
    defer starts.deinit(std.testing.allocator);
    defer ends.deinit(std.testing.allocator);
    scanHighlight(input, SpanCollector{ .styles = &styles, .starts = &starts, .ends = &ends });
    for (styles.items) |st| {
        if (std.mem.eql(u8, st, style)) return error.TestUnexpectedResult;
    }
}

test "scanHighlight — keywords and parens" {
    try expectSpan("(define x 1)", 0, 1, style_paren);
    try expectSpan("(define x 1)", 1, 7, style_keyword);
    try expectSpan("(define x 1)", 11, 12, style_paren);
}

test "scanHighlight — spans a multi-line form" {
    // The whole form reaches the highlighter now, not just one line, so an
    // offset past the newline must still resolve.
    const src = "(define (f x)\n  (+ x 1))";
    try expectSpan(src, 1, 7, style_keyword);
    try expectSpan(src, 16, 17, style_paren);
}

test "scanHighlight — string and comment" {
    try expectSpan("(display \"hi\")", 9, 13, style_string);
    try expectSpan("(+ 1) ; note", 6, 12, style_comment);
    try expectSpan("(+ #| b |# 1)", 3, 10, style_comment);
}

test "scanHighlight — a comment ends at the newline, not the buffer" {
    const src = "; one\n(+ 1 2)";
    try expectSpan(src, 0, 5, style_comment);
    try expectSpan(src, 6, 7, style_paren);
}

test "scanHighlight — #true/#false get boolean style" {
    try expectSpan("#true", 0, 5, style_boolean);
    try expectSpan("#false", 0, 6, style_boolean);
    try expectSpan("#t", 0, 2, style_boolean);
}

test "scanHighlight — #trueish is not boolean" {
    try expectNoStyle("#trueish", style_boolean);
}

test "scanHighlight — vector and bytevector open" {
    try expectSpan("#(1 2)", 0, 2, style_paren);
    try expectSpan("#u8(1 2)", 0, 4, style_paren);
}

test "scanHighlight — radix prefixes are numbers" {
    try expectSpan("#xff", 0, 4, style_number);
    try expectSpan("#b101", 0, 5, style_number);
    try expectSpan("#o77", 0, 4, style_number);
    try expectSpan("#e1.5", 0, 5, style_number);
}

test "scanHighlight — quote forms are keywords" {
    try expectSpan(",@x", 0, 2, style_keyword);
    try expectSpan("'x", 0, 1, style_keyword);
    try expectSpan("`x", 0, 1, style_keyword);
}

test "scanHighlight — datum comment and directive" {
    try expectSpan("#; foo", 0, 2, style_comment);
    try expectSpan("#!fold-case", 0, 11, style_comment);
}

test "scanHighlight — |symbol| is not a keyword" {
    try expectNoStyle("|define|", style_keyword);
}

test "scanHighlight — char literal parens do not become parens" {
    try expectSpan("#\\(", 0, 3, style_number);
    try expectNoStyle("#\\(", style_paren);
}

test "scanHighlight — brackets are not parens (kaappi#2216)" {
    // The reader pairs neither, `setMatchingBraces` is given "()" alone, and
    // `repl_sexp` treats them as ordinary atom characters. The highlighter
    // used to paint them anyway.
    try expectNoStyle("[i 0]", style_paren);
    try expectSpan("(let loop ([i 0]) i)", 0, 1, style_paren);
    try expectSpan("(let loop ([i 0]) i)", 10, 11, style_paren);
}

test "scanHighlight — infinities and nan are numbers" {
    try expectSpan("+inf.0", 0, 6, style_number);
    try expectSpan("-nan.0", 0, 6, style_number);
}

test "ansiToIcStyle — every colour config.zig emits maps to an isocline name" {
    var buf: [32]u8 = undefined;
    const cases = [_]struct { escape: []const u8, want: []const u8 }{
        .{ .escape = "\x1b[30m", .want = "ansi-black" },
        .{ .escape = "\x1b[31m", .want = "ansi-maroon" },
        .{ .escape = "\x1b[32m", .want = "ansi-green" },
        .{ .escape = "\x1b[33m", .want = "ansi-olive" },
        .{ .escape = "\x1b[34m", .want = "ansi-navy" },
        .{ .escape = "\x1b[35m", .want = "ansi-purple" },
        .{ .escape = "\x1b[36m", .want = "ansi-teal" },
        .{ .escape = "\x1b[37m", .want = "ansi-silver" },
        .{ .escape = "\x1b[90m", .want = "ansi-darkgray" },
        .{ .escape = "\x1b[91m", .want = "ansi-red" },
        .{ .escape = "\x1b[92m", .want = "ansi-lime" },
        .{ .escape = "\x1b[93m", .want = "ansi-yellow" },
        .{ .escape = "\x1b[94m", .want = "ansi-blue" },
        .{ .escape = "\x1b[95m", .want = "ansi-fuchsia" },
        .{ .escape = "\x1b[96m", .want = "ansi-aqua" },
        .{ .escape = "\x1b[97m", .want = "ansi-white" },
        // The `1;` form config.zig produces for a `bold <colour>` setting.
        .{ .escape = "\x1b[1;30m", .want = "bold ansi-black" },
        .{ .escape = "\x1b[1;93m", .want = "bold ansi-yellow" },
        .{ .escape = "\x1b[1;90m", .want = "bold ansi-darkgray" },
    };
    for (cases) |c| {
        try std.testing.expectEqualStrings(c.want, ansiToIcStyle(c.escape, &buf));
    }
}

test "ansiToIcStyle — unrecognized input is unstyled, never a wrong style" {
    var buf: [32]u8 = undefined;
    const rejects = [_][]const u8{
        "", // what `none` produces
        "\x1b[m", // shorter than any real escape
        "\x1b[0m", // reset: not a foreground colour
        "\x1b[39m", // default foreground: no isocline name for it
        "\x1b[42m", // a background colour, not a foreground one
        "0;31m", // no CSI introducer
        "\x1b[31", // no terminator
        "\x1b[xxm", // body is not a number
        "\x1b[1;xm", // ...nor after the bold prefix
        "\x1b[999m", // out of range for the u8 parse
    };
    for (rejects) |r| {
        try std.testing.expectEqualStrings("", ansiToIcStyle(r, &buf));
    }
}

test "ansiToIcStyle — both built-in themes round-trip through applyTheme's buffer" {
    // The coupling check, and the reason this function is worth testing at all:
    // it is the only bridge between config.zig's SGR escapes and isocline's
    // style names, and every failure mode returns "" — which renders unstyled
    // with nothing to notice. If config.zig ever changes how it spells a
    // colour, or a style name outgrows applyTheme's [32]u8 (bufPrintZ failing
    // is also just ""), all eight styles would quietly go plain. Assert the
    // real themes map instead of trusting hand-written escapes to stay in step.
    var buf: [32]u8 = undefined;
    for ([_]config_mod.Theme{ config_mod.Theme.dark, config_mod.Theme.light }) |t| {
        // Exactly the eight fields applyTheme feeds through.
        const escapes = [_][]const u8{
            t.keyword, t.string,      t.number, t.comment,
            t.boolean, t.match_paren, t.paren,  t.prompt,
        };
        for (escapes) |e| {
            const style = ansiToIcStyle(e, &buf);
            try std.testing.expect(style.len > 0);
            try std.testing.expect(std.mem.startsWith(u8, style, "ansi-") or
                std.mem.startsWith(u8, style, "bold ansi-"));
        }
    }
}

fn evalInputInner(vm: *vm_mod.VM, allocator: std.mem.Allocator, input: []const u8, mode: EvalMode) void {
    // Crash breadcrumb (kaappi#1514); reset on return so a crash at the idle
    // prompt is not mislabeled as this input's last stage.
    crash.note(.reading, "<repl>");
    defer crash.reset();

    var r = reader.Reader.initWithName(vm.gc, input, "<repl>");
    defer r.deinit();

    while (r.hasMore() catch |err| blk: {
        const lc = r.getLineCol();
        toplevel_driver.reportReadError("<repl>", lc.line, lc.col, err);
        break :blk false;
    }) {
        crash.noteStage(.reading);
        // Datum start position, for a compile error's fallback column when no
        // precise span was recorded (kaappi#1506).
        const datum_lc = r.getLineCol();
        var expr = r.readDatum() catch |err| {
            const lc = r.getLineCol();
            toplevel_driver.reportReadError("<repl>", lc.line, lc.col, err);
            break;
        };

        vm.gc.pushRoot(&expr);
        defer vm.gc.popRoot();

        crash.noteStage(.executing);
        if (vm.handleTopLevelForm(expr)) |top_result| {
            const result = top_result catch |err| {
                toplevel_driver.reportRuntimeError(vm, err, null);
                break;
            };
            var dr = result;
            if (types.isMultipleValues(dr)) {
                const mv = types.toObject(dr).as(types.MultipleValues);
                dr = if (mv.values.len > 0) mv.values[0] else types.VOID;
                if (mode != .show_type) {
                    printValuesLines(allocator, mv.values);
                    if (mode == .store_last and dr != types.VOID) {
                        vm.globalsPut("_", dr) catch {};
                    }
                    continue;
                }
            }
            if (dr != types.VOID) {
                if (mode == .show_type) {
                    writeStdout("; ");
                    writeStdout(getTypeName(dr));
                    writeStdout("\n");
                } else {
                    const s = printer.prettyPrint(allocator, dr, terminal_width) catch
                        (printer.valueToString(allocator, dr, .write) catch continue);
                    defer allocator.free(s);
                    writeStdout(s);
                    writeStdout("\n");
                }
                if (mode == .store_last) {
                    vm.globalsPut("_", dr) catch {};
                }
            }
            continue;
        }

        crash.noteStage(.compiling);
        const func = compiler.compileExpressionWithMacrosAt(vm.gc, expr, &vm.macros, vm.globals, datum_lc.line, "<repl>", false) catch |err| {
            toplevel_driver.reportCompileError("<repl>", datum_lc.line, datum_lc.col, err);
            break;
        };

        var func_val = types.makePointer(&func.header);
        vm.gc.pushRoot(&func_val);

        crash.noteStage(.executing);
        const result = vm.execute(func) catch |err| {
            vm.gc.popRoot();
            toplevel_driver.reportRuntimeError(vm, err, null);
            toplevel_driver.printStackTrace(vm);
            break;
        };
        vm.gc.popRoot();

        var display_result = result;
        if (types.isMultipleValues(display_result)) {
            const mv = types.toObject(display_result).as(types.MultipleValues);
            display_result = if (mv.values.len > 0) mv.values[0] else types.VOID;
            if (mode != .show_type) {
                printValuesLines(allocator, mv.values);
                if (mode == .store_last and display_result != types.VOID) {
                    vm.globalsPut("_", display_result) catch {};
                }
                continue;
            }
        }
        if (display_result != types.VOID) {
            if (mode == .show_type) {
                writeStdout("; ");
                writeStdout(getTypeName(display_result));
                writeStdout("\n");
            } else {
                const s = printer.prettyPrint(allocator, display_result, terminal_width) catch
                    (printer.valueToString(allocator, display_result, .write) catch continue);
                defer allocator.free(s);
                writeStdout(s);
                writeStdout("\n");
            }
            if (mode == .store_last) {
                vm.globalsPut("_", display_result) catch {};
            }
        }
    }
}
