;; Regression test for #1479: a procedure defined inside a define-library
;; body that thread-start!s a thunk which calls into ANOTHER library's
;; exported procedure. The thunk closure is deep-copied to the child OS
;; thread; before the fix, deep-copy dropped the closure's lib_env
;; (gc_deep_copy.zig set new_func.env = null), so the child raised "undefined
;; variable" for the cross-library name. kaappi-http's http-listen-threaded
;; hit exactly this -- its guard swallowed the error, so the client just saw
;; a hung connection.
(import (scheme base) (srfi 64) (lib1479 spawner))

(test-begin "library-thread-cross-call-1479")

;; do-work x = (+ (* x 2) 1); the child must resolve do-work across libraries
;; AND do-work must resolve its own library-scoped `helper`.
(test-equal "child thread resolves another library's procedure"
            21 (run-in-thread 10))
;; The http-shaped guarded thunk must now return the real result, not a
;; swallowed undefined-variable error.
(test-equal "guarded thunk returns the real cross-library result"
            43 (run-in-thread/guarded 21))

(let ((runner (test-runner-current)))
  (test-end "library-thread-cross-call-1479")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
