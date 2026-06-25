# Changelog

All notable changes to Kaappi are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
