;;; SRFI 17 — Generalized set!
(define-library (srfi 17)
  (import (scheme base) (scheme cxr))
  (export setter getter-with-setter)
  (begin

    (define setters
      (list
        (cons car   set-car!)
        (cons cdr   set-cdr!)
        (cons vector-ref vector-set!)
        (cons string-ref string-set!)
        ;; 2-deep compositions
        (cons caar  (lambda (p v) (set-car! (car p) v)))
        (cons cadr  (lambda (p v) (set-car! (cdr p) v)))
        (cons cdar  (lambda (p v) (set-cdr! (car p) v)))
        (cons cddr  (lambda (p v) (set-cdr! (cdr p) v)))
        ;; 3-deep compositions
        (cons caaar (lambda (p v) (set-car! (caar p) v)))
        (cons caadr (lambda (p v) (set-car! (cadr p) v)))
        (cons cadar (lambda (p v) (set-car! (cdar p) v)))
        (cons caddr (lambda (p v) (set-car! (cddr p) v)))
        (cons cdaar (lambda (p v) (set-cdr! (caar p) v)))
        (cons cdadr (lambda (p v) (set-cdr! (cadr p) v)))
        (cons cddar (lambda (p v) (set-cdr! (cdar p) v)))
        (cons cdddr (lambda (p v) (set-cdr! (cddr p) v)))
        ;; 4-deep compositions
        (cons caaaar (lambda (p v) (set-car! (caaar p) v)))
        (cons caaadr (lambda (p v) (set-car! (caadr p) v)))
        (cons caadar (lambda (p v) (set-car! (cadar p) v)))
        (cons caaddr (lambda (p v) (set-car! (caddr p) v)))
        (cons cadaar (lambda (p v) (set-car! (cdaar p) v)))
        (cons cadadr (lambda (p v) (set-car! (cdadr p) v)))
        (cons caddar (lambda (p v) (set-car! (cddar p) v)))
        (cons cadddr (lambda (p v) (set-car! (cdddr p) v)))
        (cons cdaaar (lambda (p v) (set-cdr! (caaar p) v)))
        (cons cdaadr (lambda (p v) (set-cdr! (caadr p) v)))
        (cons cdadar (lambda (p v) (set-cdr! (cadar p) v)))
        (cons cdaddr (lambda (p v) (set-cdr! (caddr p) v)))
        (cons cddaar (lambda (p v) (set-cdr! (cdaar p) v)))
        (cons cddadr (lambda (p v) (set-cdr! (cdadr p) v)))
        (cons cdddar (lambda (p v) (set-cdr! (cddar p) v)))
        (cons cddddr (lambda (p v) (set-cdr! (cdddr p) v)))))

    (define (setter proc)
      (let ((entry (assq proc setters)))
        (if entry (cdr entry)
            (error "no setter defined for procedure" proc))))

    (define (getter-with-setter getter setter-proc)
      (set! setters (cons (cons getter setter-proc) setters))
      getter)))
