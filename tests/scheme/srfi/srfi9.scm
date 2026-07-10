;; SRFI-9 (define-record-type) conformance tests — audit Phase 3.1
;; SRFI-9 is built-in: (srfi 9) is a marker library; the form itself is
;; handled by the VM (vm_records.zig). See docs/audit-strategy.md.
;; Run directly and read the pass/fail counts:
;;   zig-out/bin/kaappi tests/scheme/srfi/srfi9.scm

(import (scheme base) (srfi 9) (scheme process-context) (srfi 64))

(test-begin "srfi-9")

;;; --- the spec's <pare> example, verbatim semantics ---
(define-record-type <pare>
  (kons x y)
  pare?
  (x kar set-kar!)
  (y kdr))

(test-equal #t (pare? (kons 1 2)))
(test-equal #f (pare? (cons 1 2)))
(test-equal 1 (kar (kons 1 2)))
(test-equal 2 (kdr (kons 1 2)))
(test-equal 3 (let ((k (kons 1 2)))
                (set-kar! k 3)
                (kar k)))

;;; --- constructor field tags map by name, not position ---
(define-record-type swap (mk-swap b a) swap? (a get-a) (b get-b))
(let ((s (mk-swap 'B-val 'A-val)))
  (test-equal 'A-val (get-a s))
  (test-equal 'B-val (get-b s)))

;;; --- constructor may list a subset of fields ---
;; SRFI-9: "The initial values of all other fields are unspecified."
(define-record-type part (mk-part x) part? (x get-x) (y get-y set-y!))
(let ((p (mk-part 1)))
  (test-equal 1 (get-x p))
  (test-equal 'readable (begin (get-y p) 'readable))   ; unspecified but no crash
  (set-y! p 42)
  (test-equal 42 (get-y p)))

;;; --- disjointness ---
;; SRFI-9: "Records are disjoint from the types listed in Section 4.2 of R5RS."
(let ((r (kons 1 2)))
  (test-equal #f (pair? r))
  (test-equal #f (vector? r))
  (test-equal #f (procedure? r))
  (test-equal #f (string? r))
  (test-equal #f (symbol? r))
  (test-equal #f (boolean? r))
  (test-equal #f (char? r))
  (test-equal #f (number? r))
  (test-equal #f (null? r)))
;; and other types do not satisfy record predicates
(test-equal #f (pare? 42))
(test-equal #f (pare? '()))
(test-equal #f (pare? "record"))
(test-equal #f (pare? #(1 2)))

;;; --- distinct record types are mutually disjoint ---
(test-equal #f (swap? (kons 1 2)))
(test-equal #f (pare? (mk-swap 1 2)))

;;; --- equivalence: records compare by identity ---
(let ((r1 (kons 1 2)) (r2 (kons 1 2)))
  (test-equal #t (equal? r1 r1))
  (test-equal #t (eqv? r1 r1))
  (test-equal #f (equal? r1 r2))
  (test-equal #f (eqv? r1 r2)))

;;; --- records nest and travel through data structures ---
(let* ((inner (kons 'i1 'i2))
       (outer (kons inner (list inner))))
  (test-equal 'i1 (kar (kar outer)))
  (test-equal #t (eq? inner (car (kdr outer)))))

;;; --- accessors/modifiers on non-records raise ---
(test-equal #t (guard (e (#t (error-object? e))) (kar 42) #f))
(test-equal #t (guard (e (#t (error-object? e))) (kar '()) #f))
(test-equal #t (guard (e (#t (error-object? e))) (set-kar! "x" 1) #f))

;; Cross-type access is silently accepted (accessors skip the type check):
;; FAIL: #1199 (record accessors/mutators do not check the record type)
;; (test-equal #t (guard (e (#t (error-object? e))) (get-a (kons 1 2)) #f))

;;; --- generativity ---
;; SRFI-9: "each use creates a new record type that is distinct from all
;; existing types"
(define-record-type tt (mk-tt) tt?)
(define old-inst (mk-tt))
(define old-pred tt?)
(define old-mk mk-tt)
(define-record-type tt (mk-tt v) tt? (v tt-v))

;; the new predicate rejects instances of the old type
(test-equal #f (tt? old-inst))

;; ...previously-created procedures must keep referring to the OLD type.
;; The desugar closes over the record-type object at definition time,
;; so redefinition does not retarget them (#1203):
(test-equal #t (old-pred old-inst))
(test-equal #f (tt? (old-mk)))

;;; --- define-record-type inside begin (R7RS 5.5: outermost level or body) ---
(begin
  (define-record-type bt (mk-bt v) bt? (v bt-v))
  (test-equal 7 (bt-v (mk-bt 7))))

;;; --- define-record-type inside a <body> (R7RS 5.5: body context) ---
(test-equal 8 (let ()
                (define-record-type lt (mk-lt v) lt? (v lt-v))
                (lt-v (mk-lt 8))))

(let ((runner (test-runner-current)))
  (test-end "srfi-9")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
