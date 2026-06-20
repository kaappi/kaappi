# Kaappi Scheme User Guide

Kaappi is a complete R7RS-small Scheme implementation written in Zig. It provides
a bytecode compiler, register-based VM, mark-and-sweep garbage collector,
first-class continuations, hygienic macros, and a full library system.

---

## Installation

### Prerequisites

- **Zig 0.16+** -- the sole build tool (no cmake, make, or cargo)
- **C toolchain** -- needed to compile the vendored linenoise library (line
  editing for the REPL). On macOS this comes with Xcode Command Line Tools; on
  Linux it comes with `gcc` or `clang`.

### macOS

```bash
brew install zig
git clone <repo-url> kaappi
cd kaappi
zig build
```

### Linux

Download Zig 0.16+ from [ziglang.org/download](https://ziglang.org/download/),
extract it, and add it to your `PATH`. Then:

```bash
git clone <repo-url> kaappi
cd kaappi
zig build
```

### Verify the build

The executable is placed at `zig-out/bin/kaappi`:

```bash
./zig-out/bin/kaappi --help
```

Run the test suite to confirm everything works:

```bash
zig build test
```

### Build modes

The default build uses **ReleaseSafe** (fast execution with bounds checking).
For maximum throughput use `-Doptimize=ReleaseFast`. The Debug mode is roughly
500x slower for allocation-heavy workloads -- only use it when debugging the
runtime itself:

```bash
zig build -Doptimize=Debug
```

---

## Your First Program

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

## Language Quick Reference

### Numbers

Kaappi supports fixnums (63-bit integers), bignums (arbitrary precision),
exact rationals, flonums (IEEE 754 f64), and complex numbers.

```scheme
(+ 1 2 3)              ;=> 6
(* 2.5 4)              ;=> 10.0
(expt 2 100)           ;=> 1267650600228229401496703205376
(/ 1 3)                ;=> 1/3
(+ 1/3 1/6)            ;=> 1/2
(sqrt -1)              ;=> 0+1i
(make-rectangular 3 4) ;=> 3+4i
```

### Strings

Strings are UTF-8 encoded and indexed by codepoint position.

```scheme
(string-length "hello")       ;=> 5
(string-ref "hello" 1)        ;=> #\e
(substring "hello" 1 4)       ;=> "ell"
(string-append "foo" "bar")   ;=> "foobar"
(string-upcase "hello")       ;=> "HELLO"
(string-length "héllo")       ;=> 5
(string-ref "lambda: λ" 8)   ;=> #\λ
```

### Lists

```scheme
(cons 1 '(2 3))        ;=> (1 2 3)
(car '(a b c))          ;=> a
(cdr '(a b c))          ;=> (b c)
(list 1 2 3)            ;=> (1 2 3)
(map (lambda (x) (* x x)) '(1 2 3))  ;=> (1 4 9)
(filter odd? '(1 2 3 4 5))           ;=> (1 3 5)
(fold + 0 '(1 2 3 4 5))              ;=> 15
```

### Vectors

```scheme
(define v #(10 20 30))
(vector-ref v 1)        ;=> 20
(vector-set! v 0 99)
(vector-map + #(1 2 3) #(10 20 30))  ;=> #(11 22 33)
```

### Booleans, Characters, Symbols

```scheme
(and #t #f)             ;=> #f
(or #f 42)              ;=> 42
(char-alphabetic? #\A)  ;=> #t
(char-upcase #\a)       ;=> #\A
(symbol? 'hello)        ;=> #t
(eq? 'abc 'abc)         ;=> #t
```

### Bytevectors

```scheme
(define bv #u8(10 20 30))
(bytevector-u8-ref bv 0)     ;=> 10
(bytevector-length bv)        ;=> 3
(utf8->string #u8(104 101 108 108 111))  ;=> "hello"
```

### Definitions and Functions

```scheme
(define x 42)
(define (add a b) (+ a b))
(add x 8)              ;=> 50

(define greet
  (lambda (name)
    (string-append "Hello, " name "!")))
(greet "World")         ;=> "Hello, World!"
```

### Conditionals

```scheme
(if (> 3 2) "yes" "no")       ;=> "yes"

(cond
  ((< x 0) "negative")
  ((= x 0) "zero")
  (else     "positive"))       ;=> "positive"

(case (+ 1 1)
  ((1) "one")
  ((2) "two")
  (else "other"))              ;=> "two"
```

### Binding Forms

```scheme
(let ((x 1) (y 2)) (+ x y))            ;=> 3
(let* ((x 1) (y (+ x 1))) (+ x y))     ;=> 3
(letrec ((even? (lambda (n)
                  (if (= n 0) #t (odd? (- n 1)))))
         (odd?  (lambda (n)
                  (if (= n 0) #f (even? (- n 1))))))
  (even? 10))                           ;=> #t

;; Named let (loop)
(let loop ((n 5) (acc 1))
  (if (= n 0) acc
      (loop (- n 1) (* n acc))))        ;=> 120

;; do
(do ((i 0 (+ i 1))
     (sum 0 (+ sum i)))
    ((= i 5) sum))                      ;=> 10
```

### Macros

```scheme
(define-syntax my-when
  (syntax-rules ()
    ((my-when test body ...)
     (if test (begin body ...)))))

(my-when (> 3 2)
  (display "yes")
  (newline))
;; prints: yes
```

### Exceptions

```scheme
(guard (exn
        ((string? (error-object-message exn))
         (display "Caught: ")
         (display (error-object-message exn))
         (newline)))
  (error "something went wrong" 42))
;; prints: Caught: something went wrong

(with-exception-handler
  (lambda (e) (display "Error!\n"))
  (lambda () (raise "boom"))
  'replace)
```

### Continuations

```scheme
;; Escape continuation (non-local exit)
(call/cc (lambda (exit)
  (for-each (lambda (x)
              (when (negative? x) (exit x)))
            '(1 2 -3 4))
  'all-positive))
;=> -3
```

### Parameters

```scheme
(define my-param (make-parameter 10))
(my-param)              ;=> 10

(parameterize ((my-param 42))
  (my-param))            ;=> 42

(my-param)              ;=> 10
```

### Lazy Evaluation

```scheme
(define p (delay (begin (display "computed!\n") 42)))
(force p)  ;; prints "computed!" then returns 42
(force p)  ;; returns 42 (cached, no recomputation)
```

### Records

```scheme
(define-record-type <point>
  (make-point x y)
  point?
  (x point-x)
  (y point-y set-point-y!))

(define p (make-point 3 4))
(point-x p)             ;=> 3
(set-point-y! p 10)
(point-y p)             ;=> 10
```

### Multiple Values

```scheme
(call-with-values
  (lambda () (values 1 2 3))
  (lambda (a b c) (+ a b c)))  ;=> 6

(let-values (((a b) (values 1 2)))
  (+ a b))                     ;=> 3
```

---

## Working with Libraries

### Importing Standard Libraries

Every R7RS program starts by importing what it needs:

```scheme
(import (scheme base))
(import (scheme write))
(display (+ 1 2))
(newline)
```

Multiple imports can be combined:

```scheme
(import (scheme base)
        (scheme write)
        (scheme char))
```

### Import Modifiers

```scheme
;; Import only specific names
(import (only (scheme base) map filter))

;; Import everything except certain names
(import (except (scheme base) error))

;; Rename on import
(import (rename (scheme base) (map scheme-map)))

;; Add a prefix to all imported names
(import (prefix (scheme char) char:))
(char:char-alphabetic? #\A)  ;=> #t
```

### Standard Libraries

| Library | Contents |
|---------|----------|
| `(scheme base)` | 230+ core procedures and syntax |
| `(scheme case-lambda)` | `case-lambda` dispatch |
| `(scheme char)` | Unicode character classification and case |
| `(scheme complex)` | Complex number operations |
| `(scheme cxr)` | 24 car/cdr compositions (caaar through cddddr) |
| `(scheme eval)` | `eval`, `environment` |
| `(scheme file)` | File I/O operations |
| `(scheme inexact)` | Transcendental math (sin, cos, exp, log, ...) |
| `(scheme lazy)` | `delay`, `force`, promises |
| `(scheme load)` | `load` |
| `(scheme process-context)` | `exit`, `command-line`, environment variables |
| `(scheme read)` | `read` |
| `(scheme time)` | `current-second`, jiffies |
| `(scheme write)` | `write`, `display`, `write-shared` |

### SRFI Libraries

| Library | Contents |
|---------|----------|
| `(srfi 1)` | List library (fold, filter, find, any, every, iota, ...) |
| `(srfi 9)` | Records (alias for R7RS define-record-type) |
| `(srfi 13)` | String library (contains, prefix?, split, join, trim, ...) |
| `(srfi 18)` | Threads, mutexes, condition variables |
| `(srfi 27)` | Random numbers (random-integer, random-real) |
| `(srfi 39)` | Parameter objects (alias for R7RS make-parameter) |
| `(srfi 69)` | Hash tables |
| `(srfi 133)` | Vector library |
| `(srfi 170)` | POSIX filesystem API (file-info, directory ops, ...) |

43 additional SRFIs are available as portable `.sld` files: 2, 8, 11, 14, 16, 26, 28, 31, 34, 35, 36, 41, 48, 64, 98, 111, 113, 115, 117, 125, 128, 132, 141, 143, 145, 146, 151, 152, 158, 166, 174, 175, 189, 195, 196, 210, 219, 222, 227, 232, 233, 235.

### Writing Your Own Library

Create a file `mylib/math.sld`:

```scheme
(define-library (mylib math)
  (export square cube factorial)
  (import (scheme base))
  (begin
    (define (square x) (* x x))
    (define (cube x) (* x x x))
    (define (factorial n)
      (let loop ((i n) (acc 1))
        (if (= i 0) acc
            (loop (- i 1) (* i acc)))))))
```

Use it from another file:

```scheme
(import (mylib math))
(display (factorial 10))  ;=> 3628800
(newline)
```

### Library Search Paths

Kaappi searches for `.sld` files in this order:

1. The current directory (`./`)
2. The `./lib/` subdirectory
3. Directories specified with `--lib-path`

The library name `(mylib math)` maps to the file path `mylib/math.sld`.

```bash
zig build run -- --lib-path /path/to/libs program.scm
```

See [docs/libraries.md](libraries.md) for the complete library authoring guide.

---

## Advanced Features

### FFI (Foreign Function Interface)

Call C library functions directly from Scheme:

```scheme
(import (kaappi ffi))

;; Open a shared library
(define libm (ffi-open "libm.dylib"))  ;; macOS
;; (define libm (ffi-open "libm.so.6"))  ;; Linux

;; Bind a C function: (ffi-fn lib "name" (param-types ...) return-type)
(define c-sqrt (ffi-fn libm "sqrt" '(double) 'double))
(define c-pow  (ffi-fn libm "pow"  '(double double) 'double))

(c-sqrt 2.0)     ;=> 1.4142135623730951
(c-pow 2.0 10.0) ;=> 1024.0

;; Clean up
(ffi-close libm)
```

Supported C types: `int`, `long`, `double`, `float`, `string`, `pointer`, `void`.

**FFI callbacks** — pass Scheme procedures to C functions that expect function pointers:

```scheme
(define cb (ffi-callback (lambda (a b) (- a b)) '(pointer pointer) 'int))
;; Pass cb to a C function like qsort
(ffi-callback-release cb)  ;; free when done
```

### Bytecode Caching

Kaappi automatically caches compiled bytecode to `.sbc` files next to the
source. On subsequent runs, if the source hasn't changed, the cached bytecode
is loaded directly -- skipping the reader, expander, and compiler stages.

```bash
# Explicitly compile to bytecode
zig build run -- --compile program.scm
# Output: Compiled program.scm -> program.sbc

# Subsequent runs use the cache automatically
zig build run -- program.scm
```

### Debugger

The REPL includes a built-in stepping debugger.

**Setting breakpoints:**

```
kaappi> ,break factorial
Breakpoint set on factorial
```

**Running with breakpoints:**

When a breakpoint is hit, the debugger pauses and shows a `debug>` prompt:

```
kaappi> (factorial 5)
Break at factorial (<repl>:1)
debug>
```

**Debugger commands:**

| Command | Short | Action |
|---------|-------|--------|
| `step` | `s` | Step into the next expression |
| `next` | `n` | Step over (stay in current frame) |
| `continue` | `c` | Continue to next breakpoint |
| `locals` | `l` | Show local variable bindings |
| `backtrace` | `bt` | Print the call stack |
| `quit` | `q` | Exit the debugger |

**Other REPL debug commands:**

```
,break name        -- Set a breakpoint on a function
,breakpoints       -- List all breakpoints
,delete all        -- Remove all breakpoints
,step (expr)       -- Step through an expression from the start
```

---

## Command-Line Reference

```
zig build run -- [OPTIONS] [FILE]
```

| Option | Description |
|--------|-------------|
| *(no arguments)* | Launch the REPL |
| `FILE` | Run a Scheme source file |
| `--compile FILE` | Compile to bytecode (.sbc) without running |
| `--lib-path DIR` | Add a directory to the library search path (repeatable) |
| `--profile` | Profile execution (per-function timing, call counts, allocations) |
| `--sandbox` | Sandbox mode — blocks FFI, file I/O, `eval`, `load`, env access |
| `--no-jit` | Disable JIT compilation |
| `--no-cache` | Disable bytecode caching |
| `--gc-stats` | Print GC statistics on exit |

**Standalone binaries:**

```bash
zig build -Dbundle-src=program.scm    # compile + embed in one step
zig build -Dbundle=program.sbc        # embed pre-compiled bytecode
```

### Examples

```bash
# REPL
zig build run

# Run a file
zig build run -- program.scm

# Run with additional library paths
zig build run -- --lib-path ./vendor/libs --lib-path ./mylibs program.scm

# Compile only
zig build run -- --compile mylib.scm

# Pipe input
echo '(+ 1 2)' | zig build run

# Build and install
zig build
cp zig-out/bin/kaappi /usr/local/bin/
```

---

## Tips

- **Tail calls are optimized.** Write loops as recursive calls without worrying
  about stack overflow:

  ```scheme
  (define (loop n) (loop (+ n 1)))  ;; runs forever, no stack growth
  ```

- **Bignum arithmetic is automatic.** When a fixnum operation would overflow
  63 bits, the result is promoted to a bignum:

  ```scheme
  (expt 2 100)  ;=> 1267650600228229401496703205376
  ```

- **Unicode works everywhere.** String indexing, character predicates, and case
  conversion all operate on Unicode codepoints:

  ```scheme
  (char-alphabetic? #\λ)         ;=> #t
  (string-upcase "straße")       ;=> "STRASSE"
  ```

- **Use `guard` for structured error handling.** It combines exception catching
  with pattern matching:

  ```scheme
  (guard (e (#t (display "error caught\n")))
    (/ 1 0))
  ```
