;; Regression test for #690: hash-table-walk/fold must not use-after-free
;; when the callback triggers a rehash on the same table.

;; --- hash-table-walk with rehash ---
(define ht (make-hash-table))
(let loop ((i 0))
  (when (< i 6)
    (hash-table-set! ht i i)
    (loop (+ i 1))))

(define walk-count 0)
(hash-table-walk ht
  (lambda (k v)
    (set! walk-count (+ walk-count 1))
    (hash-table-set! ht (+ 1000 k) 'new)))

;; Should visit exactly 6 original entries (not stale/garbage entries)
(unless (= walk-count 6)
  (display "FAIL: hash-table-walk visited ")
  (display walk-count)
  (display " entries, expected 6")
  (newline)
  (exit 1))

;; --- hash-table-fold with rehash ---
(define ht2 (make-hash-table))
(let loop ((i 0))
  (when (< i 6)
    (hash-table-set! ht2 i i)
    (loop (+ i 1))))

(define result
  (hash-table-fold ht2
    (lambda (k v acc)
      (hash-table-set! ht2 (+ 2000 k) 'grown)
      (cons (cons k v) acc))
    '()))

;; Should have exactly 6 pairs, all with valid fixnum keys 0-5
(unless (= (length result) 6)
  (display "FAIL: hash-table-fold returned ")
  (display (length result))
  (display " pairs, expected 6")
  (newline)
  (exit 1))

(for-each
  (lambda (pair)
    (unless (and (number? (car pair)) (number? (cdr pair)))
      (display "FAIL: corrupted pair in fold result: ")
      (display pair)
      (newline)
      (exit 1)))
  result)

(display "PASS")
(newline)
