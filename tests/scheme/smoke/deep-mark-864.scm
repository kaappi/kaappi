;; Regression test for issue #864: GC markValue stack overflow on deeply
;; nested pair structures.  Both car and cdr are heap pointers at every
;; level, so the old recursive markValue would overflow the native stack.

;; Build a deep structure where both car and cdr are heap pointers.
;; With 100k levels and GC threshold at 8192, collections will fire
;; many times while the deep structure is live, exercising markValue.
(define (build n acc)
  (if (= n 0) acc (build (- n 1) (cons acc (cons 1 2)))))

(define deep (build 100000 '()))

(display (pair? deep))
(newline)
