;; SRFI-235 (combinators) conformance tests — audit Phase 3e
;; 24 of 36 exports are missing and all-of/conjoin have return-value
;; deviations (#1221); tests cover the present surface.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi235.scm

(import (scheme base) (srfi 235) (chibi test))

(test-begin "srfi-235")

;;; --- constantly / complement ---
(test 7 ((constantly 7) 'ignored 'args))
(test '(1 2) (call-with-values (lambda () ((constantly 1 2) 'x)) list))
(test #t ((complement even?) 3))
(test #f ((complement even?) 4))
(test #t ((complement member) 'x '(a b)))

;;; --- swap / flip ---
;; SRFI-235: ((swap proc) obj1 obj2 . objs) => (apply proc obj2 obj1 objs)
(test '(2 . 1) ((swap cons) 1 2))
(test '(2 1 3 4) ((swap list) 1 2 3 4))
;; SRFI-235: ((flip proc) . objs) => (apply proc (reverse objs))
(test '(3 2 1) ((flip list) 1 2 3))
(test '(2 . 1) ((flip cons) 1 2))

;;; --- on ---
;; SRFI-235: ((on reducer mapper) obj ...) applies mapper to each obj then
;; reducer to the results
(test 5 ((on + car) '(2 x) '(3 y)))
(test #t ((on = car) '(1 a) '(1 b)))

;;; --- each-of ---
(let ((acc '()))
  (((lambda ps (apply each-of ps))
    (lambda (x) (set! acc (cons (list 'a x) acc)))
    (lambda (x) (set! acc (cons (list 'b x) acc))))
   7)
  (test '((a 7) (b 7)) (reverse acc)))

;;; --- all-of / any-of ---
(test #t ((all-of even?) '(2 4 6)))
(test #f ((all-of even?) '(2 3)))
(test #t ((all-of even?) '()))
(test #t ((any-of even?) '(1 2)))
(test #f ((any-of even?) '(1 3)))
(test #f ((any-of even?) '()))
;; SRFI-235: all-of "returns last call result" when all satisfied
;; FAIL: #1221 (all-of returns #t instead of the last predicate result)
;; (test 2 ((all-of (lambda (x) x)) '(1 2)))

;;; --- conjoin / disjoin ---
(test #t ((conjoin number? odd?) 3))
(test #f ((conjoin number? odd?) 4))
(test #f ((conjoin number? odd?) 'x))
(test #t ((conjoin) 'anything))
(test #t ((disjoin number? symbol?) 'x))
(test #t ((disjoin number? symbol?) 1))
(test #f ((disjoin number? symbol?) "s"))
(test #f ((disjoin) 'anything))
;; FAIL: #1221 (conjoin returns #t instead of the last predicate value)
;; (test 5 ((conjoin (lambda (x) x)) 5))

;;; --- missing exports ---
;; FAIL: #1221 (left-section, right-section, apply-chain, group-by,
;;              begin-procedure, always, never, boolean, ... not exported)
;; (test 7 ((left-section + 3) 4))
;; (test #t (always 'x))

(test-end "srfi-235")
