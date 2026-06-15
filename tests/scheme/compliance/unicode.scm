;;; R7RS Unicode compliance tests

;; ---- string-length: count codepoints, not bytes ----
(display (string-length "hello")) (newline)          ; => 5
(display (string-length "")) (newline)               ; => 0
(display (string-length "h\x00E9;llo")) (newline)    ; => 5  (e-acute is 2 bytes UTF-8)
(display (string-length "\x03BB;-calculus")) (newline) ; => 10 (lambda is 2 bytes UTF-8)

;; ---- string-ref: codepoint indexing ----
(display (string-ref "hello" 0)) (newline)           ; => h
(display (string-ref "h\x00E9;llo" 1)) (newline)     ; => e-acute character
(display (char->integer (string-ref "h\x00E9;llo" 1))) (newline)  ; => 233
(display (string-ref "\x03BB;-calculus" 0)) (newline)  ; => lambda character
(display (char->integer (string-ref "\x03BB;-calculus" 0))) (newline)  ; => 955

;; ---- substring: codepoint indices ----
(display (substring "h\x00E9;llo" 0 2)) (newline)    ; => he-acute
(display (string-length (substring "h\x00E9;llo" 0 2))) (newline)  ; => 2
(display (substring "h\x00E9;llo" 2 5)) (newline)    ; => llo

;; ---- string->list: iterate codepoints ----
(display (length (string->list "abc"))) (newline)     ; => 3
(display (length (string->list "h\x00E9;llo"))) (newline) ; => 5
(display (char->integer (car (string->list "\x03BB;x")))) (newline) ; => 955

;; ---- string-copy: codepoint indices ----
(display (string-copy "h\x00E9;llo" 1 3)) (newline)  ; => e-acute + l
(display (string-length (string-copy "h\x00E9;llo" 1 3))) (newline) ; => 2

;; ---- make-string: non-ASCII fill ----
(display (string-length (make-string 3 #\a))) (newline)  ; => 3
(display (make-string 3 #\a)) (newline)                  ; => aaa

;; ---- char-alphabetic? with Unicode ----
(display (char-alphabetic? #\a)) (newline)            ; => #t
(display (char-alphabetic? #\Z)) (newline)            ; => #t
(display (char-alphabetic? #\1)) (newline)            ; => #f
(display (char-alphabetic? (integer->char 955))) (newline)   ; => #t  (lambda)
(display (char-alphabetic? (integer->char 233))) (newline)   ; => #t  (e-acute)

;; ---- char-numeric? ----
(display (char-numeric? #\5)) (newline)               ; => #t
(display (char-numeric? #\a)) (newline)               ; => #f

;; ---- char-whitespace? ----
(display (char-whitespace? #\space)) (newline)        ; => #t
(display (char-whitespace? #\tab)) (newline)          ; => #t
(display (char-whitespace? #\a)) (newline)            ; => #f

;; ---- char-upper-case? / char-lower-case? ----
(display (char-upper-case? #\A)) (newline)            ; => #t
(display (char-upper-case? #\a)) (newline)            ; => #f
(display (char-lower-case? #\a)) (newline)            ; => #t
(display (char-lower-case? #\A)) (newline)            ; => #f
;; Latin-1 uppercase (201 = E-acute, 233 = e-acute)
(display (char-upper-case? (integer->char 201))) (newline)  ; => #t  (E-acute)
(display (char-lower-case? (integer->char 233))) (newline)  ; => #t  (e-acute)

;; ---- char-upcase / char-downcase ----
(display (char->integer (char-upcase #\a))) (newline)   ; => 65
(display (char->integer (char-downcase #\A))) (newline)  ; => 97
;; Latin-1 case conversion (201 = E-acute, 233 = e-acute)
(display (char->integer (char-upcase (integer->char 233)))) (newline)  ; => 201 (E-acute)
(display (char->integer (char-downcase (integer->char 201)))) (newline) ; => 233 (e-acute)

;; ---- string-upcase / string-downcase ----
(display (string-upcase "hello")) (newline)           ; => HELLO
(display (string-downcase "HELLO")) (newline)         ; => hello
(display (string-upcase "h\x00E9;llo")) (newline)    ; => HELLO-with-E-acute
(display (string-length (string-upcase "h\x00E9;llo"))) (newline) ; => 5

;; ---- string-set! ----
(define s (string-copy "hello"))
(string-set! s 0 #\H)
(display s) (newline)                                  ; => Hello

;; ---- string-fill! ----
(define sf (make-string 3 #\a))
(string-fill! sf #\z)
(display sf) (newline)                                 ; => zzz

;; ---- string-for-each ----
(define count 0)
(string-for-each (lambda (c) (set! count (+ count 1))) "h\x00E9;llo")
(display count) (newline)                              ; => 5

;; ---- string->vector ----
(display (vector-length (string->vector "h\x00E9;llo"))) (newline) ; => 5

;; ---- string comparisons (still work correctly) ----
(display (string=? "abc" "abc")) (newline)            ; => #t
(display (string<? "abc" "abd")) (newline)            ; => #t

;; ---- char CI comparisons ----
(display (char-ci=? #\A #\a)) (newline)               ; => #t
(display (char-ci<? #\a #\B)) (newline)               ; => #t

;; ---- string CI comparisons ----
(display (string-ci=? "Hello" "hello")) (newline)     ; => #t

;; ---- digit-value ----
(display (digit-value #\0)) (newline)                 ; => 0
(display (digit-value #\9)) (newline)                 ; => 9
(display (digit-value #\a)) (newline)                 ; => #f
