# Kaappi

A complete **R7RS-small** Scheme implementation written in **Zig**.

Kaappi implements every identifier from [R7RS Appendix A](https://small.r7rs.org/) — 313 built-in procedures, 32 syntax forms, and all 14 standard libraries. The runtime uses a bytecode compiler with a register-based VM, mark-and-sweep garbage collection, and stack-copying first-class continuations.

---

## Quick start

```bash
zig build run                        # Launch the REPL
zig build run -- program.scm         # Run a Scheme file
zig build test                       # Run all tests
```

> Requires **Zig 0.16+** and a C toolchain (for the vendored linenoise library).

---

## REPL

The REPL features **line editing** (arrow keys, Ctrl-A/E, backspace), **command history** (up/down arrows, persisted to `.kaappi_history`), **tab completion** for all built-in and user-defined symbols, and **multi-line input** with automatic paren balancing.

```
$ zig build run
Kaappi Scheme v0.1.0
Type (exit) to quit.

kaappi> (define (fib n)
  ...     (if (< n 2) n
  ...         (+ (fib (- n 1)) (fib (- n 2)))))
kaappi> (fib 20)
6765
kaappi> (map (lambda (x) (* x x)) '(1 2 3 4 5))
(1 4 9 16 25)
kaappi> `(the answer is ,(* 6 7))
(the answer is 42)
kaappi> (string-length "héllo")
5
kaappi> (char-alphabetic? #\λ)
#t
```

---

## Features

### Complete R7RS-small implementation

315 built-in procedures, 32 syntax forms, all 14 standard libraries — every identifier from [Appendix A](https://small.r7rs.org/).

<details>
<summary>Standard libraries</summary>

| Library | Exports |
|---------|---------|
| `(scheme base)` | 230+ procedures and syntax |
| `(scheme case-lambda)` | `case-lambda` |
| `(scheme char)` | 21 Unicode character procedures |
| `(scheme complex)` | 6 complex number procedures |
| `(scheme cxr)` | 24 car/cdr compositions |
| `(scheme eval)` | `eval`, `environment` |
| `(scheme file)` | 10 file I/O procedures |
| `(scheme inexact)` | 12 transcendental functions |
| `(scheme lazy)` | `delay`, `force`, promises |
| `(scheme load)` | `load` |
| `(scheme process-context)` | `exit`, `command-line`, env vars |
| `(scheme read)` | `read` |
| `(scheme time)` | `current-second`, jiffies |
| `(scheme write)` | `write`, `display`, `write-shared` |

</details>

### Execution

- **Proper tail calls** — `(define (loop n) (loop (+ n 1)))` runs forever without growing the stack
- **First-class continuations** — multi-shot `call/cc` via stack copying, `dynamic-wind` for cleanup
- **Exception handling** — `guard`, `raise`, `with-exception-handler`, typed error objects (`file-error?`, `read-error?`)

### Macros and modules

- **Hygienic macros** — `syntax-rules` with scope-based renaming; pattern variables, ellipsis, literals, underscore wildcards; referential transparency for global references
- **Library system** — `define-library`, `import` with `only`/`except`/`rename`/`prefix`, `.sld` file loading, `cond-expand`

### Data

- **Numeric tower** — fixnum (63-bit), bignum (arbitrary precision), flonum (IEEE 754 f64), complex; automatic promotion on overflow
- **Full Unicode** — UTF-8 strings indexed by codepoint, Unicode character classification (Latin, Greek, Cyrillic, Arabic, Hebrew, CJK, and more), case mapping
- **Vectors and bytevectors** — `#(1 2 3)` and `#u8(10 20 30)` literals, `map`, `for-each`, `copy`, `append`
- **Records** — `define-record-type` with constructors, predicates, field accessors and mutators
- **Ports** — file, string, and bytevector ports; textual and binary I/O; datum labels for shared/circular structures

### Other

- **Lazy evaluation** — `delay`, `delay-force`, `force`, `make-promise`
- **Multiple values** — `values`, `call-with-values`, `let-values`, `let*-values`
- **Parameters** — `make-parameter`, `parameterize` with `dynamic-wind` integration
- **Quasiquote** — `` ` ``, `,`, `,@` with proper splicing and nested quasiquote support
- **REPL** — line editing, persistent history, tab completion, multi-line paren balancing (via [linenoise](https://github.com/antirez/linenoise))

### Data types

| Type | Representation | Allocation |
|------|---------------|------------|
| Integer | 63-bit fixnum or arbitrary-precision bignum | Fixnum: none (tagged); bignum: heap |
| Real | IEEE 754 f64 | Heap |
| Complex | Pair of f64 | Heap |
| Boolean | `#t` / `#f` | None (immediate) |
| Character | 21-bit Unicode codepoint | None (immediate) |
| String | UTF-8 byte array | Heap, codepoint-indexed |
| Symbol | Interned string | Heap, `eq?`-comparable |
| Pair | Car/cdr cons cell | Heap |
| Vector | Value array | Heap, `#(...)` literal syntax |
| Bytevector | Byte array | Heap, `#u8(...)` literal syntax |
| Port | File, string, or bytevector | Heap |
| Procedure | Closure or native function | Heap |
| Continuation | Saved VM state | Heap (stack-copied) |
| Promise | Memoized thunk | Heap |
| Record | User-defined struct | Heap |
| Parameter | Dynamic binding cell | Heap |

---

## Architecture

```
Source code
    │
    ▼
┌────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐     ┌────┐
│ Reader │ ──▶ │ Expander │ ──▶ │ Compiler │ ──▶ │ Bytecode │ ──▶ │ VM │
│ (UTF-8 │     │ (syntax- │     │ (register│     │          │     │    │
│  lexer)│     │  rules)  │     │  -based) │     │          │     │    │
└────────┘     └──────────┘     └──────────┘     └──────────┘     └────┘
                                                                    │
                                                              ┌─────┴─────┐
                                                              │ GC (mark  │
                                                              │ & sweep)  │
                                                              └───────────┘
```

| Component | File | Role |
|-----------|------|------|
| **Reader** | `reader.zig` | Tokenizer + recursive descent parser. Handles full R7RS lexical syntax including Unicode identifiers, `#\λ` character literals, `#(...)` vectors, `#u8(...)` bytevectors. |
| **Expander** | `expander.zig` | `syntax-rules` pattern matching with ellipsis, literal identifiers, underscore wildcards. Template instantiation with hygienic renaming. |
| **Compiler** | `compiler.zig` + 4 sub-modules | Compiles S-expressions to register-based bytecode. Detects tail positions for proper tail call optimization. Handles 32 syntax forms across 5 files. |
| **VM** | `vm.zig` + 3 sub-modules | Executes bytecode with a register file, call frame stack, exception handler stack, and dynamic-wind stack. Supports first-class continuations via stack copying. |
| **GC** | `memory.zig` | Mark-and-sweep collector with intrusive linked list. Root tracking via `pushRoot`/`popRoot`. Triggered after N allocations. |
| **Primitives** | 11 `primitives_*.zig` files | 313 built-in procedures organized by domain: arithmetic, strings, vectors, I/O, control flow, etc. |

### Value representation

Values are **tagged 64-bit words** — common types require zero heap allocation:

```
Fixnum:    [...63-bit signed integer...][1]     ← bit 0 = 1
Pointer:   [...61-bit pointer.........][000]    ← 8-byte aligned heap object
Immediate: [...payload...][type:5][10]          ← nil, bool, void, eof, char
```

---

## Building

```bash
zig build              # Build the kaappi executable
zig build run          # Build and run the REPL
zig build test         # Run all unit tests (~150 tests)
```

The executable is placed in `zig-out/bin/kaappi`.

### Running Scheme files

```bash
# Run a single file
zig build run -- examples/hello.scm

# Pipe expressions
echo '(+ 1 2)' | zig build run
```

---

## Project structure

```
kaappi/
├── build.zig                      Build configuration
├── build.zig.zon                  Package manifest
├── CLAUDE.md                      AI assistant project guide
├── README.md
├── STATUS.md                      R7RS implementation progress
│
├── src/
│   ├── main.zig                   Entry point, REPL (linenoise integration)
│   ├── types.zig                  Value type, heap objects, opcodes
│   ├── memory.zig                 GC allocator (mark-and-sweep)
│   ├── reader.zig                 Tokenizer + S-expression parser
│   ├── expander.zig               Macro expansion (syntax-rules)
│   ├── printer.zig                Value → string (write/display)
│   ├── linenoise.zig              FFI wrapper for C linenoise library
│   ├── library.zig                Library registry + standard libs
│   │
│   ├── compiler.zig               Bytecode compiler (core)
│   ├── compiler_forms.zig         Re-export hub for derived forms
│   ├── compiler_conditionals.zig  and, or, cond, when, unless, cond-expand
│   ├── compiler_bindings.zig      let, letrec, do, let-values
│   ├── compiler_advanced.zig      case, case-lambda, guard, quasiquote
│   │
│   ├── vm.zig                     Register VM (core)
│   ├── vm_library.zig             import / define-library / .sld loading
│   ├── vm_records.zig             define-record-type desugaring
│   ├── vm_continuations.zig       call/cc, dynamic-wind
│   │
│   ├── primitives.zig             Core primitives + registration hub
│   ├── primitives_arithmetic.zig  Numeric procedures (+, -, *, /, trig, etc.)
│   ├── primitives_string.zig      String ops (UTF-8 codepoint-indexed)
│   ├── primitives_char.zig        Unicode char classification + case
│   ├── primitives_vector.zig      Vector procedures
│   ├── primitives_bytevector.zig  Bytevector + binary I/O
│   ├── primitives_io.zig          Ports, file I/O, string ports
│   ├── primitives_control.zig     Exceptions, continuations, values
│   ├── primitives_lazy.zig        delay / force / promises
│   ├── primitives_cxr.zig         24 car/cdr compositions
│   ├── primitives_r7rs.zig        time, process-context, eval, load
│   │
│   ├── testing_helpers.zig        Shared test utilities
│   └── tests_phase*.zig           Unit tests (split by phase)
│
├── tests/scheme/                  Scheme-level test suites
│   ├── phase1/                    Basic eval, arithmetic, lambda
│   ├── phase2/                    Tail calls
│   ├── phase3/                    Derived forms (let, cond, do)
│   ├── phase4/                    Numeric tower
│   ├── phase5/                    Macros
│   ├── phase6/                    Libraries
│   ├── deferred/                  apply, case, case-lambda, complex, etc.
│   └── compliance/                Vectors, strings, chars, Unicode, etc.
│
├── vendor/linenoise/              Vendored C library (BSD)
├── testlib/                       Test .sld library files
└── docs/
    └── errata-corrected-r7rs.pdf  R7RS specification
```

---

## Examples

### Fibonacci

```scheme
(define (fib n)
  (if (< n 2) n
      (+ (fib (- n 1)) (fib (- n 2)))))

(fib 30) ;=> 832040
```

### Tail-recursive factorial

```scheme
(define (factorial n)
  (let loop ((i n) (acc 1))
    (if (= i 0) acc
        (loop (- i 1) (* i acc)))))

(factorial 20) ;=> 2432902008176640000
```

### Macros

```scheme
(define-syntax my-when
  (syntax-rules ()
    ((my-when test body ...)
     (if test (begin body ...)))))

(my-when #t
  (display "hello ")
  (display "world")
  (newline))
```

### Libraries

```scheme
(define-library (mylib math)
  (export square cube)
  (import (scheme base))
  (begin
    (define (square x) (* x x))
    (define (cube x) (* x x x))))

(import (mylib math))
(cube 5) ;=> 125
```

### Continuations

```scheme
(define saved #f)

(+ 1 (call/cc (lambda (k)
                (set! saved k)
                10)))
;=> 11

(saved 42)
;=> 43
```

### Unicode

```scheme
(string-length "héllo")     ;=> 5
(string-ref "λ-calculus" 0) ;=> #\λ
(char-alphabetic? #\λ)      ;=> #t
(string-upcase "héllo")     ;=> "HÉLLO"
```

---

## R7RS conformance

Kaappi implements every identifier from R7RS Appendix A. 4 intentional design choices (no exact rationals, stack-copying continuations, continuation scope, no syntax-case) and 3 low-severity edge cases remain.

See **[CONFORMANCE.md](CONFORMANCE.md)** for the full details: design rationale, gap explanations with code examples and workarounds, and the complete list of verified conformant behaviors.

---

## License

MIT
