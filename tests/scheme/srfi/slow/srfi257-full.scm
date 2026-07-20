;; SRFI-257 (simple extendable pattern matcher with backtracking)
;; conformance tests, ported from the reference test suite by Sergei Egorov
;; (MIT licensed). Curated for CI time: the pattern towers and feature
;; coverage are kept intact, while the largest backtracking enumerations use
;; shorter inputs than the reference suite (expansion cost is per-matcher,
;; not per-input, so coverage is unchanged).
;;
;; Deviations from the reference suite:
;;   - the (box 42) equal? assertion compares via unbox (equal? on SRFI 111
;;     boxes is implementation-specific; Kaappi boxes compare by identity)
;;
;; The rx sublibrary has its own reference suite, ported alongside this one as
;; tests/scheme/srfi/slow/srfi257-rx-full.scm.
;;
;; This is the FULL port (about 4½ minutes of macro expansion on an M-class
;; laptop), kept out of run-all.sh's non-recursive srfi/*.scm glob; CI runs
;; the lean tests/scheme/srfi/srfi257.scm smoke instead.
;;
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/slow/srfi257-full.scm

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

; simple matches
(define (matcher-1 x)
  (match x
    (1                                'number-one)
    ('a                               'symbol-a)
    ('(a b)                           'list-a-b)
    (`(,v q)                          `(list ,v q))
    (`((,x ,y) (,z ,x))               `(head&tail ,x ,y ,z))
    (`(+ 0 ,a ,a)                     `(* 2 ,a))
    (`(+ (,f ,@a) (,g ,@a))           `((+ ,f ,g) ,@a))
    (`(** ,(~number? a) ,(~number? b)) (expt a b))
    (w                                `(generic ,w))))

(test-matcher matcher-1
  (1                          number-one)
  (a                          symbol-a)
  (((x y) q)                  (list (x y) q))
  (((a 2) (b a))              (head&tail a 2 b))
  ((+ 0 (+ y z) (+ y z))      (* 2 (+ y z)))
  ((+ (sin a b) (cos a b))    ((+ sin cos) a b))
  ((** 2 4)                   16)
  ((** 2 a)                   (generic (** 2 a))))

; rollback to the next rule
(define (matcher-2 x k)
  (match x
    (`(,@a ,(~symbol? b) ,@c) (=> next) (k `(p1 ,a ,b ,c)) (next))
    (`(,@a ,@c ,x)            (=> next) (k `(p2 ,a ,c ,x)) (next))
    (x                       (k `(p3 ,x)))))

(test-restart matcher-2
  (1 2 3 a 4 5)
  (p1 (1 2 3) a (4 5))
  (p2 (1 2 3 a 4) () 5)
  (p3 (1 2 3 a 4 5)))

; rollback to the next match (backtracking via (=> next back))
(define (matcher-3 x k)
  (match x
    (`(,@a ,b ,@c) (=> next back) (k `(fst ,a ,b ,c)) (back))
    (`(,@a ,@c)    (=> next back) (k `(snd ,a ,c)) (back))
    (`,x               (k `(final ,x)))))

(test-restart matcher-3
  (1 2 3)
  (fst (1 2) 3 ())
  (fst (1) 2 (3))
  (fst () 1 (2 3))
  (snd (1 2 3) ())
  (snd (1 2) (3))
  (snd (1) (2 3))
  (snd () (1 2 3))
  (final (1 2 3)))

; rollback to the next match, constructor syntax
(define (matcher-4 x k)
  (match x
    ((~append a (~list b) c) (=> next back) (k `(fst ,a ,b ,c)) (back))
    ((~append a c)           (=> next back) (k `(snd ,a ,c)) (back))
    (x                       (k `(final ,x)))))

(test-restart matcher-4
  (1 2 3)
  (fst (1 2) 3 ())
  (fst (1) 2 (3))
  (fst () 1 (2 3))
  (snd (1 2 3) ())
  (snd (1 2) (3))
  (snd (1) (2 3))
  (snd () (1 2 3))
  (final (1 2 3)))

; same, but with strings (greedy and non-greedy)
(define (matcher-5 x k)
  (match x
    ((~string-append a (~string b) c) (=> next back) (k `(fst ,a ,b ,c)) (back))
    ((~string-append a c)             (=> next back) (k `(snd ,a ,c)) (back))
    (x                                (k `(final ,x)))))

(test-restart matcher-5
  "123"
  (fst "12" #\3 "")
  (fst "1" #\2 "3")
  (fst "" #\1 "23")
  (snd "123" "")
  (snd "12" "3")
  (snd "1" "23")
  (snd "" "123")
  (final "123"))

(define (matcher-5ng x k)
  (match x
    ((~string-append/ng a (~string b) c) (=> next back) (k `(fst ,a ,b ,c)) (back))
    ((~string-append/ng a c)             (=> next back) (k `(snd ,a ,c)) (back))
    (x                                           (k `(final ,x)))))

(test-restart matcher-5ng
  "123"
  (fst "" #\1 "23")
  (fst "1" #\2 "3")
  (fst "12" #\3 "")
  (snd "" "123")
  (snd "1" "23")
  (snd "12" "3")
  (snd "123" "")
  (final "123"))

; nonlinear matcher (short palindrome; reference uses "abracadarba")
(define (string-reverse s) (list->string (reverse (string->list s))))
(define (matcher-6 x k)
  (match x
    ((~string-append a b a) (=> next back) (k `(rep ,a ,b ,a)) (back))
    ((~string-append a b (~= string-reverse a)) (=> next back) (k `(rev ,a ,b ,(string-reverse a))) (back))
    (x (k `(final ,x)))))

(test-restart matcher-6
  "aba"
  (rep "a" "b" "a")
  (rep "" "aba" "")
  (rev "a" "b" "a")
  (rev "" "aba" "")
  (final "aba"))

; advanced non-iterative matches
(define-match-pattern ~list4? ()
  ((_) (~and (~list?) (~= length 4)))
  ((_ l) (~and (~list?) (~= length 4) l)))

(define-match-pattern ~listn? ()
  ((_ n) (~and (~list?) (~= length n)))
  ((_ n l) (~and (~list?) (~= length n) l)))

(define (matcher-7 x)
  (match x
    ((~or 1 2 3)                      'number-1-3)
    ((~or 'a 'b 'c)                   'symbol-a-c)
    ((~? symbol?)                     'symbol-other)
    ((~and l `(a ,b))                 `(list-a-* ,l ,b))
    ((~char? c)                       'char)
    ((~and (~list?) (~= length 3) l)  `(list-of-3 ,l))
    ((~list4? l)                      `(list-of-4 ,l))
    ((~listn? 5 l)                    `(list-of-5 ,l))
    ((~and (~list? l) (~not (~= length 3)))  `(list-of-not-3 ,l))
    (w                                `(other ,w))))

(test-matcher matcher-7
  (1                          number-1-3)
  (2                          number-1-3)
  (4                          (other 4))
  (a                          symbol-a-c)
  (z                          symbol-other)
  (#\z                        char)
  ((a 1)                      (list-a-* (a 1) 1))
  ((1 2 3)                    (list-of-3 (1 2 3)))
  ((1 2 3 4)                  (list-of-4 (1 2 3 4)))
  ((1 2 3 4 5)                (list-of-5 (1 2 3 4 5)))
  ((1 2 3 4 5 6)              (list-of-not-3 (1 2 3 4 5 6))))

; ~list-no-order (3 elements = 6 permutations, as in the reference)
(define (matcher-lno x k)
  (match x
    ((~list-no-order a b c) (=> next back) (k `(fst ,a ,b ,c)) (back))
    (x (k `(final ,x)))))

(test-restart matcher-lno
  (1 2 3)
  (fst 1 2 3)
  (fst 1 3 2)
  (fst 2 1 3)
  (fst 2 3 1)
  (fst 3 2 1)
  (fst 3 1 2)
  (final (1 2 3)))

; tests for ~or
(define-match-pattern ~opt ()
  ((_ p) (~or (~list p) '())))

(define (matcher-or x)
  (match x
    ((~or 1 2 3)                                'number-1-3)
    ((~or 'a 'b 'c)                             'symbol-a-c)
    ((~or `(,@a ,(~symbol? b) ,@a) '())         `(mp3 ,a ,b ,a))
    (`(foo ,n ,@(~opt `(align ,a)) ,x)          `(foo ,n ,a ,x))
    ((~or x y z)                                `(xyz ,x ,y ,z))))

(test-matcher matcher-or
  (1                          number-1-3)
  (4                          (xyz 4 #f #f))
  (a                          symbol-a-c)
  (()                         (mp3 #f #f #f))
  ((a)                        (mp3 () a ()))
  ((a b)                      (xyz (a b) #f #f))
  ((y z x y z)                (mp3 (y z) x (y z)))
  ((foo bar baz)              (foo bar #f baz))
  ((foo bar (align 16) baz)   (foo bar 16 baz)))

; tests for ~etc and etc
(define (matcher-etc x)
  (match x
    ((~append (~etc (~cons x y)) (~pair? (~etc (~number? z))))          `(first ,x ,y ,z))
    ((~append (~etc (~cons x (~append (~etc y) '()))) '())              `(second ,x ,y))
    ((~cons (~etc (~symbol? x)) (~etc (~cons x y)))                     `(third ,x ,y))
    ((~cons (~and x (~etc (~number?))) (~append (~etc (~cons x y)) z))  `(fourth ,x ,y ,z))
    ((~append (~pair? (~etc (~pair? x))) (~cons y _))                   `(fifth ,x ,y))
    (_                                                                  `(other))))

(test-matcher matcher-etc
  (((1) (2) (3 . 4) 5 6)                      (first (1 2 3) (() () 4) (5 6)))
  (((a b c d) (e f g) (h i) (j))              (second (a e h j) ((b c d) (f g) (i) ())))
  (((a b c) (a . 2) (b . 3) (c . 4))          (third (a b c) (2 3 4)))
  ((1 (1 . 2) (1 . 3) (2 . 6))                (other)))

(define *foobar* 42)

(define (matcher-etcetc x)
  (match x
    ((~etc (~list* 1 x y))     (cons 'first (etc (list (value *foobar*) y x))))
    ((~etc (~etc (~list x y))) (cons 'second (etc (etc (list y x)))))
    ((~etc (~cons x y))        (cons 'third (list (etc (cons x x)) (etc (cons y 4)))))
    (_                         (value '(other)))))

(test-matcher matcher-etcetc
  (((1 1) (1 2) (1 3 4))                      (first (42 () 1) (42 () 2) (42 (4) 3)))
  ((((a b) (c d)) ((e f) (g h) (i j)) ())     (second ((b a) (d c)) ((f e) (h g) (j i)) ()))
  ((1 (1 . 2) (1 . 3) (2 . 6))                (other)))

; ~cut! matcher (backtracking points inside the cut are discarded)
(define (matcher-cut x k)
  (match x
    ((~append a (~cons (~cut! (~append b c)) d))
     (=> next back) (k `(fst ,a ,b ,c ,d)) (back))
    (x (k `(final ,x)))))

(test-restart matcher-cut
  ((1) (2 3))
  (fst ((1)) (2 3) () ())
  (fst () (1) () ((2 3)))
  (final ((1) (2 3))))

; custom matcher with (extended) lambda-list-like patterns
(define-match-pattern ~llp->p (quote quasiquote)
  ((_ 'x) 'x)
  ((_ `x) `x)
  ((_ ()) '())
  ((_ (x . y)) (~cons (~llp->p x) (~llp->p y)))
  ((_ #(x ...)) (~vector (~llp->p x) ...))
  ((_ other) other))

(define-syntax ll-match
  (syntax-rules ()
    ((_ x (llp . rhs) ...)
     (match x ((~llp->p llp) . rhs) ...))))

(define (matcher-8 x)
  (ll-match x
    (1                        'number-one)
    ('a                       'symbol-a)
    ((_)                      'list1)
    ('(a b)                   'list-a-b)
    (()                       'null)
    ((x 'q)                   `(list ,x q))
    ((x 42 . z)               `(list2+/42 ,x 42 ,z))
    ((x y . z)                `(list2+ ,x ,y ,z))
    (#('point x y)            `(point2 ,x ,y))
    (#('point x y z)          `(point3 ,x ,y ,z))
    (z                        `(other ,z))))

(test-matcher matcher-8
  (1                         number-one)
  (a                         symbol-a)
  (()                        null)
  ((a)                       list1)
  ((a b)                     list-a-b)
  ((p q)                     (list p q))
  ((41 42 43 44)             (list2+/42 41 42 (43 44)))
  ((45 46 47 48)             (list2+ 45 46 (47 48)))
  (#(point 49 50)            (point2 49 50))
  (#(point 49 50 51)         (point3 49 50 51))
  (#(point 52 53 54 55)      (other #(point 52 53 54 55))))

; syntax-rules-like matcher with a standalone list of literal symbols
(test-matcher
  (lambda (in)
    (sr-match in (a b)
      ((a x) 1)
      ((b x y) 2)
      ((a x y) 3)
      ((_ _ _) 4)))
  ((a 17 37) 3)
  ((b 17 37) 2)
  ((c 17 37) 4))

(test-matcher
  (lambda (in)
    (sr-match in (a)
      ((a x* ...) x*)))
  ((a 17 37) (17 37)))

(test-matcher
  (lambda (in)
    (sr-match in (begin)
      ((begin (x* y*) ...) (list x* y*))))
  ((begin (1 5) (2 6) (3 7) (4 8)) ((1 2 3 4) (5 6 7 8))))

(test-matcher
  (lambda (in)
    (sr-match in ()
      (((x* y** ...) ...) (list x* y**))))
  (((a b c d) (e f g) (h i) (j)) ((a e h j) ((b c d) (f g) (i) ()))))

; SRFI-241/DFH-like catamorphism matcher
(test-matcher
  (lambda (in)
    (cm-match in
      ((a ,x) 1)
      ((b ,x ,y) 2)
      ((a ,x ,y) 3)
      ((,_ ,_ ,_) 4)))
  ((a 17 37) 3)
  ((b 17 37) 2)
  ((c 17 37) 4))

(test-matcher
  (lambda (in)
    (cm-match in
      ((a ,x) (- x))
      ((b ,x ,y) (+ x y))
      ((a ,x ,y) (* x y))))
  ((a 17 37) 629))

(test-matcher
  (lambda (in)
    (cm-match in
      ((a ,x* ...) x*)))
  ((a 17 37) (17 37)))

(test-matcher
  (lambda (in)
    (cm-match in
      ((begin (,x* ,y*) ...) (append x* y*))))
  ((begin (1 5) (2 6) (3 7) (4 8)) (1 2 3 4 5 6 7 8)))

(test-matcher
  (lambda (in)
    (letrec
      ((len (lambda (lst)
              (cm-match lst
                (() 0)
                ((,x ,x* ...) (+ 1 (len x*)))))))
      (len in)))
  ((a b c d) 4))

(test-matcher
  (lambda (in)
    (let ((len
           (lambda (lst)
             (cm-match lst
               (() 0)
               ((,x . ,(y)) (+ 1 y))))))
      (len in)))
  ((a b c d) 4))

(test-matcher
  (lambda (in)
    (let ((simple-eval
           (lambda (x)
             (cm-match x
               (,i (guard (integer? i)) i)
               ((+ ,(x*) ...) (apply + x*))
               ((* ,(x*) ...) (apply * x*))
               ((- ,(x) ,(y)) (- x y))
               ((/ ,(x) ,(y)) (/ x y))
               (,x (error "invalid expression" x))))))
      (simple-eval in)))
  ((+ (- 0 1) (+ 2 3)) 4)
  ((+ 1 2 3) 6))

; test record matchers
(define-record-type <pare> (kons x y)
  pare? (x kar) (y kdr))

(define-record-match-pattern (~kons x y)
  pare? (y kdr) (x kar)) ; not order-sensitive!

(define-record-match-pattern (~v2 a b)
  (lambda (x) (and (vector? x) (= (vector-length x) 2)))
  (a (lambda (v) (vector-ref v 0)))
  (b (lambda (v) (vector-ref v 1))))

(define (matcher-rec x)
  (match x
    ((~kons x y)                      `(kons-of ,x ,y))
    ((~v2 a b)                        `(v2-of ,a ,b))
    (w                                `(other ,w))))

(test-equal '(other 1) (matcher-rec 1))
(test-equal '(other (1 . 4)) (matcher-rec '(1 . 4)))
(test-equal '(v2-of 5 125) (matcher-rec #(5 125)))
(test-equal '(kons-of 42 14) (matcher-rec (kons 42 14)))

; box patterns tests (equal? on boxes is implementation-specific; compare
; through unbox instead of the reference's (test-equal (box 42) ...))
(test-equal #f (match '42 ((~box? a) a) (_ #f)))
(test-equal 42 (unbox (match (box 42) ((~box? a) a) (_ #f))))

(test-equal #f (match '42 ((~box a) a) (_ #f)))
(test-equal 42 (match (box 42) ((~box a) a) (_ #f)))

(let ((runner (test-runner-current)))
  (test-end)
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
