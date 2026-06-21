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

### ~~Improve non-tail call performance~~ ✅ Done

Added self-call specialization (`emitSelfCallSequence`): skips all guard
checks, uses STP batching for frame stores, eliminates call_count
increment, loads frame_count once. JIT support for `self_tail_call`
opcode eliminates side-exits. Further gains need lightweight JIT frames
(architectural change).

### ~~Consider raising stack limits~~ ✅ Done

Defaults raised to MAX_FRAMES=512, MAX_REGISTERS=2048. Configurable
at build time via `-Dmax-frames=N` and `-Dmax-registers=N`.

### ~~GC tuning for tight recursion~~ ✅ Done

Initial GC threshold raised from 1024 to 8192 objects. Configurable
at build time via `-Dgc-threshold=N`. Reduces early collection churn
during startup and library registration.

## Documentation Bugs Found in Source

### ~~Callback error message is wrong~~ ✅ Done

Fixed "max 16" → "max 32" in `src/primitives_ffi.zig`.

### ~~Version string is not centralized~~ ✅ Done

Extracted to `pub const version` in `src/main.zig`. Both `--version`
and the REPL reference the constant.
