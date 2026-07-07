;; Regression test for #1173: literal vectors, pairs, and bytevectors must be
;; immutable (R7RS §3.4, §6.4, §6.8, §6.9).

(import (scheme base) (scheme write) (scheme read) (scheme process-context)
        (srfi 64))

(test-begin "literal-immutability")

;;; --- Vectors ---

(test-equal "vector-set! on literal errors"
  'caught (guard (e (#t 'caught)) (vector-set! '#(0 1 2) 1 "doe")))

(test-equal "literal vector unchanged"
  #(0 1 2) '#(0 1 2))

(test-equal "vector-fill! on literal errors"
  'caught (guard (e (#t 'caught)) (vector-fill! '#(1 2 3) 0)))

(test-equal "vector-copy! into literal errors"
  'caught (guard (e (#t 'caught)) (vector-copy! '#(1 2 3) 0 (vector 4 5 6))))

(test-equal "vector-swap! on literal errors"
  'caught (guard (e (#t 'caught)) (vector-swap! '#(1 2 3) 0 1)))

(test-equal "vector-reverse! on literal errors"
  'caught (guard (e (#t 'caught)) (vector-reverse! '#(1 2 3))))

(test-equal "runtime vector is mutable"
  #(99 2 3) (let ((v (vector 1 2 3))) (vector-set! v 0 99) v))

(test-equal "vector-copy yields mutable copy"
  #(99 2 3) (let ((v (vector-copy '#(1 2 3)))) (vector-set! v 0 99) v))

;;; --- Pairs / Lists ---

(test-equal "set-car! on literal errors"
  'caught (guard (e (#t 'caught)) (set-car! '(1 2 3) 99)))

(test-equal "set-cdr! on literal errors"
  'caught (guard (e (#t 'caught)) (set-cdr! '(1 2 3) 99)))

(test-equal "list-set! on literal errors"
  'caught (guard (e (#t 'caught)) (list-set! '(0 1 2) 1 "oops")))

(test-equal "literal list unchanged"
  '(1 2 3) '(1 2 3))

(test-equal "set-car! on dotted literal errors"
  'caught (guard (e (#t 'caught)) (set-car! '(1 . 2) 99)))

(test-equal "set-cdr! on dotted literal errors"
  'caught (guard (e (#t 'caught)) (set-cdr! '(1 . 2) 99)))

(test-equal "runtime list is mutable"
  '(99 2 3) (let ((p (list 1 2 3))) (set-car! p 99) p))

(test-equal "list-copy yields mutable copy"
  '(99 2 3) (let ((p (list-copy '(1 2 3)))) (set-car! p 99) p))

;;; --- Bytevectors ---

(test-equal "bytevector-u8-set! on literal errors"
  'caught (guard (e (#t 'caught)) (bytevector-u8-set! #u8(0 1 2) 1 99)))

(test-equal "bytevector-copy! into literal errors"
  'caught (guard (e (#t 'caught)) (bytevector-copy! #u8(1 2 3) 0 (bytevector 4 5 6))))

(test-equal "literal bytevector unchanged"
  #u8(0 1 2) #u8(0 1 2))

(test-equal "runtime bytevector is mutable"
  #u8(99 2 3) (let ((bv (bytevector 1 2 3))) (bytevector-u8-set! bv 0 99) bv))

(test-equal "bytevector-copy yields mutable copy"
  #u8(99 2 3) (let ((bv (bytevector-copy #u8(1 2 3)))) (bytevector-u8-set! bv 0 99) bv))

;;; --- Cross-call persistence (the original bug) ---

(define (get-vec) '#(0 1 2))
(begin (guard (e (#t #f)) (vector-set! (get-vec) 1 'doe)) (values))
(test-equal "literal vector not mutated across calls"
  #(0 1 2) (get-vec))

(define (get-list) '(0 1 2))
(begin (guard (e (#t #f)) (list-set! (get-list) 1 "oops")) (values))
(test-equal "literal list not mutated across calls"
  '(0 1 2) (get-list))

(define (get-bv) #u8(0 1 2))
(begin (guard (e (#t #f)) (bytevector-u8-set! (get-bv) 1 99)) (values))
(test-equal "literal bytevector not mutated across calls"
  #u8(0 1 2) (get-bv))

;;; --- read returns mutable data ---

(test-equal "read pair is mutable"
  '(99 2 3) (let ((p (read (open-input-string "(1 2 3)"))))
              (set-car! p 99) p))

(test-equal "read vector is mutable"
  #(99 2 3) (let ((v (read (open-input-string "#(1 2 3)"))))
              (vector-set! v 0 99) v))

(test-equal "read string is mutable"
  "Xbc" (let ((s (read (open-input-string "\"abc\""))))
          (string-set! s 0 #\X) s))

;;; --- Summary ---

(let ((runner (test-runner-current)))
  (test-end "literal-immutability")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
