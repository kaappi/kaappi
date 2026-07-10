;; Audit tests for src/primitives_vector.zig — R7RS 6.8 vectors + SRFI-133.
;; Audit campaign Phase 2.8 (#1137). Complements tests/scheme/srfi/srfi133-ext.scm
;; and r7rs-tests.scm §6.8.
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme write) (scheme inexact) (srfi 133))
(import (scheme process-context) (srfi 64))

(test-begin "primitives_vector audit")

;;; --- vector / vector? ---
(test-equal #(a b c) (vector 'a 'b 'c))
(test-equal #() (vector))
(test-equal #t (vector? #()))
(test-equal #t (vector? (vector 1)))
(test-equal #f (vector? '(1 2)))
(test-equal #f (vector? "abc"))
(test-equal #f (vector? #u8(1 2)))

;;; --- make-vector ---
(test-equal 3 (vector-length (make-vector 3)))
(test-equal #(x x x) (make-vector 3 'x))
(test-equal #() (make-vector 0))
(test-equal 'caught (guard (e (#t 'caught)) (make-vector -1)))
(test-equal 'caught (guard (e (#t 'caught)) (make-vector 2.0)))
(test-equal 'caught (guard (e (#t 'caught)) (make-vector "3")))

;;; --- vector-length ---
(test-equal 0 (vector-length #()))
(test-equal 8 (vector-length #(1 1 2 3 5 8 13 21)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-length '(1 2))))

;;; --- vector-ref ---
(test-equal 8 (vector-ref #(1 1 2 3 5 8 13 21) 5))
;; R7RS 6.8 example: index computed via exact/round
(test-equal 13 (vector-ref #(1 1 2 3 5 8 13 21)
                           (exact (round (* 2 (acos -1))))))
(test-equal 1 (vector-ref #(1 2 3) 0))
(test-equal 3 (vector-ref #(1 2 3) 2))
(test-equal 'caught (guard (e (#t 'caught)) (vector-ref #(1 2 3) 3)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-ref #(1 2 3) -1)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-ref #(1 2 3) 1.0)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-ref #(1 2 3) (expt 2 100))))
(test-equal 'caught (guard (e (#t 'caught)) (vector-ref #() 0)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-ref "abc" 0)))

;;; --- vector-set! ---
(test-equal #(0 ("Sue" "Sue") "Anna")
    (let ((vec (vector 0 '(2 2 2 2) "Anna")))
      (vector-set! vec 1 '("Sue" "Sue"))
      vec))
(test-equal 'caught (guard (e (#t 'caught)) (vector-set! (vector 1 2) 2 'x)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-set! (vector 1 2) -1 'x)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-set! (vector 1 2) 0.0 'x)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-set! '(1 2) 0 'x)))
;; R7RS 6.8: (vector-set! '#(0 1 2) 1 "doe") => error ("constant vector").
(test-equal 'caught (guard (e (#t 'caught)) (vector-set! '#(0 1 2) 1 "doe")))

;;; --- vector->list ---
(test-equal '(dah dah didah) (vector->list #(dah dah didah)))
(test-equal '(dah) (vector->list #(dah dah didah) 1 2))
(test-equal '(dah didah) (vector->list #(dah dah didah) 1))
(test-equal '() (vector->list #()))
(test-equal '() (vector->list #(1 2 3) 2 2))
(test-equal '(3) (vector->list #(1 2 3) 2 3))
(test-equal 'caught (guard (e (#t 'caught)) (vector->list #(1 2 3) 2 1)))
(test-equal 'caught (guard (e (#t 'caught)) (vector->list #(1 2 3) 0 4)))
(test-equal 'caught (guard (e (#t 'caught)) (vector->list #(1 2 3) -1)))
(test-equal 'caught (guard (e (#t 'caught)) (vector->list '(1 2 3))))

;;; --- list->vector ---
(test-equal #(dididit dah) (list->vector '(dididit dah)))
(test-equal #() (list->vector '()))
(test-equal 'caught (guard (e (#t 'caught)) (list->vector '(1 2 . 3))))
(test-equal 'caught (guard (e (#t 'caught)) (list->vector 42)))
;; round trip preserves order
(test-equal '(1 2 3) (vector->list (list->vector '(1 2 3))))

;;; --- vector-fill! ---
(test-equal #(1 2 smash smash 5)
    (let ((a (vector 1 2 3 4 5)))
      (vector-fill! a 'smash 2 4)
      a))
(test-equal #(x x x)
    (let ((a (vector 1 2 3)))
      (vector-fill! a 'x)
      a))
(test-equal #(1 2 3)
    (let ((a (vector 1 2 3)))
      (vector-fill! a 'x 1 1)   ; empty range: no-op
      a))
(test-equal 'caught (guard (e (#t 'caught)) (vector-fill! (vector 1 2) 'x 2 1)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-fill! '(1 2) 'x)))

;;; --- vector-copy ---
(test-equal #(1 8 2 8) (vector-copy #(1 8 2 8)))
(test-equal #(8 2) (vector-copy #(1 8 2 8) 1 3))
(test-equal #(2 8) (vector-copy #(1 8 2 8) 2))
(test-equal #() (vector-copy #() 0 0))
(test-equal #f (let ((a (vector 1 2))) (eq? a (vector-copy a))))   ; newly allocated
(test-equal 'caught (guard (e (#t 'caught)) (vector-copy #(1 2) 2 1)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-copy #(1 2) 0 3)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-copy "ab")))

;;; --- vector-copy! ---
;; R7RS 6.8 example
(test-equal #(10 1 2 40 50)
    (let ((a (vector 1 2 3 4 5))
          (b (vector 10 20 30 40 50)))
      (vector-copy! b 1 a 0 2)
      b))
;; overlapping copy within one vector, both directions
(test-equal #(2 3 4 5 5)
    (let ((v (vector 1 2 3 4 5))) (vector-copy! v 0 v 1 5) v))
(test-equal #(1 1 2 3 4)
    (let ((v (vector 1 2 3 4 5))) (vector-copy! v 1 v 0 4) v))
;; at == (vector-length to) with empty source range is allowed
(test-equal #(1 2)
    (let ((v (vector 1 2))) (vector-copy! v 2 #()) v))
(test-equal 'caught (guard (e (#t 'caught)) (vector-copy! (vector 1 2) 1 #(9 9))))
(test-equal 'caught (guard (e (#t 'caught)) (vector-copy! (vector 1 2) -1 #(9))))
(test-equal 'caught (guard (e (#t 'caught)) (vector-copy! (vector 1 2) 0 #(9 9 9) 1 4)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-copy! '(1 2) 0 #(9))))
(test-equal 'caught (guard (e (#t 'caught)) (vector-copy! (vector 1 2) 0 '(9))))

;;; --- vector-append ---
(test-equal #(a b c d e f) (vector-append #(a b c) #(d e f)))
(test-equal #() (vector-append))
(test-equal #(1) (vector-append #() #(1) #()))
(test-equal 'caught (guard (e (#t 'caught)) (vector-append #(1) '(2))))

;;; --- vector->string ---
(test-equal "123" (vector->string #(#\1 #\2 #\3)))
(test-equal "bc" (vector->string #(#\a #\b #\c #\d) 1 3))
(test-equal "" (vector->string #()))
(test-equal 1 (string-length (vector->string (vector #\x1F600))))   ; astral char
(test-equal 'caught (guard (e (#t 'caught)) (vector->string #(#\a 5))))
(test-equal 'caught (guard (e (#t 'caught)) (vector->string "abc")))

;;; --- vector-map (R7RS 6.10) ---
(test-equal #(b e h) (vector-map cadr #((a b) (d e) (g h))))
(test-equal #(1 4 27 256 3125) (vector-map (lambda (n) (expt n n)) #(1 2 3 4 5)))
(test-equal #(5 7 9) (vector-map + #(1 2 3) #(4 5 6)))
;; terminates on shortest vector
(test-equal #(11 22) (vector-map + #(1 2) #(10 20 30)))
(test-equal #() (vector-map + #()))
;; native procedures accepted
(test-equal #(1 2) (vector-map car #((1) (2))))
;; errors in the callback propagate and are catchable
(test-equal 'caught (guard (e (#t 'caught)) (vector-map (lambda (x) (error "boom")) #(1))))
(test-equal 'caught (guard (e (#t 'caught)) (vector-map (lambda () 1) #(1))))  ; arity mismatch
(test-equal 'caught (guard (e (#t 'caught)) (vector-map 5 #(1))))
(test-equal 'caught (guard (e (#t 'caught)) (vector-map + '(1 2))))

;;; --- vector-for-each (R7RS 6.10) ---
(test-equal #(0 1 4 9 16)
    (let ((v (make-vector 5)))
      (vector-for-each (lambda (i) (vector-set! v i (* i i)))
                       #(0 1 2 3 4))
      v))
;; multi-vector, terminates on shortest
(test-equal 33
    (let ((sum 0))
      (vector-for-each (lambda (a b) (set! sum (+ sum a b)))
                       #(1 2) #(10 20 30))
      sum))
(test-equal 'caught (guard (e (#t 'caught)) (vector-for-each (lambda (x) (error "boom")) #(1))))
(test-equal 'caught (guard (e (#t 'caught)) (vector-for-each 5 #(1))))
;; escaping continuation from inside the callback
(test-equal 3 (call/cc (lambda (k)
                         (vector-for-each (lambda (x) (if (= x 3) (k x))) #(1 2 3 4))
                         'no-escape)))

;;; --- SRFI-133: vector-empty? ---
(test-equal #t (vector-empty? #()))
(test-equal #f (vector-empty? #(a)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-empty? '())))

;;; --- SRFI-133: vector-count ---
(test-equal 2 (vector-count even? #(1 2 3 4 5)))
(test-equal 0 (vector-count even? #()))
;; SRFI-133 example: multi-vector, stops at shortest
(test-equal 2 (vector-count < #(1 3 6 9) #(2 4 6 8 10 12)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-count even? '(1 2))))
(test-equal 'caught (guard (e (#t 'caught)) (vector-count (lambda (x) (error "boom")) #(1))))

;;; --- SRFI-133: vector-any / vector-every ---
(test-equal #t (vector-any even? #(1 3 4 5)))
(test-equal #f (vector-any even? #(1 3 5)))
(test-equal #f (vector-any even? #()))
;; returns the predicate's (truthy) result value
(test-equal 40 (vector-any (lambda (x) (and (even? x) (* x 10))) #(1 3 4 5)))
(test-equal #t (vector-any < #(1 9) #(2 0)))
(test-equal #t (vector-every positive? #(1 2 3)))
(test-equal #f (vector-every positive? #(1 -2 3)))
(test-equal #t (vector-every positive? #()))
;; returns the last result value
(test-equal 30 (vector-every (lambda (x) (* x 10)) #(1 2 3)))
;; multi-vector: stops at shortest, returns last result
(test-equal #t (vector-every < #(1 2 3 4) #(2 3 4)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-any (lambda (x) (error "boom")) #(1))))
(test-equal 'caught (guard (e (#t 'caught)) (vector-every (lambda (x) (error "boom")) #(1))))

;;; --- SRFI-133: vector-index / vector-index-right ---
(test-equal 2 (vector-index even? #(3 1 4 1 5 9)))
(test-equal #f (vector-index even? #(3 1 5 9)))
(test-equal #f (vector-index even? #()))
;; SRFI-133 example: multi-vector
(test-equal 1 (vector-index < #(3 1 4 1 5 9 2 5 6) #(2 7 1 8 2)))
(test-equal 5 (vector-index-right even? #(3 1 4 1 5 4)))
(test-equal #f (vector-index-right even? #(3 1 5)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-index even? '(1 2))))

;;; --- SRFI-133: vector-skip / vector-skip-right ---
(test-equal 2 (vector-skip number? #(1 2 a b)))
(test-equal #f (vector-skip number? #(1 2 3)))
(test-equal 0 (vector-skip symbol? #(1 2 3)))
(test-equal 2 (vector-skip-right number? #(1 a b 2)))   ; b at index 2 is first non-number from the right
(test-equal 'caught (guard (e (#t 'caught)) (vector-skip number? '(1))))
(test-equal 2 (vector-skip = #(1 2 3 4 5) #(1 2 -3 4)))
(test-equal 2 (vector-skip-right = #(1 2 3 4 5) #(1 2 -3 4 5)))

;;; --- SRFI-133: vector-swap! ---
(test-equal #(3 2 1) (let ((v (vector 1 2 3))) (vector-swap! v 0 2) v))
(test-equal #(1 2 3) (let ((v (vector 1 2 3))) (vector-swap! v 1 1) v))
(test-equal 'caught (guard (e (#t 'caught)) (vector-swap! (vector 1 2) 0 2)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-swap! (vector 1 2) -1 0)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-swap! '(1 2) 0 1)))

;;; --- SRFI-133: vector-reverse! / vector-reverse-copy ---
(test-equal #(5 4 3 2 1) (let ((v (vector 1 2 3 4 5))) (vector-reverse! v) v))
(test-equal #(1 4 3 2 5) (let ((v (vector 1 2 3 4 5))) (vector-reverse! v 1 4) v))
(test-equal #() (let ((v (vector))) (vector-reverse! v) v))
(test-equal #(5 4 3 2 1) (vector-reverse-copy #(1 2 3 4 5)))
(test-equal #(4 3 2) (vector-reverse-copy #(1 2 3 4 5) 1 4))
(test-equal #f (let ((v (vector 1))) (eq? v (vector-reverse-copy v))))
(test-equal 'caught (guard (e (#t 'caught)) (vector-reverse! '(1 2))))

;;; --- SRFI-133: vector-unfold / vector-unfold-right ---
(test-equal #(0 1 4 9) (vector-unfold (lambda (i) (* i i)) 4))
;; one seed: (values elem new-seed)
(test-equal #(0 -1 -2 -3 -4 -5)
    (vector-unfold (lambda (i x) (values x (- x 1))) 6 0))
;; two seeds
(test-equal #(1 2 3 5 8 13)
    (vector-unfold (lambda (i a b) (values (+ a b) b (+ a b))) 6 0 1))
(test-equal #() (vector-unfold (lambda (i) (error "must not be called")) 0))
(test-equal #(5 4 3 2 1 0)
    (vector-unfold-right (lambda (i x) (values x (+ x 1))) 6 0))
(test-equal 'caught (guard (e (#t 'caught)) (vector-unfold (lambda (i) 1) -1)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-unfold (lambda (i) (error "boom")) 3)))

;;; --- SRFI-133: vector-binary-search ---
;; cmp is called as (cmp element value)
(test-equal 2 (vector-binary-search #(1 3 5 7 9) 5 (lambda (a b) (- a b))))
(test-equal 0 (vector-binary-search #(1 3 5 7 9) 1 (lambda (a b) (- a b))))
(test-equal 4 (vector-binary-search #(1 3 5 7 9) 9 (lambda (a b) (- a b))))
(test-equal #f (vector-binary-search #(1 3 5 7 9) 4 (lambda (a b) (- a b))))
(test-equal #f (vector-binary-search #() 4 (lambda (a b) (- a b))))
(test-equal 0 (vector-binary-search #(7) 7 (lambda (a b) (- a b))))
(test-equal 'caught (guard (e (#t 'caught))
                      (vector-binary-search #(1 2) 1 (lambda (a b) "not-an-integer"))))
(test-equal 'caught (guard (e (#t 'caught)) (vector-binary-search '(1 2) 1 -)))

;;; --- SRFI-133: vector-concatenate ---
(test-equal #(a b c d) (vector-concatenate '(#(a b) #(c d))))
(test-equal #() (vector-concatenate '()))
(test-equal #(1) (vector-concatenate '(#() #(1))))
(test-equal 'caught (guard (e (#t 'caught)) (vector-concatenate '(#(1) 2))))
(test-equal 'caught (guard (e (#t 'caught)) (vector-concatenate #(1))))

;;; --- SRFI-133: vector-cumulate ---
;; SRFI-133 example
(test-equal #(3 4 8 9 14 23 25 30 36)
    (vector-cumulate + 0 #(3 1 4 1 5 9 2 5 6)))
(test-equal #() (vector-cumulate + 0 #()))
;; f is called as (f state element)
(test-equal #((0 . a) ((0 . a) . b))
    (vector-cumulate cons 0 #(a b)))
(test-equal 'caught (guard (e (#t 'caught)) (vector-cumulate (lambda (a b) (error "boom")) 0 #(1))))
(test-equal 'caught (guard (e (#t 'caught)) (vector-cumulate + 0 '(1))))

;;; --- SRFI-133: vector-partition ---
(test-equal '(#(2 4 6 1 3 5) 3)
    (call-with-values (lambda () (vector-partition even? #(1 2 3 4 5 6))) list))
(test-equal '(#(1 2 3) 3)
    (call-with-values (lambda () (vector-partition number? #(1 2 3))) list))
(test-equal '(#(1 2 3) 0)
    (call-with-values (lambda () (vector-partition symbol? #(1 2 3))) list))
(test-equal '(#() 0)
    (call-with-values (lambda () (vector-partition even? #())) list))
(test-equal 'caught (guard (e (#t 'caught)) (vector-partition (lambda (x) (error "boom")) #(1))))
(test-equal 'caught (guard (e (#t 'caught)) (vector-partition even? '(1))))

;;; --- SRFI-133: vector-append-subvectors ---
;; SRFI-133 example
(test-equal #(a b h i)
    (vector-append-subvectors #(a b c d e) 0 2 #(f g h i j) 2 4))
(test-equal #() (vector-append-subvectors))
(test-equal #(b c) (vector-append-subvectors #(a b c) 1 3))
(test-equal 'caught (guard (e (#t 'caught)) (vector-append-subvectors #(a b) 0)))       ; not multiple of 3
(test-equal 'caught (guard (e (#t 'caught)) (vector-append-subvectors #(a b) 0 3)))     ; end out of range
(test-equal 'caught (guard (e (#t 'caught)) (vector-append-subvectors #(a b) 1 0)))     ; end < start
(test-equal 'caught (guard (e (#t 'caught)) (vector-append-subvectors #(a b) -1 1)))

;;; --- SRFI-133 export completeness (fixed in #1172) ---
(test-equal #t (vector= = (vector 1 2) (vector 1 2)))
(test-equal 6 (vector-fold + 0 (vector 1 2 3)))
(test-equal '(3 2 1) (reverse-vector->list (vector 1 2 3)))
(test-equal #(-1 -2) (let ((v (vector 1 2))) (vector-map! - v) v))

(let ((runner (test-runner-current)))
  (test-end "primitives_vector audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
