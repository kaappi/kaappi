;;; SRFI 131: ERR5RS Record Syntax (reduced).
;;;
;;; The syntax-rules-expressible reduced subset of SRFI 99: drops SRFI 99's
;;; `#t` auto-naming shorthand for the constructor/predicate and its bare
;;; field-name shorthand (each needs identifier synthesis, per SRFI 99's
;;; own exclusion from this project -- see docs/dev/srfi-exclusions.md).
;;; Every field spec here always names its accessor explicitly, and every
;;; constructor/predicate name is either given explicitly or suppressed
;;; with #f -- never auto-derived from the type name.
;;;
;;; This SRFI's own spec text says it "does not define its own procedural
;;; layer... built on top of the procedural parts of SRFI 99" -- this
;;; implementation is built on (srfi 237)'s procedural layer instead (the
;;; same substrate SRFI 136/137 in this codebase already reuse), so it
;;; exports only `define-record-type` itself.
;;;
;;; The one genuinely SRFI-131-specific feature (vs. SRFI 136) is that its
;;; explicit `(<constructor name> <field name> ...)` constructor spec
;;; resolves field names BY NAME, not position -- and a subtype field
;;; sharing an ancestor's field name "shadows the ancestor's field name for
;;; the purposes of the constructor" (the spec's own words) while still
;;; occupying its own, separate slot: %absolute-index below always
;;; resolves a name to the MOST-DERIVED (closest-to-rtd) occurrence,
;;; searching from rtd up toward the root.
;;;
;;; ENGINE PREREQUISITE: same as SRFI 136 -- vm_eval.zig's
;;; handleTopLevelForm/isSpecialTopLevelForm let a macro literally named
;;; define-record-type shadow the built-in special form; see
;;; lib/srfi/136.sld's header for the full explanation, including the
;;; same top-level-only limitation (library bodies not yet supported).
(define-library (srfi 131)
  ;; (srfi 237 primitives) imported explicitly for %record-type-total-
  ;; field-count/%make-record (used by %named-constructor/%absolute-index
  ;; below) -- relying on their being ambiently visible without a
  ;; declared import proved unreliable in testing for this file, unlike
  ;; some other %-prefixed primitives elsewhere in this codebase.
  (import (scheme base) (srfi 237) (srfi 237 primitives))
  (export define-record-type)
  (begin

    (define (%fresh-rcd rtd)
      (let ((parent (record-type-parent rtd)))
        (make-record-descriptor rtd (if parent (%fresh-rcd parent) #f) #f)))

    ;; Absolute 0-based index of `name` in rtd's FULL (inherited-then-own)
    ;; field layout, resolving to the MOST-DERIVED occurrence when a
    ;; subtype's own field shadows an ancestor's same-named field.
    (define (%absolute-index rtd name)
      (let ((parent (record-type-parent rtd)))
        (let ((parent-count (if parent (%record-type-total-field-count parent) 0)))
          (%absolute-index-loop rtd name parent (record-type-field-names rtd) parent-count))))

    (define (%absolute-index-loop rtd name parent names i)
      (cond
        ((null? names) (if parent (%absolute-index parent name) (error "unknown field" name)))
        ((eq? (car names) name) i)
        (else (%absolute-index-loop rtd name parent (cdr names) (+ i 1)))))

    ;; The explicit (<ctor-name> <field-name> ...) form: builds the record
    ;; directly (bypassing record-constructor's positional parent-then-own
    ;; threading entirely) since fields are named, arbitrary-subset, and
    ;; possibly-shadowing -- none of which is positional.
    (define (%named-constructor rtd field-names)
      (let ((total (%record-type-total-field-count rtd)))
        (lambda args
          (let ((field-values (make-vector total (if #f #f))))
            (%named-constructor-fill! rtd field-values field-names args)
            (apply %make-record rtd (vector->list field-values))))))

    (define (%named-constructor-fill! rtd field-values field-names args)
      (if (null? field-names)
          (if #f #f)
          (let ((idx (%absolute-index rtd (car field-names))))
            (vector-set! field-values idx (car args))
            (%named-constructor-fill! rtd field-values (cdr field-names) (cdr args)))))

    (define-syntax %srfi131-def-ctor
      (syntax-rules ()
        ((_ #f rtd) (if #f #f)) ; constructor suppressed
        ((_ (cname fname ...) rtd) (define cname (%named-constructor rtd '(fname ...))))
        ((_ cname rtd) (define cname (record-constructor (%fresh-rcd rtd))))))

    (define-syntax %srfi131-def-pred
      (syntax-rules ()
        ((_ #f rtd) (if #f #f)) ; predicate suppressed
        ((_ pname rtd) (define pname (record-predicate rtd)))))

    (define-syntax %srfi131-def-accessors
      (syntax-rules ()
        ((_ rtd ()) (begin))
        ((_ rtd ((fname facc) rest ...))
         (begin (define facc (record-accessor rtd 'fname)) (%srfi131-def-accessors rtd (rest ...))))
        ((_ rtd ((fname facc fmut) rest ...))
         (begin (define facc (record-accessor rtd 'fname))
                (define fmut (record-mutator rtd 'fname))
                (%srfi131-def-accessors rtd (rest ...))))))

    ;; Produces the (immutable|mutable name) list shape (srfi 237)'s
    ;; make-record-type-descriptor expects for ITS OWN fields argument --
    ;; distinct from SRFI 131's own (name accessor [mutator]) field-spec
    ;; shape, which %srfi131-def-accessors below consumes separately (via
    ;; record-accessor/record-mutator, not via this list at all).
    (define-syntax %srfi131-field-list
      (syntax-rules ()
        ((_ ()) '())
        ((_ ((fname facc) rest ...)) (cons (list 'immutable 'fname) (%srfi131-field-list (rest ...))))
        ((_ ((fname facc fmut) rest ...)) (cons (list 'mutable 'fname) (%srfi131-field-list (rest ...))))))

    (define-syntax %srfi131-parent-rtd
      (syntax-rules ()
        ((_ #f) #f)
        ((_ p) p)))

    (define-syntax %srfi131-expand
      (syntax-rules ()
        ((_ name parent ctor-spec pred-spec (field-spec ...))
         (begin
           (define %srfi131-rtd
             (make-record-type-descriptor
               (quote name)
               (%srfi131-parent-rtd parent)
               #f #f #f
               (list->vector (%srfi131-field-list (field-spec ...)))))
           ;; Unlike SRFI 136, this SRFI has no CPS-introspection macro --
           ;; a subtype's (parent) type-spec keyword is just an ordinary
           ;; variable reference to the parent's own rtd, so the type name
           ;; itself must be bound to it directly (regardless of whether
           ;; the ctor/pred are suppressed) for that reference to resolve.
           (define name %srfi131-rtd)
           (%srfi131-def-ctor ctor-spec %srfi131-rtd)
           (%srfi131-def-pred pred-spec %srfi131-rtd)
           (%srfi131-def-accessors %srfi131-rtd (field-spec ...))))))

    (define-syntax define-record-type
      (syntax-rules ()
        ((_ (name parent) ctor-spec pred-spec field-spec ...)
         (%srfi131-expand name parent ctor-spec pred-spec (field-spec ...)))
        ((_ name ctor-spec pred-spec field-spec ...)
         (%srfi131-expand name #f ctor-spec pred-spec (field-spec ...)))))))
