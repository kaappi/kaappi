;; SRFI-210 (procedures and syntax for multiple values) tests — Phase 3d
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi210.scm

(import (scheme base) (srfi 195) (srfi 210) (chibi test))

(test-begin "srfi-210")

;;; --- syntax ---
(test '(1 2) (with-values (values 1 2) list))
(test 3 (with-values (values 1 2) +))

(test '(1 2 3) (list/mv 1 (values 2 3)))
(test '(1 2) (list/mv (values 1 2)))
(test #(1 2 3) (vector/mv 1 (values 2 3)))
(test 6 (apply/mv + 1 (values 2 3)))
(test '(1 2 3 4) (call/mv list (values 1 2) (values 3 4)))
(test 'b (value/mv 1 'a (values 'b 'c)))
(test 2 (coarity (values 1 2)))
(test 0 (coarity (values)))
(test 1 (coarity 42))

;; case-receive dispatches on value count
(test 'one (case-receive (values 1) ((a) 'one) ((a b) 'two) (else 'many)))
(test 'two (case-receive (values 1 2) ((a) 'one) ((a b) 'two) (else 'many)))
(test 'many (case-receive (values 1 2 3) ((a) 'one) ((a b) 'two) (else 'many)))

;; set!-values assigns existing variables:
;; FAIL: #1224 (set!-values is a no-op — assigns the consumer's own params)
;; (define sv-a 0)
;; (define sv-b 0)
;; (set!-values (sv-a sv-b) (values 10 20))
;; (test '(10 20) (list sv-a sv-b))

;; bind/mv chains a producer through transducers
(test 3 (bind/mv (values 1 2) +))

;;; --- procedures ---
(test '(1 2) (with-values (list-values '(1 2)) list))
(test '(1 2) (with-values (vector-values #(1 2)) list))
(test '(7) (with-values (box-values (box 7)) list))
(test '(1 2) (with-values (identity 1 2) list))
(test 5 (identity 5))

(test 9 ((compose-left (lambda (x) (+ x 1)) (lambda (x) (* x 3))) 2))
(test 7 ((compose-right (lambda (x) (+ x 1)) (lambda (x) (* x 3))) 2))
(test '(2 4) (with-values ((map-values (lambda (x) (* 2 x))) 1 2) list))

(test 6 (bind 5 (lambda (x) (+ x 1))))
(test 3 (bind/list '(1 2) +))
(test 3 (bind/box (box (values 1 2)) +))

;;; --- value: (value index obj0 ... objn-1) returns obj_index ---
;; FAIL: #1218 (value returns its first argument instead of the index-th object)
;; (test 'b (value 1 'a 'b))
;; FAIL: #1218 (value returns its first argument instead of the index-th object)
;; (test 'x (value 0 'x))
;; FAIL: #1218 (box/mv is not exported)
;; (test '(1 2 3) (unbox (box/mv 1 (values 2 3))))

(test-end "srfi-210")
