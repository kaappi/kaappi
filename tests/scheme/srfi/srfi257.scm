;; SRFI-257 (simple extendable pattern matcher with backtracking) smoke
;; tests — a lean cut of the reference suite that exercises every feature
;; family once: quasiquote/non-linear patterns, (=> next back) backtracking,
;; constructor patterns, ~etc, define-match-pattern, the misc sublibrary's
;; sr-match/cm-match, record patterns, and the box sublibrary.
;;
;; The complete port of the reference suite lives at
;; tests/scheme/srfi/slow/srfi257-full.scm (minutes of macro expansion; run
;; it when touching the expander or the SRFI 257 libraries).
;;
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi257.scm

(import (scheme base) (srfi 64)
        (srfi 257) (srfi 257 misc)
        (srfi 111) (srfi 257 box))

(test-begin "srfi-257")

(define-syntax test-matcher
  (syntax-rules ()
    ((_ matcher (in out) ...)
     (let ((m matcher))
       (test-equal 'out (matcher 'in)) ...))))

(define-syntax test-restart
  (syntax-rules ()
    ((_ matcher-k in . outs)
     (let ((mk matcher-k) (v '()))
      (mk 'in (lambda (x) (set! v (cons x v))))
      (test-equal (reverse v) 'outs)))))

; simple matches: literals, quasiquote patterns, non-linear vars, predicates
(define (matcher-1 x)
  (match x
    (1                                'number-one)
    ('a                               'symbol-a)
    (`(,v q)                          `(list ,v q))
    (`(+ 0 ,a ,a)                     `(* 2 ,a))
    (`(** ,(~number? a) ,(~number? b)) (expt a b))
    (w                                `(generic ,w))))

(test-matcher matcher-1
  (1                          number-one)
  (a                          symbol-a)
  (((x y) q)                  (list (x y) q))
  ((+ 0 (+ y z) (+ y z))      (* 2 (+ y z)))
  ((** 2 4)                   16)
  ((** 2 a)                   (generic (** 2 a))))

; backtracking with (=> next back): every solution, then the next clause
(define (matcher-3 x k)
  (match x
    (`(,@a ,b ,@c) (=> next back) (k `(fst ,a ,b ,c)) (back))
    (`(,@a ,@c)    (=> next back) (k `(snd ,a ,c)) (back))
    (`,x               (k `(final ,x)))))

(test-restart matcher-3
  (1 2)
  (fst (1) 2 ())
  (fst () 1 (2))
  (snd (1 2) ())
  (snd (1) (2))
  (snd () (1 2))
  (final (1 2)))

; non-linear pattern through backtracking constructor patterns
(test-equal '((1) (2) (1))
  (match '(1 2 1) ((~append a b a) (list a b a)) (_ 'no)))

; non-linear string palindrome (both directions of ~seq-append)
(define (matcher-6 x k)
  (match x
    ((~string-append a b a) (=> next back) (k `(rep ,a ,b ,a)) (back))
    (x (k `(final ,x)))))

(test-restart matcher-6
  "aba"
  (rep "a" "b" "a")
  (rep "" "aba" "")
  (final "aba"))

; ~etc with var extraction and non-linear interplay
(test-equal '(1 2 3) (match '(1 2 3) ((~etc a) a) (_ 'no)))
(test-equal '((1 2) (x y))
  (match '((1 x) (2 y)) ((~etc (~list a b)) (list a b)) (_ 'no)))
(test-equal '((1 2 3) (1 2 3))
  (match '(1 2 3) ((~and (~etc (~number? n)) l) (list n l)) (_ 'no)))

; user extension via define-match-pattern
(define-match-pattern ~list3? ()
  ((_ l) (~and (~list?) (~= length 3) l)))

(test-equal '(got (1 2 3))
  (match '(1 2 3) ((~list3? l) `(got ,l)) (_ 'no)))

; ~or binds unmatched vars to #f
(test-equal '(xyz 4 #f #f)
  (match 4 ((~or 1 2 3) 'small) ((~or x y z) `(xyz ,x ,y ,z))))

; sequence matchers must FAIL (not raise) on mismatched input types
; (Kaappi fix over the reference: the type predicate gates x-length)
(test-equal 'no (match '(1 2) ((~string-append a b) (list a b)) (_ 'no)))
(test-equal 'no (match "ab" ((~vector-append a b) (list a b)) (_ 'no)))
(test-equal 'no (match 7 ((~string-append/ng a b) (list a b)) (_ 'no)))

; misc sublibrary: syntax-rules-like matcher with literal list
(test-equal 3
  ((lambda (in) (sr-match in (a b) ((a x) 1) ((b x y) 2) ((a x y) 3) ((_ _ _) 4)))
   '(a 17 37)))
(test-equal '(17 37)
  ((lambda (in) (sr-match in (a) ((a x* ...) x*))) '(a 17 37)))

; misc sublibrary: catamorphism matcher
(test-equal 629
  ((lambda (in) (cm-match in ((a ,x) (- x)) ((b ,x ,y) (+ x y)) ((a ,x ,y) (* x y))))
   '(a 17 37)))
(test-equal 4
  ((lambda (in)
     (letrec ((len (lambda (lst)
                     (cm-match lst
                       (() 0)
                       ((,x ,x* ...) (+ 1 (len x*)))))))
       (len in)))
   '(a b c d)))

; record matchers
(define-record-type <pare> (kons x y)
  pare? (x kar) (y kdr))

(define-record-match-pattern (~kons x y)
  pare? (y kdr) (x kar))

(test-equal '(kons-of 42 14)
  (match (kons 42 14) ((~kons x y) `(kons-of ,x ,y)) (_ 'no)))

; box sublibrary (equal? on boxes is implementation-specific: compare via unbox)
(test-equal #f (match '42 ((~box? a) a) (_ #f)))
(test-equal 42 (unbox (match (box 42) ((~box? a) a) (_ #f))))
(test-equal 42 (match (box 42) ((~box a) a) (_ #f)))


; misc sublibrary: the ~etc+ / ~etc= / ~etc** length-refined matchers
(test-equal 'plus  (match '(1 2)  ((~etc+ (~number?)) 'plus)  (_ 'no)))
(test-equal 'no    (match '()     ((~etc+ (~number?)) 'plus)  (_ 'no)))
(test-equal '(1 2) (match '(1 2)  ((~and (~etc= 2 x) l) x)    (_ 'no)))
(test-equal 'no    (match '(1 2 3) ((~etc= 2 x) x)            (_ 'no)))
(test-equal 'twoish (match '(1 2) ((~etc** 1 3 (~number?)) 'twoish) (_ 'no)))
(test-equal 'no     (match '()    ((~etc** 1 3 (~number?)) 'twoish) (_ 'no)))

; cm-match catamorphism with an explicit (f -> x) cata operator
(test-equal 6
  (letrec ((sum (lambda (l)
                  (cm-match l
                    (() 0)
                    ((,x . ,(sum -> r)) (+ x r))))))
    (sum '(1 2 3))))

; sr-match pattern containing a non-symbol atom (exercises the upstream
; ~if-id-member yv/xv fix: non-identifier atoms fall through to a plain
; datum comparison)
(test-equal 'one-two
  ((lambda (in) (sr-match in () ((1 2) 'one-two) ((_ _) 'other))) '(1 2)))
(test-equal 'other
  ((lambda (in) (sr-match in () ((1 2) 'one-two) ((_ _) 'other))) '(3 4)))

(let ((runner (test-runner-current)))
  (test-end)
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
