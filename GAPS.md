# Known Gaps

Features that are feasible but require dedicated design and implementation effort.

---

## Standalone binary compilation

**Status:** Basic support implemented

**What:** Bundle compiled bytecode (.sbc) into the Kaappi interpreter binary to produce a single standalone executable that runs a Scheme program without external files.

**Usage:**
1. Compile the program: `kaappi --compile program.scm`
2. Rebuild with the bytecode embedded: `zig build -Dbundle=program.sbc`
3. The resulting binary runs the embedded program on startup: `./zig-out/bin/kaappi`

Command-line arguments are passed through to `(command-line)`.

**Current limitations:**
- Only programs using built-in libraries (scheme base, scheme write, etc.) — programs importing non-built-in SRFIs that need `.sld` files from disk will fail at runtime
- `include` and `load` cannot resolve paths in embedded context
- Two-step build process (compile `.sbc` separately, then rebuild with `-Dbundle`)
- Standalone mode skips `--gc-stats` and other debug flags

**Remaining work:**
- Library bundling: resolve and compile all imports into a single `.sbc`
- Single-step build: `zig build -Dbundle-src=program.scm` to compile and embed in one step
- `include`/`load` path resolution relative to embedded context

---

## Concurrency / threading

**Status:** Not implemented

Single-threaded only. No threading API, no async I/O, no thread-safe GC. Adding threading would require:
- Thread-safe GC (stop-the-world with thread coordination, or concurrent marking)
- Shared-nothing or synchronized access to mutable state
- A threading API (SRFI-18 or similar)

**Estimated scope:** Large

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
