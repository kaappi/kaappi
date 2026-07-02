;; Regression tests for #865 (magnitude on rationals) and #834 (car/cdr type error)

;; #865: magnitude on exact rationals should preserve exactness
(display (= (magnitude -1/2) 1/2))   (newline)
(display (= (magnitude 1/2) 1/2))    (newline)
(display (exact? (magnitude -1/2)))   (newline)
(display (= (magnitude -5) 5))       (newline)
(display (= (magnitude 3.0) 3.0))    (newline)
