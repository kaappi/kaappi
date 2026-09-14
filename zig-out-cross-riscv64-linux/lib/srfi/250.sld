;;; SRFI 250: Insertion-ordered Hash Tables
;;;
;;; Hash tables that preserve the order in which associations were first
;;; inserted: associations inserted earlier appear earlier in iteration,
;;; folding, and conversion, and updating the value of an existing key keeps
;;; its association in the same position.
;;;
;;; Implementation notes
;;; --------------------
;;; A doubly-linked list of nodes (oldest = head, newest = tail) records the
;;; insertion order. A backing hash table maps each key to its node, giving
;;; O(1) lookup, deletion, and update. The backing table is created with the
;;; SRFI 128 comparator directly: Kaappi's built-in make-hash-table extracts
;;; the comparator's equality predicate and hash function, so key comparison
;;; and hashing honour the comparator.
;;;
;;; A cursor is simply a node; the "end state" is the distinguished sentinel
;;; %end. Any cursor that is not a node is at the end.

(define-library (srfi 250)
  (import (scheme base)
          (scheme case-lambda)
          (srfi 128)
          ;; The backing key->node index reuses the built-in (SRFI 69) hash
          ;; table, renamed so it does not collide with this library's own
          ;; procedures of the same names.
          (rename (only (srfi 69)
                        make-hash-table hash-table-set! hash-table-ref/default
                        hash-table-delete! hash-table-size)
                  (make-hash-table        %make-index)
                  (hash-table-set!        %index-set!)
                  (hash-table-ref/default %index-ref)
                  (hash-table-delete!     %index-delete!)
                  (hash-table-size        %index-size)))

  (export
    ;; Constructors
    make-hash-table hash-table hash-table-unfold alist->hash-table
    ;; Predicates
    hash-table? hash-table-contains? hash-table-empty? hash-table-mutable?
    ;; Accessors
    hash-table-ref hash-table-ref/default hash-table-comparator
    ;; Mutators
    hash-table-add! hash-table-replace! hash-table-set! hash-table-delete!
    hash-table-intern! hash-table-update! hash-table-update!/default
    hash-table-pop! hash-table-clear!
    ;; The whole hash table
    hash-table-size hash-table= hash-table-find hash-table-count
    hash-table-keys hash-table-values hash-table-entries
    ;; Cursors
    hash-table-cursor-first hash-table-cursor-last hash-table-cursor-for-key
    hash-table-cursor-next hash-table-cursor-previous
    hash-table-cursor-key hash-table-cursor-value hash-table-cursor-key+value
    hash-table-cursor-value-set! hash-table-cursor-at-end?
    ;; Mapping and folding
    hash-table-map hash-table-map! hash-table-for-each hash-table-map->list
    hash-table-fold hash-table-fold-left hash-table-fold-right
    hash-table-prune!
    ;; Copying and conversion
    hash-table-copy hash-table-empty-copy hash-table->alist
    ;; Set operations
    hash-table-union! hash-table-intersection! hash-table-difference!
    hash-table-xor!)

  (begin

    ;; -------------------------------------------------------------------
    ;; Data structures
    ;; -------------------------------------------------------------------

    ;; A node in the insertion-order list is a 4-slot vector
    ;; #(key value prev next); prev/next are the neighbouring node vectors, or
    ;; #f at the ends of the list. Nodes are vectors rather than records so
    ;; that `write` can print a table in finite space: Kaappi's printer breaks
    ;; the prev<->next reference cycle with datum labels for pairs and vectors,
    ;; but loops on cyclic record fields.
    (define (make-node key value prev next) (vector key value prev next))
    (define (node-key n)          (vector-ref n 0))
    (define (node-value n)        (vector-ref n 1))
    (define (node-value-set! n v) (vector-set! n 1 v))
    (define (node-prev n)         (vector-ref n 2))
    (define (node-prev-set! n p)  (vector-set! n 2 p))
    (define (node-next n)         (vector-ref n 3))
    (define (node-next-set! n x)  (vector-set! n 3 x))

    ;; The hash table: comparator, the key->node index, the KEYS of the head
    ;; (oldest) and tail (newest) nodes of the order list, and a mutability
    ;; flag. Storing the head/tail *keys* rather than the head/tail nodes keeps
    ;; the record's fields leaf values, so `write` can print a table finitely:
    ;; the (cyclic) node vectors live only inside the built-in index, which
    ;; prints opaquely as #<hash-table size=N> and is never traversed. (The
    ;; record printer recurses into fields without cycle detection, so a node
    ;; reference in a field would loop.)
    (define-record-type <hash-table>
      (make-table comparator index head-key tail-key mutable)
      hash-table?
      (comparator hash-table-comparator)
      (index      table-index)
      (head-key   table-head-key table-head-key-set!)
      (tail-key   table-tail-key table-tail-key-set!)
      (mutable    hash-table-mutable? table-mutable-set!))

    ;; Sentinel head-key/tail-key value meaning "the list end" (empty table, or
    ;; no node beyond this one). A private object, so no user key is `eq?` to it.
    (define %none (list 'srfi-250-none))

    ;; The distinguished "end state" cursor. A cursor is either a node or %end.
    (define %end (list 'srfi-250-cursor-end))

    ;; Resolve the head/tail node (or #f when the table is empty).
    (define (table-head table)
      (let ((k (table-head-key table)))
        (if (eq? k %none) #f (%index-ref (table-index table) k #f))))
    (define (table-tail table)
      (let ((k (table-tail-key table)))
        (if (eq? k %none) #f (%index-ref (table-index table) k #f))))

    ;; Record NODE (or #f) as the head/tail of the order list.
    (define (table-set-head! table node)
      (table-head-key-set! table (if node (node-key node) %none)))
    (define (table-set-tail! table node)
      (table-tail-key-set! table (if node (node-key node) %none)))

    ;; -------------------------------------------------------------------
    ;; Internal helpers
    ;; -------------------------------------------------------------------

    (define (check-mutable table who)
      (unless (hash-table-mutable? table)
        (error (string-append who ": hash table is immutable") table)))

    ;; Look up KEY, returning its node or #f.
    (define (table-lookup table key)
      (%index-ref (table-index table) key #f))

    ;; Append a fresh association at the newest end. Assumes KEY is absent.
    (define (table-append! table key value)
      (let* ((old-tail (table-tail table))
             (node (make-node key value old-tail #f)))
        (if old-tail
            (node-next-set! old-tail node)
            (table-set-head! table node))
        (table-set-tail! table node)
        (%index-set! (table-index table) key node)
        node))

    ;; Prepend a fresh association at the oldest end. Assumes KEY is absent.
    ;; Used by alist->hash-table to build reverse insertion order.
    (define (table-prepend! table key value)
      (let* ((old-head (table-head table))
             (node (make-node key value #f old-head)))
        (if old-head
            (node-prev-set! old-head node)
            (table-set-tail! table node))
        (table-set-head! table node)
        (%index-set! (table-index table) key node)
        node))

    ;; Unlink NODE from the order list and drop it from the index.
    (define (table-unlink! table node)
      (let ((p (node-prev node))
            (n (node-next node)))
        (if p (node-next-set! p n) (table-set-head! table n))
        (if n (node-prev-set! n p) (table-set-tail! table p))
        (%index-delete! (table-index table) (node-key node))))

    ;; Insert or update one association (single-pair hash-table-set!).
    (define (table-set-one! table key value)
      (let ((node (table-lookup table key)))
        (if node
            (node-value-set! node value)
            (table-append! table key value))))

    ;; Walk associations oldest to newest, calling (proc node).
    (define (for-each-node table proc)
      (let loop ((node (table-head table)))
        (when node
          (proc node)
          (loop (node-next node)))))

    ;; Apply (proc key value) over a flat key1 value1 key2 value2 ... list.
    (define (do-pairwise who args proc)
      (let loop ((lst args))
        (cond ((null? lst) (if #f #f))
              ((null? (cdr lst))
               (error (string-append who ": odd number of key/value arguments")))
              (else (proc (car lst) (cadr lst))
                    (loop (cddr lst))))))

    ;; -------------------------------------------------------------------
    ;; Constructors
    ;; -------------------------------------------------------------------

    ;; (make-hash-table comparator [k]) -- k (capacity hint) is accepted and
    ;; ignored.
    (define (make-hash-table comparator . rest)
      (make-table comparator (%make-index comparator) %none %none #t))

    (define (hash-table comparator . kvs)
      (let ((table (make-hash-table comparator)))
        (do-pairwise "hash-table" kvs
          (lambda (key value) (table-set-one! table key value)))
        table))

    (define (hash-table-unfold stop? mapper successor seed comparator . rest)
      (let ((table (make-hash-table comparator)))
        (let loop ((seed seed))
          (if (stop? seed)
              table
              (call-with-values
                (lambda () (mapper seed))
                (lambda (key value)
                  (table-set-one! table key value)
                  (loop (successor seed))))))))

    (define (alist->hash-table alist comparator . rest)
      (let ((table (make-hash-table comparator)))
        ;; Process the alist left to right, prepending new keys and skipping
        ;; keys already seen. This yields reverse insertion order, with the
        ;; earliest occurrence of each key winning, as the spec requires.
        (for-each
          (lambda (pair)
            (unless (table-lookup table (car pair))
              (table-prepend! table (car pair) (cdr pair))))
          alist)
        table))

    ;; -------------------------------------------------------------------
    ;; Predicates
    ;; -------------------------------------------------------------------

    (define (hash-table-contains? table key)
      (if (table-lookup table key) #t #f))

    (define (hash-table-empty? table)
      (= (%index-size (table-index table)) 0))

    ;; -------------------------------------------------------------------
    ;; Accessors
    ;; -------------------------------------------------------------------

    (define hash-table-ref
      (case-lambda
        ((table key)
         (let ((node (table-lookup table key)))
           (if node (node-value node)
               (error "hash-table-ref: key not found" key))))
        ((table key failure)
         (let ((node (table-lookup table key)))
           (if node (node-value node) (failure))))
        ((table key failure success)
         (let ((node (table-lookup table key)))
           (if node (success (node-value node)) (failure))))))

    (define (hash-table-ref/default table key default)
      (let ((node (table-lookup table key)))
        (if node (node-value node) default)))

    ;; -------------------------------------------------------------------
    ;; Mutators
    ;; -------------------------------------------------------------------

    (define (hash-table-add! table . args)
      (check-mutable table "hash-table-add!")
      (do-pairwise "hash-table-add!" args
        (lambda (key value)
          (if (table-lookup table key)
              (error "hash-table-add!: key already present" key)
              (table-append! table key value)))))

    (define (hash-table-replace! table . args)
      (check-mutable table "hash-table-replace!")
      (do-pairwise "hash-table-replace!" args
        (lambda (key value)
          (let ((node (table-lookup table key)))
            (if node
                (node-value-set! node value)
                (error "hash-table-replace!: key not present" key))))))

    (define (hash-table-set! table . args)
      (check-mutable table "hash-table-set!")
      (do-pairwise "hash-table-set!" args
        (lambda (key value) (table-set-one! table key value))))

    (define (hash-table-delete! table . keys)
      (check-mutable table "hash-table-delete!")
      (let loop ((lst keys) (count 0))
        (if (null? lst)
            count
            (let ((node (table-lookup table (car lst))))
              (if node
                  (begin (table-unlink! table node)
                         (loop (cdr lst) (+ count 1)))
                  (loop (cdr lst) count))))))

    (define (hash-table-intern! table key failure)
      (check-mutable table "hash-table-intern!")
      (let ((node (table-lookup table key)))
        (if node
            (node-value node)
            (let ((value (failure)))
              (table-append! table key value)
              value))))

    (define hash-table-update!
      (case-lambda
        ((table key updater)
         (check-mutable table "hash-table-update!")
         (let ((node (table-lookup table key)))
           (if node
               (node-value-set! node (updater (node-value node)))
               (error "hash-table-update!: key not found" key))))
        ((table key updater failure)
         (check-mutable table "hash-table-update!")
         (let ((node (table-lookup table key)))
           (if node
               (node-value-set! node (updater (node-value node)))
               (table-append! table key (updater (failure))))))
        ((table key updater failure success)
         (check-mutable table "hash-table-update!")
         (let ((node (table-lookup table key)))
           (if node
               (node-value-set! node (updater (success (node-value node))))
               (table-append! table key (updater (failure))))))))

    (define (hash-table-update!/default table key updater default)
      (check-mutable table "hash-table-update!/default")
      (let ((node (table-lookup table key)))
        (if node
            (node-value-set! node (updater (node-value node)))
            (table-append! table key (updater default)))))

    (define (hash-table-pop! table)
      (check-mutable table "hash-table-pop!")
      (let ((node (table-tail table)))
        (if node
            (let ((key (node-key node)) (value (node-value node)))
              (table-unlink! table node)
              (values key value))
            (error "hash-table-pop!: hash table is empty"))))

    (define (hash-table-clear! table)
      (check-mutable table "hash-table-clear!")
      (for-each-node table
        (lambda (node) (%index-delete! (table-index table) (node-key node))))
      (table-set-head! table #f)
      (table-set-tail! table #f))

    ;; -------------------------------------------------------------------
    ;; The whole hash table
    ;; -------------------------------------------------------------------

    (define (hash-table-size table)
      (%index-size (table-index table)))

    (define (hash-table= same? table1 table2)
      (and (= (hash-table-size table1) (hash-table-size table2))
           (let loop ((node (table-head table1)))
             (or (not node)
                 (let ((other (table-lookup table2 (node-key node))))
                   (and other
                        (same? (node-value node) (node-value other))
                        (loop (node-next node))))))))

    (define (hash-table-find proc table failure)
      (let loop ((node (table-head table)))
        (if node
            (let ((result (proc (node-key node) (node-value node))))
              (if result result (loop (node-next node))))
            (failure))))

    (define (hash-table-count pred table)
      (let loop ((node (table-head table)) (count 0))
        (if node
            (loop (node-next node)
                  (if (pred (node-key node) (node-value node)) (+ count 1) count))
            count)))

    (define (table->vector table selector)
      (let ((vec (make-vector (hash-table-size table)))
            (i 0))
        (for-each-node table
          (lambda (node)
            (vector-set! vec i (selector node))
            (set! i (+ i 1))))
        vec))

    (define (hash-table-keys table)
      (table->vector table node-key))

    (define (hash-table-values table)
      (table->vector table node-value))

    (define (hash-table-entries table)
      (values (hash-table-keys table) (hash-table-values table)))

    ;; -------------------------------------------------------------------
    ;; Cursors
    ;; -------------------------------------------------------------------

    (define (hash-table-cursor-first table)
      (or (table-head table) %end))

    (define (hash-table-cursor-last table)
      (or (table-tail table) %end))

    (define (hash-table-cursor-for-key table key)
      (or (table-lookup table key) %end))

    (define (hash-table-cursor-next table cursor)
      (if (eq? cursor %end) %end (or (node-next cursor) %end)))

    (define (hash-table-cursor-previous table cursor)
      (if (eq? cursor %end) %end (or (node-prev cursor) %end)))

    (define (hash-table-cursor-key table cursor)
      (node-key cursor))

    (define (hash-table-cursor-value table cursor)
      (node-value cursor))

    (define (hash-table-cursor-key+value table cursor)
      (values (node-key cursor) (node-value cursor)))

    (define (hash-table-cursor-value-set! table cursor value)
      (node-value-set! cursor value))

    (define (hash-table-cursor-at-end? table cursor)
      (eq? cursor %end))

    ;; -------------------------------------------------------------------
    ;; Mapping and folding
    ;; -------------------------------------------------------------------

    (define (hash-table-map proc table)
      (let ((result (hash-table-empty-copy table)))
        (for-each-node table
          (lambda (node)
            (table-append! result (node-key node)
                           (proc (node-key node) (node-value node)))))
        result))

    (define (hash-table-map! proc table)
      (check-mutable table "hash-table-map!")
      (for-each-node table
        (lambda (node)
          (node-value-set! node (proc (node-key node) (node-value node)))))
      table)

    (define (hash-table-for-each proc table)
      (for-each-node table
        (lambda (node) (proc (node-key node) (node-value node))))
      (if #f #f))

    (define (hash-table-map->list proc table)
      (let ((result '()))
        (for-each-node table
          (lambda (node)
            (set! result (cons (proc (node-key node) (node-value node)) result))))
        (reverse result)))

    (define (hash-table-fold proc seed table)
      (let loop ((node (table-head table)) (acc seed))
        (if node
            (loop (node-next node) (proc (node-key node) (node-value node) acc))
            acc)))

    (define (hash-table-fold-left proc seed table)
      (let loop ((node (table-head table)) (acc seed))
        (if node
            (loop (node-next node) (proc acc (node-key node) (node-value node)))
            acc)))

    (define (hash-table-fold-right proc seed table)
      (let recur ((node (table-head table)))
        (if node
            (proc (node-key node) (node-value node) (recur (node-next node)))
            seed)))

    (define (hash-table-prune! proc table)
      (check-mutable table "hash-table-prune!")
      (let loop ((node (table-head table)) (removed 0))
        (if node
            (let ((next (node-next node)))
              (if (proc (node-key node) (node-value node))
                  (begin (table-unlink! table node)
                         (loop next (+ removed 1)))
                  (loop next removed)))
            removed)))

    ;; -------------------------------------------------------------------
    ;; Copying and conversion
    ;; -------------------------------------------------------------------

    (define hash-table-copy
      (case-lambda
        ((table) (hash-table-copy table #f))
        ((table mutable?)
         (let ((result (make-hash-table (hash-table-comparator table))))
           (for-each-node table
             (lambda (node)
               (table-append! result (node-key node) (node-value node))))
           (table-mutable-set! result (and mutable? #t))
           result))))

    (define (hash-table-empty-copy table)
      (make-hash-table (hash-table-comparator table)))

    (define (hash-table->alist table)
      ;; Consing while walking oldest to newest leaves the newest first, i.e.
      ;; reverse insertion order, as the spec requires.
      (let ((result '()))
        (for-each-node table
          (lambda (node)
            (set! result (cons (cons (node-key node) (node-value node)) result))))
        result))

    ;; -------------------------------------------------------------------
    ;; Set operations (destructive on the first argument)
    ;; -------------------------------------------------------------------

    (define (hash-table-union! table1 table2)
      (check-mutable table1 "hash-table-union!")
      (for-each-node table2
        (lambda (node)
          (unless (table-lookup table1 (node-key node))
            (table-append! table1 (node-key node) (node-value node)))))
      table1)

    (define (hash-table-intersection! table1 table2)
      (check-mutable table1 "hash-table-intersection!")
      (let loop ((node (table-head table1)))
        (when node
          (let ((next (node-next node)))
            (unless (table-lookup table2 (node-key node))
              (table-unlink! table1 node))
            (loop next))))
      table1)

    (define (hash-table-difference! table1 table2)
      (check-mutable table1 "hash-table-difference!")
      (let loop ((node (table-head table1)))
        (when node
          (let ((next (node-next node)))
            (when (table-lookup table2 (node-key node))
              (table-unlink! table1 node))
            (loop next))))
      table1)

    (define (hash-table-xor! table1 table2)
      (check-mutable table1 "hash-table-xor!")
      (for-each-node table2
        (lambda (node)
          (let ((existing (table-lookup table1 (node-key node))))
            (if existing
                (table-unlink! table1 existing)
                (table-append! table1 (node-key node) (node-value node))))))
      table1)))
