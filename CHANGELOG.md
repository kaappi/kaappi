# Changelog

All notable changes to Kaappi are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
