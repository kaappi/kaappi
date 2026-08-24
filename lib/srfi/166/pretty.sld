(define-library (srfi 166 pretty)
  (import (scheme base) (scheme write) (srfi 166 base))
  (export pretty pretty-shared pretty-simply pretty-with-color)
  (begin

    ;; Pretty-print obj to a string: if the flat written form fits in `width`
    ;; columns, use it unchanged; otherwise break the structure across lines so
    ;; no line exceeds width.  `writer` supplies the flat form (written /
    ;; written-shared / written-simply), which also handles datum labels for
    ;; shared and cyclic structure.
    (define (%pp obj width sw writer)
      (let ((flat (writer obj)))
        (if (<= (sw flat) width)
            flat
            (%break obj width sw writer))))

    (define (%break obj width sw writer)
      (let ((out (open-output-string)))
        (let loop ((obj obj) (indent 0))
          (cond
            ((pair? obj)
             (let ((flat (writer obj)))
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
             (let ((flat (writer obj)))
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
             (display (show #f (written obj)) out))))
        (get-output-string out)))

    (define (pretty obj)
      (fn (width string-width)
        (displayed (%pp obj width string-width (lambda (o) (show #f (written o)))))))

    (define (pretty-shared obj)
      (fn (width string-width)
        (displayed (%pp obj width string-width (lambda (o) (show #f (written-shared o)))))))

    (define (pretty-simply obj)
      (fn (width string-width)
        (displayed (%pp obj width string-width (lambda (o) (show #f (written-simply o)))))))

    ;; Syntax highlighting is optional per the spec; without it this is
    ;; equivalent to pretty.
    (define pretty-with-color pretty)

    ))
