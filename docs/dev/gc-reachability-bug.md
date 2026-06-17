# GC Reachability Bug: Immutable String Literals Freed During Execution

## Status

**Workaround applied.** The sweep phase now skips immutable strings. The deeper root cause — why the mark phase fails to reach string literals in Function constant pools — is not fully resolved.

## Symptoms

String literals display as `0xAA 0xAA` (DebugAllocator's freed-memory poison) instead of their actual content. Only occurs under heavy allocation pressure (35+ file reads in the `scripts/large-files.scm` tool). 100% reproducible and deterministic.

## Reproduction

```bash
zig build run -- scripts/large-files.scm
```

Output before fix:
```
   1243██src/vm.zig    ##############################
```

The `██` characters are bytes `0xAA 0xAA` — the string `"  "` (two spaces) was freed by GC and its data buffer overwritten by DebugAllocator's poison pattern.

## Evidence collected

### 1. The corruption is in string DATA, not the string object

The SchemeString object itself survives (otherwise `display` would crash on a bad tag). But `str.data` points to freed memory. When `freeObject` runs for a string, it does:

```zig
self.allocator.free(str.data);   // fills with 0xAA
self.allocator.destroy(str);      // frees the object
```

The data is freed first, so a dangling SchemeString pointing to freed data would read `0xAA` bytes.

### 2. Exactly 2 immutable strings are freed

Instrumentation in the sweep phase confirmed that exactly 2 strings with `immutable = true`, length 2, content `"  "` were freed. These match the two `(display "  ")` calls in the script at lines 83 and 85.

### 3. The strings are constant pool entries

String literals from source code are:
1. Read by the reader → `gc.allocString(data)`
2. Marked as immutable: `str.immutable = true`
3. Returned as datum Values
4. Compiled: stored in Function's constant pool via `addConstant`
5. At runtime: loaded via `load_const` instruction

### 4. The reachability chain (should work but doesn't)

```
Root: markVMRoots()
  ↓
  vm.frames[i].closure → Closure object (marked)
  ↓
  closure.func → Function object (marked)
  ↓
  function.constants.items[j] → string literal (SHOULD be marked)
```

Each step in this chain has correct marking code:
- `markVMRoots` marks all frame closures (line 51, vm.zig)
- Closure marking traces `cls.func` (line 698, memory.zig)
- Function marking iterates ALL constants (line 703, memory.zig)

### 5. The bug does NOT reproduce in structurally similar test files

A standalone test file with the exact same logic (read 35 files, sort, display with pad-left/pad-right) does NOT corrupt strings. The corruption only occurs in the actual `scripts/large-files.scm` file.

## Hypotheses

### H1: The Function is freed during execution (UNLIKELY)

If the Function object itself is freed, all its constants would be freed. This would cause crashes in the bytecode dispatch loop (reading freed code bytes), not just string corruption. Since only strings are corrupted, the Function is likely alive.

### H2: The constant pool ArrayList backing array is reallocated (UNLIKELY)

`Function.constants` is an `ArrayList(Value)`. If the ArrayList were resized during execution, the old backing array would be freed and the new one wouldn't be in the GC's object list (it's not a GC-tracked object — it's a raw allocator array). But the constant pool is only modified during COMPILATION, not during EXECUTION. After compilation, `constants.items` is stable.

### H3: The string literal's GC object is reused (POSSIBLE)

The GC tracks objects via an intrusive linked list (`Object.next`). When a string is freed in `sweep`, it's unlinked from the list and destroyed. If the freed memory is reused for a NEW string with the same data pointer... no, DebugAllocator wouldn't reuse memory that fast.

### H4: The frame's `locals_count` is too small, causing register under-marking (MOST LIKELY)

`markVMRoots` marks each frame's register window:

```zig
const window: usize = if (f.closure) |cls| blk: {
    const lc = cls.func.locals_count;
    break :blk if (lc == 0) 256 else @as(usize, lc);
} else 256;
const end: usize = @min(@as(usize, f.base) + window, MAX_REGISTERS);
```

`locals_count` is the compiler's recorded high-water mark of registers used. If a function uses register N for a `load_const` but `locals_count < N`, the register won't be marked. The Value in that register (the string) becomes unreachable from the frame's perspective.

However, the string is ALSO in the Function's constant pool, which should be marked independently. Unless the Function is reached via a different path (globals, not frame closure) and the global's Function pointer doesn't match.

### H5: The `call_global` superinstruction doesn't set `frame.closure` correctly (POSSIBLE)

The `call_global` opcode stores the callee at `registers[base]` and calls `callValue`. For closures, `callValue` → `callClosure` creates a new frame with `frame.closure = closure`. But `call_global` bypasses the normal `get_global + call` path. If the callee resolved from the global cache is a STALE closure (from a previous compilation), the frame's Function has different constants.

But we fixed the global cache to clear on version mismatch. And the `show` function is defined once and called multiple times with the same closure.

### H6: The `string-append` in `pad-left`/`pad-right` triggers GC that frees string constants (POSSIBLE)

`pad-left` calls `(string-append (make-string N #\space) s)`. The `string-append` native function:
1. Computes total length
2. Allocates temporary buffer via `gc.allocator.alloc` (raw, no GC)
3. Copies data from arguments
4. Calls `gc.allocString(result)` which triggers `maybeCollect()`
5. GC runs, marks reachable objects, sweeps unreachable ones

At step 4, the arguments are in VM registers (from the `call` instruction). The caller's frame should mark them. But if the caller's `locals_count` doesn't cover the argument registers...

This is essentially H4 again. The issue is that `locals_count` might not cover all live registers.

## How `locals_count` is set

In `allocReg()` (compiler.zig):

```zig
pub fn allocReg(self: *Compiler) CompileError!u8 {
    ...
    if (self.next_register > self.func.locals_count) {
        self.func.locals_count = self.next_register;
    }
    return reg;
}
```

`locals_count` tracks the peak register usage during compilation. It should cover all registers used by the function. But if a register is used for a temporary value (like a call argument) and then freed, `locals_count` still records the peak.

The issue might be: `compileCallGlobal` uses `allocReg` for the base register but doesn't allocate a register for the CALLEE (the `call_global` handler fills it at runtime). So `locals_count` might be 1 less than expected, leaving the callee's register unmarked.

But the callee register holds the closure, not the string. The string is in a different register (the argument).

## Recommended further investigation

1. **Add assertion in markVMRoots**: verify that `frame.closure.func.locals_count` covers `frame.base + <highest used register>` for each frame. Log any discrepancy.

2. **Track string constant pool membership**: add a `in_constant_pool: bool` flag to SchemeString. Set it when `addConstant` adds a string. In sweep, assert that `in_constant_pool` strings are always marked.

3. **Compare frame closures**: log the closure and function pointers for each frame during GC. Verify the function's constants include the string literal.

4. **Test with GC on every allocation**: set `GC_THRESHOLD = 1` to trigger GC maximally. This amplifies any timing-dependent reachability bugs.

5. **Binary search for the trigger**: start with 5 files (works) and increase until corruption appears. Find the exact allocation count that triggers the bug.

## Current workaround

The sweep phase skips immutable strings:

```zig
if (o.tag == .string) {
    const str = o.as(SchemeString);
    if (str.immutable) {
        o.marked = false;
        prev = o;
        obj = o.next;
        continue;
    }
}
```

This is safe because:
- Immutable strings are only created by the reader for string literals
- They're never mutated
- They're typically small (< 100 bytes)
- The memory leak is negligible
- The correctness benefit is critical
