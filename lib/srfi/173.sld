;; SRFI 173: Hooks
;;
;; A hook is an opaque object wrapping a mutable list of procedures that
;; all accept the same number of arguments (the hook's arity). Running the
;; hook applies every stored procedure to the given arguments; the order
;; of application is unspecified.

(define-library (srfi 173)
  (import (scheme base))
  (export make-hook hook? list->hook list->hook!
          hook-add! hook-delete! hook-reset! hook->list hook-run)
  (begin
    (define-record-type <hook>
      (make-hook-internal arity procs)
      hook?
      (arity hook-arity)
      (procs hook-procs set-hook-procs!))

    (define (make-hook arity)
      (make-hook-internal arity '()))

    (define (list->hook arity lst)
      (make-hook-internal arity lst))

    (define (list->hook! hook lst)
      (set-hook-procs! hook lst))

    ;; New procedures are added to the front of the list.
    (define (hook-add! hook proc)
      (set-hook-procs! hook (cons proc (hook-procs hook))))

    (define (%remove-eq proc lst)
      (cond ((null? lst) '())
            ((eq? (car lst) proc) (%remove-eq proc (cdr lst)))
            (else (cons (car lst) (%remove-eq proc (cdr lst))))))

    ;; Procedures are compared with eq?.
    (define (hook-delete! hook proc)
      (set-hook-procs! hook (%remove-eq proc (hook-procs hook))))

    (define (hook-reset! hook)
      (set-hook-procs! hook '()))

    (define (hook->list hook)
      (hook-procs hook))

    ;; It is an error if the number of args does not match the hook's arity.
    (define (hook-run hook . args)
      (if (= (length args) (hook-arity hook))
          (for-each (lambda (proc) (apply proc args)) (hook-procs hook))
          (error "hook-run: argument count does not match hook arity"
                 hook args)))))
