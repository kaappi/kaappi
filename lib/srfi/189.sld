(define-library (srfi 189)
  (import (scheme base))
  (export just nothing maybe? just? nothing? maybe-ref maybe-ref/default
          maybe-map maybe-filter maybe-bind maybe->values values->maybe
          either right left either? right? left? either-ref either-ref/default
          either-map either-filter either-bind either->values)
  (begin
    (define-record-type <just> (just val) just? (val just-val))
    (define-record-type <nothing> (make-nothing) nothing?)
    (define-record-type <right> (right val) right? (val right-val))
    (define-record-type <left> (left val) left? (val left-val))

    (define nothing (make-nothing))

    (define (maybe? x) (or (just? x) (nothing? x)))
    (define (either? x) (or (right? x) (left? x)))

    (define (maybe-ref m) (if (just? m) (just-val m) (error "maybe-ref: nothing")))
    (define (maybe-ref/default m default) (if (just? m) (just-val m) default))

    (define (maybe-map f m) (if (just? m) (just (f (just-val m))) nothing))
    (define (maybe-filter pred m)
      (if (and (just? m) (pred (just-val m))) m nothing))
    (define (maybe-bind m f) (if (just? m) (f (just-val m)) nothing))

    (define (maybe->values m) (if (just? m) (just-val m) (values)))
    (define (values->maybe . args) (if (null? args) nothing (just (car args))))

    (define (either-ref e) (if (right? e) (right-val e) (error "either-ref: left" (left-val e))))
    (define (either-ref/default e default) (if (right? e) (right-val e) default))

    (define (either-map f e) (if (right? e) (right (f (right-val e))) e))
    (define (either-filter pred e)
      (if (and (right? e) (pred (right-val e))) e (left "filter failed")))
    (define (either-bind e f) (if (right? e) (f (right-val e)) e))

    (define (either->values e) (if (right? e) (right-val e) (values)))
    ))
