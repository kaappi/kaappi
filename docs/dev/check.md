# `kaappi check` — compile-only static analysis

`kaappi check <file.scm>` answers "will this fail?" without running anything. It
reads, macro-expands, and compiles every top-level form — surfacing the same
read/expand/compile diagnostics a real run would, with their stable `KP` codes —
but executes no program code, and adds the reserved `KP4xxx` lint findings.

Part of the machine-legibility epic ([#1503](https://github.com/kaappi/kaappi/issues/1503));
tracked in [#1511](https://github.com/kaappi/kaappi/issues/1511). See also
[diagnostics.md](diagnostics.md) for the code registry and
[diagnostics-json.md](diagnostics-json.md) for the JSON shape it reuses.

## What it reports

| Code | Severity | Meaning |
|------|----------|---------|
| `KP4001` | warning | Unknown variable at top level — a free reference that is neither a built-in, an imported binding, nor defined anywhere in the file. |
| `KP4002` | error | Wrong argument count on a direct, unshadowed call to a known built-in. |
| `KP4003` | error | A literal argument whose type a known built-in cannot accept in that position. |

Plus every read (`KP1xxx`), expand/compile (`KP2xxx`), and env-setup runtime
(`KP3xxx`) diagnostic encountered while compiling the file.

- **Exit code** is nonzero if any finding is an error; `--deny-warnings`
  additionally counts warnings against it.
- **`--diagnostics=json`** emits one LSP `Diagnostic` per line on stdout — the
  same serializer as the run-mode flag and the LSP server, so there is nothing
  new to parse.

## The invariant

> `kaappi check` never rejects a program that R7RS says is valid. Anything the
> spec permits is at most a warning.

Two things carry this:

1. **Forward references are legal**, so an unknown top-level variable is only a
   warning — a name may be defined by a later top-level `define`, or reached
   through mutual recursion.
2. **The error-level checks fire only when the call is guaranteed to fail.** A
   wrong arity is compared against the built-in's registered arity — the *same*
   arity the VM enforces — so a flagged call would raise `KP3003` at run time,
   always. A wrong-type literal is flagged only for the narrow, curated set of
   built-ins where R7RS unambiguously requires a type in that position and the
   literal is definitely not it.

"R7RS says is valid" is the operative phrase. R7RS's "**it is an error** to apply
`car` to a non-pair" means the operation is *not* permitted — so flagging
`(car 5)` does not violate the invariant, even though the surrounding program
might catch the resulting condition with `guard`. The invariant protects
spec-*permitted* constructs (forward references, shadowing, redefinition, valid
literals), not operations the spec already calls errors.

## How the analysis works

`check` does not re-implement scope, macro expansion, or quoting. It drives the
**real** compiler over each form and discards the bytecode; the lint is a pass
over the IR the compiler already produces. The relevant code:

- `src/check.zig` — the driver: reads forms, processes environment-setup forms
  for effect, compiles everything else without executing it, then reports.
- `src/check_lint.zig` — the IR walker, the literal-type table, and the
  thread-local `Context` the walker fills.
- `src/ir.zig` — `lowerAndOptimize` calls `check_lint.maybeWalk` after lowering
  (before the optimization passes, so folding can't hide a call). Inert (one
  null-pointer test) outside a check run.
- `src/compiler_macro.zig` — `expandAndCompileMacroUse` brackets the compile of
  a macro expansion with `enter/exitMacroExpansion`.

Driving the compiler buys three things for free:

- **Scope and shadowing.** `IR.isRedefined` already answers "is this the genuine,
  unshadowed built-in?" from lexical scope, `set!` targets, and the globals
  table. A lexically-bound `car`, or one the user rebinds, is never flagged.
- **Recursion.** Lambda / `let` / `cond` bodies are compiled on demand through
  the same `lowerAndOptimize` choke point, so nested calls are analysed with
  their own correct scope, each walked exactly once.
- **Quoting.** Quoted data lowers to `constant` nodes, so `'(car 1 2)` is never
  seen as a call.

### Why macro expansions are suppressed

A "direct call to a built-in" is one the user wrote that survives to the IR
*outside* any macro expansion. Calls a macro synthesises are the macro's, not the
user's, so the walk is suppressed while compiling an expansion. This is what lets
the idiomatic error-test pattern pass:

```scheme
(import (chibi test))
(test-error (apply +))   ; a deliberate error the guard inside test-error catches
```

`test-error` is a macro, so its argument is not linted — the program is valid and
`check` must not reject it. Hand-rolled error tests that call the built-in
directly inside a `guard` body are still flagged; the finding is accurate (the
call does raise), and the `test-error` idiom is the documented way to say "I
expect this to error." Note also that some higher-order built-ins (`apply`,
`call/cc`, `eval`, `call-with-values`) lower to a special-form passthrough rather
than a call node, so their arity is not checked either.

### What runs, and what does not

Only environment setup runs: `import` / `define-library` / `include` /
`define-record-type` are processed (with lint suppressed over the library/record
code they compile) so later forms see the bindings and macros they introduce.
Ordinary `define`s and expressions are compiled and analysed but never executed;
their bound names are gathered structurally in a pre-pass so a forward reference
is not warned. `define-syntax` registers its macro at *compile* time, so a
later use of a same-file macro expands correctly without running anything.

## The literal-type table

`check_lint.zig`'s `type_table` is deliberately narrow. An entry belongs there
only when R7RS unambiguously requires a specific type in that position, so a
conflicting *literal* is always a run-time type error — never a value some
conforming program relies on. Higher-order and polymorphic built-ins (`map`,
`apply`, `append`, `cons`, `eq?`, `display`, `not`, …) are intentionally absent.
There is no inference: only self-evaluating and quoted literals are checked.

To extend it, add a `TypeSpec` row and a covering test in `tests_check.zig`. Do
**not** add a built-in whose argument can legitimately be more than one type in
that position — soundness (the invariant) comes first.

## Non-goal

This is not, and must not grow into, a type system. Lint classes beyond the
literal/arity checks need epic-level discussion first (see the non-goals on
[#1503](https://github.com/kaappi/kaappi/issues/1503)).

## Tests

- `src/tests_check.zig` — unit tests driving the compiler over source strings and
  asserting findings; the negative cases (shadowing, redefinition, quoting, macro
  suppression, non-literals) guard the invariant.
- `tests/scheme/errors/check.sh` — CLI behaviour, exit codes, `--deny-warnings`,
  `--diagnostics=json` parity, and the **conformance guard**: the full R7RS suite
  must pass `kaappi check` with zero errors (run in CI via `run-all.sh`).
- `tests/scheme/errors/explain.sh` — verifies each `KP4xxx` registry example
  triggers its code under `kaappi check`.
