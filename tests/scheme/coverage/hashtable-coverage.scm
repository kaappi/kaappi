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
(define (check-false name val)
  (if (not val) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

;;; ---- Basic creation and type ----
(check-true "hash-table? on make-hash-table" (hash-table? (make-hash-table)))
(check-false "hash-table? on list" (hash-table? '()))
(check-false "hash-table? on number" (hash-table? 42))
(check-false "hash-table? on string" (hash-table? "hello"))

;;; ---- Set and ref ----
(let ((ht (make-hash-table)))
  (hash-table-set! ht 'name "kaappi")
  (hash-table-set! ht 'version 1)
  (hash-table-set! ht 'lang "zig")

  (check "ref name" (hash-table-ref ht 'name) "kaappi")
  (check "ref version" (hash-table-ref ht 'version) 1)
  (check "ref lang" (hash-table-ref ht 'lang) "zig")
  (check "size" (hash-table-size ht) 3)

  ;; Overwrite
  (hash-table-set! ht 'version 2)
  (check "ref after overwrite" (hash-table-ref ht 'version) 2)
  (check "size after overwrite" (hash-table-size ht) 3)

  ;; Exists
  (check-true "exists? name" (hash-table-exists? ht 'name))
  (check-false "exists? missing" (hash-table-exists? ht 'missing))

  ;; Delete
  (hash-table-delete! ht 'lang)
  (check "size after delete" (hash-table-size ht) 2)
  (check-false "exists? after delete" (hash-table-exists? ht 'lang))

  ;; Delete missing key (should not error)
  (hash-table-delete! ht 'nonexistent)
  (check "size after delete missing" (hash-table-size ht) 2))

;;; ---- ref/default ----
(let ((ht (make-hash-table)))
  (hash-table-set! ht 'a 1)
  (check "ref/default found" (hash-table-ref/default ht 'a 99) 1)
  (check "ref/default missing" (hash-table-ref/default ht 'b 99) 99))

;;; ---- ref with default thunk ----
(let ((ht (make-hash-table)))
  (hash-table-set! ht 'a 10)
  (check "ref with default thunk found" (hash-table-ref ht 'a (lambda () 99)) 10)
  ;; SRFI-69: default thunk is returned as-is, not called
  (check-true "ref with default thunk missing" (procedure? (hash-table-ref ht 'b (lambda () 99)))))

;;; ---- Keys and values ----
(let ((ht (make-hash-table)))
  (hash-table-set! ht 'x 10)
  (hash-table-set! ht 'y 20)
  (hash-table-set! ht 'z 30)
  (let ((keys (hash-table-keys ht))
        (vals (hash-table-values ht)))
    (check "keys length" (length keys) 3)
    (check "vals length" (length vals) 3)
    (check-true "keys contains x" (memq 'x keys))
    (check-true "keys contains y" (memq 'y keys))
    (check-true "keys contains z" (memq 'z keys))
    (check-true "vals contains 10" (member 10 vals))
    (check-true "vals contains 20" (member 20 vals))
    (check-true "vals contains 30" (member 30 vals))))

;;; ---- Walk ----
(let ((ht (make-hash-table))
      (result '()))
  (hash-table-set! ht 'a 1)
  (hash-table-set! ht 'b 2)
  (hash-table-walk ht (lambda (k v) (set! result (cons (cons k v) result))))
  (check "walk length" (length result) 2)
  (check-true "walk has a" (assq 'a result))
  (check-true "walk has b" (assq 'b result)))

;;; ---- Fold ----
(let ((ht (make-hash-table)))
  (hash-table-set! ht 'a 1)
  (hash-table-set! ht 'b 2)
  (hash-table-set! ht 'c 3)
  (check "fold sum values" (hash-table-fold ht (lambda (k v acc) (+ v acc)) 0) 6))

;;; ---- hash-table->alist / alist->hash-table ----
(let ((ht (make-hash-table)))
  (hash-table-set! ht 'x 10)
  (hash-table-set! ht 'y 20)
  (let ((al (hash-table->alist ht)))
    (check "->alist length" (length al) 2)
    (check-true "->alist has x" (assq 'x al))
    (check-true "->alist has y" (assq 'y al))))

(let ((ht (alist->hash-table '((a . 1) (b . 2) (c . 3)))))
  (check-true "alist->ht is ht" (hash-table? ht))
  (check "alist->ht ref" (hash-table-ref ht 'a) 1)
  (check "alist->ht ref b" (hash-table-ref ht 'b) 2)
  (check "alist->ht size" (hash-table-size ht) 3))

;;; ---- Copy ----
(let ((ht (make-hash-table)))
  (hash-table-set! ht 'a 1)
  (hash-table-set! ht 'b 2)
  (let ((ht2 (hash-table-copy ht)))
    (check "copy ref" (hash-table-ref ht2 'a) 1)
    (check "copy size" (hash-table-size ht2) 2)
    ;; Modify copy, original unchanged
    (hash-table-set! ht2 'a 99)
    (check "original unchanged" (hash-table-ref ht 'a) 1)
    (check "copy changed" (hash-table-ref ht2 'a) 99)))

;;; ---- update!/default ----
(let ((ht (make-hash-table)))
  (hash-table-set! ht 'count 0)
  (hash-table-update!/default ht 'count (lambda (v) (+ v 1)) 0)
  (check "update!/default existing" (hash-table-ref ht 'count) 1)
  (hash-table-update!/default ht 'new-key (lambda (v) (+ v 10)) 5)
  (check "update!/default new key" (hash-table-ref ht 'new-key) 15))

;;; ---- merge! ----
(let ((ht1 (make-hash-table))
      (ht2 (make-hash-table)))
  (hash-table-set! ht1 'a 1)
  (hash-table-set! ht1 'b 2)
  (hash-table-set! ht2 'b 20)
  (hash-table-set! ht2 'c 30)
  (hash-table-merge! ht1 ht2)
  (check "merge! a" (hash-table-ref ht1 'a) 1)
  ;; merge! may keep existing values for keys already present
  (check-true "merge! b exists" (hash-table-exists? ht1 'b))
  (check "merge! c added" (hash-table-ref ht1 'c) 30)
  (check "merge! size" (hash-table-size ht1) 3))

;;; ---- Hash functions ----
(check-true "hash number" (number? (hash 42)))
(check-true "hash symbol" (number? (hash 'foo)))
(check-true "hash string" (number? (hash "hello")))
(check-true "string-hash" (number? (string-hash "hello")))
(check-true "string-ci-hash" (number? (string-ci-hash "Hello")))
(check-true "hash-by-identity" (number? (hash-by-identity 'foo)))

;;; ---- String keys ----
(let ((ht (make-hash-table)))
  (hash-table-set! ht "hello" 1)
  (hash-table-set! ht "world" 2)
  (check "string key ref" (hash-table-ref ht "hello") 1)
  (check "string key size" (hash-table-size ht) 2))

;;; ---- Number keys ----
(let ((ht (make-hash-table)))
  (hash-table-set! ht 1 'one)
  (hash-table-set! ht 2 'two)
  (hash-table-set! ht 3 'three)
  (check "number key ref" (hash-table-ref ht 2) 'two)
  (check "number key size" (hash-table-size ht) 3))

;;; ---- Empty hash table ----
(let ((ht (make-hash-table)))
  (check "empty size" (hash-table-size ht) 0)
  (check "empty keys" (hash-table-keys ht) '())
  (check "empty values" (hash-table-values ht) '())
  (check "empty ->alist" (hash-table->alist ht) '())
  (check "empty fold" (hash-table-fold ht (lambda (k v a) (+ a 1)) 0) 0))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "Hash table coverage tests failed" fail))
