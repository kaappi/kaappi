;; Regression tests for expander fixes
;; #309: flonum datum patterns in syntax-rules
;; #308: ellipsis escape hygiene

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "expander-fixes")

;; ---- #309: Flonum datum patterns ----

(define-syntax check-pi
  (syntax-rules ()
    ((check-pi 3.14) 'pi)
    ((check-pi _) 'other)))

(test-equal "flonum datum pattern matches 3.14" 'pi (check-pi 3.14))
(test-equal "flonum datum pattern rejects 2.71" 'other (check-pi 2.71))
(test-equal "flonum datum pattern rejects the fixnum 42" 'other (check-pi 42))

;; Integer datum patterns still work
(define-syntax check-zero
  (syntax-rules ()
    ((check-zero 0) 'zero)
    ((check-zero _) 'nonzero)))

(test-equal "integer datum pattern matches 0" 'zero (check-zero 0))
(test-equal "integer datum pattern rejects 1" 'nonzero (check-zero 1))

;; ---- #308: Ellipsis escape hygiene ----

;; The template-introduced variable 't' inside (... ...) should be
;; renamed for hygiene and not conflict with outer 't'.
(define-syntax my-or
  (syntax-rules ()
    ((my-or a b)
     (... (let ((t a)) (if t t b))))))

(test-equal "use-site t is not captured by the template's own t"
            42 (let ((t 42)) (my-or #f t)))

(test-equal "my-or returns its first true argument" 1 (my-or 1 2))
(test-equal "my-or falls through a false first argument" 99 (my-or #f 99))

(let ((runner (test-runner-current)))
  (test-end "expander-fixes")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
