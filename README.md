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

### R7RS compliance

All 14 standard libraries are implemented:

| Library | Procedures | Status |
|---------|-----------|--------|
| `(scheme base)` | 230+ | Complete |
| `(scheme case-lambda)` | 1 | Complete |
| `(scheme char)` | 21 | Complete |
| `(scheme complex)` | 6 | Complete |
| `(scheme cxr)` | 24 | Complete |
| `(scheme eval)` | 2 | Complete |
| `(scheme file)` | 10 | Complete |
| `(scheme inexact)` | 12 | Complete |
| `(scheme lazy)` | 5 | Complete |
| `(scheme load)` | 1 | Complete |
| `(scheme process-context)` | 5 | Complete |
| `(scheme read)` | 1 | Complete |
| `(scheme time)` | 3 | Complete |
| `(scheme write)` | 4 | Complete |

### Language features

- **Proper tail calls** — iterative recursion in constant stack space
- **First-class continuations** — `call/cc` (multi-shot, stack-copying), `call/ec` (O(1) escape), `dynamic-wind`
- **Hygienic macros** — `syntax-rules` with pattern matching, ellipsis, and literals
- **Library system** — `define-library`, `import` with `only`/`except`/`rename`/`prefix` modifiers, `.sld` file loading
- **Numeric tower** — fixnum (i64), flonum (f64), complex numbers, mixed arithmetic
- **Full Unicode** — UTF-8 strings with codepoint-based indexing, character classification across many scripts (Latin, Greek, Cyrillic, Arabic, Hebrew, CJK, and more), and case mapping for cased scripts (Latin, Greek, Cyrillic)
- **Exception handling** — `guard`, `raise`, `with-exception-handler`, error objects
- **Records** — `define-record-type` with constructors, predicates, accessors, mutators
- **Ports and I/O** — file, string, and bytevector ports; binary and textual I/O
- **Lazy evaluation** — `delay`, `delay-force`, `force`, promises
- **Multiple values** — `values`, `call-with-values`, `let-values`, `let*-values`
- **Parameter objects** — `make-parameter`, `parameterize` with dynamic-wind integration
- **Vectors and bytevectors** — mutable arrays with `map`, `for-each`, `copy`, `append`
- **Quasiquote** — `` ` ``, `,`, `,@` with proper splicing support

### Data types

| Type | Representation | Notes |
|------|---------------|-------|
| Integer | 63-bit signed fixnum | Tagged in low bit of u64, zero allocation |
| Real | IEEE 754 f64 | Heap-allocated |
| Complex | Pair of f64 | `make-rectangular`, `make-polar` |
| Boolean | Immediate `#t` / `#f` | Only `#f` is falsy |
| Character | 21-bit Unicode codepoint | Immediate value, supports full Unicode |
| String | UTF-8 byte array | Codepoint-indexed, heap-allocated |
| Symbol | Interned string | `eq?`-comparable |
| Pair | Car/cdr cons cell | Heap-allocated |
| Vector | Growable value array | `#(1 2 3)` literal syntax |
| Bytevector | Byte array | `#u8(10 20 30)` literal syntax |
| Port | File descriptor or buffer | File, string, and bytevector ports |
| Procedure | Closure or native fn | First-class, supports `apply` |
| Continuation | Saved VM state | Created by `call/cc` |
| Promise | Lazy thunk | Created by `delay` |
| Record | User-defined struct | Created by `define-record-type` |
| Parameter | Dynamic binding | Created by `make-parameter` |

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

## Known limitations

- **No bignum**: Integers are 63-bit signed fixnums. Overflow wraps silently.
- **No exact rationals**: `/` with non-divisible exact integers returns an inexact (flonum) result. Rational syntax (`1/2`) is not parsed.
- **Multi-shot continuations copy the stack**: `call/cc` snapshots the full VM state — correct and re-entrant, but O(stack depth) per capture.
- **Continuations are scoped to one top-level form**: a continuation captured in one expression cannot re-enter subsequent top-level expressions. Wrap in `(begin ...)` to span them.
- **Unicode case mapping**: Covers Latin (incl. Extended-A/B), Greek, and Cyrillic. Other scripts pass through unchanged.
- **No `syntax-case`**: Only `syntax-rules` is supported (as specified by R7RS-small).

---

## R7RS conformance notes

Kaappi implements every identifier from R7RS Appendix A. The following documents intentional design choices, known deviations, and edge-case behaviors relative to the spec.

### By design

| Area | Behavior | R7RS reference |
|------|----------|---------------|
| **No bignum** | Integers are 63-bit signed fixnums. Overflow wraps silently. | §6.2.3 allows limited range |
| **No exact rationals** | `/` with non-divisible exact integers returns an inexact flonum. `inexact->exact` truncates to the nearest integer instead of producing a rational. | §6.2.3 allows omitting rational type |
| **No rational syntax** | `1/2`, `22/7` are not parsed by the reader. Use `(/ 1 2)` instead (returns `0.5`). | §6.2.5 |
| **Stack-copying continuations** | `call/cc` snapshots the full VM state (registers, frames, handlers, wind stack). Fully re-entrant but O(depth) per capture. | §6.10 |
| **Continuation scope** | A multi-shot continuation captured in one top-level form cannot re-enter *subsequent* top-level forms (the REPL evaluates forms one at a time). Wrap in `(begin ...)` to span multiple forms. | Implementation detail |
| **No `syntax-case`** | Only `syntax-rules` is supported. | R7RS-small specifies `syntax-rules` only |

### Known deviations

#### Numeric

- **Division by zero** signals a VM-level error that crashes instead of raising a catchable Scheme error object. `(guard (e (#t 'caught)) (/ 1 0))` does not catch it. R7RS says this should be a continuable error (§6.2.6).
- **`inexact->exact`** truncates: `(inexact->exact 1.5)` → `1`, not `3/2`. This is because there is no rational type — the spec allows this but recommends returning the closest exact value.

#### Reader

- **No radix prefixes**: `#b1010`, `#o17`, `#xff` are not recognized. Only decimal integers and floats are parsed. Use procedures like `(string->number "ff" 16)` instead.
- **No exactness prefixes**: `#e1.5`, `#i3` are not recognized.
- **No datum labels**: `#0=(a b . #0#)` for shared/circular structure is not supported. Use `set-car!`/`set-cdr!` to build circular structures.
- **No `#!fold-case`/`#!no-fold-case`** directives.
- **No `\x` hex escapes in `|quoted identifiers|`**: `|H\x65;llo|` is not recognized. Plain `|Hello|` works.
- **Nested quasiquote**: `` `(a `(b ,(+ 1 2))) `` treats the inner quasiquote as a literal datum rather than fully expanding at the correct depth.

#### Tail positions

- **`when` and `unless`** do not propagate tail position to their body. R7RS §3.5 says the last expression should be in tail context when the form itself is. In Kaappi, all body expressions in `when`/`unless` are compiled as non-tail.

#### Macros

- **Hygiene is incomplete**: `syntax-rules` templates do not rename identifiers introduced by the template via gensym. Simple macros work correctly, but macros that introduce bindings (`let`, temporary variables) may capture user-level variables in edge cases. R7RS §4.3.2 requires fresh identifiers for template-introduced bindings.

#### Strings and immutability

- **Literal strings are mutable**: `(string-set! "hello" 0 #\H)` succeeds instead of signaling an error. R7RS §3.4 says literals are immutable.
- **`symbol->string` returns a mutable string**: the spec says it must be immutable (§6.5).

#### Error types

- **`file-error?` and `read-error?`** always return `#f`. Errors from file operations and the reader are plain error objects, not tagged subtypes. R7RS §6.11 says I/O errors should satisfy `file-error?` and reader errors should satisfy `read-error?`.
- **`write-shared` and `write-simple`** are aliases for `write`. No shared-structure detection or datum-label output is performed. Writing circular structures may loop. R7RS §6.13.3 distinguishes these.

#### Other

- **`case` with `=>`**: The arrow form `((datum ...) => proc)` is not supported in `case` expressions. Only the standard `((datum ...) expr ...)` and `(else expr ...)` forms work. The `=>` form in `cond` works correctly.
- **`letrec` restriction not enforced**: `(letrec ((x y) (y 1)) x)` silently evaluates (`x` binds to void) instead of signaling an error. R7RS §4.2.2 says referring to another binding's variable in an init is an error.
- **Multiple values in wrong context**: `(let ((x (values 1 2))) x)` returns a `#<values>` object instead of signaling an error. R7RS says it's an error to pass multiple values to a continuation that expects one (§6.10).
- **Unicode case mapping**: Covers Latin (including Extended-A/B), Greek, and Cyrillic. Other scripts (Arabic, Devanagari, etc.) pass through `char-upcase`/`char-downcase` unchanged.
- **`equal?` on circular structures**: Terminates via pointer-equality short-circuit (`(equal? x x)` → `#t`) but does not implement the full R7RS algorithm for structurally comparing two distinct circular objects. Comparing two different circular structures with the same shape may loop.

### Fully conformant areas

These areas have been tested and match R7RS behavior:

- Proper tail calls in `if`, `begin`, `cond`, `case`, `and`, `or`, `let`/`let*`/`letrec`/`letrec*`, `do`, `guard`, `parameterize`, lambda bodies
- NaN handling: `(eqv? +nan.0 +nan.0)` → `#t`, `(= +nan.0 +nan.0)` → `#f`
- Negative zero: `(eqv? 0.0 -0.0)` → `#f`, `(= 0.0 -0.0)` → `#t`
- Library single-load guarantee: importing the same library twice only evaluates its body once
- `dynamic-wind` before/after thunks fire correctly on normal return and continuation escape
- `values`/`call-with-values` protocol
- `delay`/`force` with memoization
- `define-record-type` with constructors, predicates, accessors, mutators
- `syntax-rules` with ellipsis, literals, underscore, multiple rules
- `cond-expand` with `r7rs`, `kaappi`, `ieee-float`, `posix` features and `(library ...)` checks
- All 14 standard libraries registered and importable

---

## License

MIT
