;; Regression test for emitSelfCallSequence frame-base off-by-one bug.
;;
;; Bug: When the native self-call optimization is enabled, emitSelfCallSequence
;; computes the callee's frame base incorrectly (off by one register slot).
;; The callee's FRAME_PTR points one slot before the actual frame base,
;; causing register reads/writes to hit wrong slots.  The return value ends
;; up in the wrong register, producing garbage results in the caller.
;;
;; The optimization is triggered when ALL of the following hold:
;;   1. The function has a name (top-level define)
;;   2. The function is not variadic
;;   3. The call uses call_global (non-tail position) to the same name
;;   4. The arity matches
;;
;; This test defines a minimal non-tail self-recursive function and runs
;; it enough times to trigger native compilation (threshold = 100 calls).
;; If the self-call frame base is wrong, the return value will be
;; corrupted and the final result will differ from the expected answer.

(import (scheme base) (scheme write) (scheme process-context))

;; ---------- Test infrastructure (lightweight, no SRFI 64 dependency) ----------

(define pass-count 0)
(define fail-count 0)

(define (check name expected actual)
  (if (equal? expected actual)
      (begin
        (set! pass-count (+ pass-count 1))
        (display "  PASS  ") (display name) (newline))
      (begin
        (set! fail-count (+ fail-count 1))
        (display "  FAIL  ") (display name)
        (display "  expected=") (display expected)
        (display "  got=") (display actual) (newline))))

;; ---------- Test 1: non-tail self-recursion (count-down) ----------
;;
;; Bytecode shape:
;;   (count-down (- n 1))   =>  call_global with sym "count-down"
;;
;; Because (+ 1 ...) wraps the recursive call, count-down is in
;; non-tail position and compiles to call_global (not tail_call_global).
;; isSelfCall matches: func.name == "count-down" and the constant
;; symbol at sym_idx is also "count-down".
;;
;; If FRAME_PTR is off by one, the callee writes its result to
;; registers[new_base + 0] but the caller reads from a different slot.
;; The (+ 1 result) then adds 1 to garbage, producing a wrong answer.

(define (count-down n)
  (if (= n 0)
      0
      (+ 1 (count-down (- n 1)))))

;; Must call >100 times per function to cross native compilation threshold.
;; count-down(10) makes 10 recursive non-tail calls per invocation.
;; 20 outer iterations * 10 calls = 200 total calls to count-down,
;; enough to natively compile it and then exercise the native code path.

(define (repeat f n expected)
  (if (= n 0)
      (f expected)         ; final call -- return its result for checking
      (begin (f expected)  ; warm up call_count
             (repeat f (- n 1) expected))))

(display "=== Native self-call regression ===") (newline)

(check "count-down 0"  0  (count-down 0))
(check "count-down 1"  1  (count-down 1))
(check "count-down 10" 10 (count-down 10))

;; Warm up to trigger native compilation, then verify post-compilation correctness.
(check "count-down 10 post-native" 10 (repeat count-down 20 10))

;; ---------- Test 2: multi-arg self-recursion (sum-range) ----------
;;
;; Two-argument version: ensures frame base + base_reg + 1 is correctly
;; computed even when base_reg > 0 (args occupy more register slots).

(define (sum-range lo hi)
  (if (> lo hi)
      0
      (+ lo (sum-range (+ lo 1) hi))))

(check "sum-range 1..10" 55 (sum-range 1 10))
(check "sum-range 1..10 post-native" 55 (repeat (lambda (x) (sum-range 1 x)) 20 10))

;; ---------- Test 3: nested self-call (double recursion) ----------
;;
;; Two non-tail self-calls in the same expression.  Both go through
;; call_global and both exercise emitSelfCallSequence.  If the second
;; call's frame base is wrong, the first call's return value (saved in
;; a register) gets clobbered.

(define (fib-like n)
  (if (< n 2)
      n
      (+ (fib-like (- n 1)) (fib-like (- n 2)))))

(check "fib-like 10" 55 (fib-like 10))
(check "fib-like 10 post-native" 55 (repeat fib-like 25 10))

;; ---------- Summary ----------

(display "---") (newline)
(display pass-count) (display " pass, ")
(display fail-count) (display " fail") (newline)

(when (> fail-count 0)
  (exit 1))
