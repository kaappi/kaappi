# `kaappi features` — machine-readable capability discovery

`kaappi features` answers an agent's (or a hurried human's) first question —
"what am I working with?" — without running a probe program or scraping
`--help`. It reports, for *this* binary:

- **version** and **git build id** (short HEAD hash, `-dirty` when the tree had
  uncommitted changes at build time)
- **target triple** and **build mode** (`Debug` / `ReleaseSafe` / …)
- **compiled-in subsystems** — the KEP-0004 `cond-expand` feature identifiers
- **SRFIs**, split into built-in (Zig primitives) and portable (`.sld` files)
- **initial VM/GC limits** and whether `--sandbox` is available

It is the CLI-boundary analogue of KEP-0004, which gives the same capability
discovery *inside* Scheme via `cond-expand`. Part of the machine-legibility epic
([#1503](https://github.com/kaappi/kaappi/issues/1503)); tracked in
[#1517](https://github.com/kaappi/kaappi/issues/1517).

## Forms

```
kaappi features            human-readable capability table
kaappi features --json     one JSON object for structured / agent use
```

`--json` is the primary interface; the table is the human-friendly secondary.
Like `kaappi explain`, `features` is a pure query over static build/registry
data — no VM, GC, or library setup — so `main` dispatches it before any of that
exists (`src/features.zig:maybeRun`, called from `src/main.zig`). It is
native-only; WASM's entry point just runs a file.

## JSON shape

```json
{
  "version": "0.14.1",
  "build_id": "5a2acef2",
  "target": "aarch64-macos-none",
  "build_mode": "ReleaseSafe",
  "gc_stress": false,
  "sandbox_available": true,
  "features": ["r7rs", "kaappi", "ieee-float", "posix", "exact-closed",
               "exact-complex", "kaappi-fibers", "kaappi-reactor",
               "kaappi-diagnostics", "kaappi-threads"],
  "srfis": { "builtin": [1, 9, 13, …], "portable": [0, 2, 4, …] },
  "limits": {
    "initial_frame_capacity": 480,
    "initial_register_capacity": 2048,
    "gc_initial_threshold": 8192
  }
}
```

Keys are the stable machine contract; string values reuse
`lsp_diagnostic.writeJsonString`, so escaping matches `--diagnostics=json` and
`kaappi explain --json` byte-for-byte.

## Single source of truth (no second list to drift)

The whole point is that this output can never disagree with the rest of the
toolchain, because every field is *derived*, never re-typed:

| Field | Derived from |
|-------|-------------|
| `features` | `types.platform_features` — the exact table `cond-expand` (`src/compiler_conditionals.zig`) and R7RS `(features)` (`src/primitives_list.zig`) resolve against. A unit test asserts the output equals this array member-for-member. |
| `srfis.builtin` | the library registry: the `srfi_*` tags of `primitives.Lib` (which carry Zig primitives) plus the syntax-only `srfi.*` entries of `library.extra_std_libraries` (currently `srfi.9`). |
| `srfis.portable` | `build_options.portable_srfis`, generated at build time by scanning `lib/srfi/*.sld` (`build.zig:scanPortableSrfis`). Ship a new portable SRFI and this list updates itself. |
| `version`, `limits`, `gc_stress` | `build_options` (set in `build.zig`). |
| `build_id` | `build_options.git_build_id` (`build.zig:gitBuildId`, best-effort `git rev-parse`; `"unknown"` if git is unavailable). |
| `target`, `build_mode` | `@import("builtin")`, comptime. |

The `features` guarantee is the load-bearing one and is enforced by a test
(`features json shares exactly the cond-expand feature table`): if someone adds
a subsystem to `platform_features` without it appearing here — or vice versa —
the test fails. The two SRFI lists are generated rather than test-locked; adding
a `Lib` tag or a `.sld` file is enough.

## Where the code lives

- `src/features.zig` — the subcommand: arg parsing, data derivation, text and
  JSON rendering, and all the unit tests.
- `build.zig` — `gitBuildId` and `scanPortableSrfis` compute the two build-time
  inputs at configure time, so the running binary never shells out to git or
  scans `lib/srfi` on disk (an installed binary may have neither).
- `src/library.zig` — `extra_std_libraries`, the shared list the two registrars
  and `features` all read (so the syntax-only built-in SRFIs can't drift).

## Adding a capability

- **A new subsystem** (a `kaappi-*` `cond-expand` identifier): add it to
  `types.platform_features`. It appears in `features` automatically; the shared
  test keeps the two in lockstep.
- **A new built-in SRFI**: it comes from a `Lib` tag (or an `extra_std_libraries`
  entry) — both are picked up with no `features` change.
- **A new portable SRFI**: drop the `lib/srfi/<n>.sld` file; the build-time scan
  finds it.

## Related

- The [conformance page](https://kaappi-lang.org/conformance/) documents the
  `cond-expand` identifiers for Scheme authors; it links here for the CLI view.
- [observing-the-pipeline.md](observing-the-pipeline.md) — the `ast`/`expand`/`ir`
  read-only dumps, the other "understand the build" introspection commands.
- [srfi-status-check.md](srfi-status-check.md) — the CI guard that reads
  `srfis.builtin`/`srfis.portable` from `features --json` and fails if any
  implemented SRFI is not `final` in the canonical registry.
- [check.md](check.md), [test-runner.md](test-runner.md) — sibling
  machine-legibility subcommands.
