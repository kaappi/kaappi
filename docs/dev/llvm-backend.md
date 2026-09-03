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
- 717 built-in procedures (primitives)
- String, vector, port, record, and other heap types

In other words, the LLVM-generated native code calls into the same Zig
runtime that the bytecode VM uses. The native binary links against
`libkaappi_rt.a` which contains the full runtime.

## Architecture

```text
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
| `kaappi_make_box` / `kaappi_box_ref` / `kaappi_box_set` | Allocate / read / write a one-slot heap box for a captured+mutated variable (assignment conversion, see [Mutable captured variables](#mutable-captured-variables-assignment-conversion)) |
| `kaappi_eval` | Parse, compile, and evaluate a Scheme expression (now only the uncached fallback path inside the two caching entry points below, and the child-thread path) |
| `kaappi_eval_cached` | Like `kaappi_eval`, but compiles the source once per call site and caches the resulting `Function` in a per-site global slot (see [Cached eval fallback](#cached-eval-fallback)) |
| `kaappi_quote_cached` | Build a quoted heap constant once per call site and memoize the built value in a per-site global slot (see [Cached quoted constants](#cached-quoted-constants)) |

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

### Where `kaappi compile` looks for `libkaappi_rt.a`

In order: the `KAAPPI_LIB_DIR` environment variable, `<exe_dir>/../lib/`,
`zig-out/lib/`, then `/usr/local/lib/`. It searches `PATH` for a C compiler
(`zig cc`, `cc`, `clang`, `gcc`).

`~/.kaappi/lib` is deliberately **not** on that list — it is thottam's
Scheme-library and FFI-`dlopen` directory, so an archive placed there is
invisible to `kaappi compile`. The install script therefore puts the archive in
`<INSTALL_DIR>/../lib` (`~/.local/lib` by default), which lands on the
`<exe_dir>/../lib` entry with no environment variable set.

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

### Inline primitive fast paths

`-O2` cleans up the emitter's own scaffolding but cannot inline the runtime
primitives (`kaappi_fixnum_add`, `kaappi_car`, …): they live in the static
archive `libkaappi_rt.a`, on the far side of a compilation boundary `-O2` alone
cannot cross. So the hottest primitives are emitted **as inline IR** instead of
calls (#1493, in `src/llvm_emit_inline.zig`), removing the per-operation call in
the common case:

| Primitive | Inline fast path | Slow-path fallback |
|-----------|------------------|--------------------|
| `+` `-` `*` | fixnum-tag check on both operands → `llvm.sadd/ssub/smul.with.overflow.i64` on the sign-extended payloads → re-box if the result is in i48 range | `call @kaappi_fixnum_{add,sub,mul}` when an operand is not a fixnum, or the result overflows the i48 range (→ bignum) |
| `<` `=` | fixnum-tag check → `icmp slt` (sign-extended) / `icmp eq` (raw) → boolean `select` | `call @kaappi_fixnum_{lt,eq}` for the full numeric tower |
| `null?` | `icmp eq` against the nil immediate → `select` | none (pure) |

The fast paths touch only the **NaN-boxed Value bits** (fixnum tag, payload,
nil/boolean immediates), whose encoding is stable and is pulled from `types.zig`
at emitter comptime (`nanbox` in `llvm_emit_inline.zig`) — no magic numbers are
hand-transcribed into the IR. `car`, `cdr`, and `cons` deliberately stay as
direct specialized calls: `Pair`/`Object` are **auto-layout** (non-`extern`)
structs whose field offsets Zig does not guarantee, so they cannot be encoded in
hand-written IR, and `cons` allocates regardless.

The inline binary path also **elides the shadow-stack rooting** (a
`kaappi_gc_push_root`/`kaappi_gc_pop_roots` call pair) that keeps the first
operand alive across the second's evaluation, whenever the second operand is a
leaf that cannot allocate (a variable reference or an immediate constant —
`nodeMayAllocate`). For a hot arithmetic loop this is the difference between a
handful of runtime calls per operation and none: `fib(38)` runs ~3.3× faster
than `-O2`-only.

> **Why not LTO?** Building `libkaappi_rt.a` as bitcode and linking with `-flto`
> would let LLVM inline every primitive, but Zig's toolchain cannot use LLD for
> Mach-O (`using LLD to link macho files is unsupported`) and LTO requires LLD —
> so `-flto` is unavailable on macOS, the primary dev platform, and would only
> work when targeting Linux. Inline IR is portable across every target (it is
> just text the emitter writes) and needs no cross-module inlining.

## LLVM IR Emission

The emitter (`src/llvm_emit.zig`) walks IR nodes and produces LLVM IR text
(`.ll` files). All 33 IR node types are handled:

| Node | LLVM IR output |
|------|---------------|
| `constant` | Literal `i64` for immediates; `kaappi_make_string` for strings; `kaappi_intern_symbol` for symbols; `(quote ...)` via `kaappi_quote_cached` (built once per call site) for other heap values |
| `global_ref` | `call @kaappi_global_lookup(...)` |
| `call` | Five paths: inline-IR fast path for `+ - * < = null?` (see [Inline primitive fast paths](#inline-primitive-fast-paths)); direct specialized call for `car cdr cons`; a register-argument `call tailcc` (or guaranteed `musttail call tailcc` in tail position) to a known native **fast entry** (see [Guaranteed mutual tail calls](#guaranteed-mutual-tail-calls-tailcc--musttail)); a uniform-ABI `call`/`tail call` to a known native function without a fast entry (variadic / boxed / over the arity bound); otherwise stack-allocate args array and `call @kaappi_call_scheme(...)` |
| `begin` | Emit each expression sequentially |
| `if` | LLVM basic blocks with `br`/`phi` |
| `and`/`or` | Short-circuit with basic blocks and `phi` |
| `when`/`unless` | Conditional body execution |
| `define` | Function definitions compiled to a native LLVM function (see Lambda Strategy). A fixed-arity one's global value is a native closure over that entry (`kaappi_create_native_closure`, #1500); a variadic one's value stays `kaappi_eval_cached`. Non-lambda values: `call @kaappi_define_global(...)` (compound values via `kaappi_eval_cached`) |
| `set!` | Store to the resolved lexical slot (local/param/upvalue) or `call @kaappi_set_global(...)` |
| `lambda` | Compiled to a native LLVM function + closure, or cached eval fallback (see Lambda Strategy) |
| `let`, `let*` | Native `alloca`s with shadow-stack rooting, for the bindings and the body's head internal defines alike (see [Internal defines in a `let` body](#internal-defines-in-a-let-body)); falls back to `kaappi_eval_cached` for forms it cannot lower in scope — a nested one declines instead, so the whole enclosing scope goes to the interpreter as one unit (kaappi#1862, `src/llvm_emit_let.zig`) |
| `cond`, `case`, `do` | Native `if`-style block/`phi` chains (`cond`/`case`) and a self-branching `alloca` loop (`do`) when every sub-form is emittable in the current lexical scope; otherwise a whole-form `kaappi_eval_cached` fallback (`src/llvm_emit_forms.zig`, kaappi#1496) |
| `letrec`, `letrec*`, `guard`, quasiquote, named `let` | Serialize to source text, `call @kaappi_eval_cached(...)` (see [Cached eval fallback](#cached-eval-fallback)) |
| `passthrough` | Serialize to source text, `call @kaappi_eval_cached(...)` |

### Lexical scope in a re-lowered body (kaappi#2117, kaappi#2118)

The backend does not emit from the IR tree it was handed. Every `lambda`,
closure and `let` body is a raw S-expression at that point, **re-lowered**
during emission through a scratch `ir.IR` — `LLVMEmitter.lowerScoped`, and the
three `body_ir` instances in `llvm_emit_lambda.zig`. A scratch IR has no
`Compiler`, and `IR` asks the `Compiler` two separate questions while lowering:

- **is this name lexically bound?** (`lowerFormWithMacros`'s `is_shadowed`) —
  decides whether `(if 1 2)` is the special form or a call to a binding named
  `if`. R7RS has no reserved words (§4.3.1).
- **may this name's value change?** (`isRedefined`) — gates constant folding,
  from both a shadowing binding and a `set!` elsewhere in the form.

Two `IR` fields stand in for the Compiler on this path, and **both must be
supplied at every lowering site** or the tiers silently disagree:

| Field | Native source | What it replaces |
|-------|---------------|------------------|
| `bound_names` | `LLVMEmitter.lexicalNames(extra)` | `Compiler.isLexicallyBound` |
| `set_targets` | `LLVMEmitter.set_targets`, from `native_compiler.zig` | `Compiler.compile`'s per-form `set!` pre-scan |

`lexicalNames` is **derived**, not maintained: it reads the same
`locals`/`boxes`/`rest_param_name`/`params`/`upvalues` maps `emitGlobalRef`
resolves against, in that order, plus an `extra` list for a frame whose scope
is not installed yet (a lambda body is lowered before `emitLambdaFunction`
swaps `params` in). A hand-kept parallel list is exactly what drifted: the
backend passed only the immediate frame's parameter names, so a binding one
level out was invisible to *both* questions, and `set_targets` was never
passed at all. `(define (outer +) (lambda () (+ 5 2)))` folded to 7,
`(define (f) (set! + -) (+ 5 2))` folded to 7, and `(define (f if) (if 1 2))`
lowered as the special form — each a plausible number from a binary whose
interpreter run gives a different one.

`set_targets` is whole-program here rather than per-top-level-form: the
emitter runs only after the read loop has seen every form, and every form of a
compiled binary runs in one process anyway. It is strictly more conservative
than the interpreter's own pre-scan, which costs folding and never
correctness. `compiler.scanSetTargetsWithoutMacros` is that pre-scan minus
macro expansion (which needs a `Compiler`); the backend already declines
native compilation of any body containing a macro use (kaappi#1807), so the
two limits line up.

`tests/scheme/compile/native-lexical-scope-fold-2117-2118.sh` runs the three
`.scm` regression suites these bugs already owned — `#788`, `#790`,
`set-redefine-fold` — through `kaappi compile`. Nothing had, which is why all
three passed under the interpreter while failing 9, 1 and 6 assertions
natively.

### Internal defines in a `let` body

An internal `(define <symbol> <expr>)` in a natively emitted `let` body is a
lexical binding, not a global (kaappi#819) — it lives in an `alloca` registered
in the emitter's `locals` map, so it shadows any same-named global for the rest
of the body. `emitLet` is the only tier that sets up such a scope; the closure
and lambda tiers decline a body containing an internal define outright, so this
path is reachable only from the top-level body and the lets nested inside it.

The slots are **minted, rooted, and counted by `emitLet`, not by `emitDefine`**
(kaappi#1854). Before emitting the body, `emitLet` walks the leading run of
`(define <symbol> <expr>)` forms — R7RS's position for internal definitions —
and for each mints an `alloca`, stores `VOID` into it, pushes it on the shadow
stack, registers it in `locals`, and adds it to the same `binding_root_count`
the bindings use. `emitDefine`'s internal path then only evaluates the
initializer and stores into that slot; `LLVMEmitter.scope_define_names` is how
it recognizes one.

Two things make this the right owner:

- **Rooting.** `emitDefine` used to mint the slot itself and never push it, so
  the binding held the only reference to a freshly allocated value across every
  later allocation in the body. A collection freed it and the memory was
  recycled into whatever came next — a wrong answer with no crash:
  `(let ((a 1)) (define xs (list 11 22 33)) <allocate> (car xs))` returned a
  loop counter.
- **A static push count.** The scope pops a fixed `n` at exit, so every push it
  counts has to execute exactly once. Pushes emitted at the head of the body
  dominate it; one emitted at a define nested inside an `if` would not. Those
  defines are exactly the ones `scope_define_names` omits, and `emitDefine`
  answers `error.UnsupportedNodeType` for them, so the enclosing `let` abandons
  and the interpreter — which binds a non-head define correctly — takes the
  whole form.

Pre-creating every slot before any initializer runs is also letrec* semantics,
which is what a body of internal definitions means: a forward or self reference
reads `VOID` (bound but not yet assigned) rather than the uninitialized `alloca`
it read before.

Rooting these slots cannot interact with `musttail` (kaappi#1499): `mustTailSafe`
already requires `self.locals == null`, which is never true inside a `let` body.

The procedure shorthand `(define (f …) …)` is a different path — `ir.lowerDefine`
turns it into a `passthrough`, so it never reaches `emitDefine` and none of the
above applies to it. `emitPassthrough` **declines it whenever a lexical scope is
active** (kaappi#1861), which is the only place that decision can be made: both
of its paths define a global (`kaappi_define_global` when the body compiles
natively, and otherwise an `emitEvalExpr` that runs in the global environment).
The enclosing scope then goes to the interpreter whole — a `let` body abandons
via `emitLet`, and a function body fails `emitLambdaFunction`, so the whole
`define` falls back. Until that fix an internal `(define (g) …)` overwrote a
same-named global (the interpreter merely shadows it), and one referencing an
enclosing binding compiled to a global function whose body looked that binding
up as a global — `(let ((a 3)) (define (h n) (* n a)) (h 5))` died with
`undefined variable 'a'` in a binary the interpreter runs fine.

Declining also **drops the name from `native_fns`/`rebound_globals` first**.
This interpreter rebinds a body define that is *not* at the head of its body as
a global, and a later call site that kept its direct call to the top-level
function of the same name cannot observe that. Compiling the shorthand as a
native local binding instead — the fuller fix — would need the closure value in
a rooted slot (the kaappi#1854 machinery extended to a lambda-valued define)
plus a way to keep the inner name out of the module-wide `native_fns` map, where
it would capture direct call sites outside the scope that defined it.

## Compile-Time Processing

The `--emit-llvm` path processes certain top-level forms at compile time
so their effects are available to subsequent expressions during IR lowering:

| Form | Compile-time action |
|------|-------------------|
| `import` | Loads the library, registers bindings in VM globals |
| `define-library` | Registers the library in the VM |
| `define-syntax` | Compiles and executes the macro definition |
| `define-record-type` | Compiles and executes the record type definition |

All four are also serialized for runtime execution in the native binary. They
emit through `kaappi_eval_cached` like other passthrough forms, but as special
top-level forms they are not cacheable — `kaappi_eval_cached` declines them and
runs a plain `eval` each time (see [Cached eval fallback](#cached-eval-fallback)).

**`import` only works at runtime for libraries built into the Zig binary**
(#1743). `kaappi_runtime_init` (`runtime_exports.zig`) starts the compiled
binary's own VM with no library search path, and the native backend does not
bundle `.sld` sources into the binary the way the `--compile`/`-Dbundle-src`
`.sbc` pathway does. So while the compiling VM resolves an `import` against
its own `--lib-path`/auto-discovered directories just fine — including a
third-party package or any of the 159 portable SRFIs — that exact resolution
is unrepeatable inside the runtime binary's fresh VM, and re-running the
serialized `import` form there raises "library not found". `emitLlvmFile`
therefore refuses to emit anything (a compile-time error, not a broken
binary) when it resolves any import from a `.sld` file rather than kaappi's
built-in registry: it repurposes the `.sbc` bundler's own
`vm.compile_collect_files` hook purely to detect this, since
`processImportSet` (`vm_library.zig`) checks the built-in registry first and
only records a file there when a library is resolved from disk. Both
`kaappi compile` and `--emit-llvm` go through `emitLlvmFile`, so both refuse
identically; the working alternatives are the interpreter or
`zig build -Dbundle-src=<file>`.

## Heap-Allocated Constants

Constants that are heap objects (pairs, vectors, symbols, strings) cannot
be embedded as raw pointer values in LLVM IR — those pointers reference
the compile-time GC heap which doesn't exist at runtime. Each type is
handled differently:

- **Strings**: `kaappi_make_string(vm, data_ptr, len)` — allocated at runtime
- **Symbols**: `kaappi_intern_symbol(vm, name_ptr, len)` — interned at runtime,
  ensuring `eq?` identity matches between native code and interpreter closures
- **Pairs, vectors, other heap values**: Serialized via `(quote ...)` and built
  at runtime via `kaappi_quote_cached`, which builds the constant once per call
  site and memoizes it in a global slot (#1495) — so a literal in a hot path is
  no longer re-consed per execution, and every evaluation returns the same object
  (`eq?`), matching the interpreter's constant-pool sharing. See
  [Cached quoted constants](#cached-quoted-constants).
- **Fixnums, booleans, characters, nil, void**: Embedded directly as `i64`
  literals (these are NaN-boxed immediates with no heap allocation)

## Cached eval fallback

Forms the backend cannot lower natively — `letrec`, `letrec*`, `guard`,
quasiquote, named `let`, `let`/`let*` it cannot scope, a `cond`/`case`/`do` whose
clauses reach an unlowerable sub-form (kaappi#1496), fallback lambdas, and
general passthrough expressions — are serialized to a Scheme source
string and executed by the interpreter. Plain `kaappi_eval` re-parses **and
re-compiles** that string every time the enclosing native code runs it; inside a
loop body or a frequently-called function that is a severe, easily-overlooked
cliff (#1494).

To remove it, every **code** fallback routes through `kaappi_eval_cached` instead
(`emitCachedEval` in `src/llvm_emit.zig`). The emitter allocates one mutable
global slot per fallback call site:

```llvm
@.eval_cache.0 = internal global i64 0
...
  %t2 = call i64 @kaappi_eval_cached(ptr %vm, ptr @.str.0, i64 30, ptr @.eval_cache.0)
```

`kaappi_eval_cached` (`src/runtime_exports.zig`) reads the slot: on the first
execution it parses and compiles the source once, permanently GC-roots the
resulting `Function`, and stashes its Value in the slot; every later execution
reads the slot and runs the cached `Function` directly, skipping the reader and
compiler. The compiled bytecode still resolves globals by name at run time, so a
fallback that first republishes the enclosing frame's params/upvalues as globals
(`bindParamsAsGlobals`, see #1410) observes the current values on each execution
— behavior is identical to plain `kaappi_eval`.

The compile-once split point is code vs. data:

- **Code fallbacks** → `kaappi_eval_cached` (compile the form once; #1494).
- **Quoted heap constants** → `kaappi_quote_cached`, which caches the *built
  value* rather than a compiled form (#1495). See
  [Cached quoted constants](#cached-quoted-constants).

Two safety properties:

- **GC rooting.** The slot is an ordinary module global the collector never
  scans, so the cached `Function` is kept alive independently via `extra_roots`
  (which, unlike the LIFO shadow stack, holds a root for the program's lifetime).
  See `compileCachedForm` in `src/vm_eval.zig`.
- **Threads.** Only the main runtime thread (whose GC is the runtime's own)
  touches a slot — the check precedes both the slot read and write. A spawned
  SRFI-18 thread has its own VM and GC, so caching a `Function` from a child heap
  (freed at thread-join) or running a main-heap `Function` under a child VM would
  be cross-heap hazards; child threads always take the plain, uncached path.
  Non-cacheable sources (a special top-level form, multiple data) also fall back
  to a plain `eval`.

## Cached quoted constants

A quoted heap constant — a pair, vector, or other literal with no immediate
representation — is serialized to a `(quote …)` source string (see
[Heap-Allocated Constants](#heap-allocated-constants)). Plain `kaappi_eval`
rebuilds that constant on **every** execution, which is both a hot-path cliff
and a correctness divergence: the interpreter compiles a `quote` to a single
constant-pool entry (`compileQuote` in `src/compiler_passthrough.zig`), so every
evaluation of one literal returns the **same** object — `(eq? (f) (f))` is `#t`
when `f` returns a quoted literal — whereas a fresh rebuild is `eq?` to nothing.

`kaappi_quote_cached` (`src/runtime_exports.zig`) closes both gaps. The emitter
(`emitQuotedEvalExpr` in `src/llvm_emit.zig`) allocates one global slot per
quoted-literal call site:

```llvm
@.quote_cache.0 = internal global i64 0
...
  %t0 = call i64 @kaappi_quote_cached(ptr %vm, ptr @.str.1, i64 15, ptr @.quote_cache.0)
```

The first execution builds the constant, permanently GC-roots it (via
`extra_roots`, exactly as the eval cache roots its `Function`), and stores it in
the slot; every later execution returns the cached object directly. This is the
**data** analogue of `kaappi_eval_cached`: that caches a compiled `Function`,
this caches the built value itself.

Two properties fall out of the per-call-site slot, both matching the interpreter:

- **`eq?` identity across evaluations.** One literal at one call site returns the
  same object every time. Before #1495 the native backend rebuilt it per
  execution, so `(eq? (f) (f))` was `#f` natively but `#t` in the interpreter.
- **Distinct literals stay distinct.** Two textually separate occurrences of the
  same datum get **separate** slots, so they are not `eq?` to each other — the
  interpreter likewise gives them separate constant-pool entries.

The **threads** carve-out mirrors the eval cache: only the main runtime thread
touches a slot (the check precedes both the read and the write). A spawned
SRFI-18 thread has its own VM and GC, so caching a child-heap constant (freed at
thread-join) or returning a main-heap one under a child VM would be cross-heap
hazards; child threads build the constant fresh on every execution — exactly the
pre-caching behavior. The build-once guarantee (and the `eq?` identity that
follows from it) therefore holds on the main thread, where all AOT-compiled
top-level code runs.

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
This is the signature `kaappi_create_native_closure` stores and
`kaappi_call_scheme` invokes for indirect dispatch. A fixed-arity, non-variadic,
non-boxed **named** function additionally gets a register-argument `tailcc`
**fast entry** for direct calls and guaranteed mutual tail recursion — see
[Guaranteed mutual tail calls](#guaranteed-mutual-tail-calls-tailcc--musttail).

The three tiers, tried in order:

1. **Capturing lambda** (`tryCompileNativeClosure`) — a lambda with free
   variables. The body compiles to an `@closure_N` function; free variables are
   discovered by free-variable analysis (`collectFreeVars`) and **copied by
   value** into an `%upvalues` array at closure-creation time (sourced from the
   enclosing frame's `%args`, or, for a lambda nested in another native closure,
   chained out of that closure's own `%upvalues` — #1410). A free variable the
   enclosing frame **boxed** (see [Mutable captured
   variables](#mutable-captured-variables-assignment-conversion)) is captured as
   the box **pointer** instead, so mutations are shared. The closure value is
   materialized with `kaappi_create_native_closure`.

2. **Closed lambda / named function** (`tryCompilePureLambdaAsNativeClosure`,
   `tryCompileDefineFunction`) — no free variables (only parameters and known
   globals). Compiles to an `@lambda_N` function created with a null upvalue
   array. A top-level `(define (f ...) ...)` takes this path and registers `f`
   in `native_fns`, so later call sites emit a **direct** `call`/`tail call`
   instead of going through `kaappi_call_scheme`.

3. **Eval fallback** (`emitLambdaViaEval`) — when neither native tier applies,
   serialize `(lambda ...)` to source text and run it via the [cached eval
   fallback](#cached-eval-fallback) (`kaappi_eval_cached`) at runtime, so a
   lambda reached repeatedly (e.g. a variadic inner lambda in a hot function) is
   compiled only once. A lambda that appears inside a `let` body and cannot
   compile natively instead forces the whole enclosing `let` to the interpreter,
   preserving lexical scope (#827).

**Supported natively:** fixed arity; variadic **rest parameters** (the rest
list is built once in the entry block with a `kaappi_cons` loop,
`emitRestListBuilder`, and its frame slot is GC-rooted so an allocation in the
body cannot collect the freshly-consed spine); closures with by-value capture;
and **self-tail-recursion compiled as a loop** — a self-call in tail position
stores the new arguments and `br`s back to the function's body label rather than
recursing. A **variadic** self-call also rebuilds the rest list from the args
past the fixed arity before branching, so variadic named functions loop too
(kaappi#1498). (Boxed frames still disable the loop; see below.)

**Falls back to the [cached eval](#cached-eval-fallback) when the body:**

- contains an eval-fallback form (`letrec`, `guard`, named `let`, …), or a
  `cond`/`case`/`do` whose clauses themselves reach one (kaappi#1496);
- contains a keyword-only special form that reaches the interpreter as a whole
  `passthrough` — `call/cc`, `call-with-current-continuation`,
  `call-with-values`, `eval` (kaappi#1799; `apply` left this set when it got
  its own native lowering, kaappi#1803 — see below);
- contains an internal `define` (the closure tier sets up no locals scope for
  it), or a rest parameter that is captured and mutated (no box model yet); or
- captures an unmutated `let`-local, or a rest parameter, that has no copyable
  slot.

### Why `call/cc` & friends decline the whole enclosing scope (kaappi#1799)

All four native-compilation gates — the two closure tiers,
`tryCompileDefineFunction`, and `emitLet` — ask
`freevars.sexprNeedsEvalFallback`, which matches head keywords against the
comptime-derived `ir.eval_fallback_form_names`. A keyword missing from that set
is a **silent miscompilation**, not a missed optimization: the enclosing frame
compiles natively, its body's `passthrough` is serialized and run by
`kaappi_eval`, and `kaappi_eval` resolves names in the **global** environment.
`(define (s xs) (apply + xs))` compiled cleanly and then failed at run time with
`undefined variable 'xs'` — or, worse, silently read an unrelated global of the
same name.

The five keywords (then including `apply`) were missing because the
`passthrough` **node** is `.capability = .native` in `llvm_node_table`, which
is right for the one shape `emitPassthrough` compiles (a `(define (f …) …)`
shorthand) and wrong for every other.

The set is **comptime-derived** and needs no maintenance: it walks
`llvm_node_table`, then every `FormKind` field (skipping those
`isNativeLoweredForm` accepts), then `other_special_forms` — so a new
`FormKind` joins it automatically, and a comptime block enforces one
`llvm_node_table` entry per `NodeTag`.

The five keywords above are contributed by
`ir.other_special_forms`, whose `bool` payload records exactly "an evaluated
form headed by this keyword becomes a passthrough the interpreter runs".
`else`, `=>`, `_`, `...`, `unquote`/`unquote-splicing` and the keywords
`lowerFormWithMacros` intercepts earlier are deliberately `false`:
`sexprNeedsEvalFallback` recurses blindly into sub-forms, so listing `else`
would reject every natively lowered `cond`/`case` with an else clause.

Publishing the frame's bindings as globals instead (`bindParamsAsGlobals`,
the kaappi#1410 mechanism the `letrec`/`let` fallbacks use) is **not** an
alternative here: it aliases across activations, and it permanently clobbers a
same-named global. Declining the frame is what keeps the interpreter's own
lexical scope authoritative.

`bindParamsAsGlobals` also cannot reach a `let`-local, which lives in an alloca
it has no name for, so it refuses outright when `self.locals != null`
(kaappi#1862) rather than emit an eval that silently cannot see one. Until that
gate existed, `emitLet`'s own mid-emission escape hatch
(`abandonLetForFallback`, reached on the triggers no up-front scan can pre-empt
— more than 32 bindings, more head defines than the scope roots, an
`ir.lowerSingleExpr`/`emitNode` failure) broke the very rule this section
describes: an inner `let` abandoning inside an enclosing one was evaluated in
the global environment, dying with `undefined variable` on the outer binding —
or, with a same-named global in scope, quietly reading that instead. Refusing
sends the error up to the enclosing scope's own abandon path, which
re-evaluates that whole scope as one unit and so keeps the bindings. Publishing
the locals was the other option and is worse: a boxed local hits the same
by-location problem as a boxed param (kaappi#1422), and both weaknesses above
would extend to let-locals.

### The second gate: `isRejectedFormHead` (kaappi#1896)

`sexprNeedsEvalFallback` is not the only gate. `isRejectedFormHead`
(`llvm_emit_forms.zig`) routes `cond`/`case`/`do` through
`exprNativeEmittable`, and until kaappi#1896 it was a hand-maintained 32-name
array structurally independent of the derived set. It had drifted by exactly
one name: `define-property`.

That was not theoretical. `define-property` is a *compile-time* form —
`compileDefineProperty` evaluates its expression while the enclosing form is
compiled — so a top-level

```scheme
(cond (#t (display "B") (define-property x k (begin (display "P") 1)) (display "C")))
```

printed `PBC` interpreted and `BPC` compiled: the `cond` was emitted natively
and the registration left behind as a run-time `kaappi_eval`. `case` diverged
the same way. `do` did not compile at all (`KP9001`), because `emitDo` installs
loop-variable locals before reaching the deferred form and `emitFormEval`
refuses to eval inside a lexical scope. The lexical-scope path was never at
risk — `sexprNeedsEvalFallback` consults the *derived* set, so any enclosing
`let`/`lambda` had already declined.

The gate is derived now, and needs no maintenance:

```text
rejected_form_heads = (eval_fallback_form_names \ derived_exclusions)
                      ∪ extra_rejected_heads
```

`derived_exclusions` is empty. `extra_rejected_heads` holds the six names the
gate rejects for its own reasons: `lambda`, `define`, `unquote`,
`unquote-splicing`, `else`, `=>`.

A comptime block rejects a stale exclusion, a duplicate extra, and any derived
name that escapes the gate. A deliberately stricter runtime test in
`tests_native.zig` fails if `derived_exclusions` gains an entry *at all*, so
weakening the gate takes two edits rather than one quiet line.

### Native `apply` (kaappi#1803)

Declining is all-or-nothing for the enclosing function, and `(apply + xs)` is
idiomatic Scheme: one `apply` that runs once de-optimized every other
expression in the body (~19x on kaappi#1803's arithmetic-loop reproducer). So
`apply` — alone among the passthrough keywords — is lowered natively.
`emitPassthrough` routes an `(apply …)` head inside a lexical scope to
`emitApplyForm` (`llvm_emit.zig`), which mirrors the interpreter's own dispatch
(`compiler.zig`) case for case:

- **unshadowed + unrebound + ≥2 operands** — the guarded shape (kaappi#2469).
  The operands are emitted once, the `apply` global is resolved, and
  `@kaappi_builtin_is_pristine` (`runtime_exports.zig`) decides at run time
  which of two arms runs: the structural apply with built-in semantics — the
  callee and fixed arguments passed like `emitCallNode`'s, the final operand
  as a Value to `@kaappi_apply`, which splices it with `primitives.applyFn`'s
  exact semantics (same `isProcedure` validation, same tortoise-and-hare
  proper-list check, same `typeError` texts) — or an ordinary indirect call
  of whatever the global holds now. This is the same decision the
  interpreter's `guard_builtin` opcode makes (R7RS 5.3.1 makes a top-level
  redefinition essentially an assignment, so a body compiled before
  `(define (apply …))` ran must still reach it); `rebound_globals`/`native_fns`
  only short-circuit to the indirect call when the emitter can already see
  the name rebound in an earlier form.
- **tail + unshadowed + unrebound + <2 operands** — the interpreter raises
  InvalidSyntax at compile time; abandoning native compilation of the enclosing
  scope (`error.UnsupportedNodeType`) routes the form to that exact error. A
  **rebound** `apply` with too few operands is not this case — the interpreter
  routes it through the ordinary call path (its #2033 gate), and so does the
  generic indirect call here, raising whatever the user's procedure (or the
  built-in arity check) raises at run time.
- **everything else resolvable** — a lexically shadowed `apply`, an `apply`
  already seen rebound (tail or non-tail), or a non-tail form with too few
  operands — is an ordinary indirect call through whatever `apply` resolves
  to in scope, matching the interpreter's plain `call_global`/local call.

Since kaappi#2451 the interpreter has a **non-tail** `apply` opcode as well,
which calls the flattened callee with an ordinary VM frame so a continuation
captured in it survives the call's return. The native backend keeps routing
both positions through `@kaappi_apply`, i.e. `applyFn`'s re-entrant
`callWithArgs`, so that one guarantee is interpreter-only. Everything the
`check_both*` cases in `tests/scheme/compile/native-apply-lowering-1803.sh`
compare — results, and the non-tail `typeError` texts — is unaffected, because
the opcode reproduces `applyFn`'s diagnostics verbatim for exactly that
reason.

Two consequences worth knowing. First, the free-variable analyses
(`nodeHasFreeVars`/`collectNodeFreeVars` in `llvm_emit_freevars.zig`) walk an
apply `passthrough`'s raw operands — a capture inside one must become a closure
upvalue, or it would be emitted as a global lookup (#1799's failure mode in a
new spot). Second, a **tail `(apply f xs)` is not a real tail call across the
runtime boundary**: `@kaappi_apply` re-enters the VM via `callWithArgs`, so a
deep apply-driven self-recursion grows the native stack where the interpreter
runs in constant space. This is the same pre-existing divergence class as any
computed-operator tail call through `kaappi_call_scheme` (verified: both
overflow around the same depth), not a new one — the emitter still balances
the frame's GC roots before the `ret` so the shadow stack never leaks
(#1498/#1585).

The per-function analysis buffers (parameters, body nodes, captured free
variables, bound names) grow on the emitter's arena, so the only size ceiling is
the runtime's real one: a native closure's arity and each upvalue index are `u8`,
so a function with more than 255 fixed parameters or captured upvalues falls back
(kaappi#1498).

The resulting value (native closure or eval'd closure) is uniformly callable
via `kaappi_call_scheme`, which dispatches through the VM's `callWithArgs`
(closures, native functions, continuations, etc.).

### Native closure values for compiled defines

A top-level `(define (f …) …)` (or `(define f (lambda …))`) has two independent
needs: **call sites** — `(f x)` — and **value uses** — passing `f` to `map`,
`apply`, `(eq? f f)`, or returning it. The compiled `@f` entry (registered in
`native_fns`) serves direct call sites. The value was, until #1500, a *separate*
interpreter closure built by eval'ing the lambda/define source through the
`kaappi_eval_cached` fallback — even though `@f` was already emitted natively.

Since #1500 a **fixed-arity** define binds its global to a native closure over
that same entry: `emitDefine` / `emitPassthrough` look up the just-registered
`native_fns` record and emit
`kaappi_create_native_closure(@f, null, 0, arity, …)` instead of the eval
fallback (`emitNativeFnClosureValue` in `llvm_emit.zig`). This removes the
per-program startup parse+compile for the value and makes value uses run native
code, and — because taking `@f`'s address keeps the otherwise-`internal`
fast-entry trampoline (#1499) alive — it also stops that trampoline being
dropped. The value and the direct call sites now run the *same* native code
(previously the value ran the interpreter), so the native backend's
value-vs-call paths no longer diverge.

**Re-entrant eval.** Making `@f` reachable as a value exposed a latent
non-re-entrancy in the cached-eval fallback. When `@f`'s body itself reaches an
eval or quote fallback and `f`'s *value* is invoked from inside an active
`vm.execute` — e.g. `(define p (f 5))` eval'd at top level runs native `@f`
under the VM's `CALL` dispatch, and `@f` calls `kaappi_eval_cached` /
`kaappi_quote_cached` for its inner fallback — the nested run landed in
`vm.execute`, which `resetExecutionState`s and runs from frame 0, corrupting the
suspended outer form (it returned garbage or crashed with `car: not a pair`).
`runTopLevelFunction` (`vm_eval.zig`) now guards this: at true top level
(`frame_count == 0`) it stays `vm.execute`; when the VM is already executing it
runs the compiled thunk through the same re-entrant path native callbacks use
(`callWithArgs`, which pushes a frame *above* the current ones), leaving the
outer execution intact. Both `eval` and `runCachedForm` route through it, so the
quoted-constant and uncached fallbacks are covered too (before #1500 a native
body only ran from native call sites, never from an outer `vm.execute`, so this
nesting could not arise).

Two kinds of define keep the eval-fallback value:

- A **variadic** define: `callNativeClosure` dispatches native closures by
  **exact** arity (`args.len != nc.arity` is an error), so a variadic entry
  cannot be a native closure value.
- A define whose body reaches a **code eval fallback** (a variadic inner lambda,
  `letrec`, `guard`, a `let` it can't scope — anything that emits
  `kaappi_eval_cached`, tracked as `NativeLambda.has_eval_fallback`). Such a
  fallback republishes the enclosing frame's params as globals
  (`bindParamsAsGlobals`), which **aliases across separate activations** — a
  pre-existing native-backend limitation (two live closures from
  `(f 1)` and `(f 2)` both read the last-published global). Direct call sites use
  the closure immediately, so they don't expose it, but binding the value to a
  native closure would run that body from new contexts and widen the aliasing to
  the common `(define a (f 1)) (define b (f 2))` pattern. The gate keeps the
  interpreter-closure value, which captures by location correctly. A **quoted
  constant** (`kaappi_quote_cached`) is *not* a code fallback and does not gate:
  quotes can't alias, and the re-entrant-eval fix above covers building them.

In both cases `@f` still serves its direct call sites — a variadic entry passes
the real argument count and builds the rest list itself — so only the value pays
the eval fallback.

(Native closure values are also why native closures now print as
`#<procedure name>`, matching the interpreter's closures — see `printer.zig` —
rather than a distinct `#<native-closure>` tag: a define'd function used as a
written value is representation-identical across both backends.)

Remaining eval-fallback lambda positions after #1500 (natural follow-ups): the
value of a **variadic** define; the value of a define whose body has a **code
eval fallback** (gated above — closing this needs the underlying
`bindParamsAsGlobals` aliasing fixed, i.e. real by-location capture for
eval-fallback closures, not just wider reach); a **bare variadic**
`(lambda args …)` / `(lambda (a . rest) …)` expression (no closure tier builds a
rest list for an anonymous lambda); and any lambda whose body still reaches an
eval-fallback form (`letrec`, `guard`, named `let`, an internal `define`).

### Mutable captured variables (assignment conversion)

The by-value `%upvalues` copy above is correct only while a captured binding is
never mutated. A binding that is both **captured** by a nested lambda and
**mutated** (by `set!`, or an internal `define` that re-binds it) is instead
**assignment-converted to a heap box** (`llvm_emit_lambda.zig`, #1497):

- At the binding's site in the enclosing native frame — a boxed **parameter**
  (`emitBoxedParamSlots`) or a boxed **`let`-local** (`emitLet`) — the value is
  wrapped in a box (`kaappi_make_box`) and the frame slot holds the box
  **pointer**. The slot is GC-rooted for the frame's lifetime.
- Every read of the boxed name compiles to `kaappi_box_ref`, every `set!` to
  `kaappi_box_set` (`emitGlobalRef` / `emitStoreToVariable`, which consult the
  emitter's `boxes` map before params/upvalues).
- A nested closure captures the **box pointer** by value. Because the pointer is
  immutable and the box's contents are shared, a `set!` through any closure over
  the binding is visible to all of them — matching the interpreter's
  by-**location** closure semantics and fixing the #1422 divergence.

A box is a one-slot heap cell represented internally as a pair `(value . '())`;
boxes never escape to Scheme, so reusing the pair type keeps GC marking, the
write barrier, and sweeping correct with no new heap type. Only captured **and**
mutated bindings are boxed — everything else keeps the by-value fast path. Boxed
frames disable the self-tail-call loop and lower their body non-tail so the box
roots are popped at a single `ret`.

### Guaranteed mutual tail calls (`tailcc` + `musttail`)

Self-tail-recursion is constant-stack via the arg-overwrite loop above, but a
tail call to *another* function cannot be: the uniform entry reads its parameters
from a caller-frame `%args` array, and a real tail call tears that frame down, so
the callee would read freed stack. `even?`/`odd?`-style **mutual** recursion
therefore grew the stack. #1499 makes it constant-stack with LLVM's `tailcc`
calling convention + `musttail` marker (which `tailcc` frees from the
prototype-match rule, so functions of different arity may mutually tail-call).

A fixed-arity, non-variadic, non-boxed **named** function (arity ≤
`max_fast_arity`, currently 8) is emitted as **two** LLVM functions:

- **`@name.fast`** — the body, `tailcc`, taking arguments **by value** in
  registers. Its entry block copies those registers into a local `%args` array,
  so the rest of the body — param resolution, the self-tail loop's in-place
  overwrite, `bindParamsAsGlobals` — is byte-identical to the uniform entry. The
  array is this frame's own; outgoing calls pass argument *values*, never a
  pointer into it, so `musttail` stays sound.
- **`@name`** — an `internal` uniform-ABI **trampoline** that unpacks `%args` and
  `call tailcc @name.fast(...)`. This is what `kaappi_create_native_closure`
  stores; indirect dispatch (`kaappi_call_scheme`) still goes through it. LLVM
  drops it when a define's value is materialized via the interpreter and nothing
  takes its address.

Direct calls reach `@name.fast` with register arguments (no args array). A tail
call from one fast entry to another emits `musttail call tailcc … ; ret` —
LLVM-guaranteed constant stack. `mustTailSafe` gates this: the caller must be a
fast entry, in tail position, with a balanced shadow stack — specifically **not
inside a rooted `let`** (`self.locals == null`) and with the frame-entry roots
(rest list / boxed params, always 0 in a fast entry) already popped, so the
`musttail` immediately precedes its `ret` as LLVM requires. When those do not
hold, it degrades to a best-effort `tail call tailcc` hint. Self-recursion keeps
the loop (better than any call); variadic, boxed, over-arity, and closure
functions keep the single uniform entry and are unchanged.

**Forward references.** Mutual recursion needs the *forward* call (a callee
defined later) to resolve to a direct `musttail` too, but `native_fns` is
populated in emission order. A syntactic **pre-scan** (`preScanReserve`, run over
all top-level nodes at the top of `emitProgram`) reserves a stable
`@r{i}`/`@r{i}.fast` name pair for every top-level function define that is
defined exactly once, never a top-level `set!` target, and has a proper list of
symbol formals within the arity bound. A forward tail call to a reserved name
emits `musttail call tailcc @r{i}.fast`; a reference to a reserved name in
free-variable analysis counts as a **global**, not a capture
(`isKnownOrReservedGlobal`), so the caller still compiles natively. When a
reserved name's define turns out non-native (it falls back to the interpreter),
finalization emits an `internal tailcc` **stub** `@r{i}.fast` that rebuilds an
args array and dispatches through `kaappi_call_scheme` — so the `musttail` target
always links, correct though not itself constant-stack for that one edge.

**Per-target gate.** `fast_tailcalls_supported` (a comptime switch on the host
arch) enables all of the above only on `aarch64` and `x86_64`, whose LLVM
backends support `tailcc`/`musttail`. Other hosts keep the uniform-only ABI
unchanged; RISC-V can be enabled once its `musttail` support is confirmed.

## Testing

Per-issue native regressions live in `tests/scheme/compile/*.sh`, each
comparing the compiled binary against the interpreter as oracle (see the
"interpreter as the native tier's oracle" block in
`tests/scheme/shell-common.sh`). A `.scm` regression test that only ever runs
under the interpreter proves nothing about this tier — three of them silently
regressed that way (kaappi#2117/#2118), so a fix here that already has a `.scm`
suite should get a `compile/` script that runs *that file* through
`kaappi compile` rather than a fresh hand-typed golden value.

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
- Mutable captured variables — counters, accumulators, and closures sharing a
  boxed binding (`native-mutable-capture.scm`, `native-set-captured.scm`)
- Recursive functions on quoted data (`flatten`, `my-len`)
- Error handling with `guard`
- User-defined macros (`define-syntax`)
- SRFI libraries (SRFI-1, SRFI-13, SRFI-69)
- Unicode strings, string ports, string mutation
- Higher-order functions (`map`, `filter`, `fold`)
- Tail-recursive loops (100k iterations)
- Guaranteed constant-stack **mutual** tail recursion via `tailcc`/`musttail`
  (`even?`/`odd?` and a 3-function cycle at millions of alternating calls,
  `native-mutual-tail.scm`) — a non-tail-calling native binary would overflow,
  so the interpreter diff doubles as the constant-stack regression check
- Inline fixnum fast paths for `+ - * < = null?` with their runtime fallbacks —
  overflow → bignum, non-fixnum (flonum/rational) operands, and sign-extended
  negatives (`native-inline-primitives.scm`, all diffed against the interpreter,
  including under a forced-collection `KAAPPI_GC_THRESHOLD=1` run)
- Native closure values for compiled defines (#1500) — a fixed-arity define used
  as a *value* (`map`/`apply`/`eq?`/`procedure?`/returned from another function)
  runs its native entry and prints as `#<procedure name>` exactly like the
  interpreter's closure (`native-fn-value.scm`, diffed against the interpreter)

## Related Documents

- [ir.md](ir.md) — IR node types, analysis passes, optimization passes
- [continuation-strategy.md](decisions/continuation-strategy.md) — hybrid approach
  for `call/cc` in native code (VM fallback)
- [architecture.md](architecture.md) — overall pipeline and file organization
