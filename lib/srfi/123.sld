;;; SRFI 123 — Generic accessor and modifier operators
;;;
;;; `ref`/`ref*`/`~` dispatch on the runtime type of `object` to fetch a
;;; "field" — a key whose meaning is type-specific: the symbols `car`/`cdr`
;;; or a non-negative integer for pairs (list-ref style), an integer index
;;; for vectors/strings/bytevectors, an arbitrary key for hash tables, or
;;; the symbol `*` (the single value slot) for SRFI 111 boxes.
;;;
;;;   (ref object field)          ; error if the field is absent
;;;   (ref object field default)  ; only meaningful for a sparse type
;;;   (ref* object field field* ...)  = (ref (ref (ref object field) ...) ...)
;;;   (~ object field field* ...)     ; synonym for ref*, same setter
;;;
;;; Only hash tables are a sparse type here (per spec, "Only hashtables are
;;; a sparse type"): `(ref table key)` errors if `key` is absent, `(ref
;;; table key default)` returns `default` instead. Every other built-in
;;; type errors if a `default` argument is supplied at all — enforced not
;;; by special-casing but simply because the underlying accessor
;;; (`vector-ref`, `string-ref`, ...) rejects the extra argument, exactly
;;; per spec: "If object is not of a sparse type, then providing the
;;; default argument is an error." `ref*`/`~` never accept a default at
;;; any step of the chain, so a sparse-type miss mid-chain is always an
;;; error (spec: "ref* cannot take default arguments for any fields it
;;; accesses").
;;;
;;; Auto-registered types (the spec's "valid types for object" minus what
;;; this codebase doesn't have): pairs, vectors, strings, bytevectors, hash
;;; tables (SRFI 69), and SRFI 111 boxes. Non-opaque records and SRFI-4
;;; typed vectors are NOT auto-registered — this codebase has no SRFI-4
;;; (so bytevectors are always accessed with plain 8-bit-unsigned
;;; `bytevector-u8-ref`/-set! semantics, per spec's fallback for systems
;;; without SRFI-4), and record support was out of scope for this port.
;;; `register-getter-with-setter!` remains available for anyone who wants
;;; to wire up a record type (or any other disjoint type) by hand.
;;;
;;; set! support: Kaappi's compiler already desugars
;;; `(set! (proc args ...) val)` into `((setter proc) args ... val)`
;;; whenever `setter` (SRFI 17's generalized-set! registry) is in scope
;;; (see `compileSet` in compiler_lambda.zig / `lowerSet` in ir.zig) — i.e.
;;; SRFI 17 is already a core compiler mechanism here, not something this
;;; library has to invent. `ref` and `ref*`/`~` are therefore both built
;;; with `(srfi 17)`'s `getter-with-setter`, so both
;;; `(set! (ref object field) value)` and
;;; `(set! (~ object f1 f2 f3) value)` work. `setter` and
;;; `getter-with-setter` are re-exported here so importing just
;;; `(srfi 123)` is enough — no need to separately import `(srfi 17)`.
(define-library (srfi 123)
  (import (scheme base)
          (scheme case-lambda)
          (srfi 17)
          (srfi 69)
          (srfi 111))
  (export
   ref ref* ~ register-getter-with-setter!
   setter getter-with-setter)
  (begin
    ;; -----------------------------------------------------------------
    ;; Dispatch registry: a list of (predicate getter sparse?) triples,
    ;; most-recently-registered first. type-of lookup uses the first
    ;; matching predicate, so a later `register-getter-with-setter!` call
    ;; takes priority over anything registered earlier — including the
    ;; six built-in types registered below.
    ;; -----------------------------------------------------------------
    (define %srfi-123-registry '())

    (define (register-getter-with-setter! type getter sparse?)
      (set! %srfi-123-registry
            (cons (list type getter sparse?) %srfi-123-registry)))

    (define (%srfi-123-find-entry object)
      (let loop ((entries %srfi-123-registry))
        (cond
          ((null? entries) #f)
          (((caar entries) object) (car entries))
          (else (loop (cdr entries))))))

    ;; -----------------------------------------------------------------
    ;; Pairs: field is 'car, 'cdr, or a non-negative integer index, as
    ;; with list-ref. Example: (ref '(a b c . d) 'cdr) => (b c . d).
    ;; -----------------------------------------------------------------
    (define (%srfi-123-pair-ref object field)
      (cond
        ((eq? field 'car) (car object))
        ((eq? field 'cdr) (cdr object))
        ((and (integer? field) (>= field 0))
         (let loop ((p object) (n field))
           (if (= n 0) (car p) (loop (cdr p) (- n 1)))))
        (else
         (error "srfi 123: ref: invalid field for pair (expected car, cdr, or a non-negative integer)"
                field))))

    (define (%srfi-123-pair-set! object field value)
      (cond
        ((eq? field 'car) (set-car! object value))
        ((eq? field 'cdr) (set-cdr! object value))
        ((and (integer? field) (>= field 0))
         (let loop ((p object) (n field))
           (if (= n 0) (set-car! p value) (loop (cdr p) (- n 1)))))
        (else
         (error "srfi 123: set!: invalid field for pair (expected car, cdr, or a non-negative integer)"
                field))))

    ;; -----------------------------------------------------------------
    ;; SRFI 111 boxes: the single value slot is denoted by the symbol *.
    ;; -----------------------------------------------------------------
    (define (%srfi-123-box-ref object field)
      (if (eq? field '*)
          (unbox object)
          (error "srfi 123: ref: invalid field for box (expected *)" field)))

    (define (%srfi-123-box-set! object field value)
      (if (eq? field '*)
          (set-box! object value)
          (error "srfi 123: set!: invalid field for box (expected *)" field)))

    ;; -----------------------------------------------------------------
    ;; Built-in type registration. Relative order among these six doesn't
    ;; matter: the predicates are mutually exclusive in this codebase.
    ;; -----------------------------------------------------------------
    (register-getter-with-setter!
     pair?
     (getter-with-setter %srfi-123-pair-ref %srfi-123-pair-set!)
     #f)

    ;; vector-ref/string-ref already have setters registered by (srfi 17)
    ;; itself (vector-set!/string-set!) — reuse them as-is.
    (register-getter-with-setter! vector? vector-ref #f)
    (register-getter-with-setter! string? string-ref #f)

    ;; No SRFI-4 in this codebase, so bytevectors are always 8-bit unsigned.
    (register-getter-with-setter!
     bytevector?
     (getter-with-setter bytevector-u8-ref bytevector-u8-set!)
     #f)

    ;; The one sparse built-in type. hash-table-ref/default already has the
    ;; exact (table key default) shape `ref` needs, both when the caller
    ;; supplies a default and internally when it doesn't (see %ref below).
    (register-getter-with-setter!
     hash-table?
     (getter-with-setter hash-table-ref/default hash-table-set!)
     #t)

    (register-getter-with-setter!
     box?
     (getter-with-setter %srfi-123-box-ref %srfi-123-box-set!)
     #f)

    ;; -----------------------------------------------------------------
    ;; %ref: the getter half of `ref`, as a case-lambda over arity.
    ;;  - (object field): non-sparse types call (getter object field).
    ;;    Sparse types call (getter object field <fresh-sentinel>) and
    ;;    signal an error if the getter had to hand that exact sentinel
    ;;    back (i.e. the field was genuinely absent and no default was
    ;;    given). A freshly-allocated pair is minted per call so it can
    ;;    never coincide with a real stored value.
    ;;  - (object field default): unconditionally (getter object field
    ;;    default) regardless of sparseness — for a non-sparse type this
    ;;    relies on the underlying accessor rejecting the extra argument,
    ;;    which is exactly the spec-mandated error.
    ;; -----------------------------------------------------------------
    (define %ref
      (case-lambda
        ((object field)
         (let ((entry (%srfi-123-find-entry object)))
           (if (not entry)
               (error "srfi 123: ref: no applicable type for object" object)
               (let ((getter (cadr entry))
                     (sparse? (car (cddr entry))))
                 (if sparse?
                     (let* ((not-found (cons #f #f))
                            (result (getter object field not-found)))
                       (if (eq? result not-found)
                           (error "srfi 123: ref: object has no entry for field"
                                  object field)
                           result))
                     (getter object field))))))
        ((object field default)
         (let ((entry (%srfi-123-find-entry object)))
           (if (not entry)
               (error "srfi 123: ref: no applicable type for object" object)
               ((cadr entry) object field default))))))

    (define (%ref* object field . fields)
      (if (null? fields)
          (%ref object field)
          (apply %ref* (%ref object field) fields)))

    ;; The field-mutator behind ref's setter: look up object's registered
    ;; getter and dispatch to *its* SRFI-17 setter.
    (define (%srfi-123-set! object field value)
      (let ((entry (%srfi-123-find-entry object)))
        (if (not entry)
            (error "srfi 123: set!: no applicable type for object" object)
            ((setter (cadr entry)) object field value))))

    (define ref
      (getter-with-setter
       %ref
       (lambda (object field value) (%srfi-123-set! object field value))))

    ;; ref*'s setter walks the field chain: every field but the last is
    ;; read with %ref (never with a default) to find the next sub-object;
    ;; the last field is mutated in place with %srfi-123-set!.
    (define (%ref*-set! object field . more)
      (let loop ((obj object) (fld field) (rest more))
        (if (null? (cdr rest))
            (%srfi-123-set! obj fld (car rest))
            (loop (%ref obj fld) (car rest) (cdr rest)))))

    (define ref* (getter-with-setter %ref* %ref*-set!))

    ;; ~ is a plain synonym: the very same procedure object as ref*, so
    ;; (setter ~) automatically resolves to the same registered setter.
    (define ~ ref*)))
