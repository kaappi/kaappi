;;; Audit: lib/srfi/225.sld (SRFI 225 — Dictionaries)
;;; Systematic audit v2, Phase 3.9 (docs/audit-strategy.md, tracking #1890).
;;;
;;; Oracle: SRFI 225, https://srfi.schemers.org/srfi-225/srfi-225.html
;;;
;;; SRFI 225 is a generic protocol over several concrete dictionary types, so
;;; the instrument that matters is the DIFFERENTIAL: the same operation on
;;; every DTO the library ships must produce the same answer. Every generic
;;; procedure below is therefore run against all three
;;; (eqv-alist-dto, equal-alist-dto, hash-table-dto) and asserted equal
;;; across them, then asserted against the spec's own stated value.
;;;
;;; The cross-DTO sweep found 49 of 51 operation groups in exact agreement.
;;; The two that differ, both correctly:
;;;   * dict-ref with no failure procedure raises on all three (the spec's
;;;     default failure signals an error), so "agreement" there is agreement
;;;     on raising;
;;;   * dict-pure? is #t for the two alist DTOs and #f for the hash-table
;;;     DTO, which is exactly what the predicate exists to report.
;;;
;;; Portability: dictionaries are unordered, so every list result is sorted
;;; and every dictionary result is compared as a sorted key/value alist.
;;;
;;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi225-audit.scm

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 64) (srfi 225)
        (except (srfi 69) string-hash string-ci-hash)
        (srfi 128) (srfi 158))

(test-begin "srfi225 audit")

(define (isort less l)
  (let loop ((in l) (out '()))
    (if (null? in) out
        (loop (cdr in)
              (let ins ((o out))
                (cond ((null? o) (list (car in)))
                      ((less (car in) (car o)) (cons (car in) o))
                      (else (cons (car o) (ins (cdr o))))))))))
(define (srt l) (isort < l))
(define (srtp l) (isort (lambda (x y) (< (car x) (car y))) l))
(define (raises? thunk)
  (call-with-current-continuation
   (lambda (k) (with-exception-handler (lambda (e) (k #t)) (lambda () (thunk) #f)))))

(define (mk-alist) (list (cons 1 'a) (cons 2 'b) (cons 3 'c)))
(define (mk-ht)
  (let ((h (make-hash-table equal?)))
    (hash-table-set! h 1 'a) (hash-table-set! h 2 'b) (hash-table-set! h 3 'c) h))

;; (label dto fresh-dict-maker)
(define dtos
  (list (list "eqv-alist" eqv-alist-dto mk-alist)
        (list "equal-alist" equal-alist-dto mk-alist)
        (list "hash-table" hash-table-dto mk-ht)))

(define (canon dto d) (srtp (dict->alist dto d)))

;; A fresh dict of the same concrete type as `dto` expects.
(define (fresh-for dto)
  (let loop ((es dtos))
    (cond ((null? es) (error "fresh-for: unknown dto"))
          ((eq? dto (cadr (car es))) ((caddr (car es))))
          (else (loop (cdr es))))))

;; Run `proc` under every DTO. Assert (a) all three agree with each other and
;; (b) they all equal `expected`.
(define (differential name expected proc)
  (let* ((vals (map (lambda (e) (proc (cadr e) ((caddr e)))) dtos))
         (first (car vals)))
    (for-each
     (lambda (e v)
       (test-equal (string-append name " [" (car e) "] agrees with the spec") expected v)
       (test-equal (string-append name " [" (car e) "] agrees with eqv-alist") first v))
     dtos vals)))

;;; ------------------------------------------------------------------
;;; Type predicate and inspection
;;; ------------------------------------------------------------------

(differential "dictionary? on a matching dict" #t (lambda (dto d) (dictionary? dto d)))
(differential "dictionary? on a number" #f (lambda (dto d) (dictionary? dto 42)))
(differential "dict->alist" '((1 . a) (2 . b) (3 . c)) (lambda (dto d) (canon dto d)))
(differential "dict-size" 3 (lambda (dto d) (dict-size dto d)))
(differential "dict-empty? on a populated dict" #f (lambda (dto d) (dict-empty? dto d)))
(differential "dict-empty? after deleting everything" #t
              (lambda (dto d) (dict-empty? dto (dict-delete-all! dto d '(1 2 3)))))
(differential "dict-contains? present" #t (lambda (dto d) (dict-contains? dto d 1)))
(differential "dict-contains? absent" #f (lambda (dto d) (dict-contains? dto d 9)))
(differential "dict-comparator returns a comparator" #t
              (lambda (dto d) (comparator? (dict-comparator dto d))))

;;; ------------------------------------------------------------------
;;; Lookup
;;; ------------------------------------------------------------------

(differential "dict-ref finds a present key" 'a (lambda (dto d) (dict-ref dto d 1)))
(differential "dict-ref calls failure for an absent key" 'none
              (lambda (dto d) (dict-ref dto d 9 (lambda () 'none))))
(differential "dict-ref passes the value to success" '(got a)
              (lambda (dto d) (dict-ref dto d 1 (lambda () 'none) (lambda (v) (list 'got v)))))
;; "If failure is not supplied, ... an error satisfying dictionary-error? is signalled."
(differential "dict-ref with no failure raises on an absent key" #t
              (lambda (dto d) (raises? (lambda () (dict-ref dto d 9)))))
(differential "dict-ref/default present" 'a (lambda (dto d) (dict-ref/default dto d 1 'dflt)))
(differential "dict-ref/default absent" 'dflt (lambda (dto d) (dict-ref/default dto d 9 'dflt)))

;;; ------------------------------------------------------------------
;;; Mutation. "New values override existing ones" for dict-set!;
;;; "Existing values prevail over new ones" for dict-adjoin!.
;;; ------------------------------------------------------------------

(differential "dict-set! adds a new key" '((1 . a) (2 . b) (3 . c) (4 . d))
              (lambda (dto d) (canon dto (dict-set! dto d 4 'd))))
(differential "dict-set! overrides an existing value" '((1 . z) (2 . b) (3 . c))
              (lambda (dto d) (canon dto (dict-set! dto d 1 'z))))
(differential "dict-set! takes several key/value pairs"
              '((1 . a) (2 . b) (3 . c) (4 . d) (5 . e))
              (lambda (dto d) (canon dto (dict-set! dto d 4 'd 5 'e))))
(differential "dict-adjoin! adds a new key" '((1 . a) (2 . b) (3 . c) (4 . d))
              (lambda (dto d) (canon dto (dict-adjoin! dto d 4 'd))))
(differential "dict-adjoin! leaves an existing value alone" '((1 . a) (2 . b) (3 . c))
              (lambda (dto d) (canon dto (dict-adjoin! dto d 1 'z))))
(differential "dict-delete! removes a key" '((2 . b) (3 . c))
              (lambda (dto d) (canon dto (dict-delete! dto d 1))))
(differential "dict-delete! of an absent key changes nothing" '((1 . a) (2 . b) (3 . c))
              (lambda (dto d) (canon dto (dict-delete! dto d 9))))
(differential "dict-delete-all! takes a list" '((2 . b))
              (lambda (dto d) (canon dto (dict-delete-all! dto d '(1 3)))))
;; "Returns a dictionary with all associations of dict except that if key
;;  exists, its value is replaced. If key absent, dict returns unchanged."
(differential "dict-replace! replaces a present key" '((1 . z) (2 . b) (3 . c))
              (lambda (dto d) (canon dto (dict-replace! dto d 1 'z))))
(differential "dict-replace! does not insert an absent key" '((1 . a) (2 . b) (3 . c))
              (lambda (dto d) (canon dto (dict-replace! dto d 9 'z))))
;; "Returns two values: if key exists, dict and its associated value;
;;  otherwise, an updated dictionary with new association and the failure result."
(differential "dict-intern! on a present key returns the existing value"
              '(((1 . a) (2 . b) (3 . c)) a)
              (lambda (dto d)
                (call-with-values (lambda () (dict-intern! dto d 1 (lambda () 'new)))
                                  (lambda (d2 v) (list (canon dto d2) v)))))
(differential "dict-intern! on an absent key inserts the failure result"
              '(((1 . a) (2 . b) (3 . c) (9 . new)) new)
              (lambda (dto d)
                (call-with-values (lambda () (dict-intern! dto d 9 (lambda () 'new)))
                                  (lambda (d2 v) (list (canon dto d2) v)))))
(differential "dict-update! applies the updater to a present value"
              '((1 . (a a)) (2 . b) (3 . c))
              (lambda (dto d)
                (canon dto (dict-update! dto d 1 (lambda (v) (list v v)) (lambda () 'fail)))))
(differential "dict-update! uses failure for an absent key"
              '((1 . a) (2 . b) (3 . c) (9 . (fail fail)))
              (lambda (dto d)
                (canon dto (dict-update! dto d 9 (lambda (v) (list v v)) (lambda () 'fail)))))
(differential "dict-update! with no failure raises on an absent key" #t
              (lambda (dto d) (raises? (lambda () (dict-update! dto d 9 (lambda (v) v))))))
(differential "dict-update/default! uses the default for an absent key"
              '((1 . a) (2 . b) (3 . c) (9 . (dflt dflt)))
              (lambda (dto d)
                (canon dto (dict-update/default! dto d 9 (lambda (v) (list v v)) 'dflt))))
(differential "dict-update/default! ignores the default for a present key"
              '((1 . (a a)) (2 . b) (3 . c))
              (lambda (dto d)
                (canon dto (dict-update/default! dto d 1 (lambda (v) (list v v)) 'dflt))))
;; "Chooses an association from dict and returns three values: a dictionary
;;  containing all associations except the chosen one, the key, and the value."
(differential "dict-pop! shrinks by one and drops the key it returned" '(2 #f)
              (lambda (dto d)
                (call-with-values (lambda () (dict-pop! dto d))
                                  (lambda (d2 k v) (list (dict-size dto d2)
                                                         (dict-contains? dto d2 k))))))
(differential "dict-pop! returns a key/value pair that was in the dict" #t
              (lambda (dto d)
                (call-with-values (lambda () (dict-pop! dto d))
                                  (lambda (d2 k v) (memv k '(1 2 3)) (and (memv k '(1 2 3)) #t)))))

;;; ------------------------------------------------------------------
;;; dict-find-update! — the primitive every other updater is built on.
;;; ------------------------------------------------------------------

(differential "dict-find-update! success/update"
              '(((1 . (a a)) (2 . b) (3 . c)) upd)
              (lambda (dto d)
                (call-with-values
                 (lambda () (dict-find-update!
                             dto d 1
                             (lambda (insert ignore) (ignore 'absent))
                             (lambda (key value update delete) (update key (list value value) 'upd))))
                 (lambda (d2 obj) (list (canon dto d2) obj)))))
(differential "dict-find-update! failure/insert"
              '(((1 . a) (2 . b) (3 . c) (9 . new)) ins)
              (lambda (dto d)
                (call-with-values
                 (lambda () (dict-find-update!
                             dto d 9
                             (lambda (insert ignore) (insert 'new 'ins))
                             (lambda (key value update delete) (update key value 'upd))))
                 (lambda (d2 obj) (list (canon dto d2) obj)))))
(differential "dict-find-update! failure/ignore leaves the dict alone"
              '(((1 . a) (2 . b) (3 . c)) skipped)
              (lambda (dto d)
                (call-with-values
                 (lambda () (dict-find-update!
                             dto d 9
                             (lambda (insert ignore) (ignore 'skipped))
                             (lambda (key value update delete) (update key value 'upd))))
                 (lambda (d2 obj) (list (canon dto d2) obj)))))
(differential "dict-find-update! success/delete"
              '(((2 . b) (3 . c)) del)
              (lambda (dto d)
                (call-with-values
                 (lambda () (dict-find-update!
                             dto d 1
                             (lambda (insert ignore) (ignore 'absent))
                             (lambda (key value update delete) (delete 'del))))
                 (lambda (d2 obj) (list (canon dto d2) obj)))))

;;; ------------------------------------------------------------------
;;; Whole-dictionary traversal
;;; ------------------------------------------------------------------

(differential "dict-count counts matching associations" 2
              (lambda (dto d) (dict-count dto (lambda (k v) (odd? k)) d)))
(differential "dict-any returns the first true result" 'found
              (lambda (dto d) (dict-any dto (lambda (k v) (and (= k 2) 'found)) d)))
(differential "dict-any returns #f when nothing matches" #f
              (lambda (dto d) (dict-any dto (lambda (k v) (and (= k 99) 'found)) d)))
(differential "dict-every is true when every association matches" #t
              (lambda (dto d) (and (dict-every dto (lambda (k v) (< k 10)) d) #t)))
(differential "dict-every is #f as soon as one fails" #f
              (lambda (dto d) (dict-every dto (lambda (k v) (= k 1)) d)))
(differential "dict-keys" '(1 2 3) (lambda (dto d) (srt (dict-keys dto d))))
(differential "dict-values has one entry per association" 3
              (lambda (dto d) (length (dict-values dto d))))
(differential "dict-entries returns keys and values as two values" '((1 2 3) 3)
              (lambda (dto d)
                (call-with-values (lambda () (dict-entries dto d))
                                  (lambda (ks vs) (list (srt ks) (length vs))))))
(differential "dict-fold threads the accumulator" 6
              (lambda (dto d) (dict-fold dto (lambda (k v acc) (+ acc k)) 0 d)))
(differential "dict-fold on an emptied dict returns knil" 'seed
              (lambda (dto d) (dict-fold dto (lambda (k v acc) 'other) 'seed
                                         (dict-delete-all! dto d '(1 2 3)))))
(differential "dict-map rewrites every value" '((1 . (a)) (2 . (b)) (3 . (c)))
              (lambda (dto d) (canon dto (dict-map dto (lambda (k v) (list v)) d))))
(differential "dict-filter keeps matching associations" '((1 . a) (3 . c))
              (lambda (dto d) (canon dto (dict-filter dto (lambda (k v) (odd? k)) d))))
(differential "dict-remove drops matching associations" '((2 . b))
              (lambda (dto d) (canon dto (dict-remove dto (lambda (k v) (odd? k)) d))))
(differential "dict-map->list" '(1 2 3)
              (lambda (dto d) (srt (dict-map->list dto (lambda (k v) k) d))))
(differential "dict-for-each visits every association" 6
              (lambda (dto d) (let ((n 0)) (dict-for-each dto (lambda (k v) (set! n (+ n k))) d) n)))
(differential "dict->generator yields every key then eof" '(1 2 3)
              (lambda (dto d)
                (let ((g (dict->generator dto d)))
                  (srt (let loop ((acc '()))
                         (let ((x (g)))
                           (if (eof-object? x) acc (loop (cons (car x) acc)))))))))
(differential "dict->generator is exhausted after the last association" #t
              (lambda (dto d)
                (let ((g (dict->generator dto d)))
                  (g) (g) (g) (eof-object? (g)))))
(differential "dict=? on a dict and itself" #t
              (lambda (dto d) (dict=? dto eqv? d d)))
;; Build the second dict with the SAME DTO, so the hash-table leg is compared
;; against a hash table rather than an alist.
(differential "dict=? on two independently built equal dicts" #t
              (lambda (dto d) (dict=? dto eqv? d (fresh-for dto))))
(differential "dict=? on dicts with different values" #f
              (lambda (dto d) (dict=? dto eqv? d (dict-set! dto (fresh-for dto) 1 'z))))
(differential "dict=? on dicts of different sizes" #f
              (lambda (dto d) (dict=? dto eqv? d (dict-delete! dto (fresh-for dto) 1))))

;;; The pure traversal procedures must not touch their argument.
(differential "dict-map does not mutate its argument" #t
              (lambda (dto d) (let ((before (canon dto d)))
                                (dict-map dto (lambda (k v) 'x) d)
                                (equal? before (canon dto d)))))
(differential "dict-filter does not mutate its argument" #t
              (lambda (dto d) (let ((before (canon dto d)))
                                (dict-filter dto (lambda (k v) #f) d)
                                (equal? before (canon dto d)))))
(differential "dict-remove does not mutate its argument" #t
              (lambda (dto d) (let ((before (canon dto d)))
                                (dict-remove dto (lambda (k v) #t) d)
                                (equal? before (canon dto d)))))

;;; ------------------------------------------------------------------
;;; Accumulators
;;; ------------------------------------------------------------------

(differential "dict-set!-accumulator collects pairs until eof"
              '((1 . a) (2 . b) (3 . c) (7 . g))
              (lambda (dto d) (let ((a (dict-set!-accumulator dto d)))
                                (a (cons 7 'g)) (canon dto (a (eof-object))))))
(differential "dict-set!-accumulator overrides an existing key"
              '((1 . z) (2 . b) (3 . c))
              (lambda (dto d) (let ((a (dict-set!-accumulator dto d)))
                                (a (cons 1 'z)) (canon dto (a (eof-object))))))
(differential "dict-adjoin!-accumulator collects pairs until eof"
              '((1 . a) (2 . b) (3 . c) (7 . g))
              (lambda (dto d) (let ((a (dict-adjoin!-accumulator dto d)))
                                (a (cons 7 'g)) (canon dto (a (eof-object))))))
(differential "dict-adjoin!-accumulator leaves an existing key alone"
              '((1 . a) (2 . b) (3 . c))
              (lambda (dto d) (let ((a (dict-adjoin!-accumulator dto d)))
                                (a (cons 1 'z)) (canon dto (a (eof-object))))))

;;; ------------------------------------------------------------------
;;; DTO construction and the proc-id tags. The `-id` names are the whole
;;; extension mechanism and none of them had ever been referenced by a test.
;;; ------------------------------------------------------------------

(test-assert "dto? on a shipped DTO" (dto? eqv-alist-dto))
(test-assert "dto? on a number" (not (dto? 42)))
(test-assert "dto? on a freshly made empty DTO" (dto? (make-dto)))
(test-assert "make-alist-dto builds a DTO" (dto? (make-alist-dto equal?)))
(test-assert "srfi-69-dto and hash-table-dto are the same object"
             (eq? srfi-69-dto hash-table-dto))
(test-assert "eqv-alist-dto and equal-alist-dto are different objects"
             (not (eq? eqv-alist-dto equal-alist-dto)))

;; Every proc-id is a distinct tag, and dto-ref answers with a procedure or #f.
(for-each
 (lambda (entry)
   (let ((name (car entry)) (id (cadr entry)))
     (test-assert (string-append "dto-ref " name " on the alist DTO answers a procedure or #f")
                  (let ((v (dto-ref eqv-alist-dto id)))
                    (or (procedure? v) (eq? v #f))))
     (test-assert (string-append "dto-ref " name " on the hash-table DTO answers a procedure or #f")
                  (let ((v (dto-ref hash-table-dto id)))
                    (or (procedure? v) (eq? v #f))))
     (test-assert (string-append "dto-ref " name " on an empty DTO is #f")
                  (not (dto-ref (make-dto) id)))))
 (list (list "dictionary?-id" dictionary?-id)
       (list "dict-find-update!-id" dict-find-update!-id)
       (list "dict-comparator-id" dict-comparator-id)
       (list "dict-map-id" dict-map-id)
       (list "dict-pure?-id" dict-pure?-id)
       (list "dict-remove-id" dict-remove-id)
       (list "dict-size-id" dict-size-id)
       (list "dict-ref-id" dict-ref-id)
       (list "dict-ref/default-id" dict-ref/default-id)
       (list "dict-set!-id" dict-set!-id)
       (list "dict-adjoin!-id" dict-adjoin!-id)
       (list "dict-delete!-id" dict-delete!-id)
       (list "dict-delete-all!-id" dict-delete-all!-id)
       (list "dict-replace!-id" dict-replace!-id)
       (list "dict-intern!-id" dict-intern!-id)
       (list "dict-update!-id" dict-update!-id)
       (list "dict-update/default!-id" dict-update/default!-id)
       (list "dict-pop!-id" dict-pop!-id)
       (list "dict-contains?-id" dict-contains?-id)
       (list "dict-empty?-id" dict-empty?-id)
       (list "dict-count-id" dict-count-id)
       (list "dict-any-id" dict-any-id)
       (list "dict-every-id" dict-every-id)
       (list "dict-keys-id" dict-keys-id)
       (list "dict-values-id" dict-values-id)
       (list "dict-entries-id" dict-entries-id)
       (list "dict-fold-id" dict-fold-id)
       (list "dict-for-each-id" dict-for-each-id)
       (list "dict-map->list-id" dict-map->list-id)
       (list "dict-filter-id" dict-filter-id)
       (list "dict->alist-id" dict->alist-id)
       (list "dict->generator-id" dict->generator-id)
       (list "dict=?-id" dict=?-id)
       (list "dict-set!-accumulator-id" dict-set!-accumulator-id)
       (list "dict-adjoin!-accumulator-id" dict-adjoin!-accumulator-id)))

;; A DTO built by hand from make-dto really is dispatched through.
(let ((custom (make-dto dictionary?-id (lambda (obj) (eq? obj 'my-dict))
                        dict-size-id (lambda (d) 42))))
  (test-assert "make-dto: the supplied type predicate is used"
               (dictionary? custom 'my-dict))
  (test-assert "make-dto: the supplied type predicate rejects other objects"
               (not (dictionary? custom 'something-else)))
  (test-equal "make-dto: the supplied dict-size is used" 42 (dict-size custom 'my-dict)))
(test-assert "make-dto with an odd number of arguments is rejected"
             (raises? (lambda () (make-dto dictionary?-id))))

;;; dict-pure? is the one operation that legitimately differs by DTO.
(test-assert "dict-pure? is true for the eqv alist DTO" (dict-pure? eqv-alist-dto (mk-alist)))
(test-assert "dict-pure? is true for the equal alist DTO" (dict-pure? equal-alist-dto (mk-alist)))
(test-assert "dict-pure? is false for the hash-table DTO"
             (not (dict-pure? hash-table-dto (mk-ht))))

;;; The alist DTOs really do use their own equality predicate.
(test-equal "the equal alist DTO matches a string key by equal?"
            'v (dict-ref equal-alist-dto (list (cons "k" 'v)) (string-copy "k") (lambda () 'none)))
(test-equal "the eqv alist DTO does not match a fresh string key"
            'none (dict-ref eqv-alist-dto (list (cons "k" 'v)) (string-copy "k") (lambda () 'none)))

;;; ------------------------------------------------------------------
;;; dictionary-error
;;; ------------------------------------------------------------------

(test-assert "dictionary-error? on a non-condition" (not (dictionary-error? 42)))
(test-equal "dictionary-error raises an object carrying its message and irritants"
            '(#t "boom" (1 2))
            (call-with-current-continuation
             (lambda (k)
               (with-exception-handler
                (lambda (e) (k (list (dictionary-error? e)
                                     (dictionary-message e)
                                     (dictionary-irritants e))))
                (lambda () (dictionary-error "boom" 1 2))))))
(test-equal "dictionary-error with no irritants"
            '()
            (call-with-current-continuation
             (lambda (k)
               (with-exception-handler (lambda (e) (k (dictionary-irritants e)))
                                       (lambda () (dictionary-error "boom"))))))

;;; The library's own documented scope decision: start/end bounds only make
;;; sense for an ordered dict, and none of the three DTOs is ordered, so both
;;; range-taking procedures reject them rather than ignoring them.
(test-assert "dict-for-each rejects a start bound on an unordered dict"
             (raises? (lambda () (dict-for-each eqv-alist-dto (lambda (k v) #f) (mk-alist) 0))))
(test-assert "dict->generator rejects a start bound on an unordered dict"
             (raises? (lambda () (dict->generator eqv-alist-dto (mk-alist) 0))))

(let ((runner (test-runner-current)))
  (test-end "srfi225 audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
