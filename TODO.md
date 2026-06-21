# Kaappi TODO

Implementation improvements identified during documentation review.

## CLI

### ~~Add `--help` flag~~ ✅ Done

Added `--help`, `-h`, and `--version` flags. Extracted version to
`pub const version` constant. Updated both arg parsing loops (main +
embedded-bytecode) and the REPL startup message.

### ~~Add `--version` flag~~ ✅ Done

Implemented together with `--help`. Version extracted to `pub const version`
in `src/main.zig`, `--version` flag added to both arg loops.

## stdin / Reader

### ~~Fix `(read)` with piped stdin~~ ✅ Done

Added `read_buf`/`read_buf_len` fields to Port struct. `readDatumFn` now
saves unconsumed bytes after parsing one datum; `readOneByte` checks the
buffer first so `read-char`/`read-line` also work after a buffered `(read)`.
Buffer freed on port close and GC collection.

## FFI

### ~~Add more C types~~ ✅ Done

Added 9 types: `int8`, `int16`, `int32`, `int64`, `uint16`, `uint32`,
`uint64`, `size_t`, `char`. New types are ABI-normalized to `int`/`long`
equivalents in `ffi.zig` dispatch, avoiding combinatorial if-chain explosion.

### Fix callback slot error message

**Priority:** Low

The error message at `src/primitives_ffi.zig:162` says "max 16" but the
actual limit is 32 (`src/ffi_callback.zig:7` defines `NUM_SLOTS = 32`).

### Document FFI parameter limit

**Priority:** Low

`src/primitives_ffi.zig:104` caps FFI function calls at 16 parameters.
This is undocumented.

## JIT / Performance

### x86_64 JIT backend

**Priority:** Medium

The JIT only targets AArch64. No x86_64 backend exists. This limits
deployment to ARM systems (M-series Macs, ARM cloud instances). An x86_64
port would broaden adoption significantly.

**Current JIT:** `src/jit.zig` (orchestration) + `src/jit_aarch64.zig`
(code generation).

### Improve non-tail call performance

**Priority:** Medium

The `tak` benchmark is disproportionately slow (3x slower than Gauche)
while `fib` is on par. The difference is non-tail multi-recursive calls.

**Analysis:**
- `tak` has 3 non-tail recursive calls per invocation (nested as
  arguments to the outer `tak` call)
- Each non-tail call in JIT-compiled code may trigger a side-exit back
  to the interpreter (`src/jit.zig:914-929`)
- Side-exits break register locality and cause costly re-entry via
  `jitFinishCallee` (`src/jit.zig:1082-1088`)
- Frame setup per call is expensive: arity check, register window
  calculation, wind count save (`src/vm.zig:1948-1991`)

**Potential improvements:**
- Cache callee function pointers to avoid re-dispatch for known targets
- Inline small recursive functions at JIT compile time
- Reduce frame setup cost for self-recursive calls (reuse callee metadata)

### Consider raising stack limits

**Priority:** Low

Current compile-time constants (`src/vm.zig:31-34`):
- `MAX_FRAMES = 256`
- `MAX_REGISTERS = 1024`
- `MAX_HANDLERS = 64`
- `MAX_WINDS = 64`

These are not runtime-configurable. 256 frames is sufficient for most
programs but tight for deeply recursive algorithms that aren't
tail-recursive. Consider making these configurable via CLI flags or
environment variables.

### GC tuning for tight recursion

**Priority:** Low

The GC threshold starts at 1024 objects and grows to `object_count * 4`
after each collection (`src/memory.zig:1001`). In tight recursive code
like `tak`, frequent allocations trigger many collections.

Consider:
- Larger initial threshold for non-interactive (file) execution
- Generational collection for short-lived objects in recursive calls

## Documentation Bugs Found in Source

### Callback error message is wrong

`src/primitives_ffi.zig:162` — error says "max 16" but actual limit is
32 (`ffi_callback.zig:7`).

### ~~Version string is not centralized~~ ✅ Done

Extracted to `pub const version` in `src/main.zig`. Both `--version`
and the REPL reference the constant.
