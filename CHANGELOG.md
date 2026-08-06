# Changelog

All notable changes to Kaappi are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Fixed

- **`(srfi 146 hash)` keys its tables with the comparator you passed** (#2044).
  Every constructor built a bare `(make-hash-table)` and stashed the
  comparator in the record, where `hashmap-key-comparator` handed it back —
  and nothing else ever consulted it. Key identity was always `equal?` with
  the native `equal?` hash, so under a comparator whose equality is `=` (or a
  case-insensitive string comparator) `1` and `1.0` stayed distinct keys and
  `Foo` never matched `foo`, while the ordered `(srfi 146)` library handled
  the same comparators correctly. All ten `make-hash-table` call sites across
  the nine constructors (`hashmap`, `hashmap-unfold`, `hashmap-map`,
  `hashmap-filter`, `hashmap-partition` — two tables, `hashmap-intersection`,
  `hashmap-difference`, `hashmap-xor`, `alist->hashmap`) now thread the
  comparator through, and the built-in SRFI-69 table falls into `.custom`
  mode calling the comparator's own equality and hash functions.

- **SRFI-113 bags can no longer hold negative multiplicities, and the three
  procedures that expanded a multiplicity no longer hang on one** (#2085).
  `bag-increment!` ignored the spec's "but not less than zero" clamp, so a
  negative count drove a multiplicity below zero and `bag->list`,
  `bag-for-each` and `bag-fold` — each looping `(= i count)` — never
  terminated, allocating without bound. `bag-product` was a second route:
  its `n` was never validated (the reference implementation's `valid-n`
  check discards its result), so a negative `n` multiplied every count
  negative. `bag-increment!` now drops the element when the result would be
  non-positive (matching `bag-decrement!`), `bag-product!` clamps a negative
  `n` at zero, and the three loops test `(>= i count)` so no count value can
  loop forever.

- **`first-ec`, `any?-ec` and `every?-ec` stop the comprehension early, per
  SRFI 42** (#2179). All three materialized the entire result first —
  `first-ec` expanded to `list-ec` and took `car`, and the two predicates
  ran the whole `do-ec` loop — so `(first-ec #f (:integers i) i)` and
  `(any?-ec (:integers i) (> i 5))` hung forever despite the spec giving all
  three early-exit semantics ("stop the loop after the first value"; "as
  soon as the result is known"). Each now allocates its own stop flag and
  sets it from the body, and the existing `%do-ec` flag mechanism unwinds
  every generator loop — including before the step, so a stopped
  comprehension never advances a side-effecting generator (`:port` reads
  exactly the datums needed, a `:dispatched` generator procedure is not
  called one extra time); the reference's `:until` fusion folds the same
  check into the loop's step test. One behavior change: `first-ec` now
  evaluates its `default` argument eagerly (it previously did so only when
  the comprehension was empty) — this matches the SRFI 42 reference
  implementation, which likewise seeds its result with `default`.

## [0.22.2] - 2026-08-05

### Added

- **The REPL now edits a whole form at once** (#2218). It ran on a vendored
  linenoise fork that read one physical line per call and joined continuation
  lines itself, so once Enter was pressed that line had left the editor: a typo
  on line 1 of a `define`, spotted on line 4, meant Ctrl-C and retyping the
  form. isocline holds the whole form in one buffer, so up and down move within
  it and reach history only at its edges, and a multi-line paste is drawn
  rather than folded to `[... N pasted lines ...]`. Completeness is now decided
  by `Reader.incomplete_input` — the same scanner the file path uses — retiring
  a second, hand-written 127-line Scheme scanner that had drifted from the real
  one twice (#358, #542).
- **Paredit-style structural editing in the REPL** (#2216): slurp
  (`alt+shift+S`), barf (`alt+shift+B`), raise (`alt+shift+R`) and rotate
  (`alt+y`) move a paren rather than a character. Rotate keeps the head and
  cycles the arguments, so repeating it restores the original. The transforms
  are pure functions over (buffer, byte cursor) and take `Reader.isDelimiter`
  directly, so strings, comments and character literals are understood rather
  than approximated. This needed the isocline migration first — on one editable
  physical line there is no whole form to restructure.
- **SRFI 41's `stream-map` and `stream-for-each` accept multiple streams**, per
  the SRFI, stopping at the shortest.
- **`kaappi test -j` / `--jobs <n>`** runs test files concurrently, defaulting
  to one job per CPU (#1887). Every file was already an isolated worker
  process, so this is a scheduling change only: verdicts, per-file output and
  its ordering, and the summary counts are identical at any job count — worker
  threads claim files from a shared counter while the main thread reports the
  completed prefix in file order. `--jobs 1` keeps the old strictly-sequential
  behaviour. Windows runs one job regardless, because there the worker's emit
  path still reaches the child through the inherited parent environment.
  Measured on 4 cores, `kaappi test tests/scheme/srfi` went from 18.5s to 4.6s.

### Changed

- **`kaappi test` and `run-all.sh` now agree on every file** (#1903). A file
  that raised an uncaught top-level error and then called `(exit 0)` was
  reported `PASS` by `run-all.sh`, which reads the process status, and `ERROR`
  with exit 1 by `kaappi test`, whose worker suppresses the exit and never
  consulted what the suppressed call had asked for. `run-all.sh` was right:
  `tests/scheme/errors/exit-code.sh` already pins "explicit `(exit 0)` wins
  over an earlier uncaught error", and `emitResult`'s own doc comment claimed
  `errored` covered a nonzero exit, which the code never implemented.
  A single `resolveVerdict` now weighs the counters, the recorded exit and the
  top-level error together. An `(exit 0)` waives only the file's *own*
  top-level error and can never bury a failing assertion, since the counters
  stay authoritative; the waived error is still reported, as a **note** printed
  under the verdict and tallied separately. This also closes the opposite
  divergence, which nobody had noticed: a file exiting nonzero with counters
  that do not explain it was `FAIL` under `run-all.sh` and silently `PASS`
  here. Across all 352 SRFI-64 files, disagreements went from 1 to 0. The
  summary's first line is now labelled `Tests:`, because `0 failed` (tests) sat
  directly above `1 failed` (files) with nothing naming the difference.

- **The handler and dynamic-wind stacks now grow on demand**, like the frame
  and register stacks, from an initial 64 entries up to 32768 (#1886). The
  initial capacities are configurable with `-Dmax-handlers` and
  `-Dmax-winds`, alongside the existing `-Dmax-frames` / `-Dmax-registers`.
  Fibers grow their own copies from a much smaller start, so the change also
  drops ~2.5 KB of preallocation per live fiber.
- **Exceeding a VM limit is no longer catchable** (#1886). A limit of the
  implementation is not a condition the program raised, so a stack overflow
  (`KP3008`) or an execution timeout (`KP3009`) now unwinds past every
  handler to the top level instead of being handed to a `guard` clause as
  `#<error "error">`. `thread-terminate!` likewise no longer runs the
  terminated thread's `guard` clauses on its way out. Genuine program faults
  — type errors, arity mismatches, unbound variables, division by zero — are
  unaffected and still catchable, as is an over-large allocation request such
  as `(make-vector 100000000000000)`.
- **A tail-position `apply` with more than 255 arguments reports
  `KP3007 invalid argument`, not `KP3008 stack overflow`** (#1886). The 255
  ceiling is what the `tail_apply` opcode's `nargs` byte can encode — a limit
  on one argument list, nothing to do with the stack — so
  `(apply values (make-list 300 #t))` was already sending readers to hunt for
  runaway recursion. It now says `apply: too many arguments (limit 255)`. It
  is an ordinary argument fault rather than a VM limit, so it stays catchable:
  it is also the bound that stops `apply` walking a circular argument list.
- **The `.sbc` bytecode cache is now transparent: a HIT behaves like a MISS**
  (#2110, #2111, #2112, #2113, #1922). Format v11 gives pair, string, vector
  and bytevector constants their immutability byte, so a `set-car!` on a
  literal raises `KP3002` warm exactly as cold; a shareable constant reached
  twice is emitted once and referenced by backref, so datum-label sharing keeps
  `eq?`, shared DAGs stay linear on disk (a 20-level DAG drops from 4.7 MB to
  474 B) and cyclic literals terminate and load; and list spines are walked
  iteratively on both halves, so a quoted list past 257 elements is cacheable.
  The writer now refuses — never truncates — anything the reader would reject,
  so an entry that recompiles forever cannot be written. Two files are no
  longer cached at all, because a HIT compiles nothing: one whose compilation
  registered a macro or syntax property (detected semantically, so a macro
  expanding into `define-syntax` is covered), and one with a top-level compile
  error, whose warm run used to execute the partial program with exit 0 and no
  diagnostic. `--timings` names the real reason. Runtime errors on the HIT path
  keep their `file:line` and snippet (#1922). Existing caches are invalidated
  by the format bump and regenerate on first use.
- **The printer is exact, iterative and cycle-safe, and `write-simple` is no
  longer an alias for `write`** (#1902, #1953, #1954, #1955, #2107). It
  silently truncated at fixed 1024-entry limits, recursed on the native stack,
  and its cycle pre-pass walked fewer containers than its print arms did — so
  an exact rational at nesting depth 1023 printed as `.../...` and read back as
  a symbol; a cycle reached only through an error-object irritant or a
  mutex/condition-variable name hung `write`, `display`, `write-shared` and
  `write-simple` alike; `write-simple` emitted the datum labels the spec
  forbids; and on wasm32 the recursion exhausted the 16 MiB shadow stack at
  depth 848 as an uncatchable module abort. One iterative, label-aware engine
  over a heap-allocated task stack now serves all of them, enumerating children
  through the same `childAt` the engine uses, so detection and printing cannot
  disagree about which edges exist. No capacity or depth constant remains on
  the exact path, and no native stack is consumed regardless of nesting.
  `write-simple` gets its own label-free implementation and raises a catchable
  error on cyclic input, where the spec anticipates non-termination.
- **`kaappi fmt` writes LF line endings** (#2093), on every platform, and says
  so.
- **All six shell completion scripts are generated from `src/cli_spec.zig` at
  comptime** (#2099). They were hand-written string literals parallel to the
  argument parsers and had drifted in both directions: `--no-ir-opt` and
  `kaappi test`'s `-j`/`--jobs`, `--changed`, `--list-affected`, `--since` and
  `--seed` were accepted by the CLI but offered nowhere, while zsh and fish
  offered the entire global flag set inside `explain`, `features`, `test`,
  `doctor` and `cache` — which parse their own argv and reject 15 of 16 probed
  flags with exit 2. `printUsage`'s `Options:` block, a fourth parallel list,
  is generated from the same table.

### Fixed

- **`thread-join!` no longer frees a joined thread's GC/VM while a thread it
  started is still running** (#2129, handle half). The v0.22.2 audit's first
  pass fixed the startup-prologue half by chaining every thread's shared
  symbol tables and maps to the root VM, but a descendant dereferences its
  own fiber handle — the dispatch-loop safepoint polls its `terminated` flag
  every 1024 instructions, and the terminal `status` store happens at exit —
  for its whole life, not just its prologue. That handle lives in the
  spawning thread's heap, so a join of a thread that had spawned another
  freed the grandchild's handle out from under it: a use-after-free for the
  grandchild's entire remaining lifetime (silent under the default
  allocator, a live crash under Guard Malloc), reachable from any ordinary
  "worker kicks off a background task and reports back" shape, and from
  `(srfi 120)`'s `make-timer` inside a thread. Each fiber now carries a
  `live_descendants` count (incremented at `thread-start!`, released by the
  child's exit defer once its own subtree drains); a join of a thread with
  live descendants **retires** its resources instead of freeing them, and
  the last descendant's defer frees them once the subtree drains — so the
  join still returns immediately and the retirement is bounded unless a
  descendant genuinely never finishes. `thread-join!` from inside a thread
  that spawned a timer now raises the documented "result contains an
  uncopyable type" error cleanly instead of aborting the process.

- **A record returned from a thread keeps its type** (#1932). `(thread-join!
  t)` on a thunk returning a `define-record-type` instance handed back a value
  that *printed* as a well-formed `#<<pt> 1 2>` while its predicate answered
  `#f` and every accessor raised `expected <pt>, got #<record_instance>` — so
  a `cond` dispatching on the predicate silently took the wrong branch. Record
  type identity was the `RecordType` address, and every thread boundary deep-
  copies into a separate heap, which necessarily changes it; a lexically
  captured predicate failed the same way on the way *in*, and the uncaught-
  exception path a third time. Identity is now a process-global counter
  carried across the copy, so all four boundaries (thunk capture, join result,
  raised object, channel message) preserve it. Generativity is untouched: two
  evaluations of a `define-record-type` form still make two distinct types.
  A `nongenerative` (SRFI 237 uid) type was the one working case before, and
  still works.

- **An FFI handle created on a child thread is no longer freed under the
  receiver** (#2027). `gc_deep_copy.zig` aliased `ffi-library` and
  `ffi-function` across heaps instead of copying them, on the reasoning that a
  dlopen handle cannot be duplicated per-heap — true of the handle, but the
  *wrapper* is an ordinary object owned by one GC, and marking skips
  foreign-owner objects. The receiver therefore held a reference neither
  collector could see: the sender's own collector reclaimed it, whether or not
  the sender had exited, and the recycled slot read back as `(0.0 . 0.0)` — an
  ordinary pair that passes `write` and every non-FFI type check, so a stored
  handle failed later with `KP3005: not a procedure`, at an arbitrary distance
  from the thread that produced it. The wrapper is now copied and the
  process-global handle and symbol address shared by value, at all three copy
  boundaries. A handle created on the *parent* and captured by a child kept
  working throughout and still does — which is why refusing FFI handles
  outright was not the fix. `ffi-callback` remains refused: it wraps a live
  Scheme closure, not a process-global address. One consequence: `ffi-close`
  now nulls the handle in one wrapper only, so a copy on another heap does not
  see the library as closed — closing a library another thread is calling was
  already undefined behaviour, and this moves where it is diagnosed.

- **SRFI 42's generic `:` qualifier works, along with `:real-range`,
  `:char-range`, `:dispatched`, and the full dispatch machinery** (#2177).
  `(list-ec (: i 5) i)` — the first form in every SRFI 42 tutorial — was
  `invalid syntax`, because the port defined only the typed qualifiers. The
  same fix revealed that three qualifiers the library already *exported* —
  `:port`, `:do`, and `:parallel` — had no expansion rules either and failed
  identically inside a comprehension; all three now work. `:` dispatches at
  run time on the argument types (lists, strings, vectors, exact-integer
  ranges, real ranges, char ranges, ports) through the SRFI's generator-
  procedure protocol, and the extension surface is complete:
  `:-dispatch-ref`, `:-dispatch-set!`, `make-initial-:-dispatch`,
  `dispatch-union`, and `:generator-proc` are exported, so user dispatchers
  compose per the spec. Typed generators also accept multiple arguments now
  (`(:list x '(1 2) '(3))` concatenates, per the spec). A zero step is
  rejected loudly in `:range` (matching the reference implementation) and
  in `:real-range` (going beyond it: the reference loops forever on an
  inexact zero step) — before, `(:range i 5 3 0)` spun forever yielding 5.
  `(:while (gen ...) test)` and `(:until (gen ...) test)` now stop only
  the generator they wrap, as the spec scopes them, instead of ending the
  whole comprehension — the bare `(:while test)`/`(:until test)` forms
  (this port's extension, absent from the spec's grammar) keep their
  stop-everything meaning, now documented. The spec's `(nested ...)`
  grouping and `(begin ...)` command qualifiers are implemented too. The
  `(index i)` variable form remains unsupported, and `:parallel` accepts
  only single-variable sub-generator forms — both documented in the
  library header.

- **`eqv?` now distinguishes an exact complex from an inexact one** (#2167).
  R7RS 6.1 requires `(eqv? a b)` to be `#f` whenever one number is exact and
  the other inexact, but every eqv?-semantics comparator — `eqv?`, `equal?`,
  `memv`/`assv`, compiled `case`, and SRFI 69 eqv-keyed hash tables — compared
  a complex number's two f64 components bitwise and never consulted the
  exactness flags, so `(eqv? (make-rectangular -3/2 -1) -1.5-1.0i)` was `#t`.
  The comparison was duplicated four times and every copy had the same gap;
  all four now share one `types.complexEqv`, which keeps the bitwise component
  rule (NaN and signed zero compare as before) and additionally requires the
  per-component exactness flags to match. `=` still treats them as
  numerically equal, as R7RS intends.

- **Negating an exact complex stays exact** (#2166).
  `(- (make-rectangular 3/2 1))` returned inexact `-1.5-1.0i`; R7RS — and the
  advertised `exact-closed`/`exact-complex` feature identifiers — require
  exact `-3/2-1i`. Unary `(- z)` and the `(- 0 z)` spelling now preserve the
  exactness flags: these are the two rounding-free cases (f64 negation is
  always exact), and an exact zero component normalizes to `+0.0` so the
  result stays `eqv?` to the same value built with `make-rectangular`. The
  rest of complex arithmetic still collapses to inexact — that is the
  f64-backed representation problem #2166 tracks, and two audit-suite
  expectations it had been masking (through the `equal?` bug above) are now
  `test-expect-fail` pending it.

- **`define-property` inside a top-level `cond`, `case` or `do` is no longer
  miscompiled by the native backend** (#1896). `isRejectedFormHead` was a
  hand-maintained list parallel to the comptime-derived
  `ir.eval_fallback_form_names`, and was missing that one name — so the form
  was emitted natively instead of deferring to the interpreter. The effect was
  observable with `display`: the property expression ran *after* the clause
  body under `kaappi compile` and *before* it under the interpreter, and a
  `do` loop containing one failed to compile at all (`KP9001`), since `emitDo`
  installs loop-variable locals before the eval fallback can run. The gate is
  now derived from the same comptime set, with six deliberate exclusions each
  carrying its reason in code, and a comptime block asserts
  `derived ⊆ rejected ∪ exclusions` so it cannot drift again.

- **On the WebAssembly build, `open-input-file`, `open-output-file` and
  `delete-file` now signal a file error** (#1972). R7RS 6.13 says these signal
  a condition satisfying `file-error?`, which is what they do on every native
  target, but the WASM build — which has no filesystem to reach — raised a
  *type* error instead: `expected non-WASM platform, got #<string>`, blaming a
  valid filename for the platform. So a portable
  `(guard (e ((file-error? e) …)) (open-input-file …))`, correct everywhere
  else, fell straight through to its caller on the playground. They now report
  `cannot open input file: this WebAssembly build has no filesystem access`
  (and the output/delete equivalents), keeping the path as the irritant. A
  non-string argument is still a type error, on every target.
- **`fd->port` reports its range rules as `KP3007 invalid argument`, not
  `KP3002 type error`** (#1972). `0` is a fixnum — exactly the type the
  procedure wants — so `expected socket/pipe file descriptor (> 2)` put a rule
  about the *value* where the expected type belongs. The two bounds are also
  now reported separately: `fd->port: descriptor 0 is a standard stream; 0, 1
  and 2 stay blocking`, and `fd->port: -1 is outside the file-descriptor
  range`. Its WebAssembly gate says `raw file descriptors are unavailable in
  this WebAssembly build` rather than naming a type. A genuinely wrong
  argument type is unchanged.
- **A `guard` clause now runs in its own `guard`'s dynamic environment**
  (#1988). R7RS 4.2.7 evaluates the implicit `cond` "with the continuation and
  dynamic environment of the guard expression", but a handler runs at the raise
  point, where every `parameterize` and `dynamic-wind` extent entered since is
  still live — and the clauses were evaluated there. A plain `raise` hid it,
  because this VM unwinds before calling any handler; the `raise-continuable`
  that a *declining* `guard` issues for its implicit re-raise does not, so an
  extent between an inner guard that declines and an outer one leaked into the
  outer guard's clauses. A `parameterize` between the two was visible to them —
  `(guard (e (#t (p))) (parameterize ((p 2)) (guard (e ((number? e) 'no))
  (raise 'boom))))` answered 2 where the same expression without the inner
  guard answered 1 — and a `dynamic-wind`'s after-thunk ran *after* the clauses
  instead of before them. Both extents are now left before the clauses run,
  without disturbing the frames the clauses stand on, so a clause may still
  reinstate a continuation captured inside the guard body — how `(srfi 255)`'s
  restarters work. One deviation remains, now written up under "Known
  limitations → Exceptions" in README.md: when no clause matches, the implicit
  re-raise happens in the guard's dynamic environment rather than the original
  raise's, which is what a plain `raise` already does here.
- **A `guard` that declines no longer strands an exception handler** (#1988).
  Its implicit re-raise popped the guard's own handler, called the outer one,
  and that handler escaped — but the popped handler was put back anyway, on top
  of a handler stack the escape had already restored. Every declining `guard`
  leaked one slot, so 32768 of them in a program hit the `KP3008` handler-stack
  cap, and a later `raise-continuable` that reached a stranded entry died with
  "escape continuation invoked outside its dynamic extent" instead of finding
  the real handler.
- **The "port I/O abandoned" error no longer blames `dynamic-wind`** (#1959).
  It named "guard, dynamic-wind, callbacks" as the frames a fiber cannot
  suspend under, but `dynamic-wind` is bootstrapped Scheme: its body runs in
  the bytecode dispatch loop and a fiber parks inside it exactly like a bare
  read. Anyone debugging this error was being sent to move blocking I/O out
  of a `dynamic-wind` for no reason, leaving it inside the `guard` that
  actually caused the drive. The message now names what genuinely opens a
  nested native frame: `guard`, and the native higher-order drivers (SRFI-1
  `fold`/`filter`/`find`, `hash-table-walk`, `assoc`/`member` with a custom
  predicate, `string-index`, `eval`). README's matching list also dropped
  `sort`, which is portable Scheme (SRFI 95) and parks too — a fiber
  blocking inside a `sort` comparator is now covered by the same test.
- **SRFI 237's record procedures now follow R6RS §6.3** (#1974). Four
  procedures deviated from the semantics SRFI 237 defines them as
  "equivalent to", each in a way that produced a wrong answer rather than an
  error. `record-type-field-names` returns a **vector**, not a list. An
  exact-integer `k` for `record-accessor`, `record-mutator` and
  `record-field-mutable?` indexes an rtd's **own** fields, per "note that `k`
  cannot be used to specify a field of any type `rtd` extends" — it indexed
  the whole instance, so on a subtype it silently returned an ancestor's
  field; that path now also rejects a non-rtd and an out-of-range `k`, both
  of which it accepted. An `opaque` record type is now actually opaque:
  `record?` answers `#f` for its instances, `record-rtd` raises, and a child
  of an opaque parent is opaque too. `record-mutator` raises for an immutable
  field instead of returning a mutator whose writes landed. The deprecated
  `make-record-constructor-descriptor` and `record-constructor-descriptor?`,
  and the 7-argument `make-record-descriptor`, are now provided. A record
  descriptor is accepted wherever a record-type descriptor is expected, and
  `record-constructor` accepts a bare rtd — including a syntactically defined
  type's own name, whose `(protocol ...)` it correctly applies — so the
  procedural and syntactic layers inherit from each other as the SRFI
  intends. Users of `record-type-field-names` must switch from list
  operations to vector operations, or wrap the call in `vector->list`.
- **Nested `guard` past 64 levels no longer returns a wrong answer** (#1886).
  The exception-handler and dynamic-wind stacks were fixed 64-entry arrays.
  Past that, `with-exception-handler` relabelled the overflow as
  out-of-memory and converted it into an ordinary Scheme error object — so
  the *enclosing* `guard` caught it, its `(#t ...)` clause returned a
  plausible value, and the program exited 0. A recursive procedure that
  wrapped its own recursive call in `guard` was silently incorrect rather
  than failing: a case that must return 0 at every depth returned `(0 1 37)`
  for depths 63/64/100. `with-exception-handler` had it worse — the overflow
  was invisible, the handler simply receiving a bare `#<error "error">`.
  `dynamic-wind` nested past 64 failed the same way.
- **`kaappi test` could have lost a file's results once it ran more than one
  worker at a time** (#1887). The path each worker writes its JSON to was
  published by setting `KAAPPI_TEST_EMIT` on the *parent* before each fork — a
  single mutable global shared by every in-flight worker, so two concurrent
  spawns would have sent both children to the same path. It now travels in the
  child's own `envp`. Not reachable before `--jobs` existed, since spawns were
  serialised.
- **`(srfi 14)` is a character set again, is Unicode-aware, and exports its
  whole API** (#1895). The old 108-line library was a multiset — `(char-set
  #\a #\a #\b)` kept the duplicate, and union with itself grew without bound,
  so every downstream size, fold and count was wrong. It was also ASCII-only,
  `char-set:full` included: `#\λ` was not in it, and `char-set:letter` stopped
  at `z`. And it exported 23 of the SRFI's 64 names while `(cond-expand
  (srfi-14 ...))` answered yes, so portable code was told the library was there
  and then handed a multiset. A char set is now an inversion list — a sorted,
  disjoint, non-adjacent list of `(lo . hi)` code-point pairs — which makes
  duplicates unrepresentable rather than merely filtered, and makes
  `char-set:full` and `char-set-complement` two pairs instead of 1.1 million
  list cells. All 64 spec names are implemented, including the cursor
  protocol, `char-set-unfold`, `char-set<=`, `char-set-hash`,
  `char-set-diff+intersection`, `ucs-range->char-set`, the `!` linear-update
  variants and the 17 standard `char-set:*` constants. The constants come from
  generated Unicode general-category tables, which is how the SRFI defines
  them, so `char-set:letter` is Lu/Ll/Lt/Lm/Lo and `char-set:digit` is all of
  Nd — both deliberately *broader or narrower* than the nearest `(scheme
  char)` predicate, since R7RS asks those predicates a different question.
  Surrogates are excluded throughout, since `integer->char` rejects them.
  Import cost is unchanged and every char set is immutable once built.
  `tools/gen_srfi115_charsets.py` is now `tools/gen_srfi_charsets.py`, with a
  `--target {115,14}` selector.
- **Three diagnostics that misdescribed the value or the procedure they were
  about** (#1916). An integral flonum rendered in a type error without its
  `.0`, so `(vector-ref v 1.0)` reported "expected exact integer, got 1" —
  and 1 *is* an exact integer, leaving the message arguing against itself.
  Error messages now render flonums through the printer, so `1.0`, `+inf.0`
  and `1.0e+30` read as they do everywhere else; this affects every type
  error, not just the numeric-vector ones. Separately, a multi-limb bignum
  handed to a `(srfi 160)` constructor was reported as "expected exact
  integer, got #<bignum>" — it is an exact integer, and its only fault was
  not fitting the element kind, so it now says "in-range" (or "non-negative"
  when the value is negative), matching what an out-of-range fixnum has
  always said. Finally, `%record?` and `%transcoded-port` reported their
  errors under the names `record?` and `transcoded-port` — each a real and
  *different* procedure, exported by `(srfi 237)` and `(srfi 181)`
  respectively, with a different argument list — so a reader who followed the
  message landed on the wrong procedure. Both now name themselves, via the
  shared-constant convention `primitives_srfi237.zig` already used for
  exactly this reason.
- **Port errors now say which kind of failure they are** (#1944).
  `primitives_io.zig` reported every failure as a type error, so three
  distinct faults all arrived mislabelled. Seeking a string port past its end
  raised a detail-less `invalid argument in 'set-port-position!'` — no index,
  no length — and now reports both, as `KP3006`. `(write-string "abc" port 5)`
  said `expected valid range, got #<string>`, blaming the one argument that
  was valid; the offending *index* is named now, with an inverted-but-in-range
  pair (`… port 2 1`) reported as `start 2 is greater than end 1` rather than
  as a range fault. And using a closed port was `KP3002 type error: expected
  open input port, got #<port>` — a closed port is a port, so it is `KP3007
  invalid argument` ("input port is closed"). Passing a genuine non-port, or
  an input port where an output port is wanted, is still a type error.
- Three internal guards in `primitives_io.zig` no longer blame the program for
  a broken interpreter (#1944). A missing VM or GC in the fiber-park I/O path
  reported `KP3007 invalid argument`; per the rules settled in #1874/#1876/#1878
  these are `KP9001 internal error` and out-of-memory respectively — the same
  tags the byte-for-byte twin helper 950 lines down the same file already used.
  Unreachable in a working build; the tag is what the next maintainer reads.
- **Four ordinary programs no longer abort the process** (#1973, #1976, #1983,
  #2185). All four were unguarded narrow arithmetic at a representation
  boundary, each an exit-134 abort invisible to `guard`: the first instance of
  any record with 27 or more fields (the allocation was sized in `u8`
  arithmetic, and under `ReleaseFast` it corrupted GC accounting silently);
  `file-info` on any devfs path, because a signed `dev_t` was cast into `u64`
  and macOS `/dev/null` stats as `st_dev = -1296473318`; SRFI-18's
  `seconds->time` and `thread-sleep!` on out-of-range values, which now
  saturate or raise per procedure; and calls at the 255-argument ISA limit.
  254 fields is the construction ceiling everywhere, loudly.
- **Non-positive segment sizes are rejected across SRFIs 152, 160, 178 and
  196** (#1949, #2084, #2172). Each loop advances by the size per iteration, so
  `n = 0` never advanced — an unbounded-allocation hang for `%uvec-segment` on
  all 12 element kinds, `string-segment` and `range-segment`, and unbounded
  recursion into an uncatchable `KP3008` for `bitvector-segment`. All four now
  raise a catchable error for any size that is not an exact positive integer,
  as SRFI 171's `tsegment` already did. `bitvector-segment` also consed outside
  its recursive call, so a legal call on a 200,000-bit vector died with a stack
  overflow; it now accumulates in tail position.
- **`(read port)` is safe across the 4096-byte chunk boundary** (#1893, #1920,
  #1940, #1945). The incremental read loop refills on exactly `UnexpectedEof`
  and treats every other outcome as final, and tokens straddling a boundary
  broke that both ways: scanners reporting truncation as a different error made
  valid files unreadable (strings, dotted pairs, split UTF-8 codepoints, raw
  and byte strings, `#`-prefixes), while scanners treating end-of-buffer as a
  terminator silently split symbols, numbers, characters and booleans — and fed
  a line comment's tail back in as program data. One new `incomplete_input`
  reader mode, set only by the chunk loop, replaces per-site patches: never
  finalize a token more bytes could extend, never reject one more bytes could
  complete. The whole-input parse at EOF keeps today's precise errors.
  Relatedly, exhausted input where `)` belongs is now `UnexpectedEof` in every
  mode, the error object names what failed (`read error: unterminated string
  literal`) instead of a bare `read error`, and a trailing `#!` directive
  yields the EOF object rather than a spurious error.
- **The reader's `#e` and `#i` prefixes agree with `string->number`** (#1891,
  #1907, #1908, #1909, #1910, #1911, #1921). Each had its own `applyExactness`
  with a structurally different strategy — `string->number` rebuilt exact
  values from the decimal digits, while the reader parsed to `f64` first and
  un-rounded it with a continued fraction under a fixed tolerance — so R7RS
  §6.2.7's requirement that the two agree was met only by coincidence, and
  every past fix had landed in one copy at a time. The reader now re-parses
  through `parseNumberText`, `string->number`'s own body, so `#e` no longer
  drops precision past `i64`, `#i` honours the radix, and the off-by-one panic
  at the 2^63 guard that aborted `check`, `fmt` and `ast` is gone. Complex
  tokens keep their own wider grammar, where exactness is the two flags and
  `#e` refuses non-finite parts.
- **Six port-layer defects, each a branch never written for a port without an
  fd** (#1941, #1942, #1943, #1995, #1997, #1998). Custom and transcoded ports
  both carry the `fd = -1` sentinel, so a path missing their branch syscalled
  on -1, got `EBADF`, and reported it as ordinary end of input or as nothing at
  all. `read` returned `#<eof>` on every custom and transcoded port, because
  `readDatumFn` is the one input primitive that bypasses `readOneByte` and its
  refill never invoked the `read!` callback even once. A `crlf` transcoder's
  encode half converted only `#\newline` while its decode half already handled
  bare CR, bare LF and CRLF, so a round trip doubled every line break; a CRLF
  split across two writes now stays one line ending. And `flush-output-port` on
  a transcoded port was a silent no-op.
- **Two custom-port callback shapes no longer abort the process** (#1939,
  #2000) — including a channel receive performed inside a callback.
- **SRFI-69 hashing agrees with the table's equality again** (#2023, #2024,
  #2025). The depth cutoff returned the *pointer* of whatever sat at depth 8
  while lookup compares with `deepEqual`, so two `equal?` keys whose structure
  reached that depth hashed to unrelated buckets and the stored entry became
  unreachable — 200 of 200 twelve-element keys unfindable, and the same through
  `(srfi 125)`, `(srfi 126)` and `(srfi 146 hash)`. A list spine is now walked
  iteratively, so length no longer spends the nesting budget; SRFI 160 numeric
  vectors, compared structurally but with no hash arm at all, are covered too.
  `rehash` no longer calls a hash procedure that can mutate the table it is
  rebuilding, and a hash procedure returning a negative value is handled rather
  than indexing out of bounds.
- **Three cross-heap uses that the owner checks were missing are now refused**
  (#1934, #2001, #2008). The globals map is shared by pointer, so a thunk that
  merely *names* a top-level binding hands a child the parent's own object, yet
  only channels and thread handles compared `Object.owner` against the running
  GC. `fiber-join` was the worst, because the API itself performs the hand-off:
  it returned the parent's heap object to the child as its documented result,
  so a `set-car!` in the child was observed by the parent — and a still-running
  foreign fiber was reported as a deadlock, sending the reader to hunt a cycle
  that does not exist. `invokeGuardian` mutated a shared guardian's registry
  with the calling thread's allocator and no lock, aborting the process 5 times
  out of 5 with empty output, and left the parent holding a pointer into a
  freed child arena.
- **Two GC roots the collector could not see** (#2160, #2161). SRFI-1's
  accumulators and the uid registry held heap values in memory outside the
  root set, so a collection at the wrong moment freed live data.
- **Four SRFI-18 concurrency defects** (#1982, #2125, #2194). `thread-join!` on
  a never-dispatched `(kaappi fibers)` fiber polled `fiber.status` in a sleep
  loop without ever driving the cooperative scheduler — and that scheduler is
  the joining thread's own, so the status could never change and the join hung
  forever (or timed out) on a fiber that would have completed instantly, while
  `fiber-join` on the same object returned at once. `thread-terminate!` could
  not interrupt a native wait, and a fiber's thread-handle identity was not
  recoverable from the fiber itself.
- **Arity is validated in the two call paths that build their frames by hand**
  (#1999, #2034). `callHandler`, `callThunk` and the fiber scheduler's
  `spawnFiber` inherited none of `callClosure`'s check, so a wrong-arity
  procedure ran anyway with its surplus parameters reading whatever the
  register file held — a live value from a neighbouring frame, not an undefined
  slot, because the hand-built frames also never cleared past the staged
  argument. A 3-argument exception handler received the caller's `list`
  procedure as its third argument, deterministically. Every re-entrant frame
  now binds through one helper that validates arity and folds surplus arguments
  into a variadic callee's rest list, covering the `with-exception-handler`
  handler, the `call-with-values` producer, and the `call/cc` and `call/ec`
  receivers in non-tail position. `with-exception-handler` and
  `%call-with-unwind-handler` check their thunk before installing the handler,
  so a bad thunk is not swallowed by the handler it just installed.
- **The native backend's re-lowered bodies get their enclosing lexical scope**
  (#2117, #2118, #2211). The LLVM backend re-lowers every lambda, closure and
  `let` body from a raw S-expression during emission, and the two IR fields
  standing in for the absent `Compiler` were both under-supplied: `bound_names`
  held only the immediate frame's parameters, so a binding one level out was
  invisible to both the constant-fold gate and the special-form-versus-call
  dispatch, and `set_targets` was never supplied at all, so a `set!` in the
  enclosing body did not suppress a later fold. Both are now derived from the
  maps the emitter already resolves against, rather than kept as parallel lists.
- **`--compile` and `--disassemble` no longer run program code** (#2114,
  #2156). Three of the eight top-level heads the dispatcher claims carry
  ordinary code, and both flags routed all eight through the *evaluator* — so a
  `delete-file` inside a top-level `begin`, `cond-expand` or `define-values`
  ran for real while the artifact was produced, and was recorded in the
  preamble too, so across compile and run the effect happened twice. A bare
  top-level `(delete-file ...)` was never executed, which is what made this the
  dispatcher's fault rather than "compiling runs the program". `begin` and
  `cond-expand` are now spliced into the driver's form stream and compiled;
  only the five declarations later forms are compiled against are evaluated.
  This also repaired an ordering divergence, since the preamble replays
  entirely before the compiled forms.
- **REPL: comma-command TAB completion replaces rather than appends** (#2224),
  and **pasted input is no longer discarded when the REPL leaves raw mode**
  (#2226) — a multi-line paste that submitted partway through silently lost its
  still-unread tail.

## [0.22.1] - 2026-07-31

### Added

- **`(kaappi primitives)`**, a library exposing the `%`-prefixed internal
  primitives that portable `.sld` files name in their own Scheme source —
  SRFI 27's random-source accessors, SRFI 74's endianness probe, SRFI 271's
  random ports, and the record substrate SRFI 57/131/136/150/237 build on
  (#1856). Each such library now declares the dependency it actually has.

### Changed

- **`(scheme base)` no longer exports 22 `%`-prefixed internal primitives**
  (#1856). Since v0.22.0 also began enforcing R7RS 5.2, any user library that
  defined one of those names and imported `(scheme base)` failed to load
  outright — the documented C-extension walkthrough, whose example exported
  `%length`, was one such casualty. `%` is this codebase's own private-helper
  marker, so user code has good reason to treat that namespace as its own. The
  names are now registered in `vm.globals` and exported by nothing, or
  re-exported from the new `(kaappi primitives)` where a portable `.sld` names
  them; `%length` is deleted outright, with case-lambda's arity dispatch
  referencing `length`'s pristine `(scheme base)` binding instead. Unexporting
  alone would have converted a loud error into a silent wrong answer, so
  compiler-synthesized references now resolve against a pristine startup
  snapshot rather than `vm.globals` — a user library defining its own
  `%record-ref` no longer captures `define-record-type`'s accessors. A comptime
  check rejects any `%` name tagged with a `scheme.*` library, and `kaappi
  check` no longer reports KP4001 on base-binding-prefixed references.
- **An uninitialized runtime is reported as KP9001 "internal error", not as a
  caller's type error** (#1874, #1876, #1878). The ~450 threadlocal
  `vm_instance` / `gc_instance` guards had drifted into an arbitrary
  TypeError/OutOfMemory split for the same "the runtime is not initialized"
  failure. A guard now returns the tag its function was going to return anyway;
  where there is none, `InvalidBytecode` → KP9001, whose registry text ("please
  report it") is the right instruction. This is user-visible for `apply` and
  for the 9 bootstrap-installed procedures, which previously reported KP3002 —
  and, setting no detail, let `mapNativeError` synthesize `type error in 'map':
  got <args[0]>`, naming a real list element as the culprit. KP9001's own
  template changes from "internal compiler error" to "internal error", since
  KP9xxx is now reached from the runtime too. No behavior change in a working
  build: the threadlocals are set during VM init, before `registerAll`. The
  rule is written down in `docs/dev/gc-safety-and-error-handling.md`.
- **A sealed parent rtd and a `nongenerative` uid collision report KP3007
  (invalid argument), not KP3002 (type error)** (#1880). Neither is a type
  error — both arguments are of a perfectly good type and the procedure rejects
  them anyway — and R6RS's own wording for the first is "an exception is raised
  if parent is sealed". Both previously reported a bare `error[KP3002]: type
  error` and nothing else: no procedure, no expected type, no value. The
  syntactic and procedural routes now share one statement of each rule, so a
  caller who wrote `define-record-type` is not told about the internal
  primitive it desugars to, and a uid collision names the one axis that
  actually differs rather than listing every axis it might have been. A third
  condition of the same shape — more than 255 fields once a parent's are
  counted — is fixed with them.
- Six oversized source files are split along their natural seams (#1853):
  `memory.zig` → `gc_alloc.zig`, `expander.zig` → `expander_instantiate.zig`,
  `llvm_emit.zig` → `llvm_emit_forms.zig`, `vm_library.zig` → `vm_imports.zig`,
  `compiler_macro.zig` → `compiler_define_syntax.zig`, and `gc_collect.zig` →
  `gc_sweep.zig`. Pure code motion, no behavior change — same-name aliases keep
  every call site compiling as-is.
- The three "add a built-in procedure" docs are corrected (#1863). Two taught
  code that cannot compile, including symbol names that never existed
  (`primitives.gc_instance`, `primitives.vm_instance`) and a
  `return PrimitiveError.TypeError` the `format` CI job exists to reject.
  `docs/dev/adding-features.md` is now the one detailed reference; `CLAUDE.md`
  and the `/add-builtin` skill defer to it. Every sample was verified by
  compiling it.

### Fixed

- **A valid R7RS record was rejected when its constructor was named `fields`,
  `parent`, or another R6RS clause keyword** (#1882). SRFI 237's R6RS clause
  grammar is ambient — `(scheme base)`'s `define-record-type` accepts it with no
  `(import (srfi 237))` — so the two syntaxes are told apart structurally, and
  the syntax detector inspected only the head of the form's 2nd element, which
  in R7RS syntax is the *constructor's* name. `(define-record-type point (fields
  x y) point? (x point-x) (y point-y))` was therefore parsed as R6RS and
  rejected with a bare
  `KP2001: invalid syntax`, in a program with nothing to suggest the R6RS
  grammar was in play; the follow-on `undefined variable 'fields'` and its `Did
  you mean 'yield'?` pointed away from the cause. The 3rd element now decides:
  R7RS always has one and it is always the bare-symbol `<predicate>`, while an
  R6RS `<record clause>` is always a list — or absent, when there is at most one
  clause. That is a pure narrowing, so no R6RS form and no malformed form
  changes path, and no diagnostic changes. In a body the same misdetection also
  aborted the internal-define scan, so sibling `define`s written after the
  record lost their mutual visibility; in a library body, where the R6RS grammar
  is rejected outright, the whole library failed to load.
- **Native backend: `(define (f …) …)` in a `let` or lambda body compiled to a
  global define** (#1861). An internal definition overwrote an outer one of the
  same name instead of shadowing it, and a helper referencing an enclosing
  binding compiled to a global function whose body looked that binding up as a
  global, so `(let ((a 3)) (define (h n) (* n a)) (h 5))` died with `undefined
  variable 'a'` in a compiled binary while the interpreter ran it. Issue #819
  fixed this class for the symbol form, but `lowerDefine` turns a pair target
  into a `.passthrough`, so the shorthand never reached that path. The form now
  declines whenever a lexical scope is active — a lambda body has no locals map
  and is lexical because of its params, and had the identical bug — handing the
  enclosing scope to the interpreter whole.
- **Native backend: a nested `let` that fell back to the interpreter lost the
  enclosing `let`'s bindings** (#1862). When a `let` inside another `let` gave up
  on native compilation mid-emission — more than 32 bindings, more head
  `define`s than the scope roots, or any binding/body form the emitter could not
  lower — the LLVM backend handed that inner form alone to `kaappi_eval`, which
  resolves names in the global environment. The compiled binary then died with
  `undefined variable` on the outer binding, or, with a same-named global in
  scope, silently read that instead; the interpreter ran the same program
  correctly. `bindParamsAsGlobals` republishes the frame's params, rest
  parameter, and upvalues, but a `let`-local lives in an `alloca` it has no name
  for, so it now declines when one is in scope. The error abandons the enclosing
  `let` in turn, handing the interpreter that whole lexical scope in one piece —
  the rule #827 already applied to everything an up-front syntactic scan can
  see, now applied to the mid-emission escape hatch as well. A fallback inside a
  plain lambda frame, where the params *are* publishable, still compiles the
  lambda natively and is unaffected.
- **Native backend: an internal `define` in a `let` body could be collected**
  (#1854). The LLVM backend gave the binding an `alloca` but never pushed it on
  the GC shadow stack, so a collection triggered anywhere later in the body
  freed the value it held and the memory was recycled into whatever the body
  allocated next — a wrong answer in a compiled binary, with no crash and no
  divergence in the interpreter. `emitLet` now mints and roots these slots
  alongside the `let`'s own bindings; a `define` outside the head of the body
  (where R7RS puts internal definitions) routes the whole form to the
  interpreter rather than compile to something unrooted.
- **A library body could not reference a global it had not imported from its
  own top level** (#1860) — the identical reference from inside a `lambda` in
  the same body worked, so a name like `cadar` or a `%`-prefixed internal
  primitive resolved or raised `undefined variable` depending only on where in
  the body it was written. #1831 gave the three global-reference opcodes one
  resolver with a `vm.globals` fallback for library code, but gated it on a
  flag derived per-function: it landed on the outer function of each
  library-body form and on none of the closures inside it. The flag is now a
  property of the environment, set from a `library`-vs-`restricted` distinction
  at the one compile entry point that has it and inherited by every nested
  function. This also closes the same gap in the other direction: a restricted
  `(environment ...)` withheld a name from the expression's own top level and
  handed it over through a `lambda`, and now withholds it from both.
- **Every type error names the expected type, and the right argument** (#1868).
  A bare `TypeError` was never as anonymous as it looked: `mapNativeError`
  already fills in `type error in '<primitive>': got <args[0]>`, so the
  procedure name survives but the *expected* type is lost — and whenever the
  offending value is not the first argument, the report confidently names the
  wrong one. A string-keyed hash table handed a bad key blamed the table
  itself:

  ```text
  -  type error in 'hash-table-set!': got #<hash-table size=0>
  +  type error in 'hash-table-set!': expected string key
       (this table compares with string=?), got 1
  ```

  All 20 remaining bare returns are resolved — 11 became real diagnostics, 9
  infrastructure guards carry a stated `// bare-ok:` reason — so the CI ratchet
  loses its baseline and becomes a plain grep-and-fail.
- **A timed wait whose deadline the dispatch tick had already popped parked
  unbounded** (#1870). `runSchedulerStep` spends its loop guard on the pre-tick
  state, so when the tick popped *this* fiber's deadline the idle branch went
  into `parkOnReactor` with nothing left to bound `reactor.poll()` — and the
  fiber's own waiter entry kept `hasRunnableFibers()` true, skipping the
  "nothing can ever happen" early return. This was the `(srfi 120)` flake: a
  timer thread parked for a 30 ms task slept until an unrelated cross-thread
  notify arrived, by which point delivery-wins handed it the `stop` message and
  the task never ran. Measured on the Windows ARM64 reference VM, one timer per
  iteration: 4 wedges in 13,500 iterations before, 0 in 9,000 after.
- **The fiber scheduler leaked when its setup allocation failed** (#1864).
  `ensureScheduler` runs two more fallible steps before `vm.scheduler` is
  assigned, so a failure in either returned with the struct neither destroyed
  nor stored, leaking it and the managed waiter-index map built inside it. Low
  severity on its own — a real OOM during the first spawn — but it blocked
  writing any OOM-sweep test that reaches a fiber path, since the leak check
  aborts the test before its own assertions run.
- The GC root stack is now unwound when an error escapes the compile/eval
  pipeline (#1855). The canonical `pushRoot` / `try` / `popRoot` rooting
  pattern leaks its root when the *protected* allocation is the one that
  fails: the error unwinds past the `popRoot`, leaving the root stack holding
  the address of a local in a frame that no longer exists for the next
  collection to dereference — and shifting the stack so that every pending
  `defer popRoot()` above it removes the wrong entry. The four
  `compileExpression*` entry points, `vm_eval.eval`, and `vm_calls.execute`
  now snapshot the root depth on entry and truncate back to it when an error
  escapes, rather than adding an errdefer to each of ~340 push sites. Only
  reachable under out-of-memory; the confirmed leak sites were in
  `syntax-rules` ellipsis instantiation.

## [0.22.0] - 2026-07-30

### Added

#### SRFI coverage: 85 → 178

This release adds 93 SRFIs — 12 built-in and 162 portable `.sld` libraries,
plus SRFI 261 as an import-resolver convention and SRFI 160, 211, and 226 as
sub-libraries only. It closes four tracking issues outright: #1694 (numeric
vectors and arrays), #1695 (records), #1699 (macro and syntax extensions),
and #1703, along with #1702 and #1810. A new `docs/dev/srfi-exclusions.md`
documents the other side of that work: all 30 SRFIs examined and deliberately
excluded, each with a written rationale — reader-syntax SRFIs that would
reinterpret already-valid syntax, macro-system SRFIs whose own spec text says
a portable `syntax-rules` implementation isn't possible, and two superseded
outright by their successors. Every supported SRFI is also a `cond-expand`
feature identifier `srfi-<n>`.

##### Macros and syntax extensions (issue #1699, closed)

- **SRFI 147 (Custom macro transformers)** — extends R7RS's `<transformer
  spec>` grammar so `define-syntax`/`let-syntax`/`letrec-syntax` accept a
  macro use that itself expands to a `syntax-rules` form, a bare keyword
  aliasing an existing one, or a `(begin <definition>... <transformer-spec>)`
  wrapper. Lets a library define its own transformer-generating transformer.
- **SRFI 148 (Eager syntax-rules)** — `em-syntax-rules` and ~110 `em-`
  combinators over a CK-machine core, giving `syntax-rules` macros eager
  evaluation of compile-time expressions. Ported from the reference
  implementation with four confirmed upstream bugs fixed (documented with
  evidence in `lib/srfi/148.sld`'s header); 134 of the reference suite's
  assertions pass.
- **SRFI 211 (Scheme macro libraries)** — the first *procedural* macro
  transformers in Kaappi. `(srfi 211 explicit-renaming)`,
  `(srfi 211 define-macro)`, and `(srfi 211 syntax-parameter)` ship as
  sub-libraries; an `er-macro-transformer`'s `rename` reuses the same
  hygiene machinery `syntax-rules` templates get. The remaining eight
  sub-libraries need syntax objects or output-provenance tracking a
  symbol-based expander cannot honestly provide, and are not exported.
- **SRFI 213 (Identifier properties)** — `define-property` and `lookup`,
  attaching compile-time properties to an identifier. Reachable only from a
  procedural transformer, per the spec.
- **SRFI 139 (Syntax parameters)** — `define-syntax-parameter` and
  `syntax-parameterize`, letting a macro's referentially-transparent
  identifier be rebound for a bounded extent (the `abort`/`return` pattern).
- **SRFI 149 (Basic `syntax-rules` template extensions)** — consecutive
  ellipses after one template element (`a ... ...`), and a pattern variable
  followed by more ellipses in the template than its matched depth.
- **SRFI 46 (Basic `syntax-rules` extensions)** — a custom ellipsis
  identifier and a tail pattern after an ellipsis.
- **SRFI 188 (Splicing binding constructs for syntactic keywords)** —
  `splicing-let-syntax` and friends, whose bindings splice into the
  surrounding body rather than opening a new scope.
- **SRFI 241 (Match)** — R6RS-style `match` with catamorphisms.
- **SRFI 247 (Syntactic monads)** — `define-syntactic-monad`, threading a
  fixed set of formals through a group of procedures.

##### Records (issue #1695, closed)

- **SRFI 237 (R6RS records, refined for R7RS)** — the one record SRFI needing
  real engine work: `RecordType` gained `parent`, per-level field metadata,
  `uid`, `sealed`, and `is_opaque`, and `define-record-type` gained a parallel
  R6RS-clause-syntax path alongside the R7RS one, dispatching on shape.
  Inheritance and `protocol` composition work at any depth.
- **SRFI 240 (Reconciled records)**, **SRFI 136 (Extensible record types)**,
  **SRFI 137 (Minimal unique types)**, **SRFI 131 (ERR5RS record syntax,
  reduced)**, and **SRFI 150 (Hygienic ERR5RS record syntax)** — all layer on
  SRFI 237's substrate. SRFI 150 uses SRFI 213 identifier properties for
  hygienic field-name matching and is therefore a SRFI 211
  `er-macro-transformer`; 21 of 25 ported reference tests pass, with the
  remaining 4 marked `test-expect-fail` against #1832's minimal repro.
- **SRFI 57 (Records with inheritance via "schemes")** — deliberately does
  *not* port its reference implementation's expansion-time identifier
  comparison; field labels are ordinary quoted symbols resolved at run time.
  Scheme conformance is nominal, not structural.

##### Homogeneous numeric vectors and arrays (issue #1694, closed)

- **SRFI 160 (Homogeneous numeric vector libraries)** — one new heap type,
  `NumericVector`, discriminated by an 11-way element-kind enum (s8/u16/s16/
  u32/s32/u64/s64/f32/f64/c64/c128); u8 stays a plain bytevector per the
  SRFI's own recommendation. Six generic primitives are the entire native
  surface; every named procedure across `(srfi 160 base)` and the 12
  per-type libraries is portable Scheme. Complex elements are stored as two
  consecutive floats and decoded only at the ref/set! boundary.
- **SRFI 66 (Octet vectors)** and **SRFI 74 (Octet-addressed binary
  blocks)** — u8vector/bytevector aliases. `(endianness native)` needed one
  new primitive, `%host-big-endian?`, since a portable implementation has no
  other way to learn real hardware byte order — which matters on Kaappi's own
  s390x and ppc64le targets.
- **SRFI 25 (Multi-dimensional array primitives)** — pure portable Scheme;
  arrays are spec-defined as heterogeneous, so a record wrapping a vector is
  sufficient. `share-array`'s affine views delegate recursively into the base
  array's own ref/set!, so nested views compose for both reads and writes.
- **SRFI 164 (Enhanced multi-dimensional arrays)** — a compatible extension
  of SRFI 25 adding a third "virtual" mode (a getter/setter pair with no
  backing storage) behind `build-array`, `index-array`, and APL-style
  generalized indexing.
- **SRFI 63 (Homogeneous and heterogeneous arrays)** — confirmed incompatible
  with 25/164 by both specs' own Issues sections (`array-set!`'s value
  argument is second here, not last; `make-array` takes a prototype, not a
  shape). 12 of its 20 prototype kinds reuse the shipped `(srfi 160 <tag>)`
  procedure sets as backing store, inheriting every conversion error for
  free. Supersedes SRFI 47, which is excluded on that basis.
- **SRFI 231 (Intervals and generalized arrays)** — the largest single SRFI
  in this codebase by an order of magnitude: 118 bindings shipped across six
  phases, merged into a public `lib/srfi/231.sld` re-export hub. A genuinely
  three-tier model (`array?` ⊃ `mutable-array?` ⊃ `specialized-array?`) with
  17 storage classes and no textual relationship to 25/164/63. Supersedes
  SRFI 179, which is excluded as a breaking revision rather than a superset.

##### Ports, I/O, and data interchange

- **SRFI 181 (Custom ports, including transcoded ports)** — five
  `make-custom-*-port` constructors plus `make-transcoder`,
  `native-transcoder`, codecs, eol-styles, and the `raise` error-handling
  mode. A custom port's callbacks are the first Value-bearing fields `Port`
  has ever had. Callbacks must be effectively synchronous: one that tries to
  block is rejected with a catchable error rather than risking a native stack
  overflow. v1 supports the UTF-8 codec only.
- **SRFI 192 (Port positioning)** — built-in. `port-position`,
  `set-port-position!`, and the two capability predicates, using plain exact
  integer byte offsets for every port kind, with the OS offset corrected for
  whatever the port's own software buffers have read ahead or not yet
  flushed. Needed a new `platform.seek` (POSIX `lseek`, Windows `_lseeki64`,
  WASI `fd_seek`).
- **SRFI 180 (JSON)**, **SRFI 207 (String-notated bytevectors)**, and
  **SRFI 238 (Codesets)**.

##### Collections and data structures

SRFI 44 (Collections), 90 (Extensible hash table constructor), 101 (Purely
functional random-access pairs and lists), 123 (Generic accessor and modifier
operators), 126 (R6RS-based hashtables), 153 (Ordered sets), 161 (Unifiable
boxes), 167 (Ordered key-value store), 168 (Generic tuple store database),
173 (Hooks), 178 (Bitvector library), 209 (Enums and enum sets),
214 (Flexvectors), 217 (Integer sets), 224 (Integer mappings),
225 (Dictionaries), and 234 (Topological sorting).

##### Binding, control, and definitions

SRFI 5 (A compatible `let` with signatures and rest arguments),
7 (Feature-based program configuration), 51 (Handling rest lists),
71 (Extended `let` for multiple values), 86 (`mu` and `nu` simulating
`values`), 156 (Syntactic combiners for binary predicates), 165 (The
environment monad), 190 (Coroutine generators), 201 (Syntactic extensions to
the core bindings), 202 (Pattern-matching variant of `and-let*`),
203 (A simple picture language in the style of SICP), 216 (SICP
prerequisites), 221 (Generator/accumulator sub-library), 236 (Evaluating
expressions in an unspecified order), 239 (Destructuring lists),
242 (The CFG language), 244 (Multiple-value definitions), 251 (Mixing groups
of definitions with expressions within bodies), and 255 (Restarting
conditions).

**SRFI 226 (Control features)** ships as three sub-libraries only —
`(srfi 226 control prompts)`, `(srfi 226 control continuations)`, and
`(srfi 226 control times)` — a reduced, escape-only continuation-prompt
subset. The spec has no default library of its own, so there is no bare
`(srfi 226)`; `lib/srfi/226/control/prompts.sld`'s header documents what is
out of scope and why.

##### Strings, text, characters, and formatting

SRFI 29 (Localization), 30 (Nested multi-line comments), 54 (Formatting),
62 (S-expression comments), 118 (Simple adjustable-size strings),
129 (Titlecase), 135 (Immutable texts), 140 (Immutable strings),
169 (Underscores in numbers), 185 (Linear adjustable-length strings), and
270 (Hexadecimal floating-point constants).

##### Numerics, comparators, and checking

SRFI 67 (Compare procedures), 70 (Numbers), 94 (Type-restricted numerical
functions), 95 (Sorting and merging), 162 (Comparators sublibrary),
223 (Bisecting search), 228 (Composing comparators), 252 (Property testing),
and 253 (Data type-checking).

##### System, environment, and transducers

SRFI 59 (Vicinity), 112 (Environment inquiry), 120 (Timer APIs),
171 (Transducers, with `(srfi 171 meta)`), 193 (Command line), 194 (Random
data generators), and 215 (Central log exchange).

SRFI 120's timers are portable Scheme with no engine changes: each
`make-timer` spawns one dedicated SRFI-18 thread owning its task list in its
own heap, coordinated purely through a `(kaappi fibers)` control channel
captured in the thread's own thunk. **Calling a timer's procedures from more
than one thread is a hard requirement violation**, not a style guideline —
doing so reproduced nondeterministic memory corruption that points at a real
bug in multi-hop channel messages interacting with cross-thread deep copy,
not root-caused and out of scope for a portable-library change.

#### Tooling and developer experience

- **`/create-announcement` skill** — drafts and posts a release announcement
  to the org Announcements forum from a release tag.
- **Markdown linting in CI** — a `format` job now runs markdownlint over the
  tree, so structural drift in Markdown is caught the way `zig fmt` already
  catches Zig drift (#1837).
- **`docs/dev/performance.md`** — a slowdown-investigation runbook, plus
  `docs/dev/srfi-exclusions.md` documenting all 30 excluded SRFIs with
  rationale, and a `docs/dev/CLAUDE.md` for the dev-docs directory.
- **Fuzzing beyond x86_64** — the fuzz matrix now covers ARM64 and
  big-endian targets.

#### SRFI 115 (regular expressions)

- **Look-behind assertions** — `(look-behind sre ...)` and
  `(neg-look-behind sre ...)` join the look-ahead pair that was already
  supported. A look-behind never sees text before the `start` index a search
  was given (#1681).
- **Grapheme clusters** — `grapheme` matches one extended grapheme cluster and
  `bog`/`eog` assert cluster boundaries, following UAX #29 (CR LF, Hangul
  syllables including conjoining jamo, regional-indicator pairs, and any base
  character followed by combining marks). In an ASCII context `grapheme` is
  `any` and the boundary assertions always hold (#1681).
- **`title-case`/`title` and `symbol` char sets** — the two named character
  sets SRFI 115 lists that Kaappi rejected. Both are backed by Unicode 15.1.0
  range tables generated by `tools/gen_srfi115_charsets.py` and embedded in
  `lib/srfi/115.sld`, since `(scheme char)` exposes no general category
  predicate and the library is portable Scheme (#1681).
- **Char set intersection and difference** — `(& ...)`/`(and ...)` and
  `(- ...)`/`(difference ...)` alongside the union and complement operators
  already supported (#1681).
- **`word` and `(word+ cset ...)`** — a bare `word` now matches a whole word,
  as SRFI 115 specifies, rather than a single word-constituent character, and
  `word+` restricts a word to a character set (#1681).

### Changed

- **`install.sh` no longer lives in this repo.** The only copy anyone runs is
  `docs/install.sh` in
  [kaappi.github.io](https://github.com/kaappi/kaappi.github.io), served at
  <https://kaappi-lang.org/install.sh>; the copy here was served by nothing
  and had silently drifted behind it by three hardening commits, making it a
  trap for anyone who "fixed the installer" by editing it. `docs/dev/porting.md`
  and `docs/dev/netbsd.md` now point at the real location.

- **`(srfi 4)`'s `f32vector` now truncates to 32-bit precision.** It is a thin
  re-export over `(srfi 160 <tag>)` for the eight non-complex names, fixing a
  real bug the old wrapped-vector implementation had: an `f32vector` stored
  full f64 values, so a stored single-precision number read back at a
  precision no `f32vector` should carry.

- **Linux release binaries are now built against glibc (2.28 floor).** Zig
  resolves the bare `x86_64-linux`/`aarch64-linux` targets to static musl, and
  static musl cannot `dlopen` — so every released Linux binary rejected
  `(kaappi ffi)` with "Dynamic loading not supported", making the entire C
  extension ecosystem (net, http, sqlite, pg, redis, crypto) unusable from a
  release install. Artifact names are unchanged, so `install.sh` keeps
  matching. Interpreter-tier arches are unaffected (#1783).

- **`define-values` now supports `letrec*`-style mutual reference.** R7RS
  draws no distinction between `define` and `define-values` for a body's
  `letrec*` scoping (5.3.2/5.3.3), but a `define-values` clause could not
  reference a name bound by a later clause in the same body — the reference
  silently compiled as a global lookup and surfaced as a runtime "undefined
  variable" once the enclosing procedure was called (#1719).

#### Performance

- **The ReleaseSafe allocator's `0xAA` fill no longer runs on hot,
  size-proportional buffers.** Zig 0.16's `Allocator.alloc`/`.free`/`.dupe`
  unconditionally `memset(…, 0xAA)` new and freed memory in ReleaseSafe,
  inside their own generic bodies rather than the vtable functions they call
  — so it is unavoidable via a backing-allocator swap or a call-site
  `@setRuntimeSafety(false)` (confirmed by disassembly). Every GC object's
  variable-length payload (vector, string, and bytevector data, closure
  upvalues, record fields) now goes through new no-fill helpers that call
  `rawAlloc`/`rawFree` directly. Continuation-heavy workloads improve by
  ~60% (#1809).

- **Importing SRFI 148 dropped from ~87s to ~0.07s.** Two independent causes:
  the expander's 1 MB buffers were declared `= undefined` and so were
  `0xAA`-filled on *every* expansion under ReleaseSafe, and the `set!`
  pre-scan speculatively ran the CK machine inside every transformer spec.
  The pre-scan is now bounded, and the buffers skip the fill (#1775, #1802).

- **The global inline cache could never hit — not once.** `call_global` and
  `tail_call_global` populated a `Function`'s global inline cache but never
  assigned `cache_version`, leaving it at its default of 0, while
  `global_version` is bumped past 0 before any user code runs. The fast-path
  guard was therefore false forever and every call to a global fell through
  to a full hash-map lookup. `get_global` already self-healed; the two call
  opcodes now apply the same pattern (#1817).

- **`apply` is lowered natively in the LLVM backend.** It becomes an
  argument-splicing `@kaappi_apply` runtime call, so an enclosing function
  keeps its native compilation instead of declining it wholesale (#1803).

#### Internal

- **`src/types.zig` split into 11 domain files.** It had grown to 1871 lines,
  one heap-type addition at a time across 105 commits — well past the
  1500-line policy. Struct and enum definitions now live in `types_ffi.zig`,
  `types_port.zig`, `types_continuation.zig`, and eight more, with
  `types.zig` re-exporting every name so the dozens of existing `types.Foo`
  call sites need no changes. `types.zig` drops to ~1200 lines (#1731).

### Fixed

- **A digit-led token that wasn't a valid number was misreported as a bare
  "unexpected character."** `3-state`, `5foo`, `1.2.3`, and similar tokens
  are correctly rejected — R7RS identifiers can never begin with a digit, so
  the reader commits to parsing a number on the leading digit — but the
  generic `KP1002` ("unexpected character", whose explanation talks about
  stray `#`-syntax) named the wrong category and gave no hint why, with the
  caret pointing one character past the token's actual start. Such a token
  now reports `KP1004` ("invalid number literal"), the accurate code since
  the reader already committed to a number; the message echoes the
  offending token and states the rule, and the caret points at the token's
  start rather than wherever the number scan stopped:
  `invalid number literal '3-state': identifiers cannot begin with a digit;
  use |3-state| for a literal symbol`. Surfaced in the CLI's text output,
  `kaappi check`, `kaappi compile`, and `--diagnostics=json` alike (#1723).

- **A procedural macro transformer's own raised condition was discarded and
  reported as a bare `"invalid syntax"`.** A Scheme-level error inside a
  SRFI 211 `er-macro-transformer`/`lisp-transformer` — the transformer's own
  `(error ...)`, or a primitive type error inside it like `(car 7)` — was
  computed and stored on the VM, then thrown away when the expander's
  `TransformerFailed` collapsed to the compiler's generic
  `CompileError.InvalidSyntax`: #1831 was a one-line resolution bug whose
  real message was `undefined variable 'cadar'`, none of which reached the
  user, so it was chased for days as a `cadar`-specific primitives bug
  instead. The real condition now flows through the same
  `syntax-error[KP2002]` channel `syntax-error` itself already reports
  through — in the CLI's text output, `kaappi check`, and
  `--diagnostics=json` alike — while an ordinary `syntax-rules` pattern-match
  rejection, which has no VM-side condition to recover, keeps its existing
  generic message (#1846).

- **A `syntax-rules` template's own free reference to a pre-existing global
  could collapse into an unrelated, same-spelled argument at the use site.**
  R7RS 4.3.1 referential transparency for a template's free reference to a
  global that already existed when the macro was defined — e.g. `count` in
  `(define-syntax inc! (syntax-rules () ((inc!) (set! count (+ count
  1)))))` — was implemented by leaving the reference unrenamed and injecting
  a register alias under that bare name, so it could pierce a same-named
  local at the use site. But a bare, unrenamed reference is indistinguishable
  from any other identifier of the same spelling introduced elsewhere in the
  same expansion, including a pattern-variable argument the caller happened
  to supply with that exact spelling. Calling such a macro with an argument
  of the same name as its own free reference collapsed the two at that one
  use site: `(let ((a 5)) (def a))`, where `def`'s own template referenced a
  pre-existing global `a` while also taking `a` as an argument, resolved
  both occurrences to the injected alias instead of the argument correctly
  reading the `let`-bound local — silently producing a wrong value, or, for
  a `set!`-based macro, overwriting the very use-site local the alias was
  supposed to leave untouched. Such a reference is now hygiene-renamed like
  any other template-introduced identifier, and its referential-transparency
  alias is injected under that renamed name instead of the bare one (#1832).

- **`thread-join!`'s default error report hid the child thread's real
  failure, and a local channel's deadlock message blamed only "fibers"
  even with another OS thread alive.** `thread-join!` has always wrapped an
  errored child's exception in a generic `"uncaught exception in thread"`
  object, with the actual cause reachable only via `(error-object-message
  (uncaught-exception-reason e))` inside a `guard` — the default, uncaught
  top-level report never looked past the wrapper text. It now unwraps
  `uncaught-exception-reason` automatically, so e.g. a channel reached
  through a shared global instead of a thread's own thunk (a top-level
  `define` is a shared pointer, never a lexical capture, so it is correctly
  rejected rather than promoted) now reports `uncaught exception in
  thread: channel belongs to another thread; pass it through the thread
  thunk to share it` instead of stopping at the uninformative wrapper.
  Separately, `channel-receive`/`channel-send`'s deadlock message for a
  channel that was never shared with another thread — `"...and all fibers
  are blocked"` — now names that thread explicitly when one is alive,
  instead of reading as though fiber scheduling were the whole story
  (#1742).

- **A `syntax-rules` template ellipsis with no driving pattern variable
  silently expanded to zero copies instead of erroring.** A template
  subform followed by `...` whose element contains no pattern variable
  bound under an ellipsis in the pattern — most often a typo'd bare `...`
  where the literal-ellipsis escape `(... ...)` was meant — used to vanish
  from the expansion with no diagnostic, e.g. `(syntax-rules () ((_)
  '(head tok ... tail)))` expanded `(head tok ... tail)` to `(head tail)`
  rather than reporting an error, per R7RS 4.3.2. `instantiateEllipsis` now
  raises an error in this case instead of silently producing nothing,
  proven not to fire for the legitimate case where such an ellipsis
  belongs to a nested `syntax-rules` template's own grammar (the SRFI
  147/148 macro-generating-macro pattern) — both call sites already gate on
  the exact predicate that distinguishes the two. This also closes a
  related gap `lib/srfi/149.sld` had documented and deliberately deferred:
  a single pattern variable asked for more ellipsis nesting in the template
  than its own matched depth, with no sibling variable to drive the extra
  level, hits the same code path one recursion level down (#1791).

- **SRFI 168 nstore prefixes could leak tuples across stores when one
  prefix was an initial subsequence of another** — `nstore-select`/
  `nstore-where` prefix-scan the packed key bytes directly (via SRFI 167's
  `engine-prefix-range`), and `engine-pack` concatenates each item's
  encoding with no marker for "prefix ends here." Two nstores sharing an
  engine/store, e.g. one keyed by `(list 0)` and another by `(list 0 0)`,
  had the shorter prefix's scan also match the longer prefix's tuples.
  Every nstore's prefix is now wrapped in a self-delimiting length header —
  the packed prefix's own byte length, itself packed via `engine-pack`,
  which is prefix-free across distinct non-negative integers — so one
  nstore's scan can no longer pull in a different nstore's tuples for any
  two *distinct* prefixes, including one being an initial subsequence of
  another. Two nstores given the exact same prefix remain
  indistinguishable, which was never a supported way to tell them apart
  (#1717).

- **Library import silently let colliding export names resolve to
  whichever import came last** — `(import (srfi 28) (srfi 29))`, which both
  export `format`, picked whichever library was written last in the
  import-set list with no diagnostic either way, and reversing the order
  silently flipped which binding won. R7RS 5.2 says importing the same
  identifier from two different libraries with different bindings is an
  error. `(import ...)` and the `environment` procedure now track which
  import-set in the same list first claims each name and reject a later
  one that would bind it to a genuinely different value, naming both
  import-sets and the identifier; re-importing the identical binding
  through two paths (e.g. a diamond dependency) still merges silently,
  since that is the same binding, not two different ones. A few portable
  SRFI libraries and test files had latent, previously-invisible
  collisions of exactly this kind and now disambiguate with
  `only`/`except`/`rename`. Getting here surfaced two related bugs: a
  non-exported helper macro reachable only through an exported macro's
  expansion (e.g. SRFI 64's `test-assert` → `%test-comp1body` chain) could
  leak into an importer's globals as a plain, callable value once the
  resolved export set was routed through a scratch map first — as
  only/except/prefix/rename already did, and a plain, unmodified import
  now also does to run the collision check — so the transitive macro
  closure is now chased only into the real, final target, never a scratch
  map that exists purely to answer "what does this import-set resolve
  to"; and a multi-set `(import a b c)` form that failed partway through
  used to keep processing the rest, letting a later, successful library
  load's own native calls clobber the shared error-detail buffer and
  reduce a specific message to a bare "invalid syntax" — `(import ...)`
  now stops at the first failing import-set, matching `environment`'s
  existing behavior (#1726).

- **`kaappi compile` binaries could not see their own command-line
  arguments** — the LLVM-emitted `main()` took no parameters at all, so
  `(command-line)` always returned `()` in a compiled binary no matter what
  arguments it was invoked with. `main` now takes the standard C
  `(argc, argv)` pair and hands `argv` to the runtime right after init, so a
  compiled binary's `(command-line)` reports its own path followed by its
  real arguments, mirroring how the interpreter reports a script's name
  followed by its arguments (#1744).

- **A special-form-shadowing macro imported by one program could corrupt
  `define-record-type`/`define-values` in a completely unrelated library
  loaded afterward** — `define-record-type`'s and `define-values`'s
  desugaring compiled their generated definitions against the
  process-global macro table instead of an isolated one, so once any
  program imported a macro shadowing a core special form (e.g. `lambda`),
  every later library's own record types or `define-values` forms could
  fail to compile, or — when the shadowed name was `define-record-type`
  itself — be silently dropped with no error at all. Record-type/
  define-values desugaring is now isolated from the importing program's
  own macro scope, and the shadow-detection that lets a library define its
  own `define-record-type` macro (SRFI 136/131/57) now checks that
  library's own scope rather than the whole process's. Importing a special
  form under a new name (`(rename (only (scheme base) let*) (let*
  my-let*))`) now fails with a clear diagnostic at the `import` instead of
  silently producing a binding that resolves to nothing (#1718).

- **The installer now installs the native backend's runtime archive** —
  releases have published `libkaappi_rt-<target>.a` since 0.8.0, but the
  install script never downloaded it, so anyone who installed via
  `curl https://kaappi-lang.org/install.sh | bash` got an interpreter-only
  install: `kaappi compile` failed to link, and `kaappi doctor` reported
  `WARN libkaappi_rt.a: not found` with a fix ("install a release build that
  ships libkaappi_rt.a") that no install path actually offered. The script now
  fetches the archive, verifies it against `SHA256SUMS` like every other
  artifact, and installs it to `<INSTALL_DIR>/../lib` — the `<exe>/../lib`
  entry in the search order `kaappi compile` already uses, so no environment
  variable is needed. Overridable with `LIB_INSTALL_DIR`. Skipped on the
  interpreter-tier arches (riscv64, s390x, powerpc64le), where the LLVM
  backend has no target triple and `kaappi compile` refuses regardless; a
  release without the asset degrades to an interpreter-only install with a
  warning rather than failing. The post-release workflow now asserts the whole
  chain — archive present, `kaappi doctor` clean, and a compiled binary that
  runs — so this cannot silently regress.

- **`(kaappi parallel)` now ships in the release library bundle** — the
  release workflow packed `kaappi-lib.tar.gz` from an enumerated list
  (`lib/srfi/`, `lib/chibi/`) that predates `lib/kaappi/`, so
  `(import (kaappi parallel))` failed with "library not found" on every
  installed release from v0.18.0 through v0.21.0 even though the library is
  documented, correct in the source tree, and already embedded in the binary
  for `--sandbox` and WASM. The bundle now packs the whole `lib/` tree, and
  the post-release acceptance suite imports one disk-loaded library per
  shipped `lib/` subdirectory — including a real `parallel-map` run — on
  every platform leg, so omitting a library directory from the tarball can
  no longer go unnoticed (#1741).

- **The generic printer no longer hangs on cyclic record structures** —
  `write`/`display`/`write-shared` already detected and datum-labeled
  cycles through pairs and vectors, but record instances were invisible to
  that machinery, so printing a cyclic record fell through to the plain
  depth-limited recursive printer instead. A direct self-reference merely
  recursed until hitting the depth cap, but a record field that's a vector
  of records which each reference it back (e.g. two mutually-referencing
  record types — the shape that motivated this issue) fans out
  combinatorially at every level of that recursion, hanging the process
  long before the cap is reached. Record instances now join pairs and
  vectors in both cycle-detection passes, so a cyclic web of records prints
  with the same `#N=`/`#N#` datum-label markers instead of looping forever
  (#1713).

#### Macro expander and hygiene

- **A library body's reference to a global resolved in tail position only.**
  The compiler picks a global-reference opcode purely by syntactic position —
  `get_global` plus a plain `tail_call` for a tail call's operator, the
  `call_global` superinstruction for every other call — but only `get_global`
  carried the `vm.globals` fallback that library code has needed since the
  fallback was introduced. A library importing just `(scheme base)` could call
  `(cadar x)` as its body's last form yet get "undefined variable 'cadar'" for
  the identical call one syntactic position over, surfacing as a bare "invalid
  syntax" when the caller ran at macro-expansion time. All three opcodes now
  resolve through one helper (#1831).

- **A macro's free reference to a name its own defining library binds resolved
  against the *use site's* globals.** A procedure reference was left completely
  unrenamed, and a non-procedure reference was protected only against lexical
  shadowing at the use site, not against a genuine top-level redefinition —
  so an unrelated `(define helper2 …)` in the importing file could silently
  corrupt an already-imported macro's expansion. Such references now resolve
  through their own library (#1812).

- **A template-introduced identifier inside `quote` was stripped of its
  hygiene rename immediately**, before any per-expansion distinguishing
  information could be recorded, so two separate expansions of `'g` were
  structurally identical *as syntax*, not just as data. This broke any
  `bound-identifier=?`-style trick built from further expansion, including
  SRFI 148's `em-gensym`, which relies on hygiene alone for uniqueness. Quoted
  identifiers are now renamed like any other and the rename is stripped back
  off where the compiler turns a quoted datum into a literal value (#1801).

- **A macro use expanding to a bare `(define x v)` in body position raised
  "undefined variable" for later references to `x`.** The post-expansion
  cleanup popped every compiler local added while compiling the expansion, on
  the assumption that all of it was transient hygienic-alias bookkeeping — but
  a definition's local is real and sibling-visible, and must survive the call
  returning. Fixes six SRFI 148 assertions and one SRFI 251 test previously
  quarantined behind `test-expect-fail` (#1800).

- **`let`/`if` literals in a macro-generated nested `syntax-rules` never
  matched.** Both are deliberately excluded from the well-known-forms set so a
  macro's own executable use of them stays hygienic under use-site shadowing,
  but that exclusion also meant a *nested* `syntax-rules`'s `let`/`if` literal
  got hygiene-renamed by the generating macro. The literal fallback stripped a
  rename off the input side only, never the literal side, so a renamed literal
  could never match a real token typed at the generated macro's use site.
  Both sides are now stripped before comparing (#1720).

- **A sibling ellipsis variable from an independent pattern group was
  re-collected wholesale.** A template like `(list (list formal (list binding
  ...)) ...)` drawing `formal` and `binding` from independent groups failed
  with an ellipsis count mismatch when the groups had different lengths, and
  silently consumed `binding` per-iteration instead of replicating it when
  they matched — because the driver scan recursed into inner `(x ...)`
  sub-templates and wrongly treated inner-only bindings as driving the outer
  repeat count. Repeat-count determination is now two-pass (#1721).

- **A custom ellipsis identifier was unrecognized outside `quote`.** A nested
  `syntax-rules` template's ordinary position can receive a custom ellipsis
  substituted from an outer pattern variable, wrapped by the usertext-marking
  protocol; neither of the two ellipsis-detection sites unwrapped it, so the
  element was emitted literally instead of splicing its repetitions (#1776,
  #1779). Two further spine walks that missed the same unwrap were fixed
  separately (#1787, #1788).

- **Head-position macro chains recursed instead of iterating**, hitting a
  native stack overflow at a depth the CK machine of SRFI 148 reaches
  routinely. The chain is now driven by a trampoline (#1796).

- **A `define-syntax` inside a literal `begin` was invisible to later
  siblings.** A literal `begin` outside real top level lowered every child
  eagerly, but a `define-syntax`'s registration into the macro table is a side
  effect of *compiling* its node, not lowering it — so a later sibling's macro
  use compiled as a plain call to an unbound global. Lowering now reserves the
  name the moment the form is reached (#1772).

- **A `syntax-rules` template ellipsis with no driving pattern variable** now
  raises rather than silently expanding to zero copies — see above (#1791).

#### Native (LLVM) backend

- **`let` and lambda bodies re-lowered without a macro table, silently
  miscompiling any macro use inside them.** A `let` body's macro use was
  unconditionally broken; a lambda body's was usually saved by accident
  (free-variable analysis rejects an unrecognized name) *unless* the macro
  shadowed an existing global, in which case it silently called the real
  primitive instead. Native lowering is now gated on macro use (#1807).

- **Long-running native loops overflowed the OS thread stack.** LLVM's
  `alloca` frees its stack space only at function return, never at "next loop
  iteration", but the backend compiles self-tail-call loops and `do` loops as
  backward branches within a single function — and several paths emit
  `alloca` inside that repeatable body, so every pass added stack that was
  never reclaimed. Reproduced with a pure-fixnum loop and a plain `do` loop,
  confirming it was unrelated to the bignum promotion in the original
  reproducer (#1808).

- **`apply` was evaluated in the global environment**, so a compiled `apply`
  lost its enclosing lexical scope (#1798, #1799).

- **`kaappi compile` now refuses an import it cannot resolve at runtime.** The
  compiled binary starts a fresh VM with no library search path, and the
  native backend never bundles `.sld` sources — so any import resolved from a
  file compiled cleanly, exited 0, and then died at runtime with "library not
  found". It now refuses to emit, names the unresolvable libraries, and points
  at the interpreter or `-Dbundle-src` (#1743).

- **Compiled binaries could not see their own command-line arguments** — see
  above (#1744).

#### Runtime and library

- **`case-lambda` broke in any scope that shadowed `length`.** Its compiled
  arity dispatch called the global `length` by name, so a library legitimately
  providing its own for a list-like type (as SRFI 101 does) broke every
  `case-lambda` defined within it. Dispatch now goes through an internal
  `%length` alias, immune to ordinary user shadowing (#1714).

- **`(expt -8.0 0.5)` returned `+nan.0` instead of the complex result.** The
  real-number fallback called `pow` unconditionally, which is undefined for a
  negative base with a non-integer real exponent — the same input shape `sqrt`
  already promoted correctly. Such inputs now route through the shared
  `z^w = e^(w·ln z)` helper; integer exponents are untouched (#1725).

- **`string->number` accepted misplaced digit-separator underscores.**
  Parsing called Zig's `parseInt` on unvalidated input, whose own underscore
  convenience is more permissive than SRFI 169 — it rejects only a leading or
  trailing underscore, not a doubled one — so `"1__2"` silently returned 12
  instead of `#f`. Underscores are now validated and stripped up front by the
  same validator the reader already used (#1724).

- **A forked child inherited the parent's exact PRNG state.** The default
  SRFI 27 source is created eagerly at VM startup, so every
  `http-listen-prefork` worker continued the parent's stream and drew
  identical "random" values — identical session ids across workers. A
  `pthread_atfork` child handler now marks the source stale (writing exactly
  one word, since anything that can take a libc lock or allocate is off-limits
  in a forked child of a multithreaded parent) and the next touch reseeds it
  in place from OS entropy (#1761).

- **Tearing down a VM while a `thread-start!`ed child was still alive raced
  into a crash.** GC and VM teardown are now skipped while children are alive
  (#1792).

#### Testing and CI

- **`-Dbundle` test builds are isolated from the shared `kaappi` binary**,
  fixing a compile-suite flake that had also been masking a Debug leg that
  wasn't actually testing Debug (#1748).
- **Mark-time use-after-free is now detected deterministically under
  `-Dgc-stress`** via a freed-owner sentinel plus cross-collection quarantine,
  so a dangling value panics with a clear message instead of segfaulting by
  luck or silently aliasing a recycled object (#1687).
- **The fuzz report files pre-fuzz unit-test failures with their test names**
  instead of misclassifying them (#1688), and fuzz generator gates are bounded
  by instruction count on Debug builds (#1835).
- **The reactor timer tests no longer fail on a `poll()` that returns a tick
  early** (#1785), and the `user-supplementary-gids` audit test uses `list?`
  rather than `pair?`, so an empty result passes (#1845).

#### SRFI 115 (regular expressions)

- **`w/ascii` and `w/unicode` were no-ops** — both were accepted and ignored,
  so `(regexp-matches '(w/ascii (* alpha)) "кириллица")` matched. They now
  restrict (resp. widen) the named character sets, `any`, and the complement
  operator they enclose (#1681).
- **Submatches can be looked up by name** — `regexp-match-submatch` and its
  `-start`/`-end` variants accept the symbol from `(-> name sre ...)`, not
  just an index. When a name is used more than once the first group that
  actually matched wins, and an unknown name raises (#1681).
- **`w/nocapture` suppressed nothing** — enclosed `$` and `->` forms still
  captured and still consumed submatch numbers (#1681).
- **`(~ a b ...)` complemented the sequence instead of the union** — SRFI 115
  defines `~` over a set union, so `(~ #\a #\b)` now excludes both characters
  rather than only the two-character sequence "ab" (#1681).

## [0.21.0] - 2026-07-20

### Added

#### SRFI 257 (Simple Extendable Pattern Matcher with Backtracking)

- **SRFI 257 — Simple Extendable Pattern Matcher with Backtracking** —
  `(import (srfi 257))` provides `match` with non-linear patterns (a pattern
  variable may appear more than once, and its occurrences must match `equal?`
  values) and backtracking through `(=> next)` / `(=> next back)` clause
  guards. Nearly every pattern is built from a small core and is
  user-extensible via `define-match-pattern` and
  `define-record-match-pattern`. Two sublibraries ship with it:
  `(srfi 257 misc)` adds `~etc+`, `~etc=`, `~etc**`, the SRFI-241-style
  catamorphism matcher `cm-match`, and the `syntax-rules`-like `sr-match`;
  `(srfi 257 box)` adds `~box?` and `~box` over SRFI 111 boxes. Ported from
  Sergei Egorov's MIT-licensed reference implementation (with two upstream
  reference bugs fixed); 111 of the reference suite's 112 assertions pass —
  the exception compares boxes with `equal?`, which is
  implementation-specific. Porting it also surfaced seven general expander
  defects, fixed under "Macro expander and hygiene" below (#1644).

#### SRFI 257 `rx` sublibrary (regexp match patterns)

- **`(srfi 257 rx)`** — the optional sublibrary of SRFI 257, matching strings
  against regexps written either as SRFI 115 SREs or as SRFI 264 SSRE strings:
  `~/`, `~/sub`, `~/any`, `~/all`, `~/all+`, `~/etc`, `~/etc+`, `~/etcse`,
  `~/extracted`, `~/split`, `~/partitioned`, plus `rx` re-exported from SRFI
  115. Subpatterns bind the submatch strings, so
  `(match s ((~/ "([a-z]*):([0-9]*)" _ name num) ...))` destructures a match in
  the pattern itself. Ported from Sergei Egorov's MIT-licensed reference
  implementation; the full upstream conformance suite (113 cases) passes
  (#1679).

#### SRFI 248 (Minimal Delimited Continuations)

- **SRFI 248 — Minimal Delimited Continuations** — `(import (srfi 248))`
  provides `with-unwind-handler`, `empty-continuation?`, and an extended
  `guard` taking an optional second identifier — `(guard (c k clause …)
  body …)` — bound to a delimited continuation for the rest of the guarded
  thunk, up to and including the `with-unwind-handler` call; enough to write
  coroutine generators, `for-each->fold`, and effect handlers in portable
  Scheme. R7RS's single-variable `guard` is unchanged. The prompt is a Filinski
  shift/reset over Kaappi's stack-copying `call/cc`, enabled by a new
  *sticky* VM exception handler that `raise` and `raise-continuable` invoke
  in place without popping, so a continuation captured while the handler runs
  re-arms the prompt when resumed (reset0 semantics). Two documented caveats:
  a delimited continuation is effectively single-shot (resuming the same `k`
  twice crosses a native frame), and the handler runs at the raise point
  rather than after unwinding — see CONFORMANCE.md (#1669).

#### SRFI 264 (String Syntax for Scheme Regular Expressions)

- **SRFI 264 (String Syntax for Scheme Regular Expressions)** — SSRE, a compact,
  PCRE-inspired string syntax for regular expressions that translates to the SRE
  S-expressions of SRFI 115. The portable `(srfi 264)` library exports
  `ssre->sre`, `ssre->regexp`, `sre->ssre`, `ssre-definitions`, `ssre-bind`, and
  `ssre-unbind`. Ported from Sergei Egorov's MIT-licensed reference
  implementation; the full upstream conformance corpus (2751 parser/unparser
  cases) passes (#1666).

#### SRFI 258 (Uninterned Symbols)

- **SRFI 258 — Uninterned Symbols** — `(import (srfi 258))` provides
  `string->uninterned-symbol`, `symbol-interned?`, and
  `generate-uninterned-symbol`. An uninterned symbol is never `eqv?` to any
  other symbol, even one built from the same name — useful for macro
  programming and guaranteed-unique identifiers. They bypass the interning
  table and are ordinary collectable objects (reclaimed once unreachable);
  equality needed no new code since Kaappi already compares symbols by
  identity. Per the SRFI they have no readable external representation, so
  `write` emits an unreadable `#<uninterned-symbol name>` form that `read`
  rejects (deliberately breaking write/read invariance). Brings the total to
  83 SRFIs (11 built-in) (#1670).

#### SRFI 260 (Generated Symbols)

- **SRFI 260 (Generated Symbols)** — `(import (srfi 260))` provides
  `generate-symbol`, which mints a fresh symbol on every call with a unique,
  unpredictable name (optionally prefixed by a `pretty-name` display hint).
  Unlike an uninterned symbol, a generated symbol keeps write/read invariance:
  printed and read back it is `eq?` to the original. In-process uniqueness is
  guaranteed by a process-global atomic counter and the name's unpredictability
  by 128 bits of OS entropy. See `src/primitives_srfi260.zig` and
  `tests/scheme/srfi/srfi260.scm` (#1674).

#### SRFI 259 and SRFI 229 (Tagged Procedures)

- **SRFI 259 (Tagged Procedures with Type Safety)** and its foundation
  **SRFI 229 (Tagged Procedures)** — `(import (srfi 259))` provides
  `define-procedure-tag`, which binds a constructor/predicate/accessor triple
  for attaching type-safe tags to procedures. Multiple protocols can tag the
  same procedure independently: each protocol's key is private and unforgeable,
  so no code can read another protocol's tag. Re-tagging preserves other
  protocols' tags and re-wraps the original underlying procedure directly
  (no nesting). Built as a portable layer over `(srfi 229)`, which ships as
  the verbatim MIT-licensed reference implementation by Marc
  Nieper-Wißkirchen. Documented caveat: the portable design retains every
  tagged procedure in a global list for identity tracking, so tagged
  procedures are never garbage-collected (#1673).

### Fixed

#### Top-level cond-expand

- **Top-level `cond-expand` now splices into top-level context.** Previously
  it was compiled as an ordinary expression, so `(import ...)` inside a
  matched clause was mis-compiled — `(cond-expand (srfi-1 (import (srfi 1)))
  (else ...))` raised "undefined variable 'srfi'" even though the import's
  side effect still ran. `handleTopLevelForm` now recognizes `cond-expand`
  and splices the selected clause's body through `handleTopLevelBegin`,
  matching the R7RS 4.2.1 requirement that top-level `cond-expand` expands
  in top-level context (#1661, #1663).

#### FFI

- **`ffi-open` reports the real dlopen failure.** Previously it reported
  `dlerror()` only after the last probe path, so a library that existed but
  failed to load (code-signing rejection, wrong architecture) was reported as
  "no such file" for a fallback path the user never asked for. Now snapshots
  per-candidate failures and reports the first candidate that exists on disk
  but failed, with the other probed paths listed (#1662).

#### Macro expander and hygiene

Surfaced by the SRFI 257 port — the reference `match` is a CPS protocol of
macro-generating macros, which exercises corners of `syntax-rules` that
ordinary macros never reach. All seven are general expander defects, not
SRFI-257-specific, and each ships with a regression test in
`src/tests_macros.zig` (#1644):

- **Spliced user text was re-renamed on every expansion generation.** A
  pattern variable's value substituted into a nested `syntax-rules` template
  got a fresh scope each generation, severing binders from their references —
  the root cause of broken non-linear patterns. Substituted values now carry
  `__hyg-usertext` provenance markers, are instantiated in
  substitute-don't-rename mode, and are stripped at the compile boundary.
- **`let-syntax` templates could not reference an enclosing function's
  locals.** Transformers now record definition-site lexical free refs
  (`def_site_local_refs`), and `renameForHygiene` leaves them unrenamed when
  the current frame cannot resolve them, so the normal upvalue path applies.
  Same-frame refs keep the shadow-proof rename+alias path.
- **A `syntax-rules` literal bound in an enclosing frame compared
  incorrectly.** `literal_bound` now resolves a literal's definition-site
  binding through the full lexical chain, matching the use-site check — which
  is what non-linear pattern variables inside generated backtracking lambdas
  depend on.
- **A hygiene-renamed, unbound identifier did not match an unbound
  `syntax-rules` literal of its base name**, so tokens like `cm-match`'s
  `<...>` / `<_>` never matched.
- **Hygienic-capture alias injection could shadow a generated `let-syntax`
  macro** whose base name collided with a user variable; macro-bound names are
  now skipped.
- **Injected aliases ignored boxing.** They now copy the slot's current
  `is_boxed`, and `markLocalBoxedBySlot` flips every local sharing that slot.
- **Quasiquote template symbols were hygiene-renamed.** They are data, and are
  now left alone; nesting depth is tracked (0-7, saturating) so a
  depth-matching `unquote` resumes expression mode.

#### SRFI 115 (Scheme regular expressions)

Found by the SRFI 257 `rx` conformance suite, which drove every one of these
(#1679):

- **Repetition now backtracks.** The matcher was possessive: `(* any)` consumed
  everything it could and nothing could hand a character back, so
  `(regexp-matches (rx (* any) "b") "ab")` returned `#f` and any pattern with a
  greedy operator before a literal silently failed to match. `%run` is now
  continuation-passing — it offers each way a node can match to a continuation
  and takes the first that lets the rest of the pattern through. Repetition of a
  single-character body still scans iteratively, so `(* any)` over a long string
  costs no stack.
- **Non-greedy operators** `(?? ...)`, `(*? ...)` and `(**? ...)` are supported;
  they previously raised "unknown SRE", which also made every SSRE non-greedy
  quantifier (`a*?`, `a+?`, `a{2,4}?`) unusable.
- **An open-ended upper bound** — `(** 1 #f "a")` — raised a type error instead
  of repeating without limit.
- **`(/ ...)` accepts characters**, not just strings: `(/ #\0 #\9)` used to build
  an empty range that matched nothing, which is the form SRFI 264 generates for
  `[0-9]`.
- **`(",;")`** — a list whose head is a string is SRFI 115's char-set shorthand
  for the characters of that string; it raised "unknown SRE".
- **`nwb`** (not-a-word-boundary) is supported; it raised "unknown character
  class".
- **`w/nocase` reaches named classes and ranges**, so `(w/nocase (* lower))`
  matches `"abcD"` and `(w/nocase (+ (/ "af")))` matches `"BeeF"`.
- **`regexp-split`, `regexp-partition` and `regexp-fold` on a regexp that can
  match the empty string.** The index handed to `regexp-fold`'s `kons` is now
  where the previous match ended rather than where the search resumed, and
  split/partition skip empty matches, so
  `(regexp-split '(* numeric) "abc123def")` is `("abc" "def")` instead of a run
  of empty strings. `regexp-partition` also no longer appends a trailing `""`
  when the string ends with a match, matching the reference implementation.

## [0.20.0] - 2026-07-19

### Added

#### Linux s390x and ppc64le support (interpreter tier)

- **Linux s390x and ppc64le** — both architectures cross-compile with zero
  runtime code changes and pass the full battery (unit, thottam, R7RS
  1395/1395, `run-all.sh`) under QEMU user-mode and on real-kernel Alpine
  VMs. s390x is the first big-endian target: the endian-explicit `.sbc`
  codec round-trips unchanged, so the s390x CI job now guards byte-order
  correctness permanently. The native LLVM backend stays aarch64/x86_64-only
  (#1657).

#### Windows x86_64 support

- **Windows x86_64 (x64) target** — `zig build -Dtarget=x86_64-windows`
  cross-compiles kaappi.exe, thottam.exe, and kaappi-lsp.exe for x64
  Windows; the platform layer was already OS-gated, so both Windows
  architectures share the same code and degradation profile
  (`docs/dev/windows.md`). Verified on Windows 11 (ARM64 reference VM
  via the built-in x64 emulation layer): full unit suite, R7RS, all
  `.scm` and shell suites, thottam, the post-release acceptance script,
  and the native-backend e2e (`kaappi compile`, 38/38) — the stock Zig
  0.16.0 x86_64-windows toolchain works natively (the #1613
  access-violation is aarch64-only), so `kaappi compile` needs no
  master-toolchain workaround on x64. CI gains a `windows-cross`
  aarch64/x86_64 matrix and a `windows-x64-test` job (windows-latest)
  running the same suites as `windows-arm-test` plus the native-backend
  e2e; releases ship `kaappi-x86_64-windows.exe`,
  `thottam-x86_64-windows.exe`, and `libkaappi_rt-x86_64-windows.lib`
  (stripped — the #1607 strip crash is aarch64-only), with a
  post-release acceptance leg on windows-latest (#1651).

#### `srfi-<n>` cond-expand feature identifiers

- **`srfi-<n>` cond-expand feature identifiers** — each supported SRFI can
  now be probed without attempting an import, e.g.
  `(cond-expand (srfi-1 (import (srfi 1))) (else …))`. The identifier is
  derived from the supported-SRFI set (never hardcoded): `srfi-<n>` is true
  iff SRFI *n* is available to this VM, answered through the same check as
  `(library (srfi <n>))`, so built-in, portable, `--sandbox` and WASM
  answers all match what `(import (srfi <n>))` would do. Works in both
  expression- and `define-library`-level `cond-expand`. Like `(library …)`
  requirements, a `srfi-<n>` identifier is a derived probe cond-expand
  resolves on demand rather than a bare feature, so `(features)` is
  unchanged. SRFI 261 (the fileless naming convention) reports `srfi-261`
  true (#1649).

#### SRFI 250 (Insertion-ordered Hash Tables)

- **SRFI 250 (Insertion-ordered Hash Tables)** — `(import (srfi 250))`
  provides hash tables that preserve first-insertion order across iteration,
  folding, and conversion, with the full API: constructors, the bidirectional
  cursor interface, ordered `fold-left`/`fold-right`, and destructive set
  operations (#1647).

#### SRFI 254 (Ephemerons and Guardians)

- **SRFI 254 (Ephemerons and Guardians)** — ephemerons (key/value pairs
  whose value is retained only while the key is reachable other than through
  the value), guardians (post-mortem resurrection for finalization), transport
  cell guardians, and `current-hash` (stable identity hash). Ephemerons and
  guardians integrate with the GC: a `processWeakRefs` pass after strong
  marking breaks ephemerons whose keys are unreachable and resurrects guarded
  objects. On this non-moving collector `current-hash` is a stable identity
  hash and transport cell guardians are degenerate (#1643).

#### SRFI 261 (Portable SRFI Library References)

- **SRFI 261 (Portable SRFI Library References)** — `(srfi srfi-<n>)` and
  `(srfi <mnemonic>-<n>)` (e.g. `(srfi lists-1)`, `(srfi vectors-133)`)
  resolve to `(srfi <n>)` as an import-resolver fallback. Literal
  registry/file names win, sub-library tails pass through, and the trailing
  number alone is authoritative. No library file — it is a pure naming
  convention (#1650).

#### SRFI 263 (Prototype Object System)

- **SRFI 263 (Prototype Object System)** — a Self-inspired prototype object
  system: `(srfi 263)` for the core message-passing/reflection protocol,
  `(srfi 263 syntax)` for `define-object`/`derive-object`/`copy-object`/
  `set-method!` sugar. Ported from the reference implementation with
  corrections for derive, copy, and unhandled-message dispatch (#1640).

#### SRFI 267 (Raw String Syntax)

- **SRFI 267 (Raw String Syntax)** — raw strings (`#"X"..."X"`) are string
  literals that interpret no escape sequences, with a per-literal delimiter.
  The lexical syntax is built into the reader; the `(srfi 267)` library adds
  port procedures (`read-raw-string`, `write-raw-string`,
  `generate-delimiter`, etc.) (#1642).

#### SRFI 271 (Random Port Libraries)

- **SRFI 271 (Random Port Libraries)** — `(import (srfi 271))` gives
  cryptographic-quality random binary input ports drawn from OS entropy;
  `(import (srfi 271 determinized))` adds reproducible, deterministic ports
  backed by a xoshiro256** generator whose state can be captured, compared,
  and restored (`random-port-state`, `random-port-state?`,
  `random-port-state=?`, `random-port?`), plus a
  `random-port-initialization-error?` condition. States have a write/read-
  invariant external representation. Random ports are ordinary R7RS binary
  input ports, so `read-u8`, `read-bytevector`, and `u8-ready?` operate on
  them directly. See `lib/srfi/271*.sld` and `tests/scheme/srfi/srfi271.scm`
  (#1641).

#### Native compilation guard

- **`kaappi compile` now refuses on unsupported architectures** instead of
  silently producing a segfaulting binary — `emitLlvmFile` exits with a
  clear error naming the arch and pointing at the interpreter. `kaappi
  doctor` reports a single `WARN` instead of the misleading PASS trio
  (#1659).

### Fixed

- **`--lib-path` entries past the 16th are no longer silently dropped**
  (#1653) — two fixed `[16]` buffers (CLI storage in `cli.zig` and the
  search-path assembly in `main.zig`) capped the library search path with
  no diagnostic, so a 17th `--lib-path` — or the auto-discovered dirs
  (script directory, `~/.kaappi/lib`, exe-relative `lib`) once 16 explicit
  ones existed — vanished. Both now grow dynamically. Same silent-data-loss
  shape as the CLI-argument cap fixed in #1652.
- **Two macro-hygiene bugs fixed** (#1648) — (1) a `let-syntax` sibling
  passed as an argument to another macro went undefined; now only siblings a
  transformer actually free-references in its template are suppressed.
  (2) A named let's loop gensym was incorrectly re-renamed by hygiene when
  riding through another macro's template; `__nlet` gensyms are now excluded
  from renaming.

## [0.19.0] - 2026-07-18

### Added

#### NetBSD platform support

- **NetBSD target (x86_64, aarch64)** — `zig build -Dtarget=<arch>-netbsd` cross-compiles all three binaries (releases ship both arches). A full-POSIX kqueue port — fiber I/O (the shared macOS/FreeBSD/OpenBSD reactor backend), SRFI-18 OS threads, complete SRFI-170, FFI via `dlopen`, the full linenoise REPL, and thottam including `build:` manifests — with two NetBSD-specific corrections. **Versioned libc symbols:** NetBSD hides ABI-changed functions behind renames (`__kevent50`, `__opendir30`/`__readdir30`, `__getpwnam50`/`__getpwuid50`); the plain names Zig's std.c binds are old-ABI compat symbols that silently misparse modern structs (directory listings came back name-shifted, `user-info` fields shuffled), so the runtime binds the versioned names explicitly. **Floating point:** NetBSD/aarch64 boots processes with FPCR flush-to-zero + default-NaN set, which breaks IEEE-754 gradual underflow (SRFI-144's `(> fl-least 0.0)` was false); the runtime resets the FP environment at startup (`platform.normalizeFpEnvBestEffort`), inherited by all threads. Self-exe lookup uses `sysctl {KERN, PROC_ARGS, -1, PROC_PATHNAME}`; the stack-limit raise now covers NetBSD's 8 MiB default; C-compiler discovery prefers clang on NetBSD (base cc is GCC, which cannot consume LLVM IR — the native backend needs pkgsrc clang). Verified on real NetBSD 10.1 aarch64 hardware: full unit suite (1141/1141), thottam, R7RS 1395/0, and the `run-all.sh` battery, plus the native backend linking with pkgsrc clang — no Zig toolchain on the box. CI runs the suites in a KVM NetBSD 10.1 VM; `install.sh` detects NetBSD (via `uname -p` — `uname -m` reports the kernel port, not the CPU). See `docs/dev/netbsd.md`

## [0.18.0] - 2026-07-18

### Added

#### OpenBSD platform support

- **OpenBSD target (x86_64, aarch64)** — `zig build -Dtarget=<arch>-openbsd` cross-compiles all three binaries (releases ship both arches). A full-POSIX kqueue port — fiber I/O (the macOS/FreeBSD reactor backend, shared), SRFI-18 OS threads, complete SRFI-170, FFI via `dlopen`, the full linenoise REPL, and thottam including `build:` manifests — with two automatic accommodations for OpenBSD's security hardening. **BTCFI:** OpenBSD enforces Branch Target CFI (an indirect branch must hit a `bti` landing pad or the kernel raises `SIGILL`), which Zig 0.16 can't emit, so each Zig-linked binary is marked `PT_OPENBSD_NOBTCFI` post-link (`tools/openbsd_nobtcfi.zig`, wired into `build.zig`) and `kaappi compile` links native output with `-z nobtcfi` — both opting out of enforcement. **Stack limit:** the interpreter raises its own soft stack limit to the hard limit at startup (`platform.raiseStackLimitBestEffort`) to clear OpenBSD's tight 4 MiB default. Self-exe lookup uses `sysctl KERN_PROC_ARGS`/argv[0] resolution (OpenBSD has no `KERN_PROC_PATHNAME`). Verified on real OpenBSD 7.9 aarch64 hardware: full unit suite (1141/1141), thottam, R7RS, and `run-all.sh` batteries, plus the native backend (`kaappi compile`) linking with the base system `cc` — no Zig toolchain on the box. CI runs the suites in a KVM OpenBSD VM. See `docs/dev/openbsd.md`

## [0.17.0] - 2026-07-18

### Added

#### FreeBSD platform support

- **FreeBSD target (x86_64, aarch64)** — `zig build -Dtarget=<arch>-freebsd` cross-compiles all three binaries (releases ship both arches). A full-POSIX port with no runtime degradations: kqueue-backed fiber I/O (the macOS reactor backend, shared), SRFI-18 OS threads, complete SRFI-170, FFI via `dlopen`, the full linenoise REPL, and thottam including `build:` manifests. Self-exe lookup uses `sysctl kern.proc.pathname`. Verified on real FreeBSD 15.1 aarch64 hardware: full unit, R7RS, and `run-all.sh` suites, plus the native backend (`kaappi compile`) linking with the base system `cc` — no Zig toolchain needed on the box. CI runs the suites in a KVM FreeBSD VM. See `docs/dev/freebsd.md`

### Fixed

- **Out-of-memory errors are now deterministic across kernels** — a single vector/bytevector/string payload allocation is capped at 1 TiB (`GC.max_payload_bytes`) and raises the catchable out-of-memory error before asking the OS. Previously the graceful error relied on `malloc` refusing absurd requests, which overcommitting kernels (FreeBSD's default) don't do — `(make-bytevector 100000000000000)` was OOM-killed by the kernel instead of raising

## [0.16.0] - 2026-07-17

### Added

#### Windows platform support

- **Windows aarch64 target** — `zig build -Dtarget=aarch64-windows` cross-compiles `kaappi.exe`, `thottam.exe`, and `kaappi-lsp.exe` (via Zig's bundled mingw-w64; releases ship `kaappi-aarch64-windows.exe`). The full interpreter works on Windows 11 ARM64 — REPL (plain line editing), fibers, channels (incl. capacity-0 rendezvous), SRFI-18 OS threads, FFI via `LoadLibrary`, and the `kaappi test` runner — verified with the complete unit and R7RS suites on real hardware. The POSIX-only slice of SRFI-170 (uid/gid, symlinks, chmod/umask, user/group info) raises a catchable file error, and `cond-expand`/`(features)` expose a `windows` identifier in place of `posix`. See `docs/dev/windows.md` (#1606)
- **Windows fd readiness** — fiber I/O suspension now works on Windows: socket-backed ports get reactor-driven non-blocking I/O via `WSAEventSelect` (#1608 stage 1), and pipe-backed ports get emulated non-blocking mode via a polled peek/write-quota backend (#1608 stage 2). File ports keep blocking reads (the POSIX baseline — no OS has regular-file readiness). The fd-readiness unit suites (`tests_reactor`, `tests_scheduler`, `tests_port_io`) run on Windows over loopback TCP socket pairs
- **Windows native backend** — `kaappi compile` verified end-to-end on Windows: `rt_lib_name` probes `kaappi_rt.lib`, emits a derived `.exe` output, and uses the `windows-gnu` triple; 38/38 tests pass via `run-e2e.ps1` (#1610)
- **thottam on Windows** — `thottam install`/`remove`/`update` work via platform-independent filesystem shim helpers replacing shell-outs on all platforms; `HOME` falls back to `USERPROFILE` (#1609)
- **Windows CI** — the shell-based test suites (`tests/scheme/run-all.sh` and sub-suites) run on Windows via Git Bash, and the FFI Scheme suite (`tests/scheme/ffi/`) runs with a cross-compiled fixture DLL (#1611, #1612)

#### Other

- **Rendezvous channels** — `(make-channel 0)` creates a capacity-0 channel with true rendezvous semantics (sender blocks until a receiver is ready) on both fiber-local and cross-thread (`SharedChannel`) representations (#1604)
- **Heap-type layout guard** — a comptime check in `types.zig` asserts every heap struct keeps its `header: Object` at byte offset 0, catching layout drift at compile time instead of silent memory corruption (#1618, #1622)
- **Porting guide** — `docs/dev/porting.md` documents porting surfaces, the degradation ladder, and staged checklists for adding a new OS or CPU architecture (#1624)

### Fixed

#### Windows

- `(ffi-open #f)` on Windows now has POSIX `dlopen(NULL)` semantics: symbol lookup on the process handle searches every loaded module, so CRT functions resolve from `ucrtbase.dll` (#1611)
- FFI 64-bit integer marshaling now uses a platform-independent `i64` carrier: on LLP64 targets (Windows) C `long` is 32-bit and is routed through the 32-bit marshaling class, while `int64`/`uint64`/`size_t` keep full 64-bit range

#### Concurrency

- An idle in-place I/O drive pinned over a resolved ancestor's wait now unwinds with a catchable "port I/O abandoned" error instead of blocking unboundedly (#1625)
- GC `referencesYoung` now traces `owned_mutexes` in the fiber arm, preventing young-generation mutexes shared with a fiber from being collected during minor GC (#1605)

#### LLVM native backend

- Fix native `let` root leak: body-scope roots were not popped on early return (#1585)
- Fix duplicated fallback effects in transactional `emitLet` (#1586)
- Fix VM-vs-native divergence for shadowed boxed names (#1590)

#### Other

- macOS release binaries can now `ffi-open` user-compiled libraries: signing entitlements add `com.apple.security.cs.disable-library-validation` (#1587)
- `--profile` no longer drops functions promoted to the old GC generation (#1599)
- Fuzz generator coverage leaks in `genLetMut` ordering and string length (#1620)
- `tests_check` hardened against silent import-resolution failures (#1627)

## [0.15.0] - 2026-07-16

### Added

#### Machine legibility: CLI diagnostics & tooling (epic #1503)

- **`kaappi check <file>`** — compile-only static analysis: reads, expands, and compiles without executing, reporting read/compile diagnostics plus `KP4xxx` lint findings (unknown top-level variable, wrong arity or wrong-type literal on a direct built-in call). Never rejects a program R7RS permits (#1511)
- **`kaappi ast` / `expand` / `ir`** — read-only pipeline-stage dumps: post-read datums, fully macro-expanded source (round-trips), and the IR tree before/after the five optimization passes (#1512)
- **Full source spans in diagnostics** — the reader records `(line, col, end_line, end_col)` per datum; compile and runtime errors report `file:line:col` instead of `file:line`, down to the exact offending sub-form. `.sbc` cache format bumped to v9 (#1506)
- **`error-object-code`** — new `(kaappi diagnostics)` library accessor returning the stable `KP` code stamped on a runtime error object, `#f` otherwise; a total, non-raising dispatch primitive for guard clauses (#1508)
- **Stable `KP` diagnostic codes on every error path** — a comptime registry (`src/diagnostics.zig`) gives each diagnostic a code, message template, and explanation; text output now shows `error[KP3001]: ...` instead of ever leaking a raw Zig error name (#1534)
- **`--diagnostics=json`** — every read/expand/compile/runtime diagnostic as JSON Lines on stderr, shaped as LSP `Diagnostic` objects shared with the language server (#1505)
- **`kaappi explain <code>`** — prints a diagnostic's registry entry (meaning, minimal triggering example, fix), like `rustc --explain`; `--json`/`--all` for tooling (#1507)
- **`kaappi doctor [--json]`** — installation/environment self-check across six groups (binary, library path, package manager, native backend, REPL, FFI), PASS/WARN/FAIL with a fix per failure; a smoke link proves the native toolchain end to end (#1513)
- **`kaappi features [--json]`** — capability discovery: version + build id, target triple, build mode, compiled-in subsystems, built-in vs. portable SRFIs, VM/GC limits — every field derived from the same source `cond-expand` and `(features)` use, so it can't drift (#1517)
- **`kaappi cache status|clear`** + build-id cache keys — the `.sbc` cache now folds the git build id into its key, so a freshly rebuilt binary never silently serves bytecode compiled by the previous one; cache moves to a central `$KAAPPI_HOME/cache` (#1516)
- **`kaappi test`** — first-class SRFI-64 runner with `--json` and `--seed`, aggregating pass/fail/skip from the runner's own counters via subprocess-per-file isolation (#1509); `--changed`/`--list-affected [--since <rev>]` run only suites whose R7RS import closure actually changed (#1510)
- **`kaappi fmt [--check]`** — canonical, comment-preserving formatter: a dedicated CST reader/printer applies 2-space R7RS indentation and 80-column reflow, guarded by a real-reader `equal?` round-trip check before every write so it can never change a program's meaning (#1518)
- **Crash-reporting panic handler** — a custom panic banner on `kaappi`/`thottam` names the build (version, target, mode), the pipeline stage in flight, and where to report the bug, before falling through to the normal Zig trace (#1514)
- **`--timings[=json]`** — per-stage pipeline wall time (read/expand/lower/optimize/emit/execute, plus native `llvm-emit`/`link`) and an always-present cache HIT/MISS line with path, using a self-time profiler stack so nested stages stay disjoint (#1515)

#### Concurrency: fiber I/O reactor (KEP-0001)

- **Reactor core** — per-OS-thread event loop with kqueue/epoll backends and a userspace timer heap (#1446)
- **Scheduler integration** — blocking fiber operations (channel/join/mutex/condvar waits, `thread-sleep!`) now park on the reactor instead of blocking the OS thread or busy-polling (#1453)
- **Non-blocking port I/O** — reads/writes that would block suspend the calling fiber instead of the thread, so fibers serving different connections interleave; ports buffer writes (8 KiB high water) with real `flush-output-port` semantics (#1459)
- **WASI `poll_oneoff` backend** — the reactor works under wasmtime/browser WASI runtimes too, with `thread-sleep!` now Scheme-visible on WASM (#1461)
- **`fd->port`** — wraps a raw file descriptor as a reactor-integrated binary port, so FFI socket libraries (kaappi-net) get non-blocking, fiber-friendly I/O with no C changes (#1478)
- **O(1) fiber scheduling** — a ready ring + free-slot list replace the old O(n) scan on every dispatch and spawn (154x faster dispatch at 5,000 concurrent fibers) (#1477); wake paths are further indexed by waited-on object for O(1) wakes instead of scanning every fiber (~8x at 10,000 fibers) (#1530)

#### Concurrency: cross-thread channels (KEP-0002)

- **`SharedChannel`** — a channel now promotes automatically for use across `thread-start!`ed OS threads; reaching one through a shared global instead of a legitimate handoff raises a descriptive error instead of corrupting memory (#1482)
- **Envelope-based `thread-start!`/`thread-join!`** — thunks, results, and exceptions cross threads via a copy-once envelope, closing a concurrent-copy race and enabling channels created inside a thunk to promote correctly (#1483)
- **Cross-thread wakeup** — a reactor-backed `ThreadNotifier` (kqueue/epoll/WASI) replaces the placeholder panic left by earlier phases (#1485)
- **Channel capacity, timeouts, close** — `make-channel` takes an optional bound, `channel-send`/`channel-receive` take `[timeout [timeout-val]]`, and `channel-close!`/`channel-closed?` work across both local and cross-thread channels (#1469)
- **`(kaappi parallel)`** — `make-pool`/`pool-submit`/`task-wait`/`pool-shutdown!`, `parallel-map`/`parallel-for-each`, and `processor-count`, degrading to fiber workers under `--sandbox` and on WASM (#1522)
- **Envelope-cost elision shipped as default** — immediate payloads (fixnums, booleans, chars) skip the per-message envelope heap entirely (28–120x faster sends), and pointer payloads reuse a recycled per-channel buffer (~50–63% lower round-trip latency for small messages) (#1472)

#### Other

- **Configurable REPL syntax highlighting** — dark/light presets, `NO_COLOR` support, per-token overrides, and configurable prompts via a new `~/.kaappi/config` file (#1456)
- **`cond-expand`/`(features)`** gain `kaappi-fibers`, `kaappi-reactor`, and `kaappi-threads` subsystem identifiers (KEP-0004 Phase 0/1) (#1488)
- **KEP-0003 access-semantics research experiment** — measures the cost of `unordered`-atomic element access for shared flat buffers ahead of building them; resolves KEP-0003's Unresolved Question 2 to a hybrid design. Docs/benchmarks only, no source changes (#1473)

### Changed

#### Native (LLVM) backend

- **Guaranteed native mutual tail calls** — a fixed-arity direct tail call between natively-compiled functions now emits `musttail call tailcc`, giving mutual recursion (not just self-recursion) LLVM-guaranteed constant stack (#1499)
- **Native `cond`/`case`/`do` lowering** — emitted directly instead of falling back to a whole-function `kaappi_eval` (#1564)
- **Cached eval-fallback compilation** — a form the native backend can't lower (`letrec`, `guard`, quasiquote, named `let`, …) is parsed and compiled once per call site instead of on every execution (#1494)
- **Cached quoted constants** — quoted pairs/vectors are built once per call site instead of re-consed on every execution, also fixing an `eq?`-identity divergence from the interpreter (#1495)
- **Inline fixnum fast paths** — `+ - * < = null?` lower to inline IR with a slow-path fallback, eliding shadow-stack rooting where the second operand can't allocate; `fib(38)` runs 3.30x faster (#1493)
- **`-O2` native compilation** with an IR-verify safety net ensuring hand-emitted IR stays well-formed under stricter optimization (#1492)
- **Boxed mutable captured variables** — assignment conversion for bindings both captured and mutated, fixing a `set!`-after-capture correctness divergence and lifting the ban on natively-compiling closures with internal `set!`/defines (#1497)
- **Fixed-arity `define` values bind as native closures** instead of being evaluated, so passing a defined function as a value also runs native code (#1500)
- **Native lambda analysis buffers grow instead of bailing out** at fixed size limits, and variadic self-tail-calls now loop instead of recursing (#1498)

#### Performance

- **Batched fd reads** in `readOneByte` — up to 4096 bytes per syscall instead of one syscall per byte for byte-at-a-time port consumers (#1460)

### Fixed

#### Concurrency

- Lost cross-thread wakeup in shared channel send/receive that could park a receiver permanently (#1489)
- Dirty-snapshot dispatch hazard in `mutex-lock!`, `condition-variable-wait`, `thread-join!`, and timed channel ops, via a generic `driving` guard that excludes an in-flight fiber from re-dispatch (#1487)
- `mutex-lock!`/`mutex-unlock!`+condvar giving up instantly across OS threads instead of polling shared state, which could silently corrupt lock ownership (#1454)
- epoll stale-fire stranding a waiter on the opposite direction of a partially-fired fd (#1462)
- `thread-sleep!` unbounded native-stack growth under concurrently retrying fibers (#1463)
- Foreign thread handles in fiber primitives (`thread-join!`/`-terminate!`/`-specific`/…), closing a double-join/UB class reachable only through a shared global (#1484)
- Cross-heap mutex abandonment on fiber death — held mutexes are now tracked on the fiber itself instead of found by scanning its GC heap, which never contained a mutex shared from the parent (#1458)
- Closures losing their library environment when deep-copied across threads, which hung or raised "undefined variable" for any library-defined procedure called from a `thread-start!` thunk (#1479)

#### GC and memory

- Stale "gap" registers (dead slots between live frame windows) copied verbatim into `call/cc` continuation snapshots (#1464) and fiber suspension snapshots (#1529) — both use-after-free hazards under `-Dgc-stress=true`

#### Compiler and tooling

- Portable SRFI libraries now resolve via an exe-relative `lib/` fallback, so a `zig build`-produced binary run from any directory (with no prior `thottam` setup) can still find them (#1523)
- Fuzz generator-coverage gates bounded by instruction count instead of wall clock, so they measure generator correctness rather than timing out under `-Dgc-stress=true` or on emulated (QEMU riscv64) CI targets (#1447)

## [0.14.1] - 2026-07-11

### Added

- **Persistent GC mark worklist** on the GC struct, eliminating per-collection heap allocation (#1436)
- **Bignum rational literals** — the reader now accepts rational literals with bignum numerators or denominators (#1423)
- **Chained nested-lambda captures** in the native closure tiers (#1419)
- **Unit suite green under `-Dgc-stress=true`** — the full unit test suite now passes with collection on every allocation (#1427)
- **Fuzzing infrastructure** (Phases 1–3): seed corpora, Smith-driven grammar generator, three differential oracles (IR opt-vs-no-opt, VM-vs-native backend, Kaappi-vs-Chibi), scheduled CI job, and auto-filed GitHub issues for findings (#1388, #1398, #1403, #1405, #1408, #1418, #1424, #1426, #1434)

### Fixed

- Root bignum intermediates in rational arithmetic and `string->number` (#1421)
- Fix nested `syntax-rules` substitution and template-let ellipsis bindings (#1411)
- Descend into `let`/`let*` in the native closure free-variable analysis (#1409)
- Return exact results from `sqrt` for rational and bignum perfect squares (#1415)
- Reject native compilation when a `set!`-mutated param is captured by a nested lambda (#1425)
- Exit non-zero on every `kaappi compile` / `--emit-llvm` failure (#1417)
- Harden the `--no-ir-opt` compile guard (#1406)

### Changed

- Pin GitHub Actions by SHA and disable persisted checkout credentials (#1413)
- Build chibi-scheme from source in oracle-diff CI (#1434)
- Security-harden the DigitalOcean test skills (#1435)

## [0.14.0] - 2026-07-10

### Added

- **SRFI-17 generalized `set!`** with pre-defined setters for `car`, `cdr`, `vector-ref`, `string-ref`, `hashtable-ref`, and `slot-ref` (#1349)
- **SRFI-61 general `cond` clause** (`generator guard => receiver`) (#1357)
- **SRFI-132 complete sort library** — 22 procedures: `list-sort`, `list-stable-sort`, `list-sort!`, `vector-sort`, `vector-stable-sort`, `vector-sort!`, merge operations, selection, and deletion (#1339)
- **FFI callback error propagation:** errors raised inside `ffi-callback` are re-raised when the C call returns, instead of being silently swallowed (#1385)
- **Descriptive FFI error messages** at call time — type mismatches, arity errors, and range violations now name the FFI function and expected type (#1370)
- **Accept native procedures in `make-thread` and `spawn`** (#1366)
- **Unicode derived properties** for `char-alphabetic?`, `char-numeric?`, `char-upper-case?`, `char-lower-case?`, `char-whitespace?` — matches full Unicode spec instead of ASCII approximations (#1263)
- **Reader Unicode tables** generated from Unicode data files, replacing hand-rolled classification (#1321)
- **UTF-8 validation in `utf8->string`** — rejects invalid byte sequences at construction instead of producing corrupt strings (#1383)
- **SRFI completions:** 15 missing SRFI-41 stream procedures (#1330), 9 missing SRFI-133 vector procedures (#1308), 27 missing SRFI-235 combinators (#1338), 21 missing SRFI-125 hash table exports (#1337), 16 missing SRFI-175 ASCII procedures (#1325), SRFI-33 aliases from SRFI-60 (#1328), SRFI-174 `timespec-hash`/`timespec->inexact`/`inexact->timespec` (#1352), SRFI-197 `nest`/`nest-reverse` (#1345), SRFI-78 `check-set-mode!`/`check-ec` (#1342), SRFI-69 `hash-table-update!` (#1315), SRFI-45 `lazy`/`eager` exports (#1353), SRFI-170 `owner/unchanged`/`group/unchanged` constants (#1363), SRFI-210 `box`/`mv` exports (#1318), SRFI-13 `string-join` grammar argument (#1312)

### Changed

- **Trampoline rewrite:** `map`, `for-each`, `dynamic-wind`, and `force` are now Scheme closures bootstrapped at VM init, eliminating native VM re-entrancy for the callback family. ~460 lines of native code retired. Callbacks that `call/cc` out of `map` now park correctly instead of corrupting the native call stack (#1374, #1378)
- **Native backend NativeClosure dispatch:** all VM call sites (call, tail-call, tail-apply, `call/cc` receiver, exception handler, dynamic-wind thunks) now handle NativeClosure, fixing native-compiled programs calling bootstrapped procedures (#1376, #1379)
- **Test framework migration:** 55 test files migrated from `(chibi test)` to SRFI-64 — the R7RS suite remains on `(chibi test)` (#1382)
- **GC root buffer is now growable** — handles deep native re-entrancy without hitting the fixed 1024-slot limit (#1298)
- **`string-map`/`string-for-each`** use linear char-list traversal instead of O(n²) index-driven loops (#1378)
- **`opt*-lambda`** supports sequential defaults and lifts the 2-optional-argument cap (#1340)

### Fixed

#### GC and memory

- Fix GC crash on stale VM registers after thread start/join cycles (#1254)
- Add GC write barriers to `readListTail` `set-cdr!` calls (#1292)
- Root hash-table-walk/fold snapshot entries to prevent use-after-free (#1294)
- Clear stale registers in tail-call window extension (#1293)

#### Compiler and macros

- Fix hygiene: use-site argument no longer captured by same-name def-site local (#1301)
- Capture `let`/`lambda` locals in `define-syntax` transformers (#1287)
- Expand macros during `set!` target pre-scan (#1291)
- Use globally-unique binding IDs for `syntax-rules` literal identity (#1284)
- Separate `let-syntax` from `letrec-syntax` scoping per R7RS (#1277)
- Handle consecutive ellipses in `syntax-rules` templates (#1278)
- Report `syntax-error` message and irritants (#1273)
- Honor `fold-case` flag in `include-ci` (#1274)
- Check lexical bindings when matching `syntax-rules` literals (#1265)
- Isolate macro tables for custom environments in `eval`/`load` (#1304)
- Let imported macros shadow built-in special forms (#1302)
- Desugar `define-record-type` in body contexts per R7RS §5.5 (#1276)
- Box `set!`-mutated locals for R7RS store semantics (#1249)
- Compile `eval` body in tail position per R7RS 3.5 (#1279)
- Fix non-exported library macros leaking to importers (#1372)
- Rewrite SRFI-26 `cut`/`cute` with recursive helper macros to fix expander bug (#1344)

#### Control flow

- Fix spurious wind unwind on return into native-callback frames (#1380)
- Make advisory yield a no-op under re-entrant native frames (#1384)
- Fix yield raising inside `with-exception-handler` after `spawn` (#1369)
- Deliver multiple values when continuation invoked with != 1 argument (#1251)
- Follow redirect chain in `force` for `delay-force` intermediates (#1280)
- Remove iteration cap from `force` trampoline for unbounded `delay-force` chains (#1259)
- Move `parameterize` converter application outside `dynamic-wind` extent (#1286)
- Fix `parameterize` to evaluate all values before binding (#1260)

#### R7RS conformance

- Enforce immutability on literal vectors, pairs, and bytevectors (#1285)
- Signal error on `define`/`set!` in immutable environments (#1275)
- Reject non-environment second argument to `eval` (#1282)
- Check record type in accessors and mutators (#1281)
- Error on unknown identifiers in `import` `only`/`except`/`rename` (#1261)
- Support optional environment-specifier in `load` per R7RS §6.14 (#1262)
- Support `import-set` modifiers in `environment` (#1289)
- Unify platform feature lists across `(features)` and `cond-expand` (#1283)
- Fix `u8-ready?` returning `#f` at EOF — R7RS requires `#t` (#1258)
- Patch datum-label references inside vectors (#1257)

#### SRFIs

- Fix SRFI-1 `take-right`/`drop-right` to accept dotted lists (#1354)
- Fix SRFI-4 integer vector kinds to be disjoint types with range validation (#1336)
- Fix SRFI-9 record-type redefinition retargeting old procedures (#1371)
- Fix SRFI-13 wrong-typed optional args silently ignored (#1360)
- Fix SRFI-27 `random-integer`/`pseudo-randomize!` to accept bignums (#1319)
- Fix SRFI-27 `random-real` to return open interval (0, 1) (#1356)
- Fix SRFI-27 `random-source-make-reals` to honor the unit argument (#1367)
- Fix SRFI-27 `default-random-source` to be a variable, not a procedure (#1305)
- Fix SRFI-37 short optional-arg dropping trailing characters (#1355)
- Fix SRFI-37 `args-fold` short option matching, seed threading, `option?` export (#1343)
- Fix SRFI-41 `stream-unfold` predicate sense and stream macro hygiene (#1322)
- Fix SRFI-42 comprehensions: recursive qualifiers, guards, and missing generators (#1346)
- Fix SRFI-43 vector library to match spec (#1326)
- Fix SRFI-69 to honor custom equivalence/hash functions (#1329)
- Fix SRFI-125 `hash-table-ref`/`update!` success proc, `hash-table-find` result (#1337)
- Fix SRFI-128 default comparator total order, hashability, and `register-default!` (#1335)
- Fix SRFI-133 `vector-skip`/`vector-skip-right` multi-vector form (#1359)
- Fix SRFI-134 `ideque-filter` calling unbound `filter` (#1341)
- Fix SRFI-141 `balanced/` to use correct tie-breaking (#1334)
- Fix SRFI-143 comparison and `min`/`max` to accept variadic arguments (#1361)
- Fix SRFI-143 `fxcopy-bit` to accept boolean bit argument (#1351)
- Fix SRFI-144 `flmax`/`flmin` to be variadic per spec (#1358)
- Fix SRFI-151 bit-argument API mismatch (#1316)
- Fix SRFI-151/143 `bitwise-and`/`ior`/`xor` for negative operands (#1310)
- Fix SRFI-152 `string-every`, `string-split`, and missing exports (#1331)
- Fix SRFI-197 `chain` `_` placeholder (#1345)
- Fix SRFI-210 `set!-values` shadowing bug (#1324), `value` procedure (#1318)
- Fix SRFI-232 curried procedures to support grouped application (#1327)
- Fix SRFI-233 `ini-file->alist` missing `(scheme char)` import (#1333)
- Fix `string-contains` and `string-replace` start2/end2 handling (#1317)
- Fix `string-trim` default criterion to use Unicode whitespace (#1368)
- Fix `posix-time`/`monotonic-time` to return SRFI-19 time objects (#1320)
- Honor explicit `#f` thread arg in `mutex-lock!` as locked/not-owned (#1306)
- Honor timeout deadlines when no fibers are runnable (#1300)

#### FFI

- Fix FFI `char` type to accept Scheme characters and return characters (#1309)
- Fix `group-info` by name returning gid 0 (#1307)

## [0.13.0] - 2026-07-05

### Added

- **REPL parenthesis highlighting:** matching parentheses are highlighted as you type (#1228)
- **`KAAPPI_HOME` environment variable:** override the default `~/.kaappi/` directory for libraries, packages, and REPL history (#1031, #1084)
- **Native backend shadow-stack GC rooting:** native-compiled binaries now use a shadow stack for precise GC root tracking (#1034, #1082)
- **Native backend `letrec*` support:** `letrec*` forms now compile natively instead of falling through to the interpreter (#1026, #1078)
- **IR-path self-tail-call optimization:** self-tail-calls are optimized to loops in the IR pipeline, with line-table recording (#1035, #1083)
- **Native backend unit tests and `.sbc` equivalence tests** (#1072, #1117)
- **Comprehensive R7RS conformance audit** (Phases 0–3.4): gap tests for R7RS sections 4.1–6.14, primitives audit tests for all 21 files, SRFI conformance tests for 40+ SRFIs (#1137)

### Changed

- **All compilation routed through the IR pipeline** — the legacy `compileExpr` direct-emit path is retired; every form now lowers to IR before bytecode emission (#1038, #1136)
- **Comptime spec tables replace runtime registration** — primitive procedure metadata is now a single comptime array with compile-time duplicate and orphan detection (#1053, #1133)
- **Unified error type:** `VMError` and `PrimitiveError` collapsed into a single error set, eliminating 8 inline error-mapping switches (#1046, #1128)
- **Typed accessors:** `expect*` helpers replace bare `TypeError` returns throughout primitives (#1057, #1135)
- **GC safety by construction:** `arg_roots` auto-root allocator Value arguments; `pushRoot` is infallible (panics on overflow); `-Dgc-stress=true` forces collection on every allocation (#1045, #1125)
- **`RootedSlot`/`RootedScope` helpers** replace 36 manual `extra_roots` sites (#1054, #1132)
- **17 `SexprArgs` `NodeTag` variants collapsed** into `.sexpr_form` with `FormKind` enum (#1040, #1134)
- **Version string single-sourced** from `build.zig.zon` via `build_options` — no more manual sync of `main.zig`/`thottam.zig` (#1060, #1100)
- **Macro expansion extracted** into `compiler_macro.zig` (#1043, #1129)
- **Compiler IR handlers extracted** into `compiler_ir.zig` (#1023)
- **CLI parsing extracted** into `src/cli.zig` with table-driven flag parser (#1062, #1123)
- **`thottam.zig` split** along natural seams into focused modules (#1063, #1089)
- **LLVM native/eval boundary centralized** in one comptime table (#1068, #1126)
- **Consolidated I/O:** `writeToFd`/`writeStdout`/`writeStderr` unified into `reporting.zig` (#1067, #1131)
- **Dead code removed:** `ir_emitter.zig` (duplicate emitter), dead IR analysis passes, dead forwarding wrappers, unused functions (#1039, #1041, #1075, #1103, #1127, #1130, #1110)
- **Replaced hand-rolled JSON** in LSP with `std.json` (#1066, #1091)

### Fixed

- Fix `current-input-port` corruption under extreme GC pressure (#1013, #1015)
- Root SRFI-1 `filter-map`/`append-map`/`unfold` callback results across allocations (#1027, #1085)
- Root `callWithArgs` return values in `map`, `fold`, and `unfold` primitives (#1098)
- Fix cross-thread `fiber.status` atomics and encapsulate `child_resources` (#1028, #1087)
- Preserve line tables in `.sbc` bytecode cache (#1096, #1097)
- Fix top-level macros invisible inside bare-lambda bodies (#1025, #1077)
- Panic instead of silently dropping reachable objects on GC mark OOM (#1014)
- Panic on `writeBarrier` remembered-set OOM instead of silently dropping (#1036, #1079)
- Propagate `InvalidSyntax` from `let*-values` and `guard` instead of swallowing as OOM (#1032, #1081)
- Propagate `OutOfMemory` from compiler hash map and list insertions (#1017)
- Fix `VMError`-to-`PrimitiveError` catch-all that collapsed all errors into `TypeError` (#1016)
- Unify `typeName` into `types.zig`, fix LSP hover for records/rationals/bignums (#1033, #1080)
- Fix duplicate primitive registration (add comptime collision guard) (#1030, #1092)
- Resurrect 11 orphaned regression tests, harden `run-all.sh` (#1029, #1086)
- Reduce `gcd-gc-843` iterations to fix flaky macOS CI OOM (#1094, #1095)
- Fix `indexError` detail helper for informative out-of-bounds messages (#1020)

## [0.12.0] - 2026-07-04

### Added

- **Width-aware pretty-printing for REPL output:** large results are formatted with indentation and line wrapping instead of a single long line (#1005)
- **Multiple-values display at top level:** `(values 1 2 3)` now prints all values, not just the first (#973)
- **Uncaught error detail:** show message and irritants for uncaught user-raised errors (#976)
- **R7RS standard ports as parameters:** `current-input-port`, `current-output-port`, and `current-error-port` are now parameter objects per R7RS (#979)

### Fixed

#### GC and memory

- Fix GC corruption during library `include`-load: fresh s-expressions in Zig locals were not rooted during include processing (#1010, #1012)
- Root top-level forms before compilation to prevent collection (#1011)
- Root `vector-partition` yes/no accumulators across allocation (#810, #944)
- Root bignum intermediates in Euclid GCD/LCM loops (#843, #885)
- Root intermediate values across allocations in numeric primitives (#861, #881)
- Trace environment `Value` in `Function`/`Transformer` to prevent use-after-free (#867, #884)
- Clean up child function roots after single-expression compilation (#832, #886)
- Retire replaced library envs instead of freeing them while still reachable (#941)
- Keep `.sbc`-loaded functions rooted for the whole run (#970)
- Convert `markValue` from recursive to iterative using an explicit worklist — eliminates stack overflow on deeply nested structures (#911)
- Iterate cdr spine in `gc_deep_copy` to fix stack overflow on long lists (#801, #952)
- Track child-interned symbols on parent GC to fix memory leak (#950)
- Deep-copy `native_fn`/`native_closure` instead of aliasing across thread heaps (#975)

#### Continuations

- Fix `call/cc` escapes lost inside re-entrant native calls (`map`, `for-each`) — frame birth IDs now prevent incorrect escape detection (#934)
- Raise error on continuation resume across a returned native call frame instead of silently corrupting state (#1009)
- Fix continuation restore escape misdetection and `dynamic-wind` double-run (#870, #875, #905)
- Fix use-after-free of frame pointer after re-entrant natives grow the frames array (#927)

#### Threading (SRFI-18)

- Share globals map by pointer with SRFI-18 child threads, lock rehashes (#958, #971)
- Fix heap corruption from child threads touching shared parent state (#958, #968)
- Fix `thread-terminate!` never stopping OS threads, hanging `thread-join!` (#933)
- Lock `symbol_mutex` unconditionally in `allocSymbol` — fixes data race under concurrent interning (#797, #945)
- Honour `timeout`/`timeout-val` in `thread-join!` for OS threads (#878, #1000)
- Call `sched_yield` in `thread-yield!` when no cooperative scheduler exists (#948, #994)
- Preserve `string`/`bytevector` `eq?` identity in thread deep copy (#807, #988)
- Fix top-level `thread-yield!` scheduler interaction and pre-scheduler parameter loss (#940)

#### Compiler and IR

- Replace fixed 256-node buffers with growable lists in IR lowering — removes hard limit on form complexity (#791, #1003)
- Honor lexical shadowing of keywords in IR lowering (#788, #967)
- Suppress constant folding of `set!`-reassigned globals in the same form (#962)
- Respect lexical shadowing of primitives in IR constant folding (#790, #956)
- Invalidate stale native call sites after `set!`/`define` rebinding (#822, #981)
- Fix closure capture inside `do` loops corrupting the captured variable (#803, #954)
- Fix panic on closures capturing 27+ variables (#809, #953)
- Fix `case-lambda` capturing user variables and dropping clauses past the 32nd (#936)
- Fix lost `set!` writes and builtin-name capture in macro templates (#935)
- Probe upvalues when checking if a keyword is shadowed (#814, #951)
- Clear global cache on `set_global`/`define_global` rebind (#812, #955)
- Scope library-body `define-syntax` macros to their library — unexported macros no longer leak globally (#877, #957)
- Scope macro-generated `define-syntax` to its body (#928)
- Fix LLVM backend `set!`/`define` ignoring lexical scope (#819, #966)
- Fix LLVM backend `eval` fallback losing lexical environment (#827, #987)
- Fix LLVM backend `emitLet` fallback to include `let`/`let*` keyword (#831, #900)
- Fix `car`/`cdr` type errors in LLVM native backend (#834, #892)

#### Macro system

- Fix nested-ellipsis expansion rejecting depth-2 pattern variables (#931)
- Fix double hygiene renaming in macro-generating macros (#923)
- Fix two R7RS suite forms aborted by hygiene and macro-shadowing bugs (#926)

#### Arithmetic

- Compare rationals exactly instead of falling back to f64 (#844, #949)
- Fix bignum `toF64` double-rounding by using u128 top-two-limb combination (#833, #907)
- Fix `exact-integer-sqrt` to use scale-aware initial guess for large bignums (#851, #906)
- Parse `#e` decimal strings exactly without f64 round-trip (#856, #996)
- Fix exact denominator 2^47 wrapping and inexact NaN on huge rationals (#842, #848, #898)
- Fix `exact`/`numerator`/`denominator` abort on flonum 2^63 and bignum rational parsing (#846, #853, #896)
- Rewrite rational arithmetic paths to handle bignums without early return (#894)
- Validate operand types in `quotient`/`remainder`/`modulo`/`gcd` bignum paths (#890)
- Fix `round` on negative exact rationals with fraction < 1/2 (#837, #888)
- Fix `magnitude` on rationals (#865, #892)
- Fix `numerator`/`denominator` on flonums to use exact dyadic fraction (#858, #903)

#### I/O

- Fix `read` after `peek-char` reordering stream bytes (#804, #997)
- Fix `peek-char` returning raw lead byte for multi-byte UTF-8 on fd ports (#798, #1001)
- Check `peek_byte` before returning EOF in string-port read (#799, #1006)
- Parse fd-backed `(read)` incrementally instead of draining to EOF (#847, #984)
- Reject directories and propagate read errors in `readFileContents` (#983)
- Return `""` for `(read-string 0 port)`, not EOF (#959)
- Signal `read-error?` when `read` hits EOF mid-datum per R7RS 6.13.2 (#977)

#### Reader

- Fix Unicode reader gaps and fold-case for non-ASCII identifiers (#920, #1004)
- Fix char literal semicolon parsing and `string-prefix?`/`suffix?` argument order (#891)

#### Strings

- Fix `string-titlecase` word boundaries and Unicode case mapping (#824, #1002)
- Fix `string-join` default delimiter from empty string to single space (#825, #909)
- Fix `string-replace` index clamping and bignum parse error propagation (#830, #893)

#### FFI

- Handle bignums in `types.toF64` to fix FFI `double`/`float` marshaling (#792, #793, #998, #999)
- Accept full unsigned 64-bit range for `uint64`/`size_t` FFI arguments (#794, #992)
- Range-check FFI args against declared narrow int types (#795, #980)
- Coerce FFI bool args to 0/1 before the C `_Bool` trampoline (#796, #963)

#### Libraries

- Handle `cond-expand` and nested `include-library-declarations` in library bodies (#874, #982)
- Fix `cond-expand (library ...)` and `include` in library bodies (#917)
- Search the script's directory for libraries; unify `cond-expand` library checks (#930)
- Expand `(scheme r5rs)` to the full R5RS identifier set (#813, #965)
- Replace fixed-size export arrays with dynamic ArrayLists in `define-library` (#862, #882)
- Add missing exports to SRFI-133 and SRFI-1 library definitions (#816, #818)

#### SRFIs

- Fix SRFI-158 `gtake` crash, SRFI-189 `nothing` procedure, SRFI-115 unknown char class (#1008)
- Mark hash-table entries occupied on insert via `update!`/`default` and `alist->hash-table` (#939)
- Guard `vector-unfold`/`unfold-right` against empty multiple values (#806, #986)
- Fix `alist->hash-table` arity check (#1011)

#### Quasiquote

- Fix quasiquote nesting for `unquote-splicing`, vectors, and dotted tails (#849, #850, #852)

#### Fibers

- Fix `channel-receive` silently returning an unspecified value when the value had to flow through two or more intermediate fiber stages: a fiber blocked with no runnable siblings now parks on the channel and is woken by the next `channel-send`, so multi-stage pipelines deliver values correctly. A receive (or `fiber-join`) that can never be satisfied now raises a catchable deadlock error instead of returning void (#978)
- `apply`-forwarded `channel-receive` propagates the park signal instead of collapsing it into a type error

#### REPL and CLI

- Stop `--sandbox` pre-scan at filename boundary (#783, #1007)
- Skip `.sbc` bytecode cache in sandbox mode (#785, #995)
- Include compiler version in `.sbc` cache validity check (#925, #993)
- Reject invalid `--timeout` and `--max-memory` values instead of silently ignoring them (#787, #989)
- Exit non-zero on CLI usage, compile, and standalone-binary errors (#964)
- Register `,condition` in REPL help, tab completion, and usage table (#828, #899)
- Stop flattening newlines in REPL history entries (#915)
- Restore `debug_mode` after `,step` instead of unconditionally disabling (#914)
- Add VT and FF to `string-trim` default whitespace criterion (#913)
- Add depth guard to `prettyPrint` to prevent hang on cyclic structures (#859)
- Add missing separator before dotted tail in pretty-printer (#863, #883)

#### LSP

- Fix `positionEncoding` rejection and `jsonUnescape` `\uXXXX` (#866, #872, #901)
- Fix `MethodNotFound` response, hover newlines, dotted define crash (#873, #871, #869, #895)

#### Package manager (thottam)

- Fix version-pinned installs: use `--end-of-options` instead of `--` so the ref resolves as a revision, not a pathspec (#780, #960)
- Copy visited-set keys to fix use-after-free on transitive deps (#947)

#### Other

- Evaluate `parameterize` param expressions exactly once (#860, #887)
- Allow empty datum list in `case` clauses (#854, #889)
- Use `raise-continuable` for unmatched `guard` clauses per R7RS (#845, #897)
- Fix `symbolNeedsBars` to catch DEL, C1 controls, and non-letter Unicode (#857, #902)
- Use `fstatat` instead of `open` in `file-exists?` (#808, #990)
- Reject filesystem paths with embedded NUL bytes (#805, #985)
- Fix >255 vector args overflowing fixed arg buffers (#802, #991)
- Range-check `nice` argument to avoid `@intCast` panic (#800, #961)
- Remove dead `.sbc` cache-read path for `.sld` libraries (#937)
- Fix SRFI-64 suite silently asserting nothing; flip exit code on script errors (#929)
- Use trailing `--` instead of `--end-of-options` in pinned checkout (#969, #974)

## [0.11.1] - 2026-07-02

### Fixed

#### GC and memory

- Fix GC safety in vm_library: root AST before `handleImport`, write barrier in cond-expand splicing, root parsed declarations before compilation (#754, #757, #759)
- Add GC write barrier in vector constant deserialization (#738)
- Fix GC safety violations in rational arithmetic paths — root intermediate heap values across allocating calls (#747)
- Fix data race in symbol table marking during SRFI-18 threading — use blocking lock instead of tryLock (#750)

#### Arithmetic

- Fix exact rational + bignum arithmetic to preserve exactness instead of falling back to inexact float (#746)
- Fix two-argument `log` to return complex for negative first argument (#752)
- Fix `angle` to return pi for -0.0 using `atan2` (#748)
- Fix minInt negation overflow in `abs`, unary minus, and `magnitude` — auto-promote to bignum (#744, #749)
- Fix `toRationalParts` returning `{0, 1}` for non-numeric types instead of raising a type error (#741)
- Fix multi-arg bignum division to process all divisors — `(/ (expt 2 100) 3 7)` now produces 2^100/21 (#739)
- Apply exactness prefix to complex number parsing in `string->number` (#751)

#### Compiler

- Fix off-by-one in `addConstant`: allow 65536 constants (#756)
- Check `resolveUpvalue` before applying `apply` tail-call optimization when `apply` is shadowed by a closure variable (#760)
- Decrement `no_collect` before propagating pushRoot OOM after macro expansion, preventing permanent GC suppression (#761)
- Validate `let-syntax` bindings have transformer spec (#758)

#### Deep copy

- Fix deep copy of promise, parameter, and error_object: register in visited map before recursing to prevent infinite recursion on circular structures (#753, #755)

#### Bytecode serialization

- Handle EOF and UNDEFINED values in writeConstant/readConstant (#743, #745)

#### Package manager (thottam)

- Add `.git` suffix to `resolveVersion` URL (#733)
- Check build exit code in `doUpdate` (#734)
- Track update failures and exit 1 if any failed (#735)
- Add `--` separator before version in `git checkout` (#736)
- Validate package name in `doRemove` before path construction (#737)

#### CLI and REPL

- Make REPL Ctrl-C show fresh prompt instead of exiting (#742)
- Report missing arguments for CLI flags (`--lib-path`, `-o`, etc.) (#740)

### Changed

- Split `main.zig`, `ir.zig`, and `memory.zig` into smaller files per 1500-line policy (#732)

## [0.11.0] - 2026-07-02

### Added

- **R7RS eval environments:** `eval` now honors its second argument; added `environment`, `null-environment`, `scheme-report-environment`, and `interaction-environment` procedures (#691)
- **Vector patterns in syntax-rules:** pattern matching and template instantiation for vector literals in `syntax-rules`
- **Ellipsis-depth validation:** syntax-rules templates validate that pattern variables are used at correct ellipsis nesting depth
- **Structural hashing:** `equal?`-based hashing for pairs, vectors, and bytevectors (improves SRFI-69/125 hash table distribution)
- **R7RS exit with dynamic-wind cleanup:** `exit` runs `dynamic-wind` before/after handlers per spec; `emergency-exit` provides immediate termination without cleanup
- **`get-environment-variables`:** R7RS process-context procedure returning all environment variables via POSIX environ
- **Cycle detection in list operations:** `member`, `memq`, `memv`, `assoc`, `assq`, `assv`, and `list-copy` detect circular lists instead of looping infinitely
- **Syntax-rules pattern variable limit:** raised from 16 to 128 per ellipsis level

### Fixed

#### GC and memory

- Fix generational GC: mark `Closure.func` in minor collections — unmarked closures could be collected prematurely
- Fix generational GC: mark `RecordInstance.record_type` in minor collections
- Fix `hash-table-walk`/`hash-table-fold` use-after-free when callback triggers rehash
- Fix GC roots in `loadLibrarySource`, `compileFile` preamble replay, and `handleTopLevelForm` (#699, #700)

#### Macro system

- Fix `let-syntax` referential transparency: free variables in transformer output now resolve in the definition environment
- Fix macro hygiene for template-introduced bindings whose names shadow built-in procedures

#### Compiler

- Fix internal-define pre-scan: use dynamic list instead of fixed 64-entry buffer — more than 64 internal defines no longer crashes
- Fix passthrough constant folding: check globals for redefined primitives before folding (#600 follow-up)
- Fix `define-values` register corruption with 2+ names in lambda body

#### LLVM native backend

- Fix native closure compilation: bail out for variadic lambdas instead of generating incorrect code
- Fix local parameter shadowing in call position — shadowed parameters now use the correct binding

#### Reader

- Require delimiter after numeric tokens per R7RS (e.g., `1a` is now an error, not parsed as `1`)
- Fix `char-alphabetic?` misclassifying non-letter Unicode codepoints (e.g., digits, symbols)

#### Hash tables

- Fix hash-table sentinel collision: `eof-object` and `void` are no longer confused with empty/deleted slots

#### I/O

- Fix `read-bytevector!` returning wrong value for zero-length target at EOF
- Fix `writeJsonEscaped`: properly escape backspace (`\b`) and form feed (`\f`)

#### Library loading

- Fix `handleDefineLibrary` aborting on import errors instead of propagating; fix bundled file paths (#703)
- Fix `compileFile` preamble skip and GC safety (#699)

#### CLI and REPL

- Fix `(command-line)` removing hardcoded "kaappi" prefix from output
- Fix REPL tab completion for Scheme identifiers containing `-`, `?`, `!`, `->` (#676)

## [0.10.0] - 2026-07-01

### Added

- Abandon mutexes held by terminated fibers, per SRFI-18 spec (#642)
- Detect `thread-join!` on current thread and raise error, per SRFI-18 spec (#643)
- Remove 256-argument cap from `apply` by using heap-allocated ArrayList (#649)
- Reduce `case` per-datum bytecode from ~39 to ~21 bytes, raising practical clause limit from ~700 to ~1000+ (#644)

### Fixed

#### GC and threading

- Fix `referencesYoung` .fiber case missing `handler_stack`, `wind_stack`, `param_overrides`, and `frame.native` — could cause premature remembered-set eviction (#646)
- Fix `markVMRoots` iterating shared libraries map in child threads without synchronization (#634)
- Fix `VM.initForThread` sharing parent's Port objects by raw pointer instead of allocating fresh ports per thread (#635)
- Fix `equal?` exponential blowup on shared DAGs deeper than 128 nodes (#648)

#### LLVM native backend

- Fix tail call passing pointer to caller's stack alloca — LLVM may reuse the frame, corrupting arguments (#639)
- Fix `emitDirectCall` skipping arity validation, causing silent wrong results on over/under-application (#636)

#### Reader and compiler

- Fix reader truncating peculiar identifiers like `->foo` to just the sign character (#647)
- Fix internal `define-syntax` inside `let`/`letrec` body leaking macro binding into enclosing scope (#651)

#### Strings

- Fix `string-for-each`/`string-map` byte cursor desync when callback mutates the string via `string-set!` (#645)
- Fix SRFI-13 `parseStartEnd` and `string-take`/`-drop` silently clamping out-of-range indices instead of raising errors (#640)

#### Arithmetic

- Fix `parseBignumString` CHUNK_DIGITS overflow for radix 12–36 (#631)
- Fix complex number printing dropping `-0.0` components (#637)

#### I/O

- Fix `read-bytevector` allocating full k-byte buffer upfront — a large k caused hangs; exploitable under `--sandbox` (#638)

#### FFI

- Fix `toCString` silently truncating strings with embedded NUL bytes (#630)

#### LSP

- Fix LSP crash on negative or oversized line/character position values (#641)

#### Other

- Fix `create-temp-file` raising uninformative bare TypeError on long prefix (#632)
- Fix REPL `highlightCallback` misparsing character literals like `#\;` and `#\(` (#633)

## [0.9.1] - 2026-07-01

### Fixed

#### Security

- Fix git argument injection in thottam package manager — custom source URLs starting with `-` parsed as git options (#614)

#### Compiler

- Fix bare lambda internal define register clobbering (#601)
- Fix constant folding ignoring redefined primitives (#600)

#### Arithmetic and numeric

- Fix exact division with bignums returning flonum instead of rational (#612)
- Fix `makeRationalFromReader` using unchecked `makeFixnum`, truncating large rational literals (#610)
- Fix `toRationalParts` calling `toFixnum` on bignum fields (#611)
- Fix `floor-quotient`/`truncate-quotient` fixnum overflow on `minInt(i48) ÷ -1` (#603)
- Fix `string->number` `"#e<large>"` process abort from unchecked `@intFromFloat` (#604)

#### GC and memory

- Fix `deepCopyValue` dropping transformer fields on cross-thread copy (#605)
- Fix `deepCopyValue` record_instance missing cycle guard, causing stack overflow on cyclic records (#606)

#### Bytecode

- Fix bytecode symbol name length write/read mismatch, panic on names > 4096 bytes (#609)
- Reject denormalized bignum in bytecode reader (#607)

#### Macro system

- Fix macro import leaking entire `def_env` into importer (#608)

#### CLI

- Fix `-o` flag stripped from `(command-line)` in normal runs (#602)

#### Package manager

- Fix `isConstraintSpec` panic on empty-after-trim version string (#613)

## [0.9.0] - 2026-06-30

### Added

- **Growable frame stack and register array:** frame stack starts at 480 and doubles on overflow up to 32,768; register file starts at 2,048 and grows to 65,536 — eliminates fixed-size stack overflow for deeply recursive programs
- **R7RS 5.3.2 compliance:** internal `define` forms desugared to `letrec*` per spec, enabling correct scoping in procedure bodies
- **Benchmark infrastructure:** 13 benchmarks covering continuations, tail calls, closures, bignum, GC pressure, plus trend visualization with regression detection and PR-level comparison workflow
- **Shell completion:** `--completions` flag generates completions for bash, zsh, and fish
- **Complex number math:** trig, inverse trig, `exp`, and `log` now accept complex arguments; `real-part`, `imag-part`, `magnitude`, `angle` handle bignum and rational inputs
- **Radix support:** `number->string` supports radix for bignums and rationals
- **R7RS radix/exactness prefixes:** `string->number` handles `#b`, `#o`, `#d`, `#x`, `#e`, `#i` prefix combinations
- **`file-info:blocks`:** reads `st_blocks` from stat

### Fixed

#### GC safety

- Root closure during upvalue capture to prevent collection
- Fix `markObjectContents` missing types causing use-after-free
- Clear old marks before full collection (corruption fix)
- Fix object size calculation for continuations (undercounted by 8x), ports, FFI types, user/group info
- Fix hash table marking using wrong sentinel in minor collection
- Add missing write barriers in mutation primitives, `hash-table-merge!`, `%parameter-set!`, `set_upvalue`/`set_box_local` opcodes, `%record-set!`, promise forcing, fiber/channel/SRFI-18 mutations
- Fix generational GC remembered set in `%record-set!`
- Root values across allocations in `vector-map`, `vector-unfold`, `vector-cumulate`, `bignum expt`, `string-split`, `map`, `call-with-values`, `make-parameter`, `command-line`, `handleDefineValues`, reader dotted-pair path, variadic call setup
- Fix unbounded `extra_roots` growth from compiler macro re-rooting
- Fix `extra_roots` leak from bytecode deserialization
- Fix `deepCopy` hash table using wrong hash function
- Add `maybeCollect` call to `allocNativeClosure`
- Add `errdefer` to alloc functions for auxiliary allocations
- Unroot accessor/mutator functions in `vm_records`

#### Compiler

- Fix `case =>` proc clause clobbering live local registers
- Guard `apply` tail-call optimization against local variable shadowing
- Fix panic on calls with >255 arguments
- Fix identity elimination dropping type checks and breaking signed-zero
- Fix `zero?` constant folding to reject non-numeric arguments
- Remove incorrect `(not (not X)) → X` optimization
- Prevent `(* expr 0)` from dropping side effects
- Fix buffer overflow in `syntax-rules` free-reference collection
- Fix `let-syntax` with >16 bindings leaking macros into enclosing scope
- Fix correctness bugs in `do`, `define`, `cond`/`case =>`, `delay`, and named-let
- Splice top-level `begin` so `define-record-type` works inside it
- Stop `define-record-type` from polluting user namespace
- Fix `define-values` to reject arity mismatches

#### FFI

- Fix unsigned return types marshaled as signed
- Fix `uint32` params panic for values > 2^31
- Fix integer args crashing on out-of-range values
- Fix `toIntArg` wrong sign and silent truncation for bignums
- Fix bignum arguments extracting pointer bits instead of numeric value
- Fix `bool_type` to accept Scheme booleans and return booleans
- Fix callback slot leak on allocation failure
- Fix pointer truncation for large addresses (promote to bignum)
- Fix use-after-free when calling functions from invalidated library
- Make `(pointer, long, long, pointer)->void` handler generic

#### Arithmetic and numeric

- Fix `inexact->exact` to return true IEEE-754 value for non-integer flonums
- Fix `floor`/`ceiling`/`truncate`/`round` on exact rationals to use exact arithmetic
- Fix `exact` returning flonum instead of bignum for large values
- Fix `expt` with exact rational base returning inexact result
- Handle bignum first argument in `sub` and `div` rational paths
- Fix `gcd` crash on inexact args outside i64 range
- Fix `negate` and `absVal` to check `minInt(i48)` not `minInt(i64)`
- Fix bignum rational normalization and sign predicates
- Allow inexact zero division to yield IEEE 754 infinity/NaN
- Fix `memv` and `assv` to handle bignums, rationals, and complex numbers
- Reject non-integer flonums in `even?` and `odd?`

#### Reader and I/O

- Fix token validation for codepoints, delimiters, and booleans
- Fix `readConstant` accepting malformed numeric constants from `.sbc`
- Fix `#e` on complex numbers and `#i` on bignums
- Fix `string->number` to return `#f` for `#e+inf.0` and `#e+nan.0`
- Skip character literals and pipe-quoted symbols in REPL paren depth
- Raise read error on file port syntax errors instead of returning EOF
- Propagate reader errors from `hasMore()` instead of swallowing them
- Fix REPL completion out-of-bounds read and highlight allocator mismatch
- Fix `peek-char` to restore exact consumed bytes, not re-encoded codepoint
- Fix EINTR handling in all read/write syscall loops
- Fix bytevector port primitives: `u8-ready?`, `read-bytevector`, `get-output-bytevector`

#### LLVM native backend

- Mark tail position in `let`/`let*` body expressions
- Fix symbol escaping and LSP document text memory leak
- Update `current_block` in `and`/`or`, handle symbol refs in `define`/`set!`
- Fix `when`/`unless` emitting incorrect phi predecessor blocks
- Fix arithmetic for non-fixnum operands and overflow

#### VM and runtime

- Handle `ContinuationInvoked` in `call_global` and `tail_call_global` fast paths
- Fix `pending_lib_envs` unconditional pop causing use-after-free on deep nesting
- Fix `callWithArgs` register bounds check and >255 args panic
- Fix u16 overflow panic in call-family dispatch handlers
- Add arity check for native functions in `tail_apply`
- Add FFI function and parameter object support to `tail_apply`
- Add missing `ArityMismatch` handling in `call-with-values` multi-value branch
- Detect re-entrant promise forcing per SRFI-45

#### Fibers and threading

- Fix fiber error handling: proper limit error, error propagation, native proc rejection
- Fix fiber scheduling starvation with round-robin dispatch
- Reclaim completed fiber slots in scheduler
- Fix four SRFI-18 threading bugs
- Store `default-random-source` on VM instead of thread-local

#### Strings and characters

- Fix character write format and `string-every`/`string-any` char criterion
- Handle `start`/`end` arguments in `string-pad` and `string-pad-right`
- Escape control characters in write mode for strings and symbols
- Accept char arguments as criterion in SRFI-13 string functions
- Validate `write-string` start/end indices are non-negative
- Fix char folding to use fold table and handle multi-char expansions
- Reject `string-set!` at index 0 on empty string
- Reject surrogate codepoints in `integer->char`

#### Vectors

- Fix `vector-count`, `vector-index-right`, and `vector-partition` SRFI-133 bugs
- Process vector unquotes in quasiquote splicing context
- Validate `vector-append-subvectors` indices are non-negative and in bounds

#### R7RS library compliance

- Fix `export (rename ...)` to use R7RS flat syntax
- Add `exact-integer-sqrt` to `(scheme base)` exports
- Remove `open-binary-input-file` and `open-binary-output-file` from `(scheme base)`
- Remove non-R7RS exports from `(scheme write)`
- Remove duplicate `string->symbol` entry from `(scheme base)`
- Fix import modifiers to apply to exported macros
- Replace fixed-size arrays with dynamic lists in import `except`/`rename`

#### Package manager (thottam)

- Fix semver resolution to use `KAAPPI_ORG`
- Fix caret (`^`) semver constraint for major version 0
- Validate package names and use cwd to prevent shell injection
- Fix memory leaks in `runCapture`, `runPassthrough`, and `getPkgManifest`
- Fix `readFile` to propagate read errors instead of returning partial data
- Fix `doVerify` SHA parsing to exclude source URL from lockfile

#### Filesystem

- Fix error handling: descriptive errno, `getgroups` cap, `readlink` truncation
- Validate `mode`/`uid`/`gid` range instead of panicking
- Validate `user-info` and `group-info` reject negative integer arguments
- Distinguish `char-special` and `block-special` in `file-info-type`

#### Bytecode serialization

- Fix cached bytecode path to handle bundled files and preamble
- Fix f64 read/write to use little-endian byte order
- Add fixnum range validation during deserialization
- Fix memory leaks in deserialization error paths

#### LSP

- Support string request IDs
- Fix three JSON handling bugs
- Fix document text memory leak
- Fix `safeValueDescription` `native_closure` tag

#### Debugger

- Fix break line number and up/down navigation
- Free breakpoint name/condition strings on delete, cap overflow, and VM teardown
- Add bounds check on register access
- Fix `allocator.free()` called on string literal in watches
- Fix dangling pointer in watch command

#### Expander

- Fix flonum datum patterns and ellipsis escape hygiene
- Fix infinite loop when `cond-expand` clause has empty body

#### SRFI-27

- Fix `make-random-source` seeding and unit validation
- Fix lossless state roundtrip, negative arg guard, zero-state rejection

#### Other

- Fix record field spec validation and REPL datum comment handling
- Fix crashes in record primitives, `read-bytevector!`, and `hash-table-merge!`
- Fix printer freeing string literal on bignum `toString` failure
- Escape JSON string values in profile output
- Use PID-unique temp path for native compilation LLVM IR

### Changed

- Split four files that exceeded the 1500-line policy
- Use descriptive `typeError` calls instead of bare `PrimitiveError.TypeError`

## [0.8.0] - 2026-06-28

### Added

- **Generational GC:** young/old generations with minor and full collections; young objects surviving 2 minor cycles are promoted; write barrier tracks old→young references
- **Native compilation CLI:** `kaappi compile program.scm -o binary` bundles LLVM IR emission and linking in one command; finds `libkaappi_rt.a` via `KAAPPI_LIB_DIR`, exe-relative path, or `zig-out/lib/`
- **LLVM backend — tail call optimization:** self-tail-calls compiled as loops; cross-function tail calls use LLVM `tail call` annotation
- **LLVM backend — variadic parameters:** lambdas with rest parameters `(lambda (x . rest) ...)` compiled natively
- **LLVM backend — let/let\* bindings:** compiled as LLVM alloca + store instead of falling back to `kaappi_eval`
- **LLVM backend — inline lambdas:** compiled to native LLVM functions wrapped as NativeClosure values
- **LLVM backend — native closures:** new NativeClosure heap type for lambdas capturing outer parameters
- **LLVM backend — inlined primitives:** `+`, `-`, `*`, `<`, `=`, `car`, `cdr`, `cons`, `null?` emitted as direct C-ABI calls bypassing runtime dispatch
- **LSP:** go-to-definition and find-references for top-level definitions
- **Debugger:** step-out, conditional breakpoints (`condition <id> <expr>`), watch expressions, up/down frame navigation
- **REPL syntax highlighting:** real-time ANSI coloring for keywords, strings, numbers, comments, booleans, parentheses
- **Package manager:** semver version constraints in depends fields (`>=`, `>`, `<=`, `<`, `^`, `~`, comma-separated ranges)
- **"Did you mean?" errors:** Levenshtein-based suggestions for undefined variable names
- **Fuzz testing:** compiler and eval fuzz targets (in addition to existing reader and bytecode loader targets)

### Fixed

- `kaappi compile` finds `libkaappi_rt.a` relative to the binary using `_NSGetExecutablePath` (macOS) / `/proc/self/exe` (Linux); release artifacts now include `libkaappi_rt.a`
- Unit test false failure from disassembler stderr writes corrupting Zig test runner IPC

## [0.7.0] - 2026-06-28

### Added

- **LLVM native backend:** compile Scheme programs to native executables via `zig build native -Dnative-src=program.scm` or `kaappi --emit-llvm`
- **Native lambda compilation:** simple functions compile as separate LLVM function definitions with direct calls; self-recursive calls bypass runtime dispatch
- **Closure support in native backend:** inner lambdas capturing outer parameters work in native binaries
- **Hybrid continuation strategy:** `guard`, `raise`, `with-exception-handler`, `dynamic-wind`, `call/ec` compile natively; `call/cc` falls back to bytecode VM
- **IR pipeline:** 33-node intermediate representation with 3 analysis passes (tail positions, primitive identification, constant detection) and 5 optimization passes (constant folding, dead branch elimination, boolean simplification, identity elimination, begin simplification)
- **`(scheme repl)` library:** R7RS §6.4 standard library, exporting `interaction-environment`
- **`include-library-declarations`:** R7RS §5.3.2 support in `define-library`
- **Error source snippets:** runtime errors show the offending source line indented below the error message
- **LSP documentSymbol:** outline view and breadcrumbs for Scheme files in VS Code
- **Profiler JSON export:** `--profile-json <file>` writes machine-readable profiling data
- **Standalone native binary:** `zig build native -Dnative-src=...` single-step compilation
- **E2e test infrastructure:** 23 native parity tests using kaappi-bdd, wired into CI
- **SRFI-69:** `hash-table-equivalence-function`, `hash-table-hash-function`
- **SRFI-133:** `vector-append-subvectors`
- **Benchmarks:** string, list, vector, hashtable benchmarks (suite grows from 4 to 8)

### Changed

- **Compiler:** all expressions route through IR pipeline (`lowerWithMacros` → analysis → optimization → `compileFromNode`)
- **IR lowering:** `lower()` is now a thin wrapper over `lowerWithMacros(null)`; macros threaded through all recursive lowering helpers

### Removed

- **JIT backends:** removed 5,215 lines of hand-written AArch64 and x86_64 JIT code; replaced by LLVM native backend
- **`--no-jit` flag:** no longer needed

### Fixed

- **IR lowering:** nested calls inside `if`/`begin`/`and`/`or` produced `passthrough` nodes instead of proper `call` nodes
- **Native backend:** symbol constants not interned at runtime, breaking `eq?` identity in closures
- **Native backend:** quoted list constants (`'(1 2 3)`) emitted as dangling pointers
- **Native backend:** `define-syntax` forms not processed at compile time, preventing macro use in subsequent expressions

## [0.6.6] - 2026-06-27

### Fixed

- **Expander:** Mismatched-length ellipsis template variables read uninitialized memory; now returns clean error
- **Reader:** Datum-label placeholder (`#N=`/`#N#`) not GC-rooted — use-after-free during nested read
- **Reader:** Malformed `#`-prefixed numeric literals (`#d` at EOF, `#e1e19`) panicked instead of clean error
- **String:** `string-fill!` lacked start/end validation — out-of-range or non-fixnum args aborted the interpreter
- **String:** `string-ci=?` and friends used downcase instead of case-folding (wrong for long-s, micro sign)
- **Compiler:** Binding forms (`let`, `let*`, `letrec`, `do`) panicked on malformed or >32-element bindings
- **Compiler:** `no_collect` leaked on `let-values` error paths, permanently disabling GC in the REPL
- **Compiler:** `letrec`/`letrec*` stored bindings in shared globals — closures didn't get fresh per-activation state
- **Compiler:** `let-values` used sequential scoping instead of evaluating all producers in the outer scope (R7RS §4.2.2)
- **SRFI-18:** `thread-join!` never freed the child VM/GC/heap (memory leak per thread)
- **SRFI-18:** Child thread data races — globals marking wrote cross-heap mark bits, `markRoots` deadlocked on symbol mutex, fiber result stored child-heap pointers visible to parent GC

### Changed

- **Build:** Release binaries now stripped (`-Dstrip` option) — Linux x86_64 drops from 9.6 MB to 1.7 MB

## [0.6.5] - 2026-06-27

### Changed

- **Bytecode:** Register operands widened from u8 to u16 (format version 3→4), raising the per-function register limit from 250 to 2048 for large library modules
- **Runtime:** Main entry point runs on a worker thread with 64 MB stack to prevent stack overflow from deeply nested `cond`/`if` chains in the compiler's recursive descent

### Fixed

- **FFI:** 64-bit integer returns (c_long) silently truncated to 48-bit fixnums; now promotes to bignum for values exceeding ±2^47
- **FFI:** Pointer returns promote to bignum for addresses ≥ 2^47; `marshalToPointer` handles bignum round-trips
- **FFI:** qsort-shaped handler `(pointer, long, long, pointer) -> void` panicked on negative count/size
- **FFI:** `validateArg` accepts bignums for `long` and `pointer` FFI types
- **Printer:** Stack overflow on deeply nested structures (200k+ levels); `markCyclesRec` and `printValue` now enforce `MAX_PRINT_DEPTH`
- **Vector:** `vector-reverse!`, `vector-reverse-copy`, `vector-unfold` panicked on negative index args (unchecked `@intCast` to `usize`)
- **String:** `string-take`, `string-drop`, `string-take-right`, `string-drop-right`, `string-pad`, `string-pad-right`, `string-replace`, `string-tabulate`, and `parseStartEnd` panicked on negative index args
- **String:** `string-pad`/`string-pad-right` crashed on multi-byte pad characters (>255 codepoint)
- **String:** `string-replace` with `start > end` silently produced corrupted output instead of erroring
- **Compiler:** `case` treated `=>` as the arrow keyword even when `=>` was lexically bound; `cond` upvalue check also added
- **Compiler:** Quasiquote with `unquote-splicing` dropped nested `unquote` in sibling elements
- **GC:** `markValue` overflowed the native stack on deeply nested pair chains; now iterates whichever branch (car or cdr) is deeper instead of recursing on both
- **GC:** AST nodes collected during macro expansion before the expanded form was rooted; `expandMacro` now suppresses GC until the result is rooted
- **Runtime:** `typeError` crashed when trying to display GC-corrupted values; now uses safe tag-only description
- **CI:** `fail-fast: false` in test matrix; R7RS crash diagnostics with stderr capture and `--no-jit` retry
- **CI:** `run-all.sh` `wait "$pid" || true` masked non-zero exit status, hiding crashed tests

## [0.6.4] - 2026-06-26

### Added

- Nested/composed import sets: `(prefix (only (scheme base) car cdr) s:)` now works per R7RS §5.6

### Fixed

- **GC safety:** Root accumulators in SRFI-1 `circular-list`, `lset-adjoin`, `lset-union`, `lset-xor`, `append-reverse`, `concatenate`, `cons*`, `unfold`
- **GC safety:** Root return value across dynamic-wind after-thunks in `.return` handler
- **GC safety:** Root vector elements during bytecode cache deserialization
- **GC safety:** Clean up `extra_roots` on bytecode deserialize error paths (memory leak)
- **JIT aarch64:** Fix `pair?` predicate branch offset (7→9) with patch-based approach
- **JIT x86_64:** Shrink register cache to {r8, r9} to avoid r10/r11 scratch conflict
- **JIT both:** Make `box_local`/`get_box_local`/`set_box_local` side-exit to interpreter (was miscompiled as plain copies)
- **Arithmetic:** Fix silent fixnum truncation in `gcd`, `lcm`, and rational `+`/`-`/`*`/`/` for results exceeding ±2^47
- **Arithmetic:** Fix `lcm` i64 multiply panic with overflow-checked bignum promotion
- **Numeric:** Fix `exact`, `string->number`, `real-part`, `floor`/`ceiling`/`truncate`/`round`, and `numerator`/`denominator` overflow/panic for large values
- **Filesystem:** Fix `file-info` field truncation for inode/device/size/time values over 2^47
- **Filesystem:** Fix `file-info:device`/`rdev` dropping device minor number on Linux
- **I/O:** Fix `peek-char` corrupting multi-byte UTF-8 characters on file ports
- **Library:** Fix use-after-free crash on library redefinition (dangling registry key)
- **Package manager:** Fix invalid free of trimmed sub-slice in `runCapture`
- **Package manager:** Fix subprocess exit-status decode treating signal-killed processes as success
- **Bytecode:** Raise `MAX_CODE_BYTES` from 1MB to 4MB with diagnostic on limit hit
- **VM:** Fix `guard` + deep recursion crash by reducing max-frames and heap-allocating VM
- **VM:** Fix `memory_limit` collection bypassing `no_collect` guard
- **Compiler:** Fix constant folding ignoring local/upvalue shadowing of operators
- **VM:** Fix `write`/`read` syscall results cast to `usize` before error check

## [0.6.3] - 2026-06-26

### Fixed

- macOS signed binaries crashing on JIT due to missing `allow-jit` entitlement for hardened runtime

## [0.6.2] - 2026-06-26

### Fixed

- JIT NaN-boxing encoding mismatch causing arithmetic crashes on both AArch64 and x86_64 backends
- Verification link in README now points to download page

## [0.6.1] - 2026-06-25

### Fixed

- Root intermediate heap values in multi-allocation GC loops
- Root remaining unrooted heap intermediates across the runtime
- Propagate errors from silent `catch {}` discards instead of swallowing them
- Complete error type coverage in remaining dispatch paths
- Convert `readListTail` to iterative to prevent stack overflow on long lists
- Add FFI argument type validation and sandbox defense-in-depth

### Added

- Vision and philosophy document for contributors (`docs/dev/vision.md`)
- Developer guide for GC safety and error handling (`docs/dev/gc-safety-and-error-handling.md`)
- Downloads page at kaappi-lang.org/download/
- GPG signature verification instructions in installation guide

## [0.6.0] - 2026-06-25

### Added

- 5 new REPL commands: `,quit`/`,exit`, `,version`, `,load <file>`,
  `,import <lib>`, `,dis <expr>`
- Grouped `,help` output with section headers (Evaluation, Inspection,
  Debugging, System)
- Usage hints for bare comma commands (e.g. `,time` without arguments
  shows `usage: ,time <expr>`)
- `thottam` supports fetching packages from arbitrary Git URLs
  (`thottam install ::url <git-url>`)
- Portable SRFI libraries bundled in release assets (`kaappi-lib.tar.gz`)
  and installed to `~/.kaappi/lib/` by the install script
- 21 new portable SRFIs (0, 4, 6, 17, 19, 23, 37, 38, 42, 43, 45, 60, 61,
  78, 87, 116, 127, 130, 134, 144, 197), bringing the total to 72
- REPL banner shows `,help` hint for discovering commands

### Changed

- **NaN-boxing**: values are now NaN-boxed 64-bit words — flonums are packed
  directly into the Value without heap allocation, improving floating-point
  performance and reducing GC pressure
- Piped stdin is evaluated without the REPL banner or prompts
  (`echo '(+ 1 2)' | kaappi` prints only `3`)

### Fixed

- FFI parameter limit raised from 4 to 5
- Library import errors now report the actual missing dependency instead of
  blaming the top-level library (e.g. "library not found: (srfi 132)"
  instead of "library not found: (mylib stats)")
- NaN-boxing edge cases: bignum division, exact conversion,
  exact-integer-sqrt hang, flonum printer
- WASM build compatibility with NaN-boxing

## [0.5.0] - 2026-06-25

### Added

- `--timeout` and `--max-memory` CLI flags for resource limits (time and
  memory caps for script execution)
- REPL history moved to `~/.kaappi/history` with comma command tab completion
- Sandbox mode blocks SRFI-18 OS threads

### Fixed

- Type error messages now include expected-vs-actual context across all
  primitives (21 files)
- Improved error messages for failed imports and arity mismatches

## [0.4.0] - 2026-06-24

### Added

- WebAssembly (wasm32-wasi) build target: `zig build wasm` produces
  `kaappi.wasm` for browser and WASI runtimes
- WASM binary included in GitHub Release artifacts
- `--coverage` flag: reports which exported library procedures a test run
  exercises (per-library counts to stderr)
- `--coverage-xml` flag: writes Cobertura XML coverage report with
  source-mapped line numbers
- GPG-signed SHA256SUMS in release artifacts
- Codecov integration in CI for Zig source coverage

### Fixed

- JIT tail_call and self-call bugs causing data corruption on recursive
  closures
- JIT `emitStoreHalfAtOffset` slow path stored address instead of value
- JIT `emitSelfCallSequence` STP writeback bug (re-enabled optimization)
- `--coverage-xml` line numbers now map to real source locations
- Thread deep copy hardened: proper error handling and memory leak fixes

### Changed

- JIT compiler handles `closure`, `close_upvalue`, and closure tail calls
  natively (fewer side-exits to interpreter)
- Split `vm.zig` into `vm_dispatch.zig` and `vm_calls.zig` for
  maintainability
- Split `jit.zig` into three files: orchestration, AArch64 compiler,
  x86_64 compiler
- CI hardened: job dependencies, timeouts, build caching, security
  permissions, GitHub Actions bumped to Node 24

## [0.3.0] - 2026-06-23

### Added

- Language Server Protocol (LSP) server (`kaappi-lsp`) with diagnostics,
  completions, and hover — works with VS Code, Neovim, Emacs, Helix
- REPL: Ctrl+R reverse history search, `,type`, `,describe`, `,apropos`
  commands, and `_` variable for last result
- 21 new SRFIs (51 → 72): 0, 4, 6, 17, 19, 23, 37, 38, 42, 43, 45, 60,
  61, 78, 87, 116, 127, 130, 134, 144, 197
- SRFI 19 expanded: timezone support, date parsing (`string->date`),
  `date->time-utc`, day-of-week/year, Julian day conversions,
  format directives (~a, ~A, ~b, ~B, ~e, ~j, ~W, ~z, ~N)
- SRFI 19 test suite (112 tests)

### Fixed

- x86_64 JIT crash: `readU16` used wrong byte order (little-endian vs
  VM's big-endian), causing misread jump offsets and SIGABRT on Linux
- JIT branch-target pre-scan: added bounds checking for jump targets
- thottam: build command cwd handling and manifest use-after-free
- `install.sh`: checksum verification and tmpdir cleanup

## [0.2.1] - 2026-06-23

### Added

- Colored output for thottam (green/red/cyan, TTY-gated — no escape codes
  when piped)
- Thottam integration test in CI (install/remove cycle against kaappi-json)

### Removed

- Old `scripts/thottam` shell script (replaced by the Zig binary in v0.2.0)

## [0.2.0] - 2026-06-23

### Added

- `thottam` package manager rewritten in Zig as a compiled binary, replacing
  the shell script (`scripts/thottam`). Ships alongside `kaappi` in release
  artifacts for all 4 platforms. Adds dependency cycle detection.

### Changed

- Release workflow now builds and uploads `thottam` binaries for all platforms
- `install.sh` now downloads and installs both `kaappi` and `thottam`
- macOS binaries (both `kaappi` and `thottam`) are Developer ID signed and
  Apple notarized

## [0.1.2] - 2026-06-23

### Changed

- macOS binary is now signed with Developer ID and notarized by Apple,
  eliminating the Gatekeeper "malware" warning for downloaded binaries

## [0.1.1] - 2026-06-23

### Fixed

- Release binaries printed `DebugAllocator` leak warnings to stderr when stdin
  was piped — now use `c_allocator` in release builds, `DebugAllocator` only in
  Debug mode
- macOS binary triggered Gatekeeper "malware" warning — release workflow now
  ad-hoc code signs the macOS binary

## [0.1.0] - 2026-06-23

Complete R7RS-small implementation with 554 built-in procedures, 32 syntax
forms, 14 standard libraries, 51 SRFIs, C FFI, JIT compiler, green threads,
profiler, stepping debugger, bytecode caching, and standalone binary bundling.

### Added

- x86_64 JIT backend with full feature parity to AArch64 (all opcodes,
  specialized arithmetic, function calls, self-tail-call)
- Register allocation for x86_64 JIT via lazy-store cache
- Cross-thread GC safety via per-thread heaps with deep copy (SRFI-18)
- `--experimental-threads` flag to gate OS threads until cross-thread GC is safe
- Source locations in REPL compile errors
- Sandbox escape test suite (31 tests) proving all gated capabilities are
  blocked under `--sandbox`
- Robustness regression test suite (28 tests) for adversarial/malformed input
- Error format regression tests (11 tests)
- Fuzz targets for reader and bytecode loader
- CI quality gates: formatting check, Debug/ReleaseFast optimize matrix, build
  caching
- Benchmark runner with JSON output, GC metrics, and CI tracking
- Release workflow with cross-compiled binaries for all 4 platforms
- Install script (`install.sh`) for zero-build installation
- Issue and PR templates, `SECURITY.md`, `CODE_OF_CONDUCT.md`
- Known limitations section in README
- Versioning policy (`VERSIONING.md`)

### Fixed

- JIT W^X violation on Linux: pages were mapped RWX, now properly use
  RW-then-RX via mprotect
- JIT icache flush on Linux aarch64
- x86_64 cross-compilation: integer promotions and mprotect API
- `build.zig` comment incorrectly claimed fixnum overflow wraps silently
  (it auto-promotes to bignum)

### Changed

- `thread-start!` now requires `--experimental-threads` flag (was silently
  unsafe)
- Applied `zig fmt` to all 22 source files that had drifted
- Consolidated CI into single workflow
