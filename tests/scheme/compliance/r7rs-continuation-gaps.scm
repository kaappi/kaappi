;; R7RS continuation-interaction gap tests — audit Phase 4B.
;; call/cc x dynamic-wind / guard / parameterize / multiple values.
;; All state mutated across a continuation re-entry lives in globals:
;; set! of register-allocated locals is rolled back on re-entry (#1168),
;; and that bug class turns these tests into infinite loops.
;; Spec references cite docs/errata-corrected-r7rs.pdf sections 6.10/6.11.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "r7rs-continuation-gaps")

;;; --- 6.10 dynamic-wind: normal before/thunk/after ordering ---
(define dw-trace '())
(define (dw-add s) (set! dw-trace (cons s dw-trace)))
(test-equal "dynamic-wind normal order" '(before during after)
  (begin
    (set! dw-trace '())
    (dynamic-wind
      (lambda () (dw-add 'before))
      (lambda () (dw-add 'during))
      (lambda () (dw-add 'after)))
    (reverse dw-trace)))

;; values of the thunk are the values of the dynamic-wind expression
(test-equal "dynamic-wind passes thunk values through" '(a b)
  (call-with-values
    (lambda () (dynamic-wind (lambda () 1) (lambda () (values 'a 'b)) (lambda () 2)))
    list))

;;; --- 6.10 escape ordering: afters run inner-to-outer ---
(test-equal "escape runs afters inner-to-outer" '(b1 b2 a2 a1)
  (begin
    (set! dw-trace '())
    (call-with-current-continuation
      (lambda (esc)
        (dynamic-wind
          (lambda () (dw-add 'b1))
          (lambda ()
            (dynamic-wind
              (lambda () (dw-add 'b2))
              (lambda () (esc 'out))
              (lambda () (dw-add 'a2))))
          (lambda () (dw-add 'a1)))))
    (reverse dw-trace)))

;;; --- 6.10 re-entry: the spec's connect/talk/disconnect example (p. 54) ---
(define reentry-path '())
(define reentry-k #f)
(define (reentry-add s) (set! reentry-path (cons s reentry-path)))
(test-equal "dynamic-wind re-entry (R7RS example)"
  '(connect talk1 disconnect connect talk2 disconnect)
  (begin
    (dynamic-wind
      (lambda () (reentry-add 'connect))
      (lambda () (reentry-add (call-with-current-continuation
                                (lambda (c0) (set! reentry-k c0) 'talk1))))
      (lambda () (reentry-add 'disconnect)))
    (if (< (length reentry-path) 4)
        (reentry-k 'talk2)
        (reverse reentry-path))))

;;; --- multi-shot: a continuation may be invoked repeatedly ---
(define ms-k #f)
(define ms-hits 0)
(test-equal "multi-shot continuation re-executes its segment" 3
  (begin
    (call-with-current-continuation (lambda (k) (set! ms-k k)))
    (set! ms-hits (+ ms-hits 1))
    (if (< ms-hits 3) (ms-k #f) ms-hits)))

;;; --- call/cc + parameterize: re-entry restores the dynamic binding ---
(define pr-p (make-parameter 'outer))
(define pr-k #f)
(define pr-n 0)
(define pr-seen '())
(test-equal "parameterize value restored on continuation re-entry"
  '(inner inner)
  (begin
    (parameterize ((pr-p 'inner))
      (call-with-current-continuation (lambda (k) (set! pr-k k)))
      (set! pr-seen (cons (pr-p) pr-seen))
      (set! pr-n (+ pr-n 1))
      (if (< pr-n 2) (pr-k #f) 'fin))
    pr-seen))
(test-equal "parameter restored after re-entrant parameterize" 'outer (pr-p))

;; escaping out of a parameterize restores the outer value
(define esc-p (make-parameter 0))
(test-equal "escape from parameterize restores parameter" '(5 0)
  (let ((inside (call-with-current-continuation
                  (lambda (esc)
                    (parameterize ((esc-p 5))
                      (esc (esc-p)))))))
    (list inside (esc-p))))

;;; --- 6.11 multiple values ---
(test-equal "call-with-values basic" 6
  (call-with-values (lambda () (values 1 2 3)) +))
(test-equal "call-with-values * - (R7RS example)" -1
  (call-with-values * -))
(test-equal "zero values to nullary consumer" 'none
  (call-with-values (lambda () (values)) (lambda () 'none)))
(test-equal "single values in ordinary context" 3
  (+ 1 (values 2)))
(test-equal "values in non-tail producer position" 3
  (let-values (((a b) (begin 'side (values 1 2)))) (+ a b)))
(test-equal "values through if in producer" '(1)
  (let-values (((a) (if #t (values 1) 2))) (list a)))

;; "The escape procedure accepts the same number of arguments as the
;; continuation to the original call" — k invoked with 2 values must
;; deliver both to the receiving producer context
;; FAIL: #1169 (continuation invoked with multiple arguments drops all
;;   but the first)
;; (test-equal "continuation carries multiple values" '(1 2)
;;   (call-with-values (lambda () (call/cc (lambda (k) (k 1 2)))) list))

;;; --- 6.11 guard + raise interactions ---
(test-equal "guard catches raise" '(caught oops)
  (guard (e ((symbol? e) (list 'caught e))) (raise 'oops)))
(test-equal "guard => clause (R7RS example)" 2
  (guard (e ((assq 'b e) => cdr))
    (raise (list (cons 'a 1) (cons 'b 2)))))
(test-equal "guard else clause" 'fallback
  (guard (e (#f 'nope) (else 'fallback)) (raise 42)))
(test-equal "unmatched guard re-raises to outer guard" '(outer sym)
  (guard (outer (#t (list 'outer outer)))
    (guard (inner ((string? inner) 'nope))
      (raise 'sym))))
(test-equal "raise-continuable resumes with handler's value" 43
  (with-exception-handler
    (lambda (c) 42)
    (lambda () (+ (raise-continuable 'x) 1))))
;; "If the handler returns, a secondary exception is raised" (6.11 raise)
(test-equal "handler return from raise triggers secondary exception"
  'secondary
  (guard (e (#t 'secondary))
    (with-exception-handler
      (lambda (c) 'returned)
      (lambda () (raise 'first) 'not-reached))))

;; guard body escape via call/cc still runs normally
(test-equal "call/cc escape from guard body" 'escaped
  (call-with-current-continuation
    (lambda (esc)
      (guard (e (#t 'caught))
        (esc 'escaped)))))

;;; --- dynamic-wind + guard: after runs when an exception unwinds ---
(define gw-trace '())
(test-equal "after thunk runs when exception unwinds through wind"
  '(before after caught)
  (begin
    (set! gw-trace '())
    (let ((r (guard (e (#t 'caught))
               (dynamic-wind
                 (lambda () (set! gw-trace (cons 'before gw-trace)))
                 (lambda () (raise 'boom))
                 (lambda () (set! gw-trace (cons 'after gw-trace)))))))
      (reverse (cons r gw-trace)))))

(let ((runner (test-runner-current)))
  (test-end "r7rs-continuation-gaps")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
