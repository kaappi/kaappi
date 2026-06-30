;; Regression test for #560: define-record-type inside begin at top level

(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)

(define-syntax check
  (syntax-rules ()
    ((_ name expr)
     (begin
       (display name)
       (display ": ")
       (if expr
         (begin (set! pass (+ pass 1)) (display "ok"))
         (begin (set! fail (+ fail 1)) (display "FAIL")))
       (newline)))))

;; define-record-type inside begin at top level
(begin
  (define-record-type pt (make-pt x y) pt? (x get-x) (y get-y)))

(check "begin-record-ctor" (pt? (make-pt 1 2)))
(check "begin-record-accessor" (= (get-x (make-pt 3 4)) 3))

;; nested begin
(begin
  (begin
    (define-record-type line (make-line a b) line? (a line-a) (b line-b))))

(check "nested-begin" (= (line-b (make-line 10 20)) 20))

;; begin with mixed definitions and expressions
(begin
  (define-record-type color (make-color r g b) color? (r red) (g green) (b blue))
  (define c (make-color 255 128 0)))

(check "begin-mixed" (and (= (red c) 255) (= (green c) 128) (= (blue c) 0)))

(display pass) (display " pass, ") (display fail) (display " fail")
(newline)
(when (> fail 0) (exit 1))
