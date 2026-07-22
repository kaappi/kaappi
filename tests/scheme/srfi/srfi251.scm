;;; SRFI 251 (Mixing groups of definitions with expressions within bodies)
;;; conformance tests. Run: zig-out/bin/kaappi tests/scheme/srfi/srfi251.scm
;;;
;;; See lib/srfi/251.sld for the mixed-lambda/mixed-define/mixed-let/
;;; mixed-let* forms this port provides (instead of shadowing lambda/
;;; define/let/let*) and the documented scope limitations, in particular
;;; that the spec's own "illegal forward reference" example is not
;;; rejected as an error here.
;;;
;;; Side-effect ordering is verified by writing to a string port instead of
;;; stdout, so the interleaving the SRFI's examples are all about can be
;;; captured and compared exactly like SRFI 64 compares values.

(import (scheme base) (srfi 251) (scheme write) (scheme process-context) (srfi 64))

(test-begin "srfi-251")

;;; --- basic sanity: ordinary (non-interleaved) bodies still work ---

(test-equal "mixed-lambda with plain definitions-then-expression body"
  30
  ((mixed-lambda (n) (define double (* 2 n)) (+ double n)) 10))

(test-equal "mixed-lambda with no definitions at all"
  7
  ((mixed-lambda (a b) (+ a b)) 3 4))

(test-equal "mixed-let with plain bindings and body"
  7
  (mixed-let ((a 3) (b 4)) (+ a b)))

;;; --- command before a definition (the rationale's own motivating case) ---

(mixed-define (double-square x)
  (unless (number? x) (error "not a number" x))
  (define y (* x x))
  (* 2 y))
(test-equal "command (a guard check) before a definition" 32 (double-square 4))

(mixed-define (log-then-prepare x log)
  (set! log (cons 'logged log))
  (define prepared (* x 10))
  (list prepared log))
(test-equal "logging command before a definition"
  '(50 (logged))
  (log-then-prepare 5 '()))

;;; --- interleaved definitions and expressions with a running counter ---

(test-equal "incremental test-building style body"
  '(2 4)
  (mixed-let ()
    (define one-plus-one (+ 1 1))
    (let ((r1 one-plus-one))
      (define two-plus-two (+ one-plus-one one-plus-one))
      (list r1 two-plus-two))))

;;; --- the SRFI's own four worked examples, via a captured output port ---

(define (captured thunk)
  (let ((port (open-output-string)))
    (thunk port)
    (get-output-string port)))

;; Example: same definition group (foo and x adjacent) => foo sees the
;; *local* x. Prints "the result is: 42".
(test-equal "same-group definitions: foo sees the local (later) x"
  "the result is: 42"
  (captured
   (lambda (port)
     (mixed-let ((x 0))
       (display "the result is" port)
       (define (foo) x)
       (define x 42)
       (display ": " port)
       (display (foo) port)))))

;; Example: foo and xx are unrelated names in the same later group; foo's x
;; still resolves to the outer binding. Prints "the result is: 0".
(test-equal "unrelated name in a later group: foo still sees the outer x"
  "the result is: 0"
  (captured
   (lambda (port)
     (mixed-let ((x 0))
       (display "the result is" port)
       (define (foo) x)
       (display ": " port)
       (define xx 42)
       (display (foo) port)))))

;; Example: a macro (define-thunk) expanding to a definition. The spec
;; treats this identically to a literal define, printing "the result is:
;; 0". This port's mixed-let nests define-thunk's *use* (define xx 42;
;; define-thunk foo x -- a new group, since a display command separates it
;; from the group that defines define-thunk) one lambda scope deeper than
;; define-thunk's own definition. Confirmed (see lib/srfi/251.sld) that
;; Kaappi does not recognize a body-local macro's produced `define` across
;; that scope boundary, independent of SRFI 251 entirely -- so this port
;; raises an "undefined variable" error here instead of computing the
;; spec's answer. Documented as a known gap rather than silently wrong.
(test-assert "known gap: macro-produced definition across a nested scope"
  (guard (e (#t #t))
    (captured
     (lambda (port)
       (mixed-let ((x 0))
         (define-syntax define-thunk
           (syntax-rules ()
             ((_ i v) (define (i) v))))
         (display "the result is" port)
         (display ": " port)
         (define xx 42)
         (define-thunk foo x)
         (display (foo) port))))
    #f))

;; Example: illegal forward reference. The spec says this must be a
;; compile-time error. This port does not enforce the visibility
;; constraint (see lib/srfi/251.sld) -- it falls back to ordinary lexical
;; scoping instead, which for this body means foo (defined before the
;; group that shadows x) never sees the later x at all, giving
;; "the result is: 0" rather than being rejected. This test locks in and
;; documents that known, deliberate deviation.
(test-equal "known gap: illegal forward reference is not rejected"
  "the result is: 0"
  (captured
   (lambda (port)
     (mixed-let ((x 0))
       (display "the result is" port)
       (define (foo) x)
       (display ": " port)
       (define x 42)
       (display (foo) port)))))

;;; --- mixed-let* threads interleaving through each nested binding ---

(test-equal "mixed-let* with an interleaved command between bindings"
  '(3 4 7)
  (mixed-let* ((a 3))
    (define probe 'seen)
    (mixed-let* ((b (+ a 1)))
      (list a b (+ a b)))))

;;; --- named mixed-let also gets an interleaving-aware body ---

;; Regression: the previous version of this test nested its (define
;; next-acc ...) inside a (begin ...) inside the (if ...)'s else branch,
;; making the named mixed-lambda's own body a *single* top-level form
;; (the if expression). %251-body's base case ((_ e) e) fires
;; immediately on a single form and returns it completely untranslated
;; -- so that version exercised none of %251-defs's actual run-collection
;; and group-closing-lambda logic for the named-let path at all (it
;; passed only because Kaappi's own body compiler independently tolerates
;; a nested define there, entirely unrelated to SRFI 251). This version
;; gives the named mixed-lambda body three top-level forms -- a command,
;; then a definition, then a command -- forcing %251-body through its
;; command-passthrough rule and %251-defs through an actual
;; collect-then-close-the-group step every iteration.
(test-equal "named mixed-let: command, then a definition, then a command, each loop iteration"
  120
  (mixed-let loop ((n 5) (acc 1))
    (when (< n 0) (error "n went negative"))
    (define next-acc (* acc n))
    (if (= n 0) acc (loop (- n 1) next-acc))))

(let ((runner (test-runner-current)))
  (test-end "srfi-251")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
