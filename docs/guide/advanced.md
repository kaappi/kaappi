# Advanced Features

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

