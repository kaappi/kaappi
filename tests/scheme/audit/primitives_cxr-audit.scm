;; Audit tests for src/primitives_cxr.zig — audit Phase 2.17
;; All 24 three- and four-level car/cdr compositions from (scheme cxr).
;; See docs/audit-strategy.md. Run directly and read the pass/fail counts:
;;   zig-out/bin/kaappi tests/scheme/audit/primitives_cxr-audit.scm

(import (scheme base) (scheme cxr) (chibi test))

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
(test 'caaar (caaar t3))
(test 'caadr (caadr t3))
(test 'cadar (cadar t3))
(test 'caddr (caddr t3))
(test 'cdaar (cdaar t3))
(test 'cdadr (cdadr t3))
(test 'cddar (cddar t3))
(test 'cdddr (cdddr t3))

;;; --- four-level compositions ---
(test 'caaaar (caaaar t4))
(test 'caaadr (caaadr t4))
(test 'caadar (caadar t4))
(test 'caaddr (caaddr t4))
(test 'cadaar (cadaar t4))
(test 'cadadr (cadadr t4))
(test 'caddar (caddar t4))
(test 'cadddr (cadddr t4))
(test 'cdaaar (cdaaar t4))
(test 'cdaadr (cdaadr t4))
(test 'cdadar (cdadar t4))
(test 'cdaddr (cdaddr t4))
(test 'cddaar (cddaar t4))
(test 'cddadr (cddadr t4))
(test 'cdddar (cdddar t4))
(test 'cddddr (cddddr t4))

;;; --- classics on flat lists ---
(test 'c (caddr '(a b c d e)))
(test 'd (cadddr '(a b c d e)))
(test '(d e) (cdddr '(a b c d e)))
(test '(e) (cddddr '(a b c d e)))
(test '() (cdddr '(1 2 3)))
(test '() (cddddr '(1 2 3 4)))
(test 'b (cadadr '(a (a b))))

;;; --- first-class procedure values ---
(test '(3 6) (map caddr '((1 2 3) (4 5 6))))
(test 3 (apply caddr (list '(1 2 3 4))))

;;; --- every accessor raises a catchable error on '() ---
(define all-cxrs
  (list caaar caadr cadar caddr cdaar cdadr cddar cdddr
        caaaar caaadr caadar caaddr cadaar cadadr caddar cadddr
        cdaaar cdaadr cdadar cdaddr cddaar cddadr cdddar cddddr))
(test 24 (length all-cxrs))
(test #t
      (let loop ((ps all-cxrs))
        (cond ((null? ps) #t)
              ((guard (e (#t (error-object? e))) ((car ps) '()) #f)
               (loop (cdr ps)))
              (else #f))))

;;; --- every accessor raises a catchable error on a non-pair ---
(test #t
      (let loop ((ps all-cxrs))
        (cond ((null? ps) #t)
              ((guard (e (#t (error-object? e))) ((car ps) 42) #f)
               (loop (cdr ps)))
              (else #f))))

;;; --- structure too shallow / dotted ---
(test #t (guard (e (#t (error-object? e))) (cadddr '(1 2 3)) #f))
(test #t (guard (e (#t (error-object? e))) (caddr '(1 2 . 3)) #f))
(test #t (guard (e (#t (error-object? e))) (cddddr "abc") #f))
(test #t (guard (e (#t (error-object? e))) (caaar '(1 2 3)) #f))

;;; --- accessors see mutation (no copying) ---
(let ((t (list (list 1 2 3))))
  (set-car! (cdr (car t)) 99)
  (test 99 (cadar t)))

(test-end "primitives_cxr audit")
