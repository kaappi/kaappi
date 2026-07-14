# `kaappi explain <code>` — the binary as its own diagnostic reference

Every diagnostic Kaappi prints carries a stable `KP` code
([diagnostics.md](diagnostics.md)). `kaappi explain` turns those codes into
documentation that ships *inside the binary* — offline, version-matched, and
identical for a human reading prose and an agent parsing JSON. The model is
Rust's `rustc --explain E0308`.

```
kaappi explain KP3001
```

```
KP3001  undefined-variable
runtime · error

undefined variable

A variable was referenced that has no binding in scope. Check for a typo
(Kaappi suggests the nearest defined name), a missing 'import', or a
'define' that has not run yet because it appears after the reference.

Example:
    (display undefined-name)
```

The output has the three things an agent (or a human in a hurry) needs to go
from a failing program to a fix: **prose** for what the diagnostic means, a
minimal **example** that triggers it, and — woven into the prose — how to
**fix** it.

## Forms

| Invocation | Output |
|------------|--------|
| `kaappi explain KP3001` | The entry for one code, as text. |
| `kaappi explain undefined-variable` | Same — the code argument accepts the kebab **name**, a bare number (`3001`), or the rendered code in any case (`kp3001`). |
| `kaappi explain --json KP3001` | The entry as one JSON object. |
| `kaappi explain --all` | Every registered code, as text (the full reference). |
| `kaappi explain --all --json` | Every code as a single JSON **array** — the source a docs generator consumes. |

Output goes to **stdout**; it is requested content, not a diagnostic. An unknown
code, a missing argument, or `--all` combined with a code is a usage error
(exit `2`) reported on stderr with stdout left empty.

## The JSON object

`--json` emits the registry entry with the same stable-code / mutable-prose
split as the [`--diagnostics=json`](diagnostics-json.md) contract: match on
`code`/`name`/`stage`, treat `message`/`explanation`/`example` as prose that may
be reworded release to release.

| Field | Type | Notes |
|-------|------|-------|
| `code` | string | The stable `KP` code, e.g. `"KP3001"`. |
| `name` | string | The stable kebab-case name, e.g. `"undefined-variable"`. |
| `stage` | string | Pipeline stage from the leading digit: `read`, `compile`, `runtime`, `static-analysis`, `internal`. |
| `severity` | string | `"error"` or `"warning"`. |
| `message` | string | The one-line message template. |
| `explanation` | string | Prose explanation (carries the fix). May contain newlines. |
| `example` | string | A minimal triggering snippet. May contain newlines. |

```json
{"code":"KP3004","name":"division-by-zero","stage":"runtime","severity":"error","message":"division by zero","explanation":"An exact division, 'modulo', 'remainder', or 'quotient' had a zero\ndivisor. ...","example":"(/ 1 0)"}
```

The JSON string escaper is shared with `--diagnostics=json`
(`lsp_diagnostic.writeJsonString`), so both machine surfaces escape identically.

## The website page is generated, never hand-written

`kaappi explain --all --json` is the single source a docs generator reads to
build the diagnostics reference on kaappi-lang.org. Because the page is
generated from the same registry the binary emits from, it **cannot drift** from
what Kaappi actually prints — a stale reference page is a build artifact to
regenerate, not prose to keep in sync by hand.

## Examples are tested, not just present

Each registry `example` is a real, minimal trigger (a handful — deeply nested
input, internal invariants — are necessarily representative and say so in the
snippet). `tests/scheme/errors/explain.sh` runs every runnable example back
through the interpreter under `--diagnostics=json` and asserts it emits the code
it is documented under. So an example that stops triggering its own code — or a
code whose message moves — fails CI, not a user.

## Where it lives

| Piece | File |
|-------|------|
| Command parsing, text/JSON rendering | `src/explain.zig` |
| Registry (codes, names, prose, examples) | `src/diagnostics.zig` |
| Early dispatch (before VM/GC setup) | `src/main.zig` (`explain.maybeRun`) |
| Shared JSON string escaper | `src/lsp_diagnostic.zig` |
| Shell completions (`explain` subcommand) | `src/completions.zig` |
| Tests | `src/explain.zig` (unit), `tests/scheme/errors/explain.sh` (end-to-end) |
