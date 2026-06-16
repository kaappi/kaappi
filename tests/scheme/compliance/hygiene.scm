;;; Hygienic macros compliance tests
;;; Tests that syntax-rules macros correctly prevent variable capture.

;; --------------------------------------------------------------------------
;; 1. Classic or/my-or hygiene: macro's internal 'temp' must not capture
;;    a user variable also called 'temp'.
;; --------------------------------------------------------------------------

(define-syntax my-or
  (syntax-rules ()
    ((my-or) #f)
    ((my-or e) e)
    ((my-or e1 e2 ...)
     (let ((temp e1))
       (if temp temp (my-or e2 ...))))))

;; Basic my-or functionality
(display (my-or))           ; => #f
(newline)
(display (my-or 1))         ; => 1
(newline)
(display (my-or #f 2))      ; => 2
(newline)
(display (my-or 1 2))       ; => 1
(newline)
(display (my-or #f #f 3))   ; => 3
(newline)

;; KEY HYGIENE TEST: user's 'temp' must not be captured by macro's 'temp'
(let ((temp 42))
  (display (my-or #f temp)))  ; => 42 (NOT #f)
(newline)

;; Another capture test: temp is the truthy value
(let ((temp 99))
  (display (my-or temp 0)))   ; => 99
(newline)

;; --------------------------------------------------------------------------
;; 2. swap! hygiene: macro's internal 'tmp' must not capture user's 'tmp'.
;; --------------------------------------------------------------------------

(define-syntax swap!
  (syntax-rules ()
    ((swap! a b)
     (let ((tmp a))
       (set! a b)
       (set! b tmp)))))

;; Basic swap with distinct names
(define x 10)
(define y 20)
(swap! x y)
(display x)  ; => 20
(newline)
(display y)  ; => 10
(newline)

;; KEY HYGIENE TEST: swap variables named 'tmp' and 'y'
(let ((tmp 1) (y 2))
  (swap! tmp y)
  (display (list tmp y)))  ; => (2 1)
(newline)

;; --------------------------------------------------------------------------
;; 3. Nested macro expansions with hygiene
;; --------------------------------------------------------------------------

;; Using my-or inside my-or (via recursive expansion)
(display (my-or #f #f #f 77))  ; => 77
(newline)

;; Nested let with same name as macro internal
(let ((temp 100))
  (display (my-or #f (my-or #f temp))))  ; => 100
(newline)

;; --------------------------------------------------------------------------
;; 4. Multiple macro invocations don't interfere
;; --------------------------------------------------------------------------

;; Each invocation of my-or should get its own gensym for 'temp'
(let ((temp 10))
  (let ((a (my-or #f temp))
        (b (my-or temp #f)))
    (display (list a b))))  ; => (10 10)
(newline)

;; --------------------------------------------------------------------------
;; 5. Macros that don't introduce bindings work unchanged
;; --------------------------------------------------------------------------

(define-syntax my-if
  (syntax-rules ()
    ((my-if test then else)
     (if test then else))))

(display (my-if #t 1 2))  ; => 1
(newline)
(display (my-if #f 1 2))  ; => 2
(newline)

;; --------------------------------------------------------------------------
;; 6. Macros with literals still work
;; --------------------------------------------------------------------------

(define-syntax my-case
  (syntax-rules (is)
    ((my-case x is y)
     (if (= x y) #t #f))))

(display (my-case 3 is 3))  ; => #t
(newline)
(display (my-case 3 is 4))  ; => #f
(newline)

;; --------------------------------------------------------------------------
;; 7. Ellipsis-based macros still work
;; --------------------------------------------------------------------------

(define-syntax my-list
  (syntax-rules ()
    ((my-list e ...)
     (list e ...))))

(display (my-list 1 2 3))  ; => (1 2 3)
(newline)

(define-syntax my-begin
  (syntax-rules ()
    ((my-begin e1 e2 ...)
     (begin e1 e2 ...))))

(display (my-begin 1 2 3))  ; => 3
(newline)
