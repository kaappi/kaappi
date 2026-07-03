;;; Regression test for #826: string-trim should treat VT and FF as whitespace

(import (srfi 13))

(define vt (string (integer->char #x0B)))
(define ff (string (integer->char #x0C)))

;; string-trim strips leading whitespace
(display (string=? (string-trim (string-append vt "hello")) "hello")) (newline)
(display (string=? (string-trim (string-append ff "hello")) "hello")) (newline)
(display (string=? (string-trim (string-append vt ff " \t\n\rhello")) "hello")) (newline)

;; string-trim-right strips trailing whitespace
(display (string=? (string-trim-right (string-append "hello" vt)) "hello")) (newline)
(display (string=? (string-trim-right (string-append "hello" ff)) "hello")) (newline)

;; string-trim-both strips both
(display (string=? (string-trim-both (string-append vt "hello" ff)) "hello")) (newline)
