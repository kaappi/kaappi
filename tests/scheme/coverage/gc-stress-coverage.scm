(import (scheme base) (scheme write) (scheme complex) (scheme inexact)
        (srfi 69) (kaappi fibers))

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

;;; Force GC while error objects are live
(let ((errors (list)))
  (let loop ((i 0))
    (when (< i 100)
      (set! errors (cons (guard (e (#t e)) (error "msg" i (make-list 10 i))) errors))
      (make-list 100 i)
      (loop (+ i 1))))
  (check "gc error objects" (length errors) 100)
  (check-true "gc error msg" (error-object? (car errors))))

;;; Force GC while multiple values are live
(let ((vals (list)))
  (let loop ((i 0))
    (when (< i 100)
      (call-with-values (lambda () (values i (* i 2) (* i 3)))
        (lambda (a b c) (set! vals (cons (list a b c) vals))))
      (make-list 100 i)
      (loop (+ i 1))))
  (check "gc multiple values" (length vals) 100))

;;; Force GC while hash tables are live
(let ((tables (list)))
  (let loop ((i 0))
    (when (< i 50)
      (let ((ht (make-hash-table)))
        (hash-table-set! ht 'key (make-list 20 i))
        (hash-table-set! ht 'val (make-string 50 #\x))
        (set! tables (cons ht tables)))
      (make-list 200 i)
      (loop (+ i 1))))
  (check "gc hash tables" (length tables) 50)
  (check "gc ht value" (hash-table-ref (car tables) 'key) (make-list 20 49)))

;;; Force GC while channels are live
(let ((channels (list)))
  (let loop ((i 0))
    (when (< i 50)
      (set! channels (cons (make-channel) channels))
      (make-list 200 i)
      (loop (+ i 1))))
  (check "gc channels" (length channels) 50)
  (check-true "gc channel?" (channel? (car channels))))

;;; Force GC while rationals are live
(let ((rats (list)))
  (let loop ((i 1))
    (when (< i 100)
      (set! rats (cons (/ 1 i) rats))
      (make-list 100 i)
      (loop (+ i 1))))
  (check "gc rationals" (length rats) 99))

;;; Force GC while complex numbers are live
(let ((cxs (list)))
  (let loop ((i 0))
    (when (< i 100)
      (set! cxs (cons (make-rectangular (inexact i) (inexact (* i 2))) cxs))
      (make-list 100 i)
      (loop (+ i 1))))
  (check "gc complex" (length cxs) 100))

;;; Force GC while promises are live
(let ((promises (list)))
  (let loop ((i 0))
    (when (< i 100)
      (set! promises (cons (delay (* i i)) promises))
      (make-list 100 i)
      (loop (+ i 1))))
  (check "gc promises" (length promises) 100)
  (check-true "gc force promise" (number? (force (car promises)))))

;;; Force GC while parameters are live
(let ((params (list)))
  (let loop ((i 0))
    (when (< i 50)
      (set! params (cons (make-parameter (make-list 10 i)) params))
      (make-list 200 i)
      (loop (+ i 1))))
  (check "gc parameters" (length params) 50))

;;; Force GC while vectors are live
(let ((vecs (list)))
  (let loop ((i 0))
    (when (< i 100)
      (set! vecs (cons (vector i (* i 2) (* i 3) (make-list 10 i)) vecs))
      (make-list 100 i)
      (loop (+ i 1))))
  (check "gc vectors" (length vecs) 100))

;;; Force GC while records are live
(define-record-type <box>
  (make-box val extra)
  box?
  (val box-val)
  (extra box-extra))
(let ((boxes (list)))
  (let loop ((i 0))
    (when (< i 100)
      (set! boxes (cons (make-box (make-list 10 i) (make-string 20 #\y)) boxes))
      (make-list 100 i)
      (loop (+ i 1))))
  (check "gc records" (length boxes) 100)
  (check-true "gc record val" (list? (box-val (car boxes)))))

;;; Force GC with unicode symbols (reader unicode paths)
(let ((syms (list)))
  (let loop ((i 0))
    (when (< i 50)
      (set! syms (cons (string->symbol (string (integer->char (+ #x400 i)))) syms))
      (make-list 200 i)
      (loop (+ i 1))))
  (check "gc unicode symbols" (length syms) 50))

;;; Exercise various unicode identifier scripts in reader
(check-true "cyrillic id" (symbol? (read (open-input-string "Ф"))))
(check-true "hebrew id" (symbol? (read (open-input-string "א"))))
(check-true "arabic id" (symbol? (read (open-input-string "ع"))))
(check-true "devanagari id" (symbol? (read (open-input-string "क"))))
(check-true "thai id" (symbol? (read (open-input-string "ก"))))
(check-true "georgian id" (symbol? (read (open-input-string "Ⴀ"))))
(check-true "hangul id" (symbol? (read (open-input-string "가"))))
(check-true "cjk id" (symbol? (read (open-input-string "中"))))
(check-true "hiragana id" (symbol? (read (open-input-string "あ"))))
(check-true "katakana id" (symbol? (read (open-input-string "ア"))))
(check-true "latin-ext id" (symbol? (read (open-input-string "ñ"))))

;;; Unicode subsequent characters
(check-true "cyrillic subsequent" (symbol? (read (open-input-string "xФ"))))
(check-true "cjk subsequent" (symbol? (read (open-input-string "x中"))))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "GC stress coverage tests failed" fail))
