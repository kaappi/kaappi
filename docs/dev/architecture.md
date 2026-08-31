# Architecture

Kaappi implements R7RS-small Scheme as a bytecode-compiled language with a
register-based VM. This document describes the major subsystems and how they
fit together.

---

## Pipeline

```text
Source code
    |
    v
+--------+     +----------+     +------+     +----------+     +----------+     +----------+     +----+
| Reader | --> | Expander | --> |  IR  | --> | Analysis | --> |  Optim.  | --> | Bytecode | --> | VM |
| (UTF-8 |     | (syntax- |     |      |     |  Passes  |     |  Passes  |     | Emission |     |    |
|  lexer)|     |  rules)  |     |      |     |          |     |          |     |          |     |    |
+--------+     +----------+     +------+     +----------+     +----------+     +----------+     +----+
                                                                                                  |
                                                                                          +-------+-------+
                                                                                          | GC (generat-  |
                                                                                          | ional mark    |
                                                                                          | & sweep)      |
                                                                                          +---------------+
```

| Stage | File(s) | Role |
|-------|---------|------|
| **Reader** | `reader.zig` + `reader_tokens.zig`, `reader_datum.zig` | Tokenizer + recursive descent parser. Handles full R7RS lexical syntax including Unicode identifiers, `#\lambda` character literals, `#(...)` vectors, `#u8(...)` bytevectors, datum labels. |
| **Expander** | `expander.zig` + `expander_instantiate.zig` | `syntax-rules` pattern matching with ellipsis, literal identifiers, and underscore wildcards. Template instantiation with hygienic renaming (gensym-based). |
| **IR** | `ir.zig` | Lowers S-expressions to a tree-structured IR (18 node types, one of which — `sexpr_form` — carries 18 `FormKind`s). Runs 1 analysis pass (tail positions) and 5 optimization passes (constant folding, dead branch elimination, boolean simplification, identity elimination, begin simplification). See [ir.md](ir.md) for details. |
| **Compiler** | `compiler.zig` + 9 sub-modules | Emits register-based bytecode from IR nodes via `compileFromNode()` (in `compiler_ir.zig`). Retains `compileExpr()` for forms delegated via `passthrough`. See the [Compiler & IR](#compiler--ir-11-files) table for the per-file split. |
| **VM** | `vm.zig` + 10 sub-modules | Executes bytecode with a growable register file, call frame stack, exception handler stack, and dynamic-wind stack (all heap-allocated, double-on-overflow; exceeding a hard cap is an uncatchable KP3008). First-class continuations via stack copying, plus a stepping debugger. |
| **GC** | `memory.zig` | Generational (young/old) mark-and-sweep collector over an intrusive linked list, with a write barrier and remembered set for old→young references. Root tracking via `pushRoot`/`popRoot`. Triggered after N allocations. |
| **Primitives** | 32 `primitives_*.zig` files | 696 built-in procedures organized by domain. |

---

## File Organization

### Core runtime

| File | Lines | Responsibility |
|------|-------|---------------|
| `types.zig` | ~1300 | Value type, `Object`/`ObjectTag`, opcodes, type predicates, hygiene helpers, re-export hub for the `types_*.zig` heap-type domain files below |
| `memory.zig` | ~1000 | GC struct, lifecycle, write barrier, rooting, quarantine; aliases the allocators below into `GC` |
| `gc_alloc.zig` | ~1400 | All `allocXxx` heap-object constructors (delegated from memory.zig, aliased into `GC` so `gc.allocXxx(...)` is unchanged) |
| `gc_collect.zig` | ~1000 | GC orchestration, remembered set, marking, SRFI 254 weak-ref processing (delegated from memory.zig) |
| `gc_sweep.zig` | ~600 | Sweep phase: sweepYoung/sweepOld/sweep, `objectSize`, `freeObject` (delegated from gc_collect.zig) |
| `gc_deep_copy.zig` | ~580 | Cross-thread deep copy (delegated from memory.zig) |
| `reader.zig` | ~1000 | `Reader`/`Token`/`ReadError` definitions and the read entry points |
| `reader_tokens.zig` | ~975 | Tokenizer: Unicode lexing, string/character escapes, number-literal parsing |
| `reader_datum.zig` | ~360 | Datum construction: lists, vectors, bytevectors, quote forms, datum labels |
| `expander.zig` | ~1000 | Macro-use expansion engine: expandMacro/expandProceduralMacro, syntax-rules pattern matching, usertext/hygiene-strip walks |
| `expander_instantiate.zig` | ~1000 | syntax-rules template instantiation + renameForHygiene/scope-table minting (shares expander.zig's threadlocal expansion context) |
| `printer.zig` | ~1250 | Value → string: iterative label-aware print engine + hashmap cycle/sharing detection (write/display/write-shared/write-simple; exact at any depth) and the bounded diagnostic `printValue` |
| `printer_pretty.zig` | ~320 | REPL pretty-printer (fits-or-wraps layout over the bounded diagnostic printer; re-exported as `printer.prettyPrint`) |

### Heap-type domain files (split into 12 files, kaappi#1731)

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
| `types_process.zig` | `Process` (KEP-0022, `(kaappi process)`), waitpid status decoders |

`Fiber` (`fiber.zig`) predates this split and follows neither convention:
its struct lives outside `types.zig` entirely with no `types.Fiber` re-export.

### Compiler & IR (11 files)

| File | Responsibility |
|------|---------------|
| `ir.zig` | IR node types (18), AST→IR lowering, 1 analysis pass, 5 optimization passes |
| `compiler.zig` | Core: IR pipeline orchestration (`compile()` lowers to IR, runs passes), retains `compileExpr()` for passthrough forms, scope/register management, macro forms |
| `compiler_ir.zig` | IR-to-bytecode: `compileFromNode()` dispatch, if, begin, call, lambda, define, set!, and, or, when, unless |
| `compiler_lambda.zig` | lambda, define, set!, begin, delay, delay-force, body compilation |
| `compiler_conditionals.zig` | and, or, when, unless, cond, cond-expand |
| `compiler_bindings.zig` | let, let*, letrec, letrec*, named let, do, let-values, let*-values |
| `compiler_advanced.zig` | case, case-lambda, guard, quasiquote |
| `compiler_macro.zig` | Macro-use path: expandAndCompileMacroUse, hygiene injection walks, free-ref collection; re-exports compiler_define_syntax.zig |
| `compiler_define_syntax.zig` | Macro-defining forms: define-syntax, let-syntax, letrec-syntax, define-property, transformer-spec resolution (SRFI 147), syntax-rules parsing, transformer finalization |
| `compiler_passthrough.zig` | The `passthrough` path's form compilers: quote, if, call, and the tail-position specializations (`apply`, `call-with-values`, `call/cc`, `eval`) |
| `compiler_forms.zig` | Re-export hub (thin file, don't edit directly) |

### VM (split into 11 files)

| File | Responsibility |
|------|---------------|
| `vm.zig` | VM struct, init/deinit, error handling, delegation wrappers |
| `vm_bootstrap.zig` | Scheme-level implementations of the higher-order procedures that must drive their callbacks through the dispatch loop rather than the Zig call stack |
| `vm_dispatch.zig` | runUntil bytecode dispatch loop, opcode handlers; re-exports vm_dispatch_helpers.zig |
| `vm_dispatch_helpers.zig` | Dispatch support: bytecode/operand readers, register-window validation, the shared global-resolution helper (lookupGlobalLocked, #1831/#1860), noinline error raisers, buildRestList |
| `vm_calls.zig` | execute, run, callValue, callClosure, callNative, profile helpers |
| `vm_eval.zig` | eval, handleTopLevelForm dispatcher |
| `vm_library.zig` | handleDefineLibrary, .sld file loading, SRFI 261 normalization, cond-expand features, include; re-exports vm_imports.zig |
| `vm_imports.zig` | Import-set algebra: handleImport, processImportSet (only/except/rename/prefix), transformer free-ref copying |
| `vm_records.zig` | handleDefineRecordType desugaring |
| `vm_continuations.zig` | captureContinuation, restoreContinuation, performWindTransition, callWithCC |
| `vm_debug.zig` | Stepping debugger: breakpoints (with conditions), watch expressions, step/next/step-out/continue, up/down frame navigation, locals, backtrace |

### Primitives (split into 32 files)

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
| `primitives_process.zig` | `(kaappi process)` (KEP-0022): posix_spawnp-based subprocess support — spawn-process, pipe ports, blocking process-wait, process-kill, zombie sweep. POSIX-only (Windows is Phase 3, WASM registers nothing) |
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
| `isocline.zig` | Zig FFI wrapper for the vendored isocline line editor |
| `main.zig` | Entry point, file execution, CLI flags, `pub const version`, `pub const panic` (the REPL loop lives in `repl.zig`) |
| `cli_spec.zig` | **The** CLI flag/subcommand tables. Every parse loop (`cli.zig`, `explain`, `features`, `doctor`, `test_runner`, `cache`, `thottam`) dispatches on an exhaustive `switch` over one of its `Id` enums, `cli.printUsage` generates its `Options:` block from it, and `completions.zig` generates all six shell scripts from it — so a flag cannot reach a parser without the docs and completions following. See `docs/dev/cli-surface.md` |
| `completions.zig` | bash/zsh/fish completion scripts for `kaappi` and `thottam`, generated at comptime from `cli_spec.zig`. Nothing here is hand-maintained |
| `crash.zig` | Custom panic handler (`PanicHandler(name)`) + pipeline breadcrumb (`noteStage`/`noteFile`); prints version/target/build-mode + stage + report URL before the trace. See `docs/dev/crash-reporting.md` |
| `native_compiler.zig` | LLVM IR emission, native binary compilation, C compiler discovery, linker invocation |
| `thottam.zig` | Package manager binary (thottam): install, remove, list, update, verify |
| `llvm_emit.zig` | LLVM IR text emitter core: LLVMEmitter struct/state, program orchestration, call emission, constants/interning (special-form/cond/case/do emitters live in `llvm_emit_forms.zig`; let/lambda/tailcall/inline/freevars satellites likewise) |
| `runtime_exports.zig` | C-ABI bridge for LLVM native backend (28 exported functions) |
| `fmt.zig` | `kaappi fmt`: comment-preserving CST reader (lexer + parser), CLI entry, real-reader `equal?` round-trip safety net |
| `fmt_print.zig` | `kaappi fmt` layout engine: fits-or-breaks pretty-printer, special-form indentation rules |
| `testing_helpers.zig` | Shared `makeTestVM` helper for unit tests |
| `tests_ir.zig` | IR tests: bytecode parity, behavioral correctness, analysis, optimizations |
| `tests_*.zig` | Unit tests by feature (core_eval, tail_calls, macros, io, etc.) |

---

## Value Representation

All Scheme values fit in a single **NaN-boxed 64-bit word**. Flonums, fixnums,
booleans, characters, and nil all fit in a u64 with zero heap allocation:

```text
Flonum:    any f64 that is not a NaN             -- stored directly
Pointer:   0xFFFC | 48-bit pointer               -- heap object
Fixnum:    0xFFFD | 48-bit signed integer         -- up to ±2^47
Immediate: 0xFFFE | payload                      -- nil, bool, void, eof, char
```

### Four categories

**Flonums** (any non-NaN f64): Stored directly in the 64-bit word. No heap
allocation — this is the key advantage of NaN-boxing over the previous tag
scheme.

**Pointers** (high 16 bits = 0xFFFC): Point to heap-allocated `Object` structs.
The 48-bit payload holds the pointer address.

**Fixnums** (high 16 bits = 0xFFFD): 48-bit signed integers (up to ±2^47).
Auto-promote to bignum on overflow.

**Immediates** (high 16 bits = 0xFFFE): Nil, true, false, void, EOF, and
characters. Characters encode a 21-bit Unicode codepoint in the payload.

This design means the most common types (integers, booleans, characters, nil)
require zero heap allocation.

---

## Heap Objects

Every heap object starts with an `Object` header:

```zig
pub const Object = struct {
    tag: ObjectTag,      // u6 -- which type (64 slots)
    flags: Flags,        // packed u8: marked, generation:u1, survive_count:u2, immutable
    owner: u32,          // id of the GC that tracks this object (fits in padding)
    next: ?*Object,      // intrusive linked list for GC
    _align: Align,       // forces 8-byte alignment for the pointer tag check
};
```

`owner` is what lets an SRFI-18 child thread's heap hold references into the
parent's without either collector writing mark bits on the other's objects
(#958); in Debug and gc-stress builds, freeing stamps it with
`memory.FREED_OWNER` so a later mark of the dead header panics deterministically
(#1687).

### ObjectTag enum (41 types)

| Tag | Value | Type |
|-----|-------|------|
| `pair` | 0 | Cons cell (car + cdr) |
| `symbol` | 1 | Interned string |
| `string` | 2 | UTF-8 byte array |
| `closure` | 3 | Function + captured upvalues |
| `native_fn` | 4 | Built-in Zig procedure |
| `vector` | 5 | Growable array of Values |
| `bytevector` | 6 | Byte array |
| `port` | 7 | File, string, or bytevector port |
| `record_type` | 8 | Record type descriptor |
| `function` | 9 | Compiled bytecode function |
| `flonum` | 10 | IEEE 754 f64 |
| `transformer` | 11 | Syntax-rules transformer |
| `error_object` | 12 | Error with message + irritants |
| `record_instance` | 13 | Instance of a record type |
| `continuation` | 14 | Captured VM state |
| `multiple_values` | 15 | Wrapper for multiple return values |
| `complex` | 16 | Complex number (pair of f64) |
| `promise` | 17 | Delayed computation |
| `parameter` | 18 | Dynamic parameter binding |
| `ffi_library` | 19 | Handle to a loaded shared library |
| `ffi_function` | 20 | Bound C function |
| `hash_table` | 21 | SRFI-69 hash table |
| `bignum` | 22 | Arbitrary-precision integer |
| `rational` | 23 | Exact rational (numerator/denominator) |
| `file_info` | 24 | SRFI-170 file metadata (stat result) |
| `user_info` | 25 | SRFI-170 user database entry |
| `group_info` | 26 | SRFI-170 group database entry |
| `directory_object` | 27 | SRFI-170 open directory stream |
| `random_source` | 28 | SRFI-27 random number generator |
| `ffi_callback` | 29 | FFI callback (Scheme → C function pointer) |
| `fiber` | 30 | Green fiber (cooperative thread) |
| `channel` | 31 | Fiber communication channel |
| `mutex` | 32 | SRFI-18 mutex |
| `condition_variable` | 33 | SRFI-18 condition variable |
| `srfi18_time` | 34 | SRFI-18 time object |
| `native_closure` | 35 | Zig closure over captured Values (a native procedure with state) |
| `scheme_environment` | 36 | First-class environment (`eval`'s second argument) |
| `ephemeron` | 37 | SRFI-254 ephemeron (key/datum pair the GC treats weakly) |
| `guardian` | 38 | SRFI-254 guardian |
| `transport_cell` | 39 | SRFI-254 transport cell (an ordinary strong pair on a non-moving GC) |
| `numeric_vector` | 40 | SRFI-160 homogeneous numeric vector (u8 stays a plain bytevector) |

---

## Garbage Collector

The GC is a **generational mark-and-sweep** collector using an **intrusive
linked list**.

### Design

- All heap objects are linked via their `Object.next` pointer.
- Every object carries a generation bit (young/old) and a survive count in its
  header; surviving a few collections promotes a young object to old.
- The GC maintains a count of allocations since the last collection.
- When the count exceeds a threshold, a collection cycle runs:
  1. **Mark**: Traverse all roots, mark reachable objects.
  2. **Sweep**: Walk the linked list, free unmarked objects.
- A **minor** collection only marks and sweeps the young generation. Old→young
  references are found through the **remembered set**, which `gc.writeBarrier`
  populates whenever a Value is stored into an old object's field — omitting
  that barrier is the classic way to corrupt a minor collection. A **full**
  collection covers both generations.

Orchestration and marking live in `gc_collect.zig`, the sweep phase in
`gc_sweep.zig`; `memory.zig` holds the `GC` struct and aliases both in.

### Root tracking

Values on the Zig stack that hold pointers to heap objects must be protected
from GC if any allocation might happen before the pointer is used:

```zig
gc.pushRoot(&val);    // protect
// ... code that might allocate ...
gc.popRoot();         // unprotect (must be LIFO)
```

The root stack grows geometrically and is hard-capped at
`GC.MAX_ROOT_CAPACITY` (65536); exceeding it panics. `pushRoot`/`popRoot` calls
must be balanced and follow LIFO order — see
[gc-safety-and-error-handling.md](gc-safety-and-error-handling.md) for why a
`defer popRoot()` is not always the safe spelling.

---

## Bytecode Format

The compiler produces register-based bytecode. Each instruction is an `OpCode`
enum value followed by operands.

### Opcodes

31 opcodes, defined by the `OpCode` enum in `src/types.zig`. Register, slot,
constant-index and symbol-index operands are u16 (big-endian); only `nargs` and
a closure capture descriptor's `is_local` flag are u8.

**[bytecode.md](bytecode.md) has the full table** — opcode numbers, operands,
byte widths, the closure capture encoding, and the disassembler's output
format. It is the single source of truth for the ISA and is deliberately not
duplicated here: this file carried its own copy until kaappi#2102, and it had
drifted to describe three opcodes that do not exist (`get_local`, `set_local`,
`close_upvalue`) while omitting three that do (`self_tail_call`,
`tail_call_cc`, `tail_eval`) — a wrong table whose row count happened to stay
right.

### Function objects

A compiled `Function` contains:

- Bytecode array (opcodes + operands)
- Constant pool (values referenced by `load_const`)
- Upvalue descriptors (for closure creation)
- Arity information
- Debug metadata (source name, line number, local variable names)

---

## String Representation

Strings are stored as **UTF-8 byte arrays** but all Scheme-visible operations
(string-length, string-ref, substring, etc.) index by **Unicode codepoint
position**, not byte offset.

This means `(string-ref "hello" 1)` returns `#\e` regardless of whether
earlier characters are multi-byte. The trade-off is that indexing is O(n) in
the worst case -- a sequential scan is needed to count codepoints. In practice,
most strings are ASCII and the performance impact is negligible.

Mutation via `string-set!` rebuilds the string when the byte width of the new
character differs from the old one.

---

## Continuations

Kaappi implements first-class continuations via **stack copying**. When
`call/cc` captures a continuation, the entire call frame stack and register
state is copied into a `Continuation` heap object.

When a continuation is invoked, the saved state is restored. If `dynamic-wind`
handlers are active, the VM performs a **wind transition** -- unwinding out of
the current dynamic context and rewinding into the saved one, calling the
appropriate before/after thunks.

An optimized `call/ec` (escape continuation) is also provided for the common
case where the continuation is only used for non-local exit and never needs to
be stored or invoked after the capturing form returns.

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
