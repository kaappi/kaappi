---
description: Cut a GitHub release for Kaappi — bumps version strings, updates CHANGELOG.md, commits, tags, pushes, and verifies the release workflow. Use when the user asks to make a release, cut a release, publish a version, tag a release, ship a version, or prepare a release.
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

## Step 1: Determine version

```bash
grep 'pub const version' src/main.zig
git tag -l 'v*' --sort=-v:refname | head -1
```

Show the current version and ask what the new version should be:

- **patch** (0.1.0 -> 0.1.1): bug fixes only
- **minor** (0.1.0 -> 0.2.0): new features, no breaking changes
- **major** (0.1.0 -> 1.0.0): breaking changes

Wait for confirmation before continuing.

## Step 2: Generate release notes

```bash
git log $(git tag -l 'v*' --sort=-v:refname | head -1)..HEAD --oneline --no-merges
```

If no tags exist yet, use `git log --oneline --no-merges`.

Combine the `[Unreleased]` section from `CHANGELOG.md` (primary source) with any commits not already reflected. Present draft notes to the user for review. Wait for confirmation.

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

## Step 5: Build verification

```bash
zig build
```

Fix any errors before proceeding.

## Step 6: Commit and tag

```bash
git add src/main.zig src/thottam.zig build.zig.zon CHANGELOG.md
git commit -m "Release vX.Y.Z"
git tag -a vX.Y.Z -m "Release vX.Y.Z"
```

## Step 7: Push (requires user confirmation)

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

## Step 8: Verify

```bash
gh run list --workflow=release.yml --limit=1
```

Show the workflow URL. After it completes:

```bash
gh release view vX.Y.Z
```

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
