;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Copyright 2019 Linus Bjornstam
;;
;; You may use this code under either the license in the SRFI document or the
;; license below.
;;
;; Permission to use, copy, modify, and/or distribute this software for any
;; purpose with or without fee is hereby granted, provided that the above
;; copyright notice and this permission notice appear in all source copies.
;; The software is provided "as is", without any express or implied warranties.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; compose: combine multiple functions right-to-left
(define (compose . functions)
  (define (make-chain thunk chain)
    (lambda args
      (call-with-values (lambda () (apply thunk args)) chain)))
  (if (null? functions)
      values
      (let loop ((fns (cdr functions)) (acc (car functions)))
        (if (null? fns)
            acc
            (loop (cdr fns) (make-chain (car fns) acc))))))

;; A special value to be used as a placeholder where no value has been set
;; and #f doesn't cut it.
(define-record-type <nothing>
  (make-nothing)
  nothing?)
(define nothing (make-nothing))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Reducing functions meant to be used at the end of the transducing
;; process.

;; a transducer-friendly cons with the empty list as identity
(define rcons
  (case-lambda
    (() '())
    ((lst) (reverse lst))
    ((lst x) (cons x lst))))


(define reverse-rcons
  (case-lambda
    (() '())
    ((lst) lst)
    ((lst x) (cons x lst))))


;; Use this as the f in transduce to count the amount of elements passed through.
(define rcount
  (case-lambda
    (() 0)
    ((result) result)
    ((result input)
     (+ 1 result))))


;; These two take a predicate and return reducing functions that behave
;; like any and every from srfi-1
(define (rany pred)
  (case-lambda
    (() #f)
    ((result) result)
    ((result input)
     (let ((test (pred input)))
       (if test
           (reduced test)
           #f)))))


(define (revery pred)
  (case-lambda
    (() #t)
    ((result) result)
    ((result input)
     (let ((test (pred input)))
       (if (and result test)
           test
           (reduced #f))))))


(define list-transduce
  (case-lambda
    ((xform f coll)
     (list-transduce xform f (f) coll))
    ((xform f init coll)
     (let* ((xf (xform f))
            (result (list-reduce xf init coll)))
       (xf result)))))

(define vector-transduce
  (case-lambda
    ((xform f coll)
     (vector-transduce xform f (f) coll))
    ((xform f init coll)
     (let* ((xf (xform f))
            (result (vector-reduce xf init coll)))
       (xf result)))))

(define string-transduce
  (case-lambda
    ((xform f coll)
     (string-transduce xform f (f) coll))
    ((xform f init coll)
     (let* ((xf (xform f))
            (result (string-reduce xf init coll)))
       (xf result)))))

(define bytevector-u8-transduce
  (case-lambda
    ((xform f coll)
     (bytevector-u8-transduce xform f (f) coll))
    ((xform f init coll)
     (let* ((xf (xform f))
            (result (bytevector-u8-reduce xf init coll)))
       (xf result)))))

(define port-transduce
  (case-lambda
    ((xform f by)
     (generator-transduce xform f by))
    ((xform f by port)
     (port-transduce xform f (f) by port))
    ((xform f init by port)
     (let* ((xf (xform f))
            (result (port-reduce xf init by port)))
       (xf result)))))

(define generator-transduce
  (case-lambda
    ((xform f gen)
     (generator-transduce xform f (f) gen))
    ((xform f init gen)
     (let* ((xf (xform f))
            (result (generator-reduce xf init gen)))
       (xf result)))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Transducers!

(define (tmap f)
  (lambda (reducer)
    (case-lambda
      (() (reducer))
      ((result) (reducer result))
      ((result input)
       (reducer result (f input))))))


(define (tfilter pred)
  (lambda (reducer)
    (case-lambda
      (() (reducer))
      ((result) (reducer result))
      ((result input)
       (if (pred input)
           (reducer result input)
           result)))))


(define (tremove pred)
  (lambda (reducer)
    (case-lambda
      (() (reducer))
      ((result) (reducer result))
      ((result input)
       (if (not (pred input))
           (reducer result input)
           result)))))


(define (tfilter-map f)
  (compose (tmap f) (tfilter values)))


(define (make-replacer map)
  (cond
   ((list? map)
    (lambda (x)
      (let ((replacer? (assoc x map)))
        (if replacer?
            (cdr replacer?)
            x))))
   ((hash-table? map)
    (lambda (x)
      (hash-table-ref/default map x x)))
   ((procedure? map) map)
   (else
    (error "Unsupported mapping in treplace" map))))


(define (treplace map)
  (tmap (make-replacer map)))


(define (tdrop n)
  (lambda (reducer)
    (let ((new-n (+ 1 n)))
      (case-lambda
        (() (reducer))
        ((result) (reducer result))
        ((result input)
         (set! new-n (- new-n 1))
         (if (positive? new-n)
             result
             (reducer result input)))))))


(define (tdrop-while pred)
  (lambda (reducer)
    (let ((drop? #t))
      (case-lambda
        (() (reducer))
        ((result) (reducer result))
        ((result input)
         (if (and (pred input) drop?)
             result
             (begin
               (set! drop? #f)
               (reducer result input))))))))


(define (ttake n)
  (lambda (reducer)
    (let ((new-n n))
      (case-lambda
        (() (reducer))
        ((result) (reducer result))
        ((result input)
         (let ((result (if (positive? new-n)
                           (reducer result input)
                           result)))
           (set! new-n (- new-n 1))
           (if (not (positive? new-n))
               (ensure-reduced result)
               result)))))))



(define ttake-while
  (case-lambda
    ((pred) (ttake-while pred (lambda (result input) result)))
    ((pred retf)
     (lambda (reducer)
       (let ((take? #t))
         (case-lambda
           (() (reducer))
           ((result) (reducer result))
           ((result input)
            (if (and take? (pred input))
                (reducer result input)
                (begin
                  (set! take? #f)
                  (ensure-reduced (retf result input)))))))))))



(define (tconcatenate reducer)
  (let ((preserving-reducer (preserving-reduced reducer)))
    (case-lambda
      (() (reducer))
      ((result) (reducer result))
      ((result input)
       (list-reduce preserving-reducer result input)))))


(define (tappend-map f)
  (compose (tmap f) tconcatenate))



;; Flattens everything and passes each value through the reducer
(define tflatten
  (lambda (reducer)
    (case-lambda
      (() '())
      ((result) (reducer result))
      ((result input)
       (if (list? input)
           (list-reduce (preserving-reduced (tflatten reducer)) result input)
           (reducer result input))))))



;; removes duplicate consecutive elements
(define tdelete-neighbor-duplicates
  (case-lambda
    (() (tdelete-neighbor-duplicates equal?))
    ((equality-pred?)
     (lambda (reducer)
       (let ((prev nothing))
         (case-lambda
           (() (reducer))
           ((result) (reducer result))
           ((result input)
            (if (and (not (nothing? prev))
                     (equality-pred? prev input))
                result
                (begin
                  (set! prev input)
                  (reducer result input))))))))))


;; Deletes all duplicates that pass through.
(define tdelete-duplicates
  (case-lambda
    (() (tdelete-duplicates equal?))
    ((equality-pred?)
     (lambda (reducer)
       (let ((already-seen (make-hash-table equality-pred?)))
         (case-lambda
           (() (reducer))
           ((result) (reducer result))
           ((result input)
            (if (hash-table-exists? already-seen input)
                result
                (begin
                  (hash-table-set! already-seen input #t)
                  (reducer result input))))))))))

;; Partitions the input into lists of N items. If the input stops it flushes
;; whatever it has collected, which may be shorter than n.
(define (tsegment n)
  (if (not (and (integer? n) (positive? n)))
      (error "argument to tsegment must be a positive integer")
      (lambda (reducer)
        (let ((i 0)
              (collect (make-vector n)))
          (case-lambda
            (() (reducer))
            ((result)
             ;; if there is anything collected when we are asked to quit
             ;; we flush it to the remaining transducers
             (let ((result
                    (if (zero? i)
                        result
                        (reducer result (vector->list collect 0 i)))))
               (set! i 0)
               ;; now finally, pass it downstream
               (if (reduced? result)
                   (reducer (unreduce result))
                   (reducer result))))
            ((result input)
             (vector-set! collect i input)
             (set! i (+ i 1))
             ;; If we have collected enough input we can pass it on downstream
             (if (< i n)
                 result
                 (let ((next-input (vector->list collect 0 i)))
                   (set! i 0)
                   (reducer result next-input)))))))))


(define (tpartition f)
  (lambda (reducer)
    (let* ((prev nothing)
           (collect '()))
      (case-lambda
        (() (reducer))
        ((result)
         (let ((result
                (if (null? collect)
                    result
                    (reducer result (reverse collect)))))
           (set! collect '())
           (if (reduced? result)
               (reducer (unreduce result))
               (reducer result))))
        ((result input)
         (let ((fout (f input)))
           (cond
            ((or (equal? fout prev) (nothing? prev))
             (set! prev fout)
             (set! collect (cons input collect))
             result)
            (else
             (let ((next-input (reverse collect)))
               (set! prev fout)
               (set! collect (list input))
               (reducer result next-input))))))))))


;; Interposes element between each value pushed through the transduction.
(define (tadd-between elem)
  (lambda (reducer)
    (let ((send-elem? #f))
      (case-lambda
        (() (reducer))
        ((result)
         (reducer result))
        ((result input)
         (if send-elem?
             (let ((result (reducer result elem)))
               (if (reduced? result)
                   result
                   (reducer result input)))
             (begin
               (set! send-elem? #t)
               (reducer result input))))))))


;; indexes every value passed through in a cons pair as in (index . value).
;; By default starts at 0
(define tenumerate
  (case-lambda
    (() (tenumerate 0))
    ((n)
     (lambda (reducer)
       (let ((n n))
         (case-lambda
           (() (reducer))
           ((result) (reducer result))
           ((result input)
            (let ((input (cons n input)))
              (set! n (+ n 1))
              (reducer result input)))))))))


(define tlog
  (case-lambda
    (() (tlog (lambda (result input) (write input) (newline))))
    ((log-function)
     (lambda (reducer)
       (case-lambda
         (() (reducer))
         ((result) (reducer result))
         ((result input)
          (log-function result input)
          (reducer result input)))))))
