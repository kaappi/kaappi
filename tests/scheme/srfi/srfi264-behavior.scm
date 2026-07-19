;; SRFI-264 behavioral tests — end-to-end integration beyond the upstream
;; parser/unparser corpus in srfi264.scm: compiling SSRE to a live SRFI-115
;; regexp and matching, the ssre-bind/ssre-unbind definition lifecycle, and
;; proper error objects on malformed syntax.
;;
;; Match tests use only greedy quantifiers: Kaappi's SRFI 115 does not yet
;; support non-greedy SREs (`**?`), so `ssre->regexp` on e.g. "a+?" raises
;; "unknown SRE **?" — a 115 limitation, orthogonal to SSRE translation itself
;; (`ssre->sre` still produces the correct `(**? ...)` SRE).

(import (scheme base) (scheme write) (srfi 115) (srfi 264)
        (scheme process-context) (srfi 64))

(test-begin "srfi-264-behavior")

;;; --- ssre->regexp compiles and matches through SRFI 115 ---
(define (matches? pat str) (and (regexp-search (ssre->regexp pat) str) #t))

(test-equal "digits match"       #t (matches? "[[:digit:]]+" "abc123"))
(test-equal "digits no match"    #f (matches? "[[:digit:]]+" "abcxyz"))
(test-equal "alternation cat"    #t (matches? "cat|dog" "a cat"))
(test-equal "alternation none"   #f (matches? "cat|dog" "a bird"))
(test-equal "anchored group"     #t (matches? "^(ab)+$" "ababab"))
(test-equal "anchored group no"  #f (matches? "^(ab)+$" "abx"))
(test-equal "bounded repeat"     #t (matches? "^a{2,4}$" "aaa"))
(test-equal "bounded too many"   #f (matches? "^a{2,4}$" "aaaaa"))
(test-equal "open repeat {m,}"   #t (matches? "^a{2,}$" "aaaaaa"))

;; submatch extraction by index (named-group lookup by *symbol* is a separate,
;; pre-existing SRFI-115 gap, so we index positionally here)
(let ((m (regexp-search (ssre->regexp "([[:digit:]]+)-([[:digit:]]+)") "42-99")))
  (test-equal "submatch 1" "42" (regexp-match-submatch m 1))
  (test-equal "submatch 2" "99" (regexp-match-submatch m 2)))

;;; --- ssre-definitions / ssre-bind / ssre-unbind lifecycle ---
;; A name resolves only while bound; unbinding removes it. parameterize keeps
;; the global ssre-definitions parameter pristine for the rest of the suite.
(parameterize ((ssre-definitions
                 (ssre-bind 'ab 'e '(: "a" "b") (ssre-definitions))))
  (test-equal "bound name expands" '(+ (: "a" "b")) (ssre->sre "{ab}+"))
  (parameterize ((ssre-definitions (ssre-unbind 'ab (ssre-definitions))))
    (test-error "unbound name errors" (ssre->sre "{ab}+"))))

;; outside the parameterize scope the name never existed
(test-error "name gone after scope" (ssre->sre "{ab}+"))

;;; --- malformed syntax yields a proper error object ---
;; Regression for the ssre-syntax-error? guard: a syntax error must surface as
;; an error-object formatted by ssre-fancy-error (prefix "ssre->sre: "), not a
;; raw list escaping the guard.
(test-assert "syntax error is a proper error-object"
  (guard (e (#t (and (error-object? e)
                     (let ((m (error-object-message e)))
                       (and (string? m)
                            (>= (string-length m) 9)
                            (string=? (substring m 0 9) "ssre->sre"))))))
    (ssre->sre "a{")
    #f))

(let ((runner (test-runner-current)))
  (test-end "srfi-264-behavior")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
