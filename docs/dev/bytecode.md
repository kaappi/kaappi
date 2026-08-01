# Bytecode

Instruction set reference and disassembler. The single source of truth for
the ISA — the `/bytecode-isa` skill points here.

## Instruction set

31 opcodes, register-based, variable-length encoding. Register/slot,
constant-index and symbol-index operands are all u16 (big-endian); jump
offsets are i16 (signed, relative to the instruction after the jump). The
only u8 operands are `nargs` and the `is_local` flag in a closure capture
descriptor. Defined in the `OpCode` enum in `src/types.zig`; executed by the
dispatch loop in `src/vm_dispatch.zig`.

The `fixed_operand_bytes` switch in `src/vm_dispatch.zig` is the authoritative
operand-width table — it is what `ensureOperands` validates against, so the
**Bytes** column below is always `1 + fixed_operand_bytes` for that opcode.

| # | Opcode | Operands | Bytes | Description |
|---|--------|----------|-------|-------------|
| 0 | `load_const` | dst:u16, idx:u16 | 5 | Load constant pool[idx] → dst |
| 1 | `load_nil` | dst:u16 | 3 | Load () → dst |
| 2 | `load_true` | dst:u16 | 3 | Load #t → dst |
| 3 | `load_false` | dst:u16 | 3 | Load #f → dst |
| 4 | `load_void` | dst:u16 | 3 | Load void → dst |
| 5 | `move` | dst:u16, src:u16 | 5 | Copy src → dst |
| 6 | `get_global` | dst:u16, sym_idx:u16 | 5 | Lookup global symbol → dst |
| 7 | `set_global` | sym_idx:u16, src:u16 | 5 | Set global from src |
| 8 | `define_global` | sym_idx:u16, src:u16 | 5 | Define global from src |
| 9 | `tail_apply` | base:u16, nargs:u8 | 4 | Tail apply with list unpacking |
| 10 | `get_upvalue` | dst:u16, idx:u16 | 5 | Load captured var → dst |
| 11 | `set_upvalue` | idx:u16, src:u16 | 5 | Set captured var from src |
| 12 | `call` | base:u16, nargs:u8 | 4 | Call fn at base with nargs args |
| 13 | `tail_call` | base:u16, nargs:u8 | 4 | Tail call (reuses frame) |
| 14 | `return` | src:u16 | 3 | Return value from src |
| 15 | `jump` | offset:i16 | 3 | Unconditional relative jump |
| 16 | `jump_false` | test:u16, offset:i16 | 5 | Jump if test is #f |
| 17 | `jump_true` | test:u16, offset:i16 | 5 | Jump if test is not #f |
| 18 | `closure` | dst:u16, func_idx:u16 | 5 + 3n | Create closure, followed by n=`upvalue_count` capture descriptors |
| 19 | `cons` | dst:u16, car:u16, cdr:u16 | 7 | Allocate pair → dst |
| 20 | `push_handler` | handler:u16 | 3 | Push exception handler |
| 21 | `pop_handler` | (none) | 1 | Pop exception handler |
| 22 | `halt` | (none) | 1 | Stop execution |
| 23 | `call_global` | base:u16, sym:u16, nargs:u8 | 6 | Fused get_global + call |
| 24 | `tail_call_global` | base:u16, sym:u16, nargs:u8 | 6 | Fused get_global + tail_call |
| 25 | `box_local` | reg:u16 | 3 | Wrap register in pair for mutation |
| 26 | `get_box_local` | dst:u16, reg:u16 | 5 | Read car of boxed register |
| 27 | `set_box_local` | reg:u16, src:u16 | 5 | Write car of boxed register |
| 28 | `self_tail_call` | base:u16, nargs:u8 | 4 | Self-recursive tail call: copy args to frame base, reset IP |
| 29 | `tail_call_cc` | base:u16, dst:u16 | 5 | `call/cc` in tail position: captures the continuation into dst, then tail-calls the receiver at base+0 |
| 30 | `tail_eval` | base:u16, nargs:u8 | 4 | `eval` in tail position: compiles the expression at base+0 (optional environment at base+1) and tail-calls it |

`self_tail_call` skips the global lookup, type check, and arity check for
direct self-recursion and named `let` loops — see
[decisions/self-tail-call-optimization.md](decisions/self-tail-call-optimization.md).

### Encoding details

- Opcodes: 1 byte (`@intFromEnum(op)`)
- u16 operands: big-endian (high byte first)
- i16 jump offsets: bitcast of u16, relative to instruction AFTER the jump
- `closure` instruction: followed by `upvalue_count * 3` bytes of capture
  descriptors — each is `is_local:u8` then `index:u16`. `is_local == 1`
  captures the parent frame's register `index` (boxing it first if it is not
  already a box); otherwise it copies the parent closure's upvalue `index`.
  The same `* 3` stride is what `bytecode_file_read.zig` skips when walking
  a `.sbc` code stream.

## Available metadata per function

The `Function` struct (`src/types.zig`) provides:

| Field | Type | Use in disassembly |
|-------|------|--------------------|
| `name` | `?[]const u8` | Function header label |
| `source_name` | `?[]const u8` | Source file reference |
| `source_line` | `u32` | Source location |
| `arity` | `u8` | Parameter count display |
| `is_variadic` | `bool` | Show rest parameter |
| `locals_count` | `u16` | Register window size |
| `upvalue_count` | `u16` | Captured variable count |
| `constants` | `ArrayList(Value)` | Constant pool for symbolic display |
| `debug_locals` | `[]DebugLocal` | Map register slots to variable names |
| `code` | `ArrayList(u8)` | Bytecode to disassemble |

## Disassembler

Implemented in `src/disassembler.zig`. Three entry points:

- `(disassemble <proc>)` — Scheme procedure
- `,dis <expr>` — REPL command
- `kaappi --disassemble file.scm` — compiles each top-level form and
  prints its bytecode instead of executing it

### Output format

For `(define (fib n) (if (<= n 1) n (+ (fib (- n 1)) (fib (- n 2)))))`,
`(disassemble fib)` prints:

```text
; Function: fib
; Source: fib.scm:1
; Arity: 1, Locals: 7, Upvalues: 0
; Constants: <=, 1, +, fib, -, 2
;
  0000  move            r2, r0
  0005  load_const      r3, 1
  0010  call_global     r1, <=, 2
  0016  jump_false      r1, -> 0029
  0021  move            r1, r0
  0026  jump            -> 0082
  0029  get_global      r1, +
  0034  move            r4, r0
  0039  load_const      r5, 1
  0044  call_global     r3, -, 2
  0050  call_global     r2, fib, 1
  0056  move            r5, r0
  0061  load_const      r6, 2
  0066  call_global     r4, -, 2
  0072  call_global     r3, fib, 1
  0078  tail_call       r1, 2
  0082  return          r1
```

The offsets double as a check on the table above: `move` at 0000 to
`load_const` at 0005 is 5 bytes, `call_global` at 0010 to `jump_false` at
0016 is 6, and `jump` at 0026 to 0029 is 3.

Formatting choices:

- Decimal offsets, zero-padded to 4 digits (`{d:0>4}`)
- Register names (`r0`, `r1`, ...) with `debug_locals` annotations where available
- Symbol names resolved from constant pool (not raw indices)
- Jump targets shown as absolute offsets, written `-> NNNN`

## Key files

| Component | Location |
|-----------|----------|
| OpCode enum | `src/types.zig` |
| VM dispatch loop | `src/vm_dispatch.zig` (`runUntil`) |
| Instruction encoding | `src/compiler.zig` |
| Function struct | `src/types.zig` |
| Disassembler | `src/disassembler.zig` |
| Value printer | `src/printer.zig` |
| Stepping debugger | `src/vm_debug.zig` |
