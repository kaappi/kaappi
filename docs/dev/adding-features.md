# Adding Features

Step-by-step guides for the most common extension tasks in Kaappi.

---

## Adding a Built-in Procedure

This is the most common change. Follow these steps:

### 1. Write the function

Choose the appropriate `src/primitives_*.zig` file based on domain (arithmetic,
string, vector, I/O, etc.) and add your function:

```zig
fn myProc(args: []const Value) PrimitiveError!Value {
    // Validate argument types
    if (!types.isFixnum(args[0])) return PrimitiveError.TypeError;

    // Compute result
    const n = types.toFixnum(args[0]);
    return types.makeFixnum(n + 1);
}
```

The function signature is always `fn([]const Value) PrimitiveError!Value`.
Arguments are passed as a slice -- arity checking has already been done by the
dispatch layer.

### 2. Register the procedure

In the same file's `registerXxx` function, add a registration call:

```zig
try reg(vm, "my-proc", &myProc, .{ .exact = 1 });
```

Arity options:
- `.{ .exact = N }` -- exactly N arguments
- `.{ .variadic = N }` -- N or more arguments

### 3. Export from a library

Add the name to the appropriate library in `src/library.zig`. For most
procedures, this means adding it to the `scheme_base_names` array:

```zig
const scheme_base_names = [_][]const u8{
    // ... existing names ...
    "my-proc",
};
```

For SRFI procedures, add to the corresponding SRFI names array.

### 4. Handle heap allocation

If your procedure allocates heap objects (strings, pairs, vectors, etc.), you
need the GC instance:

```zig
fn myAllocProc(args: []const Value) PrimitiveError!Value {
    const gc = primitives.gc_instance orelse return PrimitiveError.TypeError;
    const result = gc.allocPair(args[0], args[1]) catch return PrimitiveError.OutOfMemory;
    return types.makePointer(@ptrCast(result));
}
```

### 5. Handle calling Scheme procedures

If your procedure needs to call back into Scheme code (like `map` or
`for-each`), use the VM instance:

```zig
fn myHigherOrder(args: []const Value) PrimitiveError!Value {
    const vm = primitives.vm_instance orelse return PrimitiveError.TypeError;
    const result = vm.callValue(args[0], args[1..]) catch return PrimitiveError.TypeError;
    return result;
}
```

### 6. Test

Add unit tests in the appropriate `src/tests_*.zig` file and/or a Scheme
test in `tests/scheme/`.

---

## Adding a Compiler Form (Syntax)

When you need a new special form that the compiler must handle directly
(not a procedure and not a macro).

### 1. Add the string match

In `src/compiler.zig`, in the `compileForm` function, add a match for your
form name:

```zig
if (std.mem.eql(u8, name, "my-form")) {
    return forms.compileMyForm(self, args, dst, is_tail);
}
```

### 2. Implement the compilation

Choose the appropriate `compiler_*.zig` file based on category:

- `compiler_conditionals.zig` -- for conditional/boolean forms
- `compiler_bindings.zig` -- for binding/scoping forms
- `compiler_advanced.zig` -- for everything else

Write the compilation function:

```zig
pub fn compileMyForm(
    self: *Compiler,
    args: Value,
    dst: u8,
    is_tail: bool,
) CompileError!void {
    // Parse the form's subexpressions from `args`
    const body = types.car(args);

    // Compile subexpressions, emit bytecode
    try self.compileExpr(body, dst, is_tail);
}
```

### 3. Add the re-export

In `src/compiler_forms.zig`, add a re-export for the new function so the main
compiler can find it:

```zig
pub const compileMyForm = @import("compiler_advanced.zig").compileMyForm;
```

### 4. Test

Test both at the Zig level (compile and check emitted bytecode) and at the
Scheme level (run expressions using the new form).

---

## Adding a New Heap Type

When you need a new kind of object that lives on the GC heap.

### 1. Add the tag

In `src/types.zig`, add a new variant to `ObjectTag`:

```zig
pub const ObjectTag = enum(u6) {
    // ... existing tags (0-34 used) ...
    my_type = 35,  // Use the next available slot
};
```

Slots 35-63 are available.

### 2. Define the struct

In `src/types.zig`, define the struct. The first field **must** be the `Object`
header:

```zig
pub const MyType = struct {
    header: Object,
    data: i64,
    name: []const u8,
};
```

### 3. Add the allocator

In `src/memory.zig`, add an `allocMyType` function:

```zig
pub fn allocMyType(self: *GC, data: i64, name: []const u8) !*types.MyType {
    const obj = try self.allocObject(types.MyType, .my_type);
    obj.data = data;
    obj.name = name;
    return obj;
}
```

### 4. Handle in GC mark phase

In `memory.zig`'s `markValue` function, add a case for tracing any contained
Values (so their referents are not collected):

```zig
.my_type => {
    const mt = obj.as(types.MyType);
    // Mark any Value fields:
    // self.markValue(mt.some_value);
},
```

If your type contains no Value fields, you can skip this (but still add the
case for completeness).

### 5. Handle in GC free phase

In `memory.zig`'s `freeObject` function, add a case to free any owned memory:

```zig
.my_type => {
    const mt = obj.as(types.MyType);
    // Free any heap-allocated fields:
    // self.allocator.free(mt.name);
    self.allocator.destroy(mt);
},
```

### 6. Add display support

In `src/printer.zig`, add a case for how the object should be printed:

```zig
.my_type => {
    try writer.writeAll("#<my-type>");
},
```

### 7. Test

Create both unit tests (allocation, GC survival) and Scheme tests.

---

## GC Safety Rules

The garbage collector can run during any heap allocation. If you hold a
pointer to a heap object and then allocate, the pointer may be invalidated.

### The pushRoot/popRoot pattern

```zig
// UNSAFE: second allocation might move `first`
var first = try gc.allocPair(a, b);
var second = try gc.allocPair(c, d);  // GC might run here!
// `first` might now be a dangling pointer

// SAFE: root `first` before the second allocation
var first_val = types.makePointer(@ptrCast(try gc.allocPair(a, b)));
gc.pushRoot(&first_val);
var second = try gc.allocPair(c, d);  // GC runs, but first_val is rooted
gc.popRoot();
// `first_val` is still valid
```

### Rules

1. **Always root Values before allocating.** If you hold a `Value` that points
   to a heap object and you're about to call any function that might allocate
   (including `vm.execute()`), root it first.

2. **Pops must be LIFO.** `pushRoot`/`popRoot` calls are a stack. Always pop
   in reverse order of pushes.

3. **Root Function pointers before execute.** The VM's `execute()` wraps the
   function in a closure internally, which allocates:

   ```zig
   var func_val = types.makePointer(@ptrCast(func));
   gc.pushRoot(&func_val);
   const result = vm.execute(func) catch |err| {
       gc.popRoot();
       return err;
   };
   gc.popRoot();
   ```

4. **Root across any Scheme callback.** Procedures like `map` and `for-each`
   that call Scheme functions must root any values they need after the callback
   returns.

---

## Zig 0.16 Patterns

These patterns differ from earlier Zig versions and are important to get right:

```zig
// ArrayList is UNMANAGED -- pass allocator to every method
var list: std.ArrayList(u8) = .empty;
list.append(allocator, item) catch {};
list.deinit(allocator);

// I/O via POSIX syscalls (no std.io)
std.posix.system.write(1, bytes.ptr, bytes.len);  // stdout
std.posix.system.write(2, bytes.ptr, bytes.len);  // stderr

// String formatting via fixed buffer writer
var buf: [256]u8 = undefined;
var w: std.Io.Writer = .fixed(&buf);
w.print("{d}", .{42}) catch {};
const result = w.buffered();

// main() signature
pub fn main(init: std.process.Init.Minimal) !void { ... }

// Allocator
var da = std.heap.DebugAllocator(.{}).init;
const allocator = da.allocator();

// StringHashMap is managed (stores allocator internally)
var map = std.StringHashMap(Value).init(allocator);
map.deinit();  // no allocator arg needed
```
