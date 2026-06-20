# Working with Libraries

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

