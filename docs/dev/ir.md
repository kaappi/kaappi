# Intermediate Representation (IR)

The compiler IR is a tree-structured intermediate representation that sits
between the macro expander and bytecode emission. It enables shared analysis
and optimization passes that benefit both the bytecode VM and LLVM backend, and
provides a clean lowering target for a future native backend.

**Source:** `src/ir.zig` (~1,400 lines)
**Tests:** `src/tests_ir.zig` (~850 lines)

---

## Pipeline

The `compile()` function in `compiler.zig` orchestrates the full pipeline:

```text
S-expression (post-expansion)
    |
    v  lowerWithMacros()
IR Node tree
    |
    v  markTailPositions()      } the one analysis pass
    |
    v  foldConstants()         \
    v  eliminateDeadBranches()  \
    v  simplifyBooleans()        } optimization passes
    v  eliminateIdentity()      /
    v  simplifyBegin()         /
    |
    v  compileFromNode()
Bytecode
```

---

## Node Types

Each IR node has a `NodeTag`, a `Data` union, and an `Annotations` struct.
There are **18** node tags, grouped by how they carry data.

The IR is much less lowered than the tag count alone suggests. Only the first
group below has its sub-expressions recursively lowered into IR nodes; the four
binding tags keep their bindings as raw S-expressions, and every remaining
special form collapses into the single `sexpr_form` tag, discriminated by one
of 18 `FormKind`s. So a `cond` is not its own node type — it is
`sexpr_form` carrying `.cond`.

### Fully lowered (sub-expressions are IR nodes)

| Tag | Data type | Description |
|-----|-----------|-------------|
| `constant` | `Value` | Literal value (fixnum, string, boolean, nil, etc.) |
| `global_ref` | `Value` | Symbol reference to a global variable |
| `call` | `CallData` | Function call: operator node + argument nodes |
| `if` | `IfData` | Conditional: test, consequent, optional alternate |
| `begin` | `[]*Node` | Sequence of expressions |
| `and_form` | `[]*Node` | Short-circuit `and` |
| `or_form` | `[]*Node` | Short-circuit `or` |
| `when_form` | `CondBodyData` | `when`: test node + body nodes |
| `unless_form` | `CondBodyData` | `unless`: test node + body nodes |
| `define` | `DefineData` | Variable definition: name symbol + value S-expr |
| `set_form` | `SetData` | Variable mutation: name symbol + value S-expr |
| `lambda` | `LambdaData` | Lambda: args S-expr + optional name |

### Binding forms (bindings stored as a raw S-expression)

These four have their own tags but share `LetData`, which holds the whole form
tail unlowered. `compileFromNode()` delegates them to `compiler_bindings.zig`.

| Tag | Scheme form |
|-----|-------------|
| `let_form` | `let` |
| `let_star` | `let*` |
| `letrec` | `letrec` |
| `letrec_star` | `letrec*` |

### S-expression delegation (one tag, 18 form kinds)

| Tag | Data type | Description |
|-----|-----------|-------------|
| `sexpr_form` | `SexprFormData` | A `FormKind` discriminant plus the unlowered form tail |

Recognized during lowering but not recursively lowered; `compileFromNode()`
dispatches on the `FormKind` to the existing form compilers. The 18 kinds and
their keywords:

| FormKind | Keyword | FormKind | Keyword |
|----------|---------|----------|---------|
| `do_form` | `do` | `let_values` | `let-values` |
| `delay` | `delay` | `let_star_values` | `let*-values` |
| `delay_force` | `delay-force` | `define_syntax` | `define-syntax` |
| `cond` | `cond` | `define_property` | `define-property` |
| `case_form` | `case` | `named_let` | `let` (named) |
| `case_lambda` | `case-lambda` | `let_syntax` | `let-syntax` |
| `guard` | `guard` | `letrec_syntax` | `letrec-syntax` |
| `quasiquote` | `quasiquote` | `cond_expand` | `cond-expand` |
| `parameterize` | `parameterize` | | |
| `define_values` | `define-values` | | |

`sexpr_form_map` maps keyword → `FormKind` for 17 of them. `named_let` is the
exception: it has no keyword of its own, so `lowerLet` detects it structurally
(a `let` whose second element is a symbol). `FormKind.keyword()` is the inverse
and covers all 18.

### Fallback

| Tag | Description |
|-----|-------------|
| `passthrough` | Raw S-expression passed to `compileExpr()` unchanged. Used for remaining special forms (`syntax-rules`, `apply`, etc.) and macro invocations. |

---

## Data Structures

```zig
CallData      { operator: *Node, args: []const *Node }
IfData        { test_expr: *Node, consequent: *Node, alternate: ?*Node }
CondBodyData  { test_expr: *Node, body: []const *Node }
DefineData    { name: Value, value: Value }
SetData       { name: Value, value: Value }
LambdaData    { args: Value, name: ?[]const u8 }
LetData       { args: Value }
SexprFormData { form: FormKind, args: Value }
```

---

## Annotations

Every node carries an `Annotations` struct. It has exactly two fields:

| Field | Type | Set by | Meaning |
|-------|------|--------|---------|
| `is_tail` | `bool` | `markTailPositions` | Node is in tail position (enables TCO) |
| `span` | `types.Span` | the lowerer | Source span of the form this node came from, when the reader could key it (a pair or vector). `span.line == 0` means unknown; the compiler emits it into the bytecode line table so runtime errors can report `file:line:col` (kaappi#1506). |

---

## Lowering

Two entry points convert S-expressions to IR:

- **`lowerWithMacros(ir, expr, macros)`** — primary entry point; checks the
  macro table and falls back to `passthrough` for macro invocations
- **`lower(ir, expr)`** — convenience wrapper that calls
  `lowerWithMacros(ir, expr, null)`

All recursive lowering uses `lowerWithMacros` internally, threading the
macros parameter through helper functions. This ensures nested calls
produce proper `call` nodes instead of `passthrough` nodes.

Lowering dispatches on the head symbol of a pair. Per-form helpers:
`lowerIf`, `lowerQuote`, `lowerBegin`, `lowerLet`, `lowerDefine`,
`lowerSet`, `lowerList` (for and/or), `lowerCondBody` (for when/unless),
`lowerCall`.

**Hygienic renaming:** The lowerer strips `__hyg_N_` prefixes from symbol
names before matching special forms, so macro-generated forms are handled
correctly.

**Early constant folding:** `tryFoldFromAST()` is called during lowering
for call expressions. If the call is a known arithmetic/comparison operation
on constant fixnum arguments, it is folded to a `constant` node immediately
(before the IR optimization passes run).

---

## Analysis Pass

`markTailPositions` is the only analysis pass. Two others —
`identifyPrimitives` and `markConstants`, along with the
`is_primitive_call` / `primitive_name` / `is_constant` annotations they set —
were removed as dead code in v0.13.0 (#1039, #1041). The
primitive-name list they used survives in `ir.zig` as `isKnownGlobal`, but its
only caller is now the LLVM backend's `isKnownOrReservedGlobal` — it annotates
nothing and is not part of any IR pass.

### markTailPositions(node, is_tail)

Propagates tail-position information through the IR tree. A node in tail
position sets `ann.is_tail = true`, which `compileFromNode()` uses to emit
`tail_call` instead of `call`.

Propagation rules:

- `if`: test is non-tail; consequent and alternate inherit parent's tail status
- `begin`, `and`, `or`: last expression inherits; all others are non-tail
- `when`, `unless`: test is non-tail; last body expression inherits
- `call`: operator and arguments are always non-tail

---

## Optimization Passes

All passes take `(ir: *IR, node: *Node) -> *Node`. They return a new node
if the tree was transformed, or the original node if unchanged. Applied in
this order:

### 1. foldConstants

Evaluates constant primitive calls at compile time. Handles:

- Unary: `not`, `zero?`, `-` (negation)
- Binary: `+`, `-`, `*`, `<`, `>`, `<=`, `>=`, `=`

Fixnum overflow is checked — if the result exceeds i48 range, folding is
skipped and the call is left for runtime.

### 2. eliminateDeadBranches

Removes unreachable branches from `if` when the test is a constant:

- `(if #t A B)` → `A`
- `(if #f A B)` → `B`
- `(if #f A)` → `#void`

### 3. simplifyBooleans

Pattern-based boolean rewrites:

- `(not (not X))` → `X`
- `(if (not X) A B)` → `(if X B A)`

### 4. eliminateIdentity

Removes algebraic identity operations:

- `(+ x 0)` or `(+ 0 x)` → `x`
- `(* x 1)` or `(* 1 x)` → `x`
- `(* x 0)` or `(* 0 x)` → `0`
- `(- x 0)` → `x`

### 5. simplifyBegin

Structural cleanup:

- `(begin X)` → `X` (single-expression begin)
- Recursively simplifies nested begins

---

## Bytecode Emission

`compileFromNode()` in `compiler.zig` dispatches on the IR node tag:

- **Fully-lowered forms** (`constant`, `global_ref`, `call`, `if`, `begin`,
  `and_form`, `or_form`, `when_form`, `unless_form`, `define`, `set_form`,
  `lambda`) are compiled directly from their IR data structures.

- **Binding forms** (`let_form`, `let_star`, `letrec`, `letrec_star`) delegate
  to `compiler_bindings.zig` via their `LetData`.

- **`sexpr_form`** dispatches on its `FormKind` to the existing compiler
  sub-modules (`compiler_bindings.zig`, `compiler_advanced.zig`, etc.) via its
  `SexprFormData`.

- **`passthrough`** delegates to `compileExpr()`, the original
  syntax-directed compiler path.

Tail position: `compileFromNode()` uses `node.ann.is_tail` (set by
`markTailPositions`) instead of recomputing tail status.

---

## Testing

`tests_ir.zig` holds ~94 tests in four groups:

- **Behavioral** (`test "IR behavioral: …"`) — verify that IR-compiled code
  evaluates to the correct result at runtime. The bulk of the file.
- **Lowering** (`test "IR lowering: …"`) — verify the shape of the lowered
  tree for a given form
- **Analysis** (`test "IR analysis: …"`) — verify that `markTailPositions`
  annotates nodes correctly
- **Optimization** (`test "IR optimization: …"`, `test "IR fold: …"`,
  `test "IR opt: …"`) — verify that each optimization pass transforms nodes as
  expected (constant folding, dead branches, boolean simplification, identity
  elimination, begin simplification)

There is no longer a bytecode-parity group. It tested `ir.zig`'s standalone
`Emitter` against the direct compiler path; that emitter (and its own file,
`ir_emitter.zig`) was removed as a duplicate in v0.13.0, leaving
`compileFromNode()` as the only IR-to-bytecode path.

---

## Future: Native Backend

The IR is designed to serve as input for a future LLVM IR native backend
(Stage 6, issue #99). The direct-style IR (not CPS) was chosen to serve
both the bytecode and native backends without conversion. See
[continuation-strategy.md](decisions/continuation-strategy.md) for the hybrid
approach to `call/cc` in native code.
