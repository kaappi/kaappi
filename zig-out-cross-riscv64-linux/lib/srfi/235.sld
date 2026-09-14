(define-library (srfi 235)
  (import (scheme base) (scheme case-lambda))
  (export constantly complement swap flip on-left on-right
          on each-of all-of any-of conjoin disjoin
          left-section right-section apply-chain
          arguments-drop arguments-drop-right
          arguments-take arguments-take-right
          group-by
          begin-procedure if-procedure when-procedure unless-procedure
          value-procedure case-procedure
          and-procedure eager-and-procedure
          or-procedure eager-or-procedure
          funcall-procedure loop-procedure while-procedure until-procedure
          always never boolean
          compose o)
  (begin

    (define (constantly . vals)
      (lambda args (apply values vals)))

    (define (complement pred)
      (lambda args (not (apply pred args))))

    (define (swap f)
      (lambda (a b . rest) (apply f b a rest)))

    (define (flip f)
      (lambda args (apply f (reverse args))))

    (define (on-left f)
      (lambda (a b) (f a)))

    (define (on-right f)
      (lambda (a b) (f b)))

    (define (on f g)
      (lambda args (apply f (map g args))))

    (define (each-of . procs)
      (lambda args
        (for-each (lambda (p) (apply p args)) procs)))

    (define (all-of pred)
      (lambda (lst)
        (let loop ((l lst) (last #t))
          (if (null? l) last
              (let ((v (pred (car l))))
                (if v (loop (cdr l) v) #f))))))

    (define (any-of pred)
      (lambda (lst)
        (let loop ((l lst))
          (and (not (null? l))
               (or (pred (car l)) (loop (cdr l)))))))

    (define (conjoin . preds)
      (lambda args
        (let loop ((ps preds) (last #t))
          (if (null? ps) last
              (let ((v (apply (car ps) args)))
                (if v (loop (cdr ps) v) #f))))))

    (define (disjoin . preds)
      (lambda args
        (let loop ((ps preds))
          (and (not (null? ps))
               (or (apply (car ps) args) (loop (cdr ps)))))))

    (define (left-section proc . args)
      (lambda objs (apply proc (append args objs))))

    (define (right-section proc . args)
      (lambda objs (apply proc (append objs (reverse args)))))

    (define (apply-chain . procs)
      (if (null? procs) values
          (let ((f (car procs)) (rest (cdr procs)))
            (if (null? rest) f
                (let ((g (apply apply-chain rest)))
                  (lambda args
                    (call-with-values (lambda () (apply g args)) f)))))))

    (define (arguments-drop proc n)
      (lambda args (apply proc (list-tail args n))))

    (define (arguments-drop-right proc n)
      (lambda args (apply proc (%take args (- (length args) n)))))

    (define (arguments-take proc n)
      (lambda args (apply proc (%take args n))))

    (define (arguments-take-right proc n)
      (lambda args (apply proc (list-tail args (- (length args) n)))))

    (define (%take lst n)
      (if (<= n 0) '()
          (cons (car lst) (%take (cdr lst) (- n 1)))))

    (define group-by
      (case-lambda
        ((key-proc) (group-by key-proc equal?))
        ((key-proc =)
         (lambda (lst)
           (let loop ((l lst) (keys '()) (groups '()))
             (if (null? l)
                 (map reverse groups)
                 (let* ((elem (car l))
                        (key (key-proc elem))
                        (i (%index-of key keys =)))
                   (if i
                       (loop (cdr l) keys (%list-add groups i elem))
                       (loop (cdr l)
                             (append keys (list key))
                             (append groups (list (list elem))))))))))))

    (define (%index-of key lst =)
      (let loop ((l lst) (i 0))
        (cond ((null? l) #f)
              ((= key (car l)) i)
              (else (loop (cdr l) (+ i 1))))))

    (define (%list-add lst i elem)
      (if (= i 0)
          (cons (cons elem (car lst)) (cdr lst))
          (cons (car lst) (%list-add (cdr lst) (- i 1) elem))))

    (define (begin-procedure . thunks)
      (if (null? thunks)
          (if #f #f)
          (let loop ((ts thunks))
            (if (null? (cdr ts))
                ((car ts))
                (begin ((car ts)) (loop (cdr ts)))))))

    (define (if-procedure value then-thunk else-thunk)
      (if value (then-thunk) (else-thunk)))

    (define (when-procedure value . thunks)
      (when value (for-each (lambda (t) (t)) thunks)))

    (define (unless-procedure value . thunks)
      (unless value (for-each (lambda (t) (t)) thunks)))

    (define (value-procedure value then-proc else-thunk)
      (if value (then-proc value) (else-thunk)))

    (define case-procedure
      (case-lambda
        ((value thunk-alist)
         (let ((entry (assv value thunk-alist)))
           (if entry ((cdr entry)) (if #f #f))))
        ((value thunk-alist else-thunk)
         (let ((entry (assv value thunk-alist)))
           (if entry ((cdr entry)) (else-thunk))))))

    (define (and-procedure . thunks)
      (if (null? thunks) #t
          (let loop ((ts thunks))
            (if (null? (cdr ts))
                ((car ts))
                (let ((v ((car ts))))
                  (if v (loop (cdr ts)) #f))))))

    (define (eager-and-procedure . thunks)
      (let loop ((ts thunks) (last #t))
        (if (null? ts) last
            (let ((v ((car ts))))
              (loop (cdr ts) (if (and last v) v #f))))))

    (define (or-procedure . thunks)
      (let loop ((ts thunks))
        (if (null? ts) #f
            (let ((v ((car ts))))
              (if v v (loop (cdr ts)))))))

    (define (eager-or-procedure . thunks)
      (let loop ((ts thunks) (first #f))
        (if (null? ts) first
            (let ((v ((car ts))))
              (loop (cdr ts) (or first v))))))

    (define (funcall-procedure thunk)
      (thunk))

    (define (loop-procedure thunk)
      (let loop () (thunk) (loop)))

    (define (while-procedure thunk)
      (let loop () (when (thunk) (loop))))

    (define (until-procedure thunk)
      (let loop () (unless (thunk) (loop))))

    (define (always . args) #t)

    (define (never . args) #f)

    (define (boolean obj) (if obj #t #f))

    (define (compose . procs)
      (if (null? procs) values
          (let ((f (car procs)) (rest (cdr procs)))
            (if (null? rest) f
                (let ((g (apply compose rest)))
                  (lambda args
                    (call-with-values (lambda () (apply g args)) f)))))))

    (define o compose)))
