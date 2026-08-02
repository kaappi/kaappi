;; SRFI-42 (eager comprehensions) conformance tests
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi42.scm

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 42) (srfi 64))

(test-begin "srfi-42")

;;; --- list-ec with the core generators ---
(test-equal "range 1-arg" '(0 1 2 3) (list-ec (:range i 4) i))
(test-equal "range 2-arg" '(2 3 4) (list-ec (:range i 2 5) i))
(test-equal "range 3-arg" '(0 2 4) (list-ec (:range i 0 6 2) i))
(test-equal "list" '(a b) (list-ec (:list x '(a b)) x))
(test-equal "string" '(#\a #\b) (list-ec (:string c "ab") c))
(test-equal "vector" '(1 2) (list-ec (:vector x #(1 2)) x))

;;; --- accumulators ---
(test-equal "sum-ec" 6 (sum-ec (:range i 4) i))
(test-equal "product-ec" 24 (product-ec (:list x '(2 3 4)) x))
(test-equal "min-ec" 0 (min-ec (:range i 4) i))
(test-equal "max-ec" 3 (max-ec (:range i 4) i))
(test-equal "first-ec" 0 (first-ec 'none (:range i 4) i))
(test-equal "last-ec" 3 (last-ec 'none (:range i 4) i))
(test-equal "first-ec default" 'none (first-ec 'none (:range i 0) i))
(test-equal "any?-ec true" #t (any?-ec (:range i 4) (even? i)))
(test-equal "every?-ec false" #f (every?-ec (:range i 4) (even? i)))
(test-equal "every?-ec true" #t (every?-ec (:list x '(2 4)) (even? x)))
(test-equal "string-ec" "ab" (string-ec (:list c '(#\a #\b)) c))
(test-equal "vector-ec" #(0 1) (vector-ec (:range i 2) i))
(test-equal "append-ec" '(1 2 3 4) (append-ec (:list xs '((1 2) (3 4))) xs))

;;; --- do-ec for effects ---
(test-equal "do-ec"
  '(0 1 2)
  (let ((acc '()))
    (do-ec (:range i 3) (set! acc (cons i acc)))
    (reverse acc)))

;;; --- fold-ec (SRFI-42 signature: seed qualifier... expr proc) ---
(test-equal "fold-ec +" 6 (fold-ec 0 (:range i 4) i +))
(test-equal "fold-ec cons" '(2 1 0) (fold-ec '() (:range i 3) i cons))
(test-equal "fold-ec -" 2 (fold-ec 0 (:range i 1 4) i -))

;;; --- fold3-ec (seed qualifier... expr f1 f2) ---
(test-equal "fold3-ec" 6 (fold3-ec 'unused (:range i 1 4) i values +))
(test-equal "fold3-ec empty" 'empty (fold3-ec 'empty (:range i 0) i values +))

;;; --- nested generators (cartesian product, rightmost spins fastest) ---
(test-equal "nested list x list"
  '((1 . 3) (1 . 4) (2 . 3) (2 . 4))
  (list-ec (:list a '(1 2)) (:list b '(3 4)) (cons a b)))

(test-equal "nested range x range"
  '((0 0) (0 1) (1 0) (1 1))
  (list-ec (:range i 2) (:range j 2) (list i j)))

;;; --- guards ---
(test-equal "if guard" '(0 2 4) (list-ec (:range i 6) (if (even? i)) i))

(test-equal "not guard" '(1 3 5) (list-ec (:range i 6) (not (even? i)) i))

(test-equal "and guard" '(2 4) (list-ec (:range i 6) (and (even? i) (> i 0)) i))

(test-equal "or guard" '(0 1 3 5) (list-ec (:range i 6) (or (not (even? i)) (= i 0)) i))

;;; --- :let ---
(test-equal ":let" '(10) (list-ec (:let x 10) x))

(test-equal ":let with range"
  '(0 10 20)
  (list-ec (:range i 3) (:let x (* i 10)) x))

;;; --- :while (stop entire comprehension when test becomes false) ---
(test-equal ":while standalone" '(0 1 2)
  (list-ec (:range i 100) (:while (< i 3)) i))

(test-equal ":while wrapping generator" '(0 1 2 3 4)
  (list-ec (:while (:range i 10) (< i 5)) i))

;;; --- :until (include the triggering element, then stop) ---
(test-equal ":until" '(0 1 2 3) (list-ec (:range i 100) (:until (= i 3)) i))

;;; --- :integers with :while (infinite generator, bounded by :while) ---
(test-equal ":integers + :while"
  '(0 1 2)
  (list-ec (:integers i) (:while (< i 3)) i))

;;; --- combined: nested + guard ---
(test-equal "nested + guard"
  '((1 . 4) (2 . 3) (2 . 4))
  (list-ec (:list a '(1 2)) (:list b '(3 4)) (if (> (+ a b) 4)) (cons a b)))

;;; --- generic ':' dispatch (#2177) ---
(test-equal ": exact integer 1-arg" '(0 1 2 3 4) (list-ec (: i 5) i))
(test-equal ": exact integers 2-arg" '(2 3 4 5 6) (list-ec (: i 2 7) i))
(test-equal ": exact integers 3-arg" '(0 3 6 9) (list-ec (: i 0 10 3) i))
(test-equal ": list" '(a b c) (list-ec (: x '(a b c)) x))
(test-equal ": empty list" '() (list-ec (: x '()) x))
(test-equal ": two lists concatenate" '(1 2 3 4)
  (list-ec (: x '(1 2) '(3 4)) x))
(test-equal ": four lists (n>3 dispatch)" '(1 2 3 4)
  (list-ec (: x '(1) '(2) '(3) '(4)) x))
(test-equal ": string" '(#\h #\i) (list-ec (: c "hi") c))
(test-equal ": string round-trip" "hello" (string-ec (: c "hello") c))
(test-equal ": two strings concatenate" "abcd" (string-ec (: c "ab" "cd") c))
(test-equal ": vector" '(1 2 3) (list-ec (: x #(1 2 3)) x))
(test-equal ": two vectors concatenate" '(1 2 3 4)
  (list-ec (: x #(1 2) #(3 4)) x))
(test-equal ": real 1-arg" '(0.0 1.0 2.0) (list-ec (: x 2.5) x))
(test-equal ": rational step dispatches to :real-range" '(0 1/4 1/2 3/4)
  (list-ec (: x 0 1 1/4) x))
(test-equal ": char range" '(#\a #\b #\c #\d #\e) (list-ec (: c #\a #\e) c))
(test-equal ": port default read" '(10 20 (a b))
  (call-with-port (open-input-string "10 20 (a b)")
    (lambda (p) (list-ec (: x p) x))))
(test-equal ": port with reader" '(#\a #\b)
  (call-with-port (open-input-string "ab")
    (lambda (p) (list-ec (: c p read-char) c))))
(test-equal ": with guard" '(0 2 4) (list-ec (: i 6) (if (even? i)) i))
(test-equal ": wrapped by :while" '(0 1 2)
  (list-ec (:while (: i 10) (< i 3)) i))
(test-equal ": nested gets a fresh generator each entry"
  '((1 0) (2 0) (2 1) (3 0) (3 1) (3 2))
  (list-ec (:range n 1 4) (: i n) (list n i)))
(test-equal "sum-ec with :" 10 (sum-ec (: i 5) i))
(test-equal ": unrecognized argument raises catchably" 'caught
  (guard (e (#t 'caught)) (list-ec (: x #t) x)))

;;; --- :real-range ---
(test-equal ":real-range 1-arg all-exact stays exact" '(0 1 2 3 4)
  (list-ec (:real-range x 5) x))
(test-equal ":real-range exact rationals" '(0 1/4 1/2 3/4)
  (list-ec (:real-range x 0 1 1/4) x))
(test-equal ":real-range inexact bound infects start" '(0.0 1.0 2.0)
  (list-ec (:real-range x 0 3.0) x))
(test-equal ":real-range inexact step" '(0.0 0.5 1.0 1.5)
  (list-ec (:real-range x 0 2 0.5) x))
(test-equal ":real-range descending" '(5 4 3 2 1)
  (list-ec (:real-range x 5 0 -1) x))

;;; --- :char-range (both endpoints inclusive) ---
(test-equal ":char-range inclusive" "abcde"
  (string-ec (:char-range c #\a #\e) c))
(test-equal ":char-range single char" '(#\q)
  (list-ec (:char-range c #\q #\q) c))
(test-equal ":char-range empty when min above max" '()
  (list-ec (:char-range c #\e #\a) c))
(test-equal ":until wrapping :char-range" '(#\a #\b #\c)
  (list-ec (:until (:char-range c #\a #\z) (char=? c #\c)) c))

;;; --- :port (was exported but unusable before #2177's fix) ---
(test-equal ":port default reader" '(1 (2) x)
  (call-with-port (open-input-string "1 (2) x")
    (lambda (p) (list-ec (:port v p) v))))
(test-equal ":port custom reader" '(#\x #\y)
  (call-with-port (open-input-string "xy")
    (lambda (p) (list-ec (:port c p read-char) c))))

;;; --- :do (was exported but unusable before #2177's fix) ---
(test-equal ":do short form" '(0 1 2 3)
  (list-ec (:do ((i 0)) (< i 4) ((+ i 1))) i))
(test-equal ":do full form uses all six slots" '(0 10 20)
  (list-ec (:do (let ((n 4)))
                ((i 0))
                (< i n)
                (let ((j (* i 10))))
                (< i 2)
                ((+ i 1)))
           j))

;;; --- :parallel (was exported but unusable before #2177's fix) ---
(test-equal ":parallel lockstep, shortest wins" '((1 a) (2 b) (3 c))
  (list-ec (:parallel (:range i 1 10) (:list x '(a b c))) (list i x)))
(test-equal ":parallel three generators incl. infinite :integers"
  '((0 a 10) (1 b 11))
  (list-ec (:parallel (:integers i) (:list x '(a b)) (:range j 10 20))
           (list i x j)))
(test-equal ":parallel with coroutine-backed :let" '((1 . z))
  (list-ec (:parallel (:list a '(1 2 3)) (:let b 'z)) (cons a b)))

;;; --- :dispatched with a hand-written dispatcher ---
(define (upto-dispatcher args)
  (if (and (= 1 (length args)) (exact-integer? (car args)))
      (let ((n (car args)) (i 0))
        (lambda (empty)
          (if (< i n)
              (let ((v i)) (set! i (+ i 1)) v)
              empty)))
      #f))
(test-equal ":dispatched custom dispatcher" '(0 1 2)
  (list-ec (:dispatched i upto-dispatcher 3) i))

;;; --- :generator-proc protocol ---
(define (drain-gproc g)
  (let ((e (list #f)))
    (let loop ((acc '()) (v (g e)))
      (if (eq? v e) (reverse acc) (loop (cons v acc) (g e))))))
(test-equal ":generator-proc fast path" '(0 1 2)
  (drain-gproc (:generator-proc (:range 3))))
(test-equal ":generator-proc coroutine fallback" '(5)
  (drain-gproc (:generator-proc (:let 5))))

;;; --- dispatcher machinery ---
(test-equal "initial dispatcher identification" 'SRFI42
  ((make-initial-:-dispatch) '()))
(test-equal "dispatch-union appends identifications" '(SRFI42 symbols)
  ((dispatch-union (make-initial-:-dispatch)
                   (lambda (args) (if (null? args) 'symbols #f)))
   '()))

;; Extending ':' (mutates the library-global dispatcher; keep last).
(:-dispatch-set!
 (dispatch-union
  (:-dispatch-ref)
  (lambda (args)
    (if (and (= 1 (length args)) (symbol? (car args)))
        (:generator-proc (:string (symbol->string (car args))))
        #f))))
(test-equal ": extended to symbols via dispatch-union" '(#\f #\o #\o)
  (list-ec (: c 'foo) c))
(test-equal ": still handles integers after extension" '(0 1 2)
  (list-ec (: i 3) i))

;;; --- multi-argument typed generators (concatenation) ---
(test-equal ":list multi-arg" '(1 2 3) (list-ec (:list x '(1 2) '(3)) x))
(test-equal ":string multi-arg" "abcd" (string-ec (:string c "ab" "cd") c))
(test-equal ":vector multi-arg incl. empty" '(1 2 3 4)
  (list-ec (:vector x #(1 2) #() #(3 4)) x))

(let ((runner (test-runner-current)))
  (test-end "srfi-42")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
