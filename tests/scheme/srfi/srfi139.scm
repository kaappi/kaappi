;; SRFI 139 (Syntax parameters) tests. Fully portable on Kaappi's existing
;; syntax-rules-only expander -- let-syntax's existing "adjust the live
;; macro table for a bounded compile extent, then restore it" behavior IS
;; syntax-parameterize's semantics, so lib/srfi/139.sld needs no engine
;; changes. Part of issue #1699 (SRFI macro & syntax extension libraries).
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi139.scm
;;
;; Grown in audit v2 Phase 3.8 from 5 assertions. The two spec examples and
;; the shadow/restore cases were already here; the additions target the
;; property that actually distinguishes a syntax parameter from a
;; let-syntax binding, which the SRFI states directly:
;;
;;   "syntax-parameterize differs from let-syntax in that the binding is
;;    not shadowed, but adjusted, and so uses of the keyword in the
;;    expansion of <body> use the new transformers."
;;
;; A plain let-syntax binding is lexical, so a macro defined ELSEWHERE that
;; mentions the keyword would keep seeing the original transformer. A
;; syntax parameter must not: the adjustment has to reach through a macro
;; boundary, including one crossed several times, and has to be undone at
;; the end of the extent in every one of those places.

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

(test-equal "spec example 1: forever/abort escapes with the accumulated list"
  '(0 1 2 3 4 5 6 7 8 9)
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

(test-equal "spec example 2: lambda^ returns the product normally" 24
  (product '(1 2 3 4)))
(test-equal "spec example 2: return short-circuits on the zero element" 0
  (product '(1 2 0 4)))

;;; --- a syntax parameter's default transformer is used outside any
;;; syntax-parameterize: "in the absence of syntax-parameterize, [it] is
;;; functionally equivalent to define-syntax" ---

(define-syntax-parameter sp
  (syntax-rules () ((_) 'default)))

(test-equal "the default transformer applies outside any extent"
  'default (sp))

(test-equal "syntax-parameterize adjusts it inside the extent"
  'adjusted
  (syntax-parameterize ((sp (syntax-rules () ((_) 'adjusted)))) (sp)))

(test-equal "the default transformer is restored after the extent"
  '(adjusted default)
  (list (syntax-parameterize ((sp (syntax-rules () ((_) 'adjusted)))) (sp))
        (sp)))

(test-equal "syntax-parameterize with no bindings changes nothing"
  'default (syntax-parameterize () (sp)))

;;; --- adjustment, not shadowing: a macro defined BEFORE the
;;; syntax-parameterize, which mentions the keyword in its own template,
;;; must see the ADJUSTED transformer when its use is expanded inside the
;;; extent. This is the property a lexical let-syntax binding could not
;;; provide, and it is the whole point of the SRFI. ---

(define-syntax uses-sp (syntax-rules () ((_) (sp))))

(test-equal "a macro defined before the extent sees the adjusted transformer"
  'adjusted
  (syntax-parameterize ((sp (syntax-rules () ((_) 'adjusted)))) (uses-sp)))

(test-equal "the same macro outside the extent sees the default"
  'default (uses-sp))

(test-equal "the same macro sees the default again after the extent"
  '(default adjusted default)
  (list (uses-sp)
        (syntax-parameterize ((sp (syntax-rules () ((_) 'adjusted)))) (uses-sp))
        (uses-sp)))

;;; --- nesting the same keyword ACROSS a macro boundary: the inner extent
;;; lives inside another macro's expansion, and the outer transformer must
;;; be restored on the way out of it ---

(define-syntax level2
  (syntax-rules ()
    ((_ e) (syntax-parameterize ((sp (syntax-rules () ((_) 'inner)))) e))))

(test-equal "an inner extent inside a macro expansion restores the outer one"
  '(outer inner outer)
  (syntax-parameterize ((sp (syntax-rules () ((_) 'outer))))
    (list (sp) (level2 (sp)) (sp))))

;;; --- nested syntax-parameterize of the SAME keyword: the inner
;;; extent's transformer must not leak past its own scope ---
(define-syntax-parameter marker
  (syntax-rules ()
    ((_ . _) (syntax-error "marker used outside its extent"))))

(test-equal "nested extents of the same keyword shadow and restore correctly"
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

;;; --- several parameters adjusted by one form, independently ---

(define-syntax-parameter sq (syntax-rules () ((_) 'q-default)))

(test-equal "one syntax-parameterize adjusts several keywords at once"
  '(1 2)
  (syntax-parameterize ((sp (syntax-rules () ((_) 1)))
                        (sq (syntax-rules () ((_) 2))))
    (list (sp) (sq))))

(test-equal "adjusting one keyword leaves the others alone"
  '(1 q-default)
  (syntax-parameterize ((sp (syntax-rules () ((_) 1))))
    (list (sp) (sq))))

(test-equal "both keywords are restored after the extent"
  '(default q-default) (list (sp) (sq)))

;;; --- the extent covers a definition context too, not just expressions ---

(test-equal "the adjustment reaches a definition inside the body"
  'dc
  (syntax-parameterize ((sp (syntax-rules () ((_) 'dc))))
    (define sp-defined (sp))
    sp-defined))

;;; --- a new transformer's own template resolves its free references in
;;; the surrounding scope, exactly as R7RS 4.3.1 requires of a let-syntax
;;; transformer spec -- so a self-mentioning adjustment reads the OUTER
;;; binding rather than recursing forever ---

(test-equal "a self-mentioning adjustment reads the outer transformer"
  '(wrapped default)
  (syntax-parameterize ((sp (syntax-rules () ((_) (list 'wrapped (sp)))))) (sp)))

;;; --- a body-local variable sharing a name with the macro's own
;;; internal continuation identifier must not be captured ---
(test-equal "a body-local variable named like the macro's escape is not captured"
  'user-escape-value
  (forever
   (let ((escape 'user-escape-value))
     (abort escape))))

;;; --- the derived cond-expand feature id (#1649) ---
(test-equal "cond-expand srfi-139" 'yes (cond-expand (srfi-139 'yes) (else 'no)))

(let ((runner (test-runner-current)))
  (test-end "srfi-139")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
