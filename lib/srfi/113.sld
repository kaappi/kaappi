(define-library (srfi 113)
  (import (scheme base) (scheme case-lambda) (srfi 69) (srfi 128))
  (export
    ;; Constructors
    set bag set-unfold bag-unfold
    ;; Predicates
    set? bag? set-contains? bag-contains?
    set-empty? bag-empty? set-disjoint? bag-disjoint?
    ;; Accessors
    set-member bag-member set-element-comparator bag-element-comparator
    ;; Updaters
    set-adjoin set-adjoin! set-replace set-replace!
    set-delete set-delete! set-delete-all set-delete-all!
    set-search!
    bag-adjoin bag-adjoin! bag-replace bag-replace!
    bag-delete bag-delete! bag-delete-all bag-delete-all!
    bag-search!
    ;; Whole set/bag
    set-size bag-size set-find bag-find
    set-count bag-count set-any? bag-any? set-every? bag-every?
    ;; Mapping and folding
    set-map set-for-each set-fold
    set-filter set-filter! set-remove set-remove!
    set-partition set-partition!
    bag-map bag-for-each bag-fold
    bag-filter bag-filter! bag-remove bag-remove!
    bag-partition bag-partition!
    ;; Copying and conversion
    set-copy bag-copy set->list bag->list
    list->set list->set! list->bag list->bag!
    ;; Subsets
    set=? set<? set>? set<=? set>=?
    bag=? bag<? bag>? bag<=? bag>=?
    ;; Set theory
    set-union set-intersection set-difference set-xor
    set-union! set-intersection! set-difference! set-xor!
    bag-union bag-intersection bag-difference bag-xor
    bag-union! bag-intersection! bag-difference! bag-xor!
    ;; Bag-specific
    bag-sum bag-sum! bag-product bag-product!
    bag-unique-size bag-element-count
    bag-for-each-unique bag-fold-unique
    bag-increment! bag-decrement!
    bag->set set->bag set->bag!
    bag->alist alist->bag
    ;; Comparators
    set-comparator bag-comparator)
  (begin

    ;;; Record types

    (define-record-type <set>
      (%make-set comparator hash-table)
      set?
      (comparator %set-comparator)
      (hash-table %set-ht))

    (define-record-type <bag>
      (%make-bag comparator hash-table)
      bag?
      (comparator %bag-comparator)
      (hash-table %bag-ht))

    ;;; Internal helpers

    (define (%make-empty-set comparator)
      (%make-set comparator (make-hash-table)))

    (define (%make-empty-bag comparator)
      (%make-bag comparator (make-hash-table)))

    ;;; Constructors

    (define (set comparator . elts)
      (let ((s (%make-empty-set comparator)))
        (for-each (lambda (e) (hash-table-set! (%set-ht s) e e)) elts)
        s))

    (define (bag comparator . elts)
      (let ((b (%make-empty-bag comparator)))
        (for-each
          (lambda (e)
            (hash-table-set! (%bag-ht b) e
              (+ 1 (hash-table-ref (%bag-ht b) e 0))))
          elts)
        b))

    (define (set-unfold comparator stop? mapper successor seed)
      (let ((s (%make-empty-set comparator)))
        (let loop ((seed seed))
          (if (stop? seed) s
              (let ((elem (mapper seed)))
                (hash-table-set! (%set-ht s) elem elem)
                (loop (successor seed)))))))

    (define (bag-unfold comparator stop? mapper successor seed)
      (let ((b (%make-empty-bag comparator)))
        (let loop ((seed seed))
          (if (stop? seed) b
              (let ((elem (mapper seed)))
                (hash-table-set! (%bag-ht b) elem
                  (+ 1 (hash-table-ref (%bag-ht b) elem 0)))
                (loop (successor seed)))))))

    ;;; Predicates

    (define (set-contains? s elem)
      (hash-table-exists? (%set-ht s) elem))

    (define (bag-contains? b elem)
      (hash-table-exists? (%bag-ht b) elem))

    (define (set-empty? s)
      (= 0 (hash-table-size (%set-ht s))))

    (define (bag-empty? b)
      (= 0 (hash-table-size (%bag-ht b))))

    (define (set-disjoint? s1 s2)
      (let ((found #f))
        (hash-table-walk (%set-ht s1)
          (lambda (k v)
            (if (hash-table-exists? (%set-ht s2) k)
                (set! found #t))))
        (not found)))

    (define (bag-disjoint? b1 b2)
      (let ((found #f))
        (hash-table-walk (%bag-ht b1)
          (lambda (k v)
            (if (hash-table-exists? (%bag-ht b2) k)
                (set! found #t))))
        (not found)))

    ;;; Accessors

    (define (set-member s elem default)
      (if (hash-table-exists? (%set-ht s) elem)
          (hash-table-ref (%set-ht s) elem)
          default))

    (define (bag-member b elem default)
      (if (hash-table-exists? (%bag-ht b) elem)
          elem
          default))

    (define (set-element-comparator s) (%set-comparator s))
    (define (bag-element-comparator b) (%bag-comparator b))

    ;;; Size

    (define (set-size s)
      (hash-table-size (%set-ht s)))

    (define (bag-size b)
      (let ((total 0))
        (hash-table-walk (%bag-ht b)
          (lambda (k count) (set! total (+ total count))))
        total))

    ;;; Copy

    (define (set-copy s)
      (%make-set (%set-comparator s) (hash-table-copy (%set-ht s))))

    (define (bag-copy b)
      (%make-bag (%bag-comparator b) (hash-table-copy (%bag-ht b))))

    ;;; Conversion

    (define (set->list s)
      (hash-table-keys (%set-ht s)))

    (define (bag->list b)
      (let ((result '()))
        (hash-table-walk (%bag-ht b)
          (lambda (elem count)
            (do ((i 0 (+ i 1))) ((= i count))
              (set! result (cons elem result)))))
        result))

    (define (list->set comparator lst)
      (let ((s (%make-empty-set comparator)))
        (for-each (lambda (e) (hash-table-set! (%set-ht s) e e)) lst)
        s))

    (define (list->bag comparator lst)
      (let ((b (%make-empty-bag comparator)))
        (for-each
          (lambda (e)
            (hash-table-set! (%bag-ht b) e
              (+ 1 (hash-table-ref (%bag-ht b) e 0))))
          lst)
        b))

    (define (list->set! s lst)
      (for-each (lambda (e) (hash-table-set! (%set-ht s) e e)) lst)
      s)

    (define (list->bag! b lst)
      (for-each
        (lambda (e)
          (hash-table-set! (%bag-ht b) e
            (+ 1 (hash-table-ref (%bag-ht b) e 0))))
        lst)
      b)

    ;;; Updaters (mutating core)

    (define (set-adjoin! s . elts)
      (for-each (lambda (e) (hash-table-set! (%set-ht s) e e)) elts)
      s)

    (define (bag-adjoin! b . elts)
      (for-each
        (lambda (e)
          (hash-table-set! (%bag-ht b) e
            (+ 1 (hash-table-ref (%bag-ht b) e 0))))
        elts)
      b)

    (define (set-replace! s elem)
      (if (hash-table-exists? (%set-ht s) elem)
          (begin (hash-table-set! (%set-ht s) elem elem) s)
          s))

    (define (bag-replace! b elem)
      (if (hash-table-exists? (%bag-ht b) elem)
          (let ((count (hash-table-ref (%bag-ht b) elem)))
            (hash-table-delete! (%bag-ht b) elem)
            (hash-table-set! (%bag-ht b) elem count)
            b)
          b))

    (define (set-delete! s . elts)
      (for-each (lambda (e) (hash-table-delete! (%set-ht s) e)) elts)
      s)

    (define (bag-delete! b . elts)
      (for-each
        (lambda (e)
          (if (hash-table-exists? (%bag-ht b) e)
              (let ((count (hash-table-ref (%bag-ht b) e)))
                (if (<= count 1)
                    (hash-table-delete! (%bag-ht b) e)
                    (hash-table-set! (%bag-ht b) e (- count 1))))))
        elts)
      b)

    (define (set-delete-all! s lst)
      (for-each (lambda (e) (hash-table-delete! (%set-ht s) e)) lst)
      s)

    (define (bag-delete-all! b lst)
      (for-each
        (lambda (e)
          (if (hash-table-exists? (%bag-ht b) e)
              (let ((count (hash-table-ref (%bag-ht b) e)))
                (if (<= count 1)
                    (hash-table-delete! (%bag-ht b) e)
                    (hash-table-set! (%bag-ht b) e (- count 1))))))
        lst)
      b)

    ;;; Updaters (non-mutating wrappers)

    (define (set-adjoin s . elts)
      (apply set-adjoin! (set-copy s) elts))

    (define (bag-adjoin b . elts)
      (apply bag-adjoin! (bag-copy b) elts))

    (define (set-replace s elem)
      (set-replace! (set-copy s) elem))

    (define (bag-replace b elem)
      (bag-replace! (bag-copy b) elem))

    (define (set-delete s . elts)
      (apply set-delete! (set-copy s) elts))

    (define (bag-delete b . elts)
      (apply bag-delete! (bag-copy b) elts))

    (define (set-delete-all s lst)
      (set-delete-all! (set-copy s) lst))

    (define (bag-delete-all b lst)
      (bag-delete-all! (bag-copy b) lst))

    ;;; search!

    (define (set-search! s elem failure success)
      (if (hash-table-exists? (%set-ht s) elem)
          (let ((stored (hash-table-ref (%set-ht s) elem)))
            (success stored
              (lambda (new-elem obj)
                (hash-table-delete! (%set-ht s) elem)
                (hash-table-set! (%set-ht s) new-elem new-elem)
                (values s obj))
              (lambda (obj)
                (hash-table-delete! (%set-ht s) elem)
                (values s obj))))
          (failure
            (lambda (obj)
              (hash-table-set! (%set-ht s) elem elem)
              (values s obj))
            (lambda (obj)
              (values s obj)))))

    (define (bag-search! b elem failure success)
      (if (hash-table-exists? (%bag-ht b) elem)
          (let ((count (hash-table-ref (%bag-ht b) elem)))
            (success elem
              (lambda (new-elem obj)
                (hash-table-delete! (%bag-ht b) elem)
                (hash-table-set! (%bag-ht b) new-elem count)
                (values b obj))
              (lambda (obj)
                (hash-table-delete! (%bag-ht b) elem)
                (values b obj))))
          (failure
            (lambda (obj)
              (hash-table-set! (%bag-ht b) elem 1)
              (values b obj))
            (lambda (obj)
              (values b obj)))))

    ;;; Whole set/bag operations

    (define (set-find pred s failure)
      (let ((keys (hash-table-keys (%set-ht s))))
        (let loop ((ks keys))
          (cond
            ((null? ks) (failure))
            ((pred (car ks)) (car ks))
            (else (loop (cdr ks)))))))

    (define (bag-find pred b failure)
      (let ((keys (hash-table-keys (%bag-ht b))))
        (let loop ((ks keys))
          (cond
            ((null? ks) (failure))
            ((pred (car ks)) (car ks))
            (else (loop (cdr ks)))))))

    (define (set-count pred s)
      (let ((c 0))
        (hash-table-walk (%set-ht s)
          (lambda (k v) (if (pred k) (set! c (+ c 1)))))
        c))

    (define (bag-count pred b)
      (let ((c 0))
        (hash-table-walk (%bag-ht b)
          (lambda (k count)
            (if (pred k) (set! c (+ c count)))))
        c))

    (define (set-any? pred s)
      (let ((found #f))
        (hash-table-walk (%set-ht s)
          (lambda (k v)
            (if (pred k) (set! found #t))))
        found))

    (define (bag-any? pred b)
      (let ((found #f))
        (hash-table-walk (%bag-ht b)
          (lambda (k v)
            (if (pred k) (set! found #t))))
        found))

    (define (set-every? pred s)
      (let ((all #t))
        (hash-table-walk (%set-ht s)
          (lambda (k v)
            (if (not (pred k)) (set! all #f))))
        all))

    (define (bag-every? pred b)
      (let ((all #t))
        (hash-table-walk (%bag-ht b)
          (lambda (k v)
            (if (not (pred k)) (set! all #f))))
        all))

    ;;; Mapping and folding

    (define (set-map comparator proc s)
      (set-fold (lambda (elem result) (set-adjoin! result (proc elem)))
                (%make-empty-set comparator) s))

    (define (set-for-each proc s)
      (hash-table-walk (%set-ht s) (lambda (k v) (proc k))))

    (define (set-fold proc nil s)
      (let ((acc nil))
        (hash-table-walk (%set-ht s)
          (lambda (k v) (set! acc (proc k acc))))
        acc))

    (define (bag-map comparator proc b)
      (let ((result (%make-empty-bag comparator)))
        (hash-table-walk (%bag-ht b)
          (lambda (elem count)
            (let ((new-elem (proc elem)))
              (hash-table-set! (%bag-ht result) new-elem
                (+ count (hash-table-ref (%bag-ht result) new-elem 0))))))
        result))

    (define (bag-for-each proc b)
      (hash-table-walk (%bag-ht b)
        (lambda (elem count)
          (do ((i 0 (+ i 1))) ((= i count))
            (proc elem)))))

    (define (bag-fold proc nil b)
      (let ((acc nil))
        (hash-table-walk (%bag-ht b)
          (lambda (elem count)
            (do ((i 0 (+ i 1))) ((= i count))
              (set! acc (proc elem acc)))))
        acc))

    ;;; Filter, remove, partition

    (define (set-filter! pred s)
      (for-each
        (lambda (k) (if (not (pred k)) (hash-table-delete! (%set-ht s) k)))
        (hash-table-keys (%set-ht s)))
      s)

    (define (set-remove! pred s)
      (for-each
        (lambda (k) (if (pred k) (hash-table-delete! (%set-ht s) k)))
        (hash-table-keys (%set-ht s)))
      s)

    (define (set-partition! pred s)
      (let ((no (%make-empty-set (%set-comparator s))))
        (for-each
          (lambda (k)
            (if (not (pred k))
                (begin
                  (hash-table-set! (%set-ht no) k k)
                  (hash-table-delete! (%set-ht s) k))))
          (hash-table-keys (%set-ht s)))
        (values s no)))

    (define (bag-filter! pred b)
      (for-each
        (lambda (k) (if (not (pred k)) (hash-table-delete! (%bag-ht b) k)))
        (hash-table-keys (%bag-ht b)))
      b)

    (define (bag-remove! pred b)
      (for-each
        (lambda (k) (if (pred k) (hash-table-delete! (%bag-ht b) k)))
        (hash-table-keys (%bag-ht b)))
      b)

    (define (bag-partition! pred b)
      (let ((yes (%make-empty-bag (%bag-comparator b))))
        (for-each
          (lambda (k)
            (if (pred k)
                (begin
                  (hash-table-set! (%bag-ht yes) k (hash-table-ref (%bag-ht b) k))
                  (hash-table-delete! (%bag-ht b) k))))
          (hash-table-keys (%bag-ht b)))
        (values yes b)))

    (define (set-filter pred s)
      (set-filter! pred (set-copy s)))

    (define (set-remove pred s)
      (set-remove! pred (set-copy s)))

    (define (set-partition pred s)
      (let ((copy (set-copy s)))
        (set-partition! pred copy)))

    (define (bag-filter pred b)
      (bag-filter! pred (bag-copy b)))

    (define (bag-remove pred b)
      (bag-remove! pred (bag-copy b)))

    (define (bag-partition pred b)
      (let ((copy (bag-copy b)))
        (bag-partition! pred copy)))

    ;;; Comparison operators

    (define (%set=? s1 s2)
      (and (= (set-size s1) (set-size s2))
           (let ((all #t))
             (hash-table-walk (%set-ht s1)
               (lambda (k v)
                 (if (not (hash-table-exists? (%set-ht s2) k))
                     (set! all #f))))
             all)))

    (define (%set<=? s1 s2)
      (let ((all #t))
        (hash-table-walk (%set-ht s1)
          (lambda (k v)
            (if (not (hash-table-exists? (%set-ht s2) k))
                (set! all #f))))
        all))

    (define set=?
      (case-lambda
        ((s1 s2) (%set=? s1 s2))
        ((s1 s2 . rest) (and (%set=? s1 s2) (apply set=? s2 rest)))))

    (define set<?
      (case-lambda
        ((s1 s2) (and (%set<=? s1 s2) (not (%set=? s1 s2))))
        ((s1 s2 . rest) (and (set<? s1 s2) (apply set<? s2 rest)))))

    (define set>?
      (case-lambda
        ((s1 s2) (set<? s2 s1))
        ((s1 s2 . rest) (and (set>? s1 s2) (apply set>? s2 rest)))))

    (define set<=?
      (case-lambda
        ((s1 s2) (%set<=? s1 s2))
        ((s1 s2 . rest) (and (%set<=? s1 s2) (apply set<=? s2 rest)))))

    (define set>=?
      (case-lambda
        ((s1 s2) (%set<=? s2 s1))
        ((s1 s2 . rest) (and (set>=? s1 s2) (apply set>=? s2 rest)))))

    (define (%bag=? b1 b2)
      (and (= (hash-table-size (%bag-ht b1))
              (hash-table-size (%bag-ht b2)))
           (let ((all #t))
             (hash-table-walk (%bag-ht b1)
               (lambda (k count1)
                 (if (not (and (hash-table-exists? (%bag-ht b2) k)
                               (= count1 (hash-table-ref (%bag-ht b2) k))))
                     (set! all #f))))
             all)))

    (define (%bag<=? b1 b2)
      (let ((all #t))
        (hash-table-walk (%bag-ht b1)
          (lambda (k count1)
            (if (not (and (hash-table-exists? (%bag-ht b2) k)
                          (<= count1 (hash-table-ref (%bag-ht b2) k))))
                (set! all #f))))
        all))

    (define bag=?
      (case-lambda
        ((b1 b2) (%bag=? b1 b2))
        ((b1 b2 . rest) (and (%bag=? b1 b2) (apply bag=? b2 rest)))))

    (define bag<?
      (case-lambda
        ((b1 b2) (and (%bag<=? b1 b2) (not (%bag=? b1 b2))))
        ((b1 b2 . rest) (and (bag<? b1 b2) (apply bag<? b2 rest)))))

    (define bag>?
      (case-lambda
        ((b1 b2) (bag<? b2 b1))
        ((b1 b2 . rest) (and (bag>? b1 b2) (apply bag>? b2 rest)))))

    (define bag<=?
      (case-lambda
        ((b1 b2) (%bag<=? b1 b2))
        ((b1 b2 . rest) (and (%bag<=? b1 b2) (apply bag<=? b2 rest)))))

    (define bag>=?
      (case-lambda
        ((b1 b2) (%bag<=? b2 b1))
        ((b1 b2 . rest) (and (bag>=? b1 b2) (apply bag>=? b2 rest)))))

    ;;; Set theory operations (mutating core)

    (define (set-union! s1 . rest)
      (for-each
        (lambda (s2)
          (hash-table-walk (%set-ht s2)
            (lambda (k v)
              (if (not (hash-table-exists? (%set-ht s1) k))
                  (hash-table-set! (%set-ht s1) k k)))))
        rest)
      s1)

    (define (set-intersection! s1 . rest)
      (for-each
        (lambda (s2)
          (for-each
            (lambda (k)
              (if (not (hash-table-exists? (%set-ht s2) k))
                  (hash-table-delete! (%set-ht s1) k)))
            (hash-table-keys (%set-ht s1))))
        rest)
      s1)

    (define (set-difference! s1 . rest)
      (for-each
        (lambda (s2)
          (hash-table-walk (%set-ht s2)
            (lambda (k v)
              (hash-table-delete! (%set-ht s1) k))))
        rest)
      s1)

    (define (set-xor! s1 s2)
      (let ((to-add '()) (to-del '()))
        (hash-table-walk (%set-ht s2)
          (lambda (k v)
            (if (hash-table-exists? (%set-ht s1) k)
                (set! to-del (cons k to-del))
                (set! to-add (cons k to-add)))))
        (for-each (lambda (k) (hash-table-delete! (%set-ht s1) k)) to-del)
        (for-each (lambda (k) (hash-table-set! (%set-ht s1) k k)) to-add))
      s1)

    ;;; Set theory (non-mutating)

    (define (set-union s1 . rest)
      (apply set-union! (set-copy s1) rest))

    (define (set-intersection s1 . rest)
      (apply set-intersection! (set-copy s1) rest))

    (define (set-difference s1 . rest)
      (apply set-difference! (set-copy s1) rest))

    (define (set-xor s1 s2)
      (set-xor! (set-copy s1) s2))

    ;;; Bag set theory (mutating core)

    (define (bag-union! b1 . rest)
      (for-each
        (lambda (b2)
          (hash-table-walk (%bag-ht b2)
            (lambda (k count2)
              (let ((count1 (hash-table-ref (%bag-ht b1) k 0)))
                (hash-table-set! (%bag-ht b1) k (max count1 count2))))))
        rest)
      b1)

    (define (bag-intersection! b1 . rest)
      (for-each
        (lambda (b2)
          (for-each
            (lambda (k)
              (if (hash-table-exists? (%bag-ht b2) k)
                  (let ((count1 (hash-table-ref (%bag-ht b1) k))
                        (count2 (hash-table-ref (%bag-ht b2) k)))
                    (hash-table-set! (%bag-ht b1) k (min count1 count2)))
                  (hash-table-delete! (%bag-ht b1) k)))
            (hash-table-keys (%bag-ht b1))))
        rest)
      b1)

    (define (bag-difference! b1 . rest)
      (for-each
        (lambda (b2)
          (for-each
            (lambda (k)
              (if (hash-table-exists? (%bag-ht b1) k)
                  (let ((count1 (hash-table-ref (%bag-ht b1) k))
                        (count2 (hash-table-ref (%bag-ht b2) k)))
                    (if (<= count1 count2)
                        (hash-table-delete! (%bag-ht b1) k)
                        (hash-table-set! (%bag-ht b1) k (- count1 count2))))))
            (hash-table-keys (%bag-ht b2))))
        rest)
      b1)

    (define (bag-xor! b1 b2)
      (let ((keys2 (hash-table-keys (%bag-ht b2))))
        (for-each
          (lambda (k)
            (let ((c1 (hash-table-ref (%bag-ht b1) k 0))
                  (c2 (hash-table-ref (%bag-ht b2) k)))
              (let ((diff (abs (- c1 c2))))
                (if (= diff 0)
                    (hash-table-delete! (%bag-ht b1) k)
                    (hash-table-set! (%bag-ht b1) k diff)))))
          keys2)
        (for-each
          (lambda (k)
            (if (not (hash-table-exists? (%bag-ht b2) k))
                #f))
          (hash-table-keys (%bag-ht b1))))
      b1)

    ;;; Bag set theory (non-mutating)

    (define (bag-union b1 . rest)
      (apply bag-union! (bag-copy b1) rest))

    (define (bag-intersection b1 . rest)
      (apply bag-intersection! (bag-copy b1) rest))

    (define (bag-difference b1 . rest)
      (apply bag-difference! (bag-copy b1) rest))

    (define (bag-xor b1 b2)
      (bag-xor! (bag-copy b1) b2))

    ;;; Bag-specific: sum and product

    (define (bag-sum! b1 . rest)
      (for-each
        (lambda (b2)
          (hash-table-walk (%bag-ht b2)
            (lambda (k count2)
              (hash-table-set! (%bag-ht b1) k
                (+ count2 (hash-table-ref (%bag-ht b1) k 0))))))
        rest)
      b1)

    (define (bag-sum b1 . rest)
      (apply bag-sum! (bag-copy b1) rest))

    (define (bag-product! n b)
      (for-each
        (lambda (k)
          (if (= n 0)
              (hash-table-delete! (%bag-ht b) k)
              (hash-table-set! (%bag-ht b) k
                (* n (hash-table-ref (%bag-ht b) k)))))
        (hash-table-keys (%bag-ht b)))
      b)

    (define (bag-product n b)
      (bag-product! n (bag-copy b)))

    ;;; Bag-specific: counts and unique iteration

    (define (bag-unique-size b)
      (hash-table-size (%bag-ht b)))

    (define (bag-element-count b elem)
      (hash-table-ref (%bag-ht b) elem 0))

    (define (bag-for-each-unique proc b)
      (hash-table-walk (%bag-ht b)
        (lambda (elem count) (proc elem count))))

    (define (bag-fold-unique proc nil b)
      (let ((acc nil))
        (hash-table-walk (%bag-ht b)
          (lambda (elem count) (set! acc (proc elem count acc))))
        acc))

    (define (bag-increment! b elem count)
      (hash-table-set! (%bag-ht b) elem
        (+ count (hash-table-ref (%bag-ht b) elem 0)))
      b)

    (define (bag-decrement! b elem count)
      (let ((old (hash-table-ref (%bag-ht b) elem 0)))
        (if (<= old count)
            (hash-table-delete! (%bag-ht b) elem)
            (hash-table-set! (%bag-ht b) elem (- old count))))
      b)

    ;;; Bag/set conversions

    (define (bag->set b)
      (let ((s (%make-empty-set (%bag-comparator b))))
        (hash-table-walk (%bag-ht b)
          (lambda (k v) (hash-table-set! (%set-ht s) k k)))
        s))

    (define (set->bag s)
      (let ((b (%make-empty-bag (%set-comparator s))))
        (hash-table-walk (%set-ht s)
          (lambda (k v) (hash-table-set! (%bag-ht b) k 1)))
        b))

    (define (set->bag! b s)
      (hash-table-walk (%set-ht s)
        (lambda (k v)
          (if (not (hash-table-exists? (%bag-ht b) k))
              (hash-table-set! (%bag-ht b) k 1))))
      b)

    (define (bag->alist b)
      (let ((result '()))
        (hash-table-walk (%bag-ht b)
          (lambda (elem count)
            (set! result (cons (cons elem count) result))))
        result))

    (define (alist->bag comparator alist)
      (let ((b (%make-empty-bag comparator)))
        (for-each
          (lambda (pair)
            (hash-table-set! (%bag-ht b) (car pair) (cdr pair)))
          alist)
        b))

    ;;; Comparators for sets and bags

    (define (%set-hash s)
      (let ((h 0))
        (hash-table-walk (%set-ht s)
          (lambda (k v) (set! h (+ h (default-hash k)))))
        (modulo h (hash-bound))))

    (define (%bag-hash b)
      (let ((h 0))
        (hash-table-walk (%bag-ht b)
          (lambda (k count)
            (set! h (+ h (* count (default-hash k))))))
        (modulo h (hash-bound))))

    (define set-comparator
      (make-comparator set? %set=? #f %set-hash))

    (define bag-comparator
      (make-comparator bag? %bag=? #f %bag-hash))

  ))
