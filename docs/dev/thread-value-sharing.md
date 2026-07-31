# Cross-thread value sharing

What may cross an SRFI-18 thread boundary, by which route, and what the
engine actually checks. Written for kaappi#1937, which found that the
`gc_deep_copy.zig` uncopyable-tag list — the thing that reads like the
authoritative answer — governs one of the two routes and not the other.

**The short version.** A value reaches another thread by one of two
routes, and they have separate, unrelated enforcement:

| route | how a value travels | what enforces the rules |
|---|---|---|
| **copy** | deep-copied into the other heap | the uncopyable-tag list, one central check |
| **globals** | reached by pointer, no copy | per-type owner checks in individual primitives — present for exactly two types |

The tag list is not a statement about what can cross a thread boundary.
It is a statement about what can be *copied*. Thirteen of the fourteen
tags on it are freely reachable through a top-level `define`, and for two
of them that is the only supported way to share them at all.

## The copy route

Three boundaries deep-copy, and all three go through
`gc_deep_copy.deepCopyValue`:

- `thread-start!` — the thunk closure, copied into a
  `shared_channel.Envelope` on the **parent** thread before the child is
  spawned, then out of the envelope into the child's heap
  (`primitives_srfi18.zig`).
- `thread-join!` — the result, or the uncaught exception, copied into an
  envelope on the **child** as it exits, then out into the parent's heap
  at the join. A refusal therefore happens child-side and reaches the
  parent as a stored `failed` status, not as a live error.
- `channel-send` / `channel-receive` — the message payload, the same way.

Each traversal is a separate `deepCopy`; the envelope exists so neither
thread ever walks the other's live heap.

"Deep-copied thunk closure" means the closure's **lexical captures**. A
thunk that names a top-level binding captures nothing: the child resolves
that name through the shared globals map at run time, so the value never
enters the copy at all. This is the whole reason the two routes exist as
separate things.

`gc_deep_copy.zig` refuses fourteen tags outright:

```text
port  continuation  fiber  mutex  condition_variable  ffi_callback
file_info  user_info  group_info  directory_object  scheme_environment
ephemeron  guardian  transport_cell
```

Channels are **not** on that list. Their arm promotes the channel to a
shared representation and aliases it, which is what makes a lexically
captured channel the supported way to share one (KEP-0002 §2).

A refusal surfaces as `error.UncopyableType`, which the boundary turns
into a catchable error naming neither the type nor the offending value:

```text
uncaught exception in thread: thread thunk contains an uncopyable type
(port, continuation, etc.), or a channel owned by another thread
```

## The globals route

`VM.initForThread` shares the parent's `globals` map **by pointer**. A
child thread reading a top-level binding gets the parent's object itself,
in the parent's heap, with no copy and no check at the point of access.

Two types defend themselves at the primitive level, by comparing
`Object.owner` against the running thread's `GC.id`:

| type | check | sites |
|---|---|---|
| channel | `channel belongs to another thread; pass it through the thread thunk to share it` | `primitives_fiber.zig` — `channel-send`, `channel-receive`, `channel-close!`, `channel-closed?` |
| thread handle | `thread belongs to another OS thread; a thread handle may only be used by the thread that created it` | `primitives_srfi18.zig` `checkThreadOwner` — `thread-name`, `thread-specific`, `thread-specific-set!`, `thread-start!`, `thread-terminate!`, `thread-join!` |

Nothing else is checked. Every other type on the uncopyable list is fully
usable from a child thread through a global.

## The actual matrix

Verified at `e24e594e`, ReleaseSafe, isolated `KAAPPI_HOME`. "capture"
means bound in a `let` and closed over by the thunk; "global" means bound
with a top-level `define` and named by the thunk.

| type | capture | global | status |
|---|---|---|---|
| thread handle (fiber) | refused | refused | **coherent** — usable only by its creating thread |
| channel | **aliased — the supported way** | refused | **coherent** — one supported route, and it is checked |
| mutex | refused | works | **inverted** — the only way to share one is the route the list refuses |
| condition variable | refused | works | **inverted** — same |
| port | refused | works | unchecked (see below) |
| continuation | refused | no error, does not resume the parent | unchecked — kaappi#1936 |
| `scheme-environment` | refused | works (`eval` in it succeeds) | unchecked |
| `file-info` / `user-info` / `group-info` | refused | works | unchecked |
| directory object | refused | works | unchecked |
| ephemeron / guardian | refused | works | unchecked — these are bound to one GC's collection cycle |
| transport cell | refused | — | unreachable from Scheme: on this non-moving collector a transport-cell guardian always yields `#f` |
| ffi-callback | refused | not probed | needs a loaded FFI library to construct |

Two rows deserve their own note.

**Mutexes and condition variables are inverted relative to channels.**
The two appear side by side in every concurrency example, and the correct
idiom is exactly opposite:

```scheme
;; channel — MUST be captured lexically
(define (worker)
  (let ((ch (make-channel)))
    (thread-start! (make-thread (lambda () (channel-send ch 'done))))
    (channel-receive ch)))

;; mutex — MUST be a top-level global
(define m (make-mutex))
(thread-start! (make-thread (lambda () (mutex-lock! m) (mutex-unlock! m))))
```

Swap the two and both break, each in its own way: the captured mutex is
refused by the copy at `thread-start!`, and the global channel raises
from inside `channel-send`. A mutex left locked by a dead child correctly
reads `abandoned` from the parent (kaappi#1458), so the globals route is
genuinely supported here, not merely tolerated.

**A port through a global is not sound "because ports hold no Values".**
That is true of the plain string- and fd-backed ports whose mutable state
is byte offsets and buffers — a shared input port advances one position
for both threads, and a shared output port interleaves in call order:

```text
parent writes "P1;", child writes "CHILD;", parent writes "P2;"
  ⟹  "P1;CHILD;P2;"
```

But SRFI 181 gave `Port` two Value-bearing fields, `custom_backend` (five
Scheme callbacks) and `transcode` (a wrapped port). A custom port reached
through a global runs **the parent's closures on the child thread**, and
those closures are ordinary Scheme subject to kaappi#1924's
mutate-through-a-global hazard. Verified: a child reading from a custom
textual input port really does execute the parent-heap `read!` procedure
and really does advance the parent's own state. So the port row is not
one rule — it is "sound for the representations that hold no Values, and
the general mutation hazard for the ones that do".

## Why the checks were not simply extended to the globals route

kaappi#1937 offered this as one of two fixes. It cannot be done
uniformly, because for two of the fourteen tags the globals route is the
*only* route: refusing a foreign mutex or condition variable would remove
the sole supported way to synchronise threads, and SRFI-18 has no other.
Ports through globals would break too, and the issue itself argues that
case is fine. A per-type check is possible — `Object.owner` is on every
heap object, so the mechanism is already there and the channel and thread
cases show the shape — but it is a per-type decision about a per-type
idiom, not one sweep, and the two known-unsound cases have their own
issues (kaappi#1924, kaappi#1936).

What this document fixes is the narrower thing that made the state
misleading: the tag list read as a guarantee it never provided.

## Where these rules were written down before

Scattered, and each in a place that only answers one question:

- `lib/srfi/120.sld`'s header — the channel rule, and the general warning
  that a top-level binding "reaches the ORIGINAL object from the wrong
  heap". Correct, but discoverable only from the timer library.
- `tests/scheme/srfi/srfi18-cross-heap-abandoned-mutex.scm`'s header —
  the mutex rule, stated exactly right, inside a regression test.
- `tests/scheme/srfi/srfi18-cross-thread-channels.scm`'s header —
  KEP-0002's two motivation paths.
- `CLAUDE.md`'s "OS threads (SRFI-18)" section — the copy route only.

Nothing anywhere noted that channels and mutexes differ, which is the
finding that motivated this file.

## Keeping it honest

`tests/scheme/srfi/srfi18-sharing-model.scm` pins both routes for the nine
types that cover every distinct enforcement shape in the matrix: thread
handle, channel, mutex, condition variable, port (both directions),
continuation, environment, ephemeron, guardian. It is deliberately a
*characterisation* test — it asserts what the engine does today, including
the rows this document calls unchecked, so that a change to any of them
fails visibly and lands here rather than silently widening the gap between
the code and this table.

The four SRFI-170 record types are left out on purpose: `user-info` raises
"unsupported" on Windows and this suite runs there, and those rows add no
enforcement shape the nine already cover. `ffi-callback` needs a loaded
FFI library; the transport cell is unreachable, as above.

Two smaller checks live elsewhere and are worth knowing about rather than
duplicating: `src/tests_deepcopy.zig` asserts the port and continuation
refusals at the `GC.deepCopy` level directly, and
`src/tests_shared_channel.zig` asserts that a channel *message* carrying a
port is refused the same way.
