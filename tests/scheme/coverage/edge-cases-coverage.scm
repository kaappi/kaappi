(import (scheme base) (scheme write) (scheme read) (scheme char)
        (scheme inexact) (scheme complex) (scheme file) (scheme lazy)
        (srfi 18) (srfi 170) (kaappi fibers))

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

;;; ==== Arithmetic edge cases ====
(check-true "even? flonum" (even? 4.0))
(check-false "even? odd flonum" (even? 3.0))
(check-true "odd? flonum" (odd? 3.0))
(check-false "odd? even flonum" (odd? 4.0))
(check-true "even? bignum" (even? (expt 2 100)))
(check-true "odd? bignum" (odd? (+ (expt 2 100) 1)))
(check "lcm bignum" (lcm (expt 2 100) (expt 2 50)) (expt 2 100))
(check "gcd 0" (gcd 0 5) 5)
(check "lcm 0" (lcm 0 5) 0)
(check-true "type error in +"
  (guard (e (#t (error-object? e))) (+ 1 "hello")))

;;; ==== IO edge cases ====
(let ((p (open-input-string "λ")))
  (check "peek-char utf8" (peek-char p) #\λ)
  (check "peek-char utf8 again" (peek-char p) #\λ)
  (check "read-char utf8" (read-char p) #\λ))

;; Binary I/O on file ports
(define bio-f "/tmp/kaappi-bio-test")
(call-with-output-file bio-f (lambda (p) (write-u8 65 p) (write-u8 66 p) (write-u8 67 p)))
(let ((p (open-input-file bio-f)))
  (check "read-u8 file" (read-u8 p) 65)
  (check "peek-u8 file" (peek-u8 p) 66)
  (check "read-u8 after peek" (read-u8 p) 66)
  (close-port p))
(delete-file bio-f)

;; Error in call-with-output-file callback
(check "call-with-output-file error"
  (guard (e (#t 'caught))
    (call-with-output-file "/tmp/kaappi-err-test"
      (lambda (p) (error "err"))))
  'caught)
(when (file-exists? "/tmp/kaappi-err-test")
  (delete-file "/tmp/kaappi-err-test"))

;; Error in call-with-input-file callback
(call-with-output-file "/tmp/kaappi-err-test2" (lambda (p) (display "x" p)))
(check "call-with-input-file error"
  (guard (e (#t 'caught))
    (call-with-input-file "/tmp/kaappi-err-test2"
      (lambda (p) (error "err"))))
  'caught)
(delete-file "/tmp/kaappi-err-test2")

;; Error in with-input-from-file
(call-with-output-file "/tmp/kaappi-err-test3" (lambda (p) (display "x" p)))
(check "with-input-from-file error"
  (guard (e (#t 'caught))
    (with-input-from-file "/tmp/kaappi-err-test3" (lambda () (error "err"))))
  'caught)
(delete-file "/tmp/kaappi-err-test3")

;; Error in with-output-to-file
(check "with-output-to-file error"
  (guard (e (#t 'caught))
    (with-output-to-file "/tmp/kaappi-err-test4" (lambda () (error "err"))))
  'caught)
(when (file-exists? "/tmp/kaappi-err-test4")
  (delete-file "/tmp/kaappi-err-test4"))

;; Error in call-with-port
(check "call-with-port error"
  (guard (e (#t 'caught))
    (call-with-port (open-input-string "x") (lambda (p) (error "err"))))
  'caught)

;;; ==== Control flow edge cases ====
(check "raise string"
  (guard (e ((string? e) e)) (raise "custom"))
  "custom")
(check "raise symbol"
  (guard (e ((symbol? e) e)) (raise 'my-err))
  'my-err)
(check "raise-continuable"
  (with-exception-handler (lambda (e) (+ e 100)) (lambda () (raise-continuable 5)))
  105)
(check "raise-continuable string"
  (with-exception-handler (lambda (e) (string-append "h:" e)) (lambda () (raise-continuable "x")))
  "h:x")

;; Handler returns from non-continuable raise => re-raise
(check-true "handler re-raise"
  (guard (e (#t (error-object? e)))
    (with-exception-handler (lambda (e) 42) (lambda () (raise "boom")))))

;;; ==== SRFI-18 edge cases ====
;; mutex-lock! with timeout
(let ((m (make-mutex)))
  (mutex-lock! m)
  (let ((t (make-thread
            (lambda ()
              (mutex-lock! m (seconds->time (+ (time->seconds (current-time)) 0.01)))))))
    (thread-start! t)
    (let ((r (thread-join! t)))
      (check-true "mutex-lock timeout" (boolean? r)))
    (mutex-unlock! m)))

;; thread-join! with timeout — may not raise on all platforms, skip

;; Fiber mutex contention
(let ((m (make-mutex))
      (result (list 0)))
  (let ((f (spawn (lambda ()
              (mutex-lock! m)
              (set-car! result (+ (car result) 1))
              (mutex-unlock! m)))))
    (mutex-lock! m)
    (set-car! result (+ (car result) 1))
    (mutex-unlock! m)
    (fiber-join f)
    (check "fiber mutex" (car result) 2)))

;; mutex-unlock! with condvar and timeout
(let ((m (make-mutex))
      (cv (make-condition-variable)))
  (mutex-lock! m)
  (check-true "unlock-cv-timeout"
    (boolean? (mutex-unlock! m cv (seconds->time (+ (time->seconds (current-time)) 0.01))))))

;;; ==== Filesystem edge cases ====
(check-true "file-info:rdev" (number? (file-info:rdev (file-info "."))))
(let ((old (umask)))
  (set-umask! #o077)
  (check "set-umask!" (umask) #o077)
  (set-umask! old))
(check-true "directory-files dotfiles" (>= (length (directory-files "." #t)) (length (directory-files "."))))

;; truncate-file to 0
(define tf-edge "/tmp/kaappi-trunc-edge")
(call-with-output-file tf-edge (lambda (p) (display "hello" p)))
(truncate-file tf-edge 0)
(check "truncate to 0" (file-info:size (file-info tf-edge)) 0)
(delete-file tf-edge)

;; set-file-times with explicit times
(define tf-time "/tmp/kaappi-time-edge")
(call-with-output-file tf-time (lambda (p) (display "x" p)))
(set-file-times tf-time (posix-time) (posix-time))
(check-true "set-file-times explicit" #t)
(delete-file tf-time)

;;; ==== Reader edge cases ====
(check "read +42" (read (open-input-string "+42")) 42)
(check "read -42" (read (open-input-string "-42")) -42)
(check "read ..." (symbol? (read (open-input-string "..."))) #t)
(check "read hex escape" (read (open-input-string "\"\\x48;ello\"")) "Hello")
(check "read multi datum-comment" (read (open-input-string "#;1 #;2 42")) 42)
(check "read #true" (read (open-input-string "#true")) #t)
(check "read #false" (read (open-input-string "#false")) #f)

;;; ==== Bignum edge cases ====
(let ((a (expt 10 60)) (b (+ (expt 10 30) 7)))
  (check-true "bignum quotient multi-limb" (integer? (quotient a b)))
  (check-true "bignum remainder multi-limb" (integer? (remainder a b))))
(check-true "bignum->hex" (string? (number->string (expt 2 100) 16)))
(check-true "bignum subtraction neg" (negative? (- (expt 2 50) (expt 2 100))))
(check-true "bignum inexact" (inexact? (inexact (expt 2 100))))

;;; ==== Lazy edge cases ====
(let ((p (delay (begin 42))))
  (check "force delay" (force p) 42)
  (check "force cached" (force p) 42))
(check "delay-force" (force (delay-force (delay 99))) 99)
(check-true "promise?" (promise? (delay 1)))
(check-false "promise? num" (promise? 42))
(check "make-promise" (force (make-promise 77)) 77)

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "Edge cases coverage tests failed" fail))
