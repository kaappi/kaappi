;; SRFI-125 (intermediate hash tables) conformance tests — audit Phase 3.4
;; The library is a thin wrapper over SRFI-69; the Zig hash-table primitives
;; ignore custom comparators entirely, so comparator arguments only "work"
;; because they are dropped.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi125.scm

(import (scheme base) (srfi 125) (srfi 128) (chibi test))

(test-begin "srfi-125")

;;; --- construction ---
(define ht (make-hash-table (make-equal-comparator)))
(test #t (hash-table? ht))
(test #t (hash-table-empty? ht))
(test 0 (hash-table-size ht))

(define h2 (hash-table (make-default-comparator) 'a 1 'b 2))
(test 2 (hash-table-size h2))
(test 1 (hash-table-ref/default h2 'a #f))
(test 2 (hash-table-ref/default h2 'b #f))

;;; --- set!/ref/contains ---
(hash-table-set! ht 'x 10)
(hash-table-set! ht 'y 20)
(test #t (hash-table-contains? ht 'x))
(test #f (hash-table-contains? ht 'z))
(test #f (hash-table-empty? ht))
(test 2 (hash-table-size ht))
(test 10 (hash-table-ref ht 'x))
(test 'missing (hash-table-ref ht 'z (lambda () 'missing)))
(test 99 (hash-table-ref/default ht 'z 99))

;; ref with no failure raises on absent key
(test #t (guard (e (#t #t)) (hash-table-ref ht 'z) #f))

;; overwrite
(hash-table-set! ht 'x 11)
(test 11 (hash-table-ref ht 'x))
(test 2 (hash-table-size ht))

;;; --- update! / intern! / delete! ---
(hash-table-update! ht 'x (lambda (v) (+ v 1)))
(test 12 (hash-table-ref ht 'x))
(hash-table-update! ht 'w (lambda (v) (+ v 5)) (lambda () 100))
(test 105 (hash-table-ref ht 'w))

(test 20 (hash-table-intern! ht 'y (lambda () 999)))   ; present: keeps value
(test 7 (hash-table-intern! ht 'v (lambda () 7)))      ; absent: installs
(test 7 (hash-table-ref ht 'v))

(hash-table-delete! ht 'w)
(hash-table-delete! ht 'v)
(test #f (hash-table-contains? ht 'w))
(test 2 (hash-table-size ht))

;;; --- keys/values/entries/->alist ---
(define (set= a b)
  (and (= (length a) (length b))
       (let loop ((x a)) (or (null? x) (and (member (car x) b) (loop (cdr x)))))))
(test #t (set= '(x y) (hash-table-keys ht)))
(test #t (set= '(12 20) (hash-table-values ht)))
(test #t (call-with-values (lambda () (hash-table-entries ht))
           (lambda (ks vs) (and (set= '(x y) ks) (set= '(12 20) vs)))))
(test #t (set= '((x . 12) (y . 20)) (hash-table->alist ht)))

;;; --- copy independence ---
(define cp (hash-table-copy ht))
(hash-table-set! cp 'x 0)
(test 12 (hash-table-ref ht 'x))
(test 0 (hash-table-ref cp 'x))

;;; --- iteration ---
(test 32 (hash-table-fold (lambda (k v acc) (+ v acc)) 0 ht))
(test 1 (hash-table-count (lambda (k v) (> v 15)) ht))
(test #t (let ((n 0))
           (hash-table-for-each (lambda (k v) (set! n (+ n v))) ht)
           (= n 32)))
(test #t (set= '(24 40) (hash-table-map->list (lambda (k v) (* 2 v)) ht)))

;; hash-table-find: SRFI-125 returns the true value produced by proc
;; FAIL: #1229 (hash-table-find returns (key . value) instead of proc's result)
;; (test 120 (hash-table-find (lambda (k v) (and (= v 12) (* v 10))) ht
;;                            (lambda () 'nope)))
(test 'nope (hash-table-find (lambda (k v) #f) ht (lambda () 'nope)))

;; hash-table-ref success procedure: (hash-table-ref ht key failure success)
;; FAIL: #1229 (hash-table-ref ignores the success procedure)
;; (test 1200 (hash-table-ref ht 'x (lambda () 'no) (lambda (v) (* v 100))))

;;; --- set algebra ---
(define ta (hash-table (make-default-comparator) 'a 1 'b 2))
(define tb (hash-table (make-default-comparator) 'b 99 'c 3))
(hash-table-union! ta tb)                  ; ht1 values prevail on collision
(test 3 (hash-table-size ta))
(test 2 (hash-table-ref ta 'b))
(test 3 (hash-table-ref ta 'c))

(define tc (hash-table (make-default-comparator) 'a 1 'b 2 'c 3))
(hash-table-intersection! tc tb)
(test #t (set= '(b c) (hash-table-keys tc)))

(define td (hash-table (make-default-comparator) 'a 1 'b 2))
(hash-table-difference! td tb)
(test #t (set= '(a) (hash-table-keys td)))

;;; --- missing exports ---
;; FAIL: #1229 (hash-table-walk, hash-table-unfold, alist->hash-table,
;;   hash-table-exists?, hash-table=?, hash-table-mutable?,
;;   hash-table-clear!, hash-table-pop!, hash-table-prune!, hash-table-map,
;;   hash-table-map!, hash-table-update!/default, hash-table-empty-copy,
;;   hash-table-merge!, hash-table-xor!, hash, string-hash, string-ci-hash,
;;   hash-by-identity, hash-table-equivalence-function,
;;   hash-table-hash-function not exported)
;; (test 3 (hash-table-ref (alist->hash-table '((a . 3)) (make-equal-comparator)) 'a))

(test-end "srfi-125")
