;; SRFI-57 (Records) conformance tests.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi57.scm

(import (scheme base) (scheme write) (srfi 64) (srfi 57))

(test-begin "srfi-57")

;;; --- basic define-record-type, no schemes ---------------------------------

(define-record-type point (make-point x y) point? (x point-x) (y point-y set-point-y!))

(let ((p (make-point 3 4)))
  (test-assert "predicate recognizes its own instance" (point? p))
  (test-equal "first field accessor" 3 (point-x p))
  (test-equal "second field accessor" 4 (point-y p))
  (set-point-y! p 40)
  (test-equal "mutator writes correctly" 40 (point-y p)))
(test-assert "predicate rejects an unrelated value" (not (point? 5)))

;;; --- suppressed constructor / predicate ------------------------------------

(define-record-type suppressed #f #f (v))
;; no make-suppressed or suppressed? bound -- just confirms this doesn't
;; error at definition time.

;;; --- bare constructor name: all fields positionally ------------------------

(define-record-type triple make-triple triple? (a triple-a) (b triple-b) (c triple-c))

(let ((tr (make-triple 1 2 3)))
  (test-equal "bare ctor: first field" 1 (triple-a tr))
  (test-equal "bare ctor: second field" 2 (triple-b tr))
  (test-equal "bare ctor: third field" 3 (triple-c tr)))

;;; --- explicit named constructor with a field omitted, out of order ---------

(define-record-type quad (make-quad c a) quad? (a quad-a) (b quad-b) (c quad-c))

(let ((q (make-quad 30 10)))
  (test-equal "named ctor: field set via its own name" 10 (quad-a q))
  (test-equal "named ctor: field set via its own name, out of positional order" 30 (quad-c q))
  (test-assert "named ctor: omitted field doesn't prevent construction" (quad? q)))

;;; --- define-record-scheme: single scheme, polymorphic predicate/accessor --

(define-record-scheme <named #f named? (name <named.name))
(define-record-type person (make-person name) person? (name person-name))

(let ((pn (make-person "Alice")))
  (test-assert "scheme: polymorphic predicate recognizes a conforming type" (named? pn))
  (test-equal "scheme: polymorphic accessor reads a conforming instance" "Alice" (<named.name pn)))

(define-record-type widget0 (make-widget0 sku) widget0? (sku widget0-sku))
(test-assert "scheme: polymorphic predicate rejects a non-conforming type"
  (not (named? (make-widget0 "X"))))
(test-assert "scheme: polymorphic predicate rejects a non-record value"
  (not (named? 42)))

;;; --- multiple parent schemes with a diamond, dedup of shared fields --------

(define-record-scheme (<animal <named) #f animal? (age animal.age))
(define-record-scheme (<pet <animal <named) #f pet? (owner pet.owner))

(test-equal "scheme merge: diamond parent fields de-duplicated, first position kept"
  '(name age owner) (car <pet))

(define-record-type (dog <pet) (make-dog name age owner breed) dog? (breed dog-breed))

(let ((d (make-dog "Rex" 3 "Alice" "Lab")))
  (test-equal "multi-scheme inheritance: grandparent-scheme accessor" "Rex" (<named.name d))
  (test-equal "multi-scheme inheritance: parent-scheme accessor" 3 (animal.age d))
  (test-equal "multi-scheme inheritance: own-scheme accessor" "Alice" (pet.owner d))
  (test-equal "multi-scheme inheritance: type's own field" "Lab" (dog-breed d))
  (test-assert "multi-scheme inheritance: polymorphic predicate recognizes deep instance" (pet? d))
  (test-assert "multi-scheme inheritance: grandparent-scheme predicate recognizes deep instance" (animal? d))
  (test-assert "multi-scheme inheritance: own type predicate recognizes own instance" (dog? d)))

(define-record-type widget (make-widget sku) widget? (sku widget-sku))
(test-assert "structural conformance: unrelated type rejected by scheme predicate"
  (not (pet? (make-widget "SKU1"))))

;;; --- record-update / record-update! ----------------------------------------

(let* ((d (make-dog "Rex" 3 "Alice" "Lab"))
       (d2 (record-update d <animal (age 4))))
  (test-equal "record-update: updated field reflects new value" 4 (animal.age d2))
  (test-equal "record-update: original record is unaffected" 3 (animal.age d))
  (test-equal "record-update: untouched field carries over" "Lab" (dog-breed d2))
  (test-assert "record-update: result is a new object, not the same one" (not (eq? d d2))))

(let ((d (make-dog "Rex" 3 "Alice" "Lab")))
  (let ((result (record-update! d <animal (age 99))))
    (test-equal "record-update!: mutates the original record in place" 99 (animal.age d))
    (test-assert "record-update!: returns the (same) mutated record" (eq? result d))))

;;; --- record-compose: the spec's own worked example -------------------------

(define-record-scheme <point-s #f #f (x <point-s.x) (y <point-s.y))
(define-record-scheme <color-s #f #f (hue <color-s.hue))
(define-record-type cp (make-cp x y hue) cp? (x cp-x) (y cp-y) (hue cp-hue))
(define-record-type color-point (make-color-point x y hue info)
  color-point? (x cp2-x) (y cp2-y) (hue cp2-hue) (info cp2-info))

(let* ((c (make-cp 1 2 'blue))
       (composed (record-compose (<point-s c) (<color-s c) (color-point (x 8) (info 'hi)))))
  (test-equal "record-compose: explicit override wins over an imported field" 8 (cp2-x composed))
  (test-equal "record-compose: field copied from a polymorphic (scheme) import" 2 (cp2-y composed))
  (test-equal "record-compose: field copied from a second polymorphic import" 'blue (cp2-hue composed))
  (test-equal "record-compose: field set only via explicit override" 'hi (cp2-info composed)))

;;; --- record-compose: monomorphic import is a special case ------------------

(define-record-type full-point (make-full-point x y) full-point? (x fp-x) (y fp-y))
(define-record-type point-copy (make-point-copy x y) point-copy? (x pc-x) (y pc-y))

(let* ((fp (make-full-point 5 6))
       (copied (record-compose (full-point fp) (point-copy))))
  (test-equal "record-compose: monomorphic import copies its own field" 5 (pc-x copied))
  (test-equal "record-compose: monomorphic import copies its other field" 6 (pc-y copied)))

(let ((runner (test-runner-current)))
  (test-end "srfi-57")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
