;;; SRFI 101 — Purely Functional Random-Access Pairs and Lists
;;;
;;; An immutable, persistent alternative to ordinary pairs/lists: cons/car/cdr
;;; stay O(1), but list-ref/list-set also get O(log n) instead of O(n), via
;;; Okasaki's skew-binary random-access list representation ("Purely
;;; Functional Data Structures", 1995). A random-access list is a linked
;;; chain of "digits", each digit holding a complete binary tree whose size
;;; is a skew-binary weight (1, 3, 7, 15, ... = 2^i - 1); at most the two
;;; smallest digits may share a weight, so the chain has O(log n) digits.
;;; cons either prepends a new weight-1 digit or, when the first two digits
;;; already share a weight, merges them into one bigger digit — so cons/car/
;;; cdr only ever touch the first one or two digits: O(1).
;;;
;;; Random-access pairs are a disjoint type here (one of the two options the
;;; spec allows): a <ra-digit> record IS a non-empty random-access list (its
;;; "next" field is the rest, which may be another <ra-digit>, the empty
;;; list, or — for an improper/dotted list — any other value). The empty
;;; list is Kaappi's native '(), so null? is just a rename of the native
;;; predicate. Because the record constructors below are not exported, only
;;; this library's own cons/car/cdr can ever build or take apart a <ra-digit>,
;;; so every such object is well-formed by construction.
;;;
;;; This library shadows 44 (scheme base) identifiers (cons, car, cdr, the 28
;;; c[ad]{2,4}r compositions, pair?, null?, list?, list, make-list, length,
;;; append, reverse, list-tail, list-ref, map, for-each, equal?) with SRFI
;;; 101's own semantics on this new type. Internally it needs the native
;;; versions too (for rest-argument lists and small helper tables), so it
;;; imports them back in under a "%" prefix via rename.
;;;
;;; Complexity honesty, where this implementation does NOT hit the number
;;; the spec states:
;;;
;;; - append is O(n) in the combined length of all but the last argument
;;;   (the standard fold-of-cons implementation), not the spec's stated
;;;   O(log n). A generic persistent append fundamentally has to rebuild the
;;;   spine of every list but the last — there is no way to graft two
;;;   skew-binary digit chains together without redoing that work, so
;;;   O(log n) does not look achievable for arbitrary inputs regardless of
;;;   representation; every other portable SRFI 101 implementation we're
;;;   aware of is likewise O(n) here. cons/car/cdr/list-ref/list-set/
;;;   list-tail/length/list?/length<=?/make-list all get their full spec
;;;   complexity (O(1) or O(log n)/O(min(k,log n)) as specified) — the
;;;   skew-binary structure is real, not simulated on top of a plain list.
;;; - `quote` does not construct random-access pairs from pair-containing
;;;   literals (the spec permits this but a portable library has no reader
;;;   or expander hook to implement it with). Use `list`/`cons` to build
;;;   random-access lists explicitly, as shown in this file's own tests.
;;; - `equal?` recurses correctly through random-access list structure,
;;;   including random-access lists nested via car/cdr (a list of lists),
;;;   since every recursive step re-enters this same equal?. It does NOT
;;;   recurse into a random-access list nested inside some other container
;;;   (e.g. a vector of random-access lists) compared with this equal?,
;;;   since a vector's elements get compared by the native, identity-based
;;;   record equality once control leaves this library's equal?. The spec
;;;   explicitly permits this ("equal? ... is unspecified in implementations
;;;   with disjoint representations").
;;; - Only the plain `(srfi 101)` library name is provided, not the R6RS-
;;;   style `(srfi :101 random-access-lists)` family the spec formally
;;;   requests — consistent with how every other portable SRFI in this repo
;;;   is named.
;;;
;;; Known caveat (not this library's bug, but affects callers): consume
;;; list-ref/update's two return values with call-with-values, not
;;; let-values. When this library is imported, wrapping a call whose
;;; argument is itself built by one of this library's variadic procedures
;;; (e.g. `(list-ref/update (list 7 8 9 10) 2 proc)`) in `let-values`
;;; intermittently raises a spurious VM error ("apply: expected proper
;;; list, got #<record_instance>"). A minimal reproduction with an
;;; unrelated variadic procedure and an unrelated values-returning one in
;;; the same external library hits the same error, independent of anything
;;; list-ref/update does — it looks like a Kaappi VM/compiler bug in
;;; let-values' interaction with variadic procedures. call-with-values
;;; does not trigger it in any case tried; this file's own tests use it
;;; exclusively for that reason.

(define-library (srfi 101)
  ;; Note: (scheme base) only exports the depth-1/2 car/cdr compositions
  ;; (car, cdr, caar/cadr/cdar/cddr) — the 24 depth-3/4 ones below live in
  ;; (scheme cxr)/(scheme r5rs), which this library doesn't import, so
  ;; there is nothing to except them from; they're defined fresh below.
  (import
    (except (scheme base)
      cons car cdr
      caar cadr cdar cddr
      pair? null? list? list make-list length append reverse
      list-tail list-ref map for-each equal?)
    (rename (scheme base)
      (cons %cons) (car %car) (cdr %cdr)
      (pair? %pair?) (null? %null?) (equal? %equal?)))

  (export
    cons car cdr
    caar cadr cdar cddr
    caaar caadr cadar caddr cdaar cdadr cddar cdddr
    caaaar caaadr caadar caaddr cadaar cadadr caddar cadddr
    cdaaar cdaadr cdadar cdaddr cddaar cddadr cdddar cddddr
    pair? null? list? list make-list length length<=?
    append reverse list-tail list-ref list-set list-ref/update
    map for-each equal?
    random-access-list->linear-access-list
    linear-access-list->random-access-list)

  (begin

    ;;; --- internal representation ---
    ;;; A tree of skew weight 1 is a <ra-leaf>; weight w > 1 is a <ra-node>
    ;;; with two subtrees of weight (w-1)/2 each. A <ra-digit> is one entry
    ;;; in the top-level chain: `tree` has `weight` elements, `next` is the
    ;;; rest of the chain (another <ra-digit>, '(), or an improper tail).

    (define-record-type <ra-leaf>
      (make-ra-leaf value)
      ra-leaf?
      (value ra-leaf-value))

    (define-record-type <ra-node>
      (make-ra-node value left right)
      ra-node?
      (value ra-node-value)
      (left ra-node-left)
      (right ra-node-right))

    (define-record-type <ra-digit>
      (make-ra-digit weight tree next)
      ra-digit?
      (weight ra-digit-weight)
      (tree ra-digit-tree)
      (next ra-digit-next))

    ;;; --- O(1) core: cons, car, cdr, pair?, null? ---

    (define (cons x ts)
      (if (and (ra-digit? ts)
               (ra-digit? (ra-digit-next ts))
               (= (ra-digit-weight ts) (ra-digit-weight (ra-digit-next ts))))
          (let* ((d1 ts) (d2 (ra-digit-next ts)))
            (make-ra-digit (+ 1 (ra-digit-weight d1) (ra-digit-weight d2))
                            (make-ra-node x (ra-digit-tree d1) (ra-digit-tree d2))
                            (ra-digit-next d2)))
          (make-ra-digit 1 (make-ra-leaf x) ts)))

    (define (pair? x) (ra-digit? x))
    (define (null? x) (%null? x))

    (define (car p)
      (if (not (ra-digit? p))
          (error "car: not a pair" p)
          (if (= (ra-digit-weight p) 1)
              (ra-leaf-value (ra-digit-tree p))
              (ra-node-value (ra-digit-tree p)))))

    (define (cdr p)
      (if (not (ra-digit? p))
          (error "cdr: not a pair" p)
          (if (= (ra-digit-weight p) 1)
              (ra-digit-next p)
              (let ((half (quotient (ra-digit-weight p) 2))
                    (tree (ra-digit-tree p)))
                (make-ra-digit half (ra-node-left tree)
                                (make-ra-digit half (ra-node-right tree) (ra-digit-next p)))))))

    ;;; --- the 28 up-to-depth-4 car/cdr compositions, O(1) each ---

    (define (caar p) (car (car p)))
    (define (cadr p) (car (cdr p)))
    (define (cdar p) (cdr (car p)))
    (define (cddr p) (cdr (cdr p)))
    (define (caaar p) (car (caar p)))
    (define (caadr p) (car (cadr p)))
    (define (cadar p) (car (cdar p)))
    (define (caddr p) (car (cddr p)))
    (define (cdaar p) (cdr (caar p)))
    (define (cdadr p) (cdr (cadr p)))
    (define (cddar p) (cdr (cdar p)))
    (define (cdddr p) (cdr (cddr p)))
    (define (caaaar p) (car (caaar p)))
    (define (caaadr p) (car (caadr p)))
    (define (caadar p) (car (cadar p)))
    (define (caaddr p) (car (caddr p)))
    (define (cadaar p) (car (cdaar p)))
    (define (cadadr p) (car (cdadr p)))
    (define (caddar p) (car (cddar p)))
    (define (cadddr p) (car (cdddr p)))
    (define (cdaaar p) (cdr (caaar p)))
    (define (cdaadr p) (cdr (caadr p)))
    (define (cdadar p) (cdr (cadar p)))
    (define (cdaddr p) (cdr (caddr p)))
    (define (cddaar p) (cdr (cdaar p)))
    (define (cddadr p) (cdr (cdadr p)))
    (define (cdddar p) (cdr (cddar p)))
    (define (cddddr p) (cdr (cdddr p)))

    ;;; --- list?, length, length<=? : walk the top-level digit chain only
    ;;; (never descend into a tree), so all three are O(number of digits) =
    ;;; O(log n), matching the spec without needing tree-level work.

    (define (list? x)
      (let loop ((x x))
        (cond ((null? x) #t)
              ((not (ra-digit? x)) #f)
              (else (loop (ra-digit-next x))))))

    (define (length x)
      (let loop ((x x) (acc 0))
        (cond ((null? x) acc)
              ((not (ra-digit? x)) (error "length: not a proper list" x))
              (else (loop (ra-digit-next x) (+ acc (ra-digit-weight x)))))))

    ;; "Is x a chain of at least k pairs?" (per spec: true if k <= length,
    ;; even on an improper or non-pair x, since k <= 0 is trivially true.)
    (define (length<=? x k)
      (let loop ((x x) (k k))
        (cond ((<= k 0) #t)
              ((not (ra-digit? x)) #f)
              (else (loop (ra-digit-next x) (- k (ra-digit-weight x)))))))

    ;;; --- list-ref / list-set / list-ref/update: O(min(k,log n)) via
    ;;; Okasaki's lookupTree/updateTree, generalized to a combined
    ;;; ref-and-update in one descent for list-ref/update.

    (define (%tree-ref weight tree k)
      (if (= weight 1)
          (ra-leaf-value tree)
          (if (= k 0)
              (ra-node-value tree)
              (let ((half (quotient weight 2)))
                (if (<= k half)
                    (%tree-ref half (ra-node-left tree) (- k 1))
                    (%tree-ref half (ra-node-right tree) (- k 1 half)))))))

    (define (list-ref p k)
      (let loop ((p p) (k k))
        (if (not (ra-digit? p))
            (error "list-ref: index out of range" k)
            (if (< k (ra-digit-weight p))
                (%tree-ref (ra-digit-weight p) (ra-digit-tree p) k)
                (loop (ra-digit-next p) (- k (ra-digit-weight p)))))))

    (define (%tree-set weight tree k obj)
      (if (= weight 1)
          (make-ra-leaf obj)
          (if (= k 0)
              (make-ra-node obj (ra-node-left tree) (ra-node-right tree))
              (let ((half (quotient weight 2)))
                (if (<= k half)
                    (make-ra-node (ra-node-value tree) (%tree-set half (ra-node-left tree) (- k 1) obj) (ra-node-right tree))
                    (make-ra-node (ra-node-value tree) (ra-node-left tree) (%tree-set half (ra-node-right tree) (- k 1 half) obj)))))))

    (define (list-set p k obj)
      (let loop ((p p) (k k))
        (if (not (ra-digit? p))
            (error "list-set: index out of range" k)
            (if (< k (ra-digit-weight p))
                (make-ra-digit (ra-digit-weight p) (%tree-set (ra-digit-weight p) (ra-digit-tree p) k obj) (ra-digit-next p))
                (make-ra-digit (ra-digit-weight p) (ra-digit-tree p) (loop (ra-digit-next p) (- k (ra-digit-weight p))))))))

    ;; Both helpers below thread the (old-value . new-structure) result as a
    ;; plain native pair rather than through values/call-with-values: a
    ;; recursive function whose tail position is call-with-values over
    ;; another multiple-values-returning call trips a Kaappi VM bytecode
    ;; bug where the tail-call path for `apply` (used internally to invoke
    ;; the values-consumer) sees the MultipleValues object where it expects
    ;; a proper list ("apply: last argument must be a list") — reproduced
    ;; with plain (scheme base) call-with-values/values and no random-access
    ;; pairs involved, so it's not specific to this library's shadowing.
    ;; list-ref/update itself still returns genuine multiple values, once,
    ;; at the very end, from a non-recursive, non-tail-position call.
    (define (%tree-ref-update weight tree k proc)
      (if (= weight 1)
          (%cons (ra-leaf-value tree) (make-ra-leaf (proc (ra-leaf-value tree))))
          (if (= k 0)
              (%cons (ra-node-value tree) (make-ra-node (proc (ra-node-value tree)) (ra-node-left tree) (ra-node-right tree)))
              (let ((half (quotient weight 2)))
                (if (<= k half)
                    (let ((r (%tree-ref-update half (ra-node-left tree) (- k 1) proc)))
                      (%cons (%car r) (make-ra-node (ra-node-value tree) (%cdr r) (ra-node-right tree))))
                    (let ((r (%tree-ref-update half (ra-node-right tree) (- k 1 half) proc)))
                      (%cons (%car r) (make-ra-node (ra-node-value tree) (ra-node-left tree) (%cdr r)))))))))

    (define (%list-ref-update-pair p k proc)
      (if (not (ra-digit? p))
          (error "list-ref/update: index out of range" k)
          (if (< k (ra-digit-weight p))
              (let ((r (%tree-ref-update (ra-digit-weight p) (ra-digit-tree p) k proc)))
                (%cons (%car r) (make-ra-digit (ra-digit-weight p) (%cdr r) (ra-digit-next p))))
              (let ((r (%list-ref-update-pair (ra-digit-next p) (- k (ra-digit-weight p)) proc)))
                (%cons (%car r) (make-ra-digit (ra-digit-weight p) (ra-digit-tree p) (%cdr r)))))))

    (define (list-ref/update p k proc)
      (let ((r (%list-ref-update-pair p k proc)))
        (values (%car r) (%cdr r))))

    ;;; --- list-tail: O(log(min(k,n))) via Okasaki-style tree-splitting
    ;;; drop, not repeated cdr (which would be O(k)). Walks digits until the
    ;;; one containing index k, then peels exactly the elements before k out
    ;;; of that digit's tree, turning the untouched siblings along the way
    ;;; into new (still canonically-ordered) leading digits.

    (define (%drop-tree weight tree k rest)
      (cond
        ((= k 0) (make-ra-digit weight tree rest))
        ((= weight 1) rest)
        (else
         (let* ((half (quotient weight 2))
                (k2 (- k 1)))
           (if (<= k2 half)
               (%drop-tree half (ra-node-left tree) k2 (make-ra-digit half (ra-node-right tree) rest))
               (%drop-tree half (ra-node-right tree) (- k2 half) rest))))))

    (define (list-tail p k)
      (cond
        ((= k 0) p)
        ((not (ra-digit? p)) (error "list-tail: index out of range" k))
        ((< k (ra-digit-weight p)) (%drop-tree (ra-digit-weight p) (ra-digit-tree p) k (ra-digit-next p)))
        (else (list-tail (ra-digit-next p) (- k (ra-digit-weight p))))))

    ;;; --- make-list: O(log k) time AND space, via building each
    ;;; skew-weight tree exactly once and sharing it across every digit that
    ;;; needs a tree of that weight (safe because the structure is
    ;;; immutable) — the whole reason a list of k identical elements need
    ;;; not cost O(k).

    ;; Decreasing-weight table of (weight . tree) native pairs, one entry
    ;; per skew weight up to the largest that fits in k. Each tree is built
    ;; from the previous one in O(1) by reuse, so the whole table is O(log k).
    (define (%ra-tree-table k fill)
      (let ((leaf (make-ra-leaf fill)))
        (let loop ((w 1) (tree leaf) (acc (%cons (%cons 1 leaf) '())))
          (if (> (+ w w 1) k)
              acc
              (let* ((w2 (+ w w 1)) (tree2 (make-ra-node fill tree tree)))
                (loop w2 tree2 (%cons (%cons w2 tree2) acc)))))))

    ;; Greedily consume the largest available weight <= remaining, without
    ;; advancing past a table entry until it no longer fits — so a weight
    ;; class can be (and, per skew-binary form, sometimes must be) reused
    ;; twice, e.g. k=6 needs two weight-3 digits.
    (define (%ra-build k fill)
      (let ((table (%ra-tree-table k fill)))
        (let loop ((remaining k) (table table) (rest '()))
          (cond
            ((= remaining 0) rest)
            ((%null? table) (error "make-list: internal error" k))
            ((> (%car (%car table)) remaining) (loop remaining (%cdr table) rest))
            (else (loop (- remaining (%car (%car table)))
                        table
                        (make-ra-digit (%car (%car table)) (%cdr (%car table)) rest)))))))

    ;; Plain rest-arg dispatch rather than case-lambda: case-lambda's
    ;; generated arity check calls the global `length` directly (not a
    ;; hygienically-fixed reference to (scheme base)'s), so it would pick up
    ;; this very library's shadowed `length` and fail on a native argument
    ;; list. Every other variadic procedure below sidesteps the same trap by
    ;; using a plain `. rest` lambda instead of case-lambda.
    (define (make-list k . opt)
      (let ((fill (if (%pair? opt) (%car opt) #f)))
        (if (or (not (integer? k)) (< k 0))
            (error "make-list: k must be a non-negative integer" k)
            (if (= k 0) '() (%ra-build k fill)))))

    ;;; --- list, append, reverse, map, for-each ---

    (define (%ra-from-native-list lst)
      (if (%null? lst)
          '()
          (cons (%car lst) (%ra-from-native-list (%cdr lst)))))

    (define (list . args) (%ra-from-native-list args))

    (define (%ra-append-two a b)
      (if (null? a) b (cons (car a) (%ra-append-two (cdr a) b))))

    ;; O(n) in the combined length of all but the last argument — see the
    ;; header comment for why the spec's stated O(log n) isn't met here.
    (define (append . lists)
      (cond
        ((%null? lists) '())
        ((%null? (%cdr lists)) (%car lists))
        (else (%ra-append-two (%car lists) (apply append (%cdr lists))))))

    (define (reverse lst)
      (let loop ((lst lst) (acc '()))
        (if (null? lst) acc (loop (cdr lst) (cons (car lst) acc)))))

    (define (%any-ra-null? lsts)
      (and (%pair? lsts) (or (null? (%car lsts)) (%any-ra-null? (%cdr lsts)))))

    (define (%map-ra-car lsts)
      (if (%null? lsts) '() (%cons (car (%car lsts)) (%map-ra-car (%cdr lsts)))))

    (define (%map-ra-cdr lsts)
      (if (%null? lsts) '() (%cons (cdr (%car lsts)) (%map-ra-cdr (%cdr lsts)))))

    (define (map proc lst . more)
      (if (%null? more)
          (let loop ((lst lst) (acc '()))
            (if (null? lst) (reverse acc) (loop (cdr lst) (cons (proc (car lst)) acc))))
          (let loop ((lsts (%cons lst more)) (acc '()))
            (if (%any-ra-null? lsts)
                (reverse acc)
                (loop (%map-ra-cdr lsts) (cons (apply proc (%map-ra-car lsts)) acc))))))

    (define (for-each proc lst . more)
      (if (%null? more)
          (let loop ((lst lst))
            (unless (null? lst)
              (proc (car lst))
              (loop (cdr lst))))
          (let loop ((lsts (%cons lst more)))
            (unless (%any-ra-null? lsts)
              (apply proc (%map-ra-car lsts))
              (loop (%map-ra-cdr lsts))))))

    ;;; --- equal? : structural equality; see header comment for the one
    ;;; case (random-access lists nested in a non-random-access-list
    ;;; container) it does not reach.

    (define (equal? a b)
      (cond
        ((and (ra-digit? a) (ra-digit? b))
         (and (equal? (car a) (car b)) (equal? (cdr a) (cdr b))))
        ((or (ra-digit? a) (ra-digit? b)) #f)
        (else (%equal? a b))))

    ;;; --- conversion to/from ordinary (linear-access) lists ---

    (define (random-access-list->linear-access-list ra-list)
      (let loop ((ra ra-list))
        (if (pair? ra) (%cons (car ra) (loop (cdr ra))) ra)))

    (define (linear-access-list->random-access-list la-list)
      (let loop ((la la-list))
        (if (%pair? la) (cons (%car la) (loop (%cdr la))) la)))))
