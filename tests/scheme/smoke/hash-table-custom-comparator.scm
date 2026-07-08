;; Regression test for #1183: make-hash-table/alist->hash-table must honor
;; custom equivalence and hash functions; accessors must report them.
(import (scheme base) (scheme write) (scheme char) (scheme process-context) (srfi 64) (srfi 69))

(test-begin "hash-table-custom-comparator")

;;; --- eq? mode ---
;; Two (string #\a) calls produce distinct objects — eq? table keeps both.
(let ((ht (make-hash-table eq?)))
  (hash-table-set! ht (string #\a) 'first)
  (hash-table-set! ht (string #\a) 'second)
  (test-equal "eq? table: distinct string objects → size 2" 2 (hash-table-size ht)))

;; Same symbol is eq? — overwrites.
(let ((ht (make-hash-table eq?)))
  (hash-table-set! ht 'x 1)
  (hash-table-set! ht 'x 2)
  (test-equal "eq? table: same symbol → size 1" 1 (hash-table-size ht))
  (test-equal "eq? table: overwritten value" 2 (hash-table-ref ht 'x)))

;; eq? accessor
(test-assert "eq? accessor returns eq?"
  (eq? eq? (hash-table-equivalence-function (make-hash-table eq?))))
(test-assert "eq? hash accessor returns hash-by-identity"
  (eq? hash-by-identity (hash-table-hash-function (make-hash-table eq?))))

;;; --- equal? mode (default) ---
;; Two (string #\a) calls produce equal? strings — default table coalesces.
(let ((ht (make-hash-table)))
  (hash-table-set! ht (string #\a) 'first)
  (hash-table-set! ht (string #\a) 'second)
  (test-equal "equal? table: equal strings → size 1" 1 (hash-table-size ht)))

(test-assert "default accessor returns equal?"
  (eq? equal? (hash-table-equivalence-function (make-hash-table))))
(test-assert "default hash accessor returns hash"
  (eq? hash (hash-table-hash-function (make-hash-table))))

;;; --- string-ci=? mode ---
(let ((ht (make-hash-table string-ci=? string-ci-hash)))
  (hash-table-set! ht "ABC" 1)
  (hash-table-set! ht "abc" 2)
  (test-equal "string-ci table: ABC and abc → size 1" 1 (hash-table-size ht))
  (test-equal "string-ci table: value overwritten" 2 (hash-table-ref ht "Abc")))

(test-assert "string-ci=? accessor"
  (eq? string-ci=? (hash-table-equivalence-function
                     (make-hash-table string-ci=? string-ci-hash))))

;;; --- string=? mode ---
(let ((ht (make-hash-table string=? string-hash)))
  (hash-table-set! ht "ABC" 1)
  (hash-table-set! ht "abc" 2)
  (test-equal "string=? table: ABC and abc → size 2" 2 (hash-table-size ht))
  (hash-table-set! ht "abc" 3)
  (test-equal "string=? table: duplicate abc → still size 2" 2 (hash-table-size ht)))

;;; --- eqv? mode ---
(let ((ht (make-hash-table eqv?)))
  (hash-table-set! ht 42 'a)
  (hash-table-set! ht 42 'b)
  (test-equal "eqv? table: same fixnum → size 1" 1 (hash-table-size ht))
  (hash-table-set! ht 43 'c)
  (test-equal "eqv? table: different fixnum → size 2" 2 (hash-table-size ht)))

;;; --- alist->hash-table with custom comparator ---
(let ((ht (alist->hash-table
            (list (cons (string #\a) 1) (cons (string #\a) 2))
            eq?)))
  (test-equal "alist->hash-table with eq?: distinct keys → size 2"
    2 (hash-table-size ht)))

(let ((ht (alist->hash-table
            (list (cons "ABC" 1) (cons "abc" 2))
            string-ci=? string-ci-hash)))
  (test-equal "alist->hash-table with string-ci=?: ABC and abc → size 1"
    1 (hash-table-size ht)))

;;; --- hash-table-copy preserves mode ---
(let* ((ht (make-hash-table eq?))
       (copy (begin (hash-table-set! ht 'x 1) (hash-table-copy ht))))
  (hash-table-set! copy (string #\a) 'v1)
  (hash-table-set! copy (string #\a) 'v2)
  (test-equal "copy preserves eq? mode" 3
    ;; x plus two distinct string objects = 3
    (hash-table-size copy))
  (test-assert "copy accessor returns eq?"
    (eq? eq? (hash-table-equivalence-function copy))))

;;; --- operations on eq? tables ---
(let ((ht (make-hash-table eq?)))
  (hash-table-set! ht 'a 1)
  (hash-table-set! ht 'b 2)
  (test-assert "eq? exists?" (hash-table-exists? ht 'a))
  (test-equal "eq? ref" 1 (hash-table-ref ht 'a))
  (hash-table-delete! ht 'a)
  (test-equal "eq? delete → size 1" 1 (hash-table-size ht))
  (test-assert "eq? not exists after delete" (not (hash-table-exists? ht 'a))))

;;; --- hash-table-update! on eq? table ---
(let ((ht (make-hash-table eq?)))
  (hash-table-set! ht 'counter 0)
  (hash-table-update! ht 'counter (lambda (v) (+ v 1)))
  (test-equal "update! on eq? table" 1 (hash-table-ref ht 'counter)))

;;; --- custom Scheme comparator ---
(let ((ht (make-hash-table
            (lambda (a b) (= (modulo a 3) (modulo b 3)))
            (lambda (k) (modulo k 3)))))
  (hash-table-set! ht 1 'a)
  (hash-table-set! ht 4 'b)  ; 4 mod 3 = 1, same as 1
  (test-equal "custom comparator: 1 and 4 equivalent → size 1"
    1 (hash-table-size ht))
  (test-equal "custom comparator: overwritten value" 'b (hash-table-ref ht 7)))

(let ((runner (test-runner-current)))
  (test-end "hash-table-custom-comparator")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
