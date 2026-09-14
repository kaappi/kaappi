;;; SRFI 62 — S-expression comments
;;;
;;; Specifies `#;` datum comments: `#;` followed by a datum discards that
;;; whole datum (whatever its shape — an atom or a full nested expression)
;;; as if it were never written. This syntax was later folded into R7RS
;;; itself, and Kaappi's reader already implements it correctly (see the
;;; `#;` special case in `skipWhitespaceAndCommentsChecked` in
;;; `src/reader.zig`, which recursively reads and discards the next full
;;; datum). There is nothing to export — the feature is the reader syntax
;;; itself, active unconditionally regardless of any import. This library
;;; exists only so `(import (srfi 62))` succeeds for programs that check
;;; for it.

(define-library (srfi 62)
  (export)
  (import (scheme base)))
