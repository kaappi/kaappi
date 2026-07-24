;; SRFI-131 (ERR5RS Record Syntax, reduced) conformance tests.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi131.scm

(import (scheme base) (scheme write) (srfi 64) (srfi 131))

(test-begin "srfi-131")

;;; --- basic definition, accessors, mutators --------------------------------

(define-record-type point make-point point? (x point-x) (y point-y set-point-y!))

(let ((p (make-point 3 4)))
  (test-assert "predicate recognizes its own instance" (point? p))
  (test-equal "first field accessor" 3 (point-x p))
  (test-equal "second field accessor" 4 (point-y p))
  (set-point-y! p 40)
  (test-equal "mutator writes correctly" 40 (point-y p)))
(test-assert "predicate rejects an unrelated value" (not (point? 5)))

;;; --- suppressed constructor / predicate ------------------------------------

(define-record-type suppressed #f #f (v suppressed-v))
;; no make-suppressed or suppressed? bound -- just confirms this doesn't
;; error at definition time; nothing further to assert without a ctor.

;;; --- inheritance: bare (positional) constructor ----------------------------

(define-record-type animal make-animal animal? (name animal-name))
(define-record-type (dog animal) make-dog dog? (breed dog-breed))
(define-record-type widget make-widget widget? (sku widget-sku))

(let ((d (make-dog "Rex" "Labrador")))
  (test-assert "inheritance: ancestor predicate recognizes subtype instance" (animal? d))
  (test-assert "inheritance: own predicate recognizes own instance" (dog? d))
  (test-equal "inheritance: inherited accessor works on subtype instance" "Rex" (animal-name d))
  (test-equal "inheritance: own accessor works" "Labrador" (dog-breed d)))

(let ((w (make-widget "SKU1")))
  (test-assert "inheritance: unrelated type rejected by subtype predicate" (not (dog? w)))
  (test-assert "inheritance: unrelated type rejected by ancestor-shaped predicate" (not (animal? w))))

;; 3-level chain
(define-record-type (puppy dog) make-puppy puppy? (age puppy-age))
(let ((pp (make-puppy "Fido" "Poodle" 1)))
  (test-assert "3-level chain: grandparent predicate" (animal? pp))
  (test-assert "3-level chain: parent predicate" (dog? pp))
  (test-assert "3-level chain: own predicate" (puppy? pp))
  (test-equal "3-level chain: grandparent accessor" "Fido" (animal-name pp))
  (test-equal "3-level chain: parent accessor" "Poodle" (dog-breed pp))
  (test-equal "3-level chain: own accessor" 1 (puppy-age pp)))

;;; --- explicit, NAME-based constructor spec (this SRFI's own distinguishing feature) ---

;; Field names resolved by name, in ARBITRARY order (not positional).
(define-record-type (dog2 animal) (make-dog2 breed name) dog2? (breed dog2-breed))
(let ((d2 (make-dog2 "Poodle" "Fido")))
  (test-equal "named ctor: inherited field set via its own name, out of positional order"
              "Fido" (animal-name d2))
  (test-equal "named ctor: own field set via its own name" "Poodle" (dog2-breed d2))
  (test-assert "named ctor: subtype instance still recognized by ancestor predicate" (animal? d2))
  (test-assert "named ctor: subtype instance recognized by own predicate" (dog2? d2)))

;; A field omitted from the explicit constructor spec is left unspecified
;; but the record still constructs and the SPECIFIED fields still work.
(define-record-type (dog3 animal) (make-dog3 breed) dog3? (breed dog3-breed))
(let ((d3 (make-dog3 "Beagle")))
  (test-assert "named ctor: omitted field doesn't prevent construction" (dog3? d3))
  (test-equal "named ctor: specified field still set correctly" "Beagle" (dog3-breed d3)))

(let ((runner (test-runner-current)))
  (test-end "srfi-131")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
