;;; SRFI 217 — Integer Sets
;;;
;;; The spec's reference representation is a Patricia trie giving O(min(n,W))
;;; operations. This implementation instead stores a sorted (ascending),
;;; duplicate-free list of exact integers wrapped in a record — correct and
;;; simple, but O(n) per update/membership operation rather than the spec's
;;; near-constant-time complexity. Isets are read-heavy in most uses
;;; (iset->list is already required to produce sorted output, which a sorted
;;; list gives for free), so this trades raw performance for a
;;; straightforward, obviously-correct implementation. The `!` procedures
;;; are non-mutating (same functional contract as their non-`!` siblings),
;;; consistent with the spec's own "it is an error to rely upon these
;;; procedures working by side effect."

(define-library (srfi 217)
  (import (scheme base))
  (export
    iset iset-unfold make-range-iset
    iset? iset-contains? iset-empty? iset-disjoint?
    iset-member iset-min iset-max
    iset-adjoin iset-adjoin! iset-delete iset-delete!
    iset-delete-all iset-delete-all!
    iset-delete-min iset-delete-min! iset-delete-max iset-delete-max!
    iset-search iset-search!
    iset-size iset-find iset-count iset-any? iset-every?
    iset-map iset-for-each iset-fold iset-fold-right
    iset-filter iset-filter! iset-remove iset-remove!
    iset-partition iset-partition!
    iset-copy iset->list list->iset list->iset!
    iset=? iset<? iset>? iset<=? iset>=?
    iset-union iset-union! iset-intersection iset-intersection!
    iset-difference iset-difference! iset-xor iset-xor!
    iset-open-interval iset-closed-interval
    iset-open-closed-interval iset-closed-open-interval
    isubset= isubset< isubset<= isubset> isubset>=)
  (begin

    (define-record-type <iset>
      (%make-iset elements)
      iset?
      (elements %iset-elements))

    (define (%sorted-unique lst)
      (let ((sorted (list-sort < lst)))
        (let loop ((l sorted))
          (cond ((null? l) '())
                ((null? (cdr l)) l)
                ((= (car l) (cadr l)) (loop (cdr l)))
                (else (cons (car l) (loop (cdr l))))))))

    ;; No (scheme sort) dependency: a simple, correct merge sort.
    (define (list-sort < lst)
      (define (merge a b)
        (cond ((null? a) b) ((null? b) a)
              ((< (car b) (car a)) (cons (car b) (merge a (cdr b))))
              (else (cons (car a) (merge (cdr a) b)))))
      (define (split lst)
        (if (or (null? lst) (null? (cdr lst)))
            (values lst '())
            (let-values (((a b) (split (cddr lst))))
              (values (cons (car lst) a) (cons (cadr lst) b)))))
      (if (or (null? lst) (null? (cdr lst)))
          lst
          (let-values (((a b) (split lst)))
            (merge (list-sort < a) (list-sort < b)))))

    (define (iset . elements) (%make-iset (%sorted-unique elements)))

    (define (iset-unfold stop? mapper successor seed)
      (let loop ((seed seed) (acc '()))
        (if (stop? seed)
            (%make-iset (%sorted-unique acc))
            (loop (successor seed) (cons (mapper seed) acc)))))

    (define (make-range-iset start end . maybe-step)
      (let ((step (if (pair? maybe-step) (car maybe-step) 1)))
        (when (= step 0) (error "make-range-iset: step must not be zero" step))
        (%make-iset
          (if (> step 0)
              (let loop ((i start)) (if (>= i end) '() (cons i (loop (+ i step)))))
              (let loop ((i start)) (if (<= i end) '() (cons i (loop (+ i step)))))))))

    (define (iset-contains? s element) (and (member element (%iset-elements s)) #t))
    (define (iset-empty? s) (null? (%iset-elements s)))
    (define (iset-disjoint? s1 s2)
      (not (any (lambda (x) (iset-contains? s2 x)) (%iset-elements s1))))
    (define (any pred lst) (and (pair? lst) (or (pred (car lst)) (any pred (cdr lst)))))

    (define (iset-member s element default)
      (if (iset-contains? s element) element default))

    (define (iset-min s) (if (null? (%iset-elements s)) #f (car (%iset-elements s))))
    (define (iset-max s)
      (if (null? (%iset-elements s)) #f (list-ref (%iset-elements s) (- (length (%iset-elements s)) 1))))

    (define (iset-adjoin s . elements) (%make-iset (%sorted-unique (append elements (%iset-elements s)))))
    (define (iset-adjoin! s . elements) (apply iset-adjoin s elements))

    (define (iset-delete s . elements)
      (%make-iset (filter (lambda (x) (not (member x elements))) (%iset-elements s))))
    (define (iset-delete! s . elements) (apply iset-delete s elements))
    (define (iset-delete-all s lst) (apply iset-delete s lst))
    (define (iset-delete-all! s lst) (apply iset-delete s lst))
    (define (filter pred lst) (cond ((null? lst) '()) ((pred (car lst)) (cons (car lst) (filter pred (cdr lst)))) (else (filter pred (cdr lst)))))

    (define (iset-delete-min s)
      (let ((els (%iset-elements s)))
        (values (car els) (%make-iset (cdr els)))))
    (define (iset-delete-min! s) (iset-delete-min s))
    (define (iset-delete-max s)
      (let* ((els (%iset-elements s)) (n (length els)))
        (values (list-ref els (- n 1)) (%make-iset (%take els (- n 1))))))
    (define (iset-delete-max! s) (iset-delete-max s))
    (define (%take lst n) (if (= n 0) '() (cons (car lst) (%take (cdr lst) (- n 1)))))

    (define (iset-search s element failure success)
      (if (iset-contains? s element)
          (call-with-values
            (lambda ()
              (success element
                       (lambda (new-element obj) (values (iset-adjoin (iset-delete s element) new-element) obj))
                       (lambda (obj) (values (iset-delete s element) obj))))
            values)
          (call-with-values
            (lambda ()
              (failure (lambda (obj) (values (iset-adjoin s element) obj))
                       (lambda (obj) (values s obj))))
            values)))
    (define (iset-search! s element failure success) (iset-search s element failure success))

    (define (iset-size s) (length (%iset-elements s)))

    (define (iset-find pred s failure)
      (let loop ((l (%iset-elements s)))
        (cond ((null? l) (failure)) ((pred (car l)) (car l)) (else (loop (cdr l))))))

    (define (iset-count pred s) (length (filter pred (%iset-elements s))))
    (define (iset-any? pred s) (any pred (%iset-elements s)))
    (define (iset-every? pred s)
      (let loop ((l (%iset-elements s))) (or (null? l) (and (pred (car l)) (loop (cdr l))))))

    (define (iset-map proc s) (%make-iset (%sorted-unique (map proc (%iset-elements s)))))
    (define (iset-for-each proc s) (for-each proc (%iset-elements s)))
    (define (iset-fold proc nil s) (fold-left-i proc nil (%iset-elements s)))
    (define (fold-left-i proc acc lst) (if (null? lst) acc (fold-left-i proc (proc (car lst) acc) (cdr lst))))
    (define (iset-fold-right proc nil s)
      (let loop ((l (%iset-elements s))) (if (null? l) nil (proc (car l) (loop (cdr l))))))

    (define (iset-filter pred s) (%make-iset (filter pred (%iset-elements s))))
    (define (iset-filter! pred s) (iset-filter pred s))
    (define (iset-remove pred s) (%make-iset (filter (lambda (x) (not (pred x))) (%iset-elements s))))
    (define (iset-remove! pred s) (iset-remove pred s))
    (define (iset-partition pred s)
      (values (iset-filter pred s) (iset-remove pred s)))
    (define (iset-partition! pred s) (iset-partition pred s))

    (define (iset-copy s) (%make-iset (%iset-elements s)))
    (define (iset->list s) (%iset-elements s))
    (define (list->iset lst) (%make-iset (%sorted-unique lst)))
    (define (list->iset! s lst) (%make-iset (%sorted-unique (append lst (%iset-elements s)))))

    (define (%subset? s1 s2) (every (lambda (x) (iset-contains? s2 x)) (%iset-elements s1)))
    (define (every pred lst) (or (null? lst) (and (pred (car lst)) (every pred (cdr lst)))))

    (define (%pairwise pred lst) (or (null? lst) (null? (cdr lst)) (and (pred (car lst) (cadr lst)) (%pairwise pred (cdr lst)))))

    (define (iset=? . sets) (%pairwise (lambda (a b) (and (%subset? a b) (%subset? b a))) sets))
    (define (iset<=? . sets) (%pairwise %subset? sets))
    (define (iset>=? . sets) (%pairwise (lambda (a b) (%subset? b a)) sets))
    (define (iset<? . sets) (%pairwise (lambda (a b) (and (%subset? a b) (< (iset-size a) (iset-size b)))) sets))
    (define (iset>? . sets) (%pairwise (lambda (a b) (and (%subset? b a) (> (iset-size a) (iset-size b)))) sets))

    (define (iset-union . sets)
      (if (null? sets)
          (iset)
          (%make-iset (%sorted-unique (apply append (map %iset-elements sets))))))
    (define (iset-union! . sets) (apply iset-union sets))

    (define (iset-intersection s1 . sets)
      (%make-iset (filter (lambda (x) (every (lambda (s) (iset-contains? s x)) sets)) (%iset-elements s1))))
    (define (iset-intersection! s1 . sets) (apply iset-intersection s1 sets))

    (define (iset-difference s1 . sets)
      (let ((rest (apply iset-union sets)))
        (%make-iset (filter (lambda (x) (not (iset-contains? rest x))) (%iset-elements s1)))))
    (define (iset-difference! s1 . sets) (apply iset-difference s1 sets))

    (define (iset-xor s1 s2)
      (%make-iset
        (%sorted-unique
          (append (filter (lambda (x) (not (iset-contains? s2 x))) (%iset-elements s1))
                  (filter (lambda (x) (not (iset-contains? s1 x))) (%iset-elements s2))))))
    (define (iset-xor! s1 s2) (iset-xor s1 s2))

    (define (iset-open-interval s low high) (iset-filter (lambda (x) (and (> x low) (< x high))) s))
    (define (iset-closed-interval s low high) (iset-filter (lambda (x) (and (>= x low) (<= x high))) s))
    (define (iset-open-closed-interval s low high) (iset-filter (lambda (x) (and (> x low) (<= x high))) s))
    (define (iset-closed-open-interval s low high) (iset-filter (lambda (x) (and (>= x low) (< x high))) s))

    (define (isubset= s k) (iset-filter (lambda (x) (= x k)) s))
    (define (isubset< s k) (iset-filter (lambda (x) (< x k)) s))
    (define (isubset<= s k) (iset-filter (lambda (x) (<= x k)) s))
    (define (isubset> s k) (iset-filter (lambda (x) (> x k)) s))
    (define (isubset>= s k) (iset-filter (lambda (x) (>= x k)) s))))
