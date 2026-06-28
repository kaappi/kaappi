;; Regression test for #205: write barriers in fiber/channel mutations.
;; Exercises channel send/receive and fiber join under GC pressure to
;; verify that old→young references are tracked correctly.

(import (scheme base)
        (scheme write))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ")
        (display name)
        (display " got=")
        (write got)
        (display " expected=")
        (write expected)
        (newline))))

;; Allocate garbage to pressure GC between operations
(define (gc-pressure)
  (let loop ((i 0))
    (when (< i 500)
      (make-vector 50 (list i i i))
      (loop (+ i 1)))))

;; Test 1: channel send/receive with GC pressure
(define ch (make-channel))
(channel-send ch (list 1 2 3))
(gc-pressure)
(channel-send ch (vector 4 5 6))
(gc-pressure)
(let ((v1 (channel-receive ch)))
  (check "channel-recv-1" v1 '(1 2 3)))
(let ((v2 (channel-receive ch)))
  (check "channel-recv-2" v2 #(4 5 6)))

;; Test 2: fiber join retrieves result after GC pressure
(define f1 (spawn (lambda ()
                    (gc-pressure)
                    (list 'fiber-result 42))))
(gc-pressure)
(check "fiber-join" (fiber-join f1) '(fiber-result 42))

;; Test 3: multiple fibers communicating through channel
(define ch2 (make-channel))
(spawn (lambda ()
         (gc-pressure)
         (channel-send ch2 "hello")))
(spawn (lambda ()
         (gc-pressure)
         (channel-send ch2 "world")))
(gc-pressure)
(let* ((a (channel-receive ch2))
       (b (channel-receive ch2)))
  (check "multi-fiber-channel"
         (list (string? a) (string? b))
         '(#t #t)))

;; Summary
(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
