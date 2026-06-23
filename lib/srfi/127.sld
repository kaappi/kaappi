;;; SRFI 127 — Lazy Sequences
(define-library (srfi 127)
  (import (scheme base) (scheme lazy))
  (export generator->lseq lseq? lseq=?
          lseq-car lseq-cdr lseq-first lseq-rest
          lseq-take lseq-drop lseq-realize
          lseq-map lseq-for-each lseq-filter
          lseq-length lseq-append
          lseq-ref lseq-any lseq-every
          lseq->list list->lseq)
  (begin

    (define (generator->lseq gen)
      (let ((v (gen)))
        (if (eof-object? v) '()
            (cons v (delay (generator->lseq gen))))))

    (define (lseq? x)
      (or (null? x) (pair? x)))

    (define (lseq-car ls) (car ls))

    (define (lseq-cdr ls)
      (let ((rest (cdr ls)))
        (if (promise? rest) (force rest) rest)))

    (define lseq-first lseq-car)
    (define lseq-rest lseq-cdr)

    (define (lseq-realize ls)
      (let loop ((s ls) (acc '()))
        (if (null? s) (reverse acc)
            (loop (lseq-cdr s) (cons (lseq-car s) acc)))))

    (define lseq->list lseq-realize)

    (define (list->lseq lst) lst)

    (define (lseq-take ls n)
      (if (or (= n 0) (null? ls)) '()
          (cons (lseq-car ls)
                (delay (lseq-take (lseq-cdr ls) (- n 1))))))

    (define (lseq-drop ls n)
      (if (or (= n 0) (null? ls)) ls
          (lseq-drop (lseq-cdr ls) (- n 1))))

    (define (lseq-ref ls n)
      (if (= n 0) (lseq-car ls)
          (lseq-ref (lseq-cdr ls) (- n 1))))

    (define (lseq-length ls)
      (let loop ((s ls) (n 0))
        (if (null? s) n
            (loop (lseq-cdr s) (+ n 1)))))

    (define (lseq-map f ls)
      (if (null? ls) '()
          (cons (f (lseq-car ls))
                (delay (lseq-map f (lseq-cdr ls))))))

    (define (lseq-for-each f ls)
      (unless (null? ls)
        (f (lseq-car ls))
        (lseq-for-each f (lseq-cdr ls))))

    (define (lseq-filter pred ls)
      (cond
        ((null? ls) '())
        ((pred (lseq-car ls))
         (cons (lseq-car ls)
               (delay (lseq-filter pred (lseq-cdr ls)))))
        (else (lseq-filter pred (lseq-cdr ls)))))

    (define (lseq-any pred ls)
      (cond
        ((null? ls) #f)
        ((pred (lseq-car ls)) #t)
        (else (lseq-any pred (lseq-cdr ls)))))

    (define (lseq-every pred ls)
      (cond
        ((null? ls) #t)
        ((not (pred (lseq-car ls))) #f)
        (else (lseq-every pred (lseq-cdr ls)))))

    (define (lseq-append . lseqs)
      (cond
        ((null? lseqs) '())
        ((null? (car lseqs)) (apply lseq-append (cdr lseqs)))
        (else (cons (lseq-car (car lseqs))
                    (delay (apply lseq-append
                                  (cons (lseq-cdr (car lseqs))
                                        (cdr lseqs))))))))

    (define (lseq=? elt=? ls1 ls2)
      (cond
        ((and (null? ls1) (null? ls2)) #t)
        ((or (null? ls1) (null? ls2)) #f)
        ((elt=? (lseq-car ls1) (lseq-car ls2))
         (lseq=? elt=? (lseq-cdr ls1) (lseq-cdr ls2)))
        (else #f)))))
