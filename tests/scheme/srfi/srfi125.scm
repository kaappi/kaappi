;; SRFI-125 (intermediate hash tables) conformance tests
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi125.scm

(import (scheme base) (scheme process-context) (srfi 64) (srfi 125) (srfi 128))

(test-begin "srfi-125")

;;; --- construction ---
(define ht (make-hash-table (make-equal-comparator)))
(test-assert "hash-table?" (hash-table? ht))
(test-assert "empty?" (hash-table-empty? ht))
(test-equal "size 0" 0 (hash-table-size ht))

(define h2 (hash-table (make-default-comparator) 'a 1 'b 2))
(test-equal "hash-table size" 2 (hash-table-size h2))
(test-equal "hash-table ref a" 1 (hash-table-ref/default h2 'a #f))
(test-equal "hash-table ref b" 2 (hash-table-ref/default h2 'b #f))

;;; --- set!/ref/contains ---
(hash-table-set! ht 'x 10)
(hash-table-set! ht 'y 20)
(test-assert "contains x" (hash-table-contains? ht 'x))
(test-assert "not contains z" (not (hash-table-contains? ht 'z)))
(test-assert "not empty" (not (hash-table-empty? ht)))
(test-equal "size 2" 2 (hash-table-size ht))
(test-equal "ref x" 10 (hash-table-ref ht 'x))
(test-equal "ref missing with failure" 'missing (hash-table-ref ht 'z (lambda () 'missing)))
(test-equal "ref/default absent" 99 (hash-table-ref/default ht 'z 99))

;; ref with no failure raises on absent key
(test-assert "ref absent raises"
  (guard (e (#t #t)) (hash-table-ref ht 'z) #f))

;; overwrite
(hash-table-set! ht 'x 11)
(test-equal "overwrite" 11 (hash-table-ref ht 'x))
(test-equal "size after overwrite" 2 (hash-table-size ht))

;;; --- hash-table-ref success procedure (bug #1229) ---
(hash-table-set! ht 'x 12)
(test-equal "ref with success proc"
  1200 (hash-table-ref ht 'x (lambda () 'no) (lambda (v) (* v 100))))
(test-equal "ref without success proc" 12 (hash-table-ref ht 'x))
(test-equal "ref absent ignores success"
  'missing (hash-table-ref ht 'absent (lambda () 'missing) (lambda (v) 'never)))

;;; --- update! / intern! / delete! ---
(hash-table-update! ht 'x (lambda (v) (+ v 1)))
(test-equal "update! existing" 13 (hash-table-ref ht 'x))
(hash-table-update! ht 'w (lambda (v) (+ v 5)) (lambda () 100))
(test-equal "update! with failure" 105 (hash-table-ref ht 'w))

;; update! with success procedure
(hash-table-set! ht 'x 12)
(hash-table-update! ht 'x (lambda (v) (+ v 1)) (lambda () 0) (lambda (v) (* v 10)))
(test-equal "update! with success proc" 121 (hash-table-ref ht 'x))

(hash-table-set! ht 'y 20)
(test-equal "intern! present" 20 (hash-table-intern! ht 'y (lambda () 999)))
(test-equal "intern! absent" 7 (hash-table-intern! ht 'v (lambda () 7)))
(test-equal "intern! installed" 7 (hash-table-ref ht 'v))

(hash-table-delete! ht 'w)
(hash-table-delete! ht 'v)
(test-assert "delete!" (not (hash-table-contains? ht 'w)))

;;; --- keys/values/entries/->alist ---
(hash-table-clear! ht)
(hash-table-set! ht 'x 12)
(hash-table-set! ht 'y 20)
(define (set= a b)
  (and (= (length a) (length b))
       (let loop ((x a)) (or (null? x) (and (member (car x) b) (loop (cdr x)))))))
(test-assert "keys" (set= '(x y) (hash-table-keys ht)))
(test-assert "values" (set= '(12 20) (hash-table-values ht)))
(test-assert "entries"
  (call-with-values (lambda () (hash-table-entries ht))
    (lambda (ks vs) (and (set= '(x y) ks) (set= '(12 20) vs)))))
(test-assert "->alist" (set= '((x . 12) (y . 20)) (hash-table->alist ht)))

;;; --- copy independence ---
(define cp (hash-table-copy ht))
(hash-table-set! cp 'x 0)
(test-equal "copy independence orig" 12 (hash-table-ref ht 'x))
(test-equal "copy independence copy" 0 (hash-table-ref cp 'x))

;;; --- iteration ---
(test-equal "fold" 32 (hash-table-fold (lambda (k v acc) (+ v acc)) 0 ht))
(test-equal "count" 1 (hash-table-count (lambda (k v) (> v 15)) ht))
(test-assert "for-each"
  (let ((n 0))
    (hash-table-for-each (lambda (k v) (set! n (+ n v))) ht)
    (= n 32)))
(test-assert "map->list"
  (set= '(24 40) (hash-table-map->list (lambda (k v) (* 2 v)) ht)))

;; hash-table-walk (SRFI-69 arg order)
(test-assert "walk"
  (let ((n 0))
    (hash-table-walk ht (lambda (k v) (set! n (+ n v))))
    (= n 32)))

;;; --- hash-table-find (bug #1229) ---
(test-equal "find returns proc result"
  120 (hash-table-find (lambda (k v) (and (= v 12) (* v 10))) ht
                       (lambda () 'nope)))
(test-equal "find failure" 'nope
  (hash-table-find (lambda (k v) #f) ht (lambda () 'nope)))

;;; --- hash-table-exists? (re-exported from SRFI-69) ---
(test-assert "exists? present" (hash-table-exists? ht 'x))
(test-assert "exists? absent" (not (hash-table-exists? ht 'zzz)))

;;; --- set algebra ---
(define ta (hash-table (make-default-comparator) 'a 1 'b 2))
(define tb (hash-table (make-default-comparator) 'b 99 'c 3))
(hash-table-union! ta tb)
(test-equal "union! size" 3 (hash-table-size ta))
(test-equal "union! ht1 wins" 2 (hash-table-ref ta 'b))
(test-equal "union! adds new" 3 (hash-table-ref ta 'c))

(define tc (hash-table (make-default-comparator) 'a 1 'b 2 'c 3))
(hash-table-intersection! tc tb)
(test-assert "intersection!" (set= '(b c) (hash-table-keys tc)))

(define td (hash-table (make-default-comparator) 'a 1 'b 2))
(hash-table-difference! td tb)
(test-assert "difference!" (set= '(a) (hash-table-keys td)))

;;; --- merge! (SRFI-125 = union!, ht1 wins) ---
(define tm1 (hash-table (make-default-comparator) 'a 1 'b 2))
(define tm2 (hash-table (make-default-comparator) 'b 99 'c 3))
(hash-table-merge! tm1 tm2)
(test-equal "merge! size" 3 (hash-table-size tm1))
(test-equal "merge! ht1 wins" 2 (hash-table-ref tm1 'b))
(test-equal "merge! adds new" 3 (hash-table-ref tm1 'c))

;;; --- xor! (symmetric difference) ---
(define tx1 (hash-table (make-default-comparator) 'a 1 'b 2))
(define tx2 (hash-table (make-default-comparator) 'b 99 'c 3))
(hash-table-xor! tx1 tx2)
(test-assert "xor! keys" (set= '(a c) (hash-table-keys tx1)))
(test-equal "xor! kept" 1 (hash-table-ref tx1 'a))
(test-equal "xor! added" 3 (hash-table-ref tx1 'c))

;;; --- unfold ---
(define hu (hash-table-unfold
             (lambda (s) (> s 3))
             (lambda (s) (values s (* s 10)))
             (lambda (s) (+ s 1))
             1
             (make-default-comparator)))
(test-equal "unfold size" 3 (hash-table-size hu))
(test-equal "unfold 1" 10 (hash-table-ref hu 1))
(test-equal "unfold 2" 20 (hash-table-ref hu 2))
(test-equal "unfold 3" 30 (hash-table-ref hu 3))

;;; --- alist->hash-table ---
(define ha (alist->hash-table '((a . 3) (b . 4))))
(test-equal "alist->ht size" 2 (hash-table-size ha))
(test-equal "alist->ht ref a" 3 (hash-table-ref ha 'a))
(test-equal "alist->ht ref b" 4 (hash-table-ref ha 'b))

;;; --- hash-table=? ---
(define he1 (hash-table (make-default-comparator) 'a 1 'b 2))
(define he2 (hash-table (make-default-comparator) 'b 2 'a 1))
(define he3 (hash-table (make-default-comparator) 'a 1 'b 99))
(define he4 (hash-table (make-default-comparator) 'a 1))
(test-assert "=? same" (hash-table=? (make-default-comparator) he1 he2))
(test-assert "=? diff value" (not (hash-table=? (make-default-comparator) he1 he3)))
(test-assert "=? diff size" (not (hash-table=? (make-default-comparator) he1 he4)))

;;; --- mutable? ---
(test-assert "mutable?" (hash-table-mutable? ht))

;;; --- pop! ---
(define hp (hash-table (make-default-comparator) 'a 1 'b 2))
(test-equal "pop! before size" 2 (hash-table-size hp))
(call-with-values (lambda () (hash-table-pop! hp))
  (lambda (k v)
    (test-assert "pop! valid entry"
      (or (and (eq? k 'a) (= v 1))
          (and (eq? k 'b) (= v 2))))
    (test-equal "pop! after size" 1 (hash-table-size hp))))

;;; --- clear! ---
(define hc (hash-table (make-default-comparator) 'a 1 'b 2 'c 3))
(test-equal "clear! before" 3 (hash-table-size hc))
(hash-table-clear! hc)
(test-equal "clear! after" 0 (hash-table-size hc))
(test-assert "clear! empty" (hash-table-empty? hc))

;;; --- map (proc takes 1 arg: value) ---
(define hm (hash-table (make-default-comparator) 'a 1 'b 2))
(define mapped (hash-table-map (lambda (v) (* v 10)) (make-default-comparator) hm))
(test-equal "map a" 10 (hash-table-ref mapped 'a))
(test-equal "map b" 20 (hash-table-ref mapped 'b))
(test-equal "map original unchanged" 1 (hash-table-ref hm 'a))

;;; --- map! (proc takes 2 args: key, value) ---
(define hm2 (hash-table (make-default-comparator) 'a 1 'b 2))
(hash-table-map! (lambda (k v) (* v 100)) hm2)
(test-equal "map! a" 100 (hash-table-ref hm2 'a))
(test-equal "map! b" 200 (hash-table-ref hm2 'b))

;;; --- prune! ---
(define hpr (hash-table (make-default-comparator) 'a 1 'b 20 'c 3 'd 40))
(hash-table-prune! (lambda (k v) (> v 10)) hpr)
(test-assert "prune!" (set= '(a c) (hash-table-keys hpr)))

;;; --- empty-copy ---
(define hec (hash-table-empty-copy ht))
(test-assert "empty-copy is ht" (hash-table? hec))
(test-equal "empty-copy size" 0 (hash-table-size hec))

;;; --- update!/default ---
(define hud (hash-table (make-default-comparator) 'a 5))
(hash-table-update!/default hud 'a (lambda (v) (+ v 1)) 0)
(test-equal "update!/default existing" 6 (hash-table-ref hud 'a))
(hash-table-update!/default hud 'b (lambda (v) (+ v 1)) 0)
(test-equal "update!/default absent" 1 (hash-table-ref hud 'b))

;;; --- hash functions ---
(test-assert "hash" (integer? (hash 'foo)))
(test-assert "string-hash" (integer? (string-hash "hello")))
(test-assert "string-ci-hash" (integer? (string-ci-hash "Hello")))
(test-assert "hash-by-identity" (integer? (hash-by-identity 'bar)))
(test-equal "string-ci-hash case insensitive"
  (string-ci-hash "abc") (string-ci-hash "ABC"))

;;; --- equivalence-function / hash-function ---
(test-assert "equivalence-function" (procedure? (hash-table-equivalence-function ht)))
(test-assert "hash-function" (procedure? (hash-table-hash-function ht)))

(let ((runner (test-runner-current)))
  (test-end "srfi-125")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
