;; Regression test for #1181: hash-table-walk/fold snapshot must root
;; keys/values so GC doesn't free them when the callback deletes entries
;; and allocates.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64) (srfi 69))

(test-begin "hash-table-walk-gc-1181")

;; walk: callback deletes entries then allocates heavily
(test-equal "walk snapshot survives GC"
  '(435 0)
  (let ((ht (make-hash-table)) (sum 0) (bad 0))
    (do ((i 0 (+ i 1))) ((= i 30))
      (hash-table-set! ht (cons i 'key) (cons i 'val)))
    (hash-table-walk ht
      (lambda (k v)
        (do ((j 0 (+ j 1))) ((= j 30))
          (hash-table-delete! ht (cons j 'key)))
        (do ((j 0 (+ j 1))) ((= j 100))
          (cons j (make-vector 4 j)))
        (if (and (pair? k) (pair? v) (eq? (cdr k) 'key) (eq? (cdr v) 'val)
                 (= (car k) (car v)))
            (set! sum (+ sum (car k)))
            (set! bad (+ bad 1)))))
    (list sum bad)))

;; fold: same pattern with accumulator
(test-equal "fold snapshot survives GC"
  435
  (let ((ht (make-hash-table)))
    (do ((i 0 (+ i 1))) ((= i 30))
      (hash-table-set! ht (cons i 'key) (cons i 'val)))
    (hash-table-fold ht
      (lambda (k v acc)
        (do ((j 0 (+ j 1))) ((= j 30))
          (hash-table-delete! ht (cons j 'key)))
        (do ((j 0 (+ j 1))) ((= j 100))
          (cons j (make-vector 4 j)))
        (if (and (pair? k) (pair? v) (eq? (cdr k) 'key) (eq? (cdr v) 'val)
                 (= (car k) (car v)))
            (+ acc (car k))
            acc))
      0)))

(let ((runner (test-runner-current)))
  (test-end "hash-table-walk-gc-1181")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
