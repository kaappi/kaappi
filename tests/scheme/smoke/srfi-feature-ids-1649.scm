;; Regression test for #1649: srfi-<n> cond-expand feature identifiers.
;; R7RS implementations advertise each supported SRFI as a feature id so a
;; program can probe support without attempting an import. The id is derived
;; from the same availability check as (library (srfi <n>)), so it stays
;; truthful for built-in, portable, sandboxed and WASM configurations.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "srfi-feature-ids")

;;; --- absolute cases -------------------------------------------------------

;; Built-in SRFI (registered in the library table).
(test-equal "built-in srfi-1 is a feature id" 'yes
  (cond-expand (srfi-1 'yes) (else 'no)))

;; SRFI 261 is a pure naming convention with no .sld, but still supported.
(test-equal "srfi-261 naming convention is a feature id" 'yes
  (cond-expand (srfi-261 'yes) (else 'no)))

;; A number no SRFI uses must not match.
(test-equal "unknown srfi-99999 is not a feature id" 'no
  (cond-expand (srfi-99999 'yes) (else 'no)))

;;; --- the id agrees with the (library (srfi <n>)) spelling -----------------

;; For every n, (cond-expand (srfi-<n> ...)) must answer exactly what
;; (cond-expand ((library (srfi <n>)) ...)) — and thus (import (srfi <n>)) —
;; would. Covers a built-in (1, 133), a portable on-disk (2), and a missing
;; one (99999), so it passes regardless of whether the source tree is present.
(test-equal "srfi-1 id matches library form"
  (cond-expand ((library (srfi 1)) #t) (else #f))
  (cond-expand (srfi-1 #t) (else #f)))
(test-equal "srfi-2 id matches library form"
  (cond-expand ((library (srfi 2)) #t) (else #f))
  (cond-expand (srfi-2 #t) (else #f)))
(test-equal "srfi-133 id matches library form"
  (cond-expand ((library (srfi 133)) #t) (else #f))
  (cond-expand (srfi-133 #t) (else #f)))
(test-equal "srfi-99999 id matches library form (both #f)"
  (cond-expand ((library (srfi 99999)) #t) (else #f))
  (cond-expand (srfi-99999 #t) (else #f)))

;;; --- composition with and / or / not -------------------------------------

(test-equal "and of two known feature ids" 'yes
  (cond-expand ((and srfi-1 srfi-261) 'yes) (else 'no)))
(test-equal "or reaches a known id past an unknown" 'yes
  (cond-expand ((or srfi-99999 srfi-1) 'yes) (else 'no)))
(test-equal "not of an unknown id" 'yes
  (cond-expand ((not srfi-99999) 'yes) (else 'no)))

;;; --- inside define-library (evalLibFeatureReq, not the compiler path) -----

(define-library (test srfi-feat-ce)
  (import (scheme base))
  (export marker)
  (cond-expand
    (srfi-1 (begin (define marker 'srfi-1-branch)))
    (else   (begin (define marker 'else-branch)))))
(import (test srfi-feat-ce))
(test-equal "define-library cond-expand selects the srfi-1 branch"
  'srfi-1-branch marker)

(let ((runner (test-runner-current)))
  (test-end "srfi-feature-ids")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
