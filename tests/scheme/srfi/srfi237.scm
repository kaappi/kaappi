;; SRFI-237 (R6RS Records, refined) conformance tests.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi237.scm

(import (scheme base) (scheme write) (srfi 64) (srfi 237))

(test-begin "srfi-237")

;; #t iff calling thunk raises any error/exception.
(define (raises? thunk)
  (call-with-current-continuation
    (lambda (k)
      (with-exception-handler
        (lambda (c) (k #t))
        (lambda () (thunk) #f)))))

;;; --- syntactic layer: name-spec and field-spec variants ---------------

(define-record-type point
  (fields (immutable x point-x) (immutable y point-y)))
(test-assert "bare name-spec: predicate recognizes its own instance" (point? (make-point 1 2)))
(test-equal "bare name-spec: auto make-<name> constructor" 1 (point-x (make-point 1 2)))
(test-equal "bare name-spec: auto <name>? predicate name resolves" 2 (point-y (make-point 1 2)))
(test-assert "bare name-spec: unrelated value is not a point" (not (point? 5)))

(define-record-type (frob make-frob frob?)
  (fields widget (mutable gadget frob-gadget frob-gadget-set!)))
(test-assert "3-element name-spec: explicit ctor/pred used" (frob? (make-frob 1 2)))
(let ((f (make-frob 1 2)))
  (test-equal "bare field spec: accessor reads correctly" 1 (frob-widget f))
  (test-equal "mutable field: initial value" 2 (frob-gadget f))
  (frob-gadget-set! f 99)
  (test-equal "mutable field: mutator writes correctly" 99 (frob-gadget f)))

(define-record-type box (fields (mutable contents)))
(let ((b (make-box 'a)))
  (test-equal "(mutable name): auto accessor" 'a (box-contents b))
  (box-contents-set! b 'b)
  (test-equal "(mutable name): auto mutator (<acc>-set!)" 'b (box-contents b)))

;;; --- inheritance, no protocol -------------------------------------------

(define-record-type animal (fields (immutable name animal-name)))
(define-record-type (dog make-dog dog?) (parent animal) (fields (immutable breed dog-breed)))
(define-record-type widget-type (fields (immutable sku widget-type-sku)))

(let ((d (make-dog "Rex" "Labrador")))
  (test-assert "inheritance: ancestor predicate recognizes subtype instance" (animal? d))
  (test-assert "inheritance: own predicate recognizes own instance" (dog? d))
  (test-equal "inheritance: inherited accessor works on subtype instance" "Rex" (animal-name d))
  (test-equal "inheritance: own accessor works" "Labrador" (dog-breed d)))

(let ((w (make-widget-type "SKU1")))
  (test-assert "inheritance: unrelated type rejected by subtype predicate" (not (dog? w)))
  (test-assert "inheritance: unrelated type rejected by ancestor-shaped predicate" (not (animal? w))))

;; 3-level chain
(define-record-type (puppy make-puppy puppy?) (parent dog) (fields (immutable age puppy-age)))
(let ((pp (make-puppy "Fido" "Poodle" 1)))
  (test-assert "3-level chain: grandparent predicate" (animal? pp))
  (test-assert "3-level chain: parent predicate" (dog? pp))
  (test-assert "3-level chain: own predicate" (puppy? pp))
  (test-equal "3-level chain: grandparent accessor" "Fido" (animal-name pp))
  (test-equal "3-level chain: parent accessor" "Poodle" (dog-breed pp))
  (test-equal "3-level chain: own accessor" 1 (puppy-age pp)))

;;; --- protocols ------------------------------------------------------------

(define-record-type (point3 make-point3 point3?)
  (fields (immutable x point3-x) (immutable y point3-y))
  (protocol (lambda (new) (lambda (x y) (new (abs x) (abs y))))))
(let ((p (make-point3 -3 -4)))
  (test-equal "no-parent protocol: transforms constructor args" 3 (point3-x p))
  (test-equal "no-parent protocol: transforms both args" 4 (point3-y p)))

;; R6RS's own canonical example: protocol at BOTH parent and child levels.
(define-record-type base-shape
  (fields (immutable color base-shape-color))
  (protocol (lambda (new) (lambda (c) (new (string-append "color:" c))))))
(define-record-type (circle make-circle circle?)
  (parent base-shape)
  (fields (immutable radius circle-radius))
  (protocol (lambda (n) (lambda (c r) (let ((p (n c))) (p (* r r)))))))
(let ((c (make-circle "red" 5)))
  (test-equal "parent+child protocol: parent's own protocol ran" "color:red" (base-shape-color c))
  (test-equal "parent+child protocol: child's own protocol ran" 25 (circle-radius c))
  (test-assert "parent+child protocol: ancestor predicate still works" (base-shape? c))
  (test-assert "parent+child protocol: own predicate still works" (circle? c)))

;;; --- sealed / opaque --------------------------------------------------

(define-record-type sealed-thing (fields (immutable v sealed-thing-v)) (sealed #t) (opaque #t))
(test-assert "sealed+opaque record still constructs and type-checks" (sealed-thing? (make-sealed-thing 1)))

;;; --- nongenerative --------------------------------------------------------

(define-record-type shared-thing (fields (immutable v shared-thing-v)) (nongenerative my-shared-uid))
(define shared-inst (make-shared-thing 42))
(test-assert "nongenerative: instance recognized before redefinition" (shared-thing? shared-inst))
(define-record-type shared-thing (fields (immutable v shared-thing-v)) (nongenerative my-shared-uid))
(test-assert "nongenerative: same uid reuses the RTD across redefinition"
             (shared-thing? shared-inst))
(test-equal "nongenerative: reused RTD reads fields correctly" 42 (shared-thing-v shared-inst))

(define-record-type gen-thing (fields (immutable v gen-thing-v)))
(define gen-inst (make-gen-thing 1))
(define old-gen-pred gen-thing?)
(define-record-type gen-thing (fields (immutable v gen-thing-v)))
(test-assert "generative (default): old predicate still recognizes its own instance" (old-gen-pred gen-inst))
(test-assert "generative (default): redefinition creates an unrelated type" (not (gen-thing? gen-inst)))

;;; --- explicit (generative) clause ------------------------------------------
;;; (generative) combined with (nongenerative ...) being rejected is verified
;;; separately, not here: a top-level define-record-type that fails to parse
;;; is a compile error that aborts the whole file, not a catchable exception
;;; a SRFI-64 suite can assert against in-process.

(define-record-type explicit-gen (fields (immutable v explicit-gen-v)) (generative))
(define explicit-gen-inst (make-explicit-gen 1))
(define old-explicit-gen-pred explicit-gen?)
(define-record-type explicit-gen (fields (immutable v explicit-gen-v)) (generative))
(test-assert "explicit (generative): record-type-generative? is true"
  (record-type-generative? explicit-gen))
(test-assert "explicit (generative): behaves like the default (old predicate still recognizes its own instance)"
  (old-explicit-gen-pred explicit-gen-inst))
(test-assert "explicit (generative): behaves like the default (redefinition creates an unrelated type)"
  (not (explicit-gen? explicit-gen-inst)))

;;; --- the declared record name itself is bound to its descriptor -----------

(test-assert "the record name identifier evaluates to its own record-type descriptor"
  (record-type-descriptor? point))
(test-eq "the record name identifier is the rtd record-predicate resolves to"
  point (record-rtd (make-point 1 2)))

;;; --- procedural layer: mirrors the syntactic-layer coverage above ---------

(define proc-point-rtd (make-record-type-descriptor 'proc-point #f #f #f #f #((immutable x) (immutable y))))
(test-assert "procedural: record-type-descriptor? recognizes an rtd" (record-type-descriptor? proc-point-rtd))
(test-assert "procedural: record-type-descriptor? rejects a non-rtd" (not (record-type-descriptor? 5)))
(test-equal "procedural: record-type-name" 'proc-point (record-type-name proc-point-rtd))
(test-equal "procedural: record-type-field-names (own fields, in order)" '#(x y) (record-type-field-names proc-point-rtd))
(test-assert "procedural: record-type-generative? true with no uid" (record-type-generative? proc-point-rtd))
(test-assert "procedural: record-type-sealed? false by default" (not (record-type-sealed? proc-point-rtd)))
(test-assert "procedural: record-type-opaque? false by default" (not (record-type-opaque? proc-point-rtd)))
(test-assert "procedural: record-type-parent is #f for a root type" (not (record-type-parent proc-point-rtd)))

(define proc-point-rcd (make-record-descriptor proc-point-rtd #f #f))
(test-assert "procedural: record-descriptor? recognizes an rcd" (record-descriptor? proc-point-rcd))
(test-equal "procedural: record-descriptor-rtd round-trips" proc-point-rtd (record-descriptor-rtd proc-point-rcd))
(test-assert "procedural: record-descriptor-parent is #f for a root rcd" (not (record-descriptor-parent proc-point-rcd)))

(define proc-make-point (record-constructor proc-point-rcd))
(define proc-point? (record-predicate proc-point-rtd))
(define proc-point-x (record-accessor proc-point-rtd 'x))
(define proc-point-y (record-accessor proc-point-rtd 0))
(let ((pp (proc-make-point 7 8)))
  (test-assert "procedural: record-constructor + record-predicate" (proc-point? pp))
  (test-equal "procedural: record-accessor by field name" 7 (proc-point-x pp))
  (test-equal "procedural: record-accessor by own-field index" 7 (proc-point-y pp))
  (test-assert "procedural: record? recognizes any record" (record? pp))
  (test-eq "procedural: record-rtd round-trips" proc-point-rtd (record-rtd pp)))
(test-assert "procedural: record? rejects a non-record" (not (record? 5)))

(define proc-box-rtd (make-record-type-descriptor 'proc-box #f #f #f #f #((mutable contents))))
(define proc-box-rcd (make-record-descriptor proc-box-rtd #f #f))
(define proc-make-box (record-constructor proc-box-rcd))
(define proc-box-contents (record-accessor proc-box-rtd 'contents))
(define proc-box-contents-set! (record-mutator proc-box-rtd 'contents))
(test-assert "procedural: record-field-mutable? true for a mutable field" (record-field-mutable? proc-box-rtd 0))
(let ((b (proc-make-box 1)))
  (proc-box-contents-set! b 2)
  (test-equal "procedural: record-mutator writes correctly" 2 (proc-box-contents b)))

;; procedural inheritance, no protocol
(define proc-animal-rtd (make-record-type-descriptor 'proc-animal #f #f #f #f #((immutable name))))
(define proc-animal-rcd (make-record-descriptor proc-animal-rtd #f #f))
(define proc-make-animal (record-constructor proc-animal-rcd))
(define proc-animal? (record-predicate proc-animal-rtd))
(define proc-animal-name (record-accessor proc-animal-rtd 'name))

(define proc-dog-rtd (make-record-type-descriptor 'proc-dog proc-animal-rtd #f #f #f #((immutable breed))))
(test-equal "procedural: record-type-parent round-trips" proc-animal-rtd (record-type-parent proc-dog-rtd))
(define proc-dog-rcd (make-record-descriptor proc-dog-rtd proc-animal-rcd #f))
(define proc-make-dog (record-constructor proc-dog-rcd))
(define proc-dog? (record-predicate proc-dog-rtd))
(define proc-dog-breed (record-accessor proc-dog-rtd 'breed))

(let ((d (proc-make-dog "Rex" "Lab")))
  (test-assert "procedural inheritance: ancestor predicate" (proc-animal? d))
  (test-assert "procedural inheritance: own predicate" (proc-dog? d))
  (test-equal "procedural inheritance: inherited accessor" "Rex" (proc-animal-name d))
  (test-equal "procedural inheritance: own accessor" "Lab" (proc-dog-breed d)))

;; procedural inheritance, protocol at both levels (mirrors the syntactic test)
(define proc-shape-rtd (make-record-type-descriptor 'proc-shape #f #f #f #f #((immutable color))))
(define proc-shape-rcd (make-record-descriptor proc-shape-rtd #f
                          (lambda (new) (lambda (c) (new (string-append "color:" c))))))
(define proc-circle-rtd (make-record-type-descriptor 'proc-circle proc-shape-rtd #f #f #f #((immutable radius))))
(define proc-circle-rcd (make-record-descriptor proc-circle-rtd proc-shape-rcd
                           (lambda (n) (lambda (c r) (let ((p (n c))) (p (* r r)))))))
(define proc-make-circle (record-constructor proc-circle-rcd))
(define proc-shape-color (record-accessor proc-shape-rtd 'color))
(define proc-circle-radius (record-accessor proc-circle-rtd 'radius))
(let ((c (proc-make-circle "blue" 4)))
  (test-equal "procedural protocol chain: parent protocol ran" "color:blue" (proc-shape-color c))
  (test-equal "procedural protocol chain: child protocol ran" 16 (proc-circle-radius c)))

;;; --- nongenerative via the procedural layer + record-uid->rtd -------------

(define proc-uid-rtd1 (make-record-type-descriptor 'proc-uid-thing #f 'proc-uid-example #f #f #((immutable v))))
(define proc-uid-rtd2 (make-record-type-descriptor 'proc-uid-thing #f 'proc-uid-example #f #f #((immutable v))))
(test-eq "procedural nongenerative: same uid reuses the same rtd object" proc-uid-rtd1 proc-uid-rtd2)
(test-equal "procedural nongenerative: record-type-uid round-trips" 'proc-uid-example (record-type-uid proc-uid-rtd1))
(test-eq "record-uid->rtd resolves a registered uid" proc-uid-rtd1 (record-uid->rtd 'proc-uid-example))
(test-assert "record-uid->rtd returns #f for an unregistered uid" (not (record-uid->rtd 'never-registered-uid)))

;; regression #2161 — the two assertions above pass only because nothing
;; allocates between the two definitions. The registry used to key off the
;; uid argument's own SchemeString bytes (`symbol->string` of the uid, made
;; fresh by the portable layer on every call), so once that string was
;; collected the key dangled, the lookup missed, and the second definition
;; built a fresh, non-interoperable rtd — silently, which is the one thing
;; `nongenerative` is for.
;;
;; The gate for this is the -Dgc-stress=true leg, where these three failed
;; pre-fix and the 200-iteration loop below is not even needed. A *default*
;; build reaches the same corruption with ordinary allocation, but only once
;; it crosses the GC threshold — the issue's own repro needs 300,000
;; iterations, which stressed would be quadratic and take the whole job's
;; budget. So the loop is sized for the stressed leg, not the plain one.
(define uid-rtd-before (make-record-type-descriptor 'churned #f 'churn-uid #f #f #((immutable v))))
(let loop ((i 0)) (when (< i 200) (list i i i) (loop (+ i 1))))
(test-eq "nongenerative uid survives allocation between definitions"
  uid-rtd-before
  (make-record-type-descriptor 'churned #f 'churn-uid #f #f #((immutable v))))
(test-eq "nongenerative uid still resolves after allocation"
  uid-rtd-before
  (record-uid->rtd 'churn-uid))
;; The control: a dangling key can collide as easily as it can miss, so
;; "found" alone is not the property being pinned.
(test-assert "a different uid is still a different rtd after the churn"
  (not (eq? uid-rtd-before
            (make-record-type-descriptor 'churned #f 'other-churn-uid #f #f #((immutable v))))))

;;; --- error paths --------------------------------------------------------

(test-assert "record-accessor on an unknown field name raises"
  (raises? (lambda () (record-accessor proc-point-rtd 'no-such-field))))
(test-assert "record-ref-style accessor rejects a value of the wrong type"
  (raises? (lambda () (proc-point-x "not a point"))))
(test-assert "an accessor built for one type rejects an unrelated record instance"
  (raises? (lambda () (proc-animal-name (proc-make-box 1)))))

;;; --- R6RS conformance regressions (kaappi#1974) -------------------------
;;;
;;; Four independent deviations from R6RS 6.3, each of which had a control
;;; in the pre-fix implementation showing the data needed was already there.

;; P(a b) <- C(c d): an instance whose four fields are 1 2 3 4, so every
;; index confusion below produces a distinguishable wrong answer.
(define k-P (make-record-type-descriptor 'k-P #f #f #f #f '#((immutable a) (mutable b))))
(define k-C (make-record-type-descriptor 'k-C k-P #f #f #f '#((immutable c) (mutable d))))
(define k-inst ((record-constructor (make-record-descriptor k-C (make-record-descriptor k-P #f #f) #f))
                1 2 3 4))

;; 1. R6RS: "Returns a vector of symbols naming the fields..."
(test-assert "1: record-type-field-names returns a vector"
  (vector? (record-type-field-names k-C)))
(test-equal "1: record-type-field-names holds this type's OWN fields only"
  '#(c d) (record-type-field-names k-C))
(test-equal "1: record-type-field-names is vector-length-able"
  2 (vector-length (record-type-field-names k-C)))
(test-equal "1: record-type-field-names of a parent is unaffected"
  '#(a b) (record-type-field-names k-P))

;; 2. R6RS: "Note that k cannot be used to specify a field of any type rtd
;;    extends." Absolute indexing returned the parent's fields instead.
(test-equal "2: integer k is own-field-relative, not absolute (k=0)"
  3 ((record-accessor k-C 0) k-inst))
(test-equal "2: integer k is own-field-relative, not absolute (k=1)"
  4 ((record-accessor k-C 1) k-inst))
(test-equal "2: integer k agrees with the same field looked up by name"
  ((record-accessor k-C 'c) k-inst) ((record-accessor k-C 0) k-inst))
(test-equal "2: an ancestor's own k still reads the ancestor's field"
  1 ((record-accessor k-P 0) k-inst))
(test-equal "2: record-field-mutable? and record-accessor agree on k's meaning"
  #f (record-field-mutable? k-C 0))
(test-assert "2: record-mutator's k is own-relative too"
  (let ((m (record-mutator k-C 1)))
    (m k-inst 'written)
    (eq? 'written ((record-accessor k-C 1) k-inst))))
(test-assert "2: the integer path validates the rtd (it used to skip it)"
  (raises? (lambda () (record-accessor 5 0))))
(test-assert "2: record-mutator's integer path validates the rtd too"
  (raises? (lambda () (record-mutator 5 0))))
(test-assert "2: record-predicate validates the rtd eagerly"
  (raises? (lambda () (record-predicate 5))))
(test-assert "2: k must be a valid field index (too large)"
  (raises? (lambda () (record-accessor k-C 99))))
(test-assert "2: k must be a valid field index (negative)"
  (raises? (lambda () (record-accessor k-C -1))))
(test-assert "2: a type with no own fields has no valid k at all"
  (raises? (lambda ()
             (record-accessor (make-record-type-descriptor 'k-empty k-P #f #f #f '#()) 0))))

;; 3. R6RS: opaque means record? answers #f, record-rtd raises, and "the
;;    record type is also opaque if an opaque parent is supplied".
(define k-O (make-record-type-descriptor 'k-O #f #f #f #t '#((immutable v))))
(define k-O-inst ((record-constructor (make-record-descriptor k-O #f #f)) 7))
(define k-OC (make-record-type-descriptor 'k-OC k-O #f #f #f '#((immutable w))))
(test-assert "3: record-type-opaque? still reads the flag back" (record-type-opaque? k-O))
(test-equal "3: record? is #f for an instance of an opaque type" #f (record? k-O-inst))
(test-assert "3: record-rtd raises for an instance of an opaque type"
  (raises? (lambda () (record-rtd k-O-inst))))
(test-assert "3: opacity is inherited from an opaque parent" (record-type-opaque? k-OC))
(test-equal "3: record? is #f for an instance of a type with an opaque parent"
  #f (record? ((record-constructor
                 (make-record-descriptor k-OC (make-record-descriptor k-O #f #f) #f)) 7 8)))
(test-assert "3: a non-opaque type is still a record" (record? k-inst))
(test-assert "3: the type's own predicate still sees an opaque instance"
  ((record-predicate k-O) k-O-inst))
;; opacity through the syntactic layer, and inherited across it
(define-record-type k-opaque-syn (fields (immutable v k-opaque-syn-v)) (opaque #t))
(define-record-type (k-opaque-kid make-k-opaque-kid k-opaque-kid?)
  (parent k-opaque-syn) (fields (immutable w k-opaque-kid-w)))
(test-equal "3: syntactic (opaque #t) hides the instance from record?"
  #f (record? (make-k-opaque-syn 1)))
(test-assert "3: syntactic child of an opaque parent is opaque"
  (record-type-opaque? k-opaque-kid))
(test-equal "3: syntactic child of an opaque parent is hidden from record?"
  #f (record? (make-k-opaque-kid 1 2)))
(test-equal "3: an opaque type's own accessors keep working"
  1 (k-opaque-syn-v (make-k-opaque-syn 1)))

;; 4. R6RS: "If k specifies an immutable field, an exception with condition
;;    type &assertion is raised."
(test-equal "4: record-field-mutable? reports the immutable field" #f (record-field-mutable? k-C 0))
(test-assert "4: record-mutator refuses an immutable field by index"
  (raises? (lambda () (record-mutator k-C 0))))
(test-assert "4: record-mutator refuses an immutable field by name"
  (raises? (lambda () (record-mutator k-C 'c))))
(test-assert "4: record-mutator refuses an immutable field inherited from a parent"
  (raises? (lambda () (record-mutator k-C 'a))))
(test-assert "4: record-mutator still accepts a mutable field"
  (procedure? (record-mutator k-C 'd)))
(test-assert "4: record-mutator accepts a mutable field inherited from a parent"
  (procedure? (record-mutator k-C 'b)))
(test-equal "4: the immutable field was left alone" 3 ((record-accessor k-C 'c) k-inst))
(test-equal "4: record-field-mutable? accepts a field name too"
  #t (record-field-mutable? k-C 'd))
(test-equal "4: record-field-mutable? by name resolves into the parent"
  #f (record-field-mutable? k-C 'a))

;;; --- names the SRFI specifies that were missing (kaappi#1974) -----------

(test-assert "make-record-constructor-descriptor is bound (deprecated R6RS name)"
  (record-descriptor? (make-record-constructor-descriptor k-P #f #f)))
(test-assert "record-constructor-descriptor? is bound (deprecated R6RS name)"
  (record-constructor-descriptor? (make-record-descriptor k-P #f #f)))
(test-assert "record-constructor-descriptor? rejects a non-descriptor"
  (not (record-constructor-descriptor? 5)))

;; 7-argument make-record-descriptor: specified as exactly
;; (make-record-descriptor (make-record-type-descriptor name parent uid
;; sealed? opaque? fields) parent protocol).
(define k-7 (make-record-descriptor 'k-7 k-P #f #f #f '#((immutable e)) #f))
(test-assert "7-arg make-record-descriptor returns a record descriptor" (record-descriptor? k-7))
(test-equal "7-arg make-record-descriptor names the type" 'k-7 (record-type-name k-7))
(test-eq "7-arg make-record-descriptor wires up the parent" k-P (record-type-parent k-7))
(let ((inst ((record-constructor k-7) 10 20 30)))
  (test-equal "7-arg: inherited field via the parent's own accessor" 10 ((record-accessor k-P 0) inst))
  (test-equal "7-arg: own field via own-relative index 0" 30 ((record-accessor k-7 0) inst)))

;;; --- a record descriptor is a SUBTYPE of record-type descriptor ---------
;;;
;;; "Whenever a syntax or procedure described below expects a record-type
;;; descriptor, the result is equivalent to when the record-type descriptor
;;; is replaced by its underlying simple record-type descriptor."

(define k-rd (make-record-descriptor k-P #f #f))
(test-assert "rd: record-type-descriptor? accepts a record descriptor"
  (record-type-descriptor? k-rd))
(test-assert "rd: record-descriptor? still rejects a simple rtd"
  (not (record-descriptor? k-P)))
(test-equal "rd: record-type-name accepts a record descriptor" 'k-P (record-type-name k-rd))
(test-equal "rd: record-type-field-names accepts a record descriptor"
  '#(a b) (record-type-field-names k-rd))
(test-equal "rd: record-accessor accepts a record descriptor" 1 ((record-accessor k-rd 0) k-inst))
(test-assert "rd: record-predicate accepts a record descriptor" ((record-predicate k-rd) k-inst))
(test-equal "rd: make-record-type-descriptor accepts a record descriptor as parent"
  'k-P (record-type-name (record-type-parent
                           (make-record-type-descriptor 'k-sub k-rd #f #f #f '#((immutable z))))))
(test-eq "rd: record-descriptor-rtd of a simple rtd is that rtd itself" k-P (record-descriptor-rtd k-P))

;;; --- the SRFI's own worked Examples section ----------------------------
;;;
;;; Verbatim from the spec, minus its final `rec3` (a `(parent <expr>)`
;;; clause naming a non-record-name expression, a documented gap -- see the
;;; header of lib/srfi/237.sld). This is the cross-layer case that matters:
;;; the procedural type inherits from a SYNTACTIC one whose construction is
;;; governed by a protocol, so the parent's protocol has to run.

(define-record-type rec1
  (fields a)
  (protocol (lambda (p) (lambda (a/2) (p (* 2 a/2))))))

(define rec2
  (make-record-descriptor 'rec2
    rec1 #f #f #f
    '#((immutable b))
    (lambda (n) (lambda (a/2 b) ((n a/2) b)))))
(define make-rec2 (record-constructor rec2))
(define rec2? (record-predicate rec2))
(define rec2-b (record-accessor rec2 0))

(let ((r (make-rec2 5 7)))
  (test-assert "SRFI example: rec2's own predicate" (rec2? r))
  (test-assert "SRFI example: the syntactic parent's predicate sees it" (rec1? r))
  (test-equal "SRFI example: the syntactic parent's PROTOCOL ran (5 doubled)" 10 (rec1-a r))
  (test-equal "SRFI example: rec2's own field via own-relative index 0" 7 (rec2-b r)))
(test-assert "SRFI example: a bare parent instance is not a rec2" (not (rec2? (make-rec1 1))))

;; record-constructor on a record name: the type's own exposed constructor,
;; protocol and all.
(test-equal "record-constructor of a record name applies that type's protocol"
  10 (rec1-a ((record-constructor rec1) 5)))
(define-record-type k-plain (fields (immutable q k-plain-q)))
(test-equal "record-constructor of a protocol-less record name works too"
  4 (k-plain-q ((record-constructor k-plain) 4)))

(let ((runner (test-runner-current)))
  (test-end "srfi-237")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
