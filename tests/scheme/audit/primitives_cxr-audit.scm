;; Audit tests for src/primitives_cxr.zig — audit Phase 2.17
;; All 24 three- and four-level car/cdr compositions from (scheme cxr).
;; See docs/audit-strategy.md. Run directly and read the pass/fail counts:
;;   zig-out/bin/kaappi tests/scheme/audit/primitives_cxr-audit.scm

(import (scheme base) (scheme cxr) (scheme process-context) (srfi 64))

(test-begin "primitives_cxr audit")

;; Self-labeling complete trees: the leaf reached by each accessor holds that
;; accessor's own name. Letters in a cxr name apply right-to-left, so the leaf
;; label is "c" + reverse(root->leaf path) + "r".
(define (build depth path)
  (if (= depth 0)
      (string->symbol
       (string-append "c" (list->string (reverse (string->list path))) "r"))
      (cons (build (- depth 1) (string-append path "a"))
            (build (- depth 1) (string-append path "d")))))
(define t3 (build 3 ""))
(define t4 (build 4 ""))

;;; --- three-level compositions ---
(test-equal 'caaar (caaar t3))
(test-equal 'caadr (caadr t3))
(test-equal 'cadar (cadar t3))
(test-equal 'caddr (caddr t3))
(test-equal 'cdaar (cdaar t3))
(test-equal 'cdadr (cdadr t3))
(test-equal 'cddar (cddar t3))
(test-equal 'cdddr (cdddr t3))

;;; --- four-level compositions ---
(test-equal 'caaaar (caaaar t4))
(test-equal 'caaadr (caaadr t4))
(test-equal 'caadar (caadar t4))
(test-equal 'caaddr (caaddr t4))
(test-equal 'cadaar (cadaar t4))
(test-equal 'cadadr (cadadr t4))
(test-equal 'caddar (caddar t4))
(test-equal 'cadddr (cadddr t4))
(test-equal 'cdaaar (cdaaar t4))
(test-equal 'cdaadr (cdaadr t4))
(test-equal 'cdadar (cdadar t4))
(test-equal 'cdaddr (cdaddr t4))
(test-equal 'cddaar (cddaar t4))
(test-equal 'cddadr (cddadr t4))
(test-equal 'cdddar (cdddar t4))
(test-equal 'cddddr (cddddr t4))

;;; --- classics on flat lists ---
(test-equal 'c (caddr '(a b c d e)))
(test-equal 'd (cadddr '(a b c d e)))
(test-equal '(d e) (cdddr '(a b c d e)))
(test-equal '(e) (cddddr '(a b c d e)))
(test-equal '() (cdddr '(1 2 3)))
(test-equal '() (cddddr '(1 2 3 4)))
(test-equal 'b (cadadr '(a (a b))))

;;; --- first-class procedure values ---
(test-equal '(3 6) (map caddr '((1 2 3) (4 5 6))))
(test-equal 3 (apply caddr (list '(1 2 3 4))))

;;; --- every accessor raises a catchable error on '() ---
(define all-cxrs
  (list caaar caadr cadar caddr cdaar cdadr cddar cdddr
        caaaar caaadr caadar caaddr cadaar cadadr caddar cadddr
        cdaaar cdaadr cdadar cdaddr cddaar cddadr cdddar cddddr))
(test-equal 24 (length all-cxrs))
(test-equal #t
            (let loop ((ps all-cxrs))
              (cond ((null? ps) #t)
                    ((guard (e (#t (error-object? e))) ((car ps) '()) #f)
                     (loop (cdr ps)))
                    (else #f))))

;;; --- every accessor raises a catchable error on a non-pair ---
(test-equal #t
            (let loop ((ps all-cxrs))
              (cond ((null? ps) #t)
                    ((guard (e (#t (error-object? e))) ((car ps) 42) #f)
                     (loop (cdr ps)))
                    (else #f))))

;;; --- structure too shallow / dotted ---
(test-equal #t (guard (e (#t (error-object? e))) (cadddr '(1 2 3)) #f))
(test-equal #t (guard (e (#t (error-object? e))) (caddr '(1 2 . 3)) #f))
(test-equal #t (guard (e (#t (error-object? e))) (cddddr "abc") #f))
(test-equal #t (guard (e (#t (error-object? e))) (caaar '(1 2 3)) #f))

;;; --- accessors see mutation (no copying) ---
(let ((t (list (list 1 2 3))))
  (set-car! (cdr (car t)) 99)
  (test-equal 99 (cadar t)))

(let ((runner (test-runner-current)))
  (test-end "primitives_cxr audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
