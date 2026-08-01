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
;;; A record descriptor is a SUBTYPE of record-type descriptor (SRFI 237:
;;; "The type of record descriptors is a subtype of the type of record-type
;;; descriptors ... Whenever a syntax or procedure described below expects a
;;; record-type descriptor, the result is equivalent to when the record-type
;;; descriptor is replaced by its underlying simple record-type descriptor").
;;; Every procedure below that takes an `rtd` therefore runs it through
;;; `%rtd` first, and every procedure that takes an `rd` runs it through
;;; `%as-rcd`, which conversely accepts a simple rtd by rebuilding the
;;; protocol-less descriptor chain it is equivalent to. That two-way widening
;;; is what lets the syntactic and procedural layers inherit from each other,
;;; which is the SRFI's stated reason for existing (kaappi#1974).
;;;
;;; NOT implemented (documented gaps, not oversights):
;;;   - `port-read-rtd`/`port-write-rtd`: a minor RTD-serialization
;;;     convenience, unrelated to the SRFI's core value; no other SRFI in
;;;     this codebase does datum-to-port RTD serialization either.
;;;   - `define-record-name` and the deprecated
;;;     `record-type-descriptor`/`record-constructor-descriptor` SYNTAX
;;;     (SRFI 237 itself marks the latter deprecated -- implementing
;;;     deprecated API surface ahead of the rest would be an odd priority).
;;;     The deprecated PROCEDURES `make-record-constructor-descriptor` and
;;;     `record-constructor-descriptor?` are provided, since they are plain
;;;     aliases and their absence made a test written against the R6RS
;;;     spelling fail on the missing binding rather than on the behavior
;;;     under test (kaappi#1974).
;;;   - SRFI 237's own 4-/2-element `(<rtd name> <record name> ...)`
;;;     name-spec extension (a rare naming refinement, not core
;;;     functionality) -- the base R6RS 2-form name-spec (bare symbol, or
;;;     `(<name> <ctor> <pred>)`) is fully supported.
;;;   - A `(parent <expr>)` clause whose <expr> is not a record name:
;;;     vm_records.zig resolves the parent clause as a literal symbol at
;;;     expansion time, so SRFI 237's "expression evaluating to a
;;;     record-type descriptor or record descriptor" form is unsupported.
;;;     The reverse direction works: `make-record-type-descriptor` and the
;;;     7-argument `make-record-descriptor` both accept a syntactically
;;;     defined type's name as their `parent`.
;;;   - The <record name> bound by the syntactic `define-record-type`
;;;     evaluates to the type's simple record-type descriptor, where SRFI
;;;     237 specifies the underlying record DESCRIPTOR. Nothing observable
;;;     is lost -- `record-constructor` and every `rd`-taking procedure
;;;     accept a simple rtd (see `%as-rcd`), so `(record-constructor
;;;     <record name>)` works -- but `(record-descriptor? <record name>)`
;;;     answers #f. Closing it properly needs the descriptor type to be an
;;;     engine-level heap type rather than the portable `define-record-type`
;;;     below, since the Zig desugarer cannot see a library-level record
;;;     type; five shipped SRFIs (57, 131, 136, 150, 240) pass the record
;;;     name straight to `%`-prefixed rtd primitives today.
;;;
;;; R6RS specifies `&assertion` for the conditions this layer rejects
;;; (opaque `record-rtd`, immutable `record-mutator`, out-of-range `k`).
;;; Kaappi has no R6RS condition-type hierarchy, so each raises a plain
;;; catchable error object naming the procedure and the offending value.
(define-library (srfi 237)
  ;; (kaappi primitives): the internal %-prefixed helpers this file calls
  ;; below. They used to arrive with (scheme base), which reserved their
  ;; names against every user library (kaappi#1856).
  (import (scheme base) (srfi 237 primitives) (kaappi primitives))
  (export
    ;; procedural
    make-record-type-descriptor record-type-descriptor?
    make-record-descriptor record-descriptor-rtd record-descriptor-parent record-descriptor?
    make-record-constructor-descriptor record-constructor-descriptor?
    record-constructor record-predicate record-accessor record-mutator
    ;; inspection
    record? record-rtd record-type-name record-type-parent record-type-uid
    record-type-generative? record-type-sealed? record-type-opaque?
    record-type-field-names record-field-mutable? record-uid->rtd)
  (begin

    ;; --- record-constructor-descriptor (here, "record descriptor") -----
    ;;
    ;; A plain, ordinary record wrapping an rtd + optional parent rd +
    ;; optional protocol -- the Zig layer never sees this type at all. The
    ;; raw accessors are %-prefixed because the PUBLIC
    ;; `record-descriptor-rtd`/`record-descriptor-parent` below are wider
    ;; than the generated field accessors: they also answer for a simple
    ;; rtd, per the SRFI's "underlying simple record-type descriptor of a
    ;; simple record-type descriptor is the simple record-type descriptor
    ;; itself".
    ;;
    ;; `ctor` is a ready-made constructor to hand back verbatim, bypassing
    ;; protocol application entirely -- #f for every descriptor a user
    ;; builds, and set only by `%fresh-rcd` below when it recovers the
    ;; finished constructor a syntactic `define-record-type` already made.
    (define-record-type <record-descriptor>
      (%make-rd rtd parent protocol ctor)
      record-descriptor?
      (rtd %rd-rtd)
      (parent %rd-parent)
      (protocol %rd-protocol)
      (ctor %rd-ctor))

    ;; The record-type descriptor `x` stands for: itself when simple, its
    ;; underlying one when `x` is a record descriptor. Every `rtd` parameter
    ;; in this library goes through here, which is also the only eager
    ;; type check some of them get -- `record-accessor`/`record-predicate`
    ;; used to hand back a working-looking procedure for a non-rtd and only
    ;; fail once it was called (kaappi#1974).
    (define (%rtd who x)
      (cond ((%record-type? x) x)
            ((record-descriptor? x) (%rd-rtd x))
            (else (error (string-append who ": not a record-type descriptor") x))))

    ;; The record descriptor `x` stands for -- see `%fresh-rcd` for how one
    ;; is derived from a bare rtd. This is what makes a type defined by the
    ;; syntactic layer (whose <record name> evaluates to a simple rtd) usable
    ;; as `record-constructor`'s argument and as another type's parent
    ;; descriptor.
    (define (%as-rcd who x)
      (cond ((record-descriptor? x) x)
            ((%record-type? x) (%fresh-rcd x))
            (else (error (string-append who ": not a record descriptor") x))))

    ;; The descriptor a bare rtd stands for: no protocol of its own, parent
    ;; chain rebuilt from `record-type-parent`.
    ;;
    ;; A protocol lives on the record DESCRIPTOR, so an rtd alone cannot
    ;; carry one -- and constructing through a synthesized protocol-less
    ;; descriptor would quietly bypass a protocol and store the raw
    ;; arguments. For a type the syntactic layer defined that is recoverable:
    ;; `%record-type-constructor` returns the finished constructor the
    ;; protocol was already applied to, which this stashes in the `ctor`
    ;; slot. Only when the type is known to have a protocol AND that
    ;; constructor cannot be recovered is there nothing faithful to return,
    ;; and then it refuses -- a wrong field value surfaces arbitrarily far
    ;; from its cause, an error here does not.
    (define (%fresh-rcd rtd)
      (let ((ctor (%record-type-constructor rtd)))
        (when (and (not ctor) (%record-type-has-protocol? rtd))
          (error (string-append
                   "record-constructor: cannot recover the constructor of record type '"
                   (symbol->string (%record-type-name rtd))
                   "', whose definition has a protocol -- build a record descriptor for it"
                   " with make-record-descriptor")
                 rtd))
        (let ((parent (%record-type-parent rtd)))
          (%make-rd rtd (if parent (%fresh-rcd parent) #f) #f ctor))))

    (define (make-record-type-descriptor name parent uid sealed? opaque? fields)
      (%make-record-type-descriptor
        (symbol->string name)
        (if parent (%rtd "make-record-type-descriptor" parent) #f)
        (if uid (symbol->string uid) #f)
        (if sealed? #t #f)
        (if opaque? #t #f)
        (map (lambda (fspec)
               (cons (symbol->string (cadr fspec)) (eq? (car fspec) 'mutable)))
             (vector->list fields))))

    (define (record-type-descriptor? v)
      (or (%record-type? v) (record-descriptor? v)))

    ;; Two arities, both from the SRFI: the 3-argument R6RS-shaped one, and
    ;; the 7-argument shorthand specified as exactly
    ;; `(make-record-descriptor (make-record-type-descriptor name parent uid
    ;; sealed? opaque? fields) parent protocol)` -- note `parent` feeds both
    ;; slots, which only type-checks because `%rtd` and `%as-rcd` each
    ;; accept whichever of the two kinds it is handed.
    (define make-record-descriptor
      (case-lambda
        ((rtd parent-rd protocol)
         (%make-rd (%rtd "make-record-descriptor" rtd)
                   (if parent-rd parent-rd #f)
                   (if protocol protocol #f)
                   #f))
        ((name parent uid sealed? opaque? fields protocol)
         (make-record-descriptor
           (make-record-type-descriptor name parent uid sealed? opaque? fields)
           parent
           protocol))))

    ;; Deprecated R6RS spellings, kept as plain aliases.
    (define make-record-constructor-descriptor make-record-descriptor)
    (define record-constructor-descriptor? record-descriptor?)

    (define (record-descriptor-rtd rd)
      (cond ((record-descriptor? rd) (%rd-rtd rd))
            ((%record-type? rd) rd)
            (else (error "record-descriptor-rtd: not a record descriptor" rd))))

    (define (record-descriptor-parent rd)
      (cond ((record-descriptor? rd) (%rd-parent rd))
            ((%record-type? rd)
             (let ((p (%record-type-parent rd))) (if p (%fresh-rcd p) #f)))
            (else (error "record-descriptor-parent: not a record descriptor" rd))))

    (define (record-constructor rd)
      (let ((desc (%as-rcd "record-constructor" rd)))
        (or (%rd-ctor desc)
            (let ((rtd (%rd-rtd desc))
                  (parent-rd (%rd-parent desc))
                  (protocol (%rd-protocol desc)))
              (if parent-rd
                  (%record-constructor/parent rtd parent-rd protocol)
                  (%record-constructor/root rtd protocol))))))

    (define (%record-constructor/root rtd protocol)
      (let ((raw (lambda field-args (apply %make-record rtd field-args))))
        (if protocol (protocol raw) raw)))

    (define (%record-constructor/parent rtd parent-rd protocol)
      (let* ((parent-rtd (record-descriptor-rtd parent-rd))
             (parent-ctor (record-constructor parent-rd))
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
      (let ((rt (%rtd "record-predicate" rtd)))
        (lambda (v) (%record?/inherit v rt))))

    ;; Resolves a field designator against `rtd`, returning three values:
    ;; the rtd LEVEL the field is declared at, its 0-based index among that
    ;; level's OWN fields, and its absolute index into the full
    ;; (inherited-then-own) instance layout.
    ;;
    ;; An exact integer k is own-field-relative, per R6RS: "The field
    ;; selected corresponds to the kth element (0-based) of the fields
    ;; argument to the invocation of make-record-type-descriptor that
    ;; created rtd. Note that k cannot be used to specify a field of any
    ;; type rtd extends." It used to be read as an absolute index, which
    ;; silently returned an ancestor's field instead of the requested one
    ;; (kaappi#1974) -- and disagreed with `record-field-mutable?`, whose
    ;; own k was already own-relative.
    ;;
    ;; A field NAME is a Kaappi extension (R6RS has no name-based lookup)
    ;; that SRFI 57/131/136/150 rely on, so it keeps its ancestor-searching
    ;; behavior: a name not among this level's own fields recurses into the
    ;; parent. Each level's own fields start right after its immediate
    ;; parent's total field count, so no offset is threaded through.
    (define (%resolve-field who rtd field)
      (let* ((own-names (%record-type-field-names rtd))
             (parent (%record-type-parent rtd))
             (base (if parent (%record-type-total-field-count parent) 0)))
        (if (symbol? field)
            (let loop ((names own-names) (i 0))
              (cond
                ((null? names)
                 (if parent
                     (%resolve-field who parent field)
                     (error (string-append who ": unknown field name") field)))
                ((eq? (car names) field) (values rtd i (+ base i)))
                (else (loop (cdr names) (+ i 1)))))
            (begin
              ;; "K must be a valid field index of rtd" -- unchecked before,
              ;; so an out-of-range k produced a procedure that read or wrote
              ;; whatever happened to sit at that offset.
              (unless (and (exact-integer? field)
                           (>= field 0)
                           (< field (length own-names)))
                (error (string-append who ": not a valid own-field index of this record type")
                       field))
              (values rtd field (+ base field))))))

    (define (record-accessor rtd field)
      (let ((rt (%rtd "record-accessor" rtd)))
        (let-values (((level own idx) (%resolve-field "record-accessor" rt field)))
          (lambda (r) (%record-ref/inherit r idx rt)))))

    (define (record-mutator rtd field)
      (let ((rt (%rtd "record-mutator" rtd)))
        (let-values (((level own idx) (%resolve-field "record-mutator" rt field)))
          ;; R6RS: "If k specifies an immutable field, an exception with
          ;; condition type &assertion is raised." Checked at the level the
          ;; field is actually declared at, which is the only level whose
          ;; own-field mutability vector describes it.
          (unless (%record-field-mutable? level own)
            (error "record-mutator: field is immutable" field))
          (lambda (r v) (%record-set!/inherit r idx v rt)))))

    ;; R6RS: "Returns #t if obj is a record, and its record type is not
    ;; opaque". The opacity check lives here rather than in `%record?/any`,
    ;; whose contract is the narrower "is this a record instance at all"
    ;; that `%record-rtd` below and SRFI 136 both still want.
    (define (record? v)
      (and (%record?/any v)
           (not (%record-type-opaque? (%record-rtd v)))))

    ;; R6RS: "If the type is opaque, an exception is raised with condition
    ;; type &assertion."
    (define (record-rtd r)
      (let ((rt (%record-rtd r)))
        (if (%record-type-opaque? rt)
            (error "record-rtd: record type is opaque" r)
            rt)))

    (define (record-type-name rtd) (%record-type-name (%rtd "record-type-name" rtd)))
    (define (record-type-parent rtd) (%record-type-parent (%rtd "record-type-parent" rtd)))
    (define (record-type-uid rtd) (%record-type-uid (%rtd "record-type-uid" rtd)))
    (define (record-type-generative? rtd) (%record-type-generative? (%rtd "record-type-generative?" rtd)))
    (define (record-type-sealed? rtd) (%record-type-sealed? (%rtd "record-type-sealed?" rtd)))
    (define (record-type-opaque? rtd) (%record-type-opaque? (%rtd "record-type-opaque?" rtd)))

    ;; R6RS: "Returns a VECTOR of symbols naming the fields of the type
    ;; represented by rtd (not including the fields of parent types)." The
    ;; primitive answers with a list, which is what this library's own index
    ;; walks and SRFI 57/131/136/150 want; the vector is built at the public
    ;; boundary (kaappi#1974).
    (define (record-type-field-names rtd)
      (list->vector (%record-type-field-names (%rtd "record-type-field-names" rtd))))

    ;; "K is as in record-accessor" -- so a symbol resolves through the same
    ;; ancestor-searching path, and reports the mutability recorded at the
    ;; level the field is declared at.
    (define (record-field-mutable? rtd field)
      (let ((rt (%rtd "record-field-mutable?" rtd)))
        (if (symbol? field)
            (let-values (((level own idx) (%resolve-field "record-field-mutable?" rt field)))
              (%record-field-mutable? level own))
            (%record-field-mutable? rt field))))

    (define (record-uid->rtd uid) (%record-uid->rtd (symbol->string uid)))))
