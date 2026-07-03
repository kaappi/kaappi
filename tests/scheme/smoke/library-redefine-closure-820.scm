;; Regression test for #820: re-registering a library freed its lib_env
;; while closures compiled against it were still live (via Function.env),
;; so calling such a closure afterwards dereferenced freed memory.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "library-redefine-closure-820")

(define-library (foo bar)
  (import (scheme base))
  (export f)
  (begin
    (define secret 42)
    (define (f) secret)))
(import (foo bar))

(test-equal "closure works before redefinition" 42 (f))

;; Re-register the same library name — the old lib_env must survive
;; because f still resolves `secret` through it.
(define-library (foo bar)
  (import (scheme base))
  (export g)
  (begin (define (g) 99)))

(test-equal "stale closure still resolves old lib_env" 42 (f))

(import (foo bar))
(test-equal "replacement library works" 99 (g))

;; Churn allocations to force collections — values in the retired env
;; (like `secret` and f's stash below) must be traced by the GC.
(define-library (gc lib)
  (import (scheme base))
  (export get)
  (begin
    (define stash (list 1 2 3))
    (define (get) stash)))
(import (gc lib))
(define-library (gc lib)
  (import (scheme base))
  (export other)
  (begin (define (other) 0)))

(define junk
  (let churn ((n 100000) (acc '()))
    (if (= n 0) acc (churn (- n 1) (cons n acc)))))

(test-equal "retired env values survive GC" '(1 2 3) (get))

(let ((runner (test-runner-current)))
  (test-end "library-redefine-closure-820")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
