# LLVM Native Backend

The LLVM backend compiles Scheme programs to native executables. It is
the second of two execution backends:

1. **Interpreter** (bytecode VM + JIT) — REPL, debugging, development
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
- 554 built-in procedures (primitives)
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
                         VM + JIT                                   clang / zig cc
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
| `kaappi_call_scheme` | Call a Scheme procedure (closure, native, etc.) |
| `kaappi_define_global` | Define a global variable |
| `kaappi_make_string` | Allocate a string on the GC heap |
| `kaappi_eval` | Parse, compile, and evaluate a Scheme expression |

All functions use `callconv(.c)` and pass Values as plain `u64` (the
NaN-boxed representation crosses C ABI trivially).

## Build and Usage

```bash
zig build lib                                        # build libkaappi_rt.a
kaappi --emit-llvm program.scm -o program.ll         # emit LLVM IR
zig cc -w program.ll -o program \
    -Lzig-out/lib -lkaappi_rt -lc -lm -lpthread      # link native binary
./program                                            # run
```

**Always use `zig cc` (not `clang`) for linking.** The Zig-compiled static
library references `__zig_probe_stack` and other Zig compiler-rt intrinsics
that `clang` cannot resolve.

## LLVM IR Emission

The emitter (`src/llvm_emit.zig`) walks IR nodes and produces LLVM IR text
(`.ll` files). Supported IR node types:

| Node | LLVM IR output |
|------|---------------|
| `constant` | Literal `i64` value (NaN-boxed) |
| `global_ref` | `call @kaappi_global_lookup(...)` |
| `call` | Stack-allocate args array, `call @kaappi_call_scheme(...)` |
| `begin` | Emit each expression sequentially |
| `if` | LLVM basic blocks with `br`/`phi` |
| `define` | `call @kaappi_define_global(...)` |
| `lambda` | Serialize to source text, `call @kaappi_eval(...)` |

String constants are heap-allocated at runtime via `kaappi_make_string`.
Lambda bodies are compiled at runtime via `kaappi_eval` (the interpreter
handles the full compilation pipeline).

## Lambda Strategy

Lambda bodies are stored as raw S-expressions in the IR, not as
pre-lowered IR nodes. The LLVM emitter cannot compile them directly.
Instead, it serializes the lambda source text, embeds it as an LLVM IR
string constant, and evaluates it at runtime:

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

## Future: Replacing the JIT

Once the LLVM backend matures, the hand-written JIT backends
(`jit_compile_aarch64.zig`, `jit_compile_x86_64.zig`, and supporting
files) will be removed. LLVM subsumes their role with better optimization
and broader architecture support. See issue #99 for tracking.

## Testing

End-to-end tests live in `tests/e2e/`:

- `run-e2e.sh` — builds the runtime, runs BDD specs, compiles each test
  program to native via LLVM IR, and diffs output against the interpreter
- `test-llvm-backend.scm` — BDD specs using `kaappi-bdd`
- `programs/*.scm` — test programs compiled to native binaries

Run with: `bash tests/e2e/run-e2e.sh`

## Related Documents

- [ir.md](ir.md) — IR node types, analysis passes, optimization passes
- [continuation-strategy.md](continuation-strategy.md) — hybrid approach
  for `call/cc` in native code (VM fallback)
- [architecture.md](architecture.md) — overall pipeline and file organization
