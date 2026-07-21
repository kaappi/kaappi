;;; SRFI 178 — Bitvector Library
;;;
;;; Implemented exactly as the SRFI's own reference suggests: "a whole byte
;;; to represent each bit ... favoring simplicity/speed over compactness."
;;; A bitvector is a record wrapping a bytevector of 0/1 bytes, kept
;;; disjoint from bytevectors and from SRFI 160 u8vectors (Kaappi has no
;;; u1vector type to be disjoint from instead).

(define-library (srfi 178)
  (import (scheme base) (scheme case-lambda) (srfi 158)
          (only (srfi 151) bitwise-and arithmetic-shift integer-length))
  (export
    bit->integer bit->boolean
    make-bitvector bitvector bitvector-unfold bitvector-unfold-right
    bitvector-copy bitvector-reverse-copy bitvector-append
    bitvector-concatenate bitvector-append-subbitvectors
    bitvector? bitvector-empty? bitvector=?
    bitvector-ref/int bitvector-ref/bool bitvector-length
    bitvector-take bitvector-take-right bitvector-drop bitvector-drop-right
    bitvector-segment
    bitvector-fold/int bitvector-fold/bool
    bitvector-fold-right/int bitvector-fold-right/bool
    bitvector-map/int bitvector-map/bool
    bitvector-map!/int bitvector-map!/bool
    bitvector-map->list/int bitvector-map->list/bool
    bitvector-for-each/int bitvector-for-each/bool
    bitvector-prefix-length bitvector-suffix-length
    bitvector-prefix? bitvector-suffix?
    bitvector-pad bitvector-pad-right
    bitvector-trim bitvector-trim-right bitvector-trim-both
    bitvector-set! bitvector-swap! bitvector-reverse!
    bitvector-copy! bitvector-reverse-copy!
    bitvector->list/int bitvector->list/bool
    reverse-bitvector->list/int reverse-bitvector->list/bool
    list->bitvector reverse-list->bitvector
    bitvector->vector/int bitvector->vector/bool
    reverse-bitvector->vector/int reverse-bitvector->vector/bool
    vector->bitvector reverse-vector->bitvector
    bitvector->string string->bitvector
    bitvector->integer integer->bitvector
    make-bitvector/int-generator make-bitvector/bool-generator
    make-bitvector-accumulator
    bitvector-not bitvector-not!
    bitvector-and bitvector-and! bitvector-ior bitvector-ior!
    bitvector-xor bitvector-xor! bitvector-eqv bitvector-eqv!
    bitvector-nand bitvector-nand! bitvector-nor bitvector-nor!
    bitvector-andc1 bitvector-andc1! bitvector-andc2 bitvector-andc2!
    bitvector-orc1 bitvector-orc1! bitvector-orc2 bitvector-orc2!
    bitvector-logical-shift bitvector-count bitvector-count-run
    bitvector-if bitvector-first-bit
    bitvector-field-any? bitvector-field-every?
    bitvector-field-clear bitvector-field-clear!
    bitvector-field-set bitvector-field-set!
    bitvector-field-replace bitvector-field-replace!
    bitvector-field-replace-same bitvector-field-replace-same!
    bitvector-field-rotate bitvector-field-flip bitvector-field-flip!)
  (begin

    (define-record-type <bitvector>
      (%raw-make-bitvector bytes)
      bitvector?
      (bytes %bv-bytes))

    (define (%norm-bit bit)
      (if (or (eqv? bit 0) (eqv? bit #f)) 0 1))

    (define (bit->integer bit) (%norm-bit bit))
    (define (bit->boolean bit) (= 1 (%norm-bit bit)))

    (define (%len bv) (bytevector-length (%bv-bytes bv)))

    ;; --- constructors ---------------------------------------------------

    (define make-bitvector
      (case-lambda
        ((size) (make-bitvector size 0))
        ((size bit) (%raw-make-bitvector (make-bytevector size (%norm-bit bit))))))

    (define (bitvector . bits)
      (list->bitvector bits))

    (define (bitvector-unfold f length . seeds)
      (let ((bv (make-bytevector length 0)))
        (let loop ((i 0) (seeds seeds))
          (if (= i length)
              (%raw-make-bitvector bv)
              (call-with-values
                (lambda () (apply f i seeds))
                (lambda (bit . new-seeds)
                  (bytevector-u8-set! bv i (%norm-bit bit))
                  (loop (+ i 1) new-seeds)))))))

    (define (bitvector-unfold-right f length . seeds)
      (let ((bv (make-bytevector length 0)))
        (let loop ((i (- length 1)) (seeds seeds))
          (if (< i 0)
              (%raw-make-bitvector bv)
              (call-with-values
                (lambda () (apply f i seeds))
                (lambda (bit . new-seeds)
                  (bytevector-u8-set! bv i (%norm-bit bit))
                  (loop (- i 1) new-seeds)))))))

    (define bitvector-copy
      (case-lambda
        ((bv) (bitvector-copy bv 0 (%len bv)))
        ((bv start) (bitvector-copy bv start (%len bv)))
        ((bv start end)
         (%raw-make-bitvector (bytevector-copy (%bv-bytes bv) start end)))))

    (define bitvector-reverse-copy
      (case-lambda
        ((bv) (bitvector-reverse-copy bv 0 (%len bv)))
        ((bv start) (bitvector-reverse-copy bv start (%len bv)))
        ((bv start end)
         (let* ((n (- end start)) (out (make-bytevector n 0)) (src (%bv-bytes bv)))
           (do ((i 0 (+ i 1))) ((= i n) (%raw-make-bitvector out))
             (bytevector-u8-set! out i (bytevector-u8-ref src (- end i 1))))))))

    (define (bitvector-append . bvs)
      (bitvector-concatenate bvs))

    (define (bitvector-concatenate bvs)
      (let* ((total (apply + (map %len bvs)))
             (out (make-bytevector total 0)))
        (let loop ((bvs bvs) (at 0))
          (if (null? bvs)
              (%raw-make-bitvector out)
              (begin
                (bytevector-copy! out at (%bv-bytes (car bvs)))
                (loop (cdr bvs) (+ at (%len (car bvs)))))))))

    (define (bitvector-append-subbitvectors . triples)
      (bitvector-concatenate
        (let loop ((t triples))
          (if (null? t)
              '()
              (cons (bitvector-copy (car t) (cadr t) (caddr t))
                    (loop (cdddr t)))))))

    ;; --- predicates -------------------------------------------------------

    (define (bitvector-empty? bv) (= 0 (%len bv)))

    (define (bitvector=? . bvs)
      (or (null? bvs) (null? (cdr bvs))
          (let ((b0 (%bv-bytes (car bvs))))
            (every (lambda (b) (equal? b0 (%bv-bytes b))) (cdr bvs)))))

    (define (every pred lst)
      (or (null? lst) (and (pred (car lst)) (every pred (cdr lst)))))

    ;; --- selectors ----------------------------------------------------

    (define (bitvector-ref/int bv i) (bytevector-u8-ref (%bv-bytes bv) i))
    (define (bitvector-ref/bool bv i) (= 1 (bitvector-ref/int bv i)))
    (define (bitvector-length bv) (%len bv))

    ;; --- iteration --------------------------------------------------------

    (define (bitvector-take bv n) (bitvector-copy bv 0 n))
    (define (bitvector-take-right bv n) (bitvector-copy bv (- (%len bv) n) (%len bv)))
    (define (bitvector-drop bv n) (bitvector-copy bv n (%len bv)))
    (define (bitvector-drop-right bv n) (bitvector-copy bv 0 (- (%len bv) n)))

    (define (bitvector-segment bv n)
      (let ((len (%len bv)))
        (let loop ((i 0))
          (if (>= i len)
              '()
              (cons (bitvector-copy bv i (min len (+ i n)))
                    (loop (+ i n)))))))

    (define (%refs bvs i) (map (lambda (bv) (bitvector-ref/int bv i)) bvs))

    (define (bitvector-fold/int kons knil bv1 . bvs)
      (let ((all (cons bv1 bvs)) (len (%len bv1)))
        (let loop ((i 0) (acc knil))
          (if (= i len) acc (loop (+ i 1) (apply kons acc (%refs all i)))))))

    (define (bitvector-fold/bool kons knil bv1 . bvs)
      (apply bitvector-fold/int
             (lambda (acc . ints) (apply kons acc (map (lambda (x) (= x 1)) ints)))
             knil bv1 bvs))

    (define (bitvector-fold-right/int kons knil bv1 . bvs)
      (let ((all (cons bv1 bvs)) (len (%len bv1)))
        (let loop ((i (- len 1)) (acc knil))
          (if (< i 0) acc (loop (- i 1) (apply kons acc (%refs all i)))))))

    (define (bitvector-fold-right/bool kons knil bv1 . bvs)
      (apply bitvector-fold-right/int
             (lambda (acc . ints) (apply kons acc (map (lambda (x) (= x 1)) ints)))
             knil bv1 bvs))

    (define (bitvector-map/int f bv1 . bvs)
      (let* ((all (cons bv1 bvs)) (len (%len bv1)) (out (make-bytevector len 0)))
        (do ((i 0 (+ i 1))) ((= i len) (%raw-make-bitvector out))
          (bytevector-u8-set! out i (%norm-bit (apply f (%refs all i)))))))

    (define (bitvector-map/bool f bv1 . bvs)
      (apply bitvector-map/int
             (lambda ints (f (apply values-list->args (map (lambda (x) (= x 1)) ints))))
             bv1 bvs))

    (define (values-list->args . xs) xs)

    (define (bitvector-map!/int f bv1 . bvs)
      (let* ((all (cons bv1 bvs)) (len (%len bv1)) (dst (%bv-bytes bv1)))
        (do ((i 0 (+ i 1))) ((= i len))
          (bytevector-u8-set! dst i (%norm-bit (apply f (%refs all i)))))))

    (define (bitvector-map!/bool f bv1 . bvs)
      (apply bitvector-map!/int
             (lambda ints (f (apply values-list->args (map (lambda (x) (= x 1)) ints))))
             bv1 bvs))

    (define (bitvector-map->list/int f bv1 . bvs)
      (let ((all (cons bv1 bvs)) (len (%len bv1)))
        (let loop ((i 0))
          (if (= i len) '() (cons (apply f (%refs all i)) (loop (+ i 1)))))))

    (define (bitvector-map->list/bool f bv1 . bvs)
      (apply bitvector-map->list/int
             (lambda ints (apply f (map (lambda (x) (= x 1)) ints)))
             bv1 bvs))

    (define (bitvector-for-each/int f bv1 . bvs)
      (let ((all (cons bv1 bvs)) (len (%len bv1)))
        (do ((i 0 (+ i 1))) ((= i len)) (apply f (%refs all i)))))

    (define (bitvector-for-each/bool f bv1 . bvs)
      (apply bitvector-for-each/int
             (lambda ints (apply f (map (lambda (x) (= x 1)) ints)))
             bv1 bvs))

    ;; --- prefix/suffix/trim/pad -----------------------------------------

    (define (bitvector-prefix-length bv1 bv2)
      (let ((n (min (%len bv1) (%len bv2))))
        (let loop ((i 0))
          (if (or (= i n) (not (= (bitvector-ref/int bv1 i) (bitvector-ref/int bv2 i))))
              i (loop (+ i 1))))))

    (define (bitvector-suffix-length bv1 bv2)
      (let* ((l1 (%len bv1)) (l2 (%len bv2)) (n (min l1 l2)))
        (let loop ((i 0))
          (if (or (= i n)
                  (not (= (bitvector-ref/int bv1 (- l1 i 1)) (bitvector-ref/int bv2 (- l2 i 1)))))
              i (loop (+ i 1))))))

    (define (bitvector-prefix? bv1 bv2) (= (bitvector-prefix-length bv1 bv2) (%len bv1)))
    (define (bitvector-suffix? bv1 bv2) (= (bitvector-suffix-length bv1 bv2) (%len bv1)))

    (define (bitvector-pad bit bv length)
      (let* ((n (%len bv)) (b (%norm-bit bit)))
        (if (>= n length)
            (bitvector-copy bv (- n length) n)
            (let ((out (make-bytevector length b)))
              (bytevector-copy! out (- length n) (%bv-bytes bv))
              (%raw-make-bitvector out)))))

    (define (bitvector-pad-right bit bv length)
      (let* ((n (%len bv)) (b (%norm-bit bit)))
        (if (>= n length)
            (bitvector-copy bv 0 length)
            (let ((out (make-bytevector length b)))
              (bytevector-copy! out 0 (%bv-bytes bv))
              (%raw-make-bitvector out)))))

    (define (bitvector-trim bit bv)
      (let ((b (%norm-bit bit)) (n (%len bv)))
        (let loop ((i 0))
          (if (or (= i n) (not (= (bitvector-ref/int bv i) b)))
              (bitvector-copy bv i n)
              (loop (+ i 1))))))

    (define (bitvector-trim-right bit bv)
      (let ((b (%norm-bit bit)) (n (%len bv)))
        (let loop ((i n))
          (if (or (= i 0) (not (= (bitvector-ref/int bv (- i 1)) b)))
              (bitvector-copy bv 0 i)
              (loop (- i 1))))))

    (define (bitvector-trim-both bit bv) (bitvector-trim-right bit (bitvector-trim bit bv)))

    ;; --- mutators -----------------------------------------------------

    (define (bitvector-set! bv i bit) (bytevector-u8-set! (%bv-bytes bv) i (%norm-bit bit)))

    (define (bitvector-swap! bv i j)
      (let ((bytes (%bv-bytes bv)))
        (let ((tmp (bytevector-u8-ref bytes i)))
          (bytevector-u8-set! bytes i (bytevector-u8-ref bytes j))
          (bytevector-u8-set! bytes j tmp))))

    (define bitvector-reverse!
      (case-lambda
        ((bv) (bitvector-reverse! bv 0 (%len bv)))
        ((bv start) (bitvector-reverse! bv start (%len bv)))
        ((bv start end)
         (let loop ((i start) (j (- end 1)))
           (when (< i j) (bitvector-swap! bv i j) (loop (+ i 1) (- j 1)))))))

    (define bitvector-copy!
      (case-lambda
        ((to at from) (bitvector-copy! to at from 0 (%len from)))
        ((to at from start) (bitvector-copy! to at from start (%len from)))
        ((to at from start end)
         (bytevector-copy! (%bv-bytes to) at (%bv-bytes from) start end))))

    (define bitvector-reverse-copy!
      (case-lambda
        ((to at from) (bitvector-reverse-copy! to at from 0 (%len from)))
        ((to at from start) (bitvector-reverse-copy! to at from start (%len from)))
        ((to at from start end)
         (let ((rc (bitvector-reverse-copy from start end)))
           (bytevector-copy! (%bv-bytes to) at (%bv-bytes rc))))))

    ;; --- conversion -----------------------------------------------------

    (define bitvector->list/int
      (case-lambda
        ((bv) (bitvector->list/int bv 0 (%len bv)))
        ((bv start) (bitvector->list/int bv start (%len bv)))
        ((bv start end)
         (let loop ((i (- end 1)) (acc '()))
           (if (< i start) acc (loop (- i 1) (cons (bitvector-ref/int bv i) acc)))))))

    (define (bitvector->list/bool . args)
      (map (lambda (x) (= x 1)) (apply bitvector->list/int args)))

    (define reverse-bitvector->list/int
      (case-lambda
        ((bv) (reverse-bitvector->list/int bv 0 (%len bv)))
        ((bv start) (reverse-bitvector->list/int bv start (%len bv)))
        ((bv start end)
         (let loop ((i start) (acc '()))
           (if (>= i end) acc (loop (+ i 1) (cons (bitvector-ref/int bv i) acc)))))))

    (define (reverse-bitvector->list/bool . args)
      (map (lambda (x) (= x 1)) (apply reverse-bitvector->list/int args)))

    (define (list->bitvector lst)
      (%raw-make-bitvector (list->bytevector-of-bits lst)))

    (define (list->bytevector-of-bits lst)
      (let* ((n (length lst)) (out (make-bytevector n 0)))
        (let loop ((i 0) (l lst))
          (if (null? l) out
              (begin (bytevector-u8-set! out i (%norm-bit (car l)))
                     (loop (+ i 1) (cdr l)))))))

    (define (reverse-list->bitvector lst) (list->bitvector (reverse lst)))

    (define (bitvector->vector/int . args) (list->vector (apply bitvector->list/int args)))
    (define (bitvector->vector/bool . args) (list->vector (apply bitvector->list/bool args)))
    (define (reverse-bitvector->vector/int . args) (list->vector (apply reverse-bitvector->list/int args)))
    (define (reverse-bitvector->vector/bool . args) (list->vector (apply reverse-bitvector->list/bool args)))

    (define vector->bitvector
      (case-lambda
        ((vec) (list->bitvector (vector->list vec)))
        ((vec start) (list->bitvector (vector->list vec start)))
        ((vec start end) (list->bitvector (vector->list vec start end)))))

    (define reverse-vector->bitvector
      (case-lambda
        ((vec) (reverse-list->bitvector (vector->list vec)))
        ((vec start) (reverse-list->bitvector (vector->list vec start)))
        ((vec start end) (reverse-list->bitvector (vector->list vec start end)))))

    (define (bitvector->string bv)
      (let ((n (%len bv)))
        (let ((out (make-string (+ n 2))))
          (string-set! out 0 #\#)
          (string-set! out 1 #\*)
          (do ((i 0 (+ i 1))) ((= i n) out)
            (string-set! out (+ i 2) (if (= 1 (bitvector-ref/int bv i)) #\1 #\0))))))

    (define (string->bitvector s)
      (and (>= (string-length s) 2)
           (char=? (string-ref s 0) #\#) (char=? (string-ref s 1) #\*)
           (let* ((n (- (string-length s) 2)) (out (make-bytevector n 0)))
             (let loop ((i 0))
               (cond
                 ((= i n) (%raw-make-bitvector out))
                 (else
                  (let ((c (string-ref s (+ i 2))))
                    (cond
                      ((char=? c #\0) (bytevector-u8-set! out i 0) (loop (+ i 1)))
                      ((char=? c #\1) (bytevector-u8-set! out i 1) (loop (+ i 1)))
                      (else #f)))))))))

    (define (bitvector->integer bv)
      (let ((n (%len bv)))
        (let loop ((i (- n 1)) (acc 0))
          (if (< i 0) acc (loop (- i 1) (+ (* acc 2) (bitvector-ref/int bv i)))))))

    (define integer->bitvector
      (case-lambda
        ((int) (integer->bitvector int (integer-length int)))
        ((int len)
         (let ((out (make-bytevector len 0)))
           (do ((i 0 (+ i 1))) ((= i len) (%raw-make-bitvector out))
             (bytevector-u8-set! out i (if (= 1 (bitwise-and (arithmetic-shift int (- i)) 1)) 1 0)))))))

    ;; --- generators -----------------------------------------------------

    (define (make-bitvector/int-generator bv)
      (let ((i 0) (n (%len bv)))
        (lambda ()
          (if (>= i n)
              (eof-object)
              (let ((v (bitvector-ref/int bv i))) (set! i (+ i 1)) v)))))

    (define (make-bitvector/bool-generator bv)
      (let ((i 0) (n (%len bv)))
        (lambda ()
          (if (>= i n)
              (eof-object)
              (let ((v (bitvector-ref/bool bv i))) (set! i (+ i 1)) v)))))

    (define (make-bitvector-accumulator)
      (let ((acc '()))
        (lambda (x)
          (if (eof-object? x)
              (reverse-list->bitvector (reverse acc))
              (begin (set! acc (cons x acc)) (if #f #f))))))

    ;; --- bitwise combinators --------------------------------------------

    (define (%combine2 f bv1 bv2)
      (let* ((n (%len bv1)) (out (make-bytevector n 0)))
        (do ((i 0 (+ i 1))) ((= i n) (%raw-make-bitvector out))
          (bytevector-u8-set! out i (f (bitvector-ref/int bv1 i) (bitvector-ref/int bv2 i))))))

    (define (%combine2! dst bv1 bv2 f)
      (let ((n (%len dst)))
        (do ((i 0 (+ i 1))) ((= i n))
          (bytevector-u8-set! (%bv-bytes dst) i (f (bitvector-ref/int bv1 i) (bitvector-ref/int bv2 i))))))

    (define (%and2 a b) (if (and (= a 1) (= b 1)) 1 0))
    (define (%ior2 a b) (if (or (= a 1) (= b 1)) 1 0))
    (define (%xor2 a b) (if (= a b) 0 1))
    (define (%eqv2 a b) (if (= a b) 1 0))
    (define (%nand2 a b) (- 1 (%and2 a b)))
    (define (%nor2 a b) (- 1 (%ior2 a b)))
    (define (%andc1-2 a b) (%and2 (- 1 a) b))
    (define (%andc2-2 a b) (%and2 a (- 1 b)))
    (define (%orc1-2 a b) (%ior2 (- 1 a) b))
    (define (%orc2-2 a b) (%ior2 a (- 1 b)))

    (define (bitvector-not bv)
      (let* ((n (%len bv)) (out (make-bytevector n 0)))
        (do ((i 0 (+ i 1))) ((= i n) (%raw-make-bitvector out))
          (bytevector-u8-set! out i (- 1 (bitvector-ref/int bv i))))))

    (define (bitvector-not! bv)
      (let ((n (%len bv)))
        (do ((i 0 (+ i 1))) ((= i n))
          (bytevector-u8-set! (%bv-bytes bv) i (- 1 (bitvector-ref/int bv i))))))

    (define (%fold-assoc f bvs) (fold-left-bv f (car bvs) (cdr bvs)))
    (define (fold-left-bv f acc bvs)
      (if (null? bvs) acc (fold-left-bv f (%combine2 f acc (car bvs)) (cdr bvs))))

    (define (bitvector-and bv1 bv2 . more) (%fold-assoc %and2 (cons bv1 (cons bv2 more))))
    (define (bitvector-ior bv1 bv2 . more) (%fold-assoc %ior2 (cons bv1 (cons bv2 more))))
    (define (bitvector-xor bv1 bv2 . more) (%fold-assoc %xor2 (cons bv1 (cons bv2 more))))
    (define (bitvector-eqv bv1 bv2 . more) (%fold-assoc %eqv2 (cons bv1 (cons bv2 more))))

    (define (bitvector-and! dst . bvs) (for-each (lambda (b) (%combine2! dst dst b %and2)) bvs) dst)
    (define (bitvector-ior! dst . bvs) (for-each (lambda (b) (%combine2! dst dst b %ior2)) bvs) dst)
    (define (bitvector-xor! dst . bvs) (for-each (lambda (b) (%combine2! dst dst b %xor2)) bvs) dst)
    (define (bitvector-eqv! dst . bvs) (for-each (lambda (b) (%combine2! dst dst b %eqv2)) bvs) dst)

    (define (bitvector-nand bv1 bv2) (%combine2 %nand2 bv1 bv2))
    (define (bitvector-nor bv1 bv2) (%combine2 %nor2 bv1 bv2))
    (define (bitvector-nand! dst bv2) (%combine2! dst dst bv2 %nand2) dst)
    (define (bitvector-nor! dst bv2) (%combine2! dst dst bv2 %nor2) dst)

    (define (bitvector-andc1 bv1 bv2) (%combine2 %andc1-2 bv1 bv2))
    (define (bitvector-andc2 bv1 bv2) (%combine2 %andc2-2 bv1 bv2))
    (define (bitvector-orc1 bv1 bv2) (%combine2 %orc1-2 bv1 bv2))
    (define (bitvector-orc2 bv1 bv2) (%combine2 %orc2-2 bv1 bv2))
    (define (bitvector-andc1! dst bv2) (%combine2! dst dst bv2 %andc1-2) dst)
    (define (bitvector-andc2! dst bv2) (%combine2! dst dst bv2 %andc2-2) dst)
    (define (bitvector-orc1! dst bv2) (%combine2! dst dst bv2 %orc1-2) dst)
    (define (bitvector-orc2! dst bv2) (%combine2! dst dst bv2 %orc2-2) dst)

    ;; --- quasi-integer ops ------------------------------------------------

    (define (bitvector-logical-shift bv count bit)
      (let* ((n (%len bv)) (b (%norm-bit bit)) (out (make-bytevector n b)))
        (if (>= count 0)
            (do ((i (- n 1) (- i 1))) ((< i count) (%raw-make-bitvector out))
              (bytevector-u8-set! out i (bitvector-ref/int bv (- i count))))
            (let ((shift (- count)))
              (do ((i 0 (+ i 1))) ((>= i (- n shift)) (%raw-make-bitvector out))
                (bytevector-u8-set! out i (bitvector-ref/int bv (+ i shift))))))))

    (define (bitvector-count bit bv)
      (let ((b (%norm-bit bit)) (n (%len bv)))
        (let loop ((i 0) (c 0))
          (if (= i n) c (loop (+ i 1) (if (= (bitvector-ref/int bv i) b) (+ c 1) c))))))

    (define (bitvector-count-run bit bv i)
      (let ((b (%norm-bit bit)) (n (%len bv)))
        (let loop ((i i) (c 0))
          (if (or (= i n) (not (= (bitvector-ref/int bv i) b))) c (loop (+ i 1) (+ c 1))))))

    (define (bitvector-if if-bv then-bv else-bv)
      (let* ((n (%len if-bv)) (out (make-bytevector n 0)))
        (do ((i 0 (+ i 1))) ((= i n) (%raw-make-bitvector out))
          (bytevector-u8-set! out i
            (if (= 1 (bitvector-ref/int if-bv i)) (bitvector-ref/int then-bv i) (bitvector-ref/int else-bv i))))))

    (define (bitvector-first-bit bit bv)
      (let ((b (%norm-bit bit)) (n (%len bv)))
        (let loop ((i 0))
          (cond ((= i n) -1)
                ((= (bitvector-ref/int bv i) b) i)
                (else (loop (+ i 1)))))))

    ;; --- bit field operations -----------------------------------------

    (define (bitvector-field-any? bv start end)
      (let loop ((i start))
        (and (< i end) (or (= 1 (bitvector-ref/int bv i)) (loop (+ i 1))))))

    (define (bitvector-field-every? bv start end)
      (let loop ((i start))
        (or (>= i end) (and (= 1 (bitvector-ref/int bv i)) (loop (+ i 1))))))

    (define (bitvector-field-clear! bv start end)
      (do ((i start (+ i 1))) ((= i end)) (bitvector-set! bv i 0)))
    (define (bitvector-field-clear bv start end)
      (let ((c (bitvector-copy bv 0 (%len bv)))) (bitvector-field-clear! c start end) c))

    (define (bitvector-field-set! bv start end)
      (do ((i start (+ i 1))) ((= i end)) (bitvector-set! bv i 1)))
    (define (bitvector-field-set bv start end)
      (let ((c (bitvector-copy bv 0 (%len bv)))) (bitvector-field-set! c start end) c))

    (define (bitvector-field-replace! dest source start end)
      (do ((i start (+ i 1))) ((= i end)) (bitvector-set! dest i (bitvector-ref/int source (- i start)))))
    (define (bitvector-field-replace dest source start end)
      (let ((c (bitvector-copy dest 0 (%len dest)))) (bitvector-field-replace! c source start end) c))

    (define (bitvector-field-replace-same! dest source start end)
      (do ((i start (+ i 1))) ((= i end)) (bitvector-set! dest i (bitvector-ref/int source i))))
    (define (bitvector-field-replace-same dest source start end)
      (let ((c (bitvector-copy dest 0 (%len dest)))) (bitvector-field-replace-same! c source start end) c))

    (define (bitvector-field-rotate bv count start end)
      (let* ((n (- end start)))
        (if (= n 0)
            (bitvector-copy bv 0 (%len bv))
            (let* ((field (bitvector-copy bv start end))
                   (shift (modulo count n))
                   (rotated (bitvector-append (bitvector-copy field shift n) (bitvector-copy field 0 shift)))
                   (c (bitvector-copy bv 0 (%len bv))))
              (bitvector-field-replace! c rotated start end)
              c))))

    (define (bitvector-field-flip! bv start end)
      (do ((i start (+ i 1))) ((= i end)) (bitvector-set! bv i (- 1 (bitvector-ref/int bv i)))))
    (define (bitvector-field-flip bv start end)
      (let ((c (bitvector-copy bv 0 (%len bv)))) (bitvector-field-flip! c start end) c))))
