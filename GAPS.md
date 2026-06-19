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

**Status:** Basic instruction-counting profiler implemented

Tracks per-function bytecode instruction counts and call counts. In a bytecode interpreter, instruction count is a direct proxy for CPU time.

**Usage:**
- `kaappi --profile program.scm` — profile entire file execution
- `,profile <expr>` — profile a single expression in the REPL

Reports top 20 functions sorted by instruction count, showing both Scheme functions (with source location) and built-in procedures (by call count).

**Remaining work:**
- Wall-clock timing per function (requires tail-call accounting)
- Exclusive vs inclusive time attribution
- Allocation profiling (bytes allocated per function)

---

## JIT compilation

**Status:** Not planned for near term

The VM is purely interpreted bytecode. A tracing or method-based JIT would significantly improve performance on compute-heavy workloads but is a major undertaking.

---

## FFI callbacks — additional signatures

**Status:** 4 signatures supported

Supported callback signatures via `ffi-callback`:
- `(pointer, pointer) -> int` — qsort comparator pattern
- `(pointer) -> void` — event handlers, cleanup callbacks
- `(pointer) -> int` — predicates, filters
- `() -> void` — atexit, simple signal handlers

Each signature is a comptime trampoline generator sharing a 16-slot pool. Adding more signatures requires one new `makeTrampoline` variant in `ffi_callback.zig` and a `matchCallbackSig` entry in `primitives_ffi.zig`.

**Current limitations:**
- 16 simultaneous callbacks max (shared across all signatures)
- Single-threaded only — callbacks must be called from the VM's thread
- Exceptions in callbacks return 0 to C (void signatures silently discard errors)

**Remaining signatures worth adding:**
- `(int, pointer) -> int` — iterators with context
- `(int) -> void` — signal handlers with signal number
- `(pointer, pointer) -> void` — dual-context event handlers

---

## Sandbox mode

**Status:** Implemented

**Usage:** `kaappi --sandbox program.scm`

Blocks: FFI, file I/O, filesystem operations, `eval`, `load`, `exit`, environment variables, process info, and `.sld` library file loading. Allows: pure computation, string ports, standard I/O (stdin/stdout/stderr), built-in libraries (`scheme base/write/read/char/inexact/lazy/time/cxr/complex/case-lambda`, built-in SRFIs 1/9/13/39/69/133).

**Remaining work:**
- Resource limits (max execution time, max memory)
- Per-path filesystem allow-lists for controlled file access
- Network restrictions (when networking is added)
