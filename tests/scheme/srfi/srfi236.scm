;; SRFI-236 (Evaluating expressions in an unspecified order) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi236.scm
;;
;; One form. The spec: "(independently <expression> ...)" evaluates the
;; expressions "in an unspecified order and discards their return values.
;; The result of the independently expression is unspecified." Plus one
;; constraint that is easy to miss: "Although the order of evaluation is
;; otherwise unspecified, the effect of any concurrent evaluation of the
;; <expressions> is constrained to be consistent with some sequential order
;; of evaluation." And, from the rationale, an independently form "need not
;; contain any expression."
;;
;; So essentially NOTHING about order may be asserted, and neither may the
;; result value. Every assertion below tests one of the three things the
;; spec does promise -- every expression is evaluated, exactly once, and
;; the whole thing is well-defined for zero expressions -- or pins this
;; implementation's own deterministic behaviour explicitly labelled as such.
;;
;; Grown in audit v2 Phase 3.8 from 7 assertions. This implementation
;; happens to evaluate right-to-left (it is a `let`, and Kaappi's `let`
;; evaluates its inits right-to-left; chibi does too, which is exactly why
;; an order-assuming test here would be a portability trap rather than a
;; conformance test).

(import (scheme base) (scheme process-context) (srfi 236) (srfi 64))

(test-begin "srfi-236")

;;; --- zero expressions: legal, unlike begin ---
;; The spec itself says independently's result "is unspecified" -- this
;; does NOT assert spec-mandated behavior. It pins down the ported
;; reference implementation's own deterministic base case (a bare (values)
;; call when no expressions remain) as a regression check, so an accidental
;; future change to that base case doesn't go unnoticed.
(call-with-values (lambda () (independently))
  (lambda vals
    (test-equal "independently: zero expressions returns zero values (this implementation's behavior, not a spec guarantee)" '() vals)))

(test-assert "independently: zero expressions is accepted at all"
  (begin (independently) #t))

;;; --- every expression is evaluated ---

(let ((p (cons 0 0)))
  (independently (set-car! p 1) (set-cdr! p 2))
  (test-equal "independently: both side effects occur" '(1 . 2) p))

(let ((log '()))
  (independently
    (set! log (cons 'a log))
    (set! log (cons 'b log))
    (set! log (cons 'c log)))
  (test-equal "independently: all three side effects occur (order unspecified)" 3 (length log))
  (test-assert "independently: side effect a occurred" (memq 'a log))
  (test-assert "independently: side effect b occurred" (memq 'b log))
  (test-assert "independently: side effect c occurred" (memq 'c log)))

;;; --- exactly once, and at scale.  A count is order-independent, so this
;;; is assertable where a log order is not. ---

(let ((n 0))
  (independently
    (set! n (+ n 1)) (set! n (+ n 1)) (set! n (+ n 1)) (set! n (+ n 1))
    (set! n (+ n 1)) (set! n (+ n 1)) (set! n (+ n 1)) (set! n (+ n 1))
    (set! n (+ n 1)) (set! n (+ n 1)) (set! n (+ n 1)) (set! n (+ n 1))
    (set! n (+ n 1)) (set! n (+ n 1)) (set! n (+ n 1)) (set! n (+ n 1))
    (set! n (+ n 1)) (set! n (+ n 1)) (set! n (+ n 1)) (set! n (+ n 1)))
  (test-equal "independently: twenty expressions each run exactly once" 20 n))

(let ((n 0))
  (independently (set! n (+ n 1)))
  (test-equal "independently: a single expression runs exactly once" 1 n))

;; Order is unspecified, so the only order-independent statement about the
;; log is "each tag appears exactly once" -- checked by counting rather than
;; by comparing against any particular sequence.
(define (srfi236-count x lst)
  (let loop ((l lst) (n 0))
    (cond ((null? l) n)
          ((eqv? (car l) x) (loop (cdr l) (+ n 1)))
          (else (loop (cdr l) n)))))

(let ((seen '()))
  (independently
    (set! seen (cons 1 seen))
    (set! seen (cons 2 seen))
    (set! seen (cons 3 seen))
    (set! seen (cons 4 seen))
    (set! seen (cons 5 seen)))
  (test-equal "independently: five expressions leave five log entries" 5 (length seen))
  (for-each
    (lambda (tag)
      (test-equal (string-append "independently: expression "
                                 (number->string tag)
                                 " ran exactly once")
        1 (srfi236-count tag seen)))
    '(1 2 3 4 5)))

;;; --- the spec's own example ---
(define (set-car+cdr! p x y)
  (independently
    (set-car! p x)
    (set-cdr! p y)))
(let ((p (cons #f #f)))
  (set-car+cdr! p 'x 'y)
  (test-equal "independently: spec's set-car+cdr! example" '(x . y) p))

;;; --- expressions whose values are discarded, of every value count.  The
;;; spec says the return values are discarded, so an expression returning
;;; zero or several values must be as acceptable as one returning a single
;;; value. ---

(let ((n 0))
  (independently (begin (set! n (+ n 1)) (values)))
  (test-equal "independently: an expression returning zero values is accepted" 1 n))

(let ((n 0))
  (independently (begin (set! n (+ n 1)) (values 1 2 3)))
  (test-equal "independently: an expression returning several values is accepted" 1 n))

(let ((n 0))
  (independently (begin (set! n (+ n 1)) (values))
                 (begin (set! n (+ n 10)) (values 1 2)))
  (test-equal "independently: mixed value counts in one form" 11 n))

;;; --- hygiene: the reference implementation binds one template-introduced
;;; temporary per expression, so a use-site variable of the same spelling
;;; must not be captured by it ---

(test-equal "independently: a use-site variable named tmp is not captured"
  1
  (let ((tmp 0))
    (independently (set! tmp 1))
    tmp))

(test-equal "independently: a use-site variable named tmp survives several expressions"
  3
  (let ((tmp 0) (other 0))
    (independently (set! other 1) (set! tmp 3))
    tmp))

;;; --- composition ---

(test-equal "independently: nests inside itself"
  111
  (let ((n 0))
    (independently
      (independently (set! n (+ n 1)) (set! n (+ n 10)))
      (set! n (+ n 100)))
    n))

(test-equal "independently: works in a definition context body"
  5
  (let ()
    (define n 0)
    (independently (set! n 5))
    n))

(test-equal "independently: works inside a lambda body"
  7
  ((lambda () (let ((n 0)) (independently (set! n 7)) n))))

;;; an escaping continuation out of one expression abandons the form
(test-equal "independently: a continuation may escape from one expression"
  'escaped
  (call-with-current-continuation
    (lambda (k)
      (let ((n 0))
        (independently (set! n 1) (k 'escaped) (set! n 2))
        'not-reached))))

;;; --- the derived cond-expand feature id (#1649) ---
(test-equal "cond-expand srfi-236" 'yes (cond-expand (srfi-236 'yes) (else 'no)))

(let ((runner (test-runner-current)))
  (test-end "srfi-236")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
