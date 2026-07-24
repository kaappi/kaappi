;; SRFI-240 (Reconciled Records) conformance tests.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi240.scm
;;
;; SRFI 240 adds no new semantics over SRFI 237 -- it just guarantees
;; define-record-type accepts BOTH R7RS/SRFI-9 positional syntax and R6RS
;; clause syntax, producing interoperable record types either way, plus
;; re-exporting SRFI 237's full procedural/inspection surface. Kaappi's
;; define-record-type already dispatches both syntaxes unconditionally at
;; the engine level (src/vm_records.zig), so this suite mainly confirms
;; that importing (srfi 240) specifically doesn't change or break that,
;; and that the re-exported procedural layer is reachable through it.

(import (scheme base) (scheme write) (srfi 64) (srfi 240))

(test-begin "srfi-240")

;; R7RS/SRFI-9 positional syntax
(define-record-type point (make-point x y) point? (x point-x) (y point-y))
(let ((p (make-point 3 4)))
  (test-assert "R7RS positional syntax works under (srfi 240)" (point? p))
  (test-equal "R7RS positional syntax: accessor" 3 (point-x p))
  (test-equal "R7RS positional syntax: second accessor" 4 (point-y p)))

;; R6RS clause syntax, including inheritance, alongside the R7RS form above
(define-record-type animal (fields (immutable name animal-name)))
(define-record-type (dog make-dog dog?) (parent animal) (fields (immutable breed dog-breed)))
(let ((d (make-dog "Rex" "Lab")))
  (test-assert "R6RS clause syntax works under (srfi 240)" (dog? d))
  (test-assert "R6RS clause syntax: inheritance predicate" (animal? d))
  (test-equal "R6RS clause syntax: inherited accessor" "Rex" (animal-name d))
  (test-equal "R6RS clause syntax: own accessor" "Lab" (dog-breed d)))

;; Both syntaxes coexist as genuinely different, unrelated types
(test-assert "R7RS-defined and R6RS-defined types don't cross-recognize" (not (dog? (make-point 1 2))))
(test-assert "R7RS-defined and R6RS-defined types don't cross-recognize (other direction)" (not (point? (make-dog "x" "y"))))

;; Procedural layer re-exported from SRFI 237
(define widget-rtd (make-record-type-descriptor 'widget #f #f #f #f #((immutable sku))))
(test-equal "procedural layer re-exported: record-type-name" 'widget (record-type-name widget-rtd))
(define widget-rcd (make-record-descriptor widget-rtd #f #f))
(define make-widget (record-constructor widget-rcd))
(define widget? (record-predicate widget-rtd))
(let ((w (make-widget "SKU1")))
  (test-assert "procedural layer re-exported: record-constructor/record-predicate" (widget? w))
  (test-assert "procedural layer re-exported: record? recognizes it" (record? w)))

(let ((runner (test-runner-current)))
  (test-end "srfi-240")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
