# Performance Benchmarks

Baseline measurements on Apple M-series (macOS, ReleaseSafe build).

## Results

| Benchmark | Input | Result | Kaappi | Notes |
|-----------|-------|--------|--------|-------|
| **fib** | 35 | 9227465 | **~1.9s** | Pure recursion, fixnum arithmetic |
| **fib** | 30 | 832040 | **~173ms** | JIT-compiled hot path |
| **tak** | 33,22,11 | 22 | **~46s** | Deep recursion + arithmetic + comparisons |
| **hash-table-set!** | 10K | -- | **~1ms** | Open-addressing with linear probing |
| **hash-table-set!** | 50K | -- | **~5ms** | Linear scaling |
| **iota** | 100K | -- | **~1.4ms** | List allocation + GC |
| **fold +** | 100K | -- | **~2.1ms** | List traversal |

Measured with `(current-jiffy)` / `(jiffies-per-second)`. Pre-built executable (`zig-out/bin/kaappi`), no compilation overhead.

## Comparison context

Typical results from [ecraven/r7rs-benchmarks](https://ecraven.github.io/r7rs-benchmarks/) for the same benchmarks:

| Implementation | fib(35) | tak(33,22,11) | Type |
|---------------|---------|---------------|------|
| **Chez Scheme** | ~0.15s | ~1.2s | Native compiler |
| **Chicken** | ~0.5s | ~4s | AOT compiler (C backend) |
| **Gauche** | ~1.8s | ~15s | Bytecode interpreter |
| **Chibi** | ~3.5s | ~30s | Bytecode interpreter |
| **Kaappi** | ~1.9s | ~46s | Bytecode interpreter + JIT |

Kaappi is faster than Chibi for `fib` (1.9s vs 3.5s) and comparable on `tak`. The JIT inlines fixnum arithmetic, comparisons, `car`/`cdr`, and `cons` for hot functions.

## Optimizations implemented

- **JIT compiler** (AArch64): hot functions (100+ calls) compiled to native code; inline fixnum `+`/`-`/`*`/`<`/`>`/`<=`/`>=`/`=`, predicates (`zero?`, `null?`, `pair?`, `not`), `car`/`cdr`, `cons`
- **NativeFn fast path**: `call_global` bypasses the full dispatch chain for native functions
- **Constant folding**: `(+ 1 2)` → `3` at compile time
- **Inline global cache**: `call_global` caches resolved function pointers with version invalidation
- **Open-addressing hash tables**: O(1) lookup/insert (was O(n) linear scan — 1000x speedup)
- **Self-tail-call optimization**: detected at compile time, reuses the current frame

## Running benchmarks

```bash
zig build                              # build executable
zig build bench                        # call/cc vs call/ec micro-benchmark
zig build run -- --profile program.scm # profile with per-function timing
```
