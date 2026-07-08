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

    ;; Registered comparators for extending the default comparator
    (define registered-comparators '())

    (define (find-registered-comparator a b)
      (let loop ((cmps registered-comparators))
        (if (null? cmps)
            #f
            (if (and (comparator-test-type (car cmps) a)
                     (comparator-test-type (car cmps) b))
                (car cmps)
                (loop (cdr cmps))))))

    (define (find-registered-hash obj)
      (let loop ((cmps registered-comparators))
        (if (null? cmps)
            #f
            (if (and (comparator-test-type (car cmps) obj)
                     (comparator-hashable? (car cmps)))
                (car cmps)
                (loop (cdr cmps))))))

    (define (default-hash obj)
      (let ((reg (find-registered-hash obj)))
        (if reg
            (comparator-hash reg obj)
            (cond
              ((boolean? obj) (boolean-hash obj))
              ((char? obj) (char-hash obj))
              ((number? obj) (number-hash obj))
              ((string? obj) (string-hash obj))
              ((symbol? obj) (symbol-hash obj))
              ((null? obj) 0)
              ((pair? obj)
               (modulo (+ (default-hash (car obj))
                          (* 31 (default-hash (cdr obj))))
                       (hash-bound)))
              ((vector? obj)
               (let loop ((i 0) (h 0))
                 (if (= i (vector-length obj))
                     (modulo h (hash-bound))
                     (loop (+ i 1)
                           (+ (* h 31) (default-hash (vector-ref obj i)))))))
              ((bytevector? obj)
               (let loop ((i 0) (h 0))
                 (if (= i (bytevector-length obj))
                     (modulo h (hash-bound))
                     (loop (+ i 1)
                           (+ (* h 31) (bytevector-u8-ref obj i))))))
              (else 0)))))

    ;; Type index for cross-type total ordering
    (define (type-index obj)
      (cond
        ((null? obj) 0)
        ((boolean? obj) 1)
        ((char? obj) 2)
        ((number? obj) 3)
        ((string? obj) 4)
        ((symbol? obj) 5)
        ((bytevector? obj) 6)
        ((pair? obj) 7)
        ((vector? obj) 8)
        (else 9)))

    ;; Lexicographic ordering for compound types
    (define (pair-ordering a b)
      (cond
        ((default-ordering (car a) (car b)) #t)
        ((default-ordering (car b) (car a)) #f)
        (else (default-ordering (cdr a) (cdr b)))))

    (define (vector-ordering a b)
      (let ((la (vector-length a))
            (lb (vector-length b)))
        (let loop ((i 0))
          (cond
            ((= i la) (< la lb))
            ((= i lb) #f)
            ((default-ordering (vector-ref a i) (vector-ref b i)) #t)
            ((default-ordering (vector-ref b i) (vector-ref a i)) #f)
            (else (loop (+ i 1)))))))

    (define (bytevector-ordering a b)
      (let ((la (bytevector-length a))
            (lb (bytevector-length b)))
        (let loop ((i 0))
          (cond
            ((= i la) (< la lb))
            ((= i lb) #f)
            ((< (bytevector-u8-ref a i) (bytevector-u8-ref b i)) #t)
            ((> (bytevector-u8-ref a i) (bytevector-u8-ref b i)) #f)
            (else (loop (+ i 1)))))))

    (define (default-ordering a b)
      (let ((reg (find-registered-comparator a b)))
        (if reg
            ((comparator-ordering-predicate reg) a b)
            (let ((ta (type-index a))
                  (tb (type-index b)))
              (cond
                ((< ta tb) #t)
                ((> ta tb) #f)
                ((null? a) #f)
                ((boolean? a) (and (not a) b))
                ((char? a) (char<? a b))
                ((number? a) (< a b))
                ((string? a) (string<? a b))
                ((symbol? a) (string<? (symbol->string a) (symbol->string b)))
                ((pair? a) (pair-ordering a b))
                ((vector? a) (vector-ordering a b))
                ((bytevector? a) (bytevector-ordering a b))
                (else #f))))))

    (define (default-equality a b)
      (let ((reg (find-registered-comparator a b)))
        (if reg
            ((comparator-equality-predicate reg) a b)
            (equal? a b))))

    (define (make-eq-comparator) (make-comparator #t eq? #f default-hash))
    (define (make-eqv-comparator) (make-comparator #t eqv? #f default-hash))
    (define (make-equal-comparator) (make-comparator #t equal? #f default-hash))

    (define (make-default-comparator)
      (make-comparator #t default-equality default-ordering default-hash))

    (define (comparator-register-default! cmp)
      (set! registered-comparators (cons cmp registered-comparators)))

    (define-syntax comparator-if<=>
      (syntax-rules ()
        ((comparator-if<=> a b less equal greater)
         (comparator-if<=> (make-default-comparator) a b less equal greater))
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
