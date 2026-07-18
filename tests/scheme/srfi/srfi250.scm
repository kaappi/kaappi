;; SRFI-250 (insertion-ordered hash tables) conformance tests.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi250.scm

(import (scheme base)
        (srfi 64)
        (srfi 128)
        (srfi 250))

(test-begin "srfi-250")

(define cmp (make-default-comparator))

;; #t iff calling thunk raises any error/exception.
(define (raises? thunk)
  (call-with-current-continuation
   (lambda (k)
     (with-exception-handler
      (lambda (e) (k #t))
      (lambda () (thunk) #f)))))

;; Build a table with the given key/value pairs in order.
(define (table . kvs) (apply hash-table cmp kvs))

;; Keys/values of a table as lists (in insertion order).
(define (keys ht) (vector->list (hash-table-keys ht)))
(define (vals ht) (vector->list (hash-table-values ht)))

;;; --- constructors and basic predicates ----------------------------------

(let ((ht (make-hash-table cmp)))
  (test-assert (hash-table? ht))
  (test-assert (hash-table-empty? ht))
  (test-assert (hash-table-mutable? ht))
  (test-eqv 0 (hash-table-size ht))
  (test-assert (not (hash-table? 42)))
  (test-assert (not (hash-table? '(a b)))))

(let ((ht (hash-table cmp 'a 1 'b 2 'c 3)))
  (test-assert (hash-table? ht))
  (test-assert (hash-table-mutable? ht))         ; hash-table constructor -> mutable
  (test-eqv 3 (hash-table-size ht))
  (test-assert (hash-table-contains? ht 'b))
  (test-assert (not (hash-table-contains? ht 'z)))
  (test-equal '(a b c) (keys ht))                ; insertion order preserved
  (test-equal '(1 2 3) (vals ht)))

;;; --- accessors ----------------------------------------------------------

(let ((ht (table 'a 1 'b 2)))
  (test-eqv 1 (hash-table-ref ht 'a))
  (test-eqv 2 (hash-table-ref ht 'b))
  (test-eqv 99 (hash-table-ref ht 'z (lambda () 99)))          ; failure thunk
  (test-eqv 10 (hash-table-ref ht 'a (lambda () 0) (lambda (v) (* v 10)))) ; success
  (test-assert (raises? (lambda () (hash-table-ref ht 'z))))   ; no failure -> error
  (test-eqv 2 (hash-table-ref/default ht 'b 0))
  (test-eqv 0 (hash-table-ref/default ht 'z 0))
  (test-assert (comparator? (hash-table-comparator ht))))

;;; --- mutators: set!/add!/replace! ---------------------------------------

(let ((ht (make-hash-table cmp)))
  (hash-table-set! ht 'a 1 'b 2 'c 3)            ; multiple pairs, left to right
  (test-equal '(a b c) (keys ht))
  (hash-table-set! ht 'b 20)                     ; update keeps position
  (test-equal '(a b c) (keys ht))
  (test-equal '(1 20 3) (vals ht))
  (hash-table-set! ht 'd 4)                      ; new key appends
  (test-equal '(a b c d) (keys ht)))

(let ((ht (make-hash-table cmp)))
  (hash-table-add! ht 'a 1 'b 2)
  (test-equal '(a b) (keys ht))
  (test-assert (raises? (lambda () (hash-table-add! ht 'a 9))))  ; duplicate -> error
  ;; replace! requires an existing key
  (hash-table-replace! ht 'a 100)
  (test-eqv 100 (hash-table-ref ht 'a))
  (test-equal '(a b) (keys ht))                  ; replace keeps position
  (test-assert (raises? (lambda () (hash-table-replace! ht 'z 0)))))

;; add! rejects a key supplied twice in one call. The spec processes pairs
;; left to right, so the partial mutation before the error is unspecified;
;; check the raise on a throwaway table.
(test-assert (raises? (lambda () (hash-table-add! (make-hash-table cmp) 'x 1 'x 2))))

;;; --- mutators: delete!/intern!/update!/pop!/clear! ----------------------

(let ((ht (table 'a 1 'b 2 'c 3)))
  (test-eqv 2 (hash-table-delete! ht 'a 'z 'c))  ; returns number actually removed
  (test-equal '(b) (keys ht)))

(let ((ht (make-hash-table cmp)))
  (test-eqv 5 (hash-table-intern! ht 'a (lambda () 5)))   ; absent -> set
  (test-eqv 5 (hash-table-intern! ht 'a (lambda () 99)))  ; present -> keep
  (test-eqv 5 (hash-table-ref ht 'a)))

(let ((ht (table 'a 1)))
  (hash-table-update! ht 'a (lambda (v) (+ v 10)))
  (test-eqv 11 (hash-table-ref ht 'a))
  (hash-table-update! ht 'b (lambda (v) (+ v 1)) (lambda () 100))  ; absent -> failure
  (test-eqv 101 (hash-table-ref ht 'b))
  (test-equal '(a b) (keys ht))
  (hash-table-update!/default ht 'c (lambda (v) (+ v 1)) 40)       ; absent -> default
  (test-eqv 41 (hash-table-ref ht 'c))
  (hash-table-update!/default ht 'a (lambda (v) (* v 2)) 0)        ; present
  (test-eqv 22 (hash-table-ref ht 'a))
  (test-equal '(a b c) (keys ht)))

(let ((ht (table 'a 1 'b 2 'c 3)))
  (call-with-values (lambda () (hash-table-pop! ht))    ; removes the newest
    (lambda (k v) (test-eqv 'c k) (test-eqv 3 v)))
  (test-equal '(a b) (keys ht))
  (hash-table-clear! ht)
  (test-assert (hash-table-empty? ht))
  (test-assert (raises? (lambda () (hash-table-pop! ht)))))  ; empty -> error

;;; --- whole table: size / = / find / count -------------------------------

(let ((a (table 'x 1 'y 2))
      (b (table 'y 2 'x 1))          ; same associations, different order
      (c (table 'x 1 'y 3)))
  (test-assert (hash-table= = a b))  ; order does not affect equality
  (test-assert (not (hash-table= = a c)))
  (test-assert (not (hash-table= = a (table 'x 1)))))

(let ((ht (table 'a 1 'b 2 'c 3)))
  (test-eqv 2 (hash-table-find (lambda (k v) (and (> v 1) v)) ht (lambda () 'none)))
  (test-eqv 'none (hash-table-find (lambda (k v) (> v 100)) ht (lambda () 'none)))
  (test-eqv 2 (hash-table-count (lambda (k v) (odd? v)) ht)))

;;; --- keys/values/entries are vectors in insertion order -----------------

(let ((ht (table 'a 1 'b 2 'c 3)))
  (test-assert (vector? (hash-table-keys ht)))
  (test-assert (vector? (hash-table-values ht)))
  (test-equal #(a b c) (hash-table-keys ht))
  (test-equal #(1 2 3) (hash-table-values ht))
  (call-with-values (lambda () (hash-table-entries ht))
    (lambda (ks vs)
      (test-equal #(a b c) ks)
      (test-equal #(1 2 3) vs))))

;;; --- cursors ------------------------------------------------------------

(let ((ht (table 'a 1 'b 2 'c 3)))
  ;; forward walk yields insertion order
  (test-equal '((a . 1) (b . 2) (c . 3))
    (let loop ((cur (hash-table-cursor-first ht)) (acc '()))
      (if (hash-table-cursor-at-end? ht cur)
          (reverse acc)
          (loop (hash-table-cursor-next ht cur)
                (cons (cons (hash-table-cursor-key ht cur)
                            (hash-table-cursor-value ht cur))
                      acc)))))
  ;; backward walk from last yields reverse order
  (test-equal '(c b a)
    (let loop ((cur (hash-table-cursor-last ht)) (acc '()))
      (if (hash-table-cursor-at-end? ht cur)
          (reverse acc)
          (loop (hash-table-cursor-previous ht cur)
                (cons (hash-table-cursor-key ht cur) acc)))))
  ;; cursor-for-key and key+value
  (let ((cur (hash-table-cursor-for-key ht 'b)))
    (test-assert (not (hash-table-cursor-at-end? ht cur)))
    (call-with-values (lambda () (hash-table-cursor-key+value ht cur))
      (lambda (k v) (test-eqv 'b k) (test-eqv 2 v)))
    ;; previous of first is the end state
    (test-assert (hash-table-cursor-at-end?
                  ht (hash-table-cursor-previous
                      ht (hash-table-cursor-first ht))))
    ;; value-set! through a cursor mutates in place
    (hash-table-cursor-value-set! ht cur 200)
    (test-eqv 200 (hash-table-ref ht 'b)))
  ;; absent key -> end state
  (test-assert (hash-table-cursor-at-end? ht (hash-table-cursor-for-key ht 'z))))

;; cursors on an empty table are immediately at the end
(let ((ht (make-hash-table cmp)))
  (test-assert (hash-table-cursor-at-end? ht (hash-table-cursor-first ht)))
  (test-assert (hash-table-cursor-at-end? ht (hash-table-cursor-last ht))))

;;; --- mapping and folding ------------------------------------------------

(let ((ht (table 'a 1 'b 2 'c 3)))
  ;; map -> new table, keys unchanged, order preserved
  (let ((m (hash-table-map (lambda (k v) (* v 10)) ht)))
    (test-equal '(a b c) (keys m))
    (test-equal '(10 20 30) (vals m))
    (test-equal '(1 2 3) (vals ht)))          ; original untouched
  ;; for-each visits in insertion order
  (let ((seen '()))
    (hash-table-for-each (lambda (k v) (set! seen (cons k seen))) ht)
    (test-equal '(c b a) seen))
  ;; map->list in insertion order
  (test-equal '(a1 b2 c3)
    (hash-table-map->list
     (lambda (k v) (string->symbol (string-append (symbol->string k)
                                                   (number->string v))))
     ht))
  ;; fold (proc key value acc)
  (test-eqv 6 (hash-table-fold (lambda (k v acc) (+ v acc)) 0 ht))
  ;; fold-left: (proc acc key value), oldest to newest
  (test-equal '(c b a)
    (hash-table-fold-left (lambda (acc k v) (cons k acc)) '() ht))
  ;; fold-right: (proc key value acc), oldest ends up first
  (test-equal '(a b c)
    (hash-table-fold-right (lambda (k v acc) (cons k acc)) '() ht)))

(let ((ht (table 'a 1 'b 2 'c 3 'd 4)))
  ;; map! mutates values in place, order preserved
  (hash-table-map! (lambda (k v) (* v v)) ht)
  (test-equal '(1 4 9 16) (vals ht))
  ;; prune! removes matching, returns count
  (test-eqv 2 (hash-table-prune! (lambda (k v) (odd? v)) ht))
  (test-equal '(b d) (keys ht))
  (test-equal '(4 16) (vals ht)))

;;; --- copying and conversion ---------------------------------------------

(let ((ht (table 'a 1 'b 2 'c 3)))
  (let ((c (hash-table-copy ht #t)))            ; explicit mutable copy
    (test-assert (hash-table-mutable? c))
    (test-equal '(a b c) (keys c))
    (hash-table-set! c 'a 100)
    (test-eqv 1 (hash-table-ref ht 'a)))        ; independent of original
  (let ((c (hash-table-copy ht)))               ; default copy -> immutable
    (test-assert (not (hash-table-mutable? c)))
    (test-equal '(a b c) (keys c))
    (test-assert (raises? (lambda () (hash-table-set! c 'z 9)))))
  (let ((e (hash-table-empty-copy ht)))
    (test-assert (hash-table-mutable? e))
    (test-assert (hash-table-empty? e))
    (test-assert (comparator? (hash-table-comparator e))))
  ;; ->alist in reverse insertion order
  (test-equal '((c . 3) (b . 2) (a . 1)) (hash-table->alist ht)))

;;; --- alist->hash-table: reverse order, earliest key wins -----------------

(let ((ht (alist->hash-table '((a . 1) (b . 2) (c . 3)) cmp)))
  (test-equal '(c b a) (keys ht)))             ; reverse of alist order

(let ((ht (alist->hash-table '((a . 1) (b . 2) (a . 3)) cmp)))
  (test-eqv 1 (hash-table-ref ht 'a))          ; earliest occurrence wins
  (test-equal '(b a) (keys ht)))

;;; --- hash-table-unfold ---------------------------------------------------

(let ((ht (hash-table-unfold
           (lambda (i) (> i 3))                 ; stop?
           (lambda (i) (values i (* i i)))      ; mapper -> key, value
           (lambda (i) (+ i 1))                 ; successor
           1                                    ; seed
           cmp)))
  (test-equal '(1 2 3) (keys ht))
  (test-equal '(1 4 9) (vals ht)))

;;; --- set operations ------------------------------------------------------

(let ((a (table 'a 1 'b 2 'c 3))
      (b (table 'b 20 'c 30 'd 40)))
  (test-eq a (hash-table-union! a b))           ; returns table1
  (test-equal '(a b c d) (keys a))              ; new keys appended in b's order
  (test-equal '(1 2 3 40) (vals a)))            ; table1 values win on collision

(let ((a (table 'a 1 'b 2 'c 3))
      (b (table 'b 0 'c 0 'd 0)))
  (hash-table-intersection! a b)
  (test-equal '(b c) (keys a)))                 ; keep only keys also in b

(let ((a (table 'a 1 'b 2 'c 3))
      (b (table 'b 0 'c 0)))
  (hash-table-difference! a b)
  (test-equal '(a) (keys a)))                   ; drop keys present in b

(let ((a (table 'a 1 'b 2 'c 3))
      (b (table 'b 0 'c 0 'd 4)))
  (hash-table-xor! a b)                          ; symmetric difference
  (test-equal '(a d) (keys a))
  (test-eqv 4 (hash-table-ref a 'd)))

;;; --- immutable tables reject every mutator ------------------------------

(let ((ht (hash-table-copy (table 'a 1))))       ; immutable
  (test-assert (raises? (lambda () (hash-table-set! ht 'b 2))))
  (test-assert (raises? (lambda () (hash-table-add! ht 'b 2))))
  (test-assert (raises? (lambda () (hash-table-delete! ht 'a))))
  (test-assert (raises? (lambda () (hash-table-update!/default ht 'a (lambda (v) v) 0))))
  (test-assert (raises? (lambda () (hash-table-clear! ht))))
  (test-assert (raises? (lambda () (hash-table-map! (lambda (k v) v) ht)))))

(let ((runner (test-runner-current)))
  (test-end "srfi-250")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
