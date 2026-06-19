# Known Gaps

Features that are feasible but require dedicated design and implementation effort.

---

## Standalone binary compilation

**Status:** Not yet implemented

**What:** Bundle compiled bytecode (.sbc) into the Kaappi interpreter binary to produce a single standalone executable that runs a Scheme program without external files.

**Why it matters:** Currently, distributing a Kaappi program requires shipping the `kaappi` binary plus `.scm` or `.sbc` source files plus any library `.sld` files. A standalone binary would simplify deployment.

**Approach:** Use Zig's `@embedFile` to include a `.sbc` file at build time.

1. Compile the program: `kaappi --compile program.scm`
2. Rebuild with the bytecode embedded: `zig build -Dbundle=program.sbc`
3. The resulting binary detects embedded bytecode and runs it on startup

**Challenges:**
- Library dependencies: if the program uses `(import (srfi N))`, the `.sld` files must also be embedded or pre-compiled into the bytecode
- Two-step build process requires build system coordination
- The `.sbc` format would need versioning to detect stale embedded bytecode
- `include` and `load` paths need resolution relative to the embedded context

**Estimated scope:** Medium (build.zig changes + main.zig entry point mode + bytecode_file.zig memory reader)

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

**Status:** Not implemented

No built-in profiler for identifying hotspots. Would require bytecode-level instrumentation or sampling-based profiling of the `runUntil` loop.

---

## JIT compilation

**Status:** Not planned for near term

The VM is purely interpreted bytecode. A tracing or method-based JIT would significantly improve performance on compute-heavy workloads but is a major undertaking.

---

## FFI callbacks

**Status:** Not implemented

The C FFI supports calling C functions from Scheme (0-3 arguments), but cannot pass Scheme closures as C callbacks. This limits integration with callback-heavy C APIs (event loops, sort comparators, etc.).

---

## Sandbox mode

**Status:** Not implemented

No mechanism to restrict filesystem access, FFI, or `eval` for untrusted code execution. Would require capability-based restrictions on the VM's primitive set.
