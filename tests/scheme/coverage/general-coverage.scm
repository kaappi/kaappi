(import (scheme base) (scheme write) (scheme read) (scheme char)
        (scheme lazy) (scheme case-lambda) (scheme cxr))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))
(define (check-true name val)
  (if val (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))
(define (check-false name val)
  (if (not val) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

;;; ---- Lazy evaluation ----
(check "delay/force" (force (delay 42)) 42)
(check "delay/force expr" (force (delay (+ 1 2))) 3)
(let ((p (delay (+ 10 20))))
  (check "promise? delay" (promise? p) #t)
  (check "force" (force p) 30)
  (check "force cached" (force p) 30))

(check-false "promise? number" (promise? 42))
(check-false "promise? string" (promise? "hello"))

(let ((p (make-promise 42)))
  (check-true "promise? make-promise" (promise? p))
  (check "force make-promise" (force p) 42))

;;; delay-force (iterative forcing)
(define (stream-from n)
  (delay-force (cons n (stream-from (+ n 1)))))
(let ((s (stream-from 0)))
  (check "stream car" (car (force s)) 0)
  (check "stream cadr" (car (force (cdr (force s)))) 1))

;;; ---- case-lambda ----
(define f
  (case-lambda
    (() 'zero)
    ((x) (list 'one x))
    ((x y) (list 'two x y))
    ((x y . z) (list 'more x y z))))
(check "case-lambda 0" (f) 'zero)
(check "case-lambda 1" (f 'a) '(one a))
(check "case-lambda 2" (f 'a 'b) '(two a b))
(check "case-lambda var" (f 'a 'b 'c 'd) '(more a b (c d)))

;;; ---- cxr compositions ----
(define nested '((1 2 3) (4 5 6) (7 8 9)))
(check "caaar" (caaar '(((1 2) 3) 4)) 1)
(check "cdaar" (cdaar '(((1 2) 3) 4)) '(2))
(check "cadar" (cadar '((1 2) 3)) 2)
(check "caddr" (caddr '(1 2 3 4)) 3)
(check "cadddr" (cadddr '(1 2 3 4 5)) 4)
(check "cadaar" (cadaar '(((1 2 3) 4) 5)) 2)
(check "caddar" (caddar '((1 2 3) 4)) 3)

;;; ---- Dynamic binding ----
(define p (make-parameter 10))
(check "make-parameter" (p) 10)
(check "parameterize" (parameterize ((p 20)) (p)) 20)
(check "parameter restored" (p) 10)
(parameterize ((p 30))
  (check "nested parameterize" (p) 30)
  (parameterize ((p 40))
    (check "double nested" (p) 40))
  (check "restored inner" (p) 30))

;;; ---- Dynamic-wind ----
(let ((log '()))
  (dynamic-wind
    (lambda () (set! log (cons 'in log)))
    (lambda () (set! log (cons 'body log)))
    (lambda () (set! log (cons 'out log))))
  (check "dynamic-wind order" (reverse log) '(in body out)))

;;; ---- Values / call-with-values ----
(check "values single" (values 42) 42)
(call-with-values (lambda () (values 1 2 3))
  (lambda (a b c) (check "call-with-values" (+ a b c) 6)))
(let-values (((a b) (values 10 20)))
  (check "let-values" (+ a b) 30))
(let*-values (((a b) (values 1 2))
              ((c) (+ a b)))
  (check "let*-values" c 3))

;;; ---- String operations ----
(check "string-length" (string-length "hello") 5)
(check "string-length empty" (string-length "") 0)
(check "string-ref" (string-ref "hello" 1) #\e)
(check "substring" (substring "hello world" 6 11) "world")
(check "string-append" (string-append "hello" " " "world") "hello world")
(check "string-copy" (string-copy "hello") "hello")
(check "string-upcase" (string-upcase "hello") "HELLO")
(check "string-downcase" (string-downcase "HELLO") "hello")
(check "string->number" (string->number "42") 42)
(check "string->number float" (string->number "3.14") 3.14)
(check-false "string->number invalid" (string->number "abc"))
(check "number->string" (number->string 42) "42")
(check "number->string base" (number->string 255 16) "ff")
(check "string->list" (string->list "abc") '(#\a #\b #\c))
(check "list->string" (list->string '(#\a #\b #\c)) "abc")

;;; ---- String mutation ----
(let ((s (string-copy "hello")))
  (string-set! s 0 #\H)
  (check "string-set!" s "Hello"))

(let ((s (string-copy "hello")))
  (string-copy! s 1 "ELL")
  (check "string-copy!" s "hELLo"))

;;; ---- Char operations ----
(check-true "char-alphabetic?" (char-alphabetic? #\a))
(check-false "char-alphabetic? digit" (char-alphabetic? #\1))
(check-true "char-numeric?" (char-numeric? #\5))
(check-true "char-whitespace?" (char-whitespace? #\space))
(check-true "char-upper-case?" (char-upper-case? #\A))
(check-true "char-lower-case?" (char-lower-case? #\a))
(check "char-upcase" (char-upcase #\a) #\A)
(check "char-downcase" (char-downcase #\A) #\a)
(check "char->integer" (char->integer #\A) 65)
(check "integer->char" (integer->char 65) #\A)
(check-true "char<?" (char<? #\a #\b))
(check-true "char<=?" (char<=? #\a #\a))
(check-true "char>?" (char>? #\b #\a))

;;; ---- Bytevector operations ----
(check "make-bytevector" (make-bytevector 3 0) #u8(0 0 0))
(check "bytevector" (bytevector 1 2 3) #u8(1 2 3))
(check "bytevector-length" (bytevector-length #u8(1 2 3)) 3)
(check "bytevector-u8-ref" (bytevector-u8-ref #u8(10 20 30) 1) 20)
(let ((bv (bytevector 1 2 3)))
  (bytevector-u8-set! bv 1 99)
  (check "bytevector-u8-set!" bv #u8(1 99 3)))
(check "bytevector-copy" (bytevector-copy #u8(1 2 3)) #u8(1 2 3))
(check "bytevector-copy range" (bytevector-copy #u8(1 2 3 4 5) 1 4) #u8(2 3 4))
(check "bytevector-append" (bytevector-append #u8(1 2) #u8(3 4)) #u8(1 2 3 4))
(check "utf8->string" (utf8->string #u8(104 101 108 108 111)) "hello")
(check "string->utf8" (string->utf8 "hello") #u8(104 101 108 108 111))

;;; ---- List operations ----
(check "list-ref" (list-ref '(a b c d) 2) 'c)
(check "list-tail" (list-tail '(a b c d) 2) '(c d))
(check "list-copy" (list-copy '(1 2 3)) '(1 2 3))
(check "make-list" (make-list 3 'x) '(x x x))
(check-true "member" (pair? (member 3 '(1 2 3 4))))
(check-false "member miss" (member 5 '(1 2 3 4)))
(check "assoc" (assoc 'b '((a . 1) (b . 2) (c . 3))) '(b . 2))
(check-false "assoc miss" (assoc 'z '((a . 1) (b . 2))))
(check "assq" (assq 'b '((a . 1) (b . 2))) '(b . 2))
(check "assv" (assv 2 '((1 . a) (2 . b))) '(2 . b))

;;; ---- map / for-each with multiple lists ----
(check "map 2 lists" (map + '(1 2 3) '(10 20 30)) '(11 22 33))
(check "map 3 lists" (map + '(1 2) '(10 20) '(100 200)) '(111 222))
(let ((result '()))
  (for-each (lambda (x y) (set! result (cons (+ x y) result)))
            '(1 2 3) '(10 20 30))
  (check "for-each 2 lists" (reverse result) '(11 22 33)))

;;; ---- Tail calls in various forms ----
(define (loop-let n)
  (let lp ((i n) (acc 0))
    (if (= i 0) acc (lp (- i 1) (+ acc i)))))
(check "named let tail" (loop-let 10000) 50005000)

(define (loop-do n)
  (do ((i 0 (+ i 1))
       (acc 0 (+ acc i)))
      ((= i n) acc)))
(check "do tail" (loop-do 10000) 49995000)

;;; ---- Eval ----
(check "eval" (eval '(+ 1 2) (interaction-environment)) 3)
(check "eval list" (eval '(list 1 2 3) (interaction-environment)) '(1 2 3))

;;; ---- apply ----
(check "apply" (apply + '(1 2 3)) 6)
(check "apply mixed" (apply + 1 2 '(3 4)) 10)
(check "apply string" (apply string #\a #\b '(#\c)) "abc")

;;; ---- Quasiquote ----
(let ((x 42))
  (check "quasiquote" `(a ,x c) '(a 42 c)))
(let ((xs '(1 2 3)))
  (check "quasiquote splicing" `(a ,@xs b) '(a 1 2 3 b)))
(check "nested quasi" `(a `(b ,(+ 1 2))) '(a (quasiquote (b (unquote (+ 1 2))))))

;;; ---- Guard with re-raise ----
(check "guard re-raise"
  (guard (e ((string? (error-object-message e))
             (error-object-message e)))
    (guard (e ((number? e) 'num))
      (error "caught" 42)))
  "caught")

;;; ---- Multiple return values edge cases ----
(check "receive multiple" (call-with-values (lambda () (values)) (lambda () 'none)) 'none)

;;; ---- Tail position in cond ----
(define (cond-tail n)
  (cond ((= n 0) 'done)
        ((even? n) (cond-tail (- n 2)))
        (else (cond-tail (- n 1)))))
(check "cond tail" (cond-tail 10000) 'done)

;;; ---- Tail position in case ----
(define (case-tail n)
  (case (modulo n 3)
    ((0) (if (= n 0) 'done (case-tail (- n 3))))
    ((1) (case-tail (- n 1)))
    ((2) (case-tail (- n 2)))))
(check "case tail" (case-tail 9999) 'done)

;;; ---- Tail position in when/unless ----
(define (when-loop n)
  (when (> n 0) (when-loop (- n 1))))
(when-loop 10000)
(check-true "when tail" #t)

;;; ---- and/or as tail ----
(define (and-tail n)
  (if (= n 0) #t (and #t (and-tail (- n 1)))))
(check "and tail" (and-tail 10000) #t)

(define (or-tail n)
  (if (= n 0) 'done (or #f (or-tail (- n 1)))))
(check "or tail" (or-tail 10000) 'done)

;;; ---- Bignum basics ----
(let ((big (* 999999999999999999 999999999999999999)))
  (check-true "bignum integer?" (integer? big))
  (check-true "bignum exact?" (exact? big))
  (check-true "bignum > fixnum-max" (> big 4611686018427387903)))

;;; ---- Rational arithmetic ----
(check "rational +" (+ 1/3 1/6) 1/2)
(check "rational *" (* 2/3 3/4) 1/2)
(check "rational /" (/ 1 3) 1/3)
(check "rational exact" (exact? 1/3) #t)

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "General coverage tests failed" fail))
