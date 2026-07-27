;; Regression test for #1713: the generic record printer recursed into
;; record fields with no cycle detection. A directly self-referential
;; record eventually hit the printer's depth cap, but a *fan-out* cycle
;; (a record whose field is a vector of records that each reference it
;; back -- the shape SRFI 209's enum/enum-type design hit) branches at
;; every level of that recursion, blowing up combinatorially long before
;; the depth cap is reached. write/display/write-shared must instead
;; detect the cycle and print a datum-label marker, exactly as they
;; already do for pairs and vectors.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "cyclic-record-printer-1713")

(define (print->string proc x)
  (let ((port (open-output-string)))
    (proc x port)
    (get-output-string port)))

;; --- Directly self-referential record ----------------------------------

(define-record-type cell
  (make-cell val next)
  cell?
  (val cell-val)
  (next cell-next set-cell-next!))

(define c (make-cell 42 #f))
(set-cell-next! c c)

(test-equal "self-referential record: write"
  "#0=#<cell 42 #0#>"
  (print->string write c))

(test-equal "self-referential record: display"
  "#0=#<cell 42 #0#>"
  (print->string display c))

(test-equal "self-referential record: write-shared"
  "#0=#<cell 42 #0#>"
  (print->string write-shared c))

;; --- Fan-out cycle: two mutually-referencing record types ---------------
;; Mirrors the SRFI 209 enum/enum-type design that motivated this issue:
;; enum-type -> (vector of enums) -> each enum -> back to enum-type.
;; Without real cycle detection this fans out by the vector's width at
;; every trip around the cycle instead of just looping once.

(define-record-type enum-type
  (make-etype enums)
  etype?
  (enums etype-enums set-etype-enums!))

(define-record-type enum
  (make-enum etype)
  enum?
  (etype enum-etype))

(define et (make-etype #f))
(define enums (vector (make-enum et) (make-enum et) (make-enum et)))
(set-etype-enums! et enums)

(test-equal "fan-out record cycle: write"
  "#0=#<enum-type #(#<enum #0#> #<enum #0#> #<enum #0#>)>"
  (print->string write et))

;; --- Non-cyclic records still print in full, unlabeled ------------------

(define plain (make-cell 1 (make-cell 2 #f)))

(test-equal "non-cyclic record printing is unaffected"
  "#<cell 1 #<cell 2 #f>>"
  (print->string write plain))

(let ((runner (test-runner-current)))
  (test-end "cyclic-record-printer-1713")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
