# R7RS Conformance

Kaappi implements every identifier from [R7RS Appendix A](https://small.r7rs.org/) — 554 built-in procedures, 32 syntax forms, and all 14 standard libraries. R7RS test suite: 1,394 pass, 0 fail.

---

## Design choices

These are intentional architectural decisions, not missing features. Each is the standard approach taken by most Scheme bytecode interpreters.

### Stack-copying continuations

`call/cc` captures a continuation by copying the entire VM state — registers, call frames, exception handlers, and dynamic-wind stack — into a heap-allocated `Continuation` object. When invoked, the saved state is restored and execution resumes from the capture point.

This is correct and fully re-entrant (multi-shot continuations work). The cost is O(stack depth) per capture — a deep call stack means more data to copy. For most programs this is negligible. Only programs that capture continuations in tight inner loops would notice.

The alternatives are CPS transform (zero capture cost but all code runs slower) and segmented/heap-allocated stacks (fast capture but every call pays allocation cost). Stack copying is the simplest to implement correctly and is the same approach used by Guile and Chibi.

### Continuation scope

A continuation captured in one top-level REPL expression cannot re-enter subsequent top-level expressions. This is standard behavior shared by Guile, Chibi, Chicken, Chez, and Racket — it's how REPLs fundamentally work with continuations, not a Kaappi-specific limitation.

Within a single expression (or a file), continuations work fully.

### No `syntax-case`

Only `syntax-rules` is supported for macro definitions. R7RS-small deliberately standardizes `syntax-rules` and not `syntax-case` — the latter is part of R6RS and some implementations (Chez, Racket) but was intentionally excluded from R7RS-small.

---

## SRFI conformance

51 SRFIs supported. 8 built-in (native Zig), 43 portable (.sld files). Coverage details for the built-in SRFIs follow.

### SRFI 1 — List Library

**Coverage: ~98%** (71 of ~72 spec procedures)

Implemented: `cons*`, `xcons`, `list-tabulate`, `circular-list`, `iota`, `proper-list?`, `dotted-list?`, `circular-list?`, `not-pair?`, `null-list?`, `list=`, `first`–`tenth`, `car+cdr`, `take`, `drop`, `take-right`, `drop-right`, `take-while`, `drop-while`, `split-at`, `last`, `last-pair`, `zip`, `unzip1`, `unzip2`, `count`, `fold`, `fold-right`, `pair-fold`, `pair-fold-right`, `reduce`, `reduce-right`, `unfold`, `unfold-right`, `map-in-order`, `append-map`, `filter-map`, `pair-for-each`, `filter`, `partition`, `remove`, `find`, `find-tail`, `any`, `every`, `list-index`, `span`, `break`, `delete`, `delete-duplicates`, `alist-cons`, `alist-copy`, `alist-delete`, `lset=`, `lset-adjoin`, `lset-union`, `lset-intersection`, `lset-difference`, `lset-xor`, `append-reverse`, `length+`, `concatenate`.

**Not implemented:**
- `unzip3`–`unzip5` — rarely used
- Linear-update (`!`) variants — SRFI 1 permits non-mutating implementations
- `lset-diff+intersection` — composite operation; use `lset-difference` + `lset-intersection`

### SRFI 9 — Records

**Coverage: 100%.** `define-record-type` is implemented as R7RS compiler syntax.

### SRFI 13 — String Library

**Coverage: ~90%** (30 of ~33 core spec procedures)

Implemented: `string-contains`, `string-prefix?`, `string-suffix?`, `string-trim`, `string-trim-right`, `string-trim-both` (with predicate or SRFI-14 char-set argument, UTF-8 safe), `string-index`, `string-index-right`, `string-skip`, `string-skip-right`, `string-count`, `string-split`, `string-join`, `string-concatenate`, `string-take`, `string-drop`, `string-take-right`, `string-drop-right`, `string-pad`, `string-pad-right`, `string-reverse`, `string-filter`, `string-delete`, `string-replace`, `string-titlecase`, `string-every`, `string-any`, `string-tabulate`, `string-unfold`, `string-unfold-right`.

All predicate-accepting procedures accept SRFI-14 char-set objects directly in addition to predicate procedures. Optional `start`/`end` index parameters are supported on all searching, filtering, and transformation functions.

**Not implemented:**
- `string-xcopy!` — mutation variant

### SRFI 27 — Random Numbers

**Coverage: 100%** (12 of 12 spec procedures). Full state save/restore via `random-source-state-ref`/`state-set!` (all 4 xoshiro256 state words).

### SRFI 39 — Parameter Objects

**Coverage: 100%.** `make-parameter` (with optional converter) is exported; `parameterize` is compiler syntax.

### SRFI 69 — Hash Tables

**Coverage: ~95%** (21 of ~22 spec procedures). `hash-table-ref` correctly calls default thunk. `hash-table-merge!` overwrites existing keys. `string-ci-hash` uses Unicode case folding.

**Not implemented:**
- `hash-table-equivalence-function`, `hash-table-hash-function` — `make-hash-table` accepts but ignores custom comparator/hash arguments

### SRFI 133 — Vector Library

**Coverage: ~95%** (32 of ~33 spec procedures)

Implemented: All SRFI-133 procedures including `vector-unfold`, `vector-unfold-right`, `vector-binary-search`, `vector-concatenate`, `vector-cumulate`, `vector-partition`, `vector-swap!`, `vector-reverse!`, `vector-reverse-copy`, `vector-skip`, `vector-skip-right`.

**Not implemented:**
- `vector-append-subvectors` — composite append with subranges

### SRFI 170 — POSIX API

**Coverage: ~85%** (68 of ~80+ spec procedures)

Implemented: File info (`file-info`, `file-info?`, `file-info-type`, all `file-info:*` accessors, type predicates), file operations (`create-directory`, `delete-directory`, `rename-file`, `create-symlink`, `read-symlink`, `create-hard-link`, `real-path`, `set-file-mode`, `truncate-file`, `create-fifo`, `set-file-owner`, `set-file-times`), process state (`pid`, `umask`, `set-umask!`, `current-directory`, `set-current-directory!`, `user-uid`, `user-gid`, `user-effective-uid`, `user-effective-gid`, `user-supplementary-gids`, `nice`), environment (`set-environment-variable!`, `delete-environment-variable!`), terminal (`terminal?`), user/group database, directory traversal (`open-directory`, `read-directory`, `close-directory`, `directory-files`), time (`posix-time`, `monotonic-time`), temp files (`temp-file-prefix`, `create-temp-file`).

**Not implemented (by design):**
- Process management (`fork`, `exec*`, `waitpid`, `_exit`) — unsafe in GC'd bytecode VM
- Signal handling — requires async-safe VM interrupt mechanism
- Pipes, I/O multiplexing — not exposed

### SRFI 18 — Multithreading

**Coverage: 100%** (35 of 35 spec procedures). Fiber-based concurrency: `make-thread`, `thread-start!`, `thread-yield!`, `thread-sleep!`, `thread-join!`, `thread-terminate!`, `mutex-lock!`, `mutex-unlock!`, `condition-variable-signal!`, `condition-variable-broadcast!`, time objects.
