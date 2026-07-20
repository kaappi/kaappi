;; SRFI-257 rx sublibrary smoke tests — a lean cut that exercises every
;; exported pattern once, over both regexp (SRFI 115 `rx') and SSRE-string
;; (SRFI 264) spellings of the regexp argument, plus the ~/all+ and ~/etc+
;; "must match at least once" variants the reference suite never reaches.
;;
;; Kept deliberately small: expansion cost per `match' form climbs steeply
;; with the number of subpatterns (a five-subpattern ~/sub costs seconds on
;; its own), so no pattern here binds more than two, and the wide cases live
;; only in the complete port at tests/scheme/srfi/slow/srfi257-rx-full.scm
;; (minutes of macro expansion; run it when touching the expander, SRFI 115,
;; SRFI 264, or the SRFI 257 libraries).
;;
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi257-rx.scm

(import (scheme base) (srfi 64) (srfi 257) (srfi 257 rx))

(test-begin "srfi-257-rx")

;; One capture group, so two subpatterns cover both $0 and $1.
(define phs "home: 301; cell: 240; fax: 301")
(define ssre "({a}*): {d}*")
(define nums "abc123def456ghi789")
(define none "nothing here")

;; ~/ — the whole string must match; subpatterns bind $0, $1, ...
(test-equal "42" (match "42" ((~/ "[0-9]+" a) a) (_ #f)))
(test-equal "42" (match "42" ((~/ (rx (+ (/ "09"))) a) a) (_ #f)))
(test-equal #f (match 42 ((~/ "[0-9]+" a) a) (_ #f)))
(test-equal #f (match "x42" ((~/ "[0-9]+") #t) (_ #f)))
;; more subpatterns than submatches is a failure, not an error
(test-equal #f (match "42" ((~/ "[0-9]+" a b) (list a b)) (_ #f)))

;; ~/sub — the first matching substring only
(test-equal '("home: 301" "home") (match phs ((~/sub ssre s t) (list s t)) (_ #f)))
(test-equal #f (match phs ((~/sub ssre _ "cell") #t) (_ #f)))

;; ~/any — tries every match until the subpatterns fit
(test-equal "cell" (match phs ((~/any ssre _ "cell") "cell") (_ #f)))
(test-equal #f (match phs ((~/any ssre _ "tty") #t) (_ #f)))

;; ~/all — parallel lists of submatch strings, one per capture group
(test-equal '("home" "cell" "fax") (match phs ((~/all ssre _ t) t) (_ #f)))
;; ~/all does not fail when nothing matches: each subpattern sees '()
(test-equal '(() ()) (match none ((~/all ssre s t) (list s t)) (_ #f)))

;; ~/all+ — as ~/all, but fails when the regexp matches no substring
(test-equal '("home" "cell" "fax") (match phs ((~/all+ ssre _ t) t) (_ #f)))
(test-equal #f (match none ((~/all+ ssre s t) (list s t)) (_ #f)))

;; ~/etc — subpatterns constrain each match before the lists are built
(test-equal '("home" "cell" "fax") (match phs ((~/etc ssre _ t) t) (_ #f)))
(test-equal #f (match phs ((~/etc ssre _ (~and t (~not "cell"))) t) (_ #f)))

;; ~/etc+ — as ~/etc, but fails when the regexp matches no substring
(test-equal '("home" "cell" "fax") (match phs ((~/etc+ ssre _ t) t) (_ #f)))
(test-equal #f (match none ((~/etc+ ssre s t) (list s t)) (_ #f)))

;; ~/etcse — skips the matches whose subpatterns fail, so it never fails
(test-equal '("home" "fax")
  (match phs ((~/etcse ssre _ (~and t (~not "cell"))) t) (_ #f)))
(test-equal '() (match phs ((~/etcse ssre _ (~and t "tty")) t) (_ #f)))

;; ~/extracted, ~/split, ~/partitioned — the subpattern sees the whole list
(test-equal '("123" "456" "789") (match nums ((~/extracted "{d}+" l) l) (_ #f)))
(test-equal '("123" "456" "789")
  (match nums ((~/extracted (rx (+ numeric)) l) l) (_ #f)))
(test-equal '("abc" "def" "ghi" "") (match nums ((~/split "{d}+" l) l) (_ #f)))
(test-equal '("a" "" "b") (match "a,,b" ((~/split (rx (",;")) l) l) (_ #f)))
(test-equal '("abc" "123" "def" "456" "ghi" "789")
  (match nums ((~/partitioned "{d}*" l) l) (_ #f)))
(test-equal #f (match 42 ((~/partitioned "{d}*" l) l) (_ #f)))

;; a regexp argument that is neither a regexp nor a string is an error
(test-assert (guard (e (#t #t)) (match "x" ((~/ 42) #t) (_ #f)) #f))

(let ((runner (test-runner-current)))
  (test-end)
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
