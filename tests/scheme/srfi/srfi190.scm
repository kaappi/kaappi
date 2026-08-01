;; SRFI-190 (Coroutine Generators) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi190.scm
;;
;; Grown in audit v2 Phase 3.8 from 8 assertions. Three areas the smoke test
;; did not reach:
;;
;;  * the `yield` binding itself. SRFI 190's reference implementation binds
;;    it with a SRFI 139 syntax parameter; lib/srfi/190.sld instead makes it
;;    a lambda formal in the `coroutine-generator` template, which is a
;;    deliberately anaphoric binding. The assertions below pin both halves
;;    of what that has to mean: the coroutine's own `yield` reaches the body
;;    (including a body arriving through another macro's pattern variable,
;;    and a `yield` written in another macro's template), and an inner
;;    lexical rebinding inside the body still shadows it.
;;  * every shape of `define-coroutine-generator`, including the bare-name
;;    form, which per the spec defines a single generator OBJECT rather than
;;    a constructor -- so it is exhausted after one traversal.
;;  * resumption across a returned native frame. `make-coroutine-generator`
;;    is call/cc-based, so SRFI 190 inherits #2060 exactly: a coroutine
;;    generator resumed inside any SRFI 1 higher-order procedure raises.

(import (scheme base) (scheme process-context) (srfi 1) (srfi 158) (srfi 190) (srfi 64))

(test-begin "srfi-190")

;;; --- coroutine-generator: the spec's own example and its neighbours ---
(test-equal "coroutine-generator: the spec's own do-loop example"
  '(0 1 2)
  (generator->list
    (coroutine-generator
      (do ((i 0 (+ i 1)))
          ((= i 3))
        (yield i)))))

(test-equal "coroutine-generator: empty"
  '()
  (generator->list (coroutine-generator (values))))

(test-equal "coroutine-generator: a body that yields nothing at all"
  '()
  (generator->list (coroutine-generator 42)))

(test-equal "coroutine-generator: single value"
  '(42)
  (generator->list (coroutine-generator (yield 42))))

(test-equal "coroutine-generator: strings"
  '("a" "b" "c")
  (generator->list
    (coroutine-generator
      (for-each yield '("a" "b" "c")))))

(test-equal "coroutine-generator: multiple yields"
  '(1 2 3 4 5)
  (generator->list
    (coroutine-generator
      (yield 1) (yield 2) (yield 3) (yield 4) (yield 5))))

;;; exhaustion is sticky: once the body has returned, every further call
;;; keeps answering the eof object.
(test-equal "coroutine-generator: exhaustion is sticky"
  '(1 #t #t #t)
  (let ((g (coroutine-generator (yield 1))))
    (list (g) (eof-object? (g)) (eof-object? (g)) (eof-object? (g)))))

;;; a generator is an ordinary procedure of no arguments
(test-assert "a coroutine generator is a procedure"
  (procedure? (coroutine-generator (yield 1))))

;;; two generators built from the same form are independent
(test-equal "two generators from the same form are independent"
  '(0 0 1 1)
  (let ((mk (lambda () (coroutine-generator (yield 0) (yield 1)))))
    (let ((g1 (mk)) (g2 (mk)))
      (list (g1) (g2) (g1) (g2)))))

;;; the SRFI says yield takes one argument
(test-error "yield rejects two arguments"
  (generator->list (coroutine-generator (yield 1 2))))

;;; "It is an error to evaluate yield outside the body of a coroutine
;;; generator" -- here it is simply unbound.
(test-error "yield is not bound outside a coroutine generator"
  (eval '(yield 1) (environment '(scheme base) '(srfi 190))))

;;; --- the yield binding.  lib/srfi/190.sld introduces `yield` as a lambda
;;; formal in the template rather than as a SRFI 139 syntax parameter, so
;;; these pin what that anaphoric binding has to reach. ---

(test-equal "the coroutine's yield wins over a surrounding lexical yield"
  '(1 2)
  (let ((yield (lambda (x) (list 'user x))))
    (generator->list (coroutine-generator (yield 1) (yield 2)))))

(define-syntax srfi190-gen-of
  (syntax-rules () ((_ v) (coroutine-generator (yield v) (yield v)))))
(test-equal "a yield written in another macro's template still binds"
  '(5 5)
  (generator->list (srfi190-gen-of 5)))

(define-syntax srfi190-gen-body
  (syntax-rules () ((_ b ...) (coroutine-generator b ...))))
(test-equal "a body carried through another macro's pattern variable still binds"
  '(1 2)
  (generator->list (srfi190-gen-body (yield 1) (yield 2))))

(test-equal "an inner lexical rebinding inside the body shadows the coroutine's yield"
  '(real)
  (generator->list
    (coroutine-generator
      (let ((yield (lambda (v) 'ignored))) (yield 99))
      (yield 'real))))

(test-assert "yield is a first-class procedure inside the body"
  (let ((seen #f))
    (let ((g (coroutine-generator (set! seen (procedure? yield)) (yield 1))))
      (g)
      seen)))

;;; a nested coroutine generator gets its own yield
(test-equal "a nested coroutine generator rebinds yield for its own body"
  '(i1 i2)
  (generator->list
    (coroutine-generator
      (let ((inner (coroutine-generator (yield 'i1) (yield 'i2))))
        (yield (inner))
        (yield (inner))))))

;;; --- define-coroutine-generator: both spec-stated shapes ---
(define-coroutine-generator (counting n)
  (do ((i 0 (+ i 1)))
      ((= i n))
    (yield i)))

(test-equal "define-coroutine-generator (name . formals): with args"
  '(0 1 2 3 4)
  (generator->list (counting 5)))

(test-equal "define-coroutine-generator (name . formals): zero iterations"
  '()
  (generator->list (counting 0)))

(test-equal "define-coroutine-generator: a fresh generator per call"
  '(0 0)
  (list ((counting 3)) ((counting 3))))

(define-coroutine-generator (srfi190-nullary)
  (yield 'a))
(test-equal "define-coroutine-generator: empty formals list"
  '(a) (generator->list (srfi190-nullary)))

(define-coroutine-generator (srfi190-variadic . args)
  (for-each yield args))
(test-equal "define-coroutine-generator: variadic formals"
  '(1 2 3) (generator->list (srfi190-variadic 1 2 3)))

;;; the bare-name shape expands to (define <name> (coroutine-generator ...)),
;;; i.e. one generator object, not a constructor -- so it is exhausted after
;;; a single traversal.
(define-coroutine-generator srfi190-bare (yield 'x) (yield 'y))
(test-equal "define-coroutine-generator <name>: first traversal"
  '(x y) (generator->list srfi190-bare))
(test-equal "define-coroutine-generator <name>: it is one generator, now spent"
  '() (generator->list srfi190-bare))

(define-coroutine-generator (fibonacci-gen n)
  (let loop ((a 0) (b 1) (count 0))
    (when (< count n)
      (yield a)
      (loop b (+ a b) (+ count 1)))))

(test-equal "define-coroutine-generator: fibonacci"
  '(0 1 1 2 3 5 8)
  (generator->list (fibonacci-gen 7)))

;;; --- composition with the rest of SRFI 158 ---
(test-equal "a coroutine generator composes with gtake"
  '(1 2)
  (generator->list
    (gtake (coroutine-generator (yield 1) (yield 2) (yield 3) (yield 4)) 2)))

(test-equal "a coroutine generator composes with gmap"
  '(2 4 6)
  (generator->list
    (gmap (lambda (x) (* 2 x))
          (coroutine-generator (yield 1) (yield 2) (yield 3)))))

(test-equal "a coroutine generator composes with generator-fold"
  6
  (generator-fold + 0 (coroutine-generator (yield 1) (yield 2) (yield 3))))

;;; --- resumption across a returned native frame (#2060).
;;;
;;; make-coroutine-generator is built on call/cc, so a resume that has to
;;; cross a native driver's already-returned frame raises. SRFI 1's
;;; higher-order procedures are still native drivers; (scheme base)'s
;;; map/for-each were trampolined by #1347 and are the control. ---

(test-equal "control: a coroutine generator resumes under (scheme base) map"
  '(1 2 3)
  (let ((g (coroutine-generator (yield 1) (yield 2) (yield 3))))
    (map (lambda (i) (g)) '(a b c))))

(test-equal "control: yield inside a (scheme base) for-each"
  '(1 2 3)
  (generator->list (coroutine-generator (for-each yield '(1 2 3)))))

;; FAIL: #2060 (SRFI 1 procedures are native drivers; a resume cannot cross them)
;; (test-equal "a coroutine generator resumes under SRFI 1 fold"
;;   '(3 2 1)
;;   (let ((g (coroutine-generator (yield 1) (yield 2) (yield 3))))
;;     (fold (lambda (i acc) (cons (g) acc)) '() '(a b c))))
;; FAIL: #2060 (same, with the yield itself inside the native driver)
;; (test-equal "yield inside a SRFI 1 driver"
;;   '(1 2 3)
;;   (generator->list (coroutine-generator (any (lambda (x) (yield x) #f) '(1 2 3)))))

(test-error "a coroutine generator cannot resume under SRFI 1 fold (see #2060)"
  (let ((g (coroutine-generator (yield 1) (yield 2) (yield 3))))
    (fold (lambda (i acc) (cons (g) acc)) '() '(a b c))))
(test-error "yield inside a SRFI 1 driver cannot resume (see #2060)"
  (generator->list (coroutine-generator (any (lambda (x) (yield x) #f) '(1 2 3)))))

;;; --- the derived cond-expand feature id (#1649) ---
(test-equal "cond-expand srfi-190" 'yes (cond-expand (srfi-190 'yes) (else 'no)))

(let ((runner (test-runner-current)))
  (test-end "srfi-190")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
