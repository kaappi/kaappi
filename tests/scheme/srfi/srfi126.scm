;; SRFI 126 (R6RS-based hashtables) conformance test.
;;
;; This exercises the non-weak baseline implemented in lib/srfi/126.sld —
;; every constructor's `weakness` argument only accepts `#f` (anything else
;; errors; see the header comment of that file for the rationale). Two
;; things the spec itself calls out as unportable are intentionally NOT
;; covered here because they are not implemented:
;;
;;   * weak / ephemeral hashtable behavior (needs platform/GC support this
;;     port doesn't add — the spec agrees this "cannot be implemented by
;;     portable library code")
;;   * the `#hasheq(...)`-style external representation (reader/printer
;;     syntax) — likewise spec-documented as needing non-portable support.

(import (scheme base) (scheme process-context) (srfi 64) (srfi 126))

(test-begin "srfi-126")

;; --- local test helpers (order-independent collection comparisons) -------

(define (all-in? lst other)
  (or (null? lst) (and (member (car lst) other) (all-in? (cdr lst) other))))

(define (set-equal? a b)
  (and (= (length a) (length b)) (all-in? a b) (all-in? b a)))

;; A custom hash/equivalence pair used to exercise the general
;; make-hashtable / alist->hashtable constructors: keys are "equal" when
;; congruent mod 5.
(define (mod5-hash x) (modulo x 5))
(define (mod5-eq? a b) (= (modulo a 5) (modulo b 5)))

;;; =========================================================================
;;; Constructors
;;; =========================================================================

(test-assert "make-eq-hashtable returns a hashtable"
             (hashtable? (make-eq-hashtable)))
(test-assert "make-eq-hashtable/capacity" (hashtable? (make-eq-hashtable 16)))
(test-assert "make-eq-hashtable/capacity+weakness#f"
             (hashtable? (make-eq-hashtable 16 #f)))
(test-assert "make-eqv-hashtable returns a hashtable"
             (hashtable? (make-eqv-hashtable)))
(test-assert "make-eqv-hashtable/capacity" (hashtable? (make-eqv-hashtable 16)))
(test-assert "make-eqv-hashtable/capacity+weakness#f"
             (hashtable? (make-eqv-hashtable 16 #f)))

(test-error "make-eq-hashtable rejects non-#f weakness"
            (make-eq-hashtable 16 'weak-key))
(test-error "make-eqv-hashtable rejects non-#f weakness"
            (make-eqv-hashtable 16 'ephemeral-value))

;; eq?/eqv? delegation: hash = #f with equiv = eq?/eqv? behaves like the
;; dedicated constructors.
(test-assert "make-hashtable delegates to make-eq-hashtable when hash=#f, equiv=eq?"
             (eq? eq? (hashtable-equivalence-function (make-hashtable #f eq?))))
(test-assert "make-hashtable delegates to make-eqv-hashtable when hash=#f, equiv=eqv?"
             (eq? eqv?
                  (hashtable-equivalence-function (make-hashtable #f eqv?))))

;; General case: explicit hash + equiv.
(define cht (make-hashtable mod5-hash mod5-eq? 16))
(hashtable-set! cht 3 'three)
(test-equal "make-hashtable: custom equivalence groups congruent keys"
            'three
            (hashtable-ref cht 8))
(test-error "make-hashtable rejects non-#f weakness"
            (make-hashtable mod5-hash mod5-eq? 16 'weak-key-and-value))

;; alist->eq-hashtable / alist->eqv-hashtable / alist->hashtable, all three
;; arities, plus first-occurrence-wins on duplicate keys.
(define al '((a . 1) (b . 2) (a . 99)))

(test-equal "alist->eq-hashtable: first occurrence wins"
            1
            (hashtable-ref (alist->eq-hashtable al) 'a))
(test-equal "alist->eq-hashtable: dedups size"
            2
            (hashtable-size (alist->eq-hashtable al)))
(test-equal "alist->eq-hashtable/capacity: same contents"
            1
            (hashtable-ref (alist->eq-hashtable 32 al) 'a))
(test-equal "alist->eq-hashtable/capacity+weakness: same contents"
            1
            (hashtable-ref (alist->eq-hashtable 32 #f al) 'a))
(test-error "alist->eq-hashtable rejects non-#f weakness"
            (alist->eq-hashtable 32 'weak-key al))

(test-equal "alist->eqv-hashtable: basic"
            2
            (hashtable-ref (alist->eqv-hashtable '((1 . 2))) 1))
(test-error "alist->eqv-hashtable rejects non-#f weakness"
            (alist->eqv-hashtable 32 'weak-key '((1 . 2))))

(define cal '((3 . three) (8 . eight-collides-with-three)))
(test-equal "alist->hashtable: custom equiv, first occurrence wins"
            'three
            (hashtable-ref (alist->hashtable mod5-hash mod5-eq? cal) 3))
(test-equal "alist->hashtable/capacity"
            'three
            (hashtable-ref (alist->hashtable mod5-hash mod5-eq? 16 cal) 3))
(test-equal "alist->hashtable/capacity+weakness"
            'three
            (hashtable-ref (alist->hashtable mod5-hash mod5-eq? 16 #f cal) 3))
(test-error "alist->hashtable rejects non-#f weakness"
            (alist->hashtable mod5-hash mod5-eq? 16 'weak-key cal))
(test-assert "alist->hashtable delegates to eq? when hash=#f"
             (eq? eq?
                  (hashtable-equivalence-function (alist->hashtable #f
                                                                    eq?
                                                                    '((a . 1))))))

;;; =========================================================================
;;; Core access / mutation
;;; =========================================================================

(define ht (make-eqv-hashtable))

(test-assert "a fresh hashtable is empty" (hashtable-empty? ht))
(test-equal "a fresh hashtable has size 0" 0 (hashtable-size ht))

(hashtable-set! ht 'name "kaappi")
(hashtable-set! ht 'version 126)

(test-equal "hashtable-size after two inserts" 2 (hashtable-size ht))
(test-equal "hashtable-ref finds an existing key"
            "kaappi"
            (hashtable-ref ht 'name))
(test-assert "hashtable-contains? true for existing key"
             (hashtable-contains? ht 'name))
(test-assert "hashtable-contains? false for missing key"
             (not (hashtable-contains? ht 'missing)))

(test-equal "hashtable-ref/default returns default for missing key"
            'fallback
            (hashtable-ref ht 'missing 'fallback))
(test-error "hashtable-ref with no default errors on missing key"
            (hashtable-ref ht 'missing))

;; The default in hashtable-ref is a literal value, never invoked — even if
;; it happens to be a procedure (the key semantic difference from SRFI 69's
;; hash-table-ref, whose extra argument is invoked as a thunk).
(test-assert "hashtable-ref returns a procedure default as-is, uncalled"
             (eq? car (hashtable-ref ht 'missing car)))

(hashtable-delete! ht 'version)
(test-equal "hashtable-delete! removes the key" 1 (hashtable-size ht))
(test-assert "hashtable-contains? false after delete"
             (not (hashtable-contains? ht 'version)))

;; hashtable-lookup: two values (value, found?).
(let-values (((v found?) (hashtable-lookup ht 'name)))
  (test-equal "hashtable-lookup value for existing key" "kaappi" v)
  (test-assert "hashtable-lookup found? #t for existing key" found?))
(let-values (((v found?) (hashtable-lookup ht 'missing)))
  (test-assert "hashtable-lookup found? #f for missing key" (not found?)))

;; hashtable-update!
(hashtable-set! ht 'counter 10)
(test-equal "hashtable-update! applies proc and returns new value"
            11
            (hashtable-update! ht 'counter (lambda (v) (+ v 1))))
(test-equal "hashtable-update! persisted the new value"
            11
            (hashtable-ref ht 'counter))
(test-error "hashtable-update! with no default errors on missing key"
            (hashtable-update! ht 'nope (lambda (v) v)))
(test-equal "hashtable-update!/default uses default when key missing"
            1
            (hashtable-update! ht 'fresh (lambda (v) (+ v 1)) 0))
;; The default in hashtable-update! is likewise a plain value applied to
;; `proc`, never invoked itself.
(test-assert "hashtable-update!'s default is passed to proc uncalled"
             (eq? car
                  (cadr (hashtable-update! ht
                                           'wrapped
                                           (lambda (v) (list 'wrapped v))
                                           car))))

;; hashtable-intern!
(define intern-calls 0)
(define (make-value) (set! intern-calls (+ intern-calls 1)) intern-calls)
(test-equal "hashtable-intern! computes a value for a fresh key"
            1
            (hashtable-intern! ht 'interned make-value))
(test-equal "hashtable-intern! does not recompute for an existing key"
            1
            (hashtable-intern! ht 'interned make-value))
(test-equal "hashtable-intern!'s default-proc ran exactly once" 1 intern-calls)

;;; =========================================================================
;;; Copying
;;; =========================================================================

(define orig (make-eqv-hashtable))
(hashtable-set! orig 1 'one)
(define cp (hashtable-copy orig))
(hashtable-set! cp 2 'two)

(test-equal "hashtable-copy: original untouched by mutating the copy"
            1
            (hashtable-size orig))
(test-equal "hashtable-copy: copy has the new entry" 2 (hashtable-size cp))
(test-equal "hashtable-copy: shared entry carried over"
            'one
            (hashtable-ref cp 1))
(test-assert "hashtable-copy/mutable-true still works"
             (hashtable? (hashtable-copy orig #t)))
(test-assert "hashtable-copy/mutable+weakness#f still works"
             (hashtable? (hashtable-copy orig #t #f)))
(test-error "hashtable-copy rejects non-#f weakness"
            (hashtable-copy orig #t 'weak-key))

(define clear-ht (make-eq-hashtable))
(hashtable-set! clear-ht 'a 1)
(hashtable-set! clear-ht 'b 2)
(define clear-ht-alias clear-ht)
(hashtable-clear! clear-ht)
(test-equal "hashtable-clear! empties the table" 0 (hashtable-size clear-ht))
(test-assert "hashtable-clear! mutates in place (visible via alias)"
             (hashtable-empty? clear-ht-alias))
(hashtable-set! clear-ht 'c 3)
(test-equal "hashtable-clear!'d table is still usable"
            3
            (hashtable-ref clear-ht 'c))

(define ec-src (make-eq-hashtable))
(hashtable-set! ec-src 'x 1)
(define ec (hashtable-empty-copy ec-src))
(test-equal "hashtable-empty-copy: result is empty" 0 (hashtable-size ec))
(test-equal "hashtable-empty-copy: source untouched" 1 (hashtable-size ec-src))
(test-assert "hashtable-empty-copy: preserves equivalence function"
             (eq? eq? (hashtable-equivalence-function ec)))

;;; =========================================================================
;;; Key/value collections
;;; =========================================================================

(define kv-ht (make-eqv-hashtable))
(hashtable-set! kv-ht 1 'a)
(hashtable-set! kv-ht 2 'b)
(hashtable-set! kv-ht 3 'c)

(test-assert "hashtable-keys returns a vector" (vector? (hashtable-keys kv-ht)))
(test-assert "hashtable-values returns a vector"
             (vector? (hashtable-values kv-ht)))
(test-assert "hashtable-keys has the right elements"
             (set-equal? '(1 2 3) (vector->list (hashtable-keys kv-ht))))
(test-assert "hashtable-values has the right elements"
             (set-equal? '(a b c) (vector->list (hashtable-values kv-ht))))

(test-assert "hashtable-key-list returns a list"
             (list? (hashtable-key-list kv-ht)))
(test-assert "hashtable-value-list returns a list"
             (list? (hashtable-value-list kv-ht)))
(test-assert "hashtable-key-list has the right elements"
             (set-equal? '(1 2 3) (hashtable-key-list kv-ht)))
(test-assert "hashtable-value-list has the right elements"
             (set-equal? '(a b c) (hashtable-value-list kv-ht)))

(let-values (((ks vs) (hashtable-entries kv-ht)))
  (test-assert "hashtable-entries returns two vectors"
               (and (vector? ks) (vector? vs)))
  (test-equal "hashtable-entries: keys/values same length"
              (vector-length ks)
              (vector-length vs))
  (test-assert "hashtable-entries: keys correspond to values"
               (let loop ((i 0))
                 (or (= i (vector-length ks))
                     (and (equal? (hashtable-ref kv-ht (vector-ref ks i))
                                  (vector-ref vs i))
                          (loop (+ i 1)))))))

(let-values (((ks vs) (hashtable-entry-lists kv-ht)))
  (test-assert "hashtable-entry-lists returns two lists"
               (and (list? ks) (list? vs)))
  (test-equal "hashtable-entry-lists: keys/values same length"
              (length ks)
              (length vs))
  (test-assert "hashtable-entry-lists: keys correspond to values"
               (let loop ((ks ks) (vs vs))
                 (or (null? ks)
                     (and (equal? (hashtable-ref kv-ht (car ks)) (car vs))
                          (loop (cdr ks) (cdr vs)))))))

;;; =========================================================================
;;; Iteration
;;; =========================================================================

(define walked '())
(hashtable-walk kv-ht (lambda (k v) (set! walked (cons (cons k v) walked))))
(test-equal "hashtable-walk visits every entry" 3 (length walked))
(test-assert "hashtable-walk saw (1 . a)" (member (cons 1 'a) walked))
(test-assert "hashtable-walk saw (2 . b)" (member (cons 2 'b) walked))
(test-assert "hashtable-walk saw (3 . c)" (member (cons 3 'c) walked))

(define ua-ht (make-eqv-hashtable))
(hashtable-set! ua-ht 1 10)
(hashtable-set! ua-ht 2 20)
(hashtable-update-all! ua-ht (lambda (k v) (+ v k)))
(test-equal "hashtable-update-all! updates every value (1)"
            11
            (hashtable-ref ua-ht 1))
(test-equal "hashtable-update-all! updates every value (2)"
            22
            (hashtable-ref ua-ht 2))

(define pr-ht (make-eqv-hashtable))
(hashtable-set! pr-ht 1 10)
(hashtable-set! pr-ht 2 21)
(hashtable-set! pr-ht 3 30)
(hashtable-prune! pr-ht (lambda (k v) (odd? v)))
(test-equal "hashtable-prune! removes matching entries"
            2
            (hashtable-size pr-ht))
(test-assert "hashtable-prune! kept a non-matching entry"
             (hashtable-contains? pr-ht 1))
(test-assert "hashtable-prune! dropped a matching entry"
             (not (hashtable-contains? pr-ht 2)))

(define dest (make-eqv-hashtable))
(hashtable-set! dest 1 'dest-1)
(hashtable-set! dest 2 'dest-2)
(define src (make-eqv-hashtable))
(hashtable-set! src 2 'src-2)
(hashtable-set! src 3 'src-3)
(define merge-result (hashtable-merge! dest src))
(test-assert "hashtable-merge! returns dest" (eq? dest merge-result))
(test-equal "hashtable-merge!: source wins on key collision"
            'src-2
            (hashtable-ref dest 2))
(test-equal "hashtable-merge!: new key copied in" 'src-3 (hashtable-ref dest 3))
(test-equal "hashtable-merge!: untouched key preserved"
            'dest-1
            (hashtable-ref dest 1))

(define sum-ht (make-eqv-hashtable))
(hashtable-set! sum-ht 1 10)
(hashtable-set! sum-ht 2 20)
(hashtable-set! sum-ht 3 30)
(test-equal "hashtable-sum folds values"
            60
            (hashtable-sum sum-ht 0 (lambda (k v acc) (+ v acc))))

(test-assert "hashtable-map->lset collects mapped results"
             (set-equal? '(11 22 33)
                         (hashtable-map->lset sum-ht (lambda (k v) (+ k v)))))

(let-values (((k v found?) (hashtable-find sum-ht (lambda (k v) (= v 20)))))
  (test-equal "hashtable-find locates the right key" 2 k)
  (test-equal "hashtable-find returns the paired value" 20 v)
  (test-assert "hashtable-find found? is #t on a match" found?))
(let-values (((k v found?) (hashtable-find sum-ht (lambda (k v) (= v 999)))))
  (test-assert "hashtable-find found? is #f with no match" (not found?)))

;;; =========================================================================
;;; Misc
;;; =========================================================================

(test-assert "hashtable-empty? true for an empty table"
             (hashtable-empty? (make-eq-hashtable)))
(test-assert "hashtable-empty? false for a non-empty table"
             (not (hashtable-empty? sum-ht)))

(define pop-ht (make-eqv-hashtable))
(hashtable-set! pop-ht 'x 1)
(let-values (((k v) (hashtable-pop! pop-ht)))
  (test-equal "hashtable-pop! returns the key" 'x k)
  (test-equal "hashtable-pop! returns the value" 1 v))
(test-assert "hashtable-pop! removed the only entry" (hashtable-empty? pop-ht))
(test-error "hashtable-pop! on an empty table errors" (hashtable-pop! pop-ht))

(define cnt-ht (make-eqv-hashtable))
(test-equal "hashtable-inc! on a missing key starts from 0"
            1
            (hashtable-inc! cnt-ht 'n))
(test-equal "hashtable-inc! with an explicit number"
            6
            (hashtable-inc! cnt-ht 'n 5))
(test-equal "hashtable-dec! defaults to 1" 5 (hashtable-dec! cnt-ht 'n))
(test-equal "hashtable-dec! with an explicit number"
            0
            (hashtable-dec! cnt-ht 'n 5))
(test-equal "hashtable-inc! on a missing key with explicit number"
            3
            (hashtable-inc! cnt-ht 'fresh 3))

;;; =========================================================================
;;; Inspection
;;; =========================================================================

(test-assert "eq-hashtable equivalence function is eq?"
             (eq? eq? (hashtable-equivalence-function (make-eq-hashtable))))
(test-assert "eq-hashtable hash function is #f"
             (not (hashtable-hash-function (make-eq-hashtable))))
(test-assert "eqv-hashtable equivalence function is eqv?"
             (eq? eqv? (hashtable-equivalence-function (make-eqv-hashtable))))
(test-assert "eqv-hashtable hash function is #f"
             (not (hashtable-hash-function (make-eqv-hashtable))))
(test-assert "custom hashtable equivalence function is the given predicate"
             (eq? mod5-eq? (hashtable-equivalence-function cht)))
(test-assert "custom hashtable hash function is the given hash procedure"
             (eq? mod5-hash (hashtable-hash-function cht)))

(test-assert "hashtable-weakness is always #f"
             (not (hashtable-weakness (make-eq-hashtable))))
(test-assert "hashtable-mutable? is always #t"
             (hashtable-mutable? (make-eq-hashtable)))
(test-error "hashtable-weakness on a non-hashtable errors"
            (hashtable-weakness 42))
(test-error "hashtable-mutable? on a non-hashtable errors"
            (hashtable-mutable? 42))

;;; =========================================================================
;;; Hash functions
;;; =========================================================================

(test-assert "equal-hash returns an exact integer"
             (integer? (equal-hash '(1 2 3))))
(test-equal "equal-hash is consistent for equal? structures"
            (equal-hash (list 1 "two" 'three))
            (equal-hash (list 1 "two" 'three)))

;; The spec requires equal-hash to terminate even on cyclic structures.
(define circular (list 1 2 3))
(set-cdr! (cddr circular) circular)
(test-assert "equal-hash terminates on a circular list"
             (integer? (equal-hash circular)))

(test-equal "string-hash is consistent for string=? strings"
            (string-hash "abc")
            (string-hash "abc"))
(test-equal "string-ci-hash ignores case"
            (string-ci-hash "ABC")
            (string-ci-hash "abc"))
(test-assert "symbol-hash returns an exact integer"
             (integer? (symbol-hash 'foo)))
(test-equal "symbol-hash is consistent for eq? symbols"
            (symbol-hash 'foo)
            (symbol-hash 'foo))

(let ((runner (test-runner-current)))
  (test-end "srfi-126")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
