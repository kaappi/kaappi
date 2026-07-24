;; SRFI-136 (Extensible record types) conformance tests.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi136.scm

(import (scheme base) (scheme write) (srfi 64) (srfi 136))

(test-begin "srfi-136")

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

(define-record-type suppressed-thing #f #f (v suppressed-thing-v))
(test-assert "suppressed ctor/pred: the type still exists via introspection"
  (record-type-descriptor? (suppressed-thing)))

;;; --- inheritance (positional parent-args-then-own-fields) -----------------

(define-record-type animal make-animal animal? (name animal-name))
(define-record-type (dog animal) make-dog dog? (breed dog-breed))
(define-record-type (puppy dog) make-puppy puppy? (age puppy-age))
(define-record-type widget-type make-widget-type widget-type? (sku widget-type-sku))

(let ((d (make-dog "Rex" "Labrador")))
  (test-assert "inheritance: ancestor predicate recognizes subtype instance" (animal? d))
  (test-assert "inheritance: own predicate recognizes own instance" (dog? d))
  (test-equal "inheritance: inherited accessor works on subtype instance" "Rex" (animal-name d))
  (test-equal "inheritance: own accessor works" "Labrador" (dog-breed d)))

(let ((w (make-widget-type "SKU1")))
  (test-assert "inheritance: unrelated type rejected by subtype predicate" (not (dog? w)))
  (test-assert "inheritance: unrelated type rejected by ancestor-shaped predicate" (not (animal? w))))

(let ((pp (make-puppy "Fido" "Poodle" 1)))
  (test-assert "3-level chain: grandparent predicate" (animal? pp))
  (test-assert "3-level chain: parent predicate" (dog? pp))
  (test-assert "3-level chain: own predicate" (puppy? pp))
  (test-equal "3-level chain: grandparent accessor" "Fido" (animal-name pp))
  (test-equal "3-level chain: parent accessor" "Poodle" (dog-breed pp))
  (test-equal "3-level chain: own accessor" 1 (puppy-age pp)))

;;; --- CPS-style introspection macro -----------------------------------------

;; (<type-name>) => the type's own rtd.
(test-assert "(type-name) yields the type's own rtd" (record-type-descriptor? (point)))
(test-equal "(type-name) rtd has the right name" 'point (record-type-name (point)))

;; (<type-name> (<keyword> <datum> ...)) => (<keyword> <datum> ... <parent> <field-spec> ...),
;; recursively usable to compute something at macro-expansion time across
;; an entire inheritance chain -- this SRFI's signature technique.
(define-syntax %count-fields
  (syntax-rules ()
    ((_ #f field-spec ...) (length '(field-spec ...)))
    ((_ parent field-spec ...) (+ (parent (%count-fields)) (length '(field-spec ...))))))
(test-equal "CPS introspection: root type field count" 1 (animal (%count-fields)))
(test-equal "CPS introspection: 1-level subtype accumulates parent + own" 2 (dog (%count-fields)))
(test-equal "CPS introspection: 2-level subtype accumulates transitively" 3 (puppy (%count-fields)))

;;; --- procedural layer -------------------------------------------------------

(define proc-rtd (make-record-type-descriptor 'proc-point '(x y)))
(test-assert "procedural: record-type-descriptor? recognizes an rtd" (record-type-descriptor? proc-rtd))
(test-assert "procedural: record-type-descriptor? rejects a non-rtd" (not (record-type-descriptor? 5)))
(test-equal "procedural: record-type-name" 'proc-point (record-type-name proc-rtd))
(test-assert "procedural: record-type-parent is #f for a root type" (not (record-type-parent proc-rtd)))

(define proc-point (make-record proc-rtd #(7 8)))
(test-assert "procedural: record? recognizes a procedurally-made record" (record? proc-point))
(test-assert "procedural: record? rejects a non-record" (not (record? 5)))
(test-eq "procedural: record-type-descriptor round-trips" proc-rtd (record-type-descriptor proc-point))

(define proc-pred (record-type-predicate proc-rtd))
(test-assert "procedural: record-type-predicate recognizes its own instance" (proc-pred proc-point))

;; make-record-type-descriptor with a parent, using symbol field specs
;; (bare symbol = mutable, per this SRFI's own field-specifier grammar)
(define proc-animal-rtd (make-record-type-descriptor 'proc-animal '(name)))
(define proc-dog-rtd (make-record-type-descriptor 'proc-dog '(breed) proc-animal-rtd))
(test-eq "procedural: make-record-type-descriptor with parent round-trips" proc-animal-rtd (record-type-parent proc-dog-rtd))

;; record-type-fields returns (name accessor mutator) triples
(define-record-type mutfield-test make-mft mft? (a mft-a mft-a-set!) (b mft-b))
(let ((fields (record-type-fields (mutfield-test))))
  (test-equal "record-type-fields: correct count" 2 (length fields))
  (test-equal "record-type-fields: first field name" 'a (car (car fields)))
  (let ((inst (make-mft 1 2)))
    (test-equal "record-type-fields: reconstructed accessor works" 1 ((cadr (car fields)) inst))
    (test-assert "record-type-fields: mutable field has a non-#f mutator" (caddr (car fields)))
    (test-assert "record-type-fields: immutable field has a #f mutator" (not (caddr (cadr fields))))))

(let ((runner (test-runner-current)))
  (test-end "srfi-136")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
