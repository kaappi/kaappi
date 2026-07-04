---
description: Cut a GitHub release for Kaappi — bumps version strings, updates CHANGELOG.md and the downloads page, commits, tags, pushes, and verifies the release workflow. Use when the user asks to make a release, cut a release, publish a version, tag a release, ship a version, or prepare a release.
---

# GitHub Release

Full Kaappi release process: version bump, changelog update, commit, tag, push, and CI verification.

## Prerequisites

Check all three before proceeding:

```bash
git status          # must be clean
git branch --show-current  # must be main
gh auth status      # must be authenticated
```

If dirty, ask the user to commit or stash. If not on `main`, ask to switch.

## Step 1: Analyze changes and determine version

```bash
grep 'pub const version' src/main.zig
git tag -l 'v*' --sort=-v:refname | head -1
git log $(git tag -l 'v*' --sort=-v:refname | head -1)..HEAD --oneline --no-merges
git log $(git tag -l 'v*' --sort=-v:refname | head -1)..HEAD --stat --no-merges
```

If no tags exist yet, use `git log --oneline --no-merges`.

Analyze the commits since the last release. Summarize the changes (features,
fixes, breaking changes, docs) and recommend a version bump:

- **patch** (0.1.0 -> 0.1.1): bug fixes only
- **minor** (0.1.0 -> 0.2.0): new features, no breaking changes
- **major** (0.1.0 -> 1.0.0): breaking changes

Present the analysis and recommendation, then ask for confirmation before continuing.

## Step 2: Generate release notes

Combine the `[Unreleased]` section from `CHANGELOG.md` (primary source) with any
commits not already reflected in it. Present draft notes to the user for review.
Wait for confirmation.

## Step 3: Update CHANGELOG.md

The file uses Keep a Changelog format. After editing, it should look like:

```markdown
## [Unreleased]

## [X.Y.Z] - YYYY-MM-DD

### Added
- ...

### Fixed
- ...

## [previous version] - previous date
...
```

- Clear the `[Unreleased]` section content (keep the heading)
- Insert new `## [X.Y.Z] - YYYY-MM-DD` section with the confirmed release notes
- Use today's date in YYYY-MM-DD format
- Preserve all existing versioned sections below

## Step 4: Update version strings

Three files, all must match (no `v` prefix):

**`src/main.zig` line 35:**
```zig
pub const version = "X.Y.Z";
```

**`src/thottam.zig` line 5:**
```zig
const version = "X.Y.Z";
```

**`build.zig.zon` line 3:**
```zig
.version = "X.Y.Z",
```

The docs site's `kaappi_version` (`../kaappi.github.io/mkdocs.yml`) is **not**
bumped here — it lives in a separate repo and tracks the *released* artifact,
so Step 11's workflow bumps it after the release is published.

## Step 5: Refresh the built-in procedure count

The docs cite a built-in procedure count that drifts as procedures are added or
removed. Recompute it from source (unique names passed to `reg(vm, ...)`):

```bash
grep -rhoE '\breg\(vm, "[^"]+"' src/*.zig | sed -E 's/.*, "([^"]+)".*/\1/' | sort -u | wc -l
```

Do **not** use the raw `reg(` call count — it double-counts ~47 procedures that
are re-registered in the sandboxed path (`registerIOSandboxed`, etc.). Unique
names is the honest number.

Find every doc citing the old count and update any that are stale:

```bash
grep -rn "built-in procedures" README.md CONFORMANCE.md CLAUDE.md ../CLAUDE.md docs/dev/
```

Update the count in each match (README.md and CONFORMANCE.md are user-facing;
`CLAUDE.md`, `../CLAUDE.md`, `docs/dev/architecture.md`, and
`docs/dev/llvm-backend.md` are internal). Leave historical `CHANGELOG.md`
entries untouched — they record what was true at the time. Include any changed
files in the release commit (Step 7).

## Step 6: Build verification

```bash
zig build
```

Fix any errors before proceeding.

## Step 7: Commit and tag

Add the version files, the changelog, and any doc files whose procedure count
changed in Step 5:

```bash
git add src/main.zig src/thottam.zig build.zig.zon CHANGELOG.md
git add README.md CONFORMANCE.md CLAUDE.md docs/dev/  # if the count changed
git commit -m "Release vX.Y.Z"
git tag -a vX.Y.Z -m "Release vX.Y.Z"
```

## Step 8: Push (requires user confirmation)

**STOP.** Ask the user for explicit confirmation before pushing. Explain:

- Pushing the tag triggers the release workflow in CI
- CI builds kaappi and thottam binaries for aarch64-macos, x86_64-linux, aarch64-linux, riscv64-linux, plus kaappi.wasm (wasm32-wasi)
- macOS binaries are Developer ID signed and Apple notarized
- It generates SHA256SUMS and creates a GitHub Release
- This is irreversible

After confirmation:

```bash
git push origin main
git push origin vX.Y.Z
```

## Step 9: Verify

```bash
gh run list --workflow=release.yml --limit=1
```

Show the workflow URL. After it completes:

```bash
gh release view vX.Y.Z
```

## Step 10: Run post-release acceptance tests

The `post-release.yml` workflow listens for `release: published` events, but
it will **not** auto-trigger because the release is created by `github-actions[bot]`
using the default `GITHUB_TOKEN`. GitHub suppresses workflow triggers from
`GITHUB_TOKEN`-generated events to prevent recursive loops.

Trigger it manually:

```bash
gh workflow run post-release.yml -f tag=vX.Y.Z
gh run list --workflow=post-release.yml --limit=1
```

Watch the run and wait for it to complete. It downloads the release artifacts
and runs acceptance tests on macOS, Linux x86/ARM, WASM, plus checksum and
install script verification. If it fails, investigate before updating the
docs site — a failure means the release artifacts have a problem (e.g.
missing entitlement, broken binary, bad checksum).

## Step 11: Update docs site (playground WASM + version)

After the release workflow completes (so the release assets exist), trigger
the docs site's `update-wasm` workflow. It downloads the **released**
`kaappi.wasm`, verifies it against the release `SHA256SUMS` (so the playground
runs the same binary users install), bumps `kaappi_version`, then commits and
deploys — no local file copy:

```bash
gh workflow run update-wasm.yml -R kaappi/kaappi.github.io -f tag=vX.Y.Z
# wait for GitHub to register the run, then watch it:
sleep 5
gh run watch -R kaappi/kaappi.github.io "$(gh run list -R kaappi/kaappi.github.io -w update-wasm.yml -L 1 --json databaseId -q '.[0].databaseId')"
```

This updates `/playground/`, `/tour/` (shared WASM binary), and the version
shown on `/download/`, `/guide/first-program/`, and `/guide/repl/` (all read
from `kaappi_version` in `mkdocs.yml`). Verify at `kaappi-lang.org/playground/`
and `kaappi-lang.org/download/` after it deploys.

## Error recovery

**Before push** (undo commit and tag):

```bash
git tag -d vX.Y.Z
git reset --soft HEAD~1
```

**After push** (if workflow failed):

```bash
git push origin --delete vX.Y.Z
gh release delete vX.Y.Z --yes
git tag -d vX.Y.Z
git reset --soft HEAD~1
# Fix the issue, then restart
```

**Step 11 failed** (docs site workflow):

Re-run the workflow — it's idempotent (overwrites the same WASM file and
version string). If it fails repeatedly, check the Actions log in
`kaappi/kaappi.github.io` for the cause (SHA256 mismatch, `mkdocs build
--strict` error, push conflict).
