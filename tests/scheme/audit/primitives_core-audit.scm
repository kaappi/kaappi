;; Audit tests for src/primitives.zig (core) — audit Phase 2.18
;; Pairs/lists, type predicates, equivalence, not, core string ops, apply,
;; and the internal record primitives behind define-record-type.
;; See docs/audit-strategy.md. Run directly and read the pass/fail counts:
;;   zig-out/bin/kaappi tests/scheme/audit/primitives_core-audit.scm

(import (scheme base) (chibi test))

(test-begin "primitives_core audit")

;;; --- cons / car / cdr ---
(test '(1 . 2) (cons 1 2))
(test '(1 2) (cons 1 (cons 2 '())))
(test 1 (car (cons 1 2)))
(test 2 (cdr (cons 1 2)))
(test #t (guard (e (#t (error-object? e))) (car '()) #f))
(test #t (guard (e (#t (error-object? e))) (cdr '()) #f))
(test #t (guard (e (#t (error-object? e))) (car 5) #f))
(test #t (guard (e (#t (error-object? e))) (cdr "pair") #f))

;;; --- set-car! / set-cdr! ---
(let ((p (list 1 2)))
  (set-car! p 'x)
  (test '(x 2) p))
(let ((p (list 1 2)))
  (set-cdr! p 3)
  (test '(1 . 3) p))
(test #t (guard (e (#t (error-object? e))) (set-car! '() 1) #f))
(test #t (guard (e (#t (error-object? e))) (set-cdr! 5 1) #f))

;;; --- list ---
(test '() (list))
(test '(1 2 3) (list 1 2 3))
(test '((1 2) (3)) (list (list 1 2) (list 3)))

;;; --- length ---
(test 0 (length '()))
(test 3 (length '(a b c)))
(test #t (guard (e (#t (error-object? e))) (length '(1 2 . 3)) #f))
(test #t (guard (e (#t (error-object? e))) (length 5) #f))
(test #t (guard (e (#t (error-object? e))) (length "abc") #f))
;; circular list: Floyd detection raises instead of hanging
(let ((c (list 1 2)))
  (set-cdr! (cdr c) c)
  (test #t (guard (e (#t (error-object? e))) (length c) #f)))

;;; --- append ---
(test '() (append))
(test '(1 2 3 4) (append '(1 2) '(3 4)))
(test '(1 2 3 4 5) (append '(1) '() '(2 3) '() '(4 5)))
;; single argument returned as-is (shared)
(let ((l (list 1 2)))
  (test #t (eq? l (append l))))
;; R7RS 6.4: the result "shares structure with the last argument"
(let ((tl (list 1 2)))
  (test #t (eq? tl (cddr (append '(a b) tl)))))
;; ...but earlier arguments are copied, not shared
(let ((src (list 1 2)))
  (test #f (eq? src (append src '()))))
;; last argument can be any object (improper result)
(test '(1 2 . 3) (append '(1 2) 3))
(test 5 (append 5))
(test 'x (append '() 'x))
;; non-last arguments must be proper lists
(test #t (guard (e (#t (error-object? e))) (append '(1 . 2) '(3)) #f))
(test #t (guard (e (#t (error-object? e))) (append 5 '(3)) #f))
;; circular non-last argument hangs with unbounded allocation:
;; FAIL: #1198 (append lacks cycle detection on non-last arguments)
;; (let ((c (list 1 2)))
;;   (set-cdr! (cdr c) c)
;;   (test #t (guard (e (#t (error-object? e))) (append c '(9)) #f)))

;;; --- reverse ---
(test '() (reverse '()))
(test '(c b a) (reverse '(a b c)))
(test '((3) (1 2)) (reverse (list (list 1 2) (list 3))))
(test #t (guard (e (#t (error-object? e))) (reverse '(1 2 . 3)) #f))
(test #t (guard (e (#t (error-object? e))) (reverse 5) #f))
;; circular argument hangs with unbounded allocation:
;; FAIL: #1198 (reverse lacks cycle detection)
;; (let ((c (list 1 2)))
;;   (set-cdr! (cdr c) c)
;;   (test #t (guard (e (#t (error-object? e))) (reverse c) #f)))

;;; --- caar / cadr / cdar / cddr ---
(test 1 (caar '((1 2) 3)))
(test 3 (cadr '((1 2) 3)))
(test '(2) (cdar '((1 2) 3)))
(test '() (cddr '((1 2) 3)))
(test #t (guard (e (#t (error-object? e))) (caar '(1 2)) #f))
(test #t (guard (e (#t (error-object? e))) (cadr '(1)) #f))
(test #t (guard (e (#t (error-object? e))) (cdar '(1 2)) #f))
(test #t (guard (e (#t (error-object? e))) (cddr '(1)) #f))
(test #t (guard (e (#t (error-object? e))) (caar '()) #f))

;;; --- type predicates: pair? null? list? ---
(test #t (pair? '(1)))
(test #t (pair? '(1 . 2)))
(test #f (pair? '()))
(test #f (pair? 5))
(test #f (pair? #(1)))
(test #t (null? '()))
(test #f (null? '(1)))
(test #f (null? #f))
(test #f (null? 0))
(test #f (null? ""))
(test #t (list? '()))
(test #t (list? '(1 2 3)))
(test #f (list? '(1 . 2)))
(test #f (list? 5))
(test #f (list? "abc"))
;; circular: list? must return #f and terminate (R7RS 6.4)
(let ((c (list 1 2)))
  (set-cdr! (cdr c) c)
  (test #f (list? c)))

;;; --- numeric tower predicates (R7RS 6.2.6 examples) ---
(test #t (number? 3))
(test #t (number? 3.5))
(test #t (number? (expt 2 100)))
(test #t (number? 1/3))
(test #f (number? "3"))
(test #f (number? #\3))
(test #t (complex? 3))
(test #t (complex? 3.5))
(test #t (real? 3))
(test #t (real? +nan.0))
(test #t (real? +inf.0))
(test #t (rational? 6/10))
(test #t (rational? 6/3))
(test #t (rational? 3.5))
(test #f (rational? -inf.0))
(test #f (rational? +nan.0))
(test #t (integer? 3))
(test #t (integer? 3.0))
(test #t (integer? 8/4))
(test #t (integer? (expt 2 100)))
(test #f (integer? 8/5))
(test #f (integer? 3.5))
(test #f (integer? +nan.0))
(test #f (integer? +inf.0))

;;; --- other predicates ---
(test #t (symbol? 'a))
(test #f (symbol? "a"))
(test #f (symbol? #\a))
(test #t (string? "a"))
(test #t (string? ""))
(test #f (string? 'a))
(test #t (boolean? #t))
(test #t (boolean? #f))
(test #f (boolean? 0))
(test #f (boolean? '()))
(test #t (char? #\a))
(test #t (char? #\x3bb))
(test #f (char? "a"))
(test #t (procedure? car))
(test #t (procedure? (lambda (x) x)))
(test #t (call-with-current-continuation procedure?))
(test #f (procedure? 'car))
(test #f (procedure? '(lambda (x) x)))

;;; --- eq? ---
(test #t (eq? 'a 'a))
(test #t (eq? '() '()))
(test #t (eq? car car))
(test #f (eq? (list 'a) (list 'a)))
(test #t (let ((x '(a))) (eq? x x)))
(test #t (let ((s "s")) (eq? s s)))
(test #f (eq? 'a 'b))
(test #t (eq? #t #t))
(test #f (eq? #t #f))

;;; --- eqv? (R7RS 6.1) ---
(test #t (eqv? 'a 'a))
(test #t (eqv? 2 2))
(test #f (eqv? 2 2.0))
(test #t (eqv? 100000000 100000000))
(test #f (eqv? 1/2 0.5))
(test #t (eqv? 1/3 1/3))
(test #t (eqv? (expt 2 100) (expt 2 100)))
(test #t (eqv? (/ (expt 2 100) 3) (/ (expt 2 100) 3)))
(test #t (eqv? #\a #\a))
(test #f (eqv? #\a #\b))
(test #t (eqv? '() '()))
(test #f (eqv? (cons 1 2) (cons 1 2)))
(test #f (eqv? #f 'nil))
(test #t (let ((p (lambda (x) x))) (eqv? p p)))
;; inexact bitwise comparison (both allowed by R7RS; regression-lock current)
(test #t (eqv? +nan.0 +nan.0))
(test #f (eqv? 0.0 -0.0))
(test #t (eqv? 1.5 1.5))

;;; --- equal? (R7RS 6.1) ---
(test #t (equal? 'a 'a))
(test #t (equal? '(a) '(a)))
(test #t (equal? '(a (b) c) '(a (b) c)))
(test #t (equal? "abc" "abc"))
(test #t (equal? "" ""))
(test #t (equal? 2 2))
(test #f (equal? 2 2.0))
(test #t (equal? (make-vector 5 'a) (make-vector 5 'a)))
(test #t (equal? #() #()))
(test #f (equal? #(1 2) #(1 2 3)))
(test #t (equal? (bytevector 1 2 3) (bytevector 1 2 3)))
(test #f (equal? (bytevector 1 2 3) (bytevector 1 2 4)))
(test #t (equal? (list (expt 2 100)) (list (expt 2 100))))
(test #t (equal? (list 1/3 (vector 2/7)) (list 1/3 (vector 2/7))))
(test #f (equal? '(1 2) '(1 2 3)))
(test #f (equal? #(1 2) '(1 2)))
;; R7RS: "equal? must always terminate, even if its arguments are circular"
(let ((c1 (list 1 2)) (c2 (list 1 2 1 2)))
  (set-cdr! (cdr c1) c1)
  (set-cdr! (cdddr c2) c2)
  (test #t (boolean? (equal? c1 c2)))
  (test #f (equal? c1 '(1 2 1 2))))
;; equal? after width-changing string mutation (rebuilt buffer)
(let ((s (make-string 3 #\a)))
  (string-set! s 0 #\x3bb)
  (test #t (equal? s (string #\x3bb #\a #\a)))
  (string-set! s 0 #\b)
  (test #t (equal? s "baa")))

;;; --- not ---
(test #t (not #f))
(test #f (not #t))
(test #f (not '()))
(test #f (not 0))
(test #f (not "" ))
(test #f (not not))
(test #f (not '(f)))

;;; --- string-length (UTF-8 codepoint semantics) ---
(test 0 (string-length ""))
(test 3 (string-length "abc"))
(test 3 (string-length "aλb"))
(test 3 (string-length "a\x1D11E;b"))          ; astral plane
(test 2 (string-length "e\x0301;"))            ; combining mark counts separately
(test #t (guard (e (#t (error-object? e))) (string-length 'abc) #f))

;;; --- string-append ---
(test "" (string-append))
(test "abc" (string-append "abc"))
(test "abcdef" (string-append "abc" "" "def"))
(test 2 (string-length (string-append "λ" "\x1D11E;")))
(test #t (guard (e (#t (error-object? e))) (string-append "a" 5) #f))
;; result is freshly allocated and mutable; source unchanged
(let* ((src "ab")
       (out (string-append src)))
  (string-set! out 0 #\x)
  (test "ab" src)
  (test "xb" out))

;;; --- symbol->string ---
(test "abc" (symbol->string 'abc))
(test #t (eq? 'héllo (string->symbol (symbol->string 'héllo))))
(test #t (guard (e (#t (error-object? e))) (symbol->string "abc") #f))
;; R7RS 6.5: "it is an error to apply mutation procedures like string-set!
;; to strings returned by this procedure"
(test #t (guard (e (#t (error-object? e)))
           (string-set! (symbol->string 'foo) 0 #\x) #f))

;;; --- apply ---
(test 10 (apply + '(1 2 3 4)))
(test 10 (apply + 1 2 '(3 4)))
(test 0 (apply + '()))
(test '(1 . 2) (apply cons '(1 2)))
(test 7 (apply (lambda (a b) (+ a b)) '(3 4)))
;; large argument list
(let loop ((i 0) (acc '()))
  (if (= i 1000)
      (test 1000 (apply + acc))
      (loop (+ i 1) (cons 1 acc))))
;; errors
(test #t (guard (e (#t (error-object? e))) (apply 7 '(1)) #f))
(test #t (guard (e (#t (error-object? e))) (apply + 5) #f))
(test #t (guard (e (#t (error-object? e))) (apply + '(1 2 . 3)) #f))
;; circular final list: apply in TAIL position compiles to the tail_apply
;; opcode, which bounds out with a catchable error
(let ((c (list 1 2)))
  (set-cdr! (cdr c) c)
  (test 'caught (guard (e (#t 'caught)) (apply + c))))
;; ...but in non-tail position the native applyFn walks the circular final
;; list forever with unbounded allocation:
;; FAIL: #1198 (native applyFn lacks cycle detection on the final list)
;; (let ((c (list 1 2)))
;;   (set-cdr! (cdr c) c)
;;   (test #t (guard (e (#t #t)) (apply + c) #f)))

;;; --- records (define-record-type over %record primitives) ---
(define-record-type point (make-point x y) point? (x point-x set-point-x!) (y point-y))
(define-record-type blob (make-blob v) blob? (v blob-v))

(let ((p (make-point 1 2)))
  (test #t (point? p))
  (test 1 (point-x p))
  (test 2 (point-y p))
  (set-point-x! p 10)
  (test 10 (point-x p)))
(test #f (point? 5))
(test #f (point? '(1 2)))
(test #f (point? (make-blob 9)))
(test #f (blob? (make-point 1 2)))
;; accessor/mutator on non-records raise
(test #t (guard (e (#t (error-object? e))) (point-x 42) #f))
(test #t (guard (e (#t (error-object? e))) (set-point-x! "p" 1) #f))
;; R7RS 5.5: "It is an error to pass an accessor a value which is not a
;; record of the appropriate type." — cross-type access is silently accepted:
;; FAIL: #1199 (record accessors/mutators do not check the record type)
;; (test #t (guard (e (#t (error-object? e))) (point-x (make-blob 9)) #f))
;; FAIL: #1199 (record accessors/mutators do not check the record type)
;; (test #t (guard (e (#t (error-object? e))) (set-point-x! (make-blob 9) 42) #f))

;; internal record primitives reject garbage directly
(test #t (guard (e (#t (error-object? e))) (%record-ref 5 0) #f))
(test #t (guard (e (#t (error-object? e))) (%make-record 5) #f))

(test-end "primitives_core audit")
