(define-library (srfi 151)
  (import (scheme base) (scheme case-lambda))
  (export bitwise-not bitwise-and bitwise-ior bitwise-xor bitwise-eqv
          bitwise-nand bitwise-nor bitwise-andc1 bitwise-andc2
          bitwise-orc1 bitwise-orc2
          arithmetic-shift bit-count integer-length bitwise-if
          bit-set? copy-bit bit-swap any-bit-set? every-bit-set? first-set-bit
          bit-field bit-field-any? bit-field-every? bit-field-clear bit-field-set
          bit-field-replace bit-field-replace-same
          bit-field-rotate bit-field-reverse
          bits->list list->bits bits->vector vector->bits bits
          bitwise-fold bitwise-for-each bitwise-unfold make-bitwise-generator)
  (begin
    (define (bitwise-not n) (- -1 n))

    (define (%bitwise-and2 a b)
      (if (or (= a 0) (= b 0)) 0
          (+ (* (%bitwise-and2 (quotient a 2) (quotient b 2)) 2)
             (if (and (odd? a) (odd? b)) 1 0))))

    (define (%bitwise-ior2 a b)
      (if (and (= a 0) (= b 0)) 0
          (+ (* (%bitwise-ior2 (quotient a 2) (quotient b 2)) 2)
             (if (or (odd? a) (odd? b)) 1 0))))

    (define (%bitwise-xor2 a b)
      (if (and (= a 0) (= b 0)) 0
          (+ (* (%bitwise-xor2 (quotient a 2) (quotient b 2)) 2)
             (if (not (eq? (odd? a) (odd? b))) 1 0))))

    (define (bitwise-and . args)
      (if (null? args) -1
          (let loop ((result (car args)) (rest (cdr args)))
            (if (null? rest) result
                (loop (%bitwise-and2 result (car rest)) (cdr rest))))))

    (define (bitwise-ior . args)
      (if (null? args) 0
          (let loop ((result (car args)) (rest (cdr args)))
            (if (null? rest) result
                (loop (%bitwise-ior2 result (car rest)) (cdr rest))))))

    (define (bitwise-xor . args)
      (if (null? args) 0
          (let loop ((result (car args)) (rest (cdr args)))
            (if (null? rest) result
                (loop (%bitwise-xor2 result (car rest)) (cdr rest))))))

    (define (bitwise-eqv a b) (bitwise-not (bitwise-xor a b)))
    (define (bitwise-nand a b) (bitwise-not (bitwise-and a b)))
    (define (bitwise-nor a b) (bitwise-not (bitwise-ior a b)))
    (define (bitwise-andc1 a b) (bitwise-and (bitwise-not a) b))
    (define (bitwise-andc2 a b) (bitwise-and a (bitwise-not b)))
    (define (bitwise-orc1 a b) (bitwise-ior (bitwise-not a) b))
    (define (bitwise-orc2 a b) (bitwise-ior a (bitwise-not b)))

    (define (arithmetic-shift n count)
      (if (>= count 0)
          (* n (expt 2 count))
          (quotient n (expt 2 (- count)))))

    (define (bit-count n)
      (if (< n 0) (bit-count (bitwise-not n))
          (let loop ((x n) (c 0))
            (if (= x 0) c
                (loop (quotient x 2) (+ c (if (odd? x) 1 0)))))))

    (define (integer-length n)
      (let loop ((x (if (< n 0) (bitwise-not n) n)) (len 0))
        (if (= x 0) len
            (loop (quotient x 2) (+ len 1)))))

    (define (bitwise-if mask n0 n1)
      (bitwise-ior (bitwise-and mask n0) (bitwise-and (bitwise-not mask) n1)))

    (define (bit-set? index n) (odd? (arithmetic-shift n (- index))))

    (define (copy-bit index n bit)
      (if (= bit 0)
          (bitwise-and n (bitwise-not (arithmetic-shift 1 index)))
          (bitwise-ior n (arithmetic-shift 1 index))))

    (define (bit-swap i j n)
      (let ((bi (if (bit-set? i n) 1 0))
            (bj (if (bit-set? j n) 1 0)))
        (copy-bit i (copy-bit j n bi) bj)))

    (define (any-bit-set? mask n) (not (= 0 (bitwise-and mask n))))
    (define (every-bit-set? mask n) (= mask (bitwise-and mask n)))

    (define (first-set-bit n)
      (if (= n 0) -1
          (let loop ((x n) (i 0))
            (if (odd? x) i (loop (arithmetic-shift x -1) (+ i 1))))))

    (define (bit-field n start end)
      (bitwise-and (arithmetic-shift n (- start))
                   (- (arithmetic-shift 1 (- end start)) 1)))

    (define (bit-field-any? n start end) (not (= 0 (bit-field n start end))))
    (define (bit-field-every? n start end)
      (let ((mask (- (arithmetic-shift 1 (- end start)) 1)))
        (= mask (bit-field n start end))))

    (define (bit-field-clear n start end)
      (let ((mask (arithmetic-shift (- (arithmetic-shift 1 (- end start)) 1) start)))
        (bitwise-and n (bitwise-not mask))))

    (define (bit-field-set n start end)
      (let ((mask (arithmetic-shift (- (arithmetic-shift 1 (- end start)) 1) start)))
        (bitwise-ior n mask)))

    (define (bit-field-replace dst src start end)
      (let ((mask (arithmetic-shift (- (arithmetic-shift 1 (- end start)) 1) start)))
        (bitwise-ior (bitwise-and dst (bitwise-not mask))
                     (bitwise-and (arithmetic-shift src start) mask))))

    (define (bit-field-replace-same dst src start end)
      (bit-field-replace dst (bit-field src start end) start end))

    (define (bit-field-rotate n count start end)
      (let* ((width (- end start))
             (field (bit-field n start end))
             (count2 (modulo count width))
             (rotated (bitwise-ior (arithmetic-shift field count2)
                                   (arithmetic-shift field (- count2 width))))
             (mask (arithmetic-shift (- (arithmetic-shift 1 width) 1) start)))
        (bitwise-ior (bitwise-and n (bitwise-not mask))
                     (bitwise-and (arithmetic-shift rotated start) mask))))

    (define (bit-field-reverse n start end)
      (let* ((width (- end start))
             (field (bit-field n start end))
             (mask (arithmetic-shift (- (arithmetic-shift 1 width) 1) start)))
        (let loop ((x field) (result 0) (i 0))
          (if (= i width)
              (bitwise-ior (bitwise-and n (bitwise-not mask))
                           (arithmetic-shift result start))
              (loop (arithmetic-shift x -1)
                    (+ (* result 2) (if (odd? x) 1 0))
                    (+ i 1))))))

    (define (bits->list n len)
      (let loop ((i 0) (result '()))
        (if (= i len) (reverse result)
            (loop (+ i 1) (cons (bit-set? i n) result)))))

    (define (list->bits lst)
      (let loop ((l lst) (i 0) (result 0))
        (if (null? l) result
            (loop (cdr l) (+ i 1)
                  (if (car l) (copy-bit i result 1) result)))))

    (define (bits->vector n len)
      (let ((v (make-vector len)))
        (let loop ((i 0))
          (if (= i len) v
              (begin (vector-set! v i (bit-set? i n))
                     (loop (+ i 1)))))))

    (define (vector->bits vec)
      (let loop ((i 0) (result 0))
        (if (= i (vector-length vec)) result
            (loop (+ i 1)
                  (if (vector-ref vec i) (copy-bit i result 1) result)))))

    (define (bits . lst) (list->bits lst))

    (define (bitwise-fold proc seed n)
      (let loop ((x n) (i 0) (acc seed))
        (if (= x 0) acc
            (loop (arithmetic-shift x -1) (+ i 1) (proc (odd? x) acc)))))

    (define (bitwise-for-each proc n)
      (let loop ((x n) (i 0))
        (if (not (= x 0))
            (begin (proc (odd? x))
                   (loop (arithmetic-shift x -1) (+ i 1))))))

    (define (bitwise-unfold stop? mapper successor seed)
      (let loop ((s seed) (i 0) (result 0))
        (if (stop? s) result
            (loop (successor s) (+ i 1)
                  (if (mapper s) (copy-bit i result 1) result)))))

    (define (make-bitwise-generator n)
      (let ((x n))
        (lambda ()
          (if (= x 0) 0
              (let ((bit (if (odd? x) 1 0)))
                (set! x (arithmetic-shift x -1))
                bit)))))))
