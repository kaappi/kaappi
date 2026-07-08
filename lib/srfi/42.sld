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

    ;; Generator keywords — error when used outside a comprehension.
    ;; Defined first so %do-ec can resolve them as syntax-rules literals.
    (define-syntax :list
      (syntax-rules ()
        ((_ rest ...) (error ":list used outside a comprehension"))))
    (define-syntax :string
      (syntax-rules ()
        ((_ rest ...) (error ":string used outside a comprehension"))))
    (define-syntax :vector
      (syntax-rules ()
        ((_ rest ...) (error ":vector used outside a comprehension"))))
    (define-syntax :range
      (syntax-rules ()
        ((_ rest ...) (error ":range used outside a comprehension"))))
    (define-syntax :integers
      (syntax-rules ()
        ((_ rest ...) (error ":integers used outside a comprehension"))))
    (define-syntax :port
      (syntax-rules ()
        ((_ rest ...) (error ":port used outside a comprehension"))))
    (define-syntax :do
      (syntax-rules ()
        ((_ rest ...) (error ":do used outside a comprehension"))))
    (define-syntax :let
      (syntax-rules ()
        ((_ rest ...) (error ":let used outside a comprehension"))))
    (define-syntax :parallel
      (syntax-rules ()
        ((_ rest ...) (error ":parallel used outside a comprehension"))))
    (define-syntax :while
      (syntax-rules ()
        ((_ rest ...) (error ":while used outside a comprehension"))))
    (define-syntax :until
      (syntax-rules ()
        ((_ rest ...) (error ":until used outside a comprehension"))))

    ;; Internal recursive qualifier processor.
    ;; s = mutable stop flag for :while/:until early exit.
    ;; Processes one qualifier per expansion, recurses on the rest.
    (define-syntax %do-ec
      (syntax-rules (:range :list :string :vector :integers
                     :let :while :until if not and or)
        ;; --- generators ---
        ((_ s (:range var n) rest1 rest2 ...)
         (let ((%n n))
           (let %lp ((var 0))
             (when (and (< var %n) (not s))
               (%do-ec s rest1 rest2 ...)
               (%lp (+ var 1))))))
        ((_ s (:range var a b) rest1 rest2 ...)
         (let ((%b b))
           (let %lp ((var a))
             (when (and (< var %b) (not s))
               (%do-ec s rest1 rest2 ...)
               (%lp (+ var 1))))))
        ((_ s (:range var a b c) rest1 rest2 ...)
         (let ((%b b) (%c c))
           (let %lp ((var a))
             (when (and (if (positive? %c) (< var %b) (> var %b))
                        (not s))
               (%do-ec s rest1 rest2 ...)
               (%lp (+ var %c))))))
        ((_ s (:list var lst) rest1 rest2 ...)
         (let %lp ((%xs lst))
           (when (and (pair? %xs) (not s))
             (let ((var (car %xs)))
               (%do-ec s rest1 rest2 ...))
             (%lp (cdr %xs)))))
        ((_ s (:string var str) rest1 rest2 ...)
         (let* ((%str str) (%n (string-length %str)))
           (let %lp ((%k 0))
             (when (and (< %k %n) (not s))
               (let ((var (string-ref %str %k)))
                 (%do-ec s rest1 rest2 ...))
               (%lp (+ %k 1))))))
        ((_ s (:vector var vec) rest1 rest2 ...)
         (let* ((%v vec) (%n (vector-length %v)))
           (let %lp ((%k 0))
             (when (and (< %k %n) (not s))
               (let ((var (vector-ref %v %k)))
                 (%do-ec s rest1 rest2 ...))
               (%lp (+ %k 1))))))
        ((_ s (:integers var) rest1 rest2 ...)
         (let %lp ((var 0))
           (when (not s)
             (%do-ec s rest1 rest2 ...)
             (%lp (+ var 1)))))
        ((_ s (:let var expr) rest1 rest2 ...)
         (let ((var expr))
           (%do-ec s rest1 rest2 ...)))
        ;; --- control qualifiers ---
        ((_ s (:while test) rest1 rest2 ...)
         (if test
           (%do-ec s rest1 rest2 ...)
           (set! s #t)))
        ((_ s (:until test) rest1 rest2 ...)
         (begin
           (%do-ec s rest1 rest2 ...)
           (when test (set! s #t))))
        ;; --- guards ---
        ((_ s (if test) rest1 rest2 ...)
         (when test (%do-ec s rest1 rest2 ...)))
        ((_ s (not test) rest1 rest2 ...)
         (unless test (%do-ec s rest1 rest2 ...)))
        ((_ s (and test ...) rest1 rest2 ...)
         (when (and test ...) (%do-ec s rest1 rest2 ...)))
        ((_ s (or test ...) rest1 rest2 ...)
         (when (or test ...) (%do-ec s rest1 rest2 ...)))
        ;; --- base case ---
        ((_ s body)
         body)))

    (define-syntax do-ec
      (syntax-rules ()
        ((_ rest1 rest2 ...)
         (let ((%ec-stop #f))
           (%do-ec %ec-stop rest1 rest2 ...)))))

    (define-syntax list-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (let ((%ec-acc '()))
           (do-ec qualifier ... (set! %ec-acc (cons expr %ec-acc)))
           (reverse %ec-acc)))))

    (define-syntax fold-ec
      (syntax-rules ()
        ((_ seed qualifier ... expr f)
         (let ((%ec-acc seed))
           (do-ec qualifier ... (set! %ec-acc (f %ec-acc expr)))
           %ec-acc))))

    (define-syntax fold3-ec
      (syntax-rules ()
        ((_ qualifier ... expr f1 f2)
         (let ((%ec-first #t) (%ec-acc #f))
           (do-ec qualifier ...
             (if %ec-first
               (begin (set! %ec-acc (f1 expr))
                      (set! %ec-first #f))
               (set! %ec-acc (f2 %ec-acc expr))))
           %ec-acc))))

    (define-syntax string-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (list->string (list-ec qualifier ... expr)))))

    (define-syntax vector-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (list->vector (list-ec qualifier ... expr)))))

    (define-syntax append-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (apply append (list-ec qualifier ... expr)))))

    (define-syntax sum-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (fold-ec 0 qualifier ... expr +))))

    (define-syntax product-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (fold-ec 1 qualifier ... expr *))))

    (define-syntax min-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (apply min (list-ec qualifier ... expr)))))

    (define-syntax max-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (apply max (list-ec qualifier ... expr)))))

    (define-syntax first-ec
      (syntax-rules ()
        ((_ default qualifier ... expr)
         (let ((%result (list-ec qualifier ... expr)))
           (if (null? %result) default (car %result))))))

    (define-syntax last-ec
      (syntax-rules ()
        ((_ default qualifier ... expr)
         (let ((%result (list-ec qualifier ... expr)))
           (if (null? %result) default
               (let %lp ((%ls %result))
                 (if (null? (cdr %ls)) (car %ls) (%lp (cdr %ls)))))))))

    (define-syntax any?-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (let ((%ec-r #f))
           (do-ec qualifier ... (when expr (set! %ec-r #t)))
           %ec-r))))

    (define-syntax every?-ec
      (syntax-rules ()
        ((_ qualifier ... expr)
         (let ((%ec-r #t))
           (do-ec qualifier ... (unless expr (set! %ec-r #f)))
           %ec-r))))))
