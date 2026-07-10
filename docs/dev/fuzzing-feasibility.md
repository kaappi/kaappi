# Fuzzing Kaappi — and why Fuzzilli isn't the tool

**Feasibility note, 2026-07-09; revised 2026-07-10 with a survey of the
research literature and the AFL++ question.** Records the analysis behind a
recurring question: can [Fuzzilli](https://github.com/googleprojectzero/fuzzilli),
Google Project Zero's coverage-guided fuzzer, be pointed at Kaappi? The short
answer is no — but the reasoning maps directly onto what Kaappi *should* do for
fuzzing, so it is worth keeping. Concrete work items belong in the issue
tracker; this note is the analysis, not a task list. The operational guide —
how to run the targets, the scheduled CI job, and the failure workflow — is
[fuzzing.md](fuzzing.md).

## TL;DR

- **Fuzzilli generates JavaScript, and only JavaScript.** Kaappi has no
  JavaScript front-end, so there is no valid target. Fuzzilli cannot fuzz a
  Scheme interpreter the way it fuzzes V8 or JavaScriptCore.
- **A Fuzzilli fork for Scheme is possible but low-ROI** — it means replacing the
  parts of Fuzzilli that make it good.
- **Kaappi already has the pieces Fuzzilli's design is actually built around:** a
  coverage-guided fuzzer ([`src/tests_fuzz.zig`](../../src/tests_fuzz.zig)) and a
  fast in-process eval harness ([`vm.eval`](../../src/vm_eval.zig)). The
  improvement opportunity is to apply Fuzzilli's *ideas* to that stack, not to
  adopt the tool.
- **The research literature backs the tiered plan below.** Byte-level mutation
  stalls at the parser; structure-aware generation is what reaches the
  compiler, VM, and GC; and differential oracles — including Kaappi-internal
  ones (bytecode VM vs LLVM native backend) — are what find miscompilations
  rather than crashes. See "What the research literature says".
- **The same verdict applies to AFL++**, for different reasons: no language
  mismatch, but almost everything it would bring already exists here or is
  planned, and its compile-time instrumentation cannot target Zig code. See
  "Why not AFL++ either".

## Why Fuzzilli can't fuzz Kaappi directly

Fuzzilli's own README describes it as a fuzzer for *JavaScript engines*. Its
pipeline is JS-centric end to end:

- It mutates **FuzzIL**, a custom intermediate language, then **lifts** FuzzIL to
  **JavaScript source** and runs that source in a JS engine.
- FuzzIL's operations are JavaScript semantics: property load/store, prototype
  manipulation, `typeof`, `in`, `async`/`await`, and JS builtins. The mutators
  and code generators are tuned to produce *JS-shaped* IL.
- The README states plainly that it does **not** support non-JavaScript
  languages out of the box.

None of the JS operation set maps cleanly onto Scheme's s-expression, lambda, and
tail-call model. There is no adapter that turns a Scheme interpreter into a thing
Fuzzilli can drive.

## What a real Fuzzilli fork would require

Scoped honestly, so it's a deliberate choice rather than a surprise. To make
Fuzzilli emit and drive Scheme you would have to:

1. Write a **`SchemeLifter`** (FuzzIL → Scheme). Most FuzzIL ops are JS-only, so
   you either drop them (losing generator intelligence) or invent unnatural
   Scheme encodings for JS concepts.
2. Write a Scheme **`Environment`** (the set of known builtins/names Fuzzilli
   generates against) and a Kaappi **`Profile`** under
   `Sources/FuzzilliCli/Profiles/`.
3. Add **SanitizerCoverage** to Kaappi (`-fsanitize-coverage=trace-pc-guard`,
   the interface behind Fuzzilli's `libcoverage`).
4. Add a **REPRL** loop (Read-Eval-Print-Reset-Loop over pipes + shared memory)
   to the Kaappi binary so Fuzzilli can push a program, run it, read
   coverage/status, and reset without a process spawn.

The result is a large, research-grade fork that fights Fuzzilli's design and
throws away the JS-tuned generation that is the reason to use it. Not
recommended.

## What Kaappi already has (the Fuzzilli "bones")

The two things Fuzzilli's architecture is really about — coverage feedback and a
fast persistent harness — already exist here:

- **A coverage-guided fuzzer.** [`src/tests_fuzz.zig`](../../src/tests_fuzz.zig)
  defines four `std.testing.fuzz` targets, using Zig 0.16's built-in fuzzer
  with `std.testing.Smith`:

  | Target | Exercises |
  |--------|-----------|
  | `fuzz reader` | tokenizer + datum parser (`reader.zig`) |
  | `fuzz bytecode loader` | `.sbc` deserialization (`bytecode_file.zig`) |
  | `fuzz compiler` | read → compile one expression |
  | `fuzz eval` | full read → compile → VM execute via `vm.eval` |

  These are reachable from the `test` build: `main.zig`'s test block pulls in
  `vm_mod`, [`vm.zig`](../../src/vm.zig) imports `vm_tests.zig`, which imports
  `tests_fuzz.zig`. Run them with:

  ```
  zig build test --fuzz
  ```

  (`--fuzz[=limit]` is a `zig build` option; `-ffuzz` is the underlying compile
  flag. Without `--fuzz`, plain `zig build test` runs each target once with a
  fixed seed.)

- **A fast in-process harness.** [`vm.eval(source)`](../../src/vm_eval.zig)
  takes a source string and returns `VMError!Value`, guarded by
  `timeout_deadline_ns`. This is effectively an in-process REPRL already — no
  per-input process spawn — which is exactly the property Fuzzilli's REPRL exists
  to provide.

- **Coverage tooling.** kcov integration (`zig build coverage` /
  `coverage-scheme`) in [`build.zig`](../../build.zig) reports which `src/` lines
  a run exercises.

### An important Zig corpus detail

Zig's `std.testing.FuzzInputOptions` has a `corpus` field, but that field is a
slice of **serialized `Smith` decisions**, not a directory of application
inputs. The current four targets each make exactly one
`smith.sliceWithHash(&buf, 0)` call. Consequently, a seed for a Scheme source
`s` must be encoded as:

```
<4-byte little-endian length of s><bytes of s>
```

Passing a `.scm` file directly would make its first four source bytes look like
a length, and will normally produce an empty or malformed input. Likewise,
Zig's public fuzz API exposes a corpus but no libFuzzer-style `-dict` option.
The standard library's [`FuzzInputOptions`](https://github.com/ziglang/zig/blob/0.16.0/lib/std/testing.zig#L1222-L1232)
is the relevant API contract.

This does **not** make seeding impractical. Add a small, explicit seed helper
that encodes a curated set of source snippets at compile time, and pass those
encoded values via `.corpus`. Keep the corpus small and coverage-focused rather
than embedding the entire Scheme suite: many suite files depend on a test
harness, imports, or filesystem layout and are poor standalone `vm.eval`
inputs. A test-only corpus directory can still be useful as source material,
but needs a conversion/minimisation step before it becomes a Zig fuzz corpus.

## Why not AFL++ either

The second most recurring tool question, recorded here for the same reason
as the Fuzzilli one. [AFL++](https://github.com/AFLplusplus/AFLplusplus) is
the de-facto standard greybox fuzzer, and unlike Fuzzilli it has no target
language: it fuzzes anything it can instrument or emulate. The problem is on
the other side of the ledger — almost everything it would bring is already
here, deliberately, mapped through the same research this note surveys:

| AFL++ feature | Kaappi equivalent |
|---------------|-------------------|
| Coverage-guided greybox loop | Zig 0.16's built-in fuzzer, instrumenting the whole interpreter |
| Persistent mode (no fork per input) | The in-process `vm.eval` harness — the property persistent mode exists to approximate |
| Dictionaries / autodict | The token-vocabulary target embeds the dictionary in the generator (Zig's fuzz API has no `-x dict`) |
| Custom / grammar mutators | Tier 2's `Smith` parametric generator — byte mutation of the decision string becomes structural mutation for free (Zest), rather than a C plugin bolted onto a byte mutator |
| Sanitizers | ReleaseSafe bounds/overflow checks; Debug builds poison freed GC memory; `-Dgc-stress=true` as the GC use-after-free amplifier |
| afl-cmin / afl-tmin | Manual minimisation per the [fuzzing.md](fuzzing.md) runbook — not a bottleneck at current corpus sizes |

The integration cost is what kills it: `afl-cc` is clang/gcc-based and cannot
instrument Zig code, so the realistic modes are QEMU or FRIDA (10–100×
slower, surrendering the in-process throughput this note identifies as
Kaappi's structural advantage) or adding SanitizerCoverage to the Zig build —
the same engineering scoped in "What a real Fuzzilli fork would require",
deferred for the same reason. Adoption would also split the corpus into two
incompatible formats (Smith decision streams vs raw bytes).

One genuinely AFL-shaped problem exists here: the **bytecode loader**. A raw
binary format with magic bytes, length fields, and hashes is exactly where
AFL++'s CMPLOG/RedQueen (input-to-state correspondence) beats anything in the
Zig stack. An occasional offline AFL++ campaign in QEMU mode against
`kaappi <file.sbc>` needs no harness code and would complement — not
replace — the loader target. That idea sits with the other deferred
complements (Fuzzilli fork, Fuzz4All): revisit if Tiers 2–3 plateau.
Weinholt's AFL++-on-Loko exercise (see "Practice" in the research section
below) is the working precedent if that day comes.

## Gaps — where the real improvement opportunities are

Measured against Fuzzilli's philosophy, the current setup leaves value on the
table:

- **Not run in CI.** No `--fuzz` invocation in `build.zig` or the workflows, so
  the targets only ever run once, with a fixed seed, under normal `test`.
  *(Closed 2026-07-10 by the scheduled fuzz workflow, #1390.)*
- **Byte-oriented input.** `Smith` mutates a raw byte buffer, so most inputs are
  rejected by the reader; the fuzzer mostly stresses the **parser** and rarely
  produces semantically deep, valid Scheme that reaches the compiler, VM, or GC.
  *(Partially addressed by the token-vocabulary target, #1391; Tier 2 is the
  real fix.)*
- **No seed corpus.** Every target currently passes `.{}` to
  `std.testing.fuzz`. The Scheme suite is useful source material, but its files
  must be reduced to standalone snippets and encoded as `Smith` inputs before
  they can be used as this fuzzer's corpus.
  *(Closed 2026-07-10 by the encoded seed corpora, #1389.)*
- **No direct token dictionary.** A libFuzzer token dictionary is not an
  option exposed by Zig's current fuzz API. Keywords and lexical tokens
  (`define`, `lambda`, `let`, `call/cc`, `#\`, `#(`, `quasiquote`, …) should
  instead appear in curated encoded seeds, or preferably be selected by a
  `Smith`-driven grammar generator.
  *(Closed 2026-07-10 by the token-vocabulary target, #1391.)*
- **No structure-aware generation** and **no differential testing** — the two
  techniques that find the deepest bugs. The next section maps the research
  literature onto both.
  *(Structure-aware generation closed 2026-07-10 by the grammar generator,
  #1392. Differential testing partially closed the same day by the
  optimized-vs-unoptimized oracle — the `--no-ir-opt` switch, #1393, plus
  the `fuzz differential` target, #1394 — and by the VM-vs-native-backend
  batch harness, #1395: a native-subset generator mode
  (`src/fuzz_gen_native.zig`) feeding `tests/fuzz/native-diff.sh`, run
  nightly by the fuzz workflow. The external-reference oracle, #1396,
  remains open.)*

## What the research literature says

The gaps above are not just Fuzzilli's philosophy — they restate the central
findings of ~15 years of research on fuzzing compilers and interpreters.
[A Survey of Compiler Testing](https://dl.acm.org/doi/10.1145/3363562)
(Chen et al., ACM Computing Surveys 2020) covers the field; the entries below
are the ones that map directly onto Kaappi decisions.

### Byte-level mutation stalls at the parser

- **[Token-Level Fuzzing](https://www.usenix.org/conference/usenixsecurity21/presentation/salls)**
  (Salls et al., USENIX Security 2021). Starts from the observation that
  byte-level AFL mutations on interpreters overwhelmingly produce parse
  errors; mutating *token* sequences instead found 29 previously unknown bugs
  in four JavaScript engines, several unreachable by either byte-level or
  grammar-based fuzzers. This is the cheapest published upgrade over raw
  bytes: the mutation unit becomes `define`, `lambda`, `#(`, a number — the
  dictionary entries Zig's fuzz API cannot express today (see Gaps).
- **[GRIMOIRE](https://www.usenix.org/conference/usenixsecurity19/presentation/blazytko)**
  (Blazytko et al., USENIX Security 2019). Synthesizes grammar-like input
  structure automatically during fuzzing, for targets whose grammar is
  unknown. Kaappi's grammar is small and known, so writing a generator
  directly (Tier 2) dominates this approach — cited here as the boundary
  case.

### Grammar-based generation is the workhorse

- **[LangFuzz](https://www.usenix.org/conference/usenixsecurity12/technical-sessions/presentation/holler)**
  (Holler, Herzig, Zeller, USENIX Security 2012). Grammar-driven generation
  that recombines code *fragments* harvested from previously bug-triggering
  programs; 105 Mozilla JavaScript vulnerabilities in three months. Its
  enduring lesson: regression tests and past crashers are the highest-value
  fragment/corpus material — the reason Tier 1 folds every minimised failure
  back into the corpus.
- **[NAUTILUS](https://github.com/nautilus-fuzz/nautilus)** (Aschermann et
  al., NDSS 2019). The first practical combination of grammar-based
  generation with coverage feedback, needing no seed corpus; found bugs in
  mruby, PHP, Lua, and ChakraCore. This is the closest published architecture
  to Tier 2: a grammar generator inside a coverage-guided loop.
- **[Gramatron](https://dl.acm.org/doi/10.1145/3460319.3464814)** (Srivastava
  & Payer, ISSTA 2021). Shows plain grammar sampling is biased toward
  shallow inputs and parse-tree-local mutations are too timid; converting the
  grammar to an automaton and making large-scale mutations reached up to
  24% more coverage. Relevant when tuning how a Scheme generator mutates —
  prefer aggressive subtree splices over single-leaf tweaks.
- **[PolyGlot](https://ieeexplore.ieee.org/document/9519403/)** (Chen et al.,
  IEEE S&P 2021). Language-agnostic fuzzing of 21 language processors across
  9 languages via a uniform IR plus *semantic validation* (fixing up
  undefined variables and type mismatches); 173 bugs. Its lesson for Tier 2:
  syntactic validity is not enough — the generator should track in-scope
  identifiers so generated programs are well-bound, or most inputs die at
  "unbound variable" instead of exercising the VM.

A structural advantage worth stating: Scheme's grammar is s-expressions. The
part these papers spend most of their machinery on — getting structurally
valid inputs past a complex parser — is nearly free for Kaappi; the
engineering can go into semantic validity and interesting form selection.

### Zig's `Smith` is the Zest architecture

**[Zest](https://dl.acm.org/doi/10.1145/3293882.3330576)** (Padhye et al.,
ISSTA 2019) formalized *parametric generators*: the fuzzer mutates an untyped
string of decisions, a generator maps those decisions to structurally valid
inputs, and coverage feedback on the decision string turns byte mutations
into structural mutations for free. Bugs found in OpenJDK, Maven, and Google
Closure. This is exactly the `std.testing.Smith` model — a Tier 2 grammar
generator making `Smith` choices *is* a Zest-style parametric generator, with
Zig's built-in instrumentation closing the coverage loop. In other words,
Tier 2 is not a homegrown design; it is a published, validated architecture
that Zig's fuzz API happens to natively support.

### Differential and metamorphic oracles find correctness bugs

Crash-only fuzzing misses wrong-value bugs entirely. The literature's answer
is comparing two things that must agree:

- **[Csmith](https://dl.acm.org/doi/10.1145/1993316.1993532)** (Yang, Chen,
  Eide, Regehr, PLDI 2011). Random UB-free C programs run through multiple
  compilers, diffing outputs; 325+ GCC/LLVM bugs. Most of Csmith's complexity
  goes into generating only the *fully specified* subset of C — the direct
  analog of Tier 3's "portable subset" constraint (evaluation order, error
  objects, exactness edge cases are Scheme's unspecified zones).
- **[EMI](https://dl.acm.org/doi/10.1145/2594291.2594334)** (Le, Afshari, Su,
  PLDI 2014). Needs **no second implementation**: profile a program on an
  input, delete code the run never executed, and the result must not change;
  147 confirmed GCC/LLVM bugs, mostly miscompilations. A metamorphic
  self-oracle Kaappi could apply without installing any reference Scheme —
  mutate provably dead branches and diff Kaappi against itself.
- **[YARPGen](https://dl.acm.org/doi/10.1145/3428264)** (Livinskii, Babokin,
  Regehr, OOPSLA 2020). Adds *generation policies* that bias random programs
  toward shapes that trigger specific optimizations; 220+ bugs. Relevant as
  the IR optimizer grows: bias generation toward constant folding, dead
  branch, and boolean-simplification patterns to stress those passes.
- **[classfuzz](https://dl.acm.org/doi/10.1145/2908080.2908095)** (Chen et
  al., PLDI 2016) and its successor classming (ICSE 2019). Differential
  testing of JVMs by mutating *class files*, not source: coverage-guided
  mutant selection on a reference JVM, then diffing each mutant's behaviour
  across several independent JVM implementations. Kaappi has no second VM
  to diff against, so what transfers is the input level, not the oracle:
  semantics-preserving `.sbc` mutations, checked against unmutated
  source-path execution, could take the loader target beyond parse
  robustness.

### Functional-language precedents (closest to Scheme)

- **[Testing an optimising compiler by generating random lambda terms](https://dl.acm.org/doi/10.1145/1982595.1982615)**
  (Pałka, Claessen, Russo, Hughes, AST 2011). Generates random *well-typed*
  terms and compares GHC with and without optimization — the "one
  implementation, two configurations" oracle, which found optimizer bugs
  within ~20k tests.
- **[Effect-Driven QuickChecking of Compilers](https://dl.acm.org/doi/10.1145/3110259)**
  (Midtgaard et al., ICFP 2017). Generates OCaml programs *provably
  independent of evaluation order* via a type-and-effect system, then diffs
  the bytecode VM against the native-code backend; disagreements found in 18
  of 20 runs against a release compiler. This is precisely Kaappi's shape —
  a bytecode VM and an LLVM native backend in one project — and its
  effect-discipline is the published answer to R7RS's unspecified evaluation
  order: generate only programs whose observable behaviour cannot depend on
  the unspecified parts.
- **Lineage.** Both descend from QuickCheck (Claessen & Hughes, ICFP 2000);
  property-based random testing is native to the functional-language
  community, and a future `kaappi-test` could grow property combinators.
- **Practice.** [Fuzzing Scheme with AFL++](https://weinholt.se/articles/fuzzing-scheme-with-aflplusplus/)
  (Weinholt) — AFL++ driving Loko Scheme — is the main documented
  Scheme-fuzzing exercise. Notable mostly for how *little* prior art exists:
  Scheme implementations are dramatically under-fuzzed compared to JS
  engines, which cuts both ways — less tooling to borrow, and likely more
  low-hanging bugs.

### The Fuzzilli line (custom-IL engine fuzzing)

- **[FUZZILLI](https://www.ndss-symposium.org/ndss-paper/fuzzilli-fuzzing-for-javascript-jit-compiler-vulnerabilities/)**
  (Groß, Koch, Bernhard, Holz, Johns, NDSS 2023). The paper behind the tool
  this note is about: mutating a typed IL and lifting to source found 17
  confirmed JIT vulnerabilities in six months. Validates the
  REPRL + coverage + IL design that Tier 4 would replicate — and quantifies
  how much engine-specific engineering that path costs.
- **[DIE](https://ieeexplore.ieee.org/document/9152648/)** (Park et al., IEEE
  S&P 2020). Mutates while *preserving* the structural and type "aspects"
  that made past inputs bug-triggering; 48 new bugs. Reinforces the
  keep-your-crashers-as-corpus discipline.
- **[FuzzJIT](https://www.usenix.org/conference/usenixsecurity23/presentation/wang-junjie)**
  (Wang et al., USENIX Security 2023). Built on Fuzzilli; wraps every sample
  so the JIT-compiled and interpreted results of the same function are
  compared in-process, turning correctness into a cheap always-on oracle.
  The Kaappi translation is direct: evaluate each generated program through
  `vm.eval` *and* the LLVM native backend and diff — Tier 3 without any
  external oracle.
- **[Montage](https://www.usenix.org/conference/usenixsecurity20/presentation/lee-suyoung)**
  (Lee et al., USENIX Security 2020). Neural language model over AST
  fragments from regression tests; 37 bugs. The pre-LLM ancestor of the next
  item.

### LLM-based generation

**[Fuzz4All](https://dl.acm.org/doi/10.1145/3597503.3639121)** (Xia et al.,
ICSE 2024) uses an LLM as the generation and mutation engine, with an
autoprompting loop, and beat language-specific fuzzers' coverage across nine
processors of six languages (C, C++, Go, SMT2, Java, Python), finding
previously unknown bugs in GCC, Clang, and Z3 among others. For Kaappi this
is attractive because it requires **no grammar and no generator code**:
prompt with R7RS snippets and Kaappi documentation, run outputs through the
`kaappi` binary offline. Expect throughput far below the in-process
coverage-guided stack — each input costs an LLM inference round-trip rather
than an in-process eval — so it complements rather than replaces Tier 2:
think scheduled batch job, not fuzzing loop.

## Applying Fuzzilli's ideas to Scheme

A tiered direction, so work can stop at any point. File concrete steps as issues
(per the [dev-docs policy](README.md)); this is the shape, not the backlog.

- **Tier 1 — cheap, high value.** Wire the existing targets into CI as a
  scheduled, *bounded* `zig build test --fuzz=<iteration-limit>` job. Add a
  small set of encoded `Smith` seeds for reader, compiler, and eval forms; add
  valid and intentionally malformed `.sbc` seeds for the loader. Preserve each
  minimised failure as both a regression test and a corpus entry — LangFuzz
  and DIE both show past bug-triggering inputs are the highest-value raw
  material a fuzzer has. This is pure leverage on what already exists.
- **Tier 2 — structure-aware generation.** A grammar-based generator of valid
  R7RS forms driven directly by `Smith` choices. This is the Scheme analog of
  Fuzzilli's generative core: it gets past the reader and actually exercises the
  compiler, VM, and GC. Architecturally it is NAUTILUS (grammar generation in
  a coverage loop) realised as a Zest-style parametric generator — a design
  Zig's fuzz API natively supports. Per PolyGlot, track in-scope identifiers
  so programs are well-bound, not just grammatical; per Gramatron, prefer
  aggressive subtree mutations over leaf tweaks. Bound expression depth,
  literal sizes, allocation, and evaluation time; keep an invalid-input
  target for parser robustness.
- **Tier 3 — differential testing (highest bug value).** Two variants, in
  order of setup cost:
  - *Kaappi vs itself — no external oracle needed.* Diff the bytecode VM
    against the LLVM native backend on the same generated program — the exact
    setup Midtgaard et al. used to shake disagreements out of OCaml's two
    backends, and FuzzJIT's in-process oracle trick. With an
    opt-passes-off switch it also covers Pałka et al.'s optimized-vs-
    unoptimized oracle, and EMI-style dead-code pruning gives a third
    self-oracle. Given that Kaappi's native backend falls back to
    `kaappi_eval` for un-compiled forms, restrict generation to natively
    compiled forms (arithmetic, `if`/`and`/`or`, `let`/`let*`, lambda, tail
    calls) or the diff degenerates into VM-vs-VM.
  - *Kaappi vs a reference Scheme.* Run generated programs through Kaappi
    *and* a real external Scheme and diff the results. Pin **one** oracle at
    a fixed version — Chibi Scheme is the natural first pick for R7RS-small
    alignment (Gauche, Guile, Chez, and Racket are alternatives, but each
    needs its own setup; Guile, for instance, must be put into R7RS mode
    explicitly) — and fix the exact invocation, timeout handling, and
    output normalization in the harness, or dialect defaults will produce
    false diffs. Compare a normalized observable result (value, stdout,
    and exit class), and generate only a portable subset: R7RS leaves
    evaluation order, error objects, and several edge cases unspecified.
    Csmith's core lesson is that this "fully specified subset only"
    discipline is where most of the engineering effort goes; Midtgaard et
    al.'s effect-driven generation is the published way to sidestep
    evaluation-order nondeterminism. Note: the repo's `(chibi test)` is an
    API shim implemented in Kaappi, **not** real Chibi — a genuine external
    interpreter must be installed as the oracle.

  Both variants find **correctness** bugs (silently wrong values), which
  crash-only fuzzing never surfaces and which EMI's authors found to be the
  majority and the most pernicious class.
- **Tier 4 — Fuzzilli fork (deferred).** The path in "What a real Fuzzilli fork
  would require" remains available as a research option; documented here so it
  can be chosen consciously rather than drifted into. The
  [FUZZILLI paper](https://www.ndss-symposium.org/ndss-paper/fuzzilli-fuzzing-for-javascript-jit-compiler-vulnerabilities/)
  quantifies both the payoff and the engineering weight of that path.

## Operating guidance

- Run fuzzing in an isolated job and do not generate filesystem, process, FFI,
  or network forms. The in-process eval harness is fast, but those facilities
  would make a fuzz run nondeterministic and could alter its runner.
- Keep the 100 ms VM execution deadline, and add comparable resource bounds to
  a future grammar generator. It currently guards bytecode execution; reader
  and compiler work still need bounded input depth and size.
- Treat a crash, panic, leak report, or sanitizer finding as a failure. Ordinary
  Scheme read/compile/runtime errors are expected fuzz outcomes and should not
  fail the target.
- Periodically run the fuzz targets on a `-Dgc-stress=true` build, which
  attempts a collection at every allocation (except where collection is
  temporarily suppressed via `no_collect` or the GC is disabled). Fuzzing
  practice consistently pairs input generation with aggressive runtime
  checking; a GC-stress build turns latent rooting bugs into immediate,
  attributable failures instead of rare heisenbugs.
- Minimise every failure, add a readable regression test, then retain the
  corresponding encoded fuzzer input. A corpus is both a search aid and a
  permanent regression set, as described in the
  [libFuzzer corpus guidance](https://llvm.org/docs/LibFuzzer.html#corpus).
