(define-library (srfi 195)
  (import (scheme base))
  (export box box? unbox set-box! box-arity unbox-value set-box-value!)
  (begin

    (define-record-type <mv-box>
      (%make-mv-box values)
      box?
      (values %box-values %set-box-values!))

    (define (box . vals)
      (%make-mv-box (list->vector vals)))

    (define (unbox b)
      (let ((v (%box-values b)))
        (if (= (vector-length v) 1)
            (vector-ref v 0)
            (apply values (vector->list v)))))

    (define (set-box! b . vals)
      (let ((v (%box-values b)))
        (if (not (= (length vals) (vector-length v)))
            (error "set-box!: arity mismatch" (length vals) (vector-length v))
            (%set-box-values! b (list->vector vals)))))

    (define (box-arity b)
      (vector-length (%box-values b)))

    (define (unbox-value b i)
      (vector-ref (%box-values b) i))

    (define (set-box-value! b i obj)
      (vector-set! (%box-values b) i obj))

    ))
