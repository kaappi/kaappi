;; Audit tests for src/primitives_srfi1.zig — SRFI-1 list library.
;; Audit campaign Phase 2.6 (#1137). Complements tests/scheme/srfi/srfi1*.scm.
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme write) (srfi 1))
(import (chibi test))

(test-begin "primitives_srfi1 audit")

;;; --- fold family: argument order and multi-list ---
(test '(3 2 1) (fold cons '() '(1 2 3)))          ; kons gets (elem acc)
(test 21 (fold + 0 '(1 2 3) '(4 5 6)))            ; multi-list
(test '(1 2 3) (fold-right cons '() '(1 2 3)))
(test 6 (fold + 0 '(1 2 3)))
;; reduce: ridentity only for the empty list
(test 'rid (reduce + 'rid '()))
(test 6 (reduce + 0 '(1 2 3)))
(test '(1 2 . 3) (reduce-right (lambda (a b) (cons a b)) 0 '(1 2 3)))
;; pair-fold walks successive tails
(test '((3) (2 3) (1 2 3)) (pair-fold cons '() '(1 2 3)))
(test '((1 2 3) (2 3) (3)) (pair-fold-right cons '() '(1 2 3)))

;;; --- unfold family with optional tail ---
(test '(1 4 9) (unfold (lambda (x) (> x 3)) (lambda (x) (* x x))
                       (lambda (x) (+ x 1)) 1))
(test '(1 4 9 . end) (unfold (lambda (x) (> x 3)) (lambda (x) (* x x))
                             (lambda (x) (+ x 1)) 1 (lambda (x) 'end)))
(test '(9 4 1) (unfold-right (lambda (x) (> x 3)) (lambda (x) (* x x))
                             (lambda (x) (+ x 1)) 1 '()))
(test '(9 4 1 tail) (unfold-right (lambda (x) (> x 3)) (lambda (x) (* x x))
                                  (lambda (x) (+ x 1)) 1 '(tail)))

;;; --- iota ---
(test '(0 1 2 3 4) (iota 5))
(test '(0 -2 -4) (iota 3 0 -2))
(test '(0.0 0.5 1.0) (iota 3 0.0 0.5))
(test '() (iota 0))
(test #t (guard (e (#t #t)) (iota -1)))

;;; --- take/drop family: proper and dotted lists ---
(test '() (take '(1 2) 0))
(test '(1 2) (take '(1 2 3 . d) 2))
(test '(3 . d) (drop '(1 2 3 . d) 2))
(test 'd (drop '(1 2 3 . d) 3))
(test '(4 5) (take-right '(1 2 3 4 5) 2))
(test '(1 2 3) (drop-right '(1 2 3 4 5) 2))
(test '((1 2) (3 4)) (call-with-values (lambda () (split-at '(1 2 3 4) 2)) list))
(test #t (guard (e (#t #t)) (take '(1) 5)))
(test '(2 3 . d) (take-right '(1 2 3 . d) 2))
(test 'd (take-right '(1 2 3 . d) 0))
(test '(1) (drop-right '(1 2 3 . d) 2))
(test '(1 2 3) (drop-right '(1 2 3 . d) 0))

;;; --- span / break / partition return two values ---
(test '((2 4) (1 3)) (call-with-values (lambda () (span even? '(2 4 1 3))) list))
(test '((2 4) (1 3)) (call-with-values (lambda () (break odd? '(2 4 1 3))) list))
(test '((2 4) (1 3)) (call-with-values (lambda () (partition even? '(1 2 3 4))) list))
(test '(() ()) (call-with-values (lambda () (partition even? '())) list))

;;; --- filter / remove ---
(test '(2 4) (filter even? '(1 2 3 4)))
(test '(1 3) (remove even? '(1 2 3 4)))
(test '() (filter even? '()))

;;; --- delete / delete-duplicates: order, first-kept, custom equality ---
(test '(1 3) (delete 2 '(1 2 3 2)))
(test '(1) (delete 2.0 '(1 2) =))
(test '(a b c) (delete-duplicates '(a b a c b)))
(test '((a 1) (b 2))
  (delete-duplicates '((a 1) (b 2) (a 3))
                     (lambda (x y) (eq? (car x) (car y)))))

;;; --- searching: return values, multi-list ---
(test 4 (find even? '(3 1 4 1 5)))
(test #f (find even? '(3 1 5)))
(test '(4 1 5) (find-tail even? '(3 1 4 1 5)))
(test 2 (any (lambda (x) (and (even? x) x)) '(1 2 3)))   ; pred's value
(test #t (any < '(3 1 4) '(2 7 1)))                      ; multi-list
(test #f (any even? '()))
(test 3 (every (lambda (x) x) '(1 2 3)))                 ; last value
(test #t (every odd? '()))
(test 2 (list-index even? '(3 1 4 1)))
(test #f (list-index even? '(3 1 5)))
(test 3 (count < '(1 2 4 8) '(2 4 6 8)))
(test 3 (count even? '(2 4 6)))

;;; --- lset operations (SRFI example shapes) ---
(test '(5 4 1 2 3) (lset-adjoin eqv? '(1 2 3) 4 1 5))
(test '(5 4 1 2 3) (lset-union eqv? '(1 2 3) '(2 4) '(5)))
(test '(1 4) (lset-xor eqv? '(1 2 3) '(2 3 4)))
(test '(2 3) (lset-intersection eqv? '(1 2 3) '(2 3 4)))
(test '(1) (lset-difference eqv? '(1 2 3) '(2 3 4)))
(test #t (lset= eq? '(a b c) '(c b a) '(b a c)))
(test #f (lset= eq? '(a) '(a b)))
(test #t (lset= eq?))                                    ; trivial case

;;; --- list structure predicates ---
(test 3 (length+ '(1 2 3)))
(test #f (let ((c (list 1 2 3))) (set-cdr! (cddr c) c) (length+ c)))
(test #t (proper-list? '(1 2)))
(test #f (proper-list? '(1 . 2)))
(test #t (dotted-list? '(1 . 2)))
(test #t (dotted-list? 42))                              ; non-pair is dotted
(test #t (let ((c (list 1))) (set-cdr! c c) (circular-list? c)))
(test #f (circular-list? '(1 2)))
(test #t (null-list? '()))
(test #f (null-list? '(1)))
(test #t (not-pair? 5))
(test #f (not-pair? '(1)))
(test #t (list= = '(1 2) '(1 2) '(1 2)))
(test #f (list= = '(1 2) '(1 3)))
(test #t (list= =))

;;; --- constructors and accessors ---
(test '(1 2 . 3) (cons* 1 2 3))
(test 9 (cons* 9))
(test '(b . a) (xcons 'a 'b))
(test '(0 1 4 9) (list-tabulate 4 (lambda (i) (* i i))))
(test '(2 1 3 4) (append-reverse '(1 2) '(3 4)))
(test '(1 2 3 4) (concatenate '((1 2) (3 4))))
(test '() (concatenate '()))
(test 3 (last '(1 2 3)))
(test '(3) (last-pair '(1 2 3)))
(test '(1 (2 3)) (call-with-values (lambda () (car+cdr '(1 2 3))) list))
(test 1 (first '(1 2 3 4 5 6 7 8 9 10)))
(test 10 (tenth '(1 2 3 4 5 6 7 8 9 10)))
(test '((1 a) (2 b)) (zip '(1 2) '(a b)))
(test '((1 2) (a b)) (call-with-values (lambda () (unzip2 '((1 a) (2 b)))) list))
(test '(1 2) (unzip1 '((1 a) (2 b))))
(test 2 (let ((c (circular-list 1 2))) (list-ref c 5)))
(test #t (circular-list? (circular-list 1 2)))

;;; --- mapping variants ---
(test '(4 16) (filter-map (lambda (x) (and (even? x) (* x x))) '(1 2 3 4)))
(test '(1 1 2 2) (append-map (lambda (x) (list x x)) '(1 2)))
(test '(2 4 6) (map-in-order (lambda (x) (* 2 x)) '(1 2 3)))
(test '(1 2 3)
  (let ((acc '()))
    (pair-for-each (lambda (pr) (set! acc (cons (length pr) acc))) '(a b c))
    acc))

;;; --- alist operations ---
(test '((k . v) (a . 1)) (alist-cons 'k 'v '((a . 1))))
(test '((b . 2)) (alist-delete 'a '((a . 1) (b . 2) (a . 3))))
;; alist-copy copies the pairs themselves
(test '(#t #f)
  (let* ((al '((a . 1))) (cp (alist-copy al)))
    (list (equal? al cp) (eq? (car al) (car cp)))))

;;; --- callback error propagation ---
(test 'caught (guard (e (#t 'caught)) (find (lambda (x) (error "boom")) '(1))))
(test 'caught (guard (e (#t 'caught)) (fold (lambda (a b) (error "boom")) 0 '(1))))
(test 'caught (guard (e (#t 'caught)) (filter (lambda (x) (error "boom")) '(1))))
(test 'caught (guard (e (#t 'caught)) (list-tabulate 2 (lambda (i) (error "boom")))))

;;; --- type errors are catchable ---
(test #t (guard (e (#t #t)) (fold + 0 42)))
(test #t (guard (e (#t #t)) (concatenate 42)))
(test #t (guard (e (#t #t)) (last '())))
(test #t (guard (e (#t #t)) (first '())))
(test #t (guard (e (#t #t)) (zip 42)))

(test-end "primitives_srfi1 audit")
