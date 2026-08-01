;; Audit tests for src/primitives_hashtable.zig — SRFI-69 hash tables.
;; Audit campaign v2 Phase 2.8 (#1890); originally Phase 2.11 (#1137).
;; Run directly and read the printed counts — run-all.sh only sees exit codes.
;;
;; Every assertion carries a name string: an unnamed SRFI-64 failure on a
;; remote CI leg prints a bare #f and says nothing about what broke.
;;
;; Two standing portability rules for this file:
;;   * never assert a hash *value* that is derived from a pointer or from
;;     `usize` (32-bit on wasm32, and s390x is big-endian) — assert the
;;     spec's invariants instead;
;;   * never assert hash-table iteration *order*; SRFI 69 guarantees none.
;;     Compare sorted key lists or sums.

(import (scheme base) (scheme write) (srfi 69))
(import (scheme process-context) (srfi 64) (srfi 18))

(test-begin "primitives_hashtable audit")

;;; --- helpers ---------------------------------------------------------

(define (sort-nums lst)
  (if (null? lst)
      '()
      (let ((p (car lst)))
        (append (sort-nums (filter-lt lst p)) (list p) (sort-nums (filter-ge (cdr lst) p))))))
(define (filter-lt lst p)
  (cond ((null? lst) '()) ((< (car lst) p) (cons (car lst) (filter-lt (cdr lst) p)))
        (else (filter-lt (cdr lst) p))))
(define (filter-ge lst p)
  (cond ((null? lst) '()) ((>= (car lst) p) (cons (car lst) (filter-ge (cdr lst) p)))
        (else (filter-ge (cdr lst) p))))

(define (iota-list n) (let loop ((i (- n 1)) (acc '())) (if (< i 0) acc (loop (- i 1) (cons i acc)))))

;; Build a fresh n-element list every call, so the key is never `eq?` to a
;; stored one — that is the whole point of an `equal?` table.
(define (mk n tag) (let loop ((i 0) (acc (list tag))) (if (= i n) acc (loop (+ i 1) (cons i acc)))))

(define (misses ht keyfn n)
  (let loop ((i 0) (m 0))
    (if (= i n) m (loop (+ i 1) (if (eq? 'MISS (hash-table-ref/default ht (keyfn i) 'MISS)) (+ m 1) m)))))

(define (caught thunk) (guard (e (#t 'caught)) (thunk)))
(define (msg-of thunk)
  (guard (e (#t (if (error-object? e) (error-object-message e) (list 'raised e)))) (thunk)))

;;; --- constructors and predicate --------------------------------------

(test-equal "hash-table? on a fresh table" #t (hash-table? (make-hash-table)))
(test-equal "hash-table? on an alist" #f (hash-table? '((a . 1))))
(test-equal "hash-table? on a vector" #f (hash-table? #(1 2)))
(test-equal "hash-table? on a string" #f (hash-table? "ht"))
(test-equal "fresh table has size 0" 0 (hash-table-size (make-hash-table)))
(test-equal "make-hash-table accepts an equivalence proc" #t
            (hash-table? (make-hash-table eq?)))
(test-equal "make-hash-table accepts equivalence + hash procs" #t
            (hash-table? (make-hash-table eq? hash-by-identity)))

;;; --- set! / ref / ref/default ----------------------------------------

(test-equal "set! then ref" 'v
            (let ((ht (make-hash-table))) (hash-table-set! ht 'k 'v) (hash-table-ref ht 'k)))
(test-equal "set! twice overwrites the value" 'new
            (let ((ht (make-hash-table)))
              (hash-table-set! ht 'k 'old) (hash-table-set! ht 'k 'new) (hash-table-ref ht 'k)))
(test-equal "set! twice leaves size at 1" 1
            (let ((ht (make-hash-table)))
              (hash-table-set! ht 'k 'old) (hash-table-set! ht 'k 'new) (hash-table-size ht)))
(test-equal "ref calls the failure thunk when absent" 'from-thunk
            (hash-table-ref (make-hash-table) 'missing (lambda () 'from-thunk)))
(test-equal "ref returns a non-procedure third argument as-is" 'plain
            (hash-table-ref (make-hash-table) 'missing 'plain))
(test-equal "ref/default returns the default when absent" 'dflt
            (hash-table-ref/default (make-hash-table) 'missing 'dflt))
(test-equal "ref/default returns a stored #f, not the default" #f
            (let ((ht (make-hash-table))) (hash-table-set! ht 'k #f)
                 (hash-table-ref/default ht 'k 'dflt)))
;; SRFI 69: "if thunk is not given, an error is signalled"
(test-equal "ref with no thunk on an absent key raises" 'caught
            (caught (lambda () (hash-table-ref (make-hash-table) 'missing))))
(test-equal "an error raised by the failure thunk propagates" 'caught
            (caught (lambda () (hash-table-ref (make-hash-table) 'missing (lambda () (error "boom"))))))
(test-equal "ref on a non-table raises" 'caught
            (caught (lambda () (hash-table-ref '((a . 1)) 'a))))
(test-equal "set! on a non-table raises" 'caught
            (caught (lambda () (hash-table-set! "not-ht" 'k 'v))))
(test-equal "ref/default on a non-table raises" 'caught
            (caught (lambda () (hash-table-ref/default 42 'k 'd))))

;;; --- key-type coverage: hash and equality must agree ------------------
;;; SRFI 69: "a hash funtion hash is acceptable iff (e obj1 obj2) ->
;;; (= (hash obj1) (hash obj2))". Every key below is rebuilt for the
;;; lookup, so a table that hashes by pointer fails these.

(test-equal "string key found via an equal? copy" 'v
            (let ((ht (make-hash-table))) (hash-table-set! ht "key" 'v)
                 (hash-table-ref/default ht (string-copy "key") 'missing)))
(test-equal "char key" 'v
            (let ((ht (make-hash-table))) (hash-table-set! ht #\x 'v)
                 (hash-table-ref/default ht #\x 'missing)))
(test-equal "fixnum key" 'v
            (let ((ht (make-hash-table))) (hash-table-set! ht 42 'v)
                 (hash-table-ref/default ht 42 'missing)))
(test-equal "flonum key" 'v
            (let ((ht (make-hash-table))) (hash-table-set! ht 1.5 'v)
                 (hash-table-ref/default ht 1.5 'missing)))
(test-equal "boolean key" 'v
            (let ((ht (make-hash-table))) (hash-table-set! ht #t 'v)
                 (hash-table-ref/default ht #t 'missing)))
(test-equal "empty-list key" 'v
            (let ((ht (make-hash-table))) (hash-table-set! ht '() 'v)
                 (hash-table-ref/default ht '() 'missing)))
(test-equal "eof-object key" 'v
            (let ((ht (make-hash-table))) (hash-table-set! ht (eof-object) 'v)
                 (hash-table-ref/default ht (eof-object) 'missing)))
(test-equal "unspecified-value key" 'v
            (let ((ht (make-hash-table))) (hash-table-set! ht (if #f #f) 'v)
                 (hash-table-ref/default ht (if #f #f) 'missing)))
(test-equal "shallow pair key" 'v
            (let ((ht (make-hash-table))) (hash-table-set! ht (list 1 2) 'v)
                 (hash-table-ref/default ht (list 1 2) 'missing)))
(test-equal "vector key" 'v
            (let ((ht (make-hash-table))) (hash-table-set! ht (vector 1 "a") 'v)
                 (hash-table-ref/default ht (vector 1 "a") 'missing)))
(test-equal "long vector key (past the 4-element hash sample)" 'v
            (let ((ht (make-hash-table))) (hash-table-set! ht (make-vector 12 'z) 'v)
                 (hash-table-ref/default ht (make-vector 12 'z) 'missing)))
(test-equal "bytevector key" 'v
            (let ((ht (make-hash-table))) (hash-table-set! ht (bytevector 1 2) 'v)
                 (hash-table-ref/default ht (bytevector 1 2) 'missing)))
(test-equal "the table itself as a key" 'self
            (let ((ht (make-hash-table))) (hash-table-set! ht ht 'self)
                 (hash-table-ref/default ht ht 'missing)))
(test-equal "storing a cyclic key does not hang" 'stored
            (let ((ht (make-hash-table)) (c (list 1 2 3)))
              (set-cdr! (cddr c) c) (hash-table-set! ht c 'cyc) 'stored))

;; #1180 regression: heap-boxed numeric keys used to hash by pointer while
;; lookup compared by equal?, so entries became unfindable once the table
;; grew past one bucket-group.
(test-equal "30 bignum keys all findable (#1180)" 0
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 30)) (hash-table-set! ht (+ (expt 2 100) i) i))
              (misses ht (lambda (i) (+ (expt 2 100) i)) 30)))
(test-equal "30 rational keys all findable (#1180)" 0
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 30)) (hash-table-set! ht (/ 1 (+ i 3)) i))
              (misses ht (lambda (i) (/ 1 (+ i 3))) 30)))
(test-equal "30 complex keys all findable" 0
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 30)) (hash-table-set! ht (make-rectangular i 1.5) i))
              (misses ht (lambda (i) (make-rectangular i 1.5)) 30)))

;; The structural-hash cliff. Keys of 1..8 cons cells hash consistently;
;; the 9th cell sits at MAX_HASH_DEPTH and is hashed by pointer instead.
(test-equal "8-element list keys all findable (control for #2023)" 0
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 200)) (hash-table-set! ht (mk 7 i) i))
              (misses ht (lambda (i) (mk 7 i)) 200)))
(test-equal "equal? 8-element lists hash alike (control for #2023)" #t
            (= (hash (mk 7 'x)) (hash (mk 7 'x))))
;; FAIL: #2023 (equal? keys nested deeper than 8 hash by pointer, so a
;; 9-or-more-element list key is unfindable once the table has grown)
;; (test-equal "equal? 9-element lists hash alike (#2023)" #t
;;             (= (hash (mk 8 'x)) (hash (mk 8 'x))))
;; (test-equal "12-element list keys all findable (#2023)" 0
;;             (let ((ht (make-hash-table)))
;;               (do ((i 0 (+ i 1))) ((= i 200)) (hash-table-set! ht (mk 11 i) i))
;;               (misses ht (lambda (i) (mk 11 i)) 200)))
;; (test-equal "exists? agrees with equal? on 200 deep keys (#2023)" 200
;;             (let ((ht (make-hash-table)))
;;               (do ((i 0 (+ i 1))) ((= i 200)) (hash-table-set! ht (mk 11 i) i))
;;               (let loop ((i 0) (n 0))
;;                 (if (= i 200) n (loop (+ i 1) (if (hash-table-exists? ht (mk 11 i)) (+ n 1) n))))))

;;; --- growth and capacity ----------------------------------------------

(test-equal "100 fixnum keys stay findable across growth" 0
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 100)) (hash-table-set! ht i (* i i)))
              (misses ht (lambda (i) i) 100)))
(test-equal "100 inserts give size 100" 100
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 100)) (hash-table-set! ht i i))
              (hash-table-size ht)))
(test-equal "1000 string keys stay findable across many growths" 0
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 1000)) (hash-table-set! ht (number->string i) i))
              (misses ht (lambda (i) (number->string i)) 1000)))
(test-equal "size never exceeds the number of distinct keys" 500
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 500)) (hash-table-set! ht i i))
              (do ((i 0 (+ i 1))) ((= i 500)) (hash-table-set! ht i (- i)))
              (hash-table-size ht)))
;; Tombstones must not accumulate into an unbounded probe: 50k set/delete
;; cycles on a table that never grows past its initial capacity.
(test-equal "50k set/delete cycles leave a usable table" '(0 ok)
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 50000))
                (hash-table-set! ht i i) (hash-table-delete! ht i))
              (hash-table-set! ht 'final 'ok)
              (hash-table-delete! ht 'final)
              (hash-table-set! ht 'final 'ok)
              (list (- (hash-table-size ht) 1) (hash-table-ref/default ht 'final 'MISS))))

;;; --- exists? / delete! ------------------------------------------------

(test-equal "exists? finds a present key" #t
            (let ((ht (make-hash-table))) (hash-table-set! ht 'k 'v) (hash-table-exists? ht 'k)))
(test-equal "exists? on an empty table" #f (hash-table-exists? (make-hash-table) 'k))
(test-equal "delete! removes the key and decrements size" '(#f 0)
            (let ((ht (make-hash-table)))
              (hash-table-set! ht 'k 'v) (hash-table-delete! ht 'k)
              (list (hash-table-exists? ht 'k) (hash-table-size ht))))
(test-equal "delete! of a missing key is a no-op" 1
            (let ((ht (make-hash-table)))
              (hash-table-set! ht 'k 'v) (hash-table-delete! ht 'other) (hash-table-size ht)))
(test-equal "delete! then re-insert reuses the tombstone" 'v2
            (let ((ht (make-hash-table)))
              (hash-table-set! ht 'k 'v1) (hash-table-delete! ht 'k)
              (hash-table-set! ht 'k 'v2) (hash-table-ref ht 'k)))
(test-equal "deleting every key of a grown table empties it" 0
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 200)) (hash-table-set! ht i i))
              (do ((i 0 (+ i 1))) ((= i 200)) (hash-table-delete! ht i))
              (hash-table-size ht)))
(test-equal "size never goes negative after redundant deletes" 0
            (let ((ht (make-hash-table)))
              (hash-table-set! ht 'k 'v)
              (do ((i 0 (+ i 1))) ((= i 10)) (hash-table-delete! ht 'k))
              (hash-table-size ht)))
(test-equal "delete! on a non-table raises" 'caught
            (caught (lambda () (hash-table-delete! '() 'k))))

;;; --- keys / values / ->alist (set semantics; order is not specified) ---

(test-equal "keys returns every key, sorted for comparison" '(0 1 2 3 4)
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 5)) (hash-table-set! ht i (* i 10)))
              (sort-nums (hash-table-keys ht))))
(test-equal "values returns every value, sorted for comparison" '(0 10 20 30 40)
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 5)) (hash-table-set! ht i (* i 10)))
              (sort-nums (hash-table-values ht))))
(test-equal "keys length matches size after growth" 300
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 300)) (hash-table-set! ht i i))
              (length (hash-table-keys ht))))
(test-equal "keys of an empty table" '() (hash-table-keys (make-hash-table)))
(test-equal "values of an empty table" '() (hash-table-values (make-hash-table)))
(test-equal "->alist of a one-entry table" '((k . v))
            (let ((ht (make-hash-table))) (hash-table-set! ht 'k 'v) (hash-table->alist ht)))
(test-equal "->alist of an empty table" '() (hash-table->alist (make-hash-table)))
(test-equal "->alist car/cdr sums match the entries" '(10 100)
            (let ((ht (make-hash-table)) (ks 0) (vs 0))
              (do ((i 0 (+ i 1))) ((= i 5)) (hash-table-set! ht i (* i 10)))
              (for-each (lambda (p) (set! ks (+ ks (car p))) (set! vs (+ vs (cdr p))))
                        (hash-table->alist ht))
              (list ks vs)))
(test-equal "keys after deletions excludes the deleted ones" '(3 4)
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 5)) (hash-table-set! ht i i))
              (do ((i 0 (+ i 1))) ((= i 3)) (hash-table-delete! ht i))
              (sort-nums (hash-table-keys ht))))

;;; --- alist->hash-table -------------------------------------------------

(test-equal "alist->hash-table size" 2 (hash-table-size (alist->hash-table '((a . 1) (b . 2)))))
;; SRFI 69: earlier associations take precedence
(test-equal "earlier associations win" 1 (hash-table-ref (alist->hash-table '((k . 1) (k . 2))) 'k))
(test-equal "empty alist" 0 (hash-table-size (alist->hash-table '())))
(test-equal "12 entries (non-power-of-two count) all retrievable" '(12 12 1)
            (let ((ht (alist->hash-table '((a . 1) (b . 2) (c . 3) (d . 4) (e . 5) (f . 6)
                                           (g . 7) (h . 8) (i . 9) (j . 10) (k . 11) (l . 12)))))
              (list (hash-table-size ht)
                    (hash-table-ref/default ht 'l 'missing)
                    (hash-table-ref/default ht 'a 'missing))))
;; The initial capacity is max(count, 8) rounded up to a power of two, and
;; this path never calls growIfNeeded — a 500-entry alist exercises that.
(test-equal "500-entry alist: all entries findable, none lost" '(500 0)
            (let* ((al (let loop ((i 0) (acc '())) (if (= i 500) acc (loop (+ i 1) (cons (cons i i) acc)))))
                   (ht (alist->hash-table al)))
              (list (hash-table-size ht) (misses ht (lambda (i) i) 500))))
(test-equal "alist->hash-table with a custom equivalence proc" 2
            (hash-table-size (alist->hash-table (list (cons (string #\a) 1) (cons (string #\a) 2)) eq?)))
(test-equal "non-pair element raises" 'caught (caught (lambda () (alist->hash-table '(not-a-pair)))))
(test-equal "non-list argument raises" 'caught (caught (lambda () (alist->hash-table 42))))
(test-equal "improper alist tail raises" 'caught (caught (lambda () (alist->hash-table '((a . 1) . 2)))))

;;; --- walk: callback site 4 --------------------------------------------

(test-equal "walk visits every entry once" 6
            (let ((ht (make-hash-table)) (sum 0))
              (hash-table-set! ht 'a 1) (hash-table-set! ht 'b 2) (hash-table-set! ht 'c 3)
              (hash-table-walk ht (lambda (k v) (set! sum (+ sum v)))) sum))
(test-equal "walk over an empty table calls nothing" 0
            (let ((n 0)) (hash-table-walk (make-hash-table) (lambda (k v) (set! n (+ n 1)))) n))
(test-equal "walk sees the key/value pairing, not a shuffle" 0
            (let ((ht (make-hash-table)) (bad 0))
              (do ((i 0 (+ i 1))) ((= i 50)) (hash-table-set! ht i (* i 3)))
              (hash-table-walk ht (lambda (k v) (if (not (= v (* k 3))) (set! bad (+ bad 1)))))
              bad))
(test-equal "an error raised in the walk callback propagates" 'caught
            (caught (lambda () (let ((ht (make-hash-table)))
                                 (hash-table-set! ht 'k 'v)
                                 (hash-table-walk ht (lambda (k v) (error "boom")))))))
(test-equal "the table is intact and usable after a walk callback raises" '(10 ok)
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 10)) (hash-table-set! ht i i))
              (caught (lambda () (hash-table-walk ht (lambda (k v) (raise 'boom)))))
              (hash-table-set! ht 'z 'ok)
              (list (- (hash-table-size ht) 1) (hash-table-ref/default ht 'z 'MISS))))
;; Snapshot semantics: a callback that mutates the table sees the mutation
;; afterwards, but the iteration itself is over the pre-call entry set.
(test-equal "inserting during a walk does not extend the walk" 3
            (let ((ht (make-hash-table)) (seen 0))
              (hash-table-set! ht 'a 1) (hash-table-set! ht 'b 2) (hash-table-set! ht 'c 3)
              (hash-table-walk ht (lambda (k v) (hash-table-set! ht (list k) v) (set! seen (+ seen 1))))
              seen))
(test-equal "inserting enough during a walk to force a rehash is safe" '(5 205)
            (let ((ht (make-hash-table)) (seen 0))
              (do ((i 0 (+ i 1))) ((= i 5)) (hash-table-set! ht i i))
              (hash-table-walk ht (lambda (k v)
                                    (set! seen (+ seen 1))
                                    (do ((j 0 (+ j 1))) ((= j 40))
                                      (hash-table-set! ht (+ 1000 (* k 100) j) j))))
              (list seen (hash-table-size ht))))
(test-equal "deleting every key from inside a walk still visits them all" '(20 0)
            (let ((ht (make-hash-table)) (seen 0))
              (do ((i 0 (+ i 1))) ((= i 20)) (hash-table-set! ht i i))
              (hash-table-walk ht (lambda (k v) (set! seen (+ seen 1)) (hash-table-delete! ht k)))
              (list seen (hash-table-size ht))))
;; #1181 regression: the snapshot's keys/values must be rooted, or GC frees
;; a not-yet-visited entry when the callback deletes and then allocates.
(test-equal "walk snapshot keys survive delete-then-allocate (#1181)" '(435 0)
            (let ((ht (make-hash-table)) (sum 0) (bad 0))
              (do ((i 0 (+ i 1))) ((= i 30)) (hash-table-set! ht (cons i 'key) (cons i 'val)))
              (hash-table-walk ht
                (lambda (k v)
                  (do ((j 0 (+ j 1))) ((= j 30)) (hash-table-delete! ht (cons j 'key)))
                  (do ((j 0 (+ j 1))) ((= j 100)) (cons j (make-vector 4 j)))
                  (if (and (pair? k) (pair? v) (eq? (cdr k) 'key) (eq? (cdr v) 'val) (= (car k) (car v)))
                      (set! sum (+ sum (car k)))
                      (set! bad (+ bad 1)))))
              (list sum bad)))
(test-equal "walk with a non-procedure raises" 'caught
            (caught (lambda () (let ((ht (make-hash-table)))
                                 (hash-table-set! ht 'a 1)
                                 (hash-table-walk ht 42)))))
(test-equal "walk with a wrong-arity procedure raises" 'caught
            (caught (lambda () (let ((ht (make-hash-table)))
                                 (hash-table-set! ht 'a 1)
                                 (hash-table-walk ht (lambda (x) x))))))
(test-equal "walk on a non-table raises" 'caught
            (caught (lambda () (hash-table-walk '() (lambda (k v) k)))))

;;; --- fold: callback site 8 --------------------------------------------

(test-equal "fold sums the values" 6
            (let ((ht (make-hash-table)))
              (hash-table-set! ht 'a 1) (hash-table-set! ht 'b 2) (hash-table-set! ht 'c 3)
              (hash-table-fold ht (lambda (k v acc) (+ acc v)) 0)))
(test-equal "fold over an empty table returns the seed" 'seed
            (hash-table-fold (make-hash-table) (lambda (k v acc) 'other) 'seed))
(test-equal "fold threads the accumulator through every entry" 100
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 100)) (hash-table-set! ht i i))
              (hash-table-fold ht (lambda (k v acc) (+ acc 1)) 0)))
(test-equal "an error raised in the fold callback propagates" 'caught
            (caught (lambda () (let ((ht (make-hash-table)))
                                 (hash-table-set! ht 'k 'v)
                                 (hash-table-fold ht (lambda (k v acc) (error "boom")) 0)))))
(test-equal "mutating during a fold is safe and the fold uses the snapshot" '(6 180)
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 6)) (hash-table-set! ht i i))
              (let ((n (hash-table-fold ht (lambda (k v a)
                                             (hash-table-delete! ht k)
                                             (do ((j 0 (+ j 1))) ((= j 30))
                                               (hash-table-set! ht (list 'x k j) j))
                                             (+ a 1))
                                        0)))
                (list n (hash-table-size ht)))))
(test-equal "fold accumulator survives allocation in the callback" 435
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 30)) (hash-table-set! ht (cons i 'k) i))
              (hash-table-fold ht (lambda (k v acc)
                                    (do ((j 0 (+ j 1))) ((= j 50)) (make-vector 8 j))
                                    (+ acc v))
                               0)))
(test-equal "fold with a non-procedure raises" 'caught
            (caught (lambda () (let ((ht (make-hash-table)))
                                 (hash-table-set! ht 'a 1)
                                 (hash-table-fold ht 42 0)))))
(test-equal "fold with a wrong-arity procedure raises" 'caught
            (caught (lambda () (let ((ht (make-hash-table)))
                                 (hash-table-set! ht 'a 1)
                                 (hash-table-fold ht (lambda (x) x) 0)))))

;;; --- update! / update!/default / ref thunk: callback sites 3, 5, 6, 7 --

(test-equal "update!/default on a present key" 11
            (let ((ht (make-hash-table))) (hash-table-set! ht 'k 10)
                 (hash-table-update!/default ht 'k (lambda (x) (+ x 1)) 0)
                 (hash-table-ref ht 'k)))
(test-equal "update!/default on an absent key uses the default" 1
            (let ((ht (make-hash-table)))
              (hash-table-update!/default ht 'k (lambda (x) (+ x 1)) 0)
              (hash-table-ref ht 'k)))
(test-equal "update!/default on an absent key increments size" 1
            (let ((ht (make-hash-table)))
              (hash-table-update!/default ht 'k (lambda (x) x) 0) (hash-table-size ht)))
(test-equal "an error raised in the update!/default proc propagates" 'caught
            (caught (lambda () (hash-table-update!/default (make-hash-table) 'k
                                                           (lambda (x) (error "boom")) 0))))
(test-equal "update! on a present key" 11
            (let ((ht (make-hash-table))) (hash-table-set! ht 'k 10)
                 (hash-table-update! ht 'k (lambda (x) (+ x 1))) (hash-table-ref ht 'k)))
(test-equal "update! on an absent key with no thunk raises" 'caught
            (caught (lambda () (hash-table-update! (make-hash-table) 'k (lambda (x) x)))))
(test-equal "update! on an absent key uses the supplied thunk" 6
            (let ((ht (make-hash-table)))
              (hash-table-update! ht 'k (lambda (x) (+ x 1)) (lambda () 5))
              (hash-table-ref ht 'k)))
(test-equal "an error raised in the update! thunk propagates" 'caught
            (caught (lambda () (hash-table-update! (make-hash-table) 'k
                                                   (lambda (x) x) (lambda () (error "boom"))))))
;; The update proc runs between findKey and findSlot, so it can move the
;; entry out from under the pending write.
(test-equal "an update! proc that deletes its own key still stores the result" '(1 101)
            (let ((ht (make-hash-table)))
              (hash-table-set! ht 'k 1)
              (hash-table-update! ht 'k (lambda (old) (hash-table-delete! ht 'k) (+ old 100)))
              (list (hash-table-size ht) (hash-table-ref/default ht 'k 'MISS))))
(test-equal "an update!/default proc that forces a rehash keeps the entry" '(41 101)
            (let ((ht (make-hash-table)))
              (hash-table-set! ht 'k 1)
              (hash-table-update!/default ht 'k
                (lambda (old) (do ((j 0 (+ j 1))) ((= j 40)) (hash-table-set! ht j j)) (+ old 100))
                0)
              (list (hash-table-size ht) (hash-table-ref/default ht 'k 'MISS))))
(test-equal "a ref failure thunk may populate the table" '(thunked 30)
            (let ((ht (make-hash-table)))
              (let ((r (hash-table-ref ht 'zz (lambda ()
                                                (do ((j 0 (+ j 1))) ((= j 30)) (hash-table-set! ht j j))
                                                'thunked))))
                (list r (hash-table-size ht)))))
(test-equal "update! on a non-table raises" 'caught
            (caught (lambda () (hash-table-update! 5 'k (lambda (x) x)))))

;;; --- custom equivalence and hash: callback sites 1 and 2 --------------

;; #1183: custom equivalence/hash functions are honored
(test-equal "an eq? table keeps two equal? but distinct string keys apart (#1183)" 2
            (let ((ht (make-hash-table eq?)))
              (hash-table-set! ht (string #\a) 'first)
              (hash-table-set! ht (string #\a) 'second)
              (hash-table-size ht)))
(test-equal "equivalence-function reports the proc that was supplied (#1183)" #t
            (eq? eq? (hash-table-equivalence-function (make-hash-table eq?))))
(test-equal "a string=? table finds an equal? copy" 'v
            (let ((ht (make-hash-table string=?)))
              (hash-table-set! ht "key" 'v)
              (hash-table-ref/default ht (string-copy "key") 'missing)))
(test-equal "a string-ci=? table folds case" 'v
            (let ((ht (make-hash-table string-ci=?)))
              (hash-table-set! ht "KeY" 'v)
              (hash-table-ref/default ht "kEy" 'missing)))
(test-equal "a string=? table rejects a non-string key" 'caught
            (caught (lambda () (hash-table-set! (make-hash-table string=?) 1 2))))
(test-equal "a fully custom equivalence + hash pair works across growth" 0
            (let ((ht (make-hash-table (lambda (a b) (equal? a b))
                                       (lambda (k) (if (number? k) (modulo k 16) 3)))))
              (do ((i 0 (+ i 1))) ((= i 200)) (hash-table-set! ht i i))
              (misses ht (lambda (i) i) 200)))
;; The custom-hash arm accepts whatever the procedure returns: a fixnum is
;; folded to its magnitude, anything else is hashed structurally. None of
;; these should lose entries, because each is at least *consistent*.
(test-equal "custom hash returning a negative fixnum loses nothing" 0
            (let ((ht (make-hash-table = (lambda (k) (- 0 k)))))
              (do ((i 0 (+ i 1))) ((= i 40)) (hash-table-set! ht i i))
              (misses ht (lambda (i) i) 40)))
(test-equal "custom hash returning a constant loses nothing" 0
            (let ((ht (make-hash-table = (lambda (k) 7))))
              (do ((i 0 (+ i 1))) ((= i 40)) (hash-table-set! ht i i))
              (misses ht (lambda (i) i) 40)))
(test-equal "custom hash returning a non-integer loses nothing" 0
            (let ((ht (make-hash-table = (lambda (k) 1.5))))
              (do ((i 0 (+ i 1))) ((= i 40)) (hash-table-set! ht i i))
              (misses ht (lambda (i) i) 40)))
(test-equal "custom hash returning a string loses nothing" 0
            (let ((ht (make-hash-table = (lambda (k) "h"))))
              (do ((i 0 (+ i 1))) ((= i 40)) (hash-table-set! ht i i))
              (misses ht (lambda (i) i) 40)))
(test-equal "custom hash returning a bignum loses nothing" 0
            (let ((ht (make-hash-table = (lambda (k) (+ (expt 2 100) k)))))
              (do ((i 0 (+ i 1))) ((= i 40)) (hash-table-set! ht i i))
              (misses ht (lambda (i) i) 40)))
(test-equal "custom hash returning the unspecified value loses nothing" 0
            (let ((ht (make-hash-table = (lambda (k) (if #f #f)))))
              (do ((i 0 (+ i 1))) ((= i 40)) (hash-table-set! ht i i))
              (misses ht (lambda (i) i) 40)))
(test-equal "an error raised by a custom hash proc propagates" 'caught
            (caught (lambda () (let ((ht (make-hash-table = (lambda (k) (error "hashboom")))))
                                 (hash-table-set! ht 1 1)))))
(test-equal "a wrong-arity custom hash proc raises" 'caught
            (caught (lambda () (hash-table-set! (make-hash-table = (lambda (a b) 1)) 1 1))))
(test-equal "a wrong-arity custom equivalence proc raises" 'caught
            (caught (lambda () (let ((ht (make-hash-table (lambda (a) #t) (lambda (k) 1))))
                                 (hash-table-set! ht 1 1) (hash-table-set! ht 2 2)))))
;; A custom equality that raises part-way through a bulk insert must leave a
;; consistent table: size agrees with the number of live keys.
(test-equal "a raising custom equality leaves size and keys consistent" #t
            (let* ((n 0)
                   (ht (make-hash-table (lambda (a b) (set! n (+ n 1))
                                          (if (> n 12) (raise 'eqboom) (equal? a b)))
                                        (lambda (k) (if (number? k) (modulo k 4) 0)))))
              (caught (lambda () (do ((i 0 (+ i 1))) ((= i 40)) (hash-table-set! ht i i))))
              (set! n -1000000)
              (= (hash-table-size ht) (length (hash-table-keys ht)))))
;; A custom hash that mutates a *different* table is fine — this is the
;; discriminating control for #2024, and must keep passing.
(test-equal "a custom hash mutating a different table is safe (control for #2024)" '(5 5)
            (let* ((g (make-hash-table))
                   (armed #t)
                   (h (make-hash-table = (lambda (k)
                                           (when armed
                                             (set! armed #f)
                                             (do ((j 0 (+ j 1))) ((= j 5)) (hash-table-set! g (+ 100 j) j))
                                             (set! armed #t))
                                           (if (number? k) k 0)))))
              (do ((i 0 (+ i 1))) ((= i 5)) (hash-table-set! h i i))
              (list (hash-table-size h) (hash-table-size g))))
;; A custom *equality* that mutates its own table is also fine — rehash
;; never calls the equality proc. Second control for #2024.
(test-equal "a custom equality mutating its own table is safe (control for #2024)" #t
            (let* ((h #f) (armed #t))
              (set! h (make-hash-table
                       (lambda (a b)
                         (when (and armed h)
                           (set! armed #f)
                           (do ((j 0 (+ j 1))) ((= j 5)) (hash-table-set! h (+ 100 j) j))
                           (set! armed #t))
                         (equal? a b))
                       (lambda (k) (if (number? k) k 0))))
              (do ((i 0 (+ i 1))) ((= i 5)) (hash-table-set! h i i))
              (>= (hash-table-size h) 5)))
;; Unbounded self-re-entry from a custom hash is bounded rather than run to
;; a native stack smash — it raises `KP3008: native re-entrancy too deep`.
;; That is the third control for #2024, but it cannot be asserted in-process:
;; KP3008 is a VM limit, and `errors.isUncatchable` puts it past every
;; handler by design (#1886), so no `guard` here can see it. Verified out of
;; band instead; the recipe is in #2024.
;; FAIL: #2024 (a custom hash proc that inserts into its OWN table makes
;; rehash iterate a freed entry array — the process aborts with exit 133/134
;; and empty stdout and stderr, which no `guard` can contain, so this stays
;; commented out rather than merely disabled)
;; (test-equal "a custom hash mutating its own table does not abort (#2024)" #t
;;             (let ((h #f) (armed #t))
;;               (set! h (make-hash-table = (lambda (k)
;;                                            (when (and armed h)
;;                                              (set! armed #f)
;;                                              (do ((j 0 (+ j 1))) ((= j 5)) (hash-table-set! h (+ 100 j) j))
;;                                              (set! armed #t))
;;                                            (if (number? k) k 0))))
;;               (do ((i 0 (+ i 1))) ((= i 5)) (hash-table-set! h i i))
;;               (>= (hash-table-size h) 5)))

;;; --- callback discipline: continuations and blocking (D5) -------------

(test-equal "call/cc can escape from a walk callback" '(escaped 3)
            (let ((ht (make-hash-table)) (n 0))
              (do ((i 0 (+ i 1))) ((= i 5)) (hash-table-set! ht i i))
              (call/cc (lambda (esc)
                         (hash-table-walk ht (lambda (k v)
                                               (set! n (+ n 1))
                                               (if (= n 3) (esc (list 'escaped n)))))
                         'finished))))
(test-equal "call/cc can escape from a fold callback" 'escaped
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 5)) (hash-table-set! ht i i))
              (call/cc (lambda (esc)
                         (hash-table-fold ht (lambda (k v a) (esc 'escaped)) 0)))))
(test-equal "a walk may be re-entered from inside its own callback" 20
            (let ((ht (make-hash-table)) (n 0) (d 0))
              (do ((i 0 (+ i 1))) ((= i 4)) (hash-table-set! ht i i))
              (hash-table-walk ht (lambda (k v)
                                    (set! n (+ n 1))
                                    (when (< d 2)
                                      (set! d (+ d 1))
                                      (hash-table-walk ht (lambda (k2 v2) (set! n (+ n 1))))
                                      (set! d (- d 1)))))
              n))
;; Resuming a continuation captured inside a walk after the native call has
;; returned must fail cleanly, not resume over the freed snapshot. This is
;; the documented native-frame continuation limit (README).
(test-equal "resuming a walk continuation after the walk returned errors cleanly" #t
            (let ((ht (make-hash-table)) (saved #f))
              (do ((i 0 (+ i 1))) ((= i 4)) (hash-table-set! ht i i))
              (guard (e (#t #t))
                (hash-table-walk ht (lambda (k v) (call/cc (lambda (c) (if (not saved) (set! saved c))))))
                (if saved (let ((s saved)) (set! saved #f) (s 'again)))
                #t)))
;; There is no `in_custom_port_callback`-style blocking guard on this path,
;; and none is needed: callWithArgs drives the scheduler in place.
(test-equal "thread-sleep! inside a walk callback works" 3
            (let ((ht (make-hash-table)) (n 0))
              (do ((i 0 (+ i 1))) ((= i 3)) (hash-table-set! ht i i))
              (hash-table-walk ht (lambda (k v) (thread-sleep! 0.001) (set! n (+ n 1))))
              n))
(test-equal "thread-sleep! inside a custom hash proc works" 3
            (let ((ht (make-hash-table = (lambda (k) (thread-sleep! 0.001) (if (number? k) k 0)))))
              (do ((i 0 (+ i 1))) ((= i 3)) (hash-table-set! ht i i))
              (hash-table-size ht)))
(test-equal "thread-sleep! inside a fold callback works" 3
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 3)) (hash-table-set! ht i i))
              (hash-table-fold ht (lambda (k v a) (thread-sleep! 0.001) (+ a 1)) 0)))

;;; --- copy / merge! -----------------------------------------------------

(test-equal "copy is independent of the source" '(1 2)
            (let ((h1 (make-hash-table)))
              (hash-table-set! h1 'k 1)
              (let ((h2 (hash-table-copy h1)))
                (hash-table-set! h2 'k 2)
                (list (hash-table-ref h1 'k) (hash-table-ref h2 'k)))))
(test-equal "copy of an empty table is empty" 0 (hash-table-size (hash-table-copy (make-hash-table))))
(test-equal "copy preserves every entry across growth" '(300 0)
            (let ((h1 (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 300)) (hash-table-set! h1 i i))
              (let ((h2 (hash-table-copy h1)))
                (list (hash-table-size h2) (misses h2 (lambda (i) i) 300)))))
(test-equal "copy preserves the compare mode" 'rejected
            (let ((c (hash-table-copy (make-hash-table string=?))))
              (guard (e (#t 'rejected)) (hash-table-set! c 1 2))))
(test-equal "copy preserves the equivalence procedure identity" #t
            (let ((src (make-hash-table eq?)))
              (eq? (hash-table-equivalence-function src)
                   (hash-table-equivalence-function (hash-table-copy src)))))
(test-equal "copy of a custom-hash table still finds its keys" 0
            (let ((src (make-hash-table = (lambda (k) (if (number? k) (modulo k 8) 0)))))
              (do ((i 0 (+ i 1))) ((= i 50)) (hash-table-set! src i i))
              (misses (hash-table-copy src) (lambda (i) i) 50)))
(test-equal "copy on a non-table raises" 'caught (caught (lambda () (hash-table-copy 'x))))
(test-equal "merge! lets the second table win" 'new
            (let ((h1 (make-hash-table)) (h2 (make-hash-table)))
              (hash-table-set! h1 'k 'old) (hash-table-set! h2 'k 'new)
              (hash-table-merge! h1 h2) (hash-table-ref h1 'k)))
(test-equal "merge! unions disjoint tables" 2
            (let ((h1 (make-hash-table)) (h2 (make-hash-table)))
              (hash-table-set! h1 'a 1) (hash-table-set! h2 'b 2)
              (hash-table-size (hash-table-merge! h1 h2))))
(test-equal "merge! returns the first table" #t
            (let ((h1 (make-hash-table)) (h2 (make-hash-table)))
              (eq? h1 (hash-table-merge! h1 h2))))
(test-equal "merge! does not modify the source table" 3
            (let ((h1 (make-hash-table)) (h2 (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 3)) (hash-table-set! h2 i i))
              (hash-table-merge! h1 h2) (hash-table-size h2)))
(test-equal "merge! of a large source loses nothing" '(50 0)
            (let ((h1 (make-hash-table)) (h2 (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 50)) (hash-table-set! h2 i i))
              (hash-table-merge! h1 h2)
              (list (hash-table-size h1) (misses h1 (lambda (i) i) 50))))
;; self-merge must not corrupt (#278 regression)
(test-equal "self-merge is a no-op (#278)" 1
            (let ((ht (make-hash-table)))
              (hash-table-set! ht 'k 'v) (hash-table-merge! ht ht) (hash-table-size ht)))
(test-equal "self-merge of a grown table is a no-op (#278)" '(100 0)
            (let ((ht (make-hash-table)))
              (do ((i 0 (+ i 1))) ((= i 100)) (hash-table-set! ht i i))
              (hash-table-merge! ht ht)
              (list (hash-table-size ht) (misses ht (lambda (i) i) 100))))
(test-equal "merge! with a non-table raises" 'caught
            (caught (lambda () (hash-table-merge! (make-hash-table) '()))))
(test-equal "merge! with a non-table first argument raises" 'caught
            (caught (lambda () (hash-table-merge! '() (make-hash-table)))))

;;; --- hash procedures ---------------------------------------------------
;;; SRFI 69: "Produces a hash value for object in the range ( 0, bound (."
;;; Values are never asserted: `valueHash` returns a `usize` (32-bit on
;;; wasm32) and folds pointers for some types.

(test-equal "hash returns an integer" #t (integer? (hash '(a b c))))
(test-equal "hash is deterministic for strings" #t (= (hash "abc") (hash "abc")))
(test-equal "hash is deterministic for shallow lists" #t (= (hash (list 1 2)) (hash (list 1 2))))
(test-equal "hash respects an explicit bound" #t
            (let ((h (hash 'sym 10))) (and (<= 0 h) (< h 10))))
(test-equal "hash with a bound of 1 is always 0" 0 (hash "anything" 1))
(test-equal "string-hash agrees on equal? strings" #t
            (= (string-hash "abc") (string-hash (string-copy "abc"))))
(test-equal "string-hash respects an explicit bound" #t
            (let ((h (string-hash "abc" 7))) (and (<= 0 h) (< h 7))))
(test-equal "string-ci-hash folds ASCII case" #t (= (string-ci-hash "AbC") (string-ci-hash "abc")))
(test-equal "string-ci-hash folds non-ASCII case" #t
            (= (string-ci-hash "ΛΆΜΔΑ") (string-ci-hash "λάμδα")))
(test-equal "hash-by-identity returns an integer" #t (integer? (hash-by-identity 'x)))
(test-equal "hash-by-identity respects an explicit bound" #t
            (let ((h (hash-by-identity 'x 5))) (and (<= 0 h) (< h 5))))
(test-equal "hash-by-identity agrees with itself on the same object" #t
            (let ((o (list 1))) (= (hash-by-identity o) (hash-by-identity o))))
;; The *bounded* forms are always in range — the discriminating control for
;; #2025, which is confined to the unbounded arm.
(test-equal "bounded string-hash is in range for 199 inputs (control for #2025)" 0
            (let loop ((i 1) (bad 0))
              (if (= i 200) bad
                  (loop (+ i 1)
                        (let ((v (string-hash (make-string i #\z) 97)))
                          (if (or (< v 0) (>= v 97)) (+ bad 1) bad))))))
(test-equal "bounded hash is in range for 199 inputs (control for #2025)" 0
            (let loop ((i 1) (bad 0))
              (if (= i 200) bad
                  (loop (+ i 1)
                        (let ((v (hash (make-string i #\z) 97)))
                          (if (or (< v 0) (>= v 97)) (+ bad 1) bad))))))
;; FAIL: #2025 (the unbounded arm masks to 62 bits and then makeFixnum keeps
;; 48 with sign extension, so about half of all hashes come back negative)
;; All three inputs below are pure byte arithmetic — no pointer, and the
;; values are stable run to run — so re-enabling these is portable.
;; `hash-by-identity` is deliberately NOT covered: its input is the object's
;; own bit pattern, so any assertion about it would be layout-dependent.
;; (test-equal "unbounded string-hash is never negative (#2025)" 0
;;             (let loop ((i 1) (bad 0))
;;               (if (= i 60) bad
;;                   (loop (+ i 1) (if (< (string-hash (make-string i #\a)) 0) (+ bad 1) bad)))))
;; (test-equal "unbounded string-ci-hash is never negative (#2025)" 0
;;             (let loop ((i 1) (bad 0))
;;               (if (= i 60) bad
;;                   (loop (+ i 1) (if (< (string-ci-hash (make-string i #\a)) 0) (+ bad 1) bad)))))
;; (test-equal "unbounded hash is never negative (#2025)" 0
;;             (let loop ((i 1) (bad 0))
;;               (if (= i 60) bad
;;                   (loop (+ i 1) (if (< (hash (make-string i #\a)) 0) (+ bad 1) bad)))))

(test-equal "hash with a zero bound raises" 'caught (caught (lambda () (hash 'x 0))))
(test-equal "hash with a negative bound raises" 'caught (caught (lambda () (hash 'x -3))))
(test-equal "hash with a non-integer bound raises" 'caught (caught (lambda () (hash 'x 1.5))))
(test-equal "string-hash on a non-string raises" 'caught (caught (lambda () (string-hash 42))))
(test-equal "string-ci-hash on a non-string raises" 'caught (caught (lambda () (string-ci-hash 42))))
(test-equal "string-hash with a zero bound raises" 'caught (caught (lambda () (string-hash "a" 0))))
(test-equal "string-ci-hash with a zero bound raises" 'caught (caught (lambda () (string-ci-hash "a" 0))))
(test-equal "hash-by-identity with a zero bound raises" 'caught
            (caught (lambda () (hash-by-identity 'x 0))))

;;; --- equality-mode agreement with the underlying predicate -------------
;;; Each table is grown past its initial capacity first, so a wrong hash
;;; cannot be masked by the pointer-alignment effect at capacity 8.

(define (mode-agrees? eqp k1 k2)
  (let ((ht (make-hash-table eqp)))
    (do ((i 0 (+ i 1))) ((= i 40)) (hash-table-set! ht (list 'filler i) i))
    (hash-table-set! ht k1 'v)
    (eq? (eqp k1 k2) (not (eq? 'MISS (hash-table-ref/default ht k2 'MISS))))))

(test-equal "eqv table agrees with eqv? on equal flonums" #t (mode-agrees? eqv? 2.0 2.0))
(test-equal "eqv table agrees with eqv? on 0.0 vs -0.0" #t (mode-agrees? eqv? 0.0 -0.0))
(test-equal "eqv table agrees with eqv? on bignums" #t (mode-agrees? eqv? (expt 2 100) (expt 2 100)))
(test-equal "eqv table agrees with eqv? on rationals" #t (mode-agrees? eqv? (/ 1 3) (/ 1 3)))
(test-equal "eqv table agrees with eqv? on chars" #t (mode-agrees? eqv? #\a #\a))
(test-equal "eqv table agrees with eqv? on distinct strings" #t (mode-agrees? eqv? "a" "a"))
(test-equal "eqv table agrees with eqv? on exact vs inexact" #t (mode-agrees? eqv? 2 2.0))
(test-equal "eq table agrees with eq? on symbols" #t (mode-agrees? eq? 'sym 'sym))
(test-equal "eq table agrees with eq? on fixnums" #t (mode-agrees? eq? 7 7))
(test-equal "equal table agrees with equal? on strings" #t
            (mode-agrees? equal? "abc" (string-copy "abc")))
(test-equal "equal table agrees with equal? on shallow lists" #t
            (mode-agrees? equal? (list 1 2) (list 1 2)))
;; FAIL: #2023 (of the 12 mode/predicate cells above and this one, this is
;; the only one that disagrees; stated at scale because a single deep key in
;; a small table can still be found by luck through linear probing)
;; (test-equal "equal table agrees with equal? on 200 deep keys (#2023)" 0
;;             (let ((ht (make-hash-table)))
;;               (do ((i 0 (+ i 1))) ((= i 200)) (hash-table-set! ht (mk 11 i) i))
;;               (misses ht (lambda (i) (mk 11 i)) 200)))

;;; --- accessors ---------------------------------------------------------

(test-equal "equivalence-function of a default table is a procedure" #t
            (procedure? (hash-table-equivalence-function (make-hash-table))))
(test-equal "hash-function of a default table is a procedure" #t
            (procedure? (hash-table-hash-function (make-hash-table))))
(test-equal "hash-function of an eq? table is a procedure" #t
            (procedure? (hash-table-hash-function (make-hash-table eq?))))
(test-equal "hash-function of a string=? table is a procedure" #t
            (procedure? (hash-table-hash-function (make-hash-table string=?))))
(test-equal "a supplied hash procedure is reported back" #t
            (let ((f (lambda (k) 1)))
              (eq? f (hash-table-hash-function (make-hash-table equal? f)))))
(test-equal "equivalence-function on a non-table raises" 'caught
            (caught (lambda () (hash-table-equivalence-function 42))))
(test-equal "hash-function on a non-table raises" 'caught
            (caught (lambda () (hash-table-hash-function 42))))

;;; --- error taxonomy (D2) ----------------------------------------------
;;; Every rejection below names the offending procedure. Whether a missing
;;; key and an out-of-range bound should be KP3002 rather than KP3007 is
;;; tracked in #2021 (which lists this file's six sites); these assertions
;;; pin only the parts that are already right.

(define (contains? s pat)
  (let ((n (string-length s)) (p (string-length pat)))
    (let loop ((i 0))
      (cond ((> (+ i p) n) #f)
            ((string=? (substring s i (+ i p)) pat) #t)
            (else (loop (+ i 1)))))))
(test-equal "a non-table argument names the procedure" #t
            (let ((m (msg-of (lambda () (hash-table-set! 5 'k 'v)))))
              (and (string? m) (contains? m "hash-table-set!"))))
(test-equal "a bad hash bound names the procedure" #t
            (let ((m (msg-of (lambda () (hash 'x 0)))))
              (and (string? m) (contains? m "hash"))))
(test-equal "a walk callback's own error is not reattributed to the walk" #t
            (let ((m (msg-of (lambda () (let ((ht (make-hash-table)))
                                          (hash-table-set! ht 'a 1)
                                          (hash-table-walk ht (lambda (k v) (error "callback-said-this"))))))))
              (and (string? m) (contains? m "callback-said-this"))))
(test-equal "a string=? table's rejection explains the compare mode" #t
            (let ((m (msg-of (lambda () (hash-table-set! (make-hash-table string=?) 1 2)))))
              (and (string? m) (> (string-length m) 20))))

;;; --- cross-thread deep copy (D6) --------------------------------------
;;; A table named by a top-level binding travels the *globals* route (shared
;;; by pointer). A table captured lexically travels the *copy* route.

(define d6-shared (make-hash-table))
(hash-table-set! d6-shared 'a 1)
(hash-table-set! d6-shared (list 1 2) 3)
(test-equal "a table reached through a global is shared, not copied" '(2 1 3)
            (thread-join! (thread-start! (make-thread
              (lambda () (list (hash-table-size d6-shared)
                               (hash-table-ref/default d6-shared 'a 'MISS)
                               (hash-table-ref/default d6-shared (list 1 2) 'MISS)))))))
(test-equal "a child's insert through the globals route is visible to the parent" 9
            (begin (thread-join! (thread-start! (make-thread
                     (lambda () (hash-table-set! d6-shared 'child 9)))))
                   (hash-table-ref/default d6-shared 'child 'MISS)))

(define d6-custom (make-hash-table (lambda (a b) (equal? a b))
                                   (lambda (k) (if (number? k) (modulo k 16) 3))))
(do ((i 0 (+ i 1))) ((= i 40)) (hash-table-set! d6-custom i i))
(test-equal "custom equivalence and hash procs survive the thread boundary" '(0 40 #t)
            (thread-join! (thread-start! (make-thread
              (lambda () (list (misses d6-custom (lambda (i) i) 40)
                               (hash-table-size d6-custom)
                               (procedure? (hash-table-equivalence-function d6-custom))))))))

(define d6-eq (make-hash-table eq?))
(define d6-eq-keys (map (lambda (i) (string->symbol (string-append "d6k" (number->string i))))
                        (iota-list 40)))
(for-each (lambda (s) (hash-table-set! d6-eq s s)) d6-eq-keys)
(test-equal "an eq? table's identity hash is recomputed across the boundary" 0
            (thread-join! (thread-start! (make-thread
              (lambda ()
                (let loop ((ks d6-eq-keys) (m 0))
                  (cond ((null? ks) m)
                        ((eq? 'MISS (hash-table-ref/default d6-eq (car ks) 'MISS)) (loop (cdr ks) (+ m 1)))
                        (else (loop (cdr ks) m)))))))))

;; A table copied *back* across thread-join! that holds an uncopyable value
;; must fail cleanly rather than corrupt.
(test-equal "a table holding a port cannot cross thread-join! and says so" 'caught
            (caught (lambda ()
                      (thread-join! (thread-start! (make-thread
                        (lambda ()
                          (let ((t (make-hash-table)))
                            (hash-table-set! t 'p (open-input-string "y"))
                            t))))))))
(test-equal "a table of plain values copies back across thread-join! intact" '(30 0)
            (let ((t (thread-join! (thread-start! (make-thread
                       (lambda ()
                         (let ((h (make-hash-table)))
                           (do ((i 0 (+ i 1))) ((= i 30)) (hash-table-set! h (number->string i) i))
                           h)))))))
              (list (hash-table-size t) (misses t (lambda (i) (number->string i)) 30))))

;;; --- registration-table invariants (D4) -------------------------------
;;; Each spec's declared arity against what the body actually indexes.

(test-equal "make-hash-table is variadic from 0" #t
            (and (hash-table? (make-hash-table))
                 (hash-table? (make-hash-table equal?))
                 (hash-table? (make-hash-table equal? hash))))
(test-equal "hash-table-ref is variadic from 2" #t
            (and (eq? 'd (hash-table-ref/default (make-hash-table) 'k 'd))
                 (eq? 'd (hash-table-ref (make-hash-table) 'k (lambda () 'd)))))
(test-equal "hash-table-set! rejects two arguments" 'caught
            (caught (lambda () (hash-table-set! (make-hash-table) 'k))))
(test-equal "hash-table-set! rejects four arguments" 'caught
            (caught (lambda () (hash-table-set! (make-hash-table) 'k 'v 'extra))))
(test-equal "hash-table-size rejects two arguments" 'caught
            (caught (lambda () (hash-table-size (make-hash-table) 'extra))))
(test-equal "hash-table-update!/default rejects three arguments" 'caught
            (caught (lambda () (hash-table-update!/default (make-hash-table) 'k (lambda (x) x)))))
(test-equal "hash-table-fold rejects two arguments" 'caught
            (caught (lambda () (hash-table-fold (make-hash-table) (lambda (k v a) a)))))
(test-equal "hash-table-merge! rejects one argument" 'caught
            (caught (lambda () (hash-table-merge! (make-hash-table)))))
(test-equal "hash-table? rejects zero arguments" 'caught (caught (lambda () (hash-table?))))

(let ((runner (test-runner-current)))
  (test-end "primitives_hashtable audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
