---
globs: ["src/compiler*.zig", "src/ir.zig", "src/tests_ir.zig"]
description: Checklist for adding or modifying compiler forms and IR nodes
---

# Compiler Form Rules

When adding a new compiler form:

1. **IR node type** in `src/ir.zig`: add variant to `NodeTag`, add `Data` union
   variant (use `SexprArgs` for forms that delegate to existing compilers), add
   lowering in `lowerFormWithMacros()`/`lowerForm()`, handle in all 3 analysis
   pass switch arms, handle in all 5 optimization pass switch arms.

2. **Dispatch** in `compileFromNode()` in `src/compiler.zig`:
   ```zig
   .my_form => try forms.compileMyForm(self, node.data.my_form.args, dst, tail),
   ```

3. **Implement** in the appropriate `compiler_*.zig` file.

4. **Re-export** new public functions through `compiler_forms.zig`.

5. **IR tests** in `src/tests_ir.zig` — the IR-compiled path must produce
   identical results to the legacy `compileExpr()` path for every form.

6. **Tail position**: if the form can appear in tail position, ensure the
   compiler passes `tail=true` to the sub-expression that should receive
   the tail call optimization.
