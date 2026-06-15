;;; Phase 5: Hygienic Macros Tests

;; 1. Simple alias macro
(define-syntax my-if
  (syntax-rules ()
    ((my-if test then else)
     (if test then else))))

(display (my-if #t 1 2))  ; => 1
(newline)
(display (my-if #f 1 2))  ; => 2
(newline)

;; 2. Constant macro
(define-syntax my-const
  (syntax-rules ()
    ((my-const) 42)))

(display (my-const))  ; => 42
(newline)

;; 3. Ellipsis
(define-syntax my-begin
  (syntax-rules ()
    ((my-begin e1 e2 ...)
     (begin e1 e2 ...))))

(display (my-begin 1 2 3))  ; => 3
(newline)

;; 4. my-list using ellipsis
(define-syntax my-list
  (syntax-rules ()
    ((my-list e ...)
     (list e ...))))

(display (my-list 1 2 3))  ; => (1 2 3)
(newline)

;; 5. Multiple rules
(define-syntax my-and
  (syntax-rules ()
    ((my-and) #t)
    ((my-and x) x)
    ((my-and x y) (if x y #f))))

(display (my-and))       ; => #t
(newline)
(display (my-and 5))     ; => 5
(newline)
(display (my-and 2 3))   ; => 3
(newline)
(display (my-and #f 3))  ; => #f
(newline)

;; 6. Literals
(define-syntax my-case
  (syntax-rules (is)
    ((my-case x is y)
     (if (= x y) #t #f))))

(display (my-case 3 is 3))  ; => #t
(newline)
(display (my-case 3 is 4))  ; => #f
(newline)

;; 7. let-syntax
(display
  (let-syntax ((my-const (syntax-rules () ((my-const) 99))))
    (my-const)))  ; => 99
(newline)

;; 8. swap macro
(define-syntax my-swap
  (syntax-rules ()
    ((my-swap a b)
     (let ((tmp a))
       (set! a b)
       (set! b tmp)))))

(define x 10)
(define y 20)
(my-swap x y)
(display x)  ; => 20
(newline)
(display y)  ; => 10
(newline)

;; 9. Underscore wildcard
(define-syntax second
  (syntax-rules ()
    ((second _ x) x)))

(display (second 1 2))  ; => 2
(newline)

;; 10. Zero ellipsis matches
(display (my-begin 42))  ; => 42
(newline)
