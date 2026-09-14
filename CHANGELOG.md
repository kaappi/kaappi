# Changelog

All notable changes to Kaappi are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

Each version's section is written at release time from the commit history
since the previous tag (`/github-release` Step 2). Pull requests do not edit
this file — put the *why* in the commit body instead.

Only the current minor series is kept here. When a new minor series opens,
the previous one moves to `changelog/<major>.<minor>.md` (`/github-release`
Step 3), so this file stays small enough to read and to render. Earlier
series: [0.26.x](changelog/0.26.md), [0.25.x](changelog/0.25.md),
[0.24.x](changelog/0.24.md), [0.23.x](changelog/0.23.md),
[0.22.x](changelog/0.22.md), [0.21.x](changelog/0.21.md),
[0.20.x](changelog/0.20.md), [0.19.x](changelog/0.19.md),
[0.18.x](changelog/0.18.md), [0.17.x](changelog/0.17.md),
[0.16.x](changelog/0.16.md), [0.15.x](changelog/0.15.md),
[0.14.x](changelog/0.14.md), [0.13.x](changelog/0.13.md),
[0.12.x](changelog/0.12.md), [0.11.x](changelog/0.11.md),
[0.10.x](changelog/0.10.md), [0.9.x](changelog/0.9.md),
[0.8.x](changelog/0.8.md), [0.7.x](changelog/0.7.md),
[0.6.x](changelog/0.6.md), [0.5.x](changelog/0.5.md),
[0.4.x](changelog/0.4.md), [0.3.x](changelog/0.3.md),
[0.2.x](changelog/0.2.md), [0.1.x](changelog/0.1.md).

## [Unreleased]

## [0.27.1] - 2026-09-10

### Fixed

- **REPL: `esc` is a sticky Meta prefix, so the structural-editing keys work
  on every terminal (#2562, #2566)** — the four keys from 0.26.0 (slurp,
  barf, raise, rotate) were bound as `ESC <char>`, which needs the terminal
  to send Option/Alt as Meta. No default macOS terminal does — Terminal.app,
  iTerm2, kitty, Alacritty and Ghostty all insert the composed glyph — so on
  the primary dev platform the documented keys never ran, and the natural
  readline habit (press Escape, then the letter) cleared the whole form
  instead. `esc` followed by any key is now that key with Alt, with no
  timeout, as in readline, zsh and Emacs; a real escape sequence still
  decodes immediately from its burst. The one deliberate cost: a lone `esc`
  no longer clears the input (`ctrl-u` and `ctrl-c` still do).
- **REPL on the Windows console: `alt-shift-S`/`B`/`R` fire (#2565)** — the
  console delivered Alt+Shift+letter with a SHIFT modifier bit the editor's
  bindings never carry, so the three shifted structural-editing keys were
  silently dropped while `alt-y` rotate worked. The Windows key path now
  drops the redundant SHIFT bit, matching what a POSIX tty sends.
- **SRFI 231: the c64/c128 storage-class checkers accept a bare real flonum
  again (#2559)** — 0.27.0 (#2543) rejected `1.0` so Kaappi's verdict would
  match Gambit's, but the two disagree only because Gambit's `(imag-part
  1.0)` is an exact `0` and ours is `0.0`; R7RS-small §6.2.6 leaves that
  exactness open, and the SRFI's author confirmed the exact-0 rule is R6RS's,
  not R7RS's. The restriction cost a legal program the ability to copy real
  data into a complex array. `(array-copy a c64-storage-class)` over real
  flonums works, and the element really goes through the f32 body
  (`0.1` → `0.10000000149011612+0.0i`; unchanged in c128).

### Changed

- **REPL help names the structural-editing keys as `esc shift-S`, `esc y`,
  … (#2563, #2570)** — `,help` and the F1 key list called them `alt-shift-S`,
  which on macOS is Option and inserts a stray glyph unless the terminal is
  configured to send it as Meta. Both surfaces now spell the `esc`-prefix
  form and state the rule once, next to the table.
- **SRFI 231's bundled implementation is called what the SRFI calls it
  (#2558)** — "sample implementation", not "reference implementation", across
  the library comments, the dev notes and the differential tester. The
  "when prose and code disagree, trust the code" rule those notes attributed
  to the SRFI was ours, not the document's; it is now recorded as a working
  heuristic, with the prose governing unless there is positive reason to
  think it is in error. The tester draws the c64/c128 classes only when
  `--classes` names them, since Kaappi and Gambit now diverge there
  permanently.

## [0.27.0] - 2026-09-08

### Added

- **SRFI 277: cyclic ports (#2545)** — `open-cyclic-input-string` and
  `open-cyclic-input-bytevector` return ordinary input ports whose stream
  repeats forever: `(open-cyclic-input-bytevector #u8(1 2 3))` delivers
  `1 2 3 1 2 3 …` and never an EOF object. The SRFI exists to close SRFI
  271's one gap — a reproducible random-port seed that does not require a
  caller hand-building a 32-byte bytevector — so
  `(make-random-port (open-cyclic-input-bytevector #u8(1 2 3)))` now works,
  and two ports from `equal?` cyclic seeds yield identical streams. A
  portable `/dev/zero` is `(open-cyclic-input-bytevector #u8(0))`. SRFI 192
  positioning comes free: `port-position` stays monotonic across wraps. The
  port reads its own snapshot of the source, so Kaappi defines the SRFI's
  undefined "source modified after the call" case — mutations never affect
  the port. SRFI count 180 → 181 (165 portable).
- **SRFI 4's homogeneous-vector literal syntax (#2548)** — the reader
  accepts all eleven `#TAG(` prefixes the SRFI specifies an external
  representation for — `#s8(…)`, `#u16(…)`, `#f64(…)` and the rest, plus
  SRFI 160's `#c64(…)`/`#c128(…)`. Only `#u8(` (the R7RS bytevector form)
  was accepted before; every other prefix was a read error, so a conforming
  program failed before it ran. Literals are self-evaluating in code
  position, take full number syntax (`#u8(0 #e1e2 #xff)` reads, on the
  bytevector path too), and are immutable like `#u8(` and `#(…)` literals.
  `write` emits the readable form for every kind, with f32/c64 elements
  formatted at f32 precision so the shortest decimal round-trips
  bit-exactly. The `.sbc` codec carries the new tag, so a program using
  literals caches and bundles instead of taking a permanent cache miss;
  `kaappi fmt`, the REPL structural editor and the highlighter all learned
  the new opens.

### Fixed

- **SRFI 231's accumulating non-`!` procedures are call/cc safe (#2539)** —
  the spec defines a call/cc-safe procedure as one "written in a way that
  does not modify the state of any data captured by a continuation", and
  intends every procedure without a trailing `!` to be one. `array-copy`
  collected a non-specialized source's values into a shared mutable scratch
  vector, so a *second* continuation re-entry — or a second continuation
  captured during the first pass — resumed over positions an earlier
  re-entry had already overwritten and materialized the wrong prefix. Brad
  Lucier, the SRFI's author, reported it with a two-continuation,
  two-re-entry case. `array-stack`/`append`/`block`/`decurry` all delegate
  to `array-copy`, so one loop accounted for five procedures; the older
  `set!`-cell accumulators in `interval-fold-left`/`right`,
  `array-fold-left`/`right`, `array-reduce`, `array-every` and
  `array->list` had the same defect, the `fold-left` pair escaping notice
  only because Kaappi's left-to-right argument evaluation happened to
  snapshot the accumulator. Every accumulating procedure is now built on
  the reference implementation's shape: one lexicographic walk threading
  the accumulator through its loop variables and return values, never a
  cell. The official conformance suite passed all 10,936 of its evaluations
  against the broken code — a single re-entry cannot distinguish a shared
  buffer from a functional accumulator.
- **The c64/c128 storage-class checkers reject bare real flonums (#2542)** —
  copying real-flonum data into a `c64`/`c128` array succeeded on Kaappi and
  errored on the reference implementation. Kaappi's checker was the
  reference's line verbatim, but the verdicts diverged on every real flonum
  because Gambit's `(imag-part 1.0)` is an exact `0` while Kaappi's is `0.0`
  (R7RS 6.2.6 requires only `zero?`, not exactness). The checker now encodes
  the reference's verdict independently of the host's `imag-part`
  convention; `1.0+0.0i` is still accepted. Found by differential testing
  against Gambit 4.9.8.
- **Completed unjoined threads free their resources at process exit
  (#2537)** — a thread that finishes but is never joined must keep its
  result envelope until a `thread-join!` copies it out, so its registry
  entry holds the child's GC and VM. At process exit that join can never
  happen, yet the entry survived: a Debug build's leak-tracking allocator
  reported every object in those heaps, 29,366 entries symbolized through
  DWARF, exhausting a CI leg's entire time budget. The exit path now sweeps
  the registry in its no-live-children branch; the live-children fast path
  is untouched, and an entry whose thread has not exited is skipped rather
  than freed.
- **`set!` on an immutable homogeneous-vector literal raises (#2548)** — it
  silently mutated shared constant storage before, unlike `set-car!` and
  `bytevector-u8-set!` on their literals.
- **REPL: barfing a one-element list inserts the gap it documents
  (#2554)** — `(a)` barfs to `() a`, paredit's convention, not `()a`. A
  cursor after the barfed datum rides past the inserted gap. The REPL
  structural-editing tests added in #2221 had never been compiled into the
  unit suite, so this drift shipped with no CI signal.
