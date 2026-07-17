# Changelog

All notable changes to Kaappi are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
