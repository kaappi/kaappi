;; Regression test for #694: eof-object and void as hash-table keys
;; must work correctly instead of colliding with internal sentinels.

;; Test eof-object as key
(define ht (make-hash-table))
(hash-table-set! ht (eof-object) "eof-key-value")
(unless (= (hash-table-size ht) 1)
  (display "FAIL: size should be 1 after eof key insert, got ")
  (display (hash-table-size ht))
  (newline)
  (exit 1))

(define ref-result (hash-table-ref ht (eof-object) (lambda () 'MISSING)))
(unless (equal? ref-result "eof-key-value")
  (display "FAIL: eof key ref should be \"eof-key-value\", got ")
  (display ref-result)
  (newline)
  (exit 1))

(unless (hash-table-exists? ht (eof-object))
  (display "FAIL: eof key should exist")
  (newline)
  (exit 1))

;; Check it shows up in alist
(define alist (hash-table->alist ht))
(unless (= (length alist) 1)
  (display "FAIL: alist should have 1 entry, got ")
  (display (length alist))
  (newline)
  (exit 1))

;; Test void (unspecified) as key
(define ht2 (make-hash-table))
(define unspecified (if #f #f))
(hash-table-set! ht2 unspecified "void-key-value")
(unless (= (hash-table-size ht2) 1)
  (display "FAIL: size should be 1 after void key insert")
  (newline)
  (exit 1))

(define ref2 (hash-table-ref ht2 unspecified (lambda () 'MISSING)))
(unless (equal? ref2 "void-key-value")
  (display "FAIL: void key ref should be \"void-key-value\", got ")
  (display ref2)
  (newline)
  (exit 1))

;; Test delete of eof key
(hash-table-delete! ht (eof-object))
(unless (= (hash-table-size ht) 0)
  (display "FAIL: size should be 0 after eof key delete")
  (newline)
  (exit 1))
(when (hash-table-exists? ht (eof-object))
  (display "FAIL: eof key should not exist after delete")
  (newline)
  (exit 1))

(display "PASS")
(newline)
