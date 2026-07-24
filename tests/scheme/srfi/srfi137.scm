;; SRFI-137 (Minimal Unique Types) conformance tests.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi137.scm

(import (scheme base) (scheme write) (srfi 64) (srfi 137))

(test-begin "srfi-137")

(define-values (reia-metadata make-reia reia? reia-ref make-reia-subtype) (make-type 'reia))

(test-equal "type-accessor returns the type payload" 'reia (reia-metadata))
(test-assert "constructor + predicate: a fresh instance satisfies its own type" (reia? (make-reia 42)))
(test-equal "accessor reads back the instance payload" 42 (reia-ref (make-reia 42)))
(test-assert "predicate rejects an unrelated value" (not (reia? 5)))
(test-assert "predicate rejects a value from a completely different make-type call"
  (let-values (((m2 make-2 two? ref2 sub2) (make-type 'other)))
    (not (reia? (make-2 1)))))

;; distinctness across calls
(let-values (((a-meta make-a a? a-ref a-sub) (make-type 'a))
             ((b-meta make-b b? b-ref b-sub) (make-type 'b)))
  (test-assert "two make-type calls produce non-interoperable types (a doesn't accept b)" (not (a? (make-b 1))))
  (test-assert "two make-type calls produce non-interoperable types (b doesn't accept a)" (not (b? (make-a 1)))))

;;; --- subtypes -------------------------------------------------------------

(define-values (sub-metadata make-sub sub? sub-ref make-sub-subtype) (make-reia-subtype 'sub-of-reia))

(test-equal "subtype's own type-accessor returns its own payload" 'sub-of-reia (sub-metadata))
(let ((s (make-sub 99)))
  (test-assert "subtype instance satisfies its own predicate" (sub? s))
  (test-assert "subtype instance satisfies the ANCESTOR's predicate too" (reia? s))
  (test-equal "subtype's own accessor reads the instance payload" 99 (sub-ref s))
  (test-equal "ancestor's accessor reads the SAME instance payload" 99 (reia-ref s)))

(test-assert "a root-type instance does NOT satisfy the subtype's predicate"
  (not (sub? (make-reia 1))))

;; multi-level (grandchild) subtyping
(define-values (gc-metadata make-grandchild grandchild? grandchild-ref gc-subtype) (make-sub-subtype 'grandchild))
(let ((g (make-grandchild 7)))
  (test-assert "grandchild: own predicate" (grandchild? g))
  (test-assert "grandchild: parent predicate (direct subtype)" (sub? g))
  (test-assert "grandchild: grandparent predicate (indirect subtype)" (reia? g))
  (test-equal "grandchild: own accessor" 7 (grandchild-ref g))
  (test-equal "grandchild: parent accessor" 7 (sub-ref g))
  (test-equal "grandchild: grandparent accessor" 7 (reia-ref g)))

;; instance payload can be any Scheme object, including a container for
;; effectively-multiple-values association (per the spec's own note)
(define payload-instance (make-reia (list 'x 1 'y 2)))
(test-equal "instance payload can be an arbitrary compound object"
            '(x 1 y 2) (reia-ref payload-instance))

(let ((runner (test-runner-current)))
  (test-end "srfi-137")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
