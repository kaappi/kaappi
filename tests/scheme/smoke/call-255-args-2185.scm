;; Regression test for #2185: 255 arguments is the call ISA's maximum (nargs
;; is one byte), and exactly that count aborted the process -- callClosure
;; sized its register window with `nargs + 1` in u8 arithmetic, and the tail
;; dispatch paths computed a variadic callee's `arity + 1` rest slot the same
;; way. A 256-parameter lambda separately overflowed the compiler's u8 arity
;; counter at definition time. 253/254 arguments always worked, which is what
;; let this ship: the cliff sat on the last legal call.

(import (scheme base) (scheme eval) (scheme write) (scheme process-context)
        (srfi 64))

(test-begin "call-255-args-2185")

(define (make-params n)
  (let loop ((i (- n 1)) (acc '()))
    (if (< i 0) acc
        (loop (- i 1)
              (cons (string->symbol (string-append "p" (number->string i))) acc)))))

(define (count-up n)
  (let loop ((i (- n 1)) (acc '())) (if (< i 0) acc (loop (- i 1) (cons i acc)))))

(define env (interaction-environment))

;; Exact 255-ary procedure: the very count that overflowed `nargs + 1`.
(eval `(define f255 (lambda ,(make-params 255) p254)) env)

(test-equal "direct 255-argument call (used to abort the process)"
            254 (eval `(f255 ,@(count-up 255)) env))
(test-equal "255-argument tail call"
            254 (eval `((lambda () (f255 ,@(count-up 255)))) env))
(test-equal "apply with 255 arguments (the apply limit itself)"
            254 (apply (eval 'f255 env) (count-up 255)))

;; Variadic with 255 FIXED params: the frame needs arity + 1 = 256 argument
;; slots (fixed params plus the rest list, necessarily empty here) -- the
;; quantity the tail paths computed in u8.
(eval `(define v255 (lambda ,(append (make-params 255) 'rest) (cons p254 rest))) env)

(test-equal "variadic-255 direct call" '(254) (eval `(v255 ,@(count-up 255)) env))
(test-equal "variadic-255 tail call" '(254) (eval `((lambda () (v255 ,@(count-up 255)))) env))
(test-equal "variadic-255 via apply" '(254) (apply (eval 'v255 env) (count-up 255)))

;; 256 fixed parameters: uncallable by construction (no call site can encode
;; a 256th argument), so the definition must fail as a catchable compile
;; error -- the compiler's own arity counter overflowed here before the fix.
(test-assert "256-parameter lambda is rejected catchably, not a compile-time abort"
             (guard (e (#t #t))
               (eval `(lambda ,(make-params 256) p0) env)
               #f))

;; Control: one under the cliff keeps working.
(eval `(define f254 (lambda ,(make-params 254) p253)) env)
(test-equal "254-argument call (control, always worked)"
            253 (eval `(f254 ,@(count-up 254)) env))

(let ((runner (test-runner-current)))
  (test-end "call-255-args-2185")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
