;; Regression test for #1812: a use-site top-level redefinition of a name
;; that a macro's expansion references (syntax-rules or er-macro-transformer
;; alike) must not reach the expansion. R7RS 4.3.1 referential transparency
;; says a template's free reference to a library-internal binding always
;; denotes that library's own binding, immune to what an unrelated importer
;; later does with the same name.
;;
;; Root cause: renameForHygiene left a free reference to a procedure/
;; transformer completely unrenamed, and a non-procedure free reference was
;; only protected against LEXICAL (let/lambda) shadowing at the use site via
;; a get_global-by-name local-alias injection -- not against a genuine
;; top-level redefinition, since that injection still reads the importer's
;; own mutable vm.globals at the instruction's execution time.
;;
;; Fixtures live in lib1812/ next to this script.
(import (scheme base) (scheme write) (srfi 64)
        (srfi 211 explicit-renaming)
        (lib1812 srmac) (lib1812 constmac) (lib1812 ermac) (lib1812 tailmac)
        (lib1812 nestedmac))

(test-begin "def-env-redefinition-1812")

;; --- syntax-rules macro referencing a library-internal procedure ------------
(test-equal 42 (tw 21))

;; Shadow the library's internal helper NAME at the top level -- legal,
;; ordinary Scheme (redefining a top-level binding is always allowed) -- and
;; confirm it does not corrupt the already-imported macro's expansion.
(define helper2 'shadowed)

(test-equal 10 (tw 5))
(test-equal 'shadowed helper2)

;; --- same-library use: the macro must keep working when the library calls
;; --- it internally, exactly as before the fix -----------------------------
(test-equal 2 (self-check))

;; --- syntax-rules macro referencing a library-internal non-procedure value --
(test-equal 100 (cm))

(define k 999)

(test-equal 100 (cm))
(test-equal 999 k)

;; --- er-macro-transformer macro referencing a library-internal procedure ---
(test-equal 1005 (etw 5))

(define helper3 'shadowed-too)

(test-equal 1006 (etw 6))
(test-equal 'shadowed-too helper3)

;; --- a library macro referencing a TRUE (scheme base) procedure
;; --- (call-with-values) in tail position must be left unprefixed, so the
;; --- compiler's dedicated is_tail dispatch (compileCallWithValuesTail)
;; --- still recognizes it by its exact bare name and multiple values still
;; --- pass through correctly. Unlike helper2/k/helper3 above, this name is
;; --- NOT expected to be immune to redefinition -- call-with-values is a
;; --- universal builtin the library merely imports, not a genuinely
;; --- library-internal binding, so it deliberately keeps the pre-existing,
;; --- late-bound-by-name behavior (see renameForHygiene's own comment).
(test-equal 7 (cwv-tail (values 3 4) (lambda (x y) (+ x y))))

;; --- a library macro that defines ANOTHER macro via letrec-syntax, which
;; --- itself references a library-internal helper (SRFI 41's stream-match
;; --- shape) must not double-wrap the helper's def-env-prefixed reference --
(test-equal 15 (outer-match 5))

(let ((runner (test-runner-current)))
  (test-end "def-env-redefinition-1812")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
