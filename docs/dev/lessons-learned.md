# Lessons Learned

Hard-won insights from building Kaappi. Each section describes a class of bug, how it manifested, and the fix — so future contributors (and future-us) don't rediscover them.

---

## 1. Global namespace pollution from `letrec` and named let

**Symptom:** Built-in procedures like `even?`, `odd?`, `map` stop working after running unrelated code. The r7rs-tests suite hung in section 6.2 because `odd?` was no longer the built-in.

**Root cause:** `letrec` and named `let` compiled to `set_global` with the user-visible variable name. A test like `(letrec ((even? ...) (odd? ...)) ...)` permanently overwrote the built-in `even?` and `odd?` globals with test-local closures.

**Fix:** Generate unique gensym'd names (`__nlet_N_varname`) for each `letrec`/named-let binding. The body references are renamed in the AST before compilation. The original globals are never touched.

**Files:** `src/compiler_bindings.zig` — `compileLetrec`, `compileNamedLet`

**Lesson:** Any compiler feature that uses `set_global` for lexically-scoped variables must use unique names to avoid polluting the global namespace.

---

## 2. Copy-based upvalues prevent self-reference

**Symptom:** Named let loop closures couldn't reference themselves via upvalues because the closure doesn't exist at capture time.

**Root cause:** Upvalues are copied by value at closure creation time (via the `closure` opcode). A self-referential closure would capture `VOID` (the pre-initialization value) instead of itself.

**Workaround:** Named let stores the loop closure as a global variable (with a gensym'd name) and the loop body uses `get_global` to find itself. This works because `get_global` resolves at call time, not capture time.

**Proper fix (not yet implemented):** Post-creation patching — create the closure with a void upvalue, then emit `set_upvalue` to patch it with the closure's own value. The GC already handles cycles correctly.

**Files:** `src/compiler_bindings.zig`, `src/vm.zig` (closure opcode)

---

## 3. Global variable cache invalidation

**Symptom:** `(set! x 20)` in one function, but another function still sees `x = 10` from a cached value.

**Root cause:** The `global_cache` on Function objects cached resolved global values. Each Function had a per-cache `cache_version` that was compared to the VM's `global_version`. But caching ANY global set `cache_version = global_version`, making ALL stale entries in the cache look valid.

**Fix:** When `cache_version != global_version`, clear the ENTIRE cache before repopulating. This ensures stale entries from previous calls are never returned.

**Files:** `src/vm.zig` — `get_global` handler, `set_global` handler

**Lesson:** Per-entry versioning or full invalidation — no middle ground. A single version stamp for the whole cache creates false validity for stale entries.

---

## 4. Multiple file I/O failure (closure upvalues and GC)

**Symptom:** Opening a second file after reading and closing a first file caused `read-line` type errors.

**Root cause:** Two interacting issues:
1. Named let closures captured ports via upvalues. The first call's closure was stored as a global. On the second call, a new closure was created but the global cache returned the OLD closure (with the closed port's upvalue).
2. The global cache invalidation bug (#3 above) prevented the new closure from being seen.

**Fix:** The global cache clear-on-version-mismatch fix (#3) resolved this. When `set_global` stores the new closure, `global_version` increments, and subsequent `get_global` calls see the cache is stale and do fresh lookups.

---

## 5. `list?` infinite loop on circular lists

**Symptom:** `(list? x)` hung when `x` was a circular list (e.g., after `(set-cdr! x x)`).

**Root cause:** `list?` used a simple linear traversal without cycle detection.

**Fix:** Replaced with Floyd's tortoise-and-hare algorithm. Also fixed `length` for the same issue.

**Files:** `src/primitives.zig` — `listP`, `length`

---

## 6. Recursive macro expansion with multiple ellipsis variables

**Symptom:** `(my-macro ((x 10)) body)` dropped the `body` argument in recursive expansions. Named `let` with body expressions returned `#t` instead of the body result.

**Root cause:** `instantiateEllipsis` in the expander used the repeat count from the FIRST ellipsis binding found, regardless of which variable was referenced in the template element. When `rest ...` had 0 matches and `body ...` had 1 match, the expander used 0 for both.

**Fix:** Scan the template element to find which ellipsis variable it references, and use THAT variable's repeat count.

**Files:** `src/expander.zig` — `instantiateEllipsis`, `templateReferencesVar`

---

## 7. Named let register placement

**Symptom:** `(let ((len 10)) (let loop ((i 0)) i))` gave `i = 10` instead of `i = 0`. Outer let variables leaked into named let parameters.

**Root cause:** `compileNamedLet` placed initial call arguments at `allocReg()` positions, which weren't contiguous with the closure register when outer let bindings occupied intermediate slots. The VM's call convention expected arguments at `base+1, base+2, ...` but they were at non-contiguous positions.

**Fix:** Allocate a fresh contiguous register block for the call, starting at `call_base`. Move the closure to `call_base` and compile arguments to `call_base + 1 + j`.

**Files:** `src/compiler_bindings.zig` — `compileNamedLet`

---

## 8. GC root marking gaps

**Symptom:** Various use-after-free crashes during library loading and multi-file I/O.

**Root causes found:**
- `vm_instance` not set in `main()`, so `markVMRoots` did nothing during early GC cycles
- Library export values not rooted — heap objects in the library registry weren't traced during GC
- Flonum cache entries not rooted — cached flonums could be freed between GC cycles
- Exception handler closures not rooted between `popHandler` and `callHandler`

**Fixes:**
- Set `vm_instance` early in `main()` before any allocations
- Mark library export values in `markVMRoots`
- Mark flonum cache entries in `markRoots`
- Root exception handler before calling it after `popHandler`

**Lesson:** Every heap-allocated Value that's reachable by any code path must be traceable from a GC root. Common gaps: HashMaps (library exports, globals), caches (flonum cache, global cache), temporary variables between native function calls.

---

## 9. `.sbc` bytecode cache and macros

**Symptom:** Macro-exporting libraries worked on first load but failed on cache hit (second run). Macros defined with `define-syntax` in library `begin` blocks weren't available after loading from cache.

**Root cause:** The `.sbc` cache stores compiled bytecode functions. `define-syntax` creates a transformer during COMPILATION (not execution). The cached bytecode's `load_void` instruction doesn't recreate the transformer. So macro exports are missing on cache hit.

**Fix:** When building the library from cache, if any export can't be resolved from `vm.globals` or `vm.macros`, fall through to source compilation instead of using the incomplete cache.

**Files:** `src/vm_library.zig` — `tryLoadLibraryFromFile`

---

## 10. GC reachability: root source data during read and compile

**Symptom:** String literals displayed as `0xAA` (DebugAllocator poison) after heavy file I/O. Only happened under specific allocation pressure patterns.

**Root cause:** The reader and compiler held in-flight source data (S-expression trees) in unrooted local variables across allocations that trigger `maybeCollect()`. `allocPair` runs `maybeCollect()` BEFORE allocating, so any heap Value passed as an argument is vulnerable if not rooted. Two gaps:
- **Reader:** `readList`/`readListTail` passed the tail to `allocPair(car, rest)` with `rest` unrooted
- **Compiler:** `compile(expr)` walked the expression tree without rooting it; macro expansion created fresh unrooted forms

**Fix:** Root all in-flight data across allocation boundaries using `gc.pushRoot`/`gc.popRoot` and `gc.extra_roots`. The initial workaround (skipping immutable strings in sweep) was removed once the real root cause was fixed.

**Lesson:** Every Value held across ANY function call that might allocate must be rooted. `allocPair`, `allocString`, `allocSymbol`, `allocClosure`, `allocVector` all call `maybeCollect()` before allocating. The GC can run at any of these points.

**Files:** `src/reader_datum.zig`, `src/compiler.zig`, `src/memory.zig`

See `docs/dev/gc-reachability-bug.md` for the full investigation.

---

## 11. Performance: what worked and what didn't

**What worked:**
- **Global variable cache** (+10%): Cache resolved procedure values in Function objects. Avoids hash table lookups on repeated `get_global` instructions.
- **Flonum cache** (+10%): 16-entry cache for frequently-used float values. Reduces GC pressure from temporary flonum allocations.
- **Closure-first type dispatch** (+5%): Reorder `callValue` to check closures before native fns, FFI, parameters, continuations. Closures are the common case in Scheme.
- **`call_global` superinstruction** (+10%): Fuse `get_global` + `call` into one opcode for non-tail calls. Saves one bytecode dispatch per call.

**What didn't work:**
- **NaN-boxing**: Would reduce fixnum range from i63 to i51, breaking R7RS integer semantics. Only ~5% gain for high complexity.
- **`tail_call_global` superinstruction**: Caused 2x regression due to frame reuse semantics conflicting with the superinstruction's register layout.
- **Per-entry cache versioning**: Considered for the global cache, but full-cache clearing on version mismatch is simpler and just as effective.

**Total improvement:** fib(35) from 2.69s to ~2.0s (26% faster).
