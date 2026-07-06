;; Regression test for #1173: literal vectors, pairs, and bytevectors must be
;; immutable (R7RS §3.4, §6.4, §6.8, §6.9).

(import (scheme base) (scheme write) (scheme process-context))

(define pass 0)
(define fail 0)

(define-syntax test
  (syntax-rules ()
    ((_ expected expr)
     (let ((res expr))
       (if (equal? expected res)
           (set! pass (+ pass 1))
           (begin
             (set! fail (+ fail 1))
             (display "FAIL: expected ")
             (write expected)
             (display " got ")
             (write res)
             (newline)))))))

;;; --- Vectors ---

;; R7RS 6.8 example: vector-set! on constant vector is an error
(test 'caught (guard (e (#t 'caught)) (vector-set! '#(0 1 2) 1 "doe")))

;; Literal vector is not mutated after caught error
(test #(0 1 2) '#(0 1 2))

;; vector-fill! on literal
(test 'caught (guard (e (#t 'caught)) (vector-fill! '#(1 2 3) 0)))

;; vector-copy! into literal destination
(test 'caught (guard (e (#t 'caught)) (vector-copy! '#(1 2 3) 0 (vector 4 5 6))))

;; vector-swap! on literal
(test 'caught (guard (e (#t 'caught)) (vector-swap! '#(1 2 3) 0 1)))

;; vector-reverse! on literal
(test 'caught (guard (e (#t 'caught)) (vector-reverse! '#(1 2 3))))

;; Runtime vectors remain mutable
(test #(99 2 3) (let ((v (vector 1 2 3))) (vector-set! v 0 99) v))

;; vector-copy produces a mutable copy
(test #(99 2 3) (let ((v (vector-copy '#(1 2 3)))) (vector-set! v 0 99) v))

;;; --- Pairs / Lists ---

;; R7RS 6.4: set-car! on constant pair is an error
(test 'caught (guard (e (#t 'caught)) (set-car! '(1 2 3) 99)))

;; set-cdr! on constant pair
(test 'caught (guard (e (#t 'caught)) (set-cdr! '(1 2 3) 99)))

;; list-set! on constant list
(test 'caught (guard (e (#t 'caught)) (list-set! '(0 1 2) 1 "oops")))

;; Literal not mutated after caught error
(test '(1 2 3) '(1 2 3))

;; Dotted pair literal is immutable
(test 'caught (guard (e (#t 'caught)) (set-car! '(1 . 2) 99)))
(test 'caught (guard (e (#t 'caught)) (set-cdr! '(1 . 2) 99)))

;; Runtime pairs remain mutable
(test '(99 2 3) (let ((p (list 1 2 3))) (set-car! p 99) p))

;; list-copy produces a mutable copy
(test '(99 2 3) (let ((p (list-copy '(1 2 3)))) (set-car! p 99) p))

;;; --- Bytevectors ---

;; R7RS 6.9: bytevector-u8-set! on literal is an error
(test 'caught (guard (e (#t 'caught)) (bytevector-u8-set! #u8(0 1 2) 1 99)))

;; bytevector-copy! into literal destination
(test 'caught (guard (e (#t 'caught)) (bytevector-copy! #u8(1 2 3) 0 (bytevector 4 5 6))))

;; Literal not mutated
(test #u8(0 1 2) #u8(0 1 2))

;; Runtime bytevectors remain mutable
(test #u8(99 2 3) (let ((bv (bytevector 1 2 3))) (bytevector-u8-set! bv 0 99) bv))

;; bytevector-copy produces a mutable copy
(test #u8(99 2 3) (let ((bv (bytevector-copy #u8(1 2 3)))) (bytevector-u8-set! bv 0 99) bv))

;;; --- Cross-call persistence (the original bug) ---

;; The literal must not be mutated even if the error is caught
(define (get-vec) '#(0 1 2))
(guard (e (#t #f)) (vector-set! (get-vec) 1 'doe))
(test #(0 1 2) (get-vec))

(define (get-list) '(0 1 2))
(guard (e (#t #f)) (list-set! (get-list) 1 "oops"))
(test '(0 1 2) (get-list))

(define (get-bv) #u8(0 1 2))
(guard (e (#t #f)) (bytevector-u8-set! (get-bv) 1 99))
(test #u8(0 1 2) (get-bv))

;;; --- Summary ---

(display pass) (display " pass, ") (display fail) (display " fail")
(newline)
(when (> fail 0) (exit 1))
