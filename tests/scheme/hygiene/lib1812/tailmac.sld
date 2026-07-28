;; Fixture for #1812: a macro exported so it is USED FROM OUTSIDE its own
;; defining library (cross-boundary, the case this issue is about), whose
;; expansion calls a TRUE (scheme base) procedure (call-with-values) in TAIL
;; position -- exactly like SRFI 248's guard macro does internally.
;; call-with-values, raise-continuable, and friends are merely re-exported/
;; imported by a library, not genuinely library-internal helpers, so a
;; reference to one must NOT be marked with this library's def-env prefix:
;; compiler.zig's is_tail dispatch (compileCallWithValuesTail) recognizes
;; call-with-values only by its exact bare name, and silently loses that
;; dedicated tail-call handling for any other spelling. Caught only by
;; tracing a real regression this fix introduced in SRFI 248's own guard
;; macro during development (see expander.zig's renameForHygiene) -- SRFI
;; 248's own test suite (tests_srfi248.zig / tests/scheme/srfi/srfi248.scm)
;; is what actually exercises the deeper continuation-interaction failure
;; mode; this fixture just pins the narrower "stays unprefixed" property
;; directly, at a cross-library use site (the case that actually broke).
(define-library (lib1812 tailmac)
  (import (scheme base))
  (export cwv-tail)
  (begin
    (define-syntax cwv-tail
      (syntax-rules ()
        ((_ producer consumer)
         (call-with-values (lambda () producer) consumer))))))
