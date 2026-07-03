# REPL

Reference for the interactive REPL (`src/repl.zig`).

## Overview

The REPL uses vendored linenoise for line editing, history
(`~/.kaappi/history`, 1000 entries), and tab completion (global bindings
and comma commands). Multi-line input is supported via `parenDepth()`,
which tracks open parentheses, strings, and block comments across lines,
showing a `"  ... "` continuation prompt. The variable `_` holds the last
result.

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
| REPL loop, command dispatch, `parenDepth()`, tab completion | `src/repl.zig` |
| Entry point / CLI flags | `src/main.zig` |
| Import handling | `src/vm_library.zig` (`handleImport`) |
| Stepping debugger | `src/vm_debug.zig` |
| Disassembler | `src/disassembler.zig` |
| Value printer | `src/printer.zig` |
| Linenoise wrapper | `src/linenoise.zig` |
