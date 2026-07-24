;;; SRFI 237: R6RS Records, refined for R7RS.
;;;
;;; The syntactic layer (`define-record-type` accepting R6RS clause syntax
;;; -- fields/parent/protocol/sealed/opaque/nongenerative) is entirely a
;;; Zig-level desugarer in src/vm_records.zig (handleDefineRecordTypeR6RS),
;;; exactly like R7RS's own `define-record-type` already is -- it needs no
;;; import to work and this library exports nothing new for it. See that
;;; file's header comment for the desugaring design (the "materialize the
;;; parent instance, then re-extract its fields" strategy replacing R6RS's
;;; own CPS-style n/p protocol threading) and its documented limitation
;;; (top-level only, not yet inside a library body).
;;;
;;; This library is the PROCEDURAL and INSPECTION layers: creating record
;;; types and constructor/predicate/accessor/mutator procedures at runtime
;;; from plain data (rather than at macro-expansion time from literal
;;; syntax), and introspecting an existing record type. Built on
;;; `(srfi 237 primitives)` (src/primitives_srfi237.zig) -- the registry
;;; pre-registers every built-in Lib into vm.libraries at startup keyed by
;;; canonical name, so a same-named `.sld` is never reached; the native
;;; primitives therefore live under the sub-library name
;;; `(srfi 237 primitives)` (`.srfi_237_primitives`), and this file is the
;;; only place the public `(srfi 237)` name is defined -- same already-
;;; solved shadowing problem as SRFI 181/248.
;;;
;;; record-constructor's protocol/inheritance threading uses the SAME
;;; materialize-and-re-extract strategy as the syntactic desugarer (calling
;;; a parent RCD's own constructor via `apply`, then reading its fields
;;; back out via the low-level ref primitive) -- see vm_records.zig's
;;; header comment for why this is behaviorally exact and needs no per-
;;; level special-casing regardless of how deep the parent-RCD chain goes
;;; or which levels have protocols.
;;;
;;; NOT implemented (documented gaps, not oversights):
;;;   - `port-read-rtd`/`port-write-rtd`: a minor RTD-serialization
;;;     convenience, unrelated to the SRFI's core value; no other SRFI in
;;;     this codebase does datum-to-port RTD serialization either.
;;;   - `define-record-name` and the deprecated
;;;     `record-type-descriptor`/`record-constructor-descriptor` SYNTAX
;;;     (SRFI 237 itself marks the latter deprecated -- implementing
;;;     deprecated API surface ahead of the rest would be an odd priority).
;;;   - SRFI 237's own 4-/2-element `(<rtd name> <record name> ...)`
;;;     name-spec extension (a rare naming refinement, not core
;;;     functionality) -- the base R6RS 2-form name-spec (bare symbol, or
;;;     `(<name> <ctor> <pred>)`) is fully supported.
(define-library (srfi 237)
  (import (scheme base) (srfi 237 primitives))
  (export
    ;; procedural
    make-record-type-descriptor record-type-descriptor?
    make-record-descriptor record-descriptor-rtd record-descriptor-parent record-descriptor?
    record-constructor record-predicate record-accessor record-mutator
    ;; inspection
    record? record-rtd record-type-name record-type-parent record-type-uid
    record-type-generative? record-type-sealed? record-type-opaque?
    record-type-field-names record-field-mutable? record-uid->rtd)
  (begin

    (define (make-record-type-descriptor name parent uid sealed? opaque? fields)
      (%make-record-type-descriptor
        (symbol->string name)
        (if parent parent #f)
        (if uid (symbol->string uid) #f)
        (if sealed? #t #f)
        (if opaque? #t #f)
        (map (lambda (fspec)
               (cons (symbol->string (cadr fspec)) (eq? (car fspec) 'mutable)))
             (vector->list fields))))

    (define (record-type-descriptor? v) (%record-type? v))

    ;; --- record-constructor-descriptor (here, "record descriptor") -----
    ;;
    ;; A plain, ordinary record wrapping an rtd + optional parent rcd +
    ;; optional protocol -- the Zig layer never sees this type at all.
    (define-record-type <record-descriptor>
      (%make-record-descriptor rtd parent protocol)
      record-descriptor?
      (rtd record-descriptor-rtd)
      (parent record-descriptor-parent)
      (protocol record-descriptor-protocol))

    (define (make-record-descriptor rtd parent-rcd protocol)
      (%make-record-descriptor rtd (if parent-rcd parent-rcd #f) (if protocol protocol #f)))

    (define (record-constructor rcd)
      (let ((rtd (record-descriptor-rtd rcd))
            (parent-rcd (record-descriptor-parent rcd))
            (protocol (record-descriptor-protocol rcd)))
        (if parent-rcd
            (%record-constructor/parent rtd parent-rcd protocol)
            (%record-constructor/root rtd protocol))))

    (define (%record-constructor/root rtd protocol)
      (let ((raw (lambda field-args (apply %make-record rtd field-args))))
        (if protocol (protocol raw) raw)))

    (define (%record-constructor/parent rtd parent-rcd protocol)
      (let* ((parent-rtd (record-descriptor-rtd parent-rcd))
             (parent-ctor (record-constructor parent-rcd))
             (own-count (- (%record-type-total-field-count rtd)
                           (%record-type-total-field-count parent-rtd))))
        (define (extract-parent-fields parent-inst)
          (let loop ((i 0) (acc '()))
            (if (= i (%record-type-total-field-count parent-rtd))
                (reverse acc)
                (loop (+ i 1) (cons (%record-ref/inherit parent-inst i parent-rtd) acc)))))
        (if protocol
            (protocol (lambda n-args
                        (let ((parent-inst (apply parent-ctor n-args)))
                          (lambda own-args
                            (apply %make-record rtd (append (extract-parent-fields parent-inst) own-args))))))
            (lambda call-args
              (let* ((split (%record-split-args call-args own-count))
                     (parent-inst (apply parent-ctor (car split))))
                (apply %make-record rtd (append (extract-parent-fields parent-inst) (cdr split))))))))

    (define (record-predicate rtd)
      (lambda (v) (%record?/inherit v rtd)))

    ;; field: a field NAME (symbol) or an absolute 0-based index (exact
    ;; integer) into rtd's full (inherited-then-own) field layout. A name
    ;; not among rtd's OWN fields (record-type-field-names only reports a
    ;; type's own fields, never inherited ones) recurses into the parent --
    ;; each level's own fields start right after its immediate parent's
    ;; total field count, so no accumulated offset needs to be threaded
    ;; through the recursion.
    (define (%resolve-field-index rtd field)
      (if (integer? field)
          field
          (let ((parent (record-type-parent rtd)))
            (let ((parent-offset (if parent (%record-type-total-field-count parent) 0)))
              (let loop ((names (record-type-field-names rtd)) (i parent-offset))
                (cond
                  ((null? names)
                   (if parent (%resolve-field-index parent field) (error "unknown field" field)))
                  ((eq? (car names) field) i)
                  (else (loop (cdr names) (+ i 1)))))))))

    (define (record-accessor rtd field)
      (let ((idx (%resolve-field-index rtd field)))
        (lambda (r) (%record-ref/inherit r idx rtd))))

    (define (record-mutator rtd field)
      (let ((idx (%resolve-field-index rtd field)))
        (lambda (r v) (%record-set!/inherit r idx v rtd))))

    (define (record? v) (%record?/any v))
    (define (record-rtd r) (%record-rtd r))
    (define (record-type-name rtd) (%record-type-name rtd))
    (define (record-type-parent rtd) (%record-type-parent rtd))
    (define (record-type-uid rtd) (%record-type-uid rtd))
    (define (record-type-generative? rtd) (%record-type-generative? rtd))
    (define (record-type-sealed? rtd) (%record-type-sealed? rtd))
    (define (record-type-opaque? rtd) (%record-type-opaque? rtd))
    (define (record-type-field-names rtd) (%record-type-field-names rtd))
    (define (record-field-mutable? rtd own-field-index) (%record-field-mutable? rtd own-field-index))
    (define (record-uid->rtd uid) (%record-uid->rtd (symbol->string uid)))))
