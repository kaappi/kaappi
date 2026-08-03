;; Regression probe: a file with a top-level compile error must never be
;; cached (fixed together with kaappi#2110–#2113/#2155's format-v11 change;
;; found while reworking the cache-write gating).
;;
;; `runFile` reports a compile error, skips the failed form, and keeps going —
;; so `compiled_funcs` holds only the forms that DID compile.  The cache write
;; used to be gated only on the top-level-declaration check (`has_imports` at
;; the time, `first_toplevel_decl` since kaappi#2114), so this file wrote an entry holding
;; the partial program.  The warm run then HIT, executed the partial program
;; with no diagnostic at all, and exited 0:
;;
;;   $ kaappi t.scm            # cold — cache MISS
;;   a
;;   t.scm:4:1: compile error[KP2001]: invalid syntax
;;   b
;;   ...exit 1
;;
;;   $ kaappi t.scm            # warm — used to HIT
;;   a
;;   b
;;   ...exit 0                 # the error is gone
;;
;; The compile error vanishing on the second run is the worst shape of cache
;; opacity: it makes a broken program silently "work" and masks the diagnostic
;; exactly when someone reruns to look at it.  `runFile` now sets
;; `had_compile_error` and refuses to cache the file (`--timings` reports
;; `not cached: compile error`), so cold and warm are the identical
;; configuration and this probe must agree byte for byte, exit code included.
;;
;; The forms around the bad one both run in both runs — that is the
;; discriminating control that the fix refuses CACHING, not execution.

(display "a")
(newline)
(if)
(display "b")
(newline)
