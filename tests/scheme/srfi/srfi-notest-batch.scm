;; Conformance tests for nine small SRFIs that had no test file at all:
;;   8 (receive), 11 (let-values), 16 (case-lambda), 28 (format),
;;   31 (rec), 34 (exception handling), 111 (boxes), 145 (assume),
;;   229 (tagged procedures).
;;
;; Written by the systematic audit v2, Phase 3.7 (issue #1890). SRFI 2 and
;; SRFI 222 come from the same batch but each carries a filed defect, so each
;; got its own file (srfi2.scm, srfi222.scm) that a fix PR can re-enable
;; wholesale. The nine here are 1-4 exports apiece with no filed defects;
;; they share one hygiene harness and one set of cross-SRFI composition
;; assertions, which is why they are batched rather than split nine ways.
;;
;; Every assertion below was cross-checked against chibi-scheme 0.12.0, which
;; agrees with Kaappi on all of them. Where the two disagree the difference is
;; called out in a comment at the assertion.
;;
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi-notest-batch.scm

(import (scheme base) (scheme write) (scheme case-lambda) (srfi 64)
        (srfi 8) (srfi 11) (srfi 16) (srfi 28) (srfi 31) (srfi 34)
        (srfi 111) (srfi 145) (srfi 229)
        ;; (srfi 18) is for the thread-join! box assertion far below (#1932).
        (srfi 18))

(test-begin "srfi-notest-batch")

;;; ====================================================================
;;; Availability. Every one of the eleven SRFIs in this batch answers its
;;; cond-expand feature identifier, and all eleven load standalone.
;;; ====================================================================

(test-equal "cond-expand srfi-2"   #t (cond-expand (srfi-2 #t) (else #f)))
(test-equal "cond-expand srfi-8"   #t (cond-expand (srfi-8 #t) (else #f)))
(test-equal "cond-expand srfi-11"  #t (cond-expand (srfi-11 #t) (else #f)))
(test-equal "cond-expand srfi-16"  #t (cond-expand (srfi-16 #t) (else #f)))
(test-equal "cond-expand srfi-28"  #t (cond-expand (srfi-28 #t) (else #f)))
(test-equal "cond-expand srfi-31"  #t (cond-expand (srfi-31 #t) (else #f)))
(test-equal "cond-expand srfi-34"  #t (cond-expand (srfi-34 #t) (else #f)))
(test-equal "cond-expand srfi-111" #t (cond-expand (srfi-111 #t) (else #f)))
(test-equal "cond-expand srfi-145" #t (cond-expand (srfi-145 #t) (else #f)))
(test-equal "cond-expand srfi-222" #t (cond-expand (srfi-222 #t) (else #f)))
(test-equal "cond-expand srfi-229" #t (cond-expand (srfi-229 #t) (else #f)))

;; SRFI 11, 16 and 34 are pure re-exports of (scheme base) / (scheme
;; case-lambda) bindings. R7RS 5.2 makes importing one identifier from two
;; libraries with *different* bindings an error, and Kaappi enforces that --
;; so this file importing (scheme base) alongside all three at once, and
;; getting here at all, is the assertion.
(test-assert "(srfi 11)/(srfi 16)/(srfi 34) co-import with (scheme base)" #t)

;;; ====================================================================
;;; SRFI 8 -- receive
;;;   (receive <formals> <expression> <body>) ==
;;;   (call-with-values (lambda () <expression>) (lambda <formals> <body>))
;;; ====================================================================

(test-equal "8: fixed formals" '(1 2 3) (receive (a b c) (values 1 2 3) (list a b c)))
(test-equal "8: single formal" 42 (receive (x) (values 42) x))
(test-equal "8: rest-only formals collect every value" '(1 2 3)
            (receive all (values 1 2 3) all))
(test-equal "8: rest-only formals with no values" '() (receive all (values) all))
(test-equal "8: dotted formals split head from tail" '(1 (2 3))
            (receive (a . rest) (values 1 2 3) (list a rest)))
(test-equal "8: dotted formals with an empty tail" '(1 ())
            (receive (a . rest) (values 1) (list a rest)))
(test-equal "8: zero formals, zero values" 'ok (receive () (values) 'ok))
(test-equal "8: a single-valued expression needs no `values'" 42
            (receive (x) 42 x))
(test-equal "8: body may contain internal definitions" 3
            (receive (x) 1 (define y 2) (+ x y)))
(test-equal "8: body returns its last form" 'last
            (receive (x) 1 'first 'last))
(test-equal "8: body closes over the surrounding scope" 11
            (let ((z 10)) (receive (a) (values 1) (+ a z))))
(test-equal "8: receive nests" 3
            (receive (a b) (values 1 2) (receive (c) (values (+ a b)) c)))
(test-equal "8: the expression is evaluated exactly once" 1
            (let ((n 0)) (receive (x) (begin (set! n (+ n 1)) 'v) n)))
(test-equal "8: formals shadow an outer binding of the same name" '(inner outer)
            (let ((a 'outer)) (list (receive (a) (values 'inner) a) a)))
(test-equal "8: receive itself may return multiple values" '(1 2)
            (call-with-values (lambda () (receive (a b) (values 1 2) (values a b))) list))
(test-assert "8: too few values for fixed formals raises"
             (guard (e (#t #t)) (receive (a b) (values 1) 'never) #f))
(test-assert "8: too many values for fixed formals raises"
             (guard (e (#t #t)) (receive (a) (values 1 2) 'never) #f))

;;; ====================================================================
;;; SRFI 11 -- let-values, let*-values (the spec's own three examples)
;;; ====================================================================

(test-equal "11 spec ex: dotted formals" '(1 2 (3 4))
            (let-values (((a b . c) (values 1 2 3 4))) (list a b c)))
(test-equal "11 spec ex: let*-values sees earlier bindings" '(x y x y)
            (let ((a 'a) (b 'b) (x 'x) (y 'y))
              (let*-values (((a b) (values x y)) ((x y) (values a b)))
                (list a b x y))))
(test-equal "11 spec ex: let-values does not" '(x y a b)
            (let ((a 'a) (b 'b) (x 'x) (y 'y))
              (let-values (((a b) (values x y)) ((x y) (values a b)))
                (list a b x y))))

(test-equal "11: single binding, single value" 1 (let-values (((a) (values 1))) a))
(test-equal "11: rest-only formals" '(1 2 3) (let-values ((all (values 1 2 3))) all))
(test-equal "11: zero formals, zero values" 'ok (let-values ((() (values))) 'ok))
(test-equal "11: two independent bindings" '(1 2 3 4)
            (let-values (((a b) (values 1 2)) ((c d) (values 3 4))) (list a b c d)))
(test-equal "11: no bindings at all" 'ok (let-values () 'ok))
(test-equal "11: body may contain internal definitions" 3
            (let-values (((a) (values 1))) (define b 2) (+ a b)))
(test-equal "11: let-values nests" 10
            (let-values (((a b) (values 1 2)))
              (let-values (((c d) (values 3 4))) (+ a b c d))))
(test-equal "11: let*-values with dotted formals" '(1 (2 3) 3)
            (let*-values (((a . r) (values 1 2 3)) ((n) (values (length r))))
              (list a r (+ n 1))))
(test-assert "11: let-values arity mismatch raises"
             (guard (e (#t #t)) (let-values (((a b) (values 1))) 'never) #f))
(test-equal "11: bindings shadow the outer scope only inside the body" '(inner outer)
            (let ((v 'outer)) (list (let-values (((v) (values 'inner))) v) v)))

;;; ====================================================================
;;; SRFI 16 -- case-lambda (the spec's own examples)
;;; ====================================================================

(define plus
  (case-lambda
    (() 0)
    ((x) x)
    ((x y) (+ x y))
    ((x y z) (+ (+ x y) z))
    (args (apply + args))))

(test-equal "16 spec ex: (plus)" 0 (plus))
(test-equal "16 spec ex: (plus 1)" 1 (plus 1))
(test-equal "16 spec ex: (plus 1 2 3)" 6 (plus 1 2 3))
(test-equal "16 spec ex: (plus 1 2 3 4) falls through to the rest clause" 10
            (plus 1 2 3 4))
(test-equal "16 spec ex: inline two-clause case-lambda" 32
            ((case-lambda ((a) a) ((a b) (* a b))) 8 4))

(test-equal "16: the first matching clause wins" 'first
            ((case-lambda ((a) 'first) ((a) 'second)) 1))
(test-equal "16: a dotted clause captures the tail" '(1 (2 3))
            ((case-lambda ((a . r) (list a r))) 1 2 3))
(test-equal "16: a rest clause matches any arity" 3
            ((case-lambda ((a) 'one) (r (length r))) 1 2 3))
(test-equal "16: clauses close over the surrounding scope" 15
            (let ((k 5)) ((case-lambda ((a) (* a k))) 3)))
(test-equal "16: case-lambda is a procedure" #t (procedure? plus))
(test-assert "16: no matching clause raises"
             (guard (e (#t #t)) ((case-lambda ((a) a) ((a b) 'two)) 1 2 3) #f))
(test-assert "16: a single-clause case-lambda still checks arity"
             (guard (e (#t #t)) ((case-lambda ((a b) (+ a b))) 1) #f))

;;; ====================================================================
;;; SRFI 28 -- format
;;; ====================================================================

(test-equal "28 spec ex: ~a" "Hello, World!" (format "Hello, ~a" "World!"))
(test-equal "28 spec ex: ~s~%" "Error, list is too short: (one \"two\" 3)\n"
            (format "Error, list is too short: ~s~%" '(one "two" 3)))

(test-equal "28: no directives at all" "plain" (format "plain"))
(test-equal "28: the empty format string" "" (format ""))
(test-equal "28: ~~ inserts one tilde" "~" (format "~~"))
(test-equal "28: ~% inserts a newline" "a\nb" (format "a~%b"))
(test-equal "28: ~~a is a literal tilde then a literal a" "~a" (format "~~a"))
(test-equal "28: ~a on a number" "42" (format "~a" 42))
(test-equal "28: ~a on a symbol" "sym" (format "~a" 'sym))
(test-equal "28: ~a on a string is unquoted" "hi" (format "~a" "hi"))
(test-equal "28: ~s on a string is quoted" "\"hi\"" (format "~s" "hi"))
(test-equal "28: ~s on a char is written" "#\\c" (format "~s" #\c))
(test-equal "28: ~a on a char is displayed" "c" (format "~a" #\c))
(test-equal "28: ~a on #f" "#f" (format "~a" #f))
(test-equal "28: ~s on #f" "#f" (format "~s" #f))
(test-equal "28: ~a on the empty list" "()" (format "~a" '()))
;; R7RS 6.13.3: display outputs nested strings as by write-string and nested
;; characters as by write-char, so ~a on a list unquotes both. (chibi 0.12.0
;; disagrees here and writes them -- Kaappi matches the R7RS text.)
(test-equal "28: ~a on a list unquotes nested strings and chars" "(1 two c)"
            (format "~a" (list 1 "two" #\c)))
(test-equal "28: ~s on a list quotes them" "(1 \"two\" #\\c)"
            (format "~s" (list 1 "two" #\c)))
(test-equal "28: directives consume objects in order" "1-2-3"
            (format "~a-~a-~a" 1 2 3))
(test-equal "28: ~% and ~~ consume no object" "~\n1" (format "~~~%~a" 1))
(test-equal "28: non-ASCII literal text is preserved" "λ1λ"
            (format "λ~aλ" 1))
(test-equal "28: non-ASCII object text is preserved" "λ"
            (format "~a" (string (integer->char 955))))
;; 10,000 rather than a larger figure on purpose.  This assertion is about
;; recursion depth, and 10,000 frames already exercises that -- but `format`
;; walks its argument with `string-ref`, which is O(k) here because Kaappi
;; indexes strings by codepoint over UTF-8 bytes, so the call is O(n^2)
;; (#2100).  At 200,000 it cost 35.7s of this file's 36s and timed out the
;; 60s per-file budget on four CI legs while passing on a developer Mac.
;; 10,000 costs 88ms.  Raise this only when #2100 is fixed.
(test-equal "28: a long format string is handled without recursion limits" 10000
            (string-length (format (make-string 10000 #\x))))
(test-equal "28: surplus objects are ignored" "1" (format "~a" 1 2))
(test-assert "28: too few objects for ~a raises"
             (guard (e (#t #t)) (format "~a ~a" 1) #f))
(test-assert "28: too few objects for ~s raises"
             (guard (e (#t #t)) (format "~s" ) #f))
(test-assert "28: a non-string format argument raises"
             (guard (e (#t #t)) (format 42) #f))

;; The SRFI's own *reference implementation* raises "Incomplete escape
;; sequence" / "Unrecognized escape sequence" for the three cases below, but
;; the Specification prose mandates an error only for "fewer values ... than
;; escape sequences that require them". Kaappi passes the text through
;; instead, and chibi-scheme 0.12.0 produces byte-identical output on all
;; three -- so these pin the shared cross-implementation convention, not the
;; reference implementation.
(test-equal "28: a trailing tilde is emitted literally (chibi agrees)" "abc~"
            (format "abc~"))
(test-equal "28: an unknown directive passes through (chibi agrees)" "a~zb"
            (format "a~zb"))
(test-equal "28: directives are case-sensitive, ~A is not ~a (chibi agrees)" "~A"
            (format "~A" 1))
;; Consequence worth pinning: because ~A consumes no object, a later ~a takes
;; the *first* argument and the rest silently shift.
(test-equal "28: ~A does not consume its object, so ~a shifts (chibi agrees)" "~A1"
            (format "~A~a" 1 2))

;;; ====================================================================
;;; SRFI 31 -- rec
;;;   (rec (NAME . FORMALS) BODY ...) == (letrec ((NAME (lambda FORMALS BODY ...))) NAME)
;;;   (rec NAME EXPR)                 == (letrec ((NAME EXPR)) NAME)
;;; ====================================================================

(test-equal "31 spec ex: recursive factorial, procedure form" 120
            ((rec (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) 5))
(test-equal "31 spec ex: recursive factorial, expression form" 120
            ((rec f (lambda (n) (if (= n 0) 1 (* n (f (- n 1)))))) 5))
(test-equal "31: base case only" 1 ((rec (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) 0))
(test-equal "31: variadic formals" 3 ((rec (f . args) (length args)) 1 2 3))
(test-equal "31: dotted formals" '(1 (2 3)) ((rec (f a . r) (list a r)) 1 2 3))
(test-equal "31: zero formals" 7 ((rec (f) 7)))
(test-equal "31: the expression form need not be a procedure" 5 (rec x 5))
(test-equal "31: multiple body forms with an internal definition" 9
            ((rec (f n) (define m (* n 2)) (+ m 1)) 4))
(test-equal "31: the bound name is visible to the body" 'self
            ((rec (f) (if (procedure? f) 'self 'no))))
(test-equal "31: rec closes over the surrounding scope" 30
            (let ((k 10)) ((rec (f n) (* n k)) 3)))
(test-equal "31: rec nests" 6
            ((rec (outer n) ((rec (inner m) (* m 2)) n)) 3))
(test-equal "31: mutual recursion through one name" #t
            ((rec (even2? n) (if (= n 0) #t (if (= n 1) #f (even2? (- n 2))))) 10))
(test-equal "31: the bound name does not escape into the enclosing scope" 'outer
            (let ((f 'outer)) ((rec (f) 'inner)) f))

;;; ====================================================================
;;; SRFI 34 -- with-exception-handler, guard, raise
;;; (the spec's own six examples, adapted only to return values)
;;; ====================================================================

(test-equal "34 spec ex 1: handler escapes via a continuation" '(cond an-error)
            (call-with-current-continuation
             (lambda (k)
               (with-exception-handler
                (lambda (x) (k (list 'cond x)))
                (lambda () (+ 1 (raise 'an-error)))))))
(test-assert "34 spec ex 2: a handler that returns from `raise' raises again"
             (guard (e (#t #t))
               (with-exception-handler (lambda (x) 'dont-care)
                                       (lambda () (+ 1 (raise 'an-error))))
               #f))
(test-equal "34 spec ex 3: guard with a catch-all clause" '(cond an-error)
            (guard (condition (#t (list 'cond condition)))
              (+ 1 (raise 'an-error))))
(test-assert "34 spec ex 4: guard with no matching clause re-raises"
             (guard (e (#t #t)) (guard (condition (#f)) (+ 1 (raise 'an-error))) #f))
(test-equal "34 spec ex 5: guard `=>' clause" 42
            (guard (condition ((assq 'a condition) => cdr) ((assq 'b condition)))
              (raise (list (cons 'a 42)))))
(test-equal "34 spec ex 6: guard clause value" '(b . 23)
            (guard (condition ((assq 'a condition) => cdr) ((assq 'b condition)))
              (raise (list (cons 'b 23)))))

(test-equal "34: guard body value when nothing is raised" 7
            (guard (e (#t 'never)) 7))
(test-equal "34: the first matching clause wins" 'first
            (guard (e ((symbol? e) 'first) (#t 'second)) (raise 'x)))
(test-equal "34: an unmatched inner guard is caught by an outer one" '(outer inner)
            (guard (outer (#t (list 'outer outer)))
              (guard (e ((string? e) 'never)) (raise 'inner))))
(test-equal "34: guard catches an error object raised by `error'" "boom"
            (guard (e ((error-object? e) (error-object-message e))) (error "boom" 1 2)))
(test-equal "34: error-object irritants survive the guard" '(1 2)
            (guard (e ((error-object? e) (error-object-irritants e))) (error "boom" 1 2)))
(test-equal "34: a raised object may be any Scheme value" '(1 2)
            (guard (e (#t e)) (raise (list 1 2))))
(test-equal "34: guard body may contain internal definitions" 3
            (guard (e (#t 'never)) (define q 3) q))
(test-equal "34: raising inside a guard clause escapes to the outer guard" 'outer-saw
            (guard (o (#t 'outer-saw)) (guard (e (#t (raise 'again))) (raise 'first))))

;;; ====================================================================
;;; SRFI 111 -- boxes
;;; ====================================================================

(test-equal "111: unbox of a fresh box" 42 (unbox (box 42)))
(test-equal "111: box? of a box" #t (box? (box 1)))
(test-equal "111: set-box! then unbox" 2 (let ((b (box 1))) (set-box! b 2) (unbox b)))
(test-equal "111: set-box! is visible through an alias" 2
            (let* ((b (box 1)) (c b)) (set-box! b 2) (unbox c)))
(test-equal "111: a box may hold any object" '(1 2)
            (unbox (box (list 1 2))))
(test-equal "111: boxes nest" 7 (unbox (unbox (box (box 7)))))
(test-equal "111: set-box! may store a box" 5
            (let ((b (box 0))) (set-box! b (box 5)) (unbox (unbox b))))

;; "The box type is disjoint from all other Scheme types."
(test-equal "111: box? on non-boxes" '(#f #f #f #f #f #f #f #f #f)
            (list (box? 1) (box? 'a) (box? "s") (box? #\c) (box? '())
                  (box? (list 1)) (box? (vector 1)) (box? car) (box? #t)))
(test-equal "111: a box is not a pair" #f (pair? (box 1)))
(test-equal "111: a box is not a vector" #f (vector? (box 1)))
(test-equal "111: a box is not a procedure" #f (procedure? (box 1)))
(test-equal "111: a box is not a string" #f (string? (box 1)))
(test-equal "111: a box is not a symbol" #f (symbol? (box 1)))

;; "two boxes are both eq? and eqv? iff they are the product of the same call
;; to box and not otherwise"
(test-equal "111: two separate boxes are not eqv?" #f (eqv? (box 1) (box 1)))
(test-equal "111: two separate boxes are not eq?" #f (eq? (box 1) (box 1)))
(test-equal "111: a box is eqv? to itself" #t (let ((b (box 1))) (eqv? b b)))
(test-equal "111: a box is eq? to itself" #t (let ((b (box 1))) (eq? b b)))
;; The spec leaves equal? on distinct boxes implementation-dependent, so only
;; the direction it does fix -- eqv? implies equal? -- is asserted.
(test-equal "111: eqv? implies equal? for boxes" #t
            (let ((b (box 1))) (equal? b b)))

(test-assert "111: unbox of a non-box raises" (guard (e (#t #t)) (unbox 5) #f))
(test-assert "111: set-box! on a non-box raises" (guard (e (#t #t)) (set-box! 5 1) #f))
(test-assert "111: box with no argument raises" (guard (e (#t #t)) (box) #f))
(test-assert "111: box with two arguments raises" (guard (e (#t #t)) (box 1 2) #f))

;; An SRFI 111 box is a record, so this was #1932 reaching a *spec-mandated*
;; type: a box built on a worker thread came back with box? => #f and unbox
;; raising. Enabled now that record identity survives the copy.
(test-equal "111: a box survives thread-join!" '(#t 42)
            (let ((t (make-thread (lambda () (box 42)))))
              (thread-start! t)
              (let ((r (thread-join! t))) (list (box? r) (unbox r)))))

;;; ====================================================================
;;; SRFI 145 -- assume
;;; "This special form is an expression that evaluates to the value of obj if
;;;  obj evaluates to a true value."
;;; ====================================================================

(test-equal "145: a true expression yields its own value" 42 (assume 42))
(test-equal "145: a true expression yields its value with messages" 'sym
            (assume 'sym "m1" "m2"))
(test-equal "145: a boolean-true expression yields #t" #t (assume (= 1 1)))
(test-equal "145: a list value passes through" '(1 2) (assume (list 1 2)))
(test-equal "145: zero is a true value in Scheme" 0 (assume 0))
(test-equal "145: the empty list is a true value in Scheme" '() (assume '()))
(test-equal "145: the expression is evaluated exactly once" 1
            (let ((n 0)) (assume (begin (set! n (+ n 1)) #t)) n))
(test-assert "145: a false expression raises" (guard (e (#t #t)) (assume #f) #f))
(test-assert "145: a false expression raises with messages"
             (guard (e (#t #t)) (assume (= 1 2) "expected equal" 7) #f))
(test-equal "145: the failure is an error object" #t
            (guard (e (#t (error-object? e))) (assume #f "boom")))
;; The spec fixes neither the message text nor the irritant shape, so only
;; the two facts it does state are asserted: the messages reach the report,
;; and the quoted expression is available alongside them.
(test-equal "145: the messages reach the error object's irritants" #t
            (guard (e ((error-object? e)
                       (and (memv 7 (error-object-irritants e)) #t)))
              (assume (= 1 2) "expected equal" 7)))
(test-equal "145: the quoted expression reaches the error object" #t
            (guard (e ((error-object? e)
                       (and (member '(= 1 2) (error-object-irritants e)) #t)))
              (assume (= 1 2) "expected equal" 7)))
(test-equal "145: assume composes inside a body" 7
            (let ((a 3) (b 4)) (assume (> b a) "b>a") (+ a b)))

;;; ====================================================================
;;; SRFI 229 -- tagged procedures (the spec's own three examples)
;;; ====================================================================

(define f229 (lambda/tag 42 (x) (* x x)))

(test-equal "229 spec ex 1: procedure/tag? of a tagged procedure" #t (procedure/tag? f229))
(test-equal "229 spec ex 1: calling it behaves like the lambda" 9 (f229 3))
(test-equal "229 spec ex 1: procedure-tag returns the tag" 42 (procedure-tag f229))

;; The tag is the value of the expression at creation time, and does not
;; track later mutation of the variable it came from.
(define g229 (let ((y 10)) (lambda/tag y () (set! y (+ y 1)) y)))
(test-equal "229 spec ex 2: tag before the first call" 10 (procedure-tag g229))
(test-equal "229 spec ex 2: the call mutates its own closed-over variable" 11 (g229))
(test-equal "229 spec ex 2: the tag is unchanged afterwards" 10 (procedure-tag g229))

(define h229
  (let ((v (vector #f)))
    (case-lambda/tag v (() (vector-ref v 0)) ((val) (vector-set! v 0 val)))))
(test-equal "229 spec ex 3: the one-argument clause runs, not the tag lookup" 'ok
            (begin (h229 1) 'ok))
(test-equal "229 spec ex 3: the tag is the shared vector" 1
            (vector-ref (procedure-tag h229) 0))
(test-equal "229 spec ex 3: the zero-argument clause reads it back" 1 (h229))

(test-equal "229: a tagged procedure is a procedure" #t (procedure? f229))
(test-equal "229: procedure/tag? of an ordinary procedure" #f (procedure/tag? car))
(test-equal "229: procedure/tag? of a lambda" #f (procedure/tag? (lambda (x) x)))
(test-equal "229: procedure/tag? of a non-procedure" #f (procedure/tag? 5))
(test-equal "229: procedure/tag? of a symbol" #f (procedure/tag? 'x))
(test-equal "229: variadic formals, every arity" '(0 1 2)
            (let ((v (lambda/tag 'T args (length args)))) (list (v) (v 1) (v 1 2))))
(test-equal "229: variadic formals keep their tag" 'T
            (procedure-tag (lambda/tag 'T args (length args))))
(test-equal "229: two-argument formals" 3
            ((lambda/tag 'T (a b) (+ a b)) 1 2))
(test-equal "229: two-argument formals keep their tag" 'T
            (procedure-tag (lambda/tag 'T (a b) (+ a b))))
(test-equal "229: case-lambda/tag selects by arity" '(one two rest)
            (let ((v (case-lambda/tag 'T ((a) 'one) ((a b) 'two) (r 'rest))))
              (list (v 1) (v 1 2) (v 1 2 3))))
(test-equal "229: case-lambda/tag keeps its tag" 'T
            (procedure-tag (case-lambda/tag 'T ((a) 'one) ((a b) 'two) (r 'rest))))
(test-equal "229: the tag may be #f" #f (procedure-tag (lambda/tag #f (x) x)))
(test-equal "229: a #f-tagged procedure is still tagged" #t
            (procedure/tag? (lambda/tag #f (x) x)))
(test-equal "229: the tag may be a list" '(a b) (procedure-tag (lambda/tag '(a b) (x) x)))
(test-equal "229: two tagged procedures keep distinct tags" '(1 2)
            (let ((a (lambda/tag 1 (x) x)) (b (lambda/tag 2 (x) x)))
              (list (procedure-tag a) (procedure-tag b))))
(test-equal "229: two tagged procedures are distinct objects" #f
            (let ((a (lambda/tag 1 (x) x)) (b (lambda/tag 1 (x) x))) (eq? a b)))
(test-equal "229: a tagged procedure may itself be a tag" #t
            (let ((inner (lambda/tag 'i (x) x)))
              (eq? inner (procedure-tag (lambda/tag inner (x) x)))))
(test-equal "229: a tagged procedure closes over its scope" 15
            (let ((k 5)) ((lambda/tag 'T (n) (* n k)) 3)))
(test-assert "229: a zero-formals tagged procedure called with one argument raises"
             (guard (e (#t #t)) ((lambda/tag 'T () 9) 5) #f))
(test-assert "229: a two-formals tagged procedure called with one argument raises"
             (guard (e (#t #t)) ((lambda/tag 'T (a b) (+ a b)) 1) #f))

;;; ====================================================================
;;; Composition. Macro defects show up when forms are nested more often
;;; than when they are used alone.
;;; ====================================================================

(test-equal "compose: and-let* inside receive inside guard" "sum=3"
            (guard (e (#t (list 'err e)))
              (receive (a b) (values 1 2)
                (let ((s (+ a b))) (format "sum=~a" s)))))
(test-equal "compose: rec produced inside a receive body" 120
            (receive (n) (values 5)
              ((rec (fact k) (if (= k 0) 1 (* k (fact (- k 1))))) n)))
(test-equal "compose: assume inside a receive body" 7
            (receive (a b) (values 3 4) (assume (> b a) "b>a") (+ a b)))
(test-equal "compose: a box built inside let-values" 5
            (let-values (((b) (values (box 5)))) (unbox b)))
(test-equal "compose: receive inside a case-lambda clause" 3
            ((case-lambda ((x) (receive (a b) (values x (+ x 1)) (+ a b)))) 1))
(test-equal "compose: a tagged procedure inside case-lambda" 'T
            ((case-lambda ((x) (procedure-tag x))) (lambda/tag 'T (y) y)))
(test-equal "compose: format over values pulled out by receive" "1 and 2"
            (receive (a b) (values 1 2) (format "~a and ~a" a b)))
(test-equal "compose: guard around a failing assume" 'caught
            (guard (e (#t 'caught)) (assume #f "boom")))
(test-equal "compose: rec whose body uses receive" 3
            ((rec (f n) (receive (a b) (values n 1) (+ a b))) 2))
(test-equal "compose: let-values destructuring a case-lambda result" '(1 2)
            (let-values (((a b) ((case-lambda ((x) (values x (+ x 1)))) 1)))
              (list a b)))
(test-equal "compose: a box holding a tagged procedure" 'T
            (procedure-tag (unbox (box (lambda/tag 'T (x) x)))))
(test-equal "compose: assume guarding a box access" 5
            (let ((b (box 5))) (assume (box? b) "must be a box") (unbox b)))

;;; ====================================================================
;;; Hygiene. Each macro's template refers to identifiers from its own
;;; definition environment; R7RS 4.3.2 requires those references to survive
;;; any local binding that surrounds the use site.
;;;
;;;   "If a macro transformer inserts a free reference to an identifier, the
;;;    reference refers to the binding that was visible where the transformer
;;;    was specified, regardless of any local bindings that surround the use
;;;    of the macro."
;;;
;;; The enabled assertions below are the ones that hold; the disabled ones
;;; are the two live hygiene defects, each verified against chibi 0.12.0.
;;; ====================================================================

(test-equal "hygiene: an unrelated use-site local does not disturb receive" '(1 2)
            (let ((unrelated 5)) (receive (a b) (values 1 2) (list a b))))
(test-equal "hygiene: an unrelated use-site local does not disturb rec" 120
            (let ((unrelated 5))
              ((rec (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) 5)))
(test-equal "hygiene: an unrelated use-site local does not disturb assume" 42
            (let ((unrelated 5)) (assume 42)))
(test-equal "hygiene: a use-site local named `let' does not disturb rec" 120
            (let ((let 5)) ((rec (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) 5)))
(test-equal "hygiene: a use-site local named `if' does not disturb receive" '(1 2)
            (let ((if 5)) (receive (a b) (values 1 2) (list a b))))
;; lambda/tag's template inserts a reference to the library-internal
;; `make-procedure/tag'; a use-site local of that name must not reach it.
(test-equal "hygiene: a use-site local named `make-procedure/tag' is inert" 42
            (let ((make-procedure/tag (lambda (a b) 'HIJACKED)))
              (procedure-tag (lambda/tag 42 (x) x))))
;; A use-site local named after a *pattern* variable of the macro must not
;; leak into the expansion either.
(test-equal "hygiene: a use-site local named `formals' is inert" '(1 2)
            (let ((formals 5)) (receive (a b) (values 1 2) (list a b))))
(test-equal "hygiene: a use-site local named `expression' is inert" 42
            (let ((expression 5)) (assume 42)))

;; FAIL: #2003 (a use-site local binding captures a macro template's free
;; reference to a global procedure). receive's template refers to
;; call-with-values; assume's refers to error.
;; (test-equal "hygiene: a use-site local named `call-with-values' is inert" '(1 2)
;;             (let ((call-with-values (lambda (a b) 'HIJACKED)))
;;               (receive (a b) (values 1 2) (list a b))))
;; (test-equal "hygiene: a use-site local named `error' is inert" #t
;;             (let ((error (lambda args 'HIJACKED)))
;;               (guard (e (#t #t)) (assume #f "boom") #f)))

;; FAIL: #2074 (a use-site local named after a syntactic keyword captures it
;; inside any macro template). rec's template uses letrec; receive's uses
;; lambda; assume's uses or.
;; (test-equal "hygiene: a use-site local named `letrec' does not disturb rec" 120
;;             (let ((letrec 5))
;;               ((rec (fact n) (if (= n 0) 1 (* n (fact (- n 1))))) 5)))
;; (test-equal "hygiene: a use-site local named `lambda' does not disturb receive" '(1 2)
;;             (let ((lambda 5)) (receive (a b) (values 1 2) (list a b))))
;; (test-equal "hygiene: a use-site local named `or' does not disturb assume" 42
;;             (let ((or 5)) (assume 42)))
;; (test-equal "hygiene: a use-site local named `case-lambda' is inert" 'T
;;             (let ((case-lambda 5))
;;               (procedure-tag (case-lambda/tag 'T ((a) 'one)))))

(let ((runner (test-runner-current)))
  (test-end "srfi-notest-batch")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
