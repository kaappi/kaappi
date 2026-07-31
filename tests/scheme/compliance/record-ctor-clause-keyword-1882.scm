;; #1882: R6RS clause-syntax detection must not capture a valid R7RS-small
;; record whose constructor happens to be named after a clause keyword.
;;
;; SRFI 237's R6RS `define-record-type` grammar is ambient -- `(scheme base)`
;; accepts it with no `(import (srfi 237))` -- so the two syntaxes have to be
;; told apart structurally. The discriminator used to read only the head of
;; the form's 2nd element, which in R7RS syntax is the *constructor's* name;
;; a record whose constructor was called `fields` or `parent` was therefore
;; parsed as R6RS and rejected with a bare KP2001, in a program that never
;; mentions SRFI 237 at all.
;;
;; The 3rd element is what actually separates the two grammars: R7RS always
;; has one and it is always the bare-symbol `<predicate>`, while an R6RS
;; `<record clause>` is always a list -- or absent, when there is at most one
;; clause. So the tests below come in two halves: R7RS forms that must no
;; longer be captured, and R6RS forms that must still be detected.

(import (scheme base) (scheme process-context) (srfi 64) (lib1882 rec))

(test-begin "record-ctor-clause-keyword-1882")

;; --- R7RS: a clause keyword is an ordinary constructor name ---

(define-record-type point (fields x y) point? (x point-x) (y point-y))
(test-equal "ctor named `fields` constructs" 1 (point-x (fields 1 2)))
(test-equal "ctor named `fields`, second field" 2 (point-y (fields 1 2)))
(test-equal "ctor named `fields` satisfies its predicate" #t (point? (fields 1 2)))

(define-record-type node (parent l r) node? (l node-l) (r node-r))
(test-equal "ctor named `parent` constructs" 'a (node-l (parent 'a 'b)))
(test-equal "ctor named `parent` satisfies its predicate" #t (node? (parent 'a 'b)))
(test-equal "the two remain distinct record types" #f (point? (parent 'a 'b)))

;; A mutable field, so the misdetection can't hide behind the read-only path.
(define-record-type cell (sealed v) cell? (v cell-v set-cell-v!))
(test-equal "ctor named `sealed` constructs" 7 (cell-v (sealed 7)))
(let ((c (sealed 7)))
  (set-cell-v! c 8)
  (test-equal "mutator on a `sealed`-constructed record" 8 (cell-v c)))

;; The remaining keywords are unlikely constructor names, but they are here
;; so that a future edit to the keyword list can't quietly re-capture one.
(define-record-type r-protocol (protocol v) r-protocol? (v r-protocol-v))
(define-record-type r-opaque (opaque v) r-opaque? (v r-opaque-v))
(define-record-type r-nongen (nongenerative v) r-nongen? (v r-nongen-v))
(define-record-type r-gen (generative v) r-gen? (v r-gen-v))
(define-record-type r-prtd (parent-rtd v) r-prtd? (v r-prtd-v))
(test-equal "remaining clause keywords work as constructor names"
  '(1 2 3 4 5)
  (list (r-protocol-v (protocol 1))
        (r-opaque-v (opaque 2))
        (r-nongen-v (nongenerative 3))
        (r-gen-v (generative 4))
        (r-prtd-v (parent-rtd 5))))

;; --- R7RS: the same name in a body, and in a library body ---

;; A body's record form is scanned by the compiler's internal-define pass,
;; not the top-level handler. A misdetection there aborted the whole scan,
;; so the *siblings* defined after the record lost their forward
;; declarations too -- `ev?` below could not see `od?`.
(define (body-scan-check n)
  (define-record-type bp (fields a) bp? (a bp-a))
  (define (ev? k) (if (= k 0) #t (od? (- k 1))))
  (define (od? k) (if (= k 0) #f (ev? (- k 1))))
  (list (bp-a (fields 9)) (ev? n)))
(test-equal "a body keeps its sibling defines visible" '(9 #t) (body-scan-check 4))

;; A library body rejects R6RS clause syntax outright (top-level-only
;; feature), so a misdetection failed the entire library load -- see
;; lib1882/rec.sld.
(let ((p (make-lib-point 3 4)))
  (test-equal "library-body record with a `fields` constructor" 3 (lib-point-x p))
  (test-equal "library-body record, second field" 4 (lib-point-y p))
  (test-equal "library-body record predicate" #t (lib-point? p)))

;; --- R6RS: clause syntax is still detected, still without importing it ---

;; One clause, so there is no 3rd element at all.
(define-record-type box (fields (mutable contents)))
(test-equal "R6RS single-clause form" 42 (box-contents (make-box 42)))

;; Two clauses: the 3rd element is `(fields ...)`, a list, so still R6RS.
(define-record-type animal (fields (immutable name animal-name)))
(define-record-type (dog make-dog dog?)
  (parent animal)
  (fields (immutable breed dog-breed)))
(define rex (make-dog "rex" "lab"))
(test-equal "R6RS inheritance: parent field" "rex" (animal-name rex))
(test-equal "R6RS inheritance: own field" "lab" (dog-breed rex))
(test-equal "R6RS inheritance: parent predicate" #t (animal? rex))

;; Three clauses, none of them `fields` in 3rd position.
(define-record-type sealed-thing
  (fields (immutable v sealed-thing-v))
  (sealed #t)
  (opaque #t))
(test-equal "R6RS multi-clause form" 5 (sealed-thing-v (make-sealed-thing 5)))

(let ((runner (test-runner-current)))
  (test-end "record-ctor-clause-keyword-1882")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
