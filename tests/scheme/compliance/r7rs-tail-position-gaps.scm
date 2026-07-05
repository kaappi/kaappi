;; R7RS section 3.5 (proper tail recursion) conformance gap tests — Phase 4A.
;; Each loop runs enough iterations that a non-tail-call implementation
;; exhausts the frame stack (grows to 32768); success proves the position
;; is compiled as a tail call. Spec references cite
;; docs/errata-corrected-r7rs.pdf section 3.5 (pp. 11-12).

(import (scheme base) (scheme case-lambda) (scheme eval) (scheme repl)
        (scheme write) (scheme process-context) (srfi 64))

(test-begin "r7rs-tail-position-gaps")

(define N 1000000)     ; cheap forms
(define N-heavy 100000) ; forms with per-iteration allocation/capture cost

;; --- if: both branches are tail contexts ---
(define (loop-if-then n) (if (> n 0) (loop-if-then (- n 1)) 'done))
(define (loop-if-else n) (if (= n 0) 'done (loop-if-else (- n 1))))
(test-equal "if consequent tail" 'done (loop-if-then N))
(test-equal "if alternate tail" 'done (loop-if-else N))

;; --- cond: clause tail sequence, else tail sequence, => receiver call ---
(define (loop-cond n)
  (cond ((= n 0) 'done)
        (else (loop-cond (- n 1)))))
(test-equal "cond clause + else tail" 'done (loop-cond N))

;; "the (implied) call to the procedure that results from the evaluation of
;; <expression2> is in a tail context" (p. 12)
(define (loop-cond-arrow n)
  (cond ((= n 0) 'done)
        ((- n 1) => loop-cond-arrow)))
(test-equal "cond => receiver call tail" 'done (loop-cond-arrow N))

;; --- case: clause tail sequence and else ---
(define (loop-case n)
  (case n
    ((0) 'done)
    (else (loop-case (- n 1)))))
(test-equal "case clause + else tail" 'done (loop-case N))

;; --- and / or: final expression ---
(define (loop-and n) (and #t (if (= n 0) 'done (loop-and (- n 1)))))
(test-equal "and final expression tail" 'done (loop-and N))
(define (loop-or n) (or (= n 0) (loop-or (- n 1))))
(test-equal "or final expression tail" #t (loop-or N))

;; --- when / unless: tail sequence ---
(define (loop-when n) (if (= n 0) 'done (when #t 'ignored (loop-when (- n 1)))))
(test-equal "when tail sequence" 'done (loop-when N))
(define (loop-unless n) (if (= n 0) 'done (unless #f 'ignored (loop-unless (- n 1)))))
(test-equal "unless tail sequence" 'done (loop-unless N))

;; --- let family: tail body ---
(define (loop-let n) (if (= n 0) 'done (let ((m (- n 1))) (loop-let m))))
(test-equal "let body tail" 'done (loop-let N))
(define (loop-let* n) (if (= n 0) 'done (let* ((m (- n 1)) (m2 m)) (loop-let* m2))))
(test-equal "let* body tail" 'done (loop-let* N))
(define (loop-letrec n) (if (= n 0) 'done (letrec ((m (- n 1))) (loop-letrec m))))
(test-equal "letrec body tail" 'done (loop-letrec N))
(define (loop-letrec* n) (if (= n 0) 'done (letrec* ((m (- n 1))) (loop-letrec* m))))
(test-equal "letrec* body tail" 'done (loop-letrec* N))
(test-equal "named let self-call tail" 'done
  (let lp ((n N)) (if (= n 0) 'done (lp (- n 1)))))

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

;; --- begin: tail sequence ---
(define (loop-begin n) (if (= n 0) 'done (begin 'side (loop-begin (- n 1)))))
(test-equal "begin tail sequence" 'done (loop-begin N))

;; --- let-syntax / letrec-syntax: tail body ---
(define (loop-lsyn n)
  (if (= n 0) 'done
      (let-syntax ((noop (syntax-rules () ((_) #f))))
        (loop-lsyn (- n 1)))))
(test-equal "let-syntax body tail" 'done (loop-lsyn N-heavy))
(define (loop-lrsyn n)
  (if (= n 0) 'done
      (letrec-syntax ((noop (syntax-rules () ((_) #f))))
        (loop-lrsyn (- n 1)))))
(test-equal "letrec-syntax body tail" 'done (loop-lrsyn N-heavy))

;; --- do: iteration itself and the result tail sequence ---
(test-equal "do iteration is space-bounded" 'done
  (do ((i N (- i 1))) ((= i 0) 'done)))
(define (loop-do-result n)
  (do ((once #t #f)) (#t (if (= n 0) 'done (loop-do-result (- n 1))))))
(test-equal "do result expressions tail" 'done (loop-do-result N))

;; --- case-lambda: every clause body ---
(define cl-loop
  (case-lambda
    ((n) (if (= n 0) 'done (cl-loop (- n 1) 'extra)))
    ((n extra) (if (= n 0) 'done (cl-loop (- n 1))))))
(test-equal "case-lambda clause bodies tail" 'done (cl-loop N))

;; --- required tail-calling procedures (p. 12) ---
;; "The first argument passed to apply ... must be called via a tail call."
(define (loop-apply n) (if (= n 0) 'done (apply loop-apply (list (- n 1)))))
(test-equal "apply first-argument tail call" 'done (loop-apply N-heavy))

;; "the second argument passed to call-with-values must be called via a
;; tail call"
;; FAIL: #1240 (consumer re-enters the VM natively; panics at depth ~1024)
;; (define (loop-cwv n)
;;   (if (= n 0) 'done
;;       (call-with-values (lambda () (values (- n 1))) loop-cwv)))
;; (test-equal "call-with-values consumer tail call" 'done (loop-cwv N-heavy))

;; "The first argument passed ... to call-with-current-continuation must be
;; called via a tail call."
;; FAIL: #1240 (receiver re-enters the VM natively; panics at depth ~1024)
;; (define (loop-cc n)
;;   (if (= n 0) 'done
;;       (call-with-current-continuation
;;         (lambda (k) (loop-cc (- n 1))))))
;; (test-equal "call/cc receiver tail call" 'done (loop-cc N-heavy))

;; "eval must evaluate its first argument as if it were in tail position
;; within the eval procedure."
;; FAIL: #1240 (eval re-enters the VM natively; panics at depth ~1024)
;; (define (loop-eval n)
;;   (if (= n 0) 'done
;;       (eval (list 'loop-eval (- n 1)) (interaction-environment))))
;; (test-equal "eval tail evaluation" 'done (loop-eval 20000))

(let ((runner (test-runner-current)))
  (test-end "r7rs-tail-position-gaps")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
