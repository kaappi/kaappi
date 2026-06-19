(define-library (srfi 166)
  (import (scheme base) (scheme write) (scheme char) (scheme cxr))
  (export show displayed written written-shared written-simply
          escaped maybe-escaped
          numeric numeric/comma numeric/si
          nl fl space-to tab-to nothing
          each each-in-list joined joined/prefix joined/suffix
          joined/last joined/range
          padded padded/right padded/both
          trimmed trimmed/right trimmed/both
          fitted fitted/right fitted/both
          fn with with!
          call-with-output forked
          port row col width output pad-char ellipsis
          radix precision decimal-sep sign-rule comma-rule comma-sep
          string-width)
  (begin

    ;;; State is a vector: #(port col row width pad-char ellipsis radix precision
    ;;;                       decimal-sep sign-rule comma-rule comma-sep string-width-fn)
    (define %idx-port 0)
    (define %idx-col 1)
    (define %idx-row 2)
    (define %idx-width 3)
    (define %idx-pad 4)
    (define %idx-ellipsis 5)
    (define %idx-radix 6)
    (define %idx-precision 7)
    (define %idx-decsep 8)
    (define %idx-sign 9)
    (define %idx-comma-rule 10)
    (define %idx-comma-sep 11)
    (define %idx-strwidth 12)
    (define %state-size 13)

    (define (%make-state p)
      (let ((st (make-vector %state-size #f)))
        (vector-set! st %idx-port p)
        (vector-set! st %idx-col 0)
        (vector-set! st %idx-row 0)
        (vector-set! st %idx-width 78)
        (vector-set! st %idx-pad #\space)
        (vector-set! st %idx-ellipsis "")
        (vector-set! st %idx-radix 10)
        (vector-set! st %idx-precision #f)
        (vector-set! st %idx-decsep ".")
        (vector-set! st %idx-sign #f)
        (vector-set! st %idx-comma-rule #f)
        (vector-set! st %idx-comma-sep #\,)
        (vector-set! st %idx-strwidth string-length)
        st))

    (define (%copy-state st)
      (let ((new (make-vector %state-size)))
        (let loop ((i 0))
          (if (= i %state-size) new
              (begin (vector-set! new i (vector-ref st i)) (loop (+ i 1)))))))

    (define (%st-port st) (vector-ref st %idx-port))
    (define (%st-col st) (vector-ref st %idx-col))
    (define (%st-row st) (vector-ref st %idx-row))
    (define (%st-width st) (vector-ref st %idx-width))

    (define (%output-string st s)
      (display s (%st-port st))
      (let ((len (string-length s)))
        (let loop ((i 0) (col (%st-col st)) (row (%st-row st)))
          (if (= i len)
              (begin (vector-set! st %idx-col col)
                     (vector-set! st %idx-row row)
                     st)
              (let ((c (string-ref s i)))
                (if (char=? c #\newline)
                    (loop (+ i 1) 0 (+ row 1))
                    (loop (+ i 1) (+ col 1) row)))))))

    (define (%output-char st c)
      (%output-string st (string c)))

    (define (%run-fmt st fmt)
      (cond
        ((string? fmt) (%output-string st fmt))
        ((char? fmt) (%output-char st fmt))
        ((number? fmt) (%output-string st (number->string fmt)))
        ((procedure? fmt) (fmt st))
        (else (%output-string st (let ((p (open-output-string)))
                                   (display fmt p)
                                   (get-output-string p))))))

    ;;; show

    (define (show dest . fmts)
      (let* ((p (cond
                  ((eq? dest #t) (current-output-port))
                  ((eq? dest #f) (open-output-string))
                  ((port? dest) dest)
                  (else (error "show: invalid destination" dest))))
             (st (%make-state p)))
        (let loop ((fs fmts) (st st))
          (if (null? fs)
              (if (eq? dest #f) (get-output-string p) (values))
              (loop (cdr fs) (%run-fmt st (car fs)))))))

    ;;; State variables (just symbolic identifiers for fn/with)

    (define port (list 'port))
    (define row (list 'row))
    (define col (list 'col))
    (define width (list 'width))
    (define output (list 'output))
    (define pad-char (list 'pad-char))
    (define ellipsis (list 'ellipsis))
    (define radix (list 'radix))
    (define precision (list 'precision))
    (define decimal-sep (list 'decimal-sep))
    (define sign-rule (list 'sign-rule))
    (define comma-rule (list 'comma-rule))
    (define comma-sep (list 'comma-sep))
    (define string-width (list 'string-width))

    (define (%var->idx var)
      (cond
        ((eq? var port) %idx-port)
        ((eq? var row) %idx-row)
        ((eq? var col) %idx-col)
        ((eq? var width) %idx-width)
        ((eq? var pad-char) %idx-pad)
        ((eq? var ellipsis) %idx-ellipsis)
        ((eq? var radix) %idx-radix)
        ((eq? var precision) %idx-precision)
        ((eq? var decimal-sep) %idx-decsep)
        ((eq? var sign-rule) %idx-sign)
        ((eq? var comma-rule) %idx-comma-rule)
        ((eq? var comma-sep) %idx-comma-sep)
        ((eq? var string-width) %idx-strwidth)
        (else #f)))

    ;;; Basic formatters

    (define (displayed obj)
      (lambda (st) (%output-string st (let ((p (open-output-string)))
                                         (display obj p) (get-output-string p)))))

    (define (written obj)
      (lambda (st) (%output-string st (let ((p (open-output-string)))
                                         (write obj p) (get-output-string p)))))

    (define written-shared written)
    (define written-simply written)

    (define (escaped str . rest)
      (lambda (st)
        (let ((qch (if (null? rest) #\" (car rest))))
          (%output-char st qch)
          (let loop ((i 0) (st st))
            (if (= i (string-length str)) (%output-char st qch)
                (let ((c (string-ref str i)))
                  (if (or (char=? c qch) (char=? c #\\))
                      (loop (+ i 1) (%output-char (%output-char st #\\) c))
                      (loop (+ i 1) (%output-char st c)))))))))

    (define (maybe-escaped str pred . rest)
      (let ((needs-escape (let loop ((i 0))
                            (if (= i (string-length str)) #f
                                (if (pred (string-ref str i)) #t
                                    (loop (+ i 1)))))))
        (if needs-escape (apply escaped str rest) (displayed str))))

    ;;; Numeric

    (define (numeric num . rest)
      (lambda (st)
        (let ((r (if (null? rest) (vector-ref st %idx-radix) (car rest)))
              (prec (if (or (null? rest) (null? (cdr rest)))
                        (vector-ref st %idx-precision) (cadr rest))))
          (if prec
              (let* ((n (+ num 0.0))
                     (s (%format-float n prec)))
                (%output-string st s))
              (%output-string st (number->string num r))))))

    (define (%format-float num prec)
      (let* ((neg (negative? num))
             (abs-num (abs num))
             (int-part (exact (truncate abs-num)))
             (frac (- abs-num int-part))
             (mult (expt 10 prec))
             (frac-digits (exact (round (* frac mult))))
             (carry (if (>= frac-digits mult) 1 0))
             (frac-digits (if (>= frac-digits mult) 0 frac-digits))
             (int-part (+ int-part carry))
             (int-str (number->string int-part))
             (frac-str (number->string frac-digits))
             (frac-padded (if (< (string-length frac-str) prec)
                              (string-append (make-string (- prec (string-length frac-str)) #\0)
                                             frac-str)
                              frac-str)))
        (string-append (if neg "-" "") int-str "." frac-padded)))

    (define (numeric/comma num . rest)
      (lambda (st) (%output-string st (number->string num))))

    (define (numeric/si num . rest)
      (lambda (st)
        (let* ((suffixes '("" "k" "M" "G" "T" "P" "E"))
               (abs-n (abs num)))
          (let loop ((n abs-n) (ss suffixes))
            (if (or (< n 1000) (null? (cdr ss)))
                (let ((s (if (< n 10) (%format-float (if (negative? num) (- n) n) 1)
                             (number->string (exact (round (if (negative? num) (- n) n)))))))
                  (%output-string st (string-append s (car ss))))
                (loop (/ n 1000) (cdr ss)))))))

    ;;; Space

    (define nl (lambda (st) (%output-string st "\n")))
    (define fl (lambda (st) (if (= (%st-col st) 0) st (%output-string st "\n"))))
    (define nothing (lambda (st) st))

    (define (space-to column)
      (lambda (st)
        (let ((needed (- column (%st-col st))))
          (if (<= needed 0) st
              (%output-string st (make-string needed (vector-ref st %idx-pad)))))))

    (define (tab-to . rest)
      (let ((tw (if (null? rest) 8 (car rest))))
        (lambda (st)
          (let* ((c (%st-col st))
                 (next (* (+ (quotient c tw) 1) tw))
                 (needed (- next c)))
            (%output-string st (make-string needed #\space))))))

    ;;; Concatenation

    (define (each . fmts)
      (lambda (st) (let loop ((fs fmts) (st st))
                     (if (null? fs) st (loop (cdr fs) (%run-fmt st (car fs)))))))

    (define (each-in-list fmts)
      (lambda (st) (let loop ((fs fmts) (st st))
                     (if (null? fs) st (loop (cdr fs) (%run-fmt st (car fs)))))))

    (define (joined mapper lst . rest)
      (let ((sep (if (null? rest) "" (car rest))))
        (lambda (st)
          (if (null? lst) st
              (let loop ((items lst) (st st))
                (let ((st (%run-fmt st (mapper (car items)))))
                  (if (null? (cdr items)) st
                      (loop (cdr items) (%run-fmt st sep)))))))))

    (define (joined/prefix mapper lst . rest)
      (let ((sep (if (null? rest) "" (car rest))))
        (lambda (st)
          (let loop ((items lst) (st st))
            (if (null? items) st
                (loop (cdr items) (%run-fmt (%run-fmt st sep) (mapper (car items)))))))))

    (define (joined/suffix mapper lst . rest)
      (let ((sep (if (null? rest) "" (car rest))))
        (lambda (st)
          (let loop ((items lst) (st st))
            (if (null? items) st
                (loop (cdr items) (%run-fmt (%run-fmt st (mapper (car items))) sep)))))))

    (define (joined/last mapper last-mapper lst . rest)
      (let ((sep (if (null? rest) "" (car rest))))
        (lambda (st)
          (if (null? lst) st
              (let loop ((items lst) (st st))
                (if (null? (cdr items))
                    (%run-fmt st (last-mapper (car items)))
                    (loop (cdr items) (%run-fmt (%run-fmt st (mapper (car items))) sep))))))))

    (define (joined/range mapper start . rest)
      (let ((end (if (null? rest) #f (car rest)))
            (sep (if (or (null? rest) (null? (cdr rest))) "" (cadr rest))))
        (lambda (st)
          (if (and end (>= start end)) st
              (let loop ((i start) (st st) (first #t))
                (if (and end (>= i end)) st
                    (let ((st (if first st (%run-fmt st sep))))
                      (loop (+ i 1) (%run-fmt st (mapper i)) #f))))))))

    ;;; Padding and trimming

    (define (%capture-output st fmts)
      (let ((p (open-output-string)))
        (let ((sub (%copy-state st)))
          (vector-set! sub %idx-port p)
          (vector-set! sub %idx-col 0)
          (let loop ((fs fmts) (sub sub))
            (if (null? fs) (get-output-string p)
                (loop (cdr fs) (%run-fmt sub (car fs))))))))

    (define (padded w . fmts)
      (lambda (st)
        (let* ((s (%capture-output st fmts))
               (slen (string-length s))
               (needed (- w slen)))
          (if (<= needed 0) (%output-string st s)
              (%output-string (%output-string st (make-string needed (vector-ref st %idx-pad))) s)))))

    (define (padded/right w . fmts)
      (lambda (st)
        (let* ((s (%capture-output st fmts))
               (slen (string-length s))
               (needed (- w slen)))
          (if (<= needed 0) (%output-string st s)
              (%output-string (%output-string st s) (make-string needed (vector-ref st %idx-pad)))))))

    (define (padded/both w . fmts)
      (lambda (st)
        (let* ((s (%capture-output st fmts))
               (slen (string-length s))
               (needed (- w slen)))
          (if (<= needed 0) (%output-string st s)
              (let ((left (quotient needed 2))
                    (right (- needed (quotient needed 2))))
                (%output-string
                  (%output-string
                    (%output-string st (make-string left (vector-ref st %idx-pad)))
                    s)
                  (make-string right (vector-ref st %idx-pad))))))))

    (define (trimmed w . fmts)
      (lambda (st)
        (let* ((s (%capture-output st fmts))
               (slen (string-length s)))
          (if (<= slen w) (%output-string st s)
              (%output-string st (substring s (- slen w) slen))))))

    (define (trimmed/right w . fmts)
      (lambda (st)
        (let* ((s (%capture-output st fmts))
               (slen (string-length s)))
          (if (<= slen w) (%output-string st s)
              (%output-string st (substring s 0 w))))))

    (define (trimmed/both w . fmts)
      (lambda (st)
        (let* ((s (%capture-output st fmts))
               (slen (string-length s)))
          (if (<= slen w) (%output-string st s)
              (let ((trim (- slen w)))
                (let ((left (quotient trim 2)))
                  (%output-string st (substring s left (+ left w)))))))))

    (define (fitted w . fmts)
      (lambda (st)
        (let* ((s (%capture-output st fmts))
               (slen (string-length s)))
          (if (> slen w)
              (%output-string st (substring s (- slen w) slen))
              (let ((needed (- w slen)))
                (%output-string (%output-string st (make-string needed (vector-ref st %idx-pad))) s))))))

    (define (fitted/right w . fmts)
      (lambda (st)
        (let* ((s (%capture-output st fmts))
               (slen (string-length s)))
          (if (> slen w)
              (%output-string st (substring s 0 w))
              (let ((needed (- w slen)))
                (%output-string (%output-string st s) (make-string needed (vector-ref st %idx-pad))))))))

    (define (fitted/both w . fmts)
      (lambda (st)
        (let* ((s (%capture-output st fmts))
               (slen (string-length s)))
          (if (> slen w)
              (let ((trim (- slen w)))
                (let ((left (quotient trim 2)))
                  (%output-string st (substring s left (+ left w)))))
              (let* ((needed (- w slen))
                     (left (quotient needed 2))
                     (right (- needed left)))
                (%output-string
                  (%output-string (%output-string st (make-string left (vector-ref st %idx-pad))) s)
                  (make-string right (vector-ref st %idx-pad))))))))

    ;;; State access

    (define (fn bindings . fmts)
      (lambda (st)
        (let ((bound (map (lambda (b)
                            (let ((idx (%var->idx (car b))))
                              (if idx (vector-ref st idx) #f)))
                          bindings)))
          (let loop ((bs bindings) (vs bound) (env '()))
            (if (null? bs)
                (let loop2 ((fs fmts) (st st))
                  (if (null? fs) st (loop2 (cdr fs) (%run-fmt st (car fs)))))
                (loop (cdr bs) (cdr vs)
                      (cons (cons (cadar bs) (car vs)) env)))))))

    (define (with bindings . fmts)
      (lambda (st)
        (let ((saved (%copy-state st)))
          (let apply-bindings ((bs bindings))
            (if (not (null? bs))
                (let ((idx (%var->idx (caar bs))))
                  (if idx (vector-set! st idx (cadar bs)))
                  (apply-bindings (cdr bs)))))
          (let loop ((fs fmts) (st st))
            (if (null? fs)
                (begin
                  (let restore ((i 0))
                    (when (< i %state-size)
                      (vector-set! st i (vector-ref saved i))
                      (restore (+ i 1))))
                  st)
                (loop (cdr fs) (%run-fmt st (car fs))))))))

    (define (with! . bindings)
      (lambda (st)
        (let loop ((bs bindings))
          (if (null? bs) st
              (let ((idx (%var->idx (car bs))))
                (if idx (vector-set! st idx (cadr bs)))
                (loop (cddr bs)))))))

    (define (call-with-output fmt proc)
      (lambda (st)
        (let ((s (%capture-output st (list fmt))))
          (%run-fmt st (proc s)))))

    (define (forked fmt1 fmt2)
      (lambda (st)
        (let ((st2 (%run-fmt (%copy-state st) fmt1)))
          (%run-fmt st fmt2))))

    ))
