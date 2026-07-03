;;; Regression tests for quasiquote nesting bugs (#849, #850, #852)

;; === #849: unquote-splicing inside nested quasiquote must decrement depth ===

;; Nested quasiquote with unquote (should remain literal)
(display (equal? `(a `(b ,(+ 1 2))) '(a (quasiquote (b (unquote (+ 1 2)))))))
(newline)

;; unquote-splicing at depth 1 decrements to depth 0, so the inner
;; unquote evaluates (+ 1 2) to 3
(display (equal? `(a `(b ,@,(+ 1 2))) '(a (quasiquote (b (unquote-splicing 3))))))
(newline)

;; unquote-splicing literal at depth 1 (no inner unquote to evaluate)
(display (equal? `(a `(b ,@(list 1 2))) '(a (quasiquote (b (unquote-splicing (list 1 2)))))))
(newline)

;; === #850: vector template inside nested quasiquote preserves depth ===

;; Inner unquote at depth 1 inside a vector should remain literal
(display (equal? `(a `#(b ,(+ 1 2))) '(a (quasiquote #(b (unquote (+ 1 2)))))))
(newline)

;; Vector at depth 0 should still evaluate unquotes normally
(display (equal? `#(a ,(+ 1 2) b) '#(a 3 b)))
(newline)

;; === #852: dotted `. ,expr` tail combined with unquote-splicing ===

;; Dotted unquote tail (no splicing present) -- basic case
(display (equal? `(a . ,(list 1 2)) '(a 1 2)))
(newline)

;; Dotted unquote tail WITH unquote-splicing in the same template
(display (equal? `(,@(list 1 2) . ,(list 3 4)) '(1 2 3 4)))
(newline)

;; Spliced elements before dotted unquote tail, with normal elements too
(display (equal? `(a ,@(list 2 3) . ,(list 4 5)) '(a 2 3 4 5)))
(newline)
