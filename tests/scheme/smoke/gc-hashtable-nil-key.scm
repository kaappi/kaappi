;; Regression test for #298/#277: GC hash table marking used types.NIL
;; instead of types.EOF as tombstone sentinel, causing entries with '()
;; as key to be skipped during minor GC marking.

(import (srfi 69))

(define ht (make-hash-table))
(hash-table-set! ht '() "value-for-nil-key")
(hash-table-set! ht 'a "aaa")
(hash-table-set! ht 'b "bbb")

;; Force some GC pressure
(let loop ((i 0))
  (when (< i 5000)
    (make-vector 100 i)
    (loop (+ i 1))))

;; The value stored under '() key must survive GC
(display (hash-table-ref ht '()))
(newline)
(display (hash-table-ref ht 'a))
(newline)
(display (hash-table-ref ht 'b))
(newline)
