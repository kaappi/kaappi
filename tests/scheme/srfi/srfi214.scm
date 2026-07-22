;; SRFI-214 (flexvectors) conformance tests
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi214.scm

(import (scheme base) (srfi 214) (scheme process-context) (srfi 64) (srfi 1) (srfi 158))

(test-begin "srfi-214")

;;; --- constructors ---

(test-equal #t (flexvector? (make-flexvector 3)))
(test-equal 3 (flexvector-length (make-flexvector 3)))
(test-equal '(3 3 3) (flexvector->list (make-flexvector 3 3)))
(test-equal '() (flexvector->list (make-flexvector 0)))
(test-equal '(1 2 3) (flexvector->list (flexvector 1 2 3)))
(test-equal 0 (flexvector-length (flexvector)))

;; flexvector-unfold: spec worked example
(test-equal '(1 4 9 16 25 36 49 64 81 100)
            (flexvector->list
              (flexvector-unfold (lambda (x) (> x 10)) (lambda (x) (* x x)) (lambda (x) (+ x 1)) 1)))

;; flexvector-unfold-right: last generated element ends up first
(test-equal '(100 81 64 49 36 25 16 9 4 1)
            (flexvector->list
              (flexvector-unfold-right (lambda (x) (> x 10)) (lambda (x) (* x x)) (lambda (x) (+ x 1)) 1)))

;; flexvector-copy: spec worked example
(test-equal '(b c) (flexvector->list (flexvector-copy (flexvector 'a 'b 'c) 1)))
(test-equal '(a b c) (flexvector->list (flexvector-copy (flexvector 'a 'b 'c))))
(test-equal '(b) (flexvector->list (flexvector-copy (flexvector 'a 'b 'c) 1 2)))

(test-equal '(c b a) (flexvector->list (flexvector-reverse-copy (flexvector 'a 'b 'c))))
(test-equal '(c b) (flexvector->list (flexvector-reverse-copy (flexvector 'a 'b 'c) 1)))

(test-equal '(1 2 3 4) (flexvector->list (flexvector-append (flexvector 1 2) (flexvector 3 4))))
(test-equal '() (flexvector->list (flexvector-append)))
(test-equal '(1 2 3 4 5 6)
            (flexvector->list (flexvector-concatenate (list (flexvector 1 2) (flexvector 3 4) (flexvector 5 6)))))

;; flexvector-append-subvectors: spec worked example
(test-equal '(a b h i)
            (flexvector->list
              (flexvector-append-subvectors (flexvector 'a 'b 'c 'd 'e) 0 2
                                             (flexvector 'f 'g 'h 'i 'j) 2 4)))

;;; --- predicates ---

(test-equal #f (flexvector? (vector 1 2 3)))
(test-equal #t (flexvector-empty? (make-flexvector 0)))
(test-equal #f (flexvector-empty? (flexvector 1)))
(test-equal #t (flexvector=? = (flexvector 1 2 3) (flexvector 1 2 3)))
(test-equal #f (flexvector=? = (flexvector 1 2 3) (flexvector 1 2)))
(test-equal #f (flexvector=? = (flexvector 1 2 3) (flexvector 1 2 4)))
(test-equal #t (flexvector=? =))
(test-equal #t (flexvector=? = (flexvector 1 2)))
(test-equal #t (flexvector=? = (flexvector 1 2) (flexvector 1 2) (flexvector 1 2)))
(test-equal #f (flexvector=? = (flexvector 1 2) (flexvector 1 2) (flexvector 9 9)))

;;; --- selectors ---

(test-equal 2 (flexvector-ref (flexvector 1 2 3) 1))
(test-equal 1 (flexvector-front (flexvector 1 2 3)))
(test-equal 3 (flexvector-back (flexvector 1 2 3)))
(test-equal #t (guard (e (#t #t)) (flexvector-ref (flexvector 1 2 3) 5) #f))
(test-equal #t (guard (e (#t #t)) (flexvector-front (make-flexvector 0)) #f))
(test-equal #t (guard (e (#t #t)) (flexvector-back (make-flexvector 0)) #f))

;;; --- mutators: add ---

(let ((fv (flexvector 1 2 3)))
  (test-equal fv (flexvector-add! fv 1 'x 'y))
  (test-equal '(1 x y 2 3) (flexvector->list fv)))

(let ((fv (flexvector 1 2 3)))
  (flexvector-add-front! fv 'a 'b)
  (test-equal '(a b 1 2 3) (flexvector->list fv)))

(let ((fv (flexvector 1 2 3)))
  (flexvector-add-back! fv 'a 'b)
  (test-equal '(1 2 3 a b) (flexvector->list fv)))

(let ((fv (flexvector 1 2 3)))
  (flexvector-add-all! fv 1 '(x y z))
  (test-equal '(1 x y z 2 3) (flexvector->list fv)))

;; growth past initial capacity: add-back! many times, verify content intact
(let ((fv (make-flexvector 0)))
  (let loop ((i 0))
    (when (< i 200)
      (flexvector-add-back! fv i)
      (loop (+ i 1))))
  (test-equal 200 (flexvector-length fv))
  (test-equal 0 (flexvector-ref fv 0))
  (test-equal 199 (flexvector-ref fv 199))
  (test-equal (iota 200) (flexvector->list fv)))

;; add! at index 0 / at length behave like add-front!/add-back!
(let ((fv (flexvector 1 2 3)))
  (flexvector-add! fv 0 'z)
  (test-equal '(z 1 2 3) (flexvector->list fv)))
(let ((fv (flexvector 1 2 3)))
  (flexvector-add! fv 3 'z)
  (test-equal '(1 2 3 z) (flexvector->list fv)))

(let ((fv1 (flexvector 1 2)) (fv2 (flexvector 3 4)) (fv3 (flexvector 5 6)))
  (flexvector-append! fv1 fv2 fv3)
  (test-equal '(1 2 3 4 5 6) (flexvector->list fv1))
  ;; fv2, fv3 unaffected
  (test-equal '(3 4) (flexvector->list fv2)))

;;; --- mutators: remove ---

(let ((fv (flexvector 1 2 3 4)))
  (test-equal 2 (flexvector-remove! fv 1))
  (test-equal '(1 3 4) (flexvector->list fv)))

(let ((fv (flexvector 1 2 3)))
  (test-equal 1 (flexvector-remove-front! fv))
  (test-equal '(2 3) (flexvector->list fv)))

(let ((fv (flexvector 1 2 3)))
  (test-equal 3 (flexvector-remove-back! fv))
  (test-equal '(1 2) (flexvector->list fv)))

(let ((fv (flexvector 1 2 3 4 5)))
  (flexvector-remove-range! fv 1 3)
  (test-equal '(1 4 5) (flexvector->list fv)))

(let ((fv (flexvector 1 2 3 4 5)))
  (flexvector-remove-range! fv 3)
  (test-equal '(1 2 3) (flexvector->list fv)))

(let ((fv (flexvector 1 2 3)))
  (flexvector-clear! fv)
  (test-equal 0 (flexvector-length fv))
  (test-equal '() (flexvector->list fv))
  ;; still usable afterward
  (flexvector-add-back! fv 'a)
  (test-equal '(a) (flexvector->list fv)))

;;; --- mutators: set!/swap!/fill!/reverse!/copy! ---

(let ((fv (flexvector 1 2 3)))
  (test-equal 2 (flexvector-set! fv 1 'x))
  (test-equal '(1 x 3) (flexvector->list fv)))

;; setting at length acts like add-back!
(let ((fv (flexvector 1 2 3)))
  (flexvector-set! fv 3 'x)
  (test-equal '(1 2 3 x) (flexvector->list fv)))

(let ((fv (flexvector 1 2 3)))
  (flexvector-swap! fv 0 2)
  (test-equal '(3 2 1) (flexvector->list fv)))

(let ((fv (flexvector 1 2 3 4 5)))
  (flexvector-fill! fv 0 1 3)
  (test-equal '(1 0 0 4 5) (flexvector->list fv)))

(let ((fv (flexvector 1 2 3 4 5)))
  (flexvector-fill! fv 9)
  (test-equal '(9 9 9 9 9) (flexvector->list fv)))

(let ((fv (flexvector 1 2 3)))
  (flexvector-reverse! fv)
  (test-equal '(3 2 1) (flexvector->list fv)))

(let ((to (flexvector 'a 'b 'c 'd 'e)) (from (flexvector 'x 'y 'z)))
  (test-equal to (flexvector-copy! to 1 from))
  (test-equal '(a x y z e) (flexvector->list to)))

;; flexvector-copy! growing `to` past its current length
(let ((to (flexvector 'a)) (from (flexvector 'x 'y 'z)))
  (flexvector-copy! to 1 from)
  (test-equal '(a x y z) (flexvector->list to)))

;; flexvector-copy! self-copy (overlapping ranges)
(let ((fv (flexvector 1 2 3 4 5)))
  (flexvector-copy! fv 0 fv 2 5)
  (test-equal '(3 4 5 4 5) (flexvector->list fv)))

(let ((to (flexvector 'a 'b 'c 'd 'e)) (from (flexvector 'x 'y 'z)))
  (flexvector-reverse-copy! to 1 from)
  (test-equal '(a z y x e) (flexvector->list to)))

;;; --- iteration ---

;; flexvector-fold: spec worked example
(test-equal 4 (flexvector-fold (lambda (len str) (max (string-length str) len)) 0 (flexvector "baz" "qux" "quux")))
(test-equal '(3 2 1) (flexvector-fold (lambda (acc x) (cons x acc)) '() (flexvector 1 2 3)))
(test-equal 21 (flexvector-fold (lambda (acc a b) (+ acc a b)) 0 (flexvector 1 2 3) (flexvector 4 5 6)))
(test-equal '(1 2 3) (flexvector-fold-right (lambda (acc x) (cons x acc)) '() (flexvector 1 2 3)))

(test-equal '(2 4 6) (flexvector->list (flexvector-map (lambda (x) (* 2 x)) (flexvector 1 2 3))))
(test-equal '(5 7 9) (flexvector->list (flexvector-map + (flexvector 1 2 3) (flexvector 4 5 6))))
(test-equal '(0 1 2) (flexvector->list (flexvector-map/index (lambda (i x) i) (flexvector 'a 'b 'c))))
(test-equal '(a-0 b-1 c-2)
            (flexvector->list
              (flexvector-map/index (lambda (i x) (string->symbol (string-append (symbol->string x) "-" (number->string i))))
                                     (flexvector 'a 'b 'c))))

(let ((fv (flexvector 1 2 3)))
  (flexvector-map! (lambda (x) (* x 10)) fv)
  (test-equal '(10 20 30) (flexvector->list fv)))

(let ((fv (flexvector 'a 'b 'c)))
  (flexvector-map/index! (lambda (i x) i) fv)
  (test-equal '(0 1 2) (flexvector->list fv)))

(test-equal '(1 1 2 2 3 3)
            (flexvector->list (flexvector-append-map (lambda (x) (flexvector x x)) (flexvector 1 2 3))))
(test-equal '(0 a 1 b 2 c)
            (flexvector->list (flexvector-append-map/index (lambda (i x) (flexvector i x)) (flexvector 'a 'b 'c))))

(test-equal '(2 4) (flexvector->list (flexvector-filter even? (flexvector 1 2 3 4 5))))
(test-equal '(a c) (flexvector->list (flexvector-filter/index (lambda (i x) (even? i)) (flexvector 'a 'b 'c 'd))))

(let ((fv (flexvector 1 2 3 4 5)))
  (flexvector-filter! even? fv)
  (test-equal '(2 4) (flexvector->list fv)))

(let ((fv (flexvector 'a 'b 'c 'd)))
  (flexvector-filter/index! (lambda (i x) (even? i)) fv)
  (test-equal '(a c) (flexvector->list fv)))

(test-equal '(1 2 3)
            (let ((acc '()))
              (flexvector-for-each (lambda (x) (set! acc (cons x acc))) (flexvector 1 2 3))
              (reverse acc)))

(test-equal '(0 1 2)
            (let ((acc '()))
              (flexvector-for-each/index (lambda (i x) (set! acc (cons i acc))) (flexvector 'a 'b 'c))
              (reverse acc)))

(test-equal 2 (flexvector-count even? (flexvector 1 2 3 4 5)))
(test-equal 1 (flexvector-count < (flexvector 1 2 3) (flexvector 3 2 1)))

;; flexvector-cumulate: spec worked example
(test-equal '(3 4 8 9 14 23 25 30 36)
            (flexvector->list (flexvector-cumulate + 0 (flexvector 3 1 4 1 5 9 2 5 6))))

;;; --- searching ---

(test-equal 3 (flexvector-index even? (flexvector 1 3 5 6 7)))
(test-equal #f (flexvector-index even? (flexvector 1 3 5)))
(test-equal 1 (flexvector-index = (flexvector 1 2 3) (flexvector 4 2 6)))
(test-equal 3 (flexvector-index-right even? (flexvector 2 3 5 6 7)))
(test-equal 0 (flexvector-skip even? (flexvector 1 3 5 6 7)))
(test-equal 4 (flexvector-skip-right even? (flexvector 2 3 5 6 7)))

;; flexvector-index-right: spec worked example
(test-equal 3 (flexvector-index-right < (flexvector 3 1 4 1 5) (flexvector 2 7 1 8 2)))

(test-equal 3 (flexvector-binary-search (flexvector 1 3 5 7 9 11) 7 (lambda (a b) (- a b))))
(test-equal #f (flexvector-binary-search (flexvector 1 3 5 7 9 11) 4 (lambda (a b) (- a b))))
(test-equal 1 (flexvector-binary-search (flexvector 0 3 5 7 9 11) 3 (lambda (a b) (- a b)) 1 4))

(test-equal #t (flexvector-any even? (flexvector 1 3 5 6 7)))
(test-equal #f (flexvector-any even? (flexvector 1 3 5)))
(test-equal #t (flexvector-every odd? (flexvector 1 3 5)))
(test-equal #f (flexvector-every odd? (flexvector 1 2 5)))

(let-values (((yes no) (flexvector-partition even? (flexvector 1 2 3 4 5))))
  (test-equal '(2 4) (flexvector->list yes))
  (test-equal '(1 3 5) (flexvector->list no)))

;;; --- conversion ---

(test-equal #(1 2 3) (flexvector->vector (flexvector 1 2 3)))
(test-equal #(2 3) (flexvector->vector (flexvector 1 2 3) 1))
(test-equal '(1 2 3) (flexvector->list (vector->flexvector #(1 2 3))))
(test-equal '(2 3) (flexvector->list (vector->flexvector #(1 2 3) 1)))
(test-equal '(3 2 1) (reverse-flexvector->list (flexvector 1 2 3)))
(test-equal '(1 2 3) (flexvector->list (list->flexvector '(1 2 3))))
(test-equal '(3 2 1) (flexvector->list (reverse-list->flexvector '(1 2 3))))
(test-equal "abc" (flexvector->string (flexvector #\a #\b #\c)))
(test-equal '(#\a #\b #\c) (flexvector->list (string->flexvector "abc")))
(test-equal '(#\b #\c) (flexvector->list (string->flexvector "abc" 1)))

(test-equal '(1 2 3)
            (let ((gen (flexvector->generator (flexvector 1 2 3))))
              (let loop ((v (gen)) (acc '()))
                (if (eof-object? v) (reverse acc) (loop (gen) (cons v acc))))))

(test-equal '(1 2 3) (flexvector->list (generator->flexvector (list->generator '(1 2 3)))))

;;; --- persistence-adjacent sanity: mutating a copy doesn't affect original ---

(let* ((orig (flexvector 1 2 3))
       (copy (flexvector-copy orig)))
  (flexvector-set! copy 0 'changed)
  (test-equal '(1 2 3) (flexvector->list orig))
  (test-equal '(changed 2 3) (flexvector->list copy)))

(let ((runner (test-runner-current)))
  (test-end "srfi-214")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
