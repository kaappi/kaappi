(import (scheme base) (scheme write) (srfi 69))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))
(define (check-true name val)
  (if val (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

;;; hash functions
(check-true "hash positive" (> (hash 42) 0))
(check-true "hash string" (> (string-hash "hello") 0))
(check "hash bound" (< (hash 42 100) 100) #t)
(check "string-hash bound" (< (string-hash "hello" 100) 100) #t)
(check-true "string-ci-hash" (= (string-ci-hash "Hello") (string-ci-hash "hello")))
(check-true "hash-by-identity" (integer? (hash-by-identity 'foo)))

;;; hash-table-ref/default
(let ((ht (make-hash-table)))
  (hash-table-set! ht 'a 1)
  (check "ref/default found" (hash-table-ref/default ht 'a 0) 1)
  (check "ref/default miss" (hash-table-ref/default ht 'z 99) 99))

;;; hash-table-fold
(let ((ht (make-hash-table)))
  (hash-table-set! ht 'a 1)
  (hash-table-set! ht 'b 2)
  (hash-table-set! ht 'c 3)
  (check "fold sum" (hash-table-fold ht (lambda (k v acc) (+ acc v)) 0) 6)
  (check "fold keys" (length (hash-table-fold ht (lambda (k v acc) (cons k acc)) '())) 3))

;;; hash-table-merge!
(let ((ht1 (make-hash-table))
      (ht2 (make-hash-table)))
  (hash-table-set! ht1 'a 1)
  (hash-table-set! ht1 'b 2)
  (hash-table-set! ht2 'b 20)
  (hash-table-set! ht2 'c 30)
  (hash-table-merge! ht1 ht2)
  (check "merge keeps existing" (hash-table-ref ht1 'b) 2)
  (check "merge adds new" (hash-table-ref ht1 'c) 30)
  (check "merge size" (hash-table-size ht1) 3))

;;; hash-table-update!/default
(let ((ht (make-hash-table)))
  (hash-table-set! ht 'count 0)
  (hash-table-update!/default ht 'count (lambda (v) (+ v 1)) 0)
  (check "update existing" (hash-table-ref ht 'count) 1)
  (hash-table-update!/default ht 'new (lambda (v) (+ v 10)) 5)
  (check "update default" (hash-table-ref ht 'new) 15))

;;; hash-table-copy
(let ((ht (make-hash-table)))
  (hash-table-set! ht 'x 42)
  (let ((ht2 (hash-table-copy ht)))
    (check "copy has value" (hash-table-ref ht2 'x) 42)
    (hash-table-set! ht2 'x 99)
    (check "copy independent" (hash-table-ref ht 'x) 42)))

;;; hash-table-keys / values / walk
(let ((ht (make-hash-table)))
  (hash-table-set! ht 1 'a)
  (hash-table-set! ht 2 'b)
  (check "keys len" (length (hash-table-keys ht)) 2)
  (check "values len" (length (hash-table-values ht)) 2)
  (let ((sum 0))
    (hash-table-walk ht (lambda (k v) (set! sum (+ sum k))))
    (check "walk sum keys" sum 3)))

;;; alist->hash-table / hash-table->alist
(let ((ht (alist->hash-table '((a . 1) (b . 2) (a . 99)))))
  (check "alist first wins" (hash-table-ref ht 'a) 1)
  (check "alist size" (hash-table-size ht) 2)
  (check "->alist length" (length (hash-table->alist ht)) 2))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI 69 extended tests failed" fail))
