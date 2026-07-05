---
globs: ["src/compiler*.zig", "src/ir.zig", "src/tests_ir.zig"]
description: Checklist for adding or modifying compiler forms and IR nodes
---

# Compiler Form Rules

## Adding a new delegating form (passes raw s-expression to compiler)

Most new forms use this path — ~4 edits:

1. **`FormKind` variant** in `src/ir.zig`: add to the `FormKind` enum and
   implement `keyword()` to return the Scheme keyword string.

2. **`sexpr_form_map` entry** in `src/ir.zig`: add the keyword → FormKind
   mapping. (Skip if the form has no keyword — e.g. `named_let` is detected
   structurally by `lowerLet`, not by keyword.)

3. **Dispatch** in the `.sexpr_form` arm of `compileFromNode()` in
   `src/compiler_ir.zig`:
   ```zig
   .my_form => try forms.compileMyForm(self, sf.args, dst, tail),
   ```

4. **Implement** in the appropriate `compiler_*.zig` file + re-export through
   `compiler_forms.zig` + add **IR behavioral tests** in `src/tests_ir.zig`.

No changes needed to `NodeTag`, `Data` union, `freeNode`, analysis passes,
or optimization passes — those use `else` arms that handle `.sexpr_form`
automatically.

## Adding a new structured form (has IR-level children)

For forms that lower into structured IR nodes (like `if`, `begin`, `when`):

1. **`NodeTag` variant** + **`Data` union** field in `src/ir.zig`.

2. **Lowering** in `lowerFormWithMacros()` and a `makeXxx()` constructor.

3. **`freeNode`**: add arm if the node owns heap-allocated slices.

4. **`markTailPositions`**: add arm with correct tail-position propagation.

5. **`llvm_node_table`**: add entry with capability.

6. **`compileFromNode` dispatch** in `compiler_ir.zig`.

7. **Implement** + re-export + tests.

The 5 optimization passes use `else => return node` — no changes needed
unless the new form should participate in constant folding or simplification.
