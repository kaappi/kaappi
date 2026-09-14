# SRFI 147: one `Transformer` value, many binding sites

Postmortem of the seven fixes it took to ship transformer-spec resolution
for SRFI 147 (custom macro transformers): two found by the full Scheme suite
on the first cut, four by review of each other's fixes, one by a
discriminating reproduction that showed an earlier fix's reasoning was
wrong, not just its memory management.

## Status

**Fixed** (2026-07-26 to 2026-07-27, PRs #1760 and #1762 through #1767).
The rules that survived are recorded in the SRFI 147 section of [srfi-implementation-notes.md](../srfi-implementation-notes.md): a
`Transformer` reached from several binding sites is finalized once, gated
by `Transformer.finalized`, and its R7RS 4.3.1 peer snapshot is computed
once, gated by `Transformer.peers_computed`, with both flags set only after
the guarded slices are durably stored. The LIFO `popRoot` rule is in
`.claude/rules/gc-safety.md`; the `.sbc` build-id aliasing is in
[cache.md](../cache.md).

## Context

R7RS's `<transformer spec>` is a literal `(syntax-rules ...)`. SRFI 147
adds three alternatives: a bare keyword aliasing an existing macro, a macro
use that expands to a spec, and a macro use that expands to
`(begin <definition>... <transformer-spec>)`. The first cut (#1760) shipped
only the middle one. Tracing SRFI 148's reference implementation, not just
its grammar, showed its `em-syntax-rules-aux1`/`aux2` core bottoms out
through `(begin (define-syntax a spec) a)` — a helper definition followed
by a bare reference to it — so the other two landed together in #1762.
Every fix below is in `compiler_define_syntax.zig` (then part of
`compiler_macro.zig`).

## 1. A LIFO root-stack violation

The first draft rooted the resolved spec with `pushRoot` + `defer popRoot()`
around the allocating `parseSyntaxRules` call inside `compileLetSyntax`'s
per-binding loop. The same loop iteration then pushed an unrelated root for
its own result-array entry, so when the deferred pop fired at the end of the
iteration it removed the most recent entry — the wrong one — and left the
transformer unrooted.

Nothing in SRFI 147's own tests noticed. It surfaced in
`tests/scheme/srfi/srfi257.scm`, a heavily macro-based library, as an
"invalid syntax" error with no visible connection to the cause. Fixed by
popping explicitly, immediately after the protected call. The rule went
into `.claude/rules/gc-safety.md`, whose glob also grew to cover
`compiler*.zig` and `expander.zig` — both do GC-sensitive work directly and
neither had been covered.

## 2. A parent-scope visibility gap

`resolveTransformerSpec`'s macro lookup checked only `self.macros`. The
established macro-call path, `expandAndCompileMacroUse`, merges every
ancestor `Compiler` scope's macros first, because a nested child scope — a
`let-syntax` whose body sits inside `guard`'s desugared lambda, which SRFI
64's `test-equal` produces — never inherits an enclosing scope's macros
into its own map. A `syntax-rules*`-based spec anywhere but the outermost
scope was rejected as "not a macro". Fixed by merging the same way.

## 3. Begin-internal helpers must outlive the resolution

The `begin`-wrapped form registered its helper definitions only in
`resolveTransformerSpec`'s function-local `merged_macros`, discarded when
the call returned. That is not enough: `em-syntax-rules-aux2`'s base case
expands to `(begin (define-syntax o spec) o)`, but the *surrounding*
`syntax-rules` body also calls `o` from within its own rules (for example
`(ck s "arg" (o) . q)`), so `o` must resolve every time the macro being
defined is later invoked, not only while this one spec is resolved. A
direct reproduction — a `define-syntax` chain where `step2`'s template
calls `step1`, called twice after definition — failed with
`undefined variable '__hyg_N_step1'`. Fixed (#1763) by registering each
helper in the scope's persistent `self.macros` (and `lib_env` at library
top level), exactly as an ordinary `define-syntax` at that depth would be.

## 4. Double finalization leaked

That fix immediately surfaced the next one under the unit suite's
leak-checking allocator. A `begin`-wrapped alias can hand the same
`Transformer` value to two or more binding sites (a helper aliased directly
by its own generator, then re-aliased by an enclosing one), and each of
`compileDefineSyntax`/`compileLetSyntax`/`compileLetrecSyntax`
unconditionally ran `captureLocalsOnTransformer` and `computeBoundFreeRefs`
on whatever `resolveTransformerSpec` returned. Both allocate and overwrite
a slice field without freeing what was there, so the second pass over an
already-finalized object leaked the first allocation. Fixed by merging the
two calls into `finalizeTransformer`, guarded by a new
`Transformer.finalized` flag.

## 5. The same hazard, one code block over

Review of #1763 (CodeRabbit, after CI had already auto-merged it) found an
identical "unconditionally `dupe` and overwrite" shape in
`compileLetSyntax`'s sibling-suppression bookkeeping
(`let_syntax_peer_names`/`let_syntax_peer_vals`, R7RS 4.3.1), which lives
in a separate block of the same per-binding loop, outside
`finalizeTransformer`'s reach. Reachable as soon as two siblings of one
`let-syntax` resolve to the same `Transformer`: a begin-wrapped helper
reference for one, a bare alias of the same helper for the other.

Proving it was a real leak took care: an earlier draft's reproduction used
a template with zero free references, where `dupe` of an empty slice does
not allocate, so the mutation-tested unit test passed against the broken
code. The corrected reproduction references a true sibling. The fix
(#1764) was a linear scan of the call's own `tx_vals` prefix for an
identical value already processed in the same loop — deliberately not a
permanent per-object flag, on the reasoning that a transformer aliased into
some *other* `let-syntax` form later "genuinely needs its own peer snapshot
computed against that different form's sibling set".

## 6. Cross-form recomputation was wrong, not merely leaky

The same review flagged what the prefix scan could not catch: a transformer
aliased into a different `let-syntax` form still reached the recomputation
code, which overwrote the earlier form's snapshot without freeing it. The
first fix (#1765) freed the old pair before overwriting and kept the
reasoning above.

**That reasoning was the bug.** R7RS 4.3.1's peer snapshot exists to freeze
a template's free references against what was in scope at the template's
own point of definition, so that later shadowing at another use site cannot
change what a name resolves to. Recomputing it against a different form's
outer bindings is exactly the interference the mechanism exists to prevent.

Only a discriminating reproduction showed it. A plain top-level *procedure*
as the shared free reference cannot tell the two designs apart —
`let_syntax_peer_vals` reads `self.macros`, not `self.globals`, so a
procedure binding was never captured. A *macro* redefined between the two
forms exposed it: recomputation silently changed a previously correct
answer from 11 to −10, using the second form's redefinition instead of the
binding at the helper's point of definition. Nesting the reuse inside the
defining form's own body was worse — it corrupted the *outer* binding too,
since the emptied snapshot let an outer sibling rebinding leak through
unsuppressed for both calls.

Fixed (#1766) by replacing the scan with a permanent once-per-object
`Transformer.peers_computed` flag, mirroring `finalized` but a distinct
field: peer suppression is specific to `compileLetSyntax`, unlike the
finalization every macro-defining form needs. The snapshot is computed at
whichever form first encounters the object and reused unchanged by every
later encounter, same form or not.

Verifying this took a detour that looked like nondeterminism. Toggling the
worktree between old and new code with `git stash` / `git checkout <sha> --
<path>` without `kaappi cache clear` after each rebuild made the same
reproduction answer differently across otherwise identical rebuilds. The
`.sbc` cache key's build-id half is the git commit hash plus a binary
`-dirty` flag, not a hash of the uncommitted changes, so two different
uncommitted edits at the same base commit share cache entries. Documented
in [cache.md](../cache.md).

## 7. The flag was set before the allocations it guards

The first cut of #1766 set `peers_computed = true` immediately, before the
fallible allocations (`peer_names_f`/`peer_vals_f` appends, both `dupe`
calls) that build the snapshot. An OOM partway through would leave the flag
permanently true with the slices at their default-empty value, and every
later reuse would treat "no suppression needed" as the final answer instead
of retrying. Fixed (#1767) by assigning the flag strictly after both slices
are stored, right before the existing `self.macros.put`.

## Lessons

- **A value reachable from several binding sites needs once-per-object
  processing, gated on the object.** A per-site scan (fix 5) catches only
  the sites it can see; a per-object flag (fixes 4 and 6) catches all of
  them. And set the flag after the work it guards, never before (fix 7).
- **Test the reasoning, not only the leak.** Fix 5's reproduction proved a
  leak and nothing else; fix 6 needed a reproduction where the two designs
  give different *answers*. When a fix's justification is "this case
  genuinely needs recomputation", write the test that would fail if it
  did not.
- **A leak test that allocates nothing tests nothing.** `dupe` of an empty
  slice is free; the mutation-tested unit test passed against the broken
  code until the template gained a real free reference.
- **The full suite finds what the feature's own tests cannot.** Fixes 1 and
  2 needed a macro-heavy, multi-scope program; SRFI 257 supplied one.
- **Clear the `.sbc` cache between A/B rebuilds of uncommitted code.**
