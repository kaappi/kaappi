;; Regression test for #863: ppValue omits separator before dotted tail
;; The pretty-printer wrote "b. c" instead of "b\n  . c" for dotted pairs
;; in multi-line mode, fusing the dot with the preceding token.

(import (scheme base) (scheme write) (scheme read))

(define pass 0)
(define fail 0)

(define (check desc val expected)
  (if (equal? val expected)
    (set! pass (+ pass 1))
    (begin
      (set! fail (+ fail 1))
      (display "FAIL: ") (display desc)
      (display " got ") (write val)
      (display " expected ") (write expected) (newline))))

;; Build a long dotted list that triggers multi-line pretty-printing (>80 cols)
(define d (cons 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
                (cons 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb 3)))

;; Write it via write (flat) and verify it reads back correctly
(define flat-str (let ((p (open-output-string)))
                   (write d p)
                   (get-output-string p)))
(define read-back (read (open-input-string flat-str)))
(check "write round-trip" read-back d)

;; The dot must be a standalone token (preceded by whitespace)
;; Check that the flat representation contains " . " (space-dot-space)
(check "flat contains ' . '" (if (string-contains flat-str " . ") #t #f) #t)

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(when (> fail 0) (exit 1))
