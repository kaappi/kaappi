;; R7RS section 3.5 (proper tail recursion) gap tests, part 2 — Phase 4A.
;; Required tail-calling procedures (apply, call-with-values, call/cc, eval)
;; and binding forms whose loops allocate per iteration (let-values,
;; let-syntax). Split from r7rs-tail-position-gaps.scm so each file stays
;; inside run-all.sh's 60s timeout on Debug CI builds — let-values costs
;; ~0.6ms/iteration there.
;;
;; N = 25000 proves TCO: a non-tail implementation exhausts the register
;; file between 16k and 20k active frames (probed empirically).
;; Spec references cite docs/errata-corrected-r7rs.pdf section 3.5 (p. 12).

(import (scheme base) (scheme eval) (scheme repl) (scheme write)
        (scheme process-context) (srfi 64))

(test-begin "r7rs-tail-procedures-gaps")

(define N 25000)

;; --- let-values / let*-values: tail body ---
(define (loop-lv n)
  (if (= n 0) 'done
      (let-values (((m) (values (- n 1)))) (loop-lv m))))
(test-equal "let-values body tail" 'done (loop-lv N))

;; FAIL: #1241 (let*-values body re-enters the VM natively; panics ~1024 deep)
;; (define (loop-lsv n)
;;   (if (= n 0) 'done
;;       (let*-values (((m) (values (- n 1))) ((m2) (values m))) (loop-lsv m2))))
;; (test-equal "let*-values body tail" 'done (loop-lsv N))

;; --- let-syntax / letrec-syntax: tail body ---
(define (loop-lsyn n)
  (if (= n 0) 'done
      (let-syntax ((noop (syntax-rules () ((_) #f))))
        (loop-lsyn (- n 1)))))
(test-equal "let-syntax body tail" 'done (loop-lsyn N))
(define (loop-lrsyn n)
  (if (= n 0) 'done
      (letrec-syntax ((noop (syntax-rules () ((_) #f))))
        (loop-lrsyn (- n 1)))))
(test-equal "letrec-syntax body tail" 'done (loop-lrsyn N))

;; --- required tail-calling procedures (p. 12) ---
;; "The first argument passed to apply ... must be called via a tail call."
(define (loop-apply n) (if (= n 0) 'done (apply loop-apply (list (- n 1)))))
(test-equal "apply first-argument tail call" 'done (loop-apply N))

;; "the second argument passed to call-with-values must be called via a
;; tail call"
;; FAIL: #1240 (consumer re-enters the VM natively; panics at depth ~1024)
;; (define (loop-cwv n)
;;   (if (= n 0) 'done
;;       (call-with-values (lambda () (values (- n 1))) loop-cwv)))
;; (test-equal "call-with-values consumer tail call" 'done (loop-cwv N))

;; "The first argument passed ... to call-with-current-continuation must be
;; called via a tail call."
;; FAIL: #1240 (receiver re-enters the VM natively; panics at depth ~1024)
;; (define (loop-cc n)
;;   (if (= n 0) 'done
;;       (call-with-current-continuation
;;         (lambda (k) (loop-cc (- n 1))))))
;; (test-equal "call/cc receiver tail call" 'done (loop-cc N))

;; "eval must evaluate its first argument as if it were in tail position
;; within the eval procedure."
;; FAIL: #1240 (eval re-enters the VM natively; panics at depth ~1024)
;; (define (loop-eval n)
;;   (if (= n 0) 'done
;;       (eval (list 'loop-eval (- n 1)) (interaction-environment))))
;; (test-equal "eval tail evaluation" 'done (loop-eval N))

(let ((runner (test-runner-current)))
  (test-end "r7rs-tail-procedures-gaps")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
