;;; Final R7RS compliance gap tests
(import (scheme base) (scheme read) (scheme write) (scheme case-lambda)
        (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "final-gaps")

;; --- string->vector ---
(test-group "string->vector"
  (test-equal "string->vector full" #(#\a #\b #\c) (string->vector "abc"))
  (test-equal "string->vector with start/end" #(#\e #\l) (string->vector "hello" 1 3)))

;; --- bytevector ports ---
(test-group "bytevector ports"
  (test-eqv "read-u8 first byte"
    10
    (let ((p (open-input-bytevector #u8(10 20 30))))
      (read-u8 p)))
  (test-eqv "read-u8 second byte"
    20
    (let ((p (open-input-bytevector #u8(10 20 30))))
      (read-u8 p)
      (read-u8 p)))
  (test-eqv "read-u8 third byte"
    30
    (let ((p (open-input-bytevector #u8(10 20 30))))
      (read-u8 p)
      (read-u8 p)
      (read-u8 p)))
  (test-assert "read-u8 eof after last byte"
    (let ((p (open-input-bytevector #u8(10 20 30))))
      (read-u8 p)
      (read-u8 p)
      (read-u8 p)
      (eof-object? (read-u8 p))))
  (test-equal "open-output-bytevector / get-output-bytevector"
    #u8(1 2 3)
    (let ((out (open-output-bytevector)))
      (write-u8 1 out)
      (write-u8 2 out)
      (write-u8 3 out)
      (get-output-bytevector out)))
  (test-eqv "read-bytevector! count"
    3
    (let ((bv (make-bytevector 3))
          (p (open-input-bytevector #u8(10 20 30))))
      (read-bytevector! bv p)))
  (test-equal "read-bytevector! contents"
    #u8(10 20 30)
    (let ((bv (make-bytevector 3))
          (p (open-input-bytevector #u8(10 20 30))))
      (read-bytevector! bv p)
      bv))
  (test-assert "read-bytevector! at EOF"
    (let ((bv (make-bytevector 5))
          (p (open-input-bytevector #u8())))
      (eof-object? (read-bytevector! bv p)))))

;; --- case-lambda import ---
(test-assert "case-lambda import succeeded" #t)

;; --- fold-case / no-fold-case ---
(test-group "fold-case"
  (test-assert "fold-case makes FOO eq? to foo"
    (let ((p (open-input-string "#!fold-case FOO")))
      (let ((sym (read p)))
        (eq? sym (quote foo)))))
  (test-equal "no-fold-case restores case sensitivity"
    (list #t #t)
    (let ((p (open-input-string "#!fold-case ABC #!no-fold-case DEF")))
      (let ((s1 (read p))
            (s2 (read p)))
        (list (eq? s1 (quote abc))
              (eq? s2 (quote DEF)))))))

;; --- equal? on circular structures ---
(define a (list 1 2 3))
(set-cdr! (cddr a) a)
(define b (list 1 2 3))
(set-cdr! (cddr b) b)
(define c (list 1))
(set-cdr! c c)

(test-group "circular equal?"
  (test-assert "equal? on two circular lists" (equal? a b))
  (test-assert "equal? on self-referencing pair" (equal? c c)))

;; --- datum labels ---
(test-group "datum labels"
  (test-equal "datum label basic" '(a b) '#0=(a b))
  (test-equal "datum label shared number" '(42 42) '(#0=42 #0#))
  (test-equal "datum label shared list" '((x y) (x y)) '(#0=(x y) #0#)))

;; --- write-shared ---
(define circ (list 1 2))
(set-cdr! (cdr circ) circ)
(define sh (list 99))

(test-group "write-shared"
  (test-equal "write-shared non-shared list"
    "(1 2 3)"
    (let ((p (open-output-string)))
      (write-shared '(1 2 3) p)
      (get-output-string p)))
  (test-equal "write-shared circular list"
    "#0=(1 2 . #0#)"
    (let ((p (open-output-string)))
      (write-shared circ p)
      (get-output-string p)))
  (test-equal "write-shared shared substructure"
    "(#0=(99) #0#)"
    (let ((p (open-output-string)))
      (write-shared (list sh sh) p)
      (get-output-string p))))

;; --- nested quasiquote ---
(test-group "nested quasiquote"
  (test-equal "nested quasiquote literal inner"
    "(a (quasiquote (b (unquote (+ 1 2)))))"
    (let ((p (open-output-string)))
      (write `(a `(b ,(+ 1 2))) p)
      (get-output-string p)))
  (test-equal "nested quasiquote with splice"
    "(a (quasiquote (b (unquote 1))))"
    (let ((p (open-output-string)))
      (write (let ((x 1)) `(a `(b ,,x))) p)
      (get-output-string p))))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "final-gaps")
(if (> %test-fail-count 0) (exit 1))
