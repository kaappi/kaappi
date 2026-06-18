# Bytecode Disassembler

## Overview

`(disassemble <proc>)` is implemented in `src/disassembler.zig`.
A `--disassemble` CLI flag is not yet added (future work).

## Instruction set reference

31 opcodes, register-based, variable-length encoding. Operands are u8
(register/slot) or u16 (constant index, big-endian). Jump offsets are i16
(signed, relative to the instruction after the jump).

| # | Opcode | Operands | Bytes | Description |
|---|--------|----------|-------|-------------|
| 0 | `load_const` | dst:u8, idx:u16 | 4 | Load constant pool[idx] → dst |
| 1 | `load_nil` | dst:u8 | 2 | Load () → dst |
| 2 | `load_true` | dst:u8 | 2 | Load #t → dst |
| 3 | `load_false` | dst:u8 | 2 | Load #f → dst |
| 4 | `load_void` | dst:u8 | 2 | Load void → dst |
| 5 | `move` | dst:u8, src:u8 | 3 | Copy src → dst |
| 6 | `get_global` | dst:u8, sym_idx:u16 | 4 | Lookup global symbol → dst |
| 7 | `set_global` | sym_idx:u16, src:u8 | 4 | Set global from src |
| 8 | `define_global` | sym_idx:u16, src:u8 | 4 | Define global from src |
| 9 | `tail_apply` | base:u8, nargs:u8 | 3 | Tail apply with list unpacking |
| 10 | `get_local` | dst:u8, slot:u8 | 3 | (unused, replaced by move) |
| 11 | `set_local` | slot:u8, src:u8 | 3 | (unused, replaced by move) |
| 12 | `get_upvalue` | dst:u8, idx:u8 | 3 | Load captured var → dst |
| 13 | `set_upvalue` | idx:u8, src:u8 | 3 | Set captured var from src |
| 14 | `call` | base:u8, nargs:u8 | 3 | Call fn at base with nargs args |
| 15 | `tail_call` | base:u8, nargs:u8 | 3 | Tail call (reuses frame) |
| 16 | `return` | src:u8 | 2 | Return value from src |
| 17 | `jump` | offset:i16 | 3 | Unconditional relative jump |
| 18 | `jump_false` | test:u8, offset:i16 | 4 | Jump if test is #f |
| 19 | `jump_true` | test:u8, offset:i16 | 4 | Jump if test is not #f |
| 20 | `closure` | dst:u8, func_idx:u16 | 4+ | Create closure, followed by upvalue capture pairs |
| 21 | `close_upvalue` | slot:u8 | 2 | Box local for shared mutation |
| 22 | `cons` | dst:u8, car:u8, cdr:u8 | 4 | Allocate pair → dst |
| 23 | `push_handler` | handler:u8 | 2 | Push exception handler |
| 24 | `pop_handler` | (none) | 1 | Pop exception handler |
| 25 | `halt` | (none) | 1 | Stop execution |
| 26 | `call_global` | base:u8, sym:u16, nargs:u8 | 5 | Fused get_global + call |
| 27 | `tail_call_global` | base:u8, sym:u16, nargs:u8 | 5 | Fused get_global + tail_call |
| 28 | `box_local` | reg:u8 | 2 | Wrap register in pair for mutation |
| 29 | `get_box_local` | dst:u8, reg:u8 | 3 | Read car of boxed register |
| 30 | `set_box_local` | reg:u8, src:u8 | 3 | Write car of boxed register |

### Encoding details

- Opcodes: 1 byte (`@intFromEnum(op)`)
- u16 operands: big-endian (high byte first)
- i16 jump offsets: bitcast of u16, relative to instruction AFTER the jump
- `closure` instruction: followed by `upvalue_count * 2` bytes of capture
  descriptors (is_local:u8, index:u8 pairs)

## Available metadata per function

The `Function` struct (`src/types.zig:172-188`) provides:

| Field | Type | Use in disassembly |
|-------|------|--------------------|
| `name` | `?[]const u8` | Function header label |
| `source_name` | `?[]const u8` | Source file reference |
| `source_line` | `u32` | Source location |
| `arity` | `u8` | Parameter count display |
| `is_variadic` | `bool` | Show rest parameter |
| `locals_count` | `u8` | Register window size |
| `upvalue_count` | `u8` | Captured variable count |
| `constants` | `ArrayList(Value)` | Constant pool for symbolic display |
| `debug_locals` | `[]DebugLocal` | Map register slots to variable names |
| `code` | `ArrayList(u8)` | Bytecode to disassemble |

## Proposed output format

```
; Function: fib
; Source: fib.scm:1
; Arity: 1, Locals: 6, Upvalues: 0
; Constants: [<=, n, 1, -, fib, +, 2]
;
; Bytecode (28 bytes):
  0000  call_global     r0, <=, 2         ; (<=  n 1)
  0005  jump_false      r0, +8            ; if false, goto 0017
  0009  move            r0, r1            ; return n
  000c  return          r0
  000e  call_global     r2, -, 2          ; (- n 1)
  0013  call_global     r2, fib, 1        ; (fib ...)
  0018  call_global     r4, -, 2          ; (- n 2)
  001d  tail_call_global r4, fib, 1       ; (fib ...) [tail]
```

Key formatting choices:
- Hex offsets for jump target calculation
- Register names (`r0`, `r1`, ...) with `debug_locals` annotations where available
- Symbol names resolved from constant pool (not raw indices)
- Jump targets shown as absolute offsets
- Comments for common patterns

## Implementation plan

### Step 1: Disassembly function in a new file `src/disassembler.zig`

```zig
pub fn disassemble(func: *types.Function, writer: anytype) void {
    // Print header (name, source, arity, constants)
    // Walk code byte-by-byte, decode each instruction
    // For each: print offset, opcode name, formatted operands
}
```

The function walks `func.code.items`, matching on `@as(OpCode,
@enumFromInt(code[ip]))`, decoding operands with the same read patterns as
the VM (`readU8`/`readU16`), and printing formatted output.

### Step 2: Register as a Scheme procedure

In `src/primitives_r7rs.zig` (or a new `primitives_debug.zig`):

```zig
fn disassembleFn(args: []const Value) PrimitiveError!Value {
    if (!types.isClosure(args[0])) return PrimitiveError.TypeError;
    const closure = types.toObject(args[0]).as(types.Closure);
    disassembler.disassemble(closure.func, stderr_writer);
    return types.VOID;
}
```

Register as `(disassemble <proc>)` in `(scheme base)` or a `(kaappi debug)`
library.

### Step 3: CLI flag `--disassemble`

In `src/main.zig`, add a `--disassemble` flag that compiles each top-level
form and prints its bytecode instead of executing it.

### Step 4: Nested function display

When a constant pool entry is a Function (for inner lambdas), recursively
disassemble it indented under the parent, or print a reference like
`<fn:fib@0012>`.

## Existing infrastructure to reuse

- `printer.valueToString()` — format constant pool values for display
- `types.symbolName()` — resolve symbol indices to names
- `debug_locals` — map register slots to source variable names
- `vm_debug.zig` — stepping debugger (does NOT disassemble, but shows
  function names and local values via the same metadata)

## Complexity

Low-medium. The core disassembler is a ~150-line switch statement mirroring
the VM's dispatch loop but printing instead of executing. The CLI flag and
Scheme procedure registration are ~20 lines each.

## Key files

| Component | Location |
|-----------|----------|
| OpCode enum | `src/types.zig:683-715` |
| VM decode loop | `src/vm.zig:613-1282` |
| Instruction encoding | `src/compiler.zig:99-115` |
| Function struct | `src/types.zig:172-188` |
| Value printer | `src/printer.zig` |
| Debug commands | `src/vm_debug.zig` |
