<p align="center">
  <img src="https://kaappi.github.io/assets/logo.svg" alt="Kaappi" width="200">
</p>

<h1 align="center">Kaappi</h1>

> **Note:** Kaappi was built with the assistance of AI (Claude by Anthropic).

A complete **R7RS-small** Scheme implementation written in **Zig**.

Kaappi implements every identifier from [R7RS Appendix A](https://small.r7rs.org/) — 554 built-in procedures, 32 syntax forms, and all 14 standard libraries — plus 51 SRFIs, a C FFI, and a stepping debugger. The runtime uses a bytecode compiler with a register-based VM, mark-and-sweep garbage collection, and stack-copying first-class continuations.

---

## Quick start

```bash
zig build run                        # Launch the REPL
zig build run -- program.scm         # Run a Scheme file
zig build test                       # Run all tests
```

> Requires **Zig 0.16+** and a C toolchain (for the vendored linenoise library).

### Supported platforms

| OS | Architecture | Build | Tests | JIT |
|----|-------------|-------|-------|-----|
| macOS | aarch64 (Apple Silicon) | yes | 347/347 | yes (native AArch64) |
| Linux | x86_64 | yes | 312/320 (8 skip) | yes (native x86_64) |
| Linux | aarch64 | yes | yes | yes (native AArch64) |
| Linux | riscv64 | yes | yes | no (interpreter only) |
| WebAssembly | wasm32-wasi | yes | — | no (interpreter only) |

The WASM build (`zig build wasm`) runs in browsers and WASI runtimes. See the
[playground](https://kaappi-lang.org/playground/) for a live demo.

Windows is not supported. Kaappi depends on POSIX APIs (mmap, signals) and linenoise (terminal I/O).

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

554 built-in procedures, 32 syntax forms, all 14 standard libraries — every identifier from [Appendix A](https://small.r7rs.org/).

<details>
<summary>Standard libraries</summary>

| Library | Exports |
|---------|---------|
| `(scheme base)` | 230+ procedures and syntax |
| `(scheme case-lambda)` | `case-lambda` |
| `(scheme char)` | 22 Unicode character procedures |
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

- **C FFI** — call into shared libraries from Scheme via `(kaappi ffi)`: `ffi-open`, `ffi-fn`, `ffi-close`, plus `ffi-callback` for passing Scheme procedures to C (7 callback signatures, 18 types including explicit-width integers and `size_t`)
- **JIT compiler** — hot functions (100+ calls) are compiled to native machine code (AArch64 and x86_64); inline fixnum arithmetic, comparisons, `car`/`cdr`, `cons`, predicates; JIT-to-JIT call chaining
- **Green threads** — `(kaappi fibers)` with `spawn`, `yield`, `fiber-join`, channels; plus full SRFI-18 compatibility (`make-thread`, mutexes, condition variables)
- **Profiler** — `kaappi --profile` or `,profile expr` in the REPL; per-function self/total time, call counts, allocation bytes
- **Standalone binaries** — `zig build -Dbundle-src=program.scm` compiles and embeds bytecode + libraries into a single executable
- **Sandbox mode** — `kaappi --sandbox` blocks FFI, file I/O, `eval`, `load`, and environment access
- **Stepping debugger** — set breakpoints with `,break`, then step / next / continue and inspect locals and backtraces from the REPL
- **Bytecode caching** — compiled `.sbc` files are reloaded when the source is unchanged, skipping the reader, expander, and compiler

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
| **Primitives** | 21 `primitives_*.zig` files | 554 built-in procedures organized by domain: arithmetic, strings, vectors, I/O, control flow, etc. |

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
│   ├── primitives_srfi18.zig      SRFI-18 threads, mutexes, conditions
│   ├── primitives_hashtable.zig   SRFI-69 hash tables (open-addressing)
│   ├── primitives_random.zig      SRFI-27 random numbers
│   ├── primitives_fiber.zig       Fiber-based concurrency
│   ├── primitives_io.zig          Ports, file I/O, string ports
│   ├── primitives_filesystem.zig  SRFI-170 POSIX filesystem API
│   ├── primitives_control.zig     Exceptions, continuations, values
│   ├── primitives_lazy.zig        delay / force / promises
│   ├── primitives_cxr.zig         24 car/cdr compositions
│   ├── primitives_ffi.zig         FFI procedures (ffi-open, ffi-fn, ffi-close)
│   ├── primitives_r7rs.zig        time, process-context, eval, load
│   ├── unicode_tables.zig         Unicode 15.1 case mapping tables (auto-generated)
│   ├── jit.zig                    JIT compiler (arch dispatch + code gen)
│   ├── jit_aarch64.zig            AArch64 instruction encoding
│   ├── jit_x86_64.zig             x86_64 instruction encoding
│   ├── jit_mem.zig                Executable memory allocation
│   ├── disassembler.zig           Bytecode disassembler
│   │
│   ├── testing_helpers.zig        Shared test utilities
│   └── tests_*.zig                Unit tests by feature (core_eval, macros, io, …)
│
├── tests/scheme/                  Scheme-level test suites
│   ├── r7rs/                      R7RS test suite (1,380 tests via chibi test)
│   ├── smoke/                     Quick sanity checks (basic, tail-calls, macros, etc.)
│   ├── compliance/                Targeted conformance tests by topic
│   ├── continuations/             Advanced call/cc and call/ec edge cases
│   ├── hygiene/                   Macro hygiene edge cases
│   ├── srfi/                      SRFI conformance suites
│   ├── ffi/                       FFI tests
│   └── run-all.sh                 Run all test suites with summary
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

## Ecosystem

Kaappi has a growing ecosystem of libraries for web development, databases, and networking. Install them with **thottam** (the Kaappi package manager):

```bash
# Install the web framework (auto-installs kaappi-http, kaappi-json, kaappi-net)
thottam install kaappi-web

# Now just works — no --lib-path flags needed
kaappi app.scm
```

| Package | Description | Install |
|---------|-------------|---------|
| [kaappi-net](https://github.com/kaappi/kaappi-net) | TCP/TLS networking (shared by all network libraries) | `thottam install kaappi-net` |
| [kaappi-redis](https://github.com/kaappi/kaappi-redis) | Redis client — SET/GET, lists, hashes, pub/sub, pipelining | `thottam install kaappi-redis` |
| [kaappi-pg](https://github.com/kaappi/kaappi-pg) | PostgreSQL client — DB-API 2.0 style with cursors and type conversion | `thottam install kaappi-pg` |
| [kaappi-http](https://github.com/kaappi/kaappi-http) | HTTP/HTTPS client + server (pre-fork, threaded) | `thottam install kaappi-http` |
| [kaappi-json](https://github.com/kaappi/kaappi-json) | JSON parser and serializer | `thottam install kaappi-json` |
| [kaappi-web](https://github.com/kaappi/kaappi-web) | Web framework — routing, middleware, JSON helpers | `thottam install kaappi-web` |
| [kaappi-examples](https://github.com/kaappi/kaappi-examples) | REST API, task queue, CRUD app, file server | — |

### Quick example: REST API

```scheme
(import (kaappi web) (kaappi pg) (kaappi json))

(define db (pg-connect "dbname=myapp"))

(define app
  (routes
    (GET "/users/:id"
      (lambda (req params)
        (let ((rows (pg-query db "SELECT * FROM users WHERE id = $1"
                      (param/number params "id"))))
          (json-response (if (null? rows) '(("error" . "not found"))
                             (car rows))))))
    (POST "/users"
      (lambda (req params)
        (let ((body (request-json req)))
          (pg-exec db "INSERT INTO users (name) VALUES ($1)"
            (cdr (assoc "name" body)))
          (json-response '(("created" . #t)) 201))))))

(serve (wrap app wrap-json-body wrap-logging wrap-errors) 8080)
```

### thottam commands

```bash
thottam install <package>    # Install a package and its dependencies
thottam remove <package>     # Remove a package
thottam list                 # List installed packages
thottam update [package]     # Update one or all packages
```

Packages are installed to `~/.kaappi/lib/` and discovered automatically.

---

## Concurrency

### Green threads (fibers)

Cooperative multitasking within a single OS thread:

```scheme
(import (kaappi fibers))

(define ch (make-channel))

(spawn (lambda ()
  (channel-send ch "hello from fiber")))

(display (channel-receive ch))  ;=> hello from fiber
```

### OS threads (SRFI-18)

Real OS threads via `pthread_create` — each thread gets its own VM and GC:

```scheme
(import (srfi 18))

(define t (thread-start!
  (make-thread
    (lambda ()
      (display "running on OS thread")
      (newline)))))

(thread-join! t)
```

OS threads enable true parallel I/O (e.g., thread-per-connection HTTP servers).

---

## Documentation

| Document | Description |
|----------|-------------|
| [User Guide](https://kaappi.github.io/guide/) | Installation, REPL, language tutorial, command-line reference |
| [Procedure Reference](https://kaappi.github.io/procedures/) | Built-in procedures with arity and descriptions, organized by domain |
| [Library Reference](https://kaappi.github.io/libraries/) | 51 SRFIs, standard libraries, and how to write your own |
| [Contributing](CONTRIBUTING.md) | How to build, test, and contribute |
| [Architecture](docs/dev/architecture.md) | Pipeline, value representation, GC, file organization |
| [Adding Features](docs/dev/adding-features.md) | Step-by-step guides for extending the implementation |
| [Testing Guide](docs/dev/testing.md) | Unit tests, Scheme tests, benchmarks, CI |
| [R7RS Conformance](CONFORMANCE.md) | Design choices and SRFI coverage |

---

## R7RS conformance

Kaappi implements every identifier from R7RS Appendix A with no known functional gaps. 3 intentional architectural decisions are documented (stack-copying continuations, continuation scope, no syntax-case) — all standard across Scheme bytecode interpreters.

See **[CONFORMANCE.md](CONFORMANCE.md)** for design rationale and SRFI coverage details.

### SRFI support

51 SRFIs supported (8 built-in, 43 as portable `.sld` files in `lib/srfi/`):

**Built-in:** 1, 9, 13, 18, 39, 69, 133, 170

**Portable:** 2, 8, 11, 14, 16, 26, 27, 28, 31, 34, 35, 36, 41, 48, 64, 98, 111, 113, 115, 117, 125, 128, 132, 141, 143, 145, 146, 151, 152, 158, 166, 174, 175, 189, 195, 196, 210, 219, 222, 227, 232, 233, 235

---

## Known limitations

### Continuations

`call/cc` captures continuations by copying the full VM state (registers, call frames, exception handlers, dynamic-wind stack). Cost is O(stack depth) per capture — negligible for most programs, but noticeable if continuations are captured in tight inner loops. Continuations captured in one top-level REPL expression cannot re-enter subsequent top-level expressions (standard behavior shared by Guile, Chibi, Chicken, Chez, and Racket).

### OS threads (SRFI-18)

Each OS thread gets its own GC with an independent heap. Values are deep-copied when crossing thread boundaries (at `thread-start!` and `thread-join!`). This means threads cannot share mutable state directly — use channels or return values to communicate. Child threads can allocate and GC independently without affecting the parent.

### JIT compiler

AArch64 and x86_64 backends are both fully implemented: inline fixnum arithmetic with overflow detection, comparisons, predicates (`zero?`, `null?`, `pair?`, `not`, `car`, `cdr`), `cons` allocation, global variable access with inline caching, full call sequences with JIT-to-JIT chaining, and optimized self-recursive calls. RISC-V runs interpreter-only (no JIT backend). Use `--no-jit` to disable.

Tail calls to known primitives (`+`, `-`, `*`, `<`, etc.) are specialized inline via peephole analysis, avoiding side-exits. The JIT currently shows no measurable speedup on standard benchmarks (fib, tak, ackermann) because the interpreter's NativeFn fast path already calls primitives directly via function pointer without frame construction, and the JIT does not yet perform inter-instruction register allocation. Future work: register allocation across instructions to reduce redundant frame memory loads/stores.

### Macros

Only `syntax-rules` is supported. `syntax-case` was intentionally excluded from R7RS-small and is not implemented.

### SRFI coverage

51 SRFIs are supported. Some built-in SRFIs have minor coverage gaps (e.g., linear-update variants in SRFI-1, `string-xcopy!` in SRFI-13). See [CONFORMANCE.md](CONFORMANCE.md) for per-SRFI details.

---

## License

MIT
