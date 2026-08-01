;;; Audit: lib/srfi/240.sld (SRFI 240 — Reconciled Records) over (srfi 237)
;;; Systematic audit v2, Phase 3.9 (docs/audit-strategy.md, tracking #1890).
;;;
;;; Oracle: SRFI 240, https://srfi.schemers.org/srfi-240/srfi-240.html, whose
;;; whole content is "a `define-record-type` that accepts EITHER R6RS clause
;;; syntax or the R7RS/SRFI-9 positional syntax, both producing interoperable
;;; record types", with everything else inherited from SRFI 237.
;;;
;;; That interoperability claim is what this file tests, and it is where the
;;; finding is: a record type created by R7RS positional `define-record-type`
;;; reports ZERO field names to the SRFI 237/240 inspection layer, so
;;; record-type-field-names lies (#() rather than the fields the type has) and
;;; record-accessor / record-mutator / record-field-mutable? are unusable on
;;; it. The R6RS-clause and procedural paths are both correct, which is the
;;; discriminating control. Filed as #2088.
;;;
;;; The pre-existing tests/scheme/srfi/srfi240.scm has 12 assertions and never
;;; touches 17 of the 23 exports.
;;;
;;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi240-audit.scm

(import (scheme base) (scheme write) (scheme process-context) (srfi 64) (srfi 240))

(test-begin "srfi240 audit")

(define (raises? thunk)
  (call-with-current-continuation
   (lambda (k) (with-exception-handler (lambda (e) (k #t)) (lambda () (thunk) #f)))))

;;; ------------------------------------------------------------------
;;; The procedural layer, which SRFI 240 re-exports verbatim from SRFI 237.
;;; ------------------------------------------------------------------

(define rtd-pt (make-record-type-descriptor 'pt #f #f #f #f '#((mutable x) (immutable y))))

(test-assert "record-type-descriptor? on a procedurally built rtd"
             (record-type-descriptor? rtd-pt))
(test-assert "record-type-descriptor? on a non-rtd" (not (record-type-descriptor? 42)))
(test-equal "record-type-name" 'pt (record-type-name rtd-pt))
(test-equal "record-type-field-names is a vector of the own field names"
            '#(x y) (record-type-field-names rtd-pt))
(test-assert "record-field-mutable? on a mutable field" (record-field-mutable? rtd-pt 0))
(test-assert "record-field-mutable? on an immutable field"
             (not (record-field-mutable? rtd-pt 1)))
(test-assert "record-type-parent of a parentless rtd is #f" (not (record-type-parent rtd-pt)))
(test-assert "record-type-uid of a generative rtd is #f" (not (record-type-uid rtd-pt)))
(test-assert "record-type-generative? of a uid-less rtd" (record-type-generative? rtd-pt))
(test-assert "record-type-sealed? defaults to false" (not (record-type-sealed? rtd-pt)))
(test-assert "record-type-opaque? defaults to false" (not (record-type-opaque? rtd-pt)))

(define rcd-pt (make-record-constructor-descriptor rtd-pt #f #f))
(test-assert "record-constructor-descriptor? on a fresh rcd"
             (record-constructor-descriptor? rcd-pt))
(test-assert "record-constructor-descriptor? on an rtd" (not (record-constructor-descriptor? rtd-pt)))
(define make-pt (record-constructor rcd-pt))
(define pt? (record-predicate rtd-pt))
(define pt-x (record-accessor rtd-pt 0))
(define pt-y (record-accessor rtd-pt 1))
(define set-pt-x! (record-mutator rtd-pt 0))
(define p1 (make-pt 1 2))

(test-assert "record? on a procedurally built instance" (record? p1))
(test-assert "record? on a non-record" (not (record? 42)))
(test-assert "the predicate accepts its own instances" (pt? p1))
(test-assert "the predicate rejects other values" (not (pt? 42)))
(test-equal "accessor 0" 1 (pt-x p1))
(test-equal "accessor 1" 2 (pt-y p1))
(test-assert "record-rtd returns the type it was built from" (eq? rtd-pt (record-rtd p1)))
(test-equal "the mutator writes the field" 9 (begin (set-pt-x! p1 9) (pt-x p1)))
(test-assert "record-mutator on an immutable field is rejected"
             (raises? (lambda () (record-mutator rtd-pt 1))))
(test-assert "record-accessor with an out-of-range index is rejected"
             (raises? (lambda () (record-accessor rtd-pt 5))))

;;; Sealed, opaque and nongenerative rtds
(define rtd-sealed (make-record-type-descriptor 'sealed-pt #f #f #t #f '#((immutable a))))
(test-assert "record-type-sealed? on a sealed rtd" (record-type-sealed? rtd-sealed))
(test-assert "a sealed rtd cannot be a parent"
             (raises? (lambda () (make-record-type-descriptor 'kid rtd-sealed #f #f #f '#()))))
(define rtd-opaque (make-record-type-descriptor 'opaque-pt #f #f #f #t '#((immutable a))))
(test-assert "record-type-opaque? on an opaque rtd" (record-type-opaque? rtd-opaque))
(define rtd-uid (make-record-type-descriptor 'uid-pt #f 'srfi240-audit-uid #f #f '#((immutable a))))
(test-equal "record-type-uid of a nongenerative rtd" 'srfi240-audit-uid (record-type-uid rtd-uid))
(test-assert "record-type-generative? of a nongenerative rtd is false"
             (not (record-type-generative? rtd-uid)))
(test-assert "record-uid->rtd finds a nongenerative rtd by its uid"
             (eq? rtd-uid (record-uid->rtd 'srfi240-audit-uid)))
(test-assert "record-uid->rtd of an unknown uid is #f"
             (not (record-uid->rtd 'srfi240-audit-no-such-uid)))
(test-assert "re-declaring the same uid with the same shape yields the same rtd"
             (eq? rtd-uid (make-record-type-descriptor 'uid-pt #f 'srfi240-audit-uid #f #f
                                                       '#((immutable a)))))

;;; Inheritance through the procedural layer
(define rtd-base (make-record-type-descriptor 'base #f #f #f #f '#((immutable a))))
(define rtd-kid (make-record-type-descriptor 'kid rtd-base #f #f #f '#((immutable b))))
(test-assert "record-type-parent of a child rtd" (eq? rtd-base (record-type-parent rtd-kid)))
(test-equal "a child rtd's field names exclude the parent's" '#(b)
            (record-type-field-names rtd-kid))
(define make-kid (record-constructor (make-record-constructor-descriptor rtd-kid #f #f)))
(define k1 (make-kid 1 2))
(test-equal "a child instance's inherited field" 1 ((record-accessor rtd-base 0) k1))
(test-equal "a child instance's own field" 2 ((record-accessor rtd-kid 0) k1))
(test-assert "the parent's predicate accepts a child instance" ((record-predicate rtd-base) k1))
(test-assert "the child's predicate rejects a parent instance"
             (not ((record-predicate rtd-kid)
                   ((record-constructor (make-record-constructor-descriptor rtd-base #f #f)) 1))))

;;; record-descriptor: the pairing of an rtd with an rcd
;; Two arities: the 3-argument (rtd parent-rd protocol) form and the
;; 7-argument (name parent uid sealed? opaque? fields protocol) shorthand.
(define rd (make-record-descriptor rtd-pt #f #f))
(test-assert "record-descriptor? on a fresh record descriptor" (record-descriptor? rd))
(test-assert "record-descriptor? on an rtd" (not (record-descriptor? rtd-pt)))
(test-assert "record-descriptor-rtd returns the rtd" (eq? rtd-pt (record-descriptor-rtd rd)))
(test-assert "record-descriptor-parent of a parentless descriptor is #f"
             (not (record-descriptor-parent rd)))
(define rd7 (make-record-descriptor 'rd7 #f #f #f #f '#((immutable a)) #f))
(test-assert "the 7-argument make-record-descriptor shorthand builds a descriptor"
             (record-descriptor? rd7))
(test-equal "the 7-argument shorthand names the type it built"
            'rd7 (record-type-name (record-descriptor-rtd rd7)))
(test-assert "a constructor from a 7-argument descriptor works"
             (record? ((record-constructor rd7) 1)))
(test-assert "record-descriptor-rtd also accepts a bare rtd"
             (eq? rtd-pt (record-descriptor-rtd rtd-pt)))

;;; ------------------------------------------------------------------
;;; R6RS clause syntax. SRFI 240's own reason for existing is that this and
;;; the R7RS positional syntax produce interoperable types.
;;; ------------------------------------------------------------------

(define-record-type <r6> (fields (immutable a) (mutable b)))
(define r6 (make-<r6> 1 2))

(test-assert "an R6RS-clause record is a record" (record? r6))
(test-assert "an R6RS-clause record has an rtd" (record-type-descriptor? (record-rtd r6)))
(test-equal "an R6RS-clause record reports its field names"
            '#(a b) (record-type-field-names (record-rtd r6)))
(test-equal "record-accessor works on an R6RS-clause record"
            1 ((record-accessor (record-rtd r6) 0) r6))
(test-equal "record-accessor reaches the second field of an R6RS-clause record"
            2 ((record-accessor (record-rtd r6) 1) r6))
(test-assert "record-field-mutable? works on an R6RS-clause record"
             (not (record-field-mutable? (record-rtd r6) 0)))
(test-assert "record-field-mutable? sees the mutable field of an R6RS-clause record"
             (record-field-mutable? (record-rtd r6) 1))
(test-equal "record-mutator works on an R6RS-clause record"
            9 (let ((m (record-mutator (record-rtd r6) 1))) (m r6 9) (<r6>-b r6)))
(test-assert "a constructor derived from an R6RS-clause record's own rtd works"
             (<r6>? ((record-constructor
                      (make-record-constructor-descriptor (record-rtd r6) #f #f)) 1 2)))

;;; ------------------------------------------------------------------
;;; R7RS positional syntax. `record?`, `record-rtd`, `record-type-name` and a
;;; derived `record-constructor` all work, so the type IS visible to the
;;; inspection layer — but its field metadata is empty.
;;; ------------------------------------------------------------------

(define-record-type <r7> (make-r7 x y) r7? (x r7-x) (y r7-y set-r7-y!))
(define r7 (make-r7 1 2))

(test-assert "an R7RS record is a record" (record? r7))
(test-assert "an R7RS record has an rtd" (record-type-descriptor? (record-rtd r7)))
(test-equal "an R7RS record's rtd carries its name" '<r7> (record-type-name (record-rtd r7)))
(test-assert "record-type-parent of an R7RS record's rtd is #f"
             (not (record-type-parent (record-rtd r7))))
(test-assert "record-type-sealed? of an R7RS record's rtd is #f"
             (not (record-type-sealed? (record-rtd r7))))
(test-assert "record-type-opaque? of an R7RS record's rtd is #f"
             (not (record-type-opaque? (record-rtd r7))))
(test-assert "the R7RS record's own predicate works" (r7? r7))
(test-assert "record-predicate derived from the rtd works" ((record-predicate (record-rtd r7)) r7))
;; The arity IS known somewhere: a procedurally derived constructor takes two
;; arguments and builds a valid instance, even though field-names says zero.
(test-assert "a constructor derived from an R7RS record's own rtd builds an instance"
             (r7? ((record-constructor
                    (make-record-constructor-descriptor (record-rtd r7) #f #f)) 1 2)))

;; FAIL: #2088 (an R7RS define-record-type produces an rtd with zero own field
;;              names, so the SRFI 237/240 inspection layer cannot see its fields)
;; (test-equal "an R7RS record reports its field names"
;;             '#(x y) (record-type-field-names (record-rtd r7)))
;; FAIL: #2088
;; (test-equal "record-accessor works on an R7RS record"
;;             1 ((record-accessor (record-rtd r7) 0) r7))
;; FAIL: #2088
;; (test-assert "record-field-mutable? works on an R7RS record"
;;              (not (record-field-mutable? (record-rtd r7) 0)))
;; FAIL: #2088
;; (test-assert "record-mutator works on an R7RS record's mutable field"
;;              (procedure? (record-mutator (record-rtd r7) 1)))

;; The observed behaviour, pinned so the fix flips these too.
(test-equal "an R7RS record's rtd currently reports zero field names"
            '#() (record-type-field-names (record-rtd r7)))
(test-assert "record-accessor on an R7RS record's rtd currently raises"
             (raises? (lambda () (record-accessor (record-rtd r7) 0))))
(test-assert "record-field-mutable? on an R7RS record's rtd currently raises"
             (raises? (lambda () (record-field-mutable? (record-rtd r7) 0))))
(test-assert "record-mutator on an R7RS record's rtd currently raises"
             (raises? (lambda () (record-mutator (record-rtd r7) 1))))

;; Discriminating control: the same two-field, one-mutable shape built the two
;; other ways is fully introspectable, so the defect is specific to the R7RS
;; positional desugarer, not to the inspection layer.
(test-equal "control: the same shape as an R6RS-clause type reports 2 field names"
            2 (vector-length (record-type-field-names (record-rtd r6))))
(test-equal "control: the same shape built procedurally reports 2 field names"
            2 (vector-length (record-type-field-names rtd-pt)))

;;; ------------------------------------------------------------------
;;; SRFI 240 adds no semantics of its own: the reconciliation it describes is
;;; the engine's unconditional top-level behaviour, with or without the
;;; import. Pinned so the .sld's own header claim is checkable.
;;; ------------------------------------------------------------------

(test-assert "the R6RS and R7RS syntaxes produce distinct types"
             (not (eq? (record-rtd r6) (record-rtd r7))))
(test-assert "an R6RS-clause instance is not an R7RS instance" (not (r7? r6)))
(test-assert "an R7RS instance is not an R6RS-clause instance" (not (<r6>? r7)))
(test-assert "cond-expand reports the srfi-240 feature identifier"
             (cond-expand (srfi-240 #t) (else #f)))

(let ((runner (test-runner-current)))
  (test-end "srfi240 audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
