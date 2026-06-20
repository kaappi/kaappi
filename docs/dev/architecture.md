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
+--------+     +----------+     +----------+     +----------+     +----+
| Reader | --> | Expander | --> | Compiler | --> | Bytecode | --> | VM |
| (UTF-8 |     | (syntax- |     | (register|     |          |     |    |
|  lexer)|     |  rules)  |     |  -based) |     |          |     |    |
+--------+     +----------+     +----------+     +----------+     +----+
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
| **Compiler** | `compiler.zig` + 5 sub-modules | Compiles S-expressions to register-based bytecode. Detects tail positions for proper tail call optimization. Dispatches 32 syntax forms across 6 files. |
| **VM** | `vm.zig` + 5 sub-modules | Executes bytecode with a register file, call frame stack, exception handler stack, and dynamic-wind stack. First-class continuations via stack copying, plus a stepping debugger. |
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

### Compiler (6 files)

| File | Responsibility |
|------|---------------|
| `compiler.zig` | Core: expression dispatch, primitive forms (quote, if, call), macro handling, scope/register management |
| `compiler_lambda.zig` | lambda, define, set!, begin, delay, delay-force, body compilation |
| `compiler_conditionals.zig` | and, or, when, unless, cond, cond-expand |
| `compiler_bindings.zig` | let, let*, letrec, letrec*, named let, do, let-values, let*-values |
| `compiler_advanced.zig` | case, case-lambda, guard, quasiquote |
| `compiler_forms.zig` | Re-export hub (thin file that exposes all form compilers) |

### VM (6 files)

| File | Responsibility |
|------|---------------|
| `vm.zig` | Core: execute loop, runUntil, callValue, instruction dispatch |
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
| `primitives_ffi.zig` | FFI procedure registration (ffi-open, ffi-fn, ffi-close) |
| `primitives_r7rs.zig` | Time, process-context, eval, load, make-parameter |

### Other

| File | Responsibility |
|------|---------------|
| `library.zig` | Library registry, standard library registration |
| `linenoise.zig` | Zig FFI wrapper for vendored linenoise C library |
| `main.zig` | Entry point, REPL loop, file execution, bytecode caching |
| `ffi.zig` | FFI call dispatcher (type marshaling, arity routing) |
| `bignum.zig` | Arbitrary-precision integer arithmetic |
| `bytecode_file.zig` | Bytecode serialization/deserialization (.sbc format) |
| `bench.zig` | Micro-benchmarks |
| `testing_helpers.zig` | Shared `makeTestVM` helper for unit tests |
| `tests_*.zig | Unit tests by feature (core_eval, tail_calls, macros, etc.) |

---

## Value Representation

All Scheme values fit in a single **tagged 64-bit word**. The tag bits are in
the low-order positions:

```
Fixnum:    [...63-bit signed integer...][1]     -- bit 0 = 1
Pointer:   [...61-bit pointer.........][000]    -- 8-byte aligned heap object
Immediate: [...payload...][type:5][10]          -- nil, bool, void, eof, char
```

### Three categories

**Fixnums** (bit 0 = 1): 63-bit signed integers. No heap allocation. The value
is shifted left by 1 and OR'd with 1.

**Pointers** (low 3 bits = 000): Point to heap-allocated `Object` structs.
All heap objects are 8-byte aligned so the low 3 bits are naturally zero.

**Immediates** (low 2 bits = 10): Nil, true, false, void, EOF, and characters.
Characters encode a 21-bit Unicode codepoint in the payload.

This design means the most common types (integers, booleans, characters, nil)
require zero heap allocation.

---

## Heap Objects

Every heap object starts with an `Object` header:

```zig
pub const Object = struct {
    tag: ObjectTag,      // u5 -- which type
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
