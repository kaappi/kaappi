;; SRFI 63 (Homogeneous and Heterogeneous Arrays) tests.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi63.scm

(import (scheme base) (scheme process-context) (srfi 64) (srfi 63))

(test-begin "srfi-63")

;;; --- construction, rank, dimensions (heterogeneous: vector prototype) ---
(test-equal 2 (array-rank (make-array (vector) 2 3)))
(test-equal '(2 3) (array-dimensions (make-array (vector) 2 3)))
(test-equal 0 (array-rank (make-array (vector))))

;;; --- array? is NOT disjoint from vector/string (per spec: "Arrays are
;;; not disjoint from other Scheme types" -- vectors/strings are rank-1
;;; arrays in their own right, not just valid make-array prototypes) ---
(test-equal #t (array? (make-array (vector) 2)))
(test-equal #t (array? (vector 1 2 3)))
(test-equal #t (array? "abc"))
(test-equal #f (array? '(1 2 3)))

;;; --- vectors/strings work directly with the core accessors ---
(test-equal 1 (array-rank (vector 1 2 3)))
(test-equal '(3) (array-dimensions (vector 1 2 3)))
(test-equal '(3) (array-dimensions "abc"))
(test-equal 20 (array-ref (vector 10 20 30) 1))
(test-equal #\b (array-ref "abc" 1))
(test-equal #t (array-in-bounds? (vector 1 2 3) 2))
(test-equal #f (array-in-bounds? (vector 1 2 3) 3))
(let ((v (vector 1 2 3)))
  (array-set! v 99 1)
  (test-equal (vector 1 99 3) v))
(let ((s (make-string 3 #\a)))
  (array-set! s #\z 1)
  (test-equal "aza" s))

;;; --- array-set!'s value-SECOND calling convention (opposite of SRFI 25/164) ---
(let ((a (make-array (vector) 2 2)))
  (array-set! a 'hello 0 0)
  (test-equal 'hello (array-ref a 0 0))
  (array-set! a 42 1 1)
  (test-equal 42 (array-ref a 1 1)))

;;; --- array-in-bounds? ---
(let ((a (make-array (vector) 2 3)))
  (test-equal #t (array-in-bounds? a 1 2))
  (test-equal #f (array-in-bounds? a 2 0))
  (test-equal #f (array-in-bounds? a 0 -1))
  (test-equal #f (array-in-bounds? a 0)))

;;; --- natively-backed prototype kinds: signed fixnum, range-check rejection ---
(let ((a (make-array (A:fixZ8b) 3)))
  (array-set! a -128 0)
  (array-set! a 127 1)
  (test-equal -128 (array-ref a 0))
  (test-equal 127 (array-ref a 1))
  (test-equal #t (guard (e (#t #t)) (array-set! a 128 2) #f)))

;;; --- a prototype's own element (when it has one) becomes the fill value
;;; for a new array -- "the new array is filled with the element at the
;;; origin of prototype" -- not an unrelated kind-specific default ---
(test-equal 42 (array-ref (A:fixZ8b 42)))
(let ((a (make-array (A:fixZ8b 42) 3)))
  (test-equal 42 (array-ref a 0))
  (test-equal 42 (array-ref a 1))
  (test-equal 42 (array-ref a 2)))
(let ((a (make-array (A:bool #t) 2)))
  (test-equal #t (array-ref a 0))
  (test-equal #t (array-ref a 1)))
;; vector/string prototypes with elements fill from their own origin too
(let ((a (make-array (vector 'x 'y) 3)))
  (test-equal 'x (array-ref a 0))
  (test-equal 'x (array-ref a 2)))
;; an empty prototype has an unspecified (here, kind-default) fill -- just
;; confirm construction doesn't crash and the cell is the right type
(let ((a (make-array (A:fixZ8b) 2)))
  (test-assert (integer? (array-ref a 0))))
;; too many arguments to a prototype constructor is rejected
(test-equal #t (guard (e (#t #t)) (A:fixZ8b 1 2) #f))

;;; --- unsigned fixnum kind, negative rejected ---
(let ((a (make-array (A:fixN16b) 2)))
  (array-set! a 65535 0)
  (test-equal 65535 (array-ref a 0))
  (test-equal #t (guard (e (#t #t)) (array-set! a -1 1) #f)))

;;; --- float kind ---
(let ((a (make-array (A:floR64b) 1)))
  (array-set! a 3.25 0)
  (test-equal 3.25 (array-ref a 0)))

;;; --- complex kind ---
(let ((a (make-array (A:floC128b) 1)))
  (array-set! a (make-rectangular 1.0 2.0) 0)
  (test-equal (make-rectangular 1.0 2.0) (array-ref a 0)))

;;; --- fixN8b: bytevector-backed fallback ---
(let ((a (make-array (A:fixN8b) 2)))
  (array-set! a 255 0)
  (test-equal 255 (array-ref a 0))
  (test-equal #t (guard (e (#t #t)) (array-set! a 256 1) #f)))

;;; --- bool kind: validated fallback ---
(let ((a (make-array (A:bool) 2)))
  (array-set! a #t 0)
  (array-set! a #f 1)
  (test-equal #t (array-ref a 0))
  (test-equal #f (array-ref a 1))
  (test-equal #t (guard (e (#t #t)) (array-set! a 'not-a-bool 0) #f)))

;;; --- generic (unchecked vector) fallback for exotic kinds with no
;;; Kaappi-native representation ---
(let ((a (make-array (A:floR16b) 1)))
  (array-set! a 'anything 0)
  (test-equal 'anything (array-ref a 0)))

;;; --- string prototype: char kind ---
(let ((a (make-array "" 3)))
  (array-set! a #\x 0)
  (test-equal #\x (array-ref a 0)))

;;; --- make-shared-array: list-returning mapper (not multiple values,
;;; unlike SRFI 25/164's share-array), the spec's own diagonal example ---
(let* ((m (make-array (vector) 3 3)))
  (do ((i 0 (+ i 1))) ((= i 3))
    (do ((j 0 (+ j 1))) ((= j 3))
      (array-set! m (+ (* i 10) j) i j)))
  (let ((diag (make-shared-array m (lambda (i) (list i i)) 3)))
    (test-equal 1 (array-rank diag))
    (test-equal 0 (array-ref diag 0))
    (test-equal 11 (array-ref diag 1))
    (test-equal 22 (array-ref diag 2))
    ;; write-through to the base array
    (array-set! diag 999 1)
    (test-equal 999 (array-ref m 1 1)))
  ;; rank-2 -> rank-2 offset view, also over the mutated base
  (let ((sub (make-shared-array m (lambda (i j) (list (+ i 1) (+ j 1))) 2 2)))
    (test-equal 999 (array-ref sub 0 0))
    (test-equal 22 (array-ref sub 1 1))))

;;; --- shared-view bounds are the VIEW's own declared dims, not whatever
;;; the mapper happens to accept -- array-in-bounds? must agree with
;;; array-ref/array-set!'s actual acceptance ---
(let* ((base (make-array (vector) 10))
       (view (make-shared-array base (lambda (i) (list i)) 1)))
  (array-set! base 'zero 0)
  (test-equal 'zero (array-ref view 0))
  (test-equal #t (array-in-bounds? view 0))
  (test-equal #f (array-in-bounds? view 5))
  (test-equal #t (guard (e (#t #t)) (array-ref view 5) #f))
  (test-equal #t (guard (e (#t #t)) (array-set! view 'x 5) #f)))

;;; --- make-shared-array over a plain vector/string base ---
(let* ((v (vector 'a 'b 'c))
       (view (make-shared-array v (lambda (i) (list (- 2 i))) 3)))
  (test-equal 'c (array-ref view 0))
  (test-equal 'a (array-ref view 2))
  (array-set! view 'z 0)
  (test-equal 'z (vector-ref v 2)))

;;; --- nested shared arrays compose for both reads and writes ---
(let* ((base (make-array (vector) 2 2))
       (row0 (make-shared-array base (lambda (j) (list 0 j)) 2))
       (row0-rev (make-shared-array row0 (lambda (j) (list (- 1 j))) 2)))
  (array-set! base 'a 0 0)
  (array-set! base 'b 0 1)
  (test-equal 'b (array-ref row0-rev 0))
  (test-equal 'a (array-ref row0-rev 1))
  (array-set! row0-rev 'mutated 0)
  (test-equal 'mutated (array-ref base 0 1)))

;;; --- array-augmented equal? ---
(let ((e1 (make-array (vector) 2))
      (e2 (make-array (vector) 2)))
  (array-set! e1 'x 0) (array-set! e1 'y 1)
  (array-set! e2 'x 0) (array-set! e2 'y 1)
  (test-equal #t (equal? e1 e2))
  (array-set! e2 'z 1)
  (test-equal #f (equal? e1 e2)))
;; different dimensions
(test-equal #f (equal? (make-array (vector) 2) (make-array (vector) 3)))
;; ordinary (non-array) equal? still works
(test-equal #t (equal? (list 1 2 3) (list 1 2 3)))
(test-equal #t (equal? "abc" "abc"))
(test-equal #f (equal? "abc" "abd"))

;;; --- list->array / array->list: rank-nested list structure ---
(let ((a (list->array 2 (vector) '((1 2) (3 4)))))
  (test-equal '(2 2) (array-dimensions a))
  (test-equal 1 (array-ref a 0 0))
  (test-equal 2 (array-ref a 0 1))
  (test-equal 3 (array-ref a 1 0))
  (test-equal 4 (array-ref a 1 1))
  (test-equal '((1 2) (3 4)) (array->list a)))

;; rank-0: the "list" is the bare scalar itself, not wrapped
(let ((a (list->array 0 (vector) 'scalar)))
  (test-equal '() (array-dimensions a))
  (test-equal 'scalar (array->list a)))

;; rank-1
(let ((a (list->array 1 (vector) '(10 20 30))))
  (test-equal '(3) (array-dimensions a))
  (test-equal '(10 20 30) (array->list a)))

;; a negative or non-integer rank must be rejected, not recurse forever
(test-equal #t (guard (e (#t #t)) (list->array -1 (vector) '()) #f))
(test-equal #t (guard (e (#t #t)) (list->array 1.5 (vector) '()) #f))

;; array->list/array->vector also accept a plain vector/string directly
(test-equal '(1 2 3) (array->list (vector 1 2 3)))
(test-equal (vector #\a #\b) (array->vector "ab"))

;;; --- vector->array / array->vector: flat vector + explicit dimensions ---
(let ((a (vector->array (vector 1 2 3 4 5 6) (vector) 2 3)))
  (test-equal '(2 3) (array-dimensions a))
  (test-equal 1 (array-ref a 0 0))
  (test-equal 3 (array-ref a 0 2))
  (test-equal 4 (array-ref a 1 0))
  (test-equal 6 (array-ref a 1 2))
  (test-equal (vector 1 2 3 4 5 6) (array->vector a)))

(test-equal #t (guard (e (#t #t)) (vector->array (vector 1 2 3) (vector) 2 2) #f))

;;; --- errors are catchable ---
(let ((a (make-array (vector) 3 3)))
  (test-equal #t (guard (e (#t #t)) (array-ref a 5 5) #f))
  (test-equal #t (guard (e (#t #t)) (array-ref a -1 0) #f))
  (test-equal #t (guard (e (#t #t)) (array-ref a 0) #f))
  (test-equal #t (guard (e (#t #t)) (array-ref a 0 0 0) #f))
  (test-equal #t (guard (e (#t #t)) (array-set! a 'v 0) #f)))

(let ((runner (test-runner-current)))
  (test-end "srfi-63")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
