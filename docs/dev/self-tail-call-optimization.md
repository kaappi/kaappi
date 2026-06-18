# Self-Tail-Call Optimization

## Status

**Option A implemented.** The `self_tail_call` opcode is in place: self-recursive
tail calls (direct `define` recursion and named `let` loops) compile to a
dedicated instruction that copies arguments to the frame base and resets the
instruction pointer, skipping the global lookup, type check, and arity check.
Measured ~23% speedup on `tak(33,22,11)`.

**Option B NOT shipped.** Enabling `tail_call_global` for *all* tail calls was
attempted and reverted. The blocker is not the register overlap discussed below
(forward copy is provably safe because `abs_base >= frame.base`), but that the
`tail_call_global` VM handler only knows how to call closures and native
functions. The regular `tail_call` handler also dispatches **parameter objects,
continuations, and FFI functions**. Routing tail calls through `tail_call_global`
therefore breaks any tail call to a global holding one of those values — e.g.
`(define (get) (p))` for a parameter `p`, or every `parameterize` body (which
desugars to thunks that tail-call the parameter and `%parameter-set!`). The
compiler's name-based exclusion list cannot catch these, since the offending
value is bound to a user global whose type is unknown at compile time. Shipping
Option B safely would require `tail_call_global` to handle the same five callee
types (and error mappings) as `tail_call` — deferred as a separate, benchmarked
change. Self-recursion (the hot case for `tak`) is already covered by Option A.

One accepted behavioral trade-off of Option A: a procedure that `set!`s its own
name mid-self-recursion keeps running the original body. See CONFORMANCE.md,
"Self-redefinition during self-tail-recursion."

The remainder of this document is the original analysis and design.

## Background

The `tak(33,22,11)` benchmark runs ~43s, approximately 3x slower than Gauche
(~15s). The benchmark is dominated by billions of function calls — `tak`
makes 3 non-tail `call_global` calls and 1 tail call per invocation. The
tail call is the outer `(tak ...)` that applies the three results.

### Current tail-call paths

The compiler has two code paths for function calls:

1. **`compileCallGlobal`** — emits `call_global` or `tail_call_global` for
   calls to global symbols. Fuses the global lookup + call into one opcode.

2. **`compileCall`** — emits `get_global` + `call` or `tail_call` for all
   other calls.

**Critical:** The compiler at line 845 of `compiler.zig` explicitly
**excludes tail calls** from the `call_global` path:
```zig
if (!is_tail and types.isSymbol(operator) and ...)
    return self.compileCallGlobal(expr, operator, dst, is_tail);
```

This means tail calls to global functions go through the slower path:
`get_global r3, tak` + `tail_call r3, 3` (two instructions, two dispatches).

### Why tail calls were excluded

A previous attempt to enable `tail_call_global` for tail calls caused a
**2x performance regression**. The documented reason: "frame reuse semantics
conflicting with the superinstruction's register layout."

The `tail_call_global` opcode IS implemented in the VM and works correctly
(it's used when the compiler is forced through `compileCallGlobal` with
`is_tail=true`). The regression was in the **compiler's register allocation**
for the tail position, not in the VM handler.

### The register overlap problem

The `tail_call_global` handler works as follows:

```
; Before:  frame.base = 0, args computed at abs_base = frame.base + base_reg
; abs_base might be at offset 3 (base_reg = 3)
;
;   registers:  [arg0  arg1  arg2 | callee  a0'  a1'  a2']
;               ^                   ^
;               frame.base          abs_base
;
; The tail-call logic copies args DOWN:
;   registers[frame.base + 0] = registers[abs_base + 1]  // a0'
;   registers[frame.base + 1] = registers[abs_base + 2]  // a1'
;   registers[frame.base + 2] = registers[abs_base + 3]  // a2'
```

When `base_reg` is small (e.g., 3) and `nargs` is large enough, the source
and destination ranges **overlap**. Copying argument `a0'` from
`registers[4]` to `registers[0]` is fine, but if `abs_base + 1 = 1` (when
`base_reg = 0`), then `registers[0]` is both the source of arg0 and the
destination of the first copy — the original arg0 is overwritten before
being read.

The regular `tail_call` opcode has the same overlap risk but doesn't suffer
from it because the compiler arranges the callee at `abs_base` and arguments
at `abs_base + 1..`, ensuring there's always at least one register of
spacing. The `tail_call_global` path has a different register layout because
the callee is loaded from the global cache at runtime rather than placed by
the compiler.

## Proposed optimization: self-tail-call fast path

### Observation

For `tak` and many Scheme programs, the most common tail call pattern is a
**self-recursive tail call** — the function calls itself in tail position.
In `tak`:

```scheme
(define (tak x y z)
  (if (not (< y x))
      z
      (tak (tak (- x 1) y z)        ; non-tail call_global
           (tak (- y 1) z x)        ; non-tail call_global
           (tak (- z 1) x y))))     ; tail call to self
```

The outer `(tak ...)` is a tail call to the same function. For a
self-tail-call, we can skip:
1. Global cache lookup (the callee is the current closure)
2. Type check (`isClosure`)
3. Arity check (same function, same arity)
4. Closure/code/IP replacement in frame (already the same)

The operation reduces to just **copying arguments to frame.base** and
**resetting IP to 0**.

### Implementation approach

#### Option A: New opcode `self_tail_call`

Add a dedicated opcode that the compiler emits when it can prove the tail
call is to the current function.

**Compiler** (`compiler.zig`):

In `compileForm`, when emitting a tail call and the callee is a symbol
matching the current function's name (`self.func.name`):

```zig
if (is_tail and types.isSymbol(head) and self.func.name != null and
    std.mem.eql(u8, types.symbolName(head), self.func.name.?))
{
    return self.compileSelfTailCall(expr, dst);
}
```

`compileSelfTailCall` emits:
```
self_tail_call nargs
; args are at consecutive registers starting at some base
```

**VM** (`vm.zig`):

```zig
.self_tail_call => {
    const base_reg = self.readU8(frame);
    const nargs = self.readU8(frame);
    const abs_base = frame.base + base_reg;
    // Copy args to frame base (no callee register to skip)
    for (0..nargs) |i| {
        self.registers[frame.base + i] = self.registers[abs_base + 1 + i];
    }
    frame.ip = 0;
},
```

This is the absolute minimum work for a tail call: `nargs` register copies +
IP reset. No global lookup, no type check, no arity check, no frame
mutation.

**Pros:** Maximum speed for the hot path. ~10 lines of VM code.
**Cons:** Requires one new opcode (slot 31 of 32 available). Only helps
self-recursion, not mutual recursion.

#### Option B: Enable `tail_call_global` with overlap-safe copy

Fix the register overlap problem and re-enable `tail_call_global` for all
tail calls.

**Change in `compiler.zig`:**

Remove the `!is_tail` guard at line 845:
```zig
if (types.isSymbol(operator) and self.resolveLocal(...) == null) {
    // ... same exclusion list ...
    return self.compileCallGlobal(expr, operator, dst, is_tail);
}
```

**Change in `vm.zig`:**

Replace the forward copy loop in `tail_call_global` with an overlap-safe
copy. When `abs_base + 1 <= frame.base + nargs` (overlap), copy backwards:

```zig
if (abs_base + 1 > frame.base + arg_count) {
    // No overlap: forward copy
    for (0..arg_count) |ai| {
        self.registers[frame.base + ai] = self.registers[abs_base + 1 + ai];
    }
} else {
    // Overlap: copy via temp or backwards
    var ai = arg_count;
    while (ai > 0) {
        ai -= 1;
        self.registers[frame.base + ai] = self.registers[abs_base + 1 + ai];
    }
}
```

**Pros:** Benefits all tail calls to globals, not just self-recursion.
**Cons:** Still does global cache lookup + type check + arity check.
Backwards copy may be slower due to cache behavior. Needs careful testing to
avoid the previous regression.

#### Option C: Combine both

Emit `self_tail_call` for self-recursion (maximum speed), and enable
`tail_call_global` with overlap-safe copy for non-self tail calls (moderate
speed improvement).

### Expected impact

**`self_tail_call`** eliminates per-tail-call overhead:
- Current: cache lookup (3 comparisons + potential hash) + `isClosure`
  (2 checks) + arity check (1 comparison) + argument copy + closure/code/ip
  assignment = ~15 operations
- After: argument copy + IP reset = ~5 operations

For `tak(33,22,11)` with ~880M calls (1/4 are tail calls = ~220M tail calls):
- Saving ~10 operations × 220M = ~2.2 billion operations
- At ~1ns per operation: ~2.2s savings → ~40s → ~38s (estimated ~12% gain)

For `fib(35)` (all tail calls are to `+`, not self): minimal impact since the
tail call is to a native function, not a self-call. However, enabling
`tail_call_global` (Option B) would save one dispatch per non-tail `fib`
call — estimated ~3% additional gain.

### Correctness considerations

1. **Redefinition:** A self-tail-call optimization assumes the function
   hasn't been redefined via `set!`. If someone does `(set! tak other-fn)`,
   a cached self-tail-call would still call the original `tak`. This is
   acceptable because:
   - R7RS doesn't require `set!` on standard library bindings to be reflected
   - Most Scheme implementations (Chez, Chibi, Gauche) make the same trade-off
   - The global cache already has this property (version check guards it)

2. **Guard via `global_version`:** To be safe, the self-tail-call can check
   `global_version` against the cache version. If they differ, fall back to
   the normal path. This costs one comparison but preserves correctness under
   redefinition.

3. **Variadic functions:** Self-tail-calls to variadic functions still need
   rest-list construction. The optimization should only apply to fixed-arity
   self-tail-calls, or handle the variadic case explicitly.

4. **Compiler identification:** The compiler identifies self-calls by
   matching the callee symbol name against `self.func.name`. This is set for
   named `define` forms but null for anonymous lambdas. Anonymous self-
   recursion (via `let` or `letrec`) uses local variables, not globals, so
   it goes through `tail_call` (not `tail_call_global`) and is unaffected.

## Disassembly comparison

### Current `tak` bytecode (outer tail call)
```
  0026  get_global      r3, tak      ; 4 bytes, hash lookup
  ...
  0099  tail_call       r3, 3        ; 3 bytes, full dispatch
```
Two instructions, two bytecode dispatches.

### With `self_tail_call`
```
  ...
  0076  self_tail_call  r3, 3        ; 3 bytes, arg copy + ip=0
```
One instruction, one dispatch, no global lookup or type check.

### With `tail_call_global` enabled
```
  ...
  0076  tail_call_global r3, tak, 3  ; 5 bytes, cache + inline tail
```
One instruction, one dispatch, cache lookup + inline tail-call logic.

## Recommendation

Start with **Option A** (self-tail-call opcode) — it's the simplest, lowest
risk, and highest impact for the specific bottleneck. If more is needed,
follow up with **Option B** to cover non-self tail calls.

## Complexity

Option A: ~30 lines (10 in VM, 10 in compiler, 10 in types for the new
opcode). Option B: ~10 lines (remove `!is_tail` guard, add overlap-safe
copy). Option C: both.

## Key files

| Component | Location |
|-----------|----------|
| Tail-call exclusion | `src/compiler.zig:845` (`!is_tail` guard) |
| `compileCallGlobal` | `src/compiler.zig:933` |
| `compileCall` | `src/compiler.zig:839` |
| `tail_call_global` handler | `src/vm.zig:1166` |
| `tail_call` handler | `src/vm.zig:794` |
| OpCode enum | `src/types.zig:683` |
| Benchmarks doc | `docs/benchmarks.md` |
| Lessons learned | `docs/dev/lessons-learned.md:157` |
