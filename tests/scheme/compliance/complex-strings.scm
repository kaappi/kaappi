(import (scheme base) (scheme write) (scheme complex))
(import (chibi test))

(test-begin "complex number->string and string->number")

;;; number->string on complex
(test "1+2i" (number->string 1+2i))
(test "3-4i" (number->string 3-4i))
(test "+i" (number->string 0+1i))
(test "-i" (number->string 0-1i))

;;; string->number producing complex
(test #t (complex? (string->number "1+2i")))
(test #t (complex? (string->number "3-4i")))
(test #t (complex? (string->number "+i")))
(test #t (complex? (string->number "-i")))
(test #t (complex? (string->number "+2i")))
(test #t (complex? (string->number "-3.5i")))
(test #t (complex? (string->number "1.5+2.5i")))

;;; Verify parsed values
(let ((z (string->number "1+2i")))
  (test #t (= 1.0 (real-part z)))
  (test #t (= 2.0 (imag-part z))))
(let ((z (string->number "3-4i")))
  (test #t (= 3.0 (real-part z)))
  (test #t (= -4.0 (imag-part z))))
(let ((z (string->number "+i")))
  (test #t (= 0.0 (real-part z)))
  (test #t (= 1.0 (imag-part z))))
(let ((z (string->number "-i")))
  (test #t (= 0.0 (real-part z)))
  (test #t (= -1.0 (imag-part z))))
(let ((z (string->number "-3.5i")))
  (test #t (= 0.0 (real-part z)))
  (test #t (= -3.5 (imag-part z))))

;;; Invalid complex strings
(test #f (string->number "i"))
(test #f (string->number "1+2"))
(test #f (string->number "abc"))

;;; Roundtrip
(test #t (= 3+4i (string->number (number->string 3+4i))))

(test-end "complex number->string and string->number")
