---
name: create-announcement
description: Post a release announcement to the kaappi org Announcements forum (github.com/orgs/kaappi/discussions). Use when the user asks to announce a release, post a release announcement, tell the community about a version, or share a release on the forum. Takes a release tag such as v0.22.0.
argument-hint: "[tag]"
---

# Create Announcement

Draft and post a release announcement to
<https://github.com/orgs/kaappi/discussions/categories/announcements>.

## Where this actually posts

Org-level discussions at `github.com/orgs/kaappi/discussions` are **backed by
the `kaappi/kaappi` repository** — there is no separate discussions repo. Create
the discussion in `kaappi/kaappi`; GitHub serves it at the `orgs/kaappi` URL.

| Thing | Value |
|-------|-------|
| Repo | `kaappi/kaappi` (id `R_kgDOS7a-eg`) |
| Category | `Announcements` (id `DIC_kwDOS7a-es4C_rmH`) |
| Other categories | `general`, `ideas`, `polls`, `q-a`, `show-and-tell` |

Announcements is a **maintainer-restricted** category. A token without write
access to `kaappi/kaappi` will fail at Step 6, not earlier.

## Who this is for

The release page already carries the exhaustive CHANGELOG. The announcement is
**not** a second copy of it — it is the short, human version for people who
use Kaappi rather than build it. Write for someone who wants to know, in
thirty seconds, whether this release is worth upgrading for.

## Step 0: Resolve the tag

The argument is a release tag (`v0.22.0`). If none was given, use the latest
release and **say which tag you resolved to** before doing any work:

```bash
gh release list -R kaappi/kaappi --limit 5
```

## Step 1: Preflight

```bash
gh auth status
TAG=v0.22.0    # the resolved tag
gh release view "$TAG" -R kaappi/kaappi --json tagName,publishedAt,url,isDraft,isPrerelease
```

Stop and ask the user if any of these hold:

- The release does not exist — the tag may be pushed but the release workflow
  still running. Check `gh run list --workflow=release.yml --limit=1`.
- `isDraft` or `isPrerelease` is true. Announcing an unpublished or pre-release
  build is almost always a mistake; confirm it is deliberate.
- **The release is more than about a week old, or `CHANGELOG.md`'s
  `[Unreleased]` section has substantial content.** Both are signs the next
  release is near, and announcing the older one may not be what the user wants.
  Do not decide this yourself — surface it and let them choose:

  ```bash
  sed -n '/^## \[Unreleased\]/,/^## \[/p' CHANGELOG.md | wc -l
  ```

## Step 2: Check for an existing announcement

Re-running this skill must not double-post.

```bash
gh discussion list -R kaappi/kaappi --category "Announcements" \
  --limit 30 --json number,title,url
```

If one already covers `$TAG`, do not create a second. Show it to the user and
offer to edit it instead (see "Editing an already-posted announcement" below).

## Step 3: Gather source material

> **Authoring note — never write a dollar sign followed by a digit in a shell
> snippet in this file.** Slash-command argument expansion rewrites those tokens
> *before* the skill body is read, and the numbering is zero-indexed: a dollar
> sign followed by zero becomes this invocation's **first** argument — the tag.
> An `awk` field-variable comparison therefore arrives with the tag spliced in
> where the field reference was and matches nothing: no error, just a silently
> empty result. This skill always takes an argument, so that slot is live on
> every run. (Described in prose deliberately — written literally, this note
> would rewrite itself.) Named variables (`$TAG`, `$PREV`), `$@`, `$*`, and the
> braced `${1}` form all pass through untouched. Prefer `git describe` or `grep`
> over `awk` field variables, as below. Full measured rules:
> [claude-code-harness.md](../../../docs/dev/claude-code-harness.md).

```bash
git fetch --tags --quiet
PREV=$(git describe --tags --abbrev=0 "$TAG^" 2>/dev/null)
echo "previous tag: $PREV"

# Save the release body — it is long (v0.21.0's was 193 lines), and having it
# on disk lets you re-read sections while drafting without refetching.
gh release view "$TAG" -R kaappi/kaappi --json body --jq .body > /tmp/rel-body.md
grep -n '^#\{2,4\} ' /tmp/rel-body.md    # section map, to orient before reading

# Scale of the release, and which platforms shipped
git log "$PREV..$TAG" --oneline --no-merges | wc -l
gh release view "$TAG" -R kaappi/kaappi --json assets --jq '.assets[].name'
```

Read the release body **in full** before drafting — the section map alone is not
enough to judge what matters, and the highest-impact item is often filed under
"Fixed" rather than "Added". Cross-check anything ambiguous against
`CHANGELOG.md` in the worktree; the release body is generated from it.

## Step 4: Draft the announcement

### Choosing highlights

Pick **3–6**. The filter is *what can a user do now that they could not
before*, not *what changed*.

**Headline-worthy:**

- New user-facing capability — a subcommand, a CLI flag, a language feature.
- A new platform or architecture in the release assets.
- A group of new SRFIs — collapse the family into **one** bullet naming them,
  never one bullet each.
- A fix for a bug that plausibly bit real users (wrong answers, crashes,
  install failures), stated as the corrected behavior rather than the defect.
- A performance change large enough to notice.

**Not headline-worthy:** internal refactors, file splits, test or CI
infrastructure, doc-only changes, harness changes, fixes to bugs that only
existed on an unreleased branch.

### Title

```text
Kaappi vX.Y.Z — <3–6 word theme>
```

Use `Kaappi vX.Y.Z released` when the release has no coherent theme. Do not
stretch for one.

### Body

````markdown
**Kaappi vX.Y.Z is out.** <One sentence on what this release is mostly about.>

## Highlights

- **<Capability>** — <one sentence on what it lets you do.>
- **<Capability>** — <…>

## Install or upgrade

```bash
curl -fsSL https://kaappi-lang.org/install.sh | bash
```

Binaries for every supported platform are on the
[release page](<release URL>); see [Download](https://kaappi-lang.org/download/)
for checksums and manual install.

## Full notes

[Complete changelog for vX.Y.Z](<release URL>)

---

Questions in [Q&A](https://github.com/orgs/kaappi/discussions/categories/q-a),
feature ideas in [Ideas](https://github.com/orgs/kaappi/discussions/categories/ideas),
and if you have built something with Kaappi we would like to see it in
[Show and tell](https://github.com/orgs/kaappi/discussions/categories/show-and-tell).
````

### Accuracy rules

This is public, permanent, and signed with the maintainer's name.

- **Every claim traces to the release body or CHANGELOG.** Do not infer a
  feature from a commit subject, and do not describe what a change "means for
  users" beyond what the notes state.
- **No invented numbers.** Benchmark figures, procedure counts, and SRFI counts
  are quoted from the notes or omitted. Counting items the notes themselves list
  ("seven new SRFIs") is fine; deriving a figure they do not state is not.
- **Issue numbers belong in the changelog, not the announcement** — link the
  release page instead.
- Plain language. No superlatives the notes do not support.

### Verify every link — before Step 5, not after

A broken link is trivial to fix now and embarrassing once posted. The release
URL comes from `gh release view --json url`, never from memory. Write the body
to a file, then check every link in it actually resolves:

```bash
grep -oE 'https://[^)[:space:]]+' /path/to/announcement.md \
  | sed 's/[.,;:]*$//' | sort -u | while read -r u; do
  printf '%s  %s\n' "$(curl -s -o /dev/null -w '%{http_code}' -L --max-time 20 "$u")" "$u"
done
```

Every line must read `200`. Fix anything that does not before showing the draft.

The character class must exclude whitespace as well as `)`, and trailing
punctuation must be stripped: the body contains
`curl -fsSL https://kaappi-lang.org/install.sh | bash` inside a fence, and a
laxer pattern swallows the trailing `| bash` and reports a spurious `000` for a
URL that is fine.

## Step 5: Review with the user — STOP

Show the full title and body and **wait for explicit approval**. This step is
not optional: posting publishes public content under the user's account in a
maintainer-only category, and it notifies every watcher of the org.

Ask directly whether to post it. Revise and re-show as many times as needed.
Do not proceed on silence or on an ambiguous reply.

## Step 6: Post

Only after an explicit yes. Write the body to a file first — passing multi-line
markdown through `--body` mangles backticks and newlines:

```bash
gh discussion create -R kaappi/kaappi \
  --category "Announcements" \
  --title "Kaappi vX.Y.Z — <theme>" \
  --body-file /path/to/announcement.md
```

`gh discussion` is a preview command. If it is missing or errors out, use the
GraphQL mutation directly — the ids are fixed and listed at the top of this
skill:

```bash
gh api graphql -F body=@/path/to/announcement.md \
  -f title="Kaappi vX.Y.Z — <theme>" \
  -f query='
mutation($title: String!, $body: String!) {
  createDiscussion(input: {
    repositoryId: "R_kgDOS7a-eg",
    categoryId: "DIC_kwDOS7a-es4C_rmH",
    title: $title,
    body: $body
  }) { discussion { number url } }
}'
```

## Step 7: Verify

```bash
gh discussion view <number> -R kaappi/kaappi
```

Report the `github.com/orgs/kaappi/discussions/<number>` URL to the user. Links
were already checked in Step 4; what this pass catches is rendering — a fenced
block that swallowed the text after it, or a heading that did not survive the
round trip. Anything wrong is fixable in place via `gh discussion edit`.

Pinning cannot be automated — there is no `gh discussion pin` and no
`pinDiscussion` GraphQL mutation (verified against the live schema). If the
user wants it pinned, point them at the "Pin discussion" control in the
sidebar of the discussion page.

## Editing an already-posted announcement

```bash
gh discussion edit <number> -R kaappi/kaappi --body-file /path/to/revised.md
gh discussion edit <number> -R kaappi/kaappi --title "New title"
```

Editing is silent — watchers are not re-notified. For a correction that matters
(a wrong version number, a broken install command), also add a comment so
people who already read it see the fix:

```bash
gh discussion comment <number> -R kaappi/kaappi --body "Correction: …"
```

## Announcing something that is not a release

The flow assumes a release tag. For anything else — a new ecosystem library, a
docs milestone, a call for testing — skip Steps 0–3 and gather the material
from whatever the subject actually is, then follow Steps 4–7 unchanged. Keep
the same structure minus the "Install or upgrade" and "Full notes" sections.

## Troubleshooting

| Symptom | Cause |
|---------|-------|
| `Could not resolve to a Repository` | Token lacks access to `kaappi/kaappi`. |
| `Category not found` | Slug is `announcements`; the display name is `Announcements`. Both work with `--category`. |
| Discussion created but not at the `orgs/` URL | It will be — the org view and the repo view are the same discussion. |
| Release body is empty | The release workflow generated notes from an empty `[Unreleased]` section. Fix the release, not the announcement. |
| A shell snippet from this file behaves as if a variable were empty | A positional parameter (dollar sign plus digit, `@`, or `*`) in the snippet was replaced by the slash-command arguments before you read it. See the authoring note in Step 3. |
