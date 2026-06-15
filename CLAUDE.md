# Kaappi — R7RS Scheme in Zig

An R7RS-small Scheme implementation targeting Zig 0.16.

## Build

```
zig build          # build the executable
zig build run      # run the REPL
zig build run -- file.scm   # run a Scheme file
zig build test     # run all unit tests
```

## Architecture

```
Reader (src/reader.zig)    → S-expressions (Value)
Compiler (src/compiler.zig) → Bytecode (Function)
VM (src/vm.zig)            → Execution
```

**Value representation**: Tagged u64. Fixnums have bit 0 = 1 (63-bit signed range). Pointers have low 3 bits = 0 (8-byte aligned, Object header). Immediates have bits 0-1 = 10 (nil, bool, void, eof, char).

**GC**: Mark-and-sweep with intrusive object linked list. Roots tracked via `gc.pushRoot`/`gc.popRoot`.

**VM**: Register-based. Call frames with base register offset. Native functions dispatched inline.

## Key patterns

### Zig 0.16 specifics
- `std.ArrayList(T)` is unmanaged — use `.empty` for init, pass `allocator` to `append`, `deinit`, `toOwnedSlice`
- No `std.io` — use `std.Io.Writer` for buffered formatting, `std.posix.system.write(fd, ...)` for stdout/stderr
- `main()` takes `std.process.Init.Minimal` for args
- `std.heap.DebugAllocator(.{}).init` for allocator in main

### Adding a new built-in procedure
See `.claude/skills/add-builtin/SKILL.md`.

### Bytecode ISA
See `.claude/skills/bytecode-isa/SKILL.md`.

## Test strategy
- Zig unit tests: `test` blocks in each source file, run via `zig build test`
- Scheme test files: `tests/scheme/phase1/*.scm`, run via `zig build run -- <file>`
- R7RS conformance: will use adapted chibi-scheme r7rs-tests.scm (tests/scheme/r7rs/)

## Implementation phases
See `STATUS.md` for current progress.
