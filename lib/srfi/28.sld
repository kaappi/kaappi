(define-library (srfi 28)
  (import (scheme base) (scheme write))
  (export format)
  (begin
    (define (format format-string . objects)
      ;; Walk the format string LINEARLY by reading characters from an input
      ;; string port. Kaappi stores strings as UTF-8 and indexes by codepoint,
      ;; so a `string-ref` index loop is O(n^2) in the string length; reading
      ;; through a port is O(n) (kaappi#2100).
      (let ((out (open-output-string))
            (in (open-input-string format-string)))
        (define (loop objs)
          (let ((c (read-char in)))
            (if (eof-object? c)
                (get-output-string out)
                (if (char=? c #\~)
                    (let ((d (read-char in)))
                      (if (eof-object? d)
                          ;; Trailing tilde with no directive: emit it literally.
                          (begin (write-char #\~ out)
                                 (get-output-string out))
                          (cond
                            ((char=? d #\a)
                             (display (car objs) out)
                             (loop (cdr objs)))
                            ((char=? d #\s)
                             (write (car objs) out)
                             (loop (cdr objs)))
                            ((char=? d #\%)
                             (newline out)
                             (loop objs))
                            ((char=? d #\~)
                             (write-char #\~ out)
                             (loop objs))
                            (else
                             (write-char #\~ out)
                             (write-char d out)
                             (loop objs)))))
                    (begin (write-char c out)
                           (loop objs))))))
        (loop objects)))))
