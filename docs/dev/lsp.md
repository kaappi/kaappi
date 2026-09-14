# The language server

How `kaappi-lsp` works: the transport and the lifecycle rules, what it
reuses from the interpreter and what it keeps of its own, how one
long-lived VM diagnoses many documents without their state leaking into
each other, and which editor features are the compiler's and which are a
lexical scan. This is the as-built companion to
[KEP-0015](https://github.com/kaappi/keps/blob/main/keps/0015-language-server.md)
(the design record) and sits on the diagnostic contract that
[diagnostics-json.md](diagnostics-json.md) and [check.md](check.md)
describe. The user-facing setup — editor configuration, the VS Code
extension — is the site's editors guide.

The one-paragraph version: **the server is `kaappi check` behind a
JSON-RPC loop.** It owns a VM, reads framed requests from stdin, and on
every open or change runs the exact analysis `kaappi check` runs —
`check.analyzeSource` into a `check_lint.Context` — then serializes every
finding through the one `Diagnostic` writer the CLI also uses. Nothing
about diagnosis is LSP-specific, so the editor and the command line cannot
disagree. Completion and hover read the live globals table; document
symbols, definition and references are shallow reads of the current
document, not scope analysis.

## Where it sits

| File | Owns |
|------|------|
| `kaappi_lsp.zig` | the `main` loop, framing, the document store, the per-run isolation, the six feature handlers |
| `lsp_diagnostic.zig` | the `Diagnostic` shape and its serializer, shared with `--diagnostics=json` ([diagnostics-json.md](diagnostics-json.md)) |
| `check.zig`, `check_lint.zig` | `analyzeSource`, `collectTopLevelDefines`, the `Context`/`Finding` types the server drives ([check.md](check.md)) |
| `build.zig` | the `kaappi-lsp` executable: its own root, a 64 MiB stack, installed beside `kaappi` |

There is no `kaappi lsp` subcommand; the server is a separate binary and
the VS Code extension launches it by path (`kaappi.lspPath`, default
`kaappi-lsp`) over stdio. It advertises a hardcoded `serverInfo.version`
of `0.1.0`, decoupled from the kaappi release.

## Transport and lifecycle

JSON-RPC 2.0 over stdio with LSP `Content-Length` framing. `readMessage`
reads headers byte by byte to the blank line, parses the length, and reads
exactly that many body bytes; `writeAll` retries short writes and `EINTR`
because a partial frame desynchronizes every later message. Bodies are
parsed with `std.json`; responses are assembled by hand and the request id
is spliced back verbatim (`formatIdValue`: an integer or a string; any
other id is an Invalid Request answered with id `null`, never a
fabricated one). Logging goes to fd 2. On Windows `initStandardStreams`
keeps fd 1 byte-faithful so CRT newline rewriting cannot corrupt a frame;
on OpenBSD the server raises its own stack limit because, unlike `kaappi`,
it compiles on the main thread ([openbsd.md](openbsd.md)).

The lifecycle follows LSP 3.17 exactly, and each rule below was a defect
once (#1980):

- a request before `initialize` is `-32002` "not initialized"; an
  `initialize` sent as a notification gets no reply and does not complete
  the handshake;
- after `shutdown`, every request except `exit` is `-32600`;
- `exit` without a prior `shutdown` exits with status 1, so a supervising
  client can tell a clean shutdown from a crash;
- a malformed `Content-Length` or a missing body skips that frame and
  resynchronizes on the next header rather than ending the session;
- a request missing its `textDocument` or `position` is `-32602`; an
  unknown method with an id is `-32601`; a column past the end of a line
  clamps to the line end instead of walking into the next one.

## Capabilities

The `initialize` result is a static string: `textDocumentSync: 1` (full
text), `completionProvider` (no resolve, no trigger characters),
`hoverProvider`, `documentSymbolProvider`, `definitionProvider`,
`referencesProvider`. Diagnostics are push-only. Not implemented and not
advertised: formatting (`kaappi fmt` is wired as an editor filter, not an
LSP feature — [fmt.md](fmt.md)), semantic tokens, signature help, rename,
code actions, folding, workspace symbols, `didSave`, and pull diagnostics.

| Method | Handler | What it does |
|--------|---------|--------------|
| `textDocument/didOpen`, `didChange` | `handleDidOpenOrChange` | store the full text (`contentChanges[0].text` on change), run diagnostics, publish |
| `textDocument/didClose` | inline | drop the document, publish an empty array |
| `textDocument/completion` | `handleCompletion` | globals filtered by the prefix before the cursor |
| `textDocument/hover` | `handleHover` | type and arity of a global |
| `textDocument/documentSymbol` | `handleDocumentSymbol` | top-level definitions |
| `textDocument/definition` | `handleDefinition` | the defining form in the same document |
| `textDocument/references` | `handleReferences` | every lexical occurrence in the document |

## Diagnostics are `kaappi check`

`runDiagnostics` is the heart of the server. After the isolation steps
below, it collects the document's top-level names
(`collectTopLevelDefines`), builds a `check_lint.Context` over an arena,
and calls `check.analyzeSource` — the same function `kaappi check` and
its unit tests call. That function reads form by form, evaluates the
environment-setup heads (`import`, `define-library`, `include`,
`define-record-type`) for their effect so later forms see their bindings
and macros, splices top-level `begin` and `cond-expand`, compiles every
other form with optimization off and the lint collector active, and never
executes program code. Read errors, compile errors and every `KP4xxx`
lint land in `ctx.findings`, sorted by position.

Each finding then goes through `lsp_diagnostic.Diagnostic.writeJson` with
`spanRange(finding.span)` — the real character range — the registry
severity, and the rendered `KP` code, into an allocating writer, so an
arbitrarily long message is emitted rather than truncated. The comma
separator is appended only after a finding serialized, so one failure
cannot produce `[,` and corrupt the array. This is what #1981 established:
before it the server stopped at the first failing form, never reported a
lint, and fabricated whole-line ranges. `tests/scheme/lsp/lsp.sh` now
cross-checks the published array against `kaappi check --diagnostics=json`
on the same text, code for code and line for line.

Procedural macro transformers run during analysis here as they do under
`check`; the policy is
[decisions/compile-time-macro-execution.md](decisions/compile-time-macro-execution.md).

### One VM, many documents

A single long-lived VM analyzes every document, so each run starts by
undoing what the previous one left behind:

- **Macros.** `vm.macros` is reset to `baseline_macros`, a snapshot taken
  at startup and rooted through `extra_roots` (the GC cannot see the
  compiler-side table). A `define-syntax` in one document therefore never
  leaks into another's diagnostics (#1979); within a document, macros
  still accumulate top to bottom as `check` gives a standalone file.
- **Globals.** `pruneImportedGlobals` removes every global not present at
  startup (`baseline_global_keys`), under the globals write lock and with
  `bumpGlobalVersion` so cached lookups are invalidated. The consequence,
  intended and bounded: a document's imported names resolve for hover and
  completion only until another document is opened or edited, and
  self-heal on that document's next run.
- **Paths.** A `file://` URI is percent-decoded by `fileUriToPath`
  (empty or `localhost` authority, Windows drive letters); the document's
  directory becomes `current_lib_dir` for `include` and is prepended to
  `vm.lib_paths` for a sibling `.sld`, exactly as `main.zig` seeds them
  for `kaappi check`. The base paths are `~/.kaappi/lib` and
  `<exe>/../lib`, computed by the same `kaappi_paths` helpers the binary
  uses so the two cannot drift (#1523).
- **Output.** `beginOutputRedirect` points `current-output-port` and the
  VM's stdout port at a discard string port for the run, so a stray
  `(display …)` in an imported library body cannot write to fd 1 and
  corrupt the framing. A C library that writes to fd 1 directly during
  its load still bypasses this; closing that would mean `dup2`, which is
  platform-specific and risks the framing if a restore is ever missed.

## Completion and hover

Both read the **live `vm.globals`**: built-ins plus whatever the current
document's executed `import`s added this run. Completion iterates the
table, keeps keys starting with the symbol characters before the cursor
(`getSymbolAtPosition`), and assigns a kind by the value's type
(procedure → Function, syntax → Keyword, else Variable). Hover looks up
the full symbol under the cursor and renders its type name and arity from
the value; a name that is not a global gets `null`. There is no docstring
source and no completion of a document's own lexical bindings.

## Navigation is a lexical read

The three navigation features re-read the document rather than consult
the compiler:

- **documentSymbol** reads each top-level datum with the real reader and
  matches `define` (variable or function form), `define-syntax`,
  `define-record-type` and `define-library` heads, reporting a
  line-granular location (character 0).
- **definition** scans top-level forms for a `define`, `define-syntax` or
  `define-record-type` whose name matches the symbol under the cursor —
  the same document only, first match, character 0. It does not follow
  imports or internal defines.
- **references** is a byte scan of the document text: it skips strings
  and `;` comments, and reports every whole-symbol match with exact
  columns. There is no scope analysis, so a shadowed local and a global of
  the same name are the same reference.

`isSymbolChar` is the server's own notion of an identifier character for
these scans; it is narrower than the reader's (no Unicode, no `|`), which
is the accepted cost of not parsing for a cursor query.

## Tests

| Suite | Covers |
|-------|--------|
| `tests/scheme/lsp/lsp.sh` (161 assertions in 9 sections) | the advertised capability inventory; framing; a full session; the diagnostics cross-check against `kaappi check --diagnostics=json`; protocol edges (pre-initialize, post-shutdown, bad ids, malformed framing and bodies); document-store edges; hostile and non-Scheme content; position handling; cross-document state leakage in both directions |
| `src/kaappi_lsp.zig` (6 inline tests) | request-id formatting and the JSON field accessors |
| `src/lsp_diagnostic.zig` (8) | the shared serializer: shapes, escaping, `pointRange`/`spanRange`, severity mapping |
| `src/tests_check.zig` | `analyzeSource` itself, which the server reuses unchanged |

The shell driver spawns the real binary per case and feeds it framed
bytes, which is what makes the leakage cases meaningful: anything that
persists does so inside one session by design. It self-skips when
`kaappi-lsp` is not built.

## What this design does not do

- **Incremental sync or incremental analysis.** Every change replaces the
  whole text and re-runs the whole analysis.
- **Cross-file navigation, scope-aware references, local-binding
  completion, docstrings.** Each is a lexical or globals-table read by
  design; KEP-0015 records them as open questions.
- **A second diagnostic path.** The serializer and the analysis are both
  shared with the CLI; the server must not grow its own.
- **Formatting over LSP.** `kaappi fmt` stays an editor filter.
