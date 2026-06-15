;;; R7RS List compliance tests

;; caar, cadr, cdar, cddr
(display (caar '((1 2) 3))) (newline)            ; => 1
(display (cadr '(1 2 3))) (newline)              ; => 2
(display (cdar '((1 2) 3))) (newline)            ; => (2)
(display (cddr '(1 2 3))) (newline)              ; => (3)

;; list-ref
(display (list-ref '(a b c d) 0)) (newline)     ; => a
(display (list-ref '(a b c d) 2)) (newline)     ; => c
(display (list-ref '(a b c d) 3)) (newline)     ; => d

;; list-tail
(display (list-tail '(a b c d) 0)) (newline)    ; => (a b c d)
(display (list-tail '(a b c d) 2)) (newline)    ; => (c d)
(display (list-tail '(a b c d) 4)) (newline)    ; => ()

;; list-set!
(define ls (list 1 2 3))
(list-set! ls 1 99)
(display ls) (newline)                            ; => (1 99 3)

;; list-copy
(define original (list 1 2 3))
(define copy (list-copy original))
(display copy) (newline)                          ; => (1 2 3)
(list-set! copy 0 99)
(display original) (newline)                      ; => (1 2 3)
(display copy) (newline)                          ; => (99 2 3)

;; make-list
(display (make-list 3 0)) (newline)              ; => (0 0 0)
(display (make-list 0)) (newline)                ; => ()

;; member (uses equal?)
(display (member 3 '(1 2 3 4 5))) (newline)      ; => (3 4 5)
(display (member 6 '(1 2 3 4 5))) (newline)      ; => #f
(display (member '(b) '((a) (b) (c)))) (newline) ; => ((b) (c))

;; memq (uses eq?)
(display (memq 'b '(a b c))) (newline)           ; => (b c)
(display (memq 'd '(a b c))) (newline)           ; => #f

;; memv (uses eqv?)
(display (memv 2 '(1 2 3))) (newline)            ; => (2 3)
(display (memv 4 '(1 2 3))) (newline)            ; => #f

;; assoc (uses equal?)
(display (assoc 'b '((a 1) (b 2) (c 3)))) (newline)  ; => (b 2)
(display (assoc 'd '((a 1) (b 2) (c 3)))) (newline)  ; => #f

;; assq (uses eq?)
(display (assq 'b '((a 1) (b 2) (c 3)))) (newline)   ; => (b 2)
(display (assq 'd '((a 1) (b 2) (c 3)))) (newline)   ; => #f

;; assv (uses eqv?)
(display (assv 2 '((1 a) (2 b) (3 c)))) (newline)    ; => (2 b)
(display (assv 4 '((1 a) (2 b) (3 c)))) (newline)    ; => #f

;; boolean=?
(display (boolean=? #t #t)) (newline)            ; => #t
(display (boolean=? #f #f)) (newline)            ; => #t
(display (boolean=? #t #f)) (newline)            ; => #f
(display (boolean=? #t #t #t)) (newline)         ; => #t

;; symbol=?
(display (symbol=? 'foo 'foo)) (newline)         ; => #t
(display (symbol=? 'foo 'bar)) (newline)         ; => #f

;; map — single list
(display (map car '((1 2) (3 4) (5 6)))) (newline)  ; => (1 3 5)
(display (map (lambda (x) (* x x)) '(1 2 3))) (newline)  ; => (1 4 9)

;; map — multiple lists
(display (map + '(1 2 3) '(10 20 30))) (newline)    ; => (11 22 33)

;; map — empty list
(display (map car '())) (newline)                    ; => ()

;; for-each
(define result '())
(for-each (lambda (x) (set! result (cons x result))) '(1 2 3))
(display (reverse result)) (newline)                 ; => (1 2 3)

;; for-each — multiple lists
(define sum 0)
(for-each (lambda (a b) (set! sum (+ sum a b))) '(1 2 3) '(10 20 30))
(display sum) (newline)                              ; => 66
