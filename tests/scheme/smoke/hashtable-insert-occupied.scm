;; Regression test: hash-table-update!/default and alist->hash-table wrote
;; new entries without setting the entry state to occupied, so inserted keys
;; were invisible to lookup (hash-table-ref raised "expected key to be
;; present or default") and were dropped on the next rehash.
;;
;; Manual counters + guard instead of SRFI-64: a raised error must count as
;; a failure rather than abort the enclosing form, and failure must reach
;; the explicit (exit 1) that run-all.sh keys on.
(import (scheme base) (scheme write) (scheme process-context) (srfi 69))

(define pass 0)
(define fail 0)
(define (check name thunk expected)
  (let ((got (guard (e (#t 'check-raised-error)) (thunk))))
    (if (equal? got expected)
        (set! pass (+ pass 1))
        (begin
          (set! fail (+ fail 1))
          (display "FAIL: ") (display name)
          (display " expected ") (write expected)
          (display " got ") (write got) (newline)))))

;; hash-table-update!/default inserting a missing key
(define ht (make-hash-table))
(hash-table-update!/default ht 'counter (lambda (x) (+ x 1)) 0)
(check "update!/default inserts missing key"
       (lambda () (hash-table-ref ht 'counter)) 1)
(check "inserted key exists"
       (lambda () (hash-table-exists? ht 'counter)) #t)
(check "size counts inserted key"
       (lambda () (hash-table-size ht)) 1)
(check "keys include inserted key"
       (lambda () (hash-table-keys ht)) '(counter))

;; updating the freshly inserted key must hit the same entry
(hash-table-update!/default ht 'counter (lambda (x) (+ x 1)) 0)
(check "second update sees first"
       (lambda () (hash-table-ref ht 'counter)) 2)
(check "no duplicate entry"
       (lambda () (hash-table-size ht)) 1)

;; inserted entry must survive a rehash (growth used to drop phantom entries)
(define ht2 (make-hash-table))
(hash-table-update!/default ht2 'seed (lambda (x) x) 42)
(do ((i 0 (+ i 1)))
    ((= i 20))
  (hash-table-set! ht2 i i))
(check "inserted key survives rehash"
       (lambda () (hash-table-ref ht2 'seed)) 42)
(check "size after rehash"
       (lambda () (hash-table-size ht2)) 21)

;; alist->hash-table entries must be visible to lookup
(define ht3 (alist->hash-table '((a . 1) (b . 2) (a . 99))))
(check "alist key a" (lambda () (hash-table-ref ht3 'a)) 1)
(check "alist key b" (lambda () (hash-table-ref ht3 'b)) 2)
(check "alist size" (lambda () (hash-table-size ht3)) 2)

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(when (> fail 0) (exit 1))
