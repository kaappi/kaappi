# R7RS Conformance

Kaappi implements every identifier from [R7RS Appendix A](https://small.r7rs.org/) — 641 built-in procedures, 32 syntax forms, and all 14 standard libraries. R7RS test suite: 1,391 pass, 0 fail.

---

## SRFI conformance

163 SRFIs supported. 12 built-in (native Zig), 149 portable (.sld files), plus SRFI 261 (Portable SRFI Library Reference) as an import-resolver convention with no library file, and SRFI 226 as sub-libraries only with no bare `(srfi 226)` file (so it doesn't appear as a bare number in `kaappi features`' scan, unlike every other portable SRFI). `(srfi srfi-<n>)` and `(srfi <mnemonic>-<n>)` — e.g. `(srfi srfi-1)`, `(srfi lists-1)`, `(srfi vectors-133)` — resolve to `(srfi <n>)`, with literal names winning when they exist. Coverage details for the built-in SRFIs follow.

### SRFI 1 — List Library

**Coverage: 95%** (71 of 75 spec procedures, excluding optional linear-update variants)

Implemented: `cons*`, `xcons`, `list-tabulate`, `circular-list`, `iota`, `proper-list?`, `dotted-list?`, `circular-list?`, `not-pair?`, `null-list?`, `list=`, `first`–`tenth`, `car+cdr`, `take`, `drop`, `take-right`, `drop-right`, `take-while`, `drop-while`, `split-at`, `last`, `last-pair`, `zip`, `unzip1`, `unzip2`, `count`, `fold`, `fold-right`, `pair-fold`, `pair-fold-right`, `reduce`, `reduce-right`, `unfold`, `unfold-right`, `map-in-order`, `append-map`, `filter-map`, `pair-for-each`, `filter`, `partition`, `remove`, `find`, `find-tail`, `any`, `every`, `list-index`, `span`, `break`, `delete`, `delete-duplicates`, `alist-cons`, `alist-copy`, `alist-delete`, `lset=`, `lset-adjoin`, `lset-union`, `lset-intersection`, `lset-difference`, `lset-xor`, `append-reverse`, `length+`, `concatenate`.

**Not implemented:**
- `unzip3`–`unzip5` — rarely used
- Linear-update (`!`) variants — SRFI 1 permits non-mutating implementations
- `lset-diff+intersection` — composite operation; use `lset-difference` + `lset-intersection`

### SRFI 9 — Records

**Coverage: 100%.** `define-record-type` is implemented as R7RS compiler syntax.

### SRFI 13 — String Library

**Coverage: 97%** (30 of 31 non-mutating spec procedures)

Implemented: `string-contains`, `string-prefix?`, `string-suffix?`, `string-trim`, `string-trim-right`, `string-trim-both` (with predicate or SRFI-14 char-set argument, UTF-8 safe), `string-index`, `string-index-right`, `string-skip`, `string-skip-right`, `string-count`, `string-split`, `string-join`, `string-concatenate`, `string-take`, `string-drop`, `string-take-right`, `string-drop-right`, `string-pad`, `string-pad-right`, `string-reverse`, `string-filter`, `string-delete`, `string-replace`, `string-titlecase`, `string-every`, `string-any`, `string-tabulate`, `string-unfold`, `string-unfold-right`.

All predicate-accepting procedures accept SRFI-14 char-set objects directly in addition to predicate procedures. Optional `start`/`end` index parameters are supported on all searching, filtering, and transformation functions.

**Not implemented:**
- `string-xcopy!` — mutation variant

### SRFI 27 — Random Numbers

**Coverage: 100%** (11 of 11 spec procedures). Full state save/restore via `random-source-state-ref`/`state-set!` (all 4 xoshiro256 state words). For exact `unit`, `random-source-make-reals` quantizes to **every** multiple of `unit` in the open interval `(0,1)` — `x·unit` for `x ∈ {1, …, ceil(1/unit)−1}`. This intentionally extends the spec's illustrative `{1, …, floor(1/unit)−1}` set (introduced with "One can imagine…", i.e. non-normative), which undershoots when `1/unit` is non-integral.

### SRFI 39 — Parameter Objects

**Coverage: 100%.** `make-parameter` (with optional converter) is exported; `parameterize` is compiler syntax.

### SRFI 69 — Hash Tables

**Coverage: 91%** (21 of 23 spec procedures). `hash-table-ref` correctly calls default thunk. `hash-table-merge!` overwrites existing keys. `string-ci-hash` uses Unicode case folding.

**Not implemented:**
- `hash-table-equivalence-function`, `hash-table-hash-function` — `make-hash-table` accepts but ignores custom comparator/hash arguments

### SRFI 133 — Vector Library

**Coverage: 97%** (31 of 32 spec procedures)

Implemented: All SRFI-133 procedures including `vector-unfold`, `vector-unfold-right`, `vector-binary-search`, `vector-concatenate`, `vector-cumulate`, `vector-partition`, `vector-swap!`, `vector-reverse!`, `vector-reverse-copy`, `vector-skip`, `vector-skip-right`.

**Not implemented:**
- `vector-append-subvectors` — composite append with subranges

### SRFI 170 — POSIX API

**Coverage: 85%** (68 of 80 spec procedures)

Implemented: File info (`file-info`, `file-info?`, `file-info-type`, all `file-info:*` accessors, type predicates), file operations (`create-directory`, `delete-directory`, `rename-file`, `create-symlink`, `read-symlink`, `create-hard-link`, `real-path`, `set-file-mode`, `truncate-file`, `create-fifo`, `set-file-owner`, `set-file-times`), process state (`pid`, `umask`, `set-umask!`, `current-directory`, `set-current-directory!`, `user-uid`, `user-gid`, `user-effective-uid`, `user-effective-gid`, `user-supplementary-gids`, `nice`), environment (`set-environment-variable!`, `delete-environment-variable!`), terminal (`terminal?`), user/group database, directory traversal (`open-directory`, `read-directory`, `close-directory`, `directory-files`), time (`posix-time`, `monotonic-time`), temp files (`temp-file-prefix`, `create-temp-file`).

**Not implemented (by design):**
- Process management (`fork`, `exec*`, `waitpid`, `_exit`) — unsafe in GC'd bytecode VM
- Signal handling — requires async-safe VM interrupt mechanism
- Pipes, I/O multiplexing — not exposed

### SRFI 18 — Multithreading

**Coverage: 100%** (35 of 35 spec procedures)

Implemented: **Threads** — `current-thread`, `thread?`, `make-thread`, `thread-name`, `thread-specific`, `thread-specific-set!`, `thread-start!`, `thread-yield!`, `thread-sleep!`, `thread-terminate!`, `thread-join!`. **Mutexes** — `mutex?`, `make-mutex`, `mutex-name`, `mutex-specific`, `mutex-specific-set!`, `mutex-state`, `mutex-lock!`, `mutex-unlock!`. **Condition variables** — `condition-variable?`, `make-condition-variable`, `condition-variable-name`, `condition-variable-specific`, `condition-variable-specific-set!`, `condition-variable-signal!`, `condition-variable-broadcast!`. **Time** — `current-time`, `time?`, `time->seconds`, `seconds->time`. **Exceptions** — `join-timeout-exception?`, `abandoned-mutex-exception?`, `terminated-thread-exception?`, `uncaught-exception?`, `uncaught-exception-reason`.

Uses real OS threads via `std.Thread.spawn`. Each child thread gets its own VM and GC with an independent heap. Values are deep-copied across thread boundaries at start and join.

### SRFI 254 — Ephemerons and Guardians

**Coverage: 100%** of the exported identifiers, across `(srfi 254)` and the component libraries `(srfi 254 ephemerons)`, `(srfi 254 guardians)`, `(srfi 254 transport-cell-guardians)`, and `(srfi 254 ephemerons-and-guardians)`.

Implemented: **Ephemerons** — `make-ephemeron`, `ephemeron?`, `ephemeron-key`, `ephemeron-value`, `ephemeron-broken?`, `ephemeron-ref`. The garbage collector retains an ephemeron's value only while its key is reachable through a path that does not pass through the value, so an ephemeron breaks even when its value references its key (the case a plain weak-key pair gets wrong). **Guardians** — `make-guardian`, `guardian?`; a guardian is itself a procedure, registering elements with `(g obj [rep])` and returning resurrected representatives with `(g)`. **Transport cell guardians** — `make-transport-cell-guardian`, `transport-cell-guardian?`, `transport-cell?`, `transport-cell-key`, `transport-cell-value`, `transport-cell-broken?`, `current-hash`. **Shared** — `reference-barrier`.

Kaappi's collector is non-moving, so `current-hash` is a stable identity hash and transport cell guardians are degenerate: a key is never transported, so a registered cell never breaks and a zero-argument transport-cell-guardian call always returns `#f`. On break, an ephemeron's key and value both read as `#f` (the value is cleared for memory safety once it is no longer retained).

### SRFI 258 — Uninterned Symbols

**Coverage: 100%** of the exported identifiers: `string->uninterned-symbol`, `symbol-interned?`, `generate-uninterned-symbol`.

An uninterned symbol is a symbol that is not `eqv?` to any other symbol, even one with the same name. Because Kaappi already compares symbols by object identity rather than by name, equality needs no special code — two uninterned symbols built from equal strings, and an uninterned symbol versus the like-named interned one, are all distinct. An uninterned symbol is an ordinary collectable heap object (it bypasses the permanent interning table), so it is reclaimed once unreachable. Per the SRFI, an uninterned symbol has no readable external representation: `write` emits an unreadable `#<uninterned-symbol name>` form and `read` signals an error on it, deliberately giving up write/read invariance.

### SRFI 260 — Generated Symbols

**Coverage: 100%.** Implemented: `generate-symbol` (optional `pretty-name` string argument).

Each call returns a fresh symbol whose name is unique "for all practical purposes" and unpredictable — a process-global atomic counter guarantees in-process uniqueness and 128 bits of OS entropy supply the unpredictability. Because Kaappi interns every symbol by name (it has no uninterned symbols), a generated symbol keeps **write/read invariance**: printed and read back, it is `eq?` to the original — the property that distinguishes SRFI 260 from uninterned symbols (SRFI 258). The optional `pretty-name` is a display hint used as the name's prefix; it never determines identity, so two calls with the same `pretty-name` still yield distinct symbols.

### SRFI 192 — Port Positioning

**Coverage: partial.** Implemented: `port-position`, `set-port-position!`, `port-has-port-position?`, `port-has-set-port-position!?`, all four using plain exact-integer byte offsets for every port kind. Not implemented: the spec's opaque "implementation-dependent object" alternative for textual-port positions, and the dedicated `i/o-invalid-position-error`/`make-i/o-invalid-position-error` condition type (any failure — an unsupported port or an out-of-range position — raises an ordinary error instead).

String ports track their own position for free (the existing read cursor and write length). Fd-backed ports get a real `lseek`-equivalent (POSIX `lseek`, Windows `_lseeki64`, WASI `fd_seek`), with the OS's raw offset corrected for whatever software buffering this port has read ahead of (peek/read-ahead buffers) or not yet flushed behind (the write buffer) — otherwise the reported position would drift from what a subsequent read or seek expects. `set-port-position!` on an output port flushes pending writes first, per spec, even when the position won't change.

### Portable SRFIs (149 libraries, plus SRFI 226 as sub-libraries only)

Loaded on demand from `.sld` files via `(import (srfi N))`. Sub-libraries: (srfi 146 hash), (srfi 166 pretty), (srfi 166 columnar), (srfi 166 unicode), (srfi 166 color), (srfi 171 meta), (srfi 226 control prompts), (srfi 226 control continuations), (srfi 226 control times), (srfi 248 primitives), (srfi 254 ephemerons), (srfi 254 guardians), (srfi 254 transport-cell-guardians), (srfi 254 ephemerons-and-guardians), (srfi 257 misc), (srfi 257 box), (srfi 257 rx), (srfi 263 syntax), (srfi 271 randomized), (srfi 271 determinized).

| SRFI | Title |
|------|-------|
| 0 | Feature-based conditional expansion |
| 2 | AND-LET* |
| 4 | Homogeneous numeric vector datatypes |
| 5 | A compatible let form with signatures and rest arguments |
| 6 | Basic string ports |
| 7 | Feature-based program configuration language |
| 8 | receive: binding to multiple values |
| 11 | Syntax for receiving multiple values |
| 14 | Character-set library |
| 16 | Syntax for procedures of variable arity |
| 17 | Generalized set! |
| 19 | Time data types and procedures |
| 23 | Error reporting mechanism |
| 26 | Notation for specializing parameters |
| 27 | Sources of random bits |
| 28 | Basic format strings |
| 29 | Localization |
| 30 | Nested Multi-line Comments |
| 31 | A special form rec for recursive evaluation |
| 34 | Exception handling for programs |
| 35 | Conditions |
| 36 | I/O conditions |
| 37 | args-fold: program argument processor |
| 38 | External representation with shared structure |
| 41 | Streams |
| 42 | Eager comprehensions |
| 43 | Vector library |
| 44 | Collections |
| 45 | Primitives for iterative lazy algorithms |
| 46 | Basic Syntax-rules Extensions |
| 48 | Intermediate format strings |
| 51 | Handling rest list |
| 54 | Formatting |
| 59 | Vicinity |
| 60 | Integers as bits |
| 61 | A more general cond clause |
| 62 | S-expression comments |
| 64 | A testing framework |
| 67 | Compare procedures |
| 70 | Numbers (reduced scope) § |
| 71 | Extended LET-syntax for multiple values |
| 78 | Lightweight testing |
| 86 | MU and NU simulating VALUES & CALL-WITH-VALUES |
| 87 | => in case clauses |
| 90 | Extensible hash table constructor (reduced scope) § |
| 94 | Type-Restricted Numerical Functions |
| 95 | Sorting and merging |
| 98 | Environment variables |
| 101 | Purely functional random-access pairs and lists |
| 111 | Boxes |
| 112 | Environment Inquiry |
| 113 | Sets and bags |
| 115 | Scheme regular expressions § |
| 116 | Immutable list library |
| 117 | Queues based on lists |
| 118 | Simple adjustable-size strings |
| 120 | Timer APIs |
| 123 | Generic accessor and modifier operators |
| 125 | Intermediate hash tables |
| 126 | R6RS-based hashtables (reduced scope) § |
| 127 | Lazy sequences |
| 128 | Comparators (reduced) |
| 129 | Titlecase |
| 130 | Cursor-based string library |
| 131 | ERR5RS Record Syntax (reduced) |
| 132 | Sort libraries |
| 134 | Immutable deques |
| 135 | Immutable texts |
| 136 | Extensible record types |
| 137 | Minimal Unique Types |
| 140 | Immutable strings |
| 141 | Integer division |
| 143 | Fixnums |
| 144 | Flonums |
| 145 | Assumptions |
| 146 | Mappings |
| 151 | Bitwise operations on exact integers |
| 152 | String library (reduced) |
| 153 | Ordered sets |
| 156 | Syntactic combiners for binary predicates |
| 158 | Generators and accumulators |
| 161 | Unifiable boxes |
| 162 | Comparators sublibrary |
| 165 | The Environment Monad |
| 166 | Monadic formatting |
| 167 | Ordered key value store |
| 168 | Generic tuple store database |
| 169 | Underscores in numbers |
| 171 | Transducers |
| 173 | Hooks |
| 174 | POSIX timespecs |
| 175 | ASCII character library |
| 178 | Bitvector library |
| 180 | JSON |
| 181 | Custom Ports (reduced scope) § |
| 185 | Linear adjustable-length strings |
| 188 | Splicing binding constructs for syntactic keywords |
| 189 | Maybe and Either |
| 190 | Coroutine generators |
| 193 | Command line |
| 194 | Random data generators |
| 195 | Multiple-value boxes |
| 196 | Range objects |
| 197 | Pipeline operators |
| 201 | Syntactic Extensions to the Core Scheme Bindings |
| 202 | Pattern-matching variant of the and-let* form |
| 203 | A Simple Picture Language in the Style of SICP |
| 207 | String-notated bytevectors (reduced scope) § |
| 209 | Enums and enum sets |
| 210 | Procedures and syntax for multiple values |
| 214 | Flexvectors |
| 215 | Central Log Exchange |
| 216 | SICP Prerequisites (Portable) |
| 217 | Integer sets |
| 219 | Define higher-order lambda |
| 221 | Generator/accumulator sub-library |
| 222 | Compound objects |
| 223 | Bisecting search |
| 224 | Integer mappings |
| 225 | Dictionaries |
| 226 | Control Features (reduced scope) § |
| 227 | Optional arguments |
| 228 | Composing comparators |
| 229 | Tagged procedures |
| 232 | Flexible curried procedures |
| 233 | INI files |
| 234 | Topological sorting |
| 235 | Combinators |
| 236 | Evaluating expressions in an unspecified order |
| 237 | R6RS Records (refined) |
| 238 | Codesets |
| 239 | Destructuring Lists |
| 240 | Reconciled Records |
| 241 | Match |
| 242 | The CFG Language (reduced scope) § |
| 244 | Multiple-value Definitions |
| 247 | Syntactic Monads |
| 248 | Minimal delimited continuations ‡ |
| 250 | Insertion-ordered hash tables |
| 251 | Mixing groups of definitions with expressions within bodies |
| 252 | Property testing |
| 253 | Data (type) checking |
| 255 | Restarting conditions |
| 257 | Simple Extendable Pattern Matcher with Backtracking |
| 259 | Tagged procedures with type safety |
| 263 | Prototype Object System |
| 264 | String syntax for regular expressions |
| 267 | Raw string syntax † |
| 270 | Hexadecimal Floating-Point Constants |
| 271 | Random port libraries |

§ SRFI 115 is matched by a backtracking interpreter, not by the reference
implementation's NFA, so it shares the cost profile of every backtracking
regexp engine: a pattern that nests quantifiers over the same span — the
classic `(: (* (* #\a)) #\b)` — takes time exponential in the input length
(about 16 s at 22 characters), because the outer repetition has exponentially
many ways to partition what the inner one already matched. Ordinary patterns
are unaffected, and repetition of a single-character body is scanned
iteratively rather than recursively, so `(* any)` over a multi-megabyte string
costs no stack. Don't build a regexp out of untrusted input.

The SRE syntax itself is complete. Three named char sets carry Unicode range
tables inside `lib/srfi/115.sld` (titlecase, symbol, and the UAX #29 grapheme
break classes) because R7RS `(scheme char)` exposes no general category
predicate and the library is portable Scheme; regenerate them with
`tools/gen_srfi115_charsets.py` after a Unicode version bump. `punctuation`,
`graphic`, `printing` and `control` remain ASCII approximations in a Unicode
context. `digit` and `*$` are chibi extensions, not SRFI 115 names, and are
correctly rejected.

SRFI 263 note: `(resend #f ...)` from a method inherited from a *non-immediate*
ancestor loops, because `resend` restarts the lookup skipping only the original
receiver — a distinct-origin lookup the finalized SRFI never specified. Resending
to an explicit target, and resend from a directly-overriding method, both work.

† SRFI 267 is a hybrid: the `#"X"…"X"` lexical syntax is built into the reader
(so raw-string literals work in any source file), while the port procedures
(`read-raw-string`, `write-raw-string`, `generate-delimiter`, …) load from the
`.sld` on `(import (srfi 267))`.

‡ SRFI 248's `with-unwind-handler` prompt is layered over stack-copying
`call/cc` via a sticky exception handler, with two caveats. (1) Delimited
continuations are effectively single-shot: each captured `k` may be resumed at
most once — re-entering it twice crosses a native frame that cannot be
re-entered after it returns, the same restriction as continuations captured
under native drivers (see README.md "Known limitations → Continuations"). Every
SRFI 248 idiom — coroutine generators, `for-each->fold`, effect handlers —
invokes each `k` once. (2) The handler runs at the raise point rather than after
unwinding to `with-unwind-handler`, so a handler side effect and a
dynamic-wind after-thunk of the guarded body run in the opposite order to what
the SRFI wording implies; the captured continuation itself is unaffected.

§ SRFI 226 (Control Features, 12 sub-libraries: prompts, continuations,
shift-reset, continuation-marks, parameters, fluids, promises, exceptions,
conditions, times, threads, thread-locals, interrupts) implements only
`(srfi 226 control prompts)`, `(srfi 226 control continuations)` (escape-only,
via Kaappi's own call/cc — no composable/re-entrant continuations), and
`(srfi 226 control times)` — see the header of `lib/srfi/226/control/prompts.sld`
for what's out of scope and why. SRFI 242 (The CFG Language) implements only the
static-label subset (`cfg`, `execute`, `halt`, `bind`, `label*`, `call`) — dynamic
labels (`labels`), `finally`, `permute`, and the `define-cfg-syntax*` extension
forms need either a dominance-based free-variable analysis or syntax-case-level
macro extensibility that a portable syntax-rules transformer can't provide; see
the header of `lib/srfi/242.sld`. SRFI 70 (Numbers) implements everything
except its 0/0-comparison-is-an-error clause, which directly conflicts with
the IEEE-754/R7RS NaN semantics Kaappi already correctly implements
(`(= +nan.0 +nan.0)` returns `#f` rather than raising) and which R7RS itself
superseded; see the header of `lib/srfi/70.sld`. SRFI 207 (String-notated
bytevectors) implements the `#u8"..."` reader syntax in full plus the four
procedures most directly tied to the notation (`bytestring`,
`bytevector->hex-string`, `hex-string->bytevector`,
`write-textual-bytestring`) — the full spec's independent ~25-procedure
bytestring-processing library (padding, trimming, search, join/split,
base64) is not implemented; see the header of `lib/srfi/207.sld`. SRFI 181
(Custom Ports) implements every custom-port constructor and the full
transcoded-port surface (`make-transcoder`, `native-transcoder`,
`transcoded-port`, `bytevector->string`/`string->bytevector`,
`i/o-decoding-error?`/`i/o-encoding-error?`/`i/o-encoding-error-char`,
`unknown-encoding-error?`/`unknown-encoding-error-name`) but only the UTF-8
codec — `latin-1-codec`/`utf-16-codec` are not exported at all, rather than
bound to a procedure that always fails; `make-codec` correctly signals
`unknown-encoding-error?` for any name it doesn't recognize, including
"latin-1"/"utf-16" by name; see the header of `lib/srfi/181.sld`. SRFI 90
(Extensible hash table constructor) implements `make-table` with `test`
and `hash` as ordinary positional optional arguments rather than SRFI 89's
named-parameter syntax (`test:`/`hash:`/...) — SRFI 89 is not implemented
(see `docs/dev/srfi-exclusions.md`) — and drops `size:`/`min-load:`/`max-load:`/
`weak-keys:`/`weak-values:` entirely, which the spec's own text permits
ignoring; see the header of `lib/srfi/90.sld`. SRFI 126 (R6RS-based
hashtables) implements the full non-weak baseline (every constructor,
accessor, mutator, and iteration procedure) but not weak/ephemeral
hashtables or the `#hasheq(...)`-style reader/printer syntax, both of
which the spec's own text says "cannot be implemented by portable library
code"; see the header of `lib/srfi/126.sld`.
