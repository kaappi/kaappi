---
description: Reference for the Kaappi bytecode instruction set
---

# Bytecode ISA

Defined in `src/types.zig` as `OpCode` enum. Executed by `src/vm.zig`.

## Encoding
Each instruction is 1 byte opcode + variable operands.
- `u8` operands: 1 byte
- `u16` operands: 2 bytes big-endian
- `i16` operands: 2 bytes big-endian (signed)

## Instructions

| Opcode | Operands | Description |
|--------|----------|-------------|
| `load_const` | dst:u8, idx:u16 | `r[base+dst] = constants[idx]` |
| `load_nil` | dst:u8 | `r[base+dst] = ()` |
| `load_true` | dst:u8 | `r[base+dst] = #t` |
| `load_false` | dst:u8 | `r[base+dst] = #f` |
| `load_void` | dst:u8 | `r[base+dst] = void` |
| `move` | dst:u8, src:u8 | `r[base+dst] = r[base+src]` |
| `get_global` | dst:u8, sym:u16 | `r[base+dst] = globals[constants[sym]]` |
| `set_global` | sym:u16, src:u8 | `globals[constants[sym]] = r[base+src]` |
| `get_upvalue` | dst:u8, idx:u8 | `r[base+dst] = upvalues[idx]` |
| `set_upvalue` | idx:u8, src:u8 | `upvalues[idx] = r[base+src]` |
| `call` | base:u8, nargs:u8 | Call `r[base]` with args `r[base+1..base+nargs]` |
| `tail_call` | base:u8, nargs:u8 | Tail call (Phase 2: reuse frame) |
| `return` | src:u8 | Return `r[base+src]` to caller |
| `jump` | offset:i16 | `IP += offset` |
| `jump_false` | test:u8, offset:i16 | If `r[base+test]` is `#f`, `IP += offset` |
| `closure` | dst:u8, idx:u16 | Create closure from `constants[idx]` (a Function) |
| `close_upvalue` | slot:u8 | Close upvalue at slot (TODO) |
| `cons` | dst:u8, car:u8, cdr:u8 | `r[base+dst] = cons(r[car], r[cdr])` |
| `halt` | — | Stop execution |

## Closure encoding
After a `closure` instruction, the bytecode contains `upvalue_count` pairs of bytes:
```
[is_local:u8] [index:u8]
```
- `is_local=1`: capture from parent's register `index`
- `is_local=0`: capture from parent's upvalue `index`

## Adding a new opcode
1. Add to `OpCode` enum in `src/types.zig`
2. Add case to `run()` switch in `src/vm.zig`
3. Emit it in the compiler in `src/compiler.zig`
4. Update this skill doc
