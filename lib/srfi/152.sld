(define-library (srfi 152)
  (import (scheme base) (scheme char) (scheme case-lambda) (scheme write))
  (export
    ;; From (scheme base)
    string? make-string string string-length string-ref
    string-set! string=? string<? string>? string<=? string>=?
    substring string-append string->list list->string
    string-copy string-copy! string-fill!
    string-for-each string-map
    ;; Case operations
    string-upcase string-downcase string-foldcase
    ;; Extended operations
    string-contains string-prefix? string-suffix?
    string-index string-index-right
    string-skip string-skip-right
    string-count
    string-take string-drop
    string-take-right string-drop-right
    string-pad string-pad-right
    string-trim string-trim-right string-trim-both
    string-replace
    string-split
    string-join string-concatenate
    string-tabulate
    string-every string-any
    string-reverse)
  (begin
    (define (string-contains s1 s2)
      (let ((len1 (string-length s1))
            (len2 (string-length s2)))
        (let loop ((i 0))
          (if (> (+ i len2) len1) #f
              (if (string=? (substring s1 i (+ i len2)) s2) i
                  (loop (+ i 1)))))))

    (define (string-prefix? pre s)
      (and (<= (string-length pre) (string-length s))
           (string=? pre (substring s 0 (string-length pre)))))

    (define (string-suffix? suf s)
      (let ((ls (string-length s)) (lsuf (string-length suf)))
        (and (<= lsuf ls)
             (string=? suf (substring s (- ls lsuf) ls)))))

    (define (string-index s pred . args)
      (let ((start (if (null? args) 0 (car args)))
            (end (if (or (null? args) (null? (cdr args)))
                     (string-length s) (cadr args))))
        (let loop ((i start))
          (if (>= i end) #f
              (if (pred (string-ref s i)) i
                  (loop (+ i 1)))))))

    (define (string-index-right s pred . args)
      (let ((start (if (null? args) 0 (car args)))
            (end (if (or (null? args) (null? (cdr args)))
                     (string-length s) (cadr args))))
        (let loop ((i (- end 1)))
          (if (< i start) #f
              (if (pred (string-ref s i)) i
                  (loop (- i 1)))))))

    (define (string-skip s pred . args)
      (apply string-index s (lambda (c) (not (pred c))) args))

    (define (string-skip-right s pred . args)
      (apply string-index-right s (lambda (c) (not (pred c))) args))

    (define (string-count s pred . args)
      (let ((start (if (null? args) 0 (car args)))
            (end (if (or (null? args) (null? (cdr args)))
                     (string-length s) (cadr args))))
        (let loop ((i start) (c 0))
          (if (>= i end) c
              (loop (+ i 1) (if (pred (string-ref s i)) (+ c 1) c))))))

    (define (string-take s n) (substring s 0 n))
    (define (string-drop s n) (substring s n (string-length s)))
    (define (string-take-right s n) (substring s (- (string-length s) n) (string-length s)))
    (define (string-drop-right s n) (substring s 0 (- (string-length s) n)))

    (define (string-pad s len . args)
      (let ((ch (if (null? args) #\space (car args)))
            (slen (string-length s)))
        (if (>= slen len)
            (substring s (- slen len) slen)
            (string-append (make-string (- len slen) ch) s))))

    (define (string-pad-right s len . args)
      (let ((ch (if (null? args) #\space (car args)))
            (slen (string-length s)))
        (if (>= slen len)
            (substring s 0 len)
            (string-append s (make-string (- len slen) ch)))))

    (define (string-trim s . args)
      (let ((pred (if (null? args) char-whitespace? (car args))))
        (let ((start (string-skip s pred)))
          (if start (substring s start (string-length s)) ""))))

    (define (string-trim-right s . args)
      (let ((pred (if (null? args) char-whitespace? (car args))))
        (let ((end (string-skip-right s pred)))
          (if end (substring s 0 (+ end 1)) ""))))

    (define (string-trim-both s . args)
      (let ((pred (if (null? args) char-whitespace? (car args))))
        (string-trim-right (string-trim s pred) pred)))

    (define (string-replace s1 s2 start end)
      (string-append (substring s1 0 start)
                     s2
                     (substring s1 end (string-length s1))))

    (define (string-split s delim)
      (let ((slen (string-length s))
            (dlen (string-length delim)))
        (if (= dlen 0) (list s)
            (let loop ((start 0) (result '()))
              (let ((pos (string-contains (substring s start slen) delim)))
                (if pos
                    (loop (+ start pos dlen)
                          (cons (substring s start (+ start pos)) result))
                    (reverse (cons (substring s start slen) result))))))))

    (define (string-join strs . args)
      (let ((delim (if (null? args) " " (car args))))
        (if (null? strs) ""
            (let loop ((rest (cdr strs)) (result (car strs)))
              (if (null? rest) result
                  (loop (cdr rest) (string-append result delim (car rest))))))))

    (define (string-concatenate strs)
      (apply string-append strs))

    (define (string-tabulate proc len)
      (let ((out (open-output-string)))
        (let loop ((i 0))
          (if (< i len)
              (begin (write-char (proc i) out)
                     (loop (+ i 1)))
              (get-output-string out)))))

    (define (string-every pred s . args)
      (let ((start (if (null? args) 0 (car args)))
            (end (if (or (null? args) (null? (cdr args)))
                     (string-length s) (cadr args))))
        (let loop ((i start))
          (if (>= i end) #t
              (and (pred (string-ref s i)) (loop (+ i 1)))))))

    (define (string-any pred s . args)
      (let ((start (if (null? args) 0 (car args)))
            (end (if (or (null? args) (null? (cdr args)))
                     (string-length s) (cadr args))))
        (let loop ((i start))
          (if (>= i end) #f
              (or (pred (string-ref s i)) (loop (+ i 1)))))))

    (define (string-reverse s)
      (list->string (reverse (string->list s))))))
