;; SRFI 147 (Custom Macro Transformers) tests. Unlike SRFI 139/149, this
;; genuinely needed an engine change: compileDefineSyntax/compileLetSyntax/
;; compileLetrecSyntax (src/compiler_macro.zig) now resolve a
;; transformer-spec through resolveTransformerSpec before parsing it, so a
;; macro use that itself expands to a literal (syntax-rules ...) form is
;; accepted anywhere a transformer-spec is expected. See lib/srfi/147.sld's
;; header for the full rationale and the deliberately-deferred grammar
;; alternatives (bare-keyword aliasing, begin-wrapped definitions). Part of
;; issue #1699 (SRFI macro & syntax extension libraries).
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi147.scm

(import (scheme base) (scheme process-context) (scheme eval) (scheme repl) (srfi 64) (srfi 147))

(test-begin "srfi-147")

;;; --- the spec's own worked example: syntax-rules* automatically wraps
;;; multi-form templates in begin, so a transformer-spec can be written
;;; without an explicit (begin ...) around a multi-statement body ---
(define-syntax syntax-rules*
  (syntax-rules ()
    ((_ (literal ...) ((keyword . pattern) . template) ...)
     (syntax-rules (literal ...) ((keyword . pattern) (begin . template)) ...))))

;;; --- define-syntax accepts a custom transformer ---
(define-syntax bar (syntax-rules* () ((bar a b) (+ a b) (* a b))))
(test-equal 30 (bar 5 6))

;;; --- let-syntax accepts a custom transformer, multiple bindings in one
;;; form (exercises the per-binding loop specifically) ---
(test-equal
 '(12 9)
 (let-syntax ((foo (syntax-rules* () ((foo a b) (+ a b) (* a b))))
              (baz (syntax-rules* () ((baz a) (- a) (- (- a))))))
   (list (foo 3 4) (baz 9))))

;;; --- letrec-syntax accepts a custom transformer ---
(test-equal
 20
 (letrec-syntax ((qux (syntax-rules* () ((qux a b) (+ a b) (* a b)))))
   (qux 2 10)))

;;; --- resolution loops through multiple expansion steps: an alias macro
;;; expands to a syntax-rules* call, which itself expands to a literal
;;; syntax-rules form ---
(define-syntax alias-of-syntax-rules*
  (syntax-rules () ((_ spec) (syntax-rules* () . spec))))

(test-equal
 2
 (let-syntax ((multi (alias-of-syntax-rules* (((multi a b) (+ a b) (* a b))))))
   (multi 1 2)))

;;; --- deliberately deferred: a bare keyword aliasing an existing one
;;; (including a builtin special form) is not supported ---
(test-equal #t (guard (e (#t #t)) (eval '(let-syntax ((my-if if)) (my-if #t 1 2)) (interaction-environment)) #f))

;;; --- deliberately deferred: a macro use expanding to
;;; (begin <definition>... <transformer-spec>) is not supported ---
(test-equal
 #t
 (guard (e (#t #t))
   (eval '(let-syntax ((foo (begin (define-syntax helper (syntax-rules () ((_ x) x)))
                                    (syntax-rules () ((foo a) (helper a))))))
            (foo 1))
         (interaction-environment))
   #f))

;;; --- a transformer-spec that resolves to neither syntax-rules nor a
;;; registered macro is a compile error, not a silent success ---
(test-equal #t (guard (e (#t #t)) (eval '(let-syntax ((oops (not-a-macro))) 1) (interaction-environment)) #f))

(let ((runner (test-runner-current)))
  (test-end "srfi-147")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
