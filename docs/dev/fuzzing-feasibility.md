# Fuzzing Kaappi — and why Fuzzilli isn't the tool

**Feasibility note, 2026-07-09.** Records the analysis behind a recurring
question: can [Fuzzilli](https://github.com/googleprojectzero/fuzzilli),
Google Project Zero's coverage-guided fuzzer, be pointed at Kaappi? The short
answer is no — but the reasoning maps directly onto what Kaappi *should* do for
fuzzing, so it is worth keeping. Concrete work items belong in the issue
tracker; this note is the analysis, not a task list.

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

## Gaps — where the real improvement opportunities are

Measured against Fuzzilli's philosophy, the current setup leaves value on the
table:

- **Not run in CI.** No `--fuzz` invocation in `build.zig` or the workflows, so
  the targets only ever run once, with a fixed seed, under normal `test`.
- **Byte-oriented input.** `Smith` mutates a raw byte buffer, so most inputs are
  rejected by the reader; the fuzzer mostly stresses the **parser** and rarely
  produces semantically deep, valid Scheme that reaches the compiler, VM, or GC.
- **No seed corpus.** Every target currently passes `.{}` to
  `std.testing.fuzz`. The Scheme suite is useful source material, but its files
  must be reduced to standalone snippets and encoded as `Smith` inputs before
  they can be used as this fuzzer's corpus.
- **No direct token dictionary.** A libFuzzer token dictionary is not an
  option exposed by Zig's current fuzz API. Keywords and lexical tokens
  (`define`, `lambda`, `let`, `call/cc`, `#\`, `#(`, `quasiquote`, …) should
  instead appear in curated encoded seeds, or preferably be selected by a
  `Smith`-driven grammar generator.
- **No structure-aware generation** and **no differential testing** — the two
  techniques that find the deepest bugs.

## Applying Fuzzilli's ideas to Scheme

A tiered direction, so work can stop at any point. File concrete steps as issues
(per the [dev-docs policy](README.md)); this is the shape, not the backlog.

- **Tier 1 — cheap, high value.** Wire the existing targets into CI as a
  scheduled, *bounded* `zig build test --fuzz=<iteration-limit>` job. Add a
  small set of encoded `Smith` seeds for reader, compiler, and eval forms; add
  valid and intentionally malformed `.sbc` seeds for the loader. Preserve each
  minimised failure as both a regression test and a corpus entry. This is pure
  leverage on what already exists.
- **Tier 2 — structure-aware generation.** A grammar-based generator of valid
  R7RS forms driven directly by `Smith` choices. This is the Scheme analog of
  Fuzzilli's generative core: it gets past the reader and actually exercises the
  compiler, VM, and GC. Bound expression depth, literal sizes, allocation, and
  evaluation time; keep an invalid-input target for parser robustness.
- **Tier 3 — differential testing (highest bug value).** Run generated programs
  through Kaappi *and* a real reference Scheme (Chibi, Gauche, Guile, Chez, or
  Racket) and diff the results. This finds **correctness** bugs, not just
  crashes. Compare a normalized observable result (value, stdout, and exit
  class), and generate only a portable subset: R7RS leaves evaluation order,
  error objects, and several edge cases unspecified. Note: the repo's `(chibi
  test)` is an API shim implemented in Kaappi, **not** real Chibi — a genuine
  external interpreter must be installed as the oracle.
- **Tier 4 — Fuzzilli fork (deferred).** The path in "What a real Fuzzilli fork
  would require" remains available as a research option; documented here so it
  can be chosen consciously rather than drifted into.

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
- Minimise every failure, add a readable regression test, then retain the
  corresponding encoded fuzzer input. A corpus is both a search aid and a
  permanent regression set, as described in the
  [libFuzzer corpus guidance](https://llvm.org/docs/LibFuzzer.html#corpus).
