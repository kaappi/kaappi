;;; SRFI 118 — Simple Adjustable-Size Strings
;;;
;;; Kaappi's SchemeString has no header/buffer indirection, so a string
;;; object's identity cannot be preserved across a length change (the way
;;; string-set! preserves it across a byte-width change at a fixed length).
;;; string-append!/string-replace! are therefore implemented like SRFI 185's
;;; "linear update" operations: they rebind the place named by their first
;;; argument via set!, rather than mutating the string object in place.
;;; This matches the idiomatic usage shown in the SRFI itself (accumulating
;;; into a local variable) but, unlike a conforming SRFI 118, does not make
;;; the growth visible through any other alias of the original string.

(define-library (srfi 118)
  (import (scheme base))
  (export string-append! string-replace!)
  (begin

    (define (%->string x) (if (char? x) (string x) x))

    (define-syntax string-append!
      (syntax-rules ()
        ((_ place value ...)
         (set! place (string-append place (%->string value) ...)))))

    (define-syntax string-replace!
      (syntax-rules ()
        ((_ place dst-start dst-end src)
         (set! place (string-append (substring place 0 dst-start)
                                     src
                                     (substring place dst-end (string-length place)))))
        ((_ place dst-start dst-end src src-start)
         (set! place (string-append (substring place 0 dst-start)
                                     (substring src src-start (string-length src))
                                     (substring place dst-end (string-length place)))))
        ((_ place dst-start dst-end src src-start src-end)
         (set! place (string-append (substring place 0 dst-start)
                                     (substring src src-start src-end)
                                     (substring place dst-end (string-length place)))))))))
