(define-library (srfi 166 columnar)
  (import (scheme base) (scheme char) (scheme file) (srfi 1) (srfi 166 base))
  (export columnar tabular wrapped wrapped/list wrapped/char
          justified from-file line-numbers)
  (begin

    (define (%split-lines s)
      (let loop ((i 0) (start 0) (acc '()))
        (cond
          ((>= i (string-length s))
           (if (> i start) (reverse (cons (substring s start i) acc)) (reverse acc)))
          ((char=? (string-ref s i) #\newline)
           (loop (+ i 1) (+ i 1) (cons (substring s start i) acc)))
          (else (loop (+ i 1) start acc)))))

    (define (%split-words s sep?)
      (let loop ((i 0) (start #f) (acc '()))
        (cond
          ((>= i (string-length s))
           (reverse (if start (cons (substring s start i) acc) acc)))
          ((sep? (string-ref s i))
           (if start
               (loop (+ i 1) #f (cons (substring s start i) acc))
               (loop (+ i 1) #f acc)))
          (else
           (loop (+ i 1) (if start start i) acc)))))

    (define (%join-strings ls sep)
      (if (null? ls)
          ""
          (let loop ((ls ls) (acc (car ls)))
            (if (null? (cdr ls)) acc
                (loop (cdr ls) (string-append acc sep (car (cdr ls))))))))

    ;;; ================================================== columnar / tabular

    ;; A parsed cell is (b . str) or (c fmt width align infinite?).
    (define (%parse-columns args)
      (let loop ((ls args) (align 'left) (infinite? #f) (cw #f) (acc '()))
        (cond
          ((null? ls) (reverse acc))
          ((string? (car ls)) (loop (cdr ls) align infinite? cw (cons (list 'b (car ls)) acc)))
          ((char? (car ls)) (loop (cdr ls) align infinite? cw (cons (list 'b (string (car ls))) acc)))
          ((number? (car ls)) (loop (cdr ls) align infinite? (car ls) acc))
          ((eq? (car ls) 'infinite) (loop (cdr ls) align #t cw acc))
          ((symbol? (car ls)) (loop (cdr ls) (car ls) infinite? cw acc))
          ((procedure? (car ls))
           (loop (cdr ls) 'left #f #f (cons (list 'c (car ls) cw align infinite?) acc)))
          (else (error "columnar: invalid column argument" (car ls))))))

    (define (%border-total cells)
      (fold (lambda (c n) (if (eq? 'b (car c)) (+ n (string-length (cadr c))) n)) 0 cells))

    (define (column-cell-width c)
      (list-ref c 2))

    (define (%pad-line line w align pad-char)
      (let ((needed (- w (string-length line))))
        (if (<= needed 0)
            line
            (case align
              ((right) (string-append (make-string needed pad-char) line))
              ((center) (let ((left (quotient needed 2)))
                          (string-append (make-string left pad-char) line
                                         (make-string (- needed left) pad-char))))
              (else (string-append line (make-string needed pad-char)))))))

    (define (%render-row cells cols widths lines-list row pad-char pad-last?)
      (let loop ((cells cells) (cols cols) (widths widths) (ll lines-list) (acc '()))
        (if (null? cells)
            (%join-strings (reverse acc) "")
            (let ((cell (car cells)))
              (if (eq? 'b (car cell))
                  (loop (cdr cells) cols widths ll (cons (cadr cell) acc))
                  (let* ((col (car cols))
                         (w (car widths))
                         (is-last (null? (cdr cols)))
                         (line (if (list-ref col 4)
                                   (show #f (cadr col))
                                   (let ((ls (car ll)))
                                     (if (and ls (< row (length ls))) (list-ref ls row) ""))))
                         (padded (if (or pad-last? (not is-last))
                                     (%pad-line line w (list-ref col 3) pad-char)
                                     line)))
                    (loop (cdr cells) (cdr cols) (cdr widths) (cdr ll)
                          (cons padded acc))))))))

    (define (%render-string cells cols widths lines-list num-lines pad-char pad-last?)
      (let loop ((row 0) (acc '()))
        (if (= row num-lines)
            (%join-strings (reverse acc) "")
            (loop (+ row 1)
                  (cons (string-append
                          (%render-row cells cols widths lines-list row pad-char pad-last?)
                          "\n")
                        acc)))))

    (define (columnar . args)
      (fn (width string-width pad-char)
        (let* ((cells (%parse-columns args))
               (cols (filter (lambda (c) (eq? 'c (car c))) cells)))
          (if (null? cols)
              (displayed "\n")
              (let* ((border-total (%border-total cells))
                     (fixed-total
                       (fold (lambda (c n)
                               (let ((w (column-cell-width c)))
                                 (if (and (number? w) (>= w 1)) (+ n w) n)))
                             0 cols))
                     (num-unspec
                       (fold (lambda (c n)
                               (let ((w (column-cell-width c)))
                                 (if (and (number? w) (>= w 1)) n (+ n 1))))
                             0 cols))
                     (unspec-w (if (zero? num-unspec) 0
                                   (quotient (- width border-total fixed-total) num-unspec)))
                     (widths (map (lambda (c)
                                    (let ((w (column-cell-width c)))
                                      (if (and (number? w) (>= w 1)) w unspec-w)))
                                  cols))
                     (lines-list (map (lambda (c)
                                        (if (list-ref c 4)
                                            #f
                                            (%split-lines (show #f (cadr c)))))
                                      cols))
                     (num-lines (fold (lambda (ls n) (if ls (max n (length ls)) n)) 0 lines-list)))
                (if (zero? num-lines)
                    (displayed "\n")
                    (displayed (%render-string cells cols widths lines-list num-lines
                                               pad-char #f))))))))

    (define (tabular . args)
      (fn (string-width pad-char)
        (let* ((cells (%parse-columns args))
               (cols (filter (lambda (c) (eq? 'c (car c))) cells)))
          (if (null? cols)
              (displayed "\n")
              (let* ((lines-list (map (lambda (c)
                                        (if (list-ref c 4)
                                            #f
                                            (%split-lines (show #f (cadr c)))))
                                      cols))
                     (widths (map (lambda (c ls)
                                    (let ((mw (if ls
                                                  (fold (lambda (line n) (max n (string-length line)))
                                                        1 ls)
                                                  1))
                                          (w (column-cell-width c)))
                                      (if (and (number? w) (>= w 1)) (max w mw) mw)))
                                  cols lines-list))
                     (num-lines (fold (lambda (ls n) (if ls (max n (length ls)) n)) 0 lines-list)))
                (if (zero? num-lines)
                    (displayed "\n")
                    (displayed (%render-string cells cols widths lines-list num-lines
                                               pad-char #t))))))))

    ;;; ========================================================== wrapped

    (define (%wrap-words words width sw)
      (let loop ((ws words) (line '()) (line-w 0) (lines '()))
        (cond
          ((null? ws)
           (reverse (if (null? line) lines (cons (%join-strings (reverse line) " ") lines))))
          (else
           (let* ((w (sw (car ws)))
                  (new-w (if (null? line) w (+ line-w 1 w))))
             (if (and (not (null? line)) (> new-w width))
                 (loop ws '() 0 (cons (%join-strings (reverse line) " ") lines))
                 (loop (cdr ws) (cons (car ws) line) new-w lines)))))))

    (define (%wrap-chars text width sw)
      (let ((len (string-length text)))
        (let loop ((i 0) (chunks '()))
          (if (>= i len)
              (reverse chunks)
              (let find-j ((j i))
                (cond
                  ((>= j len) (loop len (cons (substring text i len) chunks)))
                  ((> (sw (substring text i (+ j 1))) width) (loop j (cons (substring text i j) chunks)))
                  (else (find-j (+ j 1)))))))))

    (define (wrapped . fmts)
      (fn (width string-width word-separator?)
        (let* ((text (show #f (apply each fmts)))
               (words (%split-words text (or word-separator? char-whitespace?))))
          (displayed (%join-strings (%wrap-words words width string-width) "\n")))))

    (define (wrapped/list lst)
      (fn (width string-width)
        (displayed (%join-strings (%wrap-words lst width string-width) "\n"))))

    (define (wrapped/char . fmts)
      (fn (width string-width)
        (displayed (%join-strings (%wrap-chars (show #f (apply each fmts)) width string-width) "\n"))))

    (define (justified . fmts)
      (fn (width string-width word-separator?)
        (let* ((text (show #f (apply each fmts)))
               (words (%split-words text (or word-separator? char-whitespace?)))
               (lines (%wrap-words words width string-width)))
          (displayed
            (%join-strings
              (let loop ((ls lines) (acc '()))
                (if (null? ls)
                    (reverse acc)
                    (if (null? (cdr ls))
                        (loop (cdr ls) (cons (car ls) acc))
                        (loop (cdr ls) (cons (%justify-line (car ls) width string-width) acc)))))
              "\n")))))

    (define (%justify-line line width sw)
      (let ((words (%split-words line char-whitespace?)))
        (if (or (null? words) (null? (cdr words)))
            line
            (let* ((total (fold (lambda (w n) (+ n (sw w))) 0 words))
                   (gaps (- (length words) 1))
                   (extra (- width total))
                   (base (if (positive? extra) (quotient extra gaps) 0))
                   (rem (if (positive? extra) (remainder extra gaps) 0)))
              (let loop ((ws words) (i 0) (acc (car words)))
                (if (null? (cdr ws))
                    acc
                    (let ((sep (make-string (+ 1 base (if (< i rem) 1 0)) #\space)))
                      (loop (cdr ws) (+ i 1) (string-append acc sep (car (cdr ws)))))))))))

    ;;; ================================================== from-file / numbers

    (define (from-file pathname)
      (lambda (st)
        (let ((p (open-input-file pathname)))
          (let loop ((st st))
            (let ((line (read-line p)))
              (if (eof-object? line)
                  (begin (close-input-port p) st)
                  (loop ((each (displayed line) nl) st))))))))

    ;; One number per application, right-padded to a fixed width of 5.  In
    ;; `columnar` an 'infinite column is applied once per line, so this streams
    ;; the next number on each call.
    (define (line-numbers . rest)
      (let ((start (if (null? rest) 1 (car rest))))
        (let ((n start))
          (lambda (st)
            (let ((s (number->string n)))
              (set! n (+ n 1))
              ((padded 5 (displayed s)) st))))))

    ))
