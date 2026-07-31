;; Shared fixture for the two bundled-binary regression tests, kaappi#700 and
;; kaappi#703. Both need a standalone binary whose preamble replays library
;; imports, and `zig build -Dbundle=...` recompiles the whole interpreter to
;; make one. Sharing a single fixture makes the second build a content-cache
;; hit instead of a second full rebuild (kaappi#1926) — see
;; bundle_fixture_binary in tests/scheme/shell-common.sh.
;;
;; Every library is imported in one form, as kaappi#700 requires. `sq` is not
;; spelled `square` on purpose: `square` is itself a (scheme base) export, and
;; this program imports both.
(import (scheme base)
        (scheme write)
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
