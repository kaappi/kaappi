# Your First Program

### Running a file

Create a file called `hello.scm`:

```scheme
(display "Hello, world!")
(newline)
```

Run it:

```bash
zig build run -- hello.scm
```

Output:

```
Hello, world!
```

### The REPL

Launch the REPL with no arguments:

```bash
zig build run
```

```
Kaappi Scheme v0.1.0
Type (exit) to quit.

kaappi>
```

The REPL provides:

- **Line editing** -- arrow keys, Ctrl-A (start of line), Ctrl-E (end of line),
  backspace, delete
- **Command history** -- up/down arrows, persisted across sessions in
  `.kaappi_history`
- **Tab completion** -- completes all built-in and user-defined symbols
- **Multi-line input** -- open parentheses are tracked; the prompt changes to
  `  ... ` until all parens are balanced

```
kaappi> (define (square x)
  ...     (* x x))
kaappi> (square 7)
49
kaappi> (map square '(1 2 3 4 5))
(1 4 9 16 25)
```

Type `(exit)` or press Ctrl-D to quit.

---

