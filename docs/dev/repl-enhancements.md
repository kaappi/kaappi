# REPL Enhancements

## Current state

The REPL (`src/main.zig:456-571`) uses vendored linenoise for line editing,
history (`.kaappi_history`, 1000 entries), and tab completion (global
bindings). Multi-line input is already supported via `parenDepth()` which
tracks open parentheses across lines, showing a `"  ... "` continuation
prompt. Debug commands (`,break`, `,breakpoints`, `,delete`, `,step`) are
dispatched at line 507.

## Proposed enhancements

### 1. `,time` command

**What:** Measure execution time for an expression.

```
kaappi> ,time (fib 35)
9227465
; 2.02 seconds
```

**Implementation:** In the REPL command dispatch (`main.zig:507`), add:
```zig
if (std.mem.eql(u8, trimmed, ",time") or std.mem.startsWith(u8, trimmed, ",time ")) {
    const expr = trimmed[5..]; // skip ",time"
    const start = std.posix.clock_gettime(.monotonic);
    evalInput(&vm, allocator, expr);
    const end = std.posix.clock_gettime(.monotonic);
    // print elapsed
}
```

**Complexity:** Low. ~15 lines. Timing primitives (`current-jiffy`,
`jiffies-per-second` in `primitives_r7rs.zig`) already exist but using
`clock_gettime` directly is simpler for the REPL command.

### 2. `,expand` command

**What:** Show the result of macro expansion without evaluating.

```
kaappi> (define-syntax my-or
          (syntax-rules ()
            ((my-or a b)
             (let ((temp a)) (if temp temp b)))))
kaappi> ,expand (my-or #f 42)
(let ((__hyg_1_temp #f)) (if __hyg_1_temp __hyg_1_temp 42))
```

**Implementation:** Compile the expression but intercept at the macro
expansion stage. In `compiler.zig`, the expanded form is available at line
524 (`expanded`). For the REPL command, compile with a flag that returns the
expanded S-expression instead of the bytecode.

**Complexity:** Medium. Requires either a new compiler entry point that
returns the expanded form, or a simpler approach: use `expandMacro` directly
from the REPL with access to `vm.macros`.

### 3. `,env` / `,bindings` command

**What:** List global bindings, optionally filtered by prefix.

```
kaappi> ,env fib
fib: #<closure fib>
kaappi> ,env
; 419 built-in procedures
; 3 user-defined bindings
```

**Implementation:** Iterate `vm.globals`, filter by prefix, print with
`printer.valueToString`. Group by type (procedure, variable, macro).

**Complexity:** Low. ~25 lines.

### 4. Improved incomplete-expression detection

**Current:** `parenDepth()` only counts `(` and `)`, skipping strings and
line comments. It does NOT detect:
- Unclosed string literals (`"hello`)
- Unclosed block comments (`#| ...`)
- Incomplete vector literals (`#(1 2`)
- Incomplete bytevector literals (`#u8(1 2`)

**Fix:** Extend `parenDepth` to track `in_block_comment` (nestable) and
`in_string` states, and also count `#(` / `#u8(` as opening parens. Return
a negative depth or special flag for unclosed strings.

**Complexity:** Low. Extend the existing state machine with 2-3 more flags.

### 5. `,help` command

**What:** Print available REPL commands and shortcuts.

```
kaappi> ,help
Commands:
  ,time <expr>      Measure execution time
  ,expand <expr>    Show macro expansion
  ,env [prefix]     List global bindings
  ,break <name>     Set breakpoint on function
  ,breakpoints      List active breakpoints
  ,delete all       Clear all breakpoints
  ,step <expr>      Evaluate with single-stepping
  ,help             This message
```

**Implementation:** String literal in the command dispatch.

**Complexity:** Trivial.

### 6. Pretty-printing for long output

**Current:** Values are printed on a single line regardless of length. A
large list or deeply nested structure produces an unreadable wall of text.

**Improvement:** Add width-aware pretty-printing to `printer.zig` that
inserts newlines and indentation when output exceeds ~80 columns. Activated
only in the REPL (not in `display`/`write` which must follow R7RS).

**Complexity:** Medium-high. Requires a two-pass algorithm (measure width,
then format) or a backtracking approach. Not essential but improves usability
significantly for exploratory programming.

## Priority order

1. ~~`,time`~~ — **Done**
2. ~~`,help`~~ — **Done**
3. ~~`,env`~~ — **Done**
4. Incomplete-expression detection — small fix, avoids confusion
5. `,expand` — medium effort, valuable for macro development
6. Pretty-printing — highest effort, best deferred

## Key files

| Component | Location |
|-----------|----------|
| REPL loop | `src/main.zig:456-571` |
| Command dispatch | `src/main.zig:507-551` |
| `parenDepth()` | `src/main.zig:427-454` |
| `evalInput()` | `src/main.zig:573-649` |
| Tab completion | `src/main.zig:413-425` |
| Linenoise wrapper | `src/linenoise.zig` |
| Timing primitives | `src/primitives_r7rs.zig` |
| Value printer | `src/printer.zig` |
