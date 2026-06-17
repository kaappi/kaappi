;; large-files.scm — Find source files that may need refactoring
;;
;; Usage: find src -name '*.zig' -exec wc -l {} \; | sort -rn | \
;;        zig build run -- scripts/large-files.scm

(import (scheme base) (scheme write))

(define threshold 800)

;; Read "  NNN path" lines from stdin
(define (read-entries)
  (define (find-space s i)
    (if (>= i (string-length s)) #f
        (if (char=? (string-ref s i) #\space) i
            (find-space s (+ i 1)))))
  (define (skip-spaces s i)
    (if (>= i (string-length s)) i
        (if (char=? (string-ref s i) #\space) (skip-spaces s (+ i 1))
            i)))
  (define (parse-line line)
    (let ((start (skip-spaces line 0)))
      (if (>= start (string-length line)) #f
          (let ((sp (find-space line start)))
            (if (not sp) #f
                (let ((num (string->number (substring line start sp)))
                      (file (substring line (skip-spaces line sp) (string-length line))))
                  (if num (cons num file) #f)))))))
  (define (go result)
    (let ((line (read-line)))
      (if (eof-object? line)
          (reverse result)
          (let ((entry (parse-line line)))
            (go (if entry (cons entry result) result))))))
  (go '()))

(define entries (read-entries))

(define (pad-left s w)
  (if (>= (string-length s) w) s
      (string-append (make-string (- w (string-length s)) #\space) s)))

(define (pad-right s w)
  (if (>= (string-length s) w) s
      (string-append s (make-string (- w (string-length s)) #\space))))

;; Display
(display "Kaappi source file sizes (threshold: ")
(display threshold)
(display " lines)")
(newline)
(newline)

(define max-n (if (null? entries) 0 (car (car entries))))

(define (show-entry entry)
  (let ((n (car entry)) (f (cdr entry)))
    (if (>= n threshold)
        (begin
          (display "  ")
          (display (pad-left (number->string n) 5))
          (display "  ")
          (display (pad-right f 42))
          (if (> max-n 0)
              (display (make-string (quotient (* n 30) max-n) #\#)))
          (newline)))))

(define (show-all lst)
  (if (not (null? lst))
      (begin (show-entry (car lst))
             (show-all (cdr lst)))))

(show-all entries)
(newline)

(define (sum-all lst s)
  (if (null? lst) s (sum-all (cdr lst) (+ s (car (car lst))))))

(display "  Total: ")
(display (sum-all entries 0))
(display " lines across ")
(display (length entries))
(display " files")
(newline)
(if (> (length entries) 0)
    (begin
      (display "  Average: ")
      (display (quotient (sum-all entries 0) (length entries)))
      (display " lines/file")
      (newline)))
