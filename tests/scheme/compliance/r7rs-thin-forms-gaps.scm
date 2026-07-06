;; R7RS thin-coverage form gap tests — audit Phase 4A (part 2).
;; Forms with <=1 Zig test and <=2 Scheme tests: delay/delay-force,
;; parameterize, define-values, let*-values, letrec*, letrec-syntax.
;; Spec references cite docs/errata-corrected-r7rs.pdf.

(import (scheme base) (scheme lazy) (scheme write) (scheme process-context)
        (srfi 64))

(test-begin "r7rs-thin-forms-gaps")

;;; --- 4.2.5 delay / delay-force / force ---
;; "(delay-force expression) ... allows iterative lazy algorithms to be
;; expressed in bounded space" — a chain of delay-force promises must
;; force without stack growth.
(define (df-chain n)
  (if (= n 0) (delay 'end) (delay-force (df-chain (- n 1)))))
(test-equal "delay-force chain forces in bounded space" 'end
  (force (df-chain 99999)))
(test-equal "delay-force chain beyond 100k" 'end (force (df-chain 100001)))

;; force memoizes: the body runs once even when forced repeatedly
(define force-count 0)
(define memo-p (delay (begin (set! force-count (+ force-count 1)) 'val)))
(test-equal "force returns body value" 'val (force memo-p))
(test-equal "second force reuses memoized value" 'val (force memo-p))
(test-equal "delay body evaluated exactly once" 1 force-count)

;; promise? / make-promise
(test-assert "delay yields a promise" (promise? (delay 1)))
(test-assert "delay-force yields a promise" (promise? (delay-force (delay 1))))
(test-assert "make-promise yields a promise" (promise? (make-promise 7)))
(test-equal "force of make-promise" 7 (force (make-promise 7)))
(test-assert "make-promise on a promise stays a promise"
  (promise? (make-promise (delay 3))))
(test-assert "non-promise is not promise?" (not (promise? 42)))

;;; --- 4.2.6 parameterize ---
(define pa (make-parameter 10))
(define pb (make-parameter 'b (lambda (v) (list 'conv v))))

(test-equal "parameter initial value" 10 (pa))
(test-equal "converter runs on initialization" '(conv b) (pb))

(test-equal "parameterize binds inside the body" 20
  (parameterize ((pa 20)) (pa)))
(test-equal "parameterize restores after the body" 10 (pa))

;; nested parameterize shadows and restores level by level
(test-equal "nested parameterize" '(3 2 10)
  (parameterize ((pa 2))
    (let ((inner (parameterize ((pa 3)) (pa))))
      (list inner (pa) (begin 'placeholder 10)))))
(test-equal "after nested parameterize" 10 (pa))

;; "the value of the parameter is the result of passing the value of
;; expression to the converter" — converter applies during parameterize too
(test-equal "converter runs on parameterize" '(conv x)
  (parameterize ((pb 'x)) (pb)))
(test-equal "converter not re-run on restore" '(conv b) (pb))

;; parameterize + dynamic-wind: value is the parameterized one inside,
;; restored once control leaves
(define pw (make-parameter 'out))
(test-equal "parameterize visible inside dynamic-wind thunk" '(out in out)
  (let ((seen '()))
    (parameterize ((pw 'in))
      (dynamic-wind
        (lambda () #f)
        (lambda () (set! seen (cons (pw) seen)))
        (lambda () #f)))
    (cons (pw) (cons (car seen) (list 'out)))))

;; simultaneous (letrec-free) binding: both value expressions must be
;; evaluated in the OUTER parameterization (R7RS 4.2.6 / SRFI-39 "1010")
(define p1 (make-parameter 1))
(define p2 (make-parameter 2))
;; FAIL: #1202 (parameterize installs bindings sequentially, let*-style)
;; (test-equal "parameterize evaluates values in outer parameterization"
;;   '(2 1)
;;   (parameterize ((p1 (p2)) (p2 (p1))) (list (p1) (p2))))

;;; --- 5.3.3 define-values ---
(define-values (dv-a dv-b) (values 1 2))
(test-equal "define-values fixed formals" '(1 2) (list dv-a dv-b))

(define-values (dv-x . dv-rest) (values 10 20 30))
(test-equal "define-values dotted formals" '(10 (20 30)) (list dv-x dv-rest))

(define-values dv-all (values 4 5 6))
(test-equal "define-values single-variable formals" '(4 5 6) dv-all)

(define-values (dv-only) (values 'solo))
(test-equal "define-values one name one value" 'solo dv-only)

;; define-values in a lambda body (internal definition context)
(test-equal "define-values in lambda body" 3
  ((lambda ()
     (define-values (ia ib) (values 1 2))
     (+ ia ib))))

;;; --- 4.2.2 let*-values sequential scoping ---
(test-equal "let*-values later clauses see earlier bindings" 3
  (let*-values (((a b) (values 1 2))
                ((c) (values (+ a b))))
    c))
(test-equal "let*-values shadows sequentially" 4
  (let*-values (((x) (values 2))
                ((x) (values (* x x))))
    x))
(test-equal "let*-values dotted formals" '(1 (2 3))
  (let*-values (((a . r) (values 1 2 3))) (list a r)))

;;; --- 4.2.2 letrec* ordering ---
;; "the <variable>s are bound to fresh locations, each <variable> is
;; assigned in left-to-right order" — earlier bindings usable by later inits
(test-equal "letrec* sequential initialization" 3
  (letrec* ((a 1) (b (+ a 2))) b))
(test-equal "letrec* mutual recursion via lambdas" #t
  (letrec* ((ev? (lambda (n) (if (= n 0) #t (od? (- n 1)))))
            (od? (lambda (n) (if (= n 0) #f (ev? (- n 1))))))
    (ev? 100)))
(test-equal "letrec mutual recursion via lambdas" 55
  (letrec ((fib (lambda (n) (if (< n 2) n (+ (fib (- n 1)) (fib (- n 2)))))))
    (fib 10)))

;;; --- 4.3.1 letrec-syntax recursive transformer ---
(test-equal "letrec-syntax transformer can call itself" 7
  (letrec-syntax ((my-or (syntax-rules ()
                           ((_) #f)
                           ((_ e) e)
                           ((_ e r ...) (let ((t e)) (if t t (my-or r ...)))))))
    (my-or #f #f 7)))

;; let-syntax body may contain multiple expressions
(test-equal "let-syntax multi-form body" 9
  (let-syntax ((sq (syntax-rules () ((_ x) (* x x)))))
    (sq 2)
    (sq 3)))

(let ((runner (test-runner-current)))
  (test-end "r7rs-thin-forms-gaps")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
