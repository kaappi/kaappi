;; Fixture for #1812: a macro (outer-match) whose template defines ANOTHER
;; macro via letrec-syntax (inner), which itself references a
;; library-internal helper -- mirroring SRFI 41's stream-match, which
;; defines smp/smt via letrec-syntax referencing stream-null?/stream-car/etc.
;;
;; The outer expansion (outer-match, def_env = this library) walks and
;; hygiene-renames every free identifier in its WHOLE template, including
;; ones inside the nested letrec-syntax spec for inner -- so helper4 gets
;; this library's def-env prefix right there. inner is then defined via
;; letrec-syntax at the *use site* (def_env = null, it's not a library
;; form), so when inner is later invoked, its own expansion must recognize
;; the already-prefixed helper4 reference as "already renamed" rather than
;; wrapping it in a fresh __hyg_ gensym, which would sever it from anything
;; the runtime's def-env prefix resolver can find (renameForHygiene's
;; top-of-function "already renamed" check).
(define-library (lib1812 nestedmac)
  (import (scheme base))
  (export outer-match)
  (begin
    (define (helper4 x) (* x 3))
    (define-syntax outer-match
      (syntax-rules ()
        ((_ x)
         (letrec-syntax
             ((inner
               (syntax-rules ()
                 ((inner y) (helper4 y)))))
           (inner x)))))))
