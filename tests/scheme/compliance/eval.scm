;;; Eval library compliance tests (R7RS 6.5)

;; eval basic expression
(display (eval '(+ 1 2)))  ; => 3
(newline)

;; eval with environment (environment is a no-op for now)
(display (eval '(* 3 4) (environment '(scheme base))))  ; => 12
(newline)

;; eval quoted list
(display (eval '(list 1 2 3)))  ; => (1 2 3)
(newline)
