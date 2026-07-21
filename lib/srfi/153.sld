;;; SRFI 153 — Ordered Sets
;;;
;;; Implemented as a record wrapping the comparator plus a sorted,
;;; duplicate-free list of elements (ordered by the comparator's ordering
;;; predicate) — O(n) per operation rather than a balanced-tree's O(log n),
;;; traded here for a straightforward, obviously-correct implementation.
;;; Since oset->list is already required to return elements in order, a
;;; sorted list costs nothing extra for the read side.
;;;
;;; A comparator with no ordering predicate (SRFI 128's eq-comparator, for
;;; instance) can't be sorted against — but "sortedness" is vacuous for such
;;; a comparator anyway, so osets built on one just keep insertion order
;;; (deduplicated). The spec's own oset-map example relies on constructing
;;; exactly such an oset, so this isn't an optional nicety.

(define-library (srfi 153)
  (import (scheme base) (scheme case-lambda) (srfi 128))
  (export
    oset oset/ordered oset-unfold oset-unfold/ordered oset-accumulate
    oset? oset-contains? oset-empty? oset-disjoint?
    oset-member oset-element-comparator
    oset-adjoin oset-adjoin/replace oset-delete oset-delete-all
    oset-pop oset-pop/reverse
    oset-size oset-find oset-count oset-any? oset-every?
    oset-map oset-map/monotone oset-for-each oset-fold oset-fold/reverse
    oset-filter oset-remove oset-partition
    oset->list list->oset list->oset/ordered
    oset=? oset<? oset>? oset<=? oset>=?
    oset-union oset-intersection oset-difference oset-xor
    oset-min-element oset-max-element
    oset-element-predecessor oset-element-successor
    oset-range= oset-range< oset-range> oset-range<= oset-range>=
    oset-split oset-catenate)
  (begin

    (define-record-type <oset>
      (%make-oset comparator elements)
      oset?
      (comparator oset-element-comparator)
      (elements %oset-elements))

    (define (%lt comp) (comparator-ordering-predicate comp))
    (define (%eq comp) (comparator-equality-predicate comp))

    ;; A comparator without an ordering predicate (e.g. SRFI 128's
    ;; eq-comparator) can't sort, but osets over it are still meaningful —
    ;; "sortedness" is vacuous, so any consistent order (here: insertion
    ;; order, deduplicated) is as valid as any other. The spec's own
    ;; oset-map example constructs exactly such an oset over eq-comparator.
    (define (%sort-for comp lst)
      (if (comparator-ordered? comp) (%sort< (%lt comp) lst) lst))

    (define (%sort< lt lst)
      (define (merge a b)
        (cond ((null? a) b) ((null? b) a)
              ((lt (car b) (car a)) (cons (car b) (merge a (cdr b))))
              (else (cons (car a) (merge (cdr a) b)))))
      (define (split lst)
        (if (or (null? lst) (null? (cdr lst)))
            (values lst '())
            (let-values (((a b) (split (cddr lst))))
              (values (cons (car lst) a) (cons (cadr lst) b)))))
      (if (or (null? lst) (null? (cdr lst)))
          lst
          (let-values (((a b) (split lst)))
            (merge (%sort< lt a) (%sort< lt b)))))

    ;; keep = keep the earlier element on a tie (#t) or the later one (#f)
    (define (%dedup eq lst keep-first?)
      (cond ((or (null? lst) (null? (cdr lst))) lst)
            ((eq (car lst) (cadr lst))
             (%dedup eq (if keep-first? (cons (car lst) (cddr lst)) (cdr lst)) keep-first?))
            (else (cons (car lst) (%dedup eq (cdr lst) keep-first?)))))

    (define (%build comp lst keep-first?)
      (%make-oset comp (%dedup (%eq comp) (%sort-for comp lst) keep-first?)))

    (define (oset comp . elements) (%build comp elements #t))
    (define (oset/ordered comp . elements) (%make-oset comp (%dedup (%eq comp) elements #t)))

    (define (oset-unfold stop? mapper successor seed comp)
      (let loop ((seed seed) (acc '()))
        (if (stop? seed) (%build comp acc #t) (loop (successor seed) (cons (mapper seed) acc)))))

    (define (oset-unfold/ordered stop? mapper successor seed comp)
      (let loop ((seed seed) (acc '()))
        (if (stop? seed)
            (%make-oset comp (%dedup (%eq comp) (reverse acc) #t))
            (loop (successor seed) (cons (mapper seed) acc)))))

    (define (oset-accumulate proc comp . seeds)
      (call-with-current-continuation
        (lambda (terminate)
          (let loop ((seeds seeds) (acc '()))
            (call-with-values
              (lambda () (apply proc (lambda (x) (terminate (%build comp acc #t) x)) seeds))
              (lambda (elt . new-seeds) (loop new-seeds (cons elt acc))))))))

    (define (oset-contains? s element) (and (member element (%oset-elements s) (%eq (oset-element-comparator s))) #t))
    (define (oset-empty? s) (null? (%oset-elements s)))
    (define (oset-disjoint? s1 s2) (not (any (lambda (x) (oset-contains? s2 x)) (%oset-elements s1))))
    (define (any pred lst) (and (pair? lst) (or (pred (car lst)) (any pred (cdr lst)))))

    (define (oset-member s element default) (if (oset-contains? s element) element default))

    (define (oset-adjoin s . elements) (%build (oset-element-comparator s) (append elements (%oset-elements s)) #f))
    (define (oset-adjoin/replace s . elements) (%build (oset-element-comparator s) (append elements (%oset-elements s)) #t))

    (define (oset-delete s . elements)
      (let ((eq (%eq (oset-element-comparator s))))
        (%make-oset (oset-element-comparator s)
                    (filter (lambda (x) (not (member x elements eq))) (%oset-elements s)))))
    (define (oset-delete-all s lst) (apply oset-delete s lst))
    (define (filter pred lst) (cond ((null? lst) '()) ((pred (car lst)) (cons (car lst) (filter pred (cdr lst)))) (else (filter pred (cdr lst)))))

    (define oset-pop
      (case-lambda
        ((s) (oset-pop s (lambda () (error "oset-pop: empty oset"))))
        ((s failure)
         (if (oset-empty? s) (failure)
             (values (%make-oset (oset-element-comparator s) (cdr (%oset-elements s))) (car (%oset-elements s)))))))

    (define oset-pop/reverse
      (case-lambda
        ((s) (oset-pop/reverse s (lambda () (error "oset-pop/reverse: empty oset"))))
        ((s failure)
         (if (oset-empty? s) (failure)
             (let* ((els (%oset-elements s)) (n (length els)))
               (values (%make-oset (oset-element-comparator s) (%take els (- n 1))) (list-ref els (- n 1))))))))
    (define (%take lst n) (if (= n 0) '() (cons (car lst) (%take (cdr lst) (- n 1)))))

    (define (oset-size s) (length (%oset-elements s)))
    (define (oset-find pred s failure)
      (let loop ((l (%oset-elements s))) (cond ((null? l) (failure)) ((pred (car l)) (car l)) (else (loop (cdr l))))))
    (define (oset-count pred s) (length (filter pred (%oset-elements s))))
    (define (oset-any? pred s) (any pred (%oset-elements s)))
    (define (oset-every? pred s) (let loop ((l (%oset-elements s))) (or (null? l) (and (pred (car l)) (loop (cdr l))))))

    (define (oset-map comp proc s) (%build comp (map proc (%oset-elements s)) #t))
    (define (oset-map/monotone comp proc s) (%make-oset comp (map proc (%oset-elements s))))
    (define (oset-for-each proc s) (for-each proc (%oset-elements s)))
    (define (oset-fold proc nil s) (fold-left-o proc nil (%oset-elements s)))
    (define (fold-left-o proc acc lst) (if (null? lst) acc (fold-left-o proc (proc (car lst) acc) (cdr lst))))
    (define (oset-fold/reverse proc nil s)
      (let loop ((l (%oset-elements s))) (if (null? l) nil (proc (car l) (loop (cdr l))))))

    (define (oset-filter pred s) (%make-oset (oset-element-comparator s) (filter pred (%oset-elements s))))
    (define (oset-remove pred s) (%make-oset (oset-element-comparator s) (filter (lambda (x) (not (pred x))) (%oset-elements s))))
    (define (oset-partition pred s) (values (oset-filter pred s) (oset-remove pred s)))

    (define (oset->list s) (%oset-elements s))
    (define (list->oset comp lst) (%build comp lst #t))
    (define (list->oset/ordered comp lst) (%make-oset comp (%dedup (%eq comp) lst #t)))

    (define (%eqv-sets? s1 s2)
      (and (eq? (oset-element-comparator s1) (oset-element-comparator s2))
           (= (oset-size s1) (oset-size s2))
           (every2 (%eq (oset-element-comparator s1)) (%oset-elements s1) (%oset-elements s2))))
    (define (every2 pred a b) (or (null? a) (and (pred (car a) (car b)) (every2 pred (cdr a) (cdr b)))))
    (define (%subset? s1 s2) (every (lambda (x) (oset-contains? s2 x)) (%oset-elements s1)))
    (define (every pred lst) (or (null? lst) (and (pred (car lst)) (every pred (cdr lst)))))
    (define (%pairwise pred lst) (or (null? lst) (null? (cdr lst)) (and (pred (car lst) (cadr lst)) (%pairwise pred (cdr lst)))))

    (define (oset=? . sets) (%pairwise (lambda (a b) (and (%subset? a b) (%subset? b a))) sets))
    (define (oset<=? . sets) (%pairwise %subset? sets))
    (define (oset>=? . sets) (%pairwise (lambda (a b) (%subset? b a)) sets))
    (define (oset<? . sets) (%pairwise (lambda (a b) (and (%subset? a b) (< (oset-size a) (oset-size b)))) sets))
    (define (oset>? . sets) (%pairwise (lambda (a b) (and (%subset? b a) (> (oset-size a) (oset-size b)))) sets))

    (define (oset-union s1 . sets) (%build (oset-element-comparator s1) (apply append (%oset-elements s1) (map %oset-elements sets)) #t))
    (define (oset-intersection s1 . sets)
      (%make-oset (oset-element-comparator s1) (filter (lambda (x) (every (lambda (s) (oset-contains? s x)) sets)) (%oset-elements s1))))
    (define (oset-difference s1 . sets)
      (let ((rest (apply oset-union (car sets) (cdr sets))))
        (%make-oset (oset-element-comparator s1) (filter (lambda (x) (not (oset-contains? rest x))) (%oset-elements s1)))))
    (define (oset-xor s1 s2)
      (%build (oset-element-comparator s1)
              (append (filter (lambda (x) (not (oset-contains? s2 x))) (%oset-elements s1))
                      (filter (lambda (x) (not (oset-contains? s1 x))) (%oset-elements s2)))
              #t))

    (define (oset-min-element s) (if (oset-empty? s) (error "oset-min-element: empty oset") (car (%oset-elements s))))
    (define (oset-max-element s) (if (oset-empty? s) (error "oset-max-element: empty oset") (list-ref (%oset-elements s) (- (oset-size s) 1))))

    (define (oset-element-predecessor s obj failure)
      (let ((lt (%lt (oset-element-comparator s))))
        (let loop ((l (%oset-elements s)) (best #f))
          (cond ((null? l) (if best best (failure)))
                ((lt (car l) obj) (loop (cdr l) (car l)))
                (else (if best best (failure)))))))

    (define (oset-element-successor s obj failure)
      (let ((lt (%lt (oset-element-comparator s))))
        (let loop ((l (%oset-elements s)))
          (cond ((null? l) (failure))
                ((lt obj (car l)) (car l))
                (else (loop (cdr l)))))))

    (define (oset-range= s obj) (oset-filter (lambda (x) ((%eq (oset-element-comparator s)) x obj)) s))
    (define (oset-range< s obj) (oset-filter (lambda (x) ((%lt (oset-element-comparator s)) x obj)) s))
    (define (oset-range> s obj) (oset-filter (lambda (x) ((%lt (oset-element-comparator s)) obj x)) s))
    (define (oset-range<= s obj)
      (let ((lt (%lt (oset-element-comparator s)))) (oset-filter (lambda (x) (not (lt obj x))) s)))
    (define (oset-range>= s obj)
      (let ((lt (%lt (oset-element-comparator s)))) (oset-filter (lambda (x) (not (lt x obj))) s)))

    (define (oset-split s obj)
      (values (oset-range< s obj) (oset-range<= s obj) (oset-range= s obj) (oset-range>= s obj) (oset-range> s obj)))

    (define (oset-catenate comp s1 element s2)
      (%make-oset comp (append (%oset-elements s1) (list element) (%oset-elements s2))))))
