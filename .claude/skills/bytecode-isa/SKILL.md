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
   bytecode files encode opcodes by integer value, so inserting one renumbers
   every opcode after it. The cache load path rejects a foreign build by
   compiler hash, but `src/testdata/fuzz-seed.sbc` patches that hash in at
   comptime and has no such guard: it decodes as garbage, and the `fuzz seed
   .sbc fixture stays loadable` test is what tells you). Bump the count in the
   comptime doc-sync gate below the enum and follow the files it names.
2. Add its width to the `fixed_operand_bytes` switch in `src/vm_dispatch.zig`
   — the authoritative operand-width table — and a case to the `runUntil`
   dispatch switch
3. Emit it in the compiler (`src/compiler.zig` or the relevant
   `compiler_*.zig` module)
4. Handle it in `src/disassembler.zig` (both its `fixed_operand_bytes` switch
   and its printer)
5. Add it to `validateFunctionBytecode` in `src/bytecode_file_read.zig`, or a
   `.sbc` carrying it is rejected as corrupt
6. Widen the three `raw_op > @intFromEnum(OpCode.<last>)` range checks that
   guard the decoders (`vm_dispatch.zig`, `bytecode_file_read.zig`,
   `disassembler.zig`) — they name the last enum member, so appending moves
   them
7. Update the table in `docs/dev/bytecode.md`
