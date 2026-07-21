;; SRFI 225 (Dictionaries) conformance tests.
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi225.scm
;;
;; Exercises the generic dict-* API against the two mandatory alist DTOs
;; (eqv-alist-dto, equal-alist-dto), the Kaappi-native hash-table-dto, and a
;; user-supplied DTO built with make-dto (to prove the DTO abstraction
;; itself, not just the shipped instances). Many assertions reproduce the
;; SRFI's own worked examples against '((1 . 2) (3 . 4) (5 . 6)) verbatim.

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 64) (srfi 69) (srfi 128) (srfi 225))

(test-begin "srfi-225")

(define dict '((1 . 2) (3 . 4) (5 . 6)))
(define dto eqv-alist-dto)

;;; --- Predicates -------------------------------------------------------

(test-assert "dictionary? true for an alist" (dictionary? dto dict))
(test-assert "dictionary? false for a non-alist" (not (dictionary? dto 42)))
(test-assert "dictionary? false for an improper list" (not (dictionary? dto '(1 2 3))))
(test-assert "dict-empty? false for non-empty" (not (dict-empty? dto dict)))
(test-assert "dict-empty? true for '()" (dict-empty? dto '()))
(test-assert "dict-contains? true" (dict-contains? dto dict 1))
(test-assert "dict-contains? false" (not (dict-contains? dto dict 99)))
(test-assert "dict=? same content, different order"
  (dict=? dto = dict '((5 . 6) (3 . 4) (1 . 2))))
(test-assert "dict=? different content" (not (dict=? dto = dict '((1 . 2)))))
(test-assert "dict-pure? true for alists" (dict-pure? dto dict))

;;; --- Accessors ----------------------------------------------------------

(test-equal "dict-ref/default found" 2 (dict-ref/default dto dict 1 #f))
(test-equal "dict-ref/default absent" 'none (dict-ref/default dto dict 99 'none))
(test-equal "dict-ref with success transform, spec example"
  '(2) (dict-ref dto dict 1 (lambda () '()) list))
(test-equal "dict-ref default success is identity" 4 (dict-ref dto dict 3))
(test-error "dict-ref signals by default when absent" (dict-ref dto dict 99))
(test-equal "dict-ref custom failure thunk" 'missing (dict-ref dto dict 99 (lambda () 'missing)))
(test-assert "dict-comparator on alist-dto is a comparator or #f"
  (let ((c (dict-comparator dto dict))) (or (not c) (comparator? c))))

;;; --- Update procedures: spec worked examples -----------------------------

(test-equal "dict-adjoin! spec example, new key"
  '((7 . 8) (1 . 2) (3 . 4) (5 . 6))
  (dict-adjoin! dto dict 7 8))
(test-equal "dict-adjoin! existing key: old value wins"
  dict (dict-adjoin! dto dict 3 5))
(test-equal "dict-delete! spec example, multiple keys"
  '((5 . 6)) (dict-delete! dto dict 1 3))
(test-equal "dict-delete! non-matching key is a no-op"
  '((1 . 2) (3 . 4)) (dict-delete! dto '((1 . 2) (3 . 4)) 99))
(test-equal "dict-replace! spec example"
  '((1 . 3) (3 . 4) (5 . 6)) (dict-replace! dto dict 1 3))
(test-equal "dict-replace! absent key is a no-op"
  dict (dict-replace! dto dict 99 'z))

;; dict-set!: new keys go to the front under Kaappi's alist-dto (see the
;; scope note at the top of lib/srfi/225.sld for why this deliberately
;; differs from the spec's own dict-set! example, which appends).
(test-equal "dict-set! new key is prepended"
  '((7 . 8) (1 . 2) (3 . 4) (5 . 6)) (dict-set! dto dict 7 8))
(test-equal "dict-set! existing key replaces and moves to front"
  '((3 . 5) (1 . 2) (5 . 6)) (dict-set! dto dict 3 5))
(test-equal "dict-set! multiple pairs in one call"
  '((20 . 21) (10 . 11) (1 . 2) (3 . 4) (5 . 6))
  (dict-set! dto dict 10 11 20 21))

(test-equal "dict-delete-all! removes every listed key"
  '() (dict-delete-all! dto dict '(1 3 5)))
(test-equal "dict-delete-all! keeps unlisted keys"
  '((3 . 4)) (dict-delete-all! dto dict '(1 5 99)))

;;; --- dict-pop!: spec worked example --------------------------------------

(call-with-values
  (lambda () (dict-pop! dto dict))
  (lambda (new-dict key value)
    (test-equal "dict-pop! new dict" '((3 . 4) (5 . 6)) new-dict)
    (test-equal "dict-pop! key" 1 key)
    (test-equal "dict-pop! value" 2 value)))
(test-error "dict-pop! on an empty dict signals an error" (dict-pop! dto '()))

;;; --- dict-intern! ---------------------------------------------------------

(call-with-values
  (lambda () (dict-intern! dto dict 1 (lambda () 'unused)))
  (lambda (d v) (test-equal "dict-intern! existing key returns existing value" 2 v)))
(call-with-values
  (lambda () (dict-intern! dto dict 42 (lambda () 'fresh)))
  (lambda (d v)
    (test-equal "dict-intern! new key returns failure's value" 'fresh v)
    (test-assert "dict-intern! new key is now present" (dict-contains? dto d 42))))

;;; --- dict-update! / dict-update/default! ---------------------------------

(test-equal "dict-update! applies updater to existing value"
  '((1 . 20)) (dict-update! dto '((1 . 2)) 1 (lambda (v) (* v 10))))
(test-error "dict-update! signals by default when key absent"
  (dict-update! dto '((1 . 2)) 99 (lambda (v) v)))
(test-equal "dict-update! honors an explicit failure thunk"
  '((99 . 0) (1 . 2))
  (dict-update! dto '((1 . 2)) 99 (lambda (v) v) (lambda () 0)))
(test-equal "dict-update/default! existing key"
  '((1 . 20)) (dict-update/default! dto '((1 . 2)) 1 (lambda (v) (* v 10)) 0))
(test-equal "dict-update/default! absent key uses default"
  '((99 . 0) (1 . 2)) (dict-update/default! dto '((1 . 2)) 99 (lambda (v) (* v 10)) 0))

;;; --- dict-map / dict-filter / dict-remove: spec worked examples ----------

(test-equal "dict-map spec example"
  '((1 . -2) (3 . -4) (5 . -6)) (dict-map dto (lambda (k v) (- v)) dict))
(test-equal "dict-filter keeps matching associations"
  '((3 . 4) (5 . 6)) (dict-filter dto (lambda (k v) (> v 3)) dict))
(test-equal "dict-remove drops matching associations"
  '((1 . 2)) (dict-remove dto (lambda (k v) (> v 3)) dict))

;;; --- Whole-dictionary queries ---------------------------------------------

(test-equal "dict-size" 3 (dict-size dto dict))
(test-equal "dict-count" 3 (dict-count dto (lambda (k v) (odd? k)) dict))
(test-equal "dict-count with no matches" 0 (dict-count dto (lambda (k v) (> v 100)) dict))
(test-equal "dict-any first truthy result" 6 (dict-any dto (lambda (k v) (and (> v 5) v)) dict))
(test-assert "dict-any false when nothing matches"
  (not (dict-any dto (lambda (k v) (> v 100)) dict)))
(test-assert "dict-every true when all match" (dict-every dto (lambda (k v) (> v 0)) dict))
(test-assert "dict-every false on first failure"
  (not (dict-every dto (lambda (k v) (> v 3)) dict)))
(test-equal "dict-keys" '(1 3 5) (dict-keys dto dict))
(test-equal "dict-values" '(2 4 6) (dict-values dto dict))
(call-with-values
  (lambda () (dict-entries dto dict))
  (lambda (ks vs)
    (test-equal "dict-entries keys" '(1 3 5) ks)
    (test-equal "dict-entries values" '(2 4 6) vs)))
;; Spec example verbatim: proc is called as (proc key value acc), so passing
;; + directly sums keys, values, and the accumulator together: with entries
;; (1 . 2) and (3 . 4), that's (+ 3 4 (+ 1 2 0)) = 10.
(test-equal "dict-fold spec example" 10 (dict-fold dto + 0 '((1 . 2) (3 . 4))))
(test-equal "dict-fold summing only values" 6 (dict-fold dto (lambda (k v acc) (+ v acc)) 0 '((1 . 2) (3 . 4))))
(test-equal "dict-map->list spec example" '(-1 -1 -1) (dict-map->list dto - dict))
(test-equal "dict->alist spec example" '((1 . 2) (3 . 4) (5 . 6)) (dict->alist dto dict))

;;; --- dict-for-each --------------------------------------------------------

(let ((seen '()))
  (dict-for-each dto (lambda (k v) (set! seen (cons (cons k v) seen))) dict)
  (test-equal "dict-for-each visits every association" dict (reverse seen)))
(test-error "dict-for-each with start on an unordered dict signals an error"
  (dict-for-each dto (lambda (k v) v) dict 1))

;;; --- dict->generator / accumulators (SRFI 158 interop) --------------------

(let ((gen (dict->generator dto '((1 . 2) (3 . 4)))))
  (test-equal "dict->generator yields pairs in order" '(1 . 2) (gen))
  (test-equal "dict->generator second pair" '(3 . 4) (gen))
  (test-assert "dict->generator ends with eof" (eof-object? (gen))))

(let ((acc (dict-set!-accumulator dto '())))
  (acc (cons 1 'a))
  (acc (cons 2 'b))
  (test-equal "dict-set!-accumulator builds a dict" '((2 . b) (1 . a)) (acc (eof-object))))

(let ((acc (dict-adjoin!-accumulator dto '((1 . first)))))
  (acc (cons 1 'ignored))
  (acc (cons 2 'b))
  (test-equal "dict-adjoin!-accumulator keeps first value on conflict"
    '((2 . b) (1 . first)) (acc (eof-object))))

;;; --- eqv vs equal alist DTOs ------------------------------------------

(test-assert "eqv-alist-dto distinguishes non-eqv equal strings"
  (not (dict-contains? eqv-alist-dto (list (cons (string #\a) 1)) "a")))
(test-assert "equal-alist-dto matches equal? keys"
  (dict-contains? equal-alist-dto (list (cons (string #\a) 1)) "a"))

;;; --- make-alist-dto with a custom equality predicate --------------------

(define ci-dto (make-alist-dto (lambda (a b) (string-ci=? a b))))
(test-assert "make-alist-dto: custom equality used for lookup"
  (dict-contains? ci-dto (list (cons "Hello" 1)) "HELLO"))
(test-assert "make-alist-dto: is a dto" (dto? ci-dto))

;;; --- make-dto / dto-ref low-level construction ---------------------------

(test-assert "dto? true for shipped DTOs" (dto? eqv-alist-dto))
(test-assert "dto? false for a non-dto" (not (dto? 42)))
(test-equal "dto-ref retrieves a registered procedure"
  1 ((dto-ref eqv-alist-dto dict-size-id) '((1 . 2))))
(test-assert "dto-ref returns #f for an unregistered id"
  (not (dto-ref (make-dto) 'not-a-real-id)))

;; A from-scratch DTO supplying only the 7 required procedures must still
;; get full behavior (dict-ref, dict-set!, dict-for-each, dict-fold, ...)
;; through this library's generic fallbacks.
(define minimal-dto
  (make-dto
    dictionary?-id (lambda (obj) (and (list? obj) (or (null? obj) (pair? (car obj)))))
    dict-pure?-id (lambda (dict) #t)
    dict-size-id (lambda (dict) (length dict))
    dict-comparator-id (lambda (dict) #f)
    dict-map-id (lambda (proc dict) (map (lambda (kv) (cons (car kv) (proc (car kv) (cdr kv)))) dict))
    dict-remove-id
    (lambda (pred dict)
      (let loop ((lst dict) (acc '()))
        (cond ((null? lst) (reverse acc))
              ((pred (caar lst) (cdar lst)) (loop (cdr lst) acc))
              (else (loop (cdr lst) (cons (car lst) acc))))))
    dict-find-update!-id
    (lambda (dict key failure success)
      (let loop ((lst dict) (acc '()))
        (cond
          ((null? lst)
           (failure (lambda (value carry) (values (cons (cons key value) dict) carry))
                    (lambda (carry) (values dict carry))))
          ((equal? (caar lst) key)
           (success (caar lst) (cdar lst)
             (lambda (nk nv carry) (values (cons (cons nk nv) (append (reverse acc) (cdr lst))) carry))
             (lambda (carry) (values (append (reverse acc) (cdr lst)) carry))))
          (else (loop (cdr lst) (cons (car lst) acc))))))))

(test-assert "minimal DTO: dictionary?" (dictionary? minimal-dto '((1 . 2))))
(test-equal "minimal DTO: dict-ref derived from dict-find-update!"
  2 (dict-ref minimal-dto '((1 . 2)) 1))
(test-equal "minimal DTO: dict-set! derived from dict-find-update!"
  '((3 . 4) (1 . 2)) (dict-set! minimal-dto '((1 . 2)) 3 4))
(test-equal "minimal DTO: dict-contains? derived from dict-find-update!"
  #t (dict-contains? minimal-dto '((1 . 2)) 1))
(let ((seen '()))
  (dict-for-each minimal-dto (lambda (k v) (set! seen (cons (cons k v) seen))) '((1 . 2) (3 . 4)))
  (test-equal "minimal DTO: dict-for-each derived from dict-map"
    '((1 . 2) (3 . 4)) (reverse seen)))
(test-equal "minimal DTO: dict-fold derived from dict-for-each"
  6 (dict-fold minimal-dto (lambda (k v acc) (+ v acc)) 0 '((1 . 2) (3 . 4))))
(test-equal "minimal DTO: dict-keys derived"
  '(1 3) (dict-keys minimal-dto '((1 . 2) (3 . 4))))
(test-equal "minimal DTO: dict-filter derived from dict-remove"
  '((3 . 4)) (dict-filter minimal-dto (lambda (k v) (> v 2)) '((1 . 2) (3 . 4))))
(test-equal "minimal DTO: dict-pop! derived from dict-for-each + dict-delete!"
  '(1 2)
  (call-with-values (lambda () (dict-pop! minimal-dto '((1 . 2) (3 . 4))))
    (lambda (d k v) (list k v))))
(test-equal "minimal DTO: dict-intern! new key"
  'z (call-with-values (lambda () (dict-intern! minimal-dto '((1 . 2)) 9 (lambda () 'z)))
       (lambda (d v) v)))
(test-assert "minimal DTO: dict=? against itself"
  (dict=? minimal-dto = '((1 . 2) (3 . 4)) '((3 . 4) (1 . 2))))

;;; --- hash-table-dto (impure) ----------------------------------------------

(define ht (make-hash-table))
(hash-table-set! ht 'a 1)
(hash-table-set! ht 'b 2)
(hash-table-set! ht 'c 3)

(test-assert "hash-table-dto: dictionary?" (dictionary? hash-table-dto ht))
(test-assert "hash-table-dto: not pure" (not (dict-pure? hash-table-dto ht)))
(test-equal "hash-table-dto: dict-size" 3 (dict-size hash-table-dto ht))
(test-assert "hash-table-dto: dict-contains?" (dict-contains? hash-table-dto ht 'a))
(test-equal "hash-table-dto: dict-ref" 1 (dict-ref hash-table-dto ht 'a))
(test-equal "hash-table-dto: dict-ref/default absent" 'none (dict-ref/default hash-table-dto ht 'z 'none))

(test-assert "hash-table-dto: dict-set! returns the same table (impure)"
  (eq? ht (dict-set! hash-table-dto ht 'd 4)))
(test-equal "hash-table-dto: dict-set! mutates in place" 4 (dict-size hash-table-dto ht))

(test-assert "hash-table-dto: dict-delete! removes the key"
  (begin (dict-delete! hash-table-dto ht 'd)
         (not (dict-contains? hash-table-dto ht 'd))))

(test-equal "hash-table-dto: dict-fold sums values"
  (+ 1 2 3) (dict-fold hash-table-dto (lambda (k v acc) (+ v acc)) 0 ht))

(let ((alist (dict->alist hash-table-dto ht)))
  (test-equal "hash-table-dto: dict->alist length" 3 (length alist))
  (test-equal "hash-table-dto: dict->alist has 'a" 1 (cdr (assq 'a alist))))

(test-error "hash-table-dto: dict-for-each with start signals an error"
  (dict-for-each hash-table-dto (lambda (k v) v) ht 'a))

;; srfi-69-dto is Kaappi's alias for the same DTO (one native hash-table type).
(test-assert "srfi-69-dto is the same DTO object as hash-table-dto"
  (eq? srfi-69-dto hash-table-dto))

;;; --- dictionary-error -------------------------------------------------

(test-assert "dictionary-error signals an object satisfying dictionary-error?"
  (guard (e ((dictionary-error? e) #t) (else #f))
    (dictionary-error "boom" 1 2)
    #f))
(test-equal "dictionary-message" "boom"
  (guard (e ((dictionary-error? e) (dictionary-message e)))
    (dictionary-error "boom" 1 2)))
(test-equal "dictionary-irritants" '(1 2)
  (guard (e ((dictionary-error? e) (dictionary-irritants e)))
    (dictionary-error "boom" 1 2)))

(let ((runner (test-runner-current)))
  (test-end "srfi-225")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
