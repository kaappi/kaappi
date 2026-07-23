;; SRFI-112 (Environment Inquiry) conformance test.
;;
;; Six zero-argument procedures reporting implementation/host information for
;; bug reports and logging, each returning a string or #f. Kaappi's wrapper
;; (lib/srfi/112.sld) backs implementation-version/cpu-architecture/os-name
;; with native primitives (plus the literal "kaappi" name for
;; implementation-name) and always answers #f for machine-name and
;; os-version -- a deliberate reduced scope (see the .sld header), not a bug.
;; Exact OS/CPU string values are platform-dependent and deliberately not
;; asserted here (the SRFI itself disclaims any standard string vocabulary);
;; only the string-vs-#f shape is checked.

(import (scheme base) (scheme process-context) (srfi 64) (srfi 112))

(test-begin "srfi-112")

;; --- implementation-name --------------------------------------------------

(test-assert "implementation-name returns a string" (string? (implementation-name)))
(test-equal "implementation-name is \"kaappi\"" "kaappi" (implementation-name))

;; --- implementation-version -----------------------------------------------

(test-assert "implementation-version returns a string"
  (string? (implementation-version)))

;; --- cpu-architecture -------------------------------------------------------

(test-assert "cpu-architecture returns a string" (string? (cpu-architecture)))

;; --- os-name ----------------------------------------------------------------

(test-assert "os-name returns a string" (string? (os-name)))

;; --- machine-name: deliberately unsupported, always #f ----------------------

(test-equal "machine-name is #f" #f (machine-name))

;; --- os-version: deliberately unsupported, always #f -------------------------

(test-equal "os-version is #f" #f (os-version))

;; --- Derived cond-expand feature id (#1649) ----------------------------------

(test-equal "cond-expand srfi-112" 'yes
  (cond-expand (srfi-112 'yes) (else 'no)))

(let ((runner (test-runner-current)))
  (test-end "srfi-112")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
