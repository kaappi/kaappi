---
description: Pattern for adding a new built-in Scheme procedure to Kaappi
---

# Add a Built-in Procedure

Checklist. `docs/dev/adding-features.md` ("Adding a Built-in Procedure") is the
detailed reference — read it for anything this doesn't cover.

## Steps

1. **Define the function** in the `src/primitives_*.zig` file matching its
   domain (arithmetic, string, vector, I/O, …). There are 30 of those;
   `primitives.zig` itself is the registration hub plus core list/pair ops, so
   a new procedure rarely belongs there:

```zig
fn myProc(args: []const Value) PrimitiveError!Value {
    // Validate arg types — typeError names the procedure and the bad value
    if (!types.isFixnum(args[0]))
        return primitives.typeError("my-proc", "exact integer", args[0]);
    // Compute result
    const n = types.toFixnum(args[0]);
    return types.makeFixnum(n + 1);
}
```

The signature is always `fn([]const Value) PrimitiveError!Value`; arity is
already checked by the dispatch layer.

2. **Add a spec entry** to the file's `specs` table. One entry carries the
   name, function, arity, and the libraries that export it — `library.zig`
   derives every export set from these tags, so there is no second list:

```zig
.{ .name = "my-proc", .func = &myProc, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
```

An **internal helper** — a `%`-prefixed name no user program should have to
avoid — never takes a `scheme.*` tag, which reserves the name against every
user library that imports it (kaappi#1856; a comptime check rejects this).
Two cases:

- Only compiler-generated code names it: `.libs = primitives.INTERNAL` —
  registered in `vm.globals`, exported by nothing.
- A portable `.sld` names it in its own Scheme source:
  `.libs = primitives.INTERNAL_PUBLIC`, which adds `(kaappi primitives)` so
  the `.sld` can import it (`lib/srfi/27.sld` and the record SRFIs do).

Synthesize *references* to either with `Compiler.trueBuiltinRefOrSymbol` /
`globals_mod.baseBindingSymbol`, never a bare `allocSymbol("%foo")` — that
picks up a user binding of the same name.

3. **Add a test** in the matching `src/tests_*.zig` file (44 of them, one per
   feature area — a new file only for a genuinely new area). Not in
   `src/vm.zig`: its single `test` block only imports sibling modules into the
   test build and holds no assertions. Use the `testing_helpers.zig` helpers:

```zig
const th = @import("testing_helpers.zig");

test "my-proc increments" {
    try th.expectEval("(my-proc 42)", 43);
}
```

`th.expectEvalTrue` / `expectEvalBool` / `expectEvalVoid` cover other result
shapes; `th.TestContext` is for multiple evals or inspecting the result value.
Add a Scheme test under `tests/scheme/` when the behavior deserves an
end-to-end check — and a bug fix always needs a regression test.

## Arity options

- `.{ .exact = N }` — exactly N arguments
- `.{ .variadic = N }` — at least N arguments

## Heap allocation in primitives

To allocate (cons, list, string operations), take the threadlocal GC instance
from `memory.zig` — `primitives.zig` does not re-export it:

```zig
const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
return gc.allocPair(a, b) catch return PrimitiveError.OutOfMemory;
```

Read `.claude/rules/gc-safety.md` before allocating more than once: values held
in Zig locals across a second allocation need rooting, and mutating a heap
object's fields needs a write barrier.

## Calling back into Scheme

```zig
const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
return vm.callWithArgs(proc, call_args);
```

Let the callee's error propagate — `PrimitiveError` and `VMError` are both
aliases of `errors.KaappiError`, so a raise inside the Scheme procedure returns
out of your primitive with its detail intact.

## Error handling

Use `primitives.typeError(proc, expected, got)` for type checks — it produces
`type error in 'my-proc': expected exact integer, got #t` instead of an
anonymous `TypeError`. The `format` CI job ratchets against new bare
`return PrimitiveError.TypeError`, so adding one fails the build; only
infrastructure guards with no procedure context to report opt out, with
`// bare-ok: <reason>`.

`expectFixnum` / `expectString` / `expectChar` / `expectPair` / `expectVector` /
`expectPort` validate and unwrap in one step, and `indexError(proc, index, len)`
covers out-of-range access — prefer it over returning `IndexOutOfBounds` bare,
for the same reason. Error tags with no detail to attach (`DivisionByZero`,
`OutOfMemory`, …) are returned directly.
