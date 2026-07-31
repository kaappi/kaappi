;; Probe: dead branch elimination (ir.eliminateDeadBranches).
;;
;; Top-level `if` whose test folds to a constant.  R7RS §6.3: EVERY value
;; except `#f` is true — `0`, `'()`, `""`, `#\nul` and `0.0` are all true.
;; An eliminator that used a C-style truthiness test would silently pick the
;; wrong branch, and only `--no-ir-opt` would still print the right answer.

;; --- literal #t / #f ------------------------------------------------------
(if #t (begin (display "t-then") (newline)) (begin (display "t-else") (newline)))
(if #f (begin (display "f-then") (newline)) (begin (display "f-else") (newline)))
(if #t (begin (display "no-alt") (newline)))
(if #f (begin (display "unreachable") (newline)))

;; --- everything-but-#f is true (R7RS 6.3) --------------------------------
(if 0 (begin (display "zero-true") (newline)) (begin (display "zero-FALSE") (newline)))
(if 0.0 (begin (display "flzero-true") (newline)) (begin (display "flzero-FALSE") (newline)))
(if "" (begin (display "emptystr-true") (newline)) (begin (display "emptystr-FALSE") (newline)))
(if '() (begin (display "nil-true") (newline)) (begin (display "nil-FALSE") (newline)))
(if #\null (begin (display "nullchar-true") (newline)) (begin (display "nullchar-FALSE") (newline)))

;; --- a folded test drives the elimination --------------------------------
(if (= 1 1) (begin (display "eq-then") (newline)) (begin (display "eq-else") (newline)))
(if (< 2 1) (begin (display "lt-then") (newline)) (begin (display "lt-else") (newline)))

;; --- the dead arm must not be evaluated (side effect, not just a value) --
(if #t (begin (display "live-arm") (newline)) (begin (display "DEAD-ARM-RAN") (newline)))
(if #f (begin (display "DEAD-ARM-RAN") (newline)) (begin (display "live-arm2") (newline)))

;; --- a dead arm containing an ERROR must stay unevaluated ----------------
(if #t (begin (display "no-error") (newline)) (car '()))
(if #f (car '()) (begin (display "no-error2") (newline)))

;; --- nested, so elimination has to recurse -------------------------------
(if #t
    (if #f
        (begin (display "NESTED-WRONG") (newline))
        (if #t (begin (display "nested-ok") (newline)) (begin (display "NESTED-WRONG") (newline))))
    (begin (display "NESTED-WRONG") (newline)))

;; --- `(if #f X)` with no alternate yields the unspecified value ----------
(display (if #f #f)) (newline)
(write (if #f #f)) (newline)
