# src/ — Kaappi Source

See the root `CLAUDE.md` for architecture, GC safety, and how-to guides.
This file covers patterns specific to working in this directory.

## Test files (`tests_*.zig`)

16 test files, one per feature area. Every test follows this structure:

```zig
const std = @import("std");
const th = @import("testing_helpers.zig");
const types = @import("types.zig");

test "descriptive name" {
    var gc = try th.makeTestGc();
    defer gc.deinit();
    var vm = try th.makeTestVM(&gc);
    defer vm.deinit();

    const result = try vm.run(
        \\(+ 1 2)
    );
    try std.testing.expectEqual(@as(i64, 3), types.toFixnum(result));
}
```

Always use `th.makeTestVM` — no ad-hoc VM initialization.

## Compiler split

Forms are split by semantic domain. Add new forms to the right file:

| File | Forms |
|------|-------|
| `compiler_ir.zig` | IR-to-bytecode: compileFromNode dispatch, if, begin, call, lambda, define, set!, and, or, when, unless |
| `compiler_lambda.zig` | lambda, define, set!, begin, delay |
| `compiler_conditionals.zig` | and, or, when, unless, cond, cond-expand |
| `compiler_bindings.zig` | let, let*, letrec, letrec*, named let, do |
| `compiler_advanced.zig` | case, case-lambda, guard, quasiquote |

Then add the re-export in `compiler_forms.zig` (thin hub — don't add logic there).

## VM split

| File | Hot path? | Responsibility |
|------|:---------:|---------------|
| `vm_dispatch.zig` | **yes** | Bytecode loop, opcode handlers |
| `vm_calls.zig` | yes | callValue, callClosure, execute |
| `vm.zig` | no | State, init/deinit, error helpers |
| `vm_eval.zig` | no | eval, top-level form dispatch |
| `vm_library.zig` | no | import, define-library, .sld loading |
| `vm_records.zig` | no | define-record-type desugaring |
| `vm_continuations.zig` | no | call/cc, dynamic-wind |
| `vm_debug.zig` | no | Stepping debugger |

## Primitives files

Each `primitives_*.zig` has a `registerXxx` function that calls `primitives.reg()`
for every procedure. These files are intentionally broad (many independent
functions) — don't split them further. See `.claude/rules/gc-safety.md` for
write-barrier and rooting requirements when adding primitives that allocate.

## File size

Keep files under 1500 lines. Split along architectural seams, not function count.
Flat lists of independent functions (like primitives files) are fine past 1500.
