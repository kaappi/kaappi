(define-library (srfi 128)
  (import (scheme base) (scheme case-lambda) (scheme char) (scheme inexact))
  (export comparator? comparator-ordered? comparator-hashable?
          make-comparator
          make-eq-comparator make-eqv-comparator make-equal-comparator
          make-default-comparator default-hash
          comparator-type-test-predicate comparator-equality-predicate
          comparator-ordering-predicate comparator-hash-function
          comparator-test-type comparator-check-type comparator-hash
          boolean-hash char-hash char-ci-hash
          string-hash string-ci-hash symbol-hash number-hash
          hash-bound hash-salt
          =? <? >? <=? >=?
          comparator-if<=> comparator-register-default!)
  (begin
    (define-record-type <comparator>
      (make-raw-comparator type-test equality ordering hash ordered? hashable?)
      comparator?
      (type-test comparator-type-test-predicate)
      (equality comparator-equality-predicate)
      (ordering comparator-ordering-predicate)
      (hash comparator-hash-function)
      (ordered? comparator-ordered?)
      (hashable? comparator-hashable?))

    (define (make-comparator type-test equality ordering hash)
      (make-raw-comparator
        (if (eq? type-test #t) (lambda (x) #t) type-test)
        (if (eq? equality #t)
            (lambda (x y) (equal? x y))
            equality)
        (if ordering ordering (lambda (x y) (error "comparator: no ordering")))
        (if hash hash (lambda (x) 0))
        (if ordering #t #f)
        (if hash #t #f)))

    (define (comparator-test-type cmp obj)
      ((comparator-type-test-predicate cmp) obj))

    (define (comparator-check-type cmp obj)
      (if (comparator-test-type cmp obj)
          #t
          (error "comparator type check failed" obj)))

    (define (comparator-hash cmp obj)
      ((comparator-hash-function cmp) obj))

    (define hash-bound (lambda () 33554432))
    (define hash-salt (lambda () 16064047))

    (define (boolean-hash x) (if x 1 0))
    (define (char-hash c) (modulo (char->integer c) (hash-bound)))
    (define (char-ci-hash c) (char-hash (char-downcase c)))
    (define (number-hash x) (if (exact? x) (modulo (abs x) (hash-bound))
                                (modulo (exact (floor (abs x))) (hash-bound))))
    (define (string-hash s)
      (let loop ((i 0) (h 0))
        (if (= i (string-length s)) (modulo h (hash-bound))
            (loop (+ i 1) (+ (* h 31) (char->integer (string-ref s i)))))))
    (define (string-ci-hash s) (string-hash (string-downcase s)))
    (define (symbol-hash s) (string-hash (symbol->string s)))

    (define (default-hash obj)
      (cond
        ((boolean? obj) (boolean-hash obj))
        ((char? obj) (char-hash obj))
        ((number? obj) (number-hash obj))
        ((string? obj) (string-hash obj))
        ((symbol? obj) (symbol-hash obj))
        ((null? obj) 0)
        ((pair? obj) (+ (default-hash (car obj)) (* 31 (default-hash (cdr obj)))))
        ((vector? obj) (if (= (vector-length obj) 0) 0
                           (default-hash (vector-ref obj 0))))
        (else 0)))

    (define (default-ordering a b)
      (cond
        ((and (boolean? a) (boolean? b)) (if (and b (not a)) #t #f))
        ((and (char? a) (char? b)) (char<? a b))
        ((and (number? a) (number? b)) (< a b))
        ((and (string? a) (string? b)) (string<? a b))
        ((and (symbol? a) (symbol? b)) (string<? (symbol->string a) (symbol->string b)))
        (else #f)))

    (define (make-eq-comparator) (make-comparator #t eq? #f #f))
    (define (make-eqv-comparator) (make-comparator #t eqv? #f #f))
    (define (make-equal-comparator) (make-comparator #t equal? #f default-hash))

    (define (make-default-comparator)
      (make-comparator #t equal? default-ordering default-hash))

    (define registered-comparators '())
    (define (comparator-register-default! cmp) #t)

    (define-syntax comparator-if<=>
      (syntax-rules ()
        ((comparator-if<=> cmp a b less equal greater)
         (let ((ordering (comparator-ordering-predicate cmp)))
           (cond
             ((ordering a b) less)
             ((ordering b a) greater)
             (else equal))))))

    (define =?
      (case-lambda
        ((cmp a b) ((comparator-equality-predicate cmp) a b))
        ((cmp a b c) (and (=? cmp a b) (=? cmp b c)))))

    (define <?
      (case-lambda
        ((cmp a b) ((comparator-ordering-predicate cmp) a b))
        ((cmp a b c) (and (<? cmp a b) (<? cmp b c)))))

    (define >?
      (case-lambda
        ((cmp a b) (<? cmp b a))
        ((cmp a b c) (and (>? cmp a b) (>? cmp b c)))))

    (define <=?
      (case-lambda
        ((cmp a b) (not (>? cmp a b)))
        ((cmp a b c) (and (<=? cmp a b) (<=? cmp b c)))))

    (define >=?
      (case-lambda
        ((cmp a b) (not (<? cmp a b)))
        ((cmp a b c) (and (>=? cmp a b) (>=? cmp b c)))))))
