(define-library (srfi 166 unicode)
  (import (scheme base) (scheme char) (srfi 166))
  (export upcased downcased
          terminal-aware string-terminal-width
          substring-terminal-width)
  (begin

    (define (upcased . fmts)
      (lambda (st)
        (let ((p (open-output-string)))
          (show p (apply each fmts))
          ((displayed (string-upcase (get-output-string p))) st))))

    (define (downcased . fmts)
      (lambda (st)
        (let ((p (open-output-string)))
          (show p (apply each fmts))
          ((displayed (string-downcase (get-output-string p))) st))))

    (define (string-terminal-width str)
      (string-length str))

    (define (substring-terminal-width str from to)
      (- to from))

    (define (terminal-aware . fmts)
      (apply each fmts))

    ))
