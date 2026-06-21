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

### ~~Fix callback slot error message~~ ✅ Done

Changed "max 16" to "max 32" in `src/primitives_ffi.zig`.

### ~~Document FFI parameter limit~~ ✅ Done

Added descriptive error message "ffi-fn: too many parameters (max 16)"
in `src/primitives_ffi.zig`.

## JIT / Performance

### ~~x86_64 JIT backend~~ ✅ Done (initial)

Added `src/jit_x86_64.zig` assembler, comptime arch detection, and
`compileX86_64` code gen path. Handles load/store/move/jump/return with
side-exit fallback for unimplemented opcodes. AArch64 path unchanged.
JIT auto-disables on unsupported architectures.

### ~~Improve non-tail call performance~~ ✅ Partial

Added self-call specialization (`emitSelfCallSequence`) that skips
guard checks for self-recursive non-tail calls, and JIT support for
`self_tail_call` opcode. Eliminates side-exits for functions like `tak`.

**Remaining bottleneck:** frame setup (~30 memory stores per call)
dominates — JIT and interpreter run at similar speed for `tak`. Further
improvement needs lightweight JIT-to-JIT frames or register-based
argument passing.

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

### ~~Callback error message is wrong~~ ✅ Done

Fixed "max 16" → "max 32" in `src/primitives_ffi.zig`.

### ~~Version string is not centralized~~ ✅ Done

Extracted to `pub const version` in `src/main.zig`. Both `--version`
and the REPL reference the constant.
