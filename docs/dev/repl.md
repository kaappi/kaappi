# REPL

Reference for the interactive REPL (`src/repl.zig`).

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
| `ic_set_default_highlighter` | `highlightCallback` → `scanHighlight` | Emits styled spans; `scanHighlight` is separated so the token rules are testable without a terminal. |
| `ic_style_def` | `applyTheme` | `repl.color.*` names become isocline styles via `ansiToIcStyle`. `ic-prompt` and `ic-bracematch` are isocline's own names, redefined. |
| `ic_enable_brace_matching` | — | Limited to `"()"`: the reader gives `[`/`]` no meaning (`0]` is KP1002). |

Two settings are deliberate rather than default:

- **Brace insertion is off.** Auto-closing a paren would make every buffer
  balanced, so `isCompleteCallback` would submit the moment one was typed.
- **Prompt strings carry no escapes.** isocline measures the prompt to place
  the cursor; the color arrives through the `ic-prompt` style instead.

History is written on every submit, with embedded newlines escaped, so a crash
no longer loses the session.

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
| REPL loop, command dispatch, completeness/completion/highlight callbacks | `src/repl.zig` |
| Entry point / CLI flags | `src/main.zig` |
| Import handling | `src/vm_library.zig` (`handleImport`) |
| Stepping debugger | `src/vm_debug.zig` |
| Disassembler | `src/disassembler.zig` |
| Value printer | `src/printer.zig` |
| isocline FFI wrapper | `src/isocline.zig` |
| Vendored editor + Kaappi's patches | `vendor/isocline/`, `vendor/isocline/PATCHES.md` |
