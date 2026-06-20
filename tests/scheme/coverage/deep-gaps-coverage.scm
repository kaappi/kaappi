(import (scheme base) (scheme write) (scheme read) (scheme file)
        (scheme char) (scheme inexact) (scheme complex) (scheme lazy)
        (scheme case-lambda) (scheme cxr)
        (srfi 1) (srfi 13) (srfi 18) (srfi 27) (srfi 69) (srfi 170)
        (kaappi fibers))

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

;;; ================================================================
;;; primitives_io.zig — file I/O paths, binary ports, edge cases
;;; ================================================================

;;; ---- with-input-from-file / with-output-to-file ----
(define tf "/tmp/kaappi-dgap-test.txt")
(with-output-to-file tf (lambda () (display "output-to-file test")))
(check "with-input-from-file"
  (with-input-from-file tf read-line)
  "output-to-file test")

;;; ---- call-with-input-file / call-with-output-file ----
(define tf2 "/tmp/kaappi-dgap-test2.txt")
(call-with-output-file tf2
  (lambda (p) (write-char #\X p) (write-char #\Y p) (write-char #\Z p)))
(check "call-with-input-file"
  (call-with-input-file tf2
    (lambda (p) (string (read-char p) (read-char p) (read-char p))))
  "XYZ")

;;; ---- write-bytevector to file port ----
(define tf3 "/tmp/kaappi-dgap-test3.bin")
(call-with-output-file tf3
  (lambda (p) (write-bytevector #u8(65 66 67 68) p)))
(check "read-bytevector from file"
  (call-with-input-file tf3
    (lambda (p) (read-bytevector 4 p)))
  #u8(65 66 67 68))

;;; ---- write-string with subrange to file ----
(call-with-output-file tf
  (lambda (p) (write-string "abcdefgh" p 2 6)))
(check "write-string subrange"
  (call-with-input-file tf (lambda (p) (read-line p)))
  "cdef")

;;; ---- open-binary-input-file / open-binary-output-file ----
(let ((p (open-binary-output-file tf3)))
  (write-u8 1 p)
  (write-u8 2 p)
  (write-u8 3 p)
  (close-port p))
(let ((p (open-binary-input-file tf3)))
  (check "binary file read" (read-u8 p) 1)
  (check "binary file peek" (peek-u8 p) 2)
  (check "binary file read2" (read-u8 p) 2)
  (close-port p))

;;; ---- write-bytevector with subrange ----
(let ((p (open-output-bytevector)))
  (write-bytevector #u8(10 20 30 40 50) p 1 4)
  (check "write-bytevector subrange" (get-output-bytevector p) #u8(20 30 40)))

;;; ---- open-input-bytevector extensive ----
(let ((p (open-input-bytevector #u8(1 2 3 4 5 6 7 8))))
  (check "read-bv 3" (read-bytevector 3 p) #u8(1 2 3))
  (check "read-bv 3 again" (read-bytevector 3 p) #u8(4 5 6))
  (check "read-bv rest" (read-bytevector 10 p) #u8(7 8))
  (check-true "read-bv eof" (eof-object? (read-bytevector 1 p))))

;;; ---- write-u8 to bytevector port ----
(let ((p (open-output-bytevector)))
  (write-u8 255 p)
  (write-u8 0 p)
  (write-u8 128 p)
  (check "write-u8 bv port" (get-output-bytevector p) #u8(255 0 128)))

;;; Cleanup
(delete-file tf)
(delete-file tf2)
(delete-file tf3)

;;; ================================================================
;;; printer.zig — cover remaining type printing paths
;;; ================================================================

(define (wts obj) (let ((p (open-output-string))) (write obj p) (get-output-string p)))
(define (dts obj) (let ((p (open-output-string))) (display obj p) (get-output-string p)))

;;; ---- Print various complex numbers ----
(check-true "print 0+0i" (string? (wts 0+0i)))
(check-true "print 1-0i" (string? (wts (make-rectangular 1.0 -0.0))))
(check-true "print +inf+nan" (string? (wts (make-rectangular +inf.0 +nan.0))))

;;; ---- Print promise ----
(check-true "print promise" (string? (wts (delay 42))))

;;; ---- Print hash table ----
(let ((ht (make-hash-table)))
  (hash-table-set! ht 'k 'v)
  (check-true "print ht" (string? (wts ht))))

;;; ---- Print fiber ----
(let ((f (spawn (lambda () 99))))
  (check-true "print fiber" (string? (wts f)))
  (fiber-join f))

;;; ---- Print channel ----
(check-true "print channel" (string? (wts (make-channel))))

;;; ---- Print random source ----
(check-true "print rs" (string? (wts (make-random-source))))

;;; ---- Print mutex/condvar ----
(check-true "print mutex named" (string? (wts (make-mutex 'my-m))))
(check-true "print condvar named" (string? (wts (make-condition-variable 'my-cv))))
(check-true "print thread" (string? (wts (current-thread))))
(check-true "print time" (string? (wts (current-time))))

;;; ---- Deeply nested print ----
(check-true "print deep list" (string? (wts '(((((1))))))))
(check-true "print mixed" (string? (wts (list 1 "hi" #t #\a #(1 2) #u8(3)))))

;;; ================================================================
;;; primitives_control.zig — error paths, dynamic-wind edge cases
;;; ================================================================

;;; ---- Dynamic-wind with multiple nesting levels ----
(let ((log '()))
  (dynamic-wind
    (lambda () (set! log (cons 'a-in log)))
    (lambda ()
      (dynamic-wind
        (lambda () (set! log (cons 'b-in log)))
        (lambda ()
          (dynamic-wind
            (lambda () (set! log (cons 'c-in log)))
            (lambda () (set! log (cons 'c-body log)))
            (lambda () (set! log (cons 'c-out log)))))
        (lambda () (set! log (cons 'b-out log)))))
    (lambda () (set! log (cons 'a-out log))))
  (check "3-level dw" (length log) 7))

;;; ---- Raise with error-object-type ----
(let ((e (guard (e (#t e)) (error "test" 1 2 3))))
  (check-true "error-object?" (error-object? e))
  (check "error-msg" (error-object-message e) "test")
  (check "error-irritants" (error-object-irritants e) '(1 2 3)))

;;; ---- file-error? ----
(check-true "file-error?"
  (guard (e (#t (file-error? e)))
    (open-input-file "/nonexistent-file-kaappi-test")))

;;; ---- read-error? ----
(check-true "read-error?"
  (guard (e (#t (read-error? e)))
    (read (open-input-string "#\\invalidcharname"))))

;;; ================================================================
;;; primitives_r7rs.zig — load, environment, get-environment-variables
;;; ================================================================

;;; ---- get-environment-variables ----
(let ((vars (get-environment-variables)))
  (check-true "env-vars list" (list? vars)))

;;; ---- environment ----
(let ((env (environment '(scheme base))))
  (check "eval in env" (eval '(+ 1 2) env) 3))

;;; ---- current-second/jiffy ----
(check-true "current-second" (> (current-second) 1000000000))
(check-true "current-jiffy" (> (current-jiffy) 0))
(check-true "jiffies-per-second" (> (jiffies-per-second) 0))

;;; ---- command-line ----
(check-true "command-line list" (list? (command-line)))

;;; ---- load from file ----
(define load-tf "/tmp/kaappi-load-test.scm")
(call-with-output-file load-tf
  (lambda (p) (display "(define kaappi-load-test-var 42)" p)))
(load load-tf)
(check "load" kaappi-load-test-var 42)
(delete-file load-tf)

;;; ================================================================
;;; primitives_filesystem.zig — deeper coverage
;;; ================================================================

;;; ---- create-directory / delete-directory ----
(define td "/tmp/kaappi-dgap-dir")
(when (file-exists? td) (delete-directory td))
(create-directory td)
(check-true "create-directory" (file-info-directory? (file-info td)))
(delete-directory td)
(check-false "delete-directory" (file-exists? td))

;;; ---- symlink ops ----
(define sym-target "/tmp/kaappi-dgap-symtarget")
(define sym-link "/tmp/kaappi-dgap-symlink")
(call-with-output-file sym-target (lambda (p) (display "target" p)))
(when (file-exists? sym-link) (delete-file sym-link))
(create-symlink sym-target sym-link)
(check "read-symlink" (read-symlink sym-link) sym-target)
(check-true "symlink?" (file-info-symlink? (file-info sym-link #f)))
(delete-file sym-link)
(delete-file sym-target)

;;; ---- set-umask! ----
(let ((old (umask)))
  (set-umask! #o022)
  (check "set-umask!" (umask) #o022)
  (set-umask! old))

;;; ---- truncate-file ----
(define trunc-f "/tmp/kaappi-dgap-trunc")
(call-with-output-file trunc-f (lambda (p) (display "hello world" p)))
(truncate-file trunc-f 5)
(check "truncate" (file-info:size (file-info trunc-f)) 5)
(delete-file trunc-f)

;;; ---- set-file-times ----
(define times-f "/tmp/kaappi-dgap-times")
(call-with-output-file times-f (lambda (p) (display "x" p)))
(set-file-times times-f)
(check-true "set-file-times" #t)
(delete-file times-f)

;;; ================================================================
;;; primitives_arithmetic.zig — remaining gaps
;;; ================================================================

;;; ---- Bignum division paths ----
(let ((big (expt 10 50)))
  (check "big quotient" (quotient (* big 7) big) 7)
  (check "big remainder" (remainder (* big 7) big) 0)
  (check "big modulo" (modulo (+ (* big 3) 5) big) 5)
  (check-true "big comparison" (> (* big 2) big)))

;;; ---- Mixed bignum/flonum ----
(check-true "big > flonum" (> (expt 2 100) 1e10))
(check-true "flonum < big" (< 1e10 (expt 2 100)))
(check-true "big = big" (= (expt 2 100) (expt 2 100)))

;;; ---- Complex with special values ----
(check-true "complex?" (complex? +inf.0+0.0i))
(check-true "nan complex" (nan? (imag-part +nan.0+nan.0i)))

;;; ---- Rational comparisons ----
(check-true "rational <" (< 1/3 1/2))
(check-true "rational >" (> 2/3 1/2))
(check-true "rational =" (= 2/4 1/2))

;;; ================================================================
;;; primitives_srfi18.zig — remaining thread paths
;;; ================================================================

;;; ---- Thread with mutation ----
(let ((box (list 0)))
  (let ((t (make-thread (lambda ()
              (set-car! box (+ (car box) 1))))))
    (thread-start! t)
    (thread-join! t)
    (check "thread mutation" (car box) 1)))

;;; ---- Multiple mutex lock/unlock cycles ----
(let ((m (make-mutex)))
  (mutex-lock! m)
  (mutex-unlock! m)
  (mutex-lock! m)
  (mutex-unlock! m)
  (check-true "mutex re-lock" #t))

;;; ---- Condition variable broadcast ----
(let ((m (make-mutex))
      (cv (make-condition-variable))
      (count (list 0)))
  (let ((t1 (make-thread (lambda ()
              (mutex-lock! m)
              (mutex-unlock! m cv)
              (set-car! count (+ (car count) 1)))))
        (t2 (make-thread (lambda ()
              (mutex-lock! m)
              (mutex-unlock! m cv)
              (set-car! count (+ (car count) 1))))))
    (thread-start! t1)
    (thread-start! t2)
    (thread-sleep! 0.05)
    (condition-variable-broadcast! cv)
    (thread-join! t1)
    (thread-join! t2)
    (check "cv broadcast" (car count) 2)))

;;; ================================================================
;;; reader.zig — more edge cases
;;; ================================================================

(define (rfs s) (read (open-input-string s)))

;;; ---- Various number formats ----
(check "read +1" (rfs "+1") 1)
(check "read #b neg" (rfs "#b-1010") -10)
(check "read #o neg" (rfs "#o-17") -15)
(check "read #x neg" (rfs "#x-ff") -255)
(check "read #i rational" (rfs "#i1/3") (inexact 1/3))

;;; ---- Unicode identifiers ----
(check "read unicode sym" (rfs "λ") 'λ)
(check "read unicode str" (rfs "\"λ\"") "λ")
(check "read unicode char" (rfs "#\\λ") #\λ)

;;; ---- Label forward reference ----
(let ((r (rfs "(#0=a #0#)")))
  (check "label fwd" (car r) 'a)
  (check "label fwd ref" (cadr r) 'a))

;;; ================================================================
;;; primitives_lazy.zig — edge cases
;;; ================================================================
(let ((p (delay (begin (display "") 42))))
  (check "delay force" (force p) 42)
  (check "delay force cached" (force p) 42))

(let ((p (make-promise 99)))
  (check "make-promise" (force p) 99))

(check-true "promise?" (promise? (delay 1)))
(check-false "promise? num" (promise? 42))

;;; ================================================================
;;; primitives_hashtable.zig — walk/fold edge cases
;;; ================================================================
(let ((ht (alist->hash-table '((a . 1) (b . 2) (c . 3) (d . 4) (e . 5)))))
  (check "ht fold sum" (hash-table-fold ht (lambda (k v acc) (+ v acc)) 0) 15)
  (let ((keys '()))
    (hash-table-walk ht (lambda (k v) (set! keys (cons k keys))))
    (check "ht walk count" (length keys) 5)))

;;; ---- hash-table-delete! existing ----
(let ((ht (make-hash-table)))
  (hash-table-set! ht 'x 1)
  (hash-table-set! ht 'y 2)
  (hash-table-set! ht 'z 3)
  (hash-table-delete! ht 'y)
  (check "ht delete" (hash-table-size ht) 2)
  (check-false "ht deleted key" (hash-table-exists? ht 'y)))

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "Deep gaps coverage tests failed" fail))
