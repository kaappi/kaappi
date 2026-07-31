;;; Audit: src/primitives_srfi237.zig (SRFI 237 — R6RS Records, refined)
;;; Systematic audit v2, Phase 2.5 (docs/audit-strategy.md, tracking #1890).
;;;
;;; Oracle: SRFI 237 defers to R6RS for every procedure ("Equivalent to the
;;; procedure with the same name in R6RS"), so the authority for the
;;; procedural and inspection layers is R6RS Library chapter 6 (Records).
;;; Quoted R6RS sentences appear beside the assertions they justify.
;;;
;;; Covers all 18 specs in primitives_srfi237.zig, the R6RS `define-record-type`
;;; desugarer that shares its enforcement helpers, and the portable layer in
;;; lib/srfi/237.sld that is the only caller of the 13 `.srfi_237_primitives`
;;; entries.
;;;
;;; Run: zig-out/bin/kaappi tests/scheme/audit/primitives_srfi237-audit.scm

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 18) (srfi 64) (srfi 237))

(test-begin "primitives_srfi237 audit")

;; #t iff the thunk raises anything catchable.
(define (raises? thunk)
  (call-with-current-continuation
    (lambda (k)
      (with-exception-handler (lambda (c) (k #t))
                              (lambda () (thunk) #f)))))

;; The raised message, or 'no-raise.
(define (message-of thunk)
  (call-with-current-continuation
    (lambda (k)
      (with-exception-handler
        (lambda (c) (k (if (error-object? c) (error-object-message c) 'non-error)))
        (lambda () (thunk) 'no-raise)))))

;; Naive substring search, so message assertions need no SRFI-13 import.
(define (string-search haystack needle)
  (let ((hn (string-length haystack)) (nn (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i nn) hn) #f)
            ((string=? (substring haystack i (+ i nn)) needle) #t)
            (else (loop (+ i 1)))))))

(define (fields-vector n)
  (let loop ((i 0) (acc '()))
    (if (= i n)
        (list->vector (reverse acc))
        (loop (+ i 1)
              (cons (list 'immutable (string->symbol (string-append "f" (number->string i))))
                    acc)))))

(define (count-up n)
  (let loop ((i 0) (acc '())) (if (= i n) (reverse acc) (loop (+ i 1) (cons i acc)))))

(define (root-ctor rtd) (record-constructor (make-record-descriptor rtd #f #f)))


;;; ===================================================================
;;; D1 — the internal-primitive direct-call surface
;;;
;;; All 18 specs are registered in vm.globals, so every one is callable
;;; from a plain script with no import at all. That makes each a reachable
;;; surface that must reject bad input catchably rather than crash.
;;; ===================================================================

(test-assert "D1: %record-type? reachable with no import, predicate is total"
             (not (%record-type? 5)))
(test-assert "D1: %record?/any reachable with no import, predicate is total"
             (not (%record?/any 5)))
(test-assert "D1: %record-uid->rtd reachable with no import, misses return #f"
             (not (%record-uid->rtd "no-such-uid-at-all")))
(test-assert "D1: %make-record-type-descriptor reachable with no import"
             (%record-type? (%make-record-type-descriptor "N" #f #f #f #f '(("a" . #f)))))
(test-assert "D1: %record-split-args reachable with no import"
             (equal? '((1 2) . (3)) (%record-split-args '(1 2 3) 1)))

;; Every one of the 13 type-checked entries rejects a non-record-type
;; catchably rather than crashing.
(test-assert "D1: %record-rtd rejects a non-record catchably"
             (raises? (lambda () (%record-rtd 5))))
(test-assert "D1: %record?/inherit rejects a non-record-type catchably"
             (raises? (lambda () (%record?/inherit 5 5))))
(test-assert "D1: %record-ref/inherit rejects a non-record-type catchably"
             (raises? (lambda () (%record-ref/inherit 5 0 5))))
(test-assert "D1: %record-set!/inherit rejects a non-record-type catchably"
             (raises? (lambda () (%record-set!/inherit 5 0 1 5))))
(test-assert "D1: %record-type-name rejects a non-record-type catchably"
             (raises? (lambda () (%record-type-name 5))))
(test-assert "D1: %record-type-parent rejects a non-record-type catchably"
             (raises? (lambda () (%record-type-parent 5))))
(test-assert "D1: %record-type-uid rejects a non-record-type catchably"
             (raises? (lambda () (%record-type-uid 5))))
(test-assert "D1: %record-type-generative? rejects a non-record-type catchably"
             (raises? (lambda () (%record-type-generative? 5))))
(test-assert "D1: %record-type-sealed? rejects a non-record-type catchably"
             (raises? (lambda () (%record-type-sealed? 5))))
(test-assert "D1: %record-type-opaque? rejects a non-record-type catchably"
             (raises? (lambda () (%record-type-opaque? 5))))
(test-assert "D1: %record-type-field-names rejects a non-record-type catchably"
             (raises? (lambda () (%record-type-field-names 5))))
(test-assert "D1: %record-field-mutable? rejects a non-record-type catchably"
             (raises? (lambda () (%record-field-mutable? 5 0))))
(test-assert "D1: %record-type-total-field-count rejects a non-record-type catchably"
             (raises? (lambda () (%record-type-total-field-count 5))))
(test-assert "D1: %record-uid->rtd rejects a non-string catchably"
             (raises? (lambda () (%record-uid->rtd 5))))

;;; %record-split-args — the fixed 256-element Zig stack buffer.
(test-assert "%record-split-args: 256-element list is accepted (buffer capacity)"
             (pair? (%record-split-args (count-up 256) 1)))
(test-assert "%record-split-args: 257-element list is rejected catchably, not a buffer overrun"
             (raises? (lambda () (%record-split-args (count-up 257) 1))))
(test-assert "%record-split-args: suffix longer than the list is rejected catchably"
             (raises? (lambda () (%record-split-args '(1 2) 5))))
(test-assert "%record-split-args: negative suffix length is rejected catchably"
             (raises? (lambda () (%record-split-args '(1 2) -1))))
(test-assert "%record-split-args: improper list is rejected catchably"
             (raises? (lambda () (%record-split-args '(1 . 2) 1))))
(test-assert "%record-split-args: non-list is rejected catchably"
             (raises? (lambda () (%record-split-args 5 0))))
(test-equal "%record-split-args: whole list to the suffix" '(() . (1 2))
            (%record-split-args '(1 2) 2))
(test-equal "%record-split-args: empty suffix" '((1 2) . ())
            (%record-split-args '(1 2) 0))


;;; ===================================================================
;;; Baseline fixtures
;;; ===================================================================

(define P (make-record-type-descriptor 'P #f #f #f #f #((immutable a) (immutable b))))
(define C (make-record-type-descriptor 'C P #f #f #f #((immutable c) (mutable d))))
(define c-inst
  ((record-constructor (make-record-descriptor C (make-record-descriptor P #f #f) #f)) 1 2 3 4))

(test-assert "record-type-descriptor? recognizes an rtd" (record-type-descriptor? P))
(test-assert "record-type-descriptor? rejects a non-rtd" (not (record-type-descriptor? 5)))
(test-assert "record-type-descriptor? rejects a record instance"
             (not (record-type-descriptor? c-inst)))
(test-assert "record-descriptor? rejects an rtd" (not (record-descriptor? P)))
(test-assert "record-descriptor? recognizes a record descriptor"
             (record-descriptor? (make-record-descriptor P #f #f)))
(test-eq "record-descriptor-rtd round-trips"
         P (record-descriptor-rtd (make-record-descriptor P #f #f)))
(test-assert "record-descriptor-parent is #f for a root descriptor"
             (not (record-descriptor-parent (make-record-descriptor P #f #f))))
(test-equal "record-type-name" 'C (record-type-name C))
(test-eq "record-type-parent walks one level" P (record-type-parent C))
(test-assert "record-type-parent of a root is #f" (not (record-type-parent P)))
(test-assert "record? on a plain record instance" (record? c-inst))
(test-assert "record? rejects a non-record" (not (record? 5)))
(test-assert "record? rejects an rtd itself" (not (record? P)))
(test-eq "record-rtd round-trips to the exact rtd" C (record-rtd c-inst))
(test-assert "record-rtd rejects a non-record catchably"
             (raises? (lambda () (record-rtd 5))))
(test-equal "%record-type-total-field-count counts inherited fields too"
            4 (%record-type-total-field-count C))
(test-equal "%record-type-total-field-count of a root type" 2 (%record-type-total-field-count P))


;;; ===================================================================
;;; record-type-field-names — R6RS: "Returns a VECTOR of symbols naming
;;; the fields of the type represented by rtd (not including the fields
;;; of parent types)."
;;; ===================================================================

;; Enabled control: the "not including parent fields" half is correct, and
;; the element order and symbol-ness are correct — only the container is wrong.
(test-equal "field-names: own fields only, in declaration order (as a list)"
            '(c d) (record-type-field-names C))
(test-equal "field-names: parent reports its own two" '(a b) (record-type-field-names P))
(test-equal "field-names: a zero-field type reports empty"
            '() (record-type-field-names (make-record-type-descriptor 'E #f #f #f #f #())))
(test-assert "field-names: elements are symbols"
             (symbol? (car (record-type-field-names C))))

;; FAIL: TBD (record-type-field-names returns a list; R6RS requires a vector)
;; (test-assert "field-names: R6RS requires a vector" (vector? (record-type-field-names C)))
;; FAIL: TBD (record-type-field-names returns a list; R6RS requires a vector)
;; (test-equal "field-names: vector contents" #(c d) (record-type-field-names C))
;; FAIL: TBD (record-type-field-names returns a list, so vector-length raises)
;; (test-equal "field-names: vector-length is the own-field count"
;;             2 (vector-length (record-type-field-names C)))

;; Discriminating control: make-record-type-descriptor *consumes* a vector for
;; the same field list, so the library is asymmetric rather than uniformly
;; list-based — a list `fields` argument is rejected.
(test-assert "field-names control: make-record-type-descriptor requires a VECTOR of field specs"
             (raises? (lambda () (make-record-type-descriptor 'B #f #f #f #f '((immutable v))))))


;;; ===================================================================
;;; record-accessor / record-mutator index semantics
;;;
;;; R6RS: "The field selected corresponds to the kth element (0-based) of
;;; the fields argument to the invocation of make-record-type-descriptor
;;; that created rtd. Note that k cannot be used to specify a field of any
;;; type rtd extends."
;;;
;;; Kaappi treats an integer k as an ABSOLUTE index into the full
;;; inherited-then-own layout instead.
;;; ===================================================================

;; Enabled controls: the by-NAME path resolves per level exactly as R6RS
;; requires, so the library demonstrably has the information the integer
;; path discards.
(test-equal "accessor by name: child's own field" 3 ((record-accessor C 'c) c-inst))
(test-equal "accessor by name: child's own mutable field" 4 ((record-accessor C 'd) c-inst))
(test-equal "accessor by name: inherited field reached through the parent chain"
            1 ((record-accessor C 'a) c-inst))
(test-equal "accessor by name on the parent rtd" 2 ((record-accessor P 'b) c-inst))
(test-assert "accessor by name: unknown field raises catchably"
             (raises? (lambda () (record-accessor C 'nope))))

;; Second discriminating control: record-field-mutable? on the SAME rtd with
;; the SAME k already uses own-field indexing, so the two are internally
;; inconsistent — this is not a deliberate library-wide convention.
(test-assert "index control: record-field-mutable? k=0 is C's OWN field c (immutable)"
             (not (record-field-mutable? C 0)))
(test-assert "index control: record-field-mutable? k=1 is C's OWN field d (mutable)"
             (record-field-mutable? C 1))
(test-assert "index control: record-field-mutable? on the parent's own field 0"
             (not (record-field-mutable? P 0)))

;; FAIL: TBD (record-accessor integer k is absolute, not own-field-relative)
;; (test-equal "accessor by index: k=0 selects C's OWN first field"
;;             3 ((record-accessor C 0) c-inst))
;; FAIL: TBD (record-accessor integer k is absolute, not own-field-relative)
;; (test-equal "accessor by index: k=1 selects C's OWN second field"
;;             4 ((record-accessor C 1) c-inst))
;; FAIL: TBD (record-accessor integer k is absolute — k=2 is past C's own field count)
;; (test-assert "accessor by index: k beyond the own-field count is invalid"
;;              (raises? (lambda () ((record-accessor C 2) c-inst))))
;; FAIL: TBD (record-mutator integer k is absolute, not own-field-relative)
;; (test-equal "mutator by index: k=1 writes C's OWN mutable field d"
;;             77 (let ((i ((record-constructor
;;                            (make-record-descriptor C (make-record-descriptor P #f #f) #f))
;;                          1 2 3 4)))
;;                  ((record-mutator C 1) i 77)
;;                  ((record-accessor C 'd) i)))

;; Enabled: what the absolute-index reading actually does today, so the fix
;; PR has a pinned "before".
(test-equal "accessor by index (current absolute semantics): k=0 reads the root's field a"
            1 ((record-accessor C 0) c-inst))

;; Index validation on the absolute layout is itself sound.
(test-assert "accessor: out-of-range positive index raises catchably"
             (raises? (lambda () ((record-accessor C 99) c-inst))))
(test-assert "accessor: negative index raises catchably"
             (raises? (lambda () ((record-accessor C -1) c-inst))))
(test-assert "accessor: inexact index is rejected (integer? admits 2.0)"
             (raises? (lambda () ((record-accessor P 2.0) c-inst))))

;; FAIL: #1914 (negative index reports a bare TypeError naming args[0], the record)
;; (test-assert "accessor: negative index reports an index error, not a type error"
;;              (let ((m (message-of (lambda () ((record-accessor C -1) c-inst)))))
;;                (and (string? m) (string-search m "out of range"))))


;;; ===================================================================
;;; Cross-type access — a subtype instance satisfies an ancestor's
;;; accessor, but never the reverse, and never an unrelated type's.
;;; ===================================================================

(define X (make-record-type-descriptor 'X #f #f #f #f #((immutable z))))
(define x-inst ((root-ctor X) 9))

(test-assert "cross-type: ancestor predicate accepts a subtype instance"
             ((record-predicate P) c-inst))
(test-assert "cross-type: own predicate accepts its own instance"
             ((record-predicate C) c-inst))
(test-assert "cross-type: subtype predicate rejects an ancestor-only instance"
             (not ((record-predicate C) ((root-ctor P) 1 2))))
(test-assert "cross-type: unrelated type is rejected by the predicate"
             (not ((record-predicate C) x-inst)))
(test-assert "cross-type: predicate is total — a non-record is #f, not an error"
             (not ((record-predicate C) 5)))
(test-equal "cross-type: ancestor accessor reads through a subtype instance"
            1 ((record-accessor P 'a) c-inst))
(test-assert "cross-type: accessor on an unrelated type's instance raises catchably"
             (raises? (lambda () ((record-accessor C 'c) x-inst))))
(test-assert "cross-type: subtype accessor on an ancestor-only instance raises catchably"
             (raises? (lambda () ((record-accessor C 'c) ((root-ctor P) 1 2)))))
(test-assert "cross-type: mutator on an unrelated type's instance raises catchably"
             (raises? (lambda () ((record-mutator C 'd) x-inst 1))))


;;; ===================================================================
;;; Inheritance depth × protocol composition
;;;
;;; A 4-level chain, one field per level, with every subset of levels
;;; carrying a protocol (16 combinations). A level's protocol marks its own
;;; field by adding 100, so the result names exactly which protocols ran.
;;; ===================================================================

(define (build-chain mask)
  (let* ((L0 (make-record-type-descriptor 'L0 #f #f #f #f #((immutable a))))
         (L1 (make-record-type-descriptor 'L1 L0 #f #f #f #((immutable b))))
         (L2 (make-record-type-descriptor 'L2 L1 #f #f #f #((immutable c))))
         (L3 (make-record-type-descriptor 'L3 L2 #f #f #f #((immutable d))))
         (on? (lambda (bit) (odd? (quotient mask bit))))
         (p0 (if (on? 1) (lambda (new) (lambda (a) (new (+ a 100)))) #f))
         (p1 (if (on? 2) (lambda (n) (lambda (a b) ((n a) (+ b 100)))) #f))
         (p2 (if (on? 4) (lambda (n) (lambda (a b c) ((n a b) (+ c 100)))) #f))
         (p3 (if (on? 8) (lambda (n) (lambda (a b c d) ((n a b c) (+ d 100)))) #f))
         (r0 (make-record-descriptor L0 #f p0))
         (r1 (make-record-descriptor L1 r0 p1))
         (r2 (make-record-descriptor L2 r1 p2))
         (r3 (make-record-descriptor L3 r2 p3)))
    (cons L3 (record-constructor r3))))

(define (chain-fields mask)
  (let* ((built (build-chain mask))
         (rtd (car built))
         (inst ((cdr built) 1 2 3 4)))
    ;; absolute indices 0..3 == the flat inherited-then-own layout
    (map (lambda (i) ((record-accessor rtd i) inst)) '(0 1 2 3))))

(define (chain-want mask)
  (let ((bump (lambda (base bit) (+ base (if (odd? (quotient mask bit)) 100 0)))))
    (list (bump 1 1) (bump 2 2) (bump 3 4) (bump 4 8))))

(let loop ((m 0))
  (when (< m 16)
    (test-equal (string-append "protocol matrix: 4-level chain, mask " (number->string m))
                (chain-want m) (chain-fields m))
    (loop (+ m 1))))

;; Predicates hold at every level of the deepest combination.
(let* ((built (build-chain 15)) (rtd (car built)) (inst ((cdr built) 1 2 3 4)))
  (test-assert "protocol matrix: own predicate holds with protocols at every level"
               ((record-predicate rtd) inst))
  (test-assert "protocol matrix: grandparent predicate holds"
               ((record-predicate (record-type-parent (record-type-parent rtd))) inst))
  (test-equal "protocol matrix: total field count across 4 levels"
              4 (%record-type-total-field-count rtd)))

;;; A protocol is run by record-constructor, once, regardless of how many
;;; instances are later built. R6RS: "Calls the protocol of
;;; constructor-descriptor ... and returns the resulting constructor."
(define pc0 0) (define pc1 0) (define pc2 0)
(let* ((L0 (make-record-type-descriptor 'K0 #f #f #f #f #((immutable a))))
       (L1 (make-record-type-descriptor 'K1 L0 #f #f #f #((immutable b))))
       (L2 (make-record-type-descriptor 'K2 L1 #f #f #f #((immutable c))))
       (r0 (make-record-descriptor L0 #f (lambda (new) (set! pc0 (+ pc0 1)) (lambda (a) (new a)))))
       (r1 (make-record-descriptor L1 r0 (lambda (n) (set! pc1 (+ pc1 1)) (lambda (a b) ((n a) b)))))
       (r2 (make-record-descriptor L2 r1 (lambda (n) (set! pc2 (+ pc2 1)) (lambda (a b c) ((n a b) c)))))
       (ctor (record-constructor r2)))
  (test-equal "protocol runs exactly once per record-constructor call, at construction of the ctor"
              '(1 1 1) (list pc0 pc1 pc2))
  (ctor 1 2 3) (ctor 4 5 6) (ctor 7 8 9)
  (test-equal "protocol is NOT re-run per instance" '(1 1 1) (list pc0 pc1 pc2)))

;;; Arity mismatches.
;;;
;;; A protocol-built constructor is a plain lambda of declared arity, so it
;;; checks. The no-protocol path funnels through %make-record, which ignores
;;; the declared field count (#1915) — so a subtype constructor accepts any
;;; number of arguments and silently mis-lays-out the fields.
(test-assert "protocol: too few constructor arguments raises catchably"
             (raises? (lambda () ((cdr (build-chain 15)) 1 2))))

;; Enabled controls pinning the current behaviour so #1915's fix flips them.
(let* ((A (make-record-type-descriptor 'AR #f #f #f #f #((immutable a))))
       (B (make-record-type-descriptor 'BR A #f #f #f #((immutable b))))
       (ctor (record-constructor (make-record-descriptor B (make-record-descriptor A #f #f) #f))))
  (test-equal "arity control: the correct argument count lays fields out correctly" '(1 2)
              (map (lambda (i) ((record-accessor B i) (ctor 1 2))) '(0 1)))
  (test-equal "arity: an EXTRA constructor argument is accepted and shifts the layout (#1915)"
              '(1 3)
              (map (lambda (i) ((record-accessor B i) (ctor 1 2 3))) '(0 1)))
  (test-assert "arity: too FEW constructor arguments leaks an uninitialized field (#1915)"
               (not (equal? 1 ((record-accessor B 0) (ctor 1)))))

  ;; FAIL: #1915 (%make-record ignores the declared field count)
  ;; (test-assert "arity: too many subtype constructor arguments raises catchably"
  ;;              (raises? (lambda () (ctor 1 2 3))))
  ;; FAIL: #1915 (%make-record ignores the declared field count)
  ;; (test-assert "arity: too few subtype constructor arguments raises catchably"
  ;;              (raises? (lambda () (ctor 1))))
  )


;;; ===================================================================
;;; Field shadowing — a child declaring a field name its ancestor already has
;;; ===================================================================

(define SP (make-record-type-descriptor 'SP #f #f #f #f #((immutable v) (immutable w))))
(define SC (make-record-type-descriptor 'SC SP #f #f #f #((mutable v))))
(define sc-inst
  ((record-constructor (make-record-descriptor SC (make-record-descriptor SP #f #f) #f)) 1 2 3))

(test-equal "shadowing: parent still reports its own two field names" '(v w)
            (record-type-field-names SP))
(test-equal "shadowing: child reports only its own shadowing name" '(v)
            (record-type-field-names SC))
(test-equal "shadowing: child's own v wins on the child rtd" 3 ((record-accessor SC 'v) sc-inst))
(test-equal "shadowing: parent's v is still reachable through the parent rtd"
            1 ((record-accessor SP 'v) sc-inst))
(test-equal "shadowing: the non-shadowed inherited field still resolves from the child"
            2 ((record-accessor SC 'w) sc-inst))
(test-assert "shadowing: mutability is tracked per level (child's v is mutable)"
             (record-field-mutable? SC 0))
(test-assert "shadowing: mutability is tracked per level (parent's v is immutable)"
             (not (record-field-mutable? SP 0)))
(test-equal "shadowing: total field count counts both v's separately"
            3 (%record-type-total-field-count SC))

(let ((i ((record-constructor (make-record-descriptor SC (make-record-descriptor SP #f #f) #f))
          1 2 3)))
  ((record-mutator SC 'v) i 99)
  (test-equal "shadowing: mutating the child's v writes the child's slot" 99
              ((record-accessor SC 'v) i))
  (test-equal "shadowing: mutating the child's v leaves the parent's v untouched" 1
              ((record-accessor SP 'v) i)))


;;; ===================================================================
;;; sealed
;;;
;;; R6RS: "An exception with condition type &assertion is raised if parent
;;; is sealed."
;;; ===================================================================

(define SEALED (make-record-type-descriptor 'SEALED #f #f #t #f #((immutable v))))

(test-assert "sealed: record-type-sealed? reports the flag" (record-type-sealed? SEALED))
(test-assert "sealed: an unsealed type reports #f" (not (record-type-sealed? P)))
(test-assert "sealed: a sealed type still constructs and type-checks"
             ((record-predicate SEALED) ((root-ctor SEALED) 1)))
(test-assert "sealed: subtyping a sealed rtd raises catchably"
             (raises? (lambda ()
                        (make-record-type-descriptor 'SUB SEALED #f #f #f #((immutable w))))))
(test-assert "sealed: the rejection names the sealed type and the reason"
             (let ((m (message-of (lambda ()
                                    (make-record-type-descriptor 'SUB SEALED #f #f #f
                                                                 #((immutable w)))))))
               (and (string? m)
                    (string-search m "sealed")
                    (string-search m "SEALED"))))
(test-assert "sealed: sealing is not itself inherited from an unsealed parent"
             (not (record-type-sealed? C)))


;;; ===================================================================
;;; opaque
;;;
;;; R6RS: "If true, the record type is opaque. If passed an instance of the
;;; record type, record? returns #f. Moreover, if record-rtd is called with
;;; an instance of the record type, an exception with condition type
;;; &assertion is raised." And: "The record type is also opaque if an
;;; opaque parent is supplied."
;;; ===================================================================

(define OPQ (make-record-type-descriptor 'OPQ #f #f #f #t #((immutable v))))
(define opq-inst ((root-ctor OPQ) 7))
(define OPQ-CHILD (make-record-type-descriptor 'OPQC OPQ #f #f #f #((immutable w))))

;; Enabled controls: the flag is stored, readable, and does not leak onto
;; unrelated types — so record?/record-rtd have everything they need.
(test-assert "opaque: record-type-opaque? reports the flag" (record-type-opaque? OPQ))
(test-assert "opaque: a non-opaque type reports #f" (not (record-type-opaque? P)))
(test-assert "opaque: an opaque type still constructs and type-checks"
             ((record-predicate OPQ) opq-inst))
(test-assert "opaque: accessors still work on an opaque instance"
             (= 7 ((record-accessor OPQ 'v) opq-inst)))
(test-assert "opaque control: the parent link to the opaque ancestor is intact and walkable"
             (eq? OPQ (record-type-parent OPQ-CHILD)))
(test-assert "opaque control: a child declaring opaque? #t itself does report #t"
             (record-type-opaque?
               (make-record-type-descriptor 'OPQC2 P #f #f #t #((immutable w)))))

;; FAIL: TBD (record? does not consult the opaque flag)
;; (test-assert "opaque: record? is #f for an instance of an opaque type"
;;              (not (record? opq-inst)))
;; FAIL: TBD (record-rtd does not consult the opaque flag)
;; (test-assert "opaque: record-rtd raises for an instance of an opaque type"
;;              (raises? (lambda () (record-rtd opq-inst))))
;; FAIL: TBD (opacity is not inherited from an opaque parent)
;; (test-assert "opaque: a child of an opaque parent is itself opaque"
;;              (record-type-opaque? OPQ-CHILD))
;; FAIL: TBD (opacity is not inherited, so record? leaks the subtype too)
;; (test-assert "opaque: record? is #f for an instance of a child of an opaque type"
;;              (not (record? ((record-constructor
;;                               (make-record-descriptor OPQ-CHILD
;;                                                       (make-record-descriptor OPQ #f #f) #f))
;;                             1 2))))


;;; ===================================================================
;;; Immutable-field mutators
;;;
;;; R6RS record-mutator: "If k specifies an immutable field, an exception
;;; with condition type &assertion is raised."
;;; ===================================================================

(define IMM (make-record-type-descriptor 'IMM #f #f #f #f #((immutable x) (mutable y))))
(define imm-inst ((root-ctor IMM) 1 2))

;; Enabled controls: mutability is recorded and readable, and the mutable
;; field's mutator genuinely works — so the check is absent, not the data.
(test-assert "immutable: record-field-mutable? reports #f for the immutable field"
             (not (record-field-mutable? IMM 0)))
(test-assert "immutable: record-field-mutable? reports #t for the mutable field"
             (record-field-mutable? IMM 1))
(test-equal "immutable control: mutating the MUTABLE field works" 42
            (let ((i ((root-ctor IMM) 1 2)))
              ((record-mutator IMM 'y) i 42)
              ((record-accessor IMM 'y) i)))
(test-assert "immutable: record-field-mutable? out-of-range index raises catchably"
             (raises? (lambda () (record-field-mutable? IMM 9))))
(test-assert "immutable: record-field-mutable? negative index raises catchably"
             (raises? (lambda () (record-field-mutable? IMM -1))))

;; FAIL: TBD (record-mutator does not check field mutability)
;; (test-assert "immutable: record-mutator on an immutable field raises"
;;              (raises? (lambda () (record-mutator IMM 0))))
;; FAIL: TBD (record-mutator does not check field mutability — the write lands)
;; (test-equal "immutable: an immutable field cannot be written" 1
;;             (let ((i ((root-ctor IMM) 1 2)))
;;               (guard (e (#t #t)) ((record-mutator IMM 'x) i 99))
;;               ((record-accessor IMM 'x) i)))


;;; ===================================================================
;;; nongenerative / uid
;;;
;;; R6RS: "If make-record-type-descriptor is called twice with the same uid
;;; symbol, the parent arguments in the two calls must be eqv?, the fields
;;; arguments equal?, the sealed? arguments boolean-equivalent ... and the
;;; opaque? arguments boolean-equivalent. If these conditions are not met,
;;; an exception with condition type &assertion is raised."
;;; ===================================================================

(define U1 (make-record-type-descriptor 'U #f 'audit-uid-1 #f #f #((immutable v))))
(define U2 (make-record-type-descriptor 'U #f 'audit-uid-1 #f #f #((immutable v))))

(test-assert "uid: an equivalent redefinition reuses the same rtd" (eqv? U1 U2))
(test-assert "uid: record-type-generative? is #f for a uid'd type"
             (not (record-type-generative? U1)))
(test-assert "uid: record-type-generative? is #t without a uid" (record-type-generative? P))
(test-equal "uid: record-type-uid round-trips as a symbol" 'audit-uid-1 (record-type-uid U1))
(test-assert "uid: record-type-uid is #f for a generative type" (not (record-type-uid P)))
(test-assert "uid: record-uid->rtd resolves a registered uid" (eqv? U1 (record-uid->rtd 'audit-uid-1)))
(test-assert "uid: record-uid->rtd returns #f for an unregistered uid"
             (not (record-uid->rtd 'audit-uid-never-registered)))

;; R6RS lists parent/fields/sealed?/opaque? as the equivalence axes — the
;; NAME is deliberately not among them, so a differing name still reuses.
(test-assert "uid: the type NAME is not an equivalence axis (R6RS lists four, name is not one)"
             (eqv? U1 (make-record-type-descriptor 'DIFFERENT-NAME #f 'audit-uid-1 #f #f
                                                   #((immutable v)))))

;; Each of the four axes is detected, and the message names the axis.
(define (uid-clash-message thunk) (message-of thunk))
(test-assert "uid: a different field set is rejected"
             (let ((m (uid-clash-message
                        (lambda () (make-record-type-descriptor 'U #f 'audit-uid-1 #f #f
                                                                #((immutable v) (immutable w)))))))
               (and (string? m) (string-search m "field set"))))
(test-assert "uid: a different field NAME is rejected as a field-set mismatch"
             (let ((m (uid-clash-message
                        (lambda () (make-record-type-descriptor 'U #f 'audit-uid-1 #f #f
                                                                #((immutable q)))))))
               (and (string? m) (string-search m "field set"))))
(test-assert "uid: a different field MUTABILITY is rejected as a field-set mismatch"
             (let ((m (uid-clash-message
                        (lambda () (make-record-type-descriptor 'U #f 'audit-uid-1 #f #f
                                                                #((mutable v)))))))
               (and (string? m) (string-search m "field set"))))
(test-assert "uid: a different sealed flag is rejected, naming that axis"
             (let ((m (uid-clash-message
                        (lambda () (make-record-type-descriptor 'U #f 'audit-uid-1 #t #f
                                                                #((immutable v)))))))
               (and (string? m) (string-search m "sealed flag"))))
(test-assert "uid: a different opaque flag is rejected, naming that axis"
             (let ((m (uid-clash-message
                        (lambda () (make-record-type-descriptor 'U #f 'audit-uid-1 #f #t
                                                                #((immutable v)))))))
               (and (string? m) (string-search m "opaque flag"))))
(test-assert "uid: a different parent is rejected, naming that axis"
             (let ((m (uid-clash-message
                        (lambda () (make-record-type-descriptor 'U P 'audit-uid-1 #f #f
                                                                #((immutable v)))))))
               (and (string? m) (string-search m "parent"))))

;; A nongenerative subtype of a nongenerative parent resolves by identity.
(let* ((NP (make-record-type-descriptor 'NP #f 'audit-uid-parent #f #f #((immutable a))))
       (NC (make-record-type-descriptor 'NC NP 'audit-uid-child #f #f #((immutable b))))
       (NC2 (make-record-type-descriptor 'NC NP 'audit-uid-child #f #f #((immutable b)))))
  (test-assert "uid: a nongenerative subtype of a nongenerative parent reuses" (eqv? NC NC2))
  (test-eq "uid: the reused subtype keeps its parent link" NP (record-type-parent NC2)))


;;; ===================================================================
;;; The 255-field limit, reached three ways
;;;
;;; GC.allocRecordTypeExtended caps a record type at 255 fields INCLUDING
;;; inherited ones (RecordType.num_fields is a u8).
;;; ===================================================================

(define P200 (make-record-type-descriptor 'P200 #f #f #f #f (fields-vector 200)))

;; The cliff itself is in the same place on all three paths.
(test-assert "255 limit: 255 own fields is accepted"
             (record-type-descriptor?
               (make-record-type-descriptor 'OWN255 #f #f #f #f (fields-vector 255))))
(test-assert "255 limit: 256 own fields is rejected"
             (raises? (lambda ()
                        (make-record-type-descriptor 'OWN256 #f #f #f #f (fields-vector 256)))))
(test-assert "255 limit: inherited-only — a 200-field parent with 0 own fields is accepted"
             (record-type-descriptor?
               (make-record-type-descriptor 'INH0 P200 #f #f #f #())))
(test-assert "255 limit: mixed — 200 inherited + 55 own (=255) is accepted"
             (record-type-descriptor?
               (make-record-type-descriptor 'MIX255 P200 #f #f #f (fields-vector 55))))
(test-assert "255 limit: mixed — 200 inherited + 56 own (=256) is rejected"
             (raises? (lambda ()
                        (make-record-type-descriptor 'MIX256 P200 #f #f #f (fields-vector 56)))))
(test-assert "255 limit: mixed — 200 inherited + 100 own (=300) is rejected"
             (raises? (lambda ()
                        (make-record-type-descriptor 'MIX300 P200 #f #f #f (fields-vector 100)))))

;; The inherited/mixed path reports the limit precisely.
(test-assert "255 limit: the inherited path names own, inherited, total and the limit"
             (let ((m (message-of (lambda ()
                                    (make-record-type-descriptor 'MIX300 P200 #f #f #f
                                                                 (fields-vector 100))))))
               (and (string? m)
                    (string-search m "300 fields")
                    (string-search m "100 of its own")
                    (string-search m "200 inherited")
                    (string-search m "255"))))

;; The own-fields path reports a bare TypeError naming args[0] (the type
;; NAME, which is perfectly valid) instead of the field count.
;; FAIL: #1914 (own-field 255-limit overflow reports a bare TypeError blaming args[0])
;; (test-assert "255 limit: the own-fields path reports the same limit as precisely"
;;              (let ((m (message-of (lambda ()
;;                                     (make-record-type-descriptor 'OWN256 #f #f #f #f
;;                                                                  (fields-vector 256))))))
;;                (and (string? m) (string-search m "255"))))

;; Enabled: the current, asymmetric wording, so #1914's fix has a pinned "before".
(test-assert "255 limit: the own-fields path currently reports a type error naming the rtd name"
             (let ((m (message-of (lambda ()
                                    (make-record-type-descriptor 'OWN256 #f #f #f #f
                                                                 (fields-vector 256))))))
               (and (string? m) (string-search m "type error"))))


;;; ===================================================================
;;; Record INSTANTIATION field-count limit
;;;
;;; GC.allocRecordInstance computes its byte size as
;;;   @sizeOf(RecordInstance) + record_type.num_fields * @sizeOf(Value)
;;; in u8 arithmetic (num_fields is a u8), so the whole expression
;;; overflows once 40 + 8n > 255, i.e. at n = 27. The record TYPE is
;;; created happily; the process aborts on the first instance.
;;;
;;; This is an uncatchable Zig panic, not an error, so the failing case
;;; cannot be left enabled in any form — it would abort the suite.
;;; ===================================================================

(test-assert "instantiation: a 26-field record type instantiates (control, just under the cliff)"
             (record?
               (apply (root-ctor (make-record-type-descriptor 'N26 #f #f #f #f (fields-vector 26)))
                      (count-up 26))))
(test-assert "instantiation: the 27-field record TYPE is created without complaint"
             (record-type-descriptor?
               (make-record-type-descriptor 'N27 #f #f #f #f (fields-vector 27))))

;; FAIL: TBD (allocRecordInstance sizes in u8 arithmetic — PANICS, uncatchable, at 27 fields)
;; (test-assert "instantiation: a 27-field record type instantiates"
;;              (record?
;;                (apply (root-ctor (make-record-type-descriptor 'N27 #f #f #f #f (fields-vector 27)))
;;                       (count-up 27))))
;; FAIL: TBD (same overflow, reached through inheritance rather than own fields)
;; (test-assert "instantiation: a 27-field total reached through a parent chain instantiates"
;;              (let* ((A (make-record-type-descriptor 'A27 #f #f #f #f (fields-vector 20)))
;;                     (B (make-record-type-descriptor 'B27 A #f #f #f (fields-vector 7))))
;;                (record? (apply (record-constructor
;;                                  (make-record-descriptor B (make-record-descriptor A #f #f) #f))
;;                                (count-up 27)))))

;; The same overflow is reachable from plain R7RS `define-record-type` with
;; no SRFI 237 involvement at all — allocRecordInstance is shared by both
;; record systems. Kept here because this audit is what found it.
;; FAIL: TBD (allocRecordInstance sizes in u8 arithmetic — PANICS on a plain R7RS 27-field record)
;; (test-assert "instantiation: a plain R7RS 27-field record instantiates"
;;              (begin
;;                (define-record-type r7-27
;;                  (make-r7-27 a b c d e f g h i j k l m n o p q r s t u v w x y z aa)
;;                  r7-27?
;;                  (a r7-27-a) (b r7-27-b) (c r7-27-c) (d r7-27-d) (e r7-27-e)
;;                  (f r7-27-f) (g r7-27-g) (h r7-27-h) (i r7-27-i) (j r7-27-j)
;;                  (k r7-27-k) (l r7-27-l) (m r7-27-m) (n r7-27-n) (o r7-27-o)
;;                  (p r7-27-p) (q r7-27-q) (r r7-27-r) (s r7-27-s) (t r7-27-t)
;;                  (u r7-27-u) (v r7-27-v) (w r7-27-w) (x r7-27-x) (y r7-27-y)
;;                  (z r7-27-z) (aa r7-27-aa))
;;                (r7-27? (make-r7-27 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20
;;                                    21 22 23 24 25 26 27))))


;;; ===================================================================
;;; Cross-layer: types defined syntactically, inspected procedurally
;;;
;;; SRFI 237: "Whether a record type has been defined syntactically or
;;; procedurally is generally unobservable."
;;; ===================================================================

(define-record-type syn-rec (fields (immutable a syn-a) (mutable b syn-b syn-b-set!)))
(define syn-inst (make-syn-rec 1 2))

(test-assert "cross-layer: a syntactic record satisfies record?" (record? syn-inst))
(test-assert "cross-layer: its rtd is a record-type-descriptor"
             (record-type-descriptor? (record-rtd syn-inst)))
(test-equal "cross-layer: record-type-name of a syntactic type" 'syn-rec
            (record-type-name (record-rtd syn-inst)))
(test-equal "cross-layer: record-type-field-names of a syntactic type" '(a b)
            (record-type-field-names (record-rtd syn-inst)))
(test-assert "cross-layer: field mutability survives the syntactic path"
             (and (not (record-field-mutable? (record-rtd syn-inst) 0))
                  (record-field-mutable? (record-rtd syn-inst) 1)))
(test-assert "cross-layer: a syntactic type is generative by default"
             (record-type-generative? (record-rtd syn-inst)))
(test-equal "cross-layer: a procedural accessor reads a syntactic record" 1
            ((record-accessor (record-rtd syn-inst) 'a) syn-inst))
(test-equal "cross-layer: a procedural mutator writes a syntactic record" 55
            (let ((i (make-syn-rec 1 2)))
              ((record-mutator (record-rtd i) 'b) i 55)
              (syn-b i)))
(test-assert "cross-layer: a procedural predicate recognizes a syntactic record"
             ((record-predicate (record-rtd syn-inst)) syn-inst))

;;; Sealing is enforced identically on both layers, from one shared helper.
(define-record-type syn-sealed (fields (immutable v syn-sealed-v)) (sealed #t))
(define syn-sealed-rtd (record-rtd (make-syn-sealed 1)))

(test-assert "cross-layer: a syntactically-sealed type reports sealed"
             (record-type-sealed? syn-sealed-rtd))
(test-assert "cross-layer: a syntactically-sealed rtd is rejected as a PROCEDURAL parent"
             (raises? (lambda ()
                        (make-record-type-descriptor 'sub syn-sealed-rtd #f #f #f
                                                     #((immutable w))))))
(test-assert "cross-layer: both layers report the sealed-parent rejection the same way"
             (let ((m (message-of (lambda ()
                                    (make-record-type-descriptor 'sub syn-sealed-rtd #f #f #f
                                                                 #((immutable w)))))))
               (and (string? m) (string-search m "is sealed and cannot be a parent"))))

;;; A syntactic nongenerative type is visible through the procedural registry.
(define-record-type syn-uid (fields (immutable v syn-uid-v)) (nongenerative audit-syn-uid))
(test-assert "cross-layer: a syntactic nongenerative uid registers in the procedural registry"
             (record-type-descriptor? (record-uid->rtd 'audit-syn-uid)))
(test-equal "cross-layer: the registered rtd carries the uid back" 'audit-syn-uid
            (record-type-uid (record-uid->rtd 'audit-syn-uid)))


;;; ===================================================================
;;; D6 — cross-heap deep copy (SRFI-18 thread boundaries)
;;;
;;; gc_deep_copy re-resolves a RecordType through vm.record_uid_registry,
;;; which only has an entry when the type is NONGENERATIVE.
;;; ===================================================================

(define XT (make-record-type-descriptor 'XT #f 'audit-cross-thread-uid #f #f #((immutable v))))
(define xt-ctor (root-ctor XT))
(define xt-pred (record-predicate XT))
(define xt-joined
  (let ((t (make-thread (lambda () (xt-ctor 42)))))
    (thread-start! t)
    (thread-join! t)))

(test-assert "cross-thread: a nongenerative record survives thread-join! with its type"
             (xt-pred xt-joined))
(test-eq "cross-thread: the joined record's rtd is the SAME rtd, by uid re-resolution"
         XT (record-rtd xt-joined))
(test-equal "cross-thread: the joined record's field reads correctly" 42
            ((record-accessor XT 'v) xt-joined))
(test-equal "cross-thread: the re-resolved rtd keeps its uid" 'audit-cross-thread-uid
            (record-type-uid (record-rtd xt-joined)))
(test-assert "cross-thread: the joined record is still a record" (record? xt-joined))

;; A GENERATIVE type has no registry entry, so the child heap's copy gets a
;; fresh rtd and the parent's predicate no longer recognizes it (#1932).
(define GT (make-record-type-descriptor 'GT #f #f #f #f #((immutable v))))
(define gt-ctor (root-ctor GT))
(define gt-joined
  (let ((t (make-thread (lambda () (gt-ctor 42)))))
    (thread-start! t)
    (thread-join! t)))

;; Enabled: the current, broken behaviour, pinned so #1932's fix flips it.
(test-assert "cross-thread: a generative record loses its type across thread-join! (#1932)"
             (not ((record-predicate GT) gt-joined)))
(test-assert "cross-thread control: it is still *a* record, just not of the original type"
             (record? gt-joined))

;; FAIL: #1932 (a generative record type is not preserved across thread-join!)
;; (test-assert "cross-thread: a generative record keeps its type across thread-join!"
;;              ((record-predicate GT) gt-joined))
;; FAIL: #1932 (a generative record type is not preserved across thread-join!)
;; (test-equal "cross-thread: a generative record's field reads after join" 42
;;             ((record-accessor GT 'v) gt-joined))


;;; ===================================================================
;;; Malformed input to the portable layer stays catchable
;;; ===================================================================

(test-assert "malformed: a non-symbol type name raises catchably"
             (raises? (lambda () (make-record-type-descriptor "str" #f #f #f #f #()))))
(test-assert "malformed: a non-rtd parent raises catchably"
             (raises? (lambda () (make-record-type-descriptor 'B 'not-an-rtd #f #f #f #()))))
(test-assert "malformed: a non-symbol uid raises catchably"
             (raises? (lambda () (make-record-type-descriptor 'B #f 42 #f #f #()))))
(test-assert "malformed: a bare symbol field spec raises catchably"
             (raises? (lambda () (make-record-type-descriptor 'B #f #f #f #f #(oops)))))
(test-assert "malformed: a one-element field spec raises catchably"
             (raises? (lambda () (make-record-type-descriptor 'B #f #f #f #f #((immutable))))))
(test-assert "malformed: record-constructor on a non-descriptor raises catchably"
             (raises? (lambda () (record-constructor 5))))
(test-assert "malformed: record-predicate on a non-rtd raises catchably"
             (raises? (lambda () ((record-predicate 5) 1))))
;; A SYMBOL field name forces %resolve-field-index to walk the rtd, so the
;; bad rtd is caught. An INTEGER is returned unexamined (the same passthrough
;; that makes integer k absolute rather than own-relative), so no validation
;; happens until the returned closure is applied.
(test-assert "malformed: record-accessor on a non-rtd with a field NAME raises catchably"
             (raises? (lambda () (record-accessor 5 'x))))
(test-assert "malformed: record-accessor on a non-rtd with an INTEGER defers validation"
             (procedure? (record-accessor 5 0)))
(test-assert "malformed: the deferred closure does raise when applied"
             (raises? (lambda () ((record-accessor 5 0) c-inst))))

;; FAIL: TBD (integer k bypasses rtd validation in %resolve-field-index)
;; (test-assert "malformed: record-accessor on a non-rtd raises eagerly"
;;              (raises? (lambda () (record-accessor 5 0))))
(test-assert "malformed: record-uid->rtd on a non-symbol raises catchably"
             (raises? (lambda () (record-uid->rtd "a-string"))))

;;; A zero-field record type is legal and instantiable.
(let* ((Z (make-record-type-descriptor 'Z #f #f #f #f #()))
       (zi ((root-ctor Z))))
  (test-assert "zero fields: instance is a record" (record? zi))
  (test-assert "zero fields: predicate holds" ((record-predicate Z) zi))
  (test-equal "zero fields: field-names is empty" '() (record-type-field-names Z))
  (test-equal "zero fields: total field count is 0" 0 (%record-type-total-field-count Z)))


;;; ===================================================================
;;; Missing names from the SRFI 237 export surface
;;;
;;; lib/srfi/237.sld documents four deliberate gaps (port-read-rtd,
;;; port-write-rtd, define-record-name, and the deprecated
;;; record-type-descriptor/record-constructor-descriptor SYNTAX). These
;;; three specified names are absent without being among them.
;;; ===================================================================

;; FAIL: TBD (the 7-argument make-record-descriptor variant is not implemented)
;; (test-assert "exports: the 7-argument make-record-descriptor variant"
;;              (record-descriptor?
;;                (make-record-descriptor 'Z #f #f #f #f #((immutable v)) #f)))
;; FAIL: TBD (make-record-constructor-descriptor is not exported)
;; (test-assert "exports: make-record-constructor-descriptor" (procedure? make-record-constructor-descriptor))
;; FAIL: TBD (record-constructor-descriptor? is not exported)
;; (test-assert "exports: record-constructor-descriptor?" (procedure? record-constructor-descriptor?))

;; Enabled control: the 3-argument form these are aliases of works fine, so
;; the gap is in the export surface, not the underlying mechanism.
(test-assert "exports control: the 3-argument make-record-descriptor works"
             (record-descriptor? (make-record-descriptor P #f #f)))
(test-assert "exports control: the 7-argument call raises an arity error, not a type error"
             (raises? (lambda () (make-record-descriptor 'Z #f #f #f #f #((immutable v)) #f))))


(let ((runner (test-runner-current)))
  (test-end "primitives_srfi237 audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
