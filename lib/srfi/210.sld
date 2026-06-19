(define-library (srfi 210)
  (import (scheme base) (srfi 195))
  (export with-values case-receive set!-values
          apply/mv call/mv list/mv vector/mv value/mv coarity
          list-values vector-values box-values
          value identity compose-left compose-right
          map-values bind bind/list bind/box bind/mv)
  (begin

    ;;; Syntax

    (define-syntax with-values
      (syntax-rules ()
        ((with-values producer consumer)
         (call-with-values (lambda () producer) consumer))))

    (define-syntax set!-values
      (syntax-rules ()
        ((set!-values (var ...) producer)
         (call-with-values (lambda () producer)
           (lambda (var ...) (set! var var) ...)))))

    (define-syntax case-receive
      (syntax-rules (else)
        ((case-receive producer (else body ...))
         (begin producer body ...))
        ((case-receive producer ((formals ...) body ...) rest ...)
         (let ((vals (call-with-values (lambda () producer) list)))
           (if (= (length vals) (length '(formals ...)))
               (apply (lambda (formals ...) body ...) vals)
               (case-receive (apply values vals) rest ...))))))

    (define-syntax apply/mv
      (syntax-rules ()
        ((apply/mv operator operand ... producer)
         (apply operator operand ... (call-with-values (lambda () producer) list)))))

    (define-syntax call/mv
      (syntax-rules ()
        ((call/mv consumer producer ...)
         (apply consumer
           (append (call-with-values (lambda () producer) list) ...)))))

    (define-syntax list/mv
      (syntax-rules ()
        ((list/mv element ... producer)
         (append (list element ...) (call-with-values (lambda () producer) list)))))

    (define-syntax vector/mv
      (syntax-rules ()
        ((vector/mv element ... producer)
         (list->vector (list/mv element ... producer)))))

    (define-syntax value/mv
      (syntax-rules ()
        ((value/mv i element ... producer)
         (list-ref (list/mv element ... producer) i))))

    (define-syntax coarity
      (syntax-rules ()
        ((coarity producer)
         (call-with-values (lambda () producer) (lambda args (length args))))))

    (define-syntax bind/mv
      (syntax-rules ()
        ((bind/mv producer transducer)
         (call-with-values (lambda () producer) transducer))
        ((bind/mv producer transducer rest ...)
         (bind/mv (call-with-values (lambda () producer) transducer) rest ...))))

    ;;; Procedures

    (define (list-values lst)
      (apply values lst))

    (define (vector-values vec)
      (apply values (vector->list vec)))

    (define (box-values b)
      (unbox b))

    (define (value obj . rest)
      (if (null? rest) obj
          (list-ref (cons obj rest) 0)))

    (define (identity . objs)
      (apply values objs))

    (define (compose-left . procs)
      (if (null? procs) identity
          (lambda args
            (let loop ((ps procs) (vals args))
              (if (null? ps) (apply values vals)
                  (loop (cdr ps)
                        (call-with-values (lambda () (apply (car ps) vals)) list)))))))

    (define (compose-right . procs)
      (apply compose-left (reverse procs)))

    (define (map-values proc)
      (lambda args (apply values (map proc args))))

    (define (bind obj . transducers)
      (let loop ((ts transducers) (val obj))
        (if (null? ts) val
            (loop (cdr ts) ((car ts) val)))))

    (define (bind/list lst . transducers)
      (let loop ((ts transducers) (vals lst))
        (if (null? ts) (apply values vals)
            (loop (cdr ts)
                  (call-with-values (lambda () (apply (car ts) vals)) list)))))

    (define (bind/box b . transducers)
      (let loop ((ts transducers) (vals (call-with-values (lambda () (unbox b)) list)))
        (if (null? ts) (apply values vals)
            (loop (cdr ts)
                  (call-with-values (lambda () (apply (car ts) vals)) list)))))

    ))
