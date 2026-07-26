;; SRFI 149 (Basic Syntax-rules Template Extensions) tests. Kaappi's
;; expander already implements both of this SRFI's extensions (consecutive
;; ellipses; excess-ellipsis replication for mixed-depth siblings) with no
;; engine changes -- see lib/srfi/149.sld's header for the full rationale
;; and src/tests_macros.zig for the matching Zig-level unit tests. Part of
;; issue #1699 (SRFI macro & syntax extension libraries).
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi149.scm

(import (scheme base) (scheme process-context) (srfi 64) (srfi 149))

(test-begin "srfi-149")

;;; --- the spec's own example 1: consecutive ellipses flatten a
;;; depth-2 variable one level, written without the extra parens R7RS's
;;; own stricter grammar would otherwise require ---
(define-syntax my-append
  (syntax-rules ()
    ((_ (a ...) ...) (list a ... ...))))

(test-equal '(1 2 3 4 5 6) (my-append (1 2 3) (4 5 6)))
(test-equal '() (my-append))
(test-equal '(1) (my-append (1)))

;;; --- the spec's own example 2: a mixed-depth sibling pair (a at depth
;;; 1, b at depth 2) sharing one ellipsis-driven template position; the
;;; excess ellipsis consuming b's extra nesting replicates a (already
;;; resolved to a scalar one level up) at the innermost position ---
(define-syntax foo
  (syntax-rules ()
    ((_ (a b ...) ...) (list (list (list 'a 'b) ...) ...))))

(test-equal '(((bar 1) (bar 2)) ((baz 3) (baz 4)))
            (foo (bar 1 2) (baz 3 4)))

;;; --- consecutive-ellipsis flatten composes with a following fixed
;;; tail: the flatten mechanism must resume ordinary template
;;; instantiation for whatever follows it, not swallow the rest ---
(define-syntax flatten-then-tail
  (syntax-rules ()
    ((_ (a ...) ... last) (list a ... ... last))))

(test-equal '(1 2 3 4 5 done) (flatten-then-tail (1 2) (3 4 5) 'done))

;;; --- ordinary depth-0 broadcast (the R7RS baseline this SRFI extends,
;;; unaffected) still works correctly alongside the new forms ---
(define-syntax broadcast
  (syntax-rules ()
    ((_ x (y ...)) (list (list x y) ...))))

(test-equal '((k 1) (k 2) (k 3)) (broadcast 'k (1 2 3)))

(let ((runner (test-runner-current)))
  (test-end "srfi-149")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
