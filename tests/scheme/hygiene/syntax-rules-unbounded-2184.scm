;; Regression test for #2184: syntax-rules silently capped at 32 rules
;; (and 32 literals) with a bare KP2001 InvalidSyntax and no hint. R7RS
;; places no bound on either, and a 33+ rule dispatcher macro is a normal
;; shape (srfi 42's qualifier processor reached 35 before being split).
;;
;; parseSyntaxRules used fixed [32]Value stack buffers and rejected the
;; 33rd rule/literal outright, making a structurally valid macro fail as
;; if malformed. The buffers are now growable, so a 40-rule / 40-literal
;; macro must compile and expand correctly.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "syntax-rules-unbounded")

;;; --- 40 rules: dispatch table that the old 32-cap rejected ---
(define-syntax dispatch
  (syntax-rules ()
    ((_ a) 'a)
    ((_ b) 'b)
    ((_ c) 'c)
    ((_ d) 'd)
    ((_ e) 'e)
    ((_ f) 'f)
    ((_ g) 'g)
    ((_ h) 'h)
    ((_ i) 'i)
    ((_ j) 'j)
    ((_ k) 'k)
    ((_ l) 'l)
    ((_ m) 'm)
    ((_ n) 'n)
    ((_ o) 'o)
    ((_ p) 'p)
    ((_ q) 'q)
    ((_ r) 'r)
    ((_ s) 's)
    ((_ t) 't)
    ((_ u) 'u)
    ((_ v) 'v)
    ((_ w) 'w)
    ((_ x) 'x)
    ((_ y) 'y)
    ((_ z) 'z)
    ((_ aa) 'aa)
    ((_ ab) 'ab)
    ((_ ac) 'ac)
    ((_ ad) 'ad)
    ((_ ae) 'ae)
    ((_ af) 'af)
    ((_ ag) 'ag)
    ((_ ah) 'ah)
    ((_ ai) 'ai)
    ((_ aj) 'aj)
    ((_ ak) 'ak)
    ((_ al) 'al)
    ((_ am) 'am)
    ((_ an) 'an)
    ((_ ao) 'ao)))

(test-equal 'a (dispatch a))
(test-equal 'z (dispatch z))
(test-equal 'ao (dispatch ao))
(test-equal 'an (dispatch an))
(test-equal 'ak (dispatch ak))
(test-equal 'b (dispatch b))

;;; --- 40 literals: the old 32-cap rejected the 33rd literal ---
(define-syntax litmac
  (syntax-rules (l0 l1 l2 l3 l4 l5 l6 l7 l8 l9 l10 l11 l12 l13 l14 l15
                  l16 l17 l18 l19 l20 l21 l22 l23 l24 l25 l26 l27 l28 l29
                  l30 l31 l32 l33 l34 l35 l36 l37 l38 l39)
    ((_ l0) 0) ((_ l1) 1) ((_ l2) 2) ((_ l3) 3) ((_ l4) 4) ((_ l5) 5)
    ((_ l6) 6) ((_ l7) 7) ((_ l8) 8) ((_ l9) 9) ((_ l10) 10) ((_ l11) 11)
    ((_ l12) 12) ((_ l13) 13) ((_ l14) 14) ((_ l15) 15) ((_ l16) 16) ((_ l17) 17)
    ((_ l18) 18) ((_ l19) 19) ((_ l20) 20) ((_ l21) 21) ((_ l22) 22) ((_ l23) 23)
    ((_ l24) 24) ((_ l25) 25) ((_ l26) 26) ((_ l27) 27) ((_ l28) 28) ((_ l29) 29)
    ((_ l30) 30) ((_ l31) 31) ((_ l32) 32) ((_ l33) 33) ((_ l34) 34) ((_ l35) 35)
    ((_ l36) 36) ((_ l37) 37) ((_ l38) 38) ((_ l39) 39)))

(test-equal 0 (litmac l0))
(test-equal 32 (litmac l32))
(test-equal 33 (litmac l33))
(test-equal 39 (litmac l39))
(test-equal 17 (litmac l17))

;;; --- 33 rules inside a define-library (the shape srfi 42 needed) ---
(define-library (t2184 lib)
  (import (scheme base))
  (export op)
  (begin
    (define-syntax op
      (syntax-rules ()
        ((_ 1) 1) ((_ 2) 2) ((_ 3) 3) ((_ 4) 4) ((_ 5) 5) ((_ 6) 6)
        ((_ 7) 7) ((_ 8) 8) ((_ 9) 9) ((_ 10) 10) ((_ 11) 11) ((_ 12) 12)
        ((_ 13) 13) ((_ 14) 14) ((_ 15) 15) ((_ 16) 16) ((_ 17) 17) ((_ 18) 18)
        ((_ 19) 19) ((_ 20) 20) ((_ 21) 21) ((_ 22) 22) ((_ 23) 23) ((_ 24) 24)
        ((_ 25) 25) ((_ 26) 26) ((_ 27) 27) ((_ 28) 28) ((_ 29) 29) ((_ 30) 30)
        ((_ 31) 31) ((_ 32) 32) ((_ 33) 33)))))
(import (t2184 lib))
(test-equal 33 (op 33))
(test-equal 1 (op 1))

(let ((runner (test-runner-current)))
  (test-end "syntax-rules-unbounded")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
