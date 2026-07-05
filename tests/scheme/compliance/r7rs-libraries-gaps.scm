;; R7RS sections 5.6 (Libraries) conformance gap tests — audit Phase 1A.
;; Covers library-system requirements not exercised by smoke/libraries.scm
;; or the R7RS suite. Spec references cite docs/errata-corrected-r7rs.pdf.

;; --- 5.6.1: library names may contain exact non-negative integers (p. 28)
(define-library (gaps 0 numeric)
  (import (scheme base))
  (export numeric-name-ok)
  (begin (define numeric-name-ok 'yes)))

;; --- 5.6.1: a library with zero declarations is valid
(define-library (gaps empty))

;; --- 5.6.1: (export (rename internal external)) (p. 28)
(define-library (gaps renamed-export)
  (import (scheme base))
  (export (rename internal-name public-name))
  (begin (define internal-name 'renamed-ok)))

;; Shared-state fixture for the single-instantiation test below.
(define-library (gaps state)
  (import (scheme base))
  (export state-get state-bump)
  (begin
    (define v 0)
    (define (state-get) v)
    (define (state-bump) (set! v (+ v 1)))))

(define-library (gaps state-writer)
  (import (scheme base) (gaps state))
  (export bump-through-writer)
  (begin (define (bump-through-writer) (state-bump))))

(define-library (gaps state-reader)
  (import (scheme base) (gaps state))
  (export read-through-reader)
  (begin (define (read-through-reader) (state-get))))

;; Fixture with several exports for import-set combinations.
(define-library (gaps abc)
  (import (scheme base))
  (export ga gb gc)
  (begin (define ga 1) (define gb 2) (define gc 3)))

(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "r7rs-libraries-gaps")

(import (gaps 0 numeric))
(test-equal "library name with integer component" 'yes numeric-name-ok)

(import (gaps renamed-export))
(test-equal "export (rename ...) exposes external name" 'renamed-ok public-name)

;; --- 5.2: nested import sets (p. 25) ---
;; prefix of only
(import (prefix (only (gaps abc) ga gb) p-))
(test-equal "prefix of only" '(1 2) (list p-ga p-gb))
;; rename of prefix — the shape used in the spec's own 5.6.2 example:
;; (rename (prefix (example grid) grid-) (grid-make make-grid))
(import (rename (prefix (gaps abc) g-) (g-ga renamed-ga)))
(test-equal "rename of prefix" '(1 2) (list renamed-ga g-gb))
;; only of except
(import (only (except (gaps abc) gb) ga gc))
(test-equal "only of except" '(1 3) (list ga gc))

;; --- 5.6.1: import merging (p. 28) ---
;; "(import (only (foo) a)) followed by (import (only (foo) b)) has the same
;; effect as (import (only (foo) a b))."
(define-library (gaps two)
  (import (scheme base))
  (export ta tb)
  (begin (define ta 10) (define tb 20)))
(import (only (gaps two) ta))
(import (only (gaps two) tb))
(test-equal "successive only imports merge" '(10 20) (list ta tb))

;; --- 5.6.1: single instantiation (p. 28) ---
;; "Regardless of the number of times that a library is loaded, each program
;; or library that imports bindings from a library must do so from a single
;; loading of that library" — mutation through one importer is visible
;; through another.
(import (gaps state-writer) (gaps state-reader))
(bump-through-writer)
(bump-through-writer)
(test-equal "library instantiated once (shared state)" 2 (read-through-reader))

(let ((runner (test-runner-current)))
  (test-end "r7rs-libraries-gaps")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
