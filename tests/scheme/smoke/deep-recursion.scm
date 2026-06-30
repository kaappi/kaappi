;; Test growable frame stack — non-tail-recursive patterns that previously
;; overflowed at ~475 elements with the 480-frame fixed limit.

(import (scheme base) (scheme write))

;; Non-tail-recursive filter
(define (my-filter pred lst)
  (cond ((null? lst) '())
        ((pred (car lst)) (cons (car lst) (my-filter pred (cdr lst))))
        (else (my-filter pred (cdr lst)))))

(let ((result (my-filter (lambda (x) #t) (make-list 5000 1))))
  (unless (= 5000 (length result))
    (error "my-filter failed" (length result))))

;; Non-tail-recursive enumerate-interval
(define (enumerate-interval low high)
  (if (> low high) '()
      (cons low (enumerate-interval (+ low 1) high))))

(let ((result (enumerate-interval 1 5000)))
  (unless (= 5000 (length result))
    (error "enumerate-interval failed" (length result))))

;; Non-tail-recursive map
(define (my-map f lst)
  (if (null? lst) '()
      (cons (f (car lst)) (my-map f (cdr lst)))))

(let ((result (my-map (lambda (x) (* x 2)) (make-list 3000 1))))
  (unless (= 3000 (length result))
    (error "my-map failed" (length result))))

(display "deep-recursion: all tests passed")
(newline)
