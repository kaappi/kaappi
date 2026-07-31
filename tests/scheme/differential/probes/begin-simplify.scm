;; Probe: begin simplification (ir.simplifyBegin) and the order of effects.
;;
;; Flattening `(begin A (begin B C))` into `(begin A B C)` is only sound if
;; every effect keeps its position and the value of the whole form is still
;; the LAST subform's value.  A single-subform `begin` collapsing to its
;; subform, and a `begin` in value position, are the cases where an
;; over-eager pass changes an answer rather than just a shape.

;; --- effect order across nesting -----------------------------------------
(begin (display "a") (begin (display "b") (display "c")) (display "d")) (newline)
(begin (begin (begin (display "deep")))) (newline)
(begin (display 1) (display 2) (display 3) (display 4) (display 5)) (newline)

;; --- value of a `begin` is its last subform ------------------------------
(display (begin 1 2 3)) (newline)
(display (begin (display "[eff]") 42)) (newline)
(display (begin 'only)) (newline)
(write (begin "str")) (newline)

;; --- a `begin` whose last subform is a `define`-free tail ----------------
(display (begin (+ 1 1) (* 2 2) (- 9 3))) (newline)

;; --- interleaving with `if`, so both passes see the same tree ------------
(begin
  (if #t (display "bi-then") (display "bi-else"))
  (newline)
  (begin
    (if #f (display "bi2-then") (display "bi2-else"))
    (newline)))

;; --- a `begin` that raises partway: the prefix effects must already have
;; happened, and the suffix must not.
(display "pre") (newline)
(begin (display "x") (newline) (car '()) (display "MUST-NOT-PRINT") (newline))
(display "post") (newline)
