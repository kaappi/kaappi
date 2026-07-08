(import (scheme base) (scheme write) (srfi 133))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))
(define (check-true name val)
  (if val (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))
(define (check-false name val)
  (if (not val) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

;;; vector-empty?
(check-true "empty?" (vector-empty? (vector)))
(check-false "empty? non" (vector-empty? (vector 1)))

;;; vector-count
(check "count even" (vector-count even? (vector 1 2 3 4 5)) 2)
(check "count none" (vector-count (lambda (x) (> x 10)) (vector 1 2 3)) 0)
(check "count all" (vector-count positive? (vector 1 2 3)) 3)

;;; vector-any / vector-every
(check-true "any even" (vector-any even? (vector 1 3 4 5)))
(check-false "any miss" (vector-any even? (vector 1 3 5)))
(check-true "every pos" (vector-every positive? (vector 1 2 3)))
(check-false "every fail" (vector-every even? (vector 2 3 4)))

;;; vector-index / vector-index-right
(check "index" (vector-index even? (vector 1 3 4 5)) 2)
(check-false "index miss" (vector-index even? (vector 1 3 5)))
(check "index-right" (vector-index-right even? (vector 2 3 4)) 2)

;;; vector-skip / vector-skip-right
(check "skip" (vector-skip even? (vector 2 4 5 6)) 2)
(check-false "skip all match" (vector-skip even? (vector 2 4 6)))
(check "skip-right" (vector-skip-right even? (vector 1 2 3)) 2)

;;; vector-swap!
(let ((v (vector 1 2 3)))
  (vector-swap! v 0 2)
  (check "swap" v (vector 3 2 1)))

;;; vector-reverse!
(let ((v (vector 1 2 3 4 5)))
  (vector-reverse! v)
  (check "reverse!" v (vector 5 4 3 2 1)))

(let ((v (vector 1 2 3 4 5)))
  (vector-reverse! v 1 4)
  (check "reverse! range" v (vector 1 4 3 2 5)))

;;; vector-reverse-copy
(check "reverse-copy" (vector-reverse-copy (vector 1 2 3)) (vector 3 2 1))
(check "reverse-copy range" (vector-reverse-copy (vector 1 2 3 4 5) 1 4) (vector 4 3 2))

;;; vector-unfold
(check "unfold" (vector-unfold (lambda (i) (values (* i i))) 5) (vector 0 1 4 9 16))
(check "unfold seed" (vector-unfold (lambda (i seed) (values seed (* seed 2))) 4 1)
       (vector 1 2 4 8))

;;; vector-concatenate
(check "concatenate" (vector-concatenate (list (vector 1 2) (vector 3 4) (vector 5)))
       (vector 1 2 3 4 5))
(check "concatenate empty" (vector-concatenate '()) (vector))

;;; vector-cumulate
(check "cumulate" (vector-cumulate + 0 (vector 1 2 3 4 5)) (vector 1 3 6 10 15))
(check "cumulate *" (vector-cumulate * 1 (vector 1 2 3 4)) (vector 1 2 6 24))

;;; vector-partition
;; Per SRFI 133, the first value is a vector the SAME SIZE as the input —
;; satisfying elements first (in order), then the rest (in order). The
;; second value is the count of satisfying elements.
(let-values (((part count) (vector-partition even? (vector 1 2 3 4 5))))
  (check "partition count" count 2)
  (check "partition vec" part (vector 2 4 1 3 5)))
(let-values (((part count) (vector-partition even? (vector 2 4 6))))
  (check "partition all count" count 3)
  (check "partition all vec" part (vector 2 4 6)))
(let-values (((part count) (vector-partition even? (vector 1 3 5))))
  (check "partition none count" count 0)
  (check "partition none vec" part (vector 1 3 5)))
(let-values (((part count) (vector-partition even? (vector))))
  (check "partition empty count" count 0)
  (check "partition empty vec" part (vector)))

;;; Standard ops (re-exported)
(check "vector" (vector 1 2 3) #(1 2 3))
(check "make-vector" (make-vector 3 0) #(0 0 0))
(check-true "vector?" (vector? (vector)))
(check "vector-length" (vector-length (vector 1 2 3)) 3)
(check "vector-ref" (vector-ref (vector 10 20 30) 1) 20)
(check "vector->list" (vector->list (vector 1 2 3)) '(1 2 3))
(check "list->vector" (list->vector '(1 2 3)) #(1 2 3))
(check "vector-copy" (vector-copy (vector 1 2 3)) #(1 2 3))
(check "vector-append" (vector-append (vector 1 2) (vector 3 4)) #(1 2 3 4))

;;; vector-for-each / vector-map
(let ((sum 0))
  (vector-for-each (lambda (x) (set! sum (+ sum x))) (vector 1 2 3))
  (check "for-each sum" sum 6))
(check "map" (vector-map (lambda (x) (* x 2)) (vector 1 2 3)) #(2 4 6))

;;; vector= (#1172)
(check-true "vector= empty" (vector= eq?))
(check-true "vector= one" (vector= eq? (vector 1 2)))
(check-true "vector= same" (vector= = (vector 1 2 3) (vector 1 2 3)))
(check-false "vector= diff val" (vector= = (vector 1 2 3) (vector 1 9 3)))
(check-false "vector= diff len" (vector= = (vector 1 2) (vector 1 2 3)))
(check-true "vector= three" (vector= = (vector 1) (vector 1) (vector 1)))
(check-false "vector= three fail" (vector= = (vector 1) (vector 1) (vector 2)))
(check-true "vector= custom" (vector= (lambda (a b) (= (modulo a 2) (modulo b 2)))
                                       (vector 1 2 3) (vector 3 4 5)))

;;; vector-fold (#1172)
(check "fold sum" (vector-fold + 0 (vector 1 2 3)) 6)
(check "fold cons" (vector-fold (lambda (acc x) (cons x acc)) '() (vector 1 2 3))
       '(3 2 1))
(check "fold empty" (vector-fold + 0 (vector)) 0)
(check "fold multi" (vector-fold (lambda (acc a b) (+ acc (* a b))) 0
                                 (vector 1 2 3) (vector 4 5 6))
       32)

;;; vector-fold-right (#1172)
(check "fold-right cons" (vector-fold-right (lambda (acc x) (cons x acc)) '()
                                            (vector 1 2 3))
       '(1 2 3))
(check "fold-right empty" (vector-fold-right + 0 (vector)) 0)
(check "fold-right multi" (vector-fold-right (lambda (acc a b) (cons (list a b) acc)) '()
                                             (vector 1 2 3) (vector 4 5 6))
       '((1 4) (2 5) (3 6)))

;;; vector-map! (#1172)
(let ((v (vector 1 2 3)))
  (vector-map! - v)
  (check "map! negate" v (vector -1 -2 -3)))
(let ((v (vector 1 2 3)))
  (vector-map! + v (vector 10 20 30))
  (check "map! multi" v (vector 11 22 33)))
(let ((v (vector 1 2 3)))
  (vector-map! values v)
  (check "map! identity" v (vector 1 2 3)))

;;; vector-reverse-copy! (#1172)
(let ((to (make-vector 5 0))
      (from (vector 1 2 3 4 5)))
  (vector-reverse-copy! to 0 from)
  (check "reverse-copy! full" to (vector 5 4 3 2 1)))
(let ((to (make-vector 5 0)))
  (vector-reverse-copy! to 1 (vector 10 20 30) 0 3)
  (check "reverse-copy! range" to (vector 0 30 20 10 0)))
(let ((to (make-vector 3 0)))
  (vector-reverse-copy! to 0 (vector 1 2 3 4 5) 1 4)
  (check "reverse-copy! subrange" to (vector 4 3 2)))

;;; vector-unfold! (#1172)
(let ((v (make-vector 5 0)))
  (vector-unfold! (lambda (i) (* i 10)) v 1 4)
  (check "unfold! basic" v (vector 0 10 20 30 0)))
(let ((v (make-vector 3 #f)))
  (vector-unfold! (lambda (i seed) (values seed (* seed 2))) v 0 3 1)
  (check "unfold! seed" v (vector 1 2 4)))

;;; vector-unfold-right! (#1172)
(let ((v (make-vector 3 #f)))
  (vector-unfold-right! (lambda (i seed) (values seed (* seed 2))) v 0 3 1)
  (check "unfold-right! seed" v (vector 4 2 1)))
(let ((v (make-vector 5 0)))
  (vector-unfold-right! (lambda (i) (* i i)) v 1 4)
  (check "unfold-right! basic" v (vector 0 1 4 9 0)))

;;; reverse-vector->list (#1172)
(check "rev-vec->list" (reverse-vector->list (vector 1 2 3)) '(3 2 1))
(check "rev-vec->list empty" (reverse-vector->list (vector)) '())
(check "rev-vec->list range" (reverse-vector->list (vector 1 2 3 4 5) 1 4) '(4 3 2))

;;; reverse-list->vector (#1172)
(check "rev-list->vec" (reverse-list->vector '(1 2 3)) #(3 2 1))
(check "rev-list->vec empty" (reverse-list->vector '()) #())
(check "rev-list->vec single" (reverse-list->vector '(42)) #(42))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI 133 extended tests failed" fail))
