;; SRFI-261 (Portable SRFI Library Reference) conformance tests (#1645).
;; (srfi srfi-<n>) and (srfi <mnemonic>-<n>) resolve to (srfi <n>) as a
;; fallback; literal registry/file names win; sub-library tails pass through.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi261.scm

(import (scheme base) (scheme eval) (srfi 64))

(test-begin "srfi-261")

;;; --- primary portable form: (srfi srfi-<n>) ------------------------------

;; Built-in library (registry, no .sld involved).
(import (srfi srfi-1))
(test-equal 6 (fold + 0 '(1 2 3)))

;; Portable library loaded from srfi/2.sld.
(import (srfi srfi-2))
(test-equal 5 (and-let* ((x 5)) x))

;; Leading zeros in the suffix normalize away.
(import (srfi srfi-01))
(test-equal 3 (fold + 0 '(1 2)))

;;; --- mnemonic form: (srfi <name>-<n>) ------------------------------------

;; The number is authoritative; the mnemonic is documentation. Composes with
;; import modifiers.
(import (only (srfi lists-1) last))
(test-equal 3 (last '(1 2 3)))

;; Colliding mnemonics (the spec names both 43 and 133 "vectors") resolve by
;; number: SRFI 43's vector-fold passes the index to kons, SRFI 133's does
;; not — each call succeeds only against its own library.
(import (prefix (srfi vectors-43) v43:))
(import (prefix (srfi vectors-133) v133:))
(test-equal 30 (v43:vector-fold (lambda (i st x) (+ st x)) 0 (vector 10 20)))
(test-equal 30 (v133:vector-fold (lambda (st x) (+ st x)) 0 (vector 10 20)))

;;; --- sub-library components pass through ---------------------------------

(import (srfi srfi-254 ephemerons))
(test-assert (procedure? make-ephemeron))

;;; --- the R7RS numeric form is untouched ----------------------------------

(import (srfi 1))
(test-equal 10 (fold + 0 '(1 2 3 4)))

;;; --- cond-expand (library ...) agrees with import ------------------------

;; Compile-time cond-expand (compiler -> checkLibraryExists).
(test-equal 'yes (cond-expand ((library (srfi srfi-1)) 'yes) (else 'no)))
(test-equal 'no  (cond-expand ((library (srfi srfi-99999)) 'yes) (else 'no)))

;; cond-expand inside define-library (evalLibFeatureReq).
(define-library (test srfi261-ce)
  (import (scheme base))
  (export ce-val)
  (cond-expand
    ((library (srfi srfi-1)) (begin (define ce-val 'yes)))
    (else (begin (define ce-val 'no)))))
(import (test srfi261-ce))
(test-equal 'yes ce-val)

;;; --- literal names win over the rewrite ----------------------------------

;; srfi/4.sld exists on disk, but a library *registered* under the literal
;; hyphenated name shadows the SRFI 261 rewrite entirely.
(define-library (srfi srfi-4)
  (import (scheme base))
  (export srfi261-shadow-marker)
  (begin (define srfi261-shadow-marker 42)))
(import (srfi srfi-4))
(test-equal 42 srfi261-shadow-marker)

;;; --- environment (scheme eval) resolves 261 forms ------------------------

(test-equal 6 (eval '(fold + 0 '(1 2 3))
                    (environment '(scheme base) '(srfi srfi-1))))

(let ((runner (test-runner-current)))
  (test-end "srfi-261")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
