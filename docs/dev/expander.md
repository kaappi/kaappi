# The macro expander

How `syntax-rules` and the procedural transformers expand, and how hygiene
is achieved without syntax objects. This is the as-built companion to
[KEP-0018](https://github.com/kaappi/keps/blob/main/keps/0018-macro-expander-hygiene.md)
(the design record) and the internal counterpart of
[KEP-0006](https://github.com/kaappi/keps/blob/main/keps/0006-explicit-renaming-macros.md)
/ SRFI 211 (the user-facing procedural-macro contract). Read it before
touching `expander.zig`, `expander_instantiate.zig`, `compiler_macro.zig`
or `compiler_define_syntax.zig`, and before believing a bug report that
claims an expander bug — several such reports turned out to be the
reporter's macro ([lessons-learned.md](lessons-learned.md) §16–17).

The one-paragraph version: **an identifier is a bare interned symbol, and
hygiene rides in its name.** Every identifier a template introduces is
renamed to `__hyg_<n>_<name>` under a per-invocation scope, once, while
the template is instantiated. The compiler recognizes keywords and
variables through the rename by stripping the prefix ("effective-name"
dispatch) and completes hygiene after expansion by injecting register
aliases so the renamed names resolve to the bindings the macro's
definition site meant. There is no syntax-object type, no
`datum->syntax`, no phase tower — which is also why `syntax-case` cannot
be added on top of this representation
([srfi-exclusions.md](srfi-exclusions.md)).

## Where it sits

```text
Reader ─► Compiler.compile
             │  collectSetTargets  (set! pre-scan, expands macros speculatively)
             ▼
          ir.lowerWithMacros ──► head names a macro? ──► .passthrough node
             │                                                │
             ▼                                                ▼
          compileFromNode                            compileForm ──► expandAndCompileMacroUse
                                                                          │  (compiler_macro.zig)
                                                                          ▼
                                                                  expander.expandMacro
                                                                     │            │
                                                          syntax-rules        procedural (SRFI 211)
                                                          match + instantiate  expandProceduralMacro → VM
```

Expansion is **interleaved with compilation, not a separate pass**.
`ir.lowerWithMacros` (`ir.zig`) checks whether a form's head names a macro
in the compiler's macro table and, if so, wraps the whole form in a
`.passthrough` node; `compileForm` (`compiler.zig`) then hands it to
`expandAndCompileMacroUse`, which expands and immediately compiles the
result. `kaappi expand` drives the same engine and prints the result
instead of compiling it ([observing-the-pipeline.md](observing-the-pipeline.md)).

| File | Owns |
|------|------|
| `expander.zig` | `expandMacro` (the sole expansion chokepoint), `expandProceduralMacro`, the pattern matcher, the well-known/reserved keyword tables, the usertext-marker walk, `stripHygieneFromDatum` |
| `expander_instantiate.zig` | `instantiateTemplate` and its ellipsis machinery, `renameForHygiene`, the scope-table rename minting. Shares `expander.zig`'s threadlocal per-expansion context |
| `compiler_macro.zig` | `expandAndCompileMacroUse`: the chain loop, the temporary-globals dance, alias injection, the fixpoint guard, error mapping |
| `compiler_define_syntax.zig` | `define-syntax`/`let-syntax`/`letrec-syntax`/`define-property`, transformer-spec resolution (SRFI 147), `parseSyntaxRules`, `finalizeTransformer` |
| `compiler_gate.zig` | `collectSetTargets`, the `set!` pre-scan that expands macros speculatively |
| `types_macro.zig` | the `Transformer` heap object |
| `globals.zig` / `vm_shims.zig` | the function-pointer hooks through which the expander reaches the VM without importing it |

## The Transformer object

`types_macro.Transformer` is the heap object a macro keyword is bound to,
in the compiler's `self.macros` table and, for a library-top-level
definition, the library's `lib_env`. Fields a contributor needs:

- `kind` — `syntax_rules`, `er_macro` or `lisp_macro`; the last two hold the
  Scheme procedure in `proc` (GC-traced).
- `literals` / `patterns` / `templates` / `num_rules` — the parsed
  `syntax-rules` spec; `custom_ellipsis` for SRFI 46's fourth form.
- `literal_bound` — per literal, the definition-site binding slot (or
  `LITERAL_UNBOUND`), for the R7RS 4.3.2 same-binding rule.
- `def_env` / `def_env_val` / `def_lib_name` — the defining library's
  environment and canonical name, null for a top-level or REPL macro (#1812).
  `def_env` is a raw pointer reachable only through `def_env_val`, the same
  invariant as `Function.env` (#1962).
- `bound_free_refs` / `captured_locals` / `def_site_local_refs` — computed
  once at definition time by `finalizeTransformer`: which free template
  references were bound then, and to what.
- `let_syntax_peer_names` / `let_syntax_peer_vals` — the R7RS 4.3.1
  sibling snapshot for `let-syntax`.
- `finalized` / `peers_computed` — once-per-object guards. One transformer
  value can be reached from several binding sites through SRFI 147's alias
  forms, and re-running either computation is not merely a leak but wrong
  ([postmortems/2026-07-26-srfi147-shared-transformer-values.md](postmortems/2026-07-26-srfi147-shared-transformer-values.md)).

`define-syntax` (`compileDefineSyntax`) resolves the spec, roots the fresh
transformer through `gc.extra_roots` — the compiler-local macro map is
invisible to the GC (#1401) — records `def_env`/`def_lib_name`, finalizes,
and stores it. Transformers, procedural ones included, survive a `.sbc`
cache round trip (`bytecode_file_write.zig`, #1888).

### Transformer specs beyond a literal `syntax-rules`

R7RS allows only `(syntax-rules ...)`. `resolveTransformerSpec` also
accepts, per SRFI 147, a bare keyword aliasing an existing macro, a macro
use that expands (in several steps if needed) to a spec, and
`(begin <definition>... <spec>)`; and, per SRFI 211,
`(er-macro-transformer <expr>)` / `(lisp-transformer <expr>)`, whose
`<expr>` is evaluated **at definition time in the global environment**
through the `eval_datum_for_macro` hook. That evaluation happens under
`kaappi check`, the LSP and `--sandbox` too — a ratified decision, not an
oversight ([decisions/compile-time-macro-execution.md](decisions/compile-time-macro-execution.md)).
The SRFI 147 section of [srfi-implementation-notes.md](srfi-implementation-notes.md)
has the resolution rules.

## Hygiene: rename on instantiate

### What is renamed

`instantiateTemplate` walks a template once. A symbol that is a pattern
variable is substituted; a literal or the macro's own keyword is kept; a
name in `reserved_template_forms` is kept bare; **everything else goes
through `renameForHygiene`** — including `if`, `let`, `lambda` and the
other operator keywords, which the compiler recognizes by effective name
(#2074). The reserved set is small and each member is there because
something matches it structurally by spelling: the definition and library
forms (`define`, `define-syntax`, `define-record-type`, `import`, …), the
nested-spec head `syntax-rules`, the aux syntax `else`, the pattern
markers `...` and `_`, and the quote family when used as a *value*.
`well_known_forms` is the larger list of keywords the expander knows about
at all; `if` and `let` are deliberately absent from it because the R7RS
suite rebinds them as variables.

### The scope id and its flag bits

`expandMacro` mints a fresh scope id per invocation (`freshScope`, an
atomic counter) and passes it down the walk as `intro_scope`. The high bits
of that `u32` carry context flags (`expander_instantiate.zig`):

| Flag | Meaning |
|------|---------|
| `BINDING_FLAG` | identifier is in binding position |
| `FORMAL_FLAG` | identifier is a lambda formal (the one anaphoric-binding carve-out, SRFI 190) |
| `LET_PAIR_FLAG` | template is a single `(var init)` let-binding pair |
| `NESTED_SR_FLAG` | inside a nested `syntax-rules` template (a macro-generating macro) |
| `QUOTE_FLAG` | inside `(quote ...)`: substitute, still rename (#1801) |
| `VERBATIM_FLAG` | re-walking a usertext splice: substitute, never rename |
| `ESCAPE_FLAG` | inside the `(... <template>)` ellipsis escape |
| `QQ_DEPTH_MASK` | quasiquote nesting depth (0–7); symbols under `quasiquote` are data until a depth-matching `unquote` |

`renameForHygiene` masks off every flag that does not change renaming
behaviour to get a `clean_scope`, so a binder and its references — inside
and outside a nested template, quoted or not — share one gensym. A
scope-table entry `{original_name, scope, renamed_to}` records each
rename; the table is threadlocal, capped at `MAX_SCOPE_ENTRIES = 256`
(`ScopeTableFull` beyond that), and its count is saved and restored around
each expansion so entries never leak across invocations. Concurrent
compilers (SRFI 18 threads compile with their own VM) therefore cannot
split a binding from its references.

### The decision order in `renameForHygiene`

Read the function's own comments for the incident behind each step; this
is the order and the reason.

1. **Already renamed → pass through.** A name starting `__hyg_`, `__nlet_`
   (named-let loop gensyms, which flow back through templates) or the
   def-env prefix is returned unchanged. Renaming again cannot prevent a
   capture — gensyms are unique — and only severs a reference from the
   binding an enclosing expansion made (#919).
2. **Usertext splice** (`VERBATIM_FLAG`) → bare. It is use-site data from an
   enclosing expansion, not this template's identifier.
3. **Quoted** (`QUOTE_FLAG`) → renamed anyway, deduped through
   `clean_scope`. A quoted template identifier is still an *identifier* at
   expansion level: two expansions of `'g` must stay distinguishable to a
   `bound-identifier=?` built from further expansion (SRFI 148's
   `em-gensym`). The compiler strips the rename when it compiles a real
   `quote` datum (below), so runtime `eq?` is unaffected.
4. **Def-env resolution** (#1812). A free reference that the macro's *own
   defining library* binds, and that is not a `(scheme base)` name, becomes
   `__kaappi_defenv__<lib>\x1f<name>`, which `get_global`/`call_global`
   resolve through that library's environment at run time — immune to
   whatever the use site's globals hold under the same spelling. Skipped
   while the defining library is itself still loading (`def_env ==
   globals`), because the library is not registered until its declarations
   finish. The `(scheme base)` exclusion exists because several compiler
   fast paths (`call-with-values` in tail position, `apply`, `call/cc`)
   match those names by exact bare spelling.
5. **Globals check** (#2003). A global *procedure* is renamed like any other
   identifier, so a use-site local of the same name cannot capture it
   (R7RS 4.3.2) — except a lambda formal (`FORMAL_FLAG`), kept bare and
   recorded as an identity rename, for SRFI 190's anaphoric `yield`. A
   global *transformer* stays bare so `lookupMacro` still recognizes the
   keyword. A `VOID` sentinel — planted by the body pre-scan for an internal
   `define` later in the same body — keeps its name so the reference reaches
   that binding (R7RS 5.3.2).
6. **Cross-frame def-site locals** stay bare: a free reference to a local
   of the macro's defining function, when the expansion lands in a nested
   lambda, cannot be reached by a register alias and must compile through
   the ordinary upvalue path (#1644).
7. **Scope-table lookup, else mint** `__hyg_<gensym>_<name>`.

### Provenance: the usertext marker

A macro-generating macro's template contains another `syntax-rules` spec.
When the generated macro later expands, its template mixes its own
skeleton with text the *user* supplied at generation time; without
provenance, that user text would be renamed as if template-introduced,
under a different scope at every generation, severing binders from
references (SRFI 257, #1644). So pattern-variable substitutions into a
nested template are wrapped as `(__hyg-usertext . value)` and unwrapped
verbatim by the next instantiation — or by `matchPattern`, for
pattern-side splices. `stripUsertextMarkers` removes them from a finished
expansion before compilation, skipping `syntax-rules` subtrees so specs of
macros the expansion *defines* keep theirs. Three spine-walk sites had to
learn to unwrap before this worked end to end (#1787).

### Round-tripping through `quote`

Because a quoted identifier is renamed (step 3), the compiler strips the
prefix when it turns a `quote` or `quasiquote` datum into a runtime value
(`stripHygieneFromDatum`, called from quote compilation). Consequently
**hygienic identity does not survive `quote`**: anything that needs to
tell two same-spelled identifiers apart must do so at expansion time,
while the renames are in hand, and store only spellings or indices.
SRFI 150 shipped once with field names round-tripped through `quote` and
all four of its hygiene assertions failed
([postmortems/2026-07-28-srfi150-hygienic-field-identity.md](postmortems/2026-07-28-srfi150-hygienic-field-identity.md)).

## The syntax-rules engine

`expandMacro` sets the threadlocal context (custom ellipsis, literals,
def-env, def-site local refs, the use-site binding callback), tries each
rule's pattern in order with `matchPattern`, and instantiates the first
match's template. No match is `NoMatchingPattern`.

**Patterns.** Literals follow R7RS 4.3.2: a literal matches an input
identifier only if both refer to the same binding or both are unbound,
compared as binding *slots* (`literal_bound` on the definition side,
`UseSiteBindingCheck.resolve` on the use side), so two different bindings
with one spelling are told apart. A hygiene-renamed identifier on either
side still matches an *unbound* literal of the same base name, because a
rename is minted precisely when the identifier had no binding (#1720).
`_` matches anything and binds nothing; constants match by equality;
vector patterns are converted to lists; dotted tails are supported.
The binding buffer is `MAX_BINDINGS = 128` variables of up to
`MAX_ELLIPSIS_VALUES = 1024` values each — it is about a megabyte and is
deliberately left uninitialized, because Zig's ReleaseSafe `0xAA` fill of
it was 96 % of an 80-second library compile (#1802).

**Templates.** `instantiateEllipsis` handles nesting depth seeded from the
pattern (`patternVarNesting`), consecutive ellipses `(x ... ...)` and
depth-relaxed siblings (SRFI 149), per-depth count checks
(`EllipsisCountMismatch`), and rejects a `...` whose element binds no
pattern variable at that depth (`EllipsisNoPatternVariable`, #1791 — almost
always a typo for the escape `(... ...)`). Inside a nested `syntax-rules`
template an ellipsis that references none of the outer bindings belongs to
the inner macro and is preserved.

**Custom ellipsis** (SRFI 46) is per transformer; `isEllipsis` also refuses
to treat a declared literal as the ellipsis.

## Procedural transformers (SRFI 211)

`expandMacro` dispatches on `Transformer.kind`; `er_macro` and `lisp_macro`
skip the pattern engine and go to `expandProceduralMacro`, which:

- strips usertext markers so the procedure sees plain data;
- mints a fresh `er_scope` and saves/restores the whole threadlocal
  context, so a transformer that itself triggers expansion (through `eval`)
  restores the outer invocation on return;
- roots the input and, for `er_macro`, two freshly allocated native
  procedures, then calls the transformer through the `call_proc_for_macro`
  hook. Rooting is strictly nested and the call balances its own pushes;
- for SRFI 213, re-enters a transformer that returns a procedure with the
  `lookup` procedure (bounded to 8 hops);
- maps a raised condition to `TransformerFailed`; the compiler copies the
  real Scheme message into the diagnostic (#1846).

`rename` is `renameForHygiene` under `er_scope`, applied to every symbol
leaf of any datum (a cycle is rejected as a catchable error, #2403).
Reserved forms and in-scope macro keywords rename to themselves and are
recorded as *identity entries* in the scope table — that record is what
lets `compare` tell "the transformer holds the definition-side spelling"
from "two plain use-site tokens". So an ER macro gets exactly the hygiene
strength of a `syntax-rules` one: no more, no less.

`compare` (binding-aware since PR #2401 closed #2388 on 2026-08-28,
resolving KEP-0018's UQ6) classifies
each argument as a use-site local slot, a specific def-env binding, or
free, and answers whether the classifications agree. The one shape a
symbol expander cannot settle is documented in the function's comment: a
spelling that occurs in the input *and* was bare-renamed this invocation,
compared under a use-site local shadow. `compare` refuses in that case,
which is right when one argument is the input token and a known-wrong `#f`
when both are the invocation's own rename products. `ir-macro-transformer`
is not provided for the same underlying reason: injected and
macro-generated symbols are the same interned object.

## Finishing hygiene in the compiler

`expandAndCompileMacroUse` (`compiler_macro.zig`) is where a renamed
expansion becomes code that resolves correctly.

**Before expansion**, for each transformer in the chain: captured
definition-site locals are temporarily removed from the globals view, the
def-env's bindings are temporarily added, and the transformer's
`bound_free_refs` that name a non-procedure global are collected. This
"temporary-globals dance" is what steers `renameForHygiene`'s step 5; every
change is recorded and undone LIFO when the chain finishes.

**During expansion** the GC is suppressed (`no_collect`) because the
half-built result is unrooted; the result is then appended to
`extra_roots` for the rest of the enclosing compile scope.

**After expansion**, two walks over the result complete the binding:

- `injectHygienicCapturedLocals` finds each `__hyg_N_x` whose base `x` is
  a captured definition-site local and appends a compiler local of the
  *renamed* name aliasing the definition-time slot — with the slot's
  *current* boxing status, since a lambda may have captured it since.
- `injectHygienicGlobalAliases` does the same for a renamed reference to a
  non-procedure global bound at definition time: a fresh register loaded
  with `get_global`, marked `is_global_alias`. The reference was renamed
  rather than left bare because a bare reference is indistinguishable from
  a same-spelled pattern-variable argument in the same expansion (#1832 —
  a wrong-value bug, `(999 999)` for `(999 5)`).

Both walks skip a `__hyg_` name that is macro-bound: that is a renamed
`let-syntax` *keyword*, and aliasing it would shadow the macro (SRFI 257's
`k`). `let-syntax` sibling keywords are then swapped to their outer values
for as long as the transformer's material is live (R7RS 4.3.1), and lint is
suppressed over everything compiled from the expansion (`kaappi check`
warns only about calls the user wrote, #1511).

### Effective-name dispatch

The other half of the contract is that every place the compiler recognizes
a keyword or a built-in by name does so through
`types.stripHygienicPrefix`, which peels both the `__hyg_N_` and the
def-env prefix. Fifteen source files call it. The rule for new code: **never
match a symbol name by exact spelling in a compiler path a macro can
reach** unless the name is in `reserved_template_forms`. The #1812 work
found three regressions of exactly this shape (a tail-position
`call-with-values` fast path, `stream-match`, `guard`), each a name matched
raw that a rename had just changed.

## Limits, chains and the fixpoint

Two counters in `compiler_macro.zig` guard different shapes and must not be
conflated:

| Constant | Bounds | Why |
|----------|--------|-----|
| `MAX_MACRO_EXPANSION_DEPTH = 256` | *nested* expansions — a macro use compiled from inside another expansion's result recurses natively through `compileExpr` | protects the native stack. Raising it segfaults, and in a Debug build the segfault deadlocks the test allocator's own stack capture at 0 % CPU (#1796) |
| `MAX_MACRO_EXPANSION_STEPS = 10 000` | *head-position chains* — an expansion that is directly another macro use in the same position | these iterate in a `while` loop at O(1) native stack (SRFI 148's CK machine, a runaway `(loop) → (loop)`) |

Either limit is `MacroExpansionLimit` → `KP2003`. The chain loop keeps every
link's injected aliases, temporary globals and peer swaps alive until the
*final* non-macro form finishes compiling, because identifiers link *k*
introduced can survive into it.

A **fixpoint guard** (`valuesStructurallyEqual`) handles a macro that
expands to itself *and* whose keyword is a special form — SRFI 219's
`(define x e) → (define x e)` — by suppressing the macro for that keyword so
the built-in takes over. A non-special-form self-expansion keeps chaining
and hits the step limit.

Two other bounded walks matter when a macro receives a datum-label cycle
(`#0=(a . #0#)`, #2403/#2404/#2405): `stripUsertextMarkers` and
`stripHygieneFromDatum` carry tortoise–hare spine checks and a depth cap,
`erFormMentionsSymbol` a node budget, and `lowerWithMacros` a code-path set
that turns a car-side cycle into a named compile error instead of a native
stack abort.

## The set! pre-scan

`Compiler.compile` runs `collectSetTargets` (`compiler_gate.zig`) over a
top-level form *before* lowering, so that a `set!` a macro template
introduces still boxes its target local (#1168, #1250). That makes the
pre-scan a speculative evaluator of macro code: it expands macros it can
see, including branches the real compiler never takes — it does not
register nested `define-syntax`, so an unknown operator's arguments all get
expanded. SRFI 148's `free-identifier=?` continuations doubled the work per
pattern element (#1775). It is therefore **budgeted**: `SetScanBudget`
caps the number of expansions, the walk has its own recursion cap (256,
deliberately unrelated to the expansion depth above — SRFI 257 trips this
one several times per run while compiling fine) and a spine cap for
datum-label cycles, and exhausting any of them marks the scan
`truncated`, which the compiler treats as "every name is a `set!` target"
— every local boxed, nothing folded. That degradation costs optimization,
never correctness; a silently partial scan would leave a mutated local
unboxed and foldable (#2401 review).

## Errors

`ExpandError` is `NoMatchingPattern`, `ScopeTableFull`, `PatternTooComplex`,
`EllipsisCountMismatch`, `EllipsisDepthMismatch`,
`EllipsisNoPatternVariable`, `TransformerFailed`, `OutOfMemory`.
`expandAndCompileMacroUse` maps them: the ellipsis and no-match errors to
`InvalidSyntax`, the two table limits to `InternalLimit`,
`TransformerFailed` through `recordTransformerFailure` so the transformer's
real message reaches the diagnostic. The user-visible codes are `KP2001`
(invalid syntax), `KP2002` (syntax error — `syntax-error` or no matching
rule) and `KP2003` (expansion limit); [diagnostics.md](diagnostics.md) owns
the registry.

## Tests

| Suite | Covers |
|-------|--------|
| `src/tests_macros.zig` (91) | patterns, templates, hygiene basics, transformer failures |
| `src/tests_macros_nested_sr.zig` (11) | macro-generating macros and the usertext marker |
| `src/tests_macros_procedural.zig` (26) | SRFI 211 `rename`/`compare`, re-entrancy, cycles |
| `src/tests_macro_chains.zig` (4) | the head-position chain loop and both limits |
| `src/tests_ellipsis.zig` (12) | depth, counts, SRFI 149 relaxations, #1791 |
| `src/tests_prescan.zig` (12) | the `set!` pre-scan budget and truncation |
| `tests/scheme/hygiene/` (23 files) | end-to-end hygiene: `arg-vs-free.scm`, `free-global-vs-arg-1832.scm`, `def-env-redefinition-1812.scm` + `lib1812/`, `quote-identifier-1801.scm`, `macro-fresh-global-readback-1829.scm`, … |
| `tests/scheme/srfi/srfi148.scm`, `srfi211.scm`, `srfi150.scm`, `srfi257.scm` | the heaviest consumers; SRFI 257 is the one that finds scope bugs nothing smaller reaches |

Before filing an expander bug from a macro repro, run the repro through
chibi-scheme: a bare `...` where `(... ...)` was meant, or an unquoted
final template in an `em-syntax-rules` chain, has produced more than one
"deep engine bug" that was the repro (#1787, #1828). And the unit suite
must stay green under `zig build test -Dgc-stress=true`; expansion
allocates freely and the rooting discipline in `expandProceduralMacro` and
the injection walks is what the stress build checks.

## What this design cannot do

- **`syntax-case`, `datum->syntax`, syntax objects.** A bare symbol with an
  encoded name carries no lexical context to transfer or inspect. Adding
  them means replacing the representation, not extending it (KEP-0007).
- **Source-location introspection from a macro**, for the same reason.
- **A distinguishable wrapper for bare rename products** (which would fix
  `compare`'s one undecidable shape and make `ir-macro-transformer`
  possible): the compiler's bare matching of the reserved forms macros emit
  depends on those symbols being the plain interned object.
- **Phase separation.** Procedural transformer bodies are evaluated in the
  global environment at definition time and cannot see runtime locals.
