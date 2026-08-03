;;; Regression tests for quasiquote nesting bugs (#849, #850, #852)

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "quasiquote-nested-849-850-852")

;; === #849: unquote-splicing inside nested quasiquote must decrement depth ===

;; Nested quasiquote with unquote (should remain literal)
(test-equal "nested quasiquote leaves an inner unquote literal"
            '(a (quasiquote (b (unquote (+ 1 2)))))
            `(a `(b ,(+ 1 2))))

;; unquote-splicing at depth 1 decrements to depth 0, so the inner
;; unquote evaluates (+ 1 2) to 3
(test-equal "unquote-splicing at depth 1 decrements for its inner unquote"
            '(a (quasiquote (b (unquote-splicing 3))))
            `(a `(b ,@,(+ 1 2))))

;; unquote-splicing literal at depth 1 (no inner unquote to evaluate)
(test-equal "unquote-splicing at depth 1 with no inner unquote stays literal"
            '(a (quasiquote (b (unquote-splicing (list 1 2)))))
            `(a `(b ,@(list 1 2))))

;; === #850: vector template inside nested quasiquote preserves depth ===

;; Inner unquote at depth 1 inside a vector should remain literal
(test-equal "a vector inside a nested quasiquote preserves depth"
            '(a (quasiquote #(b (unquote (+ 1 2)))))
            `(a `#(b ,(+ 1 2))))

;; Vector at depth 0 should still evaluate unquotes normally
(test-equal "a vector at depth 0 evaluates its unquotes"
            '#(a 3 b)
            `#(a ,(+ 1 2) b))

;; === #852: dotted `. ,expr` tail combined with unquote-splicing ===

;; Dotted unquote tail (no splicing present) -- basic case
(test-equal "dotted unquote tail" '(a 1 2) `(a . ,(list 1 2)))

;; Dotted unquote tail WITH unquote-splicing in the same template
(test-equal "unquote-splicing followed by a dotted unquote tail"
            '(1 2 3 4)
            `(,@(list 1 2) . ,(list 3 4)))

;; Spliced elements before dotted unquote tail, with normal elements too
(test-equal "literal, spliced and dotted-tail elements together"
            '(a 2 3 4 5)
            `(a ,@(list 2 3) . ,(list 4 5)))

(let ((runner (test-runner-current)))
  (test-end "quasiquote-nested-849-850-852")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
