;;; SRFI 42 — Eager Comprehensions
(define-library (srfi 42)
  (import (scheme base))
  (export list-ec string-ec vector-ec
          append-ec sum-ec product-ec
          min-ec max-ec
          first-ec last-ec any?-ec every?-ec
          do-ec fold-ec fold3-ec
          :list :string :vector :range :integers
          :port :do :let :parallel :while :until)
  (begin

    ;; Core: do-ec iterates, fold-ec accumulates
    (define-syntax do-ec
      (syntax-rules (:list :range :integers :let :while :until)
        ((_ (:list var lst) body ...)
         (for-each (lambda (var) body ...) lst))
        ((_ (:range var stop) body ...)
         (let loop ((var 0))
           (when (< var stop) body ... (loop (+ var 1)))))
        ((_ (:range var start stop) body ...)
         (let loop ((var start))
           (when (< var stop) body ... (loop (+ var 1)))))
        ((_ (:range var start stop step) body ...)
         (let loop ((var start))
           (when (< var stop) body ... (loop (+ var step)))))
        ((_ (:let var expr) body ...)
         (let ((var expr)) body ...))))

    (define-syntax list-ec
      (syntax-rules (:list :range :integers :let)
        ((_ (:list var lst) expr)
         (map (lambda (var) expr) lst))
        ((_ (:range var stop) expr)
         (let loop ((var 0) (acc '()))
           (if (>= var stop) (reverse acc)
               (loop (+ var 1) (cons expr acc)))))
        ((_ (:range var start stop) expr)
         (let loop ((var start) (acc '()))
           (if (>= var stop) (reverse acc)
               (loop (+ var 1) (cons expr acc)))))
        ((_ (:range var start stop step) expr)
         (let loop ((var start) (acc '()))
           (if (>= var stop) (reverse acc)
               (loop (+ var step) (cons expr acc)))))))

    (define-syntax vector-ec
      (syntax-rules (:list :range)
        ((_ qualifier expr)
         (list->vector (list-ec qualifier expr)))))

    (define-syntax string-ec
      (syntax-rules (:list :range)
        ((_ qualifier expr)
         (list->string (list-ec qualifier expr)))))

    (define-syntax append-ec
      (syntax-rules (:list :range)
        ((_ qualifier expr)
         (apply append (list-ec qualifier expr)))))

    (define-syntax sum-ec
      (syntax-rules (:list :range)
        ((_ qualifier expr)
         (apply + (list-ec qualifier expr)))))

    (define-syntax product-ec
      (syntax-rules (:list :range)
        ((_ qualifier expr)
         (apply * (list-ec qualifier expr)))))

    (define-syntax min-ec
      (syntax-rules (:list :range)
        ((_ qualifier expr)
         (apply min (list-ec qualifier expr)))))

    (define-syntax max-ec
      (syntax-rules (:list :range)
        ((_ qualifier expr)
         (apply max (list-ec qualifier expr)))))

    (define-syntax first-ec
      (syntax-rules (:list :range)
        ((_ default qualifier expr)
         (let ((result (list-ec qualifier expr)))
           (if (null? result) default (car result))))))

    (define-syntax last-ec
      (syntax-rules (:list :range)
        ((_ default qualifier expr)
         (let ((result (list-ec qualifier expr)))
           (if (null? result) default
               (let loop ((ls result))
                 (if (null? (cdr ls)) (car ls) (loop (cdr ls)))))))))

    (define-syntax any?-ec
      (syntax-rules (:list :range)
        ((_ qualifier expr)
         (let ((result (list-ec qualifier expr)))
           (let loop ((ls result))
             (cond ((null? ls) #f) ((car ls) #t) (else (loop (cdr ls)))))))))

    (define-syntax every?-ec
      (syntax-rules (:list :range)
        ((_ qualifier expr)
         (let ((result (list-ec qualifier expr)))
           (let loop ((ls result))
             (cond ((null? ls) #t) ((not (car ls)) #f) (else (loop (cdr ls)))))))))

    (define-syntax fold-ec
      (syntax-rules (:list :range)
        ((_ seed (:list var lst) f)
         (fold-left f seed (map (lambda (var) var) lst)))
        ((_ seed (:range var stop) f)
         (let loop ((var 0) (acc seed))
           (if (>= var stop) acc
               (loop (+ var 1) (f acc var)))))))

    (define (fold-left f seed lst)
      (if (null? lst) seed
          (fold-left f (f seed (car lst)) (cdr lst))))

    (define-syntax fold3-ec
      (syntax-rules ()
        ((_ qualifier f seed)
         (fold-ec seed qualifier f))))

    ;; Generator qualifiers (minimal stubs for import compatibility)
    (define-syntax :list
      (syntax-rules ()
        ((_ var lst) (error ":list used outside comprehension"))))
    (define-syntax :string
      (syntax-rules ()
        ((_ var str) (error ":string used outside comprehension"))))
    (define-syntax :vector
      (syntax-rules ()
        ((_ var vec) (error ":vector used outside comprehension"))))
    (define-syntax :range
      (syntax-rules ()
        ((_ var args ...) (error ":range used outside comprehension"))))
    (define-syntax :integers
      (syntax-rules ()
        ((_ var) (error ":integers used outside comprehension"))))
    (define-syntax :port
      (syntax-rules ()
        ((_ var port) (error ":port used outside comprehension"))))
    (define-syntax :do
      (syntax-rules ()
        ((_ args ...) (error ":do used outside comprehension"))))
    (define-syntax :let
      (syntax-rules ()
        ((_ var expr) (error ":let used outside comprehension"))))
    (define-syntax :parallel
      (syntax-rules ()
        ((_ args ...) (error ":parallel used outside comprehension"))))
    (define-syntax :while
      (syntax-rules ()
        ((_ args ...) (error ":while used outside comprehension"))))
    (define-syntax :until
      (syntax-rules ()
        ((_ args ...) (error ":until used outside comprehension"))))))
