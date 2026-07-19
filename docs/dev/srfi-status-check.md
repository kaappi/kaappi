# SRFI final-status guard

Kaappi ships only SRFIs that have reached **final** status. This guard fails CI
if the binary reports a SRFI whose status in the canonical registry is `draft`
or `withdrawn` — catching an accidental `lib/srfi/<n>.sld` for a not-yet-final
(or later-withdrawn) SRFI before it ships.

## Running it

```
zig build                              # produce zig-out/bin/kaappi
bash tools/check-srfi-status.sh        # checks zig-out/bin/kaappi by default
bash tools/check-srfi-status.sh path/to/kaappi   # or a specific binary
```

Output is one `FAIL:` line per offender, or `OK: all N implemented SRFIs are
final.`

## How it works

Two inputs, cross-referenced:

1. **What we implement** — `kaappi features --json` (`srfis.builtin` +
   `srfis.portable`), the derived source of truth described in
   [features.md](features.md), plus SRFI 261 (a resolver-level naming
   convention with no `.sld` file). Because the enumeration comes from the
   binary, adding a portable `.sld` or a built-in `Lib` tag brings the new SRFI
   under the check automatically — there is no second list to maintain.

2. **Each SRFI's status** — [`admin/srfi-data.scm`][data] from the `srfi-common`
   repository, the same data <https://srfi.schemers.org> renders. It is fetched
   at check time (not vendored) so a *newly added* SRFI is validated against its
   real, current status rather than a snapshot that a contributor could get
   wrong.

[data]: https://github.com/scheme-requests-for-implementation/srfi-common/blob/master/admin/srfi-data.scm

## Exit codes

| Code | Meaning |
|------|---------|
| `0`  | Every implemented SRFI is final. |
| `1`  | An implemented SRFI is non-final, or is absent from the registry. |
| `77` | SKIP — no usable binary, or the registry could not be fetched. |

`77` is the automake SKIP convention the shell suites already use. In CI the
step maps `77` to a warning (`::warning::`) and passes, so a transient network
failure fetching the registry never reds an unrelated change. A real non-final
SRFI still exits `1` and fails the job.

## In CI

Wired into the `test` job in
[`.github/workflows/ci.yml`](../../.github/workflows/ci.yml), gated to a single
matrix leg (`ubuntu-latest`, `ReleaseSafe`) so it runs once against that leg's
already-built binary. It is intentionally **not** part of
`tests/scheme/run-all.sh` — that runner executes in every matrix leg, and this
check makes a network request.
