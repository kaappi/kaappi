;; Regression test for issue #958 (globals read race, follow-up to PR #968):
;; a child thread's view of the globals map must track the parent's map
;; across rehashes. Before the fix, VM.initForThread copied the map header
;; by value, so the first parent-side rehash left the child reading the old
;; (freed) bucket array forever — a set! that landed in the new array was
;; never observed by the child, and this test timed out.
;;
;; The parent defines enough fresh globals to force several rehashes while
;; the child polls a global, then flips the flag. Deterministic given the
;; fix: the child sees 'go on its next locked read.

(import (scheme base) (scheme write) (srfi 18))

(define flag 'wait)

(define child
  (make-thread
   (lambda ()
     (let loop ((i 0))
       (cond ((eq? flag 'go) 'saw-it)
             ((> i 50000000) 'timeout)
             (else (loop (+ i 1))))))))

(thread-start! child)

;; Force the parent globals map through multiple rehashes while the child runs.
(let loop ((i 0))
  (when (< i 3000)
    (eval (list 'define
                (string->symbol (string-append "rehash-var-" (number->string i)))
                i))
    (loop (+ i 1))))

(set! flag 'go)

(let ((r (thread-join! child)))
  (if (eq? r 'saw-it)
      (begin (display "OK") (newline))
      (begin (display "FAIL: child never observed post-rehash write: ")
             (display r)
             (newline)
             (exit 1))))
