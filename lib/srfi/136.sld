;;; SRFI 136: Extensible record types.
;;;
;;; The spec states this is "implemented using only syntax-rules macros."
;;; Rather than re-deriving RTD storage/inheritance from scratch in raw
;;; syntax-rules (the way SRFI 57's own reference implementation famously
;;; does, at real complexity/performance cost -- see lib/srfi/57.sld's own
;;; header comment), this implementation reuses (srfi 237)'s
;;; engine-backed, already-validated record-type-descriptor machinery as
;;; its runtime substrate: everything SRFI 136 needs at the VALUE level
;;; (RTDs, inheritance-aware constructors/predicates/accessors) already
;;; exists there. Nothing about this uses non-hygienic macro power --
;;; make-record-type-descriptor/record-constructor/etc. are ordinary
;;; procedures called from ordinary (hygienically expanded) generated
;;; code, exactly as calling any other procedure from a macro's expansion
;;; would be.
;;;
;;; The one genuinely SRFI-136-specific technique is the CPS-style
;;; introspection macro: `define-record-type` binds `<type-name>` itself
;;; as a SECOND macro (not just a runtime constructor/predicate/accessor
;;; set) with two forms:
;;;   (<type-name>)                     => the type's own rtd (a value)
;;;   (<type-name> (<keyword> <datum> ...)) => (<keyword> <datum> ... <parent> <field-spec> ...)
;;; The second form splices this type's OWN <parent> keyword and
;;; <field-spec>s -- exactly as written in ITS OWN define-record-type call
;;; -- into a call to a keyword macro the CALLER supplies. This needs no
;;; identifier synthesis (unlike SRFI 99/100/150): it only ever recalls
;;; syntax this exact macro use already captured hygienically, never
;;; fabricates a new name from string parts.
;;;
;;; ENGINE PREREQUISITE: `define-record-type` is normally a hardcoded,
;;; non-overridable special form in Kaappi (checked by literal name in
;;; vm_eval.zig/compiler.zig before any macro table is consulted), which
;;; would otherwise make it impossible for ANY portable library -- this
;;; one, SRFI 131, or SRFI 57 -- to give that name new meaning via
;;; define-syntax. vm_eval.zig's handleTopLevelForm/isSpecialTopLevelForm
;;; now check whether a macro literally named define-record-type is in
;;; scope before falling back to the built-in R7RS/R6RS handler (mirroring
;;; compiler.zig's compileForm, which already prioritized macros over
;;; special forms for every non-top-level use -- see its own comment
;;; citing SRFI 219 redefining `define` as the existing precedent for this
;;; principle). This closes the gap only for the compileForm/
;;; handleTopLevelForm dispatch pair; the SEPARATE library-body scanning
;;; path (compiler_lambda.zig, vm_library.zig) does not yet have the same
;;; check, so this macro -- like the R6RS-clause syntax in
;;; src/vm_records.zig -- only works at the top level, not inside another
;;; library's own body. This mirrors that limitation for the same
;;; underlying reason (a documented gap, not silently broken behavior).
(define-library (srfi 136)
  ;; (srfi 237 primitives) imported explicitly for the same reason as
  ;; lib/srfi/131.sld: relying on ambient visibility of %-prefixed
  ;; primitives without a declared import proved unreliable in testing.
  (import (scheme base) (srfi 237) (srfi 237 primitives))
  (export define-record-type record? record-type-descriptor? record-type-descriptor
          record-type-predicate record-type-name record-type-parent record-type-fields
          make-record-type-descriptor make-record)
  (begin

    ;; Rebuilds a full RCD chain (root..rtd) at runtime by walking
    ;; record-type-parent -- SRFI 136 has no `protocol` concept at all, so
    ;; every level's rcd is trivially (rtd . parent-rcd . #f), and this
    ;; needs no macro-time information whatsoever.
    (define (%fresh-rcd rtd)
      (let ((parent (record-type-parent rtd)))
        (make-record-descriptor rtd (if parent (%fresh-rcd parent) #f) #f)))

    (define (%field-spec-name fs) (car fs))
    (define (%field-spec-accessor fs) (cadr fs))
    (define (%field-spec-mutable? fs) (pair? (cddr fs)))
    (define (%field-spec-mutator fs) (caddr fs))

    ;; make-record-type-descriptor/make-record: SRFI 136's own low-level
    ;; procedural entry points (distinct from SRFI 237's own, differently-
    ;; shaped, same-named procedures -- SRFI 136 field specs are 3-element
    ;; (name accessor mutator)/2-element (name accessor) lists rather than
    ;; SRFI 237's (kind name [accessor]) lists, and there is no uid/sealed/
    ;; opaque concept here).
    (define (make-record-type-descriptor name fieldspecs . maybe-parent)
      (%make-record-type-descriptor
        (symbol->string name)
        (if (and (pair? maybe-parent) (car maybe-parent)) (car maybe-parent) #f)
        #f #f #f
        (map (lambda (fs)
               (cons (symbol->string
                       (if (symbol? fs) fs (%field-spec-name fs)))
                     (or (symbol? fs) (%field-spec-mutable? fs))))
             fieldspecs)))

    (define (make-record rtd field-vector)
      (apply %make-record rtd (vector->list field-vector)))

    (define (record? v) (%record?/any v))
    (define (record-type-descriptor? v) (%record-type? v))
    (define (record-type-descriptor r) (%record-rtd r))
    (define (record-type-predicate rtd) (record-predicate rtd))
    (define (record-type-name rtd) (%record-type-name rtd))
    (define (record-type-parent rtd) (%record-type-parent rtd))

    ;; Returns (field-name accessor mutator) triples for THIS rtd's own
    ;; fields, with mutator #f for an immutable field -- there is no
    ;; portable way to recover the ORIGINAL accessor/mutator PROCEDURE
    ;; objects a define-record-type use created (they are ordinary runtime
    ;; closures, not something the rtd stores), so this rebuilds
    ;; equivalent fresh ones via record-accessor/record-mutator by name.
    ;;
    ;; %record-field-mutable? is called through this separate wrapper, in
    ;; TAIL position within it, rather than directly from inside the map
    ;; lambda below -- calling a %-prefixed forward-referenced global in
    ;; NON-tail position inside a closure passed to `map` produced a
    ;; genuine "undefined variable" compile error in testing (isolated
    ;; down to exactly this shape: works bare or in tail position, fails
    ;; as soon as it's wrapped in `if`/`list`/anything else -- an extra
    ;; wrapper function reliably fixes it regardless of the wrapper's own
    ;; name; the wrapper's OWN body just has to be a bare tail call).
    ;; Ordinary, non-%-prefixed names in the identical shape work fine.
    ;; Not root-caused -- worth a dedicated compiler investigation later.
    (define (%is-mutable-field? rtd idx) (%record-field-mutable? rtd idx))

    (define (record-type-fields rtd)
      (map (lambda (name)
             (let ((idx (%resolve-own-index rtd name)))
               (list name
                     (record-accessor rtd name)
                     (if (%is-mutable-field? rtd idx)
                         (record-mutator rtd name)
                         #f))))
           (record-type-field-names rtd)))

    (define (%resolve-own-index rtd name)
      (let loop ((names (record-type-field-names rtd)) (i 0))
        (cond ((null? names) (error "unknown field" name))
              ((eq? (car names) name) i)
              (else (loop (cdr names) (+ i 1))))))

    (define-syntax define-record-type
      (syntax-rules ()
        ((_ (name parent) ctor-spec pred-spec field-spec ...)
         (%srfi136-expand name parent ctor-spec pred-spec (field-spec ...)))
        ((_ name ctor-spec pred-spec field-spec ...)
         (%srfi136-expand name #f ctor-spec pred-spec (field-spec ...)))))

    (define-syntax %srfi136-parent-rtd
      (syntax-rules ()
        ((_ #f) #f)
        ((_ p) (p))))

    (define-syntax %srfi136-field-list
      (syntax-rules ()
        ((_ ()) '())
        ((_ ((fname facc) rest ...)) (cons (list 'fname 'facc) (%srfi136-field-list (rest ...))))
        ((_ ((fname facc fmut) rest ...)) (cons (list 'fname 'facc 'fmut) (%srfi136-field-list (rest ...))))))

    ;; SRFI 136's explicit (<constructor-name> <field-name> ...) ctor-spec
    ;; -- naming the positional parent/own-field parameters for readability
    ;; only, per the spec's own text ("not strictly necessary... will
    ;; certainly help readability") -- is deliberately not supported: this
    ;; implementation's constructor already gets correct positional
    ;; parent-then-own-field argument order for free from (srfi 237)'s
    ;; record-constructor, so the explicit form would add only cosmetic
    ;; parameter names, not new behavior. The list-shaped pattern below
    ;; exists purely as a guard: without it, `cname` (an unconstrained
    ;; pattern variable) would silently capture the whole
    ;; `(name field ...)` list, and `(define cname (record-constructor
    ;; ...))` would then read as `(define (name field ...) ...)` via
    ;; `define`'s function-definition shorthand -- a silently wrong
    ;; expansion, not a caught error.
    (define-syntax %srfi136-def-ctor
      (syntax-rules ()
        ((_ #f parent rtd) (if #f #f)) ; constructor suppressed
        ((_ (cname field (... ...)) parent rtd) (define cname (%srfi136-unsupported-explicit-ctor-spec)))
        ((_ cname parent rtd) (define cname (record-constructor (%fresh-rcd rtd))))))

    (define (%srfi136-unsupported-explicit-ctor-spec)
      (error "SRFI 136: explicit (constructor-name field-name ...) constructor specs are not supported -- use a bare constructor name; parent-then-own-field positional argument order is automatic"))

    (define-syntax %srfi136-def-pred
      (syntax-rules ()
        ((_ #f rtd) (if #f #f)) ; predicate suppressed
        ((_ pname rtd) (define pname (record-predicate rtd)))))

    (define-syntax %srfi136-def-accessors
      (syntax-rules ()
        ((_ rtd ()) (begin))
        ((_ rtd ((fname facc) rest ...))
         (begin (define facc (record-accessor rtd 'fname)) (%srfi136-def-accessors rtd (rest ...))))
        ((_ rtd ((fname facc fmut) rest ...))
         (begin (define facc (record-accessor rtd 'fname))
                (define fmut (record-mutator rtd 'fname))
                (%srfi136-def-accessors rtd (rest ...))))))

    (define-syntax %srfi136-expand
      (syntax-rules ()
        ((_ name parent ctor-spec pred-spec (field-spec ...))
         (begin
           (define %srfi136-rtd
             (make-record-type-descriptor 'name (%srfi136-field-list (field-spec ...)) (%srfi136-parent-rtd parent)))
           (%srfi136-def-ctor ctor-spec parent %srfi136-rtd)
           (%srfi136-def-pred pred-spec %srfi136-rtd)
           (%srfi136-def-accessors %srfi136-rtd (field-spec ...))
           (define-syntax name
             (syntax-rules ()
               ((_ (keyword datum (... ...))) (keyword datum (... ...) parent field-spec ...))
               ((_) %srfi136-rtd)))))))))
