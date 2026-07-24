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
;;; syntax`) to a `(field-symbols rtd-or-#f ancestor-schemes)` list -- no
;;; CPS introspection macro, no identifier comparison, no hygiene tricks
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
;;; NOMINAL (not structural) scheme conformance: a record conforms to a
;;; scheme only if its type was actually declared (directly or
;;; transitively) to extend that scheme -- matching the spec, which treats
;;; conformance as a declared relationship, not "happens to have the same
;;; field names." Since a record instance only carries a pointer to its
;;; raw (srfi 237) rtd -- which has no field for this library's own scheme
;;; metadata -- a type's declared ancestry is looked up from a side table
;;; (%srfi57-registry, an assq alist keyed by rtd) populated once at
;;; define-record-type time. Schemes don't need a registry entry: their
;;; own ancestry is stored directly in their value (no rtd to key on, and
;;; nothing instantiates a scheme on its own).
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
;;; 2. record-update, record-update!, and record-compose validate their
;;;    target/import/export type-or-scheme arguments (conformance) and
;;;    field labels (membership) at CALL time, not at the spec's own stated
;;;    "expansion time" -- these are ordinary values here (see DESIGN
;;;    above), so their identity isn't knowable until the code actually
;;;    runs. Genuine misuse is still caught, just one phase later than the
;;;    spec describes.
;;;
;;; 3. Every field is internally mutable regardless of whether its field
;;;    clause declares a <modifier clause> -- record-update!/record-compose
;;;    must be able to write into any field, including ones with no public
;;;    modifier name. The modifier clause only controls whether a PUBLIC
;;;    mutator gets bound, exactly as the spec intends; it was never a
;;;    runtime enforcement mechanism in this engine (record-mutator itself
;;;    enforces nothing beyond field existence, per (srfi 237)).
;;;
;;; 4. Labeled record expressions -- the spec's `(<type name> (<field
;;;    label> <expression>) ...)` construction syntax -- are not supported.
;;;    Supporting them would require <type name> to be a macro (to see
;;;    `(x 1)` as an unevaluated label/expression pair rather than a call to
;;;    a procedure named `x`), which conflicts with this library's DESIGN
;;;    choice of binding every scheme/type name to an ordinary value so
;;;    record-compose/record-update can reference it directly. The explicit
;;;    named-field constructor clause -- `(<ctor-name> <field-label> ...)`
;;;    -- already covers the same practical need (construct with named,
;;;    possibly-reordered fields) with a different call-site spelling.
;;;
;;; port-read-rtd/port-write-rtd-style serialization is out of scope here,
;;; same as already noted for (srfi 237) -- this SRFI doesn't have those,
;;; nothing to note.
(define-library (srfi 57)
  (import (scheme base) (srfi 237) (srfi 237 primitives))
  (export define-record-type define-record-scheme
          record-update record-update! record-compose)
  (begin

    (define (%srfi57-dedup lst)
      (let loop ((lst lst) (seen '()))
        (cond ((null? lst) (reverse seen))
              ((memq (car lst) seen) (loop (cdr lst) seen))
              (else (loop (cdr lst) (cons (car lst) seen))))))

    ;; --- nominal conformance registry ---------------------------------------

    ;; Maps an rtd (by eq?) to the list of scheme VALUES (by eq?) its type
    ;; was declared to extend, directly or transitively. Populated once per
    ;; define-record-type, consulted by every polymorphic predicate/
    ;; accessor/mutator and by record-update/record-update!/record-compose.
    (define %srfi57-registry '())

    (define (%srfi57-register! rtd ancestors)
      (set! %srfi57-registry (cons (cons rtd ancestors) %srfi57-registry)))

    (define (%srfi57-ancestors-of rtd)
      (let ((p (assq rtd %srfi57-registry)))
        (if p (cdr p) '())))

    ;; Does record `r` conform to `target` (a scheme or type value)? A type
    ;; target needs an exact rtd match; a scheme target needs `target`
    ;; itself to be in r's actual type's declared (transitive) ancestry.
    (define (%srfi57-conforms? r target)
      (and (record? r)
           (let ((rtd (record-rtd r)))
             (if (cadr target)
                 (eq? rtd (cadr target))
                 (and (memq target (%srfi57-ancestors-of rtd)) #t)))))

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

    ;; Scheme field-clause accessors/mutators are genuinely polymorphic:
    ;; they work across every type conforming to the scheme, but must
    ;; reject a record that doesn't actually conform (a same-shaped,
    ;; unrelated record is not enough -- see NOMINAL note above).
    (define-syntax %srfi57-def-poly-acc
      (syntax-rules ()
        ((_ #f label scheme) (if #f #f))
        ((_ acc label scheme)
         (define (acc r)
           (if (%srfi57-conforms? r scheme)
               ((record-accessor (record-rtd r) 'label) r)
               (error "accessor: record does not conform to the expected scheme" r))))))

    (define-syntax %srfi57-def-poly-mut
      (syntax-rules ()
        ((_ #f label scheme) (if #f #f))
        ((_ mut label scheme)
         (define (mut r v)
           (if (%srfi57-conforms? r scheme)
               ((record-mutator (record-rtd r) 'label) r v)
               (error "mutator: record does not conform to the expected scheme" r))))))

    (define-syntax %srfi57-def-poly-accessors
      (syntax-rules ()
        ((_ scheme ()) (begin))
        ((_ scheme ((label) rest ...)) (%srfi57-def-poly-accessors scheme (rest ...)))
        ((_ scheme ((label acc) rest ...))
         (begin (%srfi57-def-poly-acc acc label scheme) (%srfi57-def-poly-accessors scheme (rest ...))))
        ((_ scheme ((label acc mut) rest ...))
         (begin (%srfi57-def-poly-acc acc label scheme)
                (%srfi57-def-poly-mut mut label scheme)
                (%srfi57-def-poly-accessors scheme (rest ...))))))

    ;; define-record-type field-clause accessors/mutators are monomorphic:
    ;; "It is an error to pass an accessor a value not of type <type name>."
    ;; Checked against the type's own fixed rtd, not resolved dynamically.
    (define-syntax %srfi57-def-mono-acc
      (syntax-rules ()
        ((_ #f label rtd) (if #f #f))
        ((_ acc label rtd)
         (define (acc r)
           (if (eq? (record-rtd r) rtd)
               ((record-accessor rtd 'label) r)
               (error "accessor: not of the expected record type" r))))))

    (define-syntax %srfi57-def-mono-mut
      (syntax-rules ()
        ((_ #f label rtd) (if #f #f))
        ((_ mut label rtd)
         (define (mut r v)
           (if (eq? (record-rtd r) rtd)
               ((record-mutator rtd 'label) r v)
               (error "mutator: not of the expected record type" r))))))

    (define-syntax %srfi57-def-mono-accessors
      (syntax-rules ()
        ((_ rtd ()) (begin))
        ((_ rtd ((label) rest ...)) (%srfi57-def-mono-accessors rtd (rest ...)))
        ((_ rtd ((label acc) rest ...))
         (begin (%srfi57-def-mono-acc acc label rtd) (%srfi57-def-mono-accessors rtd (rest ...))))
        ((_ rtd ((label acc mut) rest ...))
         (begin (%srfi57-def-mono-acc acc label rtd)
                (%srfi57-def-mono-mut mut label rtd)
                (%srfi57-def-mono-accessors rtd (rest ...))))))

    ;; --- define-record-scheme ----------------------------------------------

    (define-syntax %srfi57-def-poly-pred
      (syntax-rules ()
        ((_ #f name) (if #f #f))
        ((_ pname name) (define (pname r) (%srfi57-conforms? r name)))))

    ;; A scheme/type's own declared ancestry is the union of each direct
    ;; parent P together with P's OWN ancestry -- i.e. `P` itself is always
    ;; a member (not just P's ancestors), so a child of P conforms to P.
    (define-syntax %srfi57-ancestors
      (syntax-rules ()
        ((_ (parent ...)) (%srfi57-dedup (append (cons parent (caddr parent)) ...)))))

    (define-syntax %srfi57-expand-scheme
      (syntax-rules ()
        ((_ name (parent ...) #f pred (field-spec ...))
         (begin
           (define name
             (list (%srfi57-dedup (append (car parent) ... (%srfi57-field-names (field-spec ...))))
                   #f
                   (%srfi57-ancestors (parent ...))))
           (%srfi57-def-poly-pred pred name)
           (%srfi57-def-poly-accessors name (field-spec ...))))))

    ;; Shorter forms omit trailing clauses entirely (not just supply #f for
    ;; them): a scheme clause alone is equivalent to supplying #f for both
    ;; the deconstructor and predicate and no field clauses.
    (define-syntax define-record-scheme
      (syntax-rules ()
        ((_ (name parent ...) deconstructor pred field-spec ...)
         (%srfi57-expand-scheme name (parent ...) deconstructor pred (field-spec ...)))
        ((_ (name parent ...))
         (%srfi57-expand-scheme name (parent ...) #f #f ()))
        ((_ name deconstructor pred field-spec ...)
         (%srfi57-expand-scheme name () deconstructor pred (field-spec ...)))
        ((_ name)
         (%srfi57-expand-scheme name () #f #f ()))))

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
           ;; clause -- see header note 3.
           (define %srfi57-trtd
             (make-record-type-descriptor 'name #f #f #f #f
               (list->vector (map (lambda (f) (list 'mutable f)) %srfi57-tfields))))
           (define %srfi57-tancestors (%srfi57-ancestors (scheme ...)))
           (%srfi57-register! %srfi57-trtd %srfi57-tancestors)
           (define name (list %srfi57-tfields %srfi57-trtd %srfi57-tancestors))
           (%srfi57-def-ctor ctor %srfi57-tfields %srfi57-trtd)
           (%srfi57-def-pred pred %srfi57-trtd)
           (%srfi57-def-mono-accessors %srfi57-trtd (field-spec ...))))))

    ;; Shorter forms omit trailing clauses entirely: a type clause alone is
    ;; equivalent to supplying #f for both the constructor and predicate and
    ;; no field clauses (a type with no fields, unconstructable except via
    ;; %make-record, and no bound predicate).
    (define-syntax define-record-type
      (syntax-rules ()
        ((_ (name scheme ...) ctor pred field-spec ...)
         (%srfi57-expand-type name (scheme ...) ctor pred (field-spec ...)))
        ((_ (name scheme ...))
         (%srfi57-expand-type name (scheme ...) #f #f ()))
        ((_ name ctor pred field-spec ...)
         (%srfi57-expand-type name () ctor pred (field-spec ...)))
        ((_ name)
         (%srfi57-expand-type name () #f #f ()))))

    ;; --- record-update / record-update! / record-compose --------------------

    ;; Checked at call time, not expansion time -- see header note 2: target
    ;; is an ordinary value here, not a macro, so its identity isn't
    ;; knowable until the code actually runs.
    (define (%srfi57-check-target rec target labels who)
      (unless (%srfi57-conforms? rec target)
        (error (string-append who ": record does not conform to the expected type/scheme") rec))
      (for-each (lambda (f)
                  (unless (memq f (car target))
                    (error (string-append who ": label is not a field of the target type/scheme") f)))
                labels))

    (define (%srfi57-update rec overrides)
      (let* ((rtd (record-rtd rec)) (fields (record-type-field-names rtd)))
        (apply %make-record rtd
          (map (lambda (f) (let ((p (assq f overrides))) (if p (cdr p) ((record-accessor rtd f) rec))))
               fields))))

    (define (%srfi57-update! rec overrides)
      (for-each (lambda (pair) ((record-mutator (record-rtd rec) (car pair)) rec (cdr pair))) overrides)
      rec)

    (define-syntax record-update
      (syntax-rules ()
        ((_ rec target (label expr) ...)
         (let ((r rec) (tgt target))
           (%srfi57-check-target r tgt '(label ...) "record-update")
           (%srfi57-update r (list (cons 'label expr) ...))))))

    (define-syntax record-update!
      (syntax-rules ()
        ((_ rec target (label expr) ...)
         (let ((r rec) (tgt target))
           (%srfi57-check-target r tgt '(label ...) "record-update!")
           (%srfi57-update! r (list (cons 'label expr) ...))))))

    ;; Only the field labels belonging to `import` (not necessarily all of
    ;; rec's own actual fields) are copied -- this is what makes a
    ;; scheme-typed import copy just that scheme's slice of a
    ;; wider-fielded actual record. `rec` must actually conform to `import`
    ;; (checked here, not left to coincidental field overlap).
    (define (%srfi57-import-alist import rec who)
      (unless (%srfi57-conforms? rec import)
        (error (string-append who ": imported record does not conform to the expected type/scheme") rec))
      (map (lambda (f) (cons f ((record-accessor (record-rtd rec) f) rec))) (car import)))

    (define (%srfi57-check-export-labels export labels who)
      (for-each (lambda (f)
                  (unless (memq f (car export))
                    (error (string-append who ": label is not a field of the export type") f)))
                labels))

    ;; Imports are processed left to right, dropping any repeated fields --
    ;; i.e. the FIRST import that has a given label wins over later ones --
    ;; then explicit overrides "overwrite any fields with the same labels
    ;; already imported", so they must win over every import regardless of
    ;; order. Putting overrides first in the list and searching with assq's
    ;; ordinary first-match-wins gives exactly that precedence.
    (define (%srfi57-compose-build export-fields export-rtd merged-alist)
      (apply %make-record export-rtd
        (map (lambda (f) (let ((p (assq f merged-alist))) (if p (cdr p) #f))) export-fields)))

    (define-syntax record-compose
      (syntax-rules ()
        ((_ (import rec) ... (export (label expr) ...))
         (let ((exp export))
           (%srfi57-check-export-labels exp '(label ...) "record-compose")
           (%srfi57-compose-build (car exp) (cadr exp)
             (append (list (cons 'label expr) ...)
                     (%srfi57-import-alist import rec "record-compose") ...))))))))
