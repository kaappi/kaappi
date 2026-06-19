(define-library (srfi 196)
  (import (scheme base) (scheme char) (scheme cxr))
  (export range numeric-range iota-range vector-range string-range
          range-append range-reverse
          range? range=?
          range-length range-ref range-first range-last
          range-split-at subrange range-segment
          range-take range-take-right range-drop range-drop-right
          range-count range-any range-every
          range-map range-map->list range-map->vector
          range-for-each range-filter-map range-filter-map->list
          range-filter range-filter->list range-remove range-remove->list
          range-fold range-fold-right
          range-index range-index-right
          range-take-while range-take-while-right
          range-drop-while range-drop-while-right
          range->list range->vector range->string
          vector->range range->generator)
  (begin

    (define-record-type <range>
      (%make-range length indexer)
      range?
      (length %range-length)
      (indexer %range-indexer))

    ;;; Constructors

    (define (range length indexer)
      (%make-range length indexer))

    (define (numeric-range start end . rest)
      (let ((step (if (null? rest) 1 (car rest))))
        (let ((len (max 0 (ceiling (/ (- end start) step)))))
          (%make-range (exact len) (lambda (i) (+ start (* i step)))))))

    (define (iota-range length . rest)
      (let ((start (if (null? rest) 0 (car rest)))
            (step (if (or (null? rest) (null? (cdr rest))) 1 (cadr rest))))
        (%make-range length (lambda (i) (+ start (* i step))))))

    (define (vector-range vec)
      (%make-range (vector-length vec) (lambda (i) (vector-ref vec i))))

    (define vector->range vector-range)

    (define (string-range str)
      (%make-range (string-length str) (lambda (i) (string-ref str i))))

    (define (range-append . ranges)
      (if (null? ranges) (%make-range 0 (lambda (i) (error "range-ref: empty range")))
          (if (null? (cdr ranges)) (car ranges)
              (let* ((lengths (map range-length ranges))
                     (total (apply + lengths))
                     (offsets (let loop ((ls lengths) (acc 0) (result '()))
                               (if (null? ls) (reverse result)
                                   (loop (cdr ls) (+ acc (car ls))
                                         (cons acc result))))))
                (%make-range total
                  (lambda (i)
                    (let find ((rs ranges) (os offsets))
                      (if (null? (cdr rs))
                          (range-ref (car rs) (- i (car os)))
                          (if (< i (+ (car os) (range-length (car rs))))
                              (range-ref (car rs) (- i (car os)))
                              (find (cdr rs) (cdr os)))))))))))

    (define (range-reverse r)
      (let ((len (range-length r)))
        (%make-range len (lambda (i) (range-ref r (- len 1 i))))))

    ;;; Predicates

    (define (range=? equal . ranges)
      (or (null? ranges)
          (null? (cdr ranges))
          (let check ((rs ranges))
            (or (null? (cdr rs))
                (let ((r1 (car rs)) (r2 (cadr rs)))
                  (and (= (range-length r1) (range-length r2))
                       (let loop ((i 0))
                         (or (= i (range-length r1))
                             (and (equal (range-ref r1 i) (range-ref r2 i))
                                  (loop (+ i 1)))))
                       (check (cdr rs))))))))

    ;;; Accessors

    (define (range-length r) (%range-length r))

    (define (range-ref r i) ((%range-indexer r) i))

    (define (range-first r) (range-ref r 0))

    (define (range-last r) (range-ref r (- (range-length r) 1)))

    ;;; Iteration / slicing

    (define (range-split-at r idx)
      (values (subrange r 0 idx) (subrange r idx (range-length r))))

    (define (subrange r start end)
      (%make-range (- end start) (lambda (i) (range-ref r (+ start i)))))

    (define (range-segment r len)
      (let ((total (range-length r)))
        (let loop ((i 0) (result '()))
          (if (>= i total) (reverse result)
              (let ((end (min (+ i len) total)))
                (loop end (cons (subrange r i end) result)))))))

    (define (range-take r count) (subrange r 0 count))
    (define (range-take-right r count) (subrange r (- (range-length r) count) (range-length r)))
    (define (range-drop r count) (subrange r count (range-length r)))
    (define (range-drop-right r count) (subrange r 0 (- (range-length r) count)))

    ;;; Counting, any, every

    (define (range-count pred . ranges)
      (let ((len (apply min (map range-length ranges))))
        (let loop ((i 0) (n 0))
          (if (= i len) n
              (loop (+ i 1)
                    (if (apply pred (map (lambda (r) (range-ref r i)) ranges))
                        (+ n 1) n))))))

    (define (range-any pred . ranges)
      (let ((len (apply min (map range-length ranges))))
        (let loop ((i 0))
          (if (= i len) #f
              (let ((result (apply pred (map (lambda (r) (range-ref r i)) ranges))))
                (if result result (loop (+ i 1))))))))

    (define (range-every pred . ranges)
      (let ((len (apply min (map range-length ranges))))
        (let loop ((i 0) (last #t))
          (if (= i len) last
              (let ((result (apply pred (map (lambda (r) (range-ref r i)) ranges))))
                (if result (loop (+ i 1) result) #f))))))

    ;;; Mapping

    (define (range-map proc . ranges)
      (let* ((len (apply min (map range-length ranges)))
             (vec (make-vector len)))
        (let loop ((i 0))
          (if (= i len) (vector-range vec)
              (begin
                (vector-set! vec i (apply proc (map (lambda (r) (range-ref r i)) ranges)))
                (loop (+ i 1)))))))

    (define (range-map->list proc . ranges)
      (let ((len (apply min (map range-length ranges))))
        (let loop ((i (- len 1)) (result '()))
          (if (< i 0) result
              (loop (- i 1)
                    (cons (apply proc (map (lambda (r) (range-ref r i)) ranges))
                          result))))))

    (define (range-map->vector proc . ranges)
      (let* ((len (apply min (map range-length ranges)))
             (vec (make-vector len)))
        (let loop ((i 0))
          (if (= i len) vec
              (begin
                (vector-set! vec i (apply proc (map (lambda (r) (range-ref r i)) ranges)))
                (loop (+ i 1)))))))

    (define (range-for-each proc . ranges)
      (let ((len (apply min (map range-length ranges))))
        (let loop ((i 0))
          (when (< i len)
            (apply proc (map (lambda (r) (range-ref r i)) ranges))
            (loop (+ i 1))))))

    (define (range-filter-map proc . ranges)
      (let* ((len (apply min (map range-length ranges)))
             (results '()))
        (let loop ((i 0) (acc '()))
          (if (= i len)
              (let ((vec (list->vector (reverse acc))))
                (vector-range vec))
              (let ((val (apply proc (map (lambda (r) (range-ref r i)) ranges))))
                (if val (loop (+ i 1) (cons val acc))
                    (loop (+ i 1) acc)))))))

    (define (range-filter-map->list proc . ranges)
      (let ((len (apply min (map range-length ranges))))
        (let loop ((i (- len 1)) (result '()))
          (if (< i 0) result
              (let ((val (apply proc (map (lambda (r) (range-ref r i)) ranges))))
                (if val (loop (- i 1) (cons val result))
                    (loop (- i 1) result)))))))

    (define (range-filter pred r)
      (let ((vec (list->vector (range-filter->list pred r))))
        (vector-range vec)))

    (define (range-filter->list pred r)
      (let ((len (range-length r)))
        (let loop ((i (- len 1)) (result '()))
          (if (< i 0) result
              (let ((val (range-ref r i)))
                (if (pred val) (loop (- i 1) (cons val result))
                    (loop (- i 1) result)))))))

    (define (range-remove pred r)
      (range-filter (lambda (x) (not (pred x))) r))

    (define (range-remove->list pred r)
      (range-filter->list (lambda (x) (not (pred x))) r))

    ;;; Folding

    (define (range-fold kons nil . ranges)
      (let ((len (apply min (map range-length ranges))))
        (let loop ((i 0) (acc nil))
          (if (= i len) acc
              (loop (+ i 1)
                    (apply kons (append (map (lambda (r) (range-ref r i)) ranges)
                                        (list acc))))))))

    (define (range-fold-right kons nil . ranges)
      (let ((len (apply min (map range-length ranges))))
        (let loop ((i (- len 1)) (acc nil))
          (if (< i 0) acc
              (loop (- i 1)
                    (apply kons (append (map (lambda (r) (range-ref r i)) ranges)
                                        (list acc))))))))

    ;;; Searching

    (define (range-index pred . ranges)
      (let ((len (apply min (map range-length ranges))))
        (let loop ((i 0))
          (cond
            ((= i len) #f)
            ((apply pred (map (lambda (r) (range-ref r i)) ranges)) i)
            (else (loop (+ i 1)))))))

    (define (range-index-right pred . ranges)
      (let ((len (apply min (map range-length ranges))))
        (let loop ((i (- len 1)))
          (cond
            ((< i 0) #f)
            ((apply pred (map (lambda (r) (range-ref r i)) ranges)) i)
            (else (loop (- i 1)))))))

    (define (range-take-while pred r)
      (let ((idx (range-index (lambda (x) (not (pred x))) r)))
        (if idx (range-take r idx) r)))

    (define (range-take-while-right pred r)
      (let ((idx (range-index-right (lambda (x) (not (pred x))) r)))
        (if idx (range-drop r (+ idx 1)) r)))

    (define (range-drop-while pred r)
      (let ((idx (range-index (lambda (x) (not (pred x))) r)))
        (if idx (range-drop r idx) (%make-range 0 (lambda (i) #f)))))

    (define (range-drop-while-right pred r)
      (let ((idx (range-index-right (lambda (x) (not (pred x))) r)))
        (if idx (range-take r (+ idx 1)) (%make-range 0 (lambda (i) #f)))))

    ;;; Conversion

    (define (range->list r)
      (let ((len (range-length r)))
        (let loop ((i (- len 1)) (result '()))
          (if (< i 0) result
              (loop (- i 1) (cons (range-ref r i) result))))))

    (define (range->vector r)
      (let* ((len (range-length r))
             (vec (make-vector len)))
        (let loop ((i 0))
          (if (= i len) vec
              (begin (vector-set! vec i (range-ref r i)) (loop (+ i 1)))))))

    (define (range->string r)
      (let ((len (range-length r)))
        (let ((s (make-string len)))
          (let loop ((i 0))
            (if (= i len) s
                (begin (string-set! s i (range-ref r i)) (loop (+ i 1))))))))

    (define (range->generator r)
      (let ((i 0) (len (range-length r)))
        (lambda ()
          (if (>= i len) (eof-object)
              (let ((val (range-ref r i)))
                (set! i (+ i 1))
                val)))))

    ))
