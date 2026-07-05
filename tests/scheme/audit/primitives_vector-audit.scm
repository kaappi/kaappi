;; Audit tests for src/primitives_vector.zig — R7RS 6.8 vectors + SRFI-133.
;; Audit campaign Phase 2.8 (#1137). Complements tests/scheme/srfi/srfi133-ext.scm
;; and r7rs-tests.scm §6.8.
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme write) (scheme inexact) (srfi 133))
(import (chibi test))

(test-begin "primitives_vector audit")

;;; --- vector / vector? ---
(test #(a b c) (vector 'a 'b 'c))
(test #() (vector))
(test #t (vector? #()))
(test #t (vector? (vector 1)))
(test #f (vector? '(1 2)))
(test #f (vector? "abc"))
(test #f (vector? #u8(1 2)))

;;; --- make-vector ---
(test 3 (vector-length (make-vector 3)))
(test #(x x x) (make-vector 3 'x))
(test #() (make-vector 0))
(test 'caught (guard (e (#t 'caught)) (make-vector -1)))
(test 'caught (guard (e (#t 'caught)) (make-vector 2.0)))
(test 'caught (guard (e (#t 'caught)) (make-vector "3")))

;;; --- vector-length ---
(test 0 (vector-length #()))
(test 8 (vector-length #(1 1 2 3 5 8 13 21)))
(test 'caught (guard (e (#t 'caught)) (vector-length '(1 2))))

;;; --- vector-ref ---
(test 8 (vector-ref #(1 1 2 3 5 8 13 21) 5))
;; R7RS 6.8 example: index computed via exact/round
(test 13 (vector-ref #(1 1 2 3 5 8 13 21)
                     (exact (round (* 2 (acos -1))))))
(test 1 (vector-ref #(1 2 3) 0))
(test 3 (vector-ref #(1 2 3) 2))
(test 'caught (guard (e (#t 'caught)) (vector-ref #(1 2 3) 3)))
(test 'caught (guard (e (#t 'caught)) (vector-ref #(1 2 3) -1)))
(test 'caught (guard (e (#t 'caught)) (vector-ref #(1 2 3) 1.0)))
(test 'caught (guard (e (#t 'caught)) (vector-ref #(1 2 3) (expt 2 100))))
(test 'caught (guard (e (#t 'caught)) (vector-ref #() 0)))
(test 'caught (guard (e (#t 'caught)) (vector-ref "abc" 0)))

;;; --- vector-set! ---
(test #(0 ("Sue" "Sue") "Anna")
    (let ((vec (vector 0 '(2 2 2 2) "Anna")))
      (vector-set! vec 1 '("Sue" "Sue"))
      vec))
(test 'caught (guard (e (#t 'caught)) (vector-set! (vector 1 2) 2 'x)))
(test 'caught (guard (e (#t 'caught)) (vector-set! (vector 1 2) -1 'x)))
(test 'caught (guard (e (#t 'caught)) (vector-set! (vector 1 2) 0.0 'x)))
(test 'caught (guard (e (#t 'caught)) (vector-set! '(1 2) 0 'x)))
;; R7RS 6.8: (vector-set! '#(0 1 2) 1 "doe") => error ("constant vector").
;; Strings already enforce literal immutability (SchemeString.immutable);
;; vectors have no such flag, so the shared literal is silently mutated.
;; FAIL: #1173 (vector literals are mutable; mutation persists across calls)
;; (test 'caught (guard (e (#t 'caught)) (vector-set! '#(0 1 2) 1 "doe")))

;;; --- vector->list ---
(test '(dah dah didah) (vector->list #(dah dah didah)))
(test '(dah) (vector->list #(dah dah didah) 1 2))
(test '(dah didah) (vector->list #(dah dah didah) 1))
(test '() (vector->list #()))
(test '() (vector->list #(1 2 3) 2 2))
(test '(3) (vector->list #(1 2 3) 2 3))
(test 'caught (guard (e (#t 'caught)) (vector->list #(1 2 3) 2 1)))
(test 'caught (guard (e (#t 'caught)) (vector->list #(1 2 3) 0 4)))
(test 'caught (guard (e (#t 'caught)) (vector->list #(1 2 3) -1)))
(test 'caught (guard (e (#t 'caught)) (vector->list '(1 2 3))))

;;; --- list->vector ---
(test #(dididit dah) (list->vector '(dididit dah)))
(test #() (list->vector '()))
(test 'caught (guard (e (#t 'caught)) (list->vector '(1 2 . 3))))
(test 'caught (guard (e (#t 'caught)) (list->vector 42)))
;; round trip preserves order
(test '(1 2 3) (vector->list (list->vector '(1 2 3))))

;;; --- vector-fill! ---
(test #(1 2 smash smash 5)
    (let ((a (vector 1 2 3 4 5)))
      (vector-fill! a 'smash 2 4)
      a))
(test #(x x x)
    (let ((a (vector 1 2 3)))
      (vector-fill! a 'x)
      a))
(test #(1 2 3)
    (let ((a (vector 1 2 3)))
      (vector-fill! a 'x 1 1)   ; empty range: no-op
      a))
(test 'caught (guard (e (#t 'caught)) (vector-fill! (vector 1 2) 'x 2 1)))
(test 'caught (guard (e (#t 'caught)) (vector-fill! '(1 2) 'x)))

;;; --- vector-copy ---
(test #(1 8 2 8) (vector-copy #(1 8 2 8)))
(test #(8 2) (vector-copy #(1 8 2 8) 1 3))
(test #(2 8) (vector-copy #(1 8 2 8) 2))
(test #() (vector-copy #() 0 0))
(test #f (let ((a (vector 1 2))) (eq? a (vector-copy a))))   ; newly allocated
(test 'caught (guard (e (#t 'caught)) (vector-copy #(1 2) 2 1)))
(test 'caught (guard (e (#t 'caught)) (vector-copy #(1 2) 0 3)))
(test 'caught (guard (e (#t 'caught)) (vector-copy "ab")))

;;; --- vector-copy! ---
;; R7RS 6.8 example
(test #(10 1 2 40 50)
    (let ((a (vector 1 2 3 4 5))
          (b (vector 10 20 30 40 50)))
      (vector-copy! b 1 a 0 2)
      b))
;; overlapping copy within one vector, both directions
(test #(2 3 4 5 5)
    (let ((v (vector 1 2 3 4 5))) (vector-copy! v 0 v 1 5) v))
(test #(1 1 2 3 4)
    (let ((v (vector 1 2 3 4 5))) (vector-copy! v 1 v 0 4) v))
;; at == (vector-length to) with empty source range is allowed
(test #(1 2)
    (let ((v (vector 1 2))) (vector-copy! v 2 #()) v))
(test 'caught (guard (e (#t 'caught)) (vector-copy! (vector 1 2) 1 #(9 9))))
(test 'caught (guard (e (#t 'caught)) (vector-copy! (vector 1 2) -1 #(9))))
(test 'caught (guard (e (#t 'caught)) (vector-copy! (vector 1 2) 0 #(9 9 9) 1 4)))
(test 'caught (guard (e (#t 'caught)) (vector-copy! '(1 2) 0 #(9))))
(test 'caught (guard (e (#t 'caught)) (vector-copy! (vector 1 2) 0 '(9))))

;;; --- vector-append ---
(test #(a b c d e f) (vector-append #(a b c) #(d e f)))
(test #() (vector-append))
(test #(1) (vector-append #() #(1) #()))
(test 'caught (guard (e (#t 'caught)) (vector-append #(1) '(2))))

;;; --- vector->string ---
(test "123" (vector->string #(#\1 #\2 #\3)))
(test "bc" (vector->string #(#\a #\b #\c #\d) 1 3))
(test "" (vector->string #()))
(test 1 (string-length (vector->string (vector #\x1F600))))   ; astral char
(test 'caught (guard (e (#t 'caught)) (vector->string #(#\a 5))))
(test 'caught (guard (e (#t 'caught)) (vector->string "abc")))

;;; --- vector-map (R7RS 6.10) ---
(test #(b e h) (vector-map cadr #((a b) (d e) (g h))))
(test #(1 4 27 256 3125) (vector-map (lambda (n) (expt n n)) #(1 2 3 4 5)))
(test #(5 7 9) (vector-map + #(1 2 3) #(4 5 6)))
;; terminates on shortest vector
(test #(11 22) (vector-map + #(1 2) #(10 20 30)))
(test #() (vector-map + #()))
;; native procedures accepted
(test #(1 2) (vector-map car #((1) (2))))
;; errors in the callback propagate and are catchable
(test 'caught (guard (e (#t 'caught)) (vector-map (lambda (x) (error "boom")) #(1))))
(test 'caught (guard (e (#t 'caught)) (vector-map (lambda () 1) #(1))))  ; arity mismatch
(test 'caught (guard (e (#t 'caught)) (vector-map 5 #(1))))
(test 'caught (guard (e (#t 'caught)) (vector-map + '(1 2))))

;;; --- vector-for-each (R7RS 6.10) ---
(test #(0 1 4 9 16)
    (let ((v (make-vector 5)))
      (vector-for-each (lambda (i) (vector-set! v i (* i i)))
                       #(0 1 2 3 4))
      v))
;; multi-vector, terminates on shortest
(test 33
    (let ((sum 0))
      (vector-for-each (lambda (a b) (set! sum (+ sum a b)))
                       #(1 2) #(10 20 30))
      sum))
(test 'caught (guard (e (#t 'caught)) (vector-for-each (lambda (x) (error "boom")) #(1))))
(test 'caught (guard (e (#t 'caught)) (vector-for-each 5 #(1))))
;; escaping continuation from inside the callback
(test 3 (call/cc (lambda (k)
                   (vector-for-each (lambda (x) (if (= x 3) (k x))) #(1 2 3 4))
                   'no-escape)))

;;; --- SRFI-133: vector-empty? ---
(test #t (vector-empty? #()))
(test #f (vector-empty? #(a)))
(test 'caught (guard (e (#t 'caught)) (vector-empty? '())))

;;; --- SRFI-133: vector-count ---
(test 2 (vector-count even? #(1 2 3 4 5)))
(test 0 (vector-count even? #()))
;; SRFI-133 example: multi-vector, stops at shortest
(test 2 (vector-count < #(1 3 6 9) #(2 4 6 8 10 12)))
(test 'caught (guard (e (#t 'caught)) (vector-count even? '(1 2))))
(test 'caught (guard (e (#t 'caught)) (vector-count (lambda (x) (error "boom")) #(1))))

;;; --- SRFI-133: vector-any / vector-every ---
(test #t (vector-any even? #(1 3 4 5)))
(test #f (vector-any even? #(1 3 5)))
(test #f (vector-any even? #()))
;; returns the predicate's (truthy) result value
(test 40 (vector-any (lambda (x) (and (even? x) (* x 10))) #(1 3 4 5)))
(test #t (vector-any < #(1 9) #(2 0)))
(test #t (vector-every positive? #(1 2 3)))
(test #f (vector-every positive? #(1 -2 3)))
(test #t (vector-every positive? #()))
;; returns the last result value
(test 30 (vector-every (lambda (x) (* x 10)) #(1 2 3)))
;; multi-vector: stops at shortest, returns last result
(test #t (vector-every < #(1 2 3 4) #(2 3 4)))
(test 'caught (guard (e (#t 'caught)) (vector-any (lambda (x) (error "boom")) #(1))))
(test 'caught (guard (e (#t 'caught)) (vector-every (lambda (x) (error "boom")) #(1))))

;;; --- SRFI-133: vector-index / vector-index-right ---
(test 2 (vector-index even? #(3 1 4 1 5 9)))
(test #f (vector-index even? #(3 1 5 9)))
(test #f (vector-index even? #()))
;; SRFI-133 example: multi-vector
(test 1 (vector-index < #(3 1 4 1 5 9 2 5 6) #(2 7 1 8 2)))
(test 5 (vector-index-right even? #(3 1 4 1 5 4)))
(test #f (vector-index-right even? #(3 1 5)))
(test 'caught (guard (e (#t 'caught)) (vector-index even? '(1 2))))

;;; --- SRFI-133: vector-skip / vector-skip-right ---
(test 2 (vector-skip number? #(1 2 a b)))
(test #f (vector-skip number? #(1 2 3)))
(test 0 (vector-skip symbol? #(1 2 3)))
(test 2 (vector-skip-right number? #(1 a b 2)))   ; b at index 2 is first non-number from the right
(test 'caught (guard (e (#t 'caught)) (vector-skip number? '(1))))
;; SRFI-133: (vector-skip pred? vec1 vec2 ...) accepts multiple vectors;
;; registered with exact arity 2 so the multi-vector form raises an arity error.
;; FAIL: #1171 (vector-skip/vector-skip-right reject the multi-vector form)
;; (test 2 (vector-skip = #(1 2 3 4 5) #(1 2 -3 4)))
;; (test 2 (vector-skip-right = #(1 2 3 4 5) #(1 2 -3 4 5)))

;;; --- SRFI-133: vector-swap! ---
(test #(3 2 1) (let ((v (vector 1 2 3))) (vector-swap! v 0 2) v))
(test #(1 2 3) (let ((v (vector 1 2 3))) (vector-swap! v 1 1) v))
(test 'caught (guard (e (#t 'caught)) (vector-swap! (vector 1 2) 0 2)))
(test 'caught (guard (e (#t 'caught)) (vector-swap! (vector 1 2) -1 0)))
(test 'caught (guard (e (#t 'caught)) (vector-swap! '(1 2) 0 1)))

;;; --- SRFI-133: vector-reverse! / vector-reverse-copy ---
(test #(5 4 3 2 1) (let ((v (vector 1 2 3 4 5))) (vector-reverse! v) v))
(test #(1 4 3 2 5) (let ((v (vector 1 2 3 4 5))) (vector-reverse! v 1 4) v))
(test #() (let ((v (vector))) (vector-reverse! v) v))
(test #(5 4 3 2 1) (vector-reverse-copy #(1 2 3 4 5)))
(test #(4 3 2) (vector-reverse-copy #(1 2 3 4 5) 1 4))
(test #f (let ((v (vector 1))) (eq? v (vector-reverse-copy v))))
(test 'caught (guard (e (#t 'caught)) (vector-reverse! '(1 2))))

;;; --- SRFI-133: vector-unfold / vector-unfold-right ---
(test #(0 1 4 9) (vector-unfold (lambda (i) (* i i)) 4))
;; one seed: (values elem new-seed)
(test #(0 -1 -2 -3 -4 -5)
    (vector-unfold (lambda (i x) (values x (- x 1))) 6 0))
;; two seeds
(test #(1 2 3 5 8 13)
    (vector-unfold (lambda (i a b) (values (+ a b) b (+ a b))) 6 0 1))
(test #() (vector-unfold (lambda (i) (error "must not be called")) 0))
(test #(5 4 3 2 1 0)
    (vector-unfold-right (lambda (i x) (values x (+ x 1))) 6 0))
(test 'caught (guard (e (#t 'caught)) (vector-unfold (lambda (i) 1) -1)))
(test 'caught (guard (e (#t 'caught)) (vector-unfold (lambda (i) (error "boom")) 3)))

;;; --- SRFI-133: vector-binary-search ---
;; cmp is called as (cmp element value)
(test 2 (vector-binary-search #(1 3 5 7 9) 5 (lambda (a b) (- a b))))
(test 0 (vector-binary-search #(1 3 5 7 9) 1 (lambda (a b) (- a b))))
(test 4 (vector-binary-search #(1 3 5 7 9) 9 (lambda (a b) (- a b))))
(test #f (vector-binary-search #(1 3 5 7 9) 4 (lambda (a b) (- a b))))
(test #f (vector-binary-search #() 4 (lambda (a b) (- a b))))
(test 0 (vector-binary-search #(7) 7 (lambda (a b) (- a b))))
(test 'caught (guard (e (#t 'caught))
                (vector-binary-search #(1 2) 1 (lambda (a b) "not-an-integer"))))
(test 'caught (guard (e (#t 'caught)) (vector-binary-search '(1 2) 1 -)))

;;; --- SRFI-133: vector-concatenate ---
(test #(a b c d) (vector-concatenate '(#(a b) #(c d))))
(test #() (vector-concatenate '()))
(test #(1) (vector-concatenate '(#() #(1))))
(test 'caught (guard (e (#t 'caught)) (vector-concatenate '(#(1) 2))))
(test 'caught (guard (e (#t 'caught)) (vector-concatenate #(1))))

;;; --- SRFI-133: vector-cumulate ---
;; SRFI-133 example
(test #(3 4 8 9 14 23 25 30 36)
    (vector-cumulate + 0 #(3 1 4 1 5 9 2 5 6)))
(test #() (vector-cumulate + 0 #()))
;; f is called as (f state element)
(test #((0 . a) ((0 . a) . b))
    (vector-cumulate cons 0 #(a b)))
(test 'caught (guard (e (#t 'caught)) (vector-cumulate (lambda (a b) (error "boom")) 0 #(1))))
(test 'caught (guard (e (#t 'caught)) (vector-cumulate + 0 '(1))))

;;; --- SRFI-133: vector-partition ---
(test '(#(2 4 6 1 3 5) 3)
    (call-with-values (lambda () (vector-partition even? #(1 2 3 4 5 6))) list))
(test '(#(1 2 3) 3)
    (call-with-values (lambda () (vector-partition number? #(1 2 3))) list))
(test '(#(1 2 3) 0)
    (call-with-values (lambda () (vector-partition symbol? #(1 2 3))) list))
(test '(#() 0)
    (call-with-values (lambda () (vector-partition even? #())) list))
(test 'caught (guard (e (#t 'caught)) (vector-partition (lambda (x) (error "boom")) #(1))))
(test 'caught (guard (e (#t 'caught)) (vector-partition even? '(1))))

;;; --- SRFI-133: vector-append-subvectors ---
;; SRFI-133 example
(test #(a b h i)
    (vector-append-subvectors #(a b c d e) 0 2 #(f g h i j) 2 4))
(test #() (vector-append-subvectors))
(test #(b c) (vector-append-subvectors #(a b c) 1 3))
(test 'caught (guard (e (#t 'caught)) (vector-append-subvectors #(a b) 0)))       ; not multiple of 3
(test 'caught (guard (e (#t 'caught)) (vector-append-subvectors #(a b) 0 3)))     ; end out of range
(test 'caught (guard (e (#t 'caught)) (vector-append-subvectors #(a b) 1 0)))     ; end < start
(test 'caught (guard (e (#t 'caught)) (vector-append-subvectors #(a b) -1 1)))

;;; --- SRFI-133 export completeness ---
;; Nine spec procedures are not implemented / exported from (srfi 133):
;; vector=, vector-fold, vector-fold-right, vector-map!, vector-reverse-copy!,
;; vector-unfold!, vector-unfold-right!, reverse-vector->list, reverse-list->vector.
;; Referencing any of them is an undefined-variable error (cannot be tested here
;; without aborting the file). Note (import (only (srfi 133) vector-fold))
;; "succeeds" because only/except/rename don't validate identifiers — see #1174.
;; FAIL: #1172 ((srfi 133) missing 9 spec-required procedures)
;; (test #t (vector= = (vector 1 2) (vector 1 2)))
;; (test 6 (vector-fold + 0 (vector 1 2 3)))
;; (test '(3 2 1) (reverse-vector->list (vector 1 2 3)))
;; (test #(-1 -2) (let ((v (vector 1 2))) (vector-map! - v) v))

(test-end "primitives_vector audit")
