;; Regression test for #448: let-syntax with >16 bindings leaks macros
;; The 17th+ bindings must NOT be visible after the let-syntax form.

(import (scheme base) (scheme write))

;; Test 1: All 17 macros work inside the let-syntax body
(let-syntax (
  (m1 (syntax-rules () ((_) 1)))
  (m2 (syntax-rules () ((_) 2)))
  (m3 (syntax-rules () ((_) 3)))
  (m4 (syntax-rules () ((_) 4)))
  (m5 (syntax-rules () ((_) 5)))
  (m6 (syntax-rules () ((_) 6)))
  (m7 (syntax-rules () ((_) 7)))
  (m8 (syntax-rules () ((_) 8)))
  (m9 (syntax-rules () ((_) 9)))
  (m10 (syntax-rules () ((_) 10)))
  (m11 (syntax-rules () ((_) 11)))
  (m12 (syntax-rules () ((_) 12)))
  (m13 (syntax-rules () ((_) 13)))
  (m14 (syntax-rules () ((_) 14)))
  (m15 (syntax-rules () ((_) 15)))
  (m16 (syntax-rules () ((_) 16)))
  (m17 (syntax-rules () ((_) 17))))
  (unless (= (+ (m1) (m2) (m3) (m4) (m5) (m6) (m7) (m8)
              (m9) (m10) (m11) (m12) (m13) (m14) (m15) (m16) (m17))
            153)
    (error "let-syntax body: macros did not expand correctly")))

;; Test 2: The 17th macro must NOT be visible after let-syntax
(define leaked-visible #f)
(guard (exn (#t (set! leaked-visible #f)))
  ;; If m17 leaked, this would expand to 17 instead of erroring
  (eval '(m17) (environment '(scheme base))))

(when leaked-visible
  (error "m17 leaked out of let-syntax scope"))

;; Test 3: letrec-syntax with >16 bindings (delegates to let-syntax)
(letrec-syntax (
  (r1 (syntax-rules () ((_) 1)))
  (r2 (syntax-rules () ((_) 2)))
  (r3 (syntax-rules () ((_) 3)))
  (r4 (syntax-rules () ((_) 4)))
  (r5 (syntax-rules () ((_) 5)))
  (r6 (syntax-rules () ((_) 6)))
  (r7 (syntax-rules () ((_) 7)))
  (r8 (syntax-rules () ((_) 8)))
  (r9 (syntax-rules () ((_) 9)))
  (r10 (syntax-rules () ((_) 10)))
  (r11 (syntax-rules () ((_) 11)))
  (r12 (syntax-rules () ((_) 12)))
  (r13 (syntax-rules () ((_) 13)))
  (r14 (syntax-rules () ((_) 14)))
  (r15 (syntax-rules () ((_) 15)))
  (r16 (syntax-rules () ((_) 16)))
  (r17 (syntax-rules () ((_) 17))))
  (unless (= (r17) 17)
    (error "letrec-syntax body: macro 17 did not expand")))

(define letrec-leaked #f)
(guard (exn (#t (set! letrec-leaked #f)))
  (eval '(r17) (environment '(scheme base))))

(when letrec-leaked
  (error "r17 leaked out of letrec-syntax scope"))

(display "PASS")
(newline)
