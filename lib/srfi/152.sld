(define-library (srfi 152)
  (import (scheme base) (scheme char) (scheme write)
          (only (srfi 13)
                string-contains string-prefix? string-suffix?
                string-index string-index-right
                string-skip string-skip-right
                string-count
                string-take string-drop
                string-take-right string-drop-right
                string-pad string-pad-right
                string-trim string-trim-right string-trim-both
                string-replace
                string-join string-concatenate
                string-tabulate
                string-every string-any
                string-unfold string-unfold-right
                string-filter)
          (rename (only (srfi 13) string-delete)
                  (string-delete string-remove)))
  (export
    ;; Predicates
    string? string-null? string-every string-any
    ;; Constructors
    make-string string string-tabulate string-unfold string-unfold-right
    ;; Conversion
    string->vector string->list vector->string list->string
    reverse-list->string
    ;; Selection
    string-length string-ref substring string-copy
    string-take string-take-right string-drop string-drop-right
    string-pad string-pad-right
    string-trim string-trim-right string-trim-both
    ;; Replacement
    string-replace
    ;; Comparison
    string=? string<? string>? string<=? string>=?
    string-ci=? string-ci<? string-ci>? string-ci<=? string-ci>=?
    ;; Prefixes and suffixes
    string-prefix-length string-suffix-length
    string-prefix? string-suffix?
    ;; Searching
    string-index string-index-right string-skip string-skip-right
    string-contains string-contains-right
    string-take-while string-take-while-right
    string-drop-while string-drop-while-right
    string-break string-span
    ;; Concatenation
    string-append string-concatenate string-concatenate-reverse
    string-join
    ;; Fold and map
    string-fold string-fold-right
    string-map string-for-each
    string-count string-filter string-remove
    ;; Replication and splitting
    string-replicate string-segment string-split
    ;; Input-output
    read-string write-string
    ;; Mutation
    string-set! string-fill! string-copy!)
  (begin

    (define (string-null? s)
      (= 0 (string-length s)))

    (define (reverse-list->string lst)
      (list->string (reverse lst)))

    (define (string-prefix-length s1 s2 . args)
      (let* ((start1 (if (pair? args) (car args) 0))
             (end1 (if (and (pair? args) (pair? (cdr args)))
                       (cadr args) (string-length s1)))
             (start2 (if (and (pair? args) (pair? (cdr args)) (pair? (cddr args)))
                         (caddr args) 0))
             (end2 (if (and (pair? args) (pair? (cdr args)) (pair? (cddr args))
                            (pair? (cdddr args)))
                       (cadddr args) (string-length s2))))
        (let loop ((i start1) (j start2) (n 0))
          (if (or (>= i end1) (>= j end2)
                  (not (char=? (string-ref s1 i) (string-ref s2 j))))
              n
              (loop (+ i 1) (+ j 1) (+ n 1))))))

    (define (string-suffix-length s1 s2 . args)
      (let* ((start1 (if (pair? args) (car args) 0))
             (end1 (if (and (pair? args) (pair? (cdr args)))
                       (cadr args) (string-length s1)))
             (start2 (if (and (pair? args) (pair? (cdr args)) (pair? (cddr args)))
                         (caddr args) 0))
             (end2 (if (and (pair? args) (pair? (cdr args)) (pair? (cddr args))
                            (pair? (cdddr args)))
                       (cadddr args) (string-length s2))))
        (let loop ((i (- end1 1)) (j (- end2 1)) (n 0))
          (if (or (< i start1) (< j start2)
                  (not (char=? (string-ref s1 i) (string-ref s2 j))))
              n
              (loop (- i 1) (- j 1) (+ n 1))))))

    (define (string-contains-right s1 s2)
      (let ((len1 (string-length s1))
            (len2 (string-length s2)))
        (let loop ((i (- len1 len2)))
          (cond
            ((< i 0) #f)
            ((string=? (substring s1 i (+ i len2)) s2) i)
            (else (loop (- i 1)))))))

    (define (string-take-while s pred)
      (let ((idx (string-skip s pred)))
        (if idx (substring s 0 idx) (string-copy s))))

    (define (string-take-while-right s pred)
      (let ((idx (string-skip-right s pred)))
        (if idx
            (substring s (+ idx 1) (string-length s))
            (string-copy s))))

    (define (string-drop-while s pred)
      (let ((idx (string-skip s pred)))
        (if idx (substring s idx (string-length s)) "")))

    (define (string-drop-while-right s pred)
      (let ((idx (string-skip-right s pred)))
        (if idx (substring s 0 (+ idx 1)) "")))

    (define (string-break s pred)
      (let ((idx (string-index s pred)))
        (if idx
            (values (substring s 0 idx)
                    (substring s idx (string-length s)))
            (values (string-copy s) ""))))

    (define (string-span s pred)
      (let ((idx (string-skip s pred)))
        (if idx
            (values (substring s 0 idx)
                    (substring s idx (string-length s)))
            (values (string-copy s) ""))))

    (define (string-concatenate-reverse strs . args)
      (if (null? args)
          (string-concatenate (reverse strs))
          (let ((final (car args)))
            (if (null? (cdr args))
                (string-concatenate (reverse (cons final strs)))
                (string-concatenate
                 (reverse (cons (substring final 0 (cadr args)) strs)))))))

    (define (string-fold kons knil s . args)
      (let ((start (if (pair? args) (car args) 0))
            (end (if (and (pair? args) (pair? (cdr args)))
                     (cadr args) (string-length s))))
        (let loop ((i start) (acc knil))
          (if (>= i end) acc
              (loop (+ i 1) (kons (string-ref s i) acc))))))

    (define (string-fold-right kons knil s . args)
      (let ((start (if (pair? args) (car args) 0))
            (end (if (and (pair? args) (pair? (cdr args)))
                     (cadr args) (string-length s))))
        (let loop ((i (- end 1)) (acc knil))
          (if (< i start) acc
              (loop (- i 1) (kons (string-ref s i) acc))))))

    (define (string-replicate s from to . args)
      (let* ((start (if (pair? args) (car args) 0))
             (end (if (and (pair? args) (pair? (cdr args)))
                      (cadr args) (string-length s)))
             (slen (- end start)))
        (when (= slen 0)
          (error "string-replicate: cannot replicate empty string"))
        (let ((out (open-output-string)))
          (do ((i from (+ i 1)))
              ((>= i to) (get-output-string out))
            (write-char (string-ref s (+ start (modulo i slen))) out)))))

    (define (string-segment s k)
      (let ((len (string-length s)))
        (let loop ((i 0) (result '()))
          (if (>= i len)
              (reverse result)
              (loop (+ i k)
                    (cons (substring s i (min (+ i k) len)) result))))))

    (define (string-split s delim . args)
      (let* ((grammar (if (pair? args) (car args) 'infix))
             (limit (if (and (pair? args) (pair? (cdr args)))
                        (cadr args) #f))
             (start (if (and (pair? args) (pair? (cdr args)) (pair? (cddr args)))
                        (caddr args) 0))
             (end (if (and (pair? args) (pair? (cdr args)) (pair? (cddr args))
                           (pair? (cdddr args)))
                      (cadddr args) (string-length s)))
             (s (substring s start end))
             (slen (string-length s))
             (dlen (string-length delim)))
        (define (do-split)
          (if (= dlen 0)
              (map string (string->list s))
              (let loop ((pos 0) (count 0) (result '()))
                (if (and limit (>= count limit))
                    (reverse (cons (substring s pos slen) result))
                    (let scan ((i pos))
                      (cond
                        ((> (+ i dlen) slen)
                         (reverse (cons (substring s pos slen) result)))
                        ((string=? (substring s i (+ i dlen)) delim)
                         (loop (+ i dlen) (+ count 1)
                               (cons (substring s pos i) result)))
                        (else (scan (+ i 1)))))))))
        (case grammar
          ((infix)
           (if (= slen 0) '() (do-split)))
          ((strict-infix)
           (if (= slen 0)
               (error "string-split: empty string with strict-infix grammar")
               (do-split)))
          ((prefix)
           (let ((parts (if (= slen 0) '() (do-split))))
             (if (and (pair? parts) (string=? "" (car parts)))
                 (cdr parts)
                 parts)))
          ((suffix)
           (let ((parts (if (= slen 0) '() (do-split))))
             (let ((rparts (reverse parts)))
               (if (and (pair? rparts) (string=? "" (car rparts)))
                   (reverse (cdr rparts))
                   parts))))
          (else (error "string-split: invalid grammar" grammar)))))))
