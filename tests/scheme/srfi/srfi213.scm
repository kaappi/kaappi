;; SRFI 213 (Identifier Properties) tests. define-property is an
;; engine-level definition form (properties keyed by effective names in a
;; VM-owned table); transformers read them back through the lookup
;; procedure the capture-lookup re-entry protocol provides — and per the
;; SRFI, capture-lookup is substitutable by the identity, so both the
;; wrapped and the bare-procedure return shapes are exercised here.
;; See lib/srfi/213.sld for the documented v1 scope reductions.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi213.scm

(import (scheme base) (scheme process-context) (srfi 64)
        (srfi 211 explicit-renaming)
        (srfi 213))

(test-begin "srfi-213")

;;; --- basic property definition and lookup (wrapped capture-lookup) ---
(define color 'red)
(define hue-key 'hue)
(define-property color hue-key (list 'bright color))

(define-syntax prop-of
  (er-macro-transformer
   (lambda (form rename compare)
     (capture-lookup
      (lambda (lookup)
        (list (rename 'quote) (lookup (cadr form) (car (cddr form)))))))))

(test-equal '(bright red) (prop-of color hue-key))

;; the expression was evaluated at expansion time in the global env: it
;; saw color's value; the binding itself is undisturbed
(test-equal 'red color)

;;; --- missing property is #f ---
(test-equal #f (prop-of color no-such-key))
(test-equal #f (prop-of no-such-id hue-key))

;;; --- bare-procedure return: capture-lookup as the identity ---
(define-syntax prop-of-bare
  (er-macro-transformer
   (lambda (form rename compare)
     (lambda (lookup)
       (list (rename 'quote) (lookup (cadr form) (car (cddr form))))))))
(test-equal '(bright red) (prop-of-bare color hue-key))
(test-assert "capture-lookup is the identity" (eq? (capture-lookup car) car))

;;; --- several keys on one identifier; several identifiers on one key ---
(define size-key 'size)
(define-property color size-key 'large)
(define shape 'square)
(define-property shape hue-key 'blue-ish)
(test-equal 'large (prop-of color size-key))
(test-equal '(bright red) (prop-of color hue-key))
(test-equal 'blue-ish (prop-of shape hue-key))
(test-equal #f (prop-of shape size-key))

;;; --- redefinition replaces the value ---
(define-property color size-key 'small)
(test-equal 'small (prop-of color size-key))

;;; --- expression evaluated exactly at definition time ---
(define eval-count 0)
(define counted 'thing)
(define count-key 'count)
(define-property counted count-key (begin (set! eval-count (+ eval-count 1)) eval-count))
(test-equal 1 eval-count)
(test-equal 1 (prop-of counted count-key))
(test-equal 1 eval-count)

;;; --- library-level define-property, read back at the use site ---
(define-library (t213 proplib)
  (import (scheme base) (srfi 211 explicit-renaming) (srfi 213))
  (export lib-prop lib-id lib-key)
  (begin
    (define lib-id 'lib-thing)
    (define lib-key 'lib-k)
    (define-property lib-id lib-key (* 6 7))
    (define-syntax lib-prop
      (er-macro-transformer
       (lambda (form rename compare)
         (capture-lookup
          (lambda (lookup)
            (list (rename 'quote) (lookup (cadr form) (car (cddr form)))))))))))
(import (t213 proplib))
(test-equal 42 (lib-prop lib-id lib-key))

;;; --- define-property through a syntax-rules template (#2089) ---
;;; A template-introduced define-property used to be hygiene-renamed to
;;; __hyg_N_define-property (it was missing from the expander's reserved
;;; template forms), and even when left bare the legacy compileForm path
;;; had no dispatch for it — so the whole define-library or program failed
;;; with "undefined variable 'define-property'". It must behave exactly
;;; like the direct form.
(define mp-color 'mp-red)
(define mp-hue 'mp-hue)
(define-syntax defprop
  (syntax-rules () ((_ id key val) (define-property id key val))))
(defprop mp-color mp-hue '(via-template BRIGHT))

(define-syntax prop-of
  (er-macro-transformer
   (lambda (form rename compare)
     (capture-lookup
      (lambda (lookup)
        (list (rename 'quote) (lookup (cadr form) (car (cddr form)))))))))
(test-equal '(via-template BRIGHT) (prop-of mp-color mp-hue))

;;; same, inside a library: define-library bodies also compile macro
;;; expansions through the legacy path
(define-library (t213 templib)
  (import (scheme base) (srfi 211 explicit-renaming) (srfi 213))
  (export lib-color lib-hue lib-prop)
  (begin
    (define lib-color 'lib-c)
    (define lib-hue 'lib-h)
    (define-syntax defprop2
      (syntax-rules () ((_ id key val) (define-property id key val))))
    (defprop2 lib-color lib-hue 'lib-v)
    (define-syntax lib-prop
      (er-macro-transformer
       (lambda (form rename compare)
         (capture-lookup
          (lambda (lookup)
            (list (rename 'quote) (lookup (cadr form) (car (cddr form)))))))))))
(import (t213 templib))
(test-equal 'lib-v (lib-prop lib-color lib-hue))

(let ((runner (test-runner-current)))
  (test-end "srfi-213")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
