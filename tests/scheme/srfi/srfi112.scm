;; SRFI-112 (Environment Inquiry) conformance test.
;;
;; Six zero-argument procedures reporting implementation/host information for
;; bug reports and logging, each returning a string or #f. Kaappi's wrapper
;; (lib/srfi/112.sld) backs implementation-version/cpu-architecture/os-name
;; with native primitives (plus the literal "kaappi" name for
;; implementation-name) and always answers #f for machine-name and
;; os-version -- a deliberate reduced scope (see the .sld header), not a bug.
;;
;; Exact OS/CPU string values are platform-dependent and deliberately not
;; asserted here: the SRFI itself says "no attempt is made to standardize
;; the string values they return", and this file runs on macOS, five Linux
;; architectures, three BSDs and two Windows targets. Only the string-vs-#f
;; shape, the "or #f" contract, arity, and call-to-call stability are
;; checked. Grown in audit v2 Phase 3.8 from 8 assertions.

(import (scheme base) (scheme process-context) (srfi 64) (srfi 112))

(test-begin "srfi-112")

;;; --- every procedure returns a string or #f, and nothing else.  This is
;;; the one blanket contract the SRFI does state: each returns a string,
;;; or #f "if the implementation cannot provide an appropriate and relevant
;;; result". ---

(define srfi112-all
  (list (cons "implementation-name" implementation-name)
        (cons "implementation-version" implementation-version)
        (cons "cpu-architecture" cpu-architecture)
        (cons "machine-name" machine-name)
        (cons "os-name" os-name)
        (cons "os-version" os-version)))

(for-each
  (lambda (entry)
    (test-assert (string-append (car entry) " returns a string or #f")
      (let ((v ((cdr entry)))) (or (string? v) (eq? v #f))))
    (test-assert (string-append (car entry) " is a procedure")
      (procedure? (cdr entry)))
    (test-error (string-append (car entry) " takes no arguments")
      ((cdr entry) 'surplus))
    (test-assert (string-append (car entry) " is stable across calls")
      (equal? ((cdr entry)) ((cdr entry)))))
  srfi112-all)

;;; --- the four that must answer with a real string on every supported
;;; platform, since each is backed by a compile-time constant ---

(test-assert "implementation-name returns a string" (string? (implementation-name)))
(test-equal "implementation-name is \"kaappi\"" "kaappi" (implementation-name))

(test-assert "implementation-version returns a string"
  (string? (implementation-version)))
(test-assert "implementation-version is non-empty"
  (> (string-length (implementation-version)) 0))

(test-assert "cpu-architecture returns a string" (string? (cpu-architecture)))
(test-assert "cpu-architecture is non-empty"
  (> (string-length (cpu-architecture)) 0))

(test-assert "os-name returns a string" (string? (os-name)))
(test-assert "os-name is non-empty" (> (string-length (os-name)) 0))

;;; --- machine-name and os-version: deliberately unsupported, always #f.
;;; The SRFI sanctions #f explicitly; this pins the reduced scope so that
;;; implementing either later is a deliberate change, not an accident. ---

(test-equal "machine-name is #f" #f (machine-name))
(test-equal "os-version is #f" #f (os-version))

;;; --- the SRFI's stated purpose is human-readable reporting, so the
;;; results have to be usable as text ---

(test-assert "the reported strings survive string-append"
  (string? (string-append (implementation-name) " " (implementation-version)
                          " on " (os-name) "/" (cpu-architecture))))

;;; --- Derived cond-expand feature id (#1649) ----------------------------------

(test-equal "cond-expand srfi-112" 'yes
  (cond-expand (srfi-112 'yes) (else 'no)))

(let ((runner (test-runner-current)))
  (test-end "srfi-112")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
