;; call/cc correctness checks (escape, multi-shot re-entry, dynamic-wind)
(import (scheme base) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "callcc-correctness")

;; 1. Simple escape continuation
(test-eqv "simple escape" 11
  (+ 1 (call/cc (lambda (k) (k 10)))))

;; 2. call/cc that is NOT invoked (proc returns normally)
(test-eqv "proc returns normally" 42
  (call/cc (lambda (k) 42)))

;; 3. Deep non-tail context, escaping out of nested calls
(define (sum-to n k)
  (if (= n 0)
      (k 'done)
      (+ n (sum-to (- n 1) k))))
(test-eq "deep non-tail escape" 'done
  (call/cc (lambda (k) (sum-to 20 k))))

;; 4. Multi-shot re-entry across SEPARATE top-level forms.
;; KNOWN LIMITATION: prints (count 1 result 2), not (count 4 result 4). A
;; continuation captured in one top-level form cannot re-run subsequent
;; top-level forms, because the driver evaluates forms one at a time and the
;; "rest of the program" is not part of the captured Scheme stack. Wrapping the
;; whole body in (begin ...) makes it print (count 4 result 4) -- see
;; callcc-multishot.scm for the working within-a-single-form version.
(define k-saved #f)
(define count 0)
(define result
  (+ 1 (call/cc (lambda (k) (set! k-saved k) 0))))
(set! count (+ count 1))
(if (< count 4) (k-saved count))
(test-equal "multi-shot across top-level (known limitation)"
  '(count 1 result 2)
  (list 'count count 'result result))

;; 5. dynamic-wind ordering with continuation escape
(define trace '())
(define (note x) (set! trace (cons x trace)))
(call/cc
 (lambda (k)
   (dynamic-wind
     (lambda () (note 'before))
     (lambda () (note 'during) (k 'out) (note 'never))
     (lambda () (note 'after)))))
(test-equal "dynamic-wind ordering" '(before during after)
  (reverse trace))

;; 6. The tail_call_cc opcode checks its receiver's arity — pinned so a fix
;;    like #2034 never has to guess which half was already right. The receiver
;;    must sit in genuine tail position, so each call is wrapped from outside.
;;    (Lives here since #2457, not in the primitives_control audit: that file
;;    redefines call/cc at top level, which now declines the superinstruction
;;    for its whole compilation unit.)
(define-syntax raised-msg-cc
  (syntax-rules ()
    ((_ e) (guard (ex (#t (if (error-object? ex) (error-object-message ex) ex)))
             (begin e 'no-raise)))))
(test-equal "tail_call_cc: a 2-argument receiver IS rejected in tail position"
  "call/cc receiver: expected 1 argument, got arity 2"
  (raised-msg-cc ((lambda () (call/cc (lambda (a b) 1))))))
(test-equal "tail_call_cc: a 3-argument receiver IS rejected in tail position"
  "call/cc receiver: expected 1 argument, got arity 3"
  (raised-msg-cc ((lambda () (call/cc (lambda (a b c) 1))))))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "callcc-correctness")
(if (> %test-fail-count 0) (exit 1))
