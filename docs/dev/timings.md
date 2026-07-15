# `--timings`: per-stage pipeline timings + cache visibility

`--profile` profiles the *user's program* — which of their procedures the VM
spends time in. Nothing reported how long *kaappi's own* pipeline stages take,
or whether a run was served from the `.sbc` bytecode cache. `--timings` fills
that gap: `zig build`-style transparency for kaappi's own work, for humans
chasing a slow startup and for CI to catch compiler-performance regressions.

Part of the machine-legibility epic
([#1503](https://github.com/kaappi/kaappi/issues/1503)); tracked in
[#1515](https://github.com/kaappi/kaappi/issues/1515). Builds directly on the
cache-transparency work in [#1516](https://github.com/kaappi/kaappi/issues/1516)
— the headline of `--timings` is that every timed run states cache **HIT** or
**MISS** and the path, so the invisible cache that
[cost real debugging hours](cache.md) can never be a silent variable again.

## Usage

```
kaappi --timings file.scm            # text summary on stderr
kaappi --timings=json file.scm       # one JSON object on stderr
kaappi --timings=text file.scm       # explicit text (the default)

kaappi --timings --compile file.scm  # the --compile (bytecode) path
kaappi --timings compile file.scm    # the native (LLVM) compile path
```

The output always goes to **stderr**, like `--diagnostics=json` — so the
program's own stdout stays clean for piping:

```
$ kaappi --timings prog.scm 2>/dev/null   # program output only
$ kaappi --timings prog.scm 1>/dev/null   # timing report only
```

## What it reports

### Run path (`kaappi file.scm`)

A cache **MISS** compiled from source, so every stage ran:

```
timings: read 1.2ms | expand 0.8ms | lower 0.4ms | optimize 0.3ms | emit 0.5ms | execute 12.1ms
cache: MISS (wrote /Users/you/.kaappi/cache/1f8b6bdfcf8b707e.sbc)
```

A cache **HIT** skipped the whole read→compile pipeline, so only `execute`
ran — the compile stages are omitted rather than printed as `0.0ms` noise:

```
timings: execute 11.9ms
cache: HIT (/Users/you/.kaappi/cache/1f8b6bdfcf8b707e.sbc)
```

The cache line is never blank. When caching was not even attempted it says why:

```
cache: off (--no-ir-opt)     # or (sandbox), or (no home dir)
cache: MISS (not cached: imports)   # imported programs are never cached (#1516)
```

### Stages

| Stage      | What it measures |
|------------|------------------|
| `read`     | Tokenizing + parsing source into datums (`reader.zig`). |
| `expand`   | `syntax-rules` macro expansion (`expander.expandMacro`). |
| `lower`    | AST → IR lowering and tail-position analysis (`ir.lowerWithMacros` + `markTailPositions`). |
| `optimize` | The five IR optimization passes (`ir.zig`). |
| `emit`     | IR → register bytecode (`compiler_ir.compileFromNode`). |
| `execute`  | VM execution of the top-level forms (`vm.execute`). |
| `llvm-emit`| IR → LLVM IR text, native backend only (`llvm_emit.zig`). |
| `link`     | Invoking the external C compiler to link the native binary. |

The native `kaappi compile` path reports `read / lower / optimize / llvm-emit /
link` plus the output binary, with no `execute` or cache line. `--compile`
(bytecode) reports `read / expand / lower / optimize / emit` plus the `.sbc`
output.

### `--timings=json`

A single object with a stable shape (all applicable stage keys always present,
`0.000` when a stage didn't run), for regression tracking alongside the
benchmark workflows:

```json
{"mode":"run","stages_ms":{"read":1.200,"expand":0.800,"lower":0.400,"optimize":0.300,"emit":0.500,"execute":12.100},"cache":{"status":"miss","path":"/Users/you/.kaappi/cache/1f8b6bdfcf8b707e.sbc","written":true}}
```

`mode` is `run` | `compile` | `native`. For a run, `cache.status` is `hit` |
`miss` | `off`; `path` and `written` accompany a hit or miss, and a `reason`
accompanies `off` (or a not-written miss). For compile/native, an `output` field
names the artifact instead of a cache object.

## Design — a self-time profiler stack

The pipeline is **not** a flat sequence. Macro expansion is interleaved with
emission: a macro use lowers to a *passthrough* IR node that is expanded, and
then *re-compiled*, during `compileFromNode`. So `emit` legitimately contains
nested `expand`, `lower`, `optimize`, and further `emit`. A single accumulator
per stage would double-count those nested regions — `emit` would absorb the
expansion time it triggered, and the numbers would sum to more than the wall
clock.

`src/timings.zig` avoids that with a **self-time stack**: every timed region is
pushed, and elapsed wall time is always credited to the *innermost* active
stage. Entering a nested stage freezes its parent; leaving resumes it. The
buckets are therefore **disjoint** — they never overlap — regardless of nesting
depth or which driver (run / `--compile` / native / imports) is on top. A
macro-heavy compile makes this visible: `expand` can dwarf `emit` precisely
because `emit` excludes the expansion it drove.

Instrumentation lives at the shared chokepoints, so all callers are covered at
once:

- `ir.lowerAndOptimize` — `lower` and `optimize`.
- `expander.expandMacro` — `expand` (the sole expansion entry point).
- `compiler.compile` / `compileMultiple` — the outermost `emit` scope.
- `native_compiler` — `read`, `llvm-emit`, `link`.
- `main.zig` run/compile drivers — `read`, `execute`, and cache HIT/MISS.

## Cost when absent, and threading

Every `begin`/`end` is a single predicted branch (`if (!enabled) return`) when
the flag is off, so there is no measurable overhead on an ordinary run — none of
the instrumented functions sit in the bytecode dispatch loop.

`enabled` is `threadlocal`, mirroring `ir.optimize_enabled`. Only the main
thread — the one that parsed the CLI and drives the top-level pipeline — ever has
it set. SRFI-18 child threads that compile via `eval` neither race on the shared
buckets nor get counted, and since the whole program's pipeline runs on the main
thread, nothing is lost.

## Tests

- `src/timings.zig` unit tests drive the self-time stack on a deterministic
  clock (`test_clock`, gated on `builtin.is_test` so it compiles out of
  production) and check the text/JSON rendering.
- `tests/scheme/timings/timings-1515.sh` is the end-to-end shell test: it
  validates the JSON shape (parsing it with `python3` when available), the
  HIT/MISS transitions, the cache-off reasons, the compile-path shape, and that
  timings never leak onto stdout.
