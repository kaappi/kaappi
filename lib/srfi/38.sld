;;; SRFI 38 — External Representation for Data With Shared Structure
;;; write-with-shared-structure / read-with-shared-structure
;;; Simplified: write/read with #n= / #n# datum labels
(define-library (srfi 38)
  (import (scheme base) (scheme write))
  (export write-with-shared-structure
          read-with-shared-structure)
  (begin

    ;; write-with-shared-structure detects shared/cyclic structure
    ;; and uses #n= / #n# labels. Simplified version: delegates to
    ;; write for non-shared data, detects simple sharing.
    (define (write-with-shared-structure obj . args)
      (let ((port (if (pair? args) (car args) (current-output-port))))
        (let ((seen (make-seen))
              (labels (make-labels)))
          ;; Pass 1: find shared objects
          (scan obj seen labels)
          ;; Pass 2: write with labels
          (write-shared obj port labels (make-emitted)))))

    (define (make-seen) (list (cons 'table '())))
    (define (make-labels) (list (cons 'table '()) (cons 'counter 0)))
    (define (make-emitted) (list (cons 'table '())))

    (define (seen-add! seen obj)
      (let ((tbl (cdr (car seen))))
        (set-cdr! (car seen) (cons (cons obj 1) tbl))))

    (define (seen-count seen obj)
      (let loop ((tbl (cdr (car seen))))
        (cond
          ((null? tbl) 0)
          ((eq? obj (caar tbl)) (cdar tbl))
          (else (loop (cdr tbl))))))

    (define (seen-inc! seen obj)
      (let loop ((tbl (cdr (car seen))))
        (when (pair? tbl)
          (when (eq? obj (caar tbl))
            (set-cdr! (car tbl) (+ (cdar tbl) 1)))
          (loop (cdr tbl)))))

    (define (label-for labels obj)
      (let loop ((tbl (cdr (car labels))))
        (cond
          ((null? tbl) #f)
          ((eq? obj (caar tbl)) (cdar tbl))
          (else (loop (cdr tbl))))))

    (define (label-assign! labels obj)
      (let ((n (cdr (cadr labels))))
        (set-cdr! (cadr labels) (+ n 1))
        (set-cdr! (car labels)
                  (cons (cons obj n) (cdr (car labels))))
        n))

    (define (emitted? emitted obj)
      (let loop ((tbl (cdr (car emitted))))
        (cond
          ((null? tbl) #f)
          ((eq? obj (car tbl)) #t)
          (else (loop (cdr tbl))))))

    (define (emitted-add! emitted obj)
      (set-cdr! (car emitted) (cons obj (cdr (car emitted)))))

    (define (scan obj seen labels)
      (when (pair? obj)
        (let ((count (seen-count seen obj)))
          (cond
            ((= count 0)
             (seen-add! seen obj)
             (scan (car obj) seen labels)
             (scan (cdr obj) seen labels))
            ((= count 1)
             (seen-inc! seen obj)
             (label-assign! labels obj))))))

    (define (write-shared obj port labels emitted)
      (cond
        ((pair? obj)
         (let ((lbl (label-for labels obj)))
           (cond
             ((and lbl (emitted? emitted obj))
              (write-char #\# port)
              (write (cdr (assq obj (cdr (car labels)))) port)
              (write-char #\# port))
             (lbl
              (emitted-add! emitted obj)
              (write-char #\# port)
              (write lbl port)
              (write-char #\= port)
              (write-pair obj port labels emitted))
             (else (write-pair obj port labels emitted)))))
        (else (write obj port))))

    (define (write-pair obj port labels emitted)
      (write-char #\( port)
      (write-shared (car obj) port labels emitted)
      (let loop ((rest (cdr obj)))
        (cond
          ((null? rest)
           (write-char #\) port))
          ((pair? rest)
           (let ((lbl (label-for labels rest)))
             (if (and lbl (emitted? emitted rest))
                 (begin
                   (write-string " . " port)
                   (write-char #\# port)
                   (write lbl port)
                   (write-char #\# port)
                   (write-char #\) port))
                 (begin
                   (when lbl
                     (emitted-add! emitted rest))
                   (write-char #\space port)
                   (write-shared (car rest) port labels emitted)
                   (loop (cdr rest))))))
          (else
           (write-string " . " port)
           (write-shared rest port labels emitted)
           (write-char #\) port)))))

    ;; read-with-shared-structure: for now, delegate to standard read
    (define (read-with-shared-structure . args)
      (let ((port (if (pair? args) (car args) (current-input-port))))
        (read port)))))
