;; large-files.scm — Find source files that may need refactoring
;;
;; Usage: zig build run -- scripts/large-files.scm
;;
;; Reads source files directly and reports line counts.

(import (scheme base) (scheme write) (scheme file))

(define threshold 800)

(define (count-lines filename)
  (if (file-exists? filename)
      (let ((port (open-input-file filename)))
        (define (go n)
          (if (eof-object? (read-line port)) n (go (+ n 1))))
        (let ((n (go 0)))
          (close-input-port port)
          n))
      0))

(define known-source-files
  '("src/vm.zig" "src/compiler.zig" "src/reader.zig" "src/memory.zig"
    "src/types.zig" "src/expander.zig" "src/printer.zig" "src/library.zig"
    "src/main.zig" "src/bignum.zig" "src/bytecode_file.zig"
    "src/primitives.zig" "src/primitives_arithmetic.zig"
    "src/primitives_numeric.zig" "src/primitives_string.zig"
    "src/primitives_char.zig" "src/primitives_vector.zig"
    "src/primitives_bytevector.zig" "src/primitives_io.zig"
    "src/primitives_control.zig" "src/primitives_lazy.zig"
    "src/primitives_cxr.zig" "src/primitives_r7rs.zig"
    "src/primitives_srfi1.zig" "src/primitives_hashtable.zig"
    "src/compiler_conditionals.zig" "src/compiler_bindings.zig"
    "src/compiler_advanced.zig" "src/compiler_forms.zig"
    "src/vm_library.zig" "src/vm_records.zig"
    "src/vm_continuations.zig" "src/vm_debug.zig"
    "src/reader_datum.zig" "src/testing_helpers.zig"))

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
