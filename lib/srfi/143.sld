(define-library (srfi 143)
  (import (scheme base))
  (export fx-width fx-greatest fx-least
          fixnum? fx=? fx<? fx>? fx<=? fx>=?
          fxzero? fxpositive? fxnegative? fxodd? fxeven?
          fxmax fxmin
          fx+ fx- fxneg fx* fxquotient fxremainder
          fxabs fxsquare
          fxand fxior fxxor fxnot
          fxarithmetic-shift fxarithmetic-shift-left fxarithmetic-shift-right
          fxbit-count fxlength fxif fxbit-set? fxcopy-bit
          fxfirst-set-bit fxbit-field
          fxbit-field-rotate fxbit-field-reverse)
  (begin
    (define fx-width 63)
    (define fx-greatest 4611686018427387903)
    (define fx-least -4611686018427387904)

    (define (fixnum? x) (and (integer? x) (exact? x)
                             (<= fx-least x fx-greatest)))
    (define (fx=? a b) (= a b))
    (define (fx<? a b) (< a b))
    (define (fx>? a b) (> a b))
    (define (fx<=? a b) (<= a b))
    (define (fx>=? a b) (>= a b))
    (define (fxzero? x) (= x 0))
    (define (fxpositive? x) (> x 0))
    (define (fxnegative? x) (< x 0))
    (define (fxodd? x) (odd? x))
    (define (fxeven? x) (even? x))
    (define (fxmax a b) (max a b))
    (define (fxmin a b) (min a b))
    (define (fx+ a b) (+ a b))
    (define (fx- a b) (- a b))
    (define (fxneg x) (- x))
    (define (fx* a b) (* a b))
    (define (fxquotient a b) (quotient a b))
    (define (fxremainder a b) (remainder a b))
    (define (fxabs x) (abs x))
    (define (fxsquare x) (* x x))

    (define (fxand a b)
      (if (and (= a 0) (= b 0)) 0
          (+ (* (fxand (arithmetic-shift a -1) (arithmetic-shift b -1)) 2)
             (if (and (odd? a) (odd? b)) 1 0))))

    (define (fxior a b)
      (if (and (= a 0) (= b 0)) 0
          (+ (* (fxior (arithmetic-shift a -1) (arithmetic-shift b -1)) 2)
             (if (or (odd? a) (odd? b)) 1 0))))

    (define (fxxor a b)
      (if (and (= a 0) (= b 0)) 0
          (+ (* (fxxor (arithmetic-shift a -1) (arithmetic-shift b -1)) 2)
             (if (not (eq? (odd? a) (odd? b))) 1 0))))

    (define (fxnot x) (- -1 x))

    (define (arithmetic-shift n count)
      (if (>= count 0)
          (* n (expt 2 count))
          (quotient n (expt 2 (- count)))))

    (define (fxarithmetic-shift x count) (arithmetic-shift x count))
    (define (fxarithmetic-shift-left x count) (arithmetic-shift x count))
    (define (fxarithmetic-shift-right x count) (arithmetic-shift x (- count)))

    (define (fxbit-count x)
      (if (< x 0)
          (fxbit-count (fxnot x))
          (let loop ((n x) (c 0))
            (if (= n 0) c
                (loop (arithmetic-shift n -1) (+ c (if (odd? n) 1 0)))))))

    (define (fxlength x)
      (let loop ((n (if (< x 0) (fxnot x) x)) (len 0))
        (if (= n 0) len
            (loop (arithmetic-shift n -1) (+ len 1)))))

    (define (fxbit-set? index x)
      (odd? (arithmetic-shift x (- index))))

    (define (fxif mask n0 n1)
      (fxior (fxand mask n0) (fxand (fxnot mask) n1)))

    (define (fxcopy-bit index x bit)
      (if (= bit 0)
          (fxand x (fxnot (arithmetic-shift 1 index)))
          (fxior x (arithmetic-shift 1 index))))

    (define (fxfirst-set-bit x)
      (if (= x 0) -1
          (let loop ((n x) (i 0))
            (if (odd? n) i
                (loop (arithmetic-shift n -1) (+ i 1))))))

    (define (fxbit-field x start end)
      (fxand (arithmetic-shift x (- start))
             (- (arithmetic-shift 1 (- end start)) 1)))

    (define (fxbit-field-rotate x count start end)
      (let* ((width (- end start))
             (field (fxbit-field x start end))
             (count2 (modulo count width))
             (rotated (fxior (arithmetic-shift field count2)
                             (arithmetic-shift field (- count2 width))))
             (mask (arithmetic-shift (- (arithmetic-shift 1 width) 1) start)))
        (fxior (fxand x (fxnot mask))
               (fxand (arithmetic-shift rotated start) mask))))

    (define (fxbit-field-reverse x start end)
      (let* ((width (- end start))
             (field (fxbit-field x start end))
             (mask (arithmetic-shift (- (arithmetic-shift 1 width) 1) start)))
        (let loop ((n field) (result 0) (i 0))
          (if (= i width)
              (fxior (fxand x (fxnot mask))
                     (arithmetic-shift result start))
              (loop (arithmetic-shift n -1)
                    (+ (* result 2) (if (odd? n) 1 0))
                    (+ i 1))))))))
