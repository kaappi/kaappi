;; large-files.scm — Find source files that may need refactoring
;;
;; Usage: zig build run -- scripts/large-files.scm [dir [ext]]
;;
;; Recursively walks a directory (default: src/) and reports line counts
;; for files matching the given extension (default: .zig).

(import (scheme base) (scheme write) (scheme file)
        (scheme process-context)
        (srfi 1) (srfi 170))

(define threshold 800)

(define cl (command-line))

(define scan-dir
  (if (>= (length cl) 3) (list-ref cl 2) "src"))

(define scan-ext
  (if (>= (length cl) 4) (list-ref cl 3) ".zig"))

(define (count-lines filename)
  (if (file-exists? filename)
      (let ((port (open-input-file filename)))
        (define (go n)
          (if (eof-object? (read-line port)) n (go (+ n 1))))
        (let ((n (go 0)))
          (close-input-port port)
          n))
      0))

(define (has-ext? name ext)
  (let ((nlen (string-length name))
        (elen (string-length ext)))
    (and (> nlen elen)
         (string=? (substring name (- nlen elen) nlen) ext))))

(define (find-files dir ext)
  (let ((entries (directory-files dir)))
    (fold (lambda (name acc)
            (let ((path (string-append dir "/" name)))
              (if (file-info-directory? (file-info path))
                  (append (find-files path ext) acc)
                  (if (has-ext? name ext)
                      (cons path acc)
                      acc))))
          '()
          entries)))

(define known-source-files (find-files scan-dir scan-ext))

(define (pad-left s w)
  (if (>= (string-length s) w) s
      (string-append (make-string (- w (string-length s)) #\space) s)))

(define (pad-right s w)
  (if (>= (string-length s) w) s
      (string-append s (make-string (- w (string-length s)) #\space))))

;; Gather sizes
(define (gather files)
  (if (null? files) '()
      (let ((n (count-lines (car files)))
            (rest (gather (cdr files))))
        (if (> n 0) (cons (cons n (car files)) rest) rest))))

(define file-sizes (gather known-source-files))

;; Sort descending
(define (insert-sorted entry sorted)
  (if (null? sorted) (list entry)
      (if (>= (car entry) (car (car sorted)))
          (cons entry sorted)
          (cons (car sorted) (insert-sorted entry (cdr sorted))))))

(define (sort-desc entries)
  (if (null? entries) '()
      (insert-sorted (car entries) (sort-desc (cdr entries)))))

(define sorted (sort-desc file-sizes))

;; Display
(display "Kaappi source file sizes (threshold: ")
(display threshold)
(display " lines)")
(newline)
(newline)

(define max-n (if (null? sorted) 0 (car (car sorted))))

(define (show entries)
  (if (not (null? entries))
      (let ((n (car (car entries)))
            (f (cdr (car entries))))
        (if (>= n threshold)
            (begin
              (display "  ")
              (display (pad-left (number->string n) 5))
              (display "  ")
              (display (pad-right f 42))
              (if (> max-n 0)
                  (display (make-string (quotient (* n 30) max-n) #\#)))
              (newline)))
        (show (cdr entries)))))

(show sorted)
(newline)

(define (sum-all lst s)
  (if (null? lst) s (sum-all (cdr lst) (+ s (car (car lst))))))

(display "  Total: ")
(display (sum-all file-sizes 0))
(display " lines across ")
(display (length file-sizes))
(display " files")
(newline)
(display "  Average: ")
(display (quotient (sum-all file-sizes 0) (length file-sizes)))
(display " lines/file")
(newline)
