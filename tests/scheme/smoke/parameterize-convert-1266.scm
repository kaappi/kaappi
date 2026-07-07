;;; Regression tests for #1266: parameterize converter mutations must not
;;; leak outside dynamic-wind extent.

(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    ((_ name expected actual)
     (let ((e expected) (a actual))
       (if (equal? e a)
           (set! pass (+ pass 1))
           (begin
             (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (display e)
             (display " got ") (display a) (newline)))))))

;; 1. A later converter must NOT observe an earlier binding's new value.
;;    SRFI-39 ref impl converts all values before installing any binding.
(let ()
  (define a (make-parameter 1))
  (define b (make-parameter 0 (lambda (v) (a))))
  (test "converter sees old value"
        1
        (parameterize ((a 2) (b 99)) (b))))

;; 2. A converter error mid-install must not permanently leak an earlier
;;    mutation — dynamic-wind's after-thunk must restore all parameters.
(let ()
  (define p (make-parameter 1))
  (define w (make-parameter #t (lambda (x)
              (if (boolean? x) x (error "bad")))))
  (test "converter error does not leak"
        1
        (guard (e (#t (p)))
          (parameterize ((p 2) (w 'oops)) 'x))))

;; 3. Duplicate params must restore the original value, not a mid-install
;;    snapshot.
(let ()
  (define q (make-parameter 0))
  (parameterize ((q 1) (q 2))
    (test "duplicate param body value" 2 (q)))
  (test "duplicate param restores original" 0 (q)))

;; 4. Basic converter still works (sanity).
(let ()
  (define p (make-parameter 0 (lambda (v) (* v 10))))
  (test "converter applied in parameterize" 50
        (parameterize ((p 5)) (p)))
  (test "original restored after parameterize" 0 (p)))

(display pass) (display " pass, ")
(display fail) (display " fail") (newline)
(when (> fail 0) (exit 1))
