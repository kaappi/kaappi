;; SRFI 150 (Hygienic ERR5RS Record Syntax) tests -- test LOGIC ported
;; verbatim from the SRFI's own reference test suite, srfi/150/test.sld in
;; https://srfi.schemers.org/srfi-150/srfi-150.html, by Marc
;; Nieper-Wisskirchen (2017), MIT-licensed. Two structural deviations from
;; that source, both following tests/scheme/srfi/srfi131.scm's own
;; established convention (this library shares 131's runtime substrate --
;; see lib/srfi/150.sld's header):
;;
;;   - No `test-group` wrapping. `test-group` runs its body inside a
;;     lambda (see its own dynamic-wind-based expansion), and Kaappi's
;;     `define-record-type`-shadowing-by-macro mechanism (needed for any
;;     SRFI in this codebase that redefines `define-record-type`: 131,
;;     136, and now 150) only fires at real top level -- the same
;;     documented limitation both 131.sld and 136.sld already carry
;;     ("library bodies not yet supported"). srfi131.scm's own suite
;;     already works around this by never using `test-group`; this file
;;     follows suit, replacing each reference test-group with a plain
;;     top-level sequence of definitions and labeled assertions.
;;   - Every bare `(test-assert expr)`/`(test-eqv a b)` from the
;;     reference gained a descriptive string label, matching every other
;;     test file in this directory (srfi131.scm included).
;;
;; The whole reference suite passes, including the four assertions
;; (Hygiene 1's two, Hygiene 2's own-field one, and Alex Shinn's
;; explicitly-constructed tuple) that used to be marked `test-expect-fail`
;; for kaappi#2051. That defect -- lib/srfi/150.sld carried field names
;; from expansion time to run time inside `quote`, and a hygiene rename
;; does not survive quoting ((eq? '__hyg_2_a 'a) is #t), so two fields
;; the expander had correctly distinguished (e.g. __hyg_2_a and a)
;; collapsed into one name before the runtime by-name lookup saw them --
;; is fixed by resolving field identity to absolute layout indices and
;; deduped runtime names entirely at macro-expansion time. The reference
;; suite's own shapes are below, followed by the issue's discriminating
;; controls as regression tests: the no-top-level-binding variant (C5),
;; the non-colliding-spelling control (C6), constant field names, and the
;; type-name-redefinition shape (the pre-existing `<record>` binding is
;; NOT the trigger for the field-name collapse; it is a separate,
;; also-fixed hazard for the type-name binding itself).
;;
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi150.scm

(import (scheme base) (scheme write) (scheme process-context) (srfi 64) (srfi 150))

(test-begin "srfi-150")

;;; --- Simple ----------------------------------------------------------

(define-record-type <pare>
  (kons x y)
  pare?
  (x kar set-kar!)
  (y kdr))

(test-assert "simple: predicate recognizes its own instance" (pare? (kons 1 2)))
(test-assert "simple: predicate rejects an unrelated pair" (not (pare? (cons 1 2))))
(test-eqv "simple: first field accessor" 1 (kar (kons 1 2)))
(test-eqv "simple: second field accessor" 2 (kdr (kons 1 2)))
(test-eqv "simple: mutator writes correctly"
  3 (let ((k (kons 1 2))) (set-kar! k 3) (kar k)))

;;; --- Inheritance -------------------------------------------------------

(define-record-type <parent>
  (make-parent x)
  parent?
  (x parent-field parent-set-field!))

(define-record-type (<child> <parent>)
  (make-child x y)
  child?
  (y child-field child-set-field!))

(test-assert "inheritance: ancestor predicate recognizes subtype instance"
  (parent? (make-child 1 2)))
(test-assert "inheritance: own predicate recognizes own instance" (child? (make-child 1 2)))
(test-assert "inheritance: subtype predicate rejects an ancestor-only instance"
  (not (child? (make-parent 1))))
(test-eqv "inheritance: inherited accessor works on subtype instance"
  1 (parent-field (make-child 1 2)))
(test-eqv "inheritance: own accessor works" 2 (child-field (make-child 1 2)))
(test-eqv "inheritance: inherited mutator works on subtype instance"
  3 (let ((c (make-child 1 2))) (parent-set-field! c 3) (parent-field c)))
(test-eqv "inheritance: own mutator works"
  3 (let ((c (make-child 1 2))) (child-set-field! c 3) (child-field c)))

;;; --- Implicit constructor arguments --------------------------------------

(define-record-type <parent>
  (make-parent)
  parent?
  (x parent-field))

(define-record-type (<child> <parent>)
  make-child
  child?
  (y child-field))

(test-eqv "implicit ctor: inherited field set positionally"
  1 (parent-field (make-child 1 2)))
(test-eqv "implicit ctor: own field set positionally" 2 (child-field (make-child 1 2)))

;;; --- Shadowing of parent fields -------------------------------------------

(define-record-type <parent>
  (make-parent x)
  parent?
  (x parent-field parent-set-field!))

(define-record-type (<child> <parent>)
  (%make-child x)
  child?
  (x child-field))

(define (make-child x)
  (let ((c (%make-child x)))
    (parent-set-field! c 'undefined)
    c))

(test-eqv "shadowing: child's own field set via child's own constructor"
  1 (child-field (make-child 1)))
(test-eqv "shadowing: parent's same-named field is untouched by child's constructor"
  'undefined (parent-field (make-child 1)))

;;; --- Field referral through accessors -------------------------------------

(define-record-type <record>
  (make-record x y get-z)
  record?
  (x get-x)
  (y x)
  (z get-z))

(test-eqv "field referral: field named x, referenced by name" 1 (get-x (make-record 1 2 3)))
(test-eqv "field referral: field named y, referenced by its accessor name x"
  2 (x (make-record 1 2 3)))
(test-eqv "field referral: field named z, referenced by its accessor name"
  3 (get-z (make-record 1 2 3)))

;;; --- Hygiene 1 -------------------------------------------------------------

(define a #f)

(define-syntax def
  (syntax-rules ()
    ((def b make-record get-a get-b)
     (define-record-type <record>
       (make-record a b)
       record?
       (a get-a)
       (b get-b)))))

(def a make-record get-a get-b)

;; kaappi#2051: `def`'s own field-name literal `a` and the `a` this use
;; site passes as `b` are distinct after expansion (__hyg_2_a vs a) but
;; used to collapse to one name when SRFI 150 carried them through `quote`
;; into its runtime by-name lookup. The `(define a #f)` above is NOT the
;; trigger (see the C5 control below); a pre-existing top-level binding of
;; the type name `<record>` from the field-referral section above IS a
;; separate hazard that used to surface here too -- the type-name binding
;; is now emitted hygiene-stripped, so the accessors below bind against the
;; freshly redefined type rather than the old one. Both are fixed; these
;; used to be `test-expect-fail`.
(test-eqv "hygiene 1: macro's own field name, unconfused by caller's same-spelled argument"
  1 (get-a (make-record 1 2)))
(test-eqv "hygiene 1: caller's argument correctly becomes its own, separate field"
  2 (get-b (make-record 1 2)))

;;; --- Hygiene 2 -------------------------------------------------------------

(define x #f)

(define-record-type <parent>
  (make-parent x)
  parent?
  (x parent-get))

(define-syntax define-child
  (syntax-rules ()
    ((define-child make-child child-get parent-field)
     (define-record-type (<child> <parent>)
       (make-child parent-field x)
       child?
       (x child-get)))))

(define-child make-child child-get x)

;; kaappi#2051, same root cause as hygiene 1: the template's own field `x`
;; and the inherited parent field the use site names `x` collapse to one
;; name through `quote`. The constructor now resolves its arguments to
;; absolute indices at expansion time, so the parent field (index 0) and
;; the shadowing own field (index 1) are filled separately even though
;; both spellings strip to `x`. Used to be `test-expect-fail`.
(test-eqv "hygiene 2: inherited field set via macro-introduced reference"
  1 (parent-get (make-child 1 2)))
(test-eqv "hygiene 2: own field, unconfused by the macro's own same-spelled field name"
  2 (child-get (make-child 1 2)))

;;; --- Alex Shinn's example --------------------------------------------------

(define-syntax define-tuple-type
  (syntax-rules ()
    ((define-tuple-type name make pred x-ref (defaults ...))
     (deftuple name (make) pred x-ref (defaults ...) (defaults ...) ()))))

(define-syntax deftuple
  (syntax-rules ()
    ((deftuple name (make args ...) pred x-ref defaults (default . rest)
       (fields ...))
     (deftuple name (make args ... tmp) pred x-ref defaults rest
       (fields ... (tmp tmp))))
    ((deftuple name (make args ...) pred x-ref (defaults ...) ()
       ((field-name get) ...))
     (begin
       (define-record-type name (make-tmp args ...) pred
         (field-name get) ...)
       (define (make . o)
         (if (pair? o) (apply make-tmp o) (make-tmp defaults ...)))
       (define x-ref
         (let ((accessors (vector get ...)))
           (lambda (x i)
             ((vector-ref accessors i) x))))))))

(define-tuple-type point make-point point? point-ref (0 0))

(test-equal "Alex Shinn's example: default-filled tuple"
  '(0 0) (let ((pt (make-point))) (list (point-ref pt 0) (point-ref pt 1))))
;; kaappi#2051, same root cause as the hygiene tests: deftuple's per-step
;; `tmp` template literal is renamed per step (__hyg_1_tmp, __hyg_2_tmp)
;; and the two fields used to strip to one shared `tmp` through `quote`,
;; so both explicitly-supplied fields read back as the second argument
;; ((2 2) instead of (1 2)). Used to be `test-expect-fail`.
(test-equal "Alex Shinn's example: explicitly-constructed tuple"
  '(1 2) (let ((pt (make-point 1 2))) (list (point-ref pt 0) (point-ref pt 1))))

;;; --- kaappi#2051 regression controls ----------------------------------------

;; C5 from the issue: the exact Hygiene 1 shape with NO top-level `a` at
;; all. It failed identically to the reference shape before the fix --
;; proving a pre-existing binding of the colliding spelling was never
;; required -- and must pass now.
(define-syntax def-no-binding
  (syntax-rules ()
    ((def-no-binding b make-record get-a get-b)
     (define-record-type <r-no-binding>
       (make-record a b)
       r-no-binding?
       (a get-a)
       (b get-b)))))

(def-no-binding a make-record get-a get-b)

(test-equal "issue C5: no pre-existing binding of the colliding spelling"
  '(1 2) (list (get-a (make-record 1 2)) (get-b (make-record 1 2))))

;; C6 from the issue: same macro, but the use site passes a NON-colliding
;; spelling. This passed even before the fix and pins down that the
;; trigger is purely the spelling collision, not the macro shape.
(define-syntax def-non-colliding
  (syntax-rules ()
    ((def-non-colliding b make-record get-a get-b)
     (define-record-type <r-non-colliding>
       (make-record a b)
       r-non-colliding?
       (a get-a)
       (b get-b)))))

(def-non-colliding q make-record get-a get-b)

(test-equal "issue C6: non-colliding use-site spelling"
  '(1 2) (list (get-a (make-record 1 2)) (get-b (make-record 1 2))))

;; The issue's minimal reproduction, verbatim.
(define-syntax def-minimal
  (syntax-rules ()
    ((def-minimal b mk ga gb)
     (define-record-type <r-minimal> (mk a b) r-minimal? (a ga) (b gb)))))

(def-minimal a mk ga gb)

(test-equal "issue minimal reproduction"
  '(1 2) (list (ga (mk 1 2)) (gb (mk 1 2))))

;; The type-name-redefinition hazard is exercised by the reference suite's
;; Hygiene 1 shape above: `<record>` is already bound (field-referral
;; section) when `def` redefines it through a macro, and the accessors
;; still bind against the freshly redefined type. The type-name binding is
;; emitted hygiene-stripped, so the redefinition lands on the global like
;; any top-level redefinition instead of being shadowed by the engine's
;; referential-transparency alias for the old type.

;; Non-identifier constant field names (SRFI 150: field names may be
;; numbers, strings, booleans, or characters; matched with equal?, never
;; against an identifier).
(define-record-type <const-rec>
  (make-const-rec 1 2)
  const-rec?
  (1 get-one)
  (2 get-two))

(test-equal "constant field names: numbers"
  '(10 20) (list (get-one (make-const-rec 10 20)) (get-two (make-const-rec 10 20))))

(define-record-type <const-str>
  (make-const-str "x" "y")
  const-str?
  ("x" get-str-x)
  ("y" get-str-y))

(test-equal "constant field names: strings"
  '(1 2) (list (get-str-x (make-const-str 1 2)) (get-str-y (make-const-str 1 2))))

;; An inherited constant field, referenced through the constructor.
(define-record-type <const-parent>
  (make-const-parent 1)
  const-parent?
  (1 get-parent-one))

(define-record-type (<const-child> <const-parent>)
  (make-const-child 1 2)
  const-child?
  (2 get-child-two))

(test-equal "constant field names: inherited, set through child constructor"
  '(10 20) (list (get-parent-one (make-const-child 10 20))
                 (get-child-two (make-const-child 10 20))))

;; The `__hyg_` note from the issue: the strip is by spelling, not by
;; provenance -- a symbol a user literally types as `'__hyg_2_a` also
;; reads back as `a` in quoted data. That is engine behavior, unchanged by
;; this fix; pinned here so the SRFI's own field-name handling stays
;; visibly distinct from it.
(test-assert "engine: quoted __hyg_-prefixed symbol strips by spelling"
  (eq? '__hyg_2_a 'a))

(let ((runner (test-runner-current)))
  (test-end "srfi-150")
  (if (> (test-runner-fail-count runner) 0) (exit 1) (exit 0)))
