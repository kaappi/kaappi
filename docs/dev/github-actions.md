# GitHub Actions conventions

Supply-chain hardening rules for every workflow in `.github/workflows/`
(introduced with #1400). CI, release, and fuzz workflows all follow them;
new workflows must too.

## Pin actions to a commit SHA

Every `uses:` reference points at a full 40-character commit SHA, with a
comment naming the version the SHA was resolved from:

```yaml
- uses: actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0 # v7.0.0
```

Tags like `@v7` are mutable — whoever controls the action repo (or
compromises it) can repoint them at arbitrary code that then runs with our
workflow's token and secrets. A commit SHA is immutable, so a compromised
upstream cannot retroactively change what our workflows execute.

To add or update a pin, resolve the tag yourself rather than copying a SHA
from the action's README:

```bash
# What refs/tags/<tag> points at — never ambiguous with branches
gh api repos/<owner>/<repo>/git/ref/tags/<tag> --jq '.object | "\(.type) \(.sha)"'
# If the type printed is "tag" (annotated), peel it to the commit:
gh api repos/<owner>/<repo>/git/tags/<that-sha> --jq .object.sha
```

Do **not** resolve with `gh api repos/<owner>/<repo>/commits/<tag>`: when a
repo has a branch and a tag with the same name, that endpoint returns the
*branch* head while the Actions runner resolves `uses: repo@<name>` to the
*tag* — so the pin silently captures different code than `@<name>` ran.
This is not hypothetical: `kaappi/github-action-pull-request-benchmark` has
a stale `v1` branch shadowing its `v1` tag, and the mismatch broke the PR
benchmark workflow when it was first pinned (#1413). If `refs/tags/<tag>`
404s, the ref really is a branch (e.g. `benchmark-action`'s `v1`) — pin the
branch head and note in the comment which release it corresponds to.

Put the exact version tag in the trailing comment. Dependabot
(`.github/dependabot.yml`, weekly) proposes bumps and rewrites both the SHA
and the version comment, so pins don't go stale silently.

## Disable persisted checkout credentials

Every `actions/checkout` step sets:

```yaml
with:
  persist-credentials: false
```

By default checkout writes the `GITHUB_TOKEN` into the local git config,
where every subsequent step — tests, benchmarks, fuzzer-generated programs,
anything an action shells out to — can read it. No workflow in this repo
needs that: steps that talk to GitHub authenticate explicitly (the `gh` CLI
via a `GH_TOKEN` env var, `github-action-benchmark` and
`action-gh-release` via their token inputs).

If a future workflow genuinely needs persisted credentials (e.g. a step
that runs bare `git push`), prefer passing the token explicitly to that
step; failing that, keep `persist-credentials: true` on that one checkout
with a comment explaining why.

## Least-privilege token permissions

Every workflow declares a top-level `permissions:` block (usually
`contents: read`) instead of inheriting the repository default. Jobs that
need more — the CI benchmark job's `contents: write` for pushing benchmark
data, the release workflow's `contents: write` for creating releases —
scope it at the job or workflow level. Remember that a job-level
`permissions:` block *replaces* the workflow-level one entirely rather
than merging with it.

## Skipping work without breaking (or silently satisfying) required checks

`main` requires eight CI contexts plus `DCO`:

```text
format
test (ubuntu-latest, ReleaseSafe)
test (ubuntu-latest, ReleaseFast)
test (ubuntu-latest, Debug)
test (ubuntu-24.04-arm, ReleaseSafe)
test (macos-latest, ReleaseSafe)
riscv64-test
wasm
DCO
```

Two GitHub behaviours govern anything that makes CI do less work, and they
point in opposite directions:

1. A workflow that does not run **never reports**. Its checks sit
   *"Expected — Waiting for status to be reported"* and the PR is
   permanently unmergeable.
2. A job that is skipped **reports Success** — GitHub's words: *"A job that
   is skipped will report its status as 'Success'. It will not prevent a
   pull request from merging, even if it is a required check."*

So workflow-level `paths:`/`paths-ignore:` is unusable in `ci.yml`: it
triggers (1). `benchmark-pr.yml` uses `paths:` safely only because none of
its checks is required.

The usable shape is a job-level `if:`, which skips the work *and* satisfies
the check. But (2) is a loaded gun. A job whose `needs` **failed** is also
skipped, and therefore also reports Success — so a dedicated gate job that
errors would turn every heavy required context green with nothing built, on
a branch that requires no approving review.

`ci.yml` therefore computes its changed-path classification **inside
`format`**, which is both a required context and every heavy job's `needs`.
A broken classifier is then a red required check, not a silent pass. Two
supporting rules:

- **Gate on `!= 'true'`, not `== 'false'`.** An empty or missing output must
  fall through to running the matrix.
- **Allowlist the inert paths** (`**/*.md`, `docs/**`, `LICENSE`); never
  denylist code. A path nobody anticipated has to default to running CI.
  `.github/workflows/**` is the thing under test and `.claude/**` holds
  executable hooks, so neither is inert — but markdown under either is,
  because nothing in CI reads a `.md` file's contents.

Jobs downstream of a gated job (`windows-*-test` via `windows-cross`,
`coverage`/`benchmark` via `test`) inherit the skip and need no `if:` of
their own.

**When adding a required context, gate it the same way or not at all.** A
new required job that always runs is safe; a new required job gated on a
condition that can never be satisfied repeats the #1728 deadlock from the
other side.
