# Bounded-step execution (kaappi#2283)

A resumable, instruction-budgeted entry point so a host can run Scheme code in
chunks — handing control back periodically — instead of blocking until the
program completes. The browser playground is the motivating consumer
(kaappi.github.io#32): a synchronous WASI `_start` can only be stopped by a hard
`terminate()` on a wall-clock timeout, which kills legitimately long-running,
constant-space programs and throws away output already produced. The canonical
example that should run indefinitely in bounded memory:

```scheme
((call/cc call/cc) (call/cc call/cc))
```

The batch WASI `_start` path (`toplevel_driver.runFile`) is unchanged; stepping is purely
additive.

## Why the hard part was already done

The VM is a cooperatively-resumable, safepoint-based machine because the
SRFI-18 scheduler and the GC need it. Stepping reuses that machinery rather than
adding a parallel one:

- The dispatch loop has a **safepoint between instructions**
  (`vm_dispatch.runUntil`, every 1024 instructions) that already polls the
  terminate flag, the GC stop-the-world request, and the timeout deadline.
- **`error.Yielded`** is an existing resumable signal: a blocking primitive
  parks the current fiber by returning it, and the scheduler resumes later.
- **All execution state lives in the VM struct**, not on the host C stack across
  a yield — kaappi reifies its own control stack for `call/cc`. So a pause can
  return out to the host and a later call can resume with frames intact. This is
  also why Asyncify/JSPI are unnecessary.

## The mechanism

A step budget is one more thing the safepoint checks. When the outermost stepped
loop reaches the deadline, it returns `error.Yielded` with a `step_paused` flag
set — between instructions, so every stack (frames, wind, handler) and the `ip`
are consistent, and no `ip` rewind is needed.

Five VM fields (`src/vm.zig`) carry it:

| Field | Role |
|-------|------|
| `step_deadline: ?u64` | Instruction-counter value at which to pause. Null disables stepping. |
| `step_active: bool` | True only in the loop the stepper dispatched into (see below). |
| `step_dispatch_pending: bool` | Set by beginStep/resumeStep, consumed by the next runUntil into `step_active`. |
| `step_paused: bool` | Set by the safepoint on a budget pause; distinguishes it from a fiber park. |
| `step_root_depth: u32` | Root-stack depth at the form's start, so a resumed form that raises unwinds correctly. |

### The one safety invariant: only the outermost loop pauses

A pause must never fire inside a *nested* `runUntil` — one entered for `eval`, a
native higher-order driver's callback, a `with-exception-handler` thunk, a
scheduler fiber slice, or a file-backed library load — because native Zig frames
sit between that loop and the stepper, and returning `Yielded` through them
would strand a half-finished native operation. (This is the same hazard that
restricts fiber parking to `dispatched_from_scheduler`.)

`runUntil` enforces it by save/restoring `step_active` exactly as it does
`dispatched_from_scheduler`: it consumes `step_dispatch_pending` into
`step_active` on entry and restores the previous value on exit, so a nested
`runUntil` runs with `step_active == false` and cannot pause. Only the
stepper's own outermost loop pauses.

`beginStep`/`resumeStep` set `step_dispatch_pending` **only when no scheduler
exists**. Once a program has spawned a fiber, `run()` routes through
`runWithScheduler`, whose per-fiber `runUntil`s are not stepped — so a fibered
program runs its scheduler slice to completion within a single step rather than
pausing mid-fiber. That is a deliberate limitation, not a correctness gap: the
motivating programs (call/cc-heavy, single-threaded) pause finely; concurrent
programs still run and terminate, just at coarser granularity.

## The API

### VM level (`src/vm_calls.zig`, re-exported from `VM`)

```zig
pub const StepStatus = enum { done, paused };
fn beginStep(vm, func, deadline, out) VMError!StepStatus  // start a top-level form
fn resumeStep(vm, deadline, out)      VMError!StepStatus  // resume the paused form
```

`beginStep` and `execute` share `prepareTopLevelFrame` (per-form reset + initial
frame) and the success/error tails (`finishRunValue`/`finishRunError`, which run
the #1855 root-boundary reset and the dynamic-wind after-thunk unwinding). The
step path intercepts the budget pause *before* those tails so nothing is torn
down while the form is merely suspended.

### Top-level driver (`src/vm_step.zig`)

`Stepper` drives a whole program the way `runFile` does — read a form, run
library declarations to completion, compile ordinary forms and execute them —
but each `step(budget)` runs at most `budget` instructions across however many
forms fit, then returns `.running` or `.done`. Result echoing and error
reporting match `runFile` so stepped and batch output are identical. A
host-settable stop flag is wired into `vm.terminate_flag`, so `requestStop()`
ends the running form at the safepoint via the existing `error.Terminated` path
(dynamic-wind after-thunks still run).

### WASM C-ABI (`src/wasm_step.zig`, wasm32-wasi only)

Exported alongside `_start` (the wasm executable is built `rdynamic`):

| Export | Purpose |
|--------|---------|
| `kaappi_step_alloc(len) -> ptr` | Allocate a linear-memory buffer for the host to write the program into. |
| `kaappi_step_setup(ptr, len) -> i32` | Fresh VM; arm a `Stepper` over the source. |
| `kaappi_step_run(budget) -> i32` | Run ≤budget instructions. `0` running, `1` done, `2` done-with-error. |
| `kaappi_step_stop()` | Request cooperative termination. |
| `kaappi_step_reset()` | Tear down, ready for the next program. |

**Streaming.** stdout/stderr reach the host's WASI `fd_write` as each
`display`/`write` runs: fd 1/2 are unbuffered (`primitives_io.isBufferedFdPort`
excludes them), so a host drains output between chunks with no extra flush.

## Tests

`src/tests_step.zig`: a finite program finishes and its side effects persist; a
long form pauses and resumes to the same result a batch run produces; the
constant-space infinite program keeps stepping forever without completing; the
stop flag ends a running program cleanly; a form error is reported but execution
continues to the next form; and the direct `beginStep`/`resumeStep` API pauses
and resumes. Loop bounds scale down under `-Dgc-stress=true` (kaappi#1401).
