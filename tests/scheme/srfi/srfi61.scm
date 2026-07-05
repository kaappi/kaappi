;; SRFI-61 (a more general cond clause) conformance tests — audit Phase 3d
;; The library is currently an empty stub (#1206); base cond still works.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi61.scm

(import (scheme base) (srfi 61) (chibi test))

(test-begin "srfi-61")

;; importing (srfi 61) must not break ordinary cond
(test 'a (cond (#t 'a) (else 'b)))
(test 'b (cond (#f 'a) (else 'b)))
(test 2 (cond ((assv 1 '((1 . 2))) => cdr) (else 'no)))

;;; --- the SRFI-61 (generator guard => receiver) clause ---
;; "⟨generator⟩ is evaluated. It may return arbitrarily many values. ⟨Guard⟩
;;  is applied to [those values] ... If ⟨guard⟩ returns a true value ...
;;  ⟨receiver⟩ is applied with an equivalent argument list."
;; FAIL: #1206 (SRFI-61 general cond clause not implemented; library is empty)
;; (test 3 (cond ((values 1 2) (lambda (a b) #t) => (lambda (a b) (+ a b)))
;;               (else 'no)))
;; FAIL: #1206 (SRFI-61 general cond clause not implemented; library is empty)
;; (test 'skipped (cond ((values 1 2) (lambda (a b) #f) => (lambda (a b) 'used))
;;                      (else 'skipped)))

(test-end "srfi-61")
