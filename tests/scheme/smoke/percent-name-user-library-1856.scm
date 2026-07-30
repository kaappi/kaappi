;; Regression test for #1856: (scheme base) exported 22 %-prefixed internal
;; primitives, so a user library defining any of those names and importing
;; (scheme base) failed to load outright — R7RS 5.2 makes importing one
;; identifier from two libraries with different bindings an error, which
;; kaappi enforces since #1726. The internals moved to the .internal tag
;; (registered in vm.globals, exported by no standard library), and the
;; desugarings that reference them now go through the pristine (scheme base)
;; snapshot, so a user binding of the same name cannot reach them either.
;;
;; The fixture libraries live in lib1856/ and are found via the script's own
;; directory on the library search path.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64)
        (lib1856 user) (lib1856 ffi))

(test-begin "percent-name-user-library-1856")

;; The whole library loads at all — this is the issue's own reproduction.
(test-equal "user %length is the user's" 2 (byte-length "hi"))

;; ... and the internal helpers the same library's desugarings need are
;; unaffected by the user's same-named bindings.
(test-equal "case-lambda dispatch: 1 arg" 'one (pick 1))
(test-equal "case-lambda dispatch: 2 args" 'two (pick 1 2))
(test-equal "case-lambda dispatch: rest" 'many (pick 1 2 3))
(test-equal "define-record-type accessor" 3 (point-x (make-point 3 4)))
(test-equal "the user's own %-helpers are still theirs"
            '(user-record-ref user-make-record) (user-helpers))

;; Same names, rebound at program top level this time: a top-level define
;; overwrites vm.globals, which the old %length alias could not survive.
(define (%length x) 'top-level-shadow)
(define (%record-ref a b c) 'top-level-shadow)
(define (%make-record . a) 'top-level-shadow)
(define g (case-lambda ((a) 'one) ((a b) 'two)))
(define-record-type pt (mk a) pt? (a pt-a))
(test-equal "case-lambda under top-level %length" 'two (g 1 2))
(test-equal "define-record-type under top-level %record-ref" 7 (pt-a (mk 7)))
(test-equal "top-level %-bindings are still the user's" 'top-level-shadow (%length "x"))

(let ((runner (test-runner-current)))
  (test-end "percent-name-user-library-1856")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
