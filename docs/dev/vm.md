# The bytecode VM

How compiled bytecode runs: the frame and register model, the calling
convention, tail calls, continuations, dynamic state, error propagation,
and the entry points. This is the as-built companion to
[KEP-0021](https://github.com/kaappi/keps/blob/main/keps/0021-bytecode-vm.md)
(the design record) and the execution-side counterpart of
[bytecode.md](bytecode.md), which owns the instruction set. Read it before
touching any `vm*.zig` file, and before writing a native primitive that
calls back into Scheme — most of the VM's subtle rules are about what a
re-entrant native frame may and may not do.

The one-paragraph version: **a pure register machine with no value
stack.** Every live frame owns a window of a flat register file; a call
places the callee and its arguments in consecutive registers of the
caller's window and the callee's window starts one past the callee slot.
Tail calls overwrite the current frame in place. Continuations copy the
whole execution state — registers, frames, handler stack, wind stack —
into a heap object and copy it back on invocation. Native primitives that
need to run Scheme push a frame and run a *nested* dispatch loop on the
Zig stack, which is where every hard rule in this document comes from.

## Where it sits

| File | Owns |
|------|------|
| `vm.zig` | the `VM` struct, capacity growth, the handler/wind push and pop, `resetExecutionState`, thin delegates to the files below |
| `vm_dispatch.zig` | `runUntil`, the dispatch loop: safepoint, operand widths, every opcode arm, `resumesHere` |
| `vm_dispatch_helpers.zig` | operand readers, window validation, `lookupGlobalCached`, `guardBuiltin`, `dispatchApply`, rest-list building, the noinline error raisers |
| `vm_calls.zig` | `execute`/`run`/`runWithScheduler`, `callValue`/`callClosure`/`callNative`, the re-entrant helpers `callReentrant`/`callHandler`/`callThunk`/`callWithArgs`, `mapNativeError`, `beginStep`/`resumeStep` |
| `vm_continuations.zig` | capture, escape, wind transition, restore |
| `vm_errors.zig` | `setErrorDetail`, stack traces, the nearest-name suggestion, `noteUncaughtException` |
| `vm_roots.zig` | `markVmRoots` (the GC's root marker) and the child-thread `CollectionState` protocol |
| `vm_eval.zig` | `eval`, the top-level head classifier, the `.sbc` run path |
| `vm_step.zig` | the bounded-step driver ([bounded-step.md](bounded-step.md)) |
| `vm_library.zig`, `vm_imports.zig`, `vm_library_cache.zig` | `define-library`, `import`, `.sld` loading and its cache ([cache.md](cache.md)) |
| `vm_records.zig` | `define-record-type` desugaring (R7RS and R6RS shapes) |
| `vm_bootstrap.zig` | the Scheme-defined drivers installed at init (see "Re-entering the VM") |
| `vm_shims.zig` | `setVMInstance`: the function-pointer hooks the compiler and expander reach the VM through |
| `vm_debug.zig` | breakpoints, stepping, watches, the profiler entries |
| `errors.zig` | `KaappiError` and `isUncatchable` |
| `types_continuation.zig` | `CallFrame`, `SavedFrame`, `ExceptionHandler`, `WindRecord`, `Continuation`, the capacity constants |

`vm_instance` is a threadlocal pointer to the live VM; every primitive
reaches the VM through it, and the GC's root marker finds the globals
through it, so it must be set (`setVMInstance`) before anything allocates
and the struct must never move afterwards (#1401). Each SRFI 18 OS thread
has its own VM and GC (`initForThread`); what crosses between them is
[thread-value-sharing.md](thread-value-sharing.md)'s subject.

## Frames and registers

The `VM` holds four heap-allocated stacks that grow geometrically and are
hard-capped (#1886):

| Stack | Element | Initial (build option) | Cap |
|-------|---------|------------------------|-----|
| `registers` | `Value` | 2048 (`-Dmax-registers`) | 65 536 |
| `frames` | `CallFrame` | 480 (`-Dmax-frames`) | 32 768 |
| `handler_stack` | `ExceptionHandler` | 64 (`-Dmax-handlers`) | 32 768 |
| `wind_stack` | `WindRecord` | 64 (`-Dmax-winds`) | 32 768 |

Exhausting any of them is `StackOverflow`, reported as `KP3008` and never
delivered to a `guard` (below). The handler and wind stacks used to be
fixed 64-entry arrays, and the 65th nested `guard` produced a silently
wrong answer; that is why all four grow the same way now.

A `CallFrame` is `{closure, native, code, ip, base, dst, saved_wind_count,
returns_to_native, seq}`:

- `base` is the frame's window start; register `r` of this frame is
  `registers[base + r]`. The window is `func.locals_count` registers, the
  compiler's high-water mark for the function (256 for a frame with no
  closure). `Function.locals_count` is also what bounds continuation
  capture and GC marking, so a compiler change that lets code touch a
  register past it is a memory-safety bug, not a performance one.
- `dst` is the register, relative to the *caller's* base, that receives
  this frame's return value.
- `saved_wind_count` is the wind-stack depth at frame entry; a return
  unwinds only what this frame pushed above it.
- `returns_to_native` marks a frame whose result belongs to a re-entrant
  Zig caller, not to a bytecode frame.
- `seq` is a birth id from a monotonic counter. A tail call reuses the
  frame and keeps the id, so it identifies a frame for the lifetime of the
  loop that owns it; `resumesHere` compares it after a continuation
  restore.

Registers between live windows are dead but not cleared on return. That
matters twice: the GC marks only live windows (`markVmRoots`), and
continuation capture and fiber save copy the contiguous range, so both
scrub the gaps first (`clearGapRegisters`, #1464 and #1529). A register
window is never assumed zeroed: `clearFrameLocals` writes `UNDEFINED` over
the unused part of a fresh callee window so stale heap pointers from a
popped frame are not marked as roots.

## The dispatch loop

`runUntil(target_frame_count, target_wind_count)` executes while
`frame_count > target_frame_count`; a return that drops the frame count to
the target ends the loop and yields the value. The top-level run is
`runUntil(0, 0)`; every re-entrant native call runs a nested `runUntil`
with the target set to the depth it was entered at, which is how a native
primitive gets a Scheme result back on the Zig stack.

Each iteration bumps `instruction_counter`, reads the opcode at
`frame.ip` (range-checked → `InvalidBytecode`), validates the operand bytes
against the `fixed_operand_bytes` switch — the table [bytecode.md](bytecode.md)
mirrors — and dispatches through a plain `switch`. **Every 1024
instructions a safepoint runs**, in this order: the SRFI 18 terminate flag
(→ `Terminated`), the child-thread stop request for a collecting parent
(`stopForCollection`, #1933), the wall-clock `timeout_deadline_ns` and the
`instruction_limit` (→ `ExecutionTimeout`), and the bounded-step deadline
(→ `Yielded` with `step_paused`). Anything that must interrupt a running
program from outside is plugged in here and nowhere else.

Three threadlocal-style flags on the VM are consumed at loop entry and
save/restored around it, so a nested loop never inherits them:

- `dispatched_from_scheduler` — this loop was entered directly by a fiber
  scheduler, so a blocking primitive may park the fiber. A nested loop
  (a native driver's callback, `with-exception-handler`'s thunk, `eval`)
  clears it, because Zig frames now sit between the bytecode and the
  scheduler. `map`, `for-each` and `dynamic-wind` are *not* nested loops:
  they are Scheme (below), so a fiber parks inside them (#1959).
- `step_active` — this is the outermost stepped loop and may pause
  ([bounded-step.md](bounded-step.md)).
- `yield_retry` — a parked primitive asked the loop to rewind `ip` to the
  start of the calling instruction (`maybeRewindRetry`), so the call
  re-executes when the fiber is rescheduled instead of resuming with an
  unwritten result register.

## Calls

`call base, nargs`: `registers[base]` holds the callee and the arguments
follow it. `callValue` dispatches on the callee's type — closure first,
because it is the common case — then `NativeFn`, `NativeClosure` (the LLVM
backend's compiled functions), `FfiFunction`, `ParameterObject` (zero
arguments reads, one sets through the converter), `Guardian`, and
`Continuation`; anything else is `NotAProcedure`.

**Closures** (`callClosure`): check arity — exact, or `nargs >= arity`
with the surplus folded into a rest list for a variadic — ensure register
and frame capacity, scrub the unused window, and push a frame with
`base = callee_base + 1` and `dst = callee_base − caller.base`. So the
callee's r0 is its first argument and the callee value itself sits just
below its window. `nargs` is a `u8`; 255 is a legal count and every `+1`
around it must widen first (#2185).

**Natives** (`callNative`): check arity against the `NativeFn.Arity`
(exact, variadic minimum, or range), clear the error-detail buffer, pass
`registers[base+1 .. base+1+nargs]` as a slice to the Zig function, store
the result at `registers[base]`. A native body indexes its `args` without
bounds checks, which is why every path that hands one a slice must run
`checkNativeArity` first — the re-entrant helpers once did not, and a
wrong-arity handler read past a fixed array and aborted the process (#2034).

**Return** (`.return src`): pop the frame, run the after-thunks of any
wind records the frame pushed above its `saved_wind_count`, and if the
loop's target is reached return the value to the Zig caller (unwinding to
`target_wind_count` first). Otherwise, if the frame was marked
`returns_to_native`, the Zig caller that owned this result is gone —
raise `KP3000` (`raiseDeadNativeReturn`) rather than write into whatever
frame now sits below. Otherwise store into `caller.base + dst`. **A
callee's return never unwinds the caller's winds**: the caller's own
bytecode may hold live winds above its entry count mid-`dynamic-wind`
(#1377). The legitimate unwind points are the frame's own return, the
scope-root return, the error paths of `callReentrant` and `execute`, and
`performWindTransition`.

### Tail calls

Three opcodes replace the current frame instead of pushing one, which is
what makes R7RS proper tail recursion hold in constant space:

- `tail_call` copies the arguments down to `frame.base`, re-ensures the
  window for the new callee's `locals_count` (`ensureTailWindow`, #2035),
  scrubs, and overwrites `closure`/`code`/`ip = 0`. The frame keeps its
  `dst`, `returns_to_native`, `saved_wind_count` and `seq` — so a thread
  thunk that tail-calls `dynamic-wind` runs its bytecode in a
  `returns_to_native` frame, which is how #1377 fired only in threads.
- `self_tail_call` copies arguments down and sets `ip = 0`: a loop back to
  the top of the same function with no lookup, type or arity check
  ([decisions/self-tail-call-optimization.md](decisions/self-tail-call-optimization.md)).
- `tail_call_global`, and the receivers of `tail_call_cc` and `tail_eval`,
  replace the frame the same way.

A tail call to a **native** takes a fast path that pops the frame itself
and returns the native's result to the caller directly. Consequence for
test writers: a lambda whose body ends in a native call (`(display x)`,
`(= a b)`) never executes a `.return` opcode, so a bug in the return arm
hides behind it; end the thunk with a non-call expression to exercise it.

### Globals

`get_global`, `set_global`, `define_global` and the fused
`call_global`/`tail_call_global` resolve through `lookupGlobalCached`: a
per-function `global_cache` indexed by constant slot, valid while
`func.cache_version` equals the shared `GlobalsRwLock.version`, which every
thread's rebinding bumps (#2483) — the snapshot is taken *before* the map
read so a concurrent rebind cannot re-bless a stale value. Only closures
and natives are cached, and only for functions with no restricted `env`;
a def-env-prefixed reference (a library macro's free reference, #1812) is
never cached, because a library's own internal `set!` does not bump the
version. Filling a slot goes through the write barrier: the function may
be old and the value young (#1961).

`guard_builtin` (#2469) is the run-time half of the builtin
superinstruction gate: it resolves the operator like `get_global` and falls
through to the fused fast path only while the value is still the pristine
primitive; anything else jumps to the ordinary call the compiler emitted
after it. R7RS 5.3.1 makes a top-level definition an assignment, so this
is the only place the question can be answered honestly.

Globals are a heap-allocated map shared *by pointer* with child-thread
VMs and guarded by `GlobalsRwLock`: the owner reads lock-free, children
take the shared lock per read, every structural mutation takes the
exclusive lock. Nesting an acquisition deadlocks; `findSimilarName` locks
internally, so error paths release before suggesting a name.

## Re-entering the VM from Zig

A native primitive that must run Scheme — an exception handler, a
`dynamic-wind` thunk, a sort comparator, a custom port's `read!` — goes
through one of four helpers, all of which funnel into `callReentrant`:

| Helper | Use | Frame flag |
|--------|-----|------------|
| `callHandler(h, arg, return_dst)` | exception handlers, `call/cc` receivers in non-tail position | — |
| `callThunk(t)` | wind thunks, `with-exception-handler`'s thunk | — |
| `callThunkReturningToNative(t)` | a thunk whose result the native itself consumes (`call-with-values`' producer, #2453) | `returns_to_native` |
| `callWithArgs(p, args)` | everything else: callbacks, converters, the compiler's macro-time calls | `returns_to_native` |

`callReentrant` picks a base above the current top frame
(`computeReentrantBase`: the frame's base plus its window and two, never
less than 16), binds the
arguments with the same arity validation `callClosure` does
(`bindReentrantArgs`), pushes a frame, and runs `runUntil` with the target
set to the current depth. It bounds `native_reentry_depth` (3000 in
release, 200 in Debug, where frames are far larger) and refuses when the GC
root stack is nearly full; both are `StackOverflow`. On error it restores
the frame and handler counts and runs the after-thunks of winds pushed
during the call — unless a continuation was invoked meanwhile
(`continuation_generation` changed), in which case the state is not its to
restore.

Three rules follow from "a Zig frame is now on the stack":

1. **A continuation captured inside the callback cannot resume after the
   native has returned.** The native's iteration state lived in Zig
   locals that are gone. The frame flags make this loud: `KP3000` at the
   dead frame's return, instead of the silent corruption it used to be.
   This is the documented restriction in
   [known-limitations.md](known-limitations.md), and the reason `map`,
   `for-each`, `fold`, `filter`, `dynamic-wind`, `force` and their
   siblings are **bootstrapped Scheme** (`vm_bootstrap.zig`): their bodies
   and callbacks stay in the one dispatch loop, so a continuation captured
   in a callback resumes freely and a fiber can park in one.
2. **A fiber cannot park under a re-entrant frame.** `waitForFd` and the
   scheduler take the drive-in-place branch instead
   ([fibers-and-reactor.md](fibers-and-reactor.md)); advisory `yield`
   no-ops when `native_reentry_depth > 0`; a custom-port callback that
   blocks raises a specific catchable error (`SRFI 181`).
3. **The helper's `frame` pointer is stale after any re-entrant call.**
   The nested run may grow `self.frames`; the dispatch loop reads `dst`
   and `returns_to_native` before calling a native and never touches the
   pointer after.

`callWithArgs` also flips a child VM's `CollectionState` to `.running`
for its extent (#1933): everything below it runs bytecode, and a
collecting parent must wait for a safepoint rather than mark mid-execution.

## Continuations

`tail_call_cc base, dst` captures, then tail-calls the receiver with the
continuation as its argument. `captureContinuation` computes the top of
the live register stack (the max of every frame's `base + window`),
scrubs the gaps, and allocates one backing block holding the registers,
every frame as a `SavedFrame` (the same fields as `CallFrame`, `seq`
included), the handler stack and the wind stack, plus the destination
register. Full, multi-shot, re-entrant, O(stack) per capture; the design
choice is [decisions/continuation-strategy.md](decisions/continuation-strategy.md).

Invocation (`callValue` on a continuation, or `callHandler`): check the
owner — a continuation belongs to the heap of the OS thread that captured
it, and invoking it elsewhere is a catchable error (#1936) — run the
`performWindTransition` from the live wind stack to the saved one
(after-thunks down to the common prefix, before-thunks back up; records
are compared by thunk identity), `restoreContinuation` (grow the stacks,
`@memcpy` everything back, clear `current_exception`, place the value at
`dst_base + dst_reg`, bump `continuation_generation`), then return
`ContinuationInvoked`.

That error is the signal that **the VM's state has been replaced under
every Zig frame currently on the stack.** Each catch site in the dispatch
loop asks `resumesHere`: does the frame at this loop's target index still
carry the `seq` it had when the loop started? If so the restored state
resumes in this loop (`continue`); if not, this loop's scope frame was
discarded and it propagates outward, so the re-entrant Zig callers between
it and the resume point unwind and keep their pending register writes
consistent (PR #934). `callReentrant` checks `continuation_generation`
and `frame_count` the same way to decide whether to return
`continuation_value` or propagate.

**Escape continuations** (`call/ec`, `captureEscape`) record only the
three stack depths and the destination; `invokeEscape` runs the
after-thunks entered since capture, truncates handlers and frames, and
delivers the value. `valid` is cleared when the `call/ec` call returns, and
a later invocation raises a catchable error. `guard` desugars to
`call/ec` plus `with-exception-handler`, which is why a guard-wrapped body
always runs under a re-entrant frame (rule 2 above, #1625).

## Dynamic state

**`dynamic-wind`** is Scheme (`vm_bootstrap.zig`); its before and after
thunks push and pop `WindRecord`s through `%push-wind`/`%pop-wind`, so every
record on the wind stack was pushed by bytecode. The VM touches the stack
at exactly the unwind points listed under "Return", and the invariants are
recorded in that section.

**`parameterize`** compiles to a `dynamic-wind` call; a `ParameterObject`
called with no arguments reads through `getParameterValue`, which consults
the current fiber's overrides and then the VM-level map — the frozen
pre-scheduler layer a spawned fiber inherits.

**Exceptions.** `push_handler`/`pop_handler` maintain the handler stack of
`{handler, frame_count, sticky}`. `raise` sets `current_exception` and
returns `ExceptionRaised`, which unwinds the Zig stack to the nearest
`with-exception-handler` (a native); that native pops its handler,
converts the condition, and calls the handler through `callHandler` — so
**a handler runs after the stack has unwound to its installer, not at the
raise point**, the caveat [known-limitations.md](known-limitations.md)
records. A handler that returns from a non-continuable `raise` re-raises
"handler returned". `raise-continuable` instead calls the handler in place
with the handler popped for the call's extent and re-pushed after — except
when the handler escaped through a continuation, in which case re-pushing
would strand it on the restored stack. SRFI 248's *sticky* handlers are
invoked in place without popping, so a continuation captured during
handling snapshots them.

A native fault (`(car 5)`, an unbound variable) propagates as a Zig error,
not a raised object. `with-exception-handler`'s catch converts it with
`nativeErrorToErrorObject`, the **single place a diagnostic code is stamped
onto an error object** (`error-object-code`, KEP-0005) — shared by the SRFI
248 handler and the fiber error arm so the four coding boundaries cannot
drift.

## Errors

`KaappiError` (`errors.zig`) is the VM's error set; `mapNativeError`
translates a primitive's `PrimitiveError` into it at every dispatch
boundary and synthesizes a detail message when the primitive set none
(which is why a bare `TypeError` return blames `args[0]`, see
[gc-safety-and-error-handling.md](gc-safety-and-error-handling.md)).
`setErrorDetail` fills a 256-byte buffer plus line/column; the reporting
layer maps the error to its `KP3xxx` code
([diagnostics.md](diagnostics.md)).

**Catchable versus uncatchable** is a semantic contract, not a detail.
`isUncatchable` names the errors `with-exception-handler` must never turn
into an object a `guard` clause can match:

| Uncatchable | Why |
|-------------|-----|
| `StackOverflow` | a VM limit — frames, registers, handlers, winds, re-entrancy depth |
| `ExecutionTimeout` | a budget the host set |
| `Terminated` | a terminated thread must not run guard clauses on its way out |
| `Yielded` | a scheduler signal, not a condition |

`ContinuationInvoked` belongs there conceptually but every catch site
handles it *before* consulting the predicate. `OutOfMemory` stays catchable
because it is overloaded: genuine exhaustion, but also the payload cap on
`(make-vector 100000000000000)`. When adding a limit, tag a cap on the VM's
own storage `StackOverflow` and a cap on one call's input
`InvalidArgument` — `apply`'s 255-argument ceiling was mis-tagged the first
way until #1886.

`execute` is the outermost boundary: on error it truncates the GC root
stack to its entry depth (the #1855 boundary), snapshots the stack trace,
records the diagnostic code, runs every pending wind after-thunk while
preserving the error detail those thunks would clobber, and resets the
per-form state. A top-level form therefore never leaks a frame, a handler,
a wind record or a root into the next form.

## Entry points

- `execute(func)` — one top-level form: reset per-form state, allocate the
  top-level closure, push frame 0, `run`. `run` is `runUntil(0, 0)` unless a
  scheduler exists, in which case `runWithScheduler` loops over fiber
  slices, saving and restoring the VM's live arrays into `Fiber` objects
  between them. A scheduler can be created lazily mid-run by the first
  `spawn`, so `run` re-checks for one when it catches `Yielded`.
- `beginStep`/`resumeStep` — the same, instruction-budgeted, with all
  state left in the VM struct across the pause.
- `callWithArgs` and friends — re-entry from a native, above.
- `eval(source)` — read, classify, compile, run. `topLevelHead` names the
  eight forms the driver evaluates itself rather than compiling (`import`,
  `define-library`, `define-record-type`, `define-values`, `include`,
  `include-ci`, `begin`, `cond-expand`); `isEnvSetup` says which of them a
  compile-only driver (`check`, the LSP) must still evaluate. The same
  classifier serves `kaappi check`, the LSP and the `.sbc` run path, so
  the three cannot disagree about what a form is.

The VM is created by `VM.init(gc)` and, for an SRFI 18 thread,
`initForThread(gc, parent)`, which shares the globals map by pointer and
the macro and library maps by struct copy. `deinit` skips the shared maps
unless `owns_globals`.

## GC interaction

`markVmRoots` is the collector's root marker: per live frame, the closure,
the native, and the register window; every handler; every wind thunk; the
in-flight exception; the continuation value; the globals, macros, record
and property registries and every library environment (owner VM only —
children never write mark bits on parent-heap objects); parameter
overrides; the scheduler's suspended fibers; the reactor. A field on the
VM that can hold a heap value and is not in that list is a use-after-free
waiting for the next collection; `default_channel_comparator` (#2394) and
`callback_error_value` are recent additions of exactly that kind.

The rooting rules for code that allocates while holding a `Value` are in
[gc-safety-and-error-handling.md](gc-safety-and-error-handling.md). Two
VM-specific ones: root a `Function*` before `execute` (it allocates the
closure wrapper), and treat the `frame` pointer as invalid across any
allocation that may run Scheme.

## Tests

| Suite | Covers |
|-------|--------|
| `src/tests_continuations.zig` (39) | capture, restore, escape, gap scrubbing under gc-stress, nested and re-entrant escapes |
| `src/tests_tail_calls.zig` (13) | the three tail opcodes and window growth |
| `src/tests_exceptions.zig` (39) | handler stack, catchable/uncatchable, the payload-cap pin |
| `src/tests_fibers.zig` (39), `tests_step.zig` (8) | scheduler slices, parking, bounded steps |
| `src/tests_core_eval.zig` (51), `tests_robustness.zig` (50) | the eval loop; limits, divergence, malformed input |
| `src/tests_gc_tracing.zig` (89) | every root the marker must reach |
| `tests/scheme/continuations/` (11 files) | the conformance gate the continuation decision pins: correctness, multishot, nested, re-entrant escape, `set!` store, `call/ec`, the `call-with-values` and native-driver re-entry cases |
| `tests/scheme/errors/` (25 files) | error codes, the crash banner, uncatchable limits |

The unit suite must stay green under `zig build test -Dgc-stress=true`;
the register-gap and root-marker bugs in this file's history were all
found that way. A `.scm` test is interpreter-only evidence: a change to
the calling convention that the native backend's `runtime_exports.zig`
also depends on needs a `tests/scheme/compile/*.sh` script
([llvm-backend.md](llvm-backend.md)).

## What this design does not do

- **Delimited or segmented stacks.** Capture is O(stack) and the copy is
  the whole state. `call/ec` covers the escape-only case in O(1); a
  segmented design was considered and rejected
  ([decisions/continuation-strategy.md](decisions/continuation-strategy.md)).
- **Resuming a continuation across a returned native frame** (rule 1).
- **Running the handler at the raise point** for non-continuable `raise`.
- **A stable ISA.** The opcode set is an internal, same-build contract;
  the `.sbc` cache key includes the compiler's build id for that reason
  ([cache.md](cache.md)).
