;; Probe: the *code* half of a `.sbc` round trip — nested functions, upvalues,
;; and the control forms whose bytecode the deserialiser has to validate.
;;
;; Audit v2, Phase 4E.  The constant probes cover `writeConstant`'s data tags;
;; this one covers `TAG_FUNCTION` (a by-index reference into the flattened
;; function table), `collectFunctions`'s depth-first flattening, the `closure`
;; opcode's upvalue-capture bytes, and `validateFunctionBytecode`'s per-opcode
;; length and operand checks.
;;
;; Nothing here may `import` — see sbc-population.scm for why.

(define (chk name a b)
  (display name)
  (display " ")
  (display (if (equal? a b) "ok" (list "MISMATCH" a b)))
  (newline))

;; --- closures and upvalues (TAG_FUNCTION + the closure opcode) -----------
(define (mk n) (lambda (x) (+ n x)))
(define add5 (mk 5))
(chk "closure-capture" (list (add5 1) (add5 2)) (list 6 7))

(define (counter)
  (let ((c 0))
    (lambda () (set! c (+ c 1)) c)))
(define c1 (counter))
(define c2 (counter))
(chk "boxed-upvalue" (list (c1) (c1) (c2) (c1)) (list 1 2 1 3))

;; --- nested function graph, three deep ------------------------------------
(define (outer a)
  (lambda (b)
    (lambda (c)
      (list a b c))))
(chk "nested-3" (((outer 1) 2) 3) (list 1 2 3))

;; --- case-lambda (several arities behind one value) ----------------------
(define pick
  (case-lambda
    ((a) (list 'one a))
    ((a b) (list 'two a b))
    ((a . r) (list 'many a r))))
(chk "case-lambda" (list (pick 1) (pick 1 2) (pick 1 2 3))
     (list '(one 1) '(two 1 2) '(many 1 (2 3))))

;; --- case over datum lists (constants reached from a jump table) ---------
(define (classify x)
  (case x
    ((1 2 3) 'low)
    ((a b) 'sym)
    (("s") 'str)
    (else 'other)))
(chk "case-datums" (list (classify 2) (classify 'b) (classify 99))
     (list 'low 'sym 'other))

;; --- named let and self-tail-call (the self_tail_call opcode) ------------
(chk "named-let"
     (let loop ((n 1000) (acc 0)) (if (= n 0) acc (loop (- n 1) (+ acc n))))
     500500)

;; --- deep tail recursion through a global (tail_call_global) -------------
(define (sum n acc) (if (= n 0) acc (sum (- n 1) (+ acc n))))
(chk "tail-recursion" (sum 100000 0) 5000050000)

;; --- continuations, handlers and winds (push_handler/pop_handler,
;;     tail_call_cc) -------------------------------------------------------
(chk "call/cc-escape"
     (call-with-current-continuation (lambda (k) (+ 1 (k 42))))
     42)
(chk "call/cc-normal"
     (call-with-current-continuation (lambda (k) 7))
     7)
(chk "guard"
     (guard (e (#t (list 'caught (error-object-message e))))
       (error "boom" 1 2))
     (list 'caught "boom"))
(define wind-log '())
(dynamic-wind
  (lambda () (set! wind-log (cons 'in wind-log)))
  (lambda () (set! wind-log (cons 'body wind-log)))
  (lambda () (set! wind-log (cons 'out wind-log))))
(chk "dynamic-wind" (reverse wind-log) (list 'in 'body 'out))

;; --- parameters and promises ---------------------------------------------
(define p (make-parameter 1))
(chk "parameterize" (list (p) (parameterize ((p 2)) (p)) (p)) (list 1 2 1))
(define lazy (delay (begin (display "") 41)))
(chk "delay-force" (list (force lazy) (force lazy)) (list 41 41))

;; --- apply / values / variadic -------------------------------------------
(define (var a . rest) (cons a rest))
(chk "variadic" (list (var 1) (var 1 2 3)) (list '(1) '(1 2 3)))
(chk "apply" (apply + '(1 2 3 4)) 10)
(chk "values" (call-with-values (lambda () (values 1 2 3)) list) (list 1 2 3))
