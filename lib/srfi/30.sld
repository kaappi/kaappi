;;; SRFI 30 — Nested Multi-line Comments
;;;
;;; Specifies `#| ... |#` block comments that nest correctly (an inner `#|`
;;; increments a depth counter rather than being treated as ordinary
;;; comment text, so the comment only ends at the matching `|#`). This
;;; syntax was later folded into R7RS itself, and Kaappi's reader already
;;; implements it correctly with nesting (see `skipBlockComment` in
;;; `src/reader.zig`, driven by a depth counter, not a first-`|#`-wins
;;; scan). There is nothing to export — the feature is the reader syntax
;;; itself, active unconditionally regardless of any import. This library
;;; exists only so `(import (srfi 30))` succeeds for programs that check
;;; for it.

(define-library (srfi 30)
  (export)
  (import (scheme base)))
