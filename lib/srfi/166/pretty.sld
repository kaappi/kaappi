(define-library (srfi 166 pretty)
  (import (scheme base) (scheme write) (srfi 69) (srfi 166 base))
  (export pretty pretty-shared pretty-simply pretty-with-color)
  (begin

    ;; Pretty-print obj to a string: if the flat written form fits in `width`
    ;; columns, use it unchanged; otherwise break the structure across lines so
    ;; no line exceeds width.  Numbers are formatted with the current
    ;; radix/precision so the result matches `written` (modulo whitespace).
    ;;
    ;; Shared or cyclic data is never broken: a manual break cannot preserve
    ;; the datum labels, and iterating a cyclic pair would not terminate.  Such
    ;; data is emitted flat (with its labels) even if it overflows the width.
    (define (%pp obj width sw radix precision shares)
      (let ((flat (%write-flat obj shares radix precision)))
        (if (<= (sw flat) width)
            flat
            (if (positive? (hash-table-size (car (extract-shared-objects obj #f))))
                flat
                (%break obj width sw radix precision)))))

    (define (%break obj width sw radix precision)
      (let ((out (open-output-string)))
        (let loop ((obj obj) (indent 0))
          (cond
            ((pair? obj)
             (let ((flat (%write-flat obj (extract-shared-objects #f #f) radix precision)))
               (if (<= (+ indent (sw flat)) width)
                   (display flat out)
                   (begin
                     (display "(" out)
                     (let lp ((ls obj) (first #t))
                       (cond
                         ((pair? ls)
                          (if first
                              (loop (car ls) (+ indent 1))
                              (begin
                                (newline out)
                                (display (make-string (+ indent 1) #\space) out)
                                (loop (car ls) (+ indent 1))))
                          (lp (cdr ls) #f))
                         ((null? ls))
                         (else
                          (newline out)
                          (display (make-string (+ indent 1) #\space) out)
                          (display ". " out)
                          (loop ls (+ indent 1)))))
                     (display ")" out)))))
            ((vector? obj)
             (let ((flat (%write-flat obj (extract-shared-objects #f #f) radix precision)))
               (if (<= (+ indent (sw flat)) width)
                   (display flat out)
                   (begin
                     (display "#(" out)
                     (let ((len (vector-length obj)))
                       (do ((i 0 (+ i 1)))
                           ((= i len))
                         (if (positive? i)
                             (begin
                               (newline out)
                               (display (make-string (+ indent 2) #\space) out)))
                         (loop (vector-ref obj i) (+ indent 2))))
                     (display ")" out)))))
            (else
             (display (%write-flat obj (extract-shared-objects #f #f) radix precision) out))))
        (get-output-string out)))

    (define (pretty obj)
      (fn (width string-width radix precision)
        (displayed (%pp obj width string-width radix precision
                        (extract-shared-objects obj #t)))))

    (define (pretty-shared obj)
      (fn (width string-width radix precision)
        (displayed (%pp obj width string-width radix precision
                        (extract-shared-objects obj #f)))))

    (define (pretty-simply obj)
      (fn (width string-width radix precision)
        (displayed (%pp obj width string-width radix precision
                        (extract-shared-objects #f #f)))))

    ;; Syntax highlighting is optional per the spec; without it this is
    ;; equivalent to pretty.
    (define pretty-with-color pretty)

    ))
