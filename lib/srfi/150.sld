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
;;;     em-syntax-rules macro.
;;;
;;; The hygienic comparison and the constructor's field-name resolution
;;; BOTH happen entirely at macro-expansion time, against the already-
;;; hygiene-renamed form the expander hands the transformer. Nothing
;;; hygienic is carried into runtime data at all, which is the point of
;;; the redesign (kaappi#2051):
;;;
;;;   * Field identity is resolved to a numeric ABSOLUTE index into the
;;;     full (inherited-then-own) field layout while the transformer still
;;;     has the renamed symbols in hand: a constructor spec entry first
;;;     matches the current form's own fields by FULL spelling (the same
;;;     template identifier renames to the same gensym within one
;;;     expansion, so this is bound-identifier=? in this engine's
;;;     rename-by-spelling model), then falls back to the parent's stored
;;;     entries matched by hygiene-STRIPPED spelling (free-identifier=?
;;;     for the top-level bindings a parent's field name actually refers
;;;     to). The named constructor then fills the record's field vector by
;;;     index; no field name ever crosses the expansion/runtime boundary
;;;     to be looked up by name at run time.
;;;
;;;   * Each own field gets a RUNTIME NAME for the record-type-descriptor
;;;     and for `record-accessor`/`record-mutator` creation: the field
;;;     name's hygiene-stripped spelling, or -- when two own fields of one
;;;     type strip to the same spelling (the Hygiene 1 shape: a macro
;;;     template's own field-name literal colliding in spelling with the
;;;     identifier the use site supplies, e.g. `__hyg_2_a` and `a`) -- the
;;;     stripped spelling with a numeric suffix, deduped against the type's
;;;     other own fields. These runtime names are quoted data and must
;;;     survive `quote` intact, so they are never hygiene-renamed; a
;;;     non-identifier constant field name (a number, string, boolean, or
;;;     character) has no spelling to preserve and gets a generated
;;;     `field-<index>` name instead (the rtd layer requires a symbol).
;;;     An own field whose stripped spelling matches an inherited field's
;;;     is fine and deliberately NOT deduped -- that is ordinary shadowing
;;;     (SRFI 150: "field names in children shadow field names in
;;;     parents"), and the runtime by-name walk resolves own-fields-first
;;;     anyway.
;;;
;;;   * The property table stores, per type, the type's TOTAL field count
;;;     (the child's own-field base) plus an alist mapping each field's
;;;     (and accessor's) stripped-spelling KEY to its absolute index --
;;;     keys and indices only, never runtime names and never renamed
;;;     symbols. Matching keys for a child's inherited-field reference are
;;;     the parent's stored stripped spellings, which is what makes
;;;     cross-form matching work at all: a rename gensym is
;;;     per-expansion, so a child could never reproduce a parent's
;;;     `__hyg_N_` spelling to compare against it.
;;;
;;;   * The emitted TYPE-NAME binding is the hygiene-stripped spelling,
;;;     not the renamed one: the type name is a define target, and a
;;;     template-introduced `__hyg_N_<t>` reference whose base `<t>` is an
;;;     already-bound global is intercepted by the engine's #1832
;;;     referential-transparency alias (it loads the PRE-EXISTING global's
;;;     value for every such reference, even inside the same expansion
;;;     that defines it), so accessors and constructor would bind against
;;;     the OLD record type whenever a macro redefined an already-bound
;;;     type name. The bare spelling rebinds the global like any top-level
;;;     redefinition (R7RS 5.3.1) and matches what SRFI 131 emits for its
;;;     type names; the property table key strips either way.
;;;
;;; This is specific to this engine's rename-by-spelling hygiene
;;; representation, noted as a `(srfi 213)` conformance property already
;;; ("nominal... matching this symbol-based expander's identity model") --
;;; a portable implementation on a syntax-object-based Scheme could not
;;; assume it and would need real bound-identifier=?/free-identifier=?.
;;; The reference implementation's own test suite (ported verbatim in
;;; tests/scheme/srfi/srfi150.scm) passes in full; the four assertions it
;;; used to mark `test-expect-fail` for kaappi#2051 are now unmarked.
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
    ;; constructor machinery. `indices` is a list of ABSOLUTE indices
    ;; into the full (inherited-then-own) field layout, resolved
    ;; hygienically at macro-expansion time, so no hygiene concern
    ;; reaches this layer and no runtime by-name lookup happens at all.
    ;; ------------------------------------------------------------------

    (define (fresh-rcd rtd)
      (let ((parent (record-type-parent rtd)))
        (make-record-descriptor rtd (if parent (fresh-rcd parent) #f) #f)))

    (define (named-constructor rtd indices)
      (let ((total (%record-type-total-field-count rtd)))
        (lambda args
          (let ((field-values (make-vector total (if #f #f))))
            (named-constructor-fill! field-values indices args)
            (apply %make-record rtd (vector->list field-values))))))

    (define (named-constructor-fill! field-values indices args)
      (if (null? indices)
          (if #f #f)
          (begin
            (vector-set! field-values (car indices) (car args))
            (named-constructor-fill! field-values (cdr indices) (cdr args)))))

    ;; ------------------------------------------------------------------
    ;; Expansion-time helpers. Everything below runs inside the
    ;; transformer's lambda -- or in a library-level helper it calls --
    ;; against the hygiene-renamed `form` the expander hands it.
    ;; ------------------------------------------------------------------

    ;; hygiene-strip-name mirrors types.stripHygienicPrefix: remove a
    ;; `__hyg_<n>_` gensym prefix (and a `__kaappi_defenv__<lib>\x1f`
    ;; definition-environment prefix), looping, leaving the underlying
    ;; name. A name that merely starts with one of the markers but has no
    ;; separator (e.g. `__hyg_foo` or `__kaappi_defenv__foo`) is left
    ;; untouched, exactly as the engine's own quote-time stripping does.
    (define (hygiene-strip-name s)
      (let loop ((s s))
        (cond
          ((and (string-prefix? "__hyg_" s)
                (string-index s #\_ 6))
           => (lambda (sep)
                (loop (substring s (+ sep 1) (string-length s)))))
          ((string-prefix? "__kaappi_defenv__" s)
           (let ((rest (substring s (string-length "__kaappi_defenv__"))))
             (if (string-index rest #\x1f)
                 (loop (substring rest (+ (string-index rest #\x1f) 1)))
                 s)))
          (else s))))

    ;; A matching KEY for a field/accessor name: the name's hygiene-
    ;; stripped spelling when it is an identifier, the datum itself (a
    ;; constant) otherwise. An identifier is never equal? to a constant,
    ;; so the two kinds never collide in an alist lookup.
    (define (hygiene-strip-key x)
      (if (symbol? x)
          (string->symbol (hygiene-strip-name (symbol->string x)))
          x))

    ;; The runtime name of an own field: its stripped spelling, with a
    ;; numeric suffix appended while the candidate collides with an
    ;; already-assigned runtime name of the same type (two own fields
    ;; stripping to one spelling -- the kaappi#2051 shape). `used` is the
    ;; list of runtime names assigned so far.
    (define (dedupe-name name used)
      (if (not (member name used))
          name
          (let loop ((n 2))
            (let ((cand (string->symbol
                         (string-append (symbol->string name) "-" (number->string n)))))
              (if (not (member cand used))
                  cand
                  (loop (+ n 1)))))))

    ;; Per-own-field expansion-time data, walked once. Returns three
    ;; values: the runtime names (one per field, deduped), the own alist
    ;; keyed by FULL spelling (for in-form, bound-identifier=-style
    ;; matching; field-name key before accessor-name key per SRFI 150's
    ;; precedence rule), and the property alist keyed by STRIPPED
    ;; spelling (for a child's cross-form matching). `base` is the number
    ;; of inherited fields, so own field i sits at absolute index base+i.
    (define (own-field-data specs base)
      (let loop ((specs specs) (i 0) (used '()) (rnames '()) (okeys '()) (oprops '()))
        (if (null? specs)
            (values (reverse rnames) (reverse okeys) (reverse oprops))
            (let* ((fs (car specs))
                   (abs (+ base i))
                   (cand (if (symbol? (car fs))
                             (hygiene-strip-key (car fs))
                             (string->symbol
                              (string-append "field-" (number->string abs)))))
                   (nm (dedupe-name cand used))
                   (field-key (car fs))
                   (acc-key (cadr fs)))
              (loop (cdr specs)
                    (+ i 1)
                    (cons nm used)
                    (cons nm rnames)
                    (cons (cons field-key abs) (cons (cons acc-key abs) okeys))
                    (cons (cons (hygiene-strip-key field-key) abs)
                          (cons (cons (hygiene-strip-key acc-key) abs) oprops)))))))

    ;; Resolve one constructor-spec entry to its absolute index: own
    ;; fields first (full spelling), then inherited fields (stripped
    ;; spelling against the parent's stored property). The precedence
    ;; rule -- a name that is both a field name and an accessor name
    ;; resolves to the FIELD -- falls out of the alists' ordering:
    ;; within each field's pair of keys the field name comes first, and
    ;; the entries are in field order.
    (define (field-alist-ref key alist)
      (cond
        ((null? alist) #f)
        ((equal? key (caar alist)) (cdar alist))
        (else (field-alist-ref key (cdr alist)))))

    (define (resolve-field-index field own-keys parent-map)
      (or (field-alist-ref field own-keys)
          (field-alist-ref (hygiene-strip-key field) parent-map)
          (error "record field not found" field)))

    (define (resolve-field-indices fields own-keys parent-map)
      (if (null? fields)
          '()
          (cons (resolve-field-index (car fields) own-keys parent-map)
                (resolve-field-indices (cdr fields) own-keys parent-map))))

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
                ;; The emitted binding name for the type. Deliberately the
                ;; hygiene-STRIPPED spelling, not the renamed one `name`: the
                ;; type name is a define target, and a template-introduced
                ;; __hyg_N_<t> reference whose base <t> is an already-bound
                ;; global is intercepted by the engine's #1832 referential-
                ;; transparency alias (it loads the PRE-EXISTING global's
                ;; value for every __hyg_N_<t> reference, even inside the
                ;; same expansion that defines it), so the accessors and
                ;; constructor would bind against the OLD record type. The
                ;; bare spelling rebinds the global like any top-level
                ;; redefinition (R7RS 5.3.1), and matches what SRFI 131
                ;; emits for its type names; the property table key strips
                ;; either way.
                (type-name (hygiene-strip-key name)))
           (capture-lookup
            (lambda (lookup)
              (let* ((parent-data (if parent (lookup parent 'srfi150-fields) #f))
                     (parent-count (if parent-data (car parent-data) 0))
                     (parent-map (if parent-data (cadr parent-data) '()))
                     (own-data (own-field-data field-specs parent-count)))
                (let-values (((runtime-names own-keys own-property) own-data))
                  (let* ((field-vec-spec
                      (map (lambda (fs nm)
                             (list (if (>= (length fs) 3) 'mutable 'immutable) nm))
                           field-specs runtime-names))
                     (accessor-defs
                      (map (lambda (fs nm)
                             (list (rename 'define) (cadr fs)
                                   (list (rename 'record-accessor) type-name
                                         (list (rename 'quote) nm))))
                           field-specs runtime-names))
                     (mutator-defs
                      (keep-truthy
                       (map (lambda (fs nm)
                              (and (>= (length fs) 3)
                                   (list (rename 'define) (car (cddr fs))
                                         (list (rename 'record-mutator) type-name
                                               (list (rename 'quote) nm)))))
                            field-specs runtime-names)))
                     (predicate-def
                      (list (rename 'define)
                            (if predicate-spec predicate-spec (rename 'suppressed-predicate))
                            (list (rename 'record-predicate) type-name)))
                     (ctor-def
                      (cond
                        ((not constructor-spec)
                         (list (rename 'define) (rename 'suppressed-constructor)
                               (list (rename 'record-constructor) (list (rename 'fresh-rcd) type-name))))
                        ((pair? constructor-spec)
                         (list (rename 'define) (car constructor-spec)
                               (list (rename 'named-constructor) type-name
                                     (list (rename 'quote)
                                           (resolve-field-indices
                                            (cdr constructor-spec) own-keys parent-map)))))
                        (else
                         (list (rename 'define) constructor-spec
                               (list (rename 'record-constructor) (list (rename 'fresh-rcd) type-name)))))))
                (append
                 (list (rename 'begin)
                       (list (rename 'define) type-name
                             (list (rename 'make-record-type-descriptor)
                                   (list (rename 'quote) type-name)
                                   parent
                                   #f #f #f
                                   (list (rename 'list->vector) (list (rename 'quote) field-vec-spec))))
                       predicate-def)
                 accessor-defs
                 mutator-defs
                 (list ctor-def
                       (list (rename 'define-property) type-name 'srfi150-fields
                             (list (rename 'quote)
                                   (list (+ parent-count (length field-specs))
                                         (append own-property parent-map)))))))))))))))))
