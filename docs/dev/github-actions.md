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
gh api repos/<owner>/<repo>/commits/<tag> --jq .sha
```

and put the exact version tag in the trailing comment. Dependabot
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
