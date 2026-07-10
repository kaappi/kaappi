;; SRFI-43 (vector library) conformance tests
;; Covers index-passing callback convention and all exported procedures.
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi43.scm

(import (scheme base) (srfi 43) (scheme process-context) (srfi 64))

(test-begin "srfi-43")

;;; --- constructors ---
(test-equal #(0 0) (make-vector 2 0))
(test-equal #(1 2 3) (vector 1 2 3))
(test-equal #(0 1 2) (vector-unfold (lambda (i) (values i)) 3))
(test-equal #(0 1 2) (vector-unfold (lambda (i x) (values x (+ x 1))) 3 0))
(test-equal #(2 1 0) (vector-unfold-right (lambda (i x) (values x (+ x 1))) 3 0))
(test-equal #(0 1 2) (vector-unfold-right (lambda (i) (values i)) 3))
(test-equal #(1 2 3 4) (vector-append #(1 2) #(3 4)))
(test-equal #(1 2 3 4) (vector-concatenate (list #(1 2) #(3 4))))
(test-equal #(1 2) (vector-copy #(1 2)))
(test-equal #(3 2 1) (vector-reverse-copy #(1 2 3)))

;;; --- predicates ---
(test-equal #t (vector? #()))
(test-equal #f (vector? 42))
(test-equal #t (vector-empty? #()))
(test-equal #f (vector-empty? #(1)))
(test-equal #t (vector= eqv? #(1 2) #(1 2)))
(test-equal #f (vector= eqv? #(1 2) #(1 3)))
(test-equal #t (vector= eqv? #() #()))
(test-equal #t (vector= eqv?))
(test-equal #t (vector= eqv? #(1)))

;;; --- selectors ---
(test-equal 2 (vector-ref #(1 2 3) 1))
(test-equal 3 (vector-length #(1 2 3)))

;;; --- iteration: index-passing callbacks (core of #1209) ---

;; vector-map: (f i elt ...) -> vector
(test-equal #(10 11 12) (vector-map (lambda (i x) (+ i x)) #(10 10 10)))
(test-equal #(a b c) (vector-map (lambda (i x) x) #(a b c)))
;; multi-vector
(test-equal #(0 2 4) (vector-map (lambda (i a b) (+ a b)) #(0 1 2) #(0 1 2)))

;; vector-map!: (f i elt ...) -> void, mutates first vector
(test-equal #(10 12 14) (let ((v (vector 10 11 12)))
                          (vector-map! (lambda (i x) (+ x i)) v)
                          v))
;; multi-vector map!
(test-equal #(5 7 9) (let ((v (vector 1 2 3)))
                       (vector-map! (lambda (i a b) (+ a b)) v #(4 5 6))
                       v))

;; vector-for-each: (f i elt ...) -> void
(test-equal '((0 . a) (1 . b))
            (let ((acc '()))
              (vector-for-each (lambda (i x) (set! acc (cons (cons i x) acc))) #(a b))
              (reverse acc)))
;; multi-vector for-each
(test-equal '((0 1 4) (1 2 5) (2 3 6))
            (let ((acc '()))
              (vector-for-each (lambda (i a b) (set! acc (cons (list i a b) acc)))
                               #(1 2 3) #(4 5 6))
              (reverse acc)))

;; vector-fold: (kons i state elt ...) -> value
(test-equal '(c b a) (vector-fold (lambda (i state x) (cons x state)) '() #(a b c)))
(test-equal '((2 . c) (1 . b) (0 . a))
            (vector-fold (lambda (i state x) (cons (cons i x) state)) '() #(a b c)))
;; multi-vector fold
(test-equal 9 (vector-fold (lambda (i state a b) (+ state a b)) 0 #(1 1 1) #(2 2 2)))

;; vector-fold-right: (kons i state elt ...) -> value, right to left
(test-equal '(a b c) (vector-fold-right (lambda (i state x) (cons x state)) '() #(a b c)))
(test-equal '((0 . a) (1 . b) (2 . c))
            (vector-fold-right (lambda (i state x) (cons (cons i x) state)) '() #(a b c)))

;; vector-count: (pred? i elt ...) -> integer
(test-equal 2 (vector-count (lambda (i x) (even? x)) #(1 2 4)))
(test-equal 0 (vector-count (lambda (i x) (even? x)) #(1 3 5)))
;; count using index
(test-equal 3 (vector-count (lambda (i x) (= i x)) #(0 1 2)))
;; multi-vector count
(test-equal 2 (vector-count (lambda (i a b) (= a b)) #(1 2 3) #(1 9 3)))

;;; --- searching (element-only callbacks, same as SRFI-133) ---
(test-equal 1 (vector-index even? #(1 2 3)))
(test-equal #f (vector-index even? #(1 3 5)))
(test-equal 2 (vector-index-right even? #(2 1 4 5)))
(test-equal 1 (vector-skip odd? #(1 2 3)))
(test-equal 1 (vector-skip-right odd? #(1 2 5)))
(test-equal #t (vector-any even? #(1 2 3)))
(test-equal #f (vector-any even? #(1 3 5)))
(test-equal #t (vector-every odd? #(1 3 5)))
(test-equal #f (vector-every odd? #(1 2 5)))
(test-equal 1 (vector-binary-search #(1 3 5 7 9) 3
                (lambda (x y) (- x y))))
(test-equal #f (vector-binary-search #(1 3 5 7 9) 4
                 (lambda (x y) (- x y))))

;;; --- mutators ---
(test-equal #(9 2 1) (let ((v (vector 1 2 9))) (vector-swap! v 0 2) v))
(test-equal #(7 7 7) (let ((v (vector 1 2 3))) (vector-fill! v 7) v))
(test-equal #(3 2 1) (let ((v (vector 1 2 3))) (vector-reverse! v) v))
(test-equal #(1 3 2) (let ((v (vector 1 2 3))) (vector-reverse! v 1) v))
(test-equal #(5 6 3) (let ((v (vector 1 2 3))) (vector-copy! v 0 #(5 6)) v))
(test-equal #(1 6 5) (let ((v (vector 1 2 3)))
                       (vector-reverse-copy! v 1 #(5 6))
                       v))

;;; --- conversion ---
(test-equal '(1 2 3) (vector->list #(1 2 3)))
(test-equal #(1 2 3) (list->vector '(1 2 3)))
(test-equal '(3 2 1) (reverse-vector->list #(1 2 3)))
(test-equal '(2 1) (reverse-vector->list #(1 2 3) 0 2))
(test-equal #(3 2 1) (reverse-list->vector '(1 2 3)))

(let ((runner (test-runner-current)))
  (test-end "srfi-43")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
