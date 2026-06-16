(define-library (srfi 141)
  (import (scheme base))
  (export floor/ floor-quotient floor-remainder
          ceiling/ ceiling-quotient ceiling-remainder
          truncate/ truncate-quotient truncate-remainder
          round/ round-quotient round-remainder
          euclidean/ euclidean-quotient euclidean-remainder
          balanced/ balanced-quotient balanced-remainder)
  (begin
    (define (floor-quotient n d)
      (let ((q (quotient n d))
            (r (remainder n d)))
        (if (and (not (= r 0)) (not (eq? (< n 0) (< d 0))))
            (- q 1) q)))
    (define (floor-remainder n d) (- n (* d (floor-quotient n d))))
    (define (floor/ n d) (values (floor-quotient n d) (floor-remainder n d)))

    (define (truncate-quotient n d) (quotient n d))
    (define (truncate-remainder n d) (remainder n d))
    (define (truncate/ n d) (values (truncate-quotient n d) (truncate-remainder n d)))

    (define (ceiling-quotient n d)
      (let ((q (quotient n d))
            (r (remainder n d)))
        (if (and (not (= r 0)) (eq? (< n 0) (< d 0)))
            (+ q 1) q)))
    (define (ceiling-remainder n d) (- n (* d (ceiling-quotient n d))))
    (define (ceiling/ n d) (values (ceiling-quotient n d) (ceiling-remainder n d)))

    (define (round-quotient n d)
      (let* ((q (quotient n d))
             (r (remainder n d))
             (ar (abs r))
             (ad (abs d)))
        (cond ((< (* 2 ar) ad) q)
              ((> (* 2 ar) ad) (if (eq? (< n 0) (< d 0)) (+ q 1) (- q 1)))
              (else (if (even? q) q (if (eq? (< n 0) (< d 0)) (+ q 1) (- q 1)))))))
    (define (round-remainder n d) (- n (* d (round-quotient n d))))
    (define (round/ n d) (values (round-quotient n d) (round-remainder n d)))

    (define (euclidean-quotient n d)
      (let ((q (floor-quotient n d)))
        (if (< (- n (* d q)) 0) (if (> d 0) (- q 1) (+ q 1)) q)))
    (define (euclidean-remainder n d) (- n (* d (euclidean-quotient n d))))
    (define (euclidean/ n d) (values (euclidean-quotient n d) (euclidean-remainder n d)))

    (define balanced-quotient round-quotient)
    (define balanced-remainder round-remainder)
    (define (balanced/ n d) (values (balanced-quotient n d) (balanced-remainder n d)))))
