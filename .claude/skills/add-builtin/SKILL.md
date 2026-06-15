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

2. **Register it** in `registerAll()` in `src/primitives.zig`:
```zig
try reg(vm, "my-proc", &myProc, .{ .exact = 1 });  // or .{ .variadic = N }
```

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
