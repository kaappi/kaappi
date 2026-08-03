;; Regression test for #298/#277: GC hash table marking used types.NIL
;; instead of types.EOF as tombstone sentinel, causing entries with '()
;; as key to be skipped during minor GC marking.

(import (scheme base) (scheme process-context) (srfi 64) (srfi 69))

(test-begin "gc-hashtable-nil-key")

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
(test-equal "'() key survives collection" "value-for-nil-key" (hash-table-ref ht '()))
(test-equal "symbol key a survives collection" "aaa" (hash-table-ref ht 'a))
(test-equal "symbol key b survives collection" "bbb" (hash-table-ref ht 'b))

(let ((runner (test-runner-current)))
  (test-end "gc-hashtable-nil-key")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
