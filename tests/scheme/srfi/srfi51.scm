;; SRFI-51 (Handling Rest List) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi51.scm

(import (scheme base) (scheme process-context) (srfi 51) (srfi 64))

(test-begin "srfi-51")

(define rest-list (list 'x 1))

;;; --- rest-values: no options / default limit ---
(test-equal "rest-values: bare rest list, all values pass through" '(x 1)
  (call-with-values (lambda () (rest-values rest-list)) list))
(test-equal "rest-values: positive limit at or above the rest length" '(x 1)
  (call-with-values (lambda () (rest-values rest-list 2)) list))

;;; --- rest-values: negative/`-` limit (no checking, arbitrary defaults) ---
;; the spec's own example
(test-equal "rest-values: spec's own `-` example" '(x 1 "str")
  (call-with-values (lambda () (rest-values rest-list - 'y 100 "str")) list))

;;; --- rest-values: too many arguments/defaults raise an error ---
(test-assert "rest-values: too many arguments signals an error"
  (guard (e (#t #t)) (rest-values 'caller rest-list 1 (list 'x 'y 'z)) #f))
(test-assert "rest-values: too many defaults signals an error"
  (guard (e (#t #t)) (rest-values rest-list -2 'y 3 1) #f))
(test-assert "rest-values: an unmatched argument (against a membership list) signals an error"
  (guard (e (#t #t)) (rest-values rest-list 2 (list 'y 'z) (cons 100 number?)) #f))

;;; --- rest-values: boolean mode (#t / #f) ---
;; the spec's own examples
(test-equal "rest-values: #t mode, spec's own example" '(1 "str" x)
  (call-with-values
    (lambda () (rest-values rest-list #t (cons 100 number?) (cons "str" string?) (list 'x 'y 'z)))
    list))
(test-equal "rest-values: #f mode, spec's own example" '(1 "str" y x)
  (call-with-values
    (lambda () (rest-values rest-list #f (cons 100 number?) (cons "str" string?) (list 'y 'z)))
    list))
(test-assert "rest-values: #t mode signals an error on leftover unmatched rest elements"
  (guard (e (#t #t))
    (call-with-values (lambda () (rest-values (list 'x 1 'extra) #t (cons 100 number?))) list)
    #f))

;;; --- rest-values: positive/`+` limit mode (checked, matched defaults) ---
(test-equal "rest-values: positive-limit mode with a matching membership default"
  '(x 1)
  (call-with-values (lambda () (rest-values rest-list 2 (list 'x 'w) (cons 1 number?))) list))
(test-equal "rest-values: positive-limit mode fills in a missing trailing default"
  '(x default)
  (call-with-values (lambda () (rest-values (list 'x) + (list 'x 'w) (cons 'default symbol?))) list))

;;; --- arg-and / arg-ands ---
;; per the spec, <variable> must be an identifier -- (symbol? 'arg) is
;; how the macro guards against passing a literal by mistake -- so every
;; check here binds a local variable first, matching the spec's own
;; (arg-and num (number? num) (< num 2)) shape. Like `and`, the return
;; value is whichever check ran last (here, always a boolean) -- the
;; meaningful behavior to test is whether it errors, not the exact value.
(test-equal "arg-and: passes through (as #t) when all checks hold" #t (let ((num 1)) (arg-and num (number? num) (< num 2))))
(test-assert "arg-and: signals an error when a check fails"
  (guard (e (#t #t)) (let ((num 5)) (arg-and num (number? num) (< num 2))) #f))
(test-equal "arg-ands: all groups pass"
  #t
  (let ((n1 1) (n2 2)) (arg-ands (n1 (number? n1)) (n2 (number? n2) (< n1 n2)))))
(test-assert "arg-ands: common caller form signals on failure"
  (guard (e (#t #t)) (let ((n1 1) (n2 5)) (arg-ands common 'my-proc (n1 (number? n1)) (n2 (< n2 2)))) #f))

;;; --- arg-or / arg-ors ---
;; like `or`, passing (no error) means every check was false, so the
;; overall result is #f here regardless of the variable's own value.
(test-equal "arg-or: passes through (as #f) when all checks are false" #f (let ((n 1)) (arg-or n (string? n))))
(test-assert "arg-or: signals an error when a check is true"
  (guard (e (#t #t)) (let ((n 5)) (arg-or n (number? n))) #f))
(test-equal "arg-ors: all groups pass" #f (let ((n1 1) (n2 2)) (arg-ors (n1 (string? n1)) (n2 (string? n2)))))

;;; --- err-and / err-ands ---
(test-equal "err-and: passes through when all expressions are true" #t (err-and 'caller (< 1 2) (< 3 4)))
(test-assert "err-and: signals an error on a false expression"
  (guard (e (#t #t)) (err-and 'caller (< 1 2) (> 1 2)) #f))
(test-equal "err-ands: all groups pass" #t (err-ands ('c1 (< 1 2)) ('c2 (< 3 4))))

;;; --- err-or / err-ors ---
(test-equal "err-or: passes through (as #f) when all expressions are false" #f (err-or 'caller (> 1 2)))
(test-assert "err-or: signals an error on a true expression"
  (guard (e (#t #t)) (err-or 'caller (< 1 2)) #f))
(test-equal "err-ors: all groups pass" #f (err-ors ('c1 (> 1 2)) ('c2 (> 3 4))))

(let ((runner (test-runner-current)))
  (test-end "srfi-51")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
