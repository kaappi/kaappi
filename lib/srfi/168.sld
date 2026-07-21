;;; SRFI 168 — Generic Tuple Store Database
;;;
;;; SRFI 168 layers a fixed-arity tuple store (an n-tuple "nstore" — a
;;; triplestore when items has 3 fields, a quadstore at 4, and so on) with
;;; pattern-based, Datalog-flavored queries on top of SRFI 167's ordered
;;; key-value store. Per SRFI 168's own post-finalization note (see the
;;; header of lib/srfi/167.sld), the author flagged this design too as
;;; having "infelicities" and recommended treating it as inspiration rather
;;; than a interface to depend on long-term — this port implements its
;;; actual procedures and the worked example faithfully, scoped the same
;;; pragmatic way as 167:
;;;
;;;  - An `nstore` does not hold a database handle. Per the spec, it is a
;;;    schema descriptor (an engine + a key prefix + the tuple's field
;;;    names); the actual store is threaded through separately as the
;;;    `transaction` argument to every `nstore-*` call (an okvs *or* a
;;;    transaction — both work, since SRFI 167's read/write procedures
;;;    dispatch on either). This lets one engine/store host multiple
;;;    nstores side by side, distinguished by prefix.
;;;  - Storage is keys-only: `nstore-add!` packs `(prefix ++ items)` into a
;;;    single sortable bytevector with `engine-pack` and stores it with an
;;;    empty bytevector value — the key already encodes the whole tuple, so
;;;    there is nothing else worth storing. This is the same design real
;;;    triplestores use for their index tables.
;;;  - Only one physical ordering of each tuple is indexed (the field order
;;;    given to `nstore`), not the full set of index permutations a
;;;    production triplestore maintains for fast lookups on every field
;;;    combination. `nstore-select` therefore prefix-scans that single
;;;    index and pattern-matches in memory: correct, and — because all
;;;    non-variable positions of a pattern are held constant across every
;;;    match — automatically ordered by the one remaining variable's value
;;;    when the pattern has exactly one (matching the spec's requirement),
;;;    but O(n) in the nstore's tuple count rather than O(log n + k). Fine
;;;    at reference/testing scale, wrong for a production store.
;;;  - `nstore-where` materializes its input generator and each pattern's
;;;    match generator into lists (via SRFI 158's `generator->list`) rather
;;;    than threading laziness through SRFI 158's `gflatten`; since the
;;;    underlying `nstore-select` already materializes its own result list
;;;    internally, no laziness is actually lost.
;;;  - Hooks reuse SRFI 167's minimal hook object directly (`make-okvs-hook`
;;;    et al.) instead of defining a second one.
;;;
;;; Bindings are represented as SRFI 146 hash-mappings (`(srfi 146 hash)`,
;;; i.e. `hashmap`), matching the spec's text ("a mapping of bindings")
;;; rather than the `(scheme mapping hash)`/`hashmap-ref` names the spec's
;;; own worked example calls out to — that is a different Scheme
;;; implementation's library-naming convention for the same SRFI 146 hash
;;; sub-library Kaappi exposes as `(srfi 146 hash)`.

(define-library (srfi 168)
  (import (scheme base)
          (srfi 1) (srfi 128) (srfi 146 hash) (srfi 158) (srfi 167))
  (export
    nstore nstore?
    nstore-ask? nstore-add! nstore-delete!
    nstore-var nstore-var? nstore-var-name
    nstore-select nstore-where nstore-query
    nstore-hook-on-add nstore-hook-on-delete)

  (begin

    (define (%opt-config args) (if (null? args) '() (car args)))
    (define (%config-ref config key default)
      (let ((entry (assq key config))) (if entry (cdr entry) default)))

    (define (%clamp-drop lst n)
      (if (or (not n) (<= n 0) (null? lst)) lst (%clamp-drop (cdr lst) (- n 1))))
    (define (%clamp-take lst n)
      (cond ((not n) lst)
            ((or (<= n 0) (null? lst)) '())
            (else (cons (car lst) (%clamp-take (cdr lst) (- n 1))))))
    (define (%apply-offset-limit lst config)
      (%clamp-take (%clamp-drop lst (%config-ref config 'offset #f)) (%config-ref config 'limit #f)))

    ;;; --- nstore-var: a disjoint "placeholder" type for query patterns ---

    (define-record-type <nstore-var>
      (nstore-var name)
      nstore-var?
      (name nstore-var-name))

    ;;; --- nstore: schema descriptor (engine + key prefix + field names) ---

    (define-record-type <nstore>
      (%make-nstore engine prefix items add-hook delete-hook)
      nstore?
      (engine %nstore-engine)
      (prefix %nstore-prefix)
      (items %nstore-items)
      (add-hook %nstore-add-hook)
      (delete-hook %nstore-delete-hook))

    (define (nstore engine prefix items)
      (%make-nstore engine prefix items (make-okvs-hook) (make-okvs-hook)))

    (define (nstore-hook-on-add ns) (%nstore-add-hook ns))
    (define (nstore-hook-on-delete ns) (%nstore-delete-hook ns))

    (define (%check-arity ns items who)
      (if (not (= (length items) (length (%nstore-items ns))))
          (error (string-append who ": wrong number of items for this nstore")
                 items (%nstore-items ns))))

    (define (%tuple-key ns items)
      (apply engine-pack (%nstore-engine ns) (append (%nstore-prefix ns) items)))

    ;;; --- mutation ---

    (define (nstore-ask? transaction ns items)
      (%check-arity ns items "nstore-ask?")
      (if (engine-ref (%nstore-engine ns) transaction (%tuple-key ns items)) #t #f))

    (define (nstore-add! transaction ns items)
      (%check-arity ns items "nstore-add!")
      (okvs-hook-run! (%nstore-add-hook ns) transaction items)
      (engine-set! (%nstore-engine ns) transaction (%tuple-key ns items) (bytevector))
      (if #f #f))

    (define (nstore-delete! transaction ns items)
      (%check-arity ns items "nstore-delete!")
      (okvs-hook-run! (%nstore-delete-hook ns) transaction items)
      (engine-delete! (%nstore-engine ns) transaction (%tuple-key ns items))
      (if #f #f))

    ;;; --- pattern matching ---

    (define (%drop lst n) (if (<= n 0) lst (%drop (cdr lst) (- n 1))))

    (define (%all-tuples transaction ns)
      (let* ((eng (%nstore-engine ns))
             (prefix-key (apply engine-pack eng (%nstore-prefix ns)))
             (gen (engine-prefix-range eng transaction prefix-key))
             (plen (length (%nstore-prefix ns))))
        (map (lambda (pair) (%drop (engine-unpack eng (car pair)) plen))
             (generator->list gen))))

    ;; Matches a pattern (a list where each position is a literal or an
    ;; nstore-var) against a stored tuple. Returns a SRFI 146 hash-mapping
    ;; of variable-name -> value on success, #f on failure.
    (define (%pattern->hashmap pattern tuple)
      (let loop ((pat pattern) (tup tuple) (hm (hashmap (make-default-comparator))))
        (cond
          ((and (null? pat) (null? tup)) hm)
          ((or (null? pat) (null? tup)) #f)
          ((nstore-var? (car pat))
           (loop (cdr pat) (cdr tup) (hashmap-set hm (nstore-var-name (car pat)) (car tup))))
          ((equal? (car pat) (car tup)) (loop (cdr pat) (cdr tup) hm))
          (else #f))))

    (define (nstore-select transaction ns pattern . config)
      (%check-arity ns pattern "nstore-select")
      (let* ((tuples (%all-tuples transaction ns))
             (bindings (filter-map (lambda (tuple) (%pattern->hashmap pattern tuple)) tuples)))
        (list->generator (%apply-offset-limit bindings (%opt-config config)))))

    (define (%substitute-pattern pattern binding)
      (map (lambda (item)
             (if (and (nstore-var? item) (hashmap-contains? binding (nstore-var-name item)))
                 (hashmap-ref binding (nstore-var-name item))
                 item))
           pattern))

    (define (%hashmap-merge base additions)
      (hashmap-fold (lambda (k v acc) (hashmap-set acc k v)) base additions))

    (define (nstore-where transaction ns pattern)
      (lambda (input-gen)
        (let* ((input-bindings (generator->list input-gen))
               (result-bindings
                 (append-map
                   (lambda (binding)
                     (let* ((substituted (%substitute-pattern pattern binding))
                            (extensions (generator->list (nstore-select transaction ns substituted))))
                       (map (lambda (ext) (%hashmap-merge binding ext)) extensions)))
                   input-bindings)))
          (list->generator result-bindings))))

    (define-syntax nstore-query
      (syntax-rules ()
        ((_ value) value)
        ((_ value f rest ...) (nstore-query (f value) rest ...))))

    ))
