;; Regression test for #432: cond-expand with empty matching clause
;; in define-library caused an infinite loop.

(import (scheme base) (scheme write))

;; Inline library with empty cond-expand clause.
;; The r7rs clause matches but has an empty body — previously hung.
(define-library (cond-expand-empty-test)
  (export greet)
  (cond-expand
    (r7rs)
    (else (begin)))
  (begin
    (define (greet) "hello")))

(import (cond-expand-empty-test))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ")
        (display name)
        (display " got=")
        (write got)
        (display " expected=")
        (write expected)
        (newline))))

(check "cond-expand-empty-clause" (greet) "hello")

;; Also test: cond-expand where else clause is empty
(define-library (cond-expand-else-empty-test)
  (export farewell)
  (cond-expand
    (nonexistent-feature (begin (define unused 1)))
    (else))
  (begin
    (define (farewell) "bye")))

(import (cond-expand-else-empty-test))
(check "cond-expand-else-empty" (farewell) "bye")

;; Test: cond-expand with multiple empty clauses before match
(define-library (cond-expand-multi-empty-test)
  (export value)
  (cond-expand
    (no-such-feature)
    (r7rs))
  (begin
    (define (value) 42)))

(import (cond-expand-multi-empty-test))
(check "cond-expand-multi-empty" (value) 42)

(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
