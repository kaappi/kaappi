(import (scheme base) (scheme write))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))
(define (check-true name val)
  (if val (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))
(define (check-false name val)
  (if (not val) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

;;; ---- Import with only ----
(import (only (scheme base) + - * /))
(check "import only +" (+ 1 2) 3)
(check "import only *" (* 3 4) 12)

;;; ---- Import with except ----
(import (except (scheme base) map for-each))
(check "import except +" (+ 10 20) 30)

;;; ---- Import with prefix ----
(import (prefix (scheme write) w:))
(let ((p (open-output-string)))
  (w:display "hello" p)
  (check "import prefix" (get-output-string p) "hello"))

;;; ---- Import with rename ----
(import (rename (scheme base) (+ plus) (- minus)))
(check "import rename plus" (plus 1 2) 3)
(check "import rename minus" (minus 10 3) 7)

;;; ---- Import multiple libraries ----
(import (scheme base) (scheme write) (scheme read) (scheme char))
(check-true "multi import char-alphabetic?" (char-alphabetic? #\a))

;;; ---- cond-expand features ----
(check "cond-expand r7rs" (cond-expand (r7rs 'yes) (else 'no)) 'yes)
(check "cond-expand kaappi" (cond-expand (kaappi 'yes) (else 'no)) 'yes)
(check "cond-expand unknown" (cond-expand (nonexistent-feature 'yes) (else 'no)) 'no)
(check "cond-expand and" (cond-expand ((and r7rs kaappi) 'yes) (else 'no)) 'yes)
(check "cond-expand and fail" (cond-expand ((and r7rs nonexistent) 'yes) (else 'no)) 'no)
(check "cond-expand or" (cond-expand ((or nonexistent r7rs) 'yes) (else 'no)) 'yes)
(check "cond-expand or fail" (cond-expand ((or nonexistent1 nonexistent2) 'yes) (else 'no)) 'no)
(check "cond-expand not" (cond-expand ((not nonexistent) 'yes) (else 'no)) 'yes)
(check "cond-expand not fail" (cond-expand ((not r7rs) 'yes) (else 'no)) 'no)
(check "cond-expand library" (cond-expand ((library (scheme base)) 'yes) (else 'no)) 'yes)
(check "cond-expand library miss" (cond-expand ((library (nonexistent lib)) 'yes) (else 'no)) 'no)

;;; ---- define-library ----
(define-library (test cov-lib1)
  (export cov-val cov-fn)
  (begin
    (define cov-val 42)
    (define (cov-fn x) (* x 2))))
(import (test cov-lib1))
(check "define-library val" cov-val 42)
(check "define-library fn" (cov-fn 5) 10)

;;; ---- define-library with cond-expand ----
(define-library (test cov-lib2)
  (export cov-feature)
  (cond-expand
    (r7rs (begin (define cov-feature 'r7rs)))
    (else (begin (define cov-feature 'other)))))
(import (test cov-lib2))
(check "define-library cond-expand" cov-feature 'r7rs)

;;; ---- define-library with import ----
(define-library (test cov-lib3)
  (import (scheme base))
  (export cov-list)
  (begin
    (define cov-list (list 1 2 3))))
(import (test cov-lib3))
(check "define-library with import" cov-list '(1 2 3))

;;; ---- define-library with rename export ----
;; rename export may use different syntax; skip if not supported

;;; ---- Import SRFI libraries (triggers file loading) ----
(import (srfi 1))
(check "srfi 1 loaded" (iota 3) '(0 1 2))

(import (srfi 27))
(check-true "srfi 27 loaded" (random-source? default-random-source))

;;; ---- define-values ----
(define-values (dv-x dv-y dv-z) (values 10 20 30))
(check "define-values x" dv-x 10)
(check "define-values y" dv-y 20)
(check "define-values z" dv-z 30)

;;; ---- Interaction environment ----
(check-true "interaction-environment" (not (eq? (interaction-environment) #f)))

;;; ---- eval with different environments ----
(check "eval scheme base" (eval '(+ 1 2) (environment '(scheme base))) 3)

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "Library coverage tests failed" fail))
