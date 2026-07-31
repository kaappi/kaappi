;; Probe: the `ir.isRedefined` guard shared by constant folding, boolean
;; simplification and identity elimination.
;;
;; All three passes recognise a call by the SPELLING of its operator symbol
;; (`"+"`, `"not"`, `"*"`, ...).  Every one of them consults `isRedefined`
;; first.  If that check is ever missed for a name, the optimised tier folds
;; a call to a procedure the program has replaced, while `--no-ir-opt` calls
;; the user's version — a silent wrong answer with no error anywhere.
;;
;; Each section redefines a name and then calls it in exactly the shape the
;; corresponding pass looks for.

;; --- redefine BEFORE use -------------------------------------------------
(define (add1-ish a b) (list 'user a b))
(define + add1-ish)
(display (+ 1 2)) (newline)

(define (times-ish a b) (list 'user* a b))
(define * times-ish)
(display (* 6 7)) (newline)
(display (* 6 1)) (newline)
(display (* 6 0)) (newline)

(define (lt-ish a b) 'user<)
(define < lt-ish)
(display (< 1 2)) (newline)
(if (< 1 2) (begin (display "lt-then") (newline)) (begin (display "lt-else") (newline)))

;; --- `not` drives the boolean-simplify rewrite ---------------------------
(define (not-ish x) 'user-not)
(define not not-ish)
(display (not #f)) (newline)
(if (not #f) (begin (display "n-then") (newline)) (begin (display "n-else") (newline)))
(if (not #t) (begin (display "n2-then") (newline)) (begin (display "n2-else") (newline)))

;; --- `set!` on a builtin name, rather than `define` ----------------------
(define (zero-ish x) 'user-zero)
(set! zero? zero-ish)
(display (zero? 0)) (newline)
(if (zero? 0) (begin (display "z-then") (newline)) (begin (display "z-else") (newline)))

;; --- redefinition AFTER the use site.  The uses above already ran; these
;; check the pass does not retroactively treat a later `define` as licence to
;; fold earlier calls (or refuse to fold ones that were still builtin).
(display (- 10 4)) (newline)
(define (sub-ish a b) 'user-)
(define - sub-ish)
(display (- 10 4)) (newline)
