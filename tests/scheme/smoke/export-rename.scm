;; Regression test for #429: export (rename old new) uses wrong syntax
;; R7RS specifies flat syntax: (export (rename internal external))

(import (scheme base) (scheme write))

;; Test with a library defined via define-library using rename exports
(define-library (test rename-lib)
  (export (rename internal-val external-val)
          (rename helper-fn public-fn)
          plain-val)
  (import (scheme base))
  (begin
    (define internal-val 42)
    (define helper-fn (lambda (x) (* x 2)))
    (define plain-val 99)))

(import (test rename-lib))

(unless (= external-val 42)
  (error "renamed export external-val should be 42" external-val))

(unless (= (public-fn 5) 10)
  (error "renamed export public-fn should work"))

(unless (= plain-val 99)
  (error "plain export should still work"))

(display "PASS")
(newline)
