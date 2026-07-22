;; SRFI-161 (Unifiable Boxes) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi161.scm

(import (scheme base) (scheme process-context) (srfi 161) (srfi 64))

(test-begin "srfi-161")

(test-assert "ubox?: true for a ubox" (ubox? (ubox 1)))
(test-assert "ubox?: false for other values" (not (ubox? 42)))
(test-equal "ubox-ref: returns the initial value" 5 (ubox-ref (ubox 5)))

(let ((b (ubox 1)))
  (ubox-set! b 2)
  (test-equal "ubox-set!: updates the value" 2 (ubox-ref b)))

(let ((b1 (ubox 1)) (b2 (ubox 2)))
  (test-assert "ubox=?: distinct boxes are not equal" (not (ubox=? b1 b2)))
  (test-assert "ubox=?: a box equals itself" (ubox=? b1 b1)))

;;; --- ubox-union! ---
(let ((b1 (ubox 'a)) (b2 (ubox 'b)))
  (ubox-union! b1 b2)
  (test-assert "ubox-union!: boxes become equal" (ubox=? b1 b2))
  (test-equal "ubox-union!: shared value visible through either box"
    (ubox-ref b1) (ubox-ref b2)))

;;; --- ubox-link! (result is specifically ubox2's prior value) ---
(let ((b1 (ubox 'a)) (b2 (ubox 'b)))
  (ubox-link! b1 b2)
  (test-assert "ubox-link!: boxes become equal" (ubox=? b1 b2))
  (test-equal "ubox-link!: shared value is b2's prior value" 'b (ubox-ref b1)))

;;; --- ubox-unify! ---
(let ((b1 (ubox 3)) (b2 (ubox 4)))
  (ubox-unify! + b1 b2)
  (test-equal "ubox-unify!: combines via proc" 7 (ubox-ref b1))
  (test-equal "ubox-unify!: visible through the other box too" 7 (ubox-ref b2)))

;;; --- classic union-find usage (from the SRFI's own rationale) ---
(define (make-set x) (ubox x))
(define (uf-union x y) (ubox-link! y x))
(define (uf-find x) (ubox-ref x))

(let* ((a (make-set 'a)) (b (make-set 'b)) (c (make-set 'c)))
  (uf-union a b)
  (uf-union b c)
  (test-assert "union-find: transitively unified" (ubox=? a c))
  (test-equal "union-find: find reflects the union" (uf-find a) (uf-find c)))

;;; --- chained unions keep a single shared class ---
(let* ((b1 (ubox 1)) (b2 (ubox 2)) (b3 (ubox 3)) (b4 (ubox 4)))
  (ubox-union! b1 b2)
  (ubox-union! b3 b4)
  (ubox-union! b1 b3)
  (test-assert "chained union: all four in one class"
    (and (ubox=? b1 b2) (ubox=? b2 b3) (ubox=? b3 b4))))

(let ((runner (test-runner-current)))
  (test-end "srfi-161")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
