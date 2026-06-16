# Kaappi — R7RS Scheme in Zig

Complete R7RS-small Scheme implementation. Zig 0.16, ~15k lines, 313 built-in procedures.

## Build

```
zig build              # build executable (zig-out/bin/kaappi)
zig build run          # launch REPL (linenoise: arrow keys, history, tab completion)
zig build run -- f.scm # run a Scheme file
zig build test         # run all unit tests
zig build bench        # call/cc vs call/ec capture micro-benchmark
```

Requires Zig 0.16+ and libc (for linenoise terminal handling).

Builds default to **ReleaseSafe** (fast, with bounds/safety checks retained;
fixnum overflow still wraps silently). Debug is ~500x slower for allocation-
and continuation-heavy workloads — only use it when debugging:
`zig build -Doptimize=Debug`. For maximum throughput: `-Doptimize=ReleaseFast`.

## Architecture

```
Source → Reader → Expander → Compiler → Bytecode → VM
         (UTF-8    (syntax-    (register-   (mark-and-
          lexer)    rules)      based)       sweep GC)
```

### Pipeline stages

| Stage | File | Role |
|-------|------|------|
| Reader | `reader.zig` | Tokenizer + recursive descent parser. Handles R7RS lexical syntax including Unicode identifiers and `#\λ` character literals. |
| Expander | `expander.zig` | `syntax-rules` pattern matching and template instantiation. Called by the compiler when a macro keyword is encountered. |
| Compiler | `compiler.zig` | S-expressions → register-based bytecode. Detects tail positions for TCO. Dispatches derived forms to sub-modules. |
| VM | `vm.zig` | Executes bytecode. Register file + call frame stack. Handles continuations (stack-copying), exception handler stack, dynamic-wind stack. |
| GC | `memory.zig` | Mark-and-sweep with intrusive linked list. Roots tracked via `gc.pushRoot`/`gc.popRoot`. Triggered after N allocations. |

### Value representation

Tagged u64 — no boxing for fixnums, booleans, characters, nil:
- **Bit 0 = 1**: fixnum (63-bit signed integer)
- **Bits 0-2 = 000**: pointer to heap `Object` (8-byte aligned)
- **Bits 0-1 = 10**: immediate (nil, true, false, void, eof, char with 21-bit codepoint)

Heap objects share an `Object` header with `ObjectTag` (u5, 32 slots) and GC mark bit. Types: Pair, Symbol, SchemeString, Closure, Function, NativeFn, Vector, Bytevector, Port, Flonum, Complex, Transformer, ErrorObject, RecordType, RecordInstance, Continuation, MultipleValues, Promise, ParameterObject.

### Strings

Stored as UTF-8 byte arrays. All string operations (string-length, string-ref, substring, etc.) index by **codepoint position**, not byte offset. Mutation via string-set! rebuilds the string when byte widths change.

## File organization

### Core runtime
| File | Lines | Responsibility |
|------|-------|---------------|
| `types.zig` | ~500 | Value type, heap object structs, ObjectTag enum, opcodes |
| `memory.zig` | ~650 | GC allocator, alloc/mark/free for all heap types |
| `reader.zig` | ~700 | Tokenizer, S-expression parser, Unicode lexing |
| `expander.zig` | ~320 | Macro expansion engine (syntax-rules) |
| `printer.zig` | ~300 | Value → string (write mode and display mode) |

### Compiler (split into 4 files)
| File | Responsibility |
|------|---------------|
| `compiler.zig` | Core: compileExpr dispatch, primitive forms (quote, if, lambda, define, set!, begin, call), macro handling, scope/register management |
| `compiler_conditionals.zig` | and, or, when, unless, cond, cond-expand |
| `compiler_bindings.zig` | let, let*, letrec, letrec*, named let, do, let-values, let*-values |
| `compiler_advanced.zig` | case, case-lambda, guard, quasiquote |
| `compiler_forms.zig` | Re-export hub (thin file, don't edit directly) |

### VM (split into 4 files)
| File | Responsibility |
|------|---------------|
| `vm.zig` | Core: execute, runUntil, callValue, eval, handleTopLevelForm dispatcher |
| `vm_library.zig` | handleImport (with only/except/rename/prefix), handleDefineLibrary, .sld file loading |
| `vm_records.zig` | handleDefineRecordType desugaring |
| `vm_continuations.zig` | captureContinuation, restoreContinuation, performWindTransition, callWithCC |

### Primitives (split into 11 files)
| File | Procedures |
|------|-----------|
| `primitives.zig` | Registration hub, core list/pair ops, type predicates, equivalence, map, for-each, apply |
| `primitives_arithmetic.zig` | +, -, *, /, comparisons, rounding, exactness, trig, exp/log, gcd/lcm |
| `primitives_string.zig` | string ops, char comparisons, number↔string, UTF-8 codepoint indexing |
| `primitives_char.zig` | (scheme char): Unicode classification, case conversion, CI comparisons |
| `primitives_vector.zig` | vector ops, vector-map, vector-for-each |
| `primitives_bytevector.zig` | bytevector ops, binary I/O, bytevector ports |
| `primitives_io.zig` | Port ops, file I/O, string ports, read/write/display |
| `primitives_control.zig` | raise, guard, with-exception-handler, call/cc, dynamic-wind, values |
| `primitives_lazy.zig` | delay, force, make-promise, promise? |
| `primitives_cxr.zig` | 24 car/cdr compositions (caaaar–cddddr) |
| `primitives_r7rs.zig` | time, process-context, eval, load, make-parameter |

### Other
| File | Responsibility |
|------|---------------|
| `library.zig` | Library registry, standard library registration ((scheme base), etc.) |
| `linenoise.zig` | Zig FFI wrapper for vendored linenoise C library |
| `main.zig` | Entry point, REPL loop with linenoise, file execution |
| `testing_helpers.zig` | Shared `makeTestVM` helper for unit tests |
| `tests_*.zig | Unit tests by feature (core_eval, tail_calls, macros, io, etc.) |

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

1. Add the string match in `compileForm` in `src/compiler.zig`:
   ```zig
   if (std.mem.eql(u8, name, "my-form")) return forms.compileMyForm(self, args, dst, is_tail);
   ```

2. Implement in the appropriate `compiler_*.zig` file.

3. Add re-export in `compiler_forms.zig`.

## How to add a new heap type

1. Add tag to `ObjectTag` enum in `src/types.zig` (slots 19+ available).
2. Add the struct with `header: Object` as first field.
3. Add `allocXxx` in `src/memory.zig`.
4. Handle in `markValue` (trace contained Values) and `freeObject` (free owned memory).
5. Add display in `src/printer.zig`.

## GC safety

When allocating between obtaining a pointer and using it, the pointer may become invalid if GC runs. Root values that must survive allocation:

```zig
var val = try gc.allocPair(a, b);
gc.pushRoot(&val);          // protect from GC
const other = try gc.allocPair(c, d);  // this might trigger GC
gc.popRoot();               // done, val is safe to use
```

Always root `Function*` pointers before calling `vm.execute()` — it allocates a closure wrapper internally.

## Tests

- **Unit tests**: `src/tests_*.zig` — named by feature: `tests_core_eval.zig`, `tests_macros.zig`, `tests_io.zig`, etc.. Run all with `zig build test`.
- **Scheme tests**: `tests/scheme/` organized by phase and compliance area. Run individually with `zig build run -- tests/scheme/compliance/vectors.scm`.
- **Adding tests**: Add Zig tests to the appropriate phase file. For Scheme tests, create `.scm` files that print expected output.

## Dependencies

- **linenoise** (vendored in `vendor/linenoise/`): BSD-licensed C library for REPL line editing, history, tab completion. Compiled as part of the Zig build.

## Known limitations

See the "Known limitations" section in `README.md` (single source of truth).
Implementation gotcha worth repeating here: fixnum arithmetic wraps on overflow
**silently** — no error even in Debug/ReleaseSafe builds, so a test that
overflows a 63-bit fixnum gets a wrapped result, not a failure.
