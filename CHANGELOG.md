# Changelog

All notable changes to Kaappi are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
