;; SRFI 90: Extensible hash table constructor
;; https://srfi.schemers.org/srfi-90/srfi-90.html
;;
;; Reduced-scope implementation
;; -----------------------------
;; SRFI 90 defines a single procedure, `make-table`, meant to be built with
;; SRFI 89's named-parameter syntax: (make-table test: eq? hash: my-hash
;; size: 100 ...). SRFI 89 is NOT implemented in this codebase (deliberately
;; excluded — no keyword-object type exists), so named/keyword arguments are
;; out of scope here.
;;
;; The spec's own text says these are "purely advisory parameters" and that
;; "an implementation may ignore size, min-load, max-load, weak-keys,
;; weak-values entirely and still conform" — a reference implementation in
;; the SRFI document itself does exactly that. This implementation goes one
;; step further and drops the named-argument syntax too, exposing `test`
;; and `hash` as ordinary **positional** optional arguments instead:
;;
;;   (make-table)             ; test defaults to equal?, hash auto-derived
;;   (make-table test)        ; custom test, hash auto-derived when recognized
;;   (make-table test hash)   ; custom test and hash
;;
;; size:, min-load:, max-load:, weak-keys:, and weak-values: are not
;; supported at all (not even as ignored/accepted-but-unused arguments):
;; without SRFI 89's keyword syntax there is no way to accept them
;; positionally after test/hash without an ambiguous, easily-misused
;; argument order. Callers who need those hints have no substitute here.
;;
;; make-table forwards straight to the built-in (srfi 69) `make-hash-table
;; [equal-proc [hash-proc]]`, which already auto-derives a matching hash
;; function when it recognizes the test procedure (e.g. passing string=?
;; alone picks string-hash automatically).
(define-library (srfi 90)
  (import (scheme base)
          (srfi 69)
          (srfi 227))
  (export make-table)
  (begin
    (define make-table
      (opt-lambda ((test equal?) (hash #f))
        (if hash
            (make-hash-table test hash)
            (make-hash-table test))))))
