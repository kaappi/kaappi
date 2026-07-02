;; Regression tests for case-lambda and case fixes:
;; #840: case-lambda drops clauses beyond 32nd
;; #854: case rejects empty datum list (() body)
;; #836: case-lambda hygiene — user variables named n or args

;; #854: empty datum list in case
(display (case 1
  (() 'never)
  ((1) 'one)
  (else 'other)))
(newline)

;; #836: case-lambda hygiene — user variable n
(define n 42)
(define f (case-lambda ((x) (+ x n))))
(display (f 1))
(newline)

;; #836: case-lambda hygiene — user variable args
(define args 100)
(define g (case-lambda ((x) (+ x args))))
(display (g 1))
(newline)
