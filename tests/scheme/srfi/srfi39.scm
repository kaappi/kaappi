;; SRFI-39 (parameter objects) conformance tests — audit Phase 3.1
;; SRFI-39 is built-in: make-parameter is a primitive (primitives_r7rs.zig),
;; parameterize a compiler form (compiler_advanced.zig).
;; See docs/audit-strategy.md. Run directly and read the pass/fail counts:
;;   zig-out/bin/kaappi tests/scheme/srfi/srfi39.scm

(import (scheme base) (srfi 39) (scheme process-context) (srfi 64))

(test-begin "srfi-39")

;;; --- creation and zero-argument read ---
;; SRFI-39: the parameter is "bound in the global dynamic environment to a
;; cell containing the value returned by the call (converter init)"
(define plain (make-parameter 10))
(test-equal 10 (plain))
(test-equal #t (procedure? plain))

;; converter runs on the initial value at creation time
(define doubled (make-parameter 5 (lambda (v) (* v 2))))
(test-equal 10 (doubled))

;; converter errors at creation are catchable
(test-equal #t (guard (e (#t (error-object? e)))
                 (make-parameter 0 (lambda (v) (error "bad init")))
                 #f))

;;; --- one-argument call assigns through the converter (SRFI-39) ---
(define radix (make-parameter 10))
(test-equal 10 (radix))
(radix 2)
(test-equal 2 (radix))
(radix 16)
(test-equal 16 (radix))

(doubled 3)
(test-equal 6 (doubled))

;; SRFI-39 example: a converter that rejects bad values —
;; "(write-shared 0)  ;gives an error"
(define write-shared
  (make-parameter #f (lambda (x)
                       (if (boolean? x) x (error "only booleans are valid")))))
(test-equal #t (guard (e (#t (error-object? e))) (write-shared 0) #f))
(write-shared #t)
(test-equal #t (write-shared))

;;; --- the spec's prompt example ---
(define prompt
  (make-parameter 123 (lambda (x) (if (string? x) x (number->string x)))))
(test-equal "123" (prompt))
(prompt ">")
(test-equal ">" (prompt))

;;; --- parameterize (R7RS 4.2.6 / SRFI-39) ---
(radix 2)
(test-equal 2 (radix))
(test-equal 16 (parameterize ((radix 16)) (radix)))
(test-equal 2 (radix))                       ; restored on exit

;; converter runs on parameterize values; restore does NOT re-run it
(define conv-count 0)
(define counted
  (make-parameter 0 (lambda (v) (set! conv-count (+ conv-count 1)) v)))
(test-equal 1 conv-count)                    ; init conversion
(test-equal 5 (parameterize ((counted 5)) (counted)))
(test-equal 2 conv-count)                    ; one more for the new binding
(test-equal 0 (counted))                     ; old value restored...
(test-equal 2 conv-count)                    ; ...without converting again

;; converter errors inside parameterize are catchable
(test-equal #t (guard (e (#t (error-object? e)))
                 (parameterize ((write-shared 'nope)) 'unreached)
                 #f))

;; nesting and restoration
(define q (make-parameter 'out))
(test-equal 'b (parameterize ((q 'a)) (parameterize ((q 'b)) (q))))
(test-equal 'a (parameterize ((q 'a)) (parameterize ((q 'b)) (q)) (q)))
(test-equal 'out (q))

;; a non-local exit restores the outer value
(test-equal 'out (guard (e (#t (q)))
                   (parameterize ((q 'in)) (raise 'boom))))
(test-equal 'out (q))

;; rebinding a parameter to its current value
(test-equal 2 (parameterize ((radix (radix))) (radix)))

;; multiple independent parameters bind together
(define px (make-parameter 1))
(define py (make-parameter 2))
(test-equal '(10 20) (parameterize ((px 10) (py 20)) (list (px) (py))))
(test-equal '(1 2) (list (px) (py)))

;; parameterize on a non-parameter raises
(test-equal #t (guard (e (#t #t)) (parameterize ((42 1)) 'x) #f))

;;; --- the spec's radix/prompt/f example block ---
(define (f n) (number->string n (radix)))
(radix 2)
(test-equal "1010" (f 10))
(test-equal "12" (parameterize ((radix 8)) (f 10)))

;; SRFI-39 (normative example): value expressions are evaluated before any
;; of the new bindings take effect —
;;   (parameterize ((radix 8) (prompt (f 10))) (prompt))  ==>  "1010"
(test-equal "1010" (parameterize ((radix 8) (prompt (f 10))) (prompt)))
(let ((a (make-parameter 1)) (b (make-parameter 0)))
  (test-equal 1 (parameterize ((a 2) (b (a))) (b)))
  (test-equal 1 (parameterize ((b (a)) (a 2)) (b))))

(let ((runner (test-runner-current)))
  (test-end "srfi-39")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
