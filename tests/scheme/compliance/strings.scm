;;; R7RS String compliance tests

;; string constructor
(display (string #\a #\b #\c)) (newline)         ; => abc
(display (string)) (newline)                      ; =>

;; make-string
(display (string-length (make-string 5))) (newline)  ; => 5
(display (make-string 3 #\x)) (newline)              ; => xxx

;; string-ref
(display (string-ref "hello" 0)) (newline)       ; => h
(display (string-ref "hello" 4)) (newline)       ; => o

;; string-length
(display (string-length "hello")) (newline)      ; => 5
(display (string-length "")) (newline)           ; => 0

;; substring
(display (substring "hello world" 0 5)) (newline) ; => hello
(display (substring "hello world" 6 11)) (newline) ; => world
(display (substring "abc" 1 2)) (newline)          ; => b

;; string-append
(display (string-append "hello" " " "world")) (newline)  ; => hello world
(display (string-append)) (newline)                       ; =>

;; string-copy
(display (string-copy "hello")) (newline)        ; => hello
(display (string-copy "hello" 1 3)) (newline)    ; => el

;; string->list
(display (string->list "abc")) (newline)         ; => (a b c)
(display (string->list "")) (newline)            ; => ()

;; list->string
(display (list->string '(#\a #\b #\c))) (newline)  ; => abc
(display (list->string '())) (newline)               ; =>

;; string->symbol
(display (string->symbol "hello")) (newline)     ; => hello
(display (symbol? (string->symbol "test"))) (newline)  ; => #t

;; symbol->string
(display (symbol->string 'hello)) (newline)      ; => hello

;; string comparisons
(display (string<? "abc" "abd")) (newline)       ; => #t
(display (string<? "abd" "abc")) (newline)       ; => #f
(display (string=? "abc" "abc")) (newline)       ; => #t
(display (string=? "abc" "abd")) (newline)       ; => #f
(display (string>? "abd" "abc")) (newline)       ; => #t
(display (string<=? "abc" "abc")) (newline)      ; => #t
(display (string>=? "abc" "abc")) (newline)      ; => #t

;; char->integer, integer->char
(display (char->integer #\A)) (newline)          ; => 65
(display (char->integer #\a)) (newline)          ; => 97
(display (integer->char 65)) (newline)           ; => A
(display (integer->char 97)) (newline)           ; => a

;; char comparisons
(display (char<? #\a #\b)) (newline)             ; => #t
(display (char=? #\a #\a)) (newline)             ; => #t
(display (char>? #\b #\a)) (newline)             ; => #t

;; number->string
(display (number->string 42)) (newline)          ; => 42
(display (number->string -7)) (newline)          ; => -7

;; string->number
(display (string->number "42")) (newline)        ; => 42
(display (string->number "bad")) (newline)       ; => #f

;; string-set!
(define s (string-copy "hello"))
(string-set! s 0 #\H)
(display s) (newline)                             ; => Hello

;; string-fill!
(define sf (make-string 3 #\a))
(string-fill! sf #\z)
(display sf) (newline)                            ; => zzz
