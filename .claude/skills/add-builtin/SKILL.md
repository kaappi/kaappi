---
description: Pattern for adding a new built-in Scheme procedure to Kaappi
---

# Add a Built-in Procedure

## Steps

1. **Define the function** in `src/primitives.zig`:

```zig
fn myProc(args: []const Value) PrimitiveError!Value {
    // Validate arg types
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;
    // Compute result
    return types.makeFixnum(result);
}
```

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
See `docs/dev/adding-features.md`.

3. **Add a test** in `src/vm.zig` test section:

```zig
test "eval my-proc" {
    var gc = memory.GC.init(std.testing.allocator);
    defer gc.deinit();
    var vm = try makeTestVM(&gc);
    defer vm.deinit();
    const result = try vm.eval("(my-proc 42)");
    try std.testing.expectEqual(@as(i64, expected), types.toFixnum(result));
}
```

4. **Update STATUS.md** — add the procedure to the "Implemented" list.

## Arity options

- `.{ .exact = N }` — exactly N arguments
- `.{ .variadic = N }` — at least N arguments

## Heap allocation in primitives

If the procedure needs to allocate (cons, list, string operations), use the global GC instance:

```zig
const gc = gc_instance orelse return PrimitiveError.OutOfMemory;
return gc.allocPair(a, b) catch return PrimitiveError.OutOfMemory;
```

## Error handling

Return `PrimitiveError.TypeError` for type errors, `PrimitiveError.DivisionByZero`, etc.
