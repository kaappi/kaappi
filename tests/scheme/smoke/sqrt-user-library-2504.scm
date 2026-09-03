;; Regression test for #2504: (scheme base) exported sqrt, which R7RS reserves
;; to (scheme inexact) (§6.2.6; Appendix A lists exact-integer-sqrt, not sqrt,
;; among the base exports). Since kaappi enforces R7RS 5.2 (importing one
;; identifier from two libraries with different bindings is an error), a
;; portable program that imported (scheme base) together with a user library
;; exporting its own sqrt failed to load with KP2001 — the same collision
;; class as #1856's %-prefixed base exports, with a name a math library is far
;; more likely to define.
;;
;; The fixture library lives in lib2504/ and is found via the script's own
;; directory on the library search path.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64)
        (lib2504 mathlib))

(test-begin "sqrt-user-library-2504")

;; The program loads at all — this is the issue's own reproduction: with
;; (scheme base) no longer exporting sqrt, the two imports do not collide.
(test-equal "user sqrt is the user's" '(lib-mine 4) (sqrt 4))
(test-equal "library-internal caller sees the library's sqrt"
            '(lib-mine 25) (hypot-ish 3 4))

;; The built-in is still reachable from the libraries R7RS and R5RS assign it
;; to, and is the same procedure via both.
(test-equal "(scheme inexact) exports sqrt"
            2 (eval '(sqrt 4) (environment '(scheme inexact))))
(test-equal "(scheme r5rs) exports sqrt"
            3 (eval '(sqrt 9) (environment '(scheme r5rs))))
(test-assert "inexact and r5rs sqrt are one binding"
             (eq? (eval 'sqrt (environment '(scheme inexact)))
                  (eval 'sqrt (environment '(scheme r5rs)))))

;; (scheme base) keeps exact-integer-sqrt — that one really is a base export.
(test-equal "(scheme base) exports exact-integer-sqrt"
            '(4 1) (eval '(call-with-values (lambda () (exact-integer-sqrt 17)) list)
                         (environment '(scheme base))))

;; Renaming around the user library still reaches the built-in, so a program
;; that wants both can have both.
(test-equal "prefixed built-in alongside the user's"
            '(2 (lib-mine 4))
            (eval '(list (in:sqrt 4) (sqrt 4))
                  (environment '(scheme base)
                               '(prefix (scheme inexact) in:)
                               '(lib2504 mathlib))))

(let ((runner (test-runner-current)))
  (test-end "sqrt-user-library-2504")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
