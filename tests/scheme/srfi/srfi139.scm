;; SRFI 139 (Syntax parameters) tests. Fully portable on Kaappi's existing
;; syntax-rules-only expander -- let-syntax's existing "adjust the live
;; macro table for a bounded compile extent, then restore it" behavior IS
;; syntax-parameterize's semantics, so lib/srfi/139.sld needs no engine
;; changes. Part of issue #1699 (SRFI macro & syntax extension libraries).
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi139.scm

(import (scheme base) (scheme process-context) (srfi 1) (srfi 64) (srfi 139))

(test-begin "srfi-139")

;;; --- the spec's own example 1: forever/abort, verbatim mechanism,
;;; adapted to return a checkable value instead of printing ---
(define-syntax-parameter abort
  (syntax-rules ()
    ((_ . _) (syntax-error "abort used outside of a loop"))))

(define-syntax forever
  (syntax-rules ()
    ((forever body1 body2 ...)
     (call-with-current-continuation
      (lambda (escape)
        (syntax-parameterize
            ((abort
              (syntax-rules ()
                ((abort value (... ...))
                 (escape value (... ...))))))
          (let loop ()
            body1 body2 ... (loop))))))))

(test-equal '(0 1 2 3 4 5 6 7 8 9)
            (let ((acc '()) (i 0))
              (forever
               (set! acc (cons i acc))
               (set! i (+ 1 i))
               (when (= i 10)
                 (abort (reverse acc))))))

;;; --- the spec's own example 2: lambda^/return, with the calls the
;;; spec's own text left incomplete (trailing "...") filled in ---
(define-syntax-parameter return
  (syntax-rules ()
    ((_ . _) (syntax-error "return used outside of a lambda^"))))

(define-syntax lambda^
  (syntax-rules ()
    ((lambda^ formals body1 body2 ...)
     (lambda formals
       (call-with-current-continuation
        (lambda (escape)
          (syntax-parameterize
              ((return
                (syntax-rules ()
                  ((return value (... ...))
                   (escape value (... ...))))))
            body1 body2 ...)))))))

(define product
  (lambda^ (lst)
    (fold (lambda (n o) (if (zero? n) (return 0) (* n o))) 1 lst)))

(test-equal 24 (product '(1 2 3 4)))
(test-equal 0 (product '(1 2 0 4)))  ;; short-circuits on the zero element

;;; --- nested syntax-parameterize of the SAME keyword: the inner
;;; extent's transformer must not leak past its own scope ---
(define-syntax-parameter marker
  (syntax-rules ()
    ((_ . _) (syntax-error "marker used outside its extent"))))

(test-equal
 '(outer (after (inner 1)))
 (call-with-current-continuation
  (lambda (outer-escape)
    (syntax-parameterize
        ((marker (syntax-rules () ((marker v) (outer-escape (list 'outer v))))))
      (let ((inner
             (call-with-current-continuation
              (lambda (inner-escape)
                (syntax-parameterize
                    ((marker (syntax-rules () ((marker v) (inner-escape (list 'inner v))))))
                  (marker 1))))))
        ;; inner extent has ended -- marker must be restored to the OUTER
        ;; transformer here, not left pointing at the inner escape
        (marker (list 'after inner)))))))

;;; --- a body-local variable sharing a name with the macro's own
;;; internal continuation identifier must not be captured ---
(test-equal 'user-escape-value
            (forever
             (let ((escape 'user-escape-value))
               (abort escape))))

(let ((runner (test-runner-current)))
  (test-end "srfi-139")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
