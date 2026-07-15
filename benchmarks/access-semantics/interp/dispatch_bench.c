/* Dispatch-model microbench for the P1 interpreter-tier control (memo §9.4).
 *
 * Every Scheme -ref/-set! is a call through a NativeFn pointer: the VM pays
 * dispatch (arg marshaling, arity + type checks, the indirect branch) and then
 * executes one element access. This bench isolates the question "once you pay
 * dispatch, is the plain-vs-unordered access annotation observable?" by calling
 * the prim_ref/prim_set primitive through a *volatile* function pointer -- an
 * opaque indirect call the optimizer cannot inline or vectorize, one call per
 * element -- and timing ns/call. The primitive body is a separate object
 * (prim_plain.o / prim_unordered.o, no LTO), so plain and unordered differ only
 * in the single element load/store.
 *
 * This is the CONSERVATIVE floor: a bare indirect call is far cheaper than real
 * VM dispatch, so if Delta is ~0 here it is certainly ~0 against the tens of ns
 * a real NativeFn call costs (measured separately by kaappi_prim.scm). Reported
 * ns/call is directly comparable to the tight-loop kernel's ns/element to show
 * dispatch dwarfs the access.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

extern int64_t prim_ref(void *base, long i, long len);
extern void prim_set(void *base, long i, long len, long v);

/* volatile => the indirect call target is reloaded each use: a genuine indirect
 * branch, and the callee body stays opaque (it lives in another object). */
static int64_t (*volatile vref)(void *, long, long) = prim_ref;
static void (*volatile vset)(void *, long, long, long) = prim_set;
static volatile int64_t g_sink;

static double now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (double)ts.tv_sec * 1e9 + (double)ts.tv_nsec;
}

int main(int argc, char **argv) {
  if (argc < 4) {
    fprintf(stderr, "usage: %s n warmup iters\n", argv[0]);
    return 2;
  }
  long n = strtol(argv[1], NULL, 10);
  int warmup = atoi(argv[2]);
  int iters = atoi(argv[3]);
  if (n < 1) n = 1;

  unsigned char *buf = malloc((size_t)n);
  if (!buf) return 3;
  memset(buf, 1, (size_t)n);

  /* choose reps so each timed sample makes a fixed, large number of calls */
  long reps = (long)(5e7 / (double)n);
  if (reps < 1) reps = 1;

  for (int w = 0; w < warmup; w++) {
    int64_t a = 0;
    for (long r = 0; r < reps; r++)
      for (long i = 0; i < n; i++) a += vref(buf, i, n);
    g_sink += a;
  }

  for (int it = 0; it < iters; it++) {
    /* -ref */
    double t0 = now_ns();
    int64_t a = 0;
    for (long r = 0; r < reps; r++)
      for (long i = 0; i < n; i++) a += vref(buf, i, n);
    double t1 = now_ns();
    g_sink += a;
    double ref_ns = (t1 - t0) / ((double)reps * (double)n);

    /* -set! */
    double t2 = now_ns();
    for (long r = 0; r < reps; r++)
      for (long i = 0; i < n; i++) vset(buf, i, n, i);
    double t3 = now_ns();
    double set_ns = (t3 - t2) / ((double)reps * (double)n);

    /* ITER <n> <iter> <ref_ns_per_call> <set_ns_per_call> */
    printf("ITER %ld %d %.6f %.6f\n", n, it, ref_ns, set_ns);
  }
  int64_t s = 0;
  for (long i = 0; i < n; i++) s += buf[i];
  g_sink += s;
  return 0;
}
