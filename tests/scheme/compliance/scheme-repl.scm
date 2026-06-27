;; Test (scheme repl) library — R7RS §6.4

(import (scheme base) (scheme write) (scheme repl))

;; interaction-environment should be accessible
(display (procedure? interaction-environment))
(newline)
;; Expected: #t

;; interaction-environment returns an environment
(let ((env (interaction-environment)))
  (display (not (eq? env #f))))
(newline)
;; Expected: #t

(display "scheme-repl-ok")
(newline)
