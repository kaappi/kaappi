---
description: Reference for the Kaappi bytecode instruction set
---

# Bytecode ISA

The instruction set reference lives in `docs/dev/bytecode.md` — read that
file for the full 32-opcode table, operand encodings, closure capture
encoding, and disassembler output format. Do not duplicate the table here;
that doc is the single source of truth.

Quick orientation:
- Opcodes are defined in the `OpCode` enum in `src/types.zig`
- Executed by the dispatch loop `runUntil` in `src/vm_dispatch.zig`
- Emitted by `src/compiler.zig` (and the `compiler_*.zig` form modules)
- 1-byte opcode + variable operands; u16 operands are big-endian; i16 jump
  offsets are relative to the instruction after the jump

## Adding a new opcode

1. Add to the `OpCode` enum in `src/types.zig` (append at the end — `.sbc`
   bytecode files encode opcodes by integer value)
2. Add a case to the `runUntil` dispatch switch in `src/vm_dispatch.zig`
3. Emit it in the compiler (`src/compiler.zig` or the relevant
   `compiler_*.zig` module)
4. Handle it in `src/disassembler.zig`
5. Update the table in `docs/dev/bytecode.md`
