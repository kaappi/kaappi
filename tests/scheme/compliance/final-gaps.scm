;;; Final R7RS compliance gap tests

;; string->vector
(display (string->vector "abc"))           ; => #(#\a #\b #\c)
(newline)
(display (string->vector "hello" 1 3))     ; => #(#\e #\l)
(newline)

;; Bytevector ports: open-input-bytevector / read-u8
(let ((p (open-input-bytevector #u8(10 20 30))))
  (display (read-u8 p))                    ; => 10
  (display " ")
  (display (read-u8 p))                    ; => 20
  (display " ")
  (display (read-u8 p))                    ; => 30
  (display " ")
  (display (eof-object? (read-u8 p))))     ; => #t
(newline)

;; open-output-bytevector / get-output-bytevector
(let ((out (open-output-bytevector)))
  (write-u8 1 out)
  (write-u8 2 out)
  (write-u8 3 out)
  (display (get-output-bytevector out)))    ; => #u8(1 2 3)
(newline)

;; read-bytevector!
(let ((bv (make-bytevector 3))
      (p2 (open-input-bytevector #u8(10 20 30))))
  (display (read-bytevector! bv p2))       ; => 3
  (display " ")
  (display bv))                            ; => #u8(10 20 30)
(newline)

;; read-bytevector! at EOF
(let ((bv (make-bytevector 5))
      (p (open-input-bytevector #u8())))
  (display (eof-object? (read-bytevector! bv p))))  ; => #t
(newline)

;; (scheme case-lambda) import
(import (scheme case-lambda))
(display "case-lambda-ok")
(newline)

;;; --- Gap 1: #!fold-case / #!no-fold-case ---

;; fold-case: FOO and foo become the same symbol
(display (let ((p (open-input-string "#!fold-case FOO")))
           (let ((sym (read p)))
             (eq? sym (quote foo)))))     ; => #t
(newline)

;; no-fold-case restores case sensitivity
(display (let ((p (open-input-string "#!fold-case ABC #!no-fold-case DEF")))
           (let ((s1 (read p))
                 (s2 (read p)))
             (list (eq? s1 (quote abc))
                   (eq? s2 (quote DEF))))))  ; => (#t #t)
(newline)

;;; --- Gap 2: equal? on circular structures ---

(define a (list 1 2 3))
(set-cdr! (cddr a) a)
(define b (list 1 2 3))
(set-cdr! (cddr b) b)
(display (equal? a b))                   ; => #t
(newline)

;; Self-referencing pair
(define c (list 1))
(set-cdr! c c)
(display (equal? c c))                   ; => #t
(newline)

;;; --- Gap 3: Datum labels ---

(display '#0=(a b))                      ; => (a b)
(newline)
(display '(#0=42 #0#))                   ; => (42 42)
(newline)
(display '(#0=(x y) #0#))               ; => ((x y) (x y))
(newline)

;;; --- Gap 4: write-shared ---

(import (scheme write))

;; Non-shared list: no labels
(write-shared '(1 2 3))                  ; => (1 2 3)
(newline)

;; Circular list
(define circ (list 1 2))
(set-cdr! (cdr circ) circ)
(write-shared circ)                      ; => #0=(1 2 . #0#)
(newline)

;; Shared substructure
(define sh (list 99))
(write-shared (list sh sh))             ; => (#0=(99) #0#)
(newline)

;;; --- Gap 5: Nested quasiquote ---

(display `(a `(b ,(+ 1 2))))
(newline)
;; => (a (quasiquote (b (unquote (+ 1 2)))))

(display (let ((x 1)) `(a `(b ,,x))))
(newline)
;; => (a (quasiquote (b (unquote 1))))
