;; Regression tests for reader token validation
;; Issues: #313 (codepoints above U+10FFFF), #312 (char literal delimiters),
;;         #311 (boolean literal delimiters)

(import (scheme base) (scheme write))

;; ---- #313: Valid Unicode codepoints should still work ----
(display (eqv? #\x41 #\A)) (newline)            ; #t
(display (eqv? #\x0 #\null)) (newline)           ; #t
(display (eqv? #\x10FFFF #\x10FFFF)) (newline)   ; #t (max valid codepoint)
(display (char->integer #\xD7FF)) (newline)       ; 55295 (just below surrogates)
(display (char->integer #\xE000)) (newline)       ; 57344 (just above surrogates)
(display (char->integer #\x10FFFF)) (newline)     ; 1114111 (max valid)

;; ---- #311: Boolean literals followed by delimiters should work ----
(display #t) (newline)                            ; #t
(display #f) (newline)                            ; #f
(display #true) (newline)                         ; #t
(display #false) (newline)                        ; #f
(display (list #t #f)) (newline)                  ; (#t #f)
(display (if #t "yes" "no")) (newline)            ; yes

;; ---- #312: Character literals followed by delimiters should work ----
(display #\a) (newline)                           ; a
(display #\space) (newline)                       ; (space char)
(display (list #\x41 #\newline)) (newline)        ; (A newline)
(display (char->integer #\x)) (newline)           ; 120

(display "all passed")
(newline)
