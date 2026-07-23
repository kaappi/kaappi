;; Fixture for srfi59.scm's "program-vicinity tracks a nested load" test.
;; Deliberately has no top-level (import ...): `load` runs a form directly
;; in the caller's environment (R7RS 6.14), and this fixture only needs
;; `program-vicinity`, which the loading script already imported. Stashes
;; the result in a global rather than relying on `load`'s return value,
;; which is just this file's last expression's value, not anything special.
(define %srfi59-nested-vicinity-result (program-vicinity))
