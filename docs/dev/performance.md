# Investigating a slowdown

A runbook for the question "this is slower than it should be — now what?"
It covers **finding** the cause and **measuring** trustworthily. It
deliberately holds no numbers: current performance figures live in the
benchmark suite and its dashboard, past optimization results in
[lessons-learned.md](lessons-learned.md) §11, and point-in-time campaign
data in the KEP benchmark documents. Numbers copied into a guide rot.

Two kinds of slowdown share this page because the tools overlap but the
first moves differ:

- **The compiler is slow** — `kaappi` takes too long to *compile* a
  program. Start at step 1.
- **Compiled code is slow** — the program itself runs too long. Skip to
  [Benchmarking generated code](#benchmarking-generated-code).

## 1. Find the stage, then find the caller

`--timings` reports per-stage pipeline wall time and cache HIT/MISS
([timings.md](timings.md)):

```bash
kaappi --timings slow.scm
```

That names the **stage**. It cannot name the **caller**, and the caller is
usually where the fix is. Do not form a theory about the code inside a
stage from the stage number alone — go straight to a stack profiler:

```bash
# macOS
kaappi slow.scm & sample $! 8 -f /tmp/prof.txt

# Linux
perf record -g -- kaappi slow.scm && perf report
```

Neither needs a special build: the ordinary `zig build` output (ReleaseSafe)
profiles with full symbolized stacks. Reach for the profiler as soon as a
stage number is surprising — before forming a theory about the code inside
that stage.

**Worked example — [#1775](https://github.com/kaappi/kaappi/issues/1775).**
A macro-generating macro compiled in 41s. `--timings` said
`expand 2765.8ms`, which was true: the time really was inside
`expander.expandMacro`. Two sessions read that as "the expander is slow"
and hand-eliminated theories in `instantiateTemplate` and
`stripUsertextMarkers`. Nothing in `expander.zig` was wrong — the
expansions were being driven by `compiler.collectSetTargets`, a `set!`
pre-scan exploring branches the real compiler never takes. One `sample`
run put 99% of samples under `collectSetTargets`.

Note what would *not* have helped: adding a `prescan` stage to
`--timings`. Stages are disjoint and self-timed, so the nested
`expandMacro` time still lands under `expand`. More stage instrumentation
does not answer a caller question — only a profiler does.

## 2. Measure before you theorize

The expensive failure mode in every slowdown investigation on record is
plausible reasoning that measurement then refutes. #1775 lost two sessions
to two such theories (exponential re-visiting of shared subtrees; O(n²)
list accumulation) before either was tested; a third — identity
memoization of the walk — sounded compelling and delivered 8%.

Cheap ways to get a real number before committing to a hypothesis:

- A counter in the suspect function, printed once per top-level form.
  Crude, decisive, and thrown away afterwards.
- Disable the suspect path entirely and re-time. If the time doesn't move,
  the theory is dead in one build.
- Distribution over the real corpus, not one input: running the whole
  `tests/scheme/` tree with a counter is what turned "4096 feels safe" into
  a defensible limit in #1775 (p99.99 = 1649, and the pathological tier
  starting at 6299).

### When the profile bottoms out in `memset`

A `sample` whose hottest leaf is `_memset` filling `0xAA` is Zig's
safety-checked-`undefined` fill: ReleaseSafe initializes every plain
`var x: T = undefined;` local by memsetting it. For a large scratch buffer
declared per call this can *be* the workload — in #1802 the expander's
~1MB rule-matching buffers made three fills per macro expansion 96% of an
80-second library compile. The only shape that suppresses the fill is
`@setRuntimeSafety(false)` at the scope of the *declaration* (in practice:
function scope, with the body wrapped in a `@setRuntimeSafety(true)` block
so real checks stay on — see `expander.expandMacro`). Wrapping just the
initializer — `b: { @setRuntimeSafety(false); break :b undefined; }` —
does not work and is worse than nothing: it materializes a runtime
undefined value whose store into the local gets the fill anyway.
`objdump -d` on the suspect function, looking for `bl _memset` with a
`#0xaa` fill byte, settles in seconds whether a given declaration is
being filled.

## 3. A/B two binaries without fooling yourself

This is where measurement most often goes wrong, because two hazards
conspire.

### Clear the bytecode cache between rebuilds

The `.sbc` cache key folds in the git build id — but `-dirty` is a **flag,
not a hash of the working tree**. Every uncommitted state at the same
commit produces the identical id, so rebuilds of *different* uncommitted
changes share cache entries and one can execute bytecode the other
produced. Full explanation in [cache.md](cache.md).

Toggling between two versions with `git stash` or
`git checkout <sha> -- <path>` and rebuilding is exactly the shape that
triggers it, and the symptom is the same input file answering differently
across otherwise-identical rebuilds — indistinguishable from
nondeterminism in the code under test.

```bash
kaappi cache clear     # after every rebuild, when A/B-ing compiler changes
```

`--no-ir-opt` also bypasses the cache in both directions, which makes it a
convenient measurement flag — at the cost of disabling the IR optimization
passes, so it answers a different question than a default-configuration
run.

### Keep the two binaries as separate files

Rebuilding over `zig-out/bin/kaappi` leaves no way to check *which* binary
just ran, and a failed or partial build silently re-measures the previous
one. Copy each build somewhere private and verify by checksum before any
run whose result you intend to act on:

```bash
zig build && cp zig-out/bin/kaappi /tmp/kaappi-base      # baseline
# ... apply the change ...
zig build && cp zig-out/bin/kaappi /tmp/kaappi-fixed     # candidate
shasum /tmp/kaappi-base /tmp/kaappi-fixed                # must differ
```

Then interleave the runs rather than running all of A followed by all of
B, so thermal and load drift hits both arms equally:

```bash
for i in 1 2 3 4 5; do
  /usr/bin/time -p /tmp/kaappi-base  --no-ir-opt case.scm 2>&1 >/dev/null | awk '/real/{print "base ", $2}'
  /usr/bin/time -p /tmp/kaappi-fixed --no-ir-opt case.scm 2>&1 >/dev/null | awk '/real/{print "fixed", $2}'
done
```

A single pair of runs is not a result. In #1775 one such pair showed a 45%
regression on a case that five interleaved runs then showed as identical.

## 4. Check the shape, not just the magnitude

Growth rate identifies the bug class faster than any absolute number.
Generate the same input at several sizes and time each: a constant ratio
per step is exponential, a constant increment is linear. #1775 read as
"~2.2x per added rule" from six data points, which ruled out the O(n²)
theory before any code was read.

The same technique verifies a fix. After bounding the work, the series
went flat (7, 9, 11 and 13 rules all landing within noise of each other) —
evidence a single before/after pair cannot give.

## Benchmarking generated code

For the runtime cost of compiled Scheme rather than the compiler, the
benchmark suite is the tool — see
[testing.md § Benchmarks](testing.md#benchmarks) for the suite, the
harness, reading results, and adding a case:

```bash
bash benchmarks/run-benchmarks.sh
bash benchmarks/compare-benchmarks.sh baseline.json current.json
```

Subsystem micro-benchmarks live behind their own build steps:
`zig build bench` (call/cc vs call/ec), `bench-fibers`, `bench-reactor`,
`bench-channel`.

CI runs the suite on every push to main and posts a per-benchmark
comparison on PRs touching `src/`, `benchmarks/`, `lib/`, or build files.
Treat ±10% on shared runners as noise.

## Where the rest of the performance material lives

| Topic | Document |
|-------|----------|
| Benchmark suite, harness, CI integration, trend dashboard | [testing.md](testing.md) |
| `--timings` output, JSON schema, where the instrumentation sits | [timings.md](timings.md) |
| `.sbc` cache key, invalidation, `cache status` / `cache clear` | [cache.md](cache.md) |
| IR optimization passes | [ir.md](ir.md) |
| Native backend optimization | [llvm-backend.md](llvm-backend.md) |
| Optimizations that worked, that didn't, and that were revisited | [lessons-learned.md](lessons-learned.md) §11 |
| Self-tail-call design (Option A shipped, B reverted) | [decisions/self-tail-call-optimization.md](decisions/self-tail-call-optimization.md) |
| KEP acceptance-gate campaigns and their datasets | `kep-0001-phase7-benchmarks.md`, `kep-0002-phase7-envelope-benchmarks.md`, `kep-0003-acceptance-gate-worksheet.md` |
