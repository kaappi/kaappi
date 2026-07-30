# Adding Features

Step-by-step guides for the most common extension tasks in Kaappi.

---

## Adding a Built-in Procedure

This is the most common change, and this section is the detailed reference for
it. The root `CLAUDE.md` and the `/add-builtin` skill are short checklists that
defer here. Follow these steps:

### 1. Write the function

Choose the appropriate `src/primitives_*.zig` file based on domain (arithmetic,
string, vector, I/O, etc.) and add your function. There are 31 of them;
`primitives.zig` itself is the registration hub plus core list/pair ops, so a
new procedure almost always belongs in one of the domain files, not there:

```zig
fn myProc(args: []const Value) PrimitiveError!Value {
    // Validate argument types
    if (!types.isFixnum(args[0]))
        return primitives.typeError("my-proc", "exact integer", args[0]);

    // Compute result
    const n = types.toFixnum(args[0]);
    return types.makeFixnum(n + 1);
}
```

The function signature is always `fn([]const Value) PrimitiveError!Value`.
Arguments are passed as a slice -- arity checking has already been done by the
dispatch layer.

**Report type errors through `primitives.typeError(proc, expected, got)`**, not
a bare `return PrimitiveError.TypeError`. `typeError` attaches the procedure
name, the expected type, and a description of what actually arrived to the
error detail, so the user sees `type error in 'my-proc': expected exact
integer, got #t` instead of an anonymous `TypeError`. The `format` CI job
enforces this with a ratchet on the count of unannotated bare returns
(`.github/workflows/ci.yml`), so adding one fails the build. Only
infrastructure guards that have no procedure context to report -- the
`vm_instance orelse` fallbacks, for example -- take a bare return, and those
carry a `// bare-ok: <reason>` comment to opt out of the ratchet.

For the common checks there are wrappers that validate and unwrap in one step,
each taking the procedure name for the same error detail: `expectFixnum`,
`expectString`, `expectChar`, `expectPair`, `expectVector`, `expectPort`, plus
`indexError(proc, index, len)` for out-of-range access.

### 2. Register the procedure and its libraries

Add an entry to the same file's `specs` table. One entry carries the name,
implementation, arity, *and* the set of libraries that export it -- there is
no second list to keep in sync:

```zig
.{ .name = "my-proc", .func = &myProc, .arity = .{ .exact = 1 }, .libs = LS.initOne(.scheme_base) },
```

Arity options:

- `.{ .exact = N }` -- exactly N arguments
- `.{ .variadic = N }` -- N or more arguments

`.libs` takes a `LibSet` (`LS.initOne(.scheme_base)`,
`LS.initMany(&.{ .scheme_base, .scheme_r5rs })`, or one of the shorthand
aliases at the top of `src/primitives.zig`). `library.zig` derives every
standard library's export set from these tables at startup, so the tag *is*
the export. Two optional fields narrow that: `.sandbox = false` withholds the
primitive under `--sandbox`, `.wasm = false` on WASM.

### 3. If the procedure is an internal helper, do not export it

A primitive that only compiler-generated code or a portable `.sld` calls --
conventionally named with a `%` prefix -- belongs in `.internal`, not in a
standard library:

```zig
.{ .name = "%my-helper", .func = &myHelper, .arity = .{ .exact = 1 }, .libs = primitives.INTERNAL },
```

`.internal` registers the primitive in `vm.globals` (so it resolves by name,
including from a library body) while exporting it from nothing. Putting a `%`
name in `(scheme base)` instead reserves it against every user library that
imports `(scheme base)`, because R7RS 5.2 makes importing one identifier from
two libraries with different bindings an error -- a user library that defined
its own `%length` could not be imported at all (kaappi#1856). A comptime check
in `primitives.zig` now rejects any `%` name tagged with a `scheme.*` library.

If a *portable* `.sld` names the helper in its own Scheme source, tag it
`primitives.INTERNAL_PUBLIC` instead: that is `.internal` plus
`.kaappi_primitives`, which exports it from `(kaappi primitives)` so the
`.sld` can declare the dependency (`lib/srfi/27.sld` and the record SRFIs do).
A helper tied to one SRFI belongs in that SRFI's own `*_primitives`
sub-library (`.srfi_237_primitives` and friends) rather than the general one.
Either way the name stays out of `(scheme base)`.

Compiler-synthesized *references* to an internal helper must go through
`Compiler.trueBuiltinRefOrSymbol` / `globals_mod.baseBindingSymbol` rather
than a bare `gc.allocSymbol("%my-helper")`: that marks the reference so it
resolves against the pristine startup snapshot
(`LibraryRegistry.internal_bindings`) instead of whatever the program being
compiled has bound that name to. A bare symbol silently picks up a user's
same-named binding -- which is how `define-record-type` inside a library that
defined its own `%record-ref` started returning the wrong value.

For SRFI procedures, tag with the corresponding `srfi_*` `Lib` value.

### 4. Handle heap allocation

If your procedure allocates heap objects (strings, pairs, vectors, etc.), you
need the GC instance. It is a threadlocal declared in `src/memory.zig` as
`memory.gc_instance` -- reach it through that module, since `primitives.zig`
does not re-export it:

```zig
fn myAllocProc(args: []const Value) PrimitiveError!Value {
    const gc = memory.gc_instance orelse return PrimitiveError.OutOfMemory;
    return gc.allocPair(args[0], args[1]) catch return PrimitiveError.OutOfMemory;
}
```

Read `.claude/rules/gc-safety.md` before writing anything that allocates more
than once: values held in Zig locals across a second allocation must be rooted,
and mutating a heap object's fields needs a write barrier.

### 5. Handle calling Scheme procedures

If your procedure needs to call back into Scheme code (like `map` or
`for-each`), use the VM instance -- likewise a threadlocal, declared in
`src/vm.zig` and reached as `vm_mod.vm_instance` under the import name every
primitives file already uses for that module:

```zig
fn myHigherOrder(args: []const Value) PrimitiveError!Value {
    const vm = vm_mod.vm_instance orelse return PrimitiveError.OutOfMemory;
    return vm.callWithArgs(args[0], args[1..]);
}
```

`callWithArgs(proc, args)` is the entry point that takes a Value slice.
(`vm_calls.callValue` is a different, register-based call used by the dispatch
loop -- it takes a register base and an argument count, not a slice.) Let the
callee's error propagate rather than rewriting it: `PrimitiveError` and
`VMError` are both aliases of `errors.KaappiError`, so a raise from inside the
Scheme procedure returns straight out of your primitive with its detail intact.

### 6. Test

Add unit tests in the appropriate `src/tests_*.zig` file (there are 44, one per
feature area -- pick the one matching your procedure's domain, and add a new
file only for a genuinely new area). `src/vm.zig` is not a test file: its single
`test` block only pulls sibling modules into the test build, and holds no
assertions.

Use the helpers in `src/testing_helpers.zig`, conventionally imported as `th`,
rather than standing a GC and VM up by hand:

```zig
const th = @import("testing_helpers.zig");

test "my-proc increments" {
    try th.expectEval("(my-proc 42)", 43);
}
```

`th.expectEvalTrue`, `th.expectEvalBool`, and `th.expectEvalVoid` cover the
other result shapes; `th.TestContext` is for tests needing several evals or
direct inspection of the result value. See `src/CLAUDE.md` for the full set.

Add a Scheme-level test under `tests/scheme/` too when the behavior is worth
checking end to end. A bug fix **must** come with a regression test that fails
without the fix.

---

## Adding a Compiler Form (Syntax)

When you need a new special form that the compiler must handle directly
(not a procedure and not a macro).

### 1. Add an IR node type

In `src/ir.zig`:

a. Add a variant to `NodeTag`:

```zig
pub const NodeTag = enum {
    // ... existing tags ...
    my_form,
};
```

b. Add the corresponding `Data` union variant. For simple forms with
sub-expressions that should be analyzed/optimized, define a custom data
struct and lower recursively. For complex forms, use `SexprArgs` to defer
to the existing compiler path:

```zig
// In Node.Data union:
my_form: SexprArgs,   // delegates body to existing compiler
```

c. Add lowering in `lowerFormWithMacros()` and `lowerForm()`:

```zig
if (std.mem.eql(u8, effective_name, "my-form"))
    return ir.makeSexprNode(.my_form, types.cdr(expr));
```

d. Handle the new tag in `freeNode`, `markTailPositions`, `identifyPrimitives`,
and `markConstants` (add to the appropriate switch arms -- usually the
no-op catch-all arm for `SexprArgs`-based forms).

### 2. Add compilation dispatch

In `src/compiler.zig`, add a case in `compileFromNode()`:

```zig
.my_form => try forms.compileMyForm(self, node.data.my_form.args, dst, tail),
```

### 3. Implement the compilation

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

### 4. Add the re-export

In `src/compiler_forms.zig`, add a re-export for the new function so the main
compiler can find it:

```zig
pub const compileMyForm = @import("compiler_advanced.zig").compileMyForm;
```

### 5. Test

Test both at the Zig level (compile and check emitted bytecode) and at the
Scheme level (run expressions using the new form). Add IR-specific tests
in `src/tests_ir.zig` -- at minimum a behavioral parity test.

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

Define the struct with an `Object` header, declared first by convention:

```zig
pub const MyType = struct {
    header: Object,
    data: i64,
    name: []const u8,
};
```

`src/types.zig` re-exports every heap type from a set of `types_*.zig`
domain files (kaappi#1731 — see its own File organization table in
`CLAUDE.md`) so existing `types.Foo` call sites work regardless of which
file defines `Foo`. Put the new struct in the matching domain file (e.g.
an FFI type goes in `types_ffi.zig`) if one fits, or directly in
`src/types.zig` if it's a core type or doesn't fit an existing domain. If
defined outside `types.zig`, add `pub const MyType = types_x.MyType;`
there, and reference the bare name `MyType` (not `types_x.MyType`) from
`Object.expectedTag()`'s switch.

Layout is otherwise free — Zig's auto layout may place `header` at a
nonzero byte offset, and that's fine. Heap Values always carry the address
of the `header` field: build them with `types.makePointer(&x.header)` (its
`*Object` parameter makes passing the struct pointer a compile error) and
recover the struct with `Object.as()`, never a direct cast (#1618).

### 3. Add the allocator

In `src/gc_alloc.zig`, add an `allocMyType` function, and alias it into the
`GC` struct next to the other allocator aliases in `src/memory.zig`
(`pub const allocMyType = gc_alloc.allocMyType;`) so call sites can use
`gc.allocMyType(...)`:

```zig
pub fn allocMyType(self: *GC, data: i64, name: []const u8) !*types.MyType {
    const obj = try self.allocObject(types.MyType, .my_type);
    obj.data = data;
    obj.name = name;
    return obj;
}
```

### 4. Handle in GC mark phase

In `src/gc_collect.zig`, add a case for tracing any contained Values (so
their referents are not collected) to **both** marking switches —
`markObjectContents` and `markValueInner`'s worklist switch — plus the
`referencesYoung` remembered-set switch:

```zig
.my_type => {
    const mt = obj.as(types.MyType);
    // Mark any Value fields:
    // markValue(gc, mt.some_value);
},
```

If your type contains no Value fields, add a no-op `{}` case — the switches
are exhaustive, so Zig forces one either way.

### 5. Handle in GC free phase

In `src/gc_sweep.zig`, add cases to `freeObject` (free any owned memory) and
`objectSize` (GC stats accounting):

```zig
.my_type => {
    const mt = obj.as(types.MyType);
    // Free any heap-allocated fields:
    // gc.allocator.free(mt.name);
    poisonAndDestroy(gc, types.MyType, mt);
},
```

Also add the new tag to `types.zig`'s `typeName` switch so type-error
messages can name it.

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
var first_val = try gc.allocPair(a, b);
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
   var func_val = types.makePointer(&func.header);
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
