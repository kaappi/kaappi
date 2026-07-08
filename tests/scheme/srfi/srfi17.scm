;; SRFI-17 (generalized set!) conformance tests — audit Phase 3a
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi17.scm

(import (scheme base) (scheme cxr) (srfi 17) (chibi test))

(test-begin "srfi-17")

;;; --- getter-with-setter (works for user-registered getters) ---
(define storage (vector 1 2 3))
(define my-get
  (getter-with-setter
   (lambda (i) (vector-ref storage i))
   (lambda (i v) (vector-set! storage i v))))
(test 2 (my-get 1))
((setter my-get) 1 99)
(test 99 (my-get 1))
(test 1 (my-get 0))

;; setter on an unregistered procedure raises
(test #t (guard (e (#t (error-object? e))) (setter (lambda (x) x)) #f))

;;; --- pre-defined setters ---
(test '(9 2) (let ((p (list 1 2))) ((setter car) p 9) p))
(test '(1 . 9) (let ((p (cons 1 2))) ((setter cdr) p 9) p))
(test #(1 9) (let ((v (vector 1 2))) ((setter vector-ref) v 1 9) v))
(test "axc" (let ((s (string-copy "abc"))) ((setter string-ref) s 1 #\x) s))

;;; --- generalized set! syntax: (set! (proc arg ...) value) ---
(test '(9 2) (let ((p (list 1 2))) (set! (car p) 9) p))
(test '(1 . 9) (let ((p (cons 1 2))) (set! (cdr p) 9) p))
(test #(1 9) (let ((v (vector 1 2))) (set! (vector-ref v 1) 9) v))
(test "axc" (let ((s (string-copy "abc"))) (set! (string-ref s 1) #\x) s))

;;; --- generalized set! with user-defined setter ---
(test 42 (let ((s (vector 0)))
           (define my-ref
             (getter-with-setter
               (lambda (v i) (vector-ref v i))
               (lambda (v i val) (vector-set! v i val))))
           (set! (my-ref s 0) 42)
           (my-ref s 0)))

;;; --- cXXr setters ---
(test '((9 2) 3)
  (let ((p (list (list 1 2) 3))) (set! (caar p) 9) p))
(test '(1 9 3)
  (let ((p (list 1 2 3))) (set! (cadr p) 9) p))
(test '((1 . 9) 3)
  (let ((p (list (cons 1 2) 3))) (set! (cdar p) 9) p))

(test-end "srfi-17")
