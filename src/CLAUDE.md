# src/ — Kaappi Source

See the root `CLAUDE.md` for architecture, GC safety, and how-to guides.
This file covers patterns specific to working in this directory.

## Test files (`tests_*.zig`)

20 test files, one per feature area. Use helpers from `testing_helpers.zig`:

```zig
const th = @import("testing_helpers.zig");

// Shortest form — eval source, assert fixnum result:
test "descriptive name" {
    try th.expectEval("(+ 1 2)", 3);
}

// When the test needs multiple evals or result inspection:
test "multi-step test" {
    var ctx: th.TestContext = undefined;
    try ctx.init();
    defer ctx.deinit();
    _ = try ctx.vm.eval("(define x 42)");
    const result = try ctx.vm.eval("x");
    try std.testing.expectEqual(@as(i64, 42), types.toFixnum(result));
}
```

Available helpers: `th.expectEval(src, fixnum)`, `th.expectEvalTrue(src)`,
`th.expectEvalBool(src, bool)`, `th.expectEvalVoid(src)`.
Use `th.TestContext` when you need the VM for multiple evals or complex assertions.

## Compiler split

Forms are split by semantic domain. Add new forms to the right file:

| File | Forms |
|------|-------|
| `compiler_ir.zig` | IR-to-bytecode: compileFromNode dispatch, if, begin, call, lambda, define, set!, and, or, when, unless |
| `compiler_lambda.zig` | lambda, define, set!, begin, delay |
| `compiler_conditionals.zig` | and, or, when, unless, cond, cond-expand |
| `compiler_bindings.zig` | let, let*, letrec, letrec*, named let, do |
| `compiler_advanced.zig` | case, case-lambda, guard, quasiquote |
| `compiler_macro.zig` | define-syntax, let-syntax, letrec-syntax, macro expansion, syntax-rules parsing, hygiene free-ref collection |

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
