;; Regression test for #877: define-syntax inside a library body must not
;; register the macro in the process-global macro table.
;;
;; Two observable bugs this guards against:
;;   1. Unexported library-body macros leaking to all code once the library
;;      loads (even when the importer filters them out).
;;   2. Loading a library silently clobbering a same-named macro that the
;;      program explicitly imported from a different library (wrong-answer bug).
;;
;; The fixture libraries live in lib877/ next to this script and are loaded
;; lazily on first import, so the clobber case reproduces the real load order.
(import (scheme base) (scheme write) (scheme eval) (srfi 64))

(test-begin "library-macro-leak-877")

;; --- 1. Unexported macro must not leak ---------------------------------------
;; Only public-f is imported; the private-mac used inside the library must not
;; become visible to the importer.
(import (only (lib877 m) public-f))

(test-equal "exported proc still uses its private macro" '(private 1) (public-f))

(test-assert "unexported library macro does not leak"
  (guard (exn (#t #t))
    ;; If private-mac had leaked into the global macro table, this would
    ;; expand to (list 'private 7); with the fix it is an unbound identifier.
    (eval '(private-mac 7) (environment '(scheme base)))
    #f))

;; --- 2. Imported macro must not be clobbered by a later library --------------
;; Import A's `tag` explicitly, then import only `bfun` from B. Loading B
;; (which also defines a `tag` macro) must not overwrite A's `tag`.
(import (only (lib877 a) tag))
(import (only (lib877 b) bfun))

(test-equal "macro imported from A is not clobbered by loading B" 'from-a (tag))
(test-equal "the non-macro export from B is usable" 'bfun (bfun))

;; --- 3. Importing and using a macro across libraries still works -------------
(import (only (lib877 user) use-tag))
(test-equal "library uses a macro imported from another library" 'from-a (use-tag))

;; --- 4. Exported macro expanding into a private helper macro still works ------
;; `outer` expands into the unexported helper `inner`; importing only `outer`
;; must still expand correctly at the use site. (The helper is made available
;; at the import target on demand so the expansion resolves — that is required
;; for correctness and is distinct from the wholesale load-time leak in #877,
;; where `private-mac` above is referenced by no export and stays hidden.)
(import (only (lib877 helper) outer))
(test-equal "exported macro expands via its private helper" 105 (outer 5))

(let ((runner (test-runner-current)))
  (test-end "library-macro-leak-877")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
