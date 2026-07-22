;;; SRFI 167 — Ordered Key Value Store
;;;
;;; SRFI 167 specifies an interface for a transactional, ordered
;;; (lexicographically-by-key) byte-string store, generic enough to sit in
;;; front of real storage engines (LMDB, FoundationDB, SQLite, ...). The
;;; SRFI's own post-finalization note (2021-03-30) says the design has
;;; "infelicities" and recommends treating it "as inspiration rather than an
;;; interface that will stand the tests of time" — so this port targets a
;;; correct, in-memory, single-process implementation of the *API surface*,
;;; not a real storage engine:
;;;
;;;  - `okvs-open`'s `home` argument and its `config` alist (`'cache`,
;;;    `'create?`, `'memory?`, `'wal?`, `'read-only?`) are accepted for
;;;    signature compatibility and then ignored: there is exactly one kind
;;;    of backing store, an in-memory (srfi 146) mapping over bytevector
;;;    keys ordered by (srfi 128)'s default bytevector comparator
;;;    (byte-by-byte, shorter-is-a-prefix-and-sorts-first — the usual
;;;    key-value-store convention, and exactly what prefix-range scanning
;;;    needs).
;;;  - Transactions get real, correct semantics without any locking: a
;;;    transaction is a private view of the store's mapping, cheap to take
;;;    since (srfi 146) mappings are immutable trees; reads inside the
;;;    transaction see its own writes, the underlying store does not see
;;;    them until the transaction procedure returns normally, and an
;;;    escaping condition (caught with `guard`) discards the transaction's
;;;    mapping entirely, i.e. rollback. Concurrent transactions against the
;;;    same store are not supported — there is no isolation/locking layer,
;;;    only the sequential atomicity-plus-rollback the spec's own examples
;;;    exercise.
;;;  - `okvs-range`/`okvs-prefix-range` build the requested sub-mapping and
;;;    hand its entries to (srfi 158)'s `list->generator`, so a range scan
;;;    is O(n) in the store's size rather than O(log n + k); fine for a
;;;    reference/testing-scale store, wrong for a production one.
;;;  - `make-default-state` returns a plain (srfi 69) hash table rather than
;;;    the (srfi 125) one named in the spec text — 125's hash tables are a
;;;    thin equal?-hashing wrapper over 69 in this codebase (see
;;;    lib/srfi/125.sld), so the extra dependency would have bought nothing.
;;;  - `engine-pack`/`engine-unpack` implement an order-preserving encoding
;;;    (a type tag byte followed by value bytes, modeled on the
;;;    FoundationDB tuple layer) for the types SRFI 168's worked examples
;;;    actually need as tuple items: booleans, exact integers (magnitude
;;;    bounded to values whose big-endian encoding fits 255 bytes — vastly
;;;    more than any realistic key), strings, and symbols. Encoded items of
;;;    the same type compare in the same order as the original values
;;;    (including a NUL-safe escape for embedded 0 bytes in strings/symbol
;;;    names); comparing across different types falls back to tag order.
;;;    Other Scheme types signal an error rather than silently producing a
;;;    key that sorts nowhere sensible.
;;;  - Hooks: the spec threads `okvs-hook-on-transaction-begin`/`-commit`
;;;    through SRFI 173, which Kaappi does not implement. A minimal hook
;;;    object (`make-okvs-hook`, `okvs-hook?`, `okvs-hook-add!`,
;;;    `okvs-hook-delete!`, `okvs-hook-run!` — an ordered list of
;;;    arity-matching procedures run for effect) covers the "sneak into the
;;;    transaction life cycle" use case the SRFI describes, without claiming
;;;    SRFI 173 conformance. SRFI 168 reuses this same object for its own
;;;    add/delete hooks rather than inventing a second one.
;;;
;;; `engine-open`'s signature is quoted in the spec as
;;; "(engine-open engine okvs [config])", reusing the parameter name `okvs`
;;; from the read/write delegates even though this procedure's job is to
;;; *create* one — like `okvs-open`, it is given a `home` locator, not an
;;; existing okvs. This port follows that (self-consistent) reading.
;;;
;;; Key/value pairs produced by `okvs-range`/`okvs-prefix-range` generators
;;; are ordinary Scheme pairs `(key . value)` — the spec says "generator of
;;; key-value pairs" without pinning down the representation.

(define-library (srfi 167)
  (import (scheme base) (scheme case-lambda)
          (srfi 1) (srfi 69) (srfi 128) (srfi 146) (srfi 158))
  (export
    ;; engine
    make-engine engine?
    engine-open engine-close engine-in-transaction
    engine-ref engine-set! engine-delete!
    engine-range-remove! engine-range engine-prefix-range
    engine-hook-on-transaction-begin engine-hook-on-transaction-commit
    engine-pack engine-unpack
    ;; okvs
    okvs-open okvs? okvs-close
    make-default-state
    okvs-transaction? okvs-transaction-state
    okvs-in-transaction
    okvs-ref okvs-set! okvs-delete!
    okvs-range-remove! okvs-range okvs-prefix-range
    make-default-engine
    okvs-hook-on-transaction-begin okvs-hook-on-transaction-commit
    ;; minimal private-hook surface (see header comment)
    make-okvs-hook okvs-hook? okvs-hook-add! okvs-hook-delete! okvs-hook-run!)

  (begin

    ;;; --- bytevector helpers ---

    (define (%list->bytevector lst)
      (let* ((len (length lst)) (bv (make-bytevector len 0)))
        (let loop ((i 0) (lst lst))
          (if (null? lst)
              bv
              (begin (bytevector-u8-set! bv i (car lst))
                     (loop (+ i 1) (cdr lst)))))))

    (define (%bytevector-append . bvs)
      (let* ((total (apply + (map bytevector-length bvs)))
             (out (make-bytevector total 0)))
        (let loop ((bvs bvs) (offset 0))
          (if (null? bvs)
              out
              (begin (bytevector-copy! out offset (car bvs))
                     (loop (cdr bvs) (+ offset (bytevector-length (car bvs)))))))))

    (define (%bytevector-prefix? prefix bv)
      (let ((plen (bytevector-length prefix)))
        (and (<= plen (bytevector-length bv))
             (let loop ((i 0))
               (or (= i plen)
                   (and (= (bytevector-u8-ref prefix i) (bytevector-u8-ref bv i))
                        (loop (+ i 1))))))))

    ;;; --- ordered mapping over bytevector keys ---
    ;;; (srfi 146) mappings are immutable trees, so handing one out as a
    ;;; transaction's private "working copy" and only writing it back to the
    ;;; okvs on commit is O(1) and gives correct isolation/rollback for free.

    (define (%empty-tree) (mapping (make-default-comparator)))

    (define (%select-range tree start-key start-include? end-key end-include?)
      (let* ((t1 (if start-include? (mapping-range>= tree start-key) (mapping-range> tree start-key)))
             (t2 (if end-include? (mapping-range<= t1 end-key) (mapping-range< t1 end-key))))
        t2))

    (define (%config-ref config key default)
      (let ((entry (assq key config)))
        (if entry (cdr entry) default)))

    (define (%clamp-drop lst n)
      (if (or (not n) (<= n 0) (null? lst)) lst (%clamp-drop (cdr lst) (- n 1))))

    (define (%clamp-take lst n)
      (cond ((not n) lst)
            ((or (<= n 0) (null? lst)) '())
            (else (cons (car lst) (%clamp-take (cdr lst) (- n 1))))))

    (define (%apply-range-config pairs config)
      (let* ((pairs (if (%config-ref config 'reverse? #f) (reverse pairs) pairs))
             (pairs (%clamp-drop pairs (%config-ref config 'offset #f))))
        (%clamp-take pairs (%config-ref config 'limit #f))))

    (define (%opt-config args) (if (null? args) '() (car args)))

    ;;; --- minimal private hook object (see header comment) ---

    (define-record-type <okvs-hook>
      (%make-hook procs)
      okvs-hook?
      (procs %hook-procs %hook-procs-set!))

    (define (%make-empty-hook) (%make-hook '()))
    (define (make-okvs-hook) (%make-empty-hook))

    (define (okvs-hook-add! hook proc)
      (%hook-procs-set! hook (append (%hook-procs hook) (list proc))))

    (define (okvs-hook-delete! hook proc)
      (%hook-procs-set! hook (remove (lambda (p) (eq? p proc)) (%hook-procs hook))))

    (define (%hook-run hook . args)
      (for-each (lambda (proc) (apply proc args)) (%hook-procs hook)))

    (define (okvs-hook-run! hook . args) (apply %hook-run hook args))

    ;;; --- okvs and transactions ---

    (define-record-type <okvs>
      (%make-okvs tree begin-hook commit-hook)
      okvs?
      (tree %okvs-tree %okvs-tree-set!)
      (begin-hook %okvs-begin-hook)
      (commit-hook %okvs-commit-hook))

    (define-record-type <okvs-transaction>
      (%make-transaction okvs tree state)
      okvs-transaction?
      (okvs %transaction-okvs)
      (tree %transaction-tree %transaction-tree-set!)
      (state okvs-transaction-state))

    (define (%deref obj) (if (okvs-transaction? obj) (%transaction-tree obj) (%okvs-tree obj)))
    (define (%store! obj new-tree)
      (if (okvs-transaction? obj) (%transaction-tree-set! obj new-tree) (%okvs-tree-set! obj new-tree)))

    (define (okvs-open home . config) (%make-okvs (%empty-tree) (%make-empty-hook) (%make-empty-hook)))
    (define (okvs-close okvs . config) #t)

    (define (make-default-state) (make-hash-table))

    (define (okvs-hook-on-transaction-begin okvs) (%okvs-begin-hook okvs))
    (define (okvs-hook-on-transaction-commit okvs) (%okvs-commit-hook okvs))

    (define okvs-in-transaction
      (case-lambda
        ((okvs proc) (okvs-in-transaction okvs proc raise))
        ((okvs proc failure) (okvs-in-transaction okvs proc failure values))
        ((okvs proc failure success) (okvs-in-transaction okvs proc failure success make-default-state))
        ((okvs proc failure success make-state) (okvs-in-transaction okvs proc failure success make-state '()))
        ((okvs proc failure success make-state config)
         (let ((txn (%make-transaction okvs (%okvs-tree okvs) (make-state))))
           (guard (condition (#t (failure condition)))
             (%hook-run (%okvs-begin-hook okvs) txn)
             (let ((result (proc txn)))
               (%hook-run (%okvs-commit-hook okvs) txn)
               (%okvs-tree-set! okvs (%transaction-tree txn))
               (success result)))))))

    (define (okvs-ref obj key) (mapping-ref/default (%deref obj) key #f))
    (define (okvs-set! obj key value) (%store! obj (mapping-set (%deref obj) key value)))
    (define (okvs-delete! obj key) (%store! obj (mapping-delete (%deref obj) key)))

    (define (okvs-range-remove! obj start-key start-include? end-key end-include?)
      (let* ((removed (%select-range (%deref obj) start-key start-include? end-key end-include?))
             (keys (map car (mapping->alist removed))))
        (%store! obj (mapping-delete-all (%deref obj) keys))))

    (define (okvs-range obj start-key start-include? end-key end-include? . config)
      (let* ((tree (%select-range (%deref obj) start-key start-include? end-key end-include?))
             (pairs (mapping->alist tree)))
        (list->generator (%apply-range-config pairs (%opt-config config)))))

    (define (okvs-prefix-range obj prefix . config)
      (let* ((all-pairs (mapping->alist (%deref obj)))
             (pairs (filter (lambda (p) (%bytevector-prefix? prefix (car p))) all-pairs)))
        (list->generator (%apply-range-config pairs (%opt-config config)))))

    ;;; --- order-preserving pack/unpack (booleans, exact integers, strings, symbols) ---

    (define %tag-false 0)
    (define %tag-true 1)
    (define %tag-integer 2)
    (define %tag-string 3)
    (define %tag-symbol 4)

    (define (%magnitude->bytes n)
      (if (= n 0)
          '()
          (let loop ((n n) (acc '()))
            (if (= n 0) acc (loop (quotient n 256) (cons (remainder n 256) acc))))))

    (define (%bytes->magnitude bytes)
      (let loop ((bytes bytes) (acc 0))
        (if (null? bytes) acc (loop (cdr bytes) (+ (* acc 256) (car bytes))))))

    (define (%pack-integer n)
      (if (>= n 0)
          (let* ((bytes (%magnitude->bytes n)) (len (length bytes)))
            (%bytevector-append (bytevector %tag-integer 1 len) (%list->bytevector bytes)))
          (let* ((bytes (%magnitude->bytes (- n))) (len (length bytes))
                 (inv-bytes (map (lambda (b) (- 255 b)) bytes)))
            (%bytevector-append (bytevector %tag-integer 0 (- 255 len)) (%list->bytevector inv-bytes)))))

    (define (%bytevector-sublist bv start len)
      (let loop ((i 0) (acc '()))
        (if (= i len) (reverse acc) (loop (+ i 1) (cons (bytevector-u8-ref bv (+ start i)) acc)))))

    (define (%unpack-integer bv start)
      (let ((sign-byte (bytevector-u8-ref bv start))
            (len-byte (bytevector-u8-ref bv (+ start 1))))
        (if (= sign-byte 1)
            (let* ((len len-byte) (bytes (%bytevector-sublist bv (+ start 2) len)))
              (values (%bytes->magnitude bytes) (+ start 2 len)))
            (let* ((len (- 255 len-byte))
                   (inv-bytes (%bytevector-sublist bv (+ start 2) len))
                   (bytes (map (lambda (b) (- 255 b)) inv-bytes)))
              (values (- (%bytes->magnitude bytes)) (+ start 2 len))))))

    ;; String/symbol names are escaped so a NUL terminator is unambiguous:
    ;; a literal 0 byte becomes [0 255], and the run ends with a lone 0.
    (define (%pack-string-bytes utf8-bytes)
      (let ((len (bytevector-length utf8-bytes)))
        (let loop ((i 0) (acc '()))
          (if (= i len)
              (%list->bytevector (reverse (cons 0 acc)))
              (let ((b (bytevector-u8-ref utf8-bytes i)))
                (if (= b 0)
                    (loop (+ i 1) (cons 255 (cons 0 acc)))
                    (loop (+ i 1) (cons b acc))))))))

    (define (%unpack-string-bytes bv start)
      (let loop ((i start) (acc '()))
        (let ((b (bytevector-u8-ref bv i)))
          (if (= b 0)
              (if (and (< (+ i 1) (bytevector-length bv)) (= (bytevector-u8-ref bv (+ i 1)) 255))
                  (loop (+ i 2) (cons 0 acc))
                  (values (reverse acc) (+ i 1)))
              (loop (+ i 1) (cons b acc))))))

    (define (%pack-item item)
      (cond
        ((eq? item #f) (bytevector %tag-false))
        ((eq? item #t) (bytevector %tag-true))
        ((and (integer? item) (exact? item)) (%pack-integer item))
        ((string? item) (%bytevector-append (bytevector %tag-string) (%pack-string-bytes (string->utf8 item))))
        ((symbol? item)
         (%bytevector-append (bytevector %tag-symbol) (%pack-string-bytes (string->utf8 (symbol->string item)))))
        (else (error "engine-pack: unsupported item type" item))))

    (define (%unpack-item bv start)
      (let ((tag (bytevector-u8-ref bv start)))
        (cond
          ((= tag %tag-false) (values #f (+ start 1)))
          ((= tag %tag-true) (values #t (+ start 1)))
          ((= tag %tag-integer) (%unpack-integer bv (+ start 1)))
          ((= tag %tag-string)
           (let-values (((bytes next) (%unpack-string-bytes bv (+ start 1))))
             (values (utf8->string (%list->bytevector bytes)) next)))
          ((= tag %tag-symbol)
           (let-values (((bytes next) (%unpack-string-bytes bv (+ start 1))))
             (values (string->symbol (utf8->string (%list->bytevector bytes))) next)))
          (else (error "engine-unpack: unsupported tag" tag)))))

    (define (%default-pack . items) (apply %bytevector-append (map %pack-item items)))

    (define (%default-unpack bv)
      (let ((len (bytevector-length bv)))
        (let loop ((offset 0) (acc '()))
          (if (= offset len)
              (reverse acc)
              (let-values (((item next) (%unpack-item bv offset)))
                (loop next (cons item acc)))))))

    ;;; --- engine record: generic dispatch over the procedures above ---

    (define-record-type <engine>
      (make-engine open close in-transaction ref set delete range-remove range prefix-range
                   hook-on-transaction-begin hook-on-transaction-commit pack unpack)
      engine?
      (open %engine-open-proc)
      (close %engine-close-proc)
      (in-transaction %engine-in-transaction-proc)
      (ref %engine-ref-proc)
      (set %engine-set-proc)
      (delete %engine-delete-proc)
      (range-remove %engine-range-remove-proc)
      (range %engine-range-proc)
      (prefix-range %engine-prefix-range-proc)
      (hook-on-transaction-begin %engine-hook-on-transaction-begin-proc)
      (hook-on-transaction-commit %engine-hook-on-transaction-commit-proc)
      (pack %engine-pack-proc)
      (unpack %engine-unpack-proc))

    (define (engine-open engine home . config) (apply (%engine-open-proc engine) home config))
    (define (engine-close engine okvs . config) (apply (%engine-close-proc engine) okvs config))
    (define (engine-in-transaction engine okvs proc . rest)
      (apply (%engine-in-transaction-proc engine) okvs proc rest))
    (define (engine-ref engine okvs key) ((%engine-ref-proc engine) okvs key))
    (define (engine-set! engine okvs key value) ((%engine-set-proc engine) okvs key value))
    (define (engine-delete! engine okvs key) ((%engine-delete-proc engine) okvs key))
    (define (engine-range-remove! engine okvs start-key start-include? end-key end-include?)
      ((%engine-range-remove-proc engine) okvs start-key start-include? end-key end-include?))
    (define (engine-range engine okvs start-key start-include? end-key end-include? . config)
      (apply (%engine-range-proc engine) okvs start-key start-include? end-key end-include? config))
    (define (engine-prefix-range engine okvs prefix . config)
      (apply (%engine-prefix-range-proc engine) okvs prefix config))
    (define (engine-hook-on-transaction-begin engine okvs) ((%engine-hook-on-transaction-begin-proc engine) okvs))
    (define (engine-hook-on-transaction-commit engine okvs) ((%engine-hook-on-transaction-commit-proc engine) okvs))
    (define (engine-pack engine . items) (apply (%engine-pack-proc engine) items))
    (define (engine-unpack engine bv) ((%engine-unpack-proc engine) bv))

    (define (make-default-engine)
      (make-engine okvs-open okvs-close okvs-in-transaction okvs-ref okvs-set! okvs-delete!
                   okvs-range-remove! okvs-range okvs-prefix-range
                   okvs-hook-on-transaction-begin okvs-hook-on-transaction-commit
                   %default-pack %default-unpack))

    ))
