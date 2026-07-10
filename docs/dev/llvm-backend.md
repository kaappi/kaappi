# LLVM Native Backend

The LLVM backend compiles Scheme programs to native executables. It is
the second of two execution backends:

1. **Interpreter** (bytecode VM) — REPL, debugging, development
2. **LLVM backend** (this document) — native executables for deployment

## What LLVM provides vs what the runtime provides

LLVM replaces the machine-code backend, not the Scheme runtime.

**LLVM provides:**
- Optimization passes (constant propagation, inlining, loop optimization, etc.)
- Code generation for many architectures (x86_64, AArch64, RISC-V, etc.)
- Mature debugging support (DWARF)
- Object file generation
- Link-time optimization (LTO)
- Platform portability

**The Kaappi runtime provides (unchanged):**
- Garbage collector (mark-and-sweep, `memory.zig`)
- Closure representation (Function + upvalues)
- NaN-boxed value scheme (tagged u64)
- Continuation support (stack-copying, VM fallback)
- 601 built-in procedures (primitives)
- String, vector, port, record, and other heap types

In other words, the LLVM-generated native code calls into the same Zig
runtime that the bytecode VM uses. The native binary links against
`libkaappi_rt.a` which contains the full runtime.

## Architecture

```
Source → Reader → Expander → IR → Analysis → Optimization
                                                    |
                              +---------------------+---------------------+
                              |                                           |
                        Bytecode Emission                          LLVM IR Emission
                              |                                           |
                            VM                                       zig cc
                              |                                           |
                        Interpreter                               Native Binary
                    (REPL, debugging)                        (links libkaappi_rt.a)
```

Both backends consume the same IR after the same analysis and optimization
passes. The split happens only at the emission stage.

## C-ABI Runtime Bridge

The LLVM IR cannot call Zig functions directly (error unions, name
mangling). A thin C-ABI wrapper in `src/runtime_exports.zig` exports
functions that native code calls:

| Function | Purpose |
|----------|---------|
| `kaappi_runtime_init` | Create GC, VM, register primitives, return VM pointer |
| `kaappi_runtime_deinit` | Clean up VM and GC |
| `kaappi_global_lookup` | Look up a global variable by name |
| `kaappi_call_scheme` | Call a Scheme procedure (closure, native, etc.) via `VM.callWithArgs` |
| `kaappi_define_global` | Define a global variable |
| `kaappi_make_string` | Allocate a string on the GC heap |
| `kaappi_intern_symbol` | Intern a symbol via the GC symbol table (ensures `eq?` identity) |
| `kaappi_eval` | Parse, compile, and evaluate a Scheme expression |

All functions use `callconv(.c)` and pass Values as plain `u64` (the
NaN-boxed representation crosses C ABI trivially).

## Build and Usage

### Manual three-step flow

```bash
zig build lib                                        # build libkaappi_rt.a
kaappi --emit-llvm -o program.ll program.scm         # emit LLVM IR
zig cc -w program.ll -o program \
    -Lzig-out/lib -lkaappi_rt -lc -lm -lpthread      # link native binary
./program                                            # run
```

### Single-step build

```bash
zig build native -Dnative-src=program.scm            # all-in-one
./zig-out/bin/program                                # run
```

**Always use `zig cc` (not `clang`) for linking.** The Zig-compiled static
library references `__zig_probe_stack` and other Zig compiler-rt intrinsics
that `clang` cannot resolve.

## LLVM IR Emission

The emitter (`src/llvm_emit.zig`) walks IR nodes and produces LLVM IR text
(`.ll` files). All 33 IR node types are handled:

| Node | LLVM IR output |
|------|---------------|
| `constant` | Literal `i64` for immediates; `kaappi_make_string` for strings; `kaappi_intern_symbol` for symbols; `(quote ...)` via `kaappi_eval` for other heap values |
| `global_ref` | `call @kaappi_global_lookup(...)` |
| `call` | Stack-allocate args array, `call @kaappi_call_scheme(...)` |
| `begin` | Emit each expression sequentially |
| `if` | LLVM basic blocks with `br`/`phi` |
| `and`/`or` | Short-circuit with basic blocks and `phi` |
| `when`/`unless` | Conditional body execution |
| `define` | `call @kaappi_define_global(...)` (compound values via `kaappi_eval`) |
| `set!` | `call @kaappi_define_global(...)` |
| `lambda` | Serialize to source text, `call @kaappi_eval(...)` |
| `let`, `letrec`, `cond`, `case`, `do`, `guard`, etc. | Serialize to source text, `call @kaappi_eval(...)` |
| `passthrough` | Serialize to source text, `call @kaappi_eval(...)` |

## Compile-Time Processing

The `--emit-llvm` path processes certain top-level forms at compile time
so their effects are available to subsequent expressions during IR lowering:

| Form | Compile-time action |
|------|-------------------|
| `import` | Loads the library, registers bindings in VM globals |
| `define-library` | Registers the library in the VM |
| `define-syntax` | Compiles and executes the macro definition |
| `define-record-type` | Compiles and executes the record type definition |

All four are also emitted as `kaappi_eval` calls for runtime execution
in the native binary.

## Heap-Allocated Constants

Constants that are heap objects (pairs, vectors, symbols, strings) cannot
be embedded as raw pointer values in LLVM IR — those pointers reference
the compile-time GC heap which doesn't exist at runtime. Each type is
handled differently:

- **Strings**: `kaappi_make_string(vm, data_ptr, len)` — allocated at runtime
- **Symbols**: `kaappi_intern_symbol(vm, name_ptr, len)` — interned at runtime,
  ensuring `eq?` identity matches between native code and interpreter closures
- **Pairs, vectors, other heap values**: Serialized via `(quote ...)` and
  evaluated at runtime via `kaappi_eval`
- **Fixnums, booleans, characters, nil, void**: Embedded directly as `i64`
  literals (these are NaN-boxed immediates with no heap allocation)

## Lambda Strategy

Lambda bodies are stored as raw S-expressions in the IR, not as
pre-lowered IR nodes. The LLVM emitter serializes the lambda source text,
embeds it as an LLVM IR string constant, and evaluates it at runtime:

```llvm
@.str.0 = private constant [23 x i8] c"(lambda (x) (* x x))"
; ...
%closure = call i64 @kaappi_eval(ptr %vm, ptr @.str.0, i64 23)
```

The resulting Closure Value is callable via `kaappi_call_scheme`, which
dispatches through the VM's `callWithArgs` (handles closures, native
functions, continuations, etc.).

This approach is correct but not optimal — each lambda is parsed and
compiled at startup. A future optimization would lower lambda bodies
directly to LLVM IR functions.

## Testing

End-to-end tests live in `tests/e2e/`:

- `run-e2e.sh` — builds the runtime, runs BDD specs, compiles each test
  program to native via LLVM IR, and diffs output against the interpreter
- `test-llvm-backend.scm` — BDD specs using `kaappi-bdd`
- `programs/*.scm` — test programs compiled to native binaries

Run with: `bash tests/e2e/run-e2e.sh`

The e2e tests run in CI on Ubuntu ReleaseSafe builds. The `KAAPPI_CC`
environment variable controls the C compiler (defaults to `zig cc`).

### What's been stress-tested

- Closures with message dispatch (`eq?` on quoted symbols)
- Recursive functions on quoted data (`flatten`, `my-len`)
- Error handling with `guard`
- User-defined macros (`define-syntax`)
- SRFI libraries (SRFI-1, SRFI-13, SRFI-69)
- Unicode strings, string ports, string mutation
- Higher-order functions (`map`, `filter`, `fold`)
- Tail-recursive loops (100k iterations)

## Related Documents

- [ir.md](ir.md) — IR node types, analysis passes, optimization passes
- [continuation-strategy.md](decisions/continuation-strategy.md) — hybrid approach
  for `call/cc` in native code (VM fallback)
- [architecture.md](architecture.md) — overall pipeline and file organization
