;; Audit tests for src/primitives.zig (core) — audit Phase 2.18
;; Pairs/lists, type predicates, equivalence, not, core string ops, apply,
;; and the internal record primitives behind define-record-type.
;; See docs/audit-strategy.md. Run directly and read the pass/fail counts:
;;   zig-out/bin/kaappi tests/scheme/audit/primitives_core-audit.scm

(import (scheme base) (scheme process-context) (srfi 64))

(test-begin "primitives_core audit")

;;; --- cons / car / cdr ---
(test-equal '(1 . 2) (cons 1 2))
(test-equal '(1 2) (cons 1 (cons 2 '())))
(test-equal 1 (car (cons 1 2)))
(test-equal 2 (cdr (cons 1 2)))
(test-equal #t (guard (e (#t (error-object? e))) (car '()) #f))
(test-equal #t (guard (e (#t (error-object? e))) (cdr '()) #f))
(test-equal #t (guard (e (#t (error-object? e))) (car 5) #f))
(test-equal #t (guard (e (#t (error-object? e))) (cdr "pair") #f))

;;; --- set-car! / set-cdr! ---
(let ((p (list 1 2)))
  (set-car! p 'x)
  (test-equal '(x 2) p))
(let ((p (list 1 2)))
  (set-cdr! p 3)
  (test-equal '(1 . 3) p))
(test-equal #t (guard (e (#t (error-object? e))) (set-car! '() 1) #f))
(test-equal #t (guard (e (#t (error-object? e))) (set-cdr! 5 1) #f))

;;; --- list ---
(test-equal '() (list))
(test-equal '(1 2 3) (list 1 2 3))
(test-equal '((1 2) (3)) (list (list 1 2) (list 3)))

;;; --- length ---
(test-equal 0 (length '()))
(test-equal 3 (length '(a b c)))
(test-equal #t (guard (e (#t (error-object? e))) (length '(1 2 . 3)) #f))
(test-equal #t (guard (e (#t (error-object? e))) (length 5) #f))
(test-equal #t (guard (e (#t (error-object? e))) (length "abc") #f))
;; circular list: Floyd detection raises instead of hanging
(let ((c (list 1 2)))
  (set-cdr! (cdr c) c)
  (test-equal #t (guard (e (#t (error-object? e))) (length c) #f)))

;;; --- append ---
(test-equal '() (append))
(test-equal '(1 2 3 4) (append '(1 2) '(3 4)))
(test-equal '(1 2 3 4 5) (append '(1) '() '(2 3) '() '(4 5)))
;; single argument returned as-is (shared)
(let ((l (list 1 2)))
  (test-equal #t (eq? l (append l))))
;; R7RS 6.4: the result "shares structure with the last argument"
(let ((tl (list 1 2)))
  (test-equal #t (eq? tl (cddr (append '(a b) tl)))))
;; ...but earlier arguments are copied, not shared
(let ((src (list 1 2)))
  (test-equal #f (eq? src (append src '()))))
;; last argument can be any object (improper result)
(test-equal '(1 2 . 3) (append '(1 2) 3))
(test-equal 5 (append 5))
(test-equal 'x (append '() 'x))
;; non-last arguments must be proper lists
(test-equal #t (guard (e (#t (error-object? e))) (append '(1 . 2) '(3)) #f))
(test-equal #t (guard (e (#t (error-object? e))) (append 5 '(3)) #f))
;; circular non-last argument must error, not hang:
(let ((c (list 1 2)))
  (set-cdr! (cdr c) c)
  (test-equal #t (guard (e (#t (error-object? e))) (append c '(9)) #f)))

;;; --- reverse ---
(test-equal '() (reverse '()))
(test-equal '(c b a) (reverse '(a b c)))
(test-equal '((3) (1 2)) (reverse (list (list 1 2) (list 3))))
(test-equal #t (guard (e (#t (error-object? e))) (reverse '(1 2 . 3)) #f))
(test-equal #t (guard (e (#t (error-object? e))) (reverse 5) #f))
;; circular argument must error, not hang:
(let ((c (list 1 2)))
  (set-cdr! (cdr c) c)
  (test-equal #t (guard (e (#t (error-object? e))) (reverse c) #f)))

;;; --- caar / cadr / cdar / cddr ---
(test-equal 1 (caar '((1 2) 3)))
(test-equal 3 (cadr '((1 2) 3)))
(test-equal '(2) (cdar '((1 2) 3)))
(test-equal '() (cddr '((1 2) 3)))
(test-equal #t (guard (e (#t (error-object? e))) (caar '(1 2)) #f))
(test-equal #t (guard (e (#t (error-object? e))) (cadr '(1)) #f))
(test-equal #t (guard (e (#t (error-object? e))) (cdar '(1 2)) #f))
(test-equal #t (guard (e (#t (error-object? e))) (cddr '(1)) #f))
(test-equal #t (guard (e (#t (error-object? e))) (caar '()) #f))

;;; --- type predicates: pair? null? list? ---
(test-equal #t (pair? '(1)))
(test-equal #t (pair? '(1 . 2)))
(test-equal #f (pair? '()))
(test-equal #f (pair? 5))
(test-equal #f (pair? #(1)))
(test-equal #t (null? '()))
(test-equal #f (null? '(1)))
(test-equal #f (null? #f))
(test-equal #f (null? 0))
(test-equal #f (null? ""))
(test-equal #t (list? '()))
(test-equal #t (list? '(1 2 3)))
(test-equal #f (list? '(1 . 2)))
(test-equal #f (list? 5))
(test-equal #f (list? "abc"))
;; circular: list? must return #f and terminate (R7RS 6.4)
(let ((c (list 1 2)))
  (set-cdr! (cdr c) c)
  (test-equal #f (list? c)))

;;; --- numeric tower predicates (R7RS 6.2.6 examples) ---
(test-equal #t (number? 3))
(test-equal #t (number? 3.5))
(test-equal #t (number? (expt 2 100)))
(test-equal #t (number? 1/3))
(test-equal #f (number? "3"))
(test-equal #f (number? #\3))
(test-equal #t (complex? 3))
(test-equal #t (complex? 3.5))
(test-equal #t (real? 3))
(test-equal #t (real? +nan.0))
(test-equal #t (real? +inf.0))
(test-equal #t (rational? 6/10))
(test-equal #t (rational? 6/3))
(test-equal #t (rational? 3.5))
(test-equal #f (rational? -inf.0))
(test-equal #f (rational? +nan.0))
(test-equal #t (integer? 3))
(test-equal #t (integer? 3.0))
(test-equal #t (integer? 8/4))
(test-equal #t (integer? (expt 2 100)))
(test-equal #f (integer? 8/5))
(test-equal #f (integer? 3.5))
(test-equal #f (integer? +nan.0))
(test-equal #f (integer? +inf.0))

;;; --- other predicates ---
(test-equal #t (symbol? 'a))
(test-equal #f (symbol? "a"))
(test-equal #f (symbol? #\a))
(test-equal #t (string? "a"))
(test-equal #t (string? ""))
(test-equal #f (string? 'a))
(test-equal #t (boolean? #t))
(test-equal #t (boolean? #f))
(test-equal #f (boolean? 0))
(test-equal #f (boolean? '()))
(test-equal #t (char? #\a))
(test-equal #t (char? #\x3bb))
(test-equal #f (char? "a"))
(test-equal #t (procedure? car))
(test-equal #t (procedure? (lambda (x) x)))
(test-equal #t (call-with-current-continuation procedure?))
(test-equal #f (procedure? 'car))
(test-equal #f (procedure? '(lambda (x) x)))

;;; --- eq? ---
(test-equal #t (eq? 'a 'a))
(test-equal #t (eq? '() '()))
(test-equal #t (eq? car car))
(test-equal #f (eq? (list 'a) (list 'a)))
(test-equal #t (let ((x '(a))) (eq? x x)))
(test-equal #t (let ((s "s")) (eq? s s)))
(test-equal #f (eq? 'a 'b))
(test-equal #t (eq? #t #t))
(test-equal #f (eq? #t #f))

;;; --- eqv? (R7RS 6.1) ---
(test-equal #t (eqv? 'a 'a))
(test-equal #t (eqv? 2 2))
(test-equal #f (eqv? 2 2.0))
(test-equal #t (eqv? 100000000 100000000))
(test-equal #f (eqv? 1/2 0.5))
(test-equal #t (eqv? 1/3 1/3))
(test-equal #t (eqv? (expt 2 100) (expt 2 100)))
(test-equal #t (eqv? (/ (expt 2 100) 3) (/ (expt 2 100) 3)))
(test-equal #t (eqv? #\a #\a))
(test-equal #f (eqv? #\a #\b))
(test-equal #t (eqv? '() '()))
(test-equal #f (eqv? (cons 1 2) (cons 1 2)))
(test-equal #f (eqv? #f 'nil))
(test-equal #t (let ((p (lambda (x) x))) (eqv? p p)))
;; inexact bitwise comparison (both allowed by R7RS; regression-lock current)
(test-equal #t (eqv? +nan.0 +nan.0))
(test-equal #f (eqv? 0.0 -0.0))
(test-equal #t (eqv? 1.5 1.5))

;;; --- equal? (R7RS 6.1) ---
(test-equal #t (equal? 'a 'a))
(test-equal #t (equal? '(a) '(a)))
(test-equal #t (equal? '(a (b) c) '(a (b) c)))
(test-equal #t (equal? "abc" "abc"))
(test-equal #t (equal? "" ""))
(test-equal #t (equal? 2 2))
(test-equal #f (equal? 2 2.0))
(test-equal #t (equal? (make-vector 5 'a) (make-vector 5 'a)))
(test-equal #t (equal? #() #()))
(test-equal #f (equal? #(1 2) #(1 2 3)))
(test-equal #t (equal? (bytevector 1 2 3) (bytevector 1 2 3)))
(test-equal #f (equal? (bytevector 1 2 3) (bytevector 1 2 4)))
(test-equal #t (equal? (list (expt 2 100)) (list (expt 2 100))))
(test-equal #t (equal? (list 1/3 (vector 2/7)) (list 1/3 (vector 2/7))))
(test-equal #f (equal? '(1 2) '(1 2 3)))
(test-equal #f (equal? #(1 2) '(1 2)))
;; R7RS: "equal? must always terminate, even if its arguments are circular"
(let ((c1 (list 1 2)) (c2 (list 1 2 1 2)))
  (set-cdr! (cdr c1) c1)
  (set-cdr! (cdddr c2) c2)
  (test-equal #t (boolean? (equal? c1 c2)))
  (test-equal #f (equal? c1 '(1 2 1 2))))
;; equal? after width-changing string mutation (rebuilt buffer)
(let ((s (make-string 3 #\a)))
  (string-set! s 0 #\x3bb)
  (test-equal #t (equal? s (string #\x3bb #\a #\a)))
  (string-set! s 0 #\b)
  (test-equal #t (equal? s "baa")))

;;; --- not ---
(test-equal #t (not #f))
(test-equal #f (not #t))
(test-equal #f (not '()))
(test-equal #f (not 0))
(test-equal #f (not "" ))
(test-equal #f (not not))
(test-equal #f (not '(f)))

;;; --- string-length (UTF-8 codepoint semantics) ---
(test-equal 0 (string-length ""))
(test-equal 3 (string-length "abc"))
(test-equal 3 (string-length "aλb"))
(test-equal 3 (string-length "a\x1D11E;b"))          ; astral plane
(test-equal 2 (string-length "e\x0301;"))            ; combining mark counts separately
(test-equal #t (guard (e (#t (error-object? e))) (string-length 'abc) #f))

;;; --- string-append ---
(test-equal "" (string-append))
(test-equal "abc" (string-append "abc"))
(test-equal "abcdef" (string-append "abc" "" "def"))
(test-equal 2 (string-length (string-append "λ" "\x1D11E;")))
(test-equal #t (guard (e (#t (error-object? e))) (string-append "a" 5) #f))
;; result is freshly allocated and mutable; source unchanged
(let* ((src "ab")
       (out (string-append src)))
  (string-set! out 0 #\x)
  (test-equal "ab" src)
  (test-equal "xb" out))

;;; --- symbol->string ---
(test-equal "abc" (symbol->string 'abc))
(test-equal #t (eq? 'héllo (string->symbol (symbol->string 'héllo))))
(test-equal #t (guard (e (#t (error-object? e))) (symbol->string "abc") #f))
;; R7RS 6.5: "it is an error to apply mutation procedures like string-set!
;; to strings returned by this procedure"
(test-equal #t (guard (e (#t (error-object? e)))
                 (string-set! (symbol->string 'foo) 0 #\x) #f))

;;; --- apply ---
(test-equal 10 (apply + '(1 2 3 4)))
(test-equal 10 (apply + 1 2 '(3 4)))
(test-equal 0 (apply + '()))
(test-equal '(1 . 2) (apply cons '(1 2)))
(test-equal 7 (apply (lambda (a b) (+ a b)) '(3 4)))
;; large argument list (guard's escape continuation limits apply to 255
;; args; use 200 to stay safely under)
(let loop ((i 0) (acc '()))
  (if (= i 200)
      (test-equal 200 (apply + acc))
      (loop (+ i 1) (cons 1 acc))))
;; errors
(test-equal #t (guard (e (#t (error-object? e))) (apply 7 '(1)) #f))
(test-equal #t (guard (e (#t (error-object? e))) (apply + 5) #f))
(test-equal #t (guard (e (#t (error-object? e))) (apply + '(1 2 . 3)) #f))
;; circular final list: apply in TAIL position compiles to the tail_apply
;; opcode, which bounds out with a catchable error
(let ((c (list 1 2)))
  (set-cdr! (cdr c) c)
  (test-equal 'caught (guard (e (#t 'caught)) (apply + c))))
;; non-tail position native applyFn must also detect circular final list:
(let ((c (list 1 2)))
  (set-cdr! (cdr c) c)
  (test-equal #t (guard (e (#t #t)) (apply + c) #f)))

;;; --- records (define-record-type over %record primitives) ---
(define-record-type point (make-point x y) point? (x point-x set-point-x!) (y point-y))
(define-record-type blob (make-blob v) blob? (v blob-v))

(let ((p (make-point 1 2)))
  (test-equal #t (point? p))
  (test-equal 1 (point-x p))
  (test-equal 2 (point-y p))
  (set-point-x! p 10)
  (test-equal 10 (point-x p)))
(test-equal #f (point? 5))
(test-equal #f (point? '(1 2)))
(test-equal #f (point? (make-blob 9)))
(test-equal #f (blob? (make-point 1 2)))
;; accessor/mutator on non-records raise
(test-equal #t (guard (e (#t (error-object? e))) (point-x 42) #f))
(test-equal #t (guard (e (#t (error-object? e))) (set-point-x! "p" 1) #f))
;; R7RS 5.5: "It is an error to pass an accessor a value which is not a
;; record of the appropriate type."
(test-equal #t (guard (e (#t (error-object? e))) (point-x (make-blob 9)) #f))
(test-equal #t (guard (e (#t (error-object? e))) (set-point-x! (make-blob 9) 42) #f))

;; internal record primitives reject garbage directly
(test-equal #t (guard (e (#t (error-object? e))) (%record-ref 5 0 #t) #f))
(test-equal #t (guard (e (#t (error-object? e))) (%record-set! 5 0 99 #t) #f))
(test-equal #t (guard (e (#t (error-object? e))) (%make-record 5) #f))

(let ((runner (test-runner-current)))
  (test-end "primitives_core audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
