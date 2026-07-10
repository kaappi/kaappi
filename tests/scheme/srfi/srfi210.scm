;; SRFI-210 (procedures and syntax for multiple values) tests — Phase 3d
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi210.scm

(import (scheme base) (srfi 195) (srfi 210) (scheme process-context) (srfi 64))

(test-begin "srfi-210")

;;; --- syntax ---
(test-equal '(1 2) (with-values (values 1 2) list))
(test-equal 3 (with-values (values 1 2) +))

(test-equal '(1 2 3) (list/mv 1 (values 2 3)))
(test-equal '(1 2) (list/mv (values 1 2)))
(test-equal #(1 2 3) (vector/mv 1 (values 2 3)))
(test-equal 6 (apply/mv + 1 (values 2 3)))
(test-equal '(1 2 3 4) (call/mv list (values 1 2) (values 3 4)))
(test-equal 'b (value/mv 1 'a (values 'b 'c)))
(test-equal 2 (coarity (values 1 2)))
(test-equal 0 (coarity (values)))
(test-equal 1 (coarity 42))

;; case-receive dispatches on value count
(test-equal 'one (case-receive (values 1) ((a) 'one) ((a b) 'two) (else 'many)))
(test-equal 'two (case-receive (values 1 2) ((a) 'one) ((a b) 'two) (else 'many)))
(test-equal 'many (case-receive (values 1 2 3) ((a) 'one) ((a b) 'two) (else 'many)))

;; set!-values assigns existing variables:
(define sv-a 0)
(define sv-b 0)
(set!-values (sv-a sv-b) (values 10 20))
(test-equal '(10 20) (list sv-a sv-b))

;; set!-values with single variable
(define sv-c 0)
(set!-values (sv-c) (values 99))
(test-equal 99 sv-c)

;; set!-values overwrites previous set!-values results
(set!-values (sv-a sv-b) (values 30 40))
(test-equal '(30 40) (list sv-a sv-b))

;; bind/mv chains a producer through transducers
(test-equal 3 (bind/mv (values 1 2) +))

;;; --- procedures ---
(test-equal '(1 2) (with-values (list-values '(1 2)) list))
(test-equal '(1 2) (with-values (vector-values #(1 2)) list))
(test-equal '(7) (with-values (box-values (box 7)) list))
(test-equal '(1 2) (with-values (identity 1 2) list))
(test-equal 5 (identity 5))

(test-equal 9 ((compose-left (lambda (x) (+ x 1)) (lambda (x) (* x 3))) 2))
(test-equal 7 ((compose-right (lambda (x) (+ x 1)) (lambda (x) (* x 3))) 2))
(test-equal '(2 4) (with-values ((map-values (lambda (x) (* 2 x))) 1 2) list))

(test-equal 6 (bind 5 (lambda (x) (+ x 1))))
(test-equal 3 (bind/list '(1 2) +))
(test-equal 3 (bind/box (box (values 1 2)) +))

;;; --- value: (value index obj0 ... objn-1) returns obj_index ---
(test-equal 'b (value 1 'a 'b))
(test-equal 'x (value 0 'x))
(test-equal 'c (value 2 'a 'b 'c))

;;; --- box/mv ---
(test-equal '(1 2 3) (with-values (unbox (box/mv 1 (values 2 3))) list))

(let ((runner (test-runner-current)))
  (test-end "srfi-210")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
