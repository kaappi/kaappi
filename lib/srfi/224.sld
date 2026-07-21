;;; SRFI 224 — Integer Mappings (fxmappings)
;;;
;;; The spec's reference representation is a big-endian radix (Patricia)
;;; tree. This implementation instead uses a record wrapping a sorted
;;; (ascending by key), duplicate-key-free association list — correct and
;;; simple, but O(n) per operation rather than the spec's near-constant-time
;;; complexity. Since fxmapping->alist/-keys/-values/-fold are already
;;; required to traverse in ascending key order, a sorted alist costs
;;; nothing extra for the read side.
;;;
;;; Kaappi's fixnums exceed the spec's minimum width (w >= 24) by a wide
;;; margin (48-bit signed, auto-promoting to bignum beyond that), so no key
;;; range restriction is enforced here beyond "exact integer".

(define-library (srfi 224)
  (import (scheme base) (scheme case-lambda))
  (export
    fxmapping fxmapping-unfold fxmapping-accumulate
    alist->fxmapping alist->fxmapping/combinator
    fxmapping? fxmapping-contains? fxmapping-empty? fxmapping-disjoint?
    fxmapping-ref fxmapping-ref/default fxmapping-min fxmapping-max
    fxmapping-adjoin fxmapping-adjoin/combinator fxmapping-set
    fxmapping-adjust fxmapping-delete fxmapping-delete-all
    fxmapping-update fxmapping-alter
    fxmapping-delete-min fxmapping-delete-max
    fxmapping-update-min fxmapping-update-max
    fxmapping-pop-min fxmapping-pop-max
    fxmapping-size fxmapping-find fxmapping-count
    fxmapping-any? fxmapping-every?
    fxmapping-map fxmapping-for-each fxmapping-fold fxmapping-fold-right
    fxmapping-map->list fxmapping-relation-map
    fxmapping-filter fxmapping-remove fxmapping-partition
    fxmapping->alist fxmapping->decreasing-alist
    fxmapping-keys fxmapping-values
    fxmapping->generator fxmapping->decreasing-generator
    fxmapping=? fxmapping<? fxmapping<=? fxmapping>? fxmapping>=?
    fxmapping-union fxmapping-intersection fxmapping-difference fxmapping-xor
    fxmapping-union/combinator fxmapping-intersection/combinator
    fxmapping-open-interval fxmapping-closed-interval
    fxmapping-open-closed-interval fxmapping-closed-open-interval
    fxsubmapping= fxsubmapping< fxsubmapping<= fxsubmapping> fxsubmapping>=
    fxmapping-split)
  (begin

    (define-record-type <fxmapping>
      (%make-fxmapping alist)
      fxmapping?
      (alist %fxm-alist))

    (define (%sort-alist< alist)
      (define (merge a b)
        (cond ((null? a) b) ((null? b) a)
              ((< (caar b) (caar a)) (cons (car b) (merge a (cdr b))))
              (else (cons (car a) (merge (cdr a) b)))))
      (define (split lst)
        (if (or (null? lst) (null? (cdr lst)))
            (values lst '())
            (let-values (((a b) (split (cddr lst))))
              (values (cons (car lst) a) (cons (cadr lst) b)))))
      (if (or (null? alist) (null? (cdr alist)))
          alist
          (let-values (((a b) (split alist)))
            (merge (%sort-alist< a) (%sort-alist< b)))))

    ;; Later duplicate keys are dropped, so "earlier associations take
    ;; priority" (the spec's convention throughout) falls out naturally
    ;; when callers build the input list with priority entries first.
    (define (%dedup-keys sorted-alist)
      (cond ((or (null? sorted-alist) (null? (cdr sorted-alist))) sorted-alist)
            ((= (caar sorted-alist) (car (cadr sorted-alist)))
             (%dedup-keys (cons (car sorted-alist) (cddr sorted-alist))))
            (else (cons (car sorted-alist) (%dedup-keys (cdr sorted-alist))))))

    (define (%build alist) (%make-fxmapping (%dedup-keys (%sort-alist< alist))))

    (define (fxmapping . kvs)
      (%build (let loop ((kvs kvs)) (if (null? kvs) '() (cons (cons (car kvs) (cadr kvs)) (loop (cddr kvs)))))))

    (define (fxmapping-unfold stop? mapper successor . seeds)
      (let loop ((seeds seeds) (acc '()))
        (if (apply stop? seeds)
            (%build (reverse acc))
            (call-with-values
              (lambda () (apply mapper seeds))
              (lambda (k v)
                (loop (call-with-values (lambda () (apply successor seeds)) list) (cons (cons k v) acc)))))))

    (define (fxmapping-accumulate proc . seeds)
      (call-with-current-continuation
        (lambda (abort)
          (let loop ((seeds seeds) (acc '()))
            (call-with-values
              (lambda () (apply proc (lambda (result) (abort (%build (reverse acc)) result)) seeds))
              (lambda (k v . new-seeds) (loop new-seeds (cons (cons k v) acc))))))))

    (define (alist->fxmapping alist) (%build alist))
    (define (alist->fxmapping/combinator proc alist)
      ;; acc is built by consing (reverse order), but %build sorts it
      ;; regardless, so no final reverse is needed.
      (let loop ((alist alist) (acc '()))
        (cond ((null? alist) (%build acc))
              ((assv (caar alist) acc) =>
               (lambda (existing)
                 (set-cdr! existing (proc (caar alist) (cdr existing) (cdar alist)))
                 (loop (cdr alist) acc)))
              (else (loop (cdr alist) (cons (cons (caar alist) (cdar alist)) acc))))))

    (define (fxmapping-contains? m k) (and (assv k (%fxm-alist m)) #t))
    (define (fxmapping-empty? m) (null? (%fxm-alist m)))
    (define (fxmapping-disjoint? m1 m2) (not (any (lambda (kv) (fxmapping-contains? m2 (car kv))) (%fxm-alist m1))))
    (define (any pred lst) (and (pair? lst) (or (pred (car lst)) (any pred (cdr lst)))))

    (define fxmapping-ref
      (case-lambda
        ((m k) (fxmapping-ref m k (lambda () (error "fxmapping-ref: key not found" k)) values))
        ((m k failure) (fxmapping-ref m k failure values))
        ((m k failure success)
         (let ((p (assv k (%fxm-alist m))))
           (if p (success (cdr p)) (failure))))))

    (define (fxmapping-ref/default m k default) (let ((p (assv k (%fxm-alist m)))) (if p (cdr p) default)))

    (define (fxmapping-min m) (let ((a (%fxm-alist m))) (values (caar a) (cdar a))))
    (define (fxmapping-max m) (let ((a (%fxm-alist m))) (let ((last (list-ref a (- (length a) 1)))) (values (car last) (cdr last)))))

    (define (fxmapping-adjoin m . kvs)
      (let loop ((kvs kvs) (acc (%fxm-alist m)))
        (if (null? kvs)
            (%build acc)
            (loop (cddr kvs) (if (assv (car kvs) acc) acc (append acc (list (cons (car kvs) (cadr kvs)))))))))

    (define (fxmapping-adjoin/combinator m proc . kvs)
      (let loop ((kvs kvs) (acc (%fxm-alist m)))
        (if (null? kvs)
            (%build acc)
            (let ((existing (assv (car kvs) acc)))
              (loop (cddr kvs)
                    (if existing
                        (map (lambda (p) (if (= (car p) (car kvs)) (cons (car p) (proc (car kvs) (cdr p) (cadr kvs))) p)) acc)
                        (append acc (list (cons (car kvs) (cadr kvs))))))))))

    (define (fxmapping-set m . kvs)
      (let loop ((kvs kvs) (acc (%fxm-alist m)))
        (if (null? kvs)
            (%build acc)
            (loop (cddr kvs) (cons (cons (car kvs) (cadr kvs)) (filter (lambda (p) (not (= (car p) (car kvs)))) acc))))))
    (define (filter pred lst) (cond ((null? lst) '()) ((pred (car lst)) (cons (car lst) (filter pred (cdr lst)))) (else (filter pred (cdr lst)))))

    (define (fxmapping-adjust m k proc)
      (%build (map (lambda (p) (if (= (car p) k) (cons k (proc k (cdr p))) p)) (%fxm-alist m))))

    (define (fxmapping-delete m . ks) (%make-fxmapping (filter (lambda (p) (not (memv (car p) ks))) (%fxm-alist m))))
    (define (fxmapping-delete-all m ks) (apply fxmapping-delete m ks))

    (define fxmapping-update
      (case-lambda
        ((m k proc) (fxmapping-update m k proc (lambda () (error "fxmapping-update: key not found" k))))
        ((m k proc failure)
         (let ((p (assv k (%fxm-alist m))))
           (if p
               (proc k (cdr p)
                     (lambda (new-v) (%build (map (lambda (q) (if (= (car q) k) (cons k new-v) q)) (%fxm-alist m))))
                     (lambda () (fxmapping-delete m k)))
               (failure))))))

    (define (fxmapping-alter m k failure success)
      (let ((p (assv k (%fxm-alist m))))
        (if p
            (success k (cdr p)
                     (lambda (new-v) (%build (map (lambda (q) (if (= (car q) k) (cons k new-v) q)) (%fxm-alist m))))
                     (lambda () (fxmapping-delete m k)))
            (failure k
                     (lambda (new-v) (fxmapping-adjoin m k new-v))
                     (lambda () m)))))

    (define (fxmapping-delete-min m) (%make-fxmapping (cdr (%fxm-alist m))))
    (define (fxmapping-delete-max m) (let ((a (%fxm-alist m))) (%make-fxmapping (%take a (- (length a) 1)))))
    (define (%take lst n) (if (= n 0) '() (cons (car lst) (%take (cdr lst) (- n 1)))))

    (define (fxmapping-update-min m proc)
      (let* ((a (%fxm-alist m)) (k (caar a)) (v (cdar a)))
        (proc k v
              (lambda (new-v) (%build (cons (cons k new-v) (cdr a))))
              (lambda () (%make-fxmapping (cdr a))))))
    (define (fxmapping-update-max m proc)
      (let* ((a (%fxm-alist m)) (n (length a)) (last (list-ref a (- n 1))))
        (proc (car last) (cdr last)
              (lambda (new-v) (%build (append (%take a (- n 1)) (list (cons (car last) new-v)))))
              (lambda () (%make-fxmapping (%take a (- n 1)))))))

    (define (fxmapping-pop-min m) (let ((a (%fxm-alist m))) (values (caar a) (cdar a) (%make-fxmapping (cdr a)))))
    (define (fxmapping-pop-max m)
      (let* ((a (%fxm-alist m)) (n (length a)) (last (list-ref a (- n 1))))
        (values (car last) (cdr last) (%make-fxmapping (%take a (- n 1))))))

    (define (fxmapping-size m) (length (%fxm-alist m)))

    (define fxmapping-find
      (case-lambda
        ((pred m failure) (fxmapping-find pred m failure values))
        ((pred m failure success)
         (let loop ((a (%fxm-alist m)))
           (cond ((null? a) (failure))
                 ((pred (caar a) (cdar a)) (success (caar a) (cdar a)))
                 (else (loop (cdr a))))))))

    (define (fxmapping-count pred m) (length (filter (lambda (p) (pred (car p) (cdr p))) (%fxm-alist m))))
    (define (fxmapping-any? pred m) (any (lambda (p) (pred (car p) (cdr p))) (%fxm-alist m)))
    (define (fxmapping-every? pred m) (let loop ((a (%fxm-alist m))) (or (null? a) (and (pred (caar a) (cdar a)) (loop (cdr a))))))

    (define (fxmapping-map proc m) (%make-fxmapping (map (lambda (p) (cons (car p) (proc (cdr p)))) (%fxm-alist m))))
    (define (fxmapping-for-each proc m) (for-each (lambda (p) (proc (car p) (cdr p))) (%fxm-alist m)))
    (define (fxmapping-fold kons knil m) (fold-left-fxm kons knil (%fxm-alist m)))
    (define (fold-left-fxm kons acc alist) (if (null? alist) acc (fold-left-fxm kons (kons (caar alist) (cdar alist) acc) (cdr alist))))
    (define (fxmapping-fold-right kons knil m)
      (let loop ((a (%fxm-alist m))) (if (null? a) knil (kons (caar a) (cdar a) (loop (cdr a))))))
    (define (fxmapping-map->list proc m) (map (lambda (p) (proc (car p) (cdr p))) (%fxm-alist m)))
    (define (fxmapping-relation-map proc m) (%build (map (lambda (p) (call-with-values (lambda () (proc (car p) (cdr p))) cons)) (%fxm-alist m))))

    (define (fxmapping-filter pred m) (%make-fxmapping (filter (lambda (p) (pred (car p) (cdr p))) (%fxm-alist m))))
    (define (fxmapping-remove pred m) (%make-fxmapping (filter (lambda (p) (not (pred (car p) (cdr p)))) (%fxm-alist m))))
    (define (fxmapping-partition pred m) (values (fxmapping-filter pred m) (fxmapping-remove pred m)))

    (define (fxmapping->alist m) (%fxm-alist m))
    (define (fxmapping->decreasing-alist m) (reverse (%fxm-alist m)))
    (define (fxmapping-keys m) (map car (%fxm-alist m)))
    (define (fxmapping-values m) (map cdr (%fxm-alist m)))

    (define (fxmapping->generator m)
      (let ((remaining (%fxm-alist m)))
        (lambda ()
          (if (null? remaining) (eof-object)
              (let ((p (car remaining))) (set! remaining (cdr remaining)) p)))))
    (define (fxmapping->decreasing-generator m)
      (let ((remaining (reverse (%fxm-alist m))))
        (lambda ()
          (if (null? remaining) (eof-object)
              (let ((p (car remaining))) (set! remaining (cdr remaining)) p)))))

    (define (%same-keys? m1 m2)
      (and (= (fxmapping-size m1) (fxmapping-size m2))
           (every (lambda (p) (fxmapping-contains? m2 (car p))) (%fxm-alist m1))))
    (define (every pred lst) (or (null? lst) (and (pred (car lst)) (every pred (cdr lst)))))

    (define (fxmapping=? comp . ms)
      (%pairwise ms (lambda (m1 m2)
                      (and (%same-keys? m1 m2)
                           (every (lambda (p) (comp (cdr p) (fxmapping-ref/default m2 (car p) p))) (%fxm-alist m1))))))
    (define (%pairwise lst pred) (or (null? lst) (null? (cdr lst)) (and (pred (car lst) (cadr lst)) (%pairwise (cdr lst) pred))))
    (define (%key-subset? m1 m2) (every (lambda (p) (fxmapping-contains? m2 (car p))) (%fxm-alist m1)))
    (define (fxmapping<=? comp . ms) (%pairwise ms %key-subset?))
    (define (fxmapping>=? comp . ms) (%pairwise ms (lambda (a b) (%key-subset? b a))))
    (define (fxmapping<? comp . ms) (%pairwise ms (lambda (a b) (and (%key-subset? a b) (< (fxmapping-size a) (fxmapping-size b))))))
    (define (fxmapping>? comp . ms) (%pairwise ms (lambda (a b) (and (%key-subset? b a) (> (fxmapping-size a) (fxmapping-size b))))))

    (define (fxmapping-union m1 . ms)
      (%make-fxmapping (fold-left-fxm (lambda (k v acc) (if (assv k acc) acc (append acc (list (cons k v))))) (%fxm-alist m1) (apply append (map %fxm-alist ms)))))
    (define (fxmapping-intersection m1 . ms) (fxmapping-filter (lambda (k v) (every (lambda (m) (fxmapping-contains? m k)) ms)) m1))
    (define (fxmapping-difference m1 . ms)
      (let ((u (apply fxmapping-union (car ms) (cdr ms))))
        (fxmapping-remove (lambda (k v) (fxmapping-contains? u k)) m1)))
    (define (fxmapping-xor m1 m2)
      (%build (append (filter (lambda (p) (not (fxmapping-contains? m2 (car p)))) (%fxm-alist m1))
                       (filter (lambda (p) (not (fxmapping-contains? m1 (car p)))) (%fxm-alist m2)))))

    (define (fxmapping-union/combinator proc m1 . ms)
      (fold-left-fxm
        (lambda (k v acc)
          (let ((existing (assv k (%fxm-alist acc))))
            (if existing (fxmapping-set acc k (proc k (cdr existing) v)) (fxmapping-adjoin acc k v))))
        m1 (apply append (map %fxm-alist ms))))
    (define (fxmapping-intersection/combinator proc m1 . ms)
      (fxmapping-map (lambda (v) v)
        (%build (filter (lambda (p) (every (lambda (m) (fxmapping-contains? m (car p))) ms)) (%fxm-alist m1)))))

    (define (fxmapping-open-interval m low high) (fxmapping-filter (lambda (k v) (and (> k low) (< k high))) m))
    (define (fxmapping-closed-interval m low high) (fxmapping-filter (lambda (k v) (and (>= k low) (<= k high))) m))
    (define (fxmapping-open-closed-interval m low high) (fxmapping-filter (lambda (k v) (and (> k low) (<= k high))) m))
    (define (fxmapping-closed-open-interval m low high) (fxmapping-filter (lambda (k v) (and (>= k low) (< k high))) m))

    (define (fxsubmapping= m k) (fxmapping-filter (lambda (k2 v) (= k2 k)) m))
    (define (fxsubmapping< m k) (fxmapping-filter (lambda (k2 v) (< k2 k)) m))
    (define (fxsubmapping<= m k) (fxmapping-filter (lambda (k2 v) (<= k2 k)) m))
    (define (fxsubmapping> m k) (fxmapping-filter (lambda (k2 v) (> k2 k)) m))
    (define (fxsubmapping>= m k) (fxmapping-filter (lambda (k2 v) (>= k2 k)) m))

    (define (fxmapping-split m k) (values (fxsubmapping<= m k) (fxsubmapping> m k)))))
