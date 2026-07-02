;; Regression test for #854: case rejects empty datum list
;; R7RS allows empty datum lists in case clauses — the clause
;; is dead code (never matches) and should be silently skipped.

;; Empty datum list before matching clause
(display (case 1
  (() 'never)
  ((1) 'one)
  (else 'other)))
(newline)

;; Empty datum list after matching clause
(display (case 2
  ((2) 'two)
  (() 'never)
  (else 'other)))
(newline)

;; Only empty datum lists, falls through to else
(display (case 3
  (() 'never1)
  (() 'never2)
  (else 'fallthrough)))
(newline)

;; Only empty datum lists, no else — result is void
(case 4
  (() 'never))

;; Expected output:
;; one
;; two
;; fallthrough
