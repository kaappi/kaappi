;;; SRFI 150: Hygienic ERR5RS Record Syntax (reduced).
;;;
;;; Extends SRFI 131 (lib/srfi/131.sld) with three things: field-name
;;; identifiers are compared hygienically (bound-identifier=? within one
;;; define-record-type form, free-identifier=? across separate forms)
;;; instead of by raw symbol; field names may be non-identifier constants
;;; (numbers, strings, booleans -- always compared with equal?, never
;;; against an identifier); and a constructor spec may name a field by its
;;; accessor as well as by its own field name.
;;;
;;; NOT a port of the reference implementation, and not this codebase's
;;; second implementation attempt either -- see issue #1810's own
;;; investigation notes for the two prior attempts and two apparent kaappi
;;; engine bugs they surfaced along the way (kaappi#1828 and kaappi#1829 --
;;; both since determined NOT to be engine bugs, see below): every design
;;; built on a macro that answers a hygienic-metadata QUERY from a later,
;;; separate define-record-type expansion (the reference's own SRFI 137
;;; `make-subtype` closures; this codebase's first rewrite, a `:secret`
;;; descriptor macro over SRFI 237) broke once more than one such query
;;; relationship existed side by side in the same program.
;;;
;;; kaappi#1829's own minimal, record-free `em-syntax-rules` repro no
;;; longer fails: it was not an expander bug at all but the referential-
;;; transparency collision of kaappi#1832, reached because the CK machine
;;; emits its output as plain data, so a macro-generated top-level define
;;; lands under its BARE name and the next expansion's reference to it is
;;; a free reference to an already-bound global. kaappi#1839's hygiene
;;; rename closed it (see tests/scheme/hygiene/
;;; macro-fresh-global-readback-1829.scm).
;;;
;;; kaappi#1828 also turned out not to be an engine bug: its own repro's
;;; final (non-`=>`) template was unquoted and called an ordinary
;;; procedure, which SRFI 148's own spec documents as an error case
;;; (unrelated to the reported "bound variable as a later step's operator"
;;; framing -- see lib/srfi/148.sld's header and
;;; tests/scheme/hygiene/em-syntax-rules-operator-chain-1828.scm, which
;;; confirms the operator-position mechanism itself works correctly,
;;; including at 3 levels of chaining). Whether the two rejected
;;; implementation attempts above would have succeeded had they not tripped
;;; over this same misunderstanding is not re-tested here -- this file's
;;; own (third) design is unaffected either way, so nothing below changes.
;;;
;;; This THIRD implementation avoids the whole pattern: it never threads
;;; anything across separate define-record-type expansions via a macro
;;; call. Instead:
;;;
;;;   - The record type itself is SRFI 131's approach unchanged: a type
;;;     name is bound directly to an ordinary runtime record-type-
;;;     descriptor (SRFI 237's `make-record-type-descriptor`), inheritance
;;;     is a plain constructor argument, and field/accessor/mutator
;;;     resolution -- including multi-level shadowing -- is handled
;;;     entirely at run time by SRFI 237's own by-name introspection
;;;     (`record-type-parent`/`record-type-field-names`, which
;;;     `record-accessor`/`record-mutator` already walk own-fields-before-
;;;     parent). This half needed no engine-level hygiene machinery at
;;;     all in SRFI 131 and needs none here either.
;;;
;;;   - The one piece SRFI 131 doesn't have -- HYGIENIC field/accessor-name
;;;     matching for named constructor specs (131 matches by raw symbol at
;;;     run time, non-hygienically) -- uses SRFI 213 (identifier
;;;     properties) instead of a query macro: each define-record-type use
;;;     attaches its own (and its ancestors') field/accessor-name pairs to
;;;     the type name via `define-property`, and a child reads its
;;;     parent's via `lookup`. SRFI 213's property table is a plain,
;;;     direct VM-level key-value store (`vm.syntax_properties`), entirely
;;;     bypassing the expander's own macro-to-macro call/argument-
;;;     threading machinery that kaappi#1828 was originally suspected of
;;;     being a bug in (see above) -- confirmed safe for repeated,
;;;     independent inheritance chains during this SRFI's own
;;;     investigation (a record-free prototype using this exact mechanism,
;;;     mirroring kaappi#1829's own failing shape, produces correct
;;;     results).
;;;
;;;   - `lookup` is only reachable from a procedural transformer (SRFI
;;;     211's `capture-lookup` convention; `em-syntax-rules`/plain
;;;     syntax-rules transformers have no way to receive a procedure), so
;;;     define-record-type itself is an er-macro-transformer, not an
;;;     em-syntax-rules macro. This turns out to simplify the hygienic
;;;     comparison too: since this engine represents every identifier as
;;;     a plain, hygiene-renamed symbol (see lib/srfi/211/explicit-
;;;     renaming.sld's own header), and SRFI 213's property storage keeps
;;;     a stored value exactly as given (it is not itself macro-expanded
;;;     or re-processed), a stored field-name/accessor-name symbol
;;;     retains its full hygienic spelling (rename prefix included) across
;;;     the definition/lookup boundary. Plain `equal?` on that raw symbol
;;;     therefore already implements both bound-identifier=? (within one
;;;     form: two same-spelled-but-differently-renamed identifiers are
;;;     literally different symbols) and free-identifier=? (across forms:
;;;     a name written directly by the user resolves to the same bare
;;;     symbol wherever it's written, and a macro-introduced fresh name
;;;     never collides with it) -- verified against the exact scenario
;;;     each SRFI 150 hygiene test group requires (a template-introduced
;;;     field name vs. the same-spelled caller-supplied one; a fresh
;;;     per-expansion rename never matching an unrelated same-spelled
;;;     binding) during this investigation, so no em-bound-identifier=?-
;;;     style machinery is needed at all. This is specific to this
;;;     engine's rename-by-spelling hygiene representation, noted as a
;;;     `(srfi 213)` conformance property already ("nominal... matching
;;;     this symbol-based expander's identity model") -- a portable
;;;     implementation on a syntax-object-based Scheme could not assume
;;;     this and would need real bound-identifier=?/free-identifier=?.
;;;
;;; `field-alist-ref` below spelled its second-element lookup as the
;;; unrolled `(cadr (car alist))` until kaappi#1831 was fixed. `cadar`
;;; is a `(scheme cxr)` name this library does not import, and a library
;;; body's reference to a global outside its own lib_env used to resolve
;;; in tail position only (get_global carried the vm.globals fallback,
;;; call_global did not), so the same call failed as a non-tail operand
;;; and surfaced as a bare "invalid syntax" from the expansion. Two
;;; near-misses made it look `cadar`-specific: `caar`/`cadr`/`cddr` here
;;; are `(scheme base)` names, so they were in lib_env either way, and
;;; the one other cxr-only name, `cdddr` on line 177, sits inside the
;;; transformer's own lambda -- evaluated at macro-definition time in
;;; the global environment, which never consults lib_env at all. The
;;; idiomatic spelling is back.
(define-library (srfi 150)
  ;; (kaappi primitives): the internal %-prefixed helpers this file calls
  ;; below. They used to arrive with (scheme base), which reserved their
  ;; names against every user library (kaappi#1856).
  (import (scheme base) (srfi 211 explicit-renaming) (srfi 213)
          (srfi 237) (srfi 237 primitives) (kaappi primitives))
  (export define-record-type)
  (begin

    ;; ------------------------------------------------------------------
    ;; Runtime helpers -- adapted from lib/srfi/131.sld's own named-
    ;; constructor and index-resolution machinery. `field` here is always
    ;; a field's own canonical name (a plain datum), already resolved
    ;; hygienically by resolve-field-name below at macro-expansion time,
    ;; so no hygiene concern reaches this layer.
    ;; ------------------------------------------------------------------

    (define (fresh-rcd rtd)
      (let ((parent (record-type-parent rtd)))
        (make-record-descriptor rtd (if parent (fresh-rcd parent) #f) #f)))

    (define (field-index rtd name)
      (let ((parent (record-type-parent rtd)))
        (let ((parent-count (if parent (%record-type-total-field-count parent) 0)))
          ;; %record-type-field-names, not the public record-type-field-names:
          ;; the public one answers with a vector (R6RS), the primitive with
          ;; the list this walk wants.
          (field-index-loop rtd name parent (%record-type-field-names rtd) parent-count))))

    (define (field-index-loop rtd name parent names i)
      (cond
        ((null? names) (if parent (field-index parent name) (error "unknown field" name)))
        ((equal? (car names) name) i)
        (else (field-index-loop rtd name parent (cdr names) (+ i 1)))))

    (define (named-constructor rtd field-names)
      (let ((total (%record-type-total-field-count rtd)))
        (lambda args
          (let ((field-values (make-vector total (if #f #f))))
            (named-constructor-fill! rtd field-values field-names args)
            (apply %make-record rtd (vector->list field-values))))))

    (define (named-constructor-fill! rtd field-values field-names args)
      (if (null? field-names)
          (if #f #f)
          (let ((idx (field-index rtd (car field-names))))
            (vector-set! field-values idx (car args))
            (named-constructor-fill! rtd field-values (cdr field-names) (cdr args)))))

    ;; ------------------------------------------------------------------
    ;; Hygienic field-name resolution -- see the header comment for why
    ;; plain `equal?` on the raw (possibly hygiene-renamed) symbol is
    ;; correct here. `alist` entries are (field-name accessor-name).
    ;; Field names take precedence over accessor names (field-name
    ;; checked first), and own fields shadow inherited ones (own-alist
    ;; checked entirely before parent-alist), per SRFI 150's own stated
    ;; precedence rules.
    ;; ------------------------------------------------------------------

    (define (field-alist-ref field alist)
      (cond
        ((null? alist) #f)
        ((equal? field (caar alist)) (caar alist))
        ((equal? field (cadar alist)) (caar alist))
        (else (field-alist-ref field (cdr alist)))))

    (define (resolve-field-name field own-alist parent-alist)
      (or (field-alist-ref field own-alist)
          (field-alist-ref field parent-alist)
          (error "record field not found" field)))

    (define (resolve-field-names fields own-alist parent-alist)
      (if (null? fields)
          '()
          (cons (resolve-field-name (car fields) own-alist parent-alist)
                (resolve-field-names (cdr fields) own-alist parent-alist))))

    (define (keep-truthy lst)
      (cond
        ((null? lst) '())
        ((car lst) (cons (car lst) (keep-truthy (cdr lst))))
        (else (keep-truthy (cdr lst)))))

    ;; ------------------------------------------------------------------
    ;; The record-type definition keyword.
    ;; ------------------------------------------------------------------

    (define-syntax define-record-type
      (er-macro-transformer
       (lambda (form rename compare)
         (let* ((type-spec (cadr form))
                (constructor-spec (car (cddr form)))
                (predicate-spec (cadr (cddr form)))
                (field-specs (cdr (cdddr form)))
                (name (if (pair? type-spec) (car type-spec) type-spec))
                (parent (if (pair? type-spec) (cadr type-spec) #f))
                (own-alist (map (lambda (fs) (list (car fs) (cadr fs))) field-specs)))
           (capture-lookup
            (lambda (lookup)
              (let* ((parent-alist (if parent (lookup parent 'srfi150-fields) '()))
                     (field-vec-spec
                      (map (lambda (fs)
                             (list (if (>= (length fs) 3) 'mutable 'immutable) (car fs)))
                           field-specs))
                     (accessor-defs
                      (map (lambda (fs)
                             (list (rename 'define) (cadr fs)
                                   (list (rename 'record-accessor) name (list (rename 'quote) (car fs)))))
                           field-specs))
                     (mutator-defs
                      (keep-truthy
                       (map (lambda (fs)
                              (and (>= (length fs) 3)
                                   (list (rename 'define) (car (cddr fs))
                                         (list (rename 'record-mutator) name (list (rename 'quote) (car fs))))))
                            field-specs)))
                     (predicate-def
                      (list (rename 'define)
                            (if predicate-spec predicate-spec (rename 'suppressed-predicate))
                            (list (rename 'record-predicate) name)))
                     (ctor-def
                      (cond
                        ((not constructor-spec)
                         (list (rename 'define) (rename 'suppressed-constructor)
                               (list (rename 'record-constructor) (list (rename 'fresh-rcd) name))))
                        ((pair? constructor-spec)
                         (list (rename 'define) (car constructor-spec)
                               (list (rename 'named-constructor) name
                                     (list (rename 'quote)
                                           (resolve-field-names (cdr constructor-spec) own-alist parent-alist)))))
                        (else
                         (list (rename 'define) constructor-spec
                               (list (rename 'record-constructor) (list (rename 'fresh-rcd) name)))))))
                (append
                 (list (rename 'begin)
                       (list (rename 'define) name
                             (list (rename 'make-record-type-descriptor)
                                   (list (rename 'quote) name)
                                   parent
                                   #f #f #f
                                   (list (rename 'list->vector) (list (rename 'quote) field-vec-spec))))
                       predicate-def)
                 accessor-defs
                 mutator-defs
                 (list ctor-def
                       (list (rename 'define-property) name 'srfi150-fields
                             (list (rename 'quote) (append own-alist parent-alist))))))))))))))
