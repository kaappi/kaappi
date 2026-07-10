# Fuzzing runbook

Operational guide for Kaappi's fuzz targets: how to run them, what the CI job
does, and how to turn a fuzz failure into a regression test and corpus entry.
The analysis behind this setup — why these targets, what the research
literature says, what the next tiers are — lives in
[fuzzing-feasibility.md](fuzzing-feasibility.md).

## The targets

All targets live in [`src/tests_fuzz.zig`](../../src/tests_fuzz.zig) and use
Zig 0.16's built-in coverage-guided fuzzer (`std.testing.fuzz` +
`std.testing.Smith`).

| Target | Input | Exercises |
|--------|-------|-----------|
| `fuzz reader` | raw bytes (256) | tokenizer + datum parser (`reader.zig`) |
| `fuzz bytecode loader` | raw bytes (512) | `.sbc` deserialization (`bytecode_file.zig`) |
| `fuzz compiler` | raw bytes (256) | read → compile one expression |
| `fuzz eval` | raw bytes (128) | full read → compile → VM execute via `vm.eval` |
| `fuzz tokens` | token sequence | read → compile → execute of near-miss token soup |
| `fuzz grammar` | generated program | compiler, VM, and GC on valid, well-bound R7RS programs |
| `fuzz differential (opt vs no-opt)` | generated program | correctness oracle: IR optimization passes vs unoptimized baseline |

The `fuzz tokens` target picks sequences from a Scheme token vocabulary
instead of raw bytes, so its inputs get past the lexer without being confined
to grammatically valid programs (Salls et al., "Token-Level Fuzzing", USENIX
Security 2021). It deliberately does **not** balance parentheses.

The `fuzz grammar` target maps the Smith decision stream through the grammar
generator in [`src/fuzz_gen.zig`](../../src/fuzz_gen.zig) (a Zest-style
parametric generator, per the Tier 2 plan in fuzzing-feasibility.md) to a
valid, well-bound, resource-bounded R7RS program. About 98% of generated
programs evaluate without error, so this is the target that actually reaches
`compiler_*.zig`, `vm_dispatch.zig`, and the GC write-barrier paths: it
weights generation toward closures, tail calls, named let/do loops,
`call/cc`, `dynamic-wind`, `guard`/`raise`, quasiquote, `syntax-rules`
definition + use, and vector/string/bytevector mutation. It never emits
filesystem, process, FFI, network, or thread forms, and bounds expression
depth, literal sizes, loop iteration counts, and program bytes by
construction. It needs no seed corpus: any decision stream decodes to a
valid program.

The `fuzz differential` target (Tier 3, #1394) is the first target that can
catch **silently wrong values**, not just crashes: it evaluates each
grammar-generated program twice — IR optimizations on and off (the switch
from #1393, `ir.optimize_enabled` / CLI `--no-ir-opt`) — and compares a
normalized observable: the printed final value plus the generator's globals
(`g0`–`g2`), and the error *class* (value / compile error / runtime error),
never error message text. Timeout, out-of-memory, and stack-overflow
outcomes make a pair incomparable (skipped) rather than a divergence, since
the two compilation paths legitimately do different amounts of work. Any
other divergence fails the target with `error.DifferentialMismatch` and is a
bug in an optimization pass (or in the baseline). To debug one: re-run the
printed program under `kaappi file.scm` vs `kaappi --no-ir-opt file.scm` and
minimise from there (`--no-ir-opt` skips the `.sbc` cache, so no stale-cache
footguns).

Ordinary Scheme read/compile/runtime errors are **expected** fuzz outcomes.
Only crashes, panics, memory leaks (via `std.testing.allocator`),
sanitizer findings, and differential mismatches fail a target. VM execution
is bounded by a 100 ms deadline per input.

## Running locally

```bash
zig build test                 # replays each target's seed corpus once (smoke)
zig build test --fuzz=1K       # bounded fuzz pass, terminates with a report
zig build test --fuzz=20K      # longer bounded pass (K/M/G suffixes)
zig build test --fuzz          # unbounded + web UI; Ctrl-C to stop
zig build test --fuzz=1K -Dgc-stress=true   # GC collects on every allocation
```

The limit applies **per fuzz test** (seven targets currently), and per-input
cost varies enormously by target: reader/compiler/loader inputs are
microseconds, but the eval, token, and grammar targets construct a full VM
per input (~20–50 ms) — and the differential target two of them — and
dominate the wall time. As a rule of thumb, `--fuzz=200` is
a ~2-minute pass and `--fuzz=20K` is half an hour or more on a fast machine.

The fuzzer's working corpus persists in `.zig-cache/f/` and accumulates
across runs; coverage stats accumulate in `.zig-cache/v/`. Delete
`.zig-cache` to start fresh. The run transcript is written to
`.zig-cache/tmp/libfuzzer.log`.

A `-Dgc-stress=true` build attempts a collection at every allocation (except
under `no_collect` or while the GC is disabled), which turns latent rooting
bugs into immediate, attributable failures instead of rare heisenbugs.
**Currently blocked:** ~440 of the 690 unit tests crash under gc-stress
([#1401](https://github.com/kaappi/kaappi/issues/1401)), so a gc-stress fuzz
run cannot get past the test phase until that is fixed.

## The CI job

[`.github/workflows/fuzz.yml`](../../.github/workflows/fuzz.yml) runs a
bounded fuzz pass daily at 02:47 UTC (scheduled away from the 05:17 UTC
ecosystem nightly), in two variants:

| Variant | Build | Limit (per fuzz test) |
|---------|-------|-----------------------|
| `default` | standard `ReleaseSafe` test build | 2K runs |
| `gc-stress` | `-Dgc-stress=true` | *disabled* — see below |

The `gc-stress` variant is disabled in the matrix until
[#1401](https://github.com/kaappi/kaappi/issues/1401) is fixed: ~440 of the
690 unit tests currently crash under `-Dgc-stress=true`, so the pre-fuzz
test phase can never pass. (Its first and only CI execution is what found
that.) Re-enable it once the suite is stress-clean.

Trigger it manually (optionally overriding the limit) with:

```bash
gh workflow run fuzz.yml                # matrix default limits
gh workflow run fuzz.yml -f limit=1K    # smaller/larger bounded pass
gh run watch
```

**Crash detection caveat:** Zig 0.16's bounded fuzz mode does not propagate
a fuzz-found crash into `zig build`'s exit code. Instead the crashing input
is saved (as a serialized Smith decision stream) to `.zig-cache/f/crash` and
a `test '...' crashed; input saved to ...` line is printed. The CI job — and
any local scripting — must check for that file; the workflow fails the run
when it exists and uploads it, the run log, and `libfuzzer.log` as the
`fuzz-artifacts-<variant>` artifact, retained for 90 days.

The job persists `.zig-cache/f` (corpus) and `.zig-cache/v` (coverage)
across runs via `actions/cache` with a rolling key, so nightly coverage
accumulates instead of restarting from the seeds; the cache is only saved
on success, so crash state never leaks into the next run.

The job needs no services, network access beyond checkout/toolchain, or
special permissions: the eval harness registers only the sandboxed
primitive set (no filesystem, process, FFI, or thread procedures), and
everything runs in-process in the test binary.

## The VM-vs-native differential batch (#1395)

[`tests/fuzz/native-diff.sh`](../../tests/fuzz/native-diff.sh) diffs Kaappi's
two evaluation paths against each other: each generated program runs through
the bytecode VM (`kaappi prog.scm`) and through the LLVM native backend
(`kaappi compile prog.scm -o prog.bin && ./prog.bin`), comparing stdout and
exit class. This is the second internal correctness oracle (after
opt-vs-no-opt) and the setup Midtgaard et al. (ICFP 2017) used to find
bytecode-vs-native disagreements in OCaml.

```bash
bash tests/fuzz/native-diff.sh            # 100 programs, seeds 0..99
bash tests/fuzz/native-diff.sh 300 1200   # 300 programs starting at seed 1200
```

The script builds anything missing (`zig build`, `zig build lib`,
`zig build fuzz-gen`), probes that `kaappi compile` can actually link here
(it finds `zig cc` on PATH; the probe is needed because `kaappi compile`
reports toolchain failures on stderr but exits 0), then runs the batch. Each
input is a generate + interpret + compile-and-link + run cycle (~1 s,
dominated by linking) — orders of magnitude slower than in-process fuzzing,
which is why this is a scheduled batch and not a `std.testing.fuzz` target.
The `native-diff` job in `fuzz.yml` runs 300 programs nightly with a seed
base that rotates per run (printed in the log; any base is replayable
locally or via `workflow_dispatch` inputs `native-diff-count` /
`native-diff-base`), and uploads divergences as the
`native-diff-divergences` artifact.

Programs come from the **native-subset generator**
([`src/fuzz_gen_native.zig`](../../src/fuzz_gen_native.zig), built as
`kaappi-fuzz-gen --native` via `zig build fuzz-gen`). The native backend
falls back to `kaappi_eval` (the interpreter) for forms it cannot compile,
so an unrestricted program would degrade the diff to VM-vs-VM; the subset
generator emits only natively-compiled forms and encodes the backend's
structural rules (function bodies reference only their own parameters and
primitives, no lambdas inside `let`, computed `set!` values only inside
lexical scopes, every top-level form void-valued with explicit `(write ...)`
output — the module doc comment has the full list and the reasons). Two
unit gates keep this honest: `tests_native.zig` asserts fixed-seed programs
emit no unexpected `kaappi_eval` calls in the LLVM IR and that every defined
function gets a native definition, and `tests_fuzz.zig` asserts the programs
evaluate cleanly.

Comparison rules:

- **Both exit 0** — stdout must match byte-for-byte. The programs print all
  observables explicitly (`write` of final expressions and of every
  non-procedure global), because the VM echoes non-void top-level values but
  native binaries do not, and procedure values print differently by design
  (`#<procedure name>` vs `#<procedure>`).
- **Both exit 1–127** — ordinary-error match, without comparing stdout: the
  VM reports a top-level error and continues with the next form, the native
  binary exits at the first error, so post-error output legitimately
  differs.
- **Any exit ≥ 128** — divergence: 128+N is death by signal N (segfault,
  abort, …), which is never an ordinary Scheme error, so it is flagged even
  when the other side also errored.
- **Exit classes differ, stdout differs, or `kaappi compile` fails or times
  out** — divergence: the program plus both sides' stdout/stderr land in
  the results dir and the script exits non-zero.
- **Either side's execution times out** (needs GNU `timeout`/`gtimeout` on
  PATH) — the pair is skipped as incomparable. Compilation gets its own,
  longer timeout so a hung linker on one seed is classified as a divergence
  instead of stalling the batch.

One caveat when triaging a divergence: argument evaluation order is
unspecified in R7RS, and generated programs do mutate globals inside
subexpressions. Both backends currently evaluate left-to-right, so a
divergence is always an implementation inconsistency worth filing — but the
fix may be "make the order consistent" rather than "wrong code".

## Turning a failure into a regression test

Every fuzz finding follows the same three steps — no exceptions:

1. **Minimise.** The crash artifact (`.zig-cache/f/crash`, locally or from
   CI) is the encoded Smith decision stream. For the four byte-input targets
   the encoding is `<4-byte LE length><input bytes>` — strip the first four
   bytes to get the failing source text. The `fuzz tokens` target's stream
   is different: a sequence of little-endian `u64` decisions (token count,
   then one table index per token) — decode indices against `token_table`
   to reconstruct the source. Either way, the fastest reproduction is
   adding the artifact's bytes verbatim as a `.corpus` entry on the target
   that crashed (plain `zig build test` replays every corpus entry). Then
   shrink the input by hand until removing anything makes the failure
   disappear. Scheme inputs minimise well structurally: drop list elements,
   replace subexpressions with literals, shorten identifiers.

   The `fuzz grammar` and `fuzz differential` targets' streams are sequences
   of `u64` grammar decisions with no simple hand-decoding; reproduce by
   replaying the artifact verbatim as a `.corpus` entry on the target that
   failed, and recover the failing *program text* by temporarily printing
   the generated source (to stderr, never fd 1) in the target body during
   the replay. Once you have the program text, minimise it as ordinary
   Scheme and add the minimised source as a `seed()` corpus entry on the
   **eval** target — source seeds are stable, decision streams are not (any
   change to the generator's decision sequence re-interprets them). A
   differential mismatch reproduces outside the harness as
   `kaappi prog.scm` vs `kaappi --no-ir-opt prog.scm` disagreeing.

   A `native-diff.sh` divergence is the easiest of all: the artifact already
   IS the program text (`seed-N.scm` plus both sides' output). Reproduce
   with `kaappi seed-N.scm` vs `kaappi compile seed-N.scm -o b && ./b`, and
   minimise as ordinary Scheme — but keep the shrunken program inside the
   native subset (check with the eval-count gate in `tests_native.zig`, or
   just verify the divergence survives each shrink step).

2. **Add a readable regression test** that fails without the fix and passes
   with it, per the repo's bug-fix rule:
   - crash in the VM/compiler/GC internals → Zig unit test in the matching
     `src/tests_*.zig`;
   - behavior visible from Scheme → `tests/scheme/smoke/` or a dedicated
     file under `tests/scheme/`.

3. **Keep the input as a corpus seed.** Add the minimised source to the
   matching target's corpus in `src/tests_fuzz.zig` via the `seed()` helper.
   Past bug-triggering inputs are the highest-value corpus material a fuzzer
   has. **Never add raw bytes directly to `.corpus`** — entries are
   serialized Smith decision streams (`<4-byte LE length><bytes>` for these
   single-slice targets); `seed()` does the encoding and rejects inputs that
   exceed the target's buffer.

## The `.sbc` loader fixture

The bytecode-loader corpus starts from a small valid compiled file,
`src/testdata/fuzz-seed.sbc` (plus comptime-derived truncated and bit-flipped
variants). Its header's compiler-version hash is patched at comptime, so
interpreter version bumps do **not** invalidate it. A bytecode format
`VERSION` bump does — the `fuzz seed .sbc fixture stays loadable` unit test
fails, and the fixture must be regenerated:

```bash
zig build
zig-out/bin/kaappi --compile src/testdata/fuzz-seed.scm -o src/testdata/fuzz-seed.sbc
```
