;; Regression test for #593: growable call frame and register stacks
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "growable-stacks")

;; Non-tail-recursive filter with 2000 elements (was overflowing at ~475)
(test-equal "non-tail-recursive filter 2000"
  2000
  (let ()
    (define (my-filter pred lst)
      (cond ((null? lst) '())
            ((pred (car lst)) (cons (car lst) (my-filter pred (cdr lst))))
            (else (my-filter pred (cdr lst)))))
    (length (my-filter (lambda (x) #t) (make-list 2000 1)))))

;; Non-tail-recursive enumerate-interval (was overflowing at ~475)
(test-equal "non-tail-recursive enumerate-interval 1000"
  1000
  (let ()
    (define (enumerate-interval low high)
      (if (> low high) '()
          (cons low (enumerate-interval (+ low 1) high))))
    (length (enumerate-interval 1 1000))))

;; Deep non-tail recursion building a list
(test-equal "deep cons recursion 1500"
  1500
  (let ()
    (define (build-list n)
      (if (= n 0) '()
          (cons n (build-list (- n 1)))))
    (length (build-list 1500))))

;; Tail-recursive still works (sanity check)
(test-equal "tail-recursive sum 100000"
  5000050000
  (let ()
    (define (sum n acc)
      (if (= n 0) acc (sum (- n 1) (+ acc n))))
    (sum 100000 0)))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "growable-stacks")
(if (> %test-fail-count 0) (exit 1))
