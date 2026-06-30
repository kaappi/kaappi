;; Regression test for #563: define-record-type should not pollute namespace
;; Internal bindings (__undefined__, __record_type_*) must not be user-visible.

(import (scheme base) (scheme write) (scheme eval))

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

;; Partial constructor — omitted field y
(define-record-type pt (make-pt x) pt? (x get-x) (y get-y set-y!))
(define p (make-pt 99))
(check "partial-ctor-field" (= (get-x p) 99))
(check "predicate" (pt? p))

;; __undefined__ must not be visible
(check "no-__undefined__"
  (guard (exn (#t #t))
    (eval '__undefined__ (interaction-environment))
    #f))

;; __record_type_pt must not be visible
(check "no-__record_type_pt"
  (guard (exn (#t #t))
    (eval '__record_type_pt (interaction-environment))
    #f))

;; Full constructor still works
(define-record-type point (make-point x y) point? (x point-x) (y point-y))
(define q (make-point 1 2))
(check "full-ctor" (and (= (point-x q) 1) (= (point-y q) 2)))

;; Mutator on partial ctor record
(set-y! p 42)
(check "set-omitted-field" (= (get-y p) 42))

(display pass) (display " pass, ") (display fail) (display " fail")
(newline)
(when (> fail 0) (exit 1))
