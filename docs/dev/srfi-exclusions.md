# Excluded SRFIs

20 final SRFIs are excluded from implementation. This document records which
ones and why, so the decision isn't relitigated.

## Meta / ecosystem SRFIs (7)

These define conventions, tooling requirements, or build-system contracts that
don't map to a library a program can import.

| SRFI | Title | Reason |
|------|-------|--------|
| 22 | Running Scheme Scripts on Unix | Defines `#!` script conventions. Kaappi already handles shebangs natively. |
| 55 | require-extension | Pre-R7RS module loading (`require-extension` form). Superseded by R7RS `import`. |
| 96 | SLIB Prerequisites | Defines prerequisites for the SLIB portability library. SLIB-specific, not general-purpose. |
| 97 | SRFI Libraries | Meta-SRFI defining how implementations should name SRFI libraries. Kaappi already follows the `(srfi N)` convention and supports SRFI 261 aliases. |
| 138 | Compiling Scheme programs to executables | Defines a compilation API. Kaappi has `kaappi compile` which covers this space with its own interface. |
| 172 | Two Safer Subsets of R7RS | Defines restricted language subsets for teaching/sandboxing. Policy, not a library. |
| 176 | Version flag | Defines `(features)` entries for version reporting. Kaappi's `(features)` and `kaappi features` already cover this. |

### SRFI 22 — Running Scheme Scripts on Unix

**Authors:** Martin Gasbichler, Michael Sperber (2002)

Describes prerequisites for running Scheme programs as Unix scripts: the
syntax of Unix scripts written in Scheme (shebang lines), a uniform
convention for calling the Scheme script interpreter, and a method for
accessing Unix command-line arguments from within a Scheme script.

**Why excluded:** Kaappi already handles `#!/usr/bin/env kaappi` shebangs
natively. Command-line arguments are available via `(command-line)` from
`(scheme process-context)`. There is nothing to implement as a library —
the functionality is built into the interpreter's entry point in `main.zig`.

### SRFI 55 — require-extension

**Authors:** Felix L. Winkelmann, D.C. Frost (2004)

Specifies a simple facility for making an extension or library available to
a Scheme top-level environment: `(require-extension ...)`. Predates R7RS.

**Why excluded:** Entirely superseded by R7RS `(import ...)`. The
`require-extension` form was a stopgap for Schemes without a module system.
R7RS provides a standardized, more capable replacement. Implementing this
would add a second, redundant module-loading mechanism.

### SRFI 96 — SLIB Prerequisites

**Authors:** Aubrey Jaffer (2008)

Specifies a set of procedures and macros presenting a uniform interface
sufficient to host the SLIB Scheme Library system — a large portability
library for R4RS/R5RS Schemes.

**Why excluded:** SLIB-specific. It defines the exact interface SLIB needs
from a host Scheme (particular I/O conventions, `system` procedures, etc.)
rather than general-purpose functionality. Kaappi targets R7RS, not the
R5RS ecosystem SLIB was designed for. Any program that genuinely needs SLIB
would face deeper compatibility issues than this SRFI alone would solve.

### SRFI 97 — SRFI Libraries

**Authors:** David Van Horn (2008)

A meta-SRFI defining a naming convention for SRFI libraries in R6RS-style
module systems: `(srfi :N name)`. Establishes a registry mapping SRFI
numbers to library names and mnemonic identifiers.

**Why excluded:** Kaappi already follows the `(srfi N)` convention from
R7RS and implements SRFI 261 (portable SRFI library references), which
provides the same mnemonic aliases (e.g. `(srfi lists-1)` → `(srfi 1)`).
The R6RS colon-prefix naming this SRFI mandates (`(srfi :1 lists)`) is
not used in R7RS-ecosystem code.

### SRFI 138 — Compiling Scheme programs to executables

**Authors:** Marc Nieper-Wißkirchen (2016)

Defines a portable interface for compiling R7RS Scheme programs to
native executables on POSIX-compatible systems: a `compile-program`
procedure and command-line conventions.

**Why excluded:** Kaappi has its own native compilation interface:
`kaappi compile program.scm -o binary` (using the LLVM backend). The
SRFI 138 API prescribes a specific calling convention and output format
that doesn't match Kaappi's architecture. Wrapping the existing backend
behind this interface would add complexity without value — users already
have a working, documented compilation command.

### SRFI 172 — Two Safer Subsets of R7RS

**Authors:** John Cowan (2019)

Provides two libraries that define restricted subsets of R7RS for use
with `eval`, making it safer to evaluate Scheme expressions of doubtful
provenance. One subset removes all I/O and mutation; the other is even
more restricted.

**Why excluded:** This is a policy decision, not a library implementation.
The SRFI itself notes it "does not provide any sort of safety guarantee"
and lists many uncaught loopholes. Kaappi's `--sandbox` flag provides a
more meaningful security boundary at the interpreter level. Implementing
these libraries would give a false sense of safety without real sandboxing.

### SRFI 176 — Version flag

**Authors:** Lassi Kortela (2020)

Defines a standard `--version` command-line flag whose output is
line-oriented S-expressions reporting implementation name, version,
supported features, etc. Intended for programmatic consumption by
tools and package managers.

**Why excluded:** Kaappi already provides `--version` (human-readable)
and `kaappi features [--json]` (machine-readable, structured output with
version, target triple, build mode, subsystems, SRFIs, and VM/GC limits).
The `kaappi features` output is a strict superset of what SRFI 176
specifies. Adopting the SRFI 176 S-expression format would mean maintaining
a second output format alongside the existing JSON one.

---

## Non-standard reader syntax SRFIs (10)

These require changes to the reader/lexer that introduce syntax incompatible
with R7RS or fundamentally alter how source code is parsed. Unlike the reader
extensions in the implementation roadmap (SRFIs 30, 62, 169, 207, 270 — which
are small, well-bounded additions), these redefine the lexical grammar in ways
that would complicate maintenance and interoperability.

| SRFI | Title | Reason |
|------|-------|--------|
| 10 | #, external form | Reader-macro dispatch (`#,(name datum ...)`). Opens arbitrary reader extension — hard to scope safely. |
| 49 | Indentation-sensitive syntax | Replaces parentheses with Python-style indentation. Completely changes the parser. |
| 105 | Curly-infix-expressions | Adds `{a + b}` infix syntax. Requires a second expression grammar inside `{}`. |
| 107 | XML reader syntax | Adds `#<tag>...</tag>` XML literals. Large surface area, niche use case. |
| 108 | Named quasi-literal constructors | Adds `$name{...}` syntax for custom quasi-literals. Depends on SRFI 107. |
| 109 | Extended string quasi-literals | Adds `$string{...}` interpolation syntax. Depends on SRFI 107. |
| 110 | Sweet-expressions (t-expressions) | Indentation + infix + neoteric-expressions. Completely replaces the reader. |
| 119 | wisp: simpler indentation-sensitive scheme | Another indentation-sensitive syntax (alternative to SRFI 49/110). |
| 58 | Array Notation | Adds `#nA(...)` reader syntax for arrays. Blocked on typed array support (SRFI 4/160); would also collide with the existing `#N=`/`#N#` datum-label dispatch on a bare digit after `#`. |
| 163 | Enhanced array literals | Adds `#A(...)` reader syntax for multi-dimensional arrays. Also blocked on typed array support (SRFI 4/160). |

### SRFI 10 — #, external form

**Author:** Oleg Kiselyov (2000)

Proposes an extensible external representation of Scheme values via a
`#,(tag datum ...)` reader syntax. The `#,()` form acts as a reader-level
dispatch mechanism — the tag determines how the enclosed datums are
interpreted. Intended as a notational convention for future SRFIs to
extend read syntax in a uniform way.

**Why excluded:** This is effectively a reader-macro system. Implementing
it means the reader's behavior becomes data-dependent at read time — any
tag could trigger arbitrary transformations. This makes the reader
non-local (you can't understand what `#,(foo ...)` means without knowing
what `foo` is bound to), complicates error reporting, and opens a class of
security concerns when reading untrusted data. R7RS deliberately does not
include reader macros. The `#,` prefix also conflicts with SRFI 10's own
acknowledgment that this is "for possible future extensions."

**Scope of change:** Would require a tag→handler registry in the reader,
callback dispatch from `reader_tokens.zig`, and a way to register handlers
from Scheme code — a significant architecture change to `reader.zig`.

### SRFI 49 — Indentation-sensitive syntax

**Author:** Egil Möller (2005)

Describes I-expressions, a syntax for Scheme that uses indentation to
group expressions instead of parentheses. I-expressions have the same
expressive power as S-expressions but use whitespace structure to
determine nesting. S-expressions and I-expressions can be mixed freely.

**Why excluded:** Completely replaces the parsing model. The current
reader is a recursive-descent S-expression parser in `reader.zig` +
`reader_tokens.zig`. Supporting I-expressions would require a parallel
parser that tracks indentation levels, handles continuation lines, and
interleaves with S-expression parsing at arbitrary depth. This doubles
the reader's complexity for a syntax that has seen minimal adoption in
the Scheme community. SRFI 110 (sweet-expressions) is a more developed
version of this same idea, and it too is excluded.

**Scope of change:** Would need an entirely separate parsing mode with
indentation tracking, callable from the existing reader when a mode
switch is detected.

### SRFI 105 — Curly-infix-expressions

**Authors:** David A. Wheeler, Alan Manuel K. Gloria (2012)

Extends Scheme's reader to interpret `{a + b}` as `(+ a b)`. Curly braces
delimit infix expressions with simple precedence-free rules: a single
binary operator between operands is converted to a prefix call. Mixed
operators produce a `$nfx$` form. Nested curly braces and mixing with
S-expressions are supported.

**Why excluded:** Requires a second expression grammar inside `{}` with
its own tokenization rules (operators as delimiters, whitespace
sensitivity around operators). The R7RS spec reserves `{}` for "possible
future extensions" but this particular use introduces a fundamentally
different parsing mode. The lack of operator precedence (by design) means
`{a + b * c}` produces `($nfx$ a + b * c)`, which is surprising to users
coming from languages where `*` binds tighter than `+`. Adoption across
the Scheme ecosystem has been minimal.

**Scope of change:** New token type in `reader_tokens.zig`, a sub-parser
for infix expressions in `reader.zig`, and special handling for `$nfx$`
forms.

### SRFI 107 — XML reader syntax

**Author:** Per Bothner (2013)

Specifies a reader extension that reads data in a superset of XML/HTML
format and produces conventional S-expressions. XML elements, attributes,
enclosed Scheme expressions, and entity references are all handled at read
time, producing `$xml-element$` forms.

**Why excluded:** Very large surface area — the reader would need to
handle XML's lexical grammar (start/end tags, attributes, CDATA,
character references, namespaces) on top of Scheme's. This is essentially
embedding an XML parser in the reader. The use case is narrow (XML
templating in Scheme), and the same result can be achieved with a
library-level XML parser (like the approach kaappi-json takes for JSON).
SRFIs 108 and 109 depend on this one, forming a chain of three excluded
SRFIs.

**Scope of change:** Major addition to `reader_tokens.zig` (XML token
types) and `reader.zig` (XML element/attribute parsing, entity decoding,
namespace handling).

### SRFI 108 — Named quasi-literal constructors

**Author:** Per Bothner (2013)

Adds `&tag{...}` syntax for named quasi-literal constructors. The reader
translates `&tag{...}` to `($construct$:tag ...)`, where `$construct$:tag`
is expected to be bound to a macro. Combines literal text and enclosed
expressions in a template-like syntax.

**Why excluded:** Depends on SRFI 107 (XML reader syntax) and SRFI 109
(extended string quasi-literals), both of which are excluded. Even in
isolation, this adds a general-purpose reader-level dispatch mechanism
(similar to SRFI 10) with its own escaping and interpolation rules.
The `&` prefix for tags is not part of R7RS lexical syntax.

**Scope of change:** New reader dispatch for `&identifier{...}`, with
escaping rules, enclosed expression parsing, and constructor-name
resolution.

### SRFI 109 — Extended string quasi-literals

**Author:** Per Bothner (2013)

Adds `&{...}` syntax for extended string quasi-literals with enclosed
unquoted expressions, multi-line string support, and special character
escaping. Related to SRFI 108 (named quasi-literal constructors) and
SRFI 107 (XML reader syntax), sharing syntax conventions.

**Why excluded:** Part of the SRFI 107/108/109 family of reader
extensions. Introduces a new string-like syntax with its own escaping
rules, expression interpolation (unquoting inside strings), and
line-handling conventions. Kaappi already has SRFI 267 (raw string
syntax `#"X"..."X"`) for multi-line strings without escape processing,
and standard `string-append` / `format` for string construction.

**Scope of change:** New string token type with interpolation in
`reader_tokens.zig`, expression-in-string parsing in `reader.zig`.

### SRFI 110 — Sweet-expressions (t-expressions)

**Authors:** David A. Wheeler, Alan Manuel K. Gloria (2013)

A comprehensive alternative syntax combining three layers:
curly-infix-expressions (SRFI 105), neoteric-expressions (function call
syntax `f(x)` instead of `(f x)`), and indentation-sensitive grouping
(extending SRFI 49). Together these produce "sweet-expressions" that
look closer to conventional programming languages while remaining
homoiconic.

**Why excluded:** The most ambitious of the alternative-syntax SRFIs.
It effectively replaces the entire reader with a three-layer parser
that handles indentation, infix, and neoteric call syntax simultaneously.
The specification is large and the interaction between the three layers
creates edge cases. No mainstream Scheme implementation has adopted this
as its default syntax, and code written in sweet-expression syntax is
not portable to other Schemes.

**Scope of change:** Would require a near-complete parallel reader
implementation alongside the existing S-expression reader.

### SRFI 119 — wisp: simpler indentation-sensitive scheme

**Author:** Arne Babenhauserheide (2015)

Another indentation-sensitive syntax for Scheme, simpler than SRFI 110.
Uses indentation to group expressions, a colon surrounded by whitespace
for inline grouping, and a leading period for continuation lines. Designed
to minimize additional syntax elements while remaining general and
homoiconic.

**Why excluded:** Same fundamental issue as SRFIs 49 and 110 — requires
a parallel parser with indentation tracking. While simpler than SRFI 110,
it still introduces whitespace-sensitive parsing that is foreign to
Scheme's lexical grammar. The three competing indentation SRFIs (49, 110,
119) suggest the community has not converged on a single approach, making
any one of them a risky investment.

**Scope of change:** Separate indentation-aware parser with colon and
period special forms, callable from the existing reader.

### SRFI 58 — Array Notation

**Author:** Aubrey Jaffer (2005)

Specifies `#nA(...)` reader syntax for n-dimensional arrays, e.g. `#2A((1
2)(3 4))` for a 2×2 array — predating and simpler than SRFI 163's version
of the same idea (no non-zero lower bounds, no explicit bounds, no
element-type tag).

**Why excluded:** Same two blockers as SRFI 163, since this is the
earlier, smaller version of the same feature. First, there is no typed
or general n-dimensional array heap type to construct — SRFI 4 in this
codebase is a purely portable wrapper over ordinary bytevectors/vectors
(`lib/srfi/4.sld`), and SRFI 160 has no implementation at all, so `#nA(...)`
would have nothing to build. Second, the syntax itself is a bare digit
immediately after `#` (`#2A(...)`), which the reader already uses for
datum labels (`#N=`/`#N#`, `reader_tokens.zig`'s digit arm in `readHash`)
— disambiguating the two would need lookahead past the digits for `A`
specifically, not just a new dispatch arm.

**Scope of change:** New heap type(s) for n-dimensional arrays (or
building on typed vectors from SRFI 4/160, if those get genuine engine
support), plus a new, digit-disambiguated dispatch path in
`reader_tokens.zig`'s `readHash`.

### SRFI 163 — Enhanced array literals

**Author:** Per Bothner (2019)

Specifies `#NdTAG(...)` reader syntax for multi-dimensional array
literals, extending Common Lisp's `#NA(...)` syntax to support non-zero
lower bounds, explicit bounds, and uniform element types compatible with
SRFI 4. Originally implemented in Guile and Kawa.

**Why excluded:** Two blockers. First, the reader syntax (`#2a(...)`,
`#f64(...)`, etc.) adds a family of new dispatch sequences to the `#`
reader, each parameterized by dimension count and element type — a
combinatorial addition to `reader_tokens.zig`. Second, the syntax is
meaningless without the underlying typed array infrastructure (SRFI 4,
SRFI 25, SRFI 160, SRFI 164), which is itself a large engine-change
project tracked separately. If the array SRFIs are implemented in the
future, this reader syntax can be reconsidered as a follow-up.

**Scope of change:** Parameterized `#` dispatch in `reader_tokens.zig`,
array construction in `reader.zig`, depends on typed array heap types
from SRFI 4/160.

---

## Macro-system-dependent SRFIs (2)

These require transferring or comparing bindings/identifiers in ways that
`syntax-rules` alone cannot express — genuinely `syntax-case`-shaped gaps,
not just missing library code. Both SRFIs' own specification text says as
much directly, rather than this being Kaappi's own conclusion. Tracked
macro/syntax-system extension work that touches the same expander surface
is in issue #1699 (SRFI 72, 139, 147, 148, 149, 211, 213).

| SRFI | Title | Reason |
|------|-------|--------|
| 206 | Auxiliary Syntax Keywords | Its core feature — independently-defined auxiliary keywords (like `else`/`=>`) matching via `free-identifier=?` across library boundaries — needs identifier-property support at the expander level. |
| 212 | Aliases | Transferring a binding so two identifiers share one location, for any binding type including syntax, needs identifier/location introspection a syntax-rules-only system can't provide. |

### SRFI 206 — Auxiliary Syntax Keywords

**Author:** Marc Nieper-Wißkirchen (2020)

Defines `define-auxiliary-syntax`, letting independently-authored libraries
define auxiliary keywords (like `cond`'s `else`) that mutually match via
`free-identifier=?` despite having no shared origin — normally, two
separately-defined identifiers with the same name do *not* count as the same
literal for `syntax-rules` matching purposes.

**Why excluded:** The SRFI's own text states plainly: "No portable
syntax-rules-only implementation is possible." The mechanism requires
attaching a SRFI-213-style identifier property to each auxiliary keyword and
having a matching macro's literal comparison consult that property instead of
(or in addition to) ordinary hygienic identity — genuine identifier-property
support at the macro-expander level, not something a library can add on top
of `syntax-rules`. A reduced version that accepts the `define-auxiliary-syntax`
syntax but silently drops the cross-library matching (its entire reason to
exist) would be actively misleading rather than useful: everything it *could*
do is already achievable by writing an ordinary error-raising `define-syntax`
directly, with no import needed.

**Scope of change:** Would need a `free-identifier=?`-consulted property
table integrated into the expander's own literal-matching logic in
`expander.zig` — the same identifier-property support SRFI 213 needs
(issue #1699).

### SRFI 212 — Aliases

**Author:** John Cowan, Marc Nieper-Wißkirchen (2020)

Defines `(alias identifier1 identifier2)`, transferring `identifier2`'s
binding to `identifier1` so both share the same location — for any kind of
binding (variable, syntax, pattern variable), not just values. Mutating one
affects the other; unlike `define`, this is not a value copy.

**Why excluded:** The SRFI's own text states plainly: "A portable Scheme
implementation is not possible." True location-sharing across two
independently-scoped identifier bindings — especially for *syntax* bindings,
which `syntax-rules` has no way to introspect or reassign at all — is an
expander-level primitive in every implementation that has it (Chez, Kawa,
Unsyntax). A reduced version restricted to plain variables would still need
either a box-indirection scheme that only works for variables declared with
`alias` in mind from the start (not a faithful "alias an existing variable"
implementation), or expander access this codebase's `syntax-rules` doesn't
have.

**Scope of change:** Would need the same kind of expander-level identifier/
location introspection as `syntax-case`-based systems provide.

---

## Value-representation-dependent SRFIs (1)

This SRFI needs to construct and inspect specific NaN bit patterns (sign,
quiet/signaling, payload) — something Kaappi's own numeric value
representation makes categorically unrepresentable, not merely
unimplemented.

| SRFI | Title | Reason |
|------|-------|--------|
| 208 | NaN procedures | Needs raw NaN sign/payload bit access. Kaappi's NaN-boxing canonicalizes every NaN to one fixed bit pattern, discarding sign and payload — load-bearing for the value representation itself, not an oversight. |

### SRFI 208 — NaN procedures

**Author:** John Cowan (2020)

Defines `nan?` (already in R7RS), plus procedures to construct a NaN with
a specific sign/payload/signaling-ness (`make-nan`) and inspect those
same properties on an existing NaN value (`nan-negative?`, `nan-payload`,
`nan-quiet?`, etc.).

**Why excluded:** The spec's own text acknowledges this needs raw
floating-point bit-punning and isn't achievable in standard portable
Scheme even in C-backed implementations. In Kaappi it is categorically
worse: `makeFlonum` (`src/types.zig`) canonicalizes *every* NaN to a
single bit pattern (`0x7FF8000000000000`) before a `Value` for it can
even exist — not a missed feature, but load-bearing for the NaN-boxing
scheme itself (a non-canonical NaN's bits could collide with the tag
ranges used for pointers/fixnums/immediates and be misread as one of
those). Supporting `make-nan`/`nan-payload` faithfully would mean
redesigning the value representation's most foundational type, a far
larger change than anything else in this document. A reduced version
that only handles the single canonical NaN (erroring on any requested
negative sign, payload, or signaling variant) would provide nothing
`nan?` doesn't already give — the entire point of this SRFI is the
bit-level introspection, so a version that can't do any of it isn't a
smaller SRFI 208, it's a no-op.

**Scope of change:** Would require replacing the NaN-boxing value
representation (`types.zig`) with one that preserves full IEEE-754 NaN
bit patterns while still safely distinguishing flonums from
pointers/fixnums/immediates — a foundational rearchitecture, not a
bounded addition.
