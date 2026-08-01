;;; Audit: lib/srfi/152.sld (SRFI 152 — String Library, reduced) — the SRFI 13
;;; seam and the (scheme base) re-exports.
;;; Systematic audit v2, Phase 3.9 (docs/audit-strategy.md, tracking #1890).
;;;
;;; Oracle: SRFI 152, https://srfi.schemers.org/srfi-152/srfi-152.html
;;;
;;; DELIBERATELY SHALLOW, for two reasons stated up front:
;;;
;;;   1. SRFI 152's own behaviour was already audited in the v1 campaign
;;;      (kaappi#1234 — string-every's return value, string-split's grammar
;;;      and limit, ~24 missing exports; all fixed), and the existing
;;;      tests/scheme/srfi/srfi152.scm carries 134 assertions.
;;;   2. All 20 of its "untested" exports are R7RS `(scheme base)` names it
;;;      re-exports unchanged, and `(scheme base)` has its own audit
;;;      (tests/scheme/audit/primitives_string-audit.scm).
;;;
;;; What was left unmeasured is the SEAM the unit was scoped around: does
;;; SRFI 152 agree with SRFI 13 (src/primitives_string_ext.zig, audited)
;;; where the two overlap? The answer is stronger than "agree" — the .sld
;;; imports those 22 names straight from `(srfi 13)`, so they are the SAME
;;; BINDING and cannot diverge. That is asserted by identity below, which is
;;; both the tightest possible statement and a regression gate: if a future
;;; change reimplements any of them inside 152, one of these fails and the
;;; behavioural comparison stops being free.
;;;
;;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi152-audit.scm

(import (scheme base) (scheme write) (scheme process-context) (srfi 64)
        (prefix (srfi 13) s13:)
        (prefix (srfi 152) s152:))

(test-begin "srfi152 audit")

;;; ------------------------------------------------------------------
;;; The SRFI 13 seam: same binding, not merely same behaviour.
;;; ------------------------------------------------------------------

(for-each
 (lambda (pair)
   (test-assert (string-append "SRFI 152's " (car pair) " is SRFI 13's own binding")
                (eq? (cadr pair) (caddr pair))))
 (list (list "string-contains" s13:string-contains s152:string-contains)
       (list "string-prefix?" s13:string-prefix? s152:string-prefix?)
       (list "string-suffix?" s13:string-suffix? s152:string-suffix?)
       (list "string-index" s13:string-index s152:string-index)
       (list "string-index-right" s13:string-index-right s152:string-index-right)
       (list "string-skip" s13:string-skip s152:string-skip)
       (list "string-skip-right" s13:string-skip-right s152:string-skip-right)
       (list "string-count" s13:string-count s152:string-count)
       (list "string-take" s13:string-take s152:string-take)
       (list "string-drop" s13:string-drop s152:string-drop)
       (list "string-take-right" s13:string-take-right s152:string-take-right)
       (list "string-drop-right" s13:string-drop-right s152:string-drop-right)
       (list "string-pad" s13:string-pad s152:string-pad)
       (list "string-pad-right" s13:string-pad-right s152:string-pad-right)
       (list "string-trim" s13:string-trim s152:string-trim)
       (list "string-trim-right" s13:string-trim-right s152:string-trim-right)
       (list "string-trim-both" s13:string-trim-both s152:string-trim-both)
       (list "string-replace" s13:string-replace s152:string-replace)
       (list "string-join" s13:string-join s152:string-join)
       (list "string-concatenate" s13:string-concatenate s152:string-concatenate)
       (list "string-tabulate" s13:string-tabulate s152:string-tabulate)
       (list "string-every" s13:string-every s152:string-every)
       (list "string-any" s13:string-any s152:string-any)
       (list "string-unfold" s13:string-unfold s152:string-unfold)
       (list "string-unfold-right" s13:string-unfold-right s152:string-unfold-right)
       (list "string-filter" s13:string-filter s152:string-filter)))

;; SRFI 152's string-remove is SRFI 13's string-delete under a new name --
;; the one renamed import, and the only place the two specs disagree on
;; spelling for the same operation.
(test-assert "SRFI 152's string-remove is SRFI 13's string-delete"
             (eq? s13:string-delete s152:string-remove))
(test-equal "string-remove and string-delete therefore agree on a value"
            "bcd" (s152:string-remove (lambda (c) (char=? c #\a)) "abacad"))

;;; ------------------------------------------------------------------
;;; The (scheme base) re-exports: 20 names that had never appeared in the
;;; SRFI 152 test file. Same-binding again, so nothing can drift.
;;; ------------------------------------------------------------------

(for-each
 (lambda (pair)
   (test-assert (string-append "SRFI 152's " (car pair) " is (scheme base)'s own binding")
                (eq? (cadr pair) (caddr pair))))
 (list (list "string?" string? s152:string?)
       (list "string" string s152:string)
       (list "make-string" make-string s152:make-string)
       (list "string-length" string-length s152:string-length)
       (list "string-ref" string-ref s152:string-ref)
       (list "string-set!" string-set! s152:string-set!)
       (list "substring" substring s152:substring)
       (list "string-copy" string-copy s152:string-copy)
       (list "string-copy!" string-copy! s152:string-copy!)
       (list "string-fill!" string-fill! s152:string-fill!)
       (list "string-append" string-append s152:string-append)
       (list "string->list" string->list s152:string->list)
       (list "list->string" list->string s152:list->string)
       (list "string->vector" string->vector s152:string->vector)
       (list "vector->string" vector->string s152:vector->string)
       (list "string-for-each" string-for-each s152:string-for-each)
       (list "string-map" string-map s152:string-map)
       (list "string=?" string=? s152:string=?)
       (list "string<?" string<? s152:string<?)
       (list "string<=?" string<=? s152:string<=?)
       (list "string>?" string>? s152:string>?)
       (list "string>=?" string>=? s152:string>=?)
       (list "string-ci=?" string-ci=? s152:string-ci=?)
       (list "read-string" read-string s152:read-string)
       (list "write-string" write-string s152:write-string)))

;;; ------------------------------------------------------------------
;;; A few values through the SRFI 152 spelling, so the identity assertions
;;; above are backed by at least one live call each on the shared surface.
;;; ------------------------------------------------------------------

(test-equal "string-null? on the empty string" #t (s152:string-null? ""))
(test-equal "string-null? on a non-empty string" #f (s152:string-null? "a"))
(test-equal "string-take" "ab" (s152:string-take "abcd" 2))
(test-equal "string-drop" "cd" (s152:string-drop "abcd" 2))
(test-equal "string-take-right" "cd" (s152:string-take-right "abcd" 2))
(test-equal "string-drop-right" "ab" (s152:string-drop-right "abcd" 2))
(test-equal "string-pad pads on the left" "..ab" (s152:string-pad "ab" 4 #\.))
(test-equal "string-pad-right pads on the right" "ab.." (s152:string-pad-right "ab" 4 #\.))
(test-equal "string-trim" "ab  " (s152:string-trim "  ab  "))
(test-equal "string-trim-right" "  ab" (s152:string-trim-right "  ab  "))
(test-equal "string-trim-both" "ab" (s152:string-trim-both "  ab  "))
(test-equal "string-index finds the first match" 1 (s152:string-index "abc" (lambda (c) (char=? c #\b))))
(test-equal "string-index returns #f when nothing matches"
            #f (s152:string-index "abc" (lambda (c) (char=? c #\z))))
(test-equal "string-index-right finds the last match"
            3 (s152:string-index-right "abab" (lambda (c) (char=? c #\b))))
(test-equal "string-count" 2 (s152:string-count "abab" (lambda (c) (char=? c #\a))))
(test-equal "string-contains finds a substring" 1 (s152:string-contains "abcd" "bc"))
(test-equal "string-contains returns #f when absent" #f (s152:string-contains "abcd" "zz"))
(test-equal "string-contains-right finds the last occurrence"
            2 (s152:string-contains-right "abab" "ab"))
(test-assert "string-prefix? on a real prefix" (s152:string-prefix? "ab" "abcd"))
(test-assert "string-suffix? on a real suffix" (s152:string-suffix? "cd" "abcd"))
(test-equal "string-prefix-length" 2 (s152:string-prefix-length "abcd" "abzz"))
(test-equal "string-suffix-length" 2 (s152:string-suffix-length "zzcd" "abcd"))
(test-equal "string-join with the default delimiter" "a b" (s152:string-join '("a" "b")))
(test-equal "string-join with an explicit delimiter" "a-b" (s152:string-join '("a" "b") "-"))
(test-equal "string-concatenate" "abc" (s152:string-concatenate '("a" "b" "c")))
(test-equal "string-tabulate" "abc" (s152:string-tabulate (lambda (i) (integer->char (+ 97 i))) 3))
(test-equal "string-filter" "aa" (s152:string-filter (lambda (c) (char=? c #\a)) "abab"))
(test-equal "string-replace" "aXXd" (s152:string-replace "abcd" "XX" 1 3))
(test-equal "string-reverse via reverse-list->string"
            "cba" (s152:reverse-list->string '(#\a #\b #\c)))
(test-equal "string-fold accumulates left to right"
            '(#\c #\b #\a) (s152:string-fold cons '() "abc"))
(test-equal "string-fold-right accumulates right to left"
            '(#\a #\b #\c) (s152:string-fold-right cons '() "abc"))
(test-equal "string-split on a delimiter" '("a" "b") (s152:string-split "a,b" ","))
(test-equal "string-segment chops into fixed-size pieces" '("ab" "cd" "e")
            (s152:string-segment "abcde" 2))
(test-equal "string-take-while" "ab" (s152:string-take-while "abZd" (lambda (c) (char-lower-case? c))))
(test-equal "string-drop-while" "Zd" (s152:string-drop-while "abZd" (lambda (c) (char-lower-case? c))))
(test-equal "string-span returns the matching prefix"
            "ab" (call-with-values (lambda () (s152:string-span "abZ" char-lower-case?))
                                   (lambda (a b) a)))
(test-equal "string-break returns the non-matching prefix"
            "ab" (call-with-values (lambda () (s152:string-break "abZ" char-upper-case?))
                                   (lambda (a b) a)))
(test-equal "string-unfold" "abc"
            (s152:string-unfold (lambda (i) (= i 3)) (lambda (i) (integer->char (+ 97 i)))
                                (lambda (i) (+ i 1)) 0))
(test-equal "string-unfold-right" "cba"
            (s152:string-unfold-right (lambda (i) (= i 3)) (lambda (i) (integer->char (+ 97 i)))
                                      (lambda (i) (+ i 1)) 0))
;; kaappi#1234's own finding: string-every returns the LAST true value.
(test-equal "string-every returns the last value the predicate produced"
            #\c (s152:string-every (lambda (c) c) "abc"))
(test-equal "string-every on the empty string is #t" #t (s152:string-every (lambda (c) #f) ""))
(test-equal "string-any returns the first true value"
            #\a (s152:string-any (lambda (c) c) "abc"))
(test-equal "string-any on the empty string is #f" #f (s152:string-any (lambda (c) c) ""))

(let ((runner (test-runner-current)))
  (test-end "srfi152 audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
