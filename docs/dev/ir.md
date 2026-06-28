# Intermediate Representation (IR)

The compiler IR is a tree-structured intermediate representation that sits
between the macro expander and bytecode emission. It enables shared analysis
and optimization passes that benefit both the bytecode VM and JIT, and
provides a clean lowering target for a future native backend.

**Source:** `src/ir.zig` (~1,500 lines)
**Tests:** `src/tests_ir.zig` (~540 lines)

---

## Pipeline

The `compile()` function in `compiler.zig` orchestrates the full pipeline:

```
S-expression (post-expansion)
    |
    v  lowerWithMacros()
IR Node tree
    |
    v  markTailPositions()     \
    v  identifyPrimitives()     } analysis passes
    v  markConstants()         /
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
The 33 node types are grouped by how they carry data:

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

### S-expression delegation (body stored as raw S-expression)

These forms are recognized and tagged during lowering but their
sub-expressions are not recursively lowered. The compiler's
`compileFromNode()` delegates them to the existing form compilers via
their `SexprArgs` data.

| Tag | Scheme form |
|-----|-------------|
| `let_form` | `let` |
| `let_star` | `let*` |
| `letrec` | `letrec` |
| `letrec_star` | `letrec*` |
| `named_let` | named `let` |
| `do_form` | `do` |
| `delay` | `delay` |
| `delay_force` | `delay-force` |
| `cond` | `cond` |
| `case_form` | `case` |
| `case_lambda` | `case-lambda` |
| `guard` | `guard` |
| `quasiquote` | quasiquote |
| `parameterize` | `parameterize` |
| `define_values` | `define-values` |
| `let_values` | `let-values` |
| `let_star_values` | `let*-values` |
| `define_syntax` | `define-syntax` |
| `let_syntax` | `let-syntax` |
| `letrec_syntax` | `letrec-syntax` |
| `cond_expand` | `cond-expand` |

### Fallback

| Tag | Description |
|-----|-------------|
| `passthrough` | Raw S-expression passed to `compileExpr()` unchanged. Used for remaining special forms (`syntax-rules`, `apply`, etc.) and macro invocations. |

---

## Data Structures

```zig
CallData    { operator: *Node, args: []const *Node }
IfData      { test_expr: *Node, consequent: *Node, alternate: ?*Node }
CondBodyData { test_expr: *Node, body: []const *Node }
DefineData  { name: Value, value: Value }
SetData     { name: Value, value: Value }
LambdaData  { args: Value, name: ?[]const u8 }
LetData     { args: Value }
SexprArgs   { args: Value }
```

---

## Annotations

Every node carries an `Annotations` struct set by the analysis passes:

| Field | Type | Set by | Meaning |
|-------|------|--------|---------|
| `is_tail` | `bool` | `markTailPositions` | Node is in tail position (enables TCO) |
| `is_primitive_call` | `bool` | `identifyPrimitives` | Call targets a known built-in |
| `primitive_name` | `?[]const u8` | `identifyPrimitives` | Name of the primitive (e.g. `"+"`) |
| `is_constant` | `bool` | `markConstants` | Expression evaluates to a compile-time constant |

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

## Analysis Passes

### markTailPositions(node, is_tail)

Propagates tail-position information through the IR tree. A node in tail
position sets `ann.is_tail = true`, which `compileFromNode()` uses to emit
`tail_call` instead of `call`.

Propagation rules:
- `if`: test is non-tail; consequent and alternate inherit parent's tail status
- `begin`, `and`, `or`: last expression inherits; all others are non-tail
- `when`, `unless`: test is non-tail; last body expression inherits
- `call`: operator and arguments are always non-tail

### identifyPrimitives(node)

Marks calls to known built-in procedures. If a `call` node's operator is a
`global_ref` matching one of 72 known primitive names, the node gets
`ann.is_primitive_call = true` and `ann.primitive_name` set.

Recognized primitives include: `+`, `-`, `*`, `/`, `=`, `<`, `>`, `cons`,
`car`, `cdr`, `list`, `map`, `apply`, `display`, `write`, `eq?`, `equal?`,
`string-append`, `vector-ref`, and ~50 others.

### markConstants(node)

Identifies compile-time constant expressions:
- `constant` nodes are always constant
- `call` nodes are constant if the operator is a primitive and all arguments
  are constant
- `begin` nodes inherit the constancy of their last expression

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

- **S-expression forms** (`let_form`, `cond`, `do_form`, etc.) delegate to
  the existing compiler sub-modules (`compiler_bindings.zig`,
  `compiler_advanced.zig`, etc.) via their `SexprArgs`.

- **`passthrough`** delegates to `compileExpr()`, the original
  syntax-directed compiler path.

Tail position: `compileFromNode()` uses `node.ann.is_tail` (set by
`markTailPositions`) instead of recomputing tail status. Primitive
identification: `node.ann.is_primitive_call` is passed through to call
emission for optimized dispatch.

---

## Standalone Emitter

`ir.zig` contains an `Emitter` struct that compiles IR nodes directly to
bytecode without going through the full compiler. This is used exclusively
by the test suite to verify bytecode parity between the IR path and the
direct compiler.

---

## Testing

`tests_ir.zig` covers four categories:

- **Parity tests** — verify that IR compilation produces identical bytecode
  to the direct compiler path for the same expression
- **Behavioral tests** — verify that IR-compiled code evaluates to the
  correct result at runtime
- **Analysis tests** — verify that each analysis pass annotates nodes
  correctly (tail positions, primitive identification, constant detection)
- **Optimization tests** — verify that each optimization pass transforms
  nodes as expected (constant folding, dead branches, boolean simplification,
  identity elimination, begin simplification)

---

## Future: Native Backend

The IR is designed to serve as input for a future LLVM IR native backend
(Stage 6, issue #99). The direct-style IR (not CPS) was chosen to serve
both the bytecode and native backends without conversion. See
[continuation-strategy.md](continuation-strategy.md) for the hybrid
approach to `call/cc` in native code.
