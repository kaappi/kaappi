;;; Eval library compliance tests (R7RS 6.5)
(import (scheme base) (scheme eval) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "eval")

;; --- eval basic ---
(test-group "eval basic"
  (test-eqv "eval arithmetic" 3 (eval '(+ 1 2))))

;; --- eval with environment ---
(test-group "eval with environment"
  (test-eqv "eval with scheme base environment" 12 (eval '(* 3 4) (environment '(scheme base)))))

;; --- eval rejects non-environment second argument (#1270) ---
(test-group "eval bad env type"
  (test-assert "eval with fixnum env raises error"
    (guard (e (#t #t))
      (eval '(+ 1 2) 42)
      #f))
  (test-assert "eval with string env raises error"
    (guard (e (#t #t))
      (eval '(+ 1 2) "not-an-env")
      #f))
  (test-assert "eval with boolean env raises error"
    (guard (e (#t #t))
      (eval '(+ 1 2) #t)
      #f))
  (test-assert "eval with bad env in tail position raises error"
    (guard (e (#t #t))
      ((lambda () (eval '(+ 1 2) 42)))
      #f)))

;; --- eval list construction ---
(test-group "eval list"
  (test-equal "eval quoted list" '(1 2 3) (eval '(list 1 2 3))))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "eval")
(if (> %test-fail-count 0) (exit 1))
