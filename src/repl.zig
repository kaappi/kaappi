const std = @import("std");
const platform = @import("platform.zig");
const is_wasm = @import("builtin").os.tag == .wasi;
const vm_mod = @import("vm.zig");
const reader = @import("reader.zig");
const memory = @import("memory.zig");
const reporting = @import("reporting.zig");
const repl_sexp = @import("repl_sexp.zig");
const repl_highlight = @import("repl_highlight.zig");
const repl_eval = @import("repl_eval.zig");
const repl_commands = @import("repl_commands.zig");
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
        ic.completeWord(cenv, prefix, &repl_commands.completeCommandNameCallback, &repl_commands.isCommandChar);
        return;
    }

    ic.completeWord(cenv, prefix, &completeWordCallback, &isIdentChar);
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

pub fn repl(vm: *vm_mod.VM) !void {
    const allocator = vm.gc.allocator;

    const cfg = config_mod.load();
    repl_highlight.setEnabled(cfg.highlight);

    writeStdout("Kaappi Scheme v" ++ version ++ "\n");
    writeStdout("Type ,help for commands, ,quit to exit.\n\n");

    repl_eval.refreshTerminalWidth();
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
        ic.enableHighlight(repl_highlight.enabled());
        ic.enableHint(false); // no hint callback is wired up
        // Opt-in SGR mouse tracking: click inside the input to move the edit
        // cursor (kaappi#2264). Off by default — while tracking is on, the
        // terminal stops reporting drag-to-select to the application.
        ic.enableMouse(cfg.mouse);
        repl_highlight.applyTheme(cfg.theme);

        ic.setIsComplete(&isCompleteCallback, null);
        ic.setSexpEdit(&sexpEditCallback, null);
        ic.setCompleter(&completionCallback, null);
        if (repl_highlight.enabled()) ic.setHighlighter(&repl_highlight.highlightCallback, null);
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

        // Comma commands (see repl_commands.zig) are REPL directives; anything
        // else is Scheme and falls through to evaluation below.
        switch (repl_commands.handleCommand(vm, allocator, debug_trimmed)) {
            .not_command => {},
            .handled => {
                input_buf.clearRetainingCapacity();
                continue;
            },
            .quit => break,
        }

        // isocline records and persists each submitted form itself, escaping
        // embedded newlines on the way to disk — so a multi-line entry comes
        // back as one editable entry rather than the old flattened line
        // (kaappi#821). Nothing to add here.
        repl_eval.evalInputTyped(vm, allocator, full_input, .store_last);

        input_buf.clearRetainingCapacity();
    }

    repl_vm = null;
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
