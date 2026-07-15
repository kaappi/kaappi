/* P1 access-semantics timing driver (kaappi#1473).
 *
 * One driver, linked once per (kernel, encoding) against that kernel's
 * separately-compiled object. The driver source is identical across all 18
 * binaries -- the only thing that differs between two compared binaries is the
 * kernel object, i.e. the experimental variable (plain vs unordered vs
 * monotonic element access). There is NO link-time optimization: the kernel
 * stays opaque to the driver, so the timed inner loop is exactly the code
 * `zig cc -w -O2` produced for the kernel .ll (verified out-of-band by the asm
 * evidence pass). This is the P5 "one binary / hold layout constant" rule
 * adapted to a codegen study whose whole point is that the codegen differs.
 *
 * Metric: nanoseconds per element visit. The driver auto-scales an inner
 * repetition count `reps` so each timed sample processes a fixed, large number
 * of element-visits (stable ns/element regardless of cache tier), then reports
 * one ns/element figure per iteration. The Python runner (run-access.py) owns
 * the invocation level of the Kalibera-Jones protocol.
 *
 * Dead-code defenses: kernel_run is external (no LTO) so the reps loop cannot
 * be collapsed; the output buffer is checksummed into a volatile sink after
 * timing so stores stay live; the input buffer is initialized and read by the
 * kernel.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Uniform wrapper exported by every kernel .ll. */
extern void kernel_run(void *out, void *in, long n);

static volatile uint64_t g_sink;

/* Target element-visits per timed sample. Large enough that even a fully
 * vectorized L1-resident kernel runs for milliseconds, so CLOCK_MONOTONIC
 * granularity is negligible; small enough that a memory-bound 64 MiB DRAM
 * kernel sample stays well under a second. */
#ifndef TARGET_VISITS
#define TARGET_VISITS 1.5e8
#endif

static double now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

int main(int argc, char **argv) {
  if (argc < 5) {
    fprintf(stderr, "usage: %s size_bytes elem_size warmup iters\n", argv[0]);
    return 2;
  }
  size_t size_bytes = strtoull(argv[1], NULL, 10);
  size_t elem_size = strtoull(argv[2], NULL, 10);
  int warmup = atoi(argv[3]);
  int iters = atoi(argv[4]);
  if (size_bytes == 0 || elem_size == 0) return 2;
  long n = (long)(size_bytes / elem_size);
  if (n < 1) n = 1;

  void *out = NULL, *in = NULL;
  if (posix_memalign(&out, 64, size_bytes) != 0) return 3;
  if (posix_memalign(&in, 64, size_bytes) != 0) return 3;
  memset(out, 0, size_bytes); /* fault output pages in */
  /* Deterministic non-trivial input (Knuth multiplicative hash of the index). */
  for (size_t i = 0; i < size_bytes; i++)
    ((unsigned char *)in)[i] = (unsigned char)((i * 2654435761u) >> 24);

  long reps = (long)(TARGET_VISITS / (double)n);
  if (reps < 1) reps = 1;

  for (int w = 0; w < warmup; w++)
    for (long r = 0; r < reps; r++) kernel_run(out, in, n);

  for (int it = 0; it < iters; it++) {
    double t0 = now_ns();
    for (long r = 0; r < reps; r++) kernel_run(out, in, n);
    double t1 = now_ns();
    double ns_per_elem = (t1 - t0) / ((double)reps * (double)n);
    /* ITER <size_bytes> <iter> <ns_per_elem> <reps> */
    printf("ITER %zu %d %.6f %ld\n", size_bytes, it, ns_per_elem, reps);
  }

  uint64_t s = 0;
  for (size_t i = 0; i < size_bytes; i++) s += ((unsigned char *)out)[i];
  g_sink = s;
  return 0;
}
