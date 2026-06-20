# Library Authoring Guide

This document covers how to create, organize, and use Scheme libraries with
Kaappi's R7RS library system.

---

## define-library Syntax

A library definition contains a name and one or more declarations:

```scheme
(define-library (library-name ...)
  (export export-spec ...)
  (import import-set ...)
  (begin body ...)
  (include filename ...)
  (include-ci filename ...)
  (cond-expand clause ...))
```

### Declarations

| Declaration | Purpose |
|-------------|---------|
| `export` | Names to make visible to importers |
| `import` | Libraries this library depends on |
| `begin` | Scheme code defining the library's bindings |
| `include` | Include source from another file (as if pasted into begin) |
| `include-ci` | Like include, but case-folded identifiers |
| `cond-expand` | Conditional declarations based on feature flags |

---

## Complete Example

A math utility library in `mylib/math.sld`:

```scheme
(define-library (mylib math)
  (export square cube factorial fibonacci)
  (import (scheme base))
  (begin
    (define (square x) (* x x))

    (define (cube x) (* x x x))

    (define (factorial n)
      (let loop ((i n) (acc 1))
        (if (= i 0) acc
            (loop (- i 1) (* i acc)))))

    (define (fibonacci n)
      (let loop ((i 0) (a 0) (b 1))
        (if (= i n) a
            (loop (+ i 1) b (+ a b)))))))
```

Using it from a program:

```scheme
(import (mylib math))

(display (square 5))      ;=> 25
(newline)
(display (factorial 10))  ;=> 3628800
(newline)
(display (fibonacci 20))  ;=> 6765
(newline)
```

---

## Export Specifications

The `export` declaration lists what the library makes available:

```scheme
;; Export names as-is
(export square cube factorial)

;; Export with renaming
(export (rename internal-name external-name))
```

Example with renaming:

```scheme
(define-library (mylib strings)
  (export (rename str-join join)
          (rename str-split split))
  (import (scheme base))
  (begin
    (define (str-join lst sep) ...)
    (define (str-split s sep) ...)))
```

---

## Import Sets and Modifiers

### Basic Import

```scheme
(import (scheme base))            ;; Import all exports
(import (scheme base) (scheme write))  ;; Import from multiple libraries
```

### only -- Import specific names

```scheme
(import (only (scheme base) map filter cons car cdr))
```

### except -- Import everything but specific names

```scheme
(import (except (scheme base) error))
```

### rename -- Import with different names

```scheme
(import (rename (scheme base)
                (map    scheme-map)
                (filter scheme-filter)))

(scheme-map + '(1 2 3) '(10 20 30))  ;=> (11 22 33)
```

### prefix -- Add prefix to all imported names

```scheme
(import (prefix (scheme char) char:))

(char:char-alphabetic? #\A)       ;=> #t
(char:string-upcase "hello")      ;=> "HELLO"
```

### Nested modifiers

Modifiers can be composed:

```scheme
(import (prefix (only (scheme base) map filter) list:))

(list:map + '(1 2) '(3 4))       ;=> (4 6)
```

---

## File Naming and Search Paths

### Naming Convention

Library names map to file paths by joining components with `/` and appending
`.sld`:

| Library Name | File Path |
|-------------|-----------|
| `(mylib math)` | `mylib/math.sld` |
| `(mylib util strings)` | `mylib/util/strings.sld` |
| `(srfi 1)` | `srfi/1.sld` |

### Search Order

Kaappi searches for `.sld` files in this order:

1. Current directory (`./`)
2. `./lib/` subdirectory
3. Directories specified with `--lib-path`

Example:

```bash
zig build run -- --lib-path /opt/scheme-libs --lib-path ./vendor program.scm
```

With this invocation, `(import (mylib math))` searches:

1. `./mylib/math.sld`
2. `./lib/mylib/math.sld`
3. `/opt/scheme-libs/mylib/math.sld`
4. `./vendor/mylib/math.sld`

---

## Bytecode Caching

Library files can be pre-compiled to bytecode for faster loading:

```bash
zig build run -- --compile mylib/math.sld
# Output: Compiled mylib/math.sld -> mylib/math.sbc
```

When Kaappi loads a library, it checks for a `.sbc` file next to the `.sld`.
If the bytecode cache is newer than the source (based on a hash of the source
content), the cache is used directly, skipping parsing and compilation.

Caching happens automatically on first run -- explicit `--compile` is only
needed if you want to pre-warm the cache.

---

## Available Libraries

### Standard R7RS Libraries (14)

| Library | Exports | Description |
|---------|---------|-------------|
| `(scheme base)` | 230+ | Core procedures and syntax |
| `(scheme case-lambda)` | 1 | `case-lambda` syntax |
| `(scheme char)` | 22 | Unicode character operations |
| `(scheme complex)` | 6 | Complex number procedures |
| `(scheme cxr)` | 28 | Car/cdr compositions (3 and 4 deep) |
| `(scheme eval)` | 3 | `eval`, `environment`, `interaction-environment` |
| `(scheme file)` | 10 | File I/O |
| `(scheme inexact)` | 12 | Transcendental math (sin, cos, exp, log, ...) |
| `(scheme lazy)` | 5 | `delay`, `force`, promises |
| `(scheme load)` | 1 | `load` |
| `(scheme process-context)` | 5 | `exit`, `command-line`, environment variables |
| `(scheme read)` | 1 | `read` |
| `(scheme time)` | 3 | `current-second`, jiffies |
| `(scheme write)` | 7 | `write`, `display`, `write-shared` |

### SRFI Libraries (51)

8 built-in SRFIs (implemented in Zig):

| Library | Description |
|---------|-------------|
| `(srfi 1)` | List library (fold, filter, find, any, every, iota, ...) |
| `(srfi 9)` | Records (alias for R7RS `define-record-type`) |
| `(srfi 13)` | String library (contains, split, join, trim, ...) |
| `(srfi 18)` | Threads, mutexes, condition variables |
| `(srfi 39)` | Parameter objects (alias for `make-parameter`) |
| `(srfi 69)` | Hash tables |
| `(srfi 133)` | Vector library |
| `(srfi 170)` | POSIX filesystem API (file-info, directory ops, ...) |

43 portable SRFIs (loaded on demand from `.sld` files in `lib/srfi/`):

| Library | Description |
|---------|-------------|
| `(srfi 2)` | `and-let*` |
| `(srfi 8)` | `receive` |
| `(srfi 11)` | `let-values` |
| `(srfi 14)` | Character sets |
| `(srfi 16)` | `case-lambda` |
| `(srfi 26)` | `cut` / `cute` (partial application) |
| `(srfi 27)` | Random numbers |
| `(srfi 28)` | `format` (basic) |
| `(srfi 31)` | `rec` (recursive expressions) |
| `(srfi 34)` | Exception handling |
| `(srfi 35)` | Conditions |
| `(srfi 36)` | I/O conditions |
| `(srfi 41)` | Streams (lazy lists) |
| `(srfi 48)` | `format` (intermediate) |
| `(srfi 64)` | Test suite framework |
| `(srfi 98)` | Environment variables |
| `(srfi 111)` | Boxes |
| `(srfi 113)` | Sets and bags |
| `(srfi 115)` | Regular expressions |
| `(srfi 117)` | Mutable queues |
| `(srfi 125)` | Hash tables (R7RS-style) |
| `(srfi 128)` | Comparators |
| `(srfi 132)` | Sort libraries |
| `(srfi 141)` | Integer division |
| `(srfi 143)` | Fixnums |
| `(srfi 145)` | `assume` |
| `(srfi 146)` | Mappings (+ `(srfi 146 hash)`) |
| `(srfi 151)` | Bitwise operations |
| `(srfi 152)` | String library (R7RS-style) |
| `(srfi 158)` | Generators and accumulators |
| `(srfi 166)` | Formatting (+ pretty, columnar, unicode, color) |
| `(srfi 174)` | POSIX timespecs |
| `(srfi 175)` | ASCII character library |
| `(srfi 189)` | Maybe and Either |
| `(srfi 195)` | Multiple values as objects |
| `(srfi 196)` | Range objects |
| `(srfi 210)` | Procedures and syntax for multiple values |
| `(srfi 219)` | `define` with curried arguments |
| `(srfi 222)` | Compound objects |
| `(srfi 227)` | Optional arguments |
| `(srfi 232)` | Flexible curried procedures |
| `(srfi 233)` | `let` with multiple values |
| `(srfi 235)` | Combinators |

### Kaappi Extension Libraries

| Library | Description |
|---------|-------------|
| `(kaappi ffi)` | Foreign function interface (ffi-open, ffi-fn, ffi-callback, ffi-close) |
| `(kaappi fibers)` | Green threads (spawn, yield, fiber-join, channels) |

---

## cond-expand for Portable Code

Use `cond-expand` to write code that adapts to different Scheme implementations:

```scheme
(define-library (mylib compat)
  (export platform-name)
  (import (scheme base))
  (cond-expand
    (kaappi
     (begin
       (define platform-name "kaappi")))
    (chicken
     (begin
       (define platform-name "chicken")))
    (else
     (begin
       (define platform-name "unknown")))))
```

The `features` procedure returns the list of feature identifiers that Kaappi
supports:

```scheme
(features)  ;=> (r7rs kaappi ...)
```

---

## Library Organization Tips

- Put each library in its own `.sld` file.
- Use a consistent directory structure that mirrors library names.
- Keep a `lib/` directory for project-local libraries.
- Use `include` to split large libraries across multiple files:

  ```scheme
  (define-library (mylib big)
    (export ...)
    (import (scheme base))
    (include "big-part1.scm")
    (include "big-part2.scm"))
  ```

- Pre-compile libraries that don't change often:

  ```bash
  zig build run -- --compile lib/mylib/utils.sld
  ```
