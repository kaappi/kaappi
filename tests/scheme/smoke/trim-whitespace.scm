;;; Regression test for #826: string-trim default criterion must match
;;; char-whitespace? (Unicode White_Space property), not just SP/TAB/CR/LF.

(import (scheme base) (scheme write) (scheme char) (srfi 13))

(define pass 0)
(define fail 0)

(define-syntax check
  (syntax-rules ()
    ((_ expr expected name)
     (let ((result expr))
       (if (equal? result expected)
           (set! pass (+ pass 1))
           (begin
             (set! fail (+ fail 1))
             (display "FAIL: ") (display name) (newline)
             (display "  expected: ") (write expected) (newline)
             (display "  got:      ") (write result) (newline)))))))

;; Vertical tab and form feed (single-byte, missed before 0x0B/0x0C fix)
(check (string-trim "\x0B;\x0C;hi")       "hi"  "trim VT/FF left")
(check (string-trim-right "hi\x0B;\x0C;") "hi"  "trim-right VT/FF")
(check (string-trim-both "\x0B;hi\x0C;")  "hi"  "trim-both VT/FF")

;; Multi-byte Unicode whitespace: NBSP (U+00A0)
(check (string-trim "\x00A0;hi")       "hi"  "trim NBSP left")
(check (string-trim-right "hi\x00A0;") "hi"  "trim-right NBSP")
(check (string-trim-both "\x00A0;hi\x00A0;") "hi" "trim-both NBSP")

;; EM SPACE (U+2003)
(check (string-trim "\x2003;hi")       "hi"  "trim EM SPACE left")
(check (string-trim-right "hi\x2003;") "hi"  "trim-right EM SPACE")

;; IDEOGRAPHIC SPACE (U+3000)
(check (string-trim "\x3000;hi")       "hi"  "trim IDEOGRAPHIC SPACE left")
(check (string-trim-right "hi\x3000;") "hi"  "trim-right IDEOGRAPHIC SPACE")

;; Mixed: regular space + NBSP + content + EM SPACE + tab
(check (string-trim-both " \x00A0;hello\x2003;\t") "hello" "trim-both mixed")

;; Default criterion must agree with explicit char-whitespace?
(check (string-trim "\x0B;\x0C;hi" char-whitespace?) "hi"
       "trim with explicit char-whitespace? (VT/FF)")
(check (string-trim "\x00A0;hi" char-whitespace?) "hi"
       "trim with explicit char-whitespace? (NBSP)")

;; Empty / all-whitespace strings
(check (string-trim "   ") "" "trim all-space")
(check (string-trim-both "\x00A0;\x2003;\x3000;") "" "trim-both all-unicode-ws")

(display pass) (display "/") (display (+ pass fail)) (display " passed") (newline)
(when (> fail 0) (exit 1))
