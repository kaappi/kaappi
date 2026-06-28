(import (scheme base) (scheme write) (kaappi bdd))

(describe "LLVM backend target expressions"
  (describe "arithmetic"
    (it "folds constant addition"
      (expect (+ 1 2) to-equal 3))

    (it "handles subtraction"
      (expect (- 10 3) to-equal 7))

    (it "handles multiplication"
      (expect (* 4 5) to-equal 20))

    (it "handles nested arithmetic"
      (expect (+ (* 2 3) (- 10 4)) to-equal 12)))

  (describe "display values"
    (it "converts fixnums to strings"
      (expect (number->string 42) to-equal "42"))

    (it "converts negative fixnums"
      (expect (number->string -7) to-equal "-7"))

    (it "concatenates strings"
      (expect (string-append "hello" " world") to-equal "hello world")))

  (describe "boolean logic"
    (it "evaluates true"
      (expect #t to-be-truthy))

    (it "evaluates false"
      (expect #f to-be-falsy))

    (it "evaluates not"
      (expect (not #f) to-be-truthy)))

  (describe "if expressions"
    (it "selects consequent when true"
      (expect (if #t 1 2) to-equal 1))

    (it "selects alternate when false"
      (expect (if #f 1 2) to-equal 2))

    (it "folds comparison in test"
      (expect (if (< 1 2) 10 20) to-equal 10)))

  (describe "string constants"
    (it "creates strings"
      (expect "hello" to-equal "hello"))

    (it "measures string length"
      (expect (string-length "world") to-equal 5)))

  (describe "lambda"
    (it "applies inline lambda"
      (expect ((lambda (x) (+ x 1)) 41) to-equal 42))

    (it "applies lambda with multiple args"
      (expect ((lambda (a b) (+ a b)) 3 7) to-equal 10))

    (it "supports nested lambda (closure)"
      (expect (((lambda (n) (lambda (x) (+ n x))) 10) 5) to-equal 15)))

  (describe "and/or"
    (it "and returns last truthy value"
      (expect (and 1 2 3) to-equal 3))

    (it "and short-circuits on false"
      (expect (and 1 #f 3) to-be-falsy))

    (it "or returns first truthy value"
      (expect (or #f #f 42) to-equal 42))

    (it "or returns false when all false"
      (expect (or #f #f) to-be-falsy)))

  (describe "when/unless"
    (it "when executes body on true"
      (expect (when #t 42) to-equal 42))

    (it "unless executes body on false"
      (expect (unless #f 99) to-equal 99)))

  (describe "let"
    (it "binds local variables"
      (expect (let ((x 5) (y 3)) (+ x y)) to-equal 8))

    (it "let* uses sequential bindings"
      (expect (let* ((x 10) (y (+ x 5))) y) to-equal 15))

    (it "nested let scopes correctly"
      (expect (let ((x 1))
                (let ((y (+ x 10)))
                  (+ x y)))
              to-equal 12))

    (it "let in function body"
      (define (compute a b)
        (let ((sum (+ a b))
              (diff (- a b)))
          (* sum diff)))
      (expect (compute 7 3) to-equal 40)))

  (describe "tail calls"
    (it "optimizes self-tail-call as loop"
      (define (loop n)
        (if (= n 0) 0 (loop (- n 1))))
      (expect (loop 1000000) to-equal 0))

    (it "handles accumulator pattern"
      (define (sum n acc)
        (if (= n 0) acc (sum (- n 1) (+ acc n))))
      (expect (sum 100 0) to-equal 5050))

    (it "tail calls to other native functions"
      (define (double x) (+ x x))
      (define (apply-double x) (double x))
      (expect (apply-double 21) to-equal 42))

    (it "non-tail calls still work"
      (define (fib n)
        (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))
      (expect (fib 10) to-equal 55)))

  (describe "variadic parameters"
    (it "collects all args as rest parameter"
      (define (my-list . args) args)
      (expect (my-list 1 2 3) to-equal '(1 2 3)))

    (it "splits fixed and rest parameters"
      (define (first-and-rest x . rest) rest)
      (expect (first-and-rest 10 20 30) to-equal '(20 30)))

    (it "handles empty rest list"
      (define (maybe-rest x . rest) rest)
      (expect (maybe-rest 42) to-equal '()))

    (it "supports operations on rest list"
      (define (sum-all . nums)
        (define (loop lst acc)
          (if (null? lst) acc
              (loop (cdr lst) (+ acc (car lst)))))
        (loop nums 0))
      (expect (sum-all 1 2 3 4 5) to-equal 15))))

(run-specs)
