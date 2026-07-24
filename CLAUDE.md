# Kaappi — R7RS Scheme in Zig

Complete R7RS-small Scheme implementation. Zig 0.16, ~80k lines, 641 built-in procedures.

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
PATH for a C compiler (zig cc, cc, clang, gcc). `~/.kaappi/lib` is
deliberately **not** in that list — it is thottam's Scheme-library and
FFI-`dlopen` directory, so an archive placed there is invisible to
`kaappi compile`. The install script therefore puts it in
`<INSTALL_DIR>/../lib` (`~/.local/lib` by default), landing on the
`<exe_dir>/../lib` entry with no env var set.

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

### Primitives (split into 26 files)
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
| `primitives_srfi258.zig` | SRFI-258: uninterned symbols (string->uninterned-symbol, symbol-interned?, generate-uninterned-symbol) |
| `primitives_srfi260.zig` | SRFI-260: generated symbols (generate-symbol) |

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
164 SRFIs supported. 12 built-in (Zig primitives): 1, 9, 13, 18, 39, 69, 133, 170, 192, 254, 258, 260. 150 portable R7RS .sld files loaded on demand via `(import (srfi N))`, plus SRFI 261 (Portable SRFI Library References) as an import-resolver convention with no library file, and SRFI 226 (see below) as sub-libraries only with no bare `(srfi 226)` file: 0, 2, 4, 5, 6, 7, 8, 11, 14, 16, 17, 19, 23, 26, 27, 28, 29, 30, 31, 34, 35, 36, 37, 38, 41, 42, 43, 44, 45, 46, 48, 51, 54, 57, 59, 60, 61, 62, 64, 67, 70, 71, 78, 86, 87, 90, 94, 95, 98, 101, 111, 112, 113, 115, 116, 117, 118, 120, 123, 125, 126, 127, 128, 129, 130, 131, 132, 134, 135, 136, 137, 140, 141, 143, 144, 145, 146, 151, 152, 153, 156, 158, 161, 162, 165, 166, 167, 168, 169, 171, 173, 174, 175, 178, 180, 181, 185, 188, 189, 190, 193, 194, 195, 196, 197, 201, 202, 203, 207, 209, 210, 214, 215, 216, 217, 219, 221, 222, 223, 224, 225, 227, 228, 229, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 244, 247, 248, 250, 251, 252, 253, 255, 257, 259, 263, 264, 267, 270, 271. Sub-libraries: (srfi 146 hash), (srfi 171 meta), (srfi 166 pretty), (srfi 166 columnar), (srfi 166 unicode), (srfi 166 color), (srfi 226 control prompts), (srfi 226 control continuations), (srfi 226 control times), (srfi 254 ephemerons), (srfi 254 guardians), (srfi 254 transport-cell-guardians), (srfi 254 ephemerons-and-guardians), (srfi 257 misc), (srfi 257 box), (srfi 257 rx), (srfi 263 syntax), (srfi 271 randomized), (srfi 271 determinized), (srfi 248 primitives). SRFI 226 (Control Features) is a 12-sub-library spec with no default/main library of its own (every feature lives under a named sub-library per its own spec); only the three `control` sub-libraries listed above (a reduced, escape-only continuation-prompt subset) are implemented — see the header of `lib/srfi/226/control/prompts.sld` for what's out of scope and why — so unlike every other portable SRFI it never appears as a bare number in `kaappi features`' scan (kaappi#1517 scans `lib/srfi/*.sld` non-recursively, matching what actually ships). SRFI 257's `rx` sublibrary layers regexp match patterns over SRFI 115 and SRFI 264 (`(~/ "([a-z]*):([0-9]*)" s name num)`); it is a verbatim port apart from the reference's missing `regexp-search-all`, which `~/all+` calls (see the header of `lib/srfi/257/rx.sld`). Its reference suite is what drove SRFI 115's matcher to a backtracking CPS engine (#1679): `%run` now offers each way a node can match to a continuation instead of returning one possessive answer, so `(regexp-matches (rx (* any) "b") "ab")` succeeds, `*?`/`??`/`**?` work, and a single-character repetition body still scans iteratively (`%run-rep1`) so `(* any)` over a long string costs no stack. #1681 then closed the remaining SRE gaps: look-behind (`%run-behind` scans backwards, floored at the search `start` that `%run` now threads alongside `end`), `grapheme`/`bog`/`eog` (UAX #29 clusters via `%gcb`/`%gcb-join?`/`%grapheme-end`), the `title-case` and `symbol` char sets, `&`/`-` set operators (every `<cset-sre>` compiles to a node `%match-one` decides, so `~`/`&`/`-` never re-enter the backtracking matcher), a real `w/ascii`/`w/unicode` context (a compile-time flag in the `%make-ctx` box, not a runtime one — SRFI 115 scopes it to char sets, so `%cm` is untouched), `w/nocapture`, submatch lookup by `(-> name …)` symbol, and bare `word` as a whole word rather than one word-constituent character. The three Unicode properties `(scheme char)` cannot answer — Lt, S\*, and the UAX #29 break classes — ship as range tables *inside* the portable `.sld`, generated by `tools/gen_srfi115_charsets.py`; regenerate them on a Unicode version bump and keep the version in step with `tools/gen_unicode_tables.py`. SRFI-254 (ephemerons and guardians) needs GC integration — its weak-reference marking/resurrection lives in `gc_collect.processWeakRefs`, its heap types (`Ephemeron`, `Guardian`, `TransportCell`) in `types.zig`, its primitives in `primitives_srfi254.zig`, and guardian invocation (a guardian is callable) in `vm_calls.invokeGuardian`. On this non-moving collector `current-hash` is a stable identity hash and transport cell guardians are degenerate (keys never move, so `(tg)` always yields #f). SRFI 258 (uninterned symbols) is built-in: `string->uninterned-symbol` and `generate-uninterned-symbol` allocate via `GC.allocUninternedSymbol` (memory.zig), which bypasses the intern table so the result is an ordinary collectable object never `eqv?` to any other symbol; the `Symbol.interned` flag (types.zig) drives `symbol-interned?` and the unreadable `#<uninterned-symbol …>` printer form that `read` rejects. Equality needs no special code (symbols already compare by identity), and `gc_deep_copy` preserves uninterned-ness across SRFI-18 thread boundaries. SRFI 260 (generated symbols) is built-in but needs no engine integration beyond one primitive (`generate-symbol` in `primitives_srfi260.zig`): because Kaappi interns every symbol by name (no uninterned symbols), write/read invariance is automatic, so the primitive just interns a fresh `"<pretty>.<counter>.<128-bit-OS-entropy-hex>"` name — a process-global atomic counter guarantees in-process uniqueness and `platform.osRandomBytes` supplies the unpredictability. SRFI 120 (Timer APIs) is portable (`lib/srfi/120.sld`) with no engine
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
development. **Single calling thread only** is a hard requirement of this
implementation, not just a style guideline: calling any of these
procedures on one timer from a *second*, different thread reproduced
nondeterministic memory corruption this session (varying panic
signatures — integer overflow, bad alignment, bus error — across runs),
even though a bare hand-written two-thread channel round trip with none
of this library's other moving parts did not reproduce it in isolation.
This points at a real bug in the interaction between multi-hop channel
messages and cross-thread deep-copy that was not root-caused and is
out of scope for a portable-library change — worth its own investigation
later. SRFI 21 and 230 are excluded — see `docs/dev/srfi-exclusions.md`.
SRFI 237 (R6RS Records, refined) is the one record-system SRFI needing real
engine changes: `RecordType` (`types.zig`) gained `parent`/`own_field_names`/
`own_field_mutable`/`uid`/`sealed`/`is_opaque` fields (`parent` is the only
new heap pointer, traced in all three `gc_collect.zig` mark-graph switches;
the rest are raw owned bytes like the pre-existing `name`, needing only
`objectSize`/`freeObject`/`gc_deep_copy` updates — RecordType is fully
immutable after construction, so none of this needs a write barrier), and
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
literal name unconditionally. This only closes the gap for top-level use;
library-body use of a shadowing `define-record-type` (`compiler_lambda.zig`/
`vm_library.zig`'s separate scanning path) is a documented, un-closed gap —
same limitation on the R6RS-clause syntax itself. SRFI 137 (Minimal Unique
Types) is pure portable Scheme built directly on `(srfi 237)`: a "subtype"
is exactly SRFI 237's `parent` relationation, with every level correctly
sharing the ROOT type's single payload field (a subtype's own rtd adds
*zero* new fields, inheriting the root's one field via the parent rtd/rcd
chain — an earlier attempt to give every level its own field this was ever
a bug is worth remembering if this file is touched again). SRFI 136
(Extensible record types) demonstrates the CPS-style introspection macro
its spec is built around — `(<type-name>)` yields the type's own rtd,
`(<type-name> (<keyword> <datum>...))` splices that type's own literal
`parent` keyword and field-specs into a call to `<keyword>` — needing no
identifier synthesis at all (it only ever replays syntax already captured
hygienically). SRFI 131 (ERR5RS Record Syntax, reduced) layers on the same
substrate with by-*name* (not positional) constructor field resolution,
including a subtype field shadowing an ancestor's same-named field per its
own spec text. Two portability gotchas surfaced repeatedly while building
these three: (1) calling a `%`-prefixed primitive from `(srfi 237
primitives)` with no explicit import is *not* reliably ambiently visible
the way some other primitives are elsewhere in this codebase — declare the
import explicitly rather than assume it; (2) a genuine, unrooted-out
compiler quirk was found (not fixed): calling one `%`-prefixed
forward-referenced global as a direct, non-tail-position argument
expression to another (e.g. inside `if`/`list`, or as an argument nested
one level deep) inside a closure passed to `map` raised a spurious
"undefined variable" for the *inner* call, reliably fixed by routing
through an extra wrapper function (any name) called in tail position —
ordinary (non-`%`) names in the identical shape were unaffected; worth a
dedicated investigation later.
SRFI 57 (Records, with inheritance via "schemes" -- a named, reusable field-
label list a type or another scheme can extend, with multiple schemes
mergeable at once via left-to-right append + delete-duplicates) is portable
(`lib/srfi/57.sld`) but deliberately does NOT port its own reference
implementation's technique: that reference compares field-label identifiers
at macro-expansion time via the standard `let-syntax`-plus-literals-list
"if-free=?" trick. A third, previously-undiscovered expander bug surfaced
while attempting this port: a `let-syntax` anywhere in an expansion chain
that eventually produces a `define-syntax` form (even many macro layers
removed) fails to compile outright — reproduced in isolation down to a
two-line `(let-syntax (...) (define-syntax ...))`, unrelated to the two
already-documented quirks above. Rather than root-cause that (a separate
expander investigation), SRFI 57 sidesteps it: field labels become ordinary
quoted symbols and every list merge/dedup/lookup happens at plain run time
(`assq`/`memq` over symbol lists) instead of macro-expansion time — a
scheme or type name is bound with plain `define` (not `define-syntax`) to a
`(field-symbols . rtd-or-#f)` pair, with no CPS introspection macro and no
identifier comparison anywhere in the file. This is simpler than the
reference design, not merely an engine-avoidance workaround, and completes
issue #1695 (all 9 of its SRFIs now shipped or excluded). A scheme's
polymorphic predicate/accessor resolve structurally at call time (does the
record's *actual* rtd, found via `record-rtd`, have every field the scheme
needs) rather than through any nominal "declared to conform" registry — and
`record-update`/`record-update!` accept but don't validate their
scheme-or-type target argument, always operating on the record's own actual
type (which is what the spec requires the result to be either way); both
are documented, deliberate scope reductions, not silent gaps.
SRFI 192 (port positioning) is built-in: `port-position`/`set-port-position!`/`port-has-port-position?`/`port-has-set-port-position!?` in `primitives_io.zig` use plain exact-integer byte offsets for every port kind (string ports already track their own position for free; fd-backed ports get a new `platform.seek` — POSIX `lseek`, Windows `_lseeki64`, WASI `fd_seek`, which needs its own `whence_t` enum) with the OS's raw offset corrected for whatever this port's own software buffers have read ahead of or not yet flushed behind; the spec's opaque textual-port position objects and its dedicated `i/o-invalid-position-error` condition type are not implemented. SRFI 181 (custom ports and transcoded ports) is portable (`lib/srfi/181.sld`) over a native primitives sub-library, `(srfi 181 primitives)` (`.srfi_181_primitives` in `primitives.zig`, `primitives_srfi181.zig`) — the same registry-shadows-a-same-named-.sld problem SRFI 248 hit first (see below): `(srfi 181)` had to move off a direct registry entry once transcoded ports needed a real `.sld` to live in. Custom ports (5 `make-custom-*-port` constructors plus `make-file-error`) landed first, in Phase 3 (#1727); transcoded ports (`make-transcoder`, `native-transcoder`, codecs, eol-styles, the `raise` error-handling mode) followed in their own follow-up (#1729) once #1727 shipped. A custom port's read!/write!/get-position/set-position!/close/flush procedures are the first Value-bearing fields `Port` has ever had (`Port.custom_backend: ?*CustomBacking`, `types.zig`) — traced by a shared `markPortValues` helper wired into all three `gc_collect.zig` marking switches plus the two dedicated (non-catch-all) `freeObject`/`objectSize` arms, since neither has an exhaustiveness check to catch a forgotten site. Every callback runs through `vm.callWithArgs`, which always executes with `vm.dispatched_from_scheduler` forced false; a callback that tries to block (another port's I/O, `thread-sleep!`) is rejected with a catchable error via a dedicated `vm.in_custom_port_callback` counter (checked in `fiber.waitForFd` and `primitives_srfi18.threadSleepFn`) rather than risking the native-stack-overflow a silent recursive scheduler drive would otherwise allow — custom port callbacks must be effectively synchronous, non-blocking code. Both `readOneByte` and `portWriteBytes` (the single byte source/sink every port primitive already funnels through) gained a custom-port branch exploiting that Kaappi strings are already UTF-8 byte arrays internally: a textual read!'s returned character count converts to a byte offset via `utf8IndexToByteOffset` on the buffer's freshly re-read `data`/`len` (never cached across the call — a differing-byte-width `string-set!` inside the callback reallocates the whole backing buffer in place, `primitives_string.stringSetFn`). Transcoded ports layer a second Value-bearing field, `Port.transcode: ?*TranscodeState` (its own marking/freeing arms alongside `custom_backend`'s in `gc_collect.zig`; `TranscodeState` holds just `wrapped_port: Value` plus plain `Codec`/`EolStyle`/`ErrorMode` enums, no other GC-traced fields). `readOneByte`/`portWriteBytes` gained a `transcode` branch that decodes/encodes exactly one character per call, never a batch: a fiber park reruns the whole native call from scratch, so any Zig-local "progress so far" would be silently lost, while a durable `*Port` field survives the retry — CRLF lookahead therefore reuses the wrapped port's own `peek_byte`/`peek_extra`, the same mechanism `read-line`'s own CR/CRLF handling already relies on, instead of a new field. The `raise` error-handling mode needed a mechanism custom ports' callbacks never required: `primitives_control.raiseContinuable` (factored out of `raise-continuable`'s own native implementation) signals a continuable `.io_decoding`/`.io_encoding` `ErrorObject` and resumes decoding from the next byte once the handler returns — safely, because a reentrant `vm.callHandler`/`runUntil` always runs with `dispatched_from_scheduler` forced false, so it can only block in place if the handler itself blocks, never return `Yielded` and retry the whole call (which would re-invoke the handler a second time for the same condition). v1 supports only the UTF-8 codec — `latin-1-codec`/`utf-16-codec` are not exported at all, rather than exported-but-always-erroring, since no other binding in Kaappi exists solely to fail — and `native-transcoder` returns UTF-8/`'none`/`'replace`, matching `read-char`'s existing no-translation, never-raise-on-invalid-UTF-8 behavior as closely as a brand-new feature reasonably can. Codecs/eol-styles/error-modes are plain symbols and the transcoder itself is a portable `define-record-type` (`lib/srfi/181.sld`), so native code never touches record internals — only the differently-named `%transcoded-port` primitive does, receiving the transcoder's already-unpacked codec/eol-style/error-mode symbols and validating them there (`make-transcoder` itself does not validate eagerly; codecs are untyped symbols, so there is no earlier point to enforce it). SRFI 267 (raw string syntax) is a hybrid: its `#"X"…"X"` lexical syntax is built into the reader (`readRawString` in `reader_tokens.zig`), while its port procedures load from the `.sld`. SRFI 248 (minimal delimited continuations) is also a hybrid: `with-unwind-handler`, `empty-continuation?`, and the extended two-variable `guard` live in `lib/srfi/248.sld` as a Filinski shift/reset over `call/cc`, built on three VM primitives (`%call-with-unwind-handler`, `%unwind-raise-empty?`, `%pop-unwind-handler!` in `primitives_control.zig`) exported by the built-in sub-library `(srfi 248 primitives)`. The enabling VM change is a *sticky* exception handler (`ExceptionHandler.sticky`): `raise`/`raise-continuable` invoke it in place without popping, so a `call/cc` snapshot taken while it handles includes it and resuming re-arms the prompt (reset0 semantics) — the delimiter must stay file-only because the registry shadows a same-named `.sld`. `empty-continuation?` combines a VM tail-call latch (`native_call_was_tail`, set by every tail-call opcode in `vm_dispatch.zig`) with the sticky handler's frame_count baseline, so a raise in tail position of a non-tail-called helper is correctly non-empty. Delimited continuations are single-shot (a resume crosses the sticky-handler native frame, the same limit as continuations captured under native drivers). SRFI 261 (portable SRFI library references) is a resolver-level convention with no library file: `(srfi srfi-<n>)` and `(srfi <mnemonic>-<n>)` (e.g. `(srfi lists-1)`, `(srfi vectors-133)`) resolve to `(srfi <n>)` as a fallback — literal registry/file names win, sub-library tails pass through, and the trailing number alone is authoritative (mnemonics are not validated). Implemented in `vm_library.zig` (`srfi261FormNumber`/`normalizeSrfiLibName` in `processImportSet`; `libraryIsAvailableSrfi261` behind both cond-expand `(library …)` entry points) and mirrored path-level in `test_selection.zig` so `kaappi test --changed` keeps the dep edge. Every supported SRFI is also a `cond-expand` feature identifier `srfi-<n>` (#1649): `(cond-expand (srfi-1 …) …)`. These are derived, never listed — `srfiFeatureAvailable` in `vm_library.zig` routes `srfi-<n>` through the same availability check as `(library (srfi <n>))`, so built-in, portable, `--sandbox` and WASM answers all match what `(import (srfi <n>))` would do. Both feature-req evaluators consult it: `evalLibFeatureReq` (inside `define-library`) directly, and the compiler's `evalFeatureReq` via the `globals.srfiFeatureAvailable` callback the VM registers (mirroring the `library_exists_checker` used by the `(library …)` form). SRFI 261 is the one supported SRFI with no `.sld`, so `srfi-261` answers true directly. Like `(library …)` requirements, `srfi-<n>` is a derived probe, not a bare feature, so `(features)` (and the `kaappi features` table it must equal, #1517) stays platform-only; `kaappi features` still notes the ids in its SRFIs section.

The library loader in `vm_library.zig` supports `cond-expand`, `include` (paths resolved relative to the .sld file), and `(export (rename ...))` in `define-library`. Macro transformers defined with `define-syntax` in library `begin` blocks are exported and imported correctly.

Of the 208 final SRFIs in the registry, 164 are implemented, 16 are tracked for
future implementation (issue #1694 — #1695 fully closed in Phase 4:
57/131/136/137/237/240 shipped, 99/100/150 excluded — #1699 minus what
Phases 1–3 closed and #1729, which completed SRFI 181's transcoded-port
half — custom ports landed separately in Phase 3, #1727; #1703 and #1702
closed in full in Phase 4), and 28 are excluded — see
`docs/dev/srfi-exclusions.md` for the full rationale (7 meta/ecosystem SRFIs
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
specifically 99's syntax-rules-expressible reduced subset; and 150, needing
SRFI 148/147's custom-macro-transformer support, whose own spec text says the
same about portability — 1 SRFI — 208 — whose own spec text states the same
about raw NaN bit-pattern access, which Kaappi's NaN-boxing value
representation makes categorically unrepresentable, 1 SRFI — 106 — redundant
with the `kaappi-net` ecosystem package's existing, broader-scoped socket
support, and 2 concurrency-model-incompatible SRFIs — 21 and 230 — which need
a userspace-scheduled thread model and cross-heap shared mutable memory
(respectively) that Kaappi's OS-native-thread,
independent-heap-per-thread SRFI-18 doesn't have).

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

1. Add tag to `ObjectTag` enum in `src/types.zig` (slots 40+ available, enum is u6 with 64 slots).
2. Add the struct with `header: Object` as the first-declared field
   (convention only — Zig's auto layout may still place it at a nonzero
   byte offset, and that's fine). Heap Values always carry the address of
   the `header` field: build them with `makePointer(&x.header)` — the
   `*Object` parameter type makes passing the struct pointer a compile
   error — and recover the struct with `Object.as()`/`@fieldParentPtr`,
   never a direct cast.
3. Add `allocXxx` in `src/memory.zig`.
4. Handle the new tag in the 5 exhaustive per-tag switches in
   `src/gc_collect.zig` (all real function names, not the stale
   `memory.zig`-hosted `markValue`/`freeObject` this step used to name):
   `markObjectContents` and `markValueInner`'s own worklist switch (both
   trace contained Values — a type with no Value fields, like `Symbol`,
   just needs a no-op `{}` arm in each, since Zig's exhaustiveness check
   forces one either way), `referencesYoung` (generational remembered-set
   check), `objectSize` (GC stats), and `freeObject` (free owned memory).
   `types.zig`'s `typeName` also switches on `ObjectTag` for error messages.
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

**The install script lives in that repo too** — `docs/install.sh`, served at
**https://kaappi-lang.org/install.sh**, which is the `curl … | bash` line in
`README.md` and the only copy anyone runs. There is deliberately **no copy in
this repo**: one existed until 0.22.0, was served and tested by nothing, and
drifted three commits behind the real one — so "fix install.sh" here shipped
nothing to users, which is how the missing `libkaappi_rt.a` install went
unnoticed. Edit it there. The `test-install-script` job in
`.github/workflows/post-release.yml` curls and tests the live script after
every release, across `ubuntu-latest`, `ubuntu-24.04-arm`, and `macos-latest`.
Adding a platform means teaching its `detect_platform` the `uname` spelling
and its `rt_artifact` case — `docs/dev/porting.md` Stage 6.

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
| `/parallel-issues` | Group open GitHub issues into parallel sets for concurrent Claude Code sessions |
| `/quiz` | Prediction-with-commitment comprehension quiz on a core-tier subsystem (`docs/dev/understanding-map.md`); answers verified against code and live runs, results logged to `~/.kaappi/quiz-ledger.md` |

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
