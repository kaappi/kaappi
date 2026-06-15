;; apply tests
(display (apply + '(1 2 3)))    ;; => 6
(newline)
(display (apply + 1 2 '(3 4))) ;; => 10
(newline)
(display (apply cons 1 '(2)))  ;; => (1 . 2)
(newline)
