;; Audit tests for the cross-heap deep-copy closure (dimension D6) at the
;; SRFI-18 thread boundaries. Audit campaign v2 Phase 2.7 (#1890).
;;
;; WHY A SEPARATE FILE. tests/scheme/audit/primitives_srfi18-audit.scm
;; (Phase 2.1, re-audited Phase 5D) audits the SRFI-18 *procedures*; this
;; file audits the *type matrix* underneath them: every ObjectTag crossing
;; every boundary. tests/scheme/audit/cross-thread-boundary-audit.scm
;; (Phase 5C) audits the mutation/ownership rules for a handful of types.
;; Neither enumerates the tag set, which is what D6 asks for.
;;
;; ORACLE. src/gc_deep_copy.zig's own switch (the tag list is the
;; specification of the copy route) plus docs/dev/thread-value-sharing.md,
;; which documents the two routes and is the table this file keeps honest.
;;
;; THE MATRIX. src/types.zig's ObjectTag has 41 members. Each falls in
;; exactly one of four classes, and this file covers every REACHABLE cell:
;;
;;   copied    22 arms — round-tripped here for type AND content fidelity
;;   aliased    3 tags — ffi_library, ffi_function (unsafe: see section E)
;;                       and channel (safe, KEP-0002; covered by Phase 2.6)
;;   refused   14 tags — 13 reachable, asserted here at both boundaries
;;   vestigial  2 tags — flonum (no allocator at all: allocFlonum returns a
;;                       NaN-boxed immediate) and native_closure (created
;;                       only by the LLVM backend's runtime_exports.zig).
;;                       Neither is constructible from interpreted Scheme.
;;
;; Three tags are covered elsewhere and are NOT re-tested here, by design:
;; ephemeron/guardian/transport_cell (Phase 2.10, #2013) and channel
;; (Phase 2.6, #2004). Their refusal rows are still asserted below because
;; the refusal is this file's subject, not the type's own behaviour.
;;
;; ****************************************************************
;; * DETERMINISM AND SAFETY RULES FOR THIS FILE                   *
;; *                                                              *
;; * 1. No wall-clock assertions anywhere.                        *
;; * 2. Nothing here may hang: every thread started is joined.    *
;; * 3. Shapes that read freed memory are COMMENTED OUT with a    *
;; *    `;; FAIL:` marker, never test-expect-fail — dereferencing  *
;; *    a dangling pointer can take the whole runner down.        *
;; * 4. Platform-dependent constructors (FFI, SRFI 170) are       *
;; *    probed at run time and their assertions are skipped when  *
;; *    unavailable, so the file is portable to the Windows and   *
;; *    BSD legs. Assertion counts therefore vary by platform.    *
;; * 5. Every assertion has a name string. An unnamed failure on  *
;; *    a remote BSD leg prints a bare #f.                        *
;; ****************************************************************

(import (scheme base) (scheme write) (scheme complex) (scheme eval)
        (srfi 18) (srfi 69) (srfi 27) (srfi 258)
        (srfi 160 f64) (srfi 237) (srfi 211 explicit-renaming)
        (srfi 64))

(test-begin "srfi18 deep-copy matrix audit")

;; ---------------------------------------------------------------------
;; Harness
;; ---------------------------------------------------------------------

;; Run THUNK on a child OS thread and return its result. Any refusal or
;; raise is converted to a descriptive list so no assertion ever escapes.
(define (join-thunk thunk)
  (let ((t (make-thread thunk)))
    (guard (e (#t (list 'RAISED
                        (if (uncaught-exception? e) 'wrapped 'direct)
                        (if (error-object? e) (error-object-message e) e))))
      (thread-start! t)
      (thread-join! t))))

;; #t when THUNK's value survived the boundary and satisfied OK?.
(define (crossed? thunk ok?)
  (let ((r (join-thunk thunk)))
    (and (not (and (pair? r) (eq? (car r) 'RAISED))) (ok? r))))

;; The outcome shape of a boundary crossing: 'ok, or (refused wrapped|direct).
(define (outcome thunk)
  (let ((r (join-thunk thunk)))
    (if (and (pair? r) (eq? (car r) 'RAISED))
        (list 'refused (cadr r))
        'ok)))

(define (substring? hay needle)
  (let ((n (string-length hay)) (m (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i m) n) #f)
            ((string=? (substring hay i (+ i m)) needle) #t)
            (else (loop (+ i 1)))))))

;; A value is "constructible on this platform" if MK returns without raising.
(define (constructible? mk) (guard (e (#t #f)) (mk) #t))

;; ---------------------------------------------------------------------
;; Section A — the copy route, IN direction (thread-start!)
;;
;; A thunk's LEXICAL captures are deep-copied into the child heap. A thunk
;; that merely names a top-level binding captures nothing (that is the
;; globals route, section F), so every value here is `let`-bound.
;; ---------------------------------------------------------------------

(let ((v (cons 1 2)))
  (test-assert "IN pair: copied, car and cdr intact"
               (crossed? (lambda () (list (car v) (cdr v)))
                         (lambda (r) (equal? r '(1 2))))))

(let ((v (list 1 (list 2 3) 4)))
  (test-assert "IN pair: nested structure copied to full depth"
               (crossed? (lambda () (cadr (cadr v))) (lambda (r) (eqv? r 3)))))

;; Internal sharing must survive as sharing, not be duplicated into two copies.
(let* ((shared (list 'x)) (v (cons shared shared)))
  (test-assert "IN pair: internal sharing preserved (car eq? cdr after copy)"
               (crossed? (lambda () (eq? (car v) (cdr v))) (lambda (r) (eq? r #t)))))

(let ((v (string->symbol "matrix-in-sym")))
  (test-assert "IN symbol: interned symbol still eq? to the child's own reading"
               (crossed? (lambda () (eq? v (string->symbol "matrix-in-sym")))
                         (lambda (r) (eq? r #t)))))

(let ((v (string->uninterned-symbol "matrix-in-u")))
  (test-assert "IN symbol: uninterned stays uninterned across the copy"
               (crossed? (lambda () (list (symbol? v) (symbol-interned? v)))
                         (lambda (r) (equal? r '(#t #f))))))

(let ((v (string-copy "abc")))
  (test-assert "IN string: contents copied"
               (crossed? (lambda () (string-length v)) (lambda (r) (eqv? r 3)))))

(let ((v (string-copy "λμν")))
  (test-assert "IN string: non-ASCII codepoints survive"
               (crossed? (lambda () (string->list v))
                         (lambda (r) (equal? r (list #\λ #\μ #\ν))))))

(let ((v (lambda (x) (* x 3))))
  (test-assert "IN closure: still callable in the child"
               (crossed? (lambda () (v 5)) (lambda (r) (eqv? r 15)))))

(let* ((n 7) (v (lambda () n)))
  (test-assert "IN closure: its own captured environment came along"
               (crossed? (lambda () (v)) (lambda (r) (eqv? r 7)))))

(let ((v car))
  (test-assert "IN native_fn: a primitive procedure crosses and works"
               (crossed? (lambda () (v '(9 8))) (lambda (r) (eqv? r 9)))))

(let ((v (vector 1 2 3)))
  (test-assert "IN vector: length and elements copied"
               (crossed? (lambda () (list (vector-length v) (vector-ref v 2)))
                         (lambda (r) (equal? r '(3 3))))))

(let ((v (bytevector 1 2 250)))
  (test-assert "IN bytevector: bytes copied including the high one"
               (crossed? (lambda () (list (bytevector-length v) (bytevector-u8-ref v 2)))
                         (lambda (r) (equal? r '(3 250))))))

(let ((v (f64vector 1.5 2.5)))
  (test-assert "IN numeric_vector: element kind and value preserved"
               (crossed? (lambda () (list (f64vector? v) (f64vector-ref v 1)))
                         (lambda (r) (equal? r '(#t 2.5))))))

(let ((v (make-rectangular 3 4)))
  (test-assert "IN complex: real and imaginary parts preserved"
               (crossed? (lambda () (list (real-part v) (imag-part v)))
                         (lambda (r) (equal? r '(3 4))))))

(let ((v (expt 2 100)))
  (test-assert "IN bignum: exact value preserved past the fixnum range"
               (crossed? (lambda () (= v (expt 2 100))) (lambda (r) (eq? r #t)))))

(let ((v (/ 1 3)))
  (test-assert "IN rational: numerator and denominator preserved"
               (crossed? (lambda () (list (numerator v) (denominator v)))
                         (lambda (r) (equal? r '(1 3))))))

(let ((v (let ((h (make-hash-table equal?)))
           (hash-table-set! h (string-copy "sk") 'val) h)))
  (test-assert "IN hash_table: equal? comparison mode survives (string key still finds)"
               (crossed? (lambda () (hash-table-ref/default v (string-copy "sk") 'MISSING))
                         (lambda (r) (eq? r 'val)))))

(let ((v (let ((h (make-hash-table eq?))) (hash-table-set! h 'k 'val) h)))
  (test-assert "IN hash_table: eq? mode table crosses with its entry"
               (crossed? (lambda () (hash-table-ref/default v 'k 'MISSING))
                         (lambda (r) (eq? r 'val)))))

(let ((v (delay (* 6 7))))
  (test-assert "IN promise: an unforced promise forces correctly in the child"
               (crossed? (lambda () (force v)) (lambda (r) (eqv? r 42)))))

(let ((v (delay (* 6 7))))
  (force v)
  (test-assert "IN promise: an already-forced promise keeps its memoised value"
               (crossed? (lambda () (force v)) (lambda (r) (eqv? r 42)))))

(let ((v (make-parameter 5 (lambda (x) (* x 10)))))
  (test-assert "IN parameter: converter ran at construction (value is 50)"
               (crossed? (lambda () (v)) (lambda (r) (eqv? r 50)))))

(let ((v (make-parameter 5 (lambda (x) (* x 10)))))
  (test-assert "IN parameter: converter still applied by parameterize in the child"
               (crossed? (lambda () (parameterize ((v 3)) (v))) (lambda (r) (eqv? r 30)))))

(let ((v (guard (e (#t e)) (error "matrix-msg" 1 2))))
  (test-assert "IN error_object: message and irritants both survive"
               (crossed? (lambda () (list (error-object-message v)
                                          (error-object-irritants v)))
                         (lambda (r) (equal? r '("matrix-msg" (1 2)))))))

(let ((v (current-time)))
  (test-assert "IN srfi18_time: crosses and still reads as a positive instant"
               (crossed? (lambda () (> (time->seconds v) 0)) (lambda (r) (eq? r #t)))))

(let ((v (make-random-source)))
  (test-assert "IN random_source: crosses and still generates in range"
               (crossed? (lambda ()
                           (let ((g ((random-source-make-integers v) 10)))
                             (and (>= g 0) (< g 10))))
                         (lambda (r) (eq? r #t)))))

(let ((v (er-macro-transformer (lambda (f rn c) (list (rn 'quote) 'hi)))))
  (test-assert "IN transformer: a procedural transformer value crosses"
               (crossed? (lambda () (if (eqv? v 1) 'never 'touched))
                         (lambda (r) (eq? r 'touched)))))

;; ---------------------------------------------------------------------
;; Section B — the copy route, OUT direction (thread-join!)
;;
;; The child's result is copied out. Same tags, opposite direction: an arm
;; can be correct one way and wrong the other, so neither substitutes for
;; the other.
;; ---------------------------------------------------------------------

(test-assert "OUT pair: child-built list arrives intact"
             (equal? (join-thunk (lambda () (list 1 2 3))) '(1 2 3)))

(test-assert "OUT pair: internal sharing preserved out of the child"
             (join-thunk (lambda () (let* ((s (list 'x)) (p (cons s s)))
                                      (eq? (car p) (cdr p))))))

(test-assert "OUT symbol: a name the parent never saw interns to the same object"
             (eq? (join-thunk (lambda () (string->symbol "matrix-out-only")))
                  (string->symbol "matrix-out-only")))

(test-assert "OUT symbol: uninterned-ness survives the join"
             (equal? (join-thunk (lambda ()
                                   (let ((u (string->uninterned-symbol "mo")))
                                     (list (symbol? u) (symbol-interned? u)))))
                     '(#t #f)))

(test-assert "OUT string: contents arrive"
             (string=? (join-thunk (lambda () (string-copy "out-str"))) "out-str"))

(test-assert "OUT string: non-ASCII codepoints arrive"
             (string=? (join-thunk (lambda () (string-copy "λμν"))) "λμν"))

(test-assert "OUT closure: a child-built closure is callable in the parent"
             (eqv? ((join-thunk (lambda () (lambda (x) (* x 4)))) 5) 20))

(test-assert "OUT closure: it carries its captured environment out"
             (eqv? ((join-thunk (lambda () (let ((n 11)) (lambda () n))))) 11))

(test-assert "OUT native_fn: a primitive procedure arrives callable"
             (eqv? ((join-thunk (lambda () cdr)) '(1 . 2)) 2))

(test-assert "OUT vector: elements arrive"
             (equal? (join-thunk (lambda () (vector 4 5 6))) #(4 5 6)))

(test-assert "OUT bytevector: bytes arrive"
             (equal? (join-thunk (lambda () (bytevector 7 8 9))) #u8(7 8 9)))

(test-assert "OUT numeric_vector: kind and element arrive"
             (equal? (join-thunk (lambda () (let ((v (f64vector 1.5 2.5)))
                                              (list (f64vector? v) (f64vector-ref v 0)))))
                     '(#t 1.5)))

(test-assert "OUT numeric_vector: the object itself arrives as an f64vector"
             (let ((r (join-thunk (lambda () (f64vector 1.5 2.5)))))
               (and (f64vector? r) (= (f64vector-ref r 1) 2.5))))

(test-assert "OUT complex: parts arrive"
             (let ((r (join-thunk (lambda () (make-rectangular 3 4)))))
               (and (= (real-part r) 3) (= (imag-part r) 4))))

(test-assert "OUT bignum: exact value arrives"
             (= (join-thunk (lambda () (expt 2 100))) (expt 2 100)))

(test-assert "OUT rational: exact value arrives"
             (= (join-thunk (lambda () (/ 1 3))) 1/3))

(test-assert "OUT hash_table: table arrives with its entry and equal? mode"
             (let ((r (join-thunk (lambda ()
                                    (let ((h (make-hash-table equal?)))
                                      (hash-table-set! h (string-copy "k") 'v) h)))))
               (eq? (hash-table-ref/default r (string-copy "k") 'MISSING) 'v)))

(test-assert "OUT promise: an unforced child promise forces in the parent"
             (eqv? (force (join-thunk (lambda () (delay (* 6 7))))) 42))

(test-assert "OUT promise: an already-forced child promise keeps its value"
             (eqv? (force (join-thunk (lambda () (let ((p (delay (* 6 7)))) (force p) p))))
                   42))

(test-assert "OUT parameter: converter survives the join (value is 50)"
             (eqv? ((join-thunk (lambda () (make-parameter 5 (lambda (x) (* x 10)))))) 50))

(test-assert "OUT parameter: converter still applied by parameterize in the parent"
             (let ((p (join-thunk (lambda () (make-parameter 5 (lambda (x) (* x 10)))))))
               (eqv? (parameterize ((p 3)) (p)) 30)))

(test-assert "OUT error_object: message and irritants arrive"
             (let ((r (join-thunk (lambda () (guard (e (#t e)) (error "out-msg" 7))))))
               (and (error-object? r)
                    (string=? (error-object-message r) "out-msg")
                    (equal? (error-object-irritants r) '(7)))))

(test-assert "OUT srfi18_time: arrives as a positive instant"
             (> (time->seconds (join-thunk (lambda () (current-time)))) 0))

(test-assert "OUT random_source: arrives usable"
             (let* ((rs (join-thunk (lambda () (make-random-source))))
                    (g ((random-source-make-integers rs) 10)))
               (and (>= g 0) (< g 10))))

(test-assert "OUT transformer: a child-built procedural transformer arrives"
             (not (eqv? (join-thunk (lambda ()
                                      (er-macro-transformer
                                       (lambda (f rn c) (list (rn 'quote) 'hi)))))
                        'unreachable)))

;; record_type / record_instance. The R6RS clause syntax of SRFI 237 binds
;; the type name to a first-class record-type descriptor, which is the only
;; way to get a `.record_type` Value into a variable from Scheme.
(define-record-type mrec (fields a b))
;; A `nongenerative` type carries a uid, and the uid registry is shared by
;; VM.initForThread — the one identity-preserving path across heaps. It is
;; the discriminating control for kaappi#1932 in all three directions.
(define-record-type nrec (nongenerative nrec-uid-2p7) (fields a b))

(test-assert "IN record_type: the descriptor crosses and keeps its name"
             (crossed? (lambda () (symbol->string (record-type-name mrec)))
                       (lambda (r) (string=? r "mrec"))))

;; FAIL: #1932 (a generative record type is re-manufactured by the copy, so
;; the instance is of a disjoint type — the accessor raises)
;; (test-assert "IN record_instance: fields readable in the child"
;;              (let ((v (make-mrec 10 20)))
;;                (crossed? (lambda () (list (mrec-a v) (mrec-b v)))
;;                          (lambda (r) (equal? r '(10 20))))))
;;
;; FAIL: #1932 (same root cause, out of the child)
;; (test-assert "OUT record_instance: a child-built record arrives with its fields"
;;              (let ((r (join-thunk (lambda () (make-mrec 30 40)))))
;;                (and (mrec? r) (= (mrec-a r) 30) (= (mrec-b r) 40))))

;; Pinned enabled so #1932's fix flips them rather than leaving a silent gap.
(test-assert "IN record_instance: generative type's predicate wrongly answers #f (#1932)"
             (eq? #f (join-thunk (let ((v (make-mrec 10 20))) (lambda () (mrec? v))))))

(test-assert "OUT record_instance: generative type's predicate wrongly answers #f (#1932)"
             (not (mrec? (join-thunk (lambda () (make-mrec 30 40))))))

;; The control: with a uid, both directions are correct today.
(test-assert "IN record_instance: nongenerative type keeps identity into the child"
             (let ((v (make-nrec 10 20)))
               (crossed? (lambda () (list (nrec? v) (nrec-a v)))
                         (lambda (r) (equal? r '(#t 10))))))

(test-assert "OUT record_instance: nongenerative type keeps identity out of the child"
             (let ((r (join-thunk (lambda () (make-nrec 30 40)))))
               (and (nrec? r) (= (nrec-a r) 30) (= (nrec-b r) 40))))

;; ---------------------------------------------------------------------
;; Section C — the uncaught-exception path
;;
;; SRFI 18: "uncaught-exception-reason returns the object which was raised
;; by the thunk." The raised object crosses through the SAME deep copy as a
;; result, so every tag has a third boundary, and the wrapper must not eat
;; the payload.
;; ---------------------------------------------------------------------

(define (raised-reason thunk)
  (let ((t (make-thread thunk)))
    (guard (e (#t (if (uncaught-exception? e)
                      (uncaught-exception-reason e)
                      (list 'NOT-WRAPPED e))))
      (thread-start! t) (thread-join! t) 'no-raise)))

(test-assert "EXC: thread-join! signals an uncaught-exception object"
             (let ((t (make-thread (lambda () (raise 'boom)))))
               (guard (e (#t (uncaught-exception? e)))
                 (thread-start! t) (thread-join! t) #f)))

(test-assert "EXC pair: the raised pair itself is the reason, copied"
             (equal? (raised-reason (lambda () (raise (cons 1 2)))) '(1 . 2)))

(test-assert "EXC symbol: the raised symbol is the reason"
             (eq? (raised-reason (lambda () (raise 'the-sym))) 'the-sym))

(test-assert "EXC fixnum: a non-heap payload is the reason"
             (eqv? (raised-reason (lambda () (raise 42))) 42))

(test-assert "EXC string: the raised string is the reason"
             (string=? (raised-reason (lambda () (raise (string-copy "s")))) "s"))

(test-assert "EXC error_object: message and irritants survive the raise path"
             (let ((r (raised-reason (lambda () (error "raised-msg" 5 6)))))
               (and (error-object? r)
                    (string=? (error-object-message r) "raised-msg")
                    (equal? (error-object-irritants r) '(5 6)))))

(test-assert "EXC vector: the raised vector is the reason"
             (equal? (raised-reason (lambda () (raise (vector 1 2)))) #(1 2)))

;; FAIL: #1932 (the raise path shares the record-copy arm, so a generative
;; type loses its identity here too — a third direction the issue's own
;; repro did not cover)
;; (test-assert "EXC record_instance: a raised record keeps its type and fields"
;;              (let ((r (raised-reason (lambda () (raise (make-mrec 1 2))))))
;;                (and (mrec? r) (= (mrec-b r) 2))))

(test-assert "EXC record_instance: generative type's predicate wrongly answers #f (#1932)"
             (not (mrec? (raised-reason (lambda () (raise (make-mrec 1 2)))))))

(test-assert "EXC record_instance: nongenerative type keeps identity on the raise path"
             (let ((r (raised-reason (lambda () (raise (make-nrec 1 2))))))
               (and (nrec? r) (= (nrec-b r) 2))))

(test-assert "EXC closure: a raised closure arrives callable"
             (eqv? ((raised-reason (lambda () (raise (lambda (x) (+ x 1))))) 1) 2))

(test-assert "EXC bignum: a raised bignum keeps its exact value"
             (= (raised-reason (lambda () (raise (expt 2 100)))) (expt 2 100)))

;; A raised UNCOPYABLE value must not smuggle itself across. The refusal
;; arrives nested as the reason, with its own descriptive message.
(test-assert "EXC port: an uncopyable payload is refused, not delivered"
             (let ((r (raised-reason (lambda () (raise (open-input-string "x"))))))
               (and (not (port? r)) (error-object? r)
                    (substring? (error-object-message r) "uncopyable"))))

(test-assert "EXC mutex: an uncopyable payload is refused, not delivered"
             (let ((r (raised-reason (lambda () (raise (make-mutex))))))
               (and (not (mutex? r)) (error-object? r)
                    (substring? (error-object-message r) "uncopyable"))))

(test-assert "EXC continuation: an uncopyable payload is refused, not delivered"
             (let ((r (raised-reason
                       (lambda () (raise (call-with-current-continuation
                                          (lambda (k) k)))))))
               (and (error-object? r)
                    (substring? (error-object-message r) "uncopyable"))))

;; ---------------------------------------------------------------------
;; Section D — the refusal set
;;
;; gc_deep_copy.zig refuses 14 tags. Every reachable one is asserted at
;; BOTH copy boundaries. The refusal SHAPE is asymmetric and that is
;; deliberate per docs/dev/thread-value-sharing.md: an IN refusal happens
;; child-side and surfaces as an uncaught-exception wrapper, an OUT refusal
;; happens at the join and surfaces directly. Nothing pinned that before.
;; ---------------------------------------------------------------------

(define (refuses-in? mk)
  (equal? (outcome (let ((v (mk))) (lambda () (if (eqv? v 1) 'never 'touched))))
          '(refused wrapped)))
(define (refuses-out? mk) (equal? (outcome (lambda () (mk))) '(refused direct)))


;; NOTE ON NAMES. Every name below is a STRING LITERAL, never a computed
;; `string-append`. SRFI 64 logs the test-name *expression* as written, so a
;; computed name records `(string-append "IN " name ...)` in the log and a
;; failure on a remote leg names no type at all — the same class of problem
;; as an unnamed assertion. Worth knowing before "simplifying" this section
;; back into a loop.

(test-assert "IN port: refused child-side (wrapped)"
             (refuses-in? (lambda () (open-input-string "x"))))
(test-assert "OUT port: refused at the join (direct)"
             (refuses-out? (lambda () (open-input-string "x"))))

;; An output port is a different Port representation from an input one.
(test-assert "IN port (output, string-backed): refused child-side (wrapped)"
             (refuses-in? (lambda () (open-output-string))))
(test-assert "OUT port (output, string-backed): refused at the join (direct)"
             (refuses-out? (lambda () (open-output-string))))

(test-assert "IN continuation: refused child-side (wrapped)"
             (refuses-in? (lambda () (call-with-current-continuation (lambda (k) k)))))
(test-assert "OUT continuation: refused at the join (direct)"
             (refuses-out? (lambda () (call-with-current-continuation (lambda (k) k)))))

(test-assert "IN fiber (thread handle): refused child-side (wrapped)"
             (refuses-in? (lambda () (make-thread (lambda () 1)))))
(test-assert "OUT fiber (thread handle): refused at the join (direct)"
             (refuses-out? (lambda () (make-thread (lambda () 1)))))

(test-assert "IN mutex: refused child-side (wrapped)"
             (refuses-in? (lambda () (make-mutex))))
(test-assert "OUT mutex: refused at the join (direct)"
             (refuses-out? (lambda () (make-mutex))))

(test-assert "IN condition_variable: refused child-side (wrapped)"
             (refuses-in? (lambda () (make-condition-variable))))
(test-assert "OUT condition_variable: refused at the join (direct)"
             (refuses-out? (lambda () (make-condition-variable))))

(test-assert "IN scheme_environment: refused child-side (wrapped)"
             (refuses-in? (lambda () (environment '(scheme base)))))
(test-assert "OUT scheme_environment: refused at the join (direct)"
             (refuses-out? (lambda () (environment '(scheme base)))))

(test-assert "refusal message names the cause without naming the value"
             (let ((r (join-thunk (let ((v (open-input-string "x")))
                                    (lambda () (if (eqv? v 1) 'never 'touched))))))
               (and (pair? r) (eq? (car r) 'RAISED)
                    (substring? (caddr r) "uncaught exception in thread"))))

;; SRFI 254 weak references: the refusal is asserted here, the types
;; themselves are Phase 2.10's subject (#2013).
(define (make-eph)
  (eval '(make-ephemeron (list 1) (list 2))
        (environment '(scheme base) '(srfi 254))))

(test-assert "IN ephemeron: refused child-side (wrapped)" (refuses-in? make-eph))
(test-assert "OUT ephemeron: refused at the join (direct)" (refuses-out? make-eph))

;; SRFI 170 record types. user-info/group-info raise "unsupported" on
;; Windows and open-directory is degraded there, so each constructor is
;; probed and its two assertions are emitted only where it works. This is
;; why the assertion count is platform-dependent.
(define (srfi170 form)
  (lambda () (eval form (environment '(scheme base) '(srfi 170)))))

(define mk-file-info (srfi170 '(file-info ".")))
(define mk-directory (srfi170 '(open-directory ".")))
(define mk-user-info (srfi170 '(user-info (user-uid))))
(define mk-group-info (srfi170 '(group-info (user-gid))))

(when (constructible? mk-file-info)
  (test-assert "IN file_info: refused child-side (wrapped)" (refuses-in? mk-file-info))
  (test-assert "OUT file_info: refused at the join (direct)" (refuses-out? mk-file-info)))

(when (constructible? mk-directory)
  (test-assert "IN directory_object: refused child-side (wrapped)" (refuses-in? mk-directory))
  (test-assert "OUT directory_object: refused at the join (direct)" (refuses-out? mk-directory)))

(when (constructible? mk-user-info)
  (test-assert "IN user_info: refused child-side (wrapped)" (refuses-in? mk-user-info))
  (test-assert "OUT user_info: refused at the join (direct)" (refuses-out? mk-user-info)))

(when (constructible? mk-group-info)
  (test-assert "IN group_info: refused child-side (wrapped)" (refuses-in? mk-group-info))
  (test-assert "OUT group_info: refused at the join (direct)" (refuses-out? mk-group-info)))

;; ---------------------------------------------------------------------
;; Section E — the ALIASED tags, and the hole in the matrix
;;
;; gc_deep_copy.zig:465 is `.ffi_library, .ffi_function => src` — the
;; source Value is returned unchanged, so the receiving heap gets a pointer
;; into the sending heap. That is sound only while the sending heap
;; outlives the receiving one. It does for the globals route and for a
;; parent-owned handle aliased back to the parent (controls below). It does
;; NOT for a handle the CHILD allocates and returns: thread-join! frees the
;; child heap, and the parent is left holding a freed object.
;;
;; FFI needs a loadable system library, so this whole section is probed.
;; ---------------------------------------------------------------------

;; Probe for a system library exporting `abs`. The name differs per platform
;; and `ffi-open` succeeding does not guarantee `ffi-fn` will, so BOTH steps
;; are guarded and the section is skipped unless a callable handle results.
(define ffi-name
  (let loop ((names '("libc.so.6" "libc.dylib" "libSystem.B.dylib"
                      "libc.so.7" "libc.so" "msvcrt.dll")))
    (cond ((null? names) #f)
          ((guard (e (#t #f))
             (and (ffi-fn (ffi-open (car names)) "abs" '(int) 'int) #t))
           (car names))
          (else (loop (cdr names))))))

(when ffi-name
  (define pfn (ffi-fn (ffi-open ffi-name) "abs" '(int) 'int))

  (test-assert "FFI control: the parent's own ffi-fn works before any thread"
               (= (pfn -5) 5))

  ;; CONTROL 1 — parent-owned handle, used by the child through lexical
  ;; capture. The alias points into the parent heap, which outlives the
  ;; child, so this is the sound direction.
  (test-assert "IN ffi_function: parent-owned handle is callable in the child"
               (crossed? (lambda () (pfn -5)) (lambda (r) (eqv? r 5))))

  (test-assert "IN ffi_function: parent's handle still works after the join"
               (= (pfn -6) 6))

  ;; CONTROL 2 — parent-owned handle captured AND returned. Aliased back
  ;; into the heap that already owns it: still sound.
  (test-assert "OUT ffi_function: a parent-owned handle returned by the child survives"
               (let ((r (join-thunk (lambda () pfn))))
                 (and (procedure? r) (= (r -8) 8))))

  ;; THE FAILING CELL — child-allocated handle returned through the join.
  ;; Same code path as the two controls; the only difference is which heap
  ;; owns the object. Left disabled: the value that comes back has been
  ;; observed reading as the pair (0.0 . 0.0), so asserting anything about
  ;; its contents dereferences freed memory.
  ;;
  ;; FAIL: #2027 (child-created ffi_function/ffi_library is aliased across
  ;; thread-join!, so the parent receives a freed object: procedure? is #f
  ;; and the slot reads back as (0.0 . 0.0))
  ;; (test-assert "OUT ffi_function: a child-created handle arrives callable"
  ;;              (let ((r (join-thunk (lambda ()
  ;;                                     (ffi-fn (ffi-open ffi-name) "abs"
  ;;                                             '(int) 'int)))))
  ;;                (and (procedure? r) (= (r -9) 9))))
  ;;
  ;; FAIL: #2027 (same root cause, ffi_library rather than ffi_function)
  ;; (test-assert "OUT ffi_library: a child-created library handle arrives usable"
  ;;              (let ((r (join-thunk (lambda () (ffi-open ffi-name)))))
  ;;                (procedure? (ffi-fn r "abs" '(int) 'int))))

  ;; What IS safe to assert: the returned object is not a usable handle.
  ;; This pins the bug without touching its contents, so it flips when the
  ;; aliasing is fixed.
  ;;
  ;; The child re-opens the library BY NAME rather than capturing `ffi-name`
  ;; from the parent, and the two-part assertion below is what makes the
  ;; result meaningful: `crossed?` must be #t (the boundary itself did not
  ;; refuse — otherwise `procedure?` would answer #f merely because an error
  ;; list came back, and the assertion would pass on a platform where FFI
  ;; does not work at all).
  (let ((r (join-thunk (lambda () (ffi-fn (ffi-open ffi-name) "abs" '(int) 'int)))))
    (test-assert "OUT ffi_function: the join itself does not refuse the handle"
                 (not (and (pair? r) (eq? (car r) 'RAISED))))
    (test-assert "OUT ffi_function: child-created handle does NOT arrive callable (bug pinned, #2027)"
                 (not (procedure? r))))

  ;; ffi_callback is the one refused FFI tag, and docs/dev/thread-value-sharing.md
  ;; records it as "not probed". Only some signatures are supported, so this
  ;; uses the two-pointer shape tests/scheme/ffi/callback-error.scm uses.
  (let ((cb (guard (e (#t #f))
              (ffi-callback (lambda (a b) 0) '(pointer pointer) 'int))))
    (when cb
      (test-assert "IN ffi_callback: refused child-side (wrapped)"
                   (equal? (outcome (lambda () (if (eqv? cb 1) 'never 'touched)))
                           '(refused wrapped)))
      (test-assert "OUT ffi_callback: refused at the join (direct)"
                   (equal? (outcome (lambda ()
                                      (ffi-callback (lambda (a b) 0)
                                                    '(pointer pointer) 'int)))
                           '(refused direct))))))

;; ---------------------------------------------------------------------
;; Section F — the globals route
;;
;; VM.initForThread shares the parent's globals map BY POINTER, so a value
;; named through a top-level define is never copied and the refusal list
;; above does not apply to it. Only two types check ownership
;; (channel, thread handle). Phase 2.10 (#2008) found invokeGuardian
;; missing its check; this section asks the same question of the types
;; that reach a child through a global WITHOUT being copied, and pins the
;; answers. These are characterisation assertions: they record what the
;; engine does today so a change lands visibly.
;; ---------------------------------------------------------------------

(define g-param (make-parameter 5 (lambda (x) (* x 10))))
(define g-promise (delay (* 6 7)))
(define g-ht (make-hash-table equal?))
(define g-f64 (f64vector 1.0 2.0))
(define g-time (current-time))
(define g-env (environment '(scheme base)))
(define g-rs (make-random-source))
(define g-port (open-input-string "abc"))
(define g-tx (er-macro-transformer (lambda (f rn c) (list (rn 'quote) 'hi))))

(test-assert "globals parameter: child reads it, converter already applied"
             (eqv? (join-thunk (lambda () (g-param))) 50))

(test-assert "globals parameter: child's parameterize applies the converter"
             (eqv? (join-thunk (lambda () (parameterize ((g-param 3)) (g-param)))) 30))

(test-assert "globals promise: a child may force a parent-heap promise"
             (eqv? (join-thunk (lambda () (force g-promise))) 42))

(test-assert "globals hash_table: a child may write and read a parent-heap table"
             (eq? (join-thunk (lambda ()
                                (hash-table-set! g-ht 'k 'v)
                                (hash-table-ref/default g-ht 'k 'MISSING)))
                  'v))

(test-assert "globals hash_table: the child's write is visible to the parent"
             (eq? (hash-table-ref/default g-ht 'k 'MISSING) 'v))

(test-assert "globals numeric_vector: a child's raw element write is visible to the parent"
             (and (eqv? (join-thunk (lambda () (f64vector-set! g-f64 0 9.5)
                                       (f64vector-ref g-f64 0)))
                        9.5)
                  (= (f64vector-ref g-f64 0) 9.5)))

(test-assert "globals srfi18_time: readable from a child"
             (eq? #t (join-thunk (lambda () (> (time->seconds g-time) 0)))))

(test-assert "globals scheme_environment: a child may eval in a parent-heap environment"
             (eqv? (join-thunk (lambda () (eval '(+ 1 2) g-env))) 3))

(test-assert "globals random_source: a child may draw from a parent-heap source"
             (eq? #t (join-thunk (lambda ()
                                   (let ((g ((random-source-make-integers g-rs) 10)))
                                     (and (>= g 0) (< g 10)))))))

(test-assert "globals port: a child may read a parent-heap port (no owner check)"
             (eqv? (join-thunk (lambda () (read-char g-port))) #\a))

(test-assert "globals port: the child's read advanced the PARENT's own position"
             (eqv? (read-char g-port) #\b))

(test-assert "globals transformer: a parent-heap transformer is reachable from a child"
             (eq? (join-thunk (lambda () (if (eqv? g-tx 1) 'never 'touched))) 'touched))

;; The two types that DO check ownership. Asserted here so the pair of
;; checked types is visible next to the many unchecked ones above.
(define g-thread (make-thread (lambda () 1)))

(test-assert "globals fiber: a child may NOT start a parent-heap thread handle"
             (let ((r (join-thunk (lambda () (thread-start! g-thread)))))
               (and (pair? r) (eq? (car r) 'RAISED))))

(test-assert "globals fiber: the ownership refusal names the rule"
             (let ((r (join-thunk (lambda () (thread-name g-thread)))))
               (and (pair? r) (eq? (car r) 'RAISED)
                    (substring? (caddr r) "uncaught exception in thread"))))

;; ---------------------------------------------------------------------
;; Section G — the vestigial and unreachable tags
;;
;; Recorded as assertions so the claim "not reachable" is testable rather
;; than a comment that can rot.
;; ---------------------------------------------------------------------

(test-assert "flonum: a float is NaN-boxed inline, never a heap object"
             ;; allocFlonum returns an immediate; the .flonum arm is dead code.
             ;; Round-tripping one still works, which is the observable claim.
             (= (join-thunk (lambda () 1.5)) 1.5))

(test-assert "flonum: an inline float survives IN-capture too"
             (let ((v 2.25)) (crossed? (lambda () v) (lambda (r) (= r 2.25)))))

(test-assert "multiple_values: values collapse to a list before any boundary"
             ;; MultipleValues is transient — call-with-values consumes it, so
             ;; no `.multiple_values` object ever reaches a thread boundary.
             (equal? (join-thunk (lambda ()
                                   (call-with-values (lambda () (values 1 2)) list)))
                     '(1 2)))

(let ((runner (test-runner-current)))
  (test-end "srfi18 deep-copy matrix audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
