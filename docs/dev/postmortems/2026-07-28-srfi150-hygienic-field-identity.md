# SRFI 150: hygienic field identity lost through `quote`

Postmortem of the three implementation attempts behind SRFI 150 (Hygienic
ERR5RS Record Syntax): two designs that broke as soon as two record types
coexisted, two "engine bugs" filed along the way that were not engine bugs,
a `cadar` red herring that hid a real library-resolution bug, and a final
defect where hygienic symbols were round-tripped through `quote`, which
strips the rename.

## Status

**Fixed** (2026-08-11, closing kaappi#2051; the library first shipped
2026-07-29 via kaappi#1810). The shipped design is described in the SRFI
150 section of
[srfi-implementation-notes.md](../srfi-implementation-notes.md); its rule
is that field identity is resolved entirely at macro-expansion time, while
the renamed symbols are still in hand, and never stored as quoted data.
Regression tests: `tests/scheme/srfi/srfi150.scm` (the reference suite plus
the discriminating controls from #2051),
`tests/scheme/hygiene/macro-fresh-global-readback-1829.scm`, and
`tests/scheme/hygiene/em-syntax-rules-operator-chain-1828.scm`.

## Context

SRFI 150 had been excluded on the grounds that it needed SRFI 147 and 148.
When both shipped (2026-07-26 and 2026-07-28) it was moved back to tracked
(#1810). It extends SRFI 131 (`lib/srfi/131.sld`, the runtime substrate)
with hygienic field-name matching, non-identifier field names, and
accessor-name field references in constructor specs.

## Attempts one and two: the query-macro pattern

The first attempt ported the reference implementation's SRFI 137
`make-subtype` closures directly. The second was a from-scratch rewrite
using a `:secret`-style descriptor macro over SRFI 237. Both had the same
shape: a child type's expansion queries a parent macro's own protocol for
its record-type descriptor through a nested macro call. Both worked for one
type and broke once more than one such query relationship existed side by
side in the same program. The breakage was isolated to two apparent
`em-syntax-rules` engine bugs, filed as #1828 and #1829.

## Neither was an engine bug

**#1829** ("a macro's fresh top-level binding reads back as a different
expansion's same-spelled binding") was the referential-transparency
collision of #1832 wearing a different outfit. The CK machine builds its
output as plain data, so a macro-generated top-level `define` lands under
its *bare* name; the next expansion's own reference to it was therefore a
free reference to an already-bound non-procedure global. #1839's hygiene
rename of free-global macro references closed both issues.

**#1828** ("a variable bound by one `=>` step can't be the operator of a
later chained step") was a misuse in its own reproduction: the final,
non-`=>` template was left unquoted while calling an ordinary procedure,
which SRFI 148's specification documents as an error case. It had nothing
to do with the operator-position framing it was filed under; the mechanism
works, including three levels of chaining, and
`tests/scheme/hygiene/em-syntax-rules-operator-chain-1828.scm` pins that.

Whether the two rejected designs would have worked without these
misunderstandings was never re-tested; the third design avoids the
query-macro pattern entirely and is unaffected either way.

## The shipped design

The type name is bound directly to an ordinary runtime record-type
descriptor, as in SRFI 131; inheritance and field/accessor/mutator
resolution, including multi-level shadowing, happen at run time through
SRFI 237's by-name introspection. The one piece SRFI 131 lacks — hygienic
matching of field and accessor names in named constructor specs — uses
SRFI 213 identifier properties instead of a query macro: each
`define-record-type` use attaches its field/accessor-name pairs to the
type name via `define-property`, a child reads its parent's via `lookup`,
and since `lookup` is reachable only from a procedural transformer,
`define-record-type` became a SRFI 211 `er-macro-transformer` rather than
an `em-syntax-rules` macro.

## The `cadar` red herring (#1831)

This design surfaced a library global-resolution bug that first presented
as `cadar` — specifically `cadar`, not `caar`/`cadr`/`cddr`, and not its
own unrolled spelling `(cadr (car x))` — failing when called from a helper
invoked during an `er-macro-transformer`'s expansion. The framing was
misleading twice over: `cadar` is a `(scheme cxr)` name that
`lib/srfi/150.sld` never imports, while its apparent siblings are
`(scheme base)` names already in `lib_env`; and the file's one other
cxr-only name (`cdddr`) sits inside the transformer's own lambda, which is
evaluated at macro-definition time in the global environment and never
consults `lib_env`. The real rule was tail versus non-tail position (see
the SRFI 237 section of the implementation notes). After the fix the
idiomatic `cadar` spelling went back into `field-alist-ref`.

## The final defect: hygienic symbols through `quote` (#2051)

The first shipped transformer stored field-name symbols in the property
table and compared them by plain `equal?` on the raw, hygiene-renamed
spelling, on the theory that the engine's rename-by-spelling representation
made a symbol's full spelling a sufficient runtime key. It is not: the
compiler strips a `__hyg_N_` rename from any quoted datum
(`compileQuote`'s `stripHygieneFromDatum`, which is correct and required — a
`syntax-rules` template's `'foo` must yield `foo`, not `__hyg_1_foo`). Two
hygienically distinct field identifiers whose spellings strip to the same
name — a template's own field-name literal and the same-spelled identifier
the use site supplies, `__hyg_2_a` and `a` — collapsed into one runtime
field. All four of the reference suite's hygiene assertions failed.

The defect was first misattributed to #1832. The discriminating control:
a pre-existing top-level binding of the colliding spelling is *not*
required — the no-binding variant fails identically — so it was not a
referential-transparency collision at all.

The fix resolves field identity entirely at expansion time: own fields
match by full spelling (this engine's `bound-identifier=?`), inherited
fields by stripped spelling against the parent's stored property
(`free-identifier=?` for what a parent's field name actually refers to),
each resolving to an absolute index into the inherited-then-own layout.
The property table stores counts and stripped-spelling keys only; no
renamed symbol is ever quoted.

Re-enabling the tests surfaced one more hazard. The emitted type-name
binding must also be hygiene-stripped: a macro-introduced `__hyg_N_<t>`
whose base `<t>` is an already-bound global is intercepted by the #1832
alias, which loads the pre-existing global's value even inside the
expansion that defines it, so accessors would have bound against the old
record type whenever a macro redefined a type name. The type name is a
define target, not a free reference, so the stripped spelling is the
correct emission — it rebinds the global like any top-level redefinition
(R7RS 5.3.1) and matches what SRFI 131 emits.

## Lessons

- **Hygienic identity does not survive `quote`.** A renamed symbol is an
  expansion-time object. Resolve everything that depends on its identity
  while the rename is in hand, and store only spellings and indices.
- **A bug filed during a failing design may be the design's bug.** Both
  "engine bugs" here were artifacts of the query-macro pattern; the design
  that replaced it never hit them. Reduce the reproduction outside the
  design before filing.
- **Write the control that would exonerate the suspect.** #2051 was
  blamed on #1832 until the no-binding variant failed identically. One
  negative control settled the attribution.
- **The name a bug presents under is not its cause.** `cadar` was the
  first name to be reached from a non-tail position, nothing more.
