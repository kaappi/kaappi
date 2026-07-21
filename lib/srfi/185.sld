(define-library (srfi 185)
  (import (scheme base) (scheme case-lambda))
  (export string-append-linear! string-replace-linear!
          string-append! string-replace!)
  (begin
    (define (string-append-linear! . args)
      (apply string-append
        (map (lambda (x) (if (char? x) (string x) x)) args)))

    (define string-replace-linear!
      (case-lambda
        ((dst dst-start dst-end src)
         (string-replace dst src dst-start dst-end 0 (string-length src)))
        ((dst dst-start dst-end src src-start)
         (string-replace dst src dst-start dst-end src-start (string-length src)))
        ((dst dst-start dst-end src src-start src-end)
         (string-replace dst src dst-start dst-end src-start src-end))))

    (define-syntax string-append!
      (syntax-rules ()
        ((_ place arg ...)
         (set! place (string-append-linear! place arg ...)))))

    (define-syntax string-replace!
      (syntax-rules ()
        ((_ place start end src)
         (set! place (string-replace-linear! place start end src)))
        ((_ place start end src src-start)
         (set! place (string-replace-linear! place start end src src-start)))
        ((_ place start end src src-start src-end)
         (set! place (string-replace-linear! place start end src src-start src-end)))))))
