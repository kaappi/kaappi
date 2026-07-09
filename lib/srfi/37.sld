(define-library (srfi 37)
  (import (scheme base))
  (export args-fold option?
          option option-names option-required-arg? option-optional-arg?
          option-processor)
  (begin

    (define-record-type <option>
      (%make-option names required-arg? optional-arg? processor)
      option?
      (names option-names)
      (required-arg? option-required-arg?)
      (optional-arg? option-optional-arg?)
      (processor option-processor))

    (define (option names required-arg? optional-arg? processor)
      (%make-option names required-arg? optional-arg? processor))

    (define (find-option opts name)
      (let loop ((os opts))
        (cond
          ((null? os) #f)
          ((member name (option-names (car os))) (car os))
          (else (loop (cdr os))))))

    (define (short-opt? s)
      (and (> (string-length s) 1)
           (char=? (string-ref s 0) #\-)
           (not (char=? (string-ref s 1) #\-))))

    (define (long-opt? s)
      (and (> (string-length s) 2)
           (char=? (string-ref s 0) #\-)
           (char=? (string-ref s 1) #\-)))

    (define (long-opt-name s)
      (let ((eq (string-index s #\=)))
        (if eq (substring s 2 eq)
            (substring s 2 (string-length s)))))

    (define (long-opt-arg s)
      (let ((eq (string-index s #\=)))
        (if eq (substring s (+ eq 1) (string-length s)) #f)))

    (define (string-index s ch)
      (let loop ((i 0))
        (cond
          ((= i (string-length s)) #f)
          ((char=? (string-ref s i) ch) i)
          (else (loop (+ i 1))))))

    (define (args-fold args options unrecognized-proc operand-proc . seeds)
      (let loop ((args args) (seeds seeds))
        (if (null? args)
            (apply values seeds)
            (let ((arg (car args)) (rest (cdr args)))
              (cond
                ((string=? arg "--")
                 (let oloop ((operands rest) (seeds seeds))
                   (if (null? operands)
                       (apply values seeds)
                       (call-with-values
                         (lambda () (apply operand-proc (car operands) seeds))
                         (lambda new-seeds
                           (oloop (cdr operands) new-seeds))))))
                ((long-opt? arg)
                 (let* ((name (long-opt-name arg))
                        (opt-arg (long-opt-arg arg))
                        (opt (find-option options name)))
                   (if opt
                       (if (option-required-arg? opt)
                           (let* ((a (or opt-arg (if (pair? rest) (car rest) #f)))
                                  (r (if (and (not opt-arg) (pair? rest)) (cdr rest) rest)))
                             (call-with-values
                               (lambda () (apply (option-processor opt) opt name a seeds))
                               (lambda new-seeds (loop r new-seeds))))
                           (call-with-values
                             (lambda () (apply (option-processor opt) opt name opt-arg seeds))
                             (lambda new-seeds (loop rest new-seeds))))
                       (call-with-values
                         (lambda () (apply unrecognized-proc
                                          (%make-option (list name) #f #f #f) name #f seeds))
                         (lambda new-seeds (loop rest new-seeds))))))
                ((short-opt? arg)
                 (let sloop ((i 1) (seeds seeds) (rest rest))
                   (if (>= i (string-length arg))
                       (loop rest seeds)
                       (let* ((ch (string-ref arg i))
                              (opt (find-option options ch)))
                         (if opt
                             (if (option-required-arg? opt)
                                 (let* ((a (if (< (+ i 1) (string-length arg))
                                               (substring arg (+ i 1) (string-length arg))
                                               (if (pair? rest) (car rest) #f)))
                                        (r (if (< (+ i 1) (string-length arg))
                                               rest (if (pair? rest) (cdr rest) rest))))
                                   (call-with-values
                                     (lambda () (apply (option-processor opt) opt ch a seeds))
                                     (lambda new-seeds (loop r new-seeds))))
                                 (if (and (option-optional-arg? opt)
                                          (< (+ i 1) (string-length arg)))
                                     (let ((a (substring arg (+ i 1) (string-length arg))))
                                       (call-with-values
                                         (lambda () (apply (option-processor opt) opt ch a seeds))
                                         (lambda new-seeds (loop rest new-seeds))))
                                     (call-with-values
                                       (lambda () (apply (option-processor opt) opt ch #f seeds))
                                       (lambda new-seeds
                                         (sloop (+ i 1) new-seeds rest)))))
                             (call-with-values
                               (lambda () (apply unrecognized-proc
                                                 (%make-option (list ch) #f #f #f) ch #f seeds))
                               (lambda new-seeds
                                 (sloop (+ i 1) new-seeds rest))))))))
                (else
                 (call-with-values
                   (lambda () (apply operand-proc arg seeds))
                   (lambda new-seeds (loop rest new-seeds)))))))))))
