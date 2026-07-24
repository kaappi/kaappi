;;; SRFI 57: Records.
;;;
;;; R6RS-flavored record inheritance via "schemes" -- a scheme is a named,
;;; reusable field-label list (with optional polymorphic predicate/
;;; accessors) that a type or another scheme can extend; multiple schemes
;;; may be extended at once, with field lists merged left-to-right and
;;; de-duplicated (delete-duplicates semantics: first occurrence's position
;;; wins). Also provides record-update/record-update!/record-compose for
;;; functional update, in-place update, and cross-type field composition.
;;;
;;; DESIGN: NOT a port of the spec's own reference implementation. That
;;; reference implementation compares field-label identifiers at macro-
;;; expansion time via the standard `let-syntax` + literals-list hygienic
;;; "if-free=?" trick (needed for its own de-duplication and lookup). That
;;; exact trick -- confirmed independently reproducible in isolation here,
;;; see e.g. a bare (let-syntax ((cmp ...)) (define-syntax later-macro
;;; ...)) -- breaks Kaappi's expander with an outright compile error
;;; whenever the branch it selects (directly or many macro-layers removed)
;;; itself expands to a `define-syntax` form; a minimal repro is preserved
;;; in this issue's PR description. Rather than fix that expander bug (a
;;; separate, uncharacterized engine investigation) this library sidesteps
;;; it entirely: field labels are turned into ordinary quoted symbols and
;;; ALL list-merging/de-duplication/lookup happens at ordinary run time
;;; (plain `assq`/`memq` over symbol lists), not macro-expansion time. A
;;; scheme or type name is bound with a plain `define` (not `define-
;;; syntax`) to a `(field-symbols . rtd-or-#f)` pair -- no CPS
;;; introspection macro, no identifier comparison, no hygiene tricks
;;; anywhere in this file. This is simpler than the reference design, not
;;; just an engine-avoidance workaround.
;;;
;;; Built on (srfi 237)'s procedural layer (the same substrate SRFI 136/
;;; 137/131 in this codebase already share) purely for its record-type/
;;; instance primitives (make-record-type-descriptor, record-accessor,
;;; record-mutator, record-rtd, record-type-field-names) -- none of 237's
;;; own inheritance/protocol machinery is used. Every SRFI-57 type is a
;;; flat (srfi 237) record type with parent = #f: "inheritance" here is
;;; pure field-list merging, not (srfi 237) parent-chaining, since a
;;; SRFI-57 scheme can have MULTIPLE parent schemes at once (237's own
;;; `parent` field supports only one).
;;;
;;; DELIBERATE SCOPE REDUCTIONS (documented, not silent gaps):
;;;
;;; 1. Deconstructor clauses (define-record-scheme's own analogue of a
;;;    constructor clause) must be #f. The spec itself frames deconstructors
;;;    as being for "future" pattern-matching use; no actual deconstruction
;;;    behavior is specified for this SRFI, so there is nothing to bind a
;;;    non-#f deconstructor name to. A parent scheme's OWN field labels
;;;    still merge into a child's field list exactly per spec either way.
;;;
;;; 2. record-update and record-update! accept but do not validate their
;;;    <scheme name>/<type name> target argument -- both always operate on
;;;    the record's own actual runtime type (via record-rtd), which is what
;;;    the spec requires the RESULT to be in both the monomorphic and
;;;    polymorphic cases anyway ("a new record value of the same type as
;;;    the original record"). What's skipped is purely the error-detection
;;;    duty of confirming upfront that the record actually conforms to/is
;;;    of the stated target -- misuse (an unrelated target) simply isn't
;;;    caught; well-formed uses are unaffected.
;;;
;;; 3. A scheme's polymorphic predicate checks conformance STRUCTURALLY --
;;;    "is this a record whose actual type has every one of the scheme's
;;;    field labels" -- rather than NOMINALLY (was this type declared, at
;;;    definition time, to conform to this exact scheme). Indistinguishable
;;;    from nominal conformance for any type that reaches its fields
;;;    through this library's own scheme-extension mechanism; could over-
;;;    accept a type that coincidentally has same-named fields through
;;;    unrelated means.
;;;
;;; 4. Every field is internally mutable regardless of whether its field
;;;    clause declares a <modifier clause> -- record-update!/record-compose
;;;    must be able to write into any field, including ones with no public
;;;    modifier name. The modifier clause only controls whether a PUBLIC
;;;    mutator gets bound, exactly as the spec intends; it was never a
;;;    runtime enforcement mechanism in this engine (record-mutator itself
;;;    enforces nothing beyond field existence, per (srfi 237)).
;;;
;;; port-read-rtd/port-write-rtd-style serialization is out of scope here,
;;; same as already noted for (srfi 237) -- this SRFI doesn't have those,
;;; nothing to note.
(define-library (srfi 57)
  (import (scheme base) (srfi 237))
  (export define-record-type define-record-scheme
          record-update record-update! record-compose)
  (begin

    (define (%srfi57-dedup lst)
      (let loop ((lst lst) (seen '()))
        (cond ((null? lst) (reverse seen))
              ((memq (car lst) seen) (loop (cdr lst) seen))
              (else (loop (cdr lst) (cons (car lst) seen))))))

    (define (%srfi57-subset? needed have)
      (or (null? needed)
          (and (memq (car needed) have) (%srfi57-subset? (cdr needed) have))))

    ;; Builds a full positional field-value list (rtd's own order) from a
    ;; partial (label . value) alist, defaulting any field the alist
    ;; doesn't mention to #f, then constructs the instance.
    (define (%srfi57-build-positional fields alist rtd)
      (apply %make-record rtd
        (map (lambda (f) (let ((p (assq f alist))) (if p (cdr p) #f))) fields)))

    ;; Field-clause shapes: (label) | (label accessor) | (label accessor modifier).
    ;; Extracts just the labels, for field-list merging.
    (define-syntax %srfi57-field-names
      (syntax-rules ()
        ((_ ()) '())
        ((_ ((label . rest) more ...)) (cons 'label (%srfi57-field-names (more ...))))))

    (define-syntax %srfi57-def-poly-acc
      (syntax-rules ()
        ((_ #f label) (if #f #f))
        ((_ acc label) (define (acc r) ((record-accessor (record-rtd r) 'label) r)))))

    (define-syntax %srfi57-def-poly-mut
      (syntax-rules ()
        ((_ #f label) (if #f #f))
        ((_ mut label) (define (mut r v) ((record-mutator (record-rtd r) 'label) r v)))))

    ;; Accessors/mutators always resolve via the INSTANCE's own actual rtd
    ;; (record-rtd), not a statically-known one -- this is what makes a
    ;; scheme's field-clause accessor polymorphic across every conforming
    ;; type for free, and is equally correct (just one dynamic lookup, not
    ;; a meaningful behavior difference) when used from a type's own
    ;; monomorphic field-clause.
    (define-syntax %srfi57-def-accessors
      (syntax-rules ()
        ((_ ()) (begin))
        ((_ ((label) rest ...)) (%srfi57-def-accessors (rest ...)))
        ((_ ((label acc) rest ...))
         (begin (%srfi57-def-poly-acc acc label) (%srfi57-def-accessors (rest ...))))
        ((_ ((label acc mut) rest ...))
         (begin (%srfi57-def-poly-acc acc label)
                (%srfi57-def-poly-mut mut label)
                (%srfi57-def-accessors (rest ...))))))

    ;; --- define-record-scheme ----------------------------------------------

    (define-syntax %srfi57-def-poly-pred
      (syntax-rules ()
        ((_ #f name) (if #f #f))
        ((_ pname name)
         (define (pname r)
           (and (record? r) (%srfi57-subset? (car name) (record-type-field-names (record-rtd r))))))))

    (define-syntax %srfi57-expand-scheme
      (syntax-rules ()
        ((_ name (parent ...) #f pred (field-spec ...))
         (begin
           (define name
             (cons (%srfi57-dedup (append (car parent) ... (%srfi57-field-names (field-spec ...)))) #f))
           (%srfi57-def-poly-pred pred name)
           (%srfi57-def-accessors (field-spec ...))))))

    (define-syntax define-record-scheme
      (syntax-rules ()
        ((_ (name parent ...) deconstructor pred field-spec ...)
         (%srfi57-expand-scheme name (parent ...) deconstructor pred (field-spec ...)))
        ((_ name deconstructor pred field-spec ...)
         (%srfi57-expand-scheme name () deconstructor pred (field-spec ...)))))

    ;; --- define-record-type -------------------------------------------------

    (define-syntax %srfi57-ctor-fields
      (syntax-rules ()
        ((_ #f) '())
        ((_ (cname f ...)) (list 'f ...))
        ((_ cname) '())))

    ;; A bare constructor name takes ALL of the type's final fields,
    ;; positionally, in the type's own (internally consistent) order --
    ;; needs no name resolution at all, unlike the explicit-field-list form.
    (define-syntax %srfi57-def-ctor
      (syntax-rules ()
        ((_ #f fields rtd) (if #f #f))
        ((_ (cname f ...) fields rtd)
         (define (cname f ...) (%srfi57-build-positional fields (list (cons 'f f) ...) rtd)))
        ((_ cname fields rtd)
         (define (cname . args) (apply %make-record rtd args)))))

    (define-syntax %srfi57-def-pred
      (syntax-rules ()
        ((_ #f rtd) (if #f #f))
        ((_ pname rtd) (define (pname r) (and (record? r) (eq? (record-rtd r) rtd))))))

    (define-syntax %srfi57-expand-type
      (syntax-rules ()
        ((_ name (scheme ...) ctor pred (field-spec ...))
         (begin
           (define %srfi57-tfields
             (%srfi57-dedup
               (append (car scheme) ... (%srfi57-ctor-fields ctor) (%srfi57-field-names (field-spec ...)))))
           ;; every field mutable internally regardless of its own modifier
           ;; clause -- see header note 4.
           (define %srfi57-trtd
             (make-record-type-descriptor 'name #f #f #f #f
               (list->vector (map (lambda (f) (list 'mutable f)) %srfi57-tfields))))
           (define name (cons %srfi57-tfields %srfi57-trtd))
           (%srfi57-def-ctor ctor %srfi57-tfields %srfi57-trtd)
           (%srfi57-def-pred pred %srfi57-trtd)
           (%srfi57-def-accessors (field-spec ...))))))

    (define-syntax define-record-type
      (syntax-rules ()
        ((_ (name scheme ...) ctor pred field-spec ...)
         (%srfi57-expand-type name (scheme ...) ctor pred (field-spec ...)))
        ((_ name ctor pred field-spec ...)
         (%srfi57-expand-type name () ctor pred (field-spec ...)))))

    ;; --- record-update / record-update! / record-compose --------------------

    (define (%srfi57-update rec overrides)
      (let* ((rtd (record-rtd rec)) (fields (record-type-field-names rtd)))
        (apply %make-record rtd
          (map (lambda (f) (let ((p (assq f overrides))) (if p (cdr p) ((record-accessor rtd f) rec))))
               fields))))

    (define (%srfi57-update! rec overrides)
      (for-each (lambda (pair) ((record-mutator (record-rtd rec) (car pair)) rec (cdr pair))) overrides)
      rec)

    ;; target is intentionally unused -- see header note 2.
    (define-syntax record-update
      (syntax-rules ()
        ((_ rec target (label expr) ...) (%srfi57-update rec (list (cons 'label expr) ...)))))

    (define-syntax record-update!
      (syntax-rules ()
        ((_ rec target (label expr) ...) (%srfi57-update! rec (list (cons 'label expr) ...)))))

    ;; Only the field labels belonging to `import` (not necessarily all of
    ;; rec's own actual fields) are copied -- this is what makes a
    ;; scheme-typed import copy just that scheme's slice of a
    ;; wider-fielded actual record.
    (define (%srfi57-import-alist import rec)
      (map (lambda (f) (cons f ((record-accessor (record-rtd rec) f) rec))) (car import)))

    ;; Later entries must win over earlier ones (later imports over earlier
    ;; imports, explicit overrides over every import) -- searching the
    ;; REVERSED concatenation with assq (first-match-wins) is the same
    ;; thing as "last original occurrence wins".
    (define (%srfi57-compose-build export-fields export-rtd merged-alist)
      (let ((rev (reverse merged-alist)))
        (apply %make-record export-rtd
          (map (lambda (f) (let ((p (assq f rev))) (if p (cdr p) #f))) export-fields))))

    (define-syntax record-compose
      (syntax-rules ()
        ((_ (import rec) ... (export (label expr) ...))
         (%srfi57-compose-build (car export) (cdr export)
           (append (%srfi57-import-alist import rec) ... (list (cons 'label expr) ...))))))))
