# GC Safety and Error Handling

Patterns contributors must follow to keep the runtime correct under
garbage collection pressure and to propagate errors consistently.

The terse checklist version of the GC rules lives in
`.claude/rules/gc-safety.md` (auto-loaded by the Claude Code harness when
editing GC-sensitive files). This document is the rationale behind those
rules — keep the two in sync.

---

## GC Safety

The garbage collector is generational (young and old generations, minor
and full collections) with mark-and-sweep at its core. It scans a root
set (VM registers, the root stack, globals, macros) and frees any heap
object not reachable from a root. GC can trigger during **any** `alloc*`
call in `memory.zig`.

### The dangerous pattern

```zig
// BAD — val1 is unrooted when allocPair triggers GC
const val1 = try gc.allocString("hello");
const pair = try gc.allocPair(val1, types.NIL);  // GC may free val1
```

Between `allocString` returning and `allocPair` storing `val1` as the
car, GC can run. Since `val1` is only on the Zig stack (which GC does
not scan), it looks unreachable and gets freed.

### The safe pattern

```zig
var val1 = try gc.allocString("hello");
gc.pushRoot(&val1);
defer gc.popRoot();
const pair = try gc.allocPair(val1, types.NIL);  // val1 is protected
```

`pushRoot` adds the address of `val1` to the GC's root stack. If GC
runs during `allocPair`, it finds `val1` through the root stack and
keeps it alive.

### Rules

1. **Root any heap Value that must survive another allocation.** If you
   call two `alloc*` functions and the first result is used by or after
   the second, root it.

2. **Pair `pushRoot` with `defer popRoot()` where the whole scope is
   `pushRoot`-free.** `popRoot` removes whatever is on top of the shared
   stack, not "your" entry, so a deferred pop is only correct when nothing
   between the push and the deferred call can push its own root. Inside a
   loop body, or right before rooting a second value, pop explicitly
   immediately after the specific call being protected instead. See the
   `compileLetSyntax` incident in `.claude/rules/gc-safety.md`.

3. **Root the accumulator in loops.** When building a list or vector
   via repeated `allocPair`/`allocVector`, root the accumulating result:

   ```zig
   var result: Value = types.NIL;
   gc.pushRoot(&result);
   defer gc.popRoot();
   for (items) |item| {
       result = try gc.allocPair(item, result);
   }
   ```

4. **Don't store unrooted Values in ArrayLists.** If you collect heap
   Values in an `ArrayList(Value)` across allocations, those Values are
   not in the root set. Either collect non-heap data (indices, offsets)
   and allocate during the rooted build phase, or use `gc.extra_roots`
   (see `readVector` in `reader_datum.zig` for the pattern).

5. **Symbols are safe.** Interned symbols live in `gc.symbols` and are
   always reachable — no rooting needed.

6. **Fixnums, booleans, characters, nil, void are safe.** These are
   immediates (encoded in the NaN-boxed u64), not heap objects.

7. **Root `Function*` before `vm.execute()`.** `execute()` allocates a
   closure wrapper internally, so an unrooted Function can be collected
   out from under the call.

### The write barrier

Because the collector is generational, minor collections scan only the
young generation plus a remembered set of old objects that point into
it. Mutating a field of a heap object (set-car!, set-cdr!, vector-set!,
hash-table-set!, record field mutation) can create an old→young
reference the minor collection would otherwise never see — the young
object would be freed while still reachable.

After storing a Value into a heap object field, call:

```zig
gc.writeBarrier(container, new_val);
```

where `container` is the heap object being mutated. The barrier records
the old→young edge in the remembered set. Omitting it does not fail
immediately — it corrupts the heap only when a minor collection happens
to run before the next full collection, which is why these bugs surface
as rare, allocation-pattern-sensitive crashes.

### Stress testing

Build with `-Dgc-threshold=1` to force a collection on every allocation.
This turns "rare, timing-dependent" rooting and barrier bugs into
deterministic failures. Every new allocation pattern in a loop should
also get a stress test — see `tests/scheme/smoke/gc-rooting-stress.scm`.

`-Dgc-stress=true` builds go further and make marking-time use-after-free
itself deterministic (#1687). Freeing an object stamps its header with the
reserved `memory.FREED_OWNER` owner id (in Debug builds too, after the
`0xAA` poison), and the freed slot is held in a per-GC quarantine —
released oldest-first, only past `GC.quarantine_max_bytes`, and only
between a later collection's mark and sweep phases. A dangling value that
reaches the mark phase then panics with
`GC: marking freed object (use-after-free)` rather than being skipped as a
foreign-owned object (the poisoned owner byte never matches the marking
GC's id) or silently aliasing a live object recycled into the same slot —
the two escape modes that let the #1682 dangling-local bug survive twelve
nightly stress runs. Release builds compile out both the stamp/check and
the quarantine.

A GC that is torn down has no later mark/sweep to release its withheld
slots at, so `GC.deinit` has to hand them somewhere: to `quarantine_heir`
if one was named, otherwise straight back to the allocator. That drain is
what made the machinery blind to *cross-heap* use-after-free for a year
(#2127) — a joined SRFI-18 child's slots went back to the allocator, the
parent's next allocation recycled one, and a parent value still pointing
into the dead child heap read a live-looking object at the next mark. The
join path (`freeChildResources` in `primitives_srfi18.zig`) now names the
parent as the child's heir, so those slots stay withheld across the
parent's marks and the panic fires. **Any new "free every object on a GC
that is going away" path needs the same decision**: an heir when something
longer-lived could still hold a pointer into that heap, a drain when
nothing can. `setQuarantineHeir` must be called from the thread doing the
teardown, once no other thread can still be freeing on either GC — the
heir's quarantine has no lock of its own.

### Unwinding the root stack on error (#1855)

Rooting around a fallible call has a hole the rules above cannot close:

```zig
var a = try gc.allocSomething(...);
gc.pushRoot(&a);
const result = try gc.allocOther(a, ...);  // if THIS fails...
gc.popRoot();                              // ...this never runs
```

When the protected call is the one that fails, the error unwinds past the
`popRoot`. `root_count` is only ever moved by `pushRoot`/`popRoot`, so
nothing put it back: the root stack was left holding the address of a local
in a frame that no longer exists, and the next collection dereferences it.
Under NaN-boxing that usually reads as a garbage flonum (harmless by luck)
and occasionally as a plausible heap pointer (UB). Worse, the extra entry
shifts the whole stack, so every `defer popRoot()` still to fire on the way
out removes the wrong entry.

Switching to `errdefer` at each of the ~340 push sites is not the fix — a
`defer`/`errdefer` near a loop is the LIFO footgun of rule 2, so the cure
reintroduces the disease. Instead the **pipeline boundaries** snapshot
`gc.root_count` on entry and call `gc.truncateRoots(depth)` when an error
escapes:

| Boundary | Covers |
|----------|--------|
| `compileExpression`, `compileExpressionWithMacrosAt`, `compileExpressionInEnv`, `compileProgram` (`compiler.zig`) | Reader, expander, IR and bytecode emission — for every caller: REPL, `main`'s file loop, `kaappi check`, the LSP, `pipeline`'s stage dumps, `native_compiler`, the `eval`/`load` primitives, library-body compilation |
| `vm_eval.eval` | The top-level-only handlers that bypass the compiler (`import`, `define-library`, `define-record-type`, …) and the reader |
| `vm_calls.execute` | The running program. Truncated inside the error branch, *before* it runs pending `dynamic-wind` after-thunks — those allocate, so a leaked root would otherwise still be live when they collect |

Two invariants follow. Roots never outlive the boundary that saw them
pushed, so nothing may `pushRoot` expecting a caller across a boundary to
pop it. And truncation only ever shrinks: a depth *below* the snapshot is an
over-pop, which re-rooting cannot repair — the resurrected slots may already
belong to a returned frame — so the boundary leaves it alone.

What is deliberately not covered: recovery *within* a running form. A root
leaked by a primitive whose error a Scheme `guard` catches survives until
the enclosing `execute` returns, because snapshotting per native call would
put a load on the interpreter's hottest path for a hazard no primitive
currently has. The sweeps in `src/tests_gc_root_boundary.zig` find leaks
only in the expander; keep primitive error paths balanced so that stays
true.

To reproduce a failure this deep, use `gc.oom_countdown` — `n` allocations
succeed, the next fails. Sweeping `n` walks the failure across every
allocation a form performs. `FailingAllocator` cannot reach these sites, and
`gc.memory_limit` is an absolute watermark that only trips once a form
*retains* more than the headroom, so it fails in the first few allocations
and never reaches the expander. `oom_countdown` is compiled out entirely
outside test binaries (`builtin.is_test`).

### Raw-allocator ownership is still local (#1864)

The boundary reset above unwinds the **GC root stack** and nothing else. A
struct taken from `gc.allocator` is owned by whichever field is eventually
assigned it, so every fallible step between the `create` and that assignment
still needs its own local `errdefer`:

```zig
const sched = vm.gc.allocator.create(FiberScheduler) catch return VMError.OutOfMemory;
sched.* = FiberScheduler.init(vm);
errdefer {                       // nothing owns `sched` until vm.scheduler is set
    sched.deinit(vm.gc.allocator);
    vm.gc.allocator.destroy(sched);
}
```

`fiber.ensureScheduler` was missing exactly this: an OOM in the main fiber's
`allocFiber` or in `addFiber` returned with the scheduler neither destroyed
nor stored, leaking both the struct and the managed `waiter_index` map inside
it. This is not the LIFO footgun of rule 2 — an `errdefer` that undoes a
*specific* allocation it names is always safe; only the shared, positional
root stack makes `defer popRoot()` order-dependent.

Note the scoping: an `errdefer` inside a block is discarded when that block
exits normally, so the one above cannot fire for a later failure in the
reactor block that follows it — which matters, because by then `vm.scheduler`
owns the pointer and freeing it would be a double free.

### Where to look

The `reverse` function in `primitives.zig` is a clean reference
implementation. The `readVector` function in `reader_datum.zig` shows
the `extra_roots` pattern for dynamic-length collections.

---

## Error Handling

### Error type hierarchy

Primitives return `PrimitiveError!Value`. The VM translates these to
`VMError` at dispatch boundaries. The mapping:

| PrimitiveError | VMError | When |
|---------------|---------|------|
| `TypeError` | `TypeError` | Wrong argument type |
| `DivisionByZero` | `DivisionByZero` | Division or modulo by zero |
| `IndexOutOfBounds` | `IndexOutOfBounds` | Vector/string index out of range |
| `InvalidArgument` | `InvalidArgument` | Semantically invalid argument value |
| `OutOfMemory` | `OutOfMemory` | Allocation failed |
| `ExceptionRaised` | `ExceptionRaised` | Scheme `raise` was called |
| `ContinuationInvoked` | `ContinuationInvoked` | `call/cc` continuation was invoked |
| `Yielded` | `Yielded` | Fiber yielded |
| `ArityMismatch` | `ArityMismatch` | Wrong argument count (checked before dispatch) |

### Catchable vs. uncatchable (#1886)

`with-exception-handler` — and so `guard`, which desugars to it — converts a
natively-propagating error into a Scheme error object so a clause can match
it. `errors.isUncatchable` is the single list of errors that must *not* get
that treatment and instead unwind past every handler to the top level:

| Error | Why it is uncatchable |
|-------|----------------------|
| `StackOverflow` | A VM limit (frames, registers, handlers, winds, native re-entrancy) — the program didn't raise it |
| `ExecutionTimeout` | A budget the *host* set; the guest must not swallow it |
| `Terminated` | `thread-terminate!`; a terminated thread must not run guard clauses on its way out |
| `Yielded` | A scheduler control signal, not a condition |

`ContinuationInvoked` belongs to this set conceptually, but every catch site
handles it *before* consulting the predicate — it needs its own non-error
unwinding, not propagation.

Until #1886 none of these were excluded, and the failure mode was a silently
wrong answer rather than a loud one: exceeding a limit inside nested `guard`s
handed the *enclosing* guard a bare `#<error "error">`, whose `(#t ...)`
clause returned a plausible value with exit 0.

Two tags are deliberately **not** in the set, both because they are
overloaded — each covers a genuine VM limit *and* an ordinary program fault,
and only the fault reading can be honored without a separate tag:

- `OutOfMemory` — real exhaustion (including a `--max-memory` budget), but
  also what `gc_alloc.max_payload_bytes` returns for
  `(make-vector 100000000000000)`.
- `InvalidArgument` — includes `apply`'s 255-argument ceiling, which was
  itself mis-tagged `StackOverflow` until #1886 re-tagged it.

**When adding a new limit check, tag it by which of those two it is.** A cap
on the VM's own storage is `StackOverflow` and becomes uncatchable; a cap on
one call's arguments or one object's size is an argument fault and stays
catchable. Getting this backwards either makes a program unable to recover
from its own bad input, or lets it swallow a genuine VM limit.

### Rules

1. **Use the specific error variant.** Don't return `TypeError` for an
   index out of bounds — return `IndexOutOfBounds`. The dispatch layer
   generates better error messages when it knows the actual error type.

2. **Set error detail before returning.** Use
   `vm.setErrorDetail("proc-name: message", .{args})` or the
   `primitives.typeError("proc-name", "expected-type", got)` helper.
   If no detail is set, the dispatch layer generates a generic message.

3. **All dispatch error switches must cover all 8 variants.** When
   catching `PrimitiveError` in `vm_dispatch.zig`, always handle:
   `TypeError`, `DivisionByZero`, `IndexOutOfBounds`,
   `InvalidArgument`, `OutOfMemory`, `ExceptionRaised`,
   `ContinuationInvoked`, `Yielded`. Use `callNative` in
   `vm_calls.zig` as the reference.

4. **Don't use `catch {}` for correctness-relevant operations.** If an
   OOM during `hashmap.put` means a binding is silently lost, propagate
   with `catch return error.OutOfMemory`. Reserve `catch {}` for:
   - Port cleanup (`closePort` in `with-*` patterns)
   - Debug info (source line tracking, line tables)
   - Error-path recovery where the primary error takes precedence

### Nothing but a type belongs in the "expected type" slot (#1972)

`typeError`'s third argument is printed as `expected <that>, got <value>`, so
whatever goes there is read as a type. Two things kept ending up there that are
not:

- **A range rule.** `fd->port` rejected `0` with `expected socket/pipe file
  descriptor (> 2)` — but `0` *is* a fixnum, the type it wants; the fault is the
  value. That is `argError` (KP3007), not `indexError`: the reserved-stdio bound
  is a semantic rule, and `indexError`'s wording (`index N out of range for
  length L`) needs a length that does not exist here.
- **A platform.** Four `comptime is_wasm` gates read `expected non-WASM
  platform, got #<string>`, blaming a valid filename for the build it was
  compiled into.

The platform gates split two ways, and the seam is worth knowing because it
looks like drift:

| Procedure | Reports | Why |
|---|---|---|
| `open-input-file`, `open-output-file`, `delete-file` | a **file error** (`file-error?` → `#t`) | R7RS 6.13 already says what these signal when the file cannot be opened or deleted, and the WASM build cannot |
| `fd->port` | `argError` (KP3007) | a Kaappi extension over `(kaappi ffi)`; no file, so nothing satisfies `file-error?` |

That split is the same one SRFI 170 already makes: its POSIX-only procedures
report `not supported on Windows` through `raiseUnsupportedOnWindows`, a file
error, because the SRFI's own text says its procedures signal file errors — not
because "unsupported platform" is generically a file error. Where no spec asks
for one, don't borrow it.

The first row is not a cosmetic choice. A type error is not a file error, so
until #1972 a portable `(guard (e ((file-error? e) …)) (open-input-file …))` —
correct on every native target — fell through to its caller on the WASM tier,
which is the playground at kaappi-lang.org. The gate now raises through
`raiseFileError`, the same helper the procedure's *own* native failure path two
lines down already used; the platform is named in the message and the path stays
the irritant. That neighbour is the general tell: **before inventing a phrasing
for a failure, check what the same procedure raises for the same failure on a
target where it can actually run.**

Two ordering consequences. The type check now runs *before* the platform gate,
so a non-string argument is a type error on every target rather than whatever
the gate said. And the gate has to stay above the first POSIX call, since a
comptime-true early return is what keeps `openat`/`unlink` out of the WASM
build's analysis at all.

A `comptime` gate cannot be tested from a native build — an assertion for one
would compile away and silently never run, passing forever. They are covered by
`tests/wasm/platform-gates.scm`, which the `wasm` CI job runs under wasmtime;
the native half (`fd->port`'s range rules) lives in
`tests/scheme/audit/primitives_io-audit.scm` next to #1944's.

### Tagging the `vm_instance` / `gc_instance` guards (#1874)

Roughly 450 sites open with one of:

```zig
const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
const vm = vm_mod.vm_instance orelse return PrimitiveError.InvalidBytecode;
```

Both threadlocals are set during VM init (`vm_mod.setVMInstance` runs before
`registerAll`), so neither guard fires in a working build. That makes the tag
a *readability* decision, not a behavioral one — and left undecided it drifted
into a 46/34 `TypeError`/`OutOfMemory` split with nothing explaining either
side. Two rules settle it.

**Rule 1 — a guard returns the tag the function was going to return anyway,
just without the formatted detail.** These helpers fetch the VM only to
*attach a message* to an error they were already committed to raising, so
losing the VM costs the message, not the diagnosis:

| Helper | Tag |
|---|---|
| `primitives.typeError` | `TypeError` |
| `primitives.indexError` | `IndexOutOfBounds` |
| `primitives.argError`, `primitives_string_ext`'s cursor guard | `InvalidArgument` |
| `primitives_arithmetic.raiseDivByZero` | `DivisionByZero` |
| the `overApplied`-style arity helpers (SRFI 181/254/258/260) | `ArityMismatch` |
| `primitives_fiber.reraiseFiberError` | `ExceptionRaised` |

A `gc_instance` guard in an allocating function is the same rule at scale: no
GC means the allocation the function exists to perform cannot happen, so
`OutOfMemory` *is* what it was going to return. That is 348 of the 354
`gc_instance` sites and stays as it is.

**Rule 2 — with no natural tag, use `InvalidBytecode`.** A null threadlocal is
an implementation-invariant violation, and `InvalidBytecode` is the only
`KaappiError` variant that means that. `diagnostics.runtimeErrorCode` maps it
to `.internal_error` (KP9001), whose registry template — the message the user
actually sees, since these guards set no detail — is "internal error" plus
"please report it with the program that triggered it". That is the correct
instruction for a condition no program can cause.

The two rejected alternatives are worth naming, because both are what the
drifted sites had:

- `OutOfMemory` prints "out of memory" and sends the reader after heap size
  for something that is not an allocation failure.
- `TypeError` is worse still: `vm_calls.mapNativeError` fills in a detail when
  none was set, so a bare `TypeError` surfaces as `type error in '<proc>': got
  <args[0]>` — a message that names a real argument as the culprit and reads
  as deliberate. That synthesized-detail trap is the whole reason the CI
  `format` job rejects an unannotated bare `return PrimitiveError.TypeError`
  (kaappi#1868/#1871); `// bare-ok: <reason>` is for Rule 1 sites only.

**Rule 1 vets the guard against its function — it does not vet the function.**
`primitives.bootstrapStub` sat in the Rule 1 table until #1876, with a
`bare-ok` on each of its two lines. The guard did mirror the function, so the
rule passed it; what nobody re-read was the function, which was reporting
"`vm_bootstrap.install()` never ran" — a Rule 2 condition if there ever was
one — as a caller type error. Both lines are `InvalidBytecode` now, and both
annotations are gone with them. So when a Rule 1 site keeps surfacing in the
kaappi#1874 grep, check what the function itself returns before recording the
site as settled: a correct guard on a wrongly-tagged function looks exactly
like a site the rule has already cleared.

Guards in functions that do not return an error union (`orelse return 0`,
`null`, `false`, or a bare `return`) have no tag to settle and are outside
both rules.

One seam the two rules leave visible, so it does not read as fresh drift: the
`raise*` helpers that build a condition object and end in `return
PrimitiveError.ExceptionRaised`. `reraiseFiberError` already carried a tag of
its own and keeps it under Rule 1; `raiseFiberError`, `raiseWrappedPortClosed`
and `raiseEntropyUnavailable` carried `OutOfMemory`, which is not what they
return, so Rule 2 moved them to `InvalidBytecode`. Reading Rule 1 strictly
would send all of them the same way — but `ExceptionRaised` is the one tag a
guard cannot honestly borrow, since it promises `vm.current_exception` was set
and the guard fired precisely because there is no VM to set it on.

`primitives_io`'s `waitPortFd` and `raisePortClosedDuringIo` sat on this seam's
Rule 1 side until #1944, on the same "it already carried a tag of its own"
reasoning — but the tag was `InvalidArgument`, which neither function returns
for any other reason, and `raisePortClosedDuringIo` is a byte-for-byte twin of
`raiseWrappedPortClosed` 950 lines further down the same file, which Rule 2 had
already moved. Both are settled the same way now: `InvalidBytecode` for the
`vm_instance` guards, `OutOfMemory` for the `gc_instance` one. That makes the
seam narrower than it reads above — a guard is only on Rule 1's side if the tag
it borrows is one the function genuinely returns, not merely one it was written
with. `primitives_io.zig`'s own test block pins all three.

A second seam, settled by #1878, is the one place a guard sits in a function
that genuinely raises `TypeError` elsewhere. `primitives.applyFn` does — for a
non-procedure first argument, and for an improper final list — so at a glance
its `vm_instance` guard reads as Rule 1. It is not: Rule 1 covers a helper that
fetches the VM only to *attach a message* to an error it was already committed
to raising, and `apply` fetches the VM in order to *call the procedure*. A null
threadlocal means `apply` cannot run at all, so it is `InvalidBytecode`, while
the `gc_instance` line directly under it keeps `OutOfMemory`. Two adjacent
guards, two different tags, one per rule — that shape is the rules working, not
drift.

The same fix covered `vm.zig`'s three macro-expansion hooks —
`evalDatumForMacro`, `callProcForMacro`, `syntaxPropertySet`. Those are the
easy half (they return `anyerror`, so there was never a tag to borrow), but
they are worth knowing about for scope: **these rules are not confined to
`primitives*.zig`.** Nothing mechanical would have found them. The `format`
job's bare-`TypeError` grep has two independent blind spots, and the `vm.zig`
sites fell through both at once:

- **Path** — it scans only `src/primitives*.zig`, so `vm.zig` is never read.
- **Spelling** — it matches only `return PrimitiveError.TypeError`, and those
  sites write `VMError.TypeError`. Fixing the path alone would still miss them.

There are in fact three spellings of the same error in `src/`, since
`PrimitiveError` and `VMError` are both aliases of `errors.KaappiError` and
`ffi.zig` declares inline `error{TypeError}` sets instead of using either. A
grep covering all three outside `primitives*.zig` returned 35 sites, triaged
by #1880. They were not 35 problems, and the four groups wanted four different
treatments:

| Group | Sites | What it was | What #1880 did |
|---|---|---|---|
| A | 2, `vm_records.zig` | Live defects: a sealed parent rtd and a `nongenerative` uid collision reported `error[KP3002]: type error` and nothing else | Both now report through `primitives_srfi237.zig`'s shared helpers as KP3007 with a message (plus a third condition the census could not see — below) |
| B | 4, `vm_dispatch.zig` + `vm_calls.zig` | Latent: two of `callFfi`'s four call sites supplied a fallback message and two did not | All four route through one `vm_calls.mapFfiError` |
| C | 2, `vm_dispatch.zig` | Already correct — `setErrorDetail` on the line above | Annotated `// bare-ok: detail set above` |
| D | 27, `ffi.zig` | Internal pass/fail signalling behind `validateArgsDetailed`, which supplies every message | Left alone |

Group A is the one worth knowing about beyond its own fix. R6RS's sealed-parent
and uid-collision rules are enforced twice — syntactically in
`vm_records.handleDefineRecordTypeR6RS`, procedurally in
`%make-record-type-descriptor` — and the procedural half had been getting this
right since #1868 while the syntactic half raised a message-less KP3002 the
whole time. Both the rule and its wording now live once, in
`primitives_srfi237.zig` (`RtdShape`, `sealedParentError`,
`reuseNongenerativeRtd`), so the two routes cannot disagree about what R6RS
requires or about how to say so. Only the procedure name differs, because a
caller who wrote `define-record-type` should not be told about the internal
primitive it desugars to.

Reading those two functions turned up a **third** condition of the same shape
that no grep in this section can see, and it is the more useful lesson: both
routes signalled "more than 255 fields once the parent's are counted" as a
`return switch` arm yielding a bare `TypeError`. Neither the path nor the
spelling blind spot explains that one — `return switch (err) { .X => VMError
.TypeError, … }` simply is not `return VMError.TypeError`, so a gate widened
to all three spellings and all of `src/` would still have walked past it. It
also showed why "bare" is the wrong mental model for these: out of a primitive,
`mapNativeError` fills a missing detail in from `args[0]`, so the procedural
half did not report *nothing* — it reported `type error in
'%make-record-type-descriptor': got "chi"`, confidently blaming the type's name
for a limit the field list broke. A message that names the wrong argument is
harder to spot in review than no message at all, and impossible to find by
counting grep hits.

Group B leaves one fact worth recording, because the obvious way to check it is
wrong. `callFfi`'s four sites are *not* reached by direct call / `apply` / `map`
— all three of those go through `vm_calls.zig`, and the two hot
`vm_dispatch.zig` sites are the **tail-call** and **tail-apply** opcodes, which
a non-tail call never reaches. A three-form check built from
`(f x)` / `(apply f …)` / `(map f …)` tests two sites twice and the other two
not at all; `tests/scheme/ffi/error-messages.scm` uses tail-position forms for
exactly this reason.

That leaves 27 sites, all of them Group D and all in `ffi.zig`, so widening the
gate is now a single question rather than a mixed bag: whether the validator's
internal pass/fail signal should carry a distinct tag (`error.FfiArgReject`)
that the grep would never count, or simply be annotated. Retagging them as
user-facing errors would change nothing a user sees and would break
`validateArgsDetailed`'s own switch. Until that is settled, read the gate as
covering the primitives layer it was written for, not the rules as a whole.

### Sandbox enforcement

Sandbox restrictions operate at two levels:

1. **Registration level** — `primitives.registerSandboxed()` omits
   dangerous procedure registrations (FFI, filesystem, threads). The
   library registry omits `(kaappi ffi)`, `(scheme file)`, etc.

2. **Defense-in-depth** — Individual procedures also check
   `vm.sandbox_mode` as a belt-and-suspenders guard. See
   `checkSandbox` in `primitives_ffi.zig`.

When adding a new procedure that accesses the filesystem, network, or
native code, add it to both layers.

---

## Testing

Every bug fix must include a regression test. Every new allocation
pattern in a loop should have a stress test that exercises GC pressure.
See `tests/scheme/smoke/gc-rooting-stress.scm` for the pattern.
