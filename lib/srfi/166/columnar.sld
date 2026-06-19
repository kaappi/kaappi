(define-library (srfi 166 columnar)
  (import (scheme base) (scheme char) (srfi 166))
  (export columnar tabular wrapped wrapped/list wrapped/char justified
          from-file line-numbers)
  (begin

    (define (%string-split-lines s)
      (let loop ((i 0) (start 0) (result '()))
        (cond
          ((= i (string-length s))
           (reverse (cons (substring s start i) result)))
          ((char=? (string-ref s i) #\newline)
           (loop (+ i 1) (+ i 1) (cons (substring s start i) result)))
          (else (loop (+ i 1) start result)))))

    (define (columnar . cols)
      (lambda (st)
        (let* ((strs (map (lambda (c)
                            (let ((p (open-output-string)))
                              (show p c)
                              (get-output-string p)))
                          cols))
               (line-lists (map %string-split-lines strs))
               (max-lines (apply max (map length line-lists))))
          (let loop ((row 0) (st st))
            (if (= row max-lines) st
                (let col-loop ((lls line-lists) (st st) (first #t))
                  (if (null? lls) (loop (+ row 1) ((each nl) st))
                      (let* ((lines (car lls))
                             (line (if (< row (length lines)) (list-ref lines row) "")))
                        (col-loop (cdr lls)
                                  ((displayed (if first line (string-append " " line))) st)
                                  #f)))))))))

    (define (tabular . cols)
      (apply columnar cols))

    (define (wrapped . fmts)
      (lambda (st)
        (let* ((s (show #f (apply each fmts)))
               (words (%split-words s))
               (w 78))
          (let loop ((ws words) (col 0) (st st) (first #t))
            (if (null? ws) st
                (let ((wlen (string-length (car ws))))
                  (if (and (not first) (> (+ col 1 wlen) w))
                      (loop ws 0 ((each nl) st) #t)
                      (let ((st (if first st ((displayed " ") st))))
                        (loop (cdr ws) (+ (if first 0 (+ col 1)) wlen)
                              ((displayed (car ws)) st) #f)))))))))

    (define (%split-words s)
      (let loop ((i 0) (start #f) (result '()))
        (cond
          ((= i (string-length s))
           (reverse (if start (cons (substring s start i) result) result)))
          ((char-whitespace? (string-ref s i))
           (if start
               (loop (+ i 1) #f (cons (substring s start i) result))
               (loop (+ i 1) #f result)))
          (else
           (loop (+ i 1) (if start start i) result)))))

    (define (wrapped/list lst)
      (wrapped (joined displayed lst " ")))

    (define (wrapped/char . fmts)
      (apply wrapped fmts))

    (define (justified . fmts)
      (apply wrapped fmts))

    (define (from-file pathname)
      (lambda (st)
        (let ((p (open-input-file pathname)))
          (let loop ((st st))
            (let ((line (read-line p)))
              (if (eof-object? line)
                  (begin (close-input-port p) st)
                  (loop ((each (displayed line) nl) st))))))))

    (define (line-numbers . rest)
      (let ((start (if (null? rest) 1 (car rest))))
        (let ((n start))
          (lambda (st)
            (let ((s (number->string n)))
              (set! n (+ n 1))
              ((each (padded 5 (displayed s)) (displayed " ")) st))))))

    ))
