(define-library (srfi 132)
  (import (scheme base) (scheme case-lambda))
  (export list-sorted? list-sort list-stable-sort list-sort! list-stable-sort!
          list-merge list-merge!
          vector-sorted? vector-sort vector-stable-sort vector-sort!
          vector-stable-sort!
          vector-merge vector-merge!
          list-delete-neighbor-dups list-delete-neighbor-dups!
          vector-delete-neighbor-dups vector-delete-neighbor-dups!
          vector-find-median vector-find-median!
          vector-select! vector-separate!)
  (begin

    ;; --- List helpers ---

    (define (list-sorted? less? lst)
      (or (null? lst) (null? (cdr lst))
          (and (not (less? (cadr lst) (car lst)))
               (list-sorted? less? (cdr lst)))))

    (define (%merge less? a b)
      (cond ((null? a) b)
            ((null? b) a)
            ((less? (car b) (car a))
             (cons (car b) (%merge less? a (cdr b))))
            (else
             (cons (car a) (%merge less? (cdr a) b)))))

    (define (%merge-sort less? lst)
      (if (or (null? lst) (null? (cdr lst))) lst
          (let-values (((a b) (%split lst)))
            (%merge less? (%merge-sort less? a) (%merge-sort less? b)))))

    (define (%split lst)
      (let loop ((slow lst) (fast lst) (acc '()))
        (if (or (null? fast) (null? (cdr fast)))
            (values (reverse acc) slow)
            (loop (cdr slow) (cddr fast) (cons (car slow) acc)))))

    ;; --- Vector helpers ---

    (define (%vector-sorted? less? vec start end)
      (or (<= (- end start) 1)
          (let loop ((i (+ start 1)))
            (or (= i end)
                (and (not (less? (vector-ref vec i)
                                 (vector-ref vec (- i 1))))
                     (loop (+ i 1)))))))

    (define (%vector-sort-range less? vec start end)
      (let ((len (- end start)))
        (if (= len 0)
            #()
            (list->vector
             (%merge-sort less? (vector->list (vector-copy vec start end)))))))

    (define (%vector-sort-range! less? vec start end)
      (when (> (- end start) 1)
        (let ((sorted (%vector-sort-range less? vec start end)))
          (vector-copy! vec start sorted))))

    (define (%vector-merge-ranges less? v1 s1 e1 v2 s2 e2)
      (let* ((len1 (- e1 s1))
             (len2 (- e2 s2))
             (result (make-vector (+ len1 len2))))
        (let loop ((i1 s1) (i2 s2) (j 0))
          (cond
           ((= i1 e1)
            (vector-copy! result j v2 i2 e2)
            result)
           ((= i2 e2)
            (vector-copy! result j v1 i1 e1)
            result)
           ((less? (vector-ref v2 i2) (vector-ref v1 i1))
            (vector-set! result j (vector-ref v2 i2))
            (loop i1 (+ i2 1) (+ j 1)))
           (else
            (vector-set! result j (vector-ref v1 i1))
            (loop (+ i1 1) i2 (+ j 1)))))))

    (define (%vector-merge-ranges! less? to at v1 s1 e1 v2 s2 e2)
      (let loop ((i1 s1) (i2 s2) (j at))
        (cond
         ((= i1 e1)
          (vector-copy! to j v2 i2 e2))
         ((= i2 e2)
          (vector-copy! to j v1 i1 e1))
         ((less? (vector-ref v2 i2) (vector-ref v1 i1))
          (vector-set! to j (vector-ref v2 i2))
          (loop i1 (+ i2 1) (+ j 1)))
         (else
          (vector-set! to j (vector-ref v1 i1))
          (loop (+ i1 1) i2 (+ j 1))))))

    ;; --- List sort procedures ---

    (define (list-sort less? lst) (%merge-sort less? lst))
    (define (list-stable-sort less? lst) (%merge-sort less? lst))
    (define (list-sort! less? lst) (%merge-sort less? lst))
    (define list-stable-sort! list-sort!)

    ;; --- List merge procedures ---

    (define (list-merge less? lis1 lis2) (%merge less? lis1 lis2))
    (define (list-merge! less? lis1 lis2) (%merge less? lis1 lis2))

    ;; --- List delete-neighbor-dups ---

    (define (list-delete-neighbor-dups = lis)
      (if (null? lis)
          '()
          (let loop ((prev (car lis)) (rest (cdr lis)) (acc (list (car lis))))
            (cond
             ((null? rest) (reverse acc))
             ((= prev (car rest)) (loop prev (cdr rest) acc))
             (else (loop (car rest) (cdr rest) (cons (car rest) acc)))))))

    (define list-delete-neighbor-dups! list-delete-neighbor-dups)

    ;; --- Vector sorted? ---

    (define vector-sorted?
      (case-lambda
        ((less? vec) (%vector-sorted? less? vec 0 (vector-length vec)))
        ((less? vec start) (%vector-sorted? less? vec start (vector-length vec)))
        ((less? vec start end) (%vector-sorted? less? vec start end))))

    ;; --- Vector sort procedures ---

    (define vector-sort
      (case-lambda
        ((less? vec)
         (%vector-sort-range less? vec 0 (vector-length vec)))
        ((less? vec start)
         (%vector-sort-range less? vec start (vector-length vec)))
        ((less? vec start end)
         (%vector-sort-range less? vec start end))))

    (define vector-stable-sort vector-sort)

    (define vector-sort!
      (case-lambda
        ((less? vec)
         (%vector-sort-range! less? vec 0 (vector-length vec)))
        ((less? vec start)
         (%vector-sort-range! less? vec start (vector-length vec)))
        ((less? vec start end)
         (%vector-sort-range! less? vec start end))))

    (define vector-stable-sort! vector-sort!)

    ;; --- Vector merge procedures ---

    (define vector-merge
      (case-lambda
        ((less? v1 v2)
         (%vector-merge-ranges less? v1 0 (vector-length v1)
                               v2 0 (vector-length v2)))
        ((less? v1 v2 s1)
         (%vector-merge-ranges less? v1 s1 (vector-length v1)
                               v2 0 (vector-length v2)))
        ((less? v1 v2 s1 e1)
         (%vector-merge-ranges less? v1 s1 e1
                               v2 0 (vector-length v2)))
        ((less? v1 v2 s1 e1 s2)
         (%vector-merge-ranges less? v1 s1 e1
                               v2 s2 (vector-length v2)))
        ((less? v1 v2 s1 e1 s2 e2)
         (%vector-merge-ranges less? v1 s1 e1 v2 s2 e2))))

    (define vector-merge!
      (case-lambda
        ((less? to v1 v2)
         (%vector-merge-ranges! less? to 0 v1 0 (vector-length v1)
                                v2 0 (vector-length v2)))
        ((less? to v1 v2 start)
         (%vector-merge-ranges! less? to start v1 0 (vector-length v1)
                                v2 0 (vector-length v2)))
        ((less? to v1 v2 start s1)
         (%vector-merge-ranges! less? to start v1 s1 (vector-length v1)
                                v2 0 (vector-length v2)))
        ((less? to v1 v2 start s1 e1)
         (%vector-merge-ranges! less? to start v1 s1 e1
                                v2 0 (vector-length v2)))
        ((less? to v1 v2 start s1 e1 s2)
         (%vector-merge-ranges! less? to start v1 s1 e1
                                v2 s2 (vector-length v2)))
        ((less? to v1 v2 start s1 e1 s2 e2)
         (%vector-merge-ranges! less? to start v1 s1 e1 v2 s2 e2))))

    ;; --- Vector delete-neighbor-dups ---

    (define vector-delete-neighbor-dups
      (case-lambda
        ((= vec)
         (%vector-delete-neighbor-dups = vec 0 (vector-length vec)))
        ((= vec start)
         (%vector-delete-neighbor-dups = vec start (vector-length vec)))
        ((= vec start end)
         (%vector-delete-neighbor-dups = vec start end))))

    (define (%vector-delete-neighbor-dups = vec start end)
      (if (>= start end)
          #()
          (let loop ((i (+ start 1))
                     (acc (list (vector-ref vec start))))
            (cond
             ((= i end) (list->vector (reverse acc)))
             ((= (car acc) (vector-ref vec i))
              (loop (+ i 1) acc))
             (else
              (loop (+ i 1) (cons (vector-ref vec i) acc)))))))

    (define vector-delete-neighbor-dups!
      (case-lambda
        ((= vec)
         (%vector-delete-neighbor-dups! = vec 0 (vector-length vec)))
        ((= vec start)
         (%vector-delete-neighbor-dups! = vec start (vector-length vec)))
        ((= vec start end)
         (%vector-delete-neighbor-dups! = vec start end))))

    (define (%vector-delete-neighbor-dups! = vec start end)
      (if (>= start end)
          start
          (let loop ((i (+ start 1)) (j (+ start 1)))
            (cond
             ((= i end) j)
             ((= (vector-ref vec (- j 1)) (vector-ref vec i))
              (loop (+ i 1) j))
             (else
              (vector-set! vec j (vector-ref vec i))
              (loop (+ i 1) (+ j 1)))))))

    ;; --- Vector find-median ---

    (define vector-find-median
      (case-lambda
        ((less? v knil)
         (%vector-find-median less? v knil (lambda (a b) (/ (+ a b) 2))))
        ((less? v knil mean)
         (%vector-find-median less? v knil mean))))

    (define (%vector-find-median less? v knil mean)
      (let ((n (vector-length v)))
        (cond
         ((= n 0) knil)
         (else
          (let ((sorted (vector-sort less? v)))
            (if (odd? n)
                (vector-ref sorted (quotient n 2))
                (mean (vector-ref sorted (- (quotient n 2) 1))
                      (vector-ref sorted (quotient n 2)))))))))

    (define vector-find-median!
      (case-lambda
        ((less? v knil)
         (%vector-find-median! less? v knil (lambda (a b) (/ (+ a b) 2))))
        ((less? v knil mean)
         (%vector-find-median! less? v knil mean))))

    (define (%vector-find-median! less? v knil mean)
      (let ((n (vector-length v)))
        (cond
         ((= n 0) knil)
         (else
          (vector-sort! less? v)
          (if (odd? n)
              (vector-ref v (quotient n 2))
              (mean (vector-ref v (- (quotient n 2) 1))
                    (vector-ref v (quotient n 2))))))))

    ;; --- Vector select! and separate! ---

    (define vector-select!
      (case-lambda
        ((less? v k)
         (%vector-sort-range! less? v 0 (vector-length v))
         (vector-ref v k))
        ((less? v k start)
         (%vector-sort-range! less? v start (vector-length v))
         (vector-ref v (+ start k)))
        ((less? v k start end)
         (%vector-sort-range! less? v start end)
         (vector-ref v (+ start k)))))

    (define vector-separate!
      (case-lambda
        ((less? v k)
         (%vector-sort-range! less? v 0 (vector-length v)))
        ((less? v k start)
         (%vector-sort-range! less? v start (vector-length v)))
        ((less? v k start end)
         (%vector-sort-range! less? v start end))))))
