# Language Quick Reference

### Numbers

Kaappi supports fixnums (63-bit integers), bignums (arbitrary precision),
exact rationals, flonums (IEEE 754 f64), and complex numbers.

```scheme
(+ 1 2 3)              ;=> 6
(* 2.5 4)              ;=> 10.0
(expt 2 100)           ;=> 1267650600228229401496703205376
(/ 1 3)                ;=> 1/3
(+ 1/3 1/6)            ;=> 1/2
(sqrt -1)              ;=> 0+1i
(make-rectangular 3 4) ;=> 3+4i
```

### Strings

Strings are UTF-8 encoded and indexed by codepoint position.

```scheme
(string-length "hello")       ;=> 5
(string-ref "hello" 1)        ;=> #\e
(substring "hello" 1 4)       ;=> "ell"
(string-append "foo" "bar")   ;=> "foobar"
(string-upcase "hello")       ;=> "HELLO"
(string-length "héllo")       ;=> 5
(string-ref "lambda: λ" 8)   ;=> #\λ
```

### Lists

```scheme
(cons 1 '(2 3))        ;=> (1 2 3)
(car '(a b c))          ;=> a
(cdr '(a b c))          ;=> (b c)
(list 1 2 3)            ;=> (1 2 3)
(map (lambda (x) (* x x)) '(1 2 3))  ;=> (1 4 9)
(filter odd? '(1 2 3 4 5))           ;=> (1 3 5)
(fold + 0 '(1 2 3 4 5))              ;=> 15
```

### Vectors

```scheme
(define v #(10 20 30))
(vector-ref v 1)        ;=> 20
(vector-set! v 0 99)
(vector-map + #(1 2 3) #(10 20 30))  ;=> #(11 22 33)
```

### Booleans, Characters, Symbols

```scheme
(and #t #f)             ;=> #f
(or #f 42)              ;=> 42
(char-alphabetic? #\A)  ;=> #t
(char-upcase #\a)       ;=> #\A
(symbol? 'hello)        ;=> #t
(eq? 'abc 'abc)         ;=> #t
```

### Bytevectors

```scheme
(define bv #u8(10 20 30))
(bytevector-u8-ref bv 0)     ;=> 10
(bytevector-length bv)        ;=> 3
(utf8->string #u8(104 101 108 108 111))  ;=> "hello"
```

### Definitions and Functions

```scheme
(define x 42)
(define (add a b) (+ a b))
(add x 8)              ;=> 50

(define greet
  (lambda (name)
    (string-append "Hello, " name "!")))
(greet "World")         ;=> "Hello, World!"
```

### Conditionals

```scheme
(if (> 3 2) "yes" "no")       ;=> "yes"

(cond
  ((< x 0) "negative")
  ((= x 0) "zero")
  (else     "positive"))       ;=> "positive"

(case (+ 1 1)
  ((1) "one")
  ((2) "two")
  (else "other"))              ;=> "two"
```

### Binding Forms

```scheme
(let ((x 1) (y 2)) (+ x y))            ;=> 3
(let* ((x 1) (y (+ x 1))) (+ x y))     ;=> 3
(letrec ((even? (lambda (n)
                  (if (= n 0) #t (odd? (- n 1)))))
         (odd?  (lambda (n)
                  (if (= n 0) #f (even? (- n 1))))))
  (even? 10))                           ;=> #t

;; Named let (loop)
(let loop ((n 5) (acc 1))
  (if (= n 0) acc
      (loop (- n 1) (* n acc))))        ;=> 120

;; do
(do ((i 0 (+ i 1))
     (sum 0 (+ sum i)))
    ((= i 5) sum))                      ;=> 10
```

### Macros

```scheme
(define-syntax my-when
  (syntax-rules ()
    ((my-when test body ...)
     (if test (begin body ...)))))

(my-when (> 3 2)
  (display "yes")
  (newline))
;; prints: yes
```

### Exceptions

```scheme
(guard (exn
        ((string? (error-object-message exn))
         (display "Caught: ")
         (display (error-object-message exn))
         (newline)))
  (error "something went wrong" 42))
;; prints: Caught: something went wrong

(with-exception-handler
  (lambda (e) (display "Error!\n"))
  (lambda () (raise "boom"))
  'replace)
```

### Continuations

```scheme
;; Escape continuation (non-local exit)
(call/cc (lambda (exit)
  (for-each (lambda (x)
              (when (negative? x) (exit x)))
            '(1 2 -3 4))
  'all-positive))
;=> -3
```

### Parameters

```scheme
(define my-param (make-parameter 10))
(my-param)              ;=> 10

(parameterize ((my-param 42))
  (my-param))            ;=> 42

(my-param)              ;=> 10
```

### Lazy Evaluation

```scheme
(define p (delay (begin (display "computed!\n") 42)))
(force p)  ;; prints "computed!" then returns 42
(force p)  ;; returns 42 (cached, no recomputation)
```

### Records

```scheme
(define-record-type <point>
  (make-point x y)
  point?
  (x point-x)
  (y point-y set-point-y!))

(define p (make-point 3 4))
(point-x p)             ;=> 3
(set-point-y! p 10)
(point-y p)             ;=> 10
```

### Multiple Values

```scheme
(call-with-values
  (lambda () (values 1 2 3))
  (lambda (a b c) (+ a b c)))  ;=> 6

(let-values (((a b) (values 1 2)))
  (+ a b))                     ;=> 3
```

---

