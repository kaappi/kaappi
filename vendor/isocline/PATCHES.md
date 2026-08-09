# Kaappi's patches to isocline

Vendored from <https://github.com/daanx/isocline> at commit
`8d6dc1ef95b1b46711e66eb23d39d4467a0fcdac` (2026-04-23, v1.1.0), MIT licensed —
see `LICENSE`.

**This is a patched copy.** Five changes diverge from upstream. Each is marked
in the source with a `KAAPPI PATCH <n>` comment pointing here. When updating
isocline, re-apply them; `grep -rn 'KAAPPI PATCH' vendor/isocline/` finds every
site.

## Patch 1 — an input-completeness callback

**Files:** `include/isocline.h`, `src/env.h`, `src/isocline.c`,
`src/editline.c`

Upstream decides at Enter that input is finished unless it ends in the
`multiline_eol` continuation character (`\`); a newline is otherwise entered
explicitly with shift-tab or ctrl-J. That is right for a shell and wrong for a
Lisp prompt, where whether the form is finished is a property of the text, not
of which key was pressed.

The patch adds:

```c
typedef bool (ic_is_complete_fun_t)(const char* input, void* arg);
void ic_set_default_is_complete(ic_is_complete_fun_t* is_complete, void* arg);
```

When set, and multi-line editing is enabled, Enter consults it: `true` submits,
`false` inserts a newline and keeps editing. With no callback set, behavior is
exactly upstream's.

Kaappi answers it from the reader (`repl.inputIncomplete` → the reader's
`incomplete_input` mode), so the prompt and the file loader agree about where a
datum ends.

## Patch 2 — configurable history size

**File:** `src/history.c`

Upstream clamps every history to `IC_MAX_HISTORY` (200) regardless of what the
caller asks for. Kaappi's `repl.history-length` defaults to 1000 and is user
configurable (`src/config.zig`), so an explicit request has to be honored.

`IC_MAX_HISTORY` is now a sanity bound (1000000) and `IC_DEFAULT_HISTORY` (200,
upstream's value) applies when the caller passes a negative count. A caller
asking for 1000 gets 1000.

## Patch 3 — structural s-expression editing

**Files:** `include/isocline.h`, `src/env.h`, `src/isocline.c`,
`src/editline.c`, `src/editline_help.c`

Upstream has no structural editing — no way to move a paren rather than a
character. The patch adds four keys and one callback:

```c
typedef enum ic_sexp_command_e {
  IC_SEXP_SLURP = 0, IC_SEXP_BARF = 1, IC_SEXP_RAISE = 2, IC_SEXP_ROTATE = 3
} ic_sexp_command_t;

typedef char* (ic_sexp_fun_t)(ic_sexp_command_t cmd, const char* input, long* pos, void* arg);
void ic_set_default_sexp_edit(ic_sexp_fun_t* sexp_edit, void* arg);
```

| Key | Command |
|---|---|
| alt+shift+S | slurp |
| alt+shift+B | barf |
| alt+shift+R | raise |
| alt+y | rotate |

isocline owns the keys and the buffer; the host language owns the syntax and
does the rewriting. The callback is handed the whole input and the cursor as a
byte offset, and returns either a replacement buffer allocated with
`ic_malloc()` (isocline frees it) or NULL to decline — an unbalanced form,
nothing to slurp — in which case the input is left exactly as it was. One
`editor_start_modify` wraps the replacement, so ctrl-Z undoes a structural
edit as a single step.

With no callback set the four keys are unbound and `F1`'s help omits the
section, so behavior is exactly upstream's.

Kaappi implements the callback in `src/repl_sexp.zig`, whose scanner derives
its rules from `src/reader.zig` — strings, `;` and `#|…|#` comments, `#;`
datum comments, `#\(` character literals and `|pipe|` symbols all hide their
parens, and `[`/`]` are ordinary atom characters because the reader gives them
no meaning.

The commands and keybindings come from [bestline](https://github.com/jart/bestline)
(BSD-2-Clause) by way of kaappi#2216. The code does not: bestline's `raise` is
an empty stub, its `rotate` rotates the kill ring rather than a form, and its
barf and slurp count parens with no awareness of strings or comments.

## Patch 4 — don't discard buffered input when leaving/entering raw mode

**File:** `src/tty.c`

Upstream's `tty_start_raw`/`tty_end_raw` — called at the start and end of
*every* `ic_readline` call — used `tcsetattr(..., TCSAFLUSH, ...)`.
`TCSAFLUSH` discards any input the kernel has already received but the
process hasn't `read(2)`ed yet.

That is fine for a shell reading one physical line at a time, and wrong for a
Lisp prompt reading a whole form: pasting a block with more than one
top-level form delivers it to the pty as a single burst, often with each
pasted newline arriving as a literal CR (terminals commonly translate a
pasted newline into the same byte a real Enter keypress sends). If the first
form alone is already complete, `isCompleteCallback` (Patch 1) submits right
there and `ic_editline` returns — before the rest of the still-unread paste
has been read at all. The `TCSAFLUSH` in `tty_end_raw` then throws it away
before the REPL's next `ic_readline` call ever gets a chance to read it
(kaappi#2226).

The fix is `TCSADRAIN` in both `tty_start_raw` and `tty_end_raw`: it still
waits for pending output (the prompt, the echoed line) to finish writing, but
leaves unread input alone. Both call sites need the change, not just
`tty_end_raw` — otherwise the next `tty_start_raw` discards on the way back
in what the previous `tty_end_raw` spared.

The `TCSAFLUSH` in the termination-signal handler (`sig_handler`, for
SIGINT/SIGTSTP/etc.) is untouched: the process is dying or suspending there,
not reading the next form, so discarding stray input is the right call and
out of scope for this bug.

## Patch 5 — click to reposition the edit cursor (mouse support)

**Files:** `include/isocline.h`, `src/env.h`, `src/isocline.c`,
`src/tty.h`, `src/tty.c`, `src/tty_esc.c`, `src/editline.c`

Upstream isocline moves the cursor with arrow keys and structural editing
only. The patch adds an opt-in `ic_enable_mouse(bool)` that turns on SGR mouse
tracking for the edit session, decodes the clicks, and translates a left press
into a cursor move (kaappi#2264).

### The three pieces

1. **Tracking on/off** (`ic_editline` in `editline.c`): on raw-mode entry,
emit `\x1b[?1000h` (button-press tracking; deliberately *not* `?1002h`/
`?1003h` motion) and `\x1b[?1006h` (SGR extended coordinates); emit the
matching `l` sequences before leaving raw mode. `?1000h` captures clicks, so
drag-to-select-and-copy in the REPL stops working while it is on — the
usual reason REPLs don't do this. Mainstream terminals bypass app mouse mode
with a modifier for one-off native selection (Option-drag in Terminal.app /
iTerm2, Shift-drag in most Linux terminals), so copy still works,
modifier-gated; preserving un-gated selection would require shift-click
passthrough, out of scope. **Windows is a second, parallel implementation,
not a reuse of this path** (kaappi#2264 comment): isocline reads `INPUT_RECORD`
structs via `ReadConsoleInputW` on Windows — not a byte stream — and currently
discards non-key events (`if (inp.EventType != KEY_EVENT) continue;` in
`tty_waitc_console`). Mouse is first-class there: `MOUSE_EVENT_RECORD` carries
`dwMousePosition` (already in console cells), `dwButtonState`, `dwEventFlags`.
The follow-up needs (1) `ENABLE_MOUSE_INPUT` and clearing
`ENABLE_QUICK_EDIT_MODE` in the Windows `tty_start_raw` — Quick Edit *is*
Windows' drag-to-select, the exact mirror of `?1000h` breaking selection on
Unix; (2) a `MOUSE_EVENT` arm instead of the drop; (3) the anchor is *easier*
there: `GetConsoleScreenBufferInfo().dwCursorPosition` is synchronous, no
`ESC[6n` round-trip. One Console-API path covers classic conhost and Windows
Terminal alike (ConPTY translates the terminal's mouse back into
`MOUSE_EVENT_RECORD`s for a console app that has not requested VT input), so
there is one shell-agnostic Windows implementation, not one per shell. Until
then, tracking stays off on Windows (`#if !defined(_WIN32)`) and the flag is
honored by nothing.

2. **Decoding** (`tty_esc.c`): SGR mouse arrives as `\x1b[<b;x;yM` (press)
or `m` (release). `<` lands in the CSI decoder's "special byte" catch, and
the generic parameter parsing only handles two parameters, so the three-part
mouse event is intercepted right after the special-byte check. The
coordinates cannot fit in the `code_t` keycode space, so the event is stashed
on the `tty` (via `tty_set_mouse_event`, new in `tty.h`) and surfaced as a
single `KEY_EVENT_MOUSE` code; the edit loop reads it back with
`tty_last_mouse`.

3. **Cursor move** (`editline.c`): on a plain left **press** (button 0, no
modifiers — the release event `m` is decoded but ignored, so a click moves
the cursor exactly once), convert the absolute screen coordinates to
prompt-relative (row, col) and call the existing `edit_set_pos_at_rowcol`
— the hard part, mapping (row, col) to a buffer byte position with prompt
width, continuation prompt, and line wrapping, is already implemented
(`sbuf_get_pos_at_rc`).

### The one hard part: absolute → relative anchor

The mouse reports **absolute** screen coordinates; isocline works entirely in
coordinates **relative to the prompt** (`eb->cur_row` is 0-based relative to
the prompt) and never queries the absolute cursor position — `term.c` has no
DSR reader wired into the edit loop. So the patch anchors the input's
on-screen start with a **one-time `\x1b[6n` query at edit-session start**
(`edit_line`, right after the prompt is written), storing the answer on the
editor as `anchor_row`/`anchor_col`. The response is read by a new
dedicated reader (`tty_read_dsr_response` in `tty.c`, deliberately not the
existing `tty_read_esc_response`): a REPL user types ahead between forms —
press Enter and start typing the next form while the previous one evaluates
— so the first bytes the reader sees are often **not** the response. The
reader accepts only a well-formed `ESC [ digits ; digits R`; anything else
it read is pushed back in order, so a queued keystroke (or an arrow key
sent as `ESC [ A`) still reaches the edit loop as a key. The only
consequence of a response that cannot be read is an unset anchor, i.e.
clicks no-op for that line — never lost input. A response that arrives
after the reader gave up decodes to `KEY_NONE` later and is ignored. This
anchor is the only piece that must be correct; everything downstream is
already safe. A terminal that does not answer (some emulators, SSH without
mouse support) leaves the anchor unset and clicks become no-ops — the
query costs at most the escape-sequence timeout.

Clicks outside the editing area are safe no-ops (`edit_set_pos_at_rowcol`
already guards `if (pos < 0) return;`, and the mapper returns `-1` for
out-of-range rows):

| Click location | Result |
|---|---|
| Below the input (blank rows) | row out of range → `-1` → cursor doesn't move |
| Above the input (prior output / scrollback) | negative relative row → `-1` → no-op *(iff the anchor is right)* |
| On the prompt glyphs | clamps to start of that logical line's content |
| Past end of a line's text | `i < end` guard clamps to line end |
| Inside text (incl. wrapped lines) | maps exactly (mapper is wrap-aware) |

Clicking into scrollback can never reposition there: that region is terminal
history, not an edit buffer, and isocline has no model of it. The whole risk
concentrates in the anchor — a stale/off-by-one anchor could map an
above-input click to a valid in-range row and jump the cursor unexpectedly,
instead of no-op'ing. The anchor is queried per `ic_readline` call (the
cursor row moves with evaluation output between calls), and it goes stale if
the input itself scrolls the terminal — the input taller than the window is a
known limitation of the first cut.

A delayed DSR response arriving *after* its query timed out decodes to
`KEY_NONE`; the edit loop now ignores `KEY_NONE` in its default case, where
previously it fell through to `code_is_unicode(0)` and inserted a NUL.

## Deliberately not patched

**No assume-TTY test hook.** The linenoise fork this replaced carried
`LINENOISE_ASSUME_TTY` so tests could drive it without a terminal. Nothing
outside `vendor/` ever set it. REPL tests use a real pty instead, which
exercises the terminal path rather than bypassing it.
