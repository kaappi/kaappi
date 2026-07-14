# Diagnostic codes and the stability policy

Every user-facing diagnostic Kaappi prints carries a stable `KP`-prefixed code:

```
err.scm:2: error[KP3001]: undefined variable 'countr'. Did you mean 'count'?
```

The code is the part a tool — an AI agent, a CI gate, an editor — matches on. The
message after it is free to improve release to release; the code is the contract.

**Source:** `src/diagnostics.zig` (the registry) · **Tests:** `src/tests_diagnostics.zig`
and `tests/scheme/errors/error-format.sh`

This is the keystone of the "machine legibility" campaign
([kaappi#1503](https://github.com/kaappi/kaappi/issues/1503)); the design record
is [KEP-0005](https://github.com/kaappi/keps/blob/main/keps/0005-diagnostic-contract.md).
Everything else in the campaign (`--diagnostics=json`, `kaappi explain`,
`error-object-code`) reads from this one registry.

Related surfaces built on the registry:

- [diagnostics-json.md](diagnostics-json.md) — the structured JSON form of these
  diagnostics (the LSP `Diagnostic` shape emitted by `--diagnostics=json`).
- [explain.md](explain.md) — `kaappi explain <code>`, the binary's own offline
  diagnostic reference (prose + example + fix for every code).

---

## The registry

`src/diagnostics.zig` is the single source of truth. One comptime `table` binds
together, per diagnostic, the things that used to live apart:

- **the code** — a `Code` enum value whose *integer is the KP number*, so
  `undefined_variable = 3001` renders as `"KP3001"`;
- **the message template** — the human message (currently a complete sentence;
  it gains `{…}` placeholders as raise sites pass structured arguments);
- **the explanation** — prose surfaced by [`kaappi explain <code>`](explain.md),
  which weaves in how to fix the diagnostic;
- **the example** — a minimal snippet that triggers the code, also shown by
  `kaappi explain`.

A `comptime` block enforces registry integrity *at build time*: every `Code` has
exactly one entry, no two entries collide, and every entry has a non-empty name,
template, explanation, and example. A malformed registry fails `zig build`; the
runtime mirror of the same check lives in `src/tests_diagnostics.zig`.

## The taxonomy

The leading digit tells an agent which pipeline stage a diagnostic came from:

| Range | Stage | Source of truth |
|-------|-------|-----------------|
| `KP1xxx` | Read / lexical | `reader*.zig` |
| `KP2xxx` | Expand / compile | `expander.zig`, `compiler*.zig`, `ir.zig` |
| `KP3xxx` | Runtime | `vm*.zig`, `primitives*.zig` |
| `KP4xxx` | Static analysis / lint | `kaappi check` — reserved ([#1511](https://github.com/kaappi/kaappi/issues/1511)) |
| `KP9xxx` | Internal / resource | internal-compiler-error and out-of-memory paths |

Ranges are deliberately sparse (1000 codes per stage). Granularity target: **one
code per user-distinguishable condition** — finer than the internal `KaappiError`
enum, which maps *many-to-one* onto codes. The `Code` namespace is curated and
independent of the internal Zig error sets on purpose (KEP-0005 "Alternatives
considered"): a coarse `TypeError` can later fan out into several codes without
touching the enum.

## The output format

The stage word is kept for the human reader; the bracketed code is inserted
before the colon:

```
<stdin>:1:12: read error[KP1002]: unexpected character
<stdin>:1: compile error[KP2001]: invalid syntax
<stdin>:1: syntax-error[KP2002]: bad usage 1
err.scm:2: error[KP3001]: undefined variable 'countr'. Did you mean 'count'?
```

All reporting flows through `src/toplevel_driver.zig` (`reportReadError`,
`reportCompileError`, `reportRuntimeError`), which the REPL, file runner, and
stdin runner share. The bundled-binary and `include` paths use the same registry.

## How a diagnostic gets its code

Two mechanisms, by stage:

- **Read and compile errors** are Zig error enums (`ReadError`, `CompileError`).
  `diagnostics.readErrorCode` / `compileErrorCode` map them to codes and the
  registry supplies the message. This is what retired the old
  `read error: error.UnexpectedChar` leaks — a raw Zig error name never reaches
  the user; unknown values resolve to a stage-appropriate catch-all.

- **Runtime errors** come in two worlds. Errors that propagate as a native
  `VMError` (undefined variable, type error, arity, …) are coded by
  `diagnostics.runtimeErrorCode` from the escaping error. Errors *raised as
  error objects* (division by zero, and anything from `raise`/`error`) carry
  their code **on the object** — `ErrorObject.code`, stamped at the raise site
  via `GC.allocErrorObjectCoded`. `VM.noteUncaughtException` lifts that code to
  the reporting layer. A user `(error …)` is uncoded (`.uncategorized`) and
  surfaces as the generic `KP3000` "uncaught exception"; the `KP` namespace is
  reserved to the implementation.

Carrying the code on the object (rather than in transient VM state) is what makes
it survive `guard` catch/re-raise, and it is the seed the Phase-4
`error-object-code` accessor will read.

### The migration is incremental

Not every raise site is coded yet — that is a long tail (KEP-0005 "Drawbacks").
The high-traffic diagnostics are coded first; an unmigrated error-object raise
simply shows `KP3000` until its site is stamped. `runtimeErrorCode` /
`readErrorCode` / `compileErrorCode` guarantee that *some* real code and message
always print, so no path ever regresses to leaking a Zig name.

## Stability policy — the contract

This is the load-bearing commitment, and the reason a registry beats scattered
strings:

1. **Once a code appears in a released version, it is never renumbered and never
   reused for a different meaning.** A diagnostic that is removed leaves its code
   permanently reserved — add a tombstone entry, do not recycle the number.
2. A code's **message text and explanation may be reworded freely.** That is the
   whole point of separating the stable code from the mutable prose.
3. A code's **severity may tighten or relax** across a major version (an error
   demoted to a warning, say), but the code persists.
4. **Pre-1.0 latitude.** Until Kaappi reaches a stability milestone, codes are
   *intended* stable but the registry may be renumbered in bulk **once**, loudly,
   if the initial taxonomy proves wrong — after which rule 1 is absolute.

Because the `Code` enum's integer value *is* the KP number, "never renumber"
means: never change an existing enum value. New codes take the next free ordinal
in their stage range.

## Adding a new code

1. Add a `Code` enum value in the right stage range with the next free ordinal,
   and a matching `table` entry (name, template, explanation, example). The
   comptime gate fails the build if you forget the entry or collide a number.
2. Route the raise site to it:
   - reader/compiler: add the `error.Xxx => .your_code` arm to
     `readErrorCode` / `compileErrorCode`;
   - runtime native error: add the arm to `runtimeErrorCode`;
   - runtime error object: stamp it at the raise site with
     `gc.allocErrorObjectCoded(msg, irritants, .your_code)`.
3. Add assertions to `tests/scheme/errors/error-format.sh` (the code appears; no
   Zig name leaks) and, if useful, a unit test in `src/tests_diagnostics.zig`.
4. Keep the explanation genuinely explanatory and give a real triggering
   `example` — they are what [`kaappi explain`](explain.md) shows, and
   `tests/scheme/errors/explain.sh` runs every example to confirm it still
   triggers its own code.
