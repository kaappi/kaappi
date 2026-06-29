;; Regression tests for expander fixes
;; #309: flonum datum patterns in syntax-rules
;; #308: ellipsis escape hygiene

(import (scheme base) (scheme write))

;; ---- #309: Flonum datum patterns ----

(define-syntax check-pi
  (syntax-rules ()
    ((check-pi 3.14) 'pi)
    ((check-pi _) 'other)))

(display (check-pi 3.14))    ; pi
(newline)
(display (check-pi 2.71))    ; other
(newline)
(display (check-pi 42))      ; other
(newline)

;; Integer datum patterns still work
(define-syntax check-zero
  (syntax-rules ()
    ((check-zero 0) 'zero)
    ((check-zero _) 'nonzero)))

(display (check-zero 0))     ; zero
(newline)
(display (check-zero 1))     ; nonzero
(newline)

;; ---- #308: Ellipsis escape hygiene ----

;; The template-introduced variable 't' inside (... ...) should be
;; renamed for hygiene and not conflict with outer 't'.
(define-syntax my-or
  (syntax-rules ()
    ((my-or a b)
     (... (let ((t a)) (if t t b))))))

(let ((t 42))
  (display (my-or #f t))      ; 42 (not shadowed by hygienic 't')
  (newline))

(display (my-or 1 2))         ; 1
(newline)
(display (my-or #f 99))       ; 99
(newline)

(display "all passed")
(newline)
