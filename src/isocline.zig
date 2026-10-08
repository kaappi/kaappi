//! FFI wrapper for the vendored isocline line editor (`vendor/isocline/`).
//!
//! isocline replaces linenoise as the REPL's line editor. The difference that
//! matters is structural: linenoise edits one physical line per call, so a
//! multi-line form has to be accumulated by the caller and its earlier lines
//! can no longer be edited. isocline holds the whole form in one buffer, so
//! `readline` returns a finished expression — newlines and all — and every line
//! of it stays editable until the user submits.
//!
//! Kaappi's copy carries five patches, all documented in
//! `vendor/isocline/PATCHES.md`: an input-completeness callback (upstream's
//! Enter always submits), a configurable history size (upstream caps at 200),
//! structural s-expression editing (upstream has none), a TCSADRAIN fix so a
//! multi-line paste tail is not discarded, and opt-in mouse click-to-position.
//!
//! Isocline is not thread-safe: `readline` and `print` must be called from one
//! thread. That holds here — only the REPL loop touches it.

const std = @import("std");

/// Zig bindings for the vendored isocline C API.
///
/// These were `@cImport({ @cInclude("isocline.h") })` until Zig 0.17 removed
/// the builtin in favour of the external translate-c package. The header is
/// self-contained (it includes only `stddef.h`, `stdbool.h`, `stdint.h` and
/// `stdarg.h`), so the handful of entry points below are declared directly
/// instead of taking on a build-time package dependency. If a new isocline
/// symbol is needed, add it here and keep the signature identical to
/// `vendor/isocline/include/isocline.h`.
pub const c = struct {
    pub const long = c_long;

    pub const ic_completion_env_t = opaque {};
    pub const ic_highlight_env_t = opaque {};

    /// Must match `ic_sexp_command_t` in the header; `setSexpEdit` asserts the
    /// numbering against `repl_sexp.Command` at runtime.
    pub const ic_sexp_command_t = enum(c_int) {
        IC_SEXP_SLURP = 0,
        IC_SEXP_BARF = 1,
        IC_SEXP_RAISE = 2,
        IC_SEXP_ROTATE = 3,
    };

    pub const Completer = *const fn (?*ic_completion_env_t, [*c]const u8) callconv(.c) void;
    pub const IsCharClass = *const fn ([*c]const u8, c_long) callconv(.c) bool;
    pub const Highlighter = *const fn (?*ic_highlight_env_t, [*c]const u8, ?*anyopaque) callconv(.c) void;
    pub const IsComplete = *const fn ([*c]const u8, ?*anyopaque) callconv(.c) bool;
    pub const SexpEdit = *const fn (ic_sexp_command_t, [*c]const u8, [*c]c_long, ?*anyopaque) callconv(.c) [*c]u8;

    pub extern fn ic_init(use_std_err: bool) void;
    pub extern fn ic_readline(prompt_text: [*c]const u8) [*c]u8;
    pub extern fn ic_free(p: ?*anyopaque) void;

    pub extern fn ic_set_history(fname: [*c]const u8, max_entries: c_long) void;
    pub extern fn ic_history_add(entry: [*c]const u8) void;
    pub extern fn ic_history_clear() void;

    pub extern fn ic_set_default_completer(completer: ?Completer, arg: ?*anyopaque) void;
    pub extern fn ic_add_completion(cenv: ?*ic_completion_env_t, completion: [*c]const u8) bool;
    pub extern fn ic_complete_word(cenv: ?*ic_completion_env_t, prefix: [*c]const u8, fun: ?Completer, is_word_char: ?IsCharClass) void;
    pub extern fn ic_complete_filename(cenv: ?*ic_completion_env_t, prefix: [*c]const u8, dir_separator: u8, roots: [*c]const u8, extensions: [*c]const u8) void;

    pub extern fn ic_set_default_highlighter(highlighter: ?Highlighter, arg: ?*anyopaque) void;
    pub extern fn ic_highlight(henv: ?*ic_highlight_env_t, pos: c_long, count: c_long, style: [*c]const u8) void;
    pub extern fn ic_style_def(style_name: [*c]const u8, fmt: [*c]const u8) void;

    pub extern fn ic_set_default_is_complete(is_complete: ?IsComplete, arg: ?*anyopaque) void;
    pub extern fn ic_set_default_sexp_edit(sexp_edit: ?SexpEdit, arg: ?*anyopaque) void;

    pub extern fn ic_malloc(sz: usize) ?*anyopaque;

    pub extern fn ic_enable_multiline(enable: bool) bool;
    pub extern fn ic_enable_multiline_indent(enable: bool) bool;
    pub extern fn ic_enable_brace_matching(enable: bool) bool;
    pub extern fn ic_enable_brace_insertion(enable: bool) bool;
    pub extern fn ic_enable_mouse(enable: bool) bool;
    pub extern fn ic_enable_highlight(enable: bool) bool;
    pub extern fn ic_enable_color(enable: bool) bool;
    pub extern fn ic_enable_hint(enable: bool) bool;
    pub extern fn ic_enable_beep(enable: bool) bool;
    pub extern fn ic_enable_auto_tab(enable: bool) bool;
    pub extern fn ic_enable_inline_help(enable: bool) bool;

    pub extern fn ic_set_matching_braces(brace_pairs: [*c]const u8) void;
    pub extern fn ic_set_insertion_braces(brace_pairs: [*c]const u8) void;
    pub extern fn ic_set_prompt_marker(prompt_marker: [*c]const u8, continuation_prompt_marker: [*c]const u8) void;
};

/// Initialize isocline. Call once before any other function here; `use_std_err`
/// routes editor output to stderr instead of stdout.
pub fn init(use_std_err: bool) void {
    c.ic_init(use_std_err);
}

/// Read one complete expression. The returned string is isocline-allocated and
/// must be released with `free`; null on EOF (ctrl-D on empty input) or on
/// cancel (ctrl-C). Embedded newlines are preserved.
pub fn readline(prompt: [*:0]const u8) ?[*:0]u8 {
    return @ptrCast(c.ic_readline(prompt));
}

pub fn free(ptr: *anyopaque) void {
    c.ic_free(ptr);
}

// --- History ---------------------------------------------------------------

/// Enable history, persisted to `path`. `max_entries` is honored as given
/// (PATCH 2); pass a negative value for isocline's own default.
pub fn setHistory(path: ?[*:0]const u8, max_entries: c_long) void {
    c.ic_set_history(path, max_entries);
}

pub fn historyAdd(entry: [*:0]const u8) void {
    c.ic_history_add(entry);
}

pub fn historyClear() void {
    c.ic_history_clear();
}

// --- Completion ------------------------------------------------------------

pub const CompletionEnv = c.ic_completion_env_t;

pub fn setCompleter(cb: ?*const fn (?*CompletionEnv, [*c]const u8) callconv(.c) void, arg: ?*anyopaque) void {
    c.ic_set_default_completer(cb, arg);
}

/// Add one completion for the current prefix. Returns false when isocline has
/// enough candidates and the completer should stop.
pub fn addCompletion(cenv: ?*CompletionEnv, completion: [*:0]const u8) bool {
    return c.ic_add_completion(cenv, completion);
}

/// Complete the word ending at the cursor, delegating back to `cb` with just
/// that word. `is_word_char` decides where the word starts.
pub fn completeWord(
    cenv: ?*CompletionEnv,
    prefix: [*c]const u8,
    cb: ?*const fn (?*CompletionEnv, [*c]const u8) callconv(.c) void,
    is_word_char: ?*const fn ([*c]const u8, c_long) callconv(.c) bool,
) void {
    c.ic_complete_word(cenv, prefix, cb, is_word_char);
}

/// Filename completion, for `,load` and friends.
pub fn completeFilename(
    cenv: ?*CompletionEnv,
    prefix: [*c]const u8,
    dir_separator: u8,
    roots: ?[*:0]const u8,
    extensions: ?[*:0]const u8,
) void {
    c.ic_complete_filename(cenv, prefix, dir_separator, roots, extensions);
}

// --- Highlighting ----------------------------------------------------------

pub const HighlightEnv = c.ic_highlight_env_t;

pub fn setHighlighter(cb: ?*const fn (?*HighlightEnv, [*c]const u8, ?*anyopaque) callconv(.c) void, arg: ?*anyopaque) void {
    c.ic_set_default_highlighter(cb, arg);
}

/// Style `count` bytes starting at byte offset `pos`. `style` is a style name
/// registered with `styleDef`, or one of isocline's built-ins ("keyword",
/// "string", "comment", "number", "type", "constant").
pub fn highlight(henv: ?*HighlightEnv, pos: c_long, count: c_long, style: ?[*:0]const u8) void {
    c.ic_highlight(henv, pos, count, style);
}

/// Define or redefine a named style, e.g. `styleDef("kaappi-paren", "bold #d0d0d0")`.
pub fn styleDef(name: [*:0]const u8, fmt: [*:0]const u8) void {
    c.ic_style_def(name, fmt);
}

// --- Input completeness (Kaappi patch 1) -----------------------------------

/// Set the callback that decides, at Enter, whether the buffer is a finished
/// expression. Returning false inserts a newline and keeps editing — this is
/// what makes the prompt continue while a form is still open. See
/// `vendor/isocline/PATCHES.md`.
pub fn setIsComplete(cb: ?*const fn ([*c]const u8, ?*anyopaque) callconv(.c) bool, arg: ?*anyopaque) void {
    c.ic_set_default_is_complete(cb, arg);
}

// --- Structural editing (Kaappi patch 3) -----------------------------------

/// Set the callback the four structural-edit keys (alt+shift+S/B/R, alt+y)
/// dispatch to. It is handed the whole buffer and the cursor as a byte offset,
/// and returns a replacement buffer from `alloc` below — isocline takes
/// ownership and frees it — or null to decline and leave the input untouched.
/// See `vendor/isocline/PATCHES.md`.
pub fn setSexpEdit(
    cb: ?*const fn (c.ic_sexp_command_t, [*c]const u8, [*c]c_long, ?*anyopaque) callconv(.c) [*c]u8,
    arg: ?*anyopaque,
) void {
    comptime {
        // The command numbering is the contract between `repl_sexp.Command`
        // and isocline's enum; a silent drift would run the wrong command.
        // This lives in a function body rather than at container scope
        // because the latter is analyzed eagerly, and `zig build test` does
        // not compile the C library at all.
        const Command = @import("repl_sexp.zig").Command;
        std.debug.assert(@as(c_int, @intCast(@backingInt(Command.slurp))) == @as(c_int, @backingInt(c.ic_sexp_command_t.IC_SEXP_SLURP)));
        std.debug.assert(@as(c_int, @intCast(@backingInt(Command.barf))) == @as(c_int, @backingInt(c.ic_sexp_command_t.IC_SEXP_BARF)));
        std.debug.assert(@as(c_int, @intCast(@backingInt(Command.raise))) == @as(c_int, @backingInt(c.ic_sexp_command_t.IC_SEXP_RAISE)));
        std.debug.assert(@as(c_int, @intCast(@backingInt(Command.rotate))) == @as(c_int, @backingInt(c.ic_sexp_command_t.IC_SEXP_ROTATE)));
    }
    c.ic_set_default_sexp_edit(cb, arg);
}

/// Allocate `n` bytes from isocline's allocator, for a buffer handed back to
/// it. Null when isocline is not initialized or the allocation fails.
pub fn alloc(n: usize) ?[*]u8 {
    return @ptrCast(c.ic_malloc(n));
}

// --- Options ---------------------------------------------------------------

pub fn enableMultiline(enable: bool) void {
    _ = c.ic_enable_multiline(enable);
}

pub fn enableMultilineIndent(enable: bool) void {
    _ = c.ic_enable_multiline_indent(enable);
}

pub fn enableBraceMatching(enable: bool) void {
    _ = c.ic_enable_brace_matching(enable);
}

pub fn enableBraceInsertion(enable: bool) void {
    _ = c.ic_enable_brace_insertion(enable);
}

/// Opt in to SGR mouse tracking so a click inside the input moves the edit
/// cursor (KAAPPI PATCH 5, kaappi#2264). Off by default: while tracking is on
/// the terminal reports button presses instead of drag-to-select.
pub fn enableMouse(enable: bool) void {
    _ = c.ic_enable_mouse(enable);
}

/// Which brace pairs to match. Kaappi's reader gives `[` and `]` no meaning,
/// so the REPL passes "()" rather than isocline's "()[]{}" default.
pub fn setMatchingBraces(pairs: [*:0]const u8) void {
    c.ic_set_matching_braces(pairs);
}

pub fn setInsertionBraces(pairs: [*:0]const u8) void {
    c.ic_set_insertion_braces(pairs);
}

pub fn enableHighlight(enable: bool) void {
    _ = c.ic_enable_highlight(enable);
}

pub fn enableColor(enable: bool) void {
    _ = c.ic_enable_color(enable);
}

pub fn enableHint(enable: bool) void {
    _ = c.ic_enable_hint(enable);
}

pub fn enableBeep(enable: bool) void {
    _ = c.ic_enable_beep(enable);
}

pub fn enableAutoTab(enable: bool) void {
    _ = c.ic_enable_auto_tab(enable);
}

pub fn enableInlineHelp(enable: bool) void {
    _ = c.ic_enable_inline_help(enable);
}

/// The marker drawn before the prompt text, and the one drawn before each
/// continuation line — isocline owns the "  ... " the REPL used to print itself.
pub fn setPromptMarker(marker: ?[*:0]const u8, continuation: ?[*:0]const u8) void {
    c.ic_set_prompt_marker(marker, continuation);
}
