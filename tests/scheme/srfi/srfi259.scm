;; SRFI 229 (Tagged Procedures) + SRFI 259 (Tagged procedures with type
;; safety) conformance tests.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi259.scm

(import (scheme base) (srfi 229) (srfi 259) (scheme process-context) (srfi 64))

(test-begin "srfi-259")

;;; ------------------------------------------------------------------
;;; SRFI 229 — the primitive tagged-procedure layer
;;; ------------------------------------------------------------------

(define f (lambda/tag 42 (x) (* x x)))
(test-equal "229: is a tagged procedure" #t (procedure/tag? f))
(test-equal "229: behaves like underlying" 9 (f 3))
(test-equal "229: tag round-trips" 42 (procedure-tag f))

;; Ordinary procedures are not tagged.
(test-equal "229: plain procedure not tagged" #f (procedure/tag? car))
(test-equal "229: lambda not tagged" #f (procedure/tag? (lambda (x) x)))

;; Two tagged procedures are distinct even with the same body.
(define f* (lambda/tag 43 (x) (* x x)))
(test-equal "229: distinct procedures" #f (eqv? f f*))
(test-equal "229: second tag" 43 (procedure-tag f*))

;; The tag expression sees the enclosing environment and is evaluated once.
(define g
  (let ((y 10))
    (lambda/tag y () (set! y (+ y 1)) y)))
(test-equal "229: tag captured at creation" 10 (procedure-tag g))
(test-equal "229: call mutates closed-over state" 11 (g))
(test-equal "229: tag unchanged after call" 10 (procedure-tag g))

;; case-lambda/tag with a mutable tag object.
(define h
  (let ((box (vector #f)))
    (case-lambda/tag box
      (() (vector-ref box 0))
      ((val) (vector-set! box 0 val)))))
(h 1)
(test-equal "229: case-lambda/tag tag object" 1 (vector-ref (procedure-tag h) 0))
(test-equal "229: case-lambda/tag dispatch" 1 (h))

;;; ------------------------------------------------------------------
;;; SRFI 259 — type-safe protocols
;;; ------------------------------------------------------------------

(define-procedure-tag make-labelled labelled? label-of)

(define sq (make-labelled 'square (lambda (x) (* x x))))
(test-equal "259: constructed procedure calls through" 25 (sq 5))
(test-equal "259: predicate true for own protocol" #t (labelled? sq))
(test-equal "259: accessor round-trips tag" 'square (label-of sq))

;; The constructor returns a fresh procedure, distinct from the underlying one.
(define base-proc (lambda (x) (* x x)))
(define tagged-proc (make-labelled 'sq base-proc))
(test-equal "259: constructor yields a fresh procedure"
            #f (eqv? base-proc tagged-proc))
(test-equal "259: underlying stays untagged" #f (labelled? base-proc))

;; Predicate is false on ordinary procedures and non-procedures.
(test-equal "259: predicate false on plain procedure" #f (labelled? car))
(test-equal "259: predicate false on non-procedure" #f (labelled? 42))
(test-equal "259: predicate false on '()" #f (labelled? '()))

;; The tag value can be any object, including a mutable one shared by reference.
(define state (vector 'init))
(define stateful (make-labelled state (lambda () 'ok)))
(vector-set! (label-of stateful) 0 'changed)
(test-equal "259: tag object shared by identity" 'changed (vector-ref state 0))

;;; --- type safety: protocols are mutually isolated -------------------

(define-procedure-tag make-metered metered? meter-of)

(define both (make-metered 100 (make-labelled 'L (lambda (a b) (+ a b)))))
(test-equal "259: still calls through after two tags" 7 (both 3 4))
(test-equal "259: first protocol predicate" #t (labelled? both))
(test-equal "259: second protocol predicate" #t (metered? both))
(test-equal "259: first protocol tag preserved" 'L (label-of both))
(test-equal "259: second protocol tag" 100 (meter-of both))

;; A procedure tagged only in protocol A is invisible to protocol B.
(test-equal "259: protocol B predicate false on A-only" #f (metered? sq))
(test-equal "259: protocol A predicate false on B-only"
            #f (labelled? (make-metered 5 (lambda () #t))))

;; Accessor signals an error on a procedure not tagged in its protocol,
;; and on an ordinary / untagged procedure.
(test-error "259: accessor errors on wrong protocol" (meter-of sq))
(test-error "259: accessor errors on plain procedure" (label-of car))
(test-error "259: accessor errors on untagged lambda"
            (label-of (lambda (x) x)))

;; Re-tagging under the same protocol replaces that protocol's tag while
;; leaving other protocols' tags intact.
(define relabelled (make-labelled 'L2 both))
(test-equal "259: same-protocol tag replaced" 'L2 (label-of relabelled))
(test-equal "259: other protocol tag survives replacement"
            100 (meter-of relabelled))
(test-equal "259: still calls through after re-tag" 11 (relabelled 5 6))

;; Independent protocols with a shared tag object stay independent.
(define shared 'shared-tag)
(define p (make-labelled shared (lambda () 1)))
(define q (make-metered shared (lambda () 2)))
(test-equal "259: independent A tag" 'shared-tag (label-of p))
(test-equal "259: independent B tag" 'shared-tag (meter-of q))
(test-equal "259: A not tagged in B" #f (metered? p))
(test-equal "259: B not tagged in A" #f (labelled? q))

;; SRFI 259 tags are opaque: a SRFI 229 consumer sees only the opaque
;; tag-set object, never the individual protocol tags.
(test-equal "259: 229 sees the procedure as tagged" #t (procedure/tag? sq))

(let ((runner (test-runner-current)))
  (test-end "srfi-259")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
