;; Verifies a `kaappi compile` binary sees its own argv via (command-line)
;; (kaappi#1744). Run directly by run-e2e.sh's Phase 3, not through the
;; generic per-program parity loop in programs/: the first (command-line)
;; element is the running binary's own path, which legitimately differs
;; between an interpreted run and a compiled run, so exact-output parity
;; with the interpreter does not apply to this program. Only the tail of
;; the list — the real arguments passed after the program name — is
;; checked by the harness.
(import (scheme base) (scheme write) (scheme process-context))
(write (cdr (command-line)))
(newline)
