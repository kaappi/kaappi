;; Regression test for #920: reader #!fold-case with Unicode identifiers
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "fold-case-unicode")

;; --- Greek ---
#!fold-case
(define ΑΒΓ 100)
(test-equal "Greek fold-case" 100 αβγ)
(test-equal "Greek mixed case" 100 Αβγ)
#!no-fold-case

;; --- Cyrillic ---
#!fold-case
(define АБВ 200)
(test-equal "Cyrillic fold-case" 200 абв)
#!no-fold-case

;; --- Latin-1 accented ---
#!fold-case
(define Ñoño 300)
(test-equal "Latin-1 fold-case" 300 ñoño)
#!no-fold-case

;; --- Coptic ---
#!fold-case
(define Ⲁⲃ 400)
(test-equal "Coptic fold-case" 400 ⲁⲃ)
#!no-fold-case

;; --- ASCII still works ---
#!fold-case
(define HELLO 42)
(test-equal "ASCII fold-case" 42 hello)
#!no-fold-case

;; --- fold-case off means case-sensitive ---
(define xyz 1)
(define XYZ 2)
(test-equal "no-fold-case lowercase" 1 xyz)
(test-equal "no-fold-case uppercase" 2 XYZ)

(let ((runner (test-runner-current)))
  (test-end "fold-case-unicode")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
