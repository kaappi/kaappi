(import (scheme base) (scheme write) (srfi 27))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))
(define (check-true name val)
  (if val (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))
(define (check-false name val)
  (if (not val) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

;;; ---- random-integer ----
(let ((r (random-integer 100)))
  (check-true "random-integer range" (and (>= r 0) (< r 100))))
(let ((r (random-integer 1)))
  (check "random-integer 1" r 0))
(let ((r (random-integer 10)))
  (check-true "random-integer < 10" (< r 10)))

;;; ---- random-real ----
(let ((r (random-real)))
  (check-true "random-real > 0" (> r 0.0))
  (check-true "random-real < 1" (< r 1.0)))

;;; ---- default-random-source ----
(check-true "default-random-source" (random-source? default-random-source))

;;; ---- make-random-source ----
(let ((rs (make-random-source)))
  (check-true "make-random-source" (random-source? rs))

  ;; random-source-randomize!
  (random-source-randomize! rs)
  (check-true "randomize!" #t)

  ;; random-source-pseudo-randomize!
  (random-source-pseudo-randomize! rs 1 2)
  (check-true "pseudo-randomize!" #t)

  ;; random-source-state-ref / random-source-state-set!
  (let ((state (random-source-state-ref rs)))
    (check-true "state-ref is list" (list? state))
    (random-source-state-set! rs state)
    (check-true "state-set!" #t))

  ;; random-source-make-integers
  (let ((gen (random-source-make-integers rs)))
    (check-true "make-integers is procedure" (procedure? gen))
    (let ((r (gen 100)))
      (check-true "gen range" (and (>= r 0) (< r 100)))))

  ;; random-source-make-reals
  (let ((gen (random-source-make-reals rs)))
    (check-true "make-reals is procedure" (procedure? gen))
    (let ((r (gen)))
      (check-true "gen-real range" (and (>= r 0.0) (< r 1.0))))))

;;; ---- random-source? predicate ----
(check-false "random-source? number" (random-source? 42))
(check-false "random-source? string" (random-source? "hello"))
(check-false "random-source? list" (random-source? '()))

;;; ---- Multiple random values ----
(let ((values (map (lambda (_) (random-integer 1000)) '(1 2 3 4 5 6 7 8 9 10))))
  (check-true "10 random ints" (= (length values) 10))
  (check-true "all in range" (every (lambda (v) (and (>= v 0) (< v 1000))) values)))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "Random coverage tests failed" fail))
