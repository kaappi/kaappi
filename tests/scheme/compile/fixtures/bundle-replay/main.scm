;; Shared fixture for the bundled-binary regression tests: kaappi#700,
;; kaappi#703, and kaappi#2010. All need a standalone binary whose preamble
;; replays library imports, and `zig build -Dbundle=...` recompiles the whole
;; interpreter to make one. Sharing a single fixture makes the second and
;; third builds content-cache hits instead of further full rebuilds
;; (kaappi#1926) — see bundle_fixture_binary in tests/scheme/shell-common.sh.
;;
;; Every library is imported in one form, as kaappi#700 requires. `sq` is not
;; spelled `square` on purpose: `square` is itself a (scheme base) export, and
;; this program imports both.
(import (scheme base)
        (scheme write)
        (scheme process-context)
        (bundle700 app)
        (bundle700 util)
        (bundle703 app))

;; kaappi#700: nested library loading during preamble replay must not corrupt
;; the import-set list under GC. (run-app 3) = (+ (quad 3) (sq 3)) = 12 + 9.
(display "700: ")
(display (run-app 3))
(display " ")
(display (double 5))
(newline)

;; kaappi#703: (bundle703 app)'s begin block must have run, so `registry` is a
;; live hash table rather than UNDEFINED.
(display "703: ")
(display (app-greet "world"))
(display " ")
(display (lookup "world"))
(newline)

;; kaappi#2010: with bytecode bundled the binary *is* the bundled program, so
;; (command-line) must report every argv element after argv[0] verbatim — even
;; words that are kaappi subcommands ("check", "fmt", "ast", "compile").
;; Print it only when arguments are present, so the shared fixture's no-arg
;; runs (700/703) keep their exact output. The interpreter runs this file
;; directly and never sees arguments, so (command-line) is ("main.scm") there
;; — length 1 — and this stays silent, keeping the interpreter-oracle
;; comparisons intact.
(when (> (length (command-line)) 1)
  (display "cmdline: ")
  (write (command-line))
  (newline))
