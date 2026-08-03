;; Regression test for #51: quasiquote + unquote-splicing must process nested unquotes

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "quasiquote-splice-nested")

(define c 99)
(define d (list 7 8))

(test-equal "nested unquote with splice"
  '(a (b 99) 7 8)
  `(a (b ,c) ,@d))

(test-equal "deeply nested unquote with splice"
  '(x (y (z 99)) 7 8)
  `(x (y (z ,c)) ,@d))

(test-equal "multiple nested unquotes with splice"
  '((1 99) (2 99) 7 8)
  `((1 ,c) (2 ,c) ,@d))

(test-equal "no splice still works"
  '(a (b 99))
  `(a (b ,c)))

(test-equal "splice only"
  '(7 8)
  `(,@d))

(let ((runner (test-runner-current)))
  (test-end "quasiquote-splice-nested")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
