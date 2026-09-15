# The C FFI and the sandbox boundary

How Scheme calls C: the `(kaappi ffi)` surface, the type system and where
each value is marshaled, the arity-dispatch tables and their limits, the
library search path, callbacks and what happens when one raises, the
places the FFI touches the GC and the thread model, and the two layers by
which `--sandbox` keeps all of it out. This is the as-built companion to
[KEP-0011](https://github.com/kaappi/keps/blob/main/keps/0011-ffi-and-sandbox.md)
(the design record). The user-facing walkthrough — writing a C extension,
the Makefile, the package manifest — is the site's C-extensions guide; the
quality bar an ecosystem FFI package must meet is
[ecosystem-library-bar.md](ecosystem-library-bar.md).

The one-paragraph version: **a signature-table FFI, not libffi.** A bound
function carries its declared parameter and return types; at call time
the 18 declared types collapse onto 7 canonical C classes and a comptime
or hand-curated table selects a Zig function-pointer type for that exact
shape. Anything outside the tables is a catchable "unsupported FFI
signature". Pointers cross the boundary as plain integers that the
collector knows nothing about, which is the whole reason the FFI is the
first thing `--sandbox` removes.

## Where it sits

| File | Owns |
|------|------|
| `primitives_ffi.zig` | the seven `(kaappi ffi)` primitives, `checkSandbox`, the `dlopen` search path and its diagnostics, `parseType`, `matchCallbackSig` |
| `ffi.zig` | `callFfi`: argument validation, marshaling in both directions, `normalizeType`, the arity dispatchers `callFfiGeneric`/`callFfi4`/`callFfi5` |
| `ffi_callback.zig` | the 32-slot trampoline pool, the 7 callback signatures, the callback error stash, `markCallbackRoots` |
| `types_ffi.zig` | `FfiType`, `FfiLibrary`, `FfiFunction`, `FfiCallback` |
| `platform.zig` / `platform_win.zig` | `dlOpen`/`dlSym`/`dlClose`/`dlError` over `dlopen(3)` or `LoadLibraryW`/`GetProcAddress`, `dl_suffixes` |
| `vm_calls.zig` | `mapFfiError`, the four call sites that route an FFI call from the VM |
| `primitives.zig` / `library.zig` | `sandboxAllowed`, `registerSandboxed`, the export filter |

Every FFI spec is `.sandbox = false, .wasm = false`: the library does not
exist under `--sandbox` or on WASM, and `kaappi features` reports
`sandbox_available` accordingly.

## The surface

| Procedure | Does |
|-----------|------|
| `(ffi-open name-or-#f)` | `dlopen`; `#f` opens the running process (libc and everything linked). Returns an `ffi-library` |
| `(ffi-fn lib "sym" '(param-types) 'ret-type)` | `dlsym` plus type parsing. Up to 16 parameter types may be *declared*; only 5 are *callable* (below) |
| `(ffi-close lib)` | `dlclose` and null the handle; a later call through a function bound from it is a catchable "FFI library is closed" |
| `(ffi-callback proc '(params) 'ret)` | wrap a closure as a C function pointer in a trampoline slot |
| `(ffi-callback-release cb)` | free the slot |
| `(ffi-callback? obj)` | predicate |
| `(ffi-bytevector-ptr bv)` | the data pointer as an integer, 0 for an empty bytevector |

An ecosystem package uses exactly this shape: a `%`-prefixed `ffi.sld`
that opens `libkaappi_<name>` and binds each C entry point with `ffi-fn`,
and a high-level `.sld` on top ([thottam.md](thottam.md) for the layout).
A bound `ffi-function` is applied like any procedure; `callValue` and
`callWithArgs` dispatch on the tag and call `callFfi` ([vm.md](vm.md)).

## Types and marshaling

`FfiType` has 18 variants: `int`, `long`, `double`, `float`, `string`,
`pointer`, `void`, `bool`, `char`, `size_t`, and `int8`/`16`/`32`/`64`
with their unsigned twins. `normalizeType` collapses them onto the seven
**canonical classes** the dispatch tables are built from:

| Class | Carrier | Declared types |
|-------|---------|----------------|
| `int` | `c_int` | `int`, `int8`, `int16`, `int32`, `uint8`, `uint16`, `char`, `bool`, and `long` on Windows (LLP64: C `long` is 32-bit there) |
| `long` | `i64` | `long`, `int64`, `uint32`, `uint64`, `size_t` |
| `double`, `float`, `string`, `pointer`, `void` | themselves | |

**Arguments** (`validateArgsDetailed`, then `marshalArg`): a type mismatch
is `TypeError` naming the function, the position, the expected and the
actual type; a value of the right kind but the wrong magnitude for a
narrow type is `InvalidArgument` — `KP3007`, not `KP3002` — so a caller can
tell a wrong type from a wrong size (#2026). A string is copied into a
4096-byte stack buffer and NUL-terminated, so it is capped at 4095 bytes
and may not contain NUL. A `bool` argument is coerced to exactly `#t`/`#f`
before dispatch, because loading any other integer into a C `_Bool` is
undefined behaviour that traps under UBSan-instrumented libraries (#796).
A `pointer` argument accepts a fixnum or single-limb bignum address, an
active `ffi-callback` (its trampoline pointer), or a bytevector (its data
pointer, passed directly).

**Returns** (`marshalReturn`): an integer that fits ±2^47 is a fixnum,
otherwise a bignum; `uint32` is masked, `uint64`/`size_t` reinterpret the
carrier as unsigned; a pointer return is the address as an integer, null
as 0; a `string` return is copied into a fresh Scheme string, null as
`#f`; `bool` normalizes nonzero to `#t`; `char` maps 0–255 to a character.

## Dispatch and its limits

`callFfiGeneric(N)` is comptime-expanded for arities 0–3: nested
`inline for` loops over the canonical classes select a
`*const fn(...) callconv(.c) ...` type for the exact shape and cast the
`dlsym` result to it. Arities 4 and 5 would exceed Zig's eval-branch quota,
so `callFfi4` and `callFfi5` are **hand-curated tables** of the shapes
ecosystem libraries actually use (pointer/long mixes returning `int`,
`pointer` or `void`). A shape outside the tables, or a sixth parameter, is
the catchable "unsupported FFI signature" / "unsupported parameter count".

Those numbers — 5 callable parameters, 16 declarable, 32 callback slots,
7 callback signatures — are current implementation limits, not
guarantees; KEP-0011 leaves their contract status open. Adding a shape to
`callFfi4`/`callFfi5` is the routine way a new ecosystem binding is
unblocked, and [ecosystem-library-bar.md](ecosystem-library-bar.md) is
why the ecosystem suites must be rerun when `ffi.zig` changes: the unit
tests cover marshaling, not which shapes the libraries depend on.

Every error out of `callFfi` is a bare Zig error tag plus a detail
message; `mapFfiError` in `vm_calls.zig` maps the tag and supplies a
fallback message only when none was set (#1880). Its four call sites are
`callValue`, `callWithArgs`, and the tail-call and tail-apply opcodes,
which is why `tests/scheme/ffi/error-messages.scm` exercises tail-position
calls: a non-tail call never reaches the opcode arms.

## Finding the library

`ffi-open` probes, in order: the name as given; the name with each
`platform.dl_suffixes` appended (`.dylib`, `.so`, `.so.6` — the last is
how glibc's `libm`/`libc` load, whose unversioned `.so` is a linker
script; `.dll` on Windows); then, **for a bare name only**,
`$KAAPPI_HOME/lib/` (default `~/.kaappi/lib/`), which is where thottam
installs a package's shared library. A name containing a path separator
is a pathname under `dlopen(3)` semantics and is not re-searched.

`dlerror(3)` remembers only the last failure, so `DlOpenDiag` snapshots
two: the as-is attempt's error, and the error of the first candidate that
*exists on disk* but refused to load. The second is the one that matters —
a code-signing, architecture or file-format rejection — and it is reported
in preference to the "no such file" of a probe the user never asked for.
On Windows `dlError` renders `GetLastError()` at read time, so the
snapshot is taken before the existence probe overwrites it. macOS release
binaries carry the entitlement that lets user-compiled libraries load
without library validation.

`ffi-close` is explicit: the sweep of an unreachable `ffi-library` frees
the wrapper but never `dlclose`s, because a function bound from it may
still be live.

All of this presupposes a binary that can `dlopen` at all. Zig's bare
`<arch>-linux` target is musl-static, and static musl has no dynamic
loader, so such a `kaappi` rejects every `ffi-open` — which is how every
released Linux binary was FFI-dead until #1783 switched the x86_64 and
aarch64 release rows to `<arch>-linux-gnu.2.28`, and how riscv64 stayed
that way until #2595 gave its row the same `zig_target`. `release.yml`'s
`linux-ffi-smoke` job runs each glibc Linux artifact (riscv64 under
QEMU) through an `ffi-open` of `libm.so.6` before anything is published;
a new Linux row needs a leg there ([porting.md](porting.md) Stage 6).
A from-source `zig build` on a glibc host is unaffected: it targets the
host's own libc.

## Callbacks

`ffi-callback` hands C a function pointer for a Scheme procedure. There
is no runtime code generation: `ffi_callback.zig` holds a fixed pool of
**32 slots** and, per slot, one comptime-generated trampoline for each of
**7 signatures** — `(pointer pointer) → int`, `(pointer) → void`,
`() → void`, `(pointer) → int`, `(int pointer) → int`, `(int) → void`,
`(pointer pointer) → void`. `matchCallbackSig` maps a declared signature
to one of them or reports "unsupported callback signature"; a full pool is
"no free callback slots". The trampoline reads its slot's closure and
calls it through `callWithArgs`; `markCallbackRoots` marks every active
slot's closure each collection, and sweeping an unreachable but still
active callback releases the slot.

**A Scheme error inside a callback cannot unwind the C frames between the
FFI call and the trampoline.** So `noteCallbackError` stashes it on the
VM (`last_callback_error`, `callback_error_value`), hands C a default
return, and `callFfi` re-raises the stash after C returns — the C result
is garbage in that case and is never delivered as a success (#1185). A
VM-level fault with no exception object is turned into one from the
recorded detail; a non-integer return from an `int` callback is stashed
the same way rather than coerced to 0. First error wins; C may keep
invoking the callback on poisoned state. The control-flow signals —
`ContinuationInvoked`, `Yielded`, `Terminated`, `ExecutionTimeout` — are
deliberately *not* stashed: resuming a continuation or parking a fiber
across live C frames is unsupported, the same class as the native-frame
limit in [vm.md](vm.md).

## Where the FFI meets the GC and the threads

- **Pointers are not managed.** They are integers to Scheme. A bytevector
  passed as `pointer` hands C `bv.data.ptr` for the duration of the call;
  the collector is non-moving, so the address is stable, but nothing
  keeps the bytevector alive past the call if C retains the pointer.
- **A blocking FFI call is a quiescent state** for the child-thread
  collection protocol: `callFfi` reports `.in_native` on a child VM so a
  collecting parent can mark its registers, and a callback that re-enters
  Scheme flips back to `.running` for its extent ([memory.md](memory.md),
  #1933).
- **Across a thread boundary** an `ffi-library` and an `ffi-function` are
  *copied*: the wrapper is a fresh object in the destination heap, the
  handle and symbol are shared by value, no second `dlopen`. They used to
  be aliased, which freed a child-created handle under the parent and read
  it back as `(0.0 . 0.0)` (#2027). The consequence: `ffi-close` nulls one
  wrapper only, so a copy on another heap no longer sees the library as
  closed. An `ffi-callback` is *refused* by deep copy — it wraps a live
  closure, not a process-global address
  ([thread-value-sharing.md](thread-value-sharing.md)).
- **Sweeping** frees an `ffi-function`'s name and type slice; an
  `ffi-library`'s name; and releases an active callback's slot.

## The sandbox

`--sandbox` is a global flag, pre-scanned from argv before any primitive
is registered and honoured only *before* the script name (#783). It keeps
the FFI out twice:

1. **Registration.** `Lib.sandboxAllowed` is false for `kaappi.ffi` (and
   for `scheme.file`, `scheme.load`, `scheme.eval`, `scheme.repl`,
   `scheme.process-context`, `scheme.r5rs`, `kaappi.process`, `srfi.18`,
   `srfi.170`, `srfi.192`, `internal`), so the library is never
   registered and `(import (kaappi ffi))` fails; `registerSandboxed` skips
   every spec with `.sandbox = false`, so the names are never bound
   either. This is the primary mechanism: nothing to call.
2. **Runtime guard.** `checkSandbox` runs at the top of `ffi-open`,
   `ffi-fn`, `ffi-close`, `ffi-callback` and `ffi-bytevector-ptr` and
   raises "`ffi-open`: not allowed in sandbox mode" if a binding was
   smuggled in anyway.

`tests/scheme/sandbox/sandbox-escape.sh` asserts both: each primitive and
the import are blocked. A new procedure that reaches native code, the
filesystem or the network goes into both layers
([gc-safety-and-error-handling.md](gc-safety-and-error-handling.md)). The
rest of the sandbox — the filesystem and thread primitives, file-backed
library loads, the `.sbc` cache, and the *degrading* capabilities such as
`processor-count` reporting 1 — is KEP-0011's table; the FFI is only its
sharpest edge.

## Tests

| Suite | Covers |
|-------|--------|
| `src/ffi.zig` (44 inline tests) | marshaling in both directions, every narrow-range check, bignum and unsigned paths |
| `src/tests_ffi.zig` (14) | `bool` coercion (#796), callback error re-raise (#1185), `ffi-open` diagnostics, `mapFfiError` (#1880, #2026) |
| `src/ffi_callback.zig` (3) | pointer-argument marshaling into a callback |
| `tests/scheme/ffi/` (17 files + `fixtures/u64test.c`) | end to end against libc and a fixture built per platform in CI (`zig cc -target …-windows-gnu` for the Windows DLL): types, ranges, bytevector pointers, callbacks and their errors, use after close, the thread boundary (#2027), fork reseeding |
| `tests/scheme/sandbox/` (4 scripts) plus `smoke/sandbox-script-arg-783.sh` | escape assertions, SRFI 181 under sandbox, the degrading capabilities, the pre-scan boundary |

The FFI is the one subsystem whose tests need a C compiler on the box;
the BSD and Windows port docs say how the fixture gets there.

## What this design does not do

- **Arbitrary signatures.** No libffi, no runtime thunk generation. A
  shape is either in a table or unsupported.
- **Structs by value, varargs, or C strings longer than 4095 bytes.**
- **Ownership.** Nothing frees what C allocated or keeps alive what C
  retained; `ffi-close` is manual on purpose.
- **Continuations or fiber parks across a C frame.**
- **A network gate in the sandbox** distinct from blocking the libraries
  that provide sockets; KEP-0011 records this as open.
