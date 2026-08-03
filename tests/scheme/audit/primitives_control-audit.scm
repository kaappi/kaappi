;; Audit tests for src/primitives_control.zig — exceptions, call/cc, call/ec,
;; dynamic-wind, values/call-with-values, and the three SRFI 248 VM primitives.
;;
;; Audit campaign v2, Phase 2.9 (tracker #1890).  The v1 pass (#1137) left 35
;; unnamed assertions here; this file re-states them with names and adds the
;; dimensions v1 did not have: the SRFI 248 sticky-handler mechanism, the
;; handler/wind stack discipline of #1886, D1 (internal-primitive reachability),
;; D2 (error taxonomy — KP codes), and D5 (re-entrancy: which of the 14 native
;; callback sites can park a fiber).
;;
;; Oracles: R7RS-small §4.2.7 (guard), §6.10 (control features), §6.11
;; (exceptions); README.md "Known limitations"; CONFORMANCE.md; the header of
;; lib/srfi/248.sld.  Behaviour R7RS leaves unspecified (multiple values in a
;; single-value context, escaping from a before/after thunk) is deliberately
;; NOT asserted.
;;
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme write) (scheme process-context)
        (kaappi diagnostics) (kaappi fibers)
        (only (srfi 248) with-unwind-handler empty-continuation?)
        (srfi 248 primitives)
        (srfi 64))

(test-begin "primitives_control audit")

;; Yields #t when EXPR raises anything at all, #f when it returns.  Used only
;; where the *fact* of a raise is the whole claim; wherever the message or the
;; diagnostic code is stable, the tests below assert that instead.
(define-syntax raises?
  (syntax-rules () ((_ e) (guard (ex (#t #t)) (begin e #f)))))

;; The message of whatever EXPR raises, or the raised object itself when it is
;; not an error object.
(define-syntax raised-msg
  (syntax-rules ()
    ((_ e) (guard (ex (#t (if (error-object? ex) (error-object-message ex) ex)))
             (begin e 'no-raise)))))

;; The stable diagnostic code (KEP-0005 §4) of whatever EXPR raises.
(define-syntax raised-code
  (syntax-rules ()
    ((_ e) (guard (ex (#t (error-object-code ex))) (begin e 'no-raise)))))

;;; ------------------------------------------------------------------
;;; values / call-with-values — R7RS §6.10
;;; ------------------------------------------------------------------

(test-equal "values: zero values reach a rest-arg consumer"
            0 (call-with-values (lambda () (values)) (lambda args (length args))))
(test-equal "values: one value is that value"
            42 (+ 1 (values 41)))
(test-equal "values: three values spread into list"
            '(1 2 3) (call-with-values (lambda () (values 1 2 3)) list))
(test-equal "call-with-values: spec example (call-with-values * -)"
            -1 (call-with-values * -))
(test-equal "call-with-values: spec example (values 4 5) -> b"
            5 (call-with-values (lambda () (values 4 5)) (lambda (a b) b)))
(test-equal "values: producer returning a single value calls consumer with one arg"
            '(7) (call-with-values (lambda () 7) list))
(test-assert "call-with-values: consumer arity is checked (too few)"
             (raises? (call-with-values (lambda () (values 1 2 3)) (lambda (a b) b))))
(test-assert "call-with-values: consumer arity is checked (too many)"
             (raises? (call-with-values (lambda () (values)) (lambda (x) x))))
(test-assert "call-with-values: consumer arity is checked (single value, 0-arg consumer)"
             (raises? (call-with-values (lambda () 1) (lambda () 'zero))))
(test-equal "values: variadic consumer accepts any count"
            '(1 2 3 4) (call-with-values (lambda () (values 1 2 3 4)) (lambda a a)))
(test-equal "call/cc: continuation applied to several values"
            '(1 2 3) (call-with-values (lambda () (call/cc (lambda (k) (k 1 2 3)))) list))
(test-equal "call/cc: continuation applied to zero values"
            '() (call-with-values (lambda () (call/cc (lambda (k) (k)))) list))

;;; ------------------------------------------------------------------
;;; raise / raise-continuable / with-exception-handler — R7RS §6.11
;;; ------------------------------------------------------------------

;; §6.11: "If the handler returns, the values it returns become the values
;; returned by the call to raise-continuable."
(test-equal "raise-continuable: handler's return value is the raise's value"
            101 (with-exception-handler (lambda (c) 100)
                  (lambda () (+ 1 (raise-continuable 'k)))))

;; §6.11 worked example verbatim — prints "should be a number", yields 65.
(test-equal "raise-continuable: R7RS 6.11 worked example yields 65"
            65 (with-exception-handler
                 (lambda (con) (if (string? con) #t #t) 42)
                 (lambda () (+ (raise-continuable "should be a number") 23))))

;; §6.11: "if the handler being called returns, then it will again become the
;; current exception handler."
(test-equal "raise-continuable: handler is re-installed after it returns"
            '(10 20) (with-exception-handler (lambda (c) (* c 10))
                       (lambda () (list (raise-continuable 1) (raise-continuable 2)))))

;; §6.11: "the current exception handler is the one that was in place when the
;; handler being called was installed."
(test-equal "raise-continuable: handler runs under the OUTER handler"
            '(inner x (outer from-inner))
            (with-exception-handler
              (lambda (c) (list 'outer c))
              (lambda ()
                (with-exception-handler
                  (lambda (c) (list 'inner c (raise-continuable 'from-inner)))
                  (lambda () (raise-continuable 'x))))))

(test-equal "raise-continuable: with no handler installed it still reaches guard"
            '(caught no-handler)
            (guard (e (#t (list 'caught e))) (raise-continuable 'no-handler)))

;; §6.11: "If the handler returns, a secondary exception is raised in the same
;; dynamic environment as the handler."
(test-equal "raise: a handler that returns triggers a secondary exception"
            'secondary-raised
            (guard (outer (#t 'secondary-raised))
              (with-exception-handler (lambda (c) 'ignored)
                (lambda () (raise 'first) 'not-reached))))

(test-equal "raise: handler runs with the OUTER handler installed"
            '(outer-saw from-handler)
            (guard (e (#t (list 'outer-saw e)))
              (with-exception-handler (lambda (c) (raise 'from-handler))
                (lambda () (raise 'inner)))))

(test-equal "raise: a non-error object arrives at the handler unchanged"
            '(#f sym) (guard (e (#t (list (error-object? e) e))) (raise 'sym)))
(test-equal "raise: a fixnum arrives unchanged"
            42 (guard (e (#t e)) (raise 42)))
(test-equal "raise: #f arrives unchanged"
            #f (guard (e (#t e)) (raise #f)))
(test-equal "raise: the empty list arrives unchanged"
            '() (guard (e (#t e)) (raise '())))
(test-assert "raise: a procedure arrives unchanged"
             (guard (e (#t (procedure? e))) (raise car)))
(test-equal "raise: a mutable vector arrives eq?, not a copy"
            #t (let ((v (vector 1 2))) (guard (e (#t (eq? e v))) (raise v))))

;; §6.11 first worked example: escape from the handler via call/cc.
(test-equal "raise: R7RS 6.11 example — k escapes from the handler"
            '(exception an-error)
            (call-with-current-continuation
              (lambda (k)
                (with-exception-handler
                  (lambda (x) (k (list 'exception x)))
                  (lambda () (+ 1 (raise 'an-error)))))))

(test-equal "with-exception-handler: normal return passes the thunk's value through"
            'v (with-exception-handler (lambda (e) 'never) (lambda () 'v)))
(test-equal "with-exception-handler: a native runtime error reaches the handler"
            #t (with-exception-handler error-object? (lambda () (car 5))))

;;; ------------------------------------------------------------------
;;; error objects — R7RS §6.11
;;; ------------------------------------------------------------------

(test-equal "error: message and irritants round-trip"
            '(#t "m" (1 2))
            (guard (e (#t (list (error-object? e)
                                (error-object-message e)
                                (error-object-irritants e))))
              (error "m" 1 2)))
(test-equal "error: no irritants yields the empty list"
            '() (guard (e (#t (error-object-irritants e))) (error "m")))
(test-equal "error-object?: a fixnum is not an error object"
            #f (error-object? 42))
(test-equal "error-object?: a raised symbol is not an error object"
            #f (guard (e (#t (error-object? e))) (raise 'x)))
(test-equal "file-error?: a plain error is not a file error"
            #f (guard (e (#t (file-error? e))) (error "x")))
(test-equal "read-error?: a plain error is not a read error"
            #f (guard (e (#t (read-error? e))) (error "x")))
(test-equal "file-error?: a non-error object answers #f rather than raising"
            #f (file-error? 42))
(test-equal "read-error?: a non-error object answers #f rather than raising"
            #f (read-error? 42))
(test-assert "error-object-message: a non-error object is a type error"
             (raises? (error-object-message 42)))
(test-assert "error-object-irritants: a non-error object is a type error"
             (raises? (error-object-irritants 42)))
(test-equal "error: irritants keep their order"
            '(1 2 3) (guard (e (#t (error-object-irritants e))) (error "m" 1 2 3)))
(test-equal "error: an irritant is eq? to what was passed"
            #t (let ((v (vector 0)))
                 (guard (e (#t (eq? v (car (error-object-irritants e)))))
                   (error "m" v))))
(test-assert "error: zero arguments is an arity error"
             (raises? (error)))

;; error-object-code (KEP-0005 §4) is documented as total — it never raises.
(test-equal "error-object-code: a non-error object answers #f"
            #f (error-object-code 42))
(test-equal "error-object-code: a raised symbol answers #f"
            #f (guard (e (#t (error-object-code e))) (raise 'x)))
(test-equal "error-object-code: a user (error ...) is uncoded"
            #f (guard (e (#t (error-object-code e))) (error "user")))
(test-equal "error-object-code: a car type error is KP3002"
            'KP3002 (raised-code (car 5)))
(test-equal "error-object-code: an undefined variable is KP3001"
            'KP3001 (guard (e (#t (error-object-code e))) (eval '(no-such-variable-here)
                                                               (interaction-environment))))
(test-equal "error-object-code: the code symbol is interned, so eq? works"
            #t (eq? 'KP3002 (raised-code (car 5))))

;;; ------------------------------------------------------------------
;;; guard — R7RS §4.2.7
;;; ------------------------------------------------------------------

;; §4.2.7 worked examples, verbatim.
(test-equal "guard: R7RS 4.2.7 example with => on assq"
            42 (guard (condition ((assq 'a condition) => cdr)
                                 ((assq 'b condition)))
                 (raise (list (cons 'a 42)))))
(test-equal "guard: R7RS 4.2.7 example returning the clause value"
            '(b . 23) (guard (condition ((assq 'a condition) => cdr)
                                        ((assq 'b condition)))
                        (raise (list (cons 'b 23)))))
(test-equal "guard: else clause"
            'elsed (guard (e (else 'elsed)) (raise 'z)))
(test-equal "guard: body value when nothing is raised"
            'fine (guard (e (#t 'caught)) 'fine))
(test-equal "guard: a declining inner guard re-raises to the outer one"
            '(outer boom)
            (guard (e (#t (list 'outer e)))
              (guard (e2 ((eq? e2 'nope) 'never)) (raise 'boom))))
(test-equal "guard: a clause that raises reaches the outer guard"
            '(outer (from-clause boom))
            (guard (e (#t (list 'outer e)))
              (guard (e2 (#t (raise (list 'from-clause e2)))) (raise 'boom))))
(test-equal "guard: catches a native runtime error"
            'handled (guard (e (#t 'handled)) (car 5)))
(test-equal "guard: body in tail position returns multiple values"
            '(1 2) (call-with-values (lambda () (guard (e (#t 'c)) (values 1 2))) list))
(test-equal "guard: the raised object is bound to the variable"
            'obj (guard (obj (#t obj)) (raise 'obj)))

;; #1886: the handler stack must not leak a slot per declining guard.
(test-equal "guard: 5000 declining guards do not exhaust the handler stack"
            5000
            (let loop ((n 5000) (acc 0))
              (if (= n 0) acc (loop (- n 1) (guard (e (#t (+ acc 1))) (raise 'z))))))
(test-equal "with-exception-handler: 5000 escapes from a handler do not leak"
            5000
            (let loop ((n 5000) (acc 0))
              (if (= n 0) acc
                  (loop (- n 1)
                        (call/cc (lambda (k)
                                   (with-exception-handler (lambda (x) (k (+ acc 1)))
                                     (lambda () (raise 'z)))))))))
(test-equal "guard: the handler stack is intact after an escape from a handler"
            '(first (second b))
            (let ((r1 (call/cc (lambda (k)
                                 (with-exception-handler (lambda (x) (k 'first))
                                   (lambda () (raise 'a)))))))
              (list r1 (guard (e (#t (list 'second e))) (raise 'b)))))
;; Depth 90, not more: `guard` spends two native re-entrancy frames per level
;; and callReentrant caps that at 200 in a Debug build — the ceiling
;; tests/scheme/smoke/handler-wind-depth-1886.scm measured and stays under.
(test-equal "guard: 90 statically nested guards all decline correctly"
            'bottom
            (letrec ((nest (lambda (n) (if (= n 0) 'bottom
                                           (guard (e (#t 'caught)) (nest (- n 1)))))))
              (nest 90)))

;;; ------------------------------------------------------------------
;;; call/cc — R7RS §6.10
;;; ------------------------------------------------------------------

(test-equal "call/cc: escaping continuation abandons the rest of the receiver"
            42 (call/cc (lambda (k) (+ 1 (k 42)))))
(test-equal "call/cc: receiver returning normally yields its value"
            7 (call/cc (lambda (k) 7)))
(test-equal "call-with-current-continuation: long name behaves identically"
            42 (call-with-current-continuation (lambda (k) (k 42))))
(test-equal "call/cc: R7RS 6.10 example — non-local exit from for-each"
            -3 (call-with-current-continuation
                 (lambda (exit)
                   (for-each (lambda (x) (if (negative? x) (exit x))) '(54 0 37 -3 245 19))
                   #t)))
(test-equal "call/cc: R7RS 6.10 example — list-length on an improper list"
            #f (letrec ((list-length
                         (lambda (obj)
                           (call-with-current-continuation
                             (lambda (return)
                               (letrec ((r (lambda (obj)
                                             (cond ((null? obj) 0)
                                                   ((pair? obj) (+ (r (cdr obj)) 1))
                                                   (else (return #f))))))
                                 (r obj)))))))
                 (list-length '(a b . c))))
(test-equal "call/cc: R7RS 6.10 example — list-length on a proper list"
            4 (letrec ((list-length
                        (lambda (obj)
                          (call-with-current-continuation
                            (lambda (return)
                              (letrec ((r (lambda (obj)
                                            (cond ((null? obj) 0)
                                                  ((pair? obj) (+ (r (cdr obj)) 1))
                                                  (else (return #f))))))
                                (r obj)))))))
                (list-length '(1 2 3 4))))
(test-equal "call/cc: re-entry with a set!-mutated local counter"
            3 (let ((n 0) (k* #f))
                (call/cc (lambda (k) (set! k* k)))
                (set! n (+ n 1))
                (if (< n 3) (k* #f))
                n))
(test-equal "call/cc: re-entry with a heap-cell counter (contrast #1168)"
            3 (let ((n (vector 0)) (k* #f))
                (call/cc (lambda (k) (set! k* k)))
                (vector-set! n 0 (+ (vector-ref n 0) 1))
                (if (< (vector-ref n 0) 3) (k* #f))
                (vector-ref n 0)))
(test-equal "call/cc: re-entry observed through a closure-captured reader"
            3 (let ((n 0) (k* #f))
                (define (read-n) n)
                (call/cc (lambda (k) (set! k* k)))
                (set! n (+ n 1))
                (if (< (read-n) 3) (k* #f))
                n))
(test-equal "call/cc: a continuation is a procedure"
            #t (call/cc procedure?))
(test-assert "call/cc: a non-procedure receiver is an error"
             (raises? (call/cc 42)))
(test-assert "call-with-current-continuation: a non-procedure receiver is an error"
             (raises? (call-with-current-continuation 42)))

;;; ------------------------------------------------------------------
;;; call/ec — escape-only continuations (Kaappi extension)
;;; ------------------------------------------------------------------

(test-equal "call/ec: escaping abandons the rest of the receiver"
            42 (call/ec (lambda (k) (+ 1 (k 42)))))
(test-equal "call-with-escape-continuation: long name behaves identically"
            7 (call-with-escape-continuation (lambda (k) 7)))
(test-equal "call/ec: escape runs the intervening dynamic-wind after-thunks"
            '(esc (B A))
            (let ((log '()))
              (list (call/ec (lambda (k)
                               (dynamic-wind (lambda () (set! log (cons 'B log)))
                                             (lambda () (k 'esc))
                                             (lambda () (set! log (cons 'A log))))))
                    (reverse log))))
(test-equal "call/ec: invoking the continuation after its extent is a clean error"
            "escape continuation invoked outside its dynamic extent"
            (let ((saved #f))
              (call/ec (lambda (k) (set! saved k) 'in))
              (raised-msg (saved 'late))))
(test-equal "call/ec: an error in the receiver still ends the extent"
            "escape continuation invoked outside its dynamic extent"
            (let ((saved #f))
              (guard (e (#t 'ignored))
                (call/ec (lambda (k) (set! saved k) (raise 'boom))))
              (raised-msg (saved 'late))))
(test-assert "call/ec: a non-procedure receiver is an error"
             (raises? (call/ec "k")))
(test-equal "call/ec: type error names call/ec and the offending value"
            "type error in 'call/ec': expected procedure, got 42"
            (raised-msg (call/ec 42)))

;;; ------------------------------------------------------------------
;;; dynamic-wind — R7RS §6.10
;;; ------------------------------------------------------------------

(test-equal "dynamic-wind: before, thunk, after each run once, in order"
            '(in body out)
            (let ((acc '()))
              (dynamic-wind (lambda () (set! acc (cons 'in acc)))
                            (lambda () (set! acc (cons 'body acc)) 'r)
                            (lambda () (set! acc (cons 'out acc))))
              (reverse acc)))
(test-equal "dynamic-wind: returns the thunk's value, not the after-thunk's"
            'val (dynamic-wind (lambda () 1) (lambda () 'val) (lambda () 2)))
(test-equal "dynamic-wind: multiple values pass through"
            '(a b) (call-with-values
                     (lambda () (dynamic-wind (lambda () 1)
                                              (lambda () (values 'a 'b))
                                              (lambda () 2)))
                     list))
(test-equal "dynamic-wind: after-thunk runs when the body escapes"
            '(in out)
            (let ((acc '()))
              (call/cc (lambda (k)
                         (dynamic-wind (lambda () (set! acc (cons 'in acc)))
                                       (lambda () (k 'escaped))
                                       (lambda () (set! acc (cons 'out acc))))))
              (reverse acc)))
(test-equal "dynamic-wind: R7RS 6.10 worked example (connect/talk/disconnect)"
            '(connect talk1 disconnect connect talk2 disconnect)
            (let ((path '()) (c #f))
              (let ((add (lambda (s) (set! path (cons s path)))))
                (dynamic-wind
                  (lambda () (add 'connect))
                  (lambda () (add (call/cc (lambda (c0) (set! c c0) 'talk1))))
                  (lambda () (add 'disconnect)))
                (if (< (length path) 4) (c 'talk2) (reverse path)))))
;; §6.10 rules 1 and 2: on re-entry the OUTER before runs first and the INNER
;; after runs first.  Both are visible in a single nested escape-and-re-enter.
(test-equal "dynamic-wind: nested exit runs inner-after first, re-entry runs outer-before first"
            '(out-before in-before in-after out-after
              out-before in-before in-after out-after)
            (let ((trace '()) (k* #f) (done #f))
              (define (add s) (set! trace (cons s trace)))
              (dynamic-wind
                (lambda () (add 'out-before))
                (lambda ()
                  (dynamic-wind (lambda () (add 'in-before))
                                (lambda () (call/cc (lambda (k) (set! k* k) 'first)))
                                (lambda () (add 'in-after))))
                (lambda () (add 'out-after)))
              (if (not done) (begin (set! done #t) (k* 'second)))
              (reverse trace)))
;; §6.10 rule 3: "If invoking a continuation requires calling the before from
;; one call to dynamic-wind and the after from another, then the after is
;; called first."
(test-equal "dynamic-wind: crossing into a sibling extent runs the after before the before"
            '(A-before A-body A-after B-before B-after A-before A-body A-after)
            (let ((t2 '()) (kk #f) (phase 0))
              (define (a2 s) (set! t2 (cons s t2)))
              (dynamic-wind (lambda () (a2 'A-before))
                            (lambda () (call/cc (lambda (k) (set! kk k))) (a2 'A-body))
                            (lambda () (a2 'A-after)))
              (set! phase (+ phase 1))
              (if (= phase 1)
                  (dynamic-wind (lambda () (a2 'B-before))
                                (lambda () (kk #f))
                                (lambda () (a2 'B-after))))
              (reverse t2)))
(test-equal "dynamic-wind: an error in the before-thunk propagates"
            'caught (guard (e (#t 'caught))
                      (dynamic-wind (lambda () (error "in-before"))
                                    (lambda () 'body) (lambda () 'after))))
(test-equal "dynamic-wind: the after-thunk runs when the body raises"
            #t (let ((ran #f))
                 (guard (e (#t ran))
                   (dynamic-wind (lambda () 1)
                                 (lambda () (error "boom"))
                                 (lambda () (set! ran #t))))))
(test-equal "dynamic-wind: an after-thunk raising during unwind wins over the body's condition"
            'after-exn
            (guard (e (#t e))
              (dynamic-wind (lambda () 'b)
                            (lambda () (raise 'body-exn))
                            (lambda () (raise 'after-exn)))))
(test-equal "dynamic-wind: an after-thunk raising on normal return is visible"
            'after-exn
            (guard (e (#t e))
              (dynamic-wind (lambda () 'b) (lambda () 'ok) (lambda () (raise 'after-exn)))))
(test-equal "dynamic-wind: the after-thunk runs exactly once when the body raises"
            1 (let ((n 0))
                (guard (e (#t n))
                  (dynamic-wind (lambda () 1)
                                (lambda () (raise 'x))
                                (lambda () (set! n (+ n 1)))))))
(test-equal "dynamic-wind: 100 nested extents unwind cleanly"
            'bottom
            (letrec ((nd (lambda (n) (if (= n 0) 'bottom
                                         (dynamic-wind (lambda () 1)
                                                       (lambda () (nd (- n 1)))
                                                       (lambda () 2))))))
              (nd 100)))
(test-equal "dynamic-wind: escaping from 300 nested extents runs every after-thunk"
            300
            (let ((c 0) (esc #f))
              (define (nd n) (if (= n 0) (esc 'deep)
                                 (dynamic-wind (lambda () #t)
                                               (lambda () (nd (- n 1)))
                                               (lambda () (set! c (+ c 1))))))
              (call/cc (lambda (k) (set! esc k) (nd 300)))
              c))
(test-assert "dynamic-wind: a non-procedure before is an error"
             (raises? (dynamic-wind 1 (lambda () 2) (lambda () 3))))
(test-assert "dynamic-wind: a non-procedure thunk is an error"
             (raises? (dynamic-wind (lambda () 1) 2 (lambda () 3))))
(test-assert "dynamic-wind: a non-procedure after is an error"
             (raises? (dynamic-wind (lambda () 1) (lambda () 2) 3)))
(test-assert "dynamic-wind: a wrong-arity before-thunk is rejected"
             (raises? (dynamic-wind (lambda (x) 1) (lambda () 2) (lambda () 3))))
(test-assert "dynamic-wind: a wrong-arity thunk is rejected"
             (raises? (dynamic-wind (lambda () 1) (lambda (x) 2) (lambda () 3))))
(test-assert "dynamic-wind: a wrong-arity after-thunk is rejected"
             (raises? (dynamic-wind (lambda () 1) (lambda () 2) (lambda (x) 3))))

;; The other half of #1886 — that genuinely exceeding a VM limit is NOT
;; catchable — needs an exit code and stderr, so it lives in
;; tests/scheme/errors/error-format.sh; deliberately triggering the limit here
;; would abort a top-level form and take this file's own exit status with it.

;;; ------------------------------------------------------------------
;;; SRFI 248 — sticky (unwind) handlers
;;; ------------------------------------------------------------------

(test-equal "SRFI 248: no raise returns the thunk's value"
            42 (with-unwind-handler (lambda (o k) 'unused) (lambda () (+ 40 2))))
(test-equal "SRFI 248: raise-continuable reaches the unwind handler"
            '(caught 99)
            (with-unwind-handler (lambda (o k) (list 'caught o))
                                 (lambda () (raise-continuable 99))))
(test-equal "SRFI 248: plain raise reaches the unwind handler too"
            '(caught boom)
            (with-unwind-handler (lambda (o k) (list 'caught o))
                                 (lambda () (raise 'boom) 'unreached)))
(test-equal "SRFI 248: the handler can resume the delimited continuation"
            '(resumed . #f)
            (with-unwind-handler (lambda (o k) (cons 'resumed (k #t)))
                                 (lambda () (not (raise-continuable 42)))))
(test-equal "SRFI 248: a native runtime error reaches the unwind handler as an error object"
            #t (with-unwind-handler (lambda (o k) (error-object? o)) (lambda () (car 5))))
(test-equal "SRFI 248: a native runtime error keeps its diagnostic code"
            'KP3002
            (with-unwind-handler (lambda (o k) (error-object-code o)) (lambda () (car 5))))
(test-equal "SRFI 248: a handler that raises escapes to the enclosing handler"
            '(outer from-handler)
            (with-unwind-handler (lambda (o k) (list 'outer o))
              (lambda ()
                (with-unwind-handler (lambda (o k) (raise 'from-handler))
                  (lambda () (raise-continuable 'inner))))))
(test-equal "SRFI 248: the innermost unwind handler wins"
            '(in 7)
            (with-unwind-handler (lambda (o k) (list 'outer o))
              (lambda ()
                (list 'in (with-unwind-handler (lambda (o k) o)
                            (lambda () (raise-continuable 7)))))))
;; Documented caveat (README.md, CONFORMANCE.md, lib/srfi/248.sld): the handler
;; runs at the raise point, so it precedes the guarded body's after-thunk.
(test-equal "SRFI 248: handler precedes the guarded body's after-thunk (documented caveat)"
            '(B H A)
            (let ((log '()))
              (with-unwind-handler
                (lambda (o k) (set! log (cons 'H log)) 'done)
                (lambda () (dynamic-wind (lambda () (set! log (cons 'B log)))
                                         (lambda () (raise-continuable 'x))
                                         (lambda () (set! log (cons 'A log))))))
              (reverse log)))
;; Resuming k re-enters the guarded body's dynamic extent, so before and after
;; run a second time — R7RS §6.10's re-entry rule, applied to a delimited k.
(test-equal "SRFI 248: resuming k re-enters the guarded body's dynamic extent"
            '(101 (B H A B A))
            (let ((log '()))
              (list (with-unwind-handler
                      (lambda (o k) (set! log (cons 'H log)) (k 100))
                      (lambda () (dynamic-wind (lambda () (set! log (cons 'B log)))
                                               (lambda () (+ 1 (raise-continuable 'q)))
                                               (lambda () (set! log (cons 'A log))))))
                    (reverse log))))
(test-equal "SRFI 248: an enclosing dynamic-wind is untouched by the handler"
            '(B H A)
            (let ((log '()))
              (dynamic-wind (lambda () (set! log (cons 'B log)))
                            (lambda () (with-unwind-handler
                                         (lambda (o k) (set! log (cons 'H log)) (k 5))
                                         (lambda () (+ 1 (raise-continuable 'q)))))
                            (lambda () (set! log (cons 'A log))))
              (reverse log)))
(test-equal "SRFI 248: a plain call/cc escape out of the guarded thunk works"
            'escaped
            (call/cc (lambda (esc)
                       (with-unwind-handler (lambda (o k) 'handler)
                         (lambda () (esc 'escaped))))))
(test-equal "SRFI 248: 200 consecutive caught raises do not exhaust the handler stack"
            200
            (let loop ((n 200) (acc 0))
              (if (= n 0) acc
                  (loop (- n 1)
                        (with-unwind-handler (lambda (o k) (+ acc 1))
                          (lambda () (raise 'x)))))))
;; An ordinary handler nested inside a sticky one handles its own raise; the
;; later raise reaches the sticky handler, which does not resume k, so the
;; enclosing `list` is abandoned and the handler's value is the whole result.
(test-equal "SRFI 248: an inner ordinary handler wins, then the sticky one discards k"
            '(sticky b)
            (with-unwind-handler (lambda (o k) (list 'sticky o))
              (lambda ()
                (list 'in (with-exception-handler (lambda (e) (list 'plain e))
                            (lambda () (raise-continuable 'a)))
                      (raise-continuable 'b)))))
(test-equal "SRFI 248: an inner ordinary handler's value is used when nothing else raises"
            '(in (plain a))
            (with-unwind-handler (lambda (o k) (list 'sticky o))
              (lambda ()
                (list 'in (with-exception-handler (lambda (e) (list 'plain e))
                            (lambda () (raise-continuable 'a)))))))

;; empty-continuation? — the tail-latch plus frame-count baseline.
(test-equal "SRFI 248: empty? — raise-continuable in tail context"
            #t (with-unwind-handler (lambda (o k) (empty-continuation? k))
                                    (lambda () (raise-continuable 42))))
(test-equal "SRFI 248: empty? — result consumed by the caller is not empty"
            #f (with-unwind-handler (lambda (o k) (empty-continuation? k))
                                    (lambda () (not (raise-continuable 42)))))
(test-equal "SRFI 248: empty? — tail raise through a tail-called helper is empty"
            #t (with-unwind-handler (lambda (o k) (empty-continuation? k))
                                    (lambda () ((lambda () (raise-continuable 42))))))
(test-equal "SRFI 248: empty? — tail raise in a non-tail-called helper is not empty"
            #f (with-unwind-handler (lambda (o k) (empty-continuation? k))
                                    (lambda () (not ((lambda () (raise-continuable 42)))))))
(test-equal "SRFI 248: empty? — a native runtime error leaves an empty continuation"
            #t (with-unwind-handler (lambda (o k) (empty-continuation? k))
                                    (lambda () (car 5))))
(test-equal "SRFI 248: empty? — plain raise in tail context is empty"
            #t (with-unwind-handler (lambda (o k) (empty-continuation? k))
                                    (lambda () (raise 42))))

;;; ------------------------------------------------------------------
;;; SRFI 248 VM primitives, called directly — D1 + misuse
;;; ------------------------------------------------------------------

(test-assert "D1: %call-with-unwind-handler is reachable as a procedure"
             (procedure? %call-with-unwind-handler))
(test-assert "D1: %unwind-raise-empty? is reachable as a procedure"
             (procedure? %unwind-raise-empty?))
(test-assert "D1: %pop-unwind-handler! is reachable as a procedure"
             (procedure? %pop-unwind-handler!))
;; %push-wind and %pop-wind corrupt VM state if called out of sequence, so
;; vm_bootstrap.internal_helpers removes them from globals after bootstrap.
(test-equal "D1: %push-wind is purged from globals after bootstrap"
            'KP3001 (raised-code (eval '(%push-wind) (interaction-environment))))
(test-equal "D1: %pop-wind is purged from globals after bootstrap"
            'KP3001 (raised-code (eval '(%pop-wind) (interaction-environment))))

(test-equal "%call-with-unwind-handler: no raise returns the thunk's value"
            42 (%call-with-unwind-handler (lambda (o) 'h) (lambda () 42)))
(test-equal "%call-with-unwind-handler: raise-continuable takes the handler's value"
            '(h 7) (%call-with-unwind-handler (lambda (o) (list 'h o))
                                              (lambda () (raise-continuable 7))))
;; Without the (srfi 248) shift wrapper the handler returns normally, which for
;; a plain raise is the R7RS secondary exception — delivered to the same sticky
;; handler exactly once, not looped.
(test-equal "%call-with-unwind-handler: a handler returning from raise yields the secondary error"
            "exception handler returned from non-continuable exception"
            (error-object-message
              (cadr (%call-with-unwind-handler (lambda (o) (list 'h o))
                                               (lambda () (raise 7))))))
(test-equal "%call-with-unwind-handler: a native error arrives as a coded error object"
            'KP3002 (%call-with-unwind-handler (lambda (o) (error-object-code o))
                                               (lambda () (car 5))))
(test-equal "%call-with-unwind-handler: a non-procedure handler is a named type error"
            "type error in '%call-with-unwind-handler': expected procedure, got 42"
            (raised-msg (%call-with-unwind-handler 42 (lambda () 1))))
(test-equal "%call-with-unwind-handler: a non-procedure thunk is a named type error"
            "type error in '%call-with-unwind-handler': expected procedure, got 42"
            (raised-msg (%call-with-unwind-handler (lambda (o) 1) 42)))
(test-assert "%unwind-raise-empty?: answers a boolean with no raise pending"
             (boolean? (%unwind-raise-empty?)))
(test-assert "%pop-unwind-handler!: is a no-op when the top handler is not sticky"
             (begin (%pop-unwind-handler!) (%pop-unwind-handler!)
                    ;; a later raise must still reach the ordinary handler
                    (guard (e (#t #t)) (raise 'still-works))))
(test-equal "%unwind-to-escape: a non-continuation is a named type error"
            "type error in '%unwind-to-escape': expected escape continuation, got 42"
            (raised-msg (%unwind-to-escape 42)))
(test-assert "%unwind-to-escape: a full continuation is ignored"
             (begin (call/cc (lambda (k) (%unwind-to-escape k))) #t))
(test-assert "%unwind-to-escape: an expired escape continuation is ignored"
             (let ((saved #f))
               (call/ec (lambda (k) (set! saved k) 'in))
               (begin (%unwind-to-escape saved) #t)))
;; It really does run the intervening after-thunks — which is exactly why it
;; must not be reachable from user code: the bootstrapped dynamic-wind that
;; pushed those records then pops a stack that is already empty (#2037).
(test-equal "%unwind-to-escape: it runs the after-thunks down to the escape's depth"
            '(B1 B2 A2 A1)
            (let ((log '()))
              (guard (e (#t #t))
                (call/ec (lambda (k)
                           (dynamic-wind
                             (lambda () (set! log (cons 'B1 log)))
                             (lambda ()
                               (dynamic-wind (lambda () (set! log (cons 'B2 log)))
                                             (lambda () (%unwind-to-escape k) 'inner)
                                             (lambda () (set! log (cons 'A2 log)))))
                             (lambda () (set! log (cons 'A1 log)))))))
              (reverse log)))
;; FAIL: #2037 (%unwind-to-escape is reachable from user code and desynchronises
;; the wind stack; the underflow surfaces as a type error naming %pop-wind)
;; (test-equal "D1: %unwind-to-escape is purged from globals after bootstrap"
;;             'KP3001 (raised-code (eval '(%unwind-to-escape 1) (interaction-environment))))

;;; ------------------------------------------------------------------
;;; D2 — error taxonomy for the control primitives
;;; ------------------------------------------------------------------

(test-equal "D2: with-exception-handler non-procedure handler is KP3002"
            'KP3002 (raised-code (with-exception-handler 42 (lambda () 1))))
(test-equal "D2: with-exception-handler non-procedure thunk is KP3002"
            'KP3002 (raised-code (with-exception-handler (lambda (e) 1) 42)))
(test-equal "D2: call-with-values non-procedure producer is KP3002"
            'KP3002 (raised-code (call-with-values 42 list)))
(test-equal "D2: call/ec non-procedure receiver is KP3002"
            'KP3002 (raised-code (call/ec 42)))
(test-equal "D2: error-object-message on a non-error is KP3002"
            'KP3002 (raised-code (error-object-message 42)))
(test-equal "D2: error-object-irritants on a non-error is KP3002"
            'KP3002 (raised-code (error-object-irritants 42)))
(test-equal "D2: raise with no arguments is an arity error (KP3003)"
            'KP3003 (raised-code (eval '(raise) (interaction-environment))))
(test-equal "D2: with-exception-handler names itself and the offending value"
            "type error in 'with-exception-handler': expected procedure, got 42"
            (raised-msg (with-exception-handler 42 (lambda () 1))))
(test-equal "D2: call-with-values names itself and the offending value"
            "type error in 'call-with-values': expected procedure, got 42"
            (raised-msg (call-with-values 42 list)))
(test-equal "D2: an expired escape continuation reports its own message"
            "escape continuation invoked outside its dynamic extent"
            (let ((saved #f))
              (call/ec (lambda (k) (set! saved k) 'in))
              (raised-msg (saved 'x))))

;; FAIL: #2036 (dynamic-wind's argument type errors carry no diagnostic code and
;; drop the offending value, unlike every other control primitive)
;; (test-equal "D2: dynamic-wind non-procedure before is KP3002"
;;             'KP3002 (raised-code (dynamic-wind 1 (lambda () 2) (lambda () 3))))
;; (test-equal "D2: dynamic-wind names the offending value"
;;             "type error in 'dynamic-wind': expected procedure, got 1"
;;             (raised-msg (dynamic-wind 1 (lambda () 2) (lambda () 3))))
;; FAIL: #2036 (call/cc in tail position reports a non-procedure receiver as
;; KP3005 with the bare message "error"; the same call non-tail gives KP3002)
;; (test-equal "D2: call/cc non-procedure receiver is KP3002 in tail position too"
;;             'KP3002 ((lambda () (raised-code (call/cc 42)))))
;; (test-equal "D2: call/cc names itself and the offending value in tail position"
;;             "type error in 'call/cc': expected procedure, got 42"
;;             ((lambda () (raised-msg (call/cc 42)))))

;; call/cc in non-tail position is the discriminating control: it goes through
;; callWithCurrentContinuation rather than the tail_call_cc superinstruction.
(test-equal "D2: call/cc non-procedure receiver is KP3002 in non-tail position"
            'KP3002 (raised-code (list (call/cc 42))))
(test-equal "D2: call/cc names itself and the offending value in non-tail position"
            "type error in 'call/cc': expected procedure, got 42"
            (raised-msg (list (call/cc 42))))

;;; ------------------------------------------------------------------
;;; D5 — re-entrancy: every control callback must let a fiber park
;;; ------------------------------------------------------------------
;;;
;;; Each probe spawns a fiber that blocks on a rendezvous channel from inside
;;; one of primitives_control.zig's callback sites, plus a sender.  A site that
;;; could not park would deadlock or raise instead of producing the value.

(define (park-probe body)
  (let* ((ch (make-channel 0))
         (f (spawn (lambda () (body ch))))
         (g (spawn (lambda () (channel-send ch 'v)))))
    (fiber-join g)
    (fiber-join f)))

(test-equal "D5: a fiber parks inside a with-exception-handler thunk"
            'v (park-probe (lambda (ch)
                             (with-exception-handler (lambda (e) 'h)
                               (lambda () (channel-receive ch))))))
(test-equal "D5: a fiber parks inside a with-exception-handler handler"
            'v (park-probe (lambda (ch)
                             (with-exception-handler (lambda (e) (channel-receive ch))
                               (lambda () (raise-continuable 'x))))))
(test-equal "D5: a fiber parks inside a call-with-values producer"
            '(v) (park-probe (lambda (ch)
                               (call-with-values (lambda () (channel-receive ch)) list))))
(test-equal "D5: a fiber parks inside a call-with-values consumer"
            '(1 v) (park-probe (lambda (ch)
                                 (call-with-values (lambda () 1)
                                                   (lambda (x) (list x (channel-receive ch)))))))
(test-equal "D5: a fiber parks inside a dynamic-wind before-thunk"
            1 (park-probe (lambda (ch)
                            (dynamic-wind (lambda () (channel-receive ch))
                                          (lambda () 1) (lambda () 2)))))
(test-equal "D5: a fiber parks inside a dynamic-wind after-thunk"
            2 (park-probe (lambda (ch)
                            (dynamic-wind (lambda () 1) (lambda () 2)
                                          (lambda () (channel-receive ch))))))
(test-equal "D5: a fiber parks inside a guard body"
            'v (park-probe (lambda (ch) (guard (e (#t 'h)) (channel-receive ch)))))
(test-equal "D5: a fiber parks inside a call/cc receiver"
            'v (park-probe (lambda (ch) (call/cc (lambda (k) (channel-receive ch))))))
(test-equal "D5: a fiber parks inside a call/ec receiver"
            'v (park-probe (lambda (ch) (call/ec (lambda (k) (channel-receive ch))))))
(test-equal "D5: a fiber parks inside a SRFI 248 unwind handler"
            'v (park-probe (lambda (ch)
                             (with-unwind-handler (lambda (o k) (channel-receive ch))
                               (lambda () (raise-continuable 'x))))))

;;; ------------------------------------------------------------------
;;; Arity discipline of the native re-entrancy helpers
;;; ------------------------------------------------------------------
;;;
;;; The ordinary call path (callClosure / callWithArgs) validates arity; the
;;; native re-entrancy helpers callHandler / callThunk did not, so a
;;; wrong-arity handler, receiver or thunk ran anyway with its surplus
;;; parameters bound to whatever the register file happened to hold.
;;; dynamic-wind's three thunks — invoked from bootstrapped Scheme through the
;;; ordinary path — are the discriminating control, and are asserted above.
;;; Fixed in #2034: every hand-built re-entrant frame now binds its arguments
;;; through one validating helper (vm_calls.bindReentrantArgs), and the two
;;; handler-installing primitives check their thunk *before* the handler goes
;;; on the stack, so the failure is not delivered to the handler it describes.

(test-assert "arity: a 2-argument exception handler is rejected"
             (raises? (with-exception-handler (lambda (a b) 'h)
                        (lambda () (raise-continuable 'x)))))
(test-assert "arity: a 0-argument exception handler is rejected"
             (raises? (with-exception-handler (lambda () 'h)
                        (lambda () (raise-continuable 'x)))))
(test-assert "arity: a 3-argument exception handler is rejected"
             (raises? (with-exception-handler (lambda (a b c) (list a b c))
                        (lambda () (raise-continuable 'x)))))
(test-assert "arity: a 1-argument with-exception-handler thunk is rejected"
             (raises? (with-exception-handler (lambda (e) 'h) (lambda (x) x))))
(test-assert "arity: a 1-argument call-with-values producer is rejected"
             (raises? (call-with-values (lambda (x) 1) list)))
(test-assert "arity: a 2-argument call/cc receiver is rejected in non-tail position"
             (raises? (list (call/cc (lambda (a b) 1)))))
(test-assert "arity: a 2-argument call/ec receiver is rejected"
             (raises? (call/ec (lambda (a b) 1))))
(test-assert "arity: a 2-argument SRFI 248 unwind-handler thunk is rejected"
             (raises? (%call-with-unwind-handler (lambda (o) 'h) (lambda (x) x))))
;; The same defect in the shape that made it worst: with a live procedure in a
;; neighbouring register, the 3-argument handler's third parameter came back as
;; `#<builtin list>` — the caller's own register, deterministically, not merely
;; an undefined slot — because the hand-built frame never cleared past the one
;; argument it staged.  Rejecting the call is what removes the leak, so this
;; pins the leak's exact register layout rather than a second mechanism.
(test-assert "arity: a rejected handler cannot surface a caller's register"
             (raises? (list list (with-exception-handler
                                     (lambda (a b c) (list a b c))
                                   (lambda () (raise-continuable 'x))))))

;; A variadic handler is legal at any arity and must keep working.
(test-equal "arity: a variadic exception handler receives exactly one argument"
            '(x) (with-exception-handler (lambda args args)
                   (lambda () (raise-continuable 'x))))
(test-equal "arity: an optional-tail handler receives the condition"
            '(x ()) (with-exception-handler (lambda (a . rest) (list a rest))
                      (lambda () (raise-continuable 'x))))
;; tail_call_cc does check its receiver's arity — pinned so the fix for #2034
;; does not have to guess which half was already right.  The receiver must sit
;; in genuine tail position, so `raises?` wraps the call from outside.
(test-equal "arity: a 2-argument call/cc receiver IS rejected in tail position"
            "call/cc receiver: expected 1 argument, got arity 2"
            (raised-msg ((lambda () (call/cc (lambda (a b) 1))))))
(test-equal "arity: a 3-argument call/cc receiver IS rejected in tail position"
            "call/cc receiver: expected 1 argument, got arity 3"
            (raised-msg ((lambda () (call/cc (lambda (a b c) 1))))))

;;; ------------------------------------------------------------------
;;; Tail-position superinstructions vs. the ordinary call path
;;; ------------------------------------------------------------------
;;;
;;; compiler.zig dispatches (apply ...), (eval ...), (call/cc ...),
;;; (call-with-current-continuation ...) and (call-with-values ...) in tail
;;; position to hand-written superinstructions, guarded only by resolveLocal /
;;; resolveUpvalue — a *global* rebinding of the name is not consulted.

;; Local shadowing IS honoured; this is the control for #2033.
(test-equal "shadowing: a local binding of call/cc wins in tail position"
            'local ((lambda () (let ((call/cc (lambda (f) 'local)))
                                 ((lambda () (call/cc 42)))))))
(test-equal "shadowing: a local binding of call-with-values wins in tail position"
            'local ((lambda () (let ((call-with-values (lambda (a b) 'local)))
                                 ((lambda () (call-with-values 1 2)))))))
(test-equal "shadowing: a local binding of apply wins in tail position"
            'local ((lambda () (let ((apply (lambda a 'local)))
                                 ((lambda () (apply + '(1 2))))))))

;; FAIL: #2033 (a top-level redefinition of these five names is ignored in tail
;; position; the same call in non-tail position honours it)
;; (define (audit-user-call/cc f) 'user)
;; (test-equal "shadowing: a top-level redefinition of call/cc wins in tail position"
;;             'user (let ()
;;                     (define (call/cc f) 'user)
;;                     ((lambda () (call/cc (lambda (k) 1))))))

;;; ------------------------------------------------------------------
;;; Deeply nested dynamic-wind
;;; ------------------------------------------------------------------

;; FAIL: #2035 (819 nested dynamic-wind extents abort the form with KP9001
;; "internal error" — the register file stops growing at 4096 of a documented
;; 65536 — and the failure is catchable, unlike every other VM limit)
;; (test-equal "dynamic-wind: 1000 nested extents unwind cleanly"
;;             'bottom
;;             (letrec ((nd (lambda (n) (if (= n 0) 'bottom
;;                                          (dynamic-wind (lambda () 1)
;;                                                        (lambda () (nd (- n 1)))
;;                                                        (lambda () 2))))))
;;               (nd 1000)))

;;; ------------------------------------------------------------------
;;; Type errors stay catchable
;;; ------------------------------------------------------------------

(test-assert "catchable: call/cc type error" (guard (e (#t #t)) (call/cc 42)))
(test-assert "catchable: dynamic-wind type error" (guard (e (#t #t)) (dynamic-wind 1 2 3)))
(test-assert "catchable: call-with-values type error"
             (guard (e (#t #t)) (call-with-values 42 list)))
(test-assert "catchable: with-exception-handler type error"
             (guard (e (#t #t)) (with-exception-handler 42 (lambda () 1))))
(test-assert "catchable: call/ec type error" (guard (e (#t #t)) (call/ec "k")))

(let ((runner (test-runner-current)))
  (test-end "primitives_control audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
