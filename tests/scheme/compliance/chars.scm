;;; R7RS Char compliance tests

;; Character classification
(display (char-alphabetic? #\a)) (newline)       ; => #t
(display (char-alphabetic? #\Z)) (newline)       ; => #t
(display (char-alphabetic? #\1)) (newline)       ; => #f
(display (char-alphabetic? #\space)) (newline)   ; => #f

(display (char-numeric? #\0)) (newline)          ; => #t
(display (char-numeric? #\9)) (newline)          ; => #t
(display (char-numeric? #\a)) (newline)          ; => #f

(display (char-whitespace? #\space)) (newline)   ; => #t
(display (char-whitespace? #\newline)) (newline) ; => #t
(display (char-whitespace? #\a)) (newline)       ; => #f

(display (char-upper-case? #\A)) (newline)       ; => #t
(display (char-upper-case? #\a)) (newline)       ; => #f

(display (char-lower-case? #\a)) (newline)       ; => #t
(display (char-lower-case? #\A)) (newline)       ; => #f

;; Case operations
(display (char-upcase #\a)) (newline)            ; => A
(display (char-upcase #\A)) (newline)            ; => A
(display (char-downcase #\A)) (newline)          ; => a
(display (char-downcase #\a)) (newline)          ; => a
(display (char-foldcase #\A)) (newline)          ; => a

;; digit-value
(display (digit-value #\0)) (newline)            ; => 0
(display (digit-value #\5)) (newline)            ; => 5
(display (digit-value #\9)) (newline)            ; => 9
(display (digit-value #\a)) (newline)            ; => #f

;; Case-insensitive char comparison
(display (char-ci=? #\A #\a)) (newline)          ; => #t
(display (char-ci<? #\A #\b)) (newline)          ; => #t
(display (char-ci>? #\z #\A)) (newline)          ; => #t

;; String case operations
(display (string-upcase "hello")) (newline)      ; => HELLO
(display (string-downcase "HELLO")) (newline)    ; => hello
(display (string-foldcase "HeLLo")) (newline)    ; => hello

;; Case-insensitive string comparison
(display (string-ci=? "Hello" "hello")) (newline)  ; => #t
(display (string-ci<? "abc" "ABD")) (newline)      ; => #t
(display (string-ci>? "abd" "ABC")) (newline)      ; => #t
