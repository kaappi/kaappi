;; Regression test for issue #77:
;; Child threads must not crash when the parent defines globals concurrently.
;; Before the fix, the parent's globals.put could rehash the map while
;; the child was mid-get, causing a torn read / use-after-free.

(import (scheme base) (scheme write) (srfi 18))

;; Spawn a worker that reads a global in a loop
(define counter 0)
(define (worker-thunk)
  (let loop ((i 0))
    (when (< i 1000)
      (+ counter 1)
      (loop (+ i 1))))
  'done)

;; Spawn 3 workers
(define threads
  (map (lambda (_)
         (thread-start! (make-thread worker-thunk)))
       '(1 2 3)))

;; Meanwhile, define new globals from the main thread
(let loop ((i 0))
  (when (< i 100)
    (eval `(define ,(string->symbol
                     (string-append "temp-var-" (number->string i)))
             ,i))
    (loop (+ i 1))))

;; Join all workers
(for-each (lambda (t)
            (let ((r (thread-join! t)))
              (unless (eq? r 'done)
                (display "FAIL: unexpected result ")
                (display r)
                (newline)
                (exit 1))))
          threads)

(display "OK")
(newline)
