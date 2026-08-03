;;; Audit: src/primitives_srfi254.zig (SRFI 254 — Ephemerons and Guardians)
;;; Systematic audit v2, Phase 2.10 (docs/audit-strategy.md, tracking #1890).
;;;
;;; Oracle: SRFI 254 (finalized 2026-06-30), https://srfi.schemers.org/srfi-254/
;;; Quoted spec sentences appear beside the assertions they justify.
;;;
;;; This is the only primitives file with real garbage-collector integration,
;;; so the surface under test is wider than one .zig file:
;;;   * src/primitives_srfi254.zig      — the 16 specs (constructors, predicates,
;;;                                       accessors, current-hash, reference-barrier)
;;;   * src/gc_collect.processWeakRefs  — breaking, resurrection, the fixpoint
;;;   * src/gc_collect.markGuardianStrong / registerPendingEphemeron
;;;   * src/vm_calls.invokeGuardian     — a guardian is itself callable
;;;   * src/types_weakrefs.zig          — Ephemeron / Guardian / TransportCell
;;;   * src/gc_deep_copy.zig            — all three tags are on the refusal list
;;;
;;; Forcing collection: objects are created inside a `let` (a top-level `define`
;;; is retained by stale registers in the base frame and is never collectable —
;;; see #1933), every GC scenario is registered up front, and a single `churn!`
;;; phase then drives several collections at once. Nothing here asserts *when* a
;;; collection happens, only what is observable after one has been forced.
;;;
;;; Run: zig-out/bin/kaappi tests/scheme/audit/primitives_srfi254-audit.scm
;;; Also verified under a separate `zig build -Dgc-stress=true` build.

(import (scheme base) (scheme write) (scheme lazy) (scheme process-context)
        (srfi 18) (srfi 64) (srfi 69) (srfi 181) (srfi 254) (kaappi fibers))

(test-begin "primitives_srfi254 audit")

;; #t iff the thunk raises anything catchable.
(define (raises? thunk)
  (call-with-current-continuation
    (lambda (k)
      (with-exception-handler (lambda (c) (k #t))
        (lambda () (thunk) #f)))))

;; The message of whatever the thunk raises, or #f if it did not raise.
(define (raised-message thunk)
  (call-with-current-continuation
    (lambda (k)
      (with-exception-handler
        (lambda (c) (k (if (error-object? c) (error-object-message c) c)))
        (lambda () (thunk) #f)))))

(define (substring? needle hay)
  (let ((n (string-length needle)) (h (string-length hay)))
    (let loop ((i 0))
      (cond ((> (+ i n) h) #f)
            ((string=? needle (substring hay i (+ i n))) #t)
            (else (loop (+ i 1)))))))

;; One churn round allocates well past the default 8192-object GC threshold.
(define (churn!) (do ((i 0 (+ i 1))) ((= i 10000)) (list i i)))
(define (churn-rounds! n) (do ((i 0 (+ i 1))) ((= i n)) (churn!)))

;; ---------------------------------------------------------------------------
;; 1. Library surface (D4, D7)
;;
;; Spec: the ephemerons library exports the six ephemeron procedures plus
;; reference-barrier; "The procedure reference-barrier is also exported by the
;; ... guardians library"; current-hash belongs to the transport cell guardians
;; library; "The (srfi :254) and (srfi :254 ephemerons-and-guardians) libraries
;; are a composite of the libraries described above."
;; ---------------------------------------------------------------------------

(test-assert "exports: make-ephemeron"              (procedure? make-ephemeron))
(test-assert "exports: ephemeron?"                  (procedure? ephemeron?))
(test-assert "exports: ephemeron-key"               (procedure? ephemeron-key))
(test-assert "exports: ephemeron-value"             (procedure? ephemeron-value))
(test-assert "exports: ephemeron-broken?"           (procedure? ephemeron-broken?))
(test-assert "exports: ephemeron-ref"               (procedure? ephemeron-ref))
(test-assert "exports: make-guardian"               (procedure? make-guardian))
(test-assert "exports: guardian?"                   (procedure? guardian?))
(test-assert "exports: reference-barrier"           (procedure? reference-barrier))
(test-assert "exports: make-transport-cell-guardian" (procedure? make-transport-cell-guardian))
(test-assert "exports: transport-cell-guardian?"    (procedure? transport-cell-guardian?))
(test-assert "exports: transport-cell?"             (procedure? transport-cell?))
(test-assert "exports: transport-cell-key"          (procedure? transport-cell-key))
(test-assert "exports: transport-cell-value"        (procedure? transport-cell-value))
(test-assert "exports: transport-cell-broken?"      (procedure? transport-cell-broken?))
(test-assert "exports: current-hash"                (procedure? current-hash))

;; SRFI 254 is a cond-expand feature identifier, derived from library
;; availability (vm_library.srfiFeatureAvailable).
(test-equal "cond-expand: srfi-254 answers yes" 'yes
            (cond-expand (srfi-254 'yes) (else 'no)))

;; ---------------------------------------------------------------------------
;; 2. Ephemerons — API without collection
;; ---------------------------------------------------------------------------

(define e-api (make-ephemeron 'k 'v))

(test-assert "ephemeron?: a fresh ephemeron"          (ephemeron? e-api))
(test-assert "ephemeron?: a symbol is not one"        (not (ephemeron? 'x)))
(test-assert "ephemeron?: a pair is not one"          (not (ephemeron? (list 1))))
(test-assert "ephemeron?: a guardian is not one"      (not (ephemeron? (make-guardian))))
(test-assert "ephemeron?: a transport cell is not one"
             (not (ephemeron? ((make-transport-cell-guardian) 'a 'b))))

;; "The ephemeron-key procedure returns the contents of the key field of
;; ephemeron if the ephemeron hasn't been broken, and #f otherwise."
(test-equal "ephemeron-key: unbroken returns the key" 'k (ephemeron-key e-api))
;; "The ephemeron-value procedure returns the contents of the value field."
(test-equal "ephemeron-value: returns the value" 'v (ephemeron-value e-api))
;; "The ephemeron-broken? procedure returns #t if ephemeron has been broken."
(test-assert "ephemeron-broken?: a fresh ephemeron is not broken"
             (not (ephemeron-broken? e-api)))

;; "returns the contents of the value field of ephemeron if the ephemeron
;; hasn't been broken and the contents of its key field and key are equivalent
;; in the sense of eq?, and default otherwise."
(test-equal "ephemeron-ref: eq? key hits" 'v (ephemeron-ref e-api 'k))
(test-equal "ephemeron-ref: non-eq? key returns the given default" 'd
            (ephemeron-ref e-api 'nope 'd))
;; "If not given, the optional default defaults to #f."
(test-assert "ephemeron-ref: non-eq? key with no default returns #f"
             (not (ephemeron-ref e-api 'nope)))
;; The key is held live so this misses for the eq?-identity reason and not
;; because a collection broke the ephemeron first.
(test-assert "ephemeron-ref: eq? is identity, not equal? — an equal? list misses"
             (let* ((k (list 1 2)) (e (make-ephemeron k 'hit)))
               (not (ephemeron-ref e (list 1 2)))))
(test-equal "ephemeron-ref: the very same list hits" 'hit
            (let* ((k (list 1 2)) (e (make-ephemeron k 'hit)))
              (ephemeron-ref e k)))

;; make-ephemeron places no constraint on either field.
(test-assert "make-ephemeron: accepts an ephemeron as its own value"
             (ephemeron? (ephemeron-value (make-ephemeron 'k (make-ephemeron 'a 'b)))))
(test-assert "make-ephemeron: accepts a guardian as key"
             (ephemeron? (make-ephemeron (make-guardian) 'v)))
(test-assert "make-ephemeron: key may be the value itself"
             (let* ((k (list 'self)) (e (make-ephemeron k k)))
               (eq? (ephemeron-key e) (ephemeron-value e))))

;; #f as a key is legal but indistinguishable from broken through
;; ephemeron-key alone — which is exactly why the spec provides
;; ephemeron-broken?: "#f is not a portable key, denoting no location."
(test-assert "ephemeron-key: an ephemeron keyed on #f returns #f while unbroken"
             (let ((e (make-ephemeron #f 'v)))
               (and (not (ephemeron-key e)) (not (ephemeron-broken? e)))))
(test-equal "ephemeron-ref: #f key still matches by eq?" 'v
            (ephemeron-ref (make-ephemeron #f 'v) #f))

;; Ephemerons have identity, not structure.
(test-assert "eqv?: an ephemeron is eqv? to itself" (eqv? e-api e-api))
(test-assert "equal?: two same-content ephemerons are distinct"
             (not (equal? (make-ephemeron 'a 'b) (make-ephemeron 'a 'b))))
(test-assert "an ephemeron is not a procedure" (not (procedure? e-api)))

;; ---------------------------------------------------------------------------
;; 3. Guardians and transport cell guardians — API without collection
;; ---------------------------------------------------------------------------

(define g-api (make-guardian))
(define tg-api (make-transport-cell-guardian))

;; "Guardians are represented by a Scheme procedure guardian."
(test-assert "guardian?: a fresh guardian"             (guardian? g-api))
(test-assert "guardian: is a procedure"                (procedure? g-api))
(test-assert "guardian?: a transport cell guardian is not an object guardian"
             (not (guardian? tg-api)))
(test-assert "transport-cell-guardian?: a fresh one"   (transport-cell-guardian? tg-api))
(test-assert "transport-cell-guardian?: an object guardian is not one"
             (not (transport-cell-guardian? g-api)))
(test-assert "transport cell guardian: is a procedure" (procedure? tg-api))
(test-assert "guardian?: a symbol is not one"          (not (guardian? 'x)))
(test-assert "guardian?: an ordinary procedure is not one" (not (guardian? car)))
(test-assert "transport-cell-guardian?: an ordinary procedure is not one"
             (not (transport-cell-guardian? car)))

;; "When guardian is invoked on no arguments, a resurrected element, if
;; available, is removed from the guardian and its contents returned. If no
;; resurrected element is available, #f is returned."
(test-assert "(g) on an empty guardian returns #f" (not (g-api)))

;; "When guardian is invoked on two Scheme values key and value, a transport
;; cell with fields key and value is added to guardian and returned to the
;; caller of guardian."
(define c-api (tg-api 'tk 'tv))
(test-assert "(tg key value) returns a transport cell" (transport-cell? c-api))
(test-equal "transport-cell-key: unbroken returns the key" 'tk (transport-cell-key c-api))
(test-equal "transport-cell-value: returns the value" 'tv (transport-cell-value c-api))
(test-assert "transport-cell-broken?: a fresh cell is not broken"
             (not (transport-cell-broken? c-api)))
(test-assert "transport-cell?: a symbol is not a cell" (not (transport-cell? 'x)))
(test-assert "transport-cell?: an ephemeron is not a cell" (not (transport-cell? e-api)))
(test-assert "transport-cell?: a guardian is not a cell" (not (transport-cell? g-api)))
(test-assert "(tg) with no transported cell returns #f" (not (tg-api)))

;; Kaappi extends the spec's two-argument register form with a one-argument
;; form (rep = obj), as R6RS/Chez guardians do. The spec defines only the
;; zero- and two-argument forms, so this is an extension, not a deviation.
(test-assert "guardian: the one-argument register form is accepted"
             (not (raises? (lambda () (g-api (list 'one-arg))))))
(test-assert "guardian: the two-argument register form is accepted"
             (not (raises? (lambda () (g-api (list 'two-arg) 'rep)))))

;; ---------------------------------------------------------------------------
;; 4. reference-barrier
;;
;; "If obj is an object such as a pair, string, vector, or bytevector that
;; denotes a location or a sequence of locations, the location or the sequence
;; of locations is kept alive."  The spec assigns no return value.
;; ---------------------------------------------------------------------------

(test-assert "reference-barrier: accepts a pair"       (not (raises? (lambda () (reference-barrier (list 1))))))
(test-assert "reference-barrier: accepts a string"     (not (raises? (lambda () (reference-barrier "s")))))
(test-assert "reference-barrier: accepts a vector"     (not (raises? (lambda () (reference-barrier (vector 1))))))
(test-assert "reference-barrier: accepts a bytevector" (not (raises? (lambda () (reference-barrier (bytevector 1))))))
(test-assert "reference-barrier: accepts an immediate" (not (raises? (lambda () (reference-barrier 42)))))
(test-assert "reference-barrier: accepts #f"           (not (raises? (lambda () (reference-barrier #f)))))
(test-assert "reference-barrier: accepts a guardian"   (not (raises? (lambda () (reference-barrier g-api)))))

;; ---------------------------------------------------------------------------
;; 5. current-hash
;;
;; "The current-hash procedure returns an exact integer. Consider objects obj1
;; and obj2 such that eq? returns #t when applied to them. If obj1 and obj2 are
;; not moved between an invocation of current-hash to obj1 and an invocation of
;; current-hash to obj2, both calls to current-hash return the same exact
;; integer."  Kaappi never moves objects, so the condition always holds.
;; ---------------------------------------------------------------------------

(define ch-obj (list 'hashed))
(define ch-h0 (current-hash ch-obj))

(test-assert "current-hash: returns an exact integer" (and (integer? ch-h0) (exact? ch-h0)))
(test-assert "current-hash: non-negative"             (>= ch-h0 0))
(test-equal "current-hash: stable for the same object" ch-h0 (current-hash ch-obj))
(test-assert "current-hash: eq? symbols hash alike"
             (= (current-hash 'sym-a) (current-hash (string->symbol "sym-a"))))
(test-assert "current-hash: eq? strings hash alike"
             (let ((s "shared")) (= (current-hash s) (current-hash s))))
;; Both pairs stay live for the comparison: an object freed between the two
;; calls could be replaced at the same address, which would make equal hashes
;; correct rather than a collision.
(test-assert "current-hash: two distinct live pairs hash differently"
             (let ((a (list 1)) (b (list 1)))
               (not (= (current-hash a) (current-hash b)))))
(test-assert "current-hash: accepts every immediate without raising"
             (not (raises? (lambda ()
                             (for-each current-hash
                                       (list 0 -1 #t #f '() #\a 1.5 +inf.0 (if #f #f)))))))
(test-assert "current-hash: accepts a guardian and an ephemeron"
             (and (exact? (current-hash g-api)) (exact? (current-hash e-api))))

;; Kaappi's hash is the NaN-boxed value word folded to 46 bits. That is
;; conformant (the spec constrains only eq? objects) but it collapses whole
;; classes of immediate: every flonum whose low 46 mantissa bits are zero maps
;; to 0, and fixnums differing only above bit 45 collide. Recorded so a future
;; change to the fold is a visible, deliberate change.
(test-assert "current-hash: distinct flonums collide (46-bit fold of the f64 bits)"
             (= (current-hash 1.5) (current-hash 2.5)))
(test-assert "current-hash: exact 0 and inexact 0.0 collide"
             (= (current-hash 0) (current-hash 0.0)))
(test-assert "current-hash: #f and '() do not collide"
             (not (= (current-hash #f) (current-hash '()))))
(test-assert "current-hash: heap objects do not collide en masse"
             (let* ((n 2000)
                    (v (make-vector n))
                    (h (make-hash-table)))
               (do ((i 0 (+ i 1))) ((= i n)) (vector-set! v i (list i)))
               (do ((i 0 (+ i 1))) ((= i n))
                 (hash-table-set! h (current-hash (vector-ref v i)) #t))
               (= n (hash-table-size h))))

;; ---------------------------------------------------------------------------
;; 6. Error taxonomy (D2)
;;
;; KP3002 = type error, KP3003 = arity mismatch, KP3007 = invalid argument.
;; Every failure below is catchable; none aborts the process.
;; ---------------------------------------------------------------------------

(define (type-error-names? proc-name thunk)
  (let ((m (raised-message thunk)))
    (and (string? m)
         (substring? "type error" m)
         (substring? proc-name m))))

(test-assert "ephemeron-key: non-ephemeron is a named type error"
             (type-error-names? "ephemeron-key" (lambda () (ephemeron-key 5))))
(test-assert "ephemeron-value: non-ephemeron is a named type error"
             (type-error-names? "ephemeron-value" (lambda () (ephemeron-value 5))))
(test-assert "ephemeron-broken?: non-ephemeron is a named type error"
             (type-error-names? "ephemeron-broken?" (lambda () (ephemeron-broken? 5))))
(test-assert "ephemeron-ref: non-ephemeron is a named type error"
             (type-error-names? "ephemeron-ref" (lambda () (ephemeron-ref 5 'k))))
(test-assert "transport-cell-key: non-cell is a named type error"
             (type-error-names? "transport-cell-key" (lambda () (transport-cell-key 5))))
(test-assert "transport-cell-value: non-cell is a named type error"
             (type-error-names? "transport-cell-value" (lambda () (transport-cell-value 5))))
(test-assert "transport-cell-broken?: non-cell is a named type error"
             (type-error-names? "transport-cell-broken?" (lambda () (transport-cell-broken? 5))))
;; The three predicates take anything and answer, rather than raising.
(test-assert "ephemeron?: never raises on a non-ephemeron"
             (not (raises? (lambda () (ephemeron? 5)))))
(test-assert "guardian?: never raises on a non-guardian"
             (not (raises? (lambda () (guardian? 5)))))
(test-assert "transport-cell?: never raises on a non-cell"
             (not (raises? (lambda () (transport-cell? 5)))))

(test-assert "make-ephemeron: too few arguments raises"
             (raises? (lambda () (make-ephemeron 'a))))
(test-assert "make-ephemeron: too many arguments raises"
             (raises? (lambda () (make-ephemeron 'a 'b 'c))))
(test-assert "make-guardian: any argument raises"
             (raises? (lambda () (make-guardian 'x))))
(test-assert "make-transport-cell-guardian: any argument raises"
             (raises? (lambda () (make-transport-cell-guardian 'x))))
(test-assert "reference-barrier: zero arguments raises"
             (raises? (lambda () (reference-barrier))))
(test-assert "reference-barrier: two arguments raises"
             (raises? (lambda () (reference-barrier 1 2))))
(test-assert "current-hash: zero arguments raises"
             (raises? (lambda () (current-hash))))
(test-assert "current-hash: two arguments raises"
             (raises? (lambda () (current-hash 1 2))))
(test-assert "ephemeron-ref: one argument raises"
             (raises? (lambda () (ephemeron-ref e-api))))
;; ephemeron-ref is registered as `.variadic = 2` and re-checks the upper bound
;; itself; the message must still name the real 2-or-3 range.
(test-assert "ephemeron-ref: four arguments raises naming the 2-or-3 range"
             (let ((m (raised-message (lambda () (ephemeron-ref e-api 'k 'd 'extra)))))
               (and (string? m) (substring? "ephemeron-ref" m) (substring? "2 or 3" m))))

;; invokeGuardian's own arity and argument checks.
(test-assert "guardian: three arguments raises naming the 1-or-2 range"
             (let ((m (raised-message (lambda () (g-api 'a 'b 'c)))))
               (and (string? m) (substring? "guardian" m) (substring? "1 or 2" m))))
;; "obj should denote a location or a sequence of locations and rep should not
;; be #f" — Kaappi enforces both as errors rather than leaving them undefined.
(test-assert "guardian: #f as the guarded object raises"
             (raises? (lambda () (g-api #f))))
(test-assert "guardian: #f as the representative raises"
             (raises? (lambda () (g-api (list 'o) #f))))
(test-assert "guardian: a non-#f immediate object is accepted"
             (not (raises? (lambda () ((make-guardian) 42)))))
(test-assert "transport cell guardian: one argument raises"
             (raises? (lambda () (tg-api 'k))))
(test-assert "transport cell guardian: three arguments raises"
             (raises? (lambda () (tg-api 'k 'v 'extra))))
;; A transport cell guardian has no #f restriction of its own in the spec.
(test-assert "transport cell guardian: #f as key is accepted"
             (transport-cell? ((make-transport-cell-guardian) #f 'v)))

;; ---------------------------------------------------------------------------
;; 7. Guardian invocation at every call site (D5)
;;
;; A guardian is not a Closure, so every dispatch site in vm_dispatch.zig and
;; vm_calls.zig has to recognise it. These pin all of them.
;; ---------------------------------------------------------------------------

(define g-call (make-guardian))

(test-assert "call site: direct application"
             (not (raises? (lambda () (g-call (list 'direct))))))
(test-assert "call site: apply with one argument"
             (not (raises? (lambda () (apply g-call (list (list 'applied)))))))
(test-assert "call site: apply with no arguments returns a value"
             (not (raises? (lambda () (apply g-call '())))))
(test-assert "call site: map"
             (not (raises? (lambda () (map g-call (list (list 1) (list 2)))))))
(test-assert "call site: for-each"
             (not (raises? (lambda () (for-each g-call (list (list 3)))))))
(test-assert "call site: tail position inside a lambda"
             (not (raises? (lambda () ((lambda (x) (g-call x)) (list 'tail))))))
(test-assert "call site: call-with-values producer"
             (not (raises? (lambda () (call-with-values (lambda () (g-call)) list)))))
(test-assert "call site: dynamic-wind before thunk"
             (not (raises? (lambda ()
                             (dynamic-wind (lambda () (g-call (list 'wind)))
                                           (lambda () 'body)
                                           (lambda () 'after))))))
(test-assert "call site: inside a guard handler"
             (not (raises? (lambda ()
                             (guard (e (#t (g-call (list 'guarded)) 'handled))
                               (raise 'boom))))))
(test-assert "call site: inside a forced promise"
             (not (raises? (lambda () (force (delay (g-call (list 'delayed))))))))
(test-assert "call site: through a vector slot"
             (not (raises? (lambda () ((vector-ref (vector g-call) 0) (list 'vec))))))
(test-assert "call site: after a call/cc escape"
             (not (raises? (lambda ()
                             (call-with-current-continuation
                               (lambda (k) (g-call (list 'cc)) (k 'escaped)))))))
(test-assert "call site: guarding a guardian"
             (not (raises? (lambda () (g-call (make-guardian) 'inner-died)))))
(test-assert "call site: a guardian guarding itself"
             (not (raises? (lambda () (g-call g-call)))))
(test-assert "call site: inside a hash-table-walk callback"
             (not (raises? (lambda ()
                             (let ((h (make-hash-table)))
                               (hash-table-set! h 'a 1)
                               (hash-table-walk h (lambda (k v) (g-call (list k v)))))))))
(test-assert "call site: inside a fiber"
             (eq? 'fiber-done
                  (fiber-join (spawn (lambda () (g-call (list 'fiber)) 'fiber-done)))))

;; SRFI 181 custom-port callbacks run with vm.in_custom_port_callback set and
;; may not block. Registering with a guardian must stay legal there.
(test-equal "call site: inside a custom-port read! callback" #\A
            (let* ((done #f)
                   (port (make-custom-textual-input-port
                           "audit-cp"
                           (lambda (str start count)
                             (g-call (list 'from-read-callback))
                             (if done 0 (begin (set! done #t)
                                               (string-set! str start #\A) 1)))
                           #f #f (lambda () #f))))
              (let ((c (read-char port))) (close-port port) c)))
(test-assert "call site: transport cell guardian inside a custom-port write! callback"
             (not (raises?
                    (lambda ()
                      (let ((port (make-custom-textual-output-port
                                    "audit-cw"
                                    (lambda (str start count)
                                      ((make-transport-cell-guardian) (list 'k) 'v)
                                      count)
                                    #f #f (lambda () #f))))
                        (write-string "hi" port)
                        (close-port port))))))

;; ---------------------------------------------------------------------------
;; 8. Cross-heap deep copy (D6)
;;
;; gc_deep_copy.zig refuses ephemeron / guardian / transport_cell outright.
;; Both SRFI-18 boundaries must fail cleanly (a catchable error), never abort.
;; ---------------------------------------------------------------------------

;; OUT: a lexically captured value is deep-copied into the child at
;; thread-start!, so the thunk must fail rather than smuggle a foreign pointer.
(define (out-fails? make)
  (let ((obj (make)))
    (raises? (lambda ()
               (let ((t (make-thread (lambda () (if obj 1 2)))))
                 (thread-start! t)
                 (thread-join! t))))))

(test-assert "deep copy OUT: a captured ephemeron fails cleanly"
             (out-fails? (lambda () (make-ephemeron (list 1) (list 2)))))
(test-assert "deep copy OUT: a captured guardian fails cleanly"
             (out-fails? (lambda () (make-guardian))))
(test-assert "deep copy OUT: a captured transport cell guardian fails cleanly"
             (out-fails? (lambda () (make-transport-cell-guardian))))
(test-assert "deep copy OUT: a captured transport cell fails cleanly"
             (out-fails? (lambda () ((make-transport-cell-guardian) (list 1) (list 2)))))

;; IN: the child's result is deep-copied back at thread-join!.
(define (in-fails? thunk)
  (raises? (lambda ()
             (let ((t (make-thread thunk)))
               (thread-start! t)
               (thread-join! t)))))

(test-assert "deep copy IN: returning an ephemeron fails cleanly"
             (in-fails? (lambda () (make-ephemeron (list 1) (list 2)))))
(test-assert "deep copy IN: returning a guardian fails cleanly"
             (in-fails? (lambda () (make-guardian))))
(test-assert "deep copy IN: returning a transport cell guardian fails cleanly"
             (in-fails? (lambda () (make-transport-cell-guardian))))
(test-assert "deep copy IN: returning a transport cell fails cleanly"
             (in-fails? (lambda () ((make-transport-cell-guardian) (list 1) (list 2)))))
(test-assert "deep copy IN: a guardian nested in a list still fails cleanly"
             (in-fails? (lambda () (list 1 (make-guardian) 3))))
(test-assert "deep copy IN: an ephemeron nested in a vector still fails cleanly"
             (in-fails? (lambda () (vector (make-ephemeron 'a 'b)))))
;; Control: an ordinary heap value crosses both boundaries.
(test-equal "deep copy IN: control — a plain list round-trips" '(1 2 3)
            (let ((t (make-thread (lambda () (list 1 2 3)))))
              (thread-start! t)
              (thread-join! t)))

;; A guardian reached through the GLOBALS route is *not* deep-copied: top-level
;; bindings are shared by pointer (docs/dev/thread-value-sharing.md), so a child
;; gets the parent's own guardian object. invokeGuardian therefore carries the
;; same Object.owner check channels (primitives_fiber.zig) and thread handles
;; (primitives_srfi18.checkThreadOwner) do (#2008). Without it, the first shape
;; below left a dangling watched pointer (silent #f in ReleaseSafe, a
;; type-confused live object under -Dgc-stress) and the second aborted the
;; process outright — exit 133/134, empty stdout, empty stderr.
(define uaf-g (make-guardian))
(test-equal "cross-heap: a child registering into a parent's guardian is refused"
            'refused
            (let ((t (make-thread (lambda ()
                                    (guard (e (#t 'refused))
                                      (uaf-g (vector 'child)) 'registered)))))
              (thread-start! t)
              (thread-join! t)))
(test-assert "cross-heap: the refused registration left nothing behind"
             (begin (churn-rounds! 4) (not (uaf-g))))
(test-assert "cross-heap: the refusal names the ownership rule"
             (let ((t (make-thread
                       (lambda ()
                         (substring? "another thread"
                                     (or (raised-message (lambda () (uaf-g (list 'x)))) ""))))))
               (thread-start! t)
               (thread-join! t)))
(define race-g (make-guardian))
(test-equal "cross-heap: concurrent registration on one guardian is refused, not aborted"
            'refused
            (let ((t (make-thread (lambda ()
                                    (guard (e (#t 'refused))
                                      (do ((i 0 (+ i 1))) ((= i 2000)) (race-g (list 'c i)))
                                      'done)))))
              (thread-start! t)
              (do ((i 0 (+ i 1))) ((= i 2000)) (race-g (list 'p i)))
              (thread-join! t)))
;; The retrieve path is checked by the same guard, ahead of both branches.
(test-equal "cross-heap: a child *reading* a parent's guardian is refused too"
            'refused
            (let ((t (make-thread (lambda () (guard (e (#t 'refused)) (race-g))))))
              (thread-start! t)
              (thread-join! t)))
;; A transport cell guardian takes the same append path and is refused alike.
(define race-tg (make-transport-cell-guardian))
(test-equal "cross-heap: a shared transport cell guardian is refused"
            'refused
            (let ((t (make-thread (lambda () (guard (e (#t 'refused)) (race-tg 'k 'v) 'made)))))
              (thread-start! t)
              (thread-join! t)))

;; Control for the pair above: one guardian per thread, no sharing, is safe —
;; which is what identifies the shared-guardian case as the defect.
(test-equal "cross-heap control: a per-thread guardian is safe under contention" 'done
            (let ((t (make-thread (lambda ()
                                    (let ((h (make-guardian)))
                                      (do ((i 0 (+ i 1))) ((= i 500)) (h (list 'c i)))
                                      'done)))))
              (thread-start! t)
              (let ((own (make-guardian)))
                (do ((i 0 (+ i 1))) ((= i 500)) (own (list 'p i))))
              (thread-join! t)))

;; ---------------------------------------------------------------------------
;; 9. Register every collection-dependent scenario, then force collection once
;; ---------------------------------------------------------------------------

;; --- ephemerons ---
(define live-key (list 'live))
(define eph-live (make-ephemeron live-key 'kept))         ; key stays reachable
(define eph-dead (make-ephemeron (list 'dead) 'gone))     ; key only via the ephemeron
(define eph-cycle (let ((k (list 'cyclic))) (make-ephemeron k (list k))))
(define eph-self (let ((k (list 'self))) (make-ephemeron k k)))
(define eph-fixnum (make-ephemeron 42 'imm-fix))          ; immediate keys have
(define eph-char (make-ephemeron #\x 'imm-char))          ; no heap identity and
(define eph-true (make-ephemeron #t 'imm-true))           ; can never be reclaimed
(define eph-nil (make-ephemeron '() 'imm-nil))

;; A two-link ephemeron chain: e-chain-1's VALUE is e-chain-2's KEY.
(define e-chain-dead-1 #f) (define e-chain-dead-2 #f)
(let* ((k1 (list 'ck1)) (k2 (list 'ck2)))
  (set! e-chain-dead-2 (make-ephemeron k2 (list 'cv2)))
  (set! e-chain-dead-1 (make-ephemeron k1 k2)))
(define chain-live-key (list 'lk1))
(define e-chain-live-1 #f) (define e-chain-live-2 #f)
(let ((k2 (list 'lk2)))
  (set! e-chain-live-2 (make-ephemeron k2 (list 'lv2)))
  (set! e-chain-live-1 (make-ephemeron chain-live-key k2)))

;; --- guardians ---
(define g-dead (make-guardian))
(g-dead (list 'finalize-me))
(define g-keep (make-guardian))
(define keep-alive (list 'keep))
(g-keep keep-alive)
(define g-rep (make-guardian))
(g-rep (list 'obj) 'representative)
(define g-imm (make-guardian))
(g-imm 42)                                      ; immediate: no location to reclaim

;; An ephemeron keyed on an object a guardian will resurrect in the same cycle.
(define g-resurrect (make-guardian))
(define eph-on-guarded #f)
(let ((o (list 'guarded)))
  (g-resurrect o)
  (set! eph-on-guarded (make-ephemeron o (list 'still-here))))

;; Two independent guardians watching one object.
(define g-two-a (make-guardian))
(define g-two-b (make-guardian))
(let ((o (list 'watched-twice))) (g-two-a o) (g-two-b o))

;; A transport cell guardian and an object guardian watching one object.
(define g-vs-tcg (make-guardian))
(define tcg-pin (make-transport-cell-guardian))
(define tcg-pin-cell #f)
(let ((o (list 'tcg-keyed)))
  (g-vs-tcg o)
  (set! tcg-pin-cell (tcg-pin o 'cell-value)))
;; Control: the same shape without the transport cell registration.
(define g-vs-nothing (make-guardian))
(let ((o (list 'not-tcg-keyed))) (g-vs-nothing o))

;; A transport cell whose key is otherwise unreachable.
(define tcg-orphan (make-transport-cell-guardian))
(define tcg-orphan-cell (tcg-orphan (list 'orphan-key) 'orphan-value))

(churn-rounds! 4)

;; ---------------------------------------------------------------------------
;; 10. Ephemeron semantics after collection
;;
;; "the ephemeron is broken in the course of the computation if the garbage
;; collector would reclaim the location or sequence of locations if the
;; locations denoted by the value fields of all (this and any other) ephemerons
;; were weakly holding."
;; ---------------------------------------------------------------------------

(test-assert "GC: an ephemeron with a reachable key is not broken"
             (not (ephemeron-broken? eph-live)))
(test-equal "GC: a reachable key still resolves through ephemeron-ref" 'kept
            (ephemeron-ref eph-live live-key))
(test-assert "GC: the key field is preserved by identity, not copied"
             (eq? live-key (ephemeron-key eph-live)))

(test-assert "GC: an ephemeron whose key is unreachable is broken"
             (ephemeron-broken? eph-dead))
;; Abstract: "Breaking an ephemeron replaces the key and value with #f."
(test-assert "GC: a broken ephemeron reports #f as its key"
             (not (ephemeron-key eph-dead)))
(test-assert "GC: a broken ephemeron reports #f as its value"
             (not (ephemeron-value eph-dead)))
;; "returns ... default otherwise" — a broken ephemeron always takes the default.
(test-equal "GC: ephemeron-ref on a broken ephemeron returns the default" 'dflt
            (ephemeron-ref eph-dead 'anything 'dflt))
(test-assert "GC: ephemeron-ref on a broken ephemeron with no default returns #f"
             (not (ephemeron-ref eph-dead 'anything)))

;; The case a weak-key pair gets wrong: the value references the key, so a weak
;; pair would keep the entry alive forever. An ephemeron must still break.
(test-assert "GC: an ephemeron whose value references its key still breaks"
             (ephemeron-broken? eph-cycle))
(test-assert "GC: an ephemeron whose key IS its value still breaks"
             (ephemeron-broken? eph-self))

;; Immediates denote no location, so they can never be reclaimed.
(test-assert "GC: a fixnum-keyed ephemeron never breaks"  (not (ephemeron-broken? eph-fixnum)))
(test-assert "GC: a char-keyed ephemeron never breaks"    (not (ephemeron-broken? eph-char)))
(test-assert "GC: a #t-keyed ephemeron never breaks"      (not (ephemeron-broken? eph-true)))
(test-assert "GC: a '()-keyed ephemeron never breaks"     (not (ephemeron-broken? eph-nil)))
(test-equal "GC: a fixnum-keyed ephemeron still resolves" 'imm-fix
            (ephemeron-ref eph-fixnum 42))

;; Chains: the whole-chain answer must be consistent, in both directions. This
;; is what distinguishes a real fixpoint from a single pass.
(test-assert "GC: a dead chain's first link breaks"  (ephemeron-broken? e-chain-dead-1))
;; A broken ephemeron's value must not keep the next key alive.
(test-assert "GC: a dead chain's second link breaks too"
             (ephemeron-broken? e-chain-dead-2))
(test-assert "GC: a live chain's first link survives" (not (ephemeron-broken? e-chain-live-1)))
;; A live ephemeron's value does keep the next key alive.
(test-assert "GC: a live chain's second link survives"
             (not (ephemeron-broken? e-chain-live-2)))
(test-equal "GC: the live chain's second value is intact" '(lv2)
            (ephemeron-value e-chain-live-2))

;; ---------------------------------------------------------------------------
;; 11. Guardian semantics after collection
;;
;; "the element is resurrected in the course of the computation when the garbage
;; collector would reclaim the location or sequence of locations if all
;; locations denoted by the fields of guarded elements or by resurrected
;; elements of all guardians were weakly resurrected."
;; ---------------------------------------------------------------------------

(test-equal "GC: an unreachable guarded object is resurrected" 'finalize-me
            (let ((got (g-dead))) (and (pair? got) (car got))))
(test-assert "GC: the guardian is empty again after the retrieval" (not (g-dead)))
(test-assert "GC: a still-reachable guarded object is not resurrected" (not (g-keep)))
(test-assert "GC: the still-reachable object is untouched" (equal? '(keep) keep-alive))
;; "Instead of the object itself, a representative can be returned."
(test-equal "GC: the two-argument form yields the representative, not the object"
            'representative (g-rep))
;; An immediate denotes no location, so nothing can ever be reclaimed for it.
(test-assert "GC: a guarded immediate is never resurrected" (not (g-imm)))

;; Resurrection makes the key reachable again, so an ephemeron keyed on it must
;; survive — and the fixpoint must run ephemerons after guardians make progress.
(test-assert "GC: an ephemeron keyed on a resurrected object is not broken"
             (not (ephemeron-broken? eph-on-guarded)))
(test-equal "GC: that ephemeron's value survived intact" '(still-here)
            (ephemeron-value eph-on-guarded))
(test-assert "GC: the resurrected object and the ephemeron key are the same object"
             (eq? (ephemeron-key eph-on-guarded) (g-resurrect)))

;; --- Two guardians watching one object -------------------------------------
;;
;; The spec's hypothetical makes "resurrected elements of all guardians" weak,
;; so both elements must be resurrected. Kaappi resurrects one and marks the
;; watched object strongly (gc_collect.markGuardianStrong marks every ready
;; entry in the strong phase), so the other guardian's probe sees a reachable
;; object and starves for as long as the first holds it. See #2011.
(test-equal "GC: exactly one of two guardians watching one object fires (#2011)"
            1
            (let ((a (g-two-a)) (b (g-two-b)))
              (+ (if a 1 0) (if b 1 0))))
;;
;; FAIL: #2011 (a second guardian watching the same object never resurrects it)
;; (test-equal "GC: spec — both guardians watching one object fire"
;;             2
;;             (let ((a (g-two-a)) (b (g-two-b)))
;;               (+ (if a 1 0) (if b 1 0))))

;; ---------------------------------------------------------------------------
;; 12. Transport cell guardians after collection
;;
;; Spec: "The content of the key field is stored in a weakly holding location."
;; and "the transport cell is broken in the course of the computation when the
;; garbage collector reclaims the location or sequence of locations."
;;
;; Kaappi marks a transport cell guardian's registered cells — and their keys —
;; strongly (gc_collect.markGuardianStrong), so no cell ever breaks and no key
;; is ever reclaimed. See #2006.
;; ---------------------------------------------------------------------------

;; "When guardian is invoked on no arguments and it contains a transport cell
;; whose key may have been moved ... If guardian contains no such transport
;; cell, #f is returned."  Kaappi never moves objects, so #f is the right answer.
(test-assert "GC: a transport cell guardian yields nothing on a non-moving collector"
             (not (tcg-pin)))
(test-assert "GC: an orphaned transport cell guardian also yields nothing"
             (not (tcg-orphan)))

;; Current behaviour, pinned so a fix flips a visible test.
(test-assert "GC: a transport cell whose key is unreachable is NOT broken (#2006)"
             (not (transport-cell-broken? tcg-orphan-cell)))
(test-equal "GC: its key is retained verbatim instead (#2006)" '(orphan-key)
            (transport-cell-key tcg-orphan-cell))
(test-assert "GC: a transport cell key blocks an object guardian (#2006)"
             (not (g-vs-tcg)))
;; The discriminating control: the same shape without a transport cell fires.
(test-equal "GC: control — without the transport cell the guardian does fire"
            'not-tcg-keyed
            (let ((got (g-vs-nothing))) (and (pair? got) (car got))))
;;
;; FAIL: #2006 (a transport cell key is held strongly, so the cell never breaks)
;; (test-assert "GC: spec — a transport cell with an unreachable key is broken"
;;              (transport-cell-broken? tcg-orphan-cell))
;;
;; FAIL: #2006 (a weakly-held transport cell key must not block resurrection)
;; (test-equal "GC: spec — a transport cell key does not block an object guardian"
;;             'tcg-keyed
;;             (let ((got (g-vs-tcg))) (and (pair? got) (car got))))

;; The cell's own value field is strong in the spec too, so it survives here
;; for the right reason regardless.
(test-equal "GC: a transport cell's value field survives collection" 'orphan-value
            (transport-cell-value tcg-orphan-cell))
(test-assert "GC: the cell registered alongside an object guardian is intact"
             (and (transport-cell? tcg-pin-cell)
                  (not (transport-cell-broken? tcg-pin-cell))))

;; ---------------------------------------------------------------------------
;; 13. A second collection round — nothing regresses, and draining unblocks
;; ---------------------------------------------------------------------------

;; Draining the guardian that won the race releases the object, so the starved
;; guardian fires on the next collection. Order-independent: whichever of the
;; two fired above was drained by that assertion.
(churn-rounds! 3)
(test-equal "GC: the starved guardian fires once the winner has been drained"
            1
            (let ((a (g-two-a)) (b (g-two-b)))
              (+ (if a 1 0) (if b 1 0))))

(test-assert "GC: a live-key ephemeron is still unbroken after more collections"
             (not (ephemeron-broken? eph-live)))
(test-assert "GC: a broken ephemeron stays broken" (ephemeron-broken? eph-dead))
(test-equal "GC: current-hash is stable across collections" ch-h0 (current-hash ch-obj))
(test-assert "GC: an already-drained guardian keeps returning #f" (not (g-dead)))
(test-assert "GC: reference-barrier still works after collection"
             (not (raises? (lambda () (reference-barrier ch-obj)))))

(let ((runner (test-runner-current)))
  (test-end "primitives_srfi254 audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
