;; SRFI-17 (generalized set!) conformance tests — audit Phase 3a
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi17.scm

(import (scheme base) (srfi 17) (chibi test))

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

;;; --- pre-defined setters (SRFI-17: "The following standard procedures
;;; have pre-defined setters": car, cdr, caXXr/cdXXr, string-ref, vector-ref)
;; FAIL: #1205 (SRFI-17 stub: no pre-defined setters)
;; (test '(9 2) (let ((p (list 1 2))) ((setter car) p 9) p))
;; FAIL: #1205 (SRFI-17 stub: no pre-defined setters)
;; (test #(1 9) (let ((v (vector 1 2))) ((setter vector-ref) v 1 9) v))

;;; --- generalized set! syntax: (set! (proc arg ...) value) ---
;; FAIL: #1205 (SRFI-17 stub: generalized set! not supported)
;; (test '(9 2) (let ((p (list 1 2))) (set! (car p) 9) p))
;; FAIL: #1205 (SRFI-17 stub: generalized set! not supported)
;; (test #(1 9) (let ((v (vector 1 2))) (set! (vector-ref v 1) 9) v))

(test-end "srfi-17")
