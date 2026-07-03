;; Test include-library-declarations — R7RS §5.3.2
;;
;; The exports fixture lives in fixtures/ so run-all.sh doesn't execute it
;; as a standalone test — it is only meaningful spliced into define-library.

(define-library (test include-lib-decls)
  (import (scheme base))
  (include-library-declarations "fixtures/include-lib-decls-exports.scm")
  (begin
    (define (my-add a b) (+ a b))
    (define (my-mul a b) (* a b))))

(import (scheme base) (scheme write) (scheme process-context)
        (test include-lib-decls))

(unless (= 7 (my-add 3 4))
  (display "FAIL my-add") (newline)
  (exit 1))

(unless (= 30 (my-mul 5 6))
  (display "FAIL my-mul") (newline)
  (exit 1))

(display "include-lib-decls-ok")
(newline)
