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
zig cc -w -O2 program.ll -o program \
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

## Optimization and IR verification

The emitter produces deliberately naive IR and relies on LLVM to clean it up:
every immediate is `add i64 0, K` (`emitImm`), let-bindings / shadow-stack root
slots / args arrays go through `alloca`/`load`/`store`, and `if`/`and`/`or`
become long `br`/`phi` chains. All three link flows above pass **`-O2`** so
mem2reg, instcombine, simplifycfg, and constant folding collapse this — at `-O0`
none of the optimization that is the point of using LLVM runs. (Root-slot
`alloca`s whose address escapes into `kaappi_gc_push_root` correctly stay in
memory; the collector scans them.)

Because the IR is hand-written, well-formedness bugs can pass `-O0` yet break or
miscompile under `-O2`'s stricter verifier and passes (e.g. an orphan block left
after a tail call, or mismatched `phi` operands). The e2e harness
(`tests/e2e/run-e2e.sh`) verifies every emitted `.ll` before linking — with
`opt -passes=verify`, `llvm-as`, or, when neither is on `PATH`, `zig cc -c`
(same bundled LLVM that links the binary). The verifier runs **without** `-w`,
so no malformed-IR diagnostic is hidden. To verify a single file by hand:

```bash
kaappi --emit-llvm -o program.ll program.scm
opt -passes=verify -disable-output program.ll        # or: llvm-as -o /dev/null program.ll
```

The `-w` on the link commands only silences cosmetic warnings on generated IR
for end users; a hard verifier **error** still fails the compile regardless.

Cross-module inlining of the runtime primitives (`kaappi_fixnum_add`,
`kaappi_car`, …) needs LTO and is tracked separately — `-O2` alone already
cleans up the emitter's own IR substantially.

## LLVM IR Emission

The emitter (`src/llvm_emit.zig`) walks IR nodes and produces LLVM IR text
(`.ll` files). All 33 IR node types are handled:

| Node | LLVM IR output |
|------|---------------|
| `constant` | Literal `i64` for immediates; `kaappi_make_string` for strings; `kaappi_intern_symbol` for symbols; `(quote ...)` via `kaappi_eval` for other heap values |
| `global_ref` | `call @kaappi_global_lookup(...)` |
| `call` | Three paths: inlined primitive (`+ - * < = car cdr cons null?`); direct `call`/`tail call` to a known native function; otherwise stack-allocate args array and `call @kaappi_call_scheme(...)` |
| `begin` | Emit each expression sequentially |
| `if` | LLVM basic blocks with `br`/`phi` |
| `and`/`or` | Short-circuit with basic blocks and `phi` |
| `when`/`unless` | Conditional body execution |
| `define` | Function definitions compiled to a native LLVM function (see Lambda Strategy); other values `call @kaappi_define_global(...)` (compound values via `kaappi_eval`) |
| `set!` | Store to the resolved lexical slot (local/param/upvalue) or `call @kaappi_set_global(...)` |
| `lambda` | Compiled to a native LLVM function + closure, or `kaappi_eval` fallback (see Lambda Strategy) |
| `let`, `let*` | Native `alloca`s with shadow-stack rooting; falls back to `kaappi_eval` for forms it cannot lower in scope |
| `letrec`, `letrec*`, `cond`, `case`, `do`, `guard`, quasiquote, named `let` | Serialize to source text, `call @kaappi_eval(...)` |
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

Lambdas and named function definitions are compiled through a tiered strategy
(`src/llvm_emit_lambda.zig`). Each tier lowers the body through the **same IR**
the rest of the emitter uses, so a lambda body gets real basic blocks, inlined
primitives, and direct calls — not a re-parse at startup.

Every native function has the uniform C-ABI signature:

```llvm
define i64 @lambda_0(ptr %vm, ptr %args, i64 %nargs, ptr %upvalues) { ... }
```

Fixed parameters are read from `%args`, captured variables from `%upvalues`.

The three tiers, tried in order:

1. **Capturing lambda** (`tryCompileNativeClosure`) — a lambda with free
   variables. The body compiles to an `@closure_N` function; free variables are
   discovered by free-variable analysis (`collectFreeVars`) and **copied by
   value** into an `%upvalues` array at closure-creation time (sourced from the
   enclosing frame's `%args`, or, for a lambda nested in another native closure,
   chained out of that closure's own `%upvalues` — #1410). The closure value is
   materialized with `kaappi_create_native_closure`.

2. **Closed lambda / named function** (`tryCompilePureLambdaAsNativeClosure`,
   `tryCompileDefineFunction`) — no free variables (only parameters and known
   globals). Compiles to an `@lambda_N` function created with a null upvalue
   array. A top-level `(define (f ...) ...)` takes this path and registers `f`
   in `native_fns`, so later call sites emit a **direct** `call`/`tail call`
   instead of going through `kaappi_call_scheme`.

3. **Eval fallback** (`emitLambdaViaEval`) — when neither native tier applies,
   serialize `(lambda ...)` to source text and `kaappi_eval` it at runtime. A
   lambda that appears inside a `let` body and cannot compile natively instead
   forces the whole enclosing `let` to the interpreter, preserving lexical
   scope (#827).

**Supported natively:** fixed arity; variadic **rest parameters** (the rest
list is built with a `kaappi_cons` loop, `emitRestListBuilder`); closures with
by-value capture; and **self-tail-recursion compiled as a loop** — a self-call
in tail position stores the new arguments and `br`s back to the function's body
label rather than recursing (non-variadic named functions only).

**Falls back to `kaappi_eval` when the body:**
- contains an eval-fallback form (`letrec`, `cond`, `case`, `do`, `guard`,
  named `let`, …);
- mutates or internally defines a captured variable — the by-value upvalue
  model cannot express mutation, and snapshotting at creation time would
  diverge from the VM's by-**location** closure semantics (#819, #1422);
- captures a `let`-local or rest parameter that has no copyable slot; or
- exceeds a fixed analysis limit (parameter/body-node/name buffers).

The resulting value (native closure or eval'd closure) is uniformly callable
via `kaappi_call_scheme`, which dispatches through the VM's `callWithArgs`
(closures, native functions, continuations, etc.).

## Testing

End-to-end tests live in `tests/e2e/`:

- `run-e2e.sh` — builds the runtime, runs BDD specs, verifies each program's
  emitted IR, compiles it to native via LLVM IR at `-O2`, and diffs output
  against the interpreter
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
