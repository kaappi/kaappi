# Compile-Time Macro Execution under `check` and `--sandbox`

## Status

**Ratified** (2026-08-27, kaappi#2389). This note writes down the policy
[KEP-0006](https://github.com/kaappi/keps/blob/main/keps/0006-explicit-renaming-macros.md)
recommended in its Unresolved question 3 — candidate (a) — and that the
implementation has followed de facto since `er-macro-transformer` shipped in
v0.22.0 (kaappi#1811). Nothing in the code changes; the decision changes
status from "behavior" to "design".

## The decision

**Macro-defining code is compile-time code, not sandboxed program code.**
Procedural transformer bodies (SRFI 211 `er-macro-transformer` /
`lisp-transformer`) run wherever macro expansion runs — including under
`kaappi check`, the LSP, `kaappi expand`/`ir`, `kaappi compile`, and
`--sandbox`. Confinement comes from what compile-time code can *reach* (the
environment it expands in), never from pretending expansion runs nothing.

This is Racket's stance: its reference notes a sandbox "cannot fully contain
compile-time macro execution" and draws the trust boundary at what
compile-time code can reach, not at which phase it runs in (Racket Reference
§14.12, Sandboxed Evaluation). KEP-0006 weighed two alternatives and this
note ratifies their rejection:

- *(b) transformer bodies run under the same sandbox restrictions as the
  program* — conflates the phases as a special case; in Kaappi it is also
  redundant, because the sandbox is environmental rather than temporal (see
  below), so (a) already gives sandboxed expansion exactly the program's
  capability set.
- *(c) `check` refuses to fully expand files defining procedural
  transformers* — would cripple `check` for any file using them and
  diverges from every other Scheme with procedural macros.

## What runs during `kaappi check`

`check`'s contract is that it executes no *program* code — not that nothing
executes. Procedural macros add two compile-time execution points to the
environment-setup category (`import` / `define-library` /
`define-record-type`) that `check` has always processed for effect:

1. **Definition time.** `(define-syntax name (er-macro-transformer expr))`
   evaluates `expr` the moment the `define-syntax` is compiled
   (`resolveTransformerSpec` in `src/compiler_define_syntax.zig` calls the
   `eval_datum_for_macro` hook), even if the macro is never used.
2. **Every use.** Expanding a use of the macro calls the transformer
   procedure (`expandProceduralMacro` in `src/expander.zig` through the
   `call_proc_for_macro` hook, installed by `setVMInstance` in
   `src/vm.zig`). There is no check-mode guard, deliberately.

A transformer spec that *cannot* be resolved without executing program code
— an alias to a global a `define` would bind at run time, or a spec
expression referencing one — is accepted under analysis as a benign
placeholder transformer instead of a KP2001 false positive (kaappi#2007,
fixed by kaappi#2329, first released v0.24.0). The placeholder branch fires
only when `check_lint.active != null`; a real run still rejects an
unresolvable spec.

Consequences worth stating plainly:

- **`check` is not a sandbox.** Plain `kaappi check untrusted.scm` runs any
  transformer bodies in the full, unrestricted environment — a malicious
  file can write to disk during a "compile-only" check. Checking untrusted
  source calls for `kaappi check --sandbox` (the flag is global and
  composes with the subcommand).
- An error a transformer raises surfaces as a compile diagnostic at the
  macro use, not a crash. VM limits are phase-blind: `--timeout` and
  `--max-memory` are applied to the VM/GC before `check` dispatches
  (`src/main.zig`), so they bound expansion-time execution too — a looping
  transformer under `--timeout` dies with the usual timeout error at the
  use site. Without `--timeout`, `check` on a looping transformer hangs,
  as in every Scheme with procedural macros.

## What `--sandbox` gates, and why the phase ordering doesn't matter

The sharp case KEP-0006 flagged: a sandboxed program that merely *defines*
(never calls) a macro still runs its transformer body the moment another
form in the same file uses the macro during compilation — before the
program's own top level executes. If the sandbox were a runtime switch,
that would be a pre-sandbox execution window.

It is not a runtime switch. `--sandbox` is enforced by *constructing a
restricted global environment before any source is read*, so
expansion-time code and run-time code see the identical capability set —
there is no pre-sandbox phase. Concretely (`--sandbox` is pre-scanned in
`src/main.zig` before registration):

- **Primitive registration** — `registerSandboxed` (`src/primitives.zig`)
  registers only `spec.sandbox` primitives; file, filesystem, process, and
  FFI primitives are marked `.sandbox = false` and *never exist* in
  `vm.globals`.
- **Built-in libraries** — `Lib.sandboxAllowed` (`src/primitives.zig`)
  excludes `(scheme file)`, `(scheme load)`, `(scheme eval)`,
  `(scheme repl)`, `(scheme process-context)`, `(scheme r5rs)`,
  `(kaappi ffi)`, `(srfi 18)`, `(srfi 170)`, `(srfi 192)`; `(kaappi
  sysinfo)`'s path-revealing members opt out per-spec.
- **File-backed `.sld` loads are blocked wholesale**
  (`tryLoadLibraryFromFile` in `src/vm_library.zig`) so sandboxed code
  cannot probe the host filesystem via crafted import paths; only the
  comptime-embedded libraries in `embedded_libraries` load. `cond-expand`
  library probes likewise never touch disk under sandbox.
- **The bytecode cache is disabled** in both directions (`src/main.zig`,
  `vm_library_cache.shouldUseCache`) — no filesystem side effects.

Because the transformer body is compiled against, and executes in, that
same environment, the sharp case is contained: the early-running macro can
reach exactly what the sandboxed program itself could reach, nothing more.
Verified end-to-end — a transformer body calling `open-output-file` writes
its file under plain `kaappi check`, and fails with "undefined variable"
under `kaappi --sandbox` and `kaappi check --sandbox` alike, because the
binding was never registered.

Two shape notes, neither a policy gap:

- ER macros are definable under `--sandbox` *without any import*: the
  `(define-syntax name (er-macro-transformer expr))` spec form is
  recognized structurally by the compiler (`src/primitives_srfi211.zig`
  header comment), and `(srfi 211 primitives)` is a registry-backed
  library that remains importable. The transformer body still runs inside
  the restricted environment, so this widens nothing.
- The portable wrapper `(srfi 211 explicit-renaming)` is a `.sld` file and
  therefore **not importable under `--sandbox`** (it is not in
  `embedded_libraries`). Sandboxed code that wants the documented library
  name rather than the primitives sub-library currently cannot have it —
  a degradation quirk on the same ladder as the other non-embedded
  libraries, fixable by embedding if it ever matters.

## Residual limits

Same caveat Racket documents: compile-time code execution is arbitrary
computation. The sandbox bounds *reach* (capabilities), not *cost* — pure
CPU and memory consumption at expansion time are bounded only if the
invoker passes `--timeout` / `--max-memory`. That is the accepted trade of
candidate (a); anything stronger is candidate (c) in disguise.
