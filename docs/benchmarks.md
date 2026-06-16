# Performance Benchmarks

Baseline measurements on Apple M-series (macOS, ReleaseSafe build).

## Results

| Benchmark | Input | Result | Kaappi | Notes |
|-----------|-------|--------|--------|-------|
| **fib** | 35 | 9227465 | **2.69s** | Pure recursion, fixnum arithmetic |
| **tak** | 33,22,11 | 22 | **60.4s** | Deep recursion + arithmetic + comparisons |

Measured with `(current-jiffy)` / `(jiffies-per-second)`. Pre-built executable (`zig-out/bin/kaappi`), no compilation overhead.

## Comparison context

Typical results from [ecraven/r7rs-benchmarks](https://ecraven.github.io/r7rs-benchmarks/) for the same benchmarks:

| Implementation | fib(35) | tak(33,22,11) | Type |
|---------------|---------|---------------|------|
| **Chez Scheme** | ~0.15s | ~1.2s | Native compiler |
| **Chicken** | ~0.5s | ~4s | AOT compiler (C backend) |
| **Gauche** | ~1.8s | ~15s | Bytecode interpreter |
| **Chibi** | ~3.5s | ~30s | Bytecode interpreter |
| **Kaappi** | ~2.7s | ~60s | Bytecode interpreter |

Kaappi is in the same ballpark as Chibi (a well-regarded bytecode interpreter) for `fib`. The `tak` benchmark is slower, likely due to the overhead of our register-based VM's frame setup on every call.

## Where time is spent

Based on the profile:
- **fib**: Dominated by function call overhead (push frame, set registers, return). Each `fib(35)` call does ~29M recursive calls.
- **tak**: ~4 billion recursive calls. Call/return overhead dominates.

## Optimization opportunities

Ranked by expected impact:

### 1. Reduce call overhead (highest impact)
The register-based VM creates a CallFrame for every Scheme function call. For `tak` which does billions of calls, this is the bottleneck. Options:
- **Inline small functions** at the bytecode level
- **Direct call optimization** when the callee is known at compile time
- **Register window slide** instead of frame push for simple calls

### 2. Global variable lookup caching
Every `get_global` does a hash table lookup. For tight loops that call named functions, this adds overhead.
- **Inline cache**: store the hash table entry pointer in the bytecode instruction stream
- Expected: ~10-20% improvement on call-heavy benchmarks

### 3. GC tuning
Current GC threshold is 1024 allocations. For benchmarks that allocate heavily:
- Increase threshold for better throughput (trade latency for throughput)
- Current: mark-and-sweep is simple but pauses on every collection

### 4. Superinstructions
Common patterns like `get_global + call` could be fused into a single opcode:
- Reduces bytecode dispatch overhead
- Each dispatch costs a branch prediction miss

### 5. NaN-boxing (float-heavy workloads)
Currently flonums are heap-allocated. Packing f64 directly into the u64 value would eliminate GC pressure for floating-point benchmarks.

## Running benchmarks

```bash
# Build first (one-time)
zig build

# Run a benchmark
./zig-out/bin/kaappi benchmarks/fib.scm < benchmarks/fib.input
```
