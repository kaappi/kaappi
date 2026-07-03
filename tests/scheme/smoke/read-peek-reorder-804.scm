;;; Regression test for #804: (read) after peek-char reorders the stream

(import (scheme base) (scheme read) (scheme write))

(define (check name actual expected)
  (when (not (equal? actual expected))
    (display "FAIL: ")
    (display name)
    (display " expected ")
    (write expected)
    (display " got ")
    (write actual)
    (newline)
    (error "test failed" name)))

(define p (open-input-string "(x)abc de"))

(let ((r1 (read p)))
  (check "r1" r1 '(x))

  (let ((pc (peek-char p)))
    (check "peek-char" pc #\a)

    (let ((r2 (read p)))
      (check "r2" r2 'abc)

      (let ((r3 (read p)))
        (check "r3" r3 'de)

        (let ((r4 (read p)))
          (check "r4" (eof-object? r4) #t))))))

(display "ok")
(newline)
