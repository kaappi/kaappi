# Kaappi

> **Note:** Kaappi was built with the assistance of AI (Claude by Anthropic).

A complete **R7RS-small** Scheme implementation written in **Zig**.

Kaappi implements every identifier from [R7RS Appendix A](https://small.r7rs.org/) — 420 built-in procedures, 32 syntax forms, and all 14 standard libraries — plus 38 SRFIs, a C FFI, and a stepping debugger. The runtime uses a bytecode compiler with a register-based VM, mark-and-sweep garbage collection, and stack-copying first-class continuations.

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

420 built-in procedures, 32 syntax forms, all 14 standard libraries — every identifier from [Appendix A](https://small.r7rs.org/).

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

- **Numeric tower** — fixnum (63-bit), bignum (arbitrary precision), exact rational, flonum (IEEE 754 f64), complex; automatic promotion on overflow
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

### Beyond R7RS

- **C FFI** — call into shared libraries from Scheme via `(kaappi ffi)`: `ffi-open`, `ffi-fn`, `ffi-close` (supports `int`, `long`, `double`, `float`, `string`, `void`)
- **Stepping debugger** — set breakpoints with `,break`, then step / next / continue and inspect locals and backtraces from the REPL
- **Bytecode caching** — compiled bytecode is cached to `.sbc` files next to the source and reloaded when the source is unchanged, skipping the reader, expander, and compiler

### Data types

| Type | Representation | Allocation |
|------|---------------|------------|
| Integer | 63-bit fixnum or arbitrary-precision bignum | Fixnum: none (tagged); bignum: heap |
| Rational | Exact numerator/denominator pair | Heap |
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
| **Compiler** | `compiler.zig` + 5 sub-modules | Compiles S-expressions to register-based bytecode. Detects tail positions for proper tail call optimization. Handles 32 syntax forms across 6 files. |
| **VM** | `vm.zig` + 5 sub-modules | Executes bytecode with a register file, call frame stack, exception handler stack, and dynamic-wind stack. Supports first-class continuations via stack copying, plus a stepping debugger. |
| **GC** | `memory.zig` | Mark-and-sweep collector with intrusive linked list. Root tracking via `pushRoot`/`popRoot`. Triggered after N allocations. |
| **Primitives** | 18 `primitives_*.zig` files | 420 built-in procedures organized by domain: arithmetic, strings, vectors, I/O, control flow, etc. |

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
├── CONFORMANCE.md                 R7RS conformance notes
│
├── src/
│   ├── main.zig                   Entry point, REPL, file execution, bytecode cache
│   ├── types.zig                  Value type, heap objects, opcodes
│   ├── memory.zig                 GC allocator (mark-and-sweep)
│   ├── bignum.zig                 Arbitrary-precision integer arithmetic
│   ├── reader.zig                 S-expression parser (core)
│   ├── reader_tokens.zig          Tokenizer / UTF-8 lexer
│   ├── reader_datum.zig           Datum parsing, datum labels
│   ├── expander.zig               Macro expansion (syntax-rules)
│   ├── printer.zig                Value → string (write/display)
│   ├── linenoise.zig              FFI wrapper for C linenoise library
│   ├── ffi.zig                    FFI call dispatcher (type marshaling)
│   ├── bytecode_file.zig          Bytecode serialization (.sbc format)
│   ├── library.zig                Library registry + standard libs
│   │
│   ├── compiler.zig               Bytecode compiler (core)
│   ├── compiler_forms.zig         Re-export hub for derived forms
│   ├── compiler_conditionals.zig  and, or, cond, when, unless, cond-expand
│   ├── compiler_bindings.zig      let, letrec, do, let-values
│   ├── compiler_advanced.zig      case, case-lambda, guard, quasiquote
│   ├── compiler_lambda.zig        lambda, define, set!, begin, delay
│   │
│   ├── vm.zig                     Register VM (core)
│   ├── vm_eval.zig                eval, top-level form handling
│   ├── vm_library.zig             import / define-library / .sld loading
│   ├── vm_records.zig             define-record-type desugaring
│   ├── vm_continuations.zig       call/cc, dynamic-wind
│   ├── vm_debug.zig               Stepping debugger (breakpoints, step, locals)
│   │
│   ├── primitives.zig             Core primitives + registration hub
│   ├── primitives_arithmetic.zig  Numeric procedures (+, -, *, /, trig, etc.)
│   ├── primitives_numeric.zig     Rounding, exactness, exact/inexact conversion
│   ├── primitives_string.zig      String ops (UTF-8 codepoint-indexed)
│   ├── primitives_string_ext.zig  SRFI-13 string library (contains, trim, ...)
│   ├── primitives_char.zig        Unicode char classification + case
│   ├── primitives_vector.zig      Vector procedures
│   ├── primitives_bytevector.zig  Bytevector + binary I/O
│   ├── primitives_list.zig        List operations (list-ref, member, ...)
│   ├── primitives_srfi1.zig       SRFI-1 list library (fold, filter, iota, ...)
│   ├── primitives_hashtable.zig   SRFI-69 hash tables
│   ├── primitives_random.zig      SRFI-27 random numbers
│   ├── primitives_io.zig          Ports, file I/O, string ports
│   ├── primitives_filesystem.zig  SRFI-170 POSIX filesystem API
│   ├── primitives_control.zig     Exceptions, continuations, values
│   ├── primitives_lazy.zig        delay / force / promises
│   ├── primitives_cxr.zig         24 car/cdr compositions
│   ├── primitives_ffi.zig         FFI procedures (ffi-open, ffi-fn, ffi-close)
│   ├── primitives_r7rs.zig        time, process-context, eval, load
│   │
│   ├── testing_helpers.zig        Shared test utilities
│   └── tests_*.zig                Unit tests by feature (core_eval, macros, io, …)
│
├── tests/scheme/                  Scheme-level test suites
│   ├── phase1/                    Basic eval, arithmetic, lambda
│   ├── phase2/                    Tail calls
│   ├── phase3/                    Derived forms (let, cond, do)
│   ├── phase4/                    Numeric tower
│   ├── phase5/                    Macros
│   ├── phase6/                    Libraries
│   ├── deferred/                  apply, case, case-lambda, complex, etc.
│   ├── compliance/                Vectors, strings, chars, Unicode, etc.
│   ├── r7rs/                      R7RS feature coverage
│   ├── srfi/                      SRFI conformance suites
│   └── ffi/                       FFI tests
│
├── lib/srfi/                      Portable SRFI .sld libraries
├── vendor/linenoise/              Vendored C library (BSD)
├── testlib/                       Test .sld library files
└── docs/
    ├── guide.md                   User guide
    ├── procedures.md              Procedure reference
    ├── libraries.md               Library authoring guide
    ├── dev/                       Architecture, testing, adding-features
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

## Documentation

| Document | Description |
|----------|-------------|
| [User Guide](docs/guide.md) | Installation, REPL, language tutorial, command-line reference |
| [Procedure Reference](docs/procedures.md) | Built-in procedures with arity and descriptions, organized by domain |
| [Library Authoring Guide](docs/libraries.md) | Writing and using R7RS libraries |
| [Contributing](CONTRIBUTING.md) | How to build, test, and contribute |
| [Architecture](docs/dev/architecture.md) | Pipeline, value representation, GC, file organization |
| [Adding Features](docs/dev/adding-features.md) | Step-by-step guides for extending the implementation |
| [Testing Guide](docs/dev/testing.md) | Unit tests, Scheme tests, benchmarks, CI |
| [R7RS Conformance](CONFORMANCE.md) | Design choices, gaps, and verified behaviors |

---

## R7RS conformance

Kaappi implements every identifier from R7RS Appendix A. 3 intentional design choices (stack-copying continuations, continuation scope, no syntax-case) and 4 low-severity edge cases remain.

See **[CONFORMANCE.md](CONFORMANCE.md)** for the full details: design rationale, gap explanations with code examples and workarounds, and the complete list of verified conformant behaviors.

### SRFI support

38 SRFIs supported (8 built-in, 30 as portable `.sld` files in `lib/srfi/`):

**Built-in:** 1, 9, 13, 27, 39, 69, 133, 170

**Portable:** 2, 8, 11, 14, 16, 26, 28, 31, 34, 41, 111, 117, 125, 128, 132, 141, 143, 145, 151, 152, 158, 174, 175, 189, 219, 222, 227, 232, 233, 235

---

## License

MIT
