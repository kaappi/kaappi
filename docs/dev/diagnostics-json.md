# `--diagnostics=json` — machine-readable diagnostics

By default Kaappi prints diagnostics as human-oriented text
([diagnostics.md](diagnostics.md)). Passing `--diagnostics=json` switches the
output to **JSON Lines** so an agent, CI gate, or editor can consume errors
structurally instead of scraping prose:

```
kaappi --diagnostics=json file.scm
```

Each diagnostic is emitted as **one JSON object per line on stderr**. Program
output on stdout is unaffected, so redirect the two apart:

```
kaappi --diagnostics=json file.scm 2>diagnostics.jsonl
```

`--diagnostics=text` is the explicit spelling of the default; any other value is
a usage error.

## The schema is the LSP `Diagnostic`

We do **not** invent a schema. Each line is a Language Server Protocol
[`Diagnostic`](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#diagnostic)
object — the exact shape the Kaappi language server already publishes for
`textDocument/publishDiagnostics`, and the shape editors and agents already
understand. The CLI and the LSP share one serializer
(`src/lsp_diagnostic.zig`), so the two can never drift.

| Field | Type | Notes |
|-------|------|-------|
| `range` | `{ start, end }` of `{ line, character }` | **Zero-based**, per LSP. See *Positions* below. |
| `severity` | integer | LSP `DiagnosticSeverity`: `1` Error, `2` Warning, `3` Information, `4` Hint. Every diagnostic is `1` today. |
| `code` | string | The stable `KP` code from the [registry](diagnostics.md), e.g. `"KP3001"`. The machine handle; match on this, not on `message`. |
| `source` | string | Always `"kaappi"`. |
| `message` | string | Human-readable text. Free to be reworded release to release — do not match on it. |
| `data.suggestions` | array | Present only when a fix is offered (see *Suggestions*). Omitted otherwise. |

Example (an undefined variable on the second line, with a "did you mean" fix).
The range is a point at the start of the enclosing form — a runtime diagnostic
carries a start column but no end (see *Positions*):

```json
{"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":0}},"severity":1,"code":"KP3001","source":"kaappi","message":"undefined variable 'countr'","data":{"suggestions":[{"kind":"rename","replacement":"count"}]}}
```

## Coverage — all four stages

`--diagnostics=json` covers every pipeline stage a program can fail in. The
leading digit of the code identifies the stage (full taxonomy in
[diagnostics.md](diagnostics.md)):

| Stage | Codes | Example trigger |
|-------|-------|-----------------|
| Read / lexical | `KP1xxx` | `(display "abc` → `KP1006` unterminated string |
| Expand (macros / `syntax-rules`) | `KP2002` | `(syntax-error "bad" 42)` → `KP2002` |
| Compile | `KP2xxx` | `(if)` → `KP2001` invalid syntax |
| Runtime | `KP3xxx` | `(car 5)` → `KP3002` type error |

## Positions

LSP positions are **zero-based** for both `line` and `character`, so a reader
error the text formatter prints as `file.scm:2:5` becomes
`{"line":1,"character":4}`.

The reader records a `(line, col, end_line, end_col)` span for every datum,
threaded through IR into the bytecode line table
([kaappi#1506](https://github.com/kaappi/kaappi/issues/1506)). How much of that
span reaches a diagnostic depends on the stage:

- **Read errors** carry a line and column, so the range is a point at the error
  position.
- **Compile errors** carry a full range: `start` at the offending form's opening
  paren and `end` one past its closing paren. The form is the innermost one the
  compiler was working on, so a nested error is pinpointed — `(define (f) (if))`
  ranges over just the inner `(if)`.
- **Runtime errors** carry the start column of the form whose instruction
  raised (from the bytecode line table), but no end; the range is a point at
  that column. An unknown position maps to line/character 0.

Widths therefore vary by stage; the `code` and `message` are stable regardless.
An unknown component (line or column) is `0`.

## Suggestions

When Kaappi can offer a concrete fix it appears under `data.suggestions`, an
array mirroring LSP code-action semantics. Today the only producer is the
undefined-variable "did you mean" corrector:

```json
"data":{"suggestions":[{"kind":"rename","replacement":"count"}]}
```

| Field | Meaning |
|-------|---------|
| `kind` | The flavour of fix. `"rename"` = substitute the flagged token. |
| `replacement` | The text to substitute. |

In JSON mode the redundant "Did you mean …?" hint is stripped from `message`
(the structured suggestion is the canonical form); in text mode the hint stays
inline.

## Notes and limits

- The stack trace and source snippet that text mode prints after a runtime error
  are suppressed in JSON mode, so the stderr stream stays one parseable object
  per line. Surfacing frames as LSP `relatedInformation` is future work.
- A standalone **bundled** binary (`zig build -Dbundle-src=…`) still reports its
  own top-level errors as text; `--diagnostics=json` governs the interpreter's
  read/expand/compile/runtime funnel (`src/toplevel_driver.zig`), which the file
  runner, stdin runner, and REPL share.

## Where it lives

| Piece | File |
|-------|------|
| Shared LSP `Diagnostic` shape + serializer | `src/lsp_diagnostic.zig` |
| CLI flag parsing | `src/cli.zig` |
| Reporting funnel (text ⇄ json switch) | `src/toplevel_driver.zig` |
| Code registry (source of `code`/`message`) | `src/diagnostics.zig` |
| LSP consumer of the same serializer | `src/kaappi_lsp.zig` |
| Tests | `tests/scheme/errors/diagnostics-json.sh`, `src/lsp_diagnostic.zig` |
