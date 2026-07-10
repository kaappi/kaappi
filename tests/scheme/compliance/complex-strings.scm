(import (scheme base) (scheme write) (scheme complex))
(import (scheme process-context) (srfi 64))

(test-begin "complex number->string and string->number")

;;; number->string on complex
(test-equal "1+2i" (number->string 1+2i))
(test-equal "3-4i" (number->string 3-4i))
(test-equal "+i" (number->string 0+1i))
(test-equal "-i" (number->string 0-1i))

;;; string->number producing complex
(test-equal #t (complex? (string->number "1+2i")))
(test-equal #t (complex? (string->number "3-4i")))
(test-equal #t (complex? (string->number "+i")))
(test-equal #t (complex? (string->number "-i")))
(test-equal #t (complex? (string->number "+2i")))
(test-equal #t (complex? (string->number "-3.5i")))
(test-equal #t (complex? (string->number "1.5+2.5i")))

;;; Verify parsed values
(let ((z (string->number "1+2i")))
  (test-equal #t (= 1.0 (real-part z)))
  (test-equal #t (= 2.0 (imag-part z))))
(let ((z (string->number "3-4i")))
  (test-equal #t (= 3.0 (real-part z)))
  (test-equal #t (= -4.0 (imag-part z))))
(let ((z (string->number "+i")))
  (test-equal #t (= 0.0 (real-part z)))
  (test-equal #t (= 1.0 (imag-part z))))
(let ((z (string->number "-i")))
  (test-equal #t (= 0.0 (real-part z)))
  (test-equal #t (= -1.0 (imag-part z))))
(let ((z (string->number "-3.5i")))
  (test-equal #t (= 0.0 (real-part z)))
  (test-equal #t (= -3.5 (imag-part z))))

;;; Invalid complex strings
(test-equal #f (string->number "i"))
(test-equal #f (string->number "1+2"))
(test-equal #f (string->number "abc"))

;;; Roundtrip
(test-equal #t (= 3+4i (string->number (number->string 3+4i))))

(let ((runner (test-runner-current)))
  (test-end "complex number->string and string->number")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
