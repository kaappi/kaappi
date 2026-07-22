;; SRFI-165 (The Environment Monad) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi165.scm

(import (scheme base) (scheme process-context) (srfi 165) (srfi 64))

(test-begin "srfi-165")

(define a (make-computation-environment-variable 'a 0 #f))
(define b (make-computation-environment-variable 'b 100 #f))

;;; --- environments ---
(test-assert "computation-environment?: fresh environment" (computation-environment? (make-computation-environment)))
(test-equal "computation-environment-ref: unbound variable returns its default" 0 (computation-environment-ref (make-computation-environment) a))
(test-equal "computation-environment-update: non-destructive, returns a new binding"
  5
  (computation-environment-ref (computation-environment-update (make-computation-environment) a 5) a))
(test-equal "computation-environment-update: original is unaffected"
  0
  (let ((env (make-computation-environment)))
    (computation-environment-update env a 5)
    (computation-environment-ref env a)))
(test-equal "computation-environment-update!: destructive"
  5
  (let ((env (make-computation-environment)))
    (computation-environment-update! env a 5)
    (computation-environment-ref env a)))
(test-equal "computation-environment-copy: sees the same bindings"
  5
  (let* ((env (computation-environment-update (make-computation-environment) a 5))
         (copy (computation-environment-copy env)))
    (computation-environment-ref copy a)))
(test-equal "computation-environment-copy: later mutation of the copy doesn't affect the original"
  5
  (let* ((env (computation-environment-update (make-computation-environment) a 5))
         (copy (computation-environment-copy env)))
    (computation-environment-update! copy a 999)
    (computation-environment-ref env a)))

;;; --- basic computations ---
(test-assert "computation?: true for make-computation" (computation? (make-computation (lambda (compute) 1))))
(test-assert "computation?: false for a plain value" (not (computation? 42)))
(test-equal "computation-pure: yields its argument" 42 (computation-run (computation-pure 42)))
(test-equal "computation-ask: yields the current environment"
  0
  (computation-run (computation-bind (computation-ask) (lambda (env) (computation-pure (computation-environment-ref env a))))))
(test-equal "computation-local: extends the environment for a sub-computation only"
  5
  (computation-run
    (computation-local
      (lambda (env) (computation-environment-update env a 5))
      (computation-bind (computation-ask) (lambda (env) (computation-pure (computation-environment-ref env a)))))))

;; the spec's own example: (if (compute a) 42 (compute b))
(test-equal "make-computation: compute runs a sub-computation and returns its result (true branch)"
  42
  (computation-run (make-computation (lambda (compute) (if (compute (computation-pure #t)) 42 (compute (computation-pure 'else)))))))
(test-equal "make-computation: compute runs a sub-computation and returns its result (false branch)"
  'else
  (computation-run (make-computation (lambda (compute) (if (compute (computation-pure #f)) 42 (compute (computation-pure 'else)))))))

;;; --- default-computation: a bare (non-computation, non-procedure) value gets converted ---
(test-equal "default-computation: converts a bare value via the installed handler"
  84
  (computation-run
    (computation-local
      (lambda (env) (computation-environment-update env default-computation (lambda (v) (computation-pure (* v 2)))))
      (make-computation (lambda (compute) (compute 42))))))

;;; --- derived monadic procedures ---
(test-equal "computation-each: yields the last computation's result" 3 (computation-run (computation-each (computation-pure 1) (computation-pure 2) (computation-pure 3))))
(test-equal "computation-each-in-list" 2 (computation-run (computation-each-in-list (list (computation-pure 1) (computation-pure 2)))))
;; Regression: computation-each with zero computations used to dereference
;; (cdr '()) before the empty-list check could help.
(test-equal "computation-each: zero computations yields zero values, not an error"
  '()
  (call-with-values (lambda () (computation-run (computation-each))) list))
(test-equal "computation-each-in-list: zero computations yields zero values, not an error"
  '()
  (call-with-values (lambda () (computation-run (computation-each-in-list '()))) list))
(test-equal "computation-bind: single proc" 10 (computation-run (computation-bind (computation-pure 5) (lambda (x) (computation-pure (* x 2))))))
(test-equal "computation-bind: left-associates over multiple procs"
  11
  (computation-run (computation-bind (computation-pure 5) (lambda (x) (computation-pure (* x 2))) (lambda (y) (computation-pure (+ y 1))))))
(test-equal "computation-bind: zero procs is the computation itself" 7 (computation-run (computation-bind (computation-pure 7))))
(test-equal "computation-sequence: yields a list of all results" '(1 2 3) (computation-run (computation-sequence (list (computation-pure 1) (computation-pure 2) (computation-pure 3)))))

;; computation-forked: earlier branches run on discarded copies of the environment
(test-equal "computation-forked: earlier branches' environment mutations don't leak into the final one"
  0
  (computation-run
    (computation-bind
      (computation-forked
        (computation-local (lambda (env) (computation-environment-update env a 999)) (computation-ask))
        (computation-ask))
      (lambda (env) (computation-pure (computation-environment-ref env a))))))
(test-equal "computation-forked: yields the last computation's result, run on the real environment"
  5
  (computation-run
    (computation-local
      (lambda (env) (computation-environment-update env a 5))
      (computation-bind
        (computation-forked
          (computation-local (lambda (env) (computation-environment-update env a 999)) (computation-pure 'discarded))
          (computation-ask))
        (lambda (env) (computation-pure (computation-environment-ref env a)))))))
;; Regression: same (cdr '()) bug as computation-each, for zero computations.
(test-equal "computation-forked: zero computations yields zero values, not an error"
  '()
  (call-with-values (lambda () (computation-run (computation-forked))) list))

;; computation-bind/forked runs `comp` on a copy: comp's own environment
;; mutation (via computation-local) never escapes, since comp yields a
;; plain value here rather than the environment itself, so the outer
;; ask afterward sees the real, unmutated environment.
(test-equal "computation-bind/forked: comp's environment mutation doesn't leak to what follows"
  '(inner-result 0)
  (computation-run
    (computation-bind
      (computation-bind/forked
        (computation-local (lambda (env) (computation-environment-update env a 999)) (computation-pure 'inner-result))
        (lambda (v) (computation-pure v)))
      (lambda (v) (computation-bind (computation-ask) (lambda (env) (computation-pure (list v (computation-environment-ref env a)))))))))

;;; --- derived syntax ---
(test-equal "computation-fn: explicit (var init) clauses"
  7
  (computation-run
    (computation-local
      (lambda (env) (computation-environment-update env a 3 b 4))
      (computation-fn ((x a) (y b)) (computation-pure (+ x y))))))
(test-equal "computation-fn: bare-variable shorthand means (variable variable)"
  7
  (computation-run
    (computation-local
      (lambda (env) (computation-environment-update env a 3 b 4))
      (computation-fn (a b) (computation-pure (+ a b))))))
(test-equal "computation-fn: unbound variable falls back to its default"
  100
  (computation-run (computation-fn (b) (computation-pure b))))

(test-equal "computation-with: non-destructively extends, yields the last expr's result"
  10
  (computation-run (computation-with ((a 10)) (computation-bind (computation-ask) (lambda (env) (computation-pure (computation-environment-ref env a)))))))
(test-equal "computation-with: sequences multiple expressions, yielding the last"
  2
  (computation-run (computation-with ((a 1)) (computation-pure 1) (computation-pure 2))))

(test-equal "computation-with!: destructively updates the current environment"
  20
  (computation-run
    (make-computation
      (lambda (compute)
        (compute (computation-with! (a 20)))
        (compute (computation-bind (computation-ask) (lambda (env) (computation-pure (computation-environment-ref env a)))))))))

(let ((runner (test-runner-current)))
  (test-end "srfi-165")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
