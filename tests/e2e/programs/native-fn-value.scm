; Native closure values for compiled defines (#1500).
;
; A fixed-arity define's global binding is now a native closure over the
; compiled entry rather than an eval'd interpreter closure. Every use of the
; NAME as a value — passing it to a higher-order procedure, apply, eq? identity,
; procedure?, returning it from another function — must behave exactly like the
; interpreter. The e2e harness diffs this program's native output against the
; interpreter, so any divergence in native-closure-value semantics fails here.
(import (scheme base) (scheme write))

(define (sq x) (* x x))                 ; sugared fixed-arity define
(define add (lambda (a b) (+ a b)))     ; un-sugared lambda-valued define

; Used as a value: map / apply over the compiled entry.
(display (map sq '(1 2 3 4 5))) (newline)
(display (apply add '(30 12))) (newline)

; eq? identity: one global binding, so the value is eq? to itself, and two
; distinct functions are not eq?.
(display (eq? sq sq)) (newline)
(display (eq? sq add)) (newline)
(display (procedure? sq)) (newline)

; Written representation matches the interpreter (#<procedure name>).
(write sq) (newline)

; Returned as a value from another compiled function, then called.
(define (pick which)
  (if (eq? which 'sq) sq add))
(display ((pick 'sq) 9)) (newline)
(display ((pick 'add) 4 5)) (newline)

; Fold using a compiled binary function as the accumulator.
(define (fold-left f acc lst)
  (if (null? lst) acc (fold-left f (f acc (car lst)) (cdr lst))))
(display (fold-left add 0 '(1 2 3 4 5 6 7 8 9 10))) (newline)

; A function whose body returns a quoted constant, used as a VALUE. Its value is
; a native closure (a quote is not a code fallback), so invoking it from the
; interpreter's eval runs the native body, whose kaappi_quote_cached re-enters
; the evaluator — which must not clobber the suspended outer form. (Before the
; #1500 re-entrancy fix this corrupted the outer form / crashed with "car: not a
; pair".) The quote cache also makes every call return the SAME object (eq?),
; matching the interpreter.
(define (digits) '(1 2 3))
(define ds (digits))
(display (car ds)) (newline)
(display (eq? (digits) (digits))) (newline)
(display (map (lambda (_) (car (digits))) '(a b c))) (newline)

; A function whose body reaches a CODE eval fallback (a variadic inner lambda)
; keeps its correctly-capturing interpreter-closure value: separate activations
; must NOT alias (this is the #1500 gate — a native closure value would share
; the bindParamsAsGlobals republished binding and return 3 3 3 here).
(define (make-const u) ((lambda (x) (lambda (c . r) x)) u))
(define a (make-const 1))
(define b (make-const 2))
(define c (make-const 3))
(display (list (a 0) (b 0) (c 0))) (newline)

; Same, with a letrec body used as a value.
(define (sumdown n)
  (letrec ((go (lambda (k acc) (if (= k 0) acc (go (- k 1) (+ acc k))))))
    (go n 0)))
(display (map sumdown '(1 2 3 4))) (newline)
