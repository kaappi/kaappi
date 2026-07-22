;; SRFI-86 (MU and NU simulating VALUES and CALL-WITH-VALUES) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi86.scm
;;
;; Covers the subset Kaappi implements — see lib/srfi/86.sld's header for
;; the full binding-spec list and what's out of scope (opt/cat/key,
;; and-integration, named alet/alet*, the whole-alet-as-procedure form).

(import (scheme base) (scheme process-context) (srfi 86) (srfi 64))

(test-begin "srfi-86")

;;; --- mu / nu ---
(test-equal "mu: captures arguments for direct call" '(1 2 3) ((mu 1 2 3) list))
(test-equal "nu: captures arguments for apply" '(1 2 3) ((nu 1 '(2 3)) list))
(test-equal "mu vs values: mu produces a procedure, not multiple values" 3 (length ((mu 1 2 3) list)))

;;; --- alet: plain bindings ---
(test-equal "alet: plain single binding" 1 (alet ((a 1)) a))
(test-equal "alet: plain multiple bindings" 3 (alet ((a 1) (b 2)) (+ a b)))

;;; --- alet: multi-value destructure via mu/nu ---
(test-equal "alet: wrapped multi-value binding" '(1 2) (alet ((a b (mu 1 2))) (list a b)))
(test-equal "alet: wrapped single-var (form 3)" 5 (alet (((a) (mu 5))) a))
(test-equal "alet: dotted-rest binding" '(1 (2 3)) (alet (((a . rest) (mu 1 2 3))) (list a rest)))

;; adapted from the spec's own rest-argument example, using the wrapped
;; ((a) (mu 1)) shorthand rather than the unwrapped "a (mu 1 2)" form
;; (form 8, out of scope — see lib/srfi/86.sld's header)
(test-equal "alet: multiple wrapped multi-value bindings"
  '(1 2 3)
  (alet (((a) (mu 1)) ((b c) (mu 2 3))) (list a b c)))

;;; --- alet: escape procedure ---
;; the spec's own worked example, including its side-effect ordering
(let ((log '()))
  (test-equal "alet: escape procedure returns the exit value"
    10
    (alet ((exit) (a 1) (b c (mu 2 3)))
      (set! log (cons (list a b c) log))
      (exit 10)
      (set! log (cons 'unreached log))))
  (test-equal "alet: code after the escape call never runs" '((1 2 3)) log))

;;; --- alet: intervening environment (effects only, no new binding) ---
(let ((log '()))
  (test-equal "alet: intervening environment doesn't bind anything, runs for effect"
    3
    (alet ((a 1) (() (set! log (cons 'ran log))) (b 2)) (+ a b)))
  (test-equal "alet: intervening environment's effect actually ran" '(ran) log))

;;; --- alet: rec (mutually recursive single-value group) ---
(test-equal "alet: rec, self-recursive" 120 (alet ((rec (f (lambda (n) (if (= n 0) 1 (* n (f (- n 1)))))))) (f 5)))
(test-equal "alet: rec, mutually recursive"
  #t
  (alet ((rec (ev? (lambda (n) (if (= n 0) #t (od? (- n 1)))))
              (od? (lambda (n) (if (= n 0) #f (ev? (- n 1)))))))
    (ev? 10)))

;;; --- alet*: sequential visibility ---
(test-equal "alet*: later binding sees an earlier one" 3 (alet* ((a 1) (b (+ a 1))) (+ a b)))
(test-equal "alet*: multi-value binding feeds a later clause" '(1 2 3) (alet* ((a b (mu 1 2)) (c (+ a b))) (list a b c)))

(let ((runner (test-runner-current)))
  (test-end "srfi-86")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
