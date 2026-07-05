;; R7RS section 3.5 (proper tail recursion) conformance gap tests — Phase 4A.
;; Syntactic tail contexts. Companion file r7rs-tail-procedures-gaps.scm
;; covers the required tail-calling procedures and binding-form bodies with
;; per-iteration allocation (split so each file stays inside run-all.sh's
;; 60s timeout on Debug CI builds).
;;
;; N is sized to prove tail-call optimization, not to stress: a non-tail
;; implementation exhausts the register file between 16k and 20k active
;; frames (probed empirically; the frame stack itself caps at 32768), so
;; 25000 iterations fail without TCO while staying fast in Debug builds.
;; Spec references cite docs/errata-corrected-r7rs.pdf section 3.5 (pp. 11-12).

(import (scheme base) (scheme case-lambda) (scheme write)
        (scheme process-context) (srfi 64))

(test-begin "r7rs-tail-position-gaps")

(define N 25000)

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

;; --- begin: tail sequence ---
(define (loop-begin n) (if (= n 0) 'done (begin 'side (loop-begin (- n 1)))))
(test-equal "begin tail sequence" 'done (loop-begin N))

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

(let ((runner (test-runner-current)))
  (test-end "r7rs-tail-position-gaps")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
