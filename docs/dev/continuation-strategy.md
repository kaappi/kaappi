# Continuation Strategy for Native Code Generation

**Decision:** Hybrid — direct-style IR with VM fallback for first-class
continuations. Native-compiled code uses the C stack for calls; code that
reaches `call/cc` side-exits to the bytecode VM, which already handles
continuations via stack copying.

## Problem

The bytecode VM implements continuations by copying its explicit frame stack
and register file into a heap-allocated `Continuation` object
(`vm_continuations.zig`). This works because the VM's execution state is a
data structure that Zig code can read, copy, and restore.

Native code runs on the hardware call stack. The C stack cannot be portably
copied or restored — `setjmp`/`longjmp` only handles a single jump, not
multi-shot re-entry. A native backend therefore needs a strategy for
continuation support that doesn't rely on copying the C stack.

## Options considered

### 1. CPS IR

Convert the IR to continuation-passing style: every function takes an
explicit continuation argument. Continuations become ordinary closures,
so `call/cc` is trivial — it just passes the current continuation to its
argument.

**Pros:** Uniform model, zero special handling for call/cc.
**Cons:** All code pays the overhead — every call allocates a closure for the
continuation. The bytecode VM already handles continuations efficiently via
stack copying, and CPS output is a poor fit for it (extra arguments, extra
closures). Optimizing CPS IR requires different passes than direct-style IR.
Two incompatible IR flavors (one for bytecode, one for native) defeats the
purpose of a shared IR.

**Verdict:** Rejected. The cost is pervasive and the bytecode backend — which
remains the primary execution path — would degrade.

### 2. Segmented / spaghetti stacks

Allocate each call frame individually on the heap. Capturing a continuation
is O(1) — just save a pointer to the current frame. Restoration is a pointer
swap.

**Pros:** O(1) capture.
**Cons:** Every call pays heap allocation cost. Destroys cache locality.
Requires rewriting the entire call convention and frame layout. The JIT
backends (aarch64, x86_64) would need complete redesign. Incompatible with
C-ABI calls to the runtime.

**Verdict:** Rejected. The architectural cost is too high for a feature most
programs never use.

### 3. Hybrid: direct-style native + VM fallback (chosen)

Keep the IR direct-style (matching the bytecode backend). Native-compiled
code uses the C stack. When code that may invoke `call/cc` is reached,
execution transfers back to the bytecode VM, which handles continuation
capture/restore via its existing stack-copying mechanism.

The key insight: most Scheme code never uses `call/cc`. Functions proven free
of first-class continuations (Stage 3 analysis) compile to native code with
no overhead. Only the small fraction of code that reaches `call/cc` falls
back to the VM.

**Pros:**
- Zero overhead for continuation-free code (the common case)
- No changes to the bytecode VM or JIT — they keep working as-is
- The direct-style IR serves both backends without conversion
- `call/ec` (escape continuations) can be implemented natively as
  `setjmp`/`longjmp` — they're single-shot by definition

**Cons:**
- Code that uses `call/cc` in hot loops does not benefit from native
  compilation. This is acceptable: such code is rare, and the bytecode
  VM + JIT already handles it well.
- The boundary between native and VM code requires a calling convention
  bridge (save/restore registers across the boundary).

**Verdict:** Chosen. Matches the project's existing architecture (bytecode VM
stays, native is an additional backend) and avoids penalizing the common case.

## Design details

### Fallback boundary

The semantic analysis pass (Stage 3) determines which functions may reach
`call/cc` — conservatively, any function that:
- Directly calls `call-with-current-continuation` or `call/cc`
- Calls a function that is not provably continuation-free
- Receives a closure argument that might invoke a continuation

Functions provably free of continuations are eligible for native compilation.
Functions that may reach `call/cc` stay on the bytecode VM.

At call boundaries, the native code calls into the VM's `execute()` function
to run bytecode-compiled callees. The VM can call back into native code for
functions it knows are native-compiled. This is analogous to how the JIT
already works — JIT-compiled functions call back into the interpreter for
opcodes they don't handle (`tail_call`, `closure`, `push_handler`).

### call/ec in native code

Escape continuations (`call/ec`) have restricted semantics: they're valid
only within their dynamic extent and cannot be re-entered after return.
This maps directly to `setjmp`/`longjmp`:

1. `call/ec` calls `setjmp` to save the C stack state
2. The thunk runs normally on the C stack
3. If the escape continuation is invoked, `longjmp` unwinds back
4. `dynamic-wind` after-thunks are called during unwinding

Since escape continuations are far more common than full `call/cc` in
practice (used for error handling, early returns, `guard`), this
optimization covers most continuation usage in native code.

### dynamic-wind interaction

The wind transition logic (`performWindTransition` in
`vm_continuations.zig`) calls before/after thunks in order. For native code:

- When side-exiting to the VM for `call/cc`, the native code's wind records
  are already on the VM's wind stack (the runtime maintains a unified stack
  regardless of execution mode).
- After-thunks during unwinding may themselves be native-compiled; the
  runtime calls them normally.

### Multi-shot continuations

Full multi-shot `call/cc` is handled entirely by the VM. A continuation
captured in VM-executed code can be invoked any number of times. If the
invocation re-enters a context where native code was running, the VM
re-invokes the native function from the saved call boundary.

## Conformance plan

All tests in `tests/scheme/continuations/` must pass. The native path must
satisfy:

- **Must pass natively:** `call/ec` correctness, escape from nested calls,
  `guard` (desugars to `call/ec`), error handling with `with-exception-handler`
- **Deferred to VM fallback:** `call/cc` multi-shot re-entry,
  `call/cc` in tight loops, continuation captured across function boundaries
- **Behavioral equivalence:** programs that use `call/cc` must produce
  identical results whether compiled natively (with VM fallback) or
  executed purely on the VM

## References

- Appel, *Compiling with Continuations* — CPS approach analysis
- Dybvig & Hieb, *Representing Control in the Presence of First-Class
  Continuations* — segmented stack and stack-copying tradeoffs
- Chicken Scheme — uses CPS transform with Cheney on the MTA
- Chez Scheme — uses segmented stacks (one-shot optimization)
- Guile, Chibi — stack copying (same as Kaappi's current approach)
