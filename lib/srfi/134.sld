;;; SRFI 134 — Immutable Deques
(define-library (srfi 134)
  (import (scheme base))
  (export ideque ideque? ideque-empty?
          ideque-front ideque-back
          ideque-add-front ideque-add-back
          ideque-remove-front ideque-remove-back
          ideque-length ideque->list list->ideque
          ideque-map ideque-for-each ideque-fold
          ideque-filter ideque-append
          ideque-ref ideque-any ideque-every)
  (begin

    ;; Simple list-pair implementation: (front . back)
    ;; front is a list, back is a reversed list

    (define (ideque . args) (list->ideque args))

    (define (ideque? x)
      (and (pair? x) (list? (car x)) (list? (cdr x))))

    (define (ideque-empty? dq)
      (and (null? (car dq)) (null? (cdr dq))))

    (define (list->ideque lst) (cons lst '()))

    (define (ideque->list dq)
      (append (car dq) (reverse (cdr dq))))

    (define (ideque-add-front dq val)
      (cons (cons val (car dq)) (cdr dq)))

    (define (ideque-add-back dq val)
      (cons (car dq) (cons val (cdr dq))))

    (define (rebalance dq)
      (if (null? (car dq))
          (cons (reverse (cdr dq)) '())
          dq))

    (define (rebalance-back dq)
      (if (null? (cdr dq))
          (cons '() (reverse (car dq)))
          dq))

    (define (ideque-front dq)
      (let ((d (rebalance dq)))
        (if (null? (car d))
            (error "ideque-front: empty deque")
            (caar d))))

    (define (ideque-back dq)
      (let ((d (rebalance-back dq)))
        (if (null? (cdr d))
            (error "ideque-back: empty deque")
            (cadr d))))

    (define (ideque-remove-front dq)
      (let ((d (rebalance dq)))
        (if (null? (car d))
            (error "ideque-remove-front: empty deque")
            (cons (cdar d) (cdr d)))))

    (define (ideque-remove-back dq)
      (let ((d (rebalance-back dq)))
        (if (null? (cdr d))
            (error "ideque-remove-back: empty deque")
            (cons (car d) (cddr d)))))

    (define (ideque-length dq)
      (+ (length (car dq)) (length (cdr dq))))

    (define (ideque-map f dq)
      (list->ideque (map f (ideque->list dq))))

    (define (ideque-for-each f dq)
      (for-each f (ideque->list dq)))

    (define (ideque-fold f seed dq)
      (fold-left f seed (ideque->list dq)))

    (define (fold-left f seed lst)
      (if (null? lst) seed
          (fold-left f (f seed (car lst)) (cdr lst))))

    (define (ideque-filter pred dq)
      (list->ideque (filter pred (ideque->list dq))))

    (define (ideque-append . dqs)
      (list->ideque (apply append (map ideque->list dqs))))

    (define (ideque-ref dq n)
      (list-ref (ideque->list dq) n))

    (define (ideque-any pred dq)
      (let loop ((lst (ideque->list dq)))
        (cond ((null? lst) #f)
              ((pred (car lst)) #t)
              (else (loop (cdr lst))))))

    (define (ideque-every pred dq)
      (let loop ((lst (ideque->list dq)))
        (cond ((null? lst) #t)
              ((not (pred (car lst))) #f)
              (else (loop (cdr lst))))))))
