# Architecture

Kaappi implements R7RS-small Scheme as a bytecode-compiled language with a
register-based VM. This document describes the major subsystems and how they
fit together.

---

## Pipeline

```
Source code
    |
    v
+--------+     +----------+     +------+     +----------+     +----------+     +----------+     +----+
| Reader | --> | Expander | --> |  IR  | --> | Analysis | --> |  Optim.  | --> | Bytecode | --> | VM |
| (UTF-8 |     | (syntax- |     |      |     |  Passes  |     |  Passes  |     | Emission |     |    |
|  lexer)|     |  rules)  |     |      |     |          |     |          |     |          |     |    |
+--------+     +----------+     +------+     +----------+     +----------+     +----------+     +----+
                                                                                                  |
                                                                                            +-----+-----+
                                                                                            | GC (mark  |
                                                                                            | & sweep)  |
                                                                                            +-----------+
```

| Stage | File(s) | Role |
|-------|---------|------|
| **Reader** | `reader.zig` | Tokenizer + recursive descent parser. Handles full R7RS lexical syntax including Unicode identifiers, `#\lambda` character literals, `#(...)` vectors, `#u8(...)` bytevectors, datum labels. |
| **Expander** | `expander.zig` | `syntax-rules` pattern matching with ellipsis, literal identifiers, and underscore wildcards. Template instantiation with hygienic renaming (gensym-based). |
| **IR** | `ir.zig` | Lowers S-expressions to a tree-structured IR (33 node types). Runs 3 analysis passes (tail positions, primitive identification, constant detection) and 5 optimization passes (constant folding, dead branch elimination, boolean simplification, identity elimination, begin simplification). See [ir.md](ir.md) for details. |
| **Compiler** | `compiler.zig` + 5 sub-modules | Emits register-based bytecode from IR nodes via `compileFromNode()`. Retains `compileExpr()` for forms delegated via `passthrough`. Dispatches 32 syntax forms across 6 files. |
| **VM** | `vm.zig` + 7 sub-modules | Executes bytecode with a register file, call frame stack, exception handler stack, and dynamic-wind stack. First-class continuations via stack copying, plus a stepping debugger. |
| **GC** | `memory.zig` | Mark-and-sweep collector with intrusive linked list. Root tracking via `pushRoot`/`popRoot`. Triggered after N allocations. |
| **Primitives** | 21 `primitives_*.zig` files | 554 built-in procedures organized by domain. |

---

## File Organization

### Core Runtime

| File | ~Lines | Responsibility |
|------|--------|---------------|
| `types.zig` | 650 | Value type, heap object structs, ObjectTag enum, opcodes |
| `memory.zig` | 650 | GC allocator, alloc/mark/free for all heap types |
| `reader.zig` | 700 | S-expression parser, Unicode lexing (core) |
| `reader_tokens.zig` | 550 | Tokenizer / lexer (numbers, strings, identifiers) |
| `reader_datum.zig` | 220 | Datum parsing, datum labels |
| `expander.zig` | 320 | Macro expansion engine (syntax-rules) |
| `printer.zig` | 300 | Value-to-string (write mode and display mode) |

### Compiler & IR (7 files)

| File | Responsibility |
|------|---------------|
| `ir.zig` | IR node types (33), AST→IR lowering, 3 analysis passes, 5 optimization passes, standalone Emitter for parity testing |
| `compiler.zig` | Core: IR pipeline orchestration (`compile()` lowers to IR, runs passes, emits via `compileFromNode()`), also retains `compileExpr()` for passthrough forms, scope/register management |
| `compiler_lambda.zig` | lambda, define, set!, begin, delay, delay-force, body compilation |
| `compiler_conditionals.zig` | and, or, when, unless, cond, cond-expand |
| `compiler_bindings.zig` | let, let*, letrec, letrec*, named let, do, let-values, let*-values |
| `compiler_advanced.zig` | case, case-lambda, guard, quasiquote |
| `compiler_forms.zig` | Re-export hub (thin file that exposes all form compilers) |

### VM (8 files)

| File | Responsibility |
|------|---------------|
| `vm.zig` | VM struct, init/deinit, error handling, delegation wrappers |
| `vm_dispatch.zig` | runUntil bytecode dispatch loop, opcode handlers |
| `vm_calls.zig` | execute, run, callValue, callClosure, callNative, profile helpers |
| `vm_eval.zig` | eval, handleTopLevelForm dispatcher |
| `vm_library.zig` | handleImport (with only/except/rename/prefix), handleDefineLibrary, .sld file loading |
| `vm_records.zig` | handleDefineRecordType desugaring |
| `vm_continuations.zig` | captureContinuation, restoreContinuation, performWindTransition, callWithCC |
| `vm_debug.zig` | Stepping debugger: breakpoints, step/next/continue, locals, backtrace |

### Primitives (21 files)

| File | Domain |
|------|--------|
| `primitives.zig` | Registration hub, core list/pair ops, type predicates, equivalence, map, for-each, apply |
| `primitives_arithmetic.zig` | +, -, *, /, comparisons, trig, exp/log, gcd/lcm, complex |
| `primitives_numeric.zig` | Rounding, exactness predicates, exact/inexact conversion |
| `primitives_string.zig` | String ops, basic char comparisons, number-string conversion, UTF-8 codepoint indexing |
| `primitives_string_ext.zig` | SRFI-13 string library (contains, prefix?, trim, split, join) |
| `primitives_char.zig` | Unicode classification, case conversion, case-insensitive comparisons |
| `primitives_vector.zig` | Vector operations, vector-map, vector-for-each |
| `primitives_bytevector.zig` | Bytevector ops, binary I/O, bytevector ports |
| `primitives_list.zig` | list-ref, list-tail, list-set!, list-copy, make-list, member, assoc |
| `primitives_srfi1.zig` | SRFI-1 list library (fold, filter, find, iota, etc.) |
| `primitives_hashtable.zig` | SRFI-69 hash tables |
| `primitives_random.zig` | SRFI-27 random numbers |
| `primitives_io.zig` | Port ops, file I/O, string ports, read/write/display |
| `primitives_filesystem.zig` | SRFI-170 POSIX filesystem API (file-info, directory ops, symlinks, user/group info) |
| `primitives_control.zig` | raise, guard, with-exception-handler, call/cc, dynamic-wind, values |
| `primitives_lazy.zig` | delay, force, make-promise, promise? |
| `primitives_cxr.zig` | 24 car/cdr compositions (caaaar through cddddr) |
| `primitives_ffi.zig` | FFI procedure registration (ffi-open, ffi-fn, ffi-close, ffi-callback). 18 FFI types. |
| `primitives_r7rs.zig` | Time, process-context, eval, load, make-parameter |
| `primitives_srfi18.zig` | SRFI-18: threads, mutexes, condition variables, time objects |

### Other

| File | Responsibility |
|------|---------------|
| `library.zig` | Library registry, standard library registration |
| `linenoise.zig` | Zig FFI wrapper for vendored linenoise C library |
| `main.zig` | Entry point, REPL loop, file execution, CLI flags (`--help`, `--version`, etc.) |
| `thottam.zig` | Package manager binary: install, remove, list, update, verify |
| `kaappi_lsp.zig` | Language server (LSP) for IDE integration |
| `ffi.zig` | FFI call dispatcher (type marshaling, arity routing, `normalizeType`) |
| `jit.zig` | JIT orchestration: eligibility, compile dispatch, C-ABI helpers, shared utilities |
| `jit_compile_aarch64.zig` | AArch64 bytecode → native compiler: NaN-boxed value encoding, frame/call sequences |
| `jit_compile_x86_64.zig` | x86_64 bytecode → native compiler: register cache, NaN-boxed value encoding |
| `jit_aarch64.zig` | AArch64 assembler (fixed 4-byte instruction encoding) |
| `jit_x86_64.zig` | x86_64 assembler (variable-length encoding, REX prefixes) |
| `jit_mem.zig` | Executable memory allocation (mmap RWX, macOS JIT protection + entitlements) |
| `runtime_exports.zig` | C-ABI bridge for LLVM native backend (8 exported functions) |
| `llvm_emit.zig` | LLVM IR text emitter (walks IR nodes, produces `.ll` files) |
| `bignum.zig` | Arbitrary-precision integer arithmetic |
| `bytecode_file.zig` | Bytecode serialization/deserialization (.sbc format) |
| `disassembler.zig` | Bytecode disassembler for `(disassemble proc)` |
| `testing_helpers.zig` | Shared `makeTestVM` helper for unit tests |
| `tests_ir.zig` | IR unit tests: bytecode parity, behavioral correctness, analysis passes, optimizations |
| `tests_*.zig` | Unit tests by feature (core_eval, tail_calls, macros, etc.) |

---

## Value Representation

All Scheme values fit in a single **NaN-boxed 64-bit word**. Flonums, fixnums,
booleans, characters, and nil all fit in a u64 with zero heap allocation:

```
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
    marked: bool = false, // GC mark bit
    next: ?*Object,      // intrusive linked list for GC
};
```

### ObjectTag enum (35 types)

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

---

## Garbage Collector

The GC is a **mark-and-sweep** collector using an **intrusive linked list**.

### Design

- All heap objects are linked via their `Object.next` pointer.
- The GC maintains a count of allocations since the last collection.
- When the count exceeds a threshold, a collection cycle runs:
  1. **Mark**: Traverse all roots, mark reachable objects.
  2. **Sweep**: Walk the linked list, free unmarked objects.

### Root tracking

Values on the Zig stack that hold pointers to heap objects must be protected
from GC if any allocation might happen before the pointer is used:

```zig
gc.pushRoot(&val);    // protect
// ... code that might allocate ...
gc.popRoot();         // unprotect (must be LIFO)
```

Roots are stored in a fixed-size root stack. `pushRoot`/`popRoot` calls must
be balanced and follow LIFO order.

---

## Bytecode Format

The compiler produces register-based bytecode. Each instruction is an `OpCode`
enum value followed by operands.

### Opcodes (31)

| Opcode | Operands | Description |
|--------|----------|-------------|
| `load_const` | dst:u8, idx:u16 | Load constant from pool |
| `load_nil` | dst:u8 | Load nil |
| `load_true` | dst:u8 | Load #t |
| `load_false` | dst:u8 | Load #f |
| `load_void` | dst:u8 | Load void |
| `move` | dst:u8, src:u8 | Copy register |
| `get_global` | dst:u8, sym_idx:u16 | Read global variable |
| `set_global` | sym_idx:u16, src:u8 | Write global variable |
| `define_global` | sym_idx:u16, src:u8 | Define global variable |
| `tail_apply` | base:u8, nargs:u8 | Tail `apply` (spreads final list arg) |
| `get_local` | dst:u8, slot:u8 | Read local variable |
| `set_local` | slot:u8, src:u8 | Write local variable |
| `get_upvalue` | dst:u8, idx:u8 | Read captured variable |
| `set_upvalue` | idx:u8, src:u8 | Write captured variable |
| `call` | base:u8, nargs:u8 | Call function |
| `tail_call` | base:u8, nargs:u8 | Tail call (reuses frame) |
| `return` | src:u8 | Return value |
| `jump` | offset:i16 | Unconditional jump |
| `jump_false` | test:u8, offset:i16 | Jump if register is `#f` |
| `jump_true` | test:u8, offset:i16 | Jump if register is not `#f` |
| `closure` | dst:u8, idx:u16 | Create closure from function |
| `close_upvalue` | slot:u8 | Close over a local variable |
| `cons` | dst:u8, car:u8, cdr:u8 | Allocate a pair |
| `push_handler` | handler_reg:u8 | Push exception handler |
| `pop_handler` | -- | Pop exception handler |
| `halt` | -- | Stop execution |
| `call_global` | base:u8, sym_idx:u16, nargs:u8 | Call a global directly (fused get_global + call) |
| `tail_call_global` | base:u8, sym_idx:u16, nargs:u8 | Tail-call a global directly |
| `box_local` | reg:u8 | Wrap a register value in a box (pair) for shared mutation |
| `get_box_local` | dst:u8, reg:u8 | Read the boxed value (car of box) |
| `set_box_local` | reg:u8, src:u8 | Set the boxed value (car of box) |

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
