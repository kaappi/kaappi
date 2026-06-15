;;; R7RS Vector compliance tests

;; Vector literals
(display #(1 2 3)) (newline)                 ; => #(1 2 3)
(display #()) (newline)                       ; => #()
(display #(a b c)) (newline)                  ; => #(a b c)

;; vector? predicate
(display (vector? #(1 2 3))) (newline)        ; => #t
(display (vector? '(1 2 3))) (newline)        ; => #f
(display (vector? 42)) (newline)              ; => #f

;; vector constructor
(display (vector 1 2 3)) (newline)            ; => #(1 2 3)
(display (vector)) (newline)                  ; => #()
(display (vector 'a 'b 'c)) (newline)         ; => #(a b c)

;; make-vector
(display (make-vector 3 0)) (newline)         ; => #(0 0 0)
(display (make-vector 0)) (newline)           ; => #()

;; vector-length
(display (vector-length #(1 2 3))) (newline)  ; => 3
(display (vector-length #())) (newline)       ; => 0

;; vector-ref
(display (vector-ref #(a b c) 0)) (newline)  ; => a
(display (vector-ref #(a b c) 1)) (newline)  ; => b
(display (vector-ref #(a b c) 2)) (newline)  ; => c

;; vector-set!
(define v (vector 1 2 3))
(vector-set! v 1 99)
(display v) (newline)                         ; => #(1 99 3)

;; vector->list
(display (vector->list #(a b c))) (newline)         ; => (a b c)
(display (vector->list #(a b c d e) 1 3)) (newline) ; => (b c)

;; list->vector
(display (list->vector '(1 2 3))) (newline)   ; => #(1 2 3)
(display (list->vector '())) (newline)        ; => #()

;; vector-fill!
(define v2 (make-vector 4 0))
(vector-fill! v2 7)
(display v2) (newline)                        ; => #(7 7 7 7)

;; vector-copy
(display (vector-copy #(a b c d e))) (newline)      ; => #(a b c d e)
(display (vector-copy #(a b c d e) 1 3)) (newline)  ; => #(b c)

;; vector-copy!
(define to (vector 1 2 3 4 5))
(vector-copy! to 1 #(10 20 30))
(display to) (newline)                        ; => #(1 10 20 30 5)

;; vector-append
(display (vector-append #(1 2) #(3 4))) (newline)     ; => #(1 2 3 4)
(display (vector-append #(1) #(2) #(3))) (newline)    ; => #(1 2 3)
(display (vector-append)) (newline)                    ; => #()

;; vector-map
(display (vector-map (lambda (x) (* x x)) #(1 2 3 4))) (newline)  ; => #(1 4 9 16)
(display (vector-map + #(1 2 3) #(10 20 30))) (newline)            ; => #(11 22 33)

;; vector-for-each
(define sum 0)
(vector-for-each (lambda (x) (set! sum (+ sum x))) #(1 2 3 4 5))
(display sum) (newline)                       ; => 15

;; vector->string
(display (vector->string #(#\h #\e #\l #\l #\o))) (newline)  ; => hello

;; equal? on vectors
(display (equal? #(1 2 3) #(1 2 3))) (newline)  ; => #t
(display (equal? #(1 2 3) #(1 2 4))) (newline)  ; => #f
(display (equal? #() #())) (newline)              ; => #t
