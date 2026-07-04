;; SRFI-158 generator tests.
;;
;; Regression focus: gtake, generator->list, and every other procedure that
;; drives a list of generators used to call them via the native map
;; primitive ((map (lambda (g) (g)) gs)). Coroutine generators capture a
;; continuation inside that call, and a continuation captured under a
;; native frame cannot resume after the native frame returns — the second
;; call crashed with "type error in 'cdr': expected pair, got #<procedure>"
;; or silently produced garbage. The impl now drives generators with plain
;; Scheme recursion (%call-generators in lib/srfi/158-impl.scm).
;;
;; Uses manual counters rather than SRFI-64. (Importing (srfi 64) together
;; with (srfi 158) used to trigger a nondeterministic CompileError in the
;; library loader — a GC hole fixed with issue #1010 and covered by
;; srfi-import-order.scm — but manual counters are kept so this file stays
;; independent of the test framework.)
(import (scheme base) (scheme write) (scheme process-context) (srfi 158))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))

;; gtake on an infinite generator (the original crash repro)
(check "gtake range"
  (generator->list (gtake (make-range-generator 0 100) 5))
  '(0 1 2 3 4))

;; generator->list with a count delegates to gtake
(check "generator->list n"
  (generator->list (make-range-generator 0 100) 3)
  '(0 1 2))

;; gtake with padding past the end of a finite generator
(check "gtake padding"
  (generator->list (gtake (generator 1 2) 4 'pad))
  '(1 2 pad pad))

;; generator->list over a coroutine generator (crashed in generator-fold)
(check "coroutine generator->list"
  (generator->list (make-coroutine-generator
                    (lambda (yield) (yield 'a) (yield 'b) (yield 'c))))
  '(a b c))

;; generator-fold over multiple generators
(check "generator-fold two gens"
  (generator-fold (lambda (a b acc) (cons (+ a b) acc)) '()
                  (generator 1 2 3) (generator 10 20 30))
  '(33 22 11))

;; gmap over multiple generators
(check "gmap two gens"
  (generator->list (gmap + (generator 1 2 3) (generator 10 20 30)))
  '(11 22 33))

;; gcombine threads a seed through the calls
(check "gcombine"
  (generator->list
   (gcombine (lambda (x seed) (values (+ x seed) (+ seed 1)))
             0 (generator 10 20 30)))
  '(10 21 32))

;; generator-for-each over multiple generators
(check "generator-for-each"
  (let ((acc '()))
    (generator-for-each (lambda (a b) (set! acc (cons (+ a b) acc)))
                        (generator 1 2) (generator 10 20))
    acc)
  '(22 11))

;; generator-map->list over multiple generators
(check "generator-map->list"
  (generator-map->list + (generator 1 2 3) (generator 4 5 6))
  '(5 7 9))

;; generator->vector and ->string with a count (delegate through gtake)
(check "generator->vector n"
  (generator->vector (make-range-generator 5) 3)
  #(5 6 7))
(check "generator->string n"
  (generator->string (generator #\k #\a #\a #\p #\p #\i) 6)
  "kaappi")

;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (exit 1))
