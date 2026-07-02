;; Regression test for #837: round on negative exact rationals with
;; fraction < 1/2 rounds away from zero instead of toward it.

;; Fraction < 1/2 — should round toward zero
(display (= (round -1/3) 0))   (newline)
(display (= (round -1/4) 0))   (newline)
(display (= (round -4/3) -1))  (newline)

;; Fraction > 1/2 — should round away from zero
(display (= (round -2/3) -1))  (newline)
(display (= (round -5/3) -2))  (newline)

;; Ties to even
(display (= (round -5/2) -2))  (newline)
(display (= (round -7/2) -4))  (newline)
(display (= (round -3/2) -2))  (newline)

;; Positive rationals (sanity check)
(display (= (round 1/3) 0))    (newline)
(display (= (round 2/3) 1))    (newline)
(display (= (round 5/2) 2))    (newline)
