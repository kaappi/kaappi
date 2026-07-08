;; Regression test for #1182: hash-table-update! missing from (srfi 69)
(import (scheme base) (scheme write) (scheme process-context) (srfi 64) (srfi 69))

(test-begin "hash-table-update!-1182")

;; Key exists — update it
(test-equal "update existing key"
  11
  (let ((ht (make-hash-table)))
    (hash-table-set! ht 'k 10)
    (hash-table-update! ht 'k (lambda (x) (+ x 1)))
    (hash-table-ref ht 'k)))

;; Key absent with thunk — insert via thunk
(test-equal "absent key with thunk"
  1
  (let ((ht (make-hash-table)))
    (hash-table-update! ht 'k (lambda (x) (+ x 1)) (lambda () 0))
    (hash-table-ref ht 'k)))

;; Key absent without thunk — error
(test-assert "absent key without thunk raises error"
  (guard (e (#t #t))
    (let ((ht (make-hash-table)))
      (hash-table-update! ht 'k (lambda (x) x))
      #f)))

(let ((runner (test-runner-current)))
  (test-end "hash-table-update!-1182")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
