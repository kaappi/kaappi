;; SRFI-252 (Property Testing) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi252.scm

(import (scheme base)
        (scheme complex)
        (srfi 1)
        (srfi 27)
        (srfi 64)
        (srfi 158)
        (srfi 194)
        (srfi 252))

(test-begin "srfi-252")

(define (three x) 3)
(define (wrong-three x) x)
(define (three-property x) (= (three x) 3))
(define (wrong-three-property x) (= (wrong-three x) 3))
(define (error-three-property x) (string-append 1 2))

(test-group "test-property"
  (test-property three-property (list (integer-generator)))
  (test-property three-property (list (real-generator)))
  (test-property three-property (list (integer-generator)) 10))

(test-group "test-property-expect-fail"
  (test-property-expect-fail wrong-three-property (list (integer-generator)))
  (test-property-expect-fail wrong-three-property (list (integer-generator)) 10))

(test-group "test-property-skip"
  (test-property-skip three-property (list (boolean-generator)))
  (test-property-skip three-property (list (boolean-generator)) 10))

(test-group "test-property-error"
  (test-property-error error-three-property (list (integer-generator)))
  (test-property-error error-three-property (list (integer-generator)) 10))

(test-group "test-property/with-2-arguments"
  (test-property (lambda (x y)
                   (and (boolean? x) (integer? y)))
                 (list (boolean-generator) (integer-generator))))

;;; --- Generator tests ---

(test-group "boolean-generator"
  (test-property boolean? (list (boolean-generator))))

(test-group "bytevector-generator"
  (test-property bytevector? (list (bytevector-generator))))

(test-group "char-generator"
  (test-property char? (list (char-generator))))

(test-group "string-generator"
  (test-property string? (list (string-generator))))

(test-group "symbol-generator"
  (test-property symbol? (list (symbol-generator))))

;;; --- Exact generators ---

(cond-expand
 (exact-complex
  (test-group "exact-complex-generator"
    (test-property (lambda (x)
                     (and (complex? x)
                          (exact? (real-part x))
                          (exact? (imag-part x))))
                   (list (exact-complex-generator)))))
 (else))

(test-group "exact-integer-generator"
  (test-property (lambda (x)
                   (and (integer? x) (exact? x)))
                 (list (exact-integer-generator))))

(test-group "exact-number-generator"
  (test-property exact? (list (exact-number-generator))))

(test-group "exact-rational-generator"
  (test-property (lambda (x)
                   (and (exact? x) (rational? x)))
                 (list (exact-rational-generator))))

(test-group "exact-real-generator"
  (test-property (lambda (x)
                   (and (exact? x) (real? x)))
                 (list (exact-real-generator))))

(cond-expand
 (exact-complex
  (test-group "exact-integer-complex-generator"
    (test-property (lambda (x)
                     (and (complex? x)
                          (exact? (real-part x))
                          (exact? (imag-part x))
                          (integer? (real-part x))
                          (integer? (imag-part x))))
                   (list (exact-integer-complex-generator)))))
 (else))

;;; --- Inexact generators ---

(test-group "inexact-complex-generator"
  (test-property (lambda (x)
                   (and (complex? x)
                        (inexact? (real-part x))
                        (inexact? (imag-part x))))
                 (list (inexact-complex-generator))))

(test-group "inexact-integer-generator"
  (test-property (lambda (x)
                   (and (inexact? x) (integer? x)))
                 (list (inexact-integer-generator))))

(test-group "inexact-number-generator"
  (test-property inexact? (list (inexact-number-generator))))

(test-group "inexact-rational-generator"
  (test-property (lambda (x)
                   (and (inexact? x) (rational? x)))
                 (list (inexact-rational-generator))))

(test-group "inexact-real-generator"
  (test-property (lambda (x)
                   (and (inexact? x) (real? x)))
                 (list (inexact-real-generator))))

;;; --- Union generators ---

(test-group "complex-generator"
  (test-property complex? (list (complex-generator))))

(test-group "integer-generator"
  (test-property integer? (list (integer-generator))))

(test-group "number-generator"
  (test-property number? (list (number-generator))))

(test-group "rational-generator"
  (test-property rational? (list (rational-generator))))

(test-group "real-generator"
  (test-property real? (list (real-generator))))

;;; --- Special generators ---

(test-group "list-generator-of"
  (test-property (lambda (x)
                   (and (list? x) (<= (length x) 64)
                        (every integer? x)))
                 (list (list-generator-of (integer-generator)))))

(test-group "pair-generator-of"
  (test-property (lambda (x)
                   (and (pair? x) (integer? (car x)) (boolean? (cdr x))))
                 (list (pair-generator-of (integer-generator)
                                          (boolean-generator)))))

(test-group "procedure-generator-of"
  (test-property (lambda (x)
                   (and (procedure? x) (integer? (x))))
                 (list (procedure-generator-of (integer-generator)))))

(test-group "vector-generator-of"
  (test-property (lambda (x)
                   (and (vector? x)
                        (<= (vector-length x) 64)
                        (every integer? (vector->list x))))
                 (list (vector-generator-of (integer-generator)))))

;;; --- Determinism ---

(test-group "determinism"
  (parameterize ((current-random-source (make-random-source)))
    (let ((gen1 (gdrop (exact-number-generator) 30)))
      (parameterize ((current-random-source (make-random-source)))
        (let ((gen2 (gdrop (exact-number-generator) 30)))
          (test-property = (list gen1 gen2)))))))

(let ((runner (test-runner-current)))
  (test-end "srfi-252")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
