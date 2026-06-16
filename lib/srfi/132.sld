(define-library (srfi 132)
  (import (scheme base))
  (export list-sorted? list-sort list-stable-sort list-sort!
          vector-sorted? vector-sort vector-stable-sort vector-sort!)
  (begin
    (define (list-sorted? less? lst)
      (or (null? lst) (null? (cdr lst))
          (and (not (less? (cadr lst) (car lst)))
               (list-sorted? less? (cdr lst)))))

    (define (%merge less? a b)
      (cond ((null? a) b)
            ((null? b) a)
            ((less? (car b) (car a)) (cons (car b) (%merge less? a (cdr b))))
            (else (cons (car a) (%merge less? (cdr a) b)))))

    (define (%merge-sort less? lst)
      (if (or (null? lst) (null? (cdr lst))) lst
          (let-values (((a b) (%split lst)))
            (%merge less? (%merge-sort less? a) (%merge-sort less? b)))))

    (define (%split lst)
      (let loop ((slow lst) (fast lst) (acc '()))
        (if (or (null? fast) (null? (cdr fast)))
            (values (reverse acc) slow)
            (loop (cdr slow) (cddr fast) (cons (car slow) acc)))))

    (define (list-sort less? lst) (%merge-sort less? lst))
    (define (list-stable-sort less? lst) (%merge-sort less? lst))
    (define (list-sort! less? lst) (%merge-sort less? lst))

    (define (vector-sorted? less? vec)
      (let ((len (vector-length vec)))
        (or (<= len 1)
            (let loop ((i 1))
              (or (= i len)
                  (and (not (less? (vector-ref vec i) (vector-ref vec (- i 1))))
                       (loop (+ i 1))))))))

    (define (vector-sort less? vec)
      (list->vector (list-sort less? (vector->list vec))))
    (define (vector-stable-sort less? vec) (vector-sort less? vec))
    (define (vector-sort! less? vec)
      (let ((sorted (vector-sort less? vec)))
        (let loop ((i 0))
          (if (< i (vector-length vec))
              (begin (vector-set! vec i (vector-ref sorted i))
                     (loop (+ i 1)))))))))
