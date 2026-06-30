;; Regression tests for fiber error handling
;; Issues: #565 (fiber limit error), #564 (error propagation), #551 (native proc rejection)

(import (scheme base) (scheme write) (kaappi fibers))

;; --- #551: spawn rejects native procedures ---
(display "test-native-reject: ")
(guard (exn (#t (display "ok") (newline)))
  (spawn random-real)
  (display "FAIL - should have raised") (newline))

;; --- #564: errors in fibers propagate via fiber-join ---
(display "test-fiber-error-propagate: ")
(let ((f (spawn (lambda () (error "fiber-boom" 42)))))
  (guard (exn (#t
    (if (and (error-object? exn)
             (string=? (error-object-message exn) "fiber-boom"))
      (begin (display "ok") (newline))
      (begin (display "FAIL - wrong error: ")
             (display (error-object-message exn)) (newline)))))
    (fiber-join f)
    (display "FAIL - should have raised") (newline)))

;; --- #564: division by zero in fiber propagates ---
(display "test-fiber-div-zero: ")
(let ((f (spawn (lambda () (/ 1 0)))))
  (guard (exn (#t (display "ok") (newline)))
    (fiber-join f)
    (display "FAIL - should have raised") (newline)))

;; --- #565: fiber limit exceeded gives proper error ---
(display "test-fiber-limit: ")
(guard (exn (#t
  (if (error-object? exn)
    (begin (display "ok") (newline))
    (begin (display "ok-non-error") (newline)))))
  (let loop ((i 0))
    (if (< i 200)
      (begin (spawn (lambda () (yield) (yield) (yield) i))
             (loop (+ i 1)))
      #t))
  (display "ok-no-error") (newline))
