# Kaappi — R7RS Scheme in Zig

Complete R7RS-small Scheme implementation. Zig 0.16, ~80k lines, 634 built-in procedures.

## Build

```
zig build                          # build executable (zig-out/bin/kaappi)
zig build run                      # launch REPL (linenoise: arrow keys, history, tab completion)
zig build run -- f.scm             # run a Scheme file
zig build run -- --help            # show CLI usage and flags
zig build run -- --version         # show version string
zig build test                     # run all unit tests
zig build test -Dtest-filter=tests_io  # only tests whose names match (repeatable)
zig build bench                    # call/cc vs call/ec capture micro-benchmark
zig build bench-fibers              # per-fiber switch time, RSS, register/frame footprint (KEP-0001 P7)
zig build bench-reactor             # reactor ONESHOT re-arm, wake-all, timer-granularity costs (KEP-0001 P7)
zig build coverage                 # unit test code coverage (requires kcov)
zig build coverage-scheme -- f.scm # Scheme file code coverage (requires kcov)
zig build -Dbundle-src=program.scm # standalone binary (compile + embed in one step)
zig build -Dbundle=program.sbc     # standalone binary from pre-compiled .sbc
zig build -Dmax-frames=1024        # initial frame capacity (default: 480, grows to 32768)
zig build -Dmax-registers=4096     # initial register count (default: 2048, grows to 65536)
zig build -Dgc-threshold=16384     # custom initial GC threshold (default: 8192)
zig build -Dgc-stress=true         # force GC on every allocation (stress testing)
```

CLI flags: `-h`/`--help`, `--version`, `--lib-path <path>`, `--compile`,
`-o <file>`, `--disassemble`, `--no-ir-opt` (disable IR optimization passes;
also skips the `.sbc` cache in both directions — useful for miscompilation
triage and `--disassemble` comparisons; note the cache key now folds in the
git build id, so a rebuilt binary never serves the old binary's bytecode —
the old "delete the cache before testing compiler changes" footgun is fixed,
see `docs/dev/cache.md`), `--sandbox`, `--gc-stats`,
`--profile`, `--timings[=text|json]` (per-stage pipeline wall time —
read/expand/lower/optimize/emit/execute, plus native `llvm-emit`/`link` — and
cache HIT/MISS + path, all on stderr; text or JSON; disjoint self-timed stages,
zero overhead when absent — see `docs/dev/timings.md`),
`--coverage`, `--diagnostics=<text|json>` (JSON Lines of LSP
`Diagnostic` objects on stderr — see `docs/dev/diagnostics-json.md`),
`--deny-warnings` (`check`-only: promote lint warnings to errors),
`--completions <shell>`.
Subcommands: `kaappi compile <file> [-o output]` compiles to a native binary
via LLVM; `kaappi check <file>` runs compile-only static analysis (reads,
expands, compiles, executes nothing) reporting read/compile errors plus the
`KP4xxx` lint findings — unknown top-level variable (warning), and arity or
wrong-type-literal on direct built-in calls (errors); honors
`--diagnostics=json` and `--deny-warnings` — see `docs/dev/check.md`;
`kaappi explain <code>` prints a diagnostic's reference entry;
`kaappi features [--json]` reports this build's capabilities — version + git
build id, target triple, build mode, compiled-in subsystems (the KEP-0004
`cond-expand` identifiers, sharing `types.platform_features`), built-in vs
portable SRFIs, and initial VM/GC limits — all derived, no hardcoded second
list; see `docs/dev/features.md`;
`kaappi test [paths...]` runs SRFI-64 suites (`--json`, `--seed <n>`,
`--lib-path`) aggregating from the runner's own counters; `--changed`
/`--list-affected` (with `--since <rev>`) select only suites whose R7RS import
closure changed, falling back to a loud full run when the graph can't be trusted
— see `docs/dev/test-runner.md`. `kaappi ast|expand|ir <file>` are read-only
pipeline-stage dumps: `ast` prints post-read datums (`read`+`write`), `expand`
prints the program after full macro expansion (round-trips), `ir` prints the IR
tree (`--no-opt` = before the optimization passes); none execute program code —
see `docs/dev/observing-the-pipeline.md`. `kaappi doctor [--json]` runs an
installation/environment self-check (binary, library search path, thottam state,
native backend + smoke link, REPL, FFI) printing `PASS`/`WARN`/`FAIL` per check
with a fix for each failure; exit is nonzero only on `FAIL` — see
`docs/dev/doctor.md`. `kaappi fmt [--check] files...` is the
canonical, comment-preserving formatter (2-space R7RS indentation, single-space
separators, closing parens gathered, reflowed to 80 cols): it rewrites files in
place (or formats stdin to stdout), while `--check` writes nothing and exits
nonzero listing paths that need formatting; every write is guarded by a
real-reader `equal?` round-trip so it can never change a program — see
`docs/dev/fmt.md`. `kaappi cache status|clear` inspects and wipes the central
bytecode cache: `status` prints its location, entry count, total size, and per
entry the size, producing build id (current vs. stale), and source path;
`clear` removes every entry — the supported way to wipe it, so you never need
to know the path. See `docs/dev/cache.md`. Version is defined as
`pub const version` in `main.zig`. Environment: `KAAPPI_LIB_DIR` overrides
`libkaappi_rt.a` lookup; `KAAPPI_HOME` (default `~/.kaappi`) locates the
bytecode cache (`$KAAPPI_HOME/cache`), installed libraries, and REPL history.

Build-time options: `-Dmax-frames=N` (initial frame capacity, default 480, grows to 32768),
`-Dmax-registers=N` (initial register count, default 2048, grows to 65536),
`-Dgc-threshold=N` (initial GC object threshold, default 8192).

Requires Zig 0.16+ and libc (for linenoise terminal handling).

### Git hooks

After cloning, enable the pre-commit format check:

```
git config core.hooksPath .githooks
```

This runs `zig fmt --check` on staged `.zig` files before each commit.

### Supported platforms

| OS | Architecture | Build | Unit Tests | Notes |
|----|-------------|-------|------------|-------|
| macOS | aarch64 (Apple Silicon) | yes | yes | Primary dev platform |
| Linux | x86_64 | yes | yes | CI tested (Ubuntu) |
| Linux | aarch64 | yes | yes | CI tested (Ubuntu ARM) |
| Linux | riscv64 | yes | yes | CI tested (QEMU) |
| Linux | s390x (big-endian) | yes | yes | CI tested (QEMU); the byte-order canary (#1654) |
| Linux | ppc64le | yes | yes | CI tested (QEMU) |
| Windows | aarch64 (ARM64), x86_64 | yes | yes | `zig build -Dtarget=<arch>-windows`; see `docs/dev/windows.md` |
| FreeBSD | x86_64, aarch64 | yes | yes | `zig build -Dtarget=<arch>-freebsd`; kqueue reactor; see `docs/dev/freebsd.md` |
| OpenBSD | x86_64, aarch64 | yes | yes | `zig build -Dtarget=<arch>-openbsd`; kqueue reactor; binaries auto-marked `PT_OPENBSD_NOBTCFI`; see `docs/dev/openbsd.md` |
| NetBSD | x86_64, aarch64 | yes | yes | `zig build -Dtarget=<arch>-netbsd`; kqueue reactor; versioned libc symbols bound explicitly; aarch64 FPCR reset at startup; see `docs/dev/netbsd.md` |
| WebAssembly | wasm32-wasi | yes | — | `zig build wasm`, browser/WASI |

**Cross-compilation:** `zig build -Dtarget=x86_64-linux` and
`zig build -Dtarget=riscv64-linux` cross-compile from macOS ARM. Binaries
run in Linux containers via podman (x86_64 via Rosetta, riscv64 via QEMU).
`zig build -Dtarget=s390x-linux` and `-Dtarget=powerpc64le-linux`
cross-compile the interpreter-tier s390x/ppc64le ports (#1654) — zero
runtime code changes; s390x is the only big-endian target and serves as
the permanent byte-order canary in CI; both were validated end-to-end on
real-kernel Alpine VMs (see `docs/dev/porting.md`).
`zig build -Dtarget=aarch64-windows` (or `x86_64-windows`) cross-compiles
the Windows binaries (kaappi.exe, thottam.exe, kaappi-lsp.exe);
syscall-level platform differences live behind the `src/platform.zig`
facade (Windows ABI/socket/pipe helpers in `src/platform_win*.zig`) —
both arches share the same OS-gated code (see `docs/dev/windows.md` for
the port's architecture, degradations, and how to test on a Windows
machine; x86_64 also builds natively with the stock Zig toolchain, and
x64 binaries run on the ARM64 reference VM via Windows' x64 emulation).
`zig build -Dtarget=aarch64-freebsd` (or `x86_64-freebsd`) cross-compiles
for FreeBSD — a full-POSIX port with no degradations (`docs/dev/freebsd.md`).
`zig build -Dtarget=aarch64-openbsd` (or `x86_64-openbsd`) cross-compiles
for OpenBSD — a kqueue port whose binaries are auto-marked
`PT_OPENBSD_NOBTCFI` (a post-link patch, `tools/openbsd_nobtcfi.zig`, wired
into `build.zig`) to survive BTCFI enforcement, since Zig 0.16 emits no BTI
landing pads (`docs/dev/openbsd.md`).
`zig build -Dtarget=aarch64-netbsd` (or `x86_64-netbsd`) cross-compiles
for NetBSD — a kqueue port that binds NetBSD's versioned libc symbols
explicitly (`__kevent50`, `__opendir30`, `__getpwnam50` — the plain names
are old-ABI compat symbols) and resets the aarch64 FPCR at startup
(NetBSD boots processes in flush-to-zero mode); the native backend needs
pkgsrc clang since base cc is GCC (`docs/dev/netbsd.md`).
Porting to a new OS or CPU architecture: `docs/dev/porting.md` (porting
surfaces, degradation ladder, staged checklists).

Builds default to **ReleaseSafe** (fast, with bounds/safety checks retained;
fixnum overflow auto-promotes to bignum). Debug is ~500x slower for allocation-
and continuation-heavy workloads — only use it when debugging:
`zig build -Doptimize=Debug`. For maximum throughput: `-Doptimize=ReleaseFast`.

### LLVM native backend

```bash
kaappi compile program.scm -o program            # recommended single command
./program                                        # run native binary

zig build native -Dnative-src=program.scm        # via build system
./zig-out/bin/program

# Or manual three-step:
zig build lib                                    # build libkaappi_rt.a
zig build run -- --emit-llvm -o out.ll program.scm  # emit LLVM IR
zig cc -w out.ll -o program -Lzig-out/lib -lkaappi_rt -lc -lm -lpthread  # link
```

`kaappi compile` locates `libkaappi_rt.a` via `KAAPPI_LIB_DIR` env var,
`<exe_dir>/../lib/`, `zig-out/lib/`, or `/usr/local/lib/`. It searches
PATH for a C compiler (zig cc, cc, clang, gcc).

**Features compiled natively:** arithmetic, comparisons, if/and/or/when/unless,
let/let*, lambda (with closures and variadic parameters), self-tail-call
optimization (compiled as loops), tail calls to other native functions.
Forms not yet compiled natively (letrec, named-let, do, etc.) fall back to
`kaappi_eval` at runtime.

**Always use `zig cc` (not `clang`) for linking native binaries against
`libkaappi_rt.a`.** The Zig-compiled static library references
`__zig_probe_stack` and other Zig compiler-rt intrinsics that `clang`
cannot resolve. `zig cc` includes these automatically.

## Architecture

```
Source → Reader → Expander → IR → Analysis → Optimization → Bytecode Emission → VM
         (UTF-8    (syntax-    (33 node  (tail pos,    (const fold,     (register-   (generational
          lexer)    rules)      types)    primitives,   dead branch,      based)       GC)
                                          constants)    boolean, etc.)
```

### Pipeline stages

| Stage | File | Role |
|-------|------|------|
| Reader | `reader.zig` (+ `reader_tokens.zig`, `reader_datum.zig`) | Tokenizer + recursive descent parser. Handles R7RS lexical syntax including Unicode identifiers and `#\λ` character literals. |
| Expander | `expander.zig` | `syntax-rules` pattern matching and template instantiation. Called by the compiler when a macro keyword is encountered. |
| IR | `ir.zig` | Lowers S-expressions to tree-structured IR (33 node types). Runs 3 analysis passes (tail positions, primitive identification, constant detection) and 5 optimization passes (constant folding, dead branch elimination, boolean simplification, identity elimination, begin simplification). See `docs/dev/ir.md`. |
| Compiler | `compiler.zig` | IR nodes → register-based bytecode via `compileFromNode()`. Retains `compileExpr()` for forms delegated via `passthrough`. Dispatches derived forms to sub-modules. |
| VM | `vm.zig` | Executes bytecode. Growable register file + call frame stack (heap-allocated, double-on-overflow). Handles continuations (stack-copying), exception handler stack, dynamic-wind stack, stepping debugger. |
| GC | `memory.zig` | Generational collector (young/old) with minor and full collections, write barrier for old→young references. Roots tracked via `gc.pushRoot`/`gc.popRoot`. Triggered after N allocations. |

### Value representation

NaN-boxed u64 — flonums, fixnums, booleans, characters, and nil all fit in a
single word with zero heap allocation:
- **Any non-NaN f64**: flonum (stored directly, no heap allocation)
- **0xFFFC | 48-bit pointer**: heap `Object` (8-byte aligned)
- **0xFFFD | 48-bit integer**: fixnum (signed, up to ±2^47; auto-promotes to bignum)
- **0xFFFE | payload**: immediate (nil, true, false, void, eof, char with 21-bit codepoint)

Heap objects share an `Object` header with `ObjectTag` (u6, 64 slots), GC mark bit, generation (u1), and survive count (u2). 36 types: Pair, Symbol, SchemeString, Closure, Function, NativeFn, Vector, Bytevector, Port, Flonum, Complex, Transformer, ErrorObject, RecordType, RecordInstance, Continuation, MultipleValues, Promise, ParameterObject, Rational, Bignum, FfiLibrary, FfiFunction, HashTable, FileInfo, UserInfo, GroupInfo, DirectoryObject, RandomSource, FfiCallback, Fiber, Channel, Mutex, ConditionVariable, Srfi18Time.

### Strings

Stored as UTF-8 byte arrays. All string operations (string-length, string-ref, substring, etc.) index by **codepoint position**, not byte offset. Mutation via string-set! rebuilds the string when byte widths change.

## File size policy

Keep source files under **1500 lines**. When a file grows past that, split it
along natural seams (arch-specific code, dispatch vs helpers, call infrastructure
vs struct definition). Do NOT split flat lists of independent functions (e.g.
primitives files) — size from breadth is fine; size from tangled coupling is not.

Exceptions: auto-generated data files (`unicode_tables.zig`) are exempt.

## File organization

### Core runtime
| File | Lines | Responsibility |
|------|-------|---------------|
| `types.zig` | ~500 | Value type, heap object structs, ObjectTag enum, opcodes |
| `memory.zig` | ~1200 | GC struct, heap type allocators, write barrier, rooting |
| `gc_collect.zig` | — | GC mark/sweep/free (delegated from memory.zig) |
| `gc_deep_copy.zig` | — | Cross-thread deep copy (delegated from memory.zig) |
| `reader.zig` | ~700 | Tokenizer, S-expression parser, Unicode lexing |
| `expander.zig` | ~320 | Macro expansion engine (syntax-rules) |
| `printer.zig` | ~300 | Value → string (write mode and display mode) |

### Compiler & IR (9 files)
| File | Responsibility |
|------|---------------|
| `ir.zig` | IR node types (33), AST→IR lowering, 3 analysis passes, 5 optimization passes |
| `ir_emitter.zig` | Standalone IR → bytecode emitter (used by Stage 1 parity tests) |
| `compiler.zig` | Core: IR pipeline orchestration (`compile()` lowers to IR, runs passes), retains `compileExpr()` for passthrough forms, scope/register management, macro forms |
| `compiler_ir.zig` | IR-to-bytecode: `compileFromNode()` dispatch, if, begin, call, lambda, define, set!, and, or, when, unless |
| `compiler_lambda.zig` | lambda, define, set!, begin, delay, delay-force, body compilation |
| `compiler_conditionals.zig` | and, or, when, unless, cond, cond-expand |
| `compiler_bindings.zig` | let, let*, letrec, letrec*, named let, do, let-values, let*-values |
| `compiler_advanced.zig` | case, case-lambda, guard, quasiquote |
| `compiler_macro.zig` | define-syntax, let-syntax, letrec-syntax, macro expansion, syntax-rules parsing, hygiene free-ref collection |
| `compiler_forms.zig` | Re-export hub (thin file, don't edit directly) |

### VM (split into 8 files)
| File | Responsibility |
|------|---------------|
| `vm.zig` | VM struct, init/deinit, error handling, delegation wrappers |
| `vm_dispatch.zig` | runUntil bytecode dispatch loop, opcode handlers, bytecode readers |
| `vm_calls.zig` | execute, run, callValue, callClosure, callNative, profile helpers |
| `vm_eval.zig` | eval, handleTopLevelForm dispatcher |
| `vm_library.zig` | handleImport (with only/except/rename/prefix), handleDefineLibrary, .sld file loading |
| `vm_records.zig` | handleDefineRecordType desugaring |
| `vm_continuations.zig` | captureContinuation, restoreContinuation, performWindTransition, callWithCC |
| `vm_debug.zig` | Stepping debugger: breakpoints (with conditions), watch expressions, step/next/step-out/continue, up/down frame navigation, locals, backtrace |

### Primitives (split into 21 files)
| File | Procedures |
|------|-----------|
| `primitives.zig` | Registration hub, core list/pair ops, type predicates, equivalence, map, for-each, apply |
| `primitives_arithmetic.zig` | +, -, *, /, comparisons, trig, exp/log, gcd/lcm, complex |
| `primitives_numeric.zig` | rounding, exactness predicates, exact/inexact conversion |
| `primitives_string.zig` | string ops, char comparisons, number↔string, UTF-8 codepoint indexing |
| `primitives_string_ext.zig` | SRFI-13 string library (contains, prefix?, trim, split, join) |
| `primitives_char.zig` | (scheme char): Unicode classification, case conversion, CI comparisons |
| `primitives_vector.zig` | vector ops, vector-map, vector-for-each |
| `primitives_bytevector.zig` | bytevector ops, binary I/O, bytevector ports |
| `primitives_list.zig` | list-ref, list-tail, list-set!, list-copy, make-list, member, assoc |
| `primitives_srfi1.zig` | SRFI-1 list library (fold, filter, find, any, every, iota, lset-intersection, lset-difference, lset=) |
| `primitives_hashtable.zig` | SRFI-69 hash tables |
| `primitives_random.zig` | SRFI-27 random numbers |
| `primitives_io.zig` | Port ops, file I/O, string ports, read/write/display |
| `primitives_filesystem.zig` | SRFI-170: file-info (full stat), directory ops, symlinks, process state, user/group info, env vars, terminal? |
| `primitives_control.zig` | raise, guard, with-exception-handler, call/cc, dynamic-wind, values |
| `primitives_lazy.zig` | delay, force, make-promise, promise? |
| `primitives_cxr.zig` | 24 car/cdr compositions (caaaar–cddddr) |
| `primitives_ffi.zig` | C FFI: ffi-open, ffi-fn, ffi-close, ffi-callback. 18 types: int, long, double, float, string, pointer, void, bool, uint8, int8, int16, int32, int64, uint16, uint32, uint64, size_t, char. |
| `primitives_r7rs.zig` | time, process-context, eval, load, make-parameter |
| `primitives_srfi18.zig` | SRFI-18: threads, mutexes, condition variables, time objects |

### Other
| File | Responsibility |
|------|---------------|
| `library.zig` | Library registry, standard library registration ((scheme base), etc.) |
| `bignum.zig` | Arbitrary-precision integer arithmetic |
| `ffi.zig` | C FFI call dispatcher (type marshaling, arity routing, `normalizeType` for extended integer types) |
| `bytecode_file.zig` | `.sbc` codec hub: shared format contract (magic, version, tags, limits), `BytecodeError`, `compilerHash`/`sourceHash`/`getSbcPath`, re-exports of the read/write halves |
| `bytecode_file_write.zig` | Serializer: `Writer`, `writeConstant`, function collection, `writeFileWithTopLevel`/`writeFileWithBundle` |
| `bytecode_file_read.zig` | Deserializer: `Reader`, `readConstant`, bytecode validation, `deserializeFromBuffer`, `readHeaderInfo`, `DeserializeResult`/`HeaderInfo` |
| `disassembler.zig` | Bytecode disassembler for `(disassemble proc)` |
| `linenoise.zig` | Zig FFI wrapper for vendored linenoise C library |
| `main.zig` | Entry point, REPL loop with linenoise, file execution, CLI flags, `pub const version`, `pub const panic` |
| `crash.zig` | Custom panic handler (`PanicHandler(name)`) + pipeline breadcrumb (`noteStage`/`noteFile`); prints version/target/build-mode + stage + report URL before the trace. See `docs/dev/crash-reporting.md` |
| `native_compiler.zig` | LLVM IR emission, native binary compilation, C compiler discovery, linker invocation |
| `thottam.zig` | Package manager binary (thottam): install, remove, list, update, verify |
| `llvm_emit.zig` | LLVM IR text emitter (walks IR nodes, produces `.ll` files) |
| `runtime_exports.zig` | C-ABI bridge for LLVM native backend (21 exported functions) |
| `fmt.zig` | `kaappi fmt`: comment-preserving CST reader (lexer + parser), CLI entry, real-reader `equal?` round-trip safety net |
| `fmt_print.zig` | `kaappi fmt` layout engine: fits-or-breaks pretty-printer, special-form indentation rules |
| `testing_helpers.zig` | Shared `makeTestVM` helper for unit tests |
| `tests_ir.zig` | IR tests: bytecode parity, behavioral correctness, analysis, optimizations |
| `tests_*.zig` | Unit tests by feature (core_eval, tail_calls, macros, io, etc.) |

### SRFI libraries (in `lib/srfi/`)
78 SRFIs supported. 9 built-in (Zig primitives): 1, 9, 13, 18, 39, 69, 133, 170, 254. 68 portable R7RS .sld files loaded on demand via `(import (srfi N))`: 0, 2, 4, 6, 8, 11, 14, 16, 17, 19, 23, 26, 27, 28, 31, 34, 35, 36, 37, 38, 41, 42, 43, 45, 48, 60, 61, 64, 78, 87, 98, 111, 113, 115, 116, 117, 125, 127, 128, 130, 132, 134, 141, 143, 144, 145, 146, 151, 152, 158, 166, 174, 175, 189, 195, 196, 197, 210, 219, 222, 227, 232, 233, 235, 250, 263, 267, 271. Sub-libraries: (srfi 146 hash), (srfi 166 pretty), (srfi 166 columnar), (srfi 166 unicode), (srfi 166 color), (srfi 254 ephemerons), (srfi 254 guardians), (srfi 254 transport-cell-guardians), (srfi 254 ephemerons-and-guardians), (srfi 263 syntax), (srfi 271 randomized), (srfi 271 determinized). SRFI-254 (ephemerons and guardians) needs GC integration — its weak-reference marking/resurrection lives in `gc_collect.processWeakRefs`, its heap types (`Ephemeron`, `Guardian`, `TransportCell`) in `types.zig`, its primitives in `primitives_srfi254.zig`, and guardian invocation (a guardian is callable) in `vm_calls.invokeGuardian`. On this non-moving collector `current-hash` is a stable identity hash and transport cell guardians are degenerate (keys never move, so `(tg)` always yields #f). SRFI 267 (raw string syntax) is a hybrid: its `#"X"…"X"` lexical syntax is built into the reader (`readRawString` in `reader_tokens.zig`), while its port procedures load from the `.sld`. SRFI 261 (portable SRFI library references) is a resolver-level convention with no library file: `(srfi srfi-<n>)` and `(srfi <mnemonic>-<n>)` (e.g. `(srfi lists-1)`, `(srfi vectors-133)`) resolve to `(srfi <n>)` as a fallback — literal registry/file names win, sub-library tails pass through, and the trailing number alone is authoritative (mnemonics are not validated). Implemented in `vm_library.zig` (`srfi261FormNumber`/`normalizeSrfiLibName` in `processImportSet`; `libraryIsAvailableSrfi261` behind both cond-expand `(library …)` entry points) and mirrored path-level in `test_selection.zig` so `kaappi test --changed` keeps the dep edge. Every supported SRFI is also a `cond-expand` feature identifier `srfi-<n>` (#1649): `(cond-expand (srfi-1 …) …)`. These are derived, never listed — `srfiFeatureAvailable` in `vm_library.zig` routes `srfi-<n>` through the same availability check as `(library (srfi <n>))`, so built-in, portable, `--sandbox` and WASM answers all match what `(import (srfi <n>))` would do. Both feature-req evaluators consult it: `evalLibFeatureReq` (inside `define-library`) directly, and the compiler's `evalFeatureReq` via the `globals.srfiFeatureAvailable` callback the VM registers (mirroring the `library_exists_checker` used by the `(library …)` form). SRFI 261 is the one supported SRFI with no `.sld`, so `srfi-261` answers true directly. Like `(library …)` requirements, `srfi-<n>` is a derived probe, not a bare feature, so `(features)` (and the `kaappi features` table it must equal, #1517) stays platform-only; `kaappi features` still notes the ids in its SRFIs section.

The library loader in `vm_library.zig` supports `cond-expand`, `include` (paths resolved relative to the .sld file), and `(export (rename ...))` in `define-library`. Macro transformers defined with `define-syntax` in library `begin` blocks are exported and imported correctly.

## Zig 0.16 patterns

These differ from earlier Zig versions and are easy to get wrong:

```zig
// ArrayList is UNMANAGED — pass allocator to every method
var list: std.ArrayList(u8) = .empty;           // NOT .{} or .init(alloc)
list.append(allocator, item) catch {};
list.deinit(allocator);

// No std.io — use std.Io.Writer or raw syscalls
var buf: [256]u8 = undefined;
var w: std.Io.Writer = .fixed(&buf);
w.print("{d}", .{42}) catch {};
const result = w.buffered();

// stdout/stderr via POSIX syscalls
std.posix.system.write(1, bytes.ptr, bytes.len);  // stdout
std.posix.system.write(2, bytes.ptr, bytes.len);  // stderr

// main() takes Init.Minimal for args
pub fn main(init: std.process.Init.Minimal) !void { ... }

// Allocator
var da = std.heap.DebugAllocator(.{}).init;
const allocator = da.allocator();

// StringHashMap is still managed (stores allocator internally)
var map = std.StringHashMap(Value).init(allocator);
map.deinit();  // no allocator arg needed
```

## How to add a new built-in procedure

1. Write the function in the appropriate `src/primitives_*.zig` file:
   ```zig
   fn myProc(args: []const Value) PrimitiveError!Value {
       if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
       return types.makeFixnum(types.toFixnum(args[0]) + 1);
   }
   ```

2. Register in the file's `registerXxx` function:
   ```zig
   try primitives.reg(vm, "my-proc", &myProc, .{ .exact = 1 });
   ```
   Arity: `.{ .exact = N }` for fixed, `.{ .variadic = N }` for N minimum args.

3. Add to library exports in `src/library.zig` (the `scheme.base` section).

4. If the procedure needs heap allocation, use `primitives.gc_instance`.
   If it needs to call Scheme procedures, use `primitives.vm_instance`.

## How to add a new compiler form

See `.claude/rules/compiler-forms.md` (loaded automatically when editing
compiler or IR files). Covers: IR node type, dispatch, implementation,
re-export, IR tests, and tail position handling.

## How to add a new heap type

1. Add tag to `ObjectTag` enum in `src/types.zig` (slots 35+ available, enum is u6 with 64 slots).
2. Add the struct with `header: Object` as the first-declared field
   (convention only — Zig's auto layout may still place it at a nonzero
   byte offset, and that's fine). Heap Values always carry the address of
   the `header` field: build them with `makePointer(&x.header)` — the
   `*Object` parameter type makes passing the struct pointer a compile
   error — and recover the struct with `Object.as()`/`@fieldParentPtr`,
   never a direct cast.
3. Add `allocXxx` in `src/memory.zig`.
4. Handle in `markValue` (trace contained Values) and `freeObject` (free owned memory).
5. Add display in `src/printer.zig`.

## GC safety

See `.claude/rules/gc-safety.md` (loaded automatically when editing primitives,
memory, or VM files). Key rules: root before allocating, write barrier after
mutating heap object fields, root `Function*` before `vm.execute()`.

## Tests

**Every bug fix MUST include a regression test** that fails without the fix and
passes with it. Place it in the appropriate location:
- Zig unit test → `src/tests_*.zig` (for VM, compiler, GC internals)
- Scheme test → `tests/scheme/smoke/` or a dedicated file under `tests/scheme/`
  (for end-to-end behavior visible from Scheme)

The unit suite must also stay green under `zig build test -Dgc-stress=true`
(collection on every allocation — #1401). Tests that hold heap values in Zig
locals across allocations must root them; loop-heavy tests that allocate per
iteration should scale their counts down via
`@import("build_options").gc_stress` (see `docs/dev/testing.md`).

- **Unit tests**: `src/tests_*.zig` — named by feature: `tests_core_eval.zig`, `tests_macros.zig`, `tests_io.zig`, etc. Run all with `zig build test`.
- **R7RS test suite**: `tests/scheme/r7rs/r7rs-tests.scm` — 1,391 tests using `(chibi test)`. Run with `zig build run -- tests/scheme/r7rs/r7rs-tests.scm`.
- **Scheme tests**: `tests/scheme/` organized by purpose:
  - `smoke/` — quick sanity checks (basic, tail-calls, derived, numeric, macros, libraries)
  - `compliance/` — targeted R7RS conformance tests by topic (strings, vectors, chars, unicode, etc.)
  - `continuations/` — advanced call/cc and call/ec edge cases
  - `hygiene/` — macro hygiene edge cases
  - `srfi/` — SRFI conformance tests
  - `ffi/` — C FFI integration tests
  - `audit/` — primitives audit tests (arithmetic, numeric, string)
  - `errors/` — error message format and exit code regression tests (`error-format.sh`, `exit-code.sh`)
  - `bench/` — raw micro-benchmarks (no assertions; used by `benchmarks/run-benchmarks.sh`, not `run-all.sh`)
  - `coverage/` — coverage gap-filler tests (used by `zig build coverage-scheme`, not `run-all.sh`)
- **Run all**: `bash tests/scheme/run-all.sh`

## Code coverage

Uses [kcov](https://simonkagstrom.github.io/kcov/) to track which Zig source lines execute during tests. Install with `brew install kcov`. Both steps build in Debug mode (regardless of `-Doptimize`) since kcov needs DWARF line info.

```
zig build coverage                                        # unit tests only
zig build coverage-scheme -- tests/scheme/r7rs/r7rs-tests.scm  # R7RS test suite
open coverage/index.html                                  # view HTML report
```

Coverage accumulates across runs — kcov merges results from the unit test binary (`coverage-tests`) and the Scheme runner (`kaappi-cov`) into a single report. The `coverage` step cleans previous unit test data on each run; `coverage-scheme` accumulates so you can run multiple `.scm` files. Delete `coverage/` to start fresh.

Only files under `src/` are included in the report (standard library and vendored code are excluded).

## Dependencies

- **linenoise** (vendored in `vendor/linenoise/`): BSD-licensed C library for REPL line editing, history, tab completion. Compiled as part of the Zig build.

## Documentation

**End-user docs** (guide, procedures, libraries, benchmarks) live in the
[kaappi/kaappi.github.io](https://github.com/kaappi/kaappi.github.io) repo
and are served at **https://kaappi-lang.org/**. Built with MkDocs Material.
That repo is exclusively for end-user documentation — no dev docs there.

**Developer/contributor docs** (architecture, testing, adding-features,
postmortems) live in `docs/dev/` in this repo. This is the single source
of truth for contributor documentation.

## Package manager (thottam)

`src/thottam.zig` is a Zig binary that installs Kaappi ecosystem libraries.
Built alongside kaappi via `zig build`, ships in release artifacts for all platforms.

```
thottam install kaappi-web                                    # from default org
thottam install kaappi-auth::https://github.com/bob/kaappi-auth  # from custom URL
thottam install kaappi-web@v1.0.0                             # pinned version
thottam install kaappi-net@">=0.2.0"                          # semver constraint
thottam list                                                  # show installed packages
thottam update                                                # pull + rebuild all
thottam remove kaappi-web                                     # uninstall
```

**How it works:**
- Clones from `github.com/kaappi/<package>` (or a custom `::url`) to `~/.kaappi/src/`
- Reads `kaappi.pkg` for dependencies and build commands
- Copies `.sld` files to `~/.kaappi/lib/` (preserving directory structure)
- Copies `.dylib`/`.so` to `~/.kaappi/lib/`

**Auto-discovery:** `main.zig` automatically adds the script's own directory
and `~/.kaappi/lib` to the library search path (after any `--lib-path`
entries), so a program can import libraries that live next to it regardless
of the working directory. `ffi-open` also searches `~/.kaappi/lib/` for
native libraries. No `--lib-path` or `DYLD_LIBRARY_PATH` needed after
install.

**Package manifest** (`kaappi.pkg`):
```
name: kaappi-web
depends: kaappi-http kaappi-json
build: make
source: https://github.com/kaappi/kaappi-web
```

All fields except `name` are optional. The `source` field declares where
this package is hosted (for third-party packages). Dependencies can also
specify custom URLs inline: `depends: kaappi-net kaappi-auth::https://github.com/bob/kaappi-auth`.
Version constraints are supported: `depends: kaappi-net@">=0.2.0"` with
operators `>=`, `>`, `<=`, `<`, `^` (compatible), `~` (patch-level), and
comma-separated ranges (`>=1.0.0,<2.0.0`). Constraints resolve against
git tags via `git ls-remote --tags`.
The lockfile (`~/.kaappi/thottam.lock`) records source URLs for provenance.

## Ecosystem libraries

| Package | Type | Dependencies | Purpose |
|---------|------|-------------|---------|
| kaappi-net | C + Scheme | OpenSSL | TCP client/server, TLS client |
| kaappi-json | Pure Scheme | none | JSON parser/serializer |
| kaappi-redis | C + Scheme | kaappi-net | Redis client (RESP2) |
| kaappi-pg | C + Scheme | libpq | PostgreSQL client (DB-API 2.0) |
| kaappi-http | Scheme | kaappi-net | HTTP/HTTPS client + server |
| kaappi-web | Pure Scheme | kaappi-http, kaappi-json | Web framework (routing, middleware) |

**Library pattern** (for creating new kaappi-* packages):
- `csrc/` — C helper for FFI (if needed)
- `lib/kaappi/<name>.sld` — main library with re-exports
- `lib/kaappi/<name>/` — sub-libraries (ffi.sld, parse.sld, etc.)
- `kaappi.pkg` — package manifest
- `Makefile` — builds `.dylib` (if C code)
- All FFI signatures must match entries in `src/ffi.zig` dispatch tables

## Fiber I/O reactor (KEP-0001)

Each OS thread's scheduler owns a `Reactor` (`src/reactor.zig`:
kqueue/epoll/WASI-`poll_oneoff`/Windows-`WSAEventSelect` backends + a
userspace timer heap), created
lazily with the scheduler by `fiber.ensureScheduler`. Port reads/writes that
would block (`EAGAIN`) suspend the calling fiber instead of the thread
(`fiber.waitForFd`): a fiber dispatched directly by a scheduler loop parks
(`.io_waiting` + the yield-retry re-execution protocol — callers stash
partial progress into `port.read_buf` first via
`primitives_io.propagateReadErr`); the main fiber or one under re-entrant
native frames drives the scheduler in place instead. An in-place drive that
goes idle while an *enclosing* drive's wait already resolved or timed out
(`FiberScheduler.driving_waits`) unwinds with a catchable "port I/O
abandoned" error rather than blocking unboundedly — the pinned ancestor can
only proceed once this fiber's native frames unwind (#1625). Port fds (never 0/1/2)
flip to `O_NONBLOCK` lazily, only once a scheduler exists — sequential
programs keep blocking fds and their exact syscall profile. On WASI the
flip is the host-capability probe: `fd_fdstat_set_flags(NONBLOCK)` failing
(e.g. the playground's browser shim) leaves ports blocking, so nothing ever
registers an fd and the reactor degrades to CLOCK-only `poll_oneoff` waits —
timers and `thread-sleep!` (the one SRFI-18 primitive registered on WASM,
as a global; the `(srfi 18)` library itself stays native-only) always work.
On Windows the probe is `fdKind` (#1608): socket-backed ports (CRT fds
wrapping a SOCKET via `_open_osfhandle`) flip via `FIONBIO` and read/write
through `platform.sockRecv/sockSend`, with WSAEventSelect readiness in the
reactor; pipe ports enter *emulated* non-blocking mode (no OS flip exists) —
`platform.pipeRead/pipeWrite`'s peek/write-quota pre-checks synthesize the
EAGAIN and the reactor re-polls the same checks on a 10 ms quantum, paid
only while a pipe waiter exists; file ports stay blocking, which is the
POSIX baseline too (no OS has regular-file readiness — see
`docs/dev/windows.md` for why IOCP was rejected).
Ports on fd > 2 buffer writes in `port.write_buf` until
`flush-output-port`, `close-port`, a read on the same port, or the 8 KiB
high-water mark; `close-port` flushes, wakes fibers parked on the fd
(`fiber.wakeIoWaitersOnFd` — their retry sees `is_open == false` and raises
cleanly), and unregisters the fd from the reactor. `readOneByte` /
`portWriteBytes` in `src/primitives_io.zig` are the single byte
source/sink for every textual *and* binary port primitive — hook new I/O
through them, not around them.

## OS threads (SRFI-18)

`thread-start!` spawns real OS threads via `std.Thread.spawn`. Each child
thread gets its own VM and GC with an independent heap. Values are
**deep-copied** when crossing thread boundaries:

- **At start:** the thunk closure is deep-copied from parent GC to child GC
- **At join:** the result is deep-copied from child GC to parent GC

This means threads cannot share mutable heap state. The child GC collects
independently and the child heap is freed after `thread-join!`.

**Key implementation details:**
- `vm_instance` and `gc_instance` are `threadlocal` (`src/vm.zig:37`, `src/primitives.zig:182`)
- `GC.initForThread` creates per-thread GC sharing parent's symbol table (`src/memory.zig`)
- `GC.deepCopy` / `GC.deepCopyValue` deep-copies values between GC heaps (`src/memory.zig`)
- `VM.initForThread` creates per-thread VM sharing parent's globals/libraries (`src/vm.zig`)
- `VM.owns_globals` prevents child VM from freeing shared maps on deinit
- `symbol_mutex` (spinlock) protects concurrent symbol interning (`src/memory.zig`)
- Child GC/VM references stored in global `child_resources` map (`src/primitives_srfi18.zig`)
- Every heap object records its owning GC (`Object.owner` / `GC.id`); marking skips
  objects owned by another GC, so a child's collections never write mark bits on
  parent-heap objects reached via shared globals (`src/gc_collect.zig`, #958)

## Claude Code harness

The repo includes a Claude Code harness (hooks, permissions, path-scoped rules,
and skills) that enforces conventions automatically during AI-assisted development.
This section is the summary; `docs/dev/claude-code-harness.md` is the full
documentation (every component, how they interact, how to extend them) — when
changing the harness, update both.

### Hooks (`.claude/settings.json`)

| Hook | Event | What it does |
|------|-------|-------------|
| `session-start.sh` | SessionStart | Prints current branch, Zig version, and warns about stale worktrees (>7 days). |
| `zig-fmt-post.sh` | PostToolUse (Edit/Write) | Auto-formats `.zig` files after every edit. Silent on success. |
| `bash-guard-pre.sh` | PreToolUse (Bash) | Blocks `rm -rf /`, `sudo`, `git push --force`, `git tag -d`, `git reset --hard`. |
| `test-on-stop.sh` | Stop | Runs `zig build test` if any `.zig` files were modified. Blocks on failure. |

Hook scripts live in `.claude/hooks/`. They supplement (not replace) the git
pre-commit hook in `.githooks/pre-commit`.

### Permissions (`.claude/settings.json`)

- **allow**: `zig build/fmt/run`, `bash tests/scheme/*`, safe git ops, `find/grep/ls`
- **ask**: `git push`, `podman`, `gh release/pr`
- **deny**: `rm -rf /`, `sudo`, `git push --force`, `.env` reads, `.git` writes

### Path-scoped rules (`.claude/rules/`)

| Rule | Globs | Loaded when |
|------|-------|-------------|
| `gc-safety.md` | `src/primitives_*.zig`, `src/memory.zig`, `src/vm*.zig` | Editing GC-sensitive code |
| `compiler-forms.md` | `src/compiler*.zig`, `src/ir.zig`, `src/tests_ir.zig` | Editing compiler/IR code |

These load automatically — no manual invocation needed. They contain the
detailed checklists for GC write barriers, rooting, and compiler form additions.

### Skills (`.claude/skills/`)

| Skill | Purpose |
|-------|---------|
| `/add-builtin` | Step-by-step guide for adding a new built-in Scheme procedure |
| `/audit-primitives` | Audit a primitives file for R7RS correctness — writes tests, runs them, fixes bugs |
| `/bytecode-isa` | Reference for the bytecode instruction set |
| `/github-release` | Full release workflow (version bump, changelog, tag, push, CI verification) |
| `/r7rs-reader` | R7RS lexical syntax reference for reader changes |
| `/linux-test` | Build and test on Linux via podman (aarch64, x86_64, riscv64) |
| `/do-linux-test` | Full test suite on real x86-64 Linux via DigitalOcean droplet |
| `/do-stress-test` | Unit suite under `-Dgc-stress=true` on a DigitalOcean droplet (3-hour lifetime) |
| `/do-gate-benchmark` | KEP gate-campaign statistical benchmark (`benchmarks/gate/`) on a Linux x86_64 reference machine via DigitalOcean droplet |

### Ecosystem plugin (`kaappi-dev`)

The `infra/` repo hosts a Claude Code plugin (`kaappi-dev`) with ecosystem-wide
skills (`/kaappi-dev:test-ecosystem`, `/kaappi-dev:repo-status`, etc.), a bash
guard hook, and an `ecosystem-reviewer` agent. It loads automatically via the
workspace-level `.claude/settings.json` when working from the multi-repo workspace.

### Enforcement map

| Rule | Enforced by | Where |
|------|------------|-------|
| Session context | SessionStart hook | `.claude/hooks/session-start.sh` |
| Zig formatting | PostToolUse hook + git pre-commit | `.claude/hooks/zig-fmt-post.sh`, `.githooks/pre-commit` |
| No destructive commands | Deny permissions + PreToolUse hook | `.claude/settings.json`, `.claude/hooks/bash-guard-pre.sh` |
| Tests pass before stop | Stop hook | `.claude/hooks/test-on-stop.sh` |
| GC safety checklist | Path-scoped rule (auto-loaded) | `.claude/rules/gc-safety.md` |
| Compiler form checklist | Path-scoped rule (auto-loaded) | `.claude/rules/compiler-forms.md` |
| Bug fixes need tests | Advisory only | This file (Tests section) |
| Files ≤ 1500 lines | Advisory only | This file (File size policy) |
| Commit message format | Advisory only | Parent CLAUDE.md (Conventions) |

## Known limitations

See the "Known limitations" section in `README.md` (single source of truth).
