;; Regression test for issue #75:
;; Datum-label placeholder must survive GC during nested read.
;; The placeholder pair is now GC-rooted across the readDatum call.

(import (scheme base) (scheme read) (scheme write))

;; Basic datum label round-trip
(let ((x (read (open-input-string "#0=(1 2 3)"))))
  (unless (equal? x '(1 2 3))
    (display "FAIL: basic datum label")
    (newline)
    (exit 1)))

;; Datum label with back-reference (cyclic structure)
(let ((x (read (open-input-string "#0=(a . #0#)"))))
  (unless (and (pair? x)
               (eq? (car x) 'a)
               (eq? (cdr x) x))
    (display "FAIL: cyclic datum label")
    (newline)
    (exit 1)))

;; Multiple datum labels
(let ((x (read (open-input-string "#0=(1 #1=(2 3) #1#)"))))
  (unless (and (equal? (car x) 1)
               (equal? (cadr x) '(2 3))
               (eq? (cadr x) (caddr x)))
    (display "FAIL: multiple datum labels")
    (newline)
    (exit 1)))

(display "OK")
(newline)
