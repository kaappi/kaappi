# Known Gaps

Features that are feasible but require dedicated design and implementation effort.

---

## Standalone binary compilation

**Status:** Complete

**What:** Bundle compiled bytecode (.sbc) into the Kaappi interpreter binary to produce a single standalone executable that runs a Scheme program without external files.

**Usage:**

Single-step build (recommended):
```
zig build -Dbundle-src=program.scm
./zig-out/bin/kaappi
```

Two-step build (for custom workflows):
```
kaappi --compile program.scm [-o output.sbc]
zig build -Dbundle=program.sbc
./zig-out/bin/kaappi
```

Command-line arguments are passed through to `(command-line)`. Debug flags `--gc-stats` and `--profile` are supported in standalone mode.

**Features:**
- Library bundling: all imported `.sld` libraries (SRFIs, user libraries) and their `include` dependencies are automatically bundled into the `.sbc` file
- Programs using any combination of built-in and file-based libraries work as standalone binaries
- `include` paths within bundled libraries resolve correctly at runtime via an embedded virtual filesystem
- Single-step build via `-Dbundle-src` compiles and embeds in one `zig build` invocation

---

## Concurrency / threading

**Status:** Green threads + SRFI-18 compatibility layer implemented

**Green threads (`(kaappi fibers)`):**
```scheme
(import (kaappi fibers))
(define f (spawn (lambda () (+ 1 2))))
(display (fiber-join f))          ; => 3

(define ch (make-channel))
(spawn (lambda () (channel-send ch 42)))
(display (channel-receive ch))    ; => 42
```

**API:** `spawn`, `yield`, `fiber-join`, `fiber?`, `make-channel`, `channel-send`, `channel-receive`, `channel?`

**SRFI-18 (`(srfi 18)`):**
```scheme
(import (srfi 18))
(define t (make-thread (lambda () (* 6 7)) 'worker))
(thread-start! t)
(display (thread-join! t))        ; => 42

(define m (make-mutex))
(mutex-lock! m)
(mutex-unlock! m)

(define cv (make-condition-variable))
(condition-variable-signal! cv)
```

**SRFI-18 API:** `current-thread`, `thread?`, `make-thread`, `thread-name`, `thread-specific`, `thread-specific-set!`, `thread-start!`, `thread-yield!`, `thread-sleep!`, `thread-terminate!`, `thread-join!`, `mutex?`, `make-mutex`, `mutex-name`, `mutex-specific`, `mutex-specific-set!`, `mutex-state`, `mutex-lock!`, `mutex-unlock!`, `condition-variable?`, `make-condition-variable`, `condition-variable-name`, `condition-variable-specific`, `condition-variable-specific-set!`, `condition-variable-signal!`, `condition-variable-broadcast!`, `current-time`, `time?`, `time->seconds`, `seconds->time`, `join-timeout-exception?`, `abandoned-mutex-exception?`, `terminated-thread-exception?`, `uncaught-exception?`, `uncaught-exception-reason`

**Design:** Single OS thread, cooperative scheduling via explicit `(yield)`. Each fiber has its own registers, call stack, handlers, and wind stack. Shared globals, macros, libraries, and GC. Channels use an unbounded pair-based queue (send never blocks). Both `(kaappi fibers)` and `(srfi 18)` operate on the same underlying Fiber objects — threads created by either library are interoperable.

**Remaining work:**
- OS-level threading with true parallelism (requires thread-safe GC)
- Async I/O integration (not planned for near term)
- Fiber-local storage

---

## Profiler

**Status:** Complete

Tracks per-function wall-clock timing (exclusive/inclusive), instruction counts, call counts, and allocation bytes. Handles tail-call accounting correctly — tail-called functions receive proper call counts and timing attribution.

**Usage:**
- `kaappi --profile program.scm` — profile entire file execution
- `,profile <expr>` — profile a single expression in the REPL

Reports top 20 functions sorted by self time, showing:
- **Self ms** — exclusive wall-clock time (time in this function, excluding callees)
- **Total ms** — inclusive wall-clock time (time including all callees)
- **Calls** — number of invocations (including tail calls)
- **Alloc KB** — heap bytes allocated while this function is active
- **Function** — name and source location (file:line) or "(built-in)"

---

## JIT compilation

**Status:** Baseline template JIT implemented (AArch64 only)

Hot functions (called 100+ times) are compiled to native AArch64 machine code. Each bytecode opcode maps to a pre-assembled native snippet that reads/writes the VM's register file directly. Complex operations (function calls, returns, GC-allocating ops) side-exit back to the interpreter. JIT is on by default; disable with `--no-jit`.

**What gets JIT'd natively:**
- `load_nil`, `load_true`, `load_false`, `load_void`, `load_const` — immediate/constant loads
- `move`, `get_local`, `set_local` — register operations
- `jump`, `jump_false`, `jump_true` — control flow

**What side-exits to the interpreter:**
- `call`, `tail_call`, `self_tail_call`, `call_global`, `tail_call_global` — function dispatch
- `return` — frame management
- `get_global`, `set_global`, `define_global` — global lookups
- `cons`, `box_local`, `get_box_local`, `set_box_local` — allocation/mutation

**Not JIT-eligible** (function stays fully interpreted):
- Functions using `closure`, `push_handler`/`pop_handler`, `close_upvalue`, `tail_apply`, or `halt`

**Design:** The JIT keeps the VM's register file, GC, and continuation machinery unchanged. Callee-saved AArch64 registers hold pointers to the VM struct and register window base. GC safety is maintained because JIT'd code never allocates — all allocating opcodes side-exit. Continuations work because `call/cc` runs entirely in the interpreter.

**Remaining work:**
- x86_64 backend
- Native templates for `get_upvalue`/`set_upvalue`
- Inline caching for `get_global`/`call_global`
- Type-specialized arithmetic (unboxed fixnum add/sub/compare)

---

## FFI callbacks

**Status:** 7 signatures supported

Supported callback signatures via `ffi-callback`:
- `(pointer, pointer) -> int` — qsort comparator pattern
- `(pointer) -> void` — event handlers, cleanup callbacks
- `(pointer) -> int` — predicates, filters
- `() -> void` — atexit, simple signal handlers
- `(int, pointer) -> int` — iterators with context
- `(int) -> void` — signal handlers with signal number
- `(pointer, pointer) -> void` — dual-context event handlers

Each signature is a comptime trampoline generator sharing a 32-slot pool. Adding more signatures requires one new `makeTrampoline` variant in `ffi_callback.zig` and a `matchCallbackSig` entry in `primitives_ffi.zig`.

**FFI call dispatcher** supports `pointer` and `string` parameter/return types across all arities (0–4 args), enabling C functions that take or return raw pointers and C strings.

**Current limitations:**
- 32 simultaneous callbacks max (shared across all signatures)
- Single-threaded only — callbacks must be called from the VM's thread
- Exceptions in callbacks return 0 to C (void signatures silently discard errors)

---

## Sandbox mode

**Status:** Implemented

**Usage:** `kaappi --sandbox program.scm`

Blocks: FFI, file I/O, filesystem operations, `eval`, `load`, `exit`, environment variables, process info, and `.sld` library file loading. Allows: pure computation, string ports, standard I/O (stdin/stdout/stderr), built-in libraries (`scheme base/write/read/char/inexact/lazy/time/cxr/complex/case-lambda`, built-in SRFIs 1/9/13/39/69/133).

**Remaining work:**
- Resource limits (max execution time, max memory)
- Per-path filesystem allow-lists for controlled file access
- Network restrictions (when networking is added)
