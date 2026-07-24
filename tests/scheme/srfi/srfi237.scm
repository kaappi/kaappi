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
(test-equal "procedural: record-type-field-names (own fields, in order)" '(x y) (record-type-field-names proc-point-rtd))
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
  (test-equal "procedural: record-accessor by absolute index" 7 (proc-point-y pp))
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

;;; --- error paths --------------------------------------------------------

(test-assert "record-accessor on an unknown field name raises"
  (raises? (lambda () (record-accessor proc-point-rtd 'no-such-field))))
(test-assert "record-ref-style accessor rejects a value of the wrong type"
  (raises? (lambda () (proc-point-x "not a point"))))
(test-assert "an accessor built for one type rejects an unrelated record instance"
  (raises? (lambda () (proc-animal-name (proc-make-box 1)))))

(let ((runner (test-runner-current)))
  (test-end "srfi-237")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
