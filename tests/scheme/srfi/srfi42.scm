;; SRFI-42 (eager comprehensions) conformance tests
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi42.scm

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 42) (srfi 64))

(test-begin "srfi-42")

;; Shared helper: run thunk, return the message of the error it raises.
(define (caught-message thunk)
  (guard (e (#t (error-object-message e))) (thunk)))

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

;; The spec's wrapping form scopes the test to the wrapped generator
;; only — enclosing generators continue (PR #2180 review).  Before the
;; fix these stopped the whole comprehension at the first failing test.
(test-equal ":while wrap stops only the wrapped generator"
  '((0 . 1) (1 . 1))
  (list-ec (:range j 2) (:while (:list x '(1 2 3)) (< x 2)) (cons j x)))
(test-equal ":until wrap stops only the wrapped generator"
  '((0 1) (0 2) (1 1) (1 2))
  (list-ec (:range j 2) (:until (:list x '(1 2 3 4)) (= x 2)) (list j x)))
;; The bare forms are this port's extension and keep their documented
;; stop-everything meaning, even from inside a wrapped generator.
(test-equal "bare :while still stops the whole comprehension"
  '((0 . 1))
  (list-ec (:range j 2) (:list x '(1 2 3))
           (:while (and (= j 0) (< x 2))) (cons j x)))
(test-equal "bare :until inside a wrapped generator stops everything"
  '((0 . 1) (0 . 2))
  (list-ec (:range j 2) (:until (:list x '(1 2 3)) (= x 99))
           (:until (= x 2)) (cons j x)))

;;; --- :until (include the triggering element, then stop) ---
(test-equal ":until" '(0 1 2 3) (list-ec (:range i 100) (:until (= i 3)) i))

;;; --- (nested ...) grouping and (begin ...) command qualifiers ---
(test-equal "nested qualifier groups a sequence"
  '((0 0) (0 1) (1 0) (1 1))
  (list-ec (nested (:range i 2) (:range j 2)) (list i j)))
(test-equal "nested qualifier composes with a guard"
  '(1 3)
  (list-ec (nested (:range i 4) (if (odd? i))) i))
(test-equal "begin qualifier runs its commands once per binding"
  '(3 (0 1 2))
  (let ((n 0))
    (let ((r (list-ec (:range i 3) (begin (set! n (+ n 1))) i)))
      (list n r))))
(test-equal "a body that is itself a begin form stays the body"
  '(0 1)
  (let ((acc '()))
    (do-ec (:range i 2) (begin (set! acc (cons i acc))))
    (reverse acc)))

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
;; The reference implementation's dispatcher tests (string? a1) twice in
;; its 2- and 3-argument string cases where a2/a3 were meant; these pin
;; the corrected branches.  The mixed-type case is the discriminating
;; one: under the reference's typo it would (wrongly) dispatch to
;; :string; the corrected check falls through to "unrecognized".
(test-equal ": three strings (3-arg dispatch)" "abcdef"
  (string-ec (: c "ab" "cd" "ef") c))
(test-equal ": three vectors (3-arg dispatch)" '(1 2 3)
  (list-ec (: x #(1) #(2) #(3)) x))
(test-equal ": mixed string/vector args are unrecognized (a2 is checked)"
  "unrecognized arguments in dispatching"
  (caught-message (lambda () (list-ec (: c "ab" #(1) "cd") c))))
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
;; A dispatcher answers '() with its identification, not a generator —
;; the convention dispatch-union and the failure path rely on.
(define (upto-dispatcher args)
  (cond
    ((null? args) 'upto)
    ((and (= 1 (length args)) (exact-integer? (car args)))
     (let ((n (car args)) (i 0))
       (lambda (empty)
         (if (< i n)
             (let ((v i)) (set! i (+ i 1)) v)
             empty))))
    (else #f)))
(test-equal ":dispatched custom dispatcher" '(0 1 2)
  (list-ec (:dispatched i upto-dispatcher 3) i))
;; The failure path reports (d '()) as the second error irritant, so the
;; identification is observable through the library, not just directly.
(test-equal ":dispatched failure reports the dispatcher identification"
  'upto
  (guard (e (#t (cadr (error-object-irritants e))))
    (list-ec (:dispatched i upto-dispatcher 'not-an-integer) i)))

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
;; Both dispatchers claiming the same argument list is a conflict.
(test-equal "dispatch-union conflict raises" "dispatching conflict"
  (caught-message
   (lambda ()
     (let ((d (dispatch-union
               (lambda (args)
                 (cond ((null? args) 'first)
                       ((and (= 1 (length args)) (symbol? (car args)))
                        (:generator-proc (:list (list (car args)))))
                       (else #f)))
               (lambda (args)
                 (cond ((null? args) 'second)
                       ((and (= 1 (length args)) (symbol? (car args)))
                        (:generator-proc (:list '(other))))
                       (else #f))))))
       (list-ec (:dispatched x d 'sym) x)))))

;;; --- zero step is rejected loudly (PR #2180 review) ---
;; Before the fix, (:range i 5 3 0) looped forever yielding 5 (the macro
;; arm and the new %gen-range never advance x), and an inexact zero step
;; in :real-range gave istop = +inf.0 — another silent infinite loop.
;; An exact zero step in :real-range already errored (division by zero);
;; the explicit check just names the actual mistake.
(test-equal ":range zero step raises (macro path)"
  "step size must not be zero in :range"
  (caught-message (lambda () (list-ec (:range i 5 3 0) i))))
(test-equal ":range zero step raises even when from < to"
  "step size must not be zero in :range"
  (caught-message (lambda () (list-ec (:range i 5 7 0) i))))
(test-equal ":range zero step raises (dispatch path)"
  "step size must not be zero in :range"
  (caught-message (lambda () (list-ec (: i 5 3 0) i))))
(test-equal ":range zero step raises (:generator-proc path)"
  "step size must not be zero in :range"
  (caught-message (lambda () (:generator-proc (:range 5 3 0)))))
(test-equal ":real-range exact zero step raises"
  "step size must not be zero in :real-range"
  (caught-message (lambda () (list-ec (:real-range x 0 1 0) x))))
(test-equal ":real-range inexact zero step raises (was an infinite loop)"
  "step size must not be zero in :real-range"
  (caught-message (lambda () (list-ec (:real-range x 0.0 1.0 0.0) x))))
(test-equal ":real-range zero step raises (dispatch path)"
  "step size must not be zero in :real-range"
  (caught-message (lambda () (list-ec (: x 0.0 1.0 0.0) x))))
(test-equal ":real-range zero step raises (:generator-proc path)"
  "step size must not be zero in :real-range"
  (caught-message (lambda () (:generator-proc (:real-range 0 1 0)))))

;;; --- multi-argument typed generators (concatenation) ---
(test-equal ":list multi-arg" '(1 2 3) (list-ec (:list x '(1 2) '(3)) x))
(test-equal ":string multi-arg" "abcd" (string-ec (:string c "ab" "cd") c))
(test-equal ":vector multi-arg incl. empty" '(1 2 3 4)
  (list-ec (:vector x #(1 2) #() #(3 4)) x))

;;; --- extending ':' via :-dispatch-set! ---
;; This block MUTATES the library-global dispatcher, so it must stay the
;; last section: every earlier ':' test targets the unmutated initial
;; dispatcher.
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

(let ((runner (test-runner-current)))
  (test-end "srfi-42")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
