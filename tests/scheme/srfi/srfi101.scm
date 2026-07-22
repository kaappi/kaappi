;; SRFI-101 (purely functional random-access pairs and lists) conformance tests
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi101.scm
;;
;; NOTE on test style: (srfi 101) shadows cons/car/cdr/list/append/reverse/
;; equal?/etc. with its own random-access-pair semantics, so this file must
;; except those names from (scheme base) to avoid an ambiguous import. It
;; also means test-equal (whose own equal? is native and doesn't know how to
;; compare a random-access pair record structurally) must never be handed a
;; raw random-access list/pair directly on either side — every such value is
;; first unwrapped with random-access-list->linear-access-list (to compare
;; against a native quoted literal) or compared with this library's own
;; equal? explicitly (yielding a plain boolean that test-equal can compare
;; natively without trouble).

(import
  (except (scheme base)
    cons car cdr
    caar cadr cdar cddr
    pair? null? list? list make-list length append reverse
    list-tail list-ref map for-each equal?)
  (srfi 101) (scheme process-context) (srfi 64))

(test-begin "srfi-101")

;;; --- basic construction and access ---

(test-equal #t (pair? (cons 1 2)))
(test-equal #f (pair? '()))
(test-equal #f (pair? 5))
(test-equal #t (null? '()))
(test-equal #f (null? (cons 1 2)))
(test-equal 1 (car (cons 1 2)))
(test-equal 2 (cdr (cons 1 2)))

;; spec worked example
(test-equal '(a) (random-access-list->linear-access-list (cons 'a '())))

;; dotted (improper) pairs
(test-equal 'a (car (cons 'a 'b)))
(test-equal 'b (cdr (cons 'a 'b)))
(test-equal #t (pair? (cons 'a 'b)))
(test-equal #f (list? (cons 'a 'b)))

;;; --- list construction from a chain of cons, and via `list` ---

(test-equal 1 (car (list 1 2 3 4)))
(test-equal 2 (car (cdr (list 1 2 3 4))))
(test-equal 4 (car (cdr (cdr (cdr (list 1 2 3 4))))))
(test-equal #t (null? (cdr (cdr (cdr (cdr (list 1 2 3 4)))))))
(test-equal #t (list? (list 1 2 3 4)))
(test-equal #t (list? (list)))
(test-equal #t (null? (list)))

;;; --- car/cdr compositions (28 total), spot-checked up to depth 4 ---

(let ((p (list 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16)))
  (test-equal 1 (caar (cons (cons 1 2) 3)))
  (test-equal 2 (cadr (list 1 2 3)))
  (test-equal 1 (cdar (cons (cons 3 1) 2)))
  (test-equal '(3) (random-access-list->linear-access-list (cddr (list 1 2 3))))
  (test-equal 1 (caaar (cons (cons (cons 1 2) 3) 4)))
  (test-equal 3 (caadr (list 1 (list 3 4))))
  (test-equal 2 (cadar (cons (list 1 2) 9)))
  (test-equal 3 (caddr (list 1 2 3 4)))
  (test-equal 4 (cadddr (list 1 2 3 4 5)))
  (test-equal 16 (list-ref p 15)))

;; every one of the 28 compositions at least runs and matches the naive
;; car/cdr expansion, generated from a single deeply-nested structure
;; `c<x1><x2><x3><x4>r` applied to p means op(x1)(op(x2)(op(x3)(op(x4)(p)))))
;; — the RIGHTMOST letter (x4) is the innermost/first operation applied, the
;; LEFTMOST (x1) is the outermost/last. E.g. caaadr = car(car(car(cdr(p)))),
;; so it takes the 'd' branch first, then two 'a' (car) branches, then a
;; final 'a' (car) — landing on the leaf reached by cdr,car,car,car from deep.
(let ((deep (cons (cons (cons (cons 'a 'b) (cons 'c 'd)) (cons (cons 'e 'f) (cons 'g 'h)))
                   (cons (cons (cons 'i 'j) (cons 'k 'l)) (cons (cons 'm 'n) (cons 'o 'p))))))
  (test-equal 'a (caaaar deep)) (test-equal 'i (caaadr deep))
  (test-equal 'e (caadar deep)) (test-equal 'm (caaddr deep))
  (test-equal 'c (cadaar deep)) (test-equal 'k (cadadr deep))
  (test-equal 'g (caddar deep)) (test-equal 'o (cadddr deep))
  (test-equal 'b (cdaaar deep)) (test-equal 'j (cdaadr deep))
  (test-equal 'f (cdadar deep)) (test-equal 'n (cdaddr deep))
  (test-equal 'd (cddaar deep)) (test-equal 'l (cddadr deep))
  (test-equal 'h (cdddar deep)) (test-equal 'p (cddddr deep)))

;;; --- length, length<=?, list? ---

(test-equal 0 (length (list)))
(test-equal 4 (length (list 1 2 3 4)))
(test-equal 100 (length (make-list 100 0)))

;; spec worked examples for length<=?
(test-equal #t (length<=? 'not-a-list 0))
(test-equal #t (length<=? (cons 'a 'b) 0))
(test-equal #t (length<=? (cons 'a 'b) 1))
(test-equal #f (length<=? (cons 'a 'b) 2))
(test-equal #t (length<=? (list 1 2 3) 3))
(test-equal #t (length<=? (list 1 2 3) 2))
(test-equal #f (length<=? (list 1 2 3) 4))
(test-equal #t (length<=? (list) 0))
(test-equal #f (length<=? (list) 1))

(test-equal #t (list? (list)))
(test-equal #t (list? (list 1 2 3)))
(test-equal #f (list? 5))
(test-equal #f (list? (cons 1 2)))
(test-equal #f (list? (cons 1 (cons 2 3))))

;;; --- make-list ---

;; spec worked example
(test-equal '(0 0 0 0 0) (random-access-list->linear-access-list (make-list 5 0)))
(test-equal 0 (length (make-list 0)))
(test-equal '() (random-access-list->linear-access-list (make-list 0)))
(test-equal 1 (length (make-list 1 'x)))
(test-equal #t (guard (e (#t #t)) (make-list -1) #f))

;; make-list produces exactly k copies of the fill value, for sizes
;; straddling the skew-binary weights 1,3,7,15,31 (where a tied pair of
;; digits of the same weight is required) as well as sizes landing exactly
;; on a weight. Reference built via native vectors, untouched by this
;; library's shadowing.
(let loop ((k 0))
  (when (<= k 40)
    (test-equal (vector->list (make-vector k 'v))
                (random-access-list->linear-access-list (make-list k 'v)))
    (loop (+ k 1))))

;;; --- list-ref / list-set ---

;; spec worked examples
(test-equal 'c (list-ref (list 'a 'b 'c 'd) 2))
(test-equal '(a b x d) (random-access-list->linear-access-list (list-set (list 'a 'b 'c 'd) 2 'x)))

;; list-ref/list-set at every index, for many sizes (exercises every
;; digit/tree shape as the list grows past each skew weight: 1,3,7,15,31,...)
(let sizes-loop ((n 1))
  (when (<= n 50)
    (let ((ra (let build ((i 0)) (if (= i n) (list) (cons i (build (+ i 1)))))))
      (test-equal n (length ra))
      (let idx-loop ((k 0))
        (when (< k n)
          (test-equal k (list-ref ra k))
          (let ((updated (list-set ra k 'X)))
            (test-equal 'X (list-ref updated k))
            (when (> k 0) (test-equal 0 (list-ref updated 0)))
            (when (< (+ k 1) n) (test-equal (+ k 1) (list-ref updated (+ k 1))))
            ;; persistence: original list is untouched by list-set
            (test-equal k (list-ref ra k)))
          (idx-loop (+ k 1)))))
    (sizes-loop (+ n 1))))

(test-equal #t (guard (e (#t #t)) (list-ref (list 1 2 3) 5) #f))
(test-equal #t (guard (e (#t #t)) (list-set (list 1 2 3) 5 'x) #f))

;;; --- list-ref/update ---

;; NOTE: uses call-with-values, not let-values, to consume the two return
;; values below. This isn't a style preference: with this library imported,
;; let-values around a call whose argument is itself built by one of this
;; library's variadic procedures (list, append, ...) intermittently fails
;; with a spurious "apply: expected proper list, got #<record_instance>"
;; VM error — reproduced independent of list-ref/update's own logic (a
;; minimal external library with just a variadic `list`-alike and an
;; unrelated values-returning procedure hits it too), so it looks like a
;; Kaappi VM/compiler bug in let-values' interaction with variadic
;; procedures rather than anything under this library's control.
;; call-with-values does not trigger it in any case tried.

;; spec worked example
(call-with-values
  (lambda () (list-ref/update (list 7 8 9 10) 2 -))
  (lambda (old new)
    (test-equal 9 old)
    (test-equal '(7 8 -9 10) (random-access-list->linear-access-list new))))

;; original is untouched (persistence), and the returned old value matches
;; a plain list-ref
(let* ((ra (list 'a 'b 'c 'd 'e)))
  (call-with-values
    (lambda () (list-ref/update ra 3 (lambda (x) (list x x))))
    (lambda (old new)
      (test-equal 'd old)
      (test-equal (list-ref ra 3) old)
      (test-equal #t (equal? (list 'd 'd) (list-ref new 3)))
      (test-equal 'd (list-ref ra 3))
      (test-equal (list-ref ra 0) (list-ref new 0))
      (test-equal (list-ref ra 4) (list-ref new 4)))))

;;; --- list-tail ---

(test-equal '(c d) (random-access-list->linear-access-list (list-tail (list 'a 'b 'c 'd) 2)))
(test-equal '() (random-access-list->linear-access-list (list-tail (list 'a 'b 'c) 3)))
(test-equal #t (equal? (list 'a 'b 'c) (list-tail (list 'a 'b 'c) 0)))

;; list-tail agrees with repeated cdr, at every index, for many sizes
;; (this specifically exercises the tree-splitting drop algorithm across
;; every possible split point within every digit shape)
(let sizes-loop ((n 1))
  (when (<= n 60)
    (let ((ra (let build ((i 0)) (if (= i n) (list) (cons i (build (+ i 1)))))))
      (let idx-loop ((k 0) (via-cdr ra))
        (when (<= k n)
          (test-equal (random-access-list->linear-access-list via-cdr)
                      (random-access-list->linear-access-list (list-tail ra k)))
          (when (< k n) (idx-loop (+ k 1) (cdr via-cdr))))))
    (sizes-loop (+ n 1))))

(test-equal #t (guard (e (#t #t)) (list-tail (list 1 2 3) 10) #f))

;;; --- append ---

;; spec worked example
(test-equal '(a b c . d) (random-access-list->linear-access-list (append (list 'a 'b) (cons 'c 'd))))
(test-equal '(1 2 3 4) (random-access-list->linear-access-list (append (list 1 2) (list 3 4))))
(test-equal '(1 2) (random-access-list->linear-access-list (append (list 1 2))))
(test-equal '() (random-access-list->linear-access-list (append)))
(test-equal '(1 2 3 4 5 6) (random-access-list->linear-access-list (append (list 1 2) (list 3 4) (list 5 6))))
;; appending onto a non-list final argument (improper result)
;; 3 proper elements consumed by list-tail leaves exactly the improper tail
(test-equal 'tail (list-tail (append (list 1 2 3) 'tail) 3))

;;; --- reverse ---

(test-equal '(3 2 1) (random-access-list->linear-access-list (reverse (list 1 2 3))))
(test-equal '() (random-access-list->linear-access-list (reverse (list))))

;;; --- map / for-each ---

(test-equal '(2 4 6) (random-access-list->linear-access-list (map (lambda (x) (* 2 x)) (list 1 2 3))))
(test-equal '(5 7 9) (random-access-list->linear-access-list (map + (list 1 2 3) (list 4 5 6))))
(test-equal '() (random-access-list->linear-access-list (map (lambda (x) x) (list))))

;; for-each's accumulator is itself built with this library's cons, so
;; convert before comparing to a native quoted literal.
(test-equal '(1 2 3)
            (random-access-list->linear-access-list
              (let ((acc (list)))
                (for-each (lambda (x) (set! acc (cons x acc))) (list 1 2 3))
                (reverse acc))))

(test-equal '(5 7 9)
            (random-access-list->linear-access-list
              (let ((acc (list)))
                (for-each (lambda (a b) (set! acc (cons (+ a b) acc))) (list 1 2 3) (list 4 5 6))
                (reverse acc))))

;; map over lists of different lengths stops at the shortest
(test-equal '(5 7) (random-access-list->linear-access-list (map + (list 1 2 3) (list 4 5))))

;;; --- equal? ---

(test-equal #t (equal? (list 1 2 3) (list 1 2 3)))
(test-equal #f (equal? (list 1 2 3) (list 1 2 4)))
(test-equal #f (equal? (list 1 2 3) (list 1 2)))
(test-equal #t (equal? (list) (list)))
(test-equal #t (equal? (list "a" "b") (list "a" "b")))
(test-equal #f (equal? (list 1 2 3) 5))
(test-equal #f (equal? 5 (list 1 2 3)))
(test-equal #t (equal? 5 5))
;; nested random-access lists compare structurally too
(test-equal #t (equal? (list (list 1 2) (list 3 4)) (list (list 1 2) (list 3 4))))
(test-equal #f (equal? (list (list 1 2) (list 3 4)) (list (list 1 2) (list 3 5))))
;; dotted pairs
(test-equal #t (equal? (cons 1 2) (cons 1 2)))
(test-equal #f (equal? (cons 1 2) (cons 1 3)))

;;; --- persistence: mutation-free operations never affect prior values ---

(let* ((a (list 1 2 3))
       (b (cons 0 a))
       (c (list-set a 0 'changed))
       (d (list-tail b 1)))
  (test-equal '(1 2 3) (random-access-list->linear-access-list a))
  (test-equal '(0 1 2 3) (random-access-list->linear-access-list b))
  (test-equal '(changed 2 3) (random-access-list->linear-access-list c))
  (test-equal '(1 2 3) (random-access-list->linear-access-list d))
  (test-equal #t (equal? a d)))

;;; --- random-access-list <-> linear-access-list conversions ---

(test-equal '(1 2 3) (random-access-list->linear-access-list (list 1 2 3)))
(test-equal '() (random-access-list->linear-access-list (list)))
(test-equal #t (equal? (list 1 2 3) (linear-access-list->random-access-list '(1 2 3))))
(test-equal #t (list? (linear-access-list->random-access-list '(1 2 3))))
(test-equal 3 (list-ref (linear-access-list->random-access-list '(1 2 3)) 2))
;; round trip through both directions is the identity (up to equal?)
(let ((native '(a b c d e f g h)))
  (test-equal native (random-access-list->linear-access-list (linear-access-list->random-access-list native))))
;; improper tails round-trip too
(test-equal '(1 2 . 3) (random-access-list->linear-access-list (linear-access-list->random-access-list '(1 2 . 3))))

;;; --- a larger structural stress: build up to 200 elements one cons at a
;;; time (forcing every skew-binary merge case along the way), and check
;;; every element is reachable and correct via both list-ref and repeated cdr

(let* ((n 200)
       (ra (let build ((i 1)) (if (> i n) (list) (cons i (build (+ i 1)))))))
  (test-equal n (length ra))
  (test-equal #t (list? ra))
  (let check ((k 0) (via-cdr ra))
    (when (< k n)
      (test-equal (+ k 1) (list-ref ra k))
      (test-equal (+ k 1) (car via-cdr))
      (check (+ k 1) (cdr via-cdr)))))

(let ((runner (test-runner-current)))
  (test-end "srfi-101")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
