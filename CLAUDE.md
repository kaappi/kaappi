# Kaappi — R7RS Scheme in Zig

Complete R7RS-small Scheme implementation. Zig 0.16, ~80k lines, 689 built-in procedures.

## Build

```bash
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
zig build -Dmax-handlers=256       # initial handler-stack capacity (default: 64, grows to 32768)
zig build -Dmax-winds=256          # initial dynamic-wind stack capacity (default: 64, grows to 32768)
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
`--lib-path`) aggregating from the runner's own counters; `-j`/`--jobs <n>`
runs files concurrently (default: one per CPU, Windows always 1) with verdicts
and output order identical at any job count, since each file was already its own
worker process; `--changed`
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
`-Dmax-handlers=N` (initial exception-handler stack capacity, default 64, grows to 32768),
`-Dmax-winds=N` (initial dynamic-wind stack capacity, default 64, grows to 32768),
`-Dgc-threshold=N` (initial GC object threshold, default 8192).

All four stacks grow geometrically and are hard-capped; exceeding a cap is
`KP3008` and, unlike a program's own `raise`, is **not** catchable — a `guard`
clause never sees it (#1886). Before that fix the handler and wind stacks were
fixed 64-entry arrays whose overflow *was* catchable, so 65 nested `guard`s
returned a plausible wrong value with exit 0. `errors.isUncatchable` is the
single list of what unwinds past every handler: VM limits (`StackOverflow`,
`ExecutionTimeout`) and control-flow signals (`Terminated`, `Yielded`).

Requires Zig 0.16+ and libc (for linenoise terminal handling).

### Git hooks

After cloning, enable the pre-commit format check:

```bash
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
let/let*, cond/case/do, lambda (with closures and variadic parameters),
self-tail-call optimization (compiled as loops), tail calls to other native
functions, and `apply` (lowered to the argument-splicing `@kaappi_apply`
runtime call, so an enclosing function keeps its native compilation —
kaappi#1803; the dispatch mirrors the interpreter's tail/non-tail/shadowed
cases exactly). Forms not yet compiled natively (letrec, named-let, guard,
quasiquote, `call/cc`, `call-with-values`, `eval`, …) run through
`kaappi_eval` at runtime — and because that eval resolves names in the *global*
environment, any lexical scope containing one (the enclosing `define`/`lambda`
frame or `let`) declines native compilation as a whole rather than splitting
itself across the boundary. The keyword set driving that decision is
`ir.eval_fallback_form_names` (kaappi#827/#1496/#1799 — see
`docs/dev/llvm-backend.md`). That set is **comptime-derived** and needs no
maintenance: it walks `llvm_node_table`, then every `FormKind` field (skipping
`isNativeLoweredForm`), then `other_special_forms`, so a new `FormKind` joins
it automatically, and a comptime block enforces one `llvm_node_table` entry per
`NodeTag`.

The silent-miscompilation hazard is real but lives one file over, in
`isRejectedFormHead` (`llvm_emit_forms.zig`) — a **hand-maintained** 32-name
array gating `cond`/`case`/`do` through `exprNativeEmittable`, structurally
independent of the derived set and already missing `define-property`
(kaappi#1896). Add a keyword there when you add a form, until that list is
derived too.

**Always use `zig cc` (not `clang`) for linking native binaries against
`libkaappi_rt.a`.** The Zig-compiled static library references
`__zig_probe_stack` and other Zig compiler-rt intrinsics that `clang`
cannot resolve. `zig cc` includes these automatically.

## Architecture

```text
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
| `types.zig` | ~1200 | Value type, `Object`/`ObjectTag`, opcodes, type predicates, hygiene helpers, re-export hub for the `types_*.zig` heap-type domain files below |
| `memory.zig` | ~850 | GC struct, lifecycle, write barrier, rooting, quarantine; aliases the allocators below into `GC` |
| `gc_alloc.zig` | ~1400 | All `allocXxx` heap-object constructors (delegated from memory.zig, aliased into `GC` so `gc.allocXxx(...)` is unchanged) |
| `gc_collect.zig` | ~1000 | GC orchestration, remembered set, marking, SRFI 254 weak-ref processing (delegated from memory.zig) |
| `gc_sweep.zig` | ~600 | Sweep phase: sweepYoung/sweepOld/sweep, `objectSize`, `freeObject` (delegated from gc_collect.zig) |
| `gc_deep_copy.zig` | — | Cross-thread deep copy (delegated from memory.zig) |
| `reader.zig` | ~700 | Tokenizer, S-expression parser, Unicode lexing |
| `expander.zig` | ~1000 | Macro-use expansion engine: expandMacro/expandProceduralMacro, syntax-rules pattern matching, usertext/hygiene-strip walks |
| `expander_instantiate.zig` | ~1000 | syntax-rules template instantiation + renameForHygiene/scope-table minting (shares expander.zig's threadlocal expansion context) |
| `printer.zig` | ~300 | Value → string (write mode and display mode) |

### Heap-type domain files (split into 11 files, kaappi#1731)

`types.zig` re-exports every name below (`pub const Foo = types_x.Foo;`), so
existing `types.Foo` call sites across the codebase are unaffected by which
file actually defines a given type. Fundamental types with no natural
domain-mate (`Pair`, `Symbol`, `SchemeString`, `Closure`, `Function`,
`Vector`, `Bytevector`, `Promise`, `Complex`, `ParameterObject`,
`SchemeEnvironment`, `RandomSource`, ...) stay directly in `types.zig`.

| File | Heap types |
|------|-----------|
| `types_macro.zig` | `Transformer`, `TransformerKind`, `CapturedLocal` |
| `types_error.zig` | `ErrorObject` |
| `types_record.zig` | `RecordType`, `RecordInstance` |
| `types_numeric.zig` | `NumericVector`, `NumericElementKind` (SRFI 160), `Bignum`, `Rational` |
| `types_port.zig` | `Port` and its satellites: `Codec`, `EolStyle`, `ErrorMode`, `TranscodeState` (SRFI 181), `CustomBacking` (SRFI 181), `RandomKind`, `RandomGen` (SRFI 271) |
| `types_continuation.zig` | `Continuation`, `CallFrame`, `SavedFrame`, `SavedHandler`, `ExceptionHandler`, `WindRecord`, `MultipleValues`, frame/register capacity constants |
| `types_ffi.zig` | `FfiLibrary`, `FfiFunction`, `FfiCallback`, `FfiType` |
| `types_threading.zig` | `Channel`, `Mutex`, `ConditionVariable`, `Srfi18Time`, `TimeType` |
| `types_hashtable.zig` | `HashTable`, `HashEntry`, `HashEntryState`, `CompareMode` (SRFI 69) |
| `types_filesystem.zig` | `FileInfo`, `UserInfo`, `GroupInfo`, `DirectoryObject` (SRFI 170) |
| `types_weakrefs.zig` | `Ephemeron`, `Guardian`, `GuardEntry`, `TransportCell` (SRFI 254) |

`Fiber` (`fiber.zig`) predates this split and follows neither convention:
its struct lives outside `types.zig` entirely with no `types.Fiber` re-export.

### Compiler & IR (11 files)

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
| `compiler_macro.zig` | Macro-use path: expandAndCompileMacroUse, hygiene injection walks, free-ref collection; re-exports compiler_define_syntax.zig |
| `compiler_define_syntax.zig` | Macro-defining forms: define-syntax, let-syntax, letrec-syntax, define-property, transformer-spec resolution (SRFI 147), syntax-rules parsing, transformer finalization |
| `compiler_forms.zig` | Re-export hub (thin file, don't edit directly) |

### VM (split into 9 files)

| File | Responsibility |
|------|---------------|
| `vm.zig` | VM struct, init/deinit, error handling, delegation wrappers |
| `vm_dispatch.zig` | runUntil bytecode dispatch loop, opcode handlers, bytecode readers |
| `vm_calls.zig` | execute, run, callValue, callClosure, callNative, profile helpers |
| `vm_eval.zig` | eval, handleTopLevelForm dispatcher |
| `vm_library.zig` | handleDefineLibrary, .sld file loading, SRFI 261 normalization, cond-expand features, include; re-exports vm_imports.zig |
| `vm_imports.zig` | Import-set algebra: handleImport, processImportSet (only/except/rename/prefix), transformer free-ref copying |
| `vm_records.zig` | handleDefineRecordType desugaring |
| `vm_continuations.zig` | captureContinuation, restoreContinuation, performWindTransition, callWithCC |
| `vm_debug.zig` | Stepping debugger: breakpoints (with conditions), watch expressions, step/next/step-out/continue, up/down frame navigation, locals, backtrace |

### Primitives (split into 31 files)

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
| `primitives_srfi160.zig` | SRFI-160: the 6 generic `%`-prefixed `NumericVector` primitives every per-type `.sld` builds on |
| `primitives_srfi181.zig` | SRFI-181: custom ports (the 5 `make-custom-*-port` constructors) and `%transcoded-port` |
| `primitives_srfi211.zig` | SRFI-211: `er-macro-transformer`, `lisp-transformer` procedural transformer constructors |
| `primitives_srfi237.zig` | SRFI-237: R6RS record procedural layer (`(srfi 237 primitives)`) |
| `primitives_srfi254.zig` | SRFI-254: ephemeron/guardian constructors, predicates, accessors (GC half lives in `gc_collect.zig`) |
| `primitives_fiber.zig` | `(kaappi fibers)`: spawn, yield, fiber-join, channels |
| `primitives_parallel.zig` | KEP-0002: the single native primitive backing `lib/kaappi/parallel.sld` |
| `primitives_random_port.zig` | SRFI-271 random port `%`-prefixed internals |
| `primitives_sysinfo.zig` | System inquiry shared by SRFI 59 (vicinity), 112 (environment), 193 (command line) |

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
| `llvm_emit.zig` | LLVM IR text emitter core: LLVMEmitter struct/state, program orchestration, call emission, constants/interning (special-form/cond/case/do emitters live in `llvm_emit_forms.zig`; let/lambda/tailcall/inline/freevars satellites likewise) |
| `runtime_exports.zig` | C-ABI bridge for LLVM native backend (21 exported functions) |
| `fmt.zig` | `kaappi fmt`: comment-preserving CST reader (lexer + parser), CLI entry, real-reader `equal?` round-trip safety net |
| `fmt_print.zig` | `kaappi fmt` layout engine: fits-or-breaks pretty-printer, special-form indentation rules |
| `testing_helpers.zig` | Shared `makeTestVM` helper for unit tests |
| `tests_ir.zig` | IR tests: bytecode parity, behavioral correctness, analysis, optimizations |
| `tests_*.zig` | Unit tests by feature (core_eval, tail_calls, macros, io, etc.) |

### SRFI libraries (in `lib/srfi/`)

178 SRFIs supported. 12 built-in (Zig primitives): 1, 9, 13, 18, 39, 69, 133, 170, 192, 254, 258, 260. 162 portable R7RS .sld files loaded on demand via `(import (srfi N))`, plus SRFI 261 (Portable SRFI Library References) as an import-resolver convention with no library file, and SRFI 226, SRFI 160, and SRFI 211 (see below) as sub-libraries only with no bare `(srfi 226)`/`(srfi 160)`/`(srfi 211)` file (so none appears as a bare number in `kaappi features`' scan): 0, 2, 4, 5, 6, 7, 8, 11, 14, 16, 17, 19, 23, 25, 26, 27, 28, 29, 30, 31, 34, 35, 36, 37, 38, 41, 42, 43, 44, 45, 46, 48, 51, 54, 57, 59, 60, 61, 62, 63, 64, 66, 67, 70, 71, 74, 78, 86, 87, 90, 94, 95, 98, 101, 111, 112, 113, 115, 116, 117, 118, 120, 123, 125, 126, 127, 128, 129, 130, 131, 132, 134, 135, 136, 137, 139, 140, 141, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 156, 158, 161, 162, 164, 165, 166, 167, 168, 169, 171, 173, 174, 175, 178, 180, 181, 185, 188, 189, 190, 193, 194, 195, 196, 197, 201, 202, 203, 207, 209, 210, 213, 214, 215, 216, 217, 219, 221, 222, 223, 224, 225, 227, 228, 229, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 241, 242, 244, 247, 248, 250, 251, 252, 253, 255, 257, 259, 263, 264, 267, 270, 271. Sub-libraries: (srfi 146 hash), (srfi 171 meta), (srfi 166 pretty), (srfi 166 columnar), (srfi 166 unicode), (srfi 166 color), (srfi 211 explicit-renaming), (srfi 211 define-macro), (srfi 211 syntax-parameter), (srfi 226 control prompts), (srfi 226 control continuations), (srfi 226 control times), (srfi 254 ephemerons), (srfi 254 guardians), (srfi 254 transport-cell-guardians), (srfi 254 ephemerons-and-guardians), (srfi 257 misc), (srfi 257 box), (srfi 257 rx), (srfi 263 syntax), (srfi 271 randomized), (srfi 271 determinized), (srfi 248 primitives). SRFI 226 (Control Features) is a 12-sub-library spec with no default/main library of its own (every feature lives under a named sub-library per its own spec); only the three `control` sub-libraries listed above (a reduced, escape-only continuation-prompt subset) are implemented — see the header of `lib/srfi/226/control/prompts.sld` for what's out of scope and why — so unlike every other portable SRFI it never appears as a bare number in `kaappi features`' scan (kaappi#1517 scans `lib/srfi/*.sld` non-recursively, matching what actually ships). SRFI 257's `rx` sublibrary layers regexp match patterns over SRFI 115 and SRFI 264 (`(~/ "([a-z]*):([0-9]*)" s name num)`); it is a verbatim port apart from the reference's missing `regexp-search-all`, which `~/all+` calls (see the header of `lib/srfi/257/rx.sld`). Its reference suite is what drove SRFI 115's matcher to a backtracking CPS engine (#1679): `%run` now offers each way a node can match to a continuation instead of returning one possessive answer, so `(regexp-matches (rx (* any) "b") "ab")` succeeds, `*?`/`??`/`**?` work, and a single-character repetition body still scans iteratively (`%run-rep1`) so `(* any)` over a long string costs no stack. #1681 then closed the remaining SRE gaps: look-behind (`%run-behind` scans backwards, floored at the search `start` that `%run` now threads alongside `end`), `grapheme`/`bog`/`eog` (UAX #29 clusters via `%gcb`/`%gcb-join?`/`%grapheme-end`), the `title-case` and `symbol` char sets, `&`/`-` set operators (every `<cset-sre>` compiles to a node `%match-one` decides, so `~`/`&`/`-` never re-enter the backtracking matcher), a real `w/ascii`/`w/unicode` context (a compile-time flag in the `%make-ctx` box, not a runtime one — SRFI 115 scopes it to char sets, so `%cm` is untouched), `w/nocapture`, submatch lookup by `(-> name …)` symbol, and bare `word` as a whole word rather than one word-constituent character. The three Unicode properties `(scheme char)` cannot answer — Lt, S\*, and the UAX #29 break classes — ship as range tables *inside* the portable `.sld`, generated by `tools/gen_srfi_charsets.py --target 115`; regenerate them on a Unicode version bump and keep the version in step with `tools/gen_unicode_tables.py`. SRFI 14 (character sets) uses the same generator (`--target 14`) for the same reason, and for more categories: a char set is an inversion list of `(lo . hi)` code-point pairs and every standard `char-set:*` constant is a literal built from a category table, never from a scan over `(scheme char)` — a scan costs ~0.14s per predicate, and memoising one lazily is unsafe here, since a child SRFI-18 thread forcing the memo writes a child-heap value into a parent-heap record that dangles after the join (kaappi#1895). Consequence worth knowing: `char-set:letter` is L* while `char-alphabetic?` is the broader Alphabetic property, and `char-set:digit` is all 680 of Nd while `char-numeric?`'s hand-written table covers only the 370 in the BMP. SRFI-254 (ephemerons and guardians) needs GC integration — its weak-reference marking/resurrection lives in `gc_collect.processWeakRefs`, its heap types (`Ephemeron`, `Guardian`, `TransportCell`) in `types.zig`, its primitives in `primitives_srfi254.zig`, and guardian invocation (a guardian is callable) in `vm_calls.invokeGuardian`. On this non-moving collector `current-hash` is a stable identity hash and transport cell guardians are degenerate (keys never move, so `(tg)` always yields #f). SRFI 258 (uninterned symbols) is built-in: `string->uninterned-symbol` and `generate-uninterned-symbol` allocate via `GC.allocUninternedSymbol` (gc_alloc.zig), which bypasses the intern table so the result is an ordinary collectable object never `eqv?` to any other symbol; the `Symbol.interned` flag (types.zig) drives `symbol-interned?` and the unreadable `#<uninterned-symbol …>` printer form that `read` rejects. Equality needs no special code (symbols already compare by identity), and `gc_deep_copy` preserves uninterned-ness across SRFI-18 thread boundaries. SRFI 260 (generated symbols) is built-in but needs no engine integration beyond one primitive (`generate-symbol` in `primitives_srfi260.zig`): because Kaappi interns every symbol by name (no uninterned symbols), write/read invariance is automatic, so the primitive just interns a fresh `"<pretty>.<counter>.<128-bit-OS-entropy-hex>"` name — a process-global atomic counter guarantees in-process uniqueness and `platform.osRandomBytes` supplies the unpredictability. SRFI 120 (Timer APIs) is portable (`lib/srfi/120.sld`) with no engine
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
development. **Single calling thread only** is a requirement of this
implementation: its request/reply design assumes it. This header used to
report that a second thread calling into a timer produced nondeterministic
memory corruption, blamed on an un-root-caused interaction between
multi-hop channel messages and cross-thread deep-copy. **That no longer
reproduces** — re-checked 2026-07-31 at v0.22.1, both documented entry
paths fail cleanly and deterministically (10/10 runs) with a catchable
error, because a `<timer>` holds a Fiber and `gc_deep_copy` rejects that
tag as `error.UncopyableType`, making the constraint engine-enforced. The
multi-hop mechanism itself survived ~4,000 nested reply-channel round
trips. Treat single-thread-only as the supported usage, not as a live
corruption hazard; see `lib/srfi/120.sld`'s header for the caveats on
that re-check. SRFI 21 and 230 are excluded — see `docs/dev/srfi-exclusions.md`.
SRFI 237 (R6RS Records, refined) is the one record-system SRFI needing real
engine changes: `RecordType` (`types.zig`) gained `parent`/`own_field_names`/
`own_field_mutable`/`uid`/`sealed`/`is_opaque`/`has_protocol` fields (`parent`
is the only heap pointer, traced in all three `gc_collect.zig` mark-graph
switches; the rest are raw owned bytes like the pre-existing `name` or plain
bools, needing only `objectSize`/`freeObject`/`gc_deep_copy` updates — no
field ever needs a write barrier, since `parent` is set once at allocation
and the one field written afterwards, `has_protocol`, is a bool.
`src/tests_gc_tracing.zig` pins the field inventory at comptime, so adding a
field to any heap struct fails the build until the tracing question has been
answered explicitly), and
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
literal name unconditionally. Library-body use of a shadowing
`define-record-type` (`compiler_lambda.zig`/`vm_library.zig`'s separate
scanning path) was documented here as an un-closed gap; **it works as of
v0.22.1** — a `.sld` body that shadows the name via `define-syntax` binds
the shadowed definition, same as at top level. When testing this, bind a
name that comes from the macro's **pattern**, not one introduced by its
template: a template-introduced name is hygienically renamed, so the
binding is invisible from outside and the test looks like a failure for
an unrelated reason. kaappi#1974 then fixed four R6RS §6.3 deviations in
the procedural/inspection layers, all of them in `lib/srfi/237.sld` rather
than the engine: `record-type-field-names` returns a **vector** (the
`%record-type-field-names` primitive still answers with the list every
internal index walk wants — SRFI 57/131/136/150 call the primitive
directly for that reason, and so does this library); an integer `k` for
`record-accessor`/`record-mutator`/`record-field-mutable?` is
**own-field-relative**, per "note that k cannot be used to specify a field
of any type rtd extends" (it was read as absolute, silently returning an
ancestor's field — and disagreeing with `record-field-mutable?`, whose own
`k` was already own-relative; SRFI 137's payload accessor relied on the
bug and now asks by name, since a subtype there declares zero own fields
and so has no valid `k` at all); `opaque` is enforced (`record?` → `#f`,
`record-rtd` raises, and opacity is inherited from an opaque parent — the
inheritance is folded in at *construction* by
`primitives_srfi237.effectiveOpaque`, shared by both creation paths, so
`RecordType.is_opaque` stays the single already-effective answer); and
`record-mutator` rejects an immutable field. The deprecated
`make-record-constructor-descriptor`/`record-constructor-descriptor?` and
the 7-argument `make-record-descriptor` were added at the same time.
A record descriptor is now accepted **wherever an rtd is expected** (the
SRFI's "the type of record descriptors is a subtype of the type of
record-type descriptors"), and conversely `record-constructor` accepts a
bare rtd — which matters because a syntactic `define-record-type`'s
<record name> evaluates to a simple rtd, not the record descriptor SRFI
237 specifies. A protocol lives on the *descriptor*, so synthesizing a
protocol-less one from an rtd would silently bypass it; instead
`%record-type-constructor` recovers the finished, protocol-applied
constructor the desugarer already bound under its fixed
`__record_ctor_<name>` alias, after checking the sibling
`__record_type_<name>` alias still names *that* rtd (both alias names are
spelled with a leading space, so no source identifier can collide with
them, and both are keyed by type name, so a generative redefinition
rebinds them). When it cannot be
recovered and `RecordType.has_protocol` says there is one, it raises
rather than constructing a wrong record. That combination is what makes
the SRFI's own worked Examples section run — a procedural type inheriting
from a syntactic one whose construction a protocol governs. SRFI 137 (Minimal Unique
Types) is pure portable Scheme built directly on `(srfi 237)`: a "subtype"
is exactly SRFI 237's `parent` relation, with every level correctly
sharing the ROOT type's single payload field (a subtype's own rtd adds
*zero* new fields, inheriting the root's one field via the parent rtd/rcd
chain — an earlier draft gave every level its own field instead, which was
a bug; worth remembering if this file is touched again). SRFI 136
(Extensible record types) demonstrates the CPS-style introspection macro
its spec is built around — `(<type-name>)` yields the type's own rtd,
`(<type-name> (<keyword> <datum>...))` splices that type's own literal
`parent` keyword and field-specs into a call to `<keyword>` — needing no
identifier synthesis at all (it only ever replays syntax already captured
hygienically). SRFI 131 (ERR5RS Record Syntax, reduced) layers on the same
substrate with by-*name* (not positional) constructor field resolution,
including a subtype field shadowing an ancestor's same-named field per its
own spec text. Two portability gotchas surfaced repeatedly while building
these three, and both turned out to be one engine bug, fixed in
kaappi#1831: (1) calling a `%`-prefixed primitive from `(srfi 237
primitives)` with no explicit import looked *unreliably* ambient — it
worked in some positions and not others; (2) calling one `%`-prefixed
forward-referenced global as a direct, non-tail-position argument
expression to another (e.g. inside `if`/`list`, or as an argument nested
one level deep) inside a closure passed to `map` raised a spurious
"undefined variable" for the *inner* call, reliably worked around at the
time by routing through an extra wrapper function (any name) called in
tail position. Both were the same thing: a library body's reference to a
global that lives in vm.globals but not in its own lib_env resolved in
tail position only, because `get_global` carried the vm.globals fallback
and the `call_global` superinstruction the compiler emits for every
non-tail call did not. Ordinary (non-`%`) names looked unaffected only
because `(scheme base)` puts them in lib_env; all three global-reference
opcodes now resolve through one helper in `vm_dispatch.zig`. That fix left
one residual, closed in kaappi#1860: the fallback is gated on
`Function.restricted_globals`, which was derived per-function, so it was
off for the outer function of each library-body form and on for every
closure inside it — the same reference resolved from inside a `lambda` and
raised `undefined variable` as a library-body *top-level* `define`'s
initializer. It is now a property of the environment
(`compiler.EnvKind`, inherited by `Compiler.initChild`), which also stops
a restricted `(environment ...)` from leaking vm.globals through a
closure. Declaring the import explicitly is still the better style, but it
is no longer load-bearing.
SRFI 57 (Records, with inheritance via "schemes" -- a named, reusable field-
label list a type or another scheme can extend, with multiple schemes
mergeable at once via left-to-right append + delete-duplicates) is portable
(`lib/srfi/57.sld`) but deliberately does NOT port its own reference
implementation's technique: that reference compares field-label identifiers
at macro-expansion time via the standard `let-syntax`-plus-literals-list
"if-free=?" trick. A third expander bug surfaced while attempting this
port: a `let-syntax` anywhere in an expansion chain that eventually
produced a `define-syntax` form failed to compile outright, reproduced
down to a two-line `(let-syntax (...) (define-syntax ...))`. **That is
fixed as of v0.22.1** — the two-line repro compiles and runs. SRFI 57's
design below was chosen while it was live and has not been revisited;
it remains the better design on its own merits (see the end of this
paragraph), so this note is history, not a TODO. SRFI 57 sidesteps it:
field labels become ordinary
quoted symbols and every list merge/dedup/lookup happens at plain run time
(`assq`/`memq` over symbol lists) instead of macro-expansion time — a
scheme or type name is bound with plain `define` (not `define-syntax`) to a
`(field-symbols rtd-or-#f ancestor-schemes)` list, with no CPS introspection
macro and no identifier comparison anywhere in the file. This is simpler
than the reference design, not merely an engine-avoidance workaround, and
completes issue #1695 (all 9 of its SRFIs now shipped or excluded). Scheme
conformance is NOMINAL, not structural: a record's actual rtd carries no
field for this library's own scheme metadata, so a type's declared ancestry
(computed once, transitively, at `define-record-type` time) lives in a side
table keyed by rtd (`%srfi57-registry`) — an earlier structural draft ("does
the record's actual rtd merely have every field the scheme needs") let any
same-shaped-but-undeclared type pass every scheme predicate/accessor and
`record-update`/`record-compose` target check, caught by a second review
pass. `record-update`/`record-update!`/`record-compose` all validate their
target/import/export type-or-scheme and field-label arguments at call time
(not the spec's stated expansion time — these are ordinary values, not
macros, so their identity isn't knowable until the code runs); this and the
missing labeled-record-expression syntax (`(type-name (label expr)...)`,
which would need every type/scheme name to be a macro instead) are the
remaining documented, deliberate scope reductions. The same review pass
also found a real, severe, PRE-EXISTING bug in `vm_records.zig` unrelated
to SRFI 57 itself: 8 places (4 already present in the R7RS
`handleDefineRecordType`, 4 new in this slice's R6RS path) paired
`no_collect += 1; errdefer no_collect -= 1;` with a manual mid-block
`no_collect -= 1` followed by *more* fallible operations still inside the
`errdefer`'s scope — a late failure double-decremented the counter,
underflowing a `u32` and permanently disabling GC for the rest of the
process. Fixed everywhere by deleting the manual mid-block decrement and
using a single unconditional `defer` instead (the pattern
`gc_deep_copy.zig` already used correctly) — this bug class (`errdefer X -=
1` plus a later, unguarded `X -= 1` of the same reentrancy counter) is
worth grepping for if `no_collect`-style guards are touched again elsewhere.
SRFI 192 (port positioning) is built-in: `port-position`/`set-port-position!`/`port-has-port-position?`/`port-has-set-port-position!?` in `primitives_io.zig` use plain exact-integer byte offsets for every port kind (string ports already track their own position for free; fd-backed ports get a new `platform.seek` — POSIX `lseek`, Windows `_lseeki64`, WASI `fd_seek`, which needs its own `whence_t` enum) with the OS's raw offset corrected for whatever this port's own software buffers have read ahead of or not yet flushed behind; the spec's opaque textual-port position objects and its dedicated `i/o-invalid-position-error` condition type are not implemented. SRFI 181 (custom ports and transcoded ports) is portable (`lib/srfi/181.sld`) over a native primitives sub-library, `(srfi 181 primitives)` (`.srfi_181_primitives` in `primitives.zig`, `primitives_srfi181.zig`) — the same registry-shadows-a-same-named-.sld problem SRFI 248 hit first (see below): `(srfi 181)` had to move off a direct registry entry once transcoded ports needed a real `.sld` to live in. Custom ports (5 `make-custom-*-port` constructors plus `make-file-error`) landed first, in Phase 3 (#1727); transcoded ports (`make-transcoder`, `native-transcoder`, codecs, eol-styles, the `raise` error-handling mode) followed in their own follow-up (#1729) once #1727 shipped. A custom port's read!/write!/get-position/set-position!/close/flush procedures are the first Value-bearing fields `Port` has ever had (`Port.custom_backend: ?*CustomBacking`, `types.zig`) — traced by a shared `markPortValues` helper wired into all three `gc_collect.zig` marking switches plus the two dedicated (non-catch-all) `freeObject`/`objectSize` arms (gc_sweep.zig), since neither has an exhaustiveness check to catch a forgotten site. Every callback runs through `vm.callWithArgs`, which always executes with `vm.dispatched_from_scheduler` forced false; a callback that tries to block (another port's I/O, `thread-sleep!`) is rejected with a catchable error via a dedicated `vm.in_custom_port_callback` counter (checked in `fiber.waitForFd` and `primitives_srfi18.threadSleepFn`) rather than risking the native-stack-overflow a silent recursive scheduler drive would otherwise allow — custom port callbacks must be effectively synchronous, non-blocking code. Both `readOneByte` and `portWriteBytes` (the single byte source/sink every port primitive already funnels through) gained a custom-port branch exploiting that Kaappi strings are already UTF-8 byte arrays internally: a textual read!'s returned character count converts to a byte offset via `utf8IndexToByteOffset` on the buffer's freshly re-read `data`/`len` (never cached across the call — a differing-byte-width `string-set!` inside the callback reallocates the whole backing buffer in place, `primitives_string.stringSetFn`). Transcoded ports layer a second Value-bearing field, `Port.transcode: ?*TranscodeState` (its own marking/freeing arms alongside `custom_backend`'s in `gc_collect.zig`; `TranscodeState` holds just `wrapped_port: Value` plus plain `Codec`/`EolStyle`/`ErrorMode` enums, no other GC-traced fields). `readOneByte`/`portWriteBytes` gained a `transcode` branch that decodes/encodes exactly one character per call, never a batch: a fiber park reruns the whole native call from scratch, so any Zig-local "progress so far" would be silently lost, while a durable `*Port` field survives the retry — CRLF lookahead therefore reuses the wrapped port's own `peek_byte`/`peek_extra`, the same mechanism `read-line`'s own CR/CRLF handling already relies on, instead of a new field. The `raise` error-handling mode needed a mechanism custom ports' callbacks never required: `primitives_control.raiseContinuable` (factored out of `raise-continuable`'s own native implementation) signals a continuable `.io_decoding`/`.io_encoding` `ErrorObject` and resumes decoding from the next byte once the handler returns — safely, because a reentrant `vm.callHandler`/`runUntil` always runs with `dispatched_from_scheduler` forced false, so it can only block in place if the handler itself blocks, never return `Yielded` and retry the whole call (which would re-invoke the handler a second time for the same condition). v1 supports only the UTF-8 codec — `latin-1-codec`/`utf-16-codec` are not exported at all, rather than exported-but-always-erroring, since no other binding in Kaappi exists solely to fail — and `native-transcoder` returns UTF-8/`'none`/`'replace`, matching `read-char`'s existing no-translation, never-raise-on-invalid-UTF-8 behavior as closely as a brand-new feature reasonably can. Codecs/eol-styles/error-modes are plain symbols and the transcoder itself is a portable `define-record-type` (`lib/srfi/181.sld`), so native code never touches record internals — only the differently-named `%transcoded-port` primitive does, receiving the transcoder's already-unpacked codec/eol-style/error-mode symbols and validating them there (`make-transcoder` itself does not validate eagerly; codecs are untyped symbols, so there is no earlier point to enforce it). SRFI 267 (raw string syntax) is a hybrid: its `#"X"…"X"` lexical syntax is built into the reader (`readRawString` in `reader_tokens.zig`), while its port procedures load from the `.sld`. SRFI 248 (minimal delimited continuations) is also a hybrid: `with-unwind-handler`, `empty-continuation?`, and the extended two-variable `guard` live in `lib/srfi/248.sld` as a Filinski shift/reset over `call/cc`, built on three VM primitives (`%call-with-unwind-handler`, `%unwind-raise-empty?`, `%pop-unwind-handler!` in `primitives_control.zig`) exported by the built-in sub-library `(srfi 248 primitives)`. The enabling VM change is a *sticky* exception handler (`ExceptionHandler.sticky`): `raise`/`raise-continuable` invoke it in place without popping, so a `call/cc` snapshot taken while it handles includes it and resuming re-arms the prompt (reset0 semantics) — the delimiter must stay file-only because the registry shadows a same-named `.sld`. `empty-continuation?` combines a VM tail-call latch (`native_call_was_tail`, set by every tail-call opcode in `vm_dispatch.zig`) with the sticky handler's frame_count baseline, so a raise in tail position of a non-tail-called helper is correctly non-empty. Delimited continuations are single-shot (a resume crosses the sticky-handler native frame, the same limit as continuations captured under native drivers). SRFI 261 (portable SRFI library references) is a resolver-level convention with no library file: `(srfi srfi-<n>)` and `(srfi <mnemonic>-<n>)` (e.g. `(srfi lists-1)`, `(srfi vectors-133)`) resolve to `(srfi <n>)` as a fallback — literal registry/file names win, sub-library tails pass through, and the trailing number alone is authoritative (mnemonics are not validated). Implemented in `vm_library.zig` (`srfi261FormNumber`/`normalizeSrfiLibName` in `processImportSet`; `libraryIsAvailableSrfi261` behind both cond-expand `(library …)` entry points) and mirrored path-level in `test_selection.zig` so `kaappi test --changed` keeps the dep edge. Every supported SRFI is also a `cond-expand` feature identifier `srfi-<n>` (#1649): `(cond-expand (srfi-1 …) …)`. These are derived, never listed — `srfiFeatureAvailable` in `vm_library.zig` routes `srfi-<n>` through the same availability check as `(library (srfi <n>))`, so built-in, portable, `--sandbox` and WASM answers all match what `(import (srfi <n>))` would do. Both feature-req evaluators consult it: `evalLibFeatureReq` (inside `define-library`) directly, and the compiler's `evalFeatureReq` via the `globals.srfiFeatureAvailable` callback the VM registers (mirroring the `library_exists_checker` used by the `(library …)` form). SRFI 261 is the one supported SRFI with no `.sld`, so `srfi-261` answers true directly. Like `(library …)` requirements, `srfi-<n>` is a derived probe, not a bare feature, so `(features)` (and the `kaappi features` table it must equal, #1517) stays platform-only; `kaappi features` still notes the ids in its SRFIs section. SRFI 160 (homogeneous numeric vector libraries) is a hybrid, and the vector-family half of issue #1694 (the array-family's own SRFI 231 has since shipped too — issue #1694 is fully closed — and 58 stays excluded; see the "Of the 208 final SRFIs" paragraph above for how the family actually splits, which is not the three-mutually-incompatible-lineages shape originally assumed when #1694 was filed): one native heap type, `types.NumericVector` (`types.zig`), discriminated by an 11-way `NumericElementKind` enum (s8/u16/s16/u32/s32/u64/s64/f32/f64/c64/c128) covers every element kind except u8, which stays a plain R7RS bytevector per the SRFI's own recommendation (and because the pre-existing SRFI 4 port already relies on `(bytevector? (make-u8vector 5))` staying `#t`) — the same one-heap-type-with-discriminator pattern as SRFI 237's `RecordType` extension, avoiding 11x duplication of GC touch points. c64/c128 (complex) elements are stored as two consecutive f32s or f64s (real, imag) packed contiguously in the raw byte buffer, decoded into a real Kaappi `Complex` only at the `%numeric-vector-ref`/`-set!` boundary; multi-byte elements use host-native byte order (`builtin.cpu.arch.endian()`), since there is no reader syntax to round-trip and no cross-process persistence. Six generic `%`-prefixed primitives in `primitives_srfi160.zig` (registered under `.srfi_160_primitives`, the same registry-shadows-a-same-named-.sld precedent as `.srfi_237_primitives`) — create/predicate/kind/length/ref/set! — are the *entire* native surface; every named procedure (the SRFI-4-shaped 9-procedure core per type, plus SRFI 160's much larger SRFI-133-shaped extended surface — map/fold/filter/unfold/copy!/append/generator/comparator/etc.) is portable Scheme in `lib/srfi/160/base.sld` + one `lib/srfi/160/<tag>.sld` per type. The extended surface is written *once*, generically, in `(srfi 160 base)`: low-level dispatch helpers (`%uvec-ref`/`%uvec-set!`/`%uvec-length`/`%uvec-make`) branch on `bytevector?` vs. `%numeric-vector?`, so the same ~25 generic procedure bodies serve all 12 kinds including u8 — each per-type library just renames the kind-agnostic ones (fold, for-each, index, swap!, ...) directly and wraps the kind-constructing ones (map, copy, filter, unfold, ...) in a one-line closure fixing that type's kind symbol via R7RS's `(import (rename (srfi 160 base) (old new) ...))`, which (per `vm_library.zig`'s `processImportRename`) imports *everything* from the wrapped library with only the listed pairs renamed — not just the renamed subset — so the per-type file's own kind-closing wrappers can call the unrenamed generics directly without a second import clause. `(srfi 4)` is now a thin re-export over `(srfi 160 <tag>)` for the 8 non-complex-non-160-only names (fixing a real bug the old wrapped-vector implementation had: f32vector didn't actually truncate to 32-bit precision). SRFI 66 (octet vectors) and SRFI 74 (octet-addressed binary blocks, "blobs") are both u8vector/bytevector aliases needing zero heap-type work: SRFI 66 re-exports `(srfi 160 u8)`'s core plus new logic for `u8vector-copy!`'s different argument order and `u8vector=?`/`u8vector-compare`; SRFI 74's blobs are bytevectors, with `blob-uint-ref`/`-set!` et al. implemented as byte-at-a-time Horner assembly (floats are explicitly out of SRFI 74's own scope). `(endianness native)` is the one place either SRFI needed a genuinely new primitive: `%host-big-endian?` (`primitives_r7rs.zig`, wrapping `builtin.cpu.arch.endian()`) — a portable implementation has no other way to learn real hardware byte order, and this SRFI's native-tagged accessors exist specifically for interop with externally-produced binary data, so assuming little-endian would be silently wrong on kaappi's own s390x/ppc64le targets. SRFI 25 (multi-dimensional array primitives), the first piece of #1694's array family, is pure portable Scheme (`lib/srfi/25.sld`) needing no engine work at all: arrays are spec-defined as heterogeneous (arbitrary Scheme objects, no relationship to SRFI 4/160's numeric vectors), so a `define-record-type` wrapping a plain vector is spec-sufficient. A shape is a vector of `(lower . upper)` pairs (deliberately not made to satisfy `array?` itself — the spec's own "a shape is a d-by-2 array" framing is Rationale prose never operationally exercised by any of the 10 mandated procedures, since there is no `shape?` and no way to recover a shape back from an array). The one array record type covers both "simple" arrays (a row-major-ordered backing vector) and `share-array`'s affine views (a base array plus an index-translation `mapper`, no backing vector of its own): `array-ref`/`array-set!` on a view translate the requested index through `mapper` and recurse into the *base array's own* ref/set! rather than poking its raw vector directly, so arbitrarily nested views (a view of a view of a view) compose correctly for both reads and writes at the cost of one extra call per nesting level — the spec's rationale for requiring `mapper` to be affine is that composed affine maps *could* be collapsed to O(1), but this is a documented optimization opportunity, not a conformance requirement, and recursive delegation was the simpler, fully-conformant choice. The one point in the spec genuinely left ambiguous by its prose alone — whether `share-array`'s `mapper` receives/returns indices as separate arguments or a packed list/vector — was resolved by fetching the spec's own worked example (a diagonal-view identity-matrix construction using `(lambda (k) (values k k))`): `mapper` takes the new array's indices as separate variadic arguments and returns the base array's coordinates via multiple values, exactly mirroring `array-ref`/`array-set!`'s own variadic calling convention; that identity-matrix example is now a verbatim regression test. `array-ref`/`array-set!` also accept a single packed index that is a vector or a 0-based 1-dimensional array (dispatched by argument count and type), and `array-set!`'s new-value argument is the *last* argument after all indices — the opposite convention from SRFI 47/63, which is the documented reason those two lineages don't compose (see the "Of the 208 final SRFIs" paragraph above). SRFI 164 (enhanced multi-dimensional arrays), the second piece, is a documented, compatible *extension* of SRFI 25 (identical shape representation, `share-array` copied from 25's spec text verbatim) implemented as its own independent library (`lib/srfi/164.sld`) rather than by importing `(srfi 25)`, since `define-record-type` field accessors don't cross library boundaries and this SRFI's array needs a third mode SRFI 25's record has no room for. One record covers three modes: "simple" (own row-major vector, same as 25), "shared/view" (base array + index-translation `mapper`, same recursive-delegation design as 25's `share-array`), and "virtual" (a `getter`/optional-`setter` pair, no backing storage at all — backs `build-array`, `index-array`, and `array-index-ref`'s non-scalar case). `array-transform`'s `transform` argument uses a *different* calling convention than `share-array`'s `mapper` per the spec's own explicit contrast (one vector argument in, one vector out, vs. separate variadic arguments and multiple values) — adapted with a one-line wrapper into the shared/view mode's own convention, which works unmodified for a non-affine `transform` since this codebase's `share-array` never checked or exploited affineness in the first place. `array-index-ref`/`array-index-share` (APL-style generalized indexing, where each of an array's per-dimension indices is either an integer or an array) share one resolver (`%index-shape-parts`/`%index-take`) computing the concatenated result shape and an index-splitting closure; both were written as flat, separately-named top-level helpers rather than nested internal defines after a deeply-nested first draft produced a mis-balanced closing-paren count that silently ate several nesting levels (`kaappi check` catches this class of bug immediately — always run it on a new portable library before executing it). A second, subtler bug from that same draft: the resolver closure was defined with a rest parameter (`(lambda new-indices ...)`) but every call site passed an *already-built* list as a single argument (`(resolver new-indices)`), silently wrapping it one list-level too deep and producing wrong-looking "index out of range" errors far from the actual mistake — fixed by making the resolver take one fixed parameter instead of a rest parameter, since none of its callers were ever splatting separate arguments into it. `array-reshape` aliases the source's backing vector directly when the source is simple (per spec: "uses the same underlying vector as array") but falls back to a shared/view array with a row-major-rank-based recompute (`%row-major-offset` composed with its own inverse, `%unrank`) when the source is not simple — this recompute is not affine, which the shared/view mode's own lack of an affineness check already makes safe. `array->vector` returns the live backing vector for a simple array (true zero-copy identity) but only a disconnected snapshot copy for a non-simple one — the spec calls for a live view there too, which a literal R7RS vector cannot provide in portable Scheme (vectors have no hooks, unlike this codebase's custom ports) — a deliberate, documented scope reduction, unlike `array-flatten`, which the spec itself mandates as always a fresh copy regardless of source mode. SRFI 63 (homogeneous and heterogeneous arrays), the third piece of #1694's array family, supersedes SRFI 47 outright (47's own page says so; see `docs/dev/srfi-exclusions.md`), so only 63 is implemented (`lib/srfi/63.sld`) — confirmed incompatible with SRFI 25/164 by both SRFIs' own Issues sections: `array-set!`'s new-value argument is *second* here (right after `array`, before any indices), the opposite of 25/164's value-last convention, and `make-array`'s first argument is a *prototype* (a type/fill-value carrier — an array, vector, string, or one of 20 dedicated type-tag generator procedures like `A:fixZ8b`/`A:floC128b`, confirmed against the spec's own list), not a bounds-shape object; every dimension is a plain zero-based size, with no arbitrary lower bounds and no shape object at all. The one `<uarray>` record covers two modes: "simple" (a `kind` symbol dispatches, via a small table built once at load time, to the accessor closures for that element type) and "shared" (a base array plus an index-translating `mapper`, the same recursive-delegation design as 25/164 — translate through `mapper`, then recurse into the *base array's own* ref/set!, so nested views compose correctly for both reads and writes regardless of rank change). 12 of the 20 prototype kinds reuse this codebase's own already-shipped `(srfi 160 <tag>)` procedure sets (or a plain bytevector for the 8-bit unsigned case, matching u8's treatment throughout this codebase) as the backing store, getting every homogeneous-type conversion error (non-integer into a fixed-width slot, negative into unsigned, too-large, inexact into exact, non-real into a real-float slot) for free with zero new validation code; the remaining 8 kinds (16- and 128-bit floats, 16- and 32-bit complex, all 3 decimal-float widths) have no Kaappi-native representation, so they fall back to a plain, unchecked vector — a fallback the spec itself sanctions ("resorting finally to vector") rather than a shortcut, since even the reference implementation calls the decimal-float conversion rules "yet to be determined." `make-shared-array`'s `mapper` takes the new array's indices as separate variadic arguments (matching this codebase's other array SRFIs) but — confirmed from the spec's own worked diagonal-view and offset-view examples — *returns a list* of old-array coordinates, not multiple values like 25/164's `share-array`/`array-transform`; this is the one genuinely easy-to-get-backwards detail in the whole SRFI, so it got its own explicit, never-assumed-to-match adapter. `equal?` is a real library-level override (array-augmented R5RS `equal?`): the library imports `(scheme base)`'s `equal?` under a rename, defines its own that delegates to the original for the non-array case, and exports the override — verified directly (a throwaway test library) that this shadows `equal?` only for code that imports it from `(srfi 63)`, with ordinary R7RS import-collision rules applying otherwise, so no engine change was needed. `list->array`/`array->list` and `vector->array`/`array->vector` turned out to need two genuinely different algorithms, not one shared "row-major fill" — confirmed by fetching the spec's own examples rather than assumed: `list->array rank proto list` takes a **rank-nested** list (dimensions inferred from nesting depth and sublist lengths, e.g. a list of 2 sublists of 2 elements each infers `(2 2)`) with `array->list` as its exact nested-output inverse, while `vector->array vect proto dim1 ...` takes a **flat** vector plus **explicit** dimension arguments, like `make-array` — the two pairs are not interchangeable despite looking parallel at first glance. SRFI 231 (intervals and generalized arrays), the fourth and final piece of #1694's array family, is a genuinely unrelated redesign from 25/164/63 (no textual relationship, per its own spec) shipped across 6 phases (issues tracked under #1694; `lib/srfi/231/{misc,intervals,storage-classes,arrays,views,combinators,assembly}.sld`, merged into a public `lib/srfi/231.sld` re-export hub — 118 bindings total, an exact bijection confirmed against the reference implementation's own export clause) — the largest single SRFI in this codebase by an order of magnitude. An `<interval>` is two parallel exact-integer vectors (lower/upper bounds, arbitrary — including negative — per axis), not 25/164's shape-of-pairs nor 63's bare sizes. The array hierarchy is genuinely three-tier (`array?` ⊃ `mutable-array?` ⊃ `specialized-array?`), all one record (`domain`/`getter`/`setter`/`body`/`indexer`/`storage-class`/`safe?`, with mode-specific fields `#f` on a plain array) rather than 25/164's simple/shared/virtual union — confirmed as a genuine hybrid of prior conventions on two independent axes: `array?` is disjoint from vector/string (matching 25/164, not 63), while `array-set!`'s new-value argument is *second*, right after the array (matching 63, not 25/164's value-last). A storage class (17 singletons — 14 real, 3 deferred to `#f`: `u1`/`f8`/`f16` — plus `make-storage-class` for custom ones) is a 9-field record (getter/setter/checker/maker/copier/length/default/data?/data->body) that a specialized array's `body`/`indexer` pair delegates to for the actual backing-store representation. The single most-reused implementation pattern across the views/combinators/assembly phases: build a lazy virtual array via `make-array` with a computed getter over the target domain, then delegate to `array-copy` (which already owns all storage-class/mutable?/safe? option parsing and the materializing fill loop) rather than hand-rolling a fill mechanism per procedure — used for `array-stack`, `array-decurry`, `array-append`, `array-block`, and more. Their `!` twins are confirmed-safe pure aliases (verified by reading the reference implementation: both entry points wrap one shared helper differing only in whether inputs are eagerly pre-materialized before the fill, a distinction observable only under multi-shot-continuation re-entry, which the spec itself declares undefined). `specialized-array-reshape` uses a deliberate packed-check-based affine-detection simplification instead of the reference's full multi-group algorithm, verified identical on the spec's own worked examples. `array-block` needed a genuinely two-phase algorithm unlike everything else in the SRFI: full per-axis width-consistency validation (reusing `array-curry`+`array-permute`+`index-first`) followed by cheap single-pencil-probing for offsets (reusing `array-curry`+`array-permute`+`index-last`), both confirmed against the reference implementation. The SRFI's own prose pseudocode disagreed with its reference implementation at least twice (`check-nested-list`'s dimension-0 case returns `'()`, not the prose's nonsensical `#t`; `array-inner-product`'s prose omits a required `array-curry` argument the reference code supplies) — confirming "when this SRFI's prose and its reference implementation disagree, trust the code" as a load-bearing rule for this SRFI specifically. `array-extract`-derived views preserve **absolute** source coordinates, never resetting to 0-based, per the spec's own worked example. SRFI 231 supersedes SRFI 179 (its own abstract: "a revised and improved version of SRFI 179") with acknowledged breaking changes, not a strict superset — see `docs/dev/srfi-exclusions.md` for specifics; 179 is excluded on that basis.

The library loader in `vm_library.zig` supports `cond-expand`, `include` (paths resolved relative to the .sld file), and `(export (rename ...))` in `define-library`. Macro transformers defined with `define-syntax` in library `begin` blocks are exported and imported correctly.

Of the 208 final SRFIs in the registry, 178 are implemented and 30 are
excluded — see `docs/dev/srfi-exclusions.md` for the full rationale. Issue #1699
("Implement SRFI macro & syntax extension libraries") is now fully
closed: 139 and 149 needed no engine changes and shipped directly, 147
(custom macro transformers) needed one, 148 (eager syntax-rules) — the
group's hardest portable case — shipped over 147's mechanism once six
separate engine bugs it surfaced were fixed, 211 and 213 shipped last on
the procedural-transformer mechanism (see their own paragraph below), and
72 was excluded: the issue table's "explicit renaming macros" note was a
mislabel — SRFI 72 is van Tonder's *replacement* macro system (evaluated
transformer expressions over syntax objects, a novel hygiene rule,
begin-for-syntax phasing), incompatible with R7RS's structural
transformer-spec grammar and this symbol-based expander, while the ER
facility actually wanted is exactly `(srfi 211 explicit-renaming)`.
SRFI 150 (Hygienic ERR5RS Record Syntax, issue #1810) was retired from
`docs/dev/srfi-exclusions.md` once its own stated blockers (SRFI 147 and
148) shipped, and needed three implementation attempts to land. It
extends SRFI 131 (`lib/srfi/131.sld`, its shared runtime substrate) with
hygienic field-name matching, non-identifier field names, and accessor-
name field references in constructor specs. The first two attempts —
porting the reference's own SRFI 137 `make-subtype` closures directly,
then a from-scratch rewrite using a `:secret`-style descriptor macro over
SRFI 237 — both used the same general shape (a child type's expansion
queries a parent macro's own protocol for its record-type-descriptor via
a nested macro call) and both broke once more than one such query
relationship existed side by side in the same program, isolated to two
apparent `em-syntax-rules` engine bugs along the way (kaappi#1828 and
kaappi#1829 — both since determined NOT to be engine bugs). kaappi#1829
turned out not to be an expander bug of its own at all: because the CK
machine builds its output as plain data, a macro-generated top-level
`define` lands under its BARE name, so the next expansion's own reference
to it was a free reference to an already-bound non-procedure global —
exactly the referential-transparency collision of kaappi#1832, which
kaappi#1839's hygiene rename closed for both;
`tests/scheme/hygiene/macro-fresh-global-readback-1829.scm` guards that
shape directly. kaappi#1828 also turned out not to be an engine bug: its
own repro's final (non-`=>`) template was left unquoted while calling an
ordinary procedure, which SRFI 148's own spec documents as an error case,
unrelated to the "bound variable as a later step's operator" framing it
was filed under — `lib/srfi/148.sld`'s header and
`tests/scheme/hygiene/em-syntax-rules-operator-chain-1828.scm` confirm the
operator-position mechanism itself works correctly, including 3 levels of
chaining. Whether the two rejected attempts above would have succeeded
without this same misunderstanding is not re-tested. The third, shipped
design avoids the whole query-macro pattern regardless, so it is unaffected
either way: the type name is bound directly to an ordinary runtime record-type-
descriptor exactly as in SRFI 131 (inheritance and field/accessor/
mutator resolution, including multi-level shadowing, handled entirely at
run time by SRFI 237's own by-name introspection), and the one piece
SRFI 131 doesn't have — hygienic field/accessor-name matching for named
constructor specs — uses SRFI 213 (identifier properties) instead of a
query macro: each `define-record-type` use attaches its own field/
accessor-name pairs to the type name via `define-property`, a child
reads its parent's via `lookup`, and `lookup` is only reachable from a
procedural transformer, so `define-record-type` itself is a SRFI 211
`er-macro-transformer` rather than an `em-syntax-rules` macro. Since this
engine represents every identifier as a plain, hygiene-renamed symbol,
plain `equal?` on that raw symbol already implements both
bound-identifier=? and free-identifier=? for SRFI 213's stored names —
specific to this engine's rename-by-spelling hygiene representation, not
a portable assumption. This design surfaced the library global-resolution
bug fixed in kaappi#1831, which first presented as `cadar` specifically —
not `caar`/`cadr`/`cddr`, and not its own unrolled spelling
`(cadr (car x))` — failing when called from a helper function invoked
during an `er-macro-transformer`'s expansion. The `cadar` framing was a
red herring on two counts: `cadar` is a `(scheme cxr)` name
`lib/srfi/150.sld` never imports while its apparent siblings there are
`(scheme base)` names already in lib_env, and the file's one other
cxr-only name (`cdddr`) sits inside the transformer's own lambda, which
is evaluated at macro-definition time in the global environment and so
never consults lib_env at all. The real rule was tail vs. non-tail
position (see the SRFI 237 paragraph above); the idiomatic `cadar`
spelling is back in `field-alist-ref`. SRFI 150 ships with one
documented, unfixed gap rather than blocking on an engine fix: 21 of 25
tests ported from the reference suite pass; the other 4 (two "Hygiene 1"
assertions, one "Hygiene 2" assertion, and Alex Shinn's
explicit-construction tuple
example, marked `test-expect-fail`/annotated in
`tests/scheme/srfi/srfi150.scm`) hit a precise, minimal, record-free
reproduction (kaappi#1832) of the already-documented "a use-site
top-level redefinition of a referenced name reaches the expansion"
limitation noted in the SRFI 211 paragraph below — a `syntax-rules`
template's own field-name literal can lose its hygienic rename on one of
two internal re-expansions specifically when it collides in spelling
with a pre-existing top-level binding, which is exactly the adversarial
case SRFI 150's own hygiene tests are designed to probe. Issue #1694 (the
numeric-vector and array family) is now fully closed: the vector-family
subset — 4 (already shipped pre-Phase-4, just undocumented until Phase 4
Slice 4), 160, 66, 74 — shipped in Phase 4 Slice 4 on one shared native
substrate (`types.NumericVector`); the array family — 25 (Slice 5), 164
(Slice 6), 63 (Slice 7, with 47 excluded as superseded), and finally 231
(Slices 8–13, 118 bindings across 6 phases: misc+intervals, storage
classes, core array object, views/sharing/reshaping, bulk
combinators/conversions, multi-array assembly — a three-tier
array/mutable-array/specialized-array model with no textual relationship
to 25/164/63 at all, merged into a public `lib/srfi/231.sld` re-export hub
in the final step, which also moved SRFI 179 from tracked to excluded as
231's own designated, if not fully backward-compatible, successor) — is
fully shipped too, leaving only SRFI 58's reader/writer array-literal
syntax excluded (its stated blocker — no typed array infrastructure to
build on — no longer holds at all now that SRFI 4/160/25/164/63/231 exist,
worth re-examining if 58 is ever picked up). #1695 was fully closed
earlier in Phase 4: 57/131/136/137/237/240 shipped, 99/100/150
excluded. #1699 (minus what Phases 1–3 closed) and #1729, which completed
SRFI 181's transcoded-port half — custom ports landed separately in
Phase 3, #1727 — plus issues #1703 and #1702, were all closed in full in
Phase 4 as well.
`docs/dev/srfi-exclusions.md`'s 30 excluded break down as: 7 meta/ecosystem SRFIs
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
specifically 99's syntax-rules-expressible reduced subset; and 72, a
complete replacement macro system (arbitrary transformer expressions
evaluated at expansion time over a syntax-object type with its own hygiene
rule and phase tower) incompatible with R7RS's structural transformer-spec
grammar and this symbol-based expander (150, formerly this group's sixth
member, moved back to tracked — issue #1810 — once its stated blockers
SRFI 147+148 shipped) — 1 SRFI — 208 — whose own spec text states the same
about raw NaN bit-pattern access, which Kaappi's NaN-boxing value
representation makes categorically unrepresentable, 1 SRFI — 106 — redundant
with the `kaappi-net` ecosystem package's existing, broader-scoped socket
support, 2 concurrency-model-incompatible SRFIs — 21 and 230 — which need
a userspace-scheduled thread model and cross-heap shared mutable memory
(respectively) that Kaappi's OS-native-thread,
independent-heap-per-thread SRFI-18 doesn't have, and 2 SRFIs — 47 and
179 — superseded outright by their respective successors: 47's own page
states the supersession by SRFI 63 directly, with 63's procedure set a
strict superset of 47's with identical signatures throughout; 179's
successor SRFI 231 states in its own abstract "This is a revised and
improved version of SRFI 179," though — unlike 47/63 — it is a breaking
revision, not a strict superset (see `docs/dev/srfi-exclusions.md` for
the specific incompatibilities).

SRFI 139 (syntax parameters) is the first piece of issue #1699 (SRFI
macro & syntax extension libraries) to ship, and turned out to need no
engine work at all despite being grouped with 6 SRFIs that do: `let-syntax`
(`compileLetSyntax`, `compiler_define_syntax.zig`) already implements exactly
`syntax-parameterize`'s own semantics — adjust the live macro table for a
bounded compile extent, then restore it — so `lib/srfi/139.sld` is a
2-form, 6-line library (`define-syntax-parameter` → `define-syntax`,
`syntax-parameterize` → `let-syntax`), verified against both of the
spec's own worked examples (`forever`/`abort`, `lambda^`/`return`) plus 2
adversarial cases: nested `syntax-parameterize` of the same keyword (the
inner extent's transformer must not leak past its own scope once it
exits) and a body-local variable sharing a name with the macro's own
internal continuation identifier (must not be captured) — both passed
without any implementation changes, confirming the mechanism generalizes
correctly rather than only working for the two examples it was designed
around.

SRFI 149 (basic syntax-rules template extensions) is the second piece of
issue #1699 to ship without engine changes. Its two extensions — consecutive
ellipses directly after one template element (`a ... ...`, which R7RS's
own stricter grammar requires extra parens for instead) and letting a
pattern variable be followed by MORE ellipses in the template than its own
pattern-matched depth, with the excess replicating a shallower sibling at
the innermost position — are both already correct in the
expander's existing `instantiateEllipsis` (expander_instantiate.zig). The spec's own prose gives no worked
example for the genuinely-new nonzero-depth-excess case, so this needed
fetching the reference implementation's `expand-template` algorithm (a
`map` plus `depth-1` applications of `apply append`, driven by a
free-variables-at-this-dimension scan) to understand precisely what
"innermost" means, then confirming Kaappi's binding-driven design (live
per-binding depth reduction, rather than a static free-variable scan)
produces the identical result: a shallower sibling, already reduced to a
scalar by an earlier ellipsis level, is naturally held constant when a
deeper sibling drives further iteration — which *is* innermost-replication,
arrived at by a different mechanism. Verified against both of the spec's
own worked examples (`my-append`'s consecutive flatten; `foo`'s mixed-depth
`a`/`b` siblings) plus 2 more. `lib/srfi/149.sld` is a trivial
`(export syntax-rules)` re-export, the same shape as SRFI 46's own "these
R7RS extensions are already native" library. One pre-existing, unrelated
gap found and deliberately left alone: an ellipsis with no driving
variable at all (e.g. a lone variable asked for more ellipses than its own
maximum depth) silently produces an empty result instead of erroring —
predates this SRFI, isn't a case it needs to support, and fixing the
underlying leniency is a separate, ecosystem-wide-blast-radius project of
its own.

SRFI 147 (custom macro transformers) is the third piece of issue #1699 to
ship, and the first that genuinely needed an engine change: R7RS's
`<transformer spec>` only accepts a literal `(syntax-rules ...)` form,
and 147 extends it to also accept a macro use that itself expands
(possibly through several steps) to one -- letting a library define its
own transformer-generating-transformer, e.g. the spec's own worked
example, a `syntax-rules*` that auto-wraps multi-form templates in
`begin`. `compileDefineSyntax`/`compileLetSyntax`/`compileLetrecSyntax`
(`compiler_define_syntax.zig`) now route every transformer-spec through a new
`resolveTransformerSpec`, which expands a non-literal spec via the same
`expander.expandMacro` every ordinary macro call already goes through,
looping (depth-bounded) until it bottoms out at a literal `syntax-rules`
form. The grammar's other two new alternatives -- a bare keyword aliasing
an existing one, and a macro use expanding to `(begin <definition>...
<transformer-spec>)` -- were initially deferred as unneeded by SRFI 148
(the reason 147 was implemented), then shipped in a same-week follow-up
once tracing SRFI 148's actual reference implementation (not just its
spec prose) showed its core `em-syntax-rules-aux1`/`em-syntax-rules-aux2`
mechanism bottoms out through exactly `(begin (define-syntax a spec) a)`
-- a helper definition followed by a bare reference to it, needing both
alternatives together. `resolveTransformerSpecRec`'s contract changed
accordingly: it now returns an already-parsed `Transformer` (not raw
`syntax-rules` source), because the bare-symbol alias case has no source
to hand back, only a `Transformer` an earlier step already parsed --
looked up directly in the same `merged_macros` map the resolution loop
already threads through. Aliasing a builtin special form still correctly
falls through to `InvalidSyntax`: builtins are recognized structurally in
`ir_mod.isSpecialForm`, never stored as `Transformer` values in that map,
so there is nothing for a bare-symbol lookup to find.

Verifying this against just its own worked example wasn't enough --
`bash tests/scheme/run-all.sh` caught two real, generalizable bugs that no
amount of SRFI-147-specific testing alone would have found, since both
needed a macro-heavy, multi-scope program to manifest:

1. **A LIFO root-stack violation.** An early draft rooted the resolved
   spec via `pushRoot` + `defer popRoot()` around the (allocating)
   `parseSyntaxRules` call inside `compileLetSyntax`'s per-binding loop.
   The SAME loop iteration pushes an unrelated root for its own result
   array entry right after -- so by the time the deferred call fired (end
   of that iteration), it popped the wrong (most recently pushed) entry
   off the stack instead of the one it was meant to protect, silently
   unrooting the actual transformer object. This surfaced only in
   `tests/scheme/srfi/srfi257.scm` -- a heavily macro-based library --
   as a "invalid syntax" error with no apparent connection to the real
   cause, and never in any of this SRFI's own smaller tests. Fixed by
   popping immediately and explicitly right after the specific call being
   protected, never via `defer` across a stretch that itself calls
   `pushRoot` -- now documented as its own rule in
   `.claude/rules/gc-safety.md`, whose glob also grew to cover
   `compiler*.zig`/`expander.zig`, which it hadn't before despite both
   doing GC-sensitive work directly.
2. **A parent-scope-chain visibility gap.** `resolveTransformerSpec`'s
   macro lookup originally checked only `self.macros`, unlike the
   established macro-CALL-expansion path (`expandAndCompileMacroUse`),
   which explicitly merges every ancestor `Compiler` scope's macros before
   looking anything up -- because a nested child scope (e.g. a
   `let-syntax` whose body sits inside `guard`'s desugared lambda, as
   SRFI 64's own `test-equal` produces) never automatically inherits an
   enclosing scope's macros into its own map. A `syntax-rules*`-based
   transformer-spec placed anywhere but the outermost scope was wrongly
   rejected as "not a macro" until this was fixed to merge the same way.

The begin-wrapped-definitions follow-up itself needed a THIRD correction,
found only once SRFI 148's reference implementation was traced through in
full rather than just its grammar: `em-syntax-rules-aux2`'s own base case
expands to `(begin (define-syntax o spec) o)`, but the SURROUNDING
`syntax-rules` body it sits inside ALSO calls `o` directly from within its
own rules (e.g. `(ck s "arg" (o) . q)`), not just as the bare tail -- so
`o` must keep resolving every time the macro being defined here is later
invoked, not just while resolving this one transformer-spec. A helper
registered only in `resolveTransformerSpec`'s transient, function-local
`merged_macros` (discarded once that call returns) cannot satisfy this --
confirmed via direct reproduction (`(begin (define-syntax step1 ...)
(define-syntax step2 (... (step1 ...))) (syntax-rules () ((_ y) (step2
y))))`, called twice after definition) failing with `undefined variable
'__hyg_N_step1'`. Fixed by registering each begin-internal helper into the
real, persistent-for-this-scope's-lifetime `self.macros` (and `lib_env` at
library top level) exactly like an ordinary `define-syntax` at the same
nesting depth gets, not just the transient resolution-scoped map. That fix
immediately surfaced a fourth, adjacent bug under the unit test suite's
leak-checking allocator: a begin-wrapped alias can hand the exact same
`Transformer` `Value` to two or more different binding sites (a helper
aliased directly by its own generator, then re-aliased by an enclosing
one), and `compileDefineSyntax`/`compileLetSyntax`/`compileLetrecSyntax`
each unconditionally ran `captureLocalsOnTransformer`/
`computeBoundFreeRefs` on whatever `resolveTransformerSpec` returned --
both allocate and overwrite a slice field with no free of what was there
before, so a second finalization pass on an already-finalized object
leaked the first allocation. Fixed by merging both calls into one
`finalizeTransformer`, guarded by a new `Transformer.finalized` flag, so
every transformer is finalized exactly once regardless of how many names
end up pointing at it.

CodeRabbit caught a fifth, adjacent instance of the exact same hazard in
review of that fix, after CI had already auto-merged it -- shipped as its
own immediate follow-up: `compileLetSyntax`'s sibling-suppression
bookkeeping (`let_syntax_peer_names`/`let_syntax_peer_vals`, R7RS 4.3.1)
lives in a separate code block in the SAME per-binding loop, outside
`finalizeTransformer`'s reach, and has the identical "unconditionally
`dupe` and overwrite" shape -- reachable as soon as two sibling bindings
in one `let-syntax` form resolve to the same `Transformer` (a begin-
wrapped helper reference for one, a bare alias of that same helper for
the other). Verified as a real, non-hypothetical leak (not just a
theoretical overwrite) by confirming the shared transformer's template
has a genuinely non-empty free-reference set first -- an earlier draft's
reproduction used a template with zero free references, where `dupe`ing
an empty slice doesn't actually allocate, so the mutation-tested unit
test silently failed to catch anything until the reproduction was
corrected to reference a true sibling. Fixed with a narrower, deliberately
non-permanent guard: a linear scan of this call's own `tx_vals` prefix for
an identical `Value` already processed earlier in the SAME loop -- unlike
`Transformer.finalized`, this can't be a permanent per-object flag, since
a transformer aliased into some OTHER, unrelated `let-syntax` form later
genuinely needs its own peer snapshot computed against that different
form's sibling set.

That same review flagged a sixth spot the fifth's fix didn't close: the
`tx_vals`-prefix scan only ever catches the same `Transformer` reappearing
*within* one `let-syntax` form, so a transformer aliased into a
*different*, unrelated `let-syntax` form later still reached the
recomputation code -- which still unconditionally overwrote whatever an
earlier form's processing had set, with no free. The first fix for this
(shipped, then reviewed) freed the old pair before every such overwrite
and reasoned that recomputing was *correct*, since "a transformer aliased
elsewhere genuinely needs its own peer snapshot against that different
form's siblings." **That reasoning was wrong, not just the leak.** R7RS
4.3.1's peer snapshot exists precisely to freeze a template's free
references against whatever was in scope at the template's own true point
of definition, so that *later* shadowing at some *other* use site can't
reach in and change what a name resolves to -- recomputing it against a
different form's outer bindings is exactly the kind of interference the
mechanism exists to prevent, not a case it needs to additionally handle.
Caught only by a properly discriminating reproduction: a plain top-level
*procedure* as the shared free reference can't tell the two designs apart
at all (a procedure binding was never captured by `let_syntax_peer_vals`
in the first place, which reads `self.macros`, not `self.globals`) --
only a *macro* redefined between the two forms exposes it, and did:
recomputing silently changed a previously-correct answer from 11 to -10,
using the second form's redefinition instead of the first form's binding
where the helper was actually written. Nesting the reuse inside the
defining form's own body (rather than two separate top-level forms) was
worse: it corrupted the *outer* binding too, since the emptied snapshot
let an outer sibling rebinding leak through unsuppressed for both calls.
Fixed by replacing the per-call scan with a permanent, once-per-object
`Transformer.peers_computed` flag (mirroring `finalized`'s own shape, but
a distinct field -- peer suppression is `compileLetSyntax`-specific,
unlike the finalization every macro-defining form needs): the snapshot is
computed exactly once, at whichever form's processing the object is first
encountered in, and every later encounter -- same form or a different
one -- reuses it unchanged. (Verifying the fix took an unrelated detour:
toggling the worktree between the old and new code via `git stash`/
`git checkout <sha> -- <path>` without running `kaappi cache clear` after
each rebuild made the same reproduction file answer differently across
otherwise-identical rebuilds, looking exactly like nondeterminism until
traced back to the `.sbc` bytecode cache's build-id half -- the git commit
hash plus a binary `-dirty` flag, not a hash of what the uncommitted
changes actually are, so any two different uncommitted edits at the same
base commit alias to the identical id and share cache entries -- see
`docs/dev/cache.md`.)

CodeRabbit's review of that fix caught one more ordering bug: the first
cut set `peers_computed = true` immediately, before the several fallible
allocations (`peer_names_f`/`peer_vals_f` appends, both `dupe` calls) that
actually build the snapshot. An OOM partway through would leave the flag
permanently true with `let_syntax_peer_names`/`vals` still at their
default-empty value -- every later reuse would then treat "no suppression
needed" as the final, correct answer instead of retrying. Fixed by moving
the flag assignment to strictly after both slices are durably stored,
right before the `self.macros.put` that was already there.

SRFI 148 (eager syntax-rules) is the fourth piece of issue #1699 and the
reason 147 was implemented at all: `lib/srfi/148.sld` is pure portable
Scheme (the 134-definition CK-machine core plus ~110 `em-` combinators,
combining the reference's three source files in one library body), with
`em-syntax-rules` and several combinators resolving through exactly the
begin-wrapped-`define-syntax` SRFI 147 mechanism described above. No
engine changes shipped WITH it — instead it surfaced, and was blocked by,
six engine bugs fixed separately first: the #1776/#1779 quote-fast-path
and custom-ellipsis unwrap gaps, the #1787/#1790 usertext-marker
spine-walk gaps, the #1796/#1797 head-position chain depth wall (the CK
machine is exactly that shape), and finally #1802's compile-cost cliff
(the ReleaseSafe `= undefined` 0xAA fill of the expander's 1MB buffers
plus the `set!` pre-scan speculatively running the CK machine inside
every transformer spec) — importing the full library now costs ~0.07s
where it cost ~87s. Two details worth knowing before editing the `.sld`:
the reference's genuinely-empty `(syntax-rules ())` for its
`:call`/`:prepare` "secret literals" is rejected by Kaappi's parser
(tracked limitation), so each carries one structurally-unreachable rule
instead; and the port fixes 4 real, confirmed bugs in the SRFI's own
reference implementation (em-append-map's stray `map` token,
em-set-intersection/em-set-difference dropping `'compare` in their 3+-list
recursions, and em-set= being vacuously `#t` for 3+ arguments) — all
documented with evidence in the `.sld` header. The test suite
(`tests/scheme/srfi/srfi148.scm`) is the reference's own `test.sld`
ported verbatim, and **all 142 assertions pass with zero
`test-expect-fail`**. The two general engine bugs the port surfaced
— #1800 (macro-expanded bare `(define x v)` in body position invisible
to later siblings) and #1801 (two expansions of a template-introduced
literal symbol wrongly `bound-identifier=?`) — are both fixed; the test
file's own header explains each fix and is accurate, so read it rather
than assuming the citations are stale.

SRFI 211 (Scheme Macro Libraries) and SRFI 213 (Identifier Properties)
closed issue #1699, and are the codebase's first *procedural* macro
transformers. `Transformer` gained a `kind` tag (syntax_rules / er_macro /
lisp_macro) plus a GC-traced `proc` Value (`types.zig`; marked in all
`gc_collect.zig` switches, deep-copied cross-thread). A transformer spec
`(er-macro-transformer <expr>)` / `(lisp-transformer <expr>)` is
recognized structurally in `resolveTransformerSpecRec` (hygiene-stripped
head, like renamed special forms), and `<expr>` is evaluated AT
MACRO-DEFINITION TIME in the global environment — deliberate phase
separation; enclosing runtime locals are invisible — via
`globals.eval_datum_for_macro`, one of four fn-pointer hooks the VM
registers in `setVMInstance` (the expander/compiler cannot import vm.zig;
the others are `call_proc_for_macro` and the SRFI 213 property get/set
pair). Expansion routes through `expander.expandProceduralMacro`: the ER
`rename`/`compare` arguments are freshly allocated NativeFns reading
threadlocal per-invocation context (fresh scope id + the same
save/restore discipline as the syntax-rules `active_*` context), and
`rename` reuses `renameForHygiene` — so ER macros get exactly the hygiene
strength syntax-rules templates have, including the shared pre-existing
limitation that a use-site top-level redefinition of a referenced name
reaches the expansion (verified equivalent on both paths). A bare-symbol
spec falls back to a globals lookup holding a Transformer value, so
`(define t (er-macro-transformer p))` + `(define-syntax m t)` works. Two
non-obvious integration points: (1) `vm_imports.copyTransformerFreeRefs`
copies a procedural transformer's WHOLE def_env at import (factored
`copyOneDefEnvBinding` shared with the template scan) — its free
references are computed by running code, so the whole environment is the
honest static over-approximation of the template-scan copying
syntax-rules macros get; without it, `(rename 'lib-helper)` output
resolved at the definition site but died "undefined variable" at the use
site. (2) SRFI 213's `capture-lookup` is the identity (its spec permits
exactly this): the expander re-enters ANY procedural result that is a
procedure with the property `lookup` NativeFn, looping (bounded) until a
datum comes back — so wrapped and bare returns behave identically.
`define-property` is a delegating compiler form (`FormKind.define_property`
→ `compileDefineProperty`, auto-membered into
`ir.eval_fallback_form_names`) storing into the VM-owned
`syntax_properties` table (marked in `markVMRoots`, keys owned,
effective-name keyed — nominal conformance like SRFI 57); body-scope use
is rejected, top-level and library top-level work. The public surface is
sub-library-only for 211 — `(srfi 211 explicit-renaming)` /
`(srfi 211 define-macro)` / `(srfi 211 syntax-parameter)` (.slds over the
`.srfi_211_primitives` registry entry; a bare `(srfi 211)` would require
all eleven facilities including syntax-case, and the spec explicitly
permits providing a subset of libraries, each whole) — plus
`lib/srfi/213.sld`, whose `define-property` export is
declaration-of-intent like SRFI 46/149's syntax-rules re-exports (export
of a name missing from lib_env is silently skipped; recognition is
ambient). The remaining 211 sub-libraries (syntax-case, low-level,
syntactic-closures, implicit-renaming, variable-transformer,
identifier-syntax, with-ellipsis, presyntax) need syntax objects,
identifier macros, or output-provenance tracking a symbol-based expander
cannot honestly provide — implicit renaming specifically cannot
distinguish injected from macro-generated symbols when both are the same
interned object.

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

`docs/dev/adding-features.md` is the detailed reference; this is the checklist.

1. Write the function in the appropriate `src/primitives_*.zig` file — one of
   the 30 domain files, not `primitives.zig` itself (that's the registration
   hub plus core list/pair ops):

   ```zig
   fn myProc(args: []const Value) PrimitiveError!Value {
       if (!types.isFixnum(args[0]))
           return primitives.typeError("my-proc", "exact integer", args[0]);
       return types.makeFixnum(types.toFixnum(args[0]) + 1);
   }
   ```

   Report type errors with `primitives.typeError(proc, expected, got)`, never a
   bare `return PrimitiveError.TypeError` — it names the expected type and the
   offending value, and the `format` CI job rejects any unannotated bare return
   (the count-based ratchet was retired at 0 by kaappi#1868).
   `expectFixnum`/`expectString`/`expectPair`/… validate and unwrap in one step.
   Infrastructure guards with no procedure context to report opt out with
   `// bare-ok: <reason>`.

   A bare return is not silent — `vm_calls.mapNativeError` synthesizes
   `type error in '<primitive>': got <args[0]>` when no detail was set — which
   is exactly what makes it dangerous: the procedure name survives, so the
   message looks deliberate while omitting the expected type and, when the
   offending value is not the first argument, naming the wrong one.

   Use the sibling helpers for failures that are not type errors, rather than
   stretching `typeError` over them: `indexError(proc, index, len)`
   (`IndexOutOfBounds`, KP3006) and `argError(proc, fmt, args)`
   (`InvalidArgument`, KP3007 — for a value of acceptable type that the
   procedure rejects anyway, e.g. a sealed parent rtd). See
   `docs/dev/adding-features.md`.

2. Add one entry to the file's `specs` table — name, function, arity, and the
   libraries that export it. `registerAll` walks `all_specs` and
   `library.zig` derives every export set from the same tags, so this is the
   whole registration; there is no second list and no manual `reg()` call:

   ```zig
   .{ .name = "my-proc", .func = &myProc, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
   ```

   Arity: `.{ .exact = N }` for fixed, `.{ .variadic = N }` for N minimum args.

3. An internal helper — a `%`-prefixed name only
   compiler-generated code or a portable `.sld` calls — takes
   `primitives.INTERNAL` instead: registered in `vm.globals`, exported by
   nothing, so it doesn't reserve the name against user libraries
   (kaappi#1856; a comptime check rejects a `%` name tagged `scheme.*`).
   `primitives.INTERNAL_PUBLIC` additionally exports it from
   `(kaappi primitives)`, for helpers a portable `.sld` names in Scheme
   source (SRFI 27/74/271 and the record SRFIs import it).
   Synthesize *references* to one with `Compiler.trueBuiltinRefOrSymbol` /
   `globals_mod.baseBindingSymbol`, never a bare `allocSymbol("%foo")`, or a
   user binding of the same name silently wins. See
   `docs/dev/adding-features.md`.

4. If the procedure needs heap allocation, use `memory.gc_instance` (a
   threadlocal in `src/memory.zig`; `primitives.zig` does not re-export it).
   If it needs to call Scheme procedures, use `vm_mod.vm_instance` and
   `vm.callWithArgs(proc, args)`. Both are `orelse`-optional:

   ```zig
   const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
   ```

5. Add a unit test in the matching `src/tests_*.zig` file (44 of them, one per
   feature area) using the `testing_helpers.zig` helpers — `th.expectEval` for
   the common case, `th.TestContext` when the test needs several evals. Not in
   `src/vm.zig`: its one `test` block only imports sibling modules into the
   test build. Add a Scheme test under `tests/scheme/` when the behavior is
   worth an end-to-end check.

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
   never a direct cast. Define it in the matching `types_*.zig` domain
   file (see the table above) if one fits, or directly in `types.zig` if
   it's a core type or doesn't fit an existing domain; either way, add a
   `pub const MyType = types_x.MyType;` re-export in `types.zig` if it
   isn't defined there directly, and reference the new type's bare name
   (not `types_x.MyType`) from `Object.expectedTag()`'s switch.
3. Add `allocXxx` in `src/gc_alloc.zig`, and alias it into `GC` next to the
   other allocator aliases in `src/memory.zig`
   (`pub const allocXxx = gc_alloc.allocXxx;`).
4. Handle the new tag in the 5 exhaustive per-tag switches — three in
   `src/gc_collect.zig`: `markObjectContents` and `markValueInner`'s own
   worklist switch (both trace contained Values — a type with no Value
   fields, like `Symbol`, just needs a no-op `{}` arm in each, since Zig's
   exhaustiveness check forces one either way) and `referencesYoung`
   (generational remembered-set check) — and two in `src/gc_sweep.zig`:
   `objectSize` (GC stats) and `freeObject` (free owned memory).
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

```bash
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

## Issue tracker

**Every issue you file or triage gets exactly one `priority:` label** —
`critical`, `high`, `medium`, or `low`. Set it when filing; an issue that
arrives without one is not triaged. `docs/dev/github-issues.md` is the full
rubric (the four label axes, worked boundary cases, the triage commands);
this is the part you need at filing time:

| Level | The question it answers |
|-------|------------------------|
| critical | Does this compromise the process — memory unsafety, or an abort reachable from an ordinary program? |
| high | Does a legal program get a silently wrong answer, hang, or lose data in a path users actually reach? |
| medium | Is behaviour wrong against a spec or a documented guarantee, but loud, narrow, or recoverable? |
| low | Is the behaviour right and only its *description* or *diagnostic* wrong? |

Four rules decide the hard cases:

- **`critical` is process-level unsafety only.** A correctness bug tops out
  at `high` however broad or silent. All 13 issues ever marked critical are
  memory unsafety or a process abort.
- **Reachability separates critical from high.** An abort needing a stress
  harness is `high`; one reachable from a five-line program is `critical`.
- **An audit header's `Severity:` is an input, not the answer.**
  `wrong-result` spans `high` to `medium` purely on blast radius.
- **Silence is an aggravator, not a level.** A loud failure is safer than a
  quiet one, so silence moves an issue up *within* its level.

Auto-filed `fuzz-finding` CI reports are the one exemption — they are
triage-and-close, and carry no priority. To find every issue that violates
the rule — none *or* more than one, since "exactly one" has two failure
modes:

```bash
gh issue list --repo kaappi/kaappi --state open --limit 400 \
  --json number,title,labels \
  --jq '.[] | ([.labels[].name | select(startswith("priority:"))] | length) as $n
            | select($n != 1)
            | select([.labels[].name] | index("fuzz-finding") | not)
        | "\(.number)\t\(.title)"'
```

## Package manager (thottam)

`src/thottam.zig` is a Zig binary that installs Kaappi ecosystem libraries.
Built alongside kaappi via `zig build`, ships in release artifacts for all platforms.

```bash
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

```text
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
thread gets its own VM and GC with an independent heap. A value reaches
another thread by one of **two routes**, with separate and unrelated
enforcement — `docs/dev/thread-value-sharing.md` is the full matrix,
pinned by `tests/scheme/srfi/srfi18-sharing-model.scm`.

**The copy route.** Values are **deep-copied** at three boundaries:

- **At start:** the thunk closure is deep-copied from parent GC to child GC
- **At join:** the result (or uncaught exception) is deep-copied back
- **Channel messages:** the payload is copied in each direction

`gc_deep_copy.zig` refuses 14 tags outright here (port, continuation,
fiber, mutex, condition variable, ffi-callback, the four SRFI-170 record
types, environment, and the three SRFI-254 weak references). Channels are
the exception: their arm promotes and aliases, which is what makes lexical
capture the supported way to share one.

**The globals route.** `VM.initForThread` shares the parent's `globals`
map **by pointer**, so a thunk that *names* a top-level binding captures
nothing — the child resolves it at run time and gets the parent's own
object, uncopied. That list of 14 does not apply here, and 13 of the 14
are freely usable this way. Only two types defend themselves, by comparing
`Object.owner` against the running `GC.id`: channels
(`primitives_fiber.zig`) and thread handles
(`primitives_srfi18.checkThreadOwner`).

So threads **can** share mutable heap state, and for mutexes and condition
variables a global is the *only* supported way to share one — exactly
inverted from channels, which must be captured lexically. Mutating shared
state through a global is a live hazard (#1924), not a supported idiom;
the child GC collects independently and the child heap is freed after
`thread-join!`.

**Key implementation details:**

- `vm_instance` and `gc_instance` are `threadlocal` (`src/vm.zig`, `src/memory.zig`)
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
| `/create-announcement` | Draft and post a release announcement to the org Announcements forum (takes a release tag) |
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
| Markdown structure | CI `format` job (markdownlint) | `.markdownlint-cli2.jsonc`, `.github/workflows/ci.yml` |
| No bare `PrimitiveError.TypeError` | CI `format` job (grep, zero allowed) | `.github/workflows/ci.yml` |
| No destructive commands | Deny permissions + PreToolUse hook | `.claude/settings.json`, `.claude/hooks/bash-guard-pre.sh` |
| Tests pass before stop | Stop hook | `.claude/hooks/test-on-stop.sh` |
| GC safety checklist | Path-scoped rule (auto-loaded) | `.claude/rules/gc-safety.md` |
| Compiler form checklist | Path-scoped rule (auto-loaded) | `.claude/rules/compiler-forms.md` |
| Bug fixes need tests | Advisory only | This file (Tests section) |
| Files ≤ 1500 lines | Advisory only | This file (File size policy) |
| One `priority:` label per issue | Advisory only | This file (Issue tracker), `docs/dev/github-issues.md` |
| Commit message format | Advisory only | Parent CLAUDE.md (Conventions) |

## Known limitations

See the "Known limitations" section in `README.md` (single source of truth).
