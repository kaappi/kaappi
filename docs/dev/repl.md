# REPL

Reference for the interactive REPL: `src/repl.zig` owns the loop and the
line-editing callbacks, with the comma commands, the syntax highlighting, and
the evaluation driver split out into `src/repl_commands.zig`,
`src/repl_highlight.zig`, and `src/repl_eval.zig` (see
[Key files](#key-files)).

## Overview

The REPL uses vendored isocline (`vendor/isocline/`) for line editing, history
(`~/.kaappi/history`, `repl.history-length` entries, default 1000), syntax
highlighting, and tab completion. The variable `_` holds the last result.

`ic_readline` returns a **whole expression**, not a line. A form that spans
lines is one buffer: up and down move within it and reach history only at its
edges, every line stays editable until submit, and the entry recalled from
history later comes back the same way. `repl.zig` does not accumulate
continuation lines — the only path that still does is the WASI fallback reader,
which `main.zig` never reaches.

### How the pieces connect

| isocline hook | Kaappi side | Notes |
|---|---|---|
| `ic_set_default_is_complete` | `isCompleteCallback` → `inputIncomplete` | Enter submits only when the **reader** says the form is finished. Not upstream isocline — see `vendor/isocline/PATCHES.md`. |
| `ic_set_default_completer` | `completionCallback` | Comma commands match the whole line; everything else goes through `ic_complete_word` over `vm.globals`. `,load`/`,import` complete filenames. |
| `ic_set_default_sexp_edit` | `sexpEditCallback` → `repl_sexp.apply` | The four structural-edit keys. Not upstream isocline — patch 3. |
| `ic_set_default_highlighter` | `highlightCallback` → `scanHighlight` | Emits styled spans; `scanHighlight` is separated so the token rules are testable without a terminal. |
| `ic_style_def` | `applyTheme` | `repl.color.*` names become isocline styles via `ansiToIcStyle`. `ic-prompt` and `ic-bracematch` are isocline's own names, redefined. |
| `ic_enable_brace_matching` | — | Limited to `"()"`: the reader gives `[`/`]` no meaning (`0]` is KP1002). |
| `ic_enable_mouse` | — | Opt-in SGR mouse tracking: click inside the input to move the edit cursor. Off by default (`repl.mouse` in `~/.kaappi/config`); see `vendor/isocline/PATCHES.md`, patch 5. |

Two settings are deliberate rather than default:

- **Brace insertion is off.** Auto-closing a paren would make every buffer
  balanced, so `isCompleteCallback` would submit the moment one was typed.
- **Prompt strings carry no escapes.** isocline measures the prompt to place
  the cursor; the color arrives through the `ic-prompt` style instead.

History is written on every submit, with embedded newlines escaped, so a crash
no longer loses the session.

## Structural editing

Four keys move a *paren* rather than a character (kaappi#2216). `|` marks the
cursor:

| Key | Command | Effect |
|---|---|---|
| alt+shift+S | slurp | `(a\| b) c d` → `(a\| b c) d` |
| alt+shift+B | barf | `(a\| b c)` → `(a\| b) c` |
| alt+shift+R | raise | `(+ 1 (* 2 \|3))` → `(+ 1 \|3)` |
| alt+y | rotate | `(if a\| b c)` → `(if b c a\|)` |

They are listed under F1 too, and only when the callback is set. Each is
`ESC` followed by the character, so a terminal that does not send Option as
Meta (macOS Terminal.app, unless "Use Option as Meta key" is on) will not
deliver them.

`src/repl_sexp.zig` holds the transforms — pure functions over
`(buffer, byte cursor)`, so they unit-test without a terminal. The keys and the
buffer swap live in the vendored editor (`vendor/isocline/PATCHES.md`, patch
3); `tests/scheme/smoke/repl-structural-editing-2216.sh` drives that half over
a real pty, since nothing in Zig can reach it.

Three things are worth knowing before changing them:

- **The scanner derives its rules from `reader.zig`.** `Reader.isDelimiter`
  decides where an atom ends, and strings, `;` and `#|…|#` comments, `#;`
  datum comments, `#\(` character literals and `|pipe|` symbols all hide their
  parens. That is not decoration: bestline's originals, which the issue
  proposed porting, count parens with none of it.
- **`[` and `]` are ordinary atom characters**, because the reader gives them
  no meaning (`0]` is KP1002). `scanHighlight` used to paint them like parens;
  it no longer does, so the colors, `ic_enable_brace_matching`, the reader and
  `repl_sexp` now all agree.
- **An unbalanced form declines.** Every command needs a close paren to move,
  so a half-typed form is left exactly as it is rather than guessed at.

Rotate keeps the head in place and cycles the arguments. Rotating the head too
would turn every call form into something unevaluatable (`(+ 1 2)` → `(1 2 +)`);
as it stands, repeating it n-1 times on n arguments restores the original.

## Click to position the cursor

`repl.mouse: true` in `~/.kaappi/config` turns on SGR mouse tracking for the
edit session, so a left click inside the current input moves the edit cursor
(kaappi#2264). Default is **off**: while tracking is on, the terminal stops
reporting drag-to-select to the application — copy still works
modifier-gated (Option-drag in Terminal.app / iTerm2, Shift-drag in most
Linux terminals). Clicks outside the editing area — into scrollback above,
blank rows below — are no-ops; a click on the prompt clamps to the start of
that line's content.

The mouse reports absolute screen coordinates, so the editor anchors the
input's on-screen start with a one-time `ESC[6n` query at the start of each
read. The response reader never consumes input: typing ahead between forms
(Enter, then start typing the next form while the previous one evaluates)
is common, and bytes that are not a well-formed response are pushed back to
be read as keys — only the anchor is skipped for that line, never a
keystroke. A terminal that does not answer (some emulators, SSH without
mouse support) makes clicks no-ops. The Windows console needs its own
mouse-input path, not SGR, and is not supported
(`vendor/isocline/PATCHES.md`, patch 5).

`tests/scheme/smoke/repl-mouse-click-2264.sh` drives the whole path over a
real pty: it answers the DSR query the way a terminal emulator would and
then feeds SGR mouse sequences, asserting on what the evaluator prints.

## Comma commands

Type `,help` in the REPL for the authoritative list.

**General:** `,help`, `,quit` (also `,exit`)

**Evaluation:**

| Command | Effect |
|---------|--------|
| `,time <expr>` | Measure execution time |
| `,type <expr>` | Show result type |
| `,expand <expr>` | Show macro expansion without evaluating |
| `,profile <expr>` | Profile timing, calls, and allocations |
| `,dis <expr>` | Disassemble a procedure (see [bytecode.md](bytecode.md)) |

**Inspection:**

| Command | Effect |
|---------|--------|
| `,describe <sym>` | Show procedure arity and type |
| `,apropos <str>` | Search bindings by substring |
| `,env [prefix]` | List bindings, optionally filtered by prefix |

**Debugging:**

| Command | Effect |
|---------|--------|
| `,break <name>` | Set breakpoint on function |
| `,breakpoints` | List active breakpoints |
| `,delete all` | Clear all breakpoints |
| `,step <expr>` | Evaluate with single-stepping |
| `,condition <id> <expr>` | Set breakpoint condition |

**System:**

| Command | Effect |
|---------|--------|
| `,gc` | Show GC statistics |
| `,version` | Show Kaappi version |
| `,load <file>` | Load and run a Scheme file |
| `,import <lib>` | Import a library (e.g. `,import (srfi 1)`) |

## Not yet implemented

Width-aware pretty-printing for long output — tracked in
[#921](https://github.com/kaappi/kaappi/issues/921).

## Key files

| Component | Location |
|-----------|----------|
| REPL loop, line editing, completeness/completion callbacks | `src/repl.zig` |
| Comma-command dispatch and handlers (`,load`, `,break`, `,time`, …) | `src/repl_commands.zig` |
| Syntax highlighting: token scanner, highlighter callback, theme bridge | `src/repl_highlight.zig` |
| Evaluation driver: read → compile → execute → print | `src/repl_eval.zig` |
| Structural editing transforms (slurp, barf, raise, rotate) | `src/repl_sexp.zig` |
| Entry point / CLI flags | `src/main.zig` |
| Import handling | `src/vm_library.zig` (`handleImport`) |
| Stepping debugger | `src/vm_debug.zig` |
| Disassembler | `src/disassembler.zig` |
| Value printer | `src/printer.zig` |
| isocline FFI wrapper | `src/isocline.zig` |
| Vendored editor + Kaappi's patches | `vendor/isocline/`, `vendor/isocline/PATCHES.md` |
