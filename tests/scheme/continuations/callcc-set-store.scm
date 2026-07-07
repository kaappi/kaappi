;; Regression test for #1168: set! of non-captured locals must persist
;; across continuation re-entry (R7RS §3.4 store semantics).
;; Tests 9-12: regression for #1250 (macro-introduced set!).
(import (scheme base) (scheme process-context) (srfi 64))

(define-syntax inc!
  (syntax-rules ()
    ((_ v) (set! v (+ v 1)))))

(define-syntax counter-loop
  (syntax-rules ()
    ((_ limit)
     (let ((n 0) (k* #f))
       (call/cc (lambda (k) (set! k* k)))
       (set! n (+ n 1))
       (if (< n limit) (k* #f))
       n))))

(test-begin "callcc-set-store")

;; 1. let binding — the original reproduction from #1168
(test-equal "let: set! persists across call/cc re-entry"
  3
  (let ((n 0) (k* #f))
    (call/cc (lambda (k) (set! k* k)))
    (set! n (+ n 1))
    (if (< n 3) (k* #f))
    n))

;; 2. let* binding
(test-equal "let*: set! persists across call/cc re-entry"
  3
  (let* ((n 0) (k* #f))
    (call/cc (lambda (k) (set! k* k)))
    (set! n (+ n 1))
    (if (< n 3) (k* #f))
    n))

;; 3. lambda parameter
(test-equal "lambda param: set! persists across call/cc re-entry"
  3
  ((lambda (n)
     (let ((k* #f))
       (call/cc (lambda (k) (set! k* k)))
       (set! n (+ n 1))
       (if (< n 3) (k* #f))
       n))
   0))

;; 4. Multiple mutated locals
(test-equal "multiple set! locals persist"
  '(3 13)
  (let ((a 0) (b 10) (k* #f))
    (call/cc (lambda (k) (set! k* k)))
    (set! a (+ a 1))
    (set! b (+ b 1))
    (if (< a 3) (k* #f))
    (list a b)))

;; 5. Mixed: one mutated, one not — non-mutated local should be unaffected
(test-equal "non-mutated local unchanged by continuation"
  '(3 42)
  (let ((n 0) (x 42) (k* #f))
    (call/cc (lambda (k) (set! k* k)))
    (set! n (+ n 1))
    (if (< n 3) (k* #f))
    (list n x)))

;; 6. Nested let with set! in inner scope
(test-equal "nested let: inner set! persists"
  5
  (let ((k* #f))
    (let ((n 0))
      (call/cc (lambda (k) (set! k* k)))
      (set! n (+ n 1))
      (if (< n 5) (k* #f))
      n)))

;; 7. Heap-cell workaround (should still work — regression guard)
(test-equal "heap-cell counter still works"
  3
  (let ((n (vector 0)) (k* #f))
    (call/cc (lambda (k) (set! k* k)))
    (vector-set! n 0 (+ (vector-ref n 0) 1))
    (if (< (vector-ref n 0) 3) (k* #f))
    (vector-ref n 0)))

;; 8. Closure-captured workaround (should still work — regression guard)
(test-equal "closure-captured counter still works"
  3
  (let ((n 0) (k* #f))
    (define (read-n) n)
    (call/cc (lambda (k) (set! k* k)))
    (set! n (+ n 1))
    (if (< (read-n) 3) (k* #f))
    n))

;; 9. Macro-introduced set! (inc! wrapper) — #1250
(test-equal "macro-introduced set! persists" 3
  (let ((n 0) (k* #f))
    (call/cc (lambda (k) (set! k* k)))
    (inc! n)
    (if (< n 3) (k* #f))
    n))

;; 10. Macro that expands to entire let+set! — #1250
(test-equal "macro-expanded let+set! persists" 3
  (counter-loop 3))

;; 11. let* with macro-introduced set! — #1250
(test-equal "let*: macro-introduced set! persists" 3
  (let* ((n 0) (k* #f))
    (call/cc (lambda (k) (set! k* k)))
    (inc! n)
    (if (< n 3) (k* #f))
    n))

;; 12. Lambda param with macro-introduced set! — #1250
(test-equal "lambda param: macro-introduced set! persists" 3
  ((lambda (n)
     (let ((k* #f))
       (call/cc (lambda (k) (set! k* k)))
       (inc! n)
       (if (< n 3) (k* #f))
       n))
   0))

(let ((runner (test-runner-current)))
  (test-end "callcc-set-store")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
