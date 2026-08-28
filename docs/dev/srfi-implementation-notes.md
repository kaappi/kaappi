# SRFI implementation notes

A narrative record of how each non-trivial SRFI is implemented in Kaappi: what
needed engine changes, what is portable Scheme, which spec ambiguities were
resolved and how, and which bugs each port surfaced. Written to be read *before*
touching one of these libraries, not as reference documentation for using them.

Companions:

- `docs/dev/srfi-exclusions.md` — the 30 SRFIs that are deliberately not implemented, and why
- `kaappi features --json` — what this build actually reports at run time
- `docs/dev/srfi-status-check.md` — how to re-derive the counts after a release

## What ships

178 SRFIs supported. 12 built-in (Zig primitives): 1, 9, 13, 18, 39, 69, 133,
170, 192, 254, 258, 260. 162 portable R7RS .sld files loaded on demand via
`(import (srfi N))`, plus SRFI 261 (Portable SRFI Library References) as an
import-resolver convention with no library file, and SRFI 226, SRFI 160, and
SRFI 211 (see below) as sub-libraries only with no bare `(srfi 226)`/`(srfi
160)`/`(srfi 211)` file (so none appears as a bare number in `kaappi
features`' scan): 0, 2, 4, 5, 6, 7, 8, 11, 14, 16, 17, 19, 23, 25, 26, 27, 28,
29, 30, 31, 34, 35, 36, 37, 38, 41, 42, 43, 44, 45, 46, 48, 51, 54, 57, 59,
60, 61, 62, 63, 64, 66, 67, 70, 71, 74, 78, 86, 87, 90, 94, 95, 98, 101, 111,
112, 113, 115, 116, 117, 118, 120, 123, 125, 126, 127, 128, 129, 130, 131,
132, 134, 135, 136, 137, 139, 140, 141, 143, 144, 145, 146, 147, 148, 149,
150, 151, 152, 153, 156, 158, 161, 162, 164, 165, 166, 167, 168, 169, 171,
173, 174, 175, 178, 180, 181, 185, 188, 189, 190, 193, 194, 195, 196, 197,
201, 202, 203, 207, 209, 210, 213, 214, 215, 216, 217, 219, 221, 222, 223,
224, 225, 227, 228, 229, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240,
241, 242, 244, 247, 248, 250, 251, 252, 253, 255, 257, 259, 263, 264, 267,
270, 271. Sub-libraries: (srfi 146 hash), (srfi 171 meta), (srfi 166 pretty),
(srfi 166 columnar), (srfi 166 unicode), (srfi 166 color), (srfi 211
explicit-renaming), (srfi 211 define-macro), (srfi 211 syntax-parameter),
(srfi 226 control prompts), (srfi 226 control continuations), (srfi 226
control times), (srfi 254 ephemerons), (srfi 254 guardians), (srfi 254
transport-cell-guardians), (srfi 254 ephemerons-and-guardians), (srfi 257
misc), (srfi 257 box), (srfi 257 rx), (srfi 263 syntax), (srfi 271
randomized), (srfi 271 determinized), (srfi 248 primitives).

## Per-SRFI notes

### SRFI 170 — POSIX API

SRFI 170 is one of the 12 built-in SRFIs: all its procedures are Zig
primitives in `src/primitives_filesystem.zig` and export directly from the
`(srfi 170)` library (there is no `lib/srfi/170.sld`). Three things about
this implementation are worth knowing when editing it:

- **The posix-error protocol is errno-on-the-condition** (#1978).
  `posix-error?`, `posix-error-name` and `posix-error-message` read a
  `posix_errno` field on the `ErrorObject`. The raise helper `raiseFileError`
  snapshots `std.c._errno()` on entry — before any allocation or further
  libc call can clobber it — and every SRFI-170 syscall-failure site funnels
  through it, so ENOENT/ENOTDIR/EACCES/ELOOP/ENAMETOOLONG are all
  distinguishable from Scheme. Raise sites that never ran a syscall (the
  embedded-NUL pre-check, "symlink target too long", Windows-unsupported
  stubs) pass errno 0 explicitly via `raiseFileErrorCode`, so
  `posix-error?` stays false for them. `posix-error-name` derives the symbol
  by scanning `std.c.E`, which exists as an enum on every target we build
  (darwin, linux, the BSDs, windows, wasi) but is `void` on the switch's
  `else` platforms — guard that case. `posix-error-message` calls
  strerror(3). The errno survives a thread-boundary copy: the
  `gc_deep_copy.zig` `.error_object` arm carries `posix_errno`.

- **Argument-range validation is KP3007, not a file error** (#1978). The
  mode/uid-gid/nice/prefix range checks validate an argument of acceptable
  type, so they raise through `raiseArgError` — a `.general` condition
  stamped `.invalid_argument` — and answer `#f` to `file-error?`. The
  message text is unchanged from the old file-error wording.

- **Every variadic signature declares its upper bound.** The SRFI-170
  procedures use the `.range` arity (`create-temp-file` 0..1, `file-info`
  1..2, `set-file-times` 1..3, …) rather than unbounded `.variadic`, so
  surplus arguments are an arity mismatch instead of being silently
  ignored (#1977). `set-file-times` also enforces the spec's
  "exactly one time is an error" rule in the body. `file-info`,
  `user-info` and `group-info` are pure value records and are copied by
  value across the SRFI-18 thread boundary; only `directory-object` among
  the SRFI-170 types is genuinely uncopyable (it owns a live `DIR*`).

### SRFI 226 — Control Features

SRFI 226 (Control Features) is a 12-sub-library spec with no default/main
library of its own (every feature lives under a named sub-library per its own
spec); only the three `control` sub-libraries listed above (a reduced,
escape-only continuation-prompt subset) are implemented — see the header of
`lib/srfi/226/control/prompts.sld` for what's out of scope and why — so unlike
every other portable SRFI it never appears as a bare number in `kaappi
features`' scan (kaappi#1517 scans `lib/srfi/*.sld` non-recursively, matching
what actually ships). SRFI 257's `rx` sublibrary layers regexp match patterns
over SRFI 115 and SRFI 264 (`(~/ "([a-z]*):([0-9]*)" s name num)`); it is a
verbatim port apart from the reference's missing `regexp-search-all`, which
`~/all+` calls (see the header of `lib/srfi/257/rx.sld`). Its reference suite
is what drove SRFI 115's matcher to a backtracking CPS engine (#1679): `%run`
now offers each way a node can match to a continuation instead of returning
one possessive answer, so `(regexp-matches (rx (* any) "b") "ab")` succeeds,
`*?`/`??`/`**?` work, and a single-character repetition body still scans
iteratively (`%run-rep1`) so `(* any)` over a long string costs no stack.
kaappi#1681 then closed the remaining SRE gaps: look-behind (`%run-behind` scans
backwards, floored at the search `start` that `%run` now threads alongside
`end`), `grapheme`/`bog`/`eog` (UAX #29 clusters via
`%gcb`/`%gcb-join?`/`%grapheme-end`), the `title-case` and `symbol` char sets,
`&`/`-` set operators (every `<cset-sre>` compiles to a node `%match-one`
decides, so `~`/`&`/`-` never re-enter the backtracking matcher), a real
`w/ascii`/`w/unicode` context (a compile-time flag in the `%make-ctx` box, not
a runtime one — SRFI 115 scopes it to char sets, so `%cm` is untouched),
`w/nocapture`, submatch lookup by `(-> name …)` symbol, and bare `word` as a
whole word rather than one word-constituent character. The three Unicode
properties `(scheme char)` cannot answer — Lt, S\*, and the UAX #29 break
classes — ship as range tables *inside* the portable `.sld`, generated by
`tools/gen_srfi_charsets.py --target 115`; regenerate them on a Unicode
version bump and keep the version in step with `tools/gen_unicode_tables.py`.

### SRFI 189 — Maybe and Either

SRFI 189 (Maybe and Either: optional container types, #2087) is a port of the
sample implementation by Wolfgang Corcoran-Mathe, with the full 82-identifier
surface of the final spec. A Just, Right, or Left container may hold zero or
more payload objects, stored internally as a list, so a Just with no payload
differs from Nothing (success with no values). `nothing` is a procedure
returning the unique Nothing object, as the spec requires. Signatures follow
the spec exactly, including the ones the earlier partial implementation got
wrong: `maybe-ref`/`either-ref` take a required `failure` procedure and an
optional `success` (default `values`); `maybe-bind`/`either-bind` are variadic
in the mprocs, short-circuiting Nothing/Left immediately (the spec defines the
result as if `maybe-compose`/`either-compose` had been applied to the mprocs,
but the implementation inlines a local loop over them through
`maybe-ref`/`either-ref` rather than calling compose);
`either-filter`/`either-remove` take `obj ...` for the Left payload;
`values->maybe`/`values->either` invoke a *producer* thunk rather than taking
bare values. The whole spec surface is pinned by
`tests/scheme/srfi/srfi189-audit.scm` (232 assertions, including the three
monad laws and both functor laws asserted as properties over five payload
values) plus the older `srfi189.scm`. The syntax group (`maybe-if`, `maybe-and`,
`maybe-or`, `maybe-let*`, `maybe-let*-values`, `either-guard`, …) is portable
`syntax-rules`; the macro templates reference library-internal bindings
(`unspecified`, `nothing-obj`, `%guard-value`, `maybe-bind`, `either-bind`,
`singleton?`, `just-objs`, `right-objs`), which hygiene
resolves to the defining library. `%`-prefixed helper names are fine here —
since v0.22.1 they are not reserved against user libraries (kaappi#1856).

The list-protocol procedures (`maybe->list`, `either->list`, `maybe->list-truth`,
`either->list-truth`) return a copy of the payload rather than the internal
list, so mutating a result cannot corrupt an immutable container (the spec
makes mutating these results an error, and the copy keeps that guarantee
structural rather than merely conventional).

One engine interaction is worth knowing before touching `exception->either` or
`either-guard`: they are built on R7RS `guard`, and kaappi's `guard` has a
documented known deviation (see `compileGuard` in `src/compiler_advanced.zig`)
— when no clause matches, the re-raise happens in the guard's own dynamic
environment and does not resume the original `raise-continuable` site with the
outer handler's return value. Matching raises are still caught into a Left and
non-matching raises still propagate (both pinned in the audit), but the
continuable-resume edge case that the reference suite's
`with-exception-handler`/`raise-continuable` check exercises cannot work until
that engine deviation is addressed.

### SRFI 14 — character sets

SRFI 14 (character sets) uses the same generator (`--target 14`) for the same
reason, and for more categories: a char set is an inversion list of `(lo .
hi)` code-point pairs and every standard `char-set:*` constant is a literal
built from a category table, never from a scan over `(scheme char)` — a scan
costs ~0.14s per predicate, and memoising one lazily is unsafe here, since a
child SRFI-18 thread forcing the memo writes a child-heap value into a
parent-heap record that dangles after the join (kaappi#1895). Consequence
worth knowing: `char-set:letter` is L* while `char-alphabetic?` is the broader
Alphabetic property, and `char-set:digit` is all 680 of Nd while
`char-numeric?`'s hand-written table covers only the 370 in the BMP.

### SRFI 254 — ephemerons and guardians

SRFI-254 (ephemerons and guardians) needs GC integration — its weak-reference
marking/resurrection lives in `gc_collect.processWeakRefs`, its heap types
(`Ephemeron`, `Guardian`, `TransportCell`) in `types.zig`, its primitives in
`primitives_srfi254.zig`, and guardian invocation (a guardian is callable) in
`vm_calls.invokeGuardian`. On this non-moving collector `current-hash` is a
stable identity hash and transport cell guardians are degenerate in one
direction only: keys never move, so a cell is never transported and `(tg)`
always yields #f — but a cell's key is still weakly holding and the cell
still breaks when the key is reclaimed (#2006). Guardian resurrection follows
the spec's "weakly resurrected" hypothetical exactly (#2011): ready-queue
contents and freshly resurrected elements are kept alive (a per-collection
`weak_resurrected` set, materialized into real marks once every weak decision
is made) without ever counting as reachable, so N guardians watching one
object all fire in the same collection instead of the first starving the rest.

### SRFI 258 — uninterned symbols

SRFI 258 (uninterned symbols) is built-in: `string->uninterned-symbol` and
`generate-uninterned-symbol` allocate via `GC.allocUninternedSymbol`
(gc_alloc.zig), which bypasses the intern table so the result is an ordinary
collectable object never `eqv?` to any other symbol; the `Symbol.interned`
flag (types.zig) drives `symbol-interned?` and the unreadable
`#<uninterned-symbol …>` printer form that `read` rejects. Equality needs no
special code (symbols already compare by identity), and `gc_deep_copy`
preserves uninterned-ness across SRFI-18 thread boundaries.

### SRFI 260 — generated symbols

SRFI 260 (generated symbols) is built-in but needs no engine integration
beyond one primitive (`generate-symbol` in `primitives_srfi260.zig`).
Kaappi *does* have uninterned symbols (SRFI 258, above), so write/read
invariance is not automatic: `generate-symbol` gets it by deliberately
interning through `GC.allocSymbol` — the opposite choice from SRFI 258's
`generate-uninterned-symbol`, which uses `GC.allocUninternedSymbol`. The
primitive interns a fresh `"<pretty>.<counter>.<128-bit-OS-entropy-hex>"`
name — a process-global atomic counter guarantees in-process uniqueness and
`platform.osRandomBytes` supplies the unpredictability.

### SRFI 120 — Timer APIs

SRFI 120 (Timer APIs) is portable (`lib/srfi/120.sld`) with no engine
changes: each `make-timer` spawns one dedicated SRFI-18 thread owning its
task list entirely in its own heap, coordinated purely through a `(kaappi
fibers)` control channel created before the thread starts and captured in
its thunk (the way a channel must be shared across threads —
`channel-receive` rejects one reached any other way, e.g. a top-level
`define`, since top-level bindings are shared by pointer across threads,
not deep-copied-and-re-owned the way lexical closure captures are).
`timer-schedule!`/`timer-reschedule!`/`timer-task-remove!`/
`timer-task-exists?` are synchronous request/reply (a fresh one-shot
reply channel per call) so the timer thread stays the one place a task-id
counter needs to live; `timer-cancel!` `thread-join!`s the timer's thread
before returning, both for correct resource cleanup and because not doing
so raced process/thread teardown into a nondeterministic crash during
development. **Single calling thread only** is a requirement of this
implementation: its request/reply design assumes it. This header used to
report that a second thread calling into a timer produced nondeterministic
memory corruption, blamed on an un-root-caused interaction between
multi-hop channel messages and cross-thread deep-copy. **That claim is
retired** — re-checked 2026-07-31 at v0.22.1 and again 2026-08-02 (audit
v2 phase 5A) under both ReleaseSafe and `-Dgc-stress=true`; nothing
corrupts, and the multi-hop mechanism itself survived ~4,000 nested
reply-channel round trips. A `<timer>` simply cannot reach another thread,
and it is refused by **two independent guards, not one** — the earlier
re-check credited `gc_deep_copy`'s `.fiber` rejection with closing both
entry paths, but a value reached through a top-level binding is never
deep-copied at all, so that list has no bearing on it; what refuses there
is the control channel's `Object.owner` check. Five entry paths (both
copy-route and globals-route, plus a channel payload, a task thunk closing
over a second timer, and a top-level *container*) are pinned by
`tests/scheme/srfi/srfi120-thread-boundary.scm`. The one live hazard
was **kaappi#2129**: `thread-join!` used to free the joined thread's
GC/VM while a thread it spawned was still dereferencing its fiber
handle in the joined heap, and the process died (24/30 runs) when the
creating thread was joined. Fixed in the v0.22.2 audit (a join now
retires rather than frees the resources of a thread that still has live
descendants) — but `make-timer` from inside a SRFI-18 thread still
raises the documented "uncopyable type" error at the join, since the
timer record holds a thread handle. See `lib/srfi/120.sld`'s header. SRFI 21 and 230 are excluded — see `docs/dev/srfi-exclusions.md`.

### SRFI 237 — R6RS Records, refined

SRFI 237 (R6RS Records, refined) is the one record-system SRFI needing real
engine changes: `RecordType` (`types.zig`) gained `parent`/`own_field_names`/
`own_field_mutable`/`uid`/`sealed`/`is_opaque`/`has_protocol` fields (`parent`
is the only heap pointer, traced in all three `gc_collect.zig` mark-graph
switches; the rest are raw owned bytes like the pre-existing `name` or plain
bools, needing only `objectSize`/`freeObject`/`gc_deep_copy` updates — no
field ever needs a write barrier, since `parent` is set once at allocation
and the one field written afterwards, `has_protocol`, is a bool.
`src/tests_gc_tracing.zig` pins the field inventory at comptime, so adding a
field to any heap struct fails the build until the tracing question has been
answered explicitly), and
`vm_records.zig`'s `define-record-type` desugarer gained a parallel R6RS-
clause-syntax path (`handleDefineRecordTypeR6RS`) alongside the original
R7RS one, dispatching on shape (R6RS's 2nd-position clause list vs R7RS's
`(ctor field...)`). Inheritance/`protocol` composition (including R6RS's own
worked example — a `protocol` at both parent and child levels) uses a
"materialize the parent instance via its own already-working constructor,
then re-extract its fields via `%record-ref`" strategy instead of R6RS's own
CPS-style n/p continuation threading: behaviorally identical (a
constructor's protocol runs exactly once either way) but needs no per-level
special-casing regardless of protocol/no-protocol mixing at any depth. The
`(srfi 237)`/`(srfi 240)`/`(srfi 136)`/`(srfi 131)` procedural layers (new
sub-library `(srfi 237 primitives)`, `primitives_srfi237.zig`) reuse this
same strategy in portable Scheme. Getting there needed one more engine
change: `vm_eval.zig`'s `handleTopLevelForm`/`isSpecialTopLevelForm` now
check whether a macro literally named `define-record-type` is in scope
before dispatching to the built-in handler (mirroring `compiler.zig`'s
`compileForm`, which already prioritized macros over special forms for
every *non*-top-level use — see its own comment citing SRFI 219 redefining
`define`) — without this, no portable library could ever give that name new
meaning via `define-syntax`, since the top-level dispatch checked for the
literal name unconditionally. Library-body use of a shadowing
`define-record-type` (`compiler_lambda.zig`/`vm_library.zig`'s separate
scanning path) was documented here as an un-closed gap; **it works as of
v0.22.1** — a `.sld` body that shadows the name via `define-syntax` binds
the shadowed definition, same as at top level. When testing this, bind a
name that comes from the macro's **pattern**, not one introduced by its
template: a template-introduced name is hygienically renamed, so the
binding is invisible from outside and the test looks like a failure for
an unrelated reason. kaappi#1974 then fixed four R6RS §6.3 deviations in
the procedural/inspection layers, all of them in `lib/srfi/237.sld` rather
than the engine: `record-type-field-names` returns a **vector** (the
`%record-type-field-names` primitive still answers with the list every
internal index walk wants — SRFI 57/131/136/150 call the primitive
directly for that reason, and so does this library); an integer `k` for
`record-accessor`/`record-mutator`/`record-field-mutable?` is
**own-field-relative**, per "note that k cannot be used to specify a field
of any type rtd extends" (it was read as absolute, silently returning an
ancestor's field — and disagreeing with `record-field-mutable?`, whose own
`k` was already own-relative; SRFI 137's payload accessor relied on the
bug and now asks by name, since a subtype there declares zero own fields
and so has no valid `k` at all); `opaque` is enforced (`record?` → `#f`,
`record-rtd` raises, and opacity is inherited from an opaque parent — the
inheritance is folded in at *construction* by
`primitives_srfi237.effectiveOpaque`, shared by both creation paths, so
`RecordType.is_opaque` stays the single already-effective answer); and
`record-mutator` rejects an immutable field. The deprecated
`make-record-constructor-descriptor`/`record-constructor-descriptor?` and
the 7-argument `make-record-descriptor` were added at the same time.
A record descriptor is now accepted **wherever an rtd is expected** (the
SRFI's "the type of record descriptors is a subtype of the type of
record-type descriptors"), and conversely `record-constructor` accepts a
bare rtd — which matters because a syntactic `define-record-type`'s
<record name> evaluates to a simple rtd, not the record descriptor SRFI
237 specifies. A protocol lives on the *descriptor*, so synthesizing a
protocol-less one from an rtd would silently bypass it; instead
`%record-type-constructor` recovers the finished, protocol-applied
constructor the desugarer already bound under its fixed
`__record_ctor_<name>` alias, after checking the sibling
`__record_type_<name>` alias still names *that* rtd (both alias names are
spelled with a leading space, so no source identifier can collide with
them, and both are keyed by type name, so a generative redefinition
rebinds them). When it cannot be
recovered and `RecordType.has_protocol` says there is one, it raises
rather than constructing a wrong record. That combination is what makes
the SRFI's own worked Examples section run — a procedural type inheriting
from a syntactic one whose construction a protocol governs.

`VM.record_uid_registry` — the map that makes `nongenerative` mean
anything — is a `StringHashMap` that **does not own its keys**, so every
insert must supply a key that outlives the entry. There are three inserts
and they must all key off the *rtd's own* `RecordType.uid`, an owned copy:
`gc_deep_copy.zig` always did, `vm_records.zig`'s syntactic path gets away
with an interned symbol's name (interned symbols are permanently rooted),
and the procedural `%make-record-type-descriptor` keyed off the uid
argument's `SchemeString` bytes until kaappi#2161. That string is transient
— `lib/srfi/237/base.sld` makes it fresh with `symbol->string` on every
call — so ordinary allocation between two same-uid definitions collected it,
the key dangled, the lookup missed, and the second definition quietly built
a second, non-interoperable type for one uid. Silent, and only on the
procedural path.

### SRFI 137 — Minimal Unique Types

SRFI 137 (Minimal Unique
Types) is pure portable Scheme built directly on `(srfi 237)`: a "subtype"
is exactly SRFI 237's `parent` relation, with every level correctly
sharing the ROOT type's single payload field (a subtype's own rtd adds
*zero* new fields, inheriting the root's one field via the parent rtd/rcd
chain — an earlier draft gave every level its own field instead, which was
a bug; worth remembering if this file is touched again). SRFI 136
(Extensible record types) demonstrates the CPS-style introspection macro
its spec is built around — `(<type-name>)` yields the type's own rtd,
`(<type-name> (<keyword> <datum>...))` splices that type's own literal
`parent` keyword and field-specs into a call to `<keyword>` — needing no
identifier synthesis at all (it only ever replays syntax already captured
hygienically).

### SRFI 131 — ERR5RS Record Syntax, reduced

SRFI 131 (ERR5RS Record Syntax, reduced) layers on the same
substrate with by-*name* (not positional) constructor field resolution,
including a subtype field shadowing an ancestor's same-named field per its
own spec text. Two portability gotchas surfaced repeatedly while building
these three, and both turned out to be one engine bug, fixed in
kaappi#1831: (1) calling a `%`-prefixed primitive from `(srfi 237
primitives)` with no explicit import looked *unreliably* ambient — it
worked in some positions and not others; (2) calling one `%`-prefixed
forward-referenced global as a direct, non-tail-position argument
expression to another (e.g. inside `if`/`list`, or as an argument nested
one level deep) inside a closure passed to `map` raised a spurious
"undefined variable" for the *inner* call, reliably worked around at the
time by routing through an extra wrapper function (any name) called in
tail position. Both were the same thing: a library body's reference to a
global that lives in vm.globals but not in its own lib_env resolved in
tail position only, because `get_global` carried the vm.globals fallback
and the `call_global` superinstruction the compiler emits for every
non-tail call did not. Ordinary (non-`%`) names looked unaffected only
because `(scheme base)` puts them in lib_env; all three global-reference
opcodes now resolve through one helper (`lookupGlobalLocked`, now in
`vm_dispatch_helpers.zig`). That fix left
one residual, closed in kaappi#1860: the fallback is gated on
`Function.restricted_globals`, which was derived per-function, so it was
off for the outer function of each library-body form and on for every
closure inside it — the same reference resolved from inside a `lambda` and
raised `undefined variable` as a library-body *top-level* `define`'s
initializer. It is now a property of the environment
(`compiler.EnvKind`, inherited by `Compiler.initChild`), which also stops
a restricted `(environment ...)` from leaking vm.globals through a
closure. Declaring the import explicitly is still the better style, but it
is no longer load-bearing.

### SRFI 57 — Records, with inheritance via schemes

SRFI 57 (Records, with inheritance via "schemes" -- a named, reusable field-
label list a type or another scheme can extend, with multiple schemes
mergeable at once via left-to-right append + delete-duplicates) is portable
(`lib/srfi/57.sld`) but deliberately does NOT port its own reference
implementation's technique: that reference compares field-label identifiers
at macro-expansion time via the standard `let-syntax`-plus-literals-list
"if-free=?" trick. A third expander bug surfaced while attempting this
port: a `let-syntax` anywhere in an expansion chain that eventually
produced a `define-syntax` form failed to compile outright, reproduced
down to a two-line `(let-syntax (...) (define-syntax ...))`. **That is
fixed as of v0.22.1** — the two-line repro compiles and runs. SRFI 57's
design below was chosen while it was live and has not been revisited;
it remains the better design on its own merits (see the end of this
paragraph), so this note is history, not a TODO. SRFI 57 sidesteps it:
field labels become ordinary
quoted symbols and every list merge/dedup/lookup happens at plain run time
(`assq`/`memq` over symbol lists) instead of macro-expansion time — a
scheme or type name is bound with plain `define` (not `define-syntax`) to a
`(field-symbols rtd-or-#f ancestor-schemes)` list, with no CPS introspection
macro and no identifier comparison anywhere in the file. This is simpler
than the reference design, not merely an engine-avoidance workaround, and
completes issue #1695 (all 9 of its SRFIs now shipped or excluded). Scheme
conformance is NOMINAL, not structural: a record's actual rtd carries no
field for this library's own scheme metadata, so a type's declared ancestry
(computed once, transitively, at `define-record-type` time) lives in a side
table keyed by rtd (`%srfi57-registry`) — an earlier structural draft ("does
the record's actual rtd merely have every field the scheme needs") let any
same-shaped-but-undeclared type pass every scheme predicate/accessor and
`record-update`/`record-compose` target check, caught by a second review
pass. `record-update`/`record-update!`/`record-compose` all validate their
target/import/export type-or-scheme and field-label arguments at call time
(not the spec's stated expansion time — these are ordinary values, not
macros, so their identity isn't knowable until the code runs); this and the
missing labeled-record-expression syntax (`(type-name (label expr)...)`,
which would need every type/scheme name to be a macro instead) are the
remaining documented, deliberate scope reductions. The same review pass
also found a real, severe, PRE-EXISTING bug in `vm_records.zig` unrelated
to SRFI 57 itself: 8 places (4 already present in the R7RS
`handleDefineRecordType`, 4 new in this slice's R6RS path) paired
`no_collect += 1; errdefer no_collect -= 1;` with a manual mid-block
`no_collect -= 1` followed by *more* fallible operations still inside the
`errdefer`'s scope — a late failure double-decremented the counter,
underflowing a `u32` and permanently disabling GC for the rest of the
process. Fixed everywhere by deleting the manual mid-block decrement and
using a single unconditional `defer` instead (the pattern
`gc_deep_copy.zig` already used correctly) — this bug class (`errdefer X -=
1` plus a later, unguarded `X -= 1` of the same reentrancy counter) is
worth grepping for if `no_collect`-style guards are touched again elsewhere.

### SRFI 192 — port positioning

SRFI 192 (port positioning) is built-in:
`port-position`/`set-port-position!`/`port-has-port-position?`/`port-has-set-port-position!?`
in `primitives_io.zig` use plain exact-integer byte offsets for every port
kind (string ports already track their own position for free; fd-backed ports
get a new `platform.seek` — POSIX `lseek`, Windows `_lseeki64`, WASI
`fd_seek`, which needs its own `whence_t` enum) with the OS's raw offset
corrected for whatever this port's own software buffers have read ahead of or
not yet flushed behind; the spec's opaque textual-port position objects and
its dedicated `i/o-invalid-position-error` condition type are not implemented.

### SRFI 181 — custom ports and transcoded ports

SRFI 181 (custom ports and transcoded ports) is portable (`lib/srfi/181.sld`)
over a native primitives sub-library, `(srfi 181 primitives)`
(`.srfi_181_primitives` in `primitives.zig`, `primitives_srfi181.zig`) — the
same registry-shadows-a-same-named-.sld problem SRFI 248 hit first (see
below): `(srfi 181)` had to move off a direct registry entry once transcoded
ports needed a real `.sld` to live in. Custom ports (5 `make-custom-*-port`
constructors plus `make-file-error`) landed first, in Phase 3 (#1727);
transcoded ports (`make-transcoder`, `native-transcoder`, codecs, eol-styles,
the `raise` error-handling mode) followed in their own follow-up (#1729) once
kaappi#1727 shipped. A custom port's
read!/write!/get-position/set-position!/close/flush procedures are the first
Value-bearing fields `Port` has ever had (`Port.custom_backend:
?*CustomBacking`, `types.zig`) — and they made `Port` the one heap type whose
Values sit behind a pointer it *owns*, so five sites had to follow it: the
three `gc_collect.zig` marking switches plus the two dedicated (non-catch-all)
`freeObject`/`objectSize` arms (gc_sweep.zig), none of which has an
exhaustiveness check on the *inside* of an arm. That was five hand-kept copies
of one field list until audit v2 Phase 7A measured the cost: a third
Value-bearing field compiled clean under `zig build` and was missed by 3 of
the 5 (a bare `Value`, or one on an existing satellite) or by all 5 (a
brand-new satellite) -- each an observed use-after-free, the satellite case
leaking too. All five now derive from one enumeration in `types_port.zig`:
`forEachValue` (a visitor, so `markValueInner` keeps appending to its worklist
while `markObjectContents` recurses and `referencesYoung` short-circuits --
the reason it could not just call the old helper), plus
`satelliteBytes`/`destroySatellites` for the sweep arms. Adding a Value to
`Port` or to an existing satellite now needs **no GC edit at all**; adding a
whole new satellite is a `@compileError` until it is listed in
`types_port.satellites`. `src/tests_gc_tracing.zig` carries the mutation tests
and the field-list pin. Every callback runs through `vm.callWithArgs`, which
always executes with `vm.dispatched_from_scheduler` forced false; a callback
that tries to block is rejected with a catchable error via a dedicated
`vm.in_custom_port_callback` counter rather than risking the
native-stack-overflow a silent recursive scheduler drive would otherwise allow
— custom port callbacks must be effectively synchronous, non-blocking code.
That counter is read at three sites, and the general one is
`fiber.runSchedulerStep` (#2000): every in-place drive passes through it, so
`channel-receive`/`channel-send`/`fiber-join` and SRFI-18's
`thread-join!`/`mutex-lock!`/`condition-variable-wait` are covered without
being listed, and so is any blocking primitive added later. Until that check
existed the counter was read only in `fiber.waitForFd` and
`primitives_srfi18.threadSleepFn` — the two still check for themselves,
earlier, each having state (a registered fd, an armed timer) it is cheaper
never to arm — and all six of the above drove the scheduler recursively
instead: a whole sibling fiber ran to completion *inside* the callback, and
`n` fibers reading one such port took the process down with SIGBUS at n = 2500
(clean at 2400), well before `callReentrant`'s own `max_native_depth = 3000`
could fire, since a level here is a nested `runUntil` **plus** a drive rather
than a plain re-entrant call. Re-entrancy is a separate axis and is *allowed*:
a `read!` may read from its own port, and the bytes its inner call leaves
buffered are chronologically ahead of the ones the outer invocation then
produces. `primitives_io.takeFirstBufferingRest` — the one place all three
fills (fd burst, custom `read!`, transcoded character) hand out a byte,
**including their EOF exits** — concatenates them in that order. Each of the
three used to `assert(port.read_buf == null)` instead, and the outer burst's
size decided which way it broke: ≥ 2 bytes aborted the process uncatchably,
exactly 1 silently reordered the stream, and 0 reported `eof-object` while the
earlier bytes were still buffered, so the *next* read produced data after an
EOF (#1939). Both `readOneByte` and `portWriteBytes` (the single byte
source/sink every port primitive already funnels through) gained a custom-port
branch exploiting that Kaappi strings are already UTF-8 byte arrays
internally: a textual read!'s returned character count converts to a byte
offset via `utf8IndexToByteOffset` on the buffer's freshly re-read
`data`/`len` (never cached across the call — a differing-byte-width
`string-set!` inside the callback reallocates the whole backing buffer in
place, `primitives_string.stringSetFn`). Transcoded ports layer a second
Value-bearing field, `Port.transcode: ?*TranscodeState` (the same derived walk
covers it, with no arm of its own; `TranscodeState` holds just `wrapped_port:
Value` plus plain `Codec`/`EolStyle`/`ErrorMode` enums, no other GC-traced
fields). `readOneByte`/`portWriteBytes` gained a `transcode` branch that
decodes/encodes exactly one character per call, never a batch: a fiber park
reruns the whole native call from scratch, so any Zig-local "progress so far"
would be silently lost, while a durable `*Port` field survives the retry —
CRLF lookahead therefore reuses the wrapped port's own
`peek_byte`/`peek_extra`, the same mechanism `read-line`'s own CR/CRLF
handling already relies on, instead of a new field. The `raise` error-handling
mode needed a mechanism custom ports' callbacks never required:
`primitives_control.raiseContinuable` (factored out of `raise-continuable`'s
own native implementation) signals a continuable `.io_decoding`/`.io_encoding`
`ErrorObject` and resumes decoding from the next byte once the handler returns
— safely, because a reentrant `vm.callHandler`/`runUntil` always runs with
`dispatched_from_scheduler` forced false, so it can only block in place if the
handler itself blocks, never return `Yielded` and retry the whole call (which
would re-invoke the handler a second time for the same condition). v1 supports
only the UTF-8 codec — `latin-1-codec`/`utf-16-codec` are not exported at all,
rather than exported-but-always-erroring, since no other binding in Kaappi
exists solely to fail — and `native-transcoder` returns
UTF-8/`'none`/`'replace`, matching `read-char`'s existing no-translation,
never-raise-on-invalid-UTF-8 behavior as closely as a brand-new feature
reasonably can. Codecs/eol-styles/error-modes are plain symbols and the
transcoder itself is a portable `define-record-type` (`lib/srfi/181.sld`), so
native code never touches record internals — only the differently-named
`%transcoded-port` primitive does, receiving the transcoder's already-unpacked
codec/eol-style/error-mode symbols and validating them there
(`make-transcoder` itself does not validate eagerly; codecs are untyped
symbols, so there is no earlier point to enforce it).

### SRFI 267 — raw string syntax

SRFI 267 (raw string syntax) is a hybrid: its `#"X"…"X"` lexical syntax is built into the reader (`readRawString` in `reader_tokens.zig`), while its port procedures load from the `.sld`.

### SRFI 248 — minimal delimited continuations

SRFI 248 (minimal delimited continuations) is also a hybrid:
`with-unwind-handler`, `empty-continuation?`, and the extended two-variable
`guard` live in `lib/srfi/248.sld` as a Filinski shift/reset over `call/cc`,
built on three VM primitives (`%call-with-unwind-handler`,
`%unwind-raise-empty?`, `%pop-unwind-handler!` in `primitives_control.zig`)
exported by the built-in sub-library `(srfi 248 primitives)`. The enabling VM
change is a *sticky* exception handler (`ExceptionHandler.sticky`):
`raise`/`raise-continuable` invoke it in place without popping, so a `call/cc`
snapshot taken while it handles includes it and resuming re-arms the prompt
(reset0 semantics) — the delimiter must stay file-only because the registry
shadows a same-named `.sld`. `empty-continuation?` combines a VM tail-call
latch (`native_call_was_tail`, set by every tail-call opcode in
`vm_dispatch.zig`) with the sticky handler's frame_count baseline, so a raise
in tail position of a non-tail-called helper is correctly non-empty. Delimited
continuations are single-shot (a resume crosses the sticky-handler native
frame, the same limit as continuations captured under native drivers).

### SRFI 261 — portable SRFI library references

SRFI 261 (portable SRFI library references) is a resolver-level convention
with no library file: `(srfi srfi-<n>)` and `(srfi <mnemonic>-<n>)` (e.g.
`(srfi lists-1)`, `(srfi vectors-133)`) resolve to `(srfi <n>)` as a fallback
— literal registry/file names win, sub-library tails pass through, and the
trailing number alone is authoritative (mnemonics are not validated).
Implemented in `vm_library.zig` (`srfi261FormNumber`/`normalizeSrfiLibName` in
`processImportSet`; `libraryIsAvailableSrfi261` behind both cond-expand
`(library …)` entry points) and mirrored path-level in `test_selection.zig` so
`kaappi test --changed` keeps the dep edge. Every supported SRFI is also a
`cond-expand` feature identifier `srfi-<n>` (#1649): `(cond-expand (srfi-1 …)
…)`. These are derived, never listed — `srfiFeatureAvailable` in
`vm_library.zig` routes `srfi-<n>` through the same availability check as
`(library (srfi <n>))`, so built-in, portable, `--sandbox` and WASM answers
all match what `(import (srfi <n>))` would do. Both feature-req evaluators
consult it: `evalLibFeatureReq` (inside `define-library`) directly, and the
compiler's `evalFeatureReq` via the `globals.srfiFeatureAvailable` callback
the VM registers (mirroring the `library_exists_checker` used by the `(library
…)` form). SRFI 261 is the one supported SRFI with no `.sld`, so `srfi-261`
answers true directly. Like `(library …)` requirements, `srfi-<n>` is a
derived probe, not a bare feature, so `(features)` (and the `kaappi features`
table it must equal, #1517) stays platform-only; `kaappi features` still notes
the ids in its SRFIs section.

### SRFI 160 — homogeneous numeric vector libraries

SRFI 160 (homogeneous numeric vector libraries) is a hybrid, and the
vector-family half of issue #1694 (the array-family's own SRFI 231 has since
shipped too — issue #1694 is fully closed — and 58 stays excluded; see the "Of
the 208 final SRFIs" paragraph above for how the family actually splits, which
is not the three-mutually-incompatible-lineages shape originally assumed when
kaappi#1694 was filed): one native heap type, `types.NumericVector` (`types.zig`),
discriminated by an 11-way `NumericElementKind` enum
(s8/u16/s16/u32/s32/u64/s64/f32/f64/c64/c128) covers every element kind except
u8, which stays a plain R7RS bytevector per the SRFI's own recommendation (and
because the pre-existing SRFI 4 port already relies on `(bytevector?
(make-u8vector 5))` staying `#t`) — the same one-heap-type-with-discriminator
pattern as SRFI 237's `RecordType` extension, avoiding 11x duplication of GC
touch points. c64/c128 (complex) elements are stored as two consecutive f32s
or f64s (real, imag) packed contiguously in the raw byte buffer, decoded into
a real Kaappi `Complex` only at the `%numeric-vector-ref`/`-set!` boundary;
multi-byte elements use host-native byte order (`builtin.cpu.arch.endian()`),
since there is no reader syntax to round-trip and no cross-process
persistence. Six generic `%`-prefixed primitives in `primitives_srfi160.zig`
(registered under `.srfi_160_primitives`, the same
registry-shadows-a-same-named-.sld precedent as `.srfi_237_primitives`) —
create/predicate/kind/length/ref/set! — are the *entire* native surface; every
named procedure (the SRFI-4-shaped 9-procedure core per type, plus SRFI 160's
much larger SRFI-133-shaped extended surface —
map/fold/filter/unfold/copy!/append/generator/comparator/etc.) is portable
Scheme in `lib/srfi/160/base.sld` + one `lib/srfi/160/<tag>.sld` per type. The
extended surface is written *once*, generically, in `(srfi 160 base)`:
low-level dispatch helpers
(`%uvec-ref`/`%uvec-set!`/`%uvec-length`/`%uvec-make`) branch on `bytevector?`
vs. `%numeric-vector?`, so the same ~25 generic procedure bodies serve all 12
kinds including u8 — each per-type library just renames the kind-agnostic ones
(fold, for-each, index, swap!, ...) directly and wraps the kind-constructing
ones (map, copy, filter, unfold, ...) in a one-line closure fixing that type's
kind symbol via R7RS's `(import (rename (srfi 160 base) (old new) ...))`,
which (per `vm_library.zig`'s `processImportRename`) imports *everything* from
the wrapped library with only the listed pairs renamed — not just the renamed
subset — so the per-type file's own kind-closing wrappers can call the
unrenamed generics directly without a second import clause. `(srfi 4)` is now
a thin re-export over `(srfi 160 <tag>)` for the 8 non-complex-non-160-only
names (fixing a real bug the old wrapped-vector implementation had: f32vector
didn't actually truncate to 32-bit precision).

### SRFI 66 — octet vectors

SRFI 66 (octet vectors) and SRFI 74 (octet-addressed binary blocks, "blobs")
are both u8vector/bytevector aliases needing zero heap-type work: SRFI 66
re-exports `(srfi 160 u8)`'s core plus new logic for `u8vector-copy!`'s
different argument order and `u8vector=?`/`u8vector-compare`; SRFI 74's blobs
are bytevectors, with `blob-uint-ref`/`-set!` et al. implemented as
byte-at-a-time Horner assembly (floats are explicitly out of SRFI 74's own
scope). `(endianness native)` is the one place either SRFI needed a genuinely
new primitive: `%host-big-endian?` (`primitives_r7rs.zig`, wrapping
`builtin.cpu.arch.endian()`) — a portable implementation has no other way to
learn real hardware byte order, and this SRFI's native-tagged accessors exist
specifically for interop with externally-produced binary data, so assuming
little-endian would be silently wrong on kaappi's own s390x/ppc64le targets.

### SRFI 25 — multi-dimensional array primitives

SRFI 25 (multi-dimensional array primitives), the first piece of #1694's array
family, is pure portable Scheme (`lib/srfi/25.sld`) needing no engine work at
all: arrays are spec-defined as heterogeneous (arbitrary Scheme objects, no
relationship to SRFI 4/160's numeric vectors), so a `define-record-type`
wrapping a plain vector is spec-sufficient. A shape is a vector of `(lower .
upper)` pairs (deliberately not made to satisfy `array?` itself — the spec's
own "a shape is a d-by-2 array" framing is Rationale prose never operationally
exercised by any of the 10 mandated procedures, since there is no `shape?` and
no way to recover a shape back from an array). The one array record type
covers both "simple" arrays (a row-major-ordered backing vector) and
`share-array`'s affine views (a base array plus an index-translation `mapper`,
no backing vector of its own): `array-ref`/`array-set!` on a view translate
the requested index through `mapper` and recurse into the *base array's own*
ref/set! rather than poking its raw vector directly, so arbitrarily nested
views (a view of a view of a view) compose correctly for both reads and writes
at the cost of one extra call per nesting level — the spec's rationale for
requiring `mapper` to be affine is that composed affine maps *could* be
collapsed to O(1), but this is a documented optimization opportunity, not a
conformance requirement, and recursive delegation was the simpler,
fully-conformant choice. The one point in the spec genuinely left ambiguous by
its prose alone — whether `share-array`'s `mapper` receives/returns indices as
separate arguments or a packed list/vector — was resolved by fetching the
spec's own worked example (a diagonal-view identity-matrix construction using
`(lambda (k) (values k k))`): `mapper` takes the new array's indices as
separate variadic arguments and returns the base array's coordinates via
multiple values, exactly mirroring `array-ref`/`array-set!`'s own variadic
calling convention; that identity-matrix example is now a verbatim regression
test. `array-ref`/`array-set!` also accept a single packed index that is a
vector or a 0-based 1-dimensional array (dispatched by argument count and
type), and `array-set!`'s new-value argument is the *last* argument after all
indices — the opposite convention from SRFI 47/63, which is the documented
reason those two lineages don't compose (see the "Of the 208 final SRFIs"
paragraph above).

### SRFI 164 — enhanced multi-dimensional arrays

SRFI 164 (enhanced multi-dimensional arrays), the second piece, is a
documented, compatible *extension* of SRFI 25 (identical shape representation,
`share-array` copied from 25's spec text verbatim) implemented as its own
independent library (`lib/srfi/164.sld`) rather than by importing `(srfi 25)`,
since `define-record-type` field accessors don't cross library boundaries and
this SRFI's array needs a third mode SRFI 25's record has no room for. One
record covers three modes: "simple" (own row-major vector, same as 25),
"shared/view" (base array + index-translation `mapper`, same
recursive-delegation design as 25's `share-array`), and "virtual" (a
`getter`/optional-`setter` pair, no backing storage at all — backs
`build-array`, `index-array`, and `array-index-ref`'s non-scalar case).
`array-transform`'s `transform` argument uses a *different* calling convention
than `share-array`'s `mapper` per the spec's own explicit contrast (one vector
argument in, one vector out, vs. separate variadic arguments and multiple
values) — adapted with a one-line wrapper into the shared/view mode's own
convention, which works unmodified for a non-affine `transform` since this
codebase's `share-array` never checked or exploited affineness in the first
place. `array-index-ref`/`array-index-share` (APL-style generalized indexing,
where each of an array's per-dimension indices is either an integer or an
array) share one resolver (`%index-shape-parts`/`%index-take`) computing the
concatenated result shape and an index-splitting closure; both were written as
flat, separately-named top-level helpers rather than nested internal defines
after a deeply-nested first draft produced a mis-balanced closing-paren count
that silently ate several nesting levels (`kaappi check` catches this class of
bug immediately — always run it on a new portable library before executing
it). A second, subtler bug from that same draft: the resolver closure was
defined with a rest parameter (`(lambda new-indices ...)`) but every call site
passed an *already-built* list as a single argument (`(resolver
new-indices)`), silently wrapping it one list-level too deep and producing
wrong-looking "index out of range" errors far from the actual mistake — fixed
by making the resolver take one fixed parameter instead of a rest parameter,
since none of its callers were ever splatting separate arguments into it.
`array-reshape` aliases the source's backing vector directly when the source
is simple (per spec: "uses the same underlying vector as array") but falls
back to a shared/view array with a row-major-rank-based recompute
(`%row-major-offset` composed with its own inverse, `%unrank`) when the source
is not simple — this recompute is not affine, which the shared/view mode's own
lack of an affineness check already makes safe. `array->vector` returns the
live backing vector for a simple array (true zero-copy identity) but only a
disconnected snapshot copy for a non-simple one — the spec calls for a live
view there too, which a literal R7RS vector cannot provide in portable Scheme
(vectors have no hooks, unlike this codebase's custom ports) — a deliberate,
documented scope reduction, unlike `array-flatten`, which the spec itself
mandates as always a fresh copy regardless of source mode.

### SRFI 166 — Monadic Formatting

SRFI 166 ships as six libraries: `(srfi 166 base)` holds the entire state
model and formatting core, and `(srfi 166)` re-exports base plus the four
sub-libraries (`pretty`, `columnar`, `unicode`, `color`) from
`lib/srfi/166/`. The #2292 rewrite put every state variable, `fn`/`with`
macro, and formatter on one architecture: a state variable is a record
carrying name/default/immutable (so `make-state-variable` is the real spec
extension point, and `with!` errors on an immutable one because the spec
allows "only dynamically bound with with"), the formatting state is a hash
table keyed by the state-variable *object*, formatters mutate the state in
place, and `with` restores exactly the variables it bound — which is why
`col`/`row` survive a `with` while `forked`/`call-with-output` snapshot the
whole table with `hash-table-copy`. Three constraints from that file that
are invisible from the code and easy to break:

1. **The writer streams token by token, and that is load-bearing.**
   `%write-stream` calls `(emit string)` for every token ("(", each element,
   separators, ")") rather than building one string; `written` and friends
   thread each chunk through the `output` state variable. This is what makes
   `trimmed/lazy` implementable at all: it installs a counting `output` hook
   and, when the width budget is spent, unwinds the *generator itself* via a
   `call/cc` escape — the spec's only mechanism that is "safe to use with an
   infinite amount of output, e.g. from written-simply on an infinite
   (circular) list". Regressing `%write-stream` back to whole-string
   accumulation reinstates a hard KP3008 stack overflow on that case (the
   audit pins it). Two related details: the list/vector spines are written
   tail-recursively (a 50k-element list must not overflow), and
   `trimmed/lazy` must restore the `output` binding on its escape path by
   hand — a plain `with` skips its restore on a non-local exit, which would
   strand the counting hook in the state for every later formatter.
2. **`extract-shared-objects`' exit-event timing is the cycle/sharing
   distinction.** The walk is an explicit enter/exit worklist (again so long
   lists don't consume stack). An entry survives the `cyclic-only?` deletion
   only if it was revisited *before* its first visit completed — that is a
   cycle, kept for `written`'s datum labels; plain acyclic sharing re-visits
   only after the exit event deleted the entry, so it re-counts from one and
   `written` prints it duplicated, exactly like `write`, while
   `written-shared` keeps it. Moving the delete earlier (e.g. to make the
   cdr walk a tail call) misses cycles and hangs the writer on circular
   data; moving it later labels sharing under plain `written`, which the
   spec reserves for `-shared`.
3. **Label numbers are assigned at first emission, not by the walk.** The
   count stored in the shared table is a placeholder; `%gen-shared-ref`
   overwrites it from a counter at the moment the label is first printed,
   so numbering follows output order (`#0=` then `#0#`) regardless of hash
   iteration order.

A test-harness trap worth knowing: the library search order is explicit
`--lib-path`, then the auto-added script dir, `~/.kaappi/lib`, and the
exe-relative `zig-out/lib`, all *before* the cwd `lib/` fallback — so an
installed or previously-built copy silently shadows edits to the source
tree, and `zig build` (which re-installs `lib/` into `zig-out/lib`) must be
rerun after every `.sld` edit. The shell suites isolate this with a temp
`KAAPPI_HOME`; do the same when running
`tests/scheme/srfi/srfi166-audit.scm` by hand.

### SRFI 63 — homogeneous and heterogeneous arrays

SRFI 63 (homogeneous and heterogeneous arrays), the third piece of #1694's
array family, supersedes SRFI 47 outright (47's own page says so; see
`docs/dev/srfi-exclusions.md`), so only 63 is implemented (`lib/srfi/63.sld`)
— confirmed incompatible with SRFI 25/164 by both SRFIs' own Issues sections:
`array-set!`'s new-value argument is *second* here (right after `array`,
before any indices), the opposite of 25/164's value-last convention, and
`make-array`'s first argument is a *prototype* (a type/fill-value carrier — an
array, vector, string, or one of 20 dedicated type-tag generator procedures
like `A:fixZ8b`/`A:floC128b`, confirmed against the spec's own list), not a
bounds-shape object; every dimension is a plain zero-based size, with no
arbitrary lower bounds and no shape object at all. The one `<uarray>` record
covers two modes: "simple" (a `kind` symbol dispatches, via a small table
built once at load time, to the accessor closures for that element type) and
"shared" (a base array plus an index-translating `mapper`, the same
recursive-delegation design as 25/164 — translate through `mapper`, then
recurse into the *base array's own* ref/set!, so nested views compose
correctly for both reads and writes regardless of rank change). 12 of the 20
prototype kinds reuse this codebase's own already-shipped `(srfi 160 <tag>)`
procedure sets (or a plain bytevector for the 8-bit unsigned case, matching
u8's treatment throughout this codebase) as the backing store, getting every
homogeneous-type conversion error (non-integer into a fixed-width slot,
negative into unsigned, too-large, inexact into exact, non-real into a
real-float slot) for free with zero new validation code; the remaining 8 kinds
(16- and 128-bit floats, 16- and 32-bit complex, all 3 decimal-float widths)
have no Kaappi-native representation, so they fall back to a plain, unchecked
vector — a fallback the spec itself sanctions ("resorting finally to vector")
rather than a shortcut, since even the reference implementation calls the
decimal-float conversion rules "yet to be determined." `make-shared-array`'s
`mapper` takes the new array's indices as separate variadic arguments
(matching this codebase's other array SRFIs) but — confirmed from the spec's
own worked diagonal-view and offset-view examples — *returns a list* of
old-array coordinates, not multiple values like 25/164's
`share-array`/`array-transform`; this is the one genuinely
easy-to-get-backwards detail in the whole SRFI, so it got its own explicit,
never-assumed-to-match adapter. `equal?` is a real library-level override
(array-augmented R5RS `equal?`): the library imports `(scheme base)`'s
`equal?` under a rename, defines its own that delegates to the original for
the non-array case, and exports the override — verified directly (a throwaway
test library) that this shadows `equal?` only for code that imports it from
`(srfi 63)`, with ordinary R7RS import-collision rules applying otherwise, so
no engine change was needed. `list->array`/`array->list` and
`vector->array`/`array->vector` turned out to need two genuinely different
algorithms, not one shared "row-major fill" — confirmed by fetching the spec's
own examples rather than assumed: `list->array rank proto list` takes a
**rank-nested** list (dimensions inferred from nesting depth and sublist
lengths, e.g. a list of 2 sublists of 2 elements each infers `(2 2)`) with
`array->list` as its exact nested-output inverse, while `vector->array vect
proto dim1 ...` takes a **flat** vector plus **explicit** dimension arguments,
like `make-array` — the two pairs are not interchangeable despite looking
parallel at first glance.

### SRFI 231 — intervals and generalized arrays

SRFI 231 (intervals and generalized arrays), the fourth and final piece of
kaappi#1694's array family, is a genuinely unrelated redesign from 25/164/63 (no
textual relationship, per its own spec) shipped across 6 phases (issues
tracked under #1694;
`lib/srfi/231/{misc,intervals,storage-classes,arrays,views,combinators,assembly}.sld`,
merged into a public `lib/srfi/231.sld` re-export hub — 118 bindings total, an
exact bijection confirmed against the reference implementation's own export
clause) — the largest single SRFI in this codebase by an order of magnitude.
An `<interval>` is two parallel exact-integer vectors (lower/upper bounds,
arbitrary — including negative — per axis), not 25/164's shape-of-pairs nor
63's bare sizes. The array hierarchy is genuinely three-tier (`array?` ⊃
`mutable-array?` ⊃ `specialized-array?`), all one record
(`domain`/`getter`/`setter`/`body`/`indexer`/`storage-class`/`safe?`, with
mode-specific fields `#f` on a plain array) rather than 25/164's
simple/shared/virtual union — confirmed as a genuine hybrid of prior
conventions on two independent axes: `array?` is disjoint from vector/string
(matching 25/164, not 63), while `array-set!`'s new-value argument is
*second*, right after the array (matching 63, not 25/164's value-last). A
storage class (17 singletons, 16 real, plus `make-storage-class` for custom
ones; only `f8` is deferred to `#f` — even the reference leaves it `#f`,
since no standard 8-bit float type exists. `u1` and `f16` are ports of the
reference's own bit-packing and software half-floats over `u16vector`) is a
9-field record
(getter/setter/checker/maker/copier/length/default/data?/data->body) that a
specialized array's `body`/`indexer` pair delegates to for the actual
backing-store representation. c64/c128 bodies follow the reference's
interleaved-float representation — an f32/f64vector of twice the logical
length holding re/im pairs — rather than native `c64vector`/`c128vector`
(whose byte layout is identical: 2 consecutive f32s/f64s per element): the
spec's `data?` contract ("`#t` iff `data->body` returns a body sharing the
data, without copying") makes accepting the reference's even-length float
vectors possible only by actually using them as the body, and that shape is
what reference-coupled code and the official suite's fixtures feed to
`make-specialized-array-from-data` (#2382). The single most-reused implementation pattern
across the views/combinators/assembly phases: build a lazy virtual array via
`make-array` with a computed getter over the target domain, then delegate to
`array-copy` (which already owns all storage-class/mutable?/safe? option
parsing and the materializing fill loop) rather than hand-rolling a fill
mechanism per procedure — used for `array-stack`, `array-decurry`,
`array-append`, `array-block`, and more. Their `!` twins are confirmed-safe
pure aliases (verified by reading the reference implementation: both entry
points wrap one shared helper differing only in whether inputs are eagerly
pre-materialized before the fill, a distinction observable only under
multi-shot-continuation re-entry, which the spec itself declares undefined).
`specialized-array-reshape` uses a deliberate packed-check-based
affine-detection simplification instead of the reference's full multi-group
algorithm, verified identical on the spec's own worked examples. (`array-packed?`
itself means consecutive-increasing from any body base — not a zero base —
per #2314; an `array-extract` view with a non-zero offset is packed and
reshapes in place through this same fast path, like the reference.) `array-block`
needed a genuinely two-phase algorithm unlike everything else in the SRFI:
full per-axis width-consistency validation (reusing
`array-curry`+`array-permute`+`index-first`) followed by cheap
single-pencil-probing for offsets (reusing
`array-curry`+`array-permute`+`index-last`), both confirmed against the
reference implementation. The SRFI's own prose pseudocode disagreed with its
reference implementation at least twice (`check-nested-list`'s dimension-0
case returns `'()`, not the prose's nonsensical `#t`; `array-inner-product`'s
prose omits a required `array-curry` argument the reference code supplies) —
confirming "when this SRFI's prose and its reference implementation disagree,
trust the code" as a load-bearing rule for this SRFI specifically.
`array-extract`-derived views preserve **absolute** source coordinates, never
resetting to 0-based, per the spec's own worked example. SRFI 231 supersedes
SRFI 179 (its own abstract: "a revised and improved version of SRFI 179") with
acknowledged breaking changes, not a strict superset — see
`docs/dev/srfi-exclusions.md` for specifics; 179 is excluded on that basis.

## Library loader

The library loader in `vm_library.zig` supports `cond-expand`, `include` (paths resolved relative to the .sld file), and `(export (rename ...))` in `define-library`. Macro transformers defined with `define-syntax` in library `begin` blocks are exported and imported correctly.

## Coverage, closed issue groups, and the exclusion breakdown

Of the 208 final SRFIs in the registry, 178 are implemented and 30 are
excluded — see `docs/dev/srfi-exclusions.md` for the full rationale. Issue #1699
("Implement SRFI macro & syntax extension libraries") is now fully
closed: 139 and 149 needed no engine changes and shipped directly, 147
(custom macro transformers) needed one, 148 (eager syntax-rules) — the
group's hardest portable case — shipped over 147's mechanism once six
separate engine bugs it surfaced were fixed, 211 and 213 shipped last on
the procedural-transformer mechanism (see their own paragraph below), and
72 was excluded: the issue table's "explicit renaming macros" note was a
mislabel — SRFI 72 is van Tonder's *replacement* macro system (evaluated
transformer expressions over syntax objects, a novel hygiene rule,
begin-for-syntax phasing), incompatible with R7RS's structural
transformer-spec grammar and this symbol-based expander, while the ER
facility actually wanted is exactly `(srfi 211 explicit-renaming)`.

### SRFI 150 — Hygienic ERR5RS Record Syntax

SRFI 150 (Hygienic ERR5RS Record Syntax, issue #1810) was retired from
`docs/dev/srfi-exclusions.md` once its own stated blockers (SRFI 147 and
148) shipped, and needed three implementation attempts to land. It
extends SRFI 131 (`lib/srfi/131.sld`, its shared runtime substrate) with
hygienic field-name matching, non-identifier field names, and accessor-
name field references in constructor specs. The first two attempts —
porting the reference's own SRFI 137 `make-subtype` closures directly,
then a from-scratch rewrite using a `:secret`-style descriptor macro over
SRFI 237 — both used the same general shape (a child type's expansion
queries a parent macro's own protocol for its record-type-descriptor via
a nested macro call) and both broke once more than one such query
relationship existed side by side in the same program, isolated to two
apparent `em-syntax-rules` engine bugs along the way (kaappi#1828 and
kaappi#1829 — both since determined NOT to be engine bugs). kaappi#1829
turned out not to be an expander bug of its own at all: because the CK
machine builds its output as plain data, a macro-generated top-level
`define` lands under its BARE name, so the next expansion's own reference
to it was a free reference to an already-bound non-procedure global —
exactly the referential-transparency collision of kaappi#1832, which
kaappi#1839's hygiene rename closed for both;
`tests/scheme/hygiene/macro-fresh-global-readback-1829.scm` guards that
shape directly. kaappi#1828 also turned out not to be an engine bug: its
own repro's final (non-`=>`) template was left unquoted while calling an
ordinary procedure, which SRFI 148's own spec documents as an error case,
unrelated to the "bound variable as a later step's operator" framing it
was filed under — `lib/srfi/148.sld`'s header and
`tests/scheme/hygiene/em-syntax-rules-operator-chain-1828.scm` confirm the
operator-position mechanism itself works correctly, including 3 levels of
chaining. Whether the two rejected attempts above would have succeeded
without this same misunderstanding is not re-tested. The third, shipped
design avoids the whole query-macro pattern regardless, so it is unaffected
either way: the type name is bound directly to an ordinary runtime record-type-
descriptor exactly as in SRFI 131 (inheritance and field/accessor/
mutator resolution, including multi-level shadowing, handled entirely at
run time by SRFI 237's own by-name introspection), and the one piece
SRFI 131 doesn't have — hygienic field/accessor-name matching for named
constructor specs — uses SRFI 213 (identifier properties) instead of a
query macro: each `define-record-type` use attaches its own field/
accessor-name pairs to the type name via `define-property`, a child
reads its parent's via `lookup`, and `lookup` is only reachable from a
procedural transformer, so `define-record-type` itself is a SRFI 211
`er-macro-transformer` rather than an `em-syntax-rules` macro. (The
matching and index resolution themselves happen entirely inside that
transformer — see the kaappi#2051 paragraph below, which replaced an
earlier scheme that stored field-name symbols in the property table and
compared them by plain `equal?` on the raw, hygiene-renamed spelling.
That scheme was unsound: quoted data strips the rename, so the stored
symbols collapsed across hygienically-distinct fields.) This design
surfaced the library global-resolution
bug fixed in kaappi#1831, which first presented as `cadar` specifically —
not `caar`/`cadr`/`cddr`, and not its own unrolled spelling
`(cadr (car x))` — failing when called from a helper function invoked
during an `er-macro-transformer`'s expansion. The `cadar` framing was a
red herring on two counts: `cadar` is a `(scheme cxr)` name
`lib/srfi/150.sld` never imports while its apparent siblings there are
`(scheme base)` names already in lib_env, and the file's one other
cxr-only name (`cdddr`) sits inside the transformer's own lambda, which
is evaluated at macro-definition time in the global environment and so
never consults lib_env at all. The real rule was tail vs. non-tail
position (see the SRFI 237 paragraph above); the idiomatic `cadar`
spelling is back in `field-alist-ref`.

SRFI 150's own final design (kaappi#2051) then had to be reworked twice:
field identity was originally carried from expansion time to run time
inside `quote`, on the theory that the engine's rename-by-spelling
hygiene representation made the stored symbol's full spelling a sufficient
runtime key. It is not: the compiler strips a `__hyg_N_` rename from any
quoted datum (`compileQuote`'s `stripHygieneFromDatum`, which is correct
and required — a `syntax-rules` template's `'foo` must yield `foo`, not
`__hyg_1_foo`), so two hygienically-distinct field identifiers whose
spellings strip to the same name (a macro template's own field-name
literal and the same-spelled identifier the use site supplies, e.g.
`__hyg_2_a` and `a`) collapsed into one runtime field. All four of the
reference suite's hygiene assertions failed on it, and the defect was
misattributed to kaappi#1832 (a pre-existing top-level binding of the
colliding spelling is NOT required — the no-binding control fails
identically). The current design therefore resolves field identity
ENTIRELY at macro-expansion time, while the renamed symbols are still in
hand, and never round-trips a hygienic symbol through `quote`:

* A constructor spec entry matches the current form's own fields by
    FULL spelling (same template identifier, same gensym — this engine's
    bound-identifier=?), then inherited fields by hygiene-STRIPPED
    spelling against the parent's stored property (free-identifier=? for
    the top-level bindings a parent's field name actually refers to), and
    resolves to a numeric ABSOLUTE index into the full
    (inherited-then-own) field layout. `named-constructor` fills the
    record's field vector by index; no by-name lookup happens at run
    time.
* Each own field gets a runtime name for the record-type-descriptor
    and accessor/mutator creation: its stripped spelling, deduped with a
    numeric suffix when two own fields strip to the same name (the
    Hygiene 1 shape); a non-identifier constant field name gets a
    generated `field-<index>` name (the rtd layer requires a symbol). An
    own field matching an inherited field's stripped spelling is
    deliberately NOT deduped — that is ordinary shadowing, resolved
    own-fields-first at run time.
* The property table stores the parent's total field count plus an
    alist of stripped-spelling KEYs to absolute indices — keys and
    indices only, no renamed symbols.

One separate hazard surfaced while re-enabling the tests: the emitted
type-name binding is also emitted hygiene-STRIPPED, because a
macro-introduced `__hyg_N_<t>` reference whose base `<t>` is an
already-bound global is intercepted by the #1832 referential-transparency
alias (it loads the PRE-EXISTING global's value for every such reference,
even inside the same expansion that defines it), so the accessors would
bind against the old record type when a macro redefines an already-bound
type name. The type name is a define target, not a genuinely free
reference, so the stripped spelling is the correct emission — it rebinds
the global like any top-level redefinition (R7RS 5.3.1) and matches what
SRFI 131 emits for its type names. The reference suite now passes in
full; `tests/scheme/srfi/srfi150.scm` adds the issue's discriminating
controls (the no-binding C5 variant, the non-colliding-spelling C6
control, constant field names, and the quoted-`__hyg_`-strip note) as
regression tests. Issue #1694 (the
numeric-vector and array family) is now fully closed: the vector-family
subset — 4 (already shipped pre-Phase-4, just undocumented until Phase 4
Slice 4), 160, 66, 74 — shipped in Phase 4 Slice 4 on one shared native
substrate (`types.NumericVector`); the array family — 25 (Slice 5), 164
(Slice 6), 63 (Slice 7, with 47 excluded as superseded), and finally 231
(Slices 8–13, 118 bindings across 6 phases: misc+intervals, storage
classes, core array object, views/sharing/reshaping, bulk
combinators/conversions, multi-array assembly — a three-tier
array/mutable-array/specialized-array model with no textual relationship
to 25/164/63 at all, merged into a public `lib/srfi/231.sld` re-export hub
in the final step, which also moved SRFI 179 from tracked to excluded as
231's own designated, if not fully backward-compatible, successor) — is
fully shipped too, leaving only SRFI 58's reader/writer array-literal
syntax excluded (its stated blocker — no typed array infrastructure to
build on — no longer holds at all now that SRFI 4/160/25/164/63/231 exist,
worth re-examining if 58 is ever picked up). #1695 was fully closed
earlier in Phase 4: 57/131/136/137/237/240 shipped, 99/100/150
excluded. #1699 (minus what Phases 1–3 closed) and #1729, which completed
SRFI 181's transcoded-port half — custom ports landed separately in
Phase 3, #1727 — plus issues #1703 and #1702, were all closed in full in
Phase 4 as well.
`docs/dev/srfi-exclusions.md`'s 30 excluded break down as: 7 meta/ecosystem SRFIs
already covered by existing features, 11 non-standard reader syntax SRFIs
that would fundamentally alter the parser, reinterpret already-valid syntax,
or need typed-array infrastructure that doesn't exist, 6 macro-system-
dependent SRFIs — 206 and 212, whose own spec text states a portable
syntax-rules-only implementation isn't possible; 89, whose reference
implementation needs the same non-hygienic macro power for a different
reason (discriminating a keyword-shaped parameter from a symbol-shaped one
during pattern matching); 99 and 100, both needing identifier synthesis
(`make-<name>`, `<name>?`, etc.) from string concatenation at macro-expansion
time, which `syntax-rules` cannot perform — SRFI 131 (implemented) is
specifically 99's syntax-rules-expressible reduced subset; and 72, a
complete replacement macro system (arbitrary transformer expressions
evaluated at expansion time over a syntax-object type with its own hygiene
rule and phase tower) incompatible with R7RS's structural transformer-spec
grammar and this symbol-based expander (150, formerly this group's sixth
member, moved back to tracked — issue #1810 — once its stated blockers
SRFI 147+148 shipped) — 1 SRFI — 208 — whose own spec text states the same
about raw NaN bit-pattern access, which Kaappi's NaN-boxing value
representation makes categorically unrepresentable, 1 SRFI — 106 — redundant
with the `kaappi-net` ecosystem package's existing, broader-scoped socket
support, 2 concurrency-model-incompatible SRFIs — 21 and 230 — which need
a userspace-scheduled thread model and cross-heap shared mutable memory
(respectively) that Kaappi's OS-native-thread,
independent-heap-per-thread SRFI-18 doesn't have, and 2 SRFIs — 47 and
179 — superseded outright by their respective successors: 47's own page
states the supersession by SRFI 63 directly, with 63's procedure set a
strict superset of 47's with identical signatures throughout; 179's
successor SRFI 231 states in its own abstract "This is a revised and
improved version of SRFI 179," though — unlike 47/63 — it is a breaking
revision, not a strict superset (see `docs/dev/srfi-exclusions.md` for
the specific incompatibilities).

## The macro & syntax extension group (issue #1699)

### SRFI 139 — syntax parameters

SRFI 139 (syntax parameters) is the first piece of issue #1699 (SRFI
macro & syntax extension libraries) to ship, and turned out to need no
engine work at all despite being grouped with 6 SRFIs that do: `let-syntax`
(`compileLetSyntax`, `compiler_define_syntax.zig`) already implements exactly
`syntax-parameterize`'s own semantics — adjust the live macro table for a
bounded compile extent, then restore it — so `lib/srfi/139.sld` is a
2-form, 6-line library (`define-syntax-parameter` → `define-syntax`,
`syntax-parameterize` → `let-syntax`), verified against both of the
spec's own worked examples (`forever`/`abort`, `lambda^`/`return`) plus 2
adversarial cases: nested `syntax-parameterize` of the same keyword (the
inner extent's transformer must not leak past its own scope once it
exits) and a body-local variable sharing a name with the macro's own
internal continuation identifier (must not be captured) — both passed
without any implementation changes, confirming the mechanism generalizes
correctly rather than only working for the two examples it was designed
around.

### SRFI 149 — basic syntax-rules template extensions

SRFI 149 (basic syntax-rules template extensions) is the second piece of
issue #1699 to ship without engine changes. Its two extensions — consecutive
ellipses directly after one template element (`a ... ...`, which R7RS's
own stricter grammar requires extra parens for instead) and letting a
pattern variable be followed by MORE ellipses in the template than its own
pattern-matched depth, with the excess replicating a shallower sibling at
the innermost position — are both already correct in the
expander's existing `instantiateEllipsis` (expander_instantiate.zig). The spec's own prose gives no worked
example for the genuinely-new nonzero-depth-excess case, so this needed
fetching the reference implementation's `expand-template` algorithm (a
`map` plus `depth-1` applications of `apply append`, driven by a
free-variables-at-this-dimension scan) to understand precisely what
"innermost" means, then confirming Kaappi's binding-driven design (live
per-binding depth reduction, rather than a static free-variable scan)
produces the identical result: a shallower sibling, already reduced to a
scalar by an earlier ellipsis level, is naturally held constant when a
deeper sibling drives further iteration — which *is* innermost-replication,
arrived at by a different mechanism. Verified against both of the spec's
own worked examples (`my-append`'s consecutive flatten; `foo`'s mixed-depth
`a`/`b` siblings) plus 2 more. `lib/srfi/149.sld` is a trivial
`(export syntax-rules)` re-export, the same shape as SRFI 46's own "these
R7RS extensions are already native" library. One pre-existing, unrelated
gap found and deliberately left alone: an ellipsis with no driving
variable at all (e.g. a lone variable asked for more ellipses than its own
maximum depth) silently produces an empty result instead of erroring —
predates this SRFI, isn't a case it needs to support, and fixing the
underlying leniency is a separate, ecosystem-wide-blast-radius project of
its own.

### SRFI 147 — custom macro transformers

SRFI 147 (custom macro transformers) is the third piece of issue #1699 to
ship, and the first that genuinely needed an engine change: R7RS's
`<transformer spec>` only accepts a literal `(syntax-rules ...)` form,
and 147 extends it to also accept a macro use that itself expands
(possibly through several steps) to one -- letting a library define its
own transformer-generating-transformer, e.g. the spec's own worked
example, a `syntax-rules*` that auto-wraps multi-form templates in
`begin`. `compileDefineSyntax`/`compileLetSyntax`/`compileLetrecSyntax`
(`compiler_define_syntax.zig`) now route every transformer-spec through a new
`resolveTransformerSpec`, which expands a non-literal spec via the same
`expander.expandMacro` every ordinary macro call already goes through,
looping (depth-bounded) until it bottoms out at a literal `syntax-rules`
form. The grammar's other two new alternatives -- a bare keyword aliasing
an existing one, and a macro use expanding to `(begin <definition>...
<transformer-spec>)` -- were initially deferred as unneeded by SRFI 148
(the reason 147 was implemented), then shipped in a same-week follow-up
once tracing SRFI 148's actual reference implementation (not just its
spec prose) showed its core `em-syntax-rules-aux1`/`em-syntax-rules-aux2`
mechanism bottoms out through exactly `(begin (define-syntax a spec) a)`
-- a helper definition followed by a bare reference to it, needing both
alternatives together. `resolveTransformerSpecRec`'s contract changed
accordingly: it now returns an already-parsed `Transformer` (not raw
`syntax-rules` source), because the bare-symbol alias case has no source
to hand back, only a `Transformer` an earlier step already parsed --
looked up directly in the same `merged_macros` map the resolution loop
already threads through. Aliasing a builtin special form still correctly
falls through to `InvalidSyntax`: builtins are recognized structurally in
`ir_mod.isSpecialForm`, never stored as `Transformer` values in that map,
so there is nothing for a bare-symbol lookup to find.

Verifying this against just its own worked example wasn't enough --
`bash tests/scheme/run-all.sh` caught two real, generalizable bugs that no
amount of SRFI-147-specific testing alone would have found, since both
needed a macro-heavy, multi-scope program to manifest:

1. **A LIFO root-stack violation.** An early draft rooted the resolved
   spec via `pushRoot` + `defer popRoot()` around the (allocating)
   `parseSyntaxRules` call inside `compileLetSyntax`'s per-binding loop.
   The SAME loop iteration pushes an unrelated root for its own result
   array entry right after -- so by the time the deferred call fired (end
   of that iteration), it popped the wrong (most recently pushed) entry
   off the stack instead of the one it was meant to protect, silently
   unrooting the actual transformer object. This surfaced only in
   `tests/scheme/srfi/srfi257.scm` -- a heavily macro-based library --
   as a "invalid syntax" error with no apparent connection to the real
   cause, and never in any of this SRFI's own smaller tests. Fixed by
   popping immediately and explicitly right after the specific call being
   protected, never via `defer` across a stretch that itself calls
   `pushRoot` -- now documented as its own rule in
   `.claude/rules/gc-safety.md`, whose glob also grew to cover
   `compiler*.zig`/`expander.zig`, which it hadn't before despite both
   doing GC-sensitive work directly.
2. **A parent-scope-chain visibility gap.** `resolveTransformerSpec`'s
   macro lookup originally checked only `self.macros`, unlike the
   established macro-CALL-expansion path (`expandAndCompileMacroUse`),
   which explicitly merges every ancestor `Compiler` scope's macros before
   looking anything up -- because a nested child scope (e.g. a
   `let-syntax` whose body sits inside `guard`'s desugared lambda, as
   SRFI 64's own `test-equal` produces) never automatically inherits an
   enclosing scope's macros into its own map. A `syntax-rules*`-based
   transformer-spec placed anywhere but the outermost scope was wrongly
   rejected as "not a macro" until this was fixed to merge the same way.

The begin-wrapped-definitions follow-up itself needed a THIRD correction,
found only once SRFI 148's reference implementation was traced through in
full rather than just its grammar: `em-syntax-rules-aux2`'s own base case
expands to `(begin (define-syntax o spec) o)`, but the SURROUNDING
`syntax-rules` body it sits inside ALSO calls `o` directly from within its
own rules (e.g. `(ck s "arg" (o) . q)`), not just as the bare tail -- so
`o` must keep resolving every time the macro being defined here is later
invoked, not just while resolving this one transformer-spec. A helper
registered only in `resolveTransformerSpec`'s transient, function-local
`merged_macros` (discarded once that call returns) cannot satisfy this --
confirmed via direct reproduction (`(begin (define-syntax step1 ...)
(define-syntax step2 (... (step1 ...))) (syntax-rules () ((_ y) (step2
y))))`, called twice after definition) failing with `undefined variable
'__hyg_N_step1'`. Fixed by registering each begin-internal helper into the
real, persistent-for-this-scope's-lifetime `self.macros` (and `lib_env` at
library top level) exactly like an ordinary `define-syntax` at the same
nesting depth gets, not just the transient resolution-scoped map. That fix
immediately surfaced a fourth, adjacent bug under the unit test suite's
leak-checking allocator: a begin-wrapped alias can hand the exact same
`Transformer` `Value` to two or more different binding sites (a helper
aliased directly by its own generator, then re-aliased by an enclosing
one), and `compileDefineSyntax`/`compileLetSyntax`/`compileLetrecSyntax`
each unconditionally ran `captureLocalsOnTransformer`/
`computeBoundFreeRefs` on whatever `resolveTransformerSpec` returned --
both allocate and overwrite a slice field with no free of what was there
before, so a second finalization pass on an already-finalized object
leaked the first allocation. Fixed by merging both calls into one
`finalizeTransformer`, guarded by a new `Transformer.finalized` flag, so
every transformer is finalized exactly once regardless of how many names
end up pointing at it.

CodeRabbit caught a fifth, adjacent instance of the exact same hazard in
review of that fix, after CI had already auto-merged it -- shipped as its
own immediate follow-up: `compileLetSyntax`'s sibling-suppression
bookkeeping (`let_syntax_peer_names`/`let_syntax_peer_vals`, R7RS 4.3.1)
lives in a separate code block in the SAME per-binding loop, outside
`finalizeTransformer`'s reach, and has the identical "unconditionally
`dupe` and overwrite" shape -- reachable as soon as two sibling bindings
in one `let-syntax` form resolve to the same `Transformer` (a begin-
wrapped helper reference for one, a bare alias of that same helper for
the other). Verified as a real, non-hypothetical leak (not just a
theoretical overwrite) by confirming the shared transformer's template
has a genuinely non-empty free-reference set first -- an earlier draft's
reproduction used a template with zero free references, where `dupe`ing
an empty slice doesn't actually allocate, so the mutation-tested unit
test silently failed to catch anything until the reproduction was
corrected to reference a true sibling. Fixed with a narrower, deliberately
non-permanent guard: a linear scan of this call's own `tx_vals` prefix for
an identical `Value` already processed earlier in the SAME loop -- unlike
`Transformer.finalized`, this can't be a permanent per-object flag, since
a transformer aliased into some OTHER, unrelated `let-syntax` form later
genuinely needs its own peer snapshot computed against that different
form's sibling set.

That same review flagged a sixth spot the fifth's fix didn't close: the
`tx_vals`-prefix scan only ever catches the same `Transformer` reappearing
*within* one `let-syntax` form, so a transformer aliased into a
*different*, unrelated `let-syntax` form later still reached the
recomputation code -- which still unconditionally overwrote whatever an
earlier form's processing had set, with no free. The first fix for this
(shipped, then reviewed) freed the old pair before every such overwrite
and reasoned that recomputing was *correct*, since "a transformer aliased
elsewhere genuinely needs its own peer snapshot against that different
form's siblings." **That reasoning was wrong, not just the leak.** R7RS
4.3.1's peer snapshot exists precisely to freeze a template's free
references against whatever was in scope at the template's own true point
of definition, so that *later* shadowing at some *other* use site can't
reach in and change what a name resolves to -- recomputing it against a
different form's outer bindings is exactly the kind of interference the
mechanism exists to prevent, not a case it needs to additionally handle.
Caught only by a properly discriminating reproduction: a plain top-level
*procedure* as the shared free reference can't tell the two designs apart
at all (a procedure binding was never captured by `let_syntax_peer_vals`
in the first place, which reads `self.macros`, not `self.globals`) --
only a *macro* redefined between the two forms exposes it, and did:
recomputing silently changed a previously-correct answer from 11 to -10,
using the second form's redefinition instead of the first form's binding
where the helper was actually written. Nesting the reuse inside the
defining form's own body (rather than two separate top-level forms) was
worse: it corrupted the *outer* binding too, since the emptied snapshot
let an outer sibling rebinding leak through unsuppressed for both calls.
Fixed by replacing the per-call scan with a permanent, once-per-object
`Transformer.peers_computed` flag (mirroring `finalized`'s own shape, but
a distinct field -- peer suppression is `compileLetSyntax`-specific,
unlike the finalization every macro-defining form needs): the snapshot is
computed exactly once, at whichever form's processing the object is first
encountered in, and every later encounter -- same form or a different
one -- reuses it unchanged. (Verifying the fix took an unrelated detour:
toggling the worktree between the old and new code via `git stash`/
`git checkout <sha> -- <path>` without running `kaappi cache clear` after
each rebuild made the same reproduction file answer differently across
otherwise-identical rebuilds, looking exactly like nondeterminism until
traced back to the `.sbc` bytecode cache's build-id half -- the git commit
hash plus a binary `-dirty` flag, not a hash of what the uncommitted
changes actually are, so any two different uncommitted edits at the same
base commit alias to the identical id and share cache entries -- see
`docs/dev/cache.md`.)

CodeRabbit's review of that fix caught one more ordering bug: the first
cut set `peers_computed = true` immediately, before the several fallible
allocations (`peer_names_f`/`peer_vals_f` appends, both `dupe` calls) that
actually build the snapshot. An OOM partway through would leave the flag
permanently true with `let_syntax_peer_names`/`vals` still at their
default-empty value -- every later reuse would then treat "no suppression
needed" as the final, correct answer instead of retrying. Fixed by moving
the flag assignment to strictly after both slices are durably stored,
right before the `self.macros.put` that was already there.

### SRFI 148 — eager syntax-rules

SRFI 148 (eager syntax-rules) is the fourth piece of issue #1699 and the
reason 147 was implemented at all: `lib/srfi/148.sld` is pure portable
Scheme (the 134-definition CK-machine core plus ~110 `em-` combinators,
combining the reference's three source files in one library body), with
`em-syntax-rules` and several combinators resolving through exactly the
begin-wrapped-`define-syntax` SRFI 147 mechanism described above. No
engine changes shipped WITH it — instead it surfaced, and was blocked by,
six engine bugs fixed separately first: the #1776/#1779 quote-fast-path
and custom-ellipsis unwrap gaps, the #1787/#1790 usertext-marker
spine-walk gaps, the #1796/#1797 head-position chain depth wall (the CK
machine is exactly that shape), and finally #1802's compile-cost cliff
(the ReleaseSafe `= undefined` 0xAA fill of the expander's 1MB buffers
plus the `set!` pre-scan speculatively running the CK machine inside
every transformer spec) — importing the full library now costs ~0.07s
where it cost ~87s. Two details worth knowing before editing the `.sld`:
the reference's genuinely-empty `(syntax-rules ())` for its
`:call`/`:prepare` "secret literals" is rejected by Kaappi's parser
(tracked limitation), so each carries one structurally-unreachable rule
instead; and the port fixes 4 real, confirmed bugs in the SRFI's own
reference implementation (em-append-map's stray `map` token,
em-set-intersection/em-set-difference dropping `'compare` in their 3+-list
recursions, and em-set= being vacuously `#t` for 3+ arguments) — all
documented with evidence in the `.sld` header. The test suite
(`tests/scheme/srfi/srfi148.scm`) is the reference's own `test.sld`
ported verbatim, and **all 142 assertions pass with zero
`test-expect-fail`**. The two general engine bugs the port surfaced
— #1800 (macro-expanded bare `(define x v)` in body position invisible
to later siblings) and #1801 (two expansions of a template-introduced
literal symbol wrongly `bound-identifier=?`) — are both fixed; the test
file's own header explains each fix and is accurate, so read it rather
than assuming the citations are stale.

### SRFI 211 — Scheme Macro Libraries

SRFI 211 (Scheme Macro Libraries) and SRFI 213 (Identifier Properties)
closed issue #1699, and are the codebase's first *procedural* macro
transformers. `Transformer` gained a `kind` tag (syntax_rules / er_macro /
lisp_macro) plus a GC-traced `proc` Value (`types.zig`; marked in all
`gc_collect.zig` switches, deep-copied cross-thread). A transformer spec
`(er-macro-transformer <expr>)` / `(lisp-transformer <expr>)` is
recognized structurally in `resolveTransformerSpecRec` (hygiene-stripped
head, like renamed special forms), and `<expr>` is evaluated AT
MACRO-DEFINITION TIME in the global environment — deliberate phase
separation; enclosing runtime locals are invisible — via
`globals.eval_datum_for_macro`, one of four fn-pointer hooks the VM
registers in `setVMInstance` (the expander/compiler cannot import vm.zig;
the others are `call_proc_for_macro` and the SRFI 213 property get/set
pair). Expansion routes through `expander.expandProceduralMacro`: the ER
`rename`/`compare` arguments are freshly allocated NativeFns reading
threadlocal per-invocation context (fresh scope id + the same
save/restore discipline as the syntax-rules `active_*` context), and
`rename` reuses `renameForHygiene` — so ER macros get exactly the hygiene
strength syntax-rules templates have, including the shared pre-existing
limitation that a use-site top-level redefinition of a referenced name
reaches the expansion (verified equivalent on both paths). A bare-symbol
spec falls back to a globals lookup holding a Transformer value, so
`(define t (er-macro-transformer p))` + `(define-syntax m t)` works. Two
non-obvious integration points: (1) `vm_imports.copyTransformerFreeRefs`
copies a procedural transformer's WHOLE def_env at import (factored
`copyOneDefEnvBinding` shared with the template scan) — its free
references are computed by running code, so the whole environment is the
honest static over-approximation of the template-scan copying
syntax-rules macros get; without it, `(rename 'lib-helper)` output
resolved at the definition site but died "undefined variable" at the use
site. (2) SRFI 213's `capture-lookup` is the identity (its spec permits
exactly this): the expander re-enters ANY procedural result that is a
procedure with the property `lookup` NativeFn, looping (bounded) until a
datum comes back — so wrapped and bare returns behave identically.
`define-property` is a delegating compiler form (`FormKind.define_property`
→ `compileDefineProperty`, auto-membered into
`ir.eval_fallback_form_names`) storing into the VM-owned
`syntax_properties` table (marked in `markVMRoots`, keys owned,
effective-name keyed — nominal conformance like SRFI 57); body-scope use
is rejected, top-level and library top-level work. The public surface is
sub-library-only for 211 — `(srfi 211 explicit-renaming)` /
`(srfi 211 define-macro)` / `(srfi 211 syntax-parameter)` (.slds over the
`.srfi_211_primitives` registry entry; a bare `(srfi 211)` would require
all eleven facilities including syntax-case, and the spec explicitly
permits providing a subset of libraries, each whole) — plus
`lib/srfi/213.sld`, whose `define-property` export is
declaration-of-intent like SRFI 46/149's syntax-rules re-exports (export
of a name missing from lib_env is silently skipped; recognition is
ambient). The remaining 211 sub-libraries (syntax-case, low-level,
syntactic-closures, implicit-renaming, variable-transformer,
identifier-syntax, with-ellipsis, presyntax) need syntax objects,
identifier macros, or output-provenance tracking a symbol-based expander
cannot honestly provide — implicit renaming specifically cannot
distinguish injected from macro-generated symbols when both are the same
interned object.

### SRFI 241 and SRFI 202 — match and pattern and-let*, on explicit renaming

Both libraries were re-ported from pure `syntax-rules` onto
`er-macro-transformer` (kaappi#2391, KEP-0006 step 5 — the acceptance
test for SRFI 211). The old ports' template gymnastics — a custom `%%%`
ellipsis identifier in every helper macro so the literal `...` token
could be matched as data — are gone; each library is now one procedural
transformer that compiles the pattern language by ordinary list
processing. The re-port lifted all four of the old 241 port's documented
limitations: arbitrary (compound/nested/cata) sub-patterns under an
ellipsis, mandatory patterns after the ellipsis in lists and vectors
(`(,x ... ,y . ,r)`, `#(,a ,m ... ,z)`), the SRFI's ellipsis-aware
quasiquote inside clause bodies, and the spec's cata evaluation order
(cata operators run only after the guard passes — hidden temporaries are
bound during the structural match, then applied through the
`%match-cata` runtime helper, which also transposes per-ellipsis-level
result lists so one cata can bind several variables under `...`). The
202 re-port additionally gained SRFI 2's bare bound-variable claw and
vector patterns in quasiquoted claws.

Engine facts the port depends on (each probed before use, all
regression-covered by `tests/scheme/srfi/srfi241.scm` / `srfi202.scm`):

- **A macro expansion can rebind `quasiquote` via `let-syntax` with a
  bare-symbol transformer spec.** `match` wraps each clause body in
  `(let-syntax ((quasiquote <renamed %match-qq>)) body ...)`, where
  `%match-qq` is a library-level `(define %match-qq
  (er-macro-transformer ...))` global holding a Transformer value; the
  renamed reference resolves at the use site through the whole-def-env
  import copy, and the binding shadows the built-in quasiquote for
  exactly the body's scope. The binding NAME is the bare symbol
  `quasiquote` (deliberately unhygienic — it must capture the body's
  use-site backticks).
- **Fresh temporaries are `rename` of counter-distinct symbols.**
  Renaming the same symbol twice in one expansion yields the same
  identifier, so every temporary is minted as `%mN.<base>` with a
  per-expansion counter, then renamed.
- **Keyword recognition (`...`, `_`, `->`, `guard`, `unquote`,
  `quasiquote`, `values`) is `compare` against `rename` of the keyword —
  hygiene-stripped name equality.** That strength suffices for these
  macros (kaappi#2388 records the evidence); a use inside another
  er-macro's output whose keywords arrive renamed still compares equal.
  The known edge: a match form produced by a *syntax-rules* template is
  subject to that template's own ellipsis processing first, and a
  template-renamed `quasiquote` in a clause body resolves to the
  built-in quasiquote, not the match-body one.
- **A worktree's `.sld` edit is invisible until `zig-out/lib` is
  refreshed** — the exe-relative library dir is populated at `zig build`
  time, so rebuild (or re-copy) after editing, on top of the usual
  `KAAPPI_HOME=$(mktemp -d)` isolation (kaappi#2352).
