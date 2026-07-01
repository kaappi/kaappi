;;; Regression test for issue #634: markVMRoots must not iterate shared
;;; vm.libraries map in child threads (data race with parent's import).
;;; The fix gates library marking on owns_globals, matching globals/macros.

(import (scheme base) (scheme write) (srfi 18))

(define (allocator)
  (lambda ()
    (let loop ((i 0) (acc '()))
      (if (< i 50000)
          (loop (+ i 1) (cons i acc))
          (length acc)))))

(define t1 (thread-start! (make-thread (allocator))))

(define result (thread-join! t1))
(unless (= result 50000)
  (display "FAIL: expected 50000, got ")
  (display result)
  (newline)
  (exit 1))

(display "OK")
(newline)
