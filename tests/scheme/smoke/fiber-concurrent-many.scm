;; Coverage test for KEP-0001 Phase 2 (kaappi/kaappi#1440): the fiber
;; scheduler's table is now a growable list, not a fixed 64-slot array.
;; Spawns 100 fibers BEFORE joining any of them, so all 100 are
;; concurrently live at once — unlike fiber-slot-reuse.scm's sequential
;; spawn-then-join pattern, which never has more than a couple of fibers
;; alive simultaneously.

(import (scheme base) (scheme write) (kaappi fibers))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ")
        (display name)
        (display " got=")
        (write got)
        (display " expected=")
        (write expected)
        (newline))))

(define n 100)

(define fibers
  (let loop ((i 0) (acc '()))
    (if (= i n)
        (reverse acc)
        (loop (+ i 1) (cons (spawn (lambda () (* i i))) acc)))))

(define results (map fiber-join fibers))

(check "fiber-count" (length results) n)
(check "first-result" (car results) 0)
(check "last-result" (list-ref results (- n 1)) (* (- n 1) (- n 1)))
(check "all-fibers?"
       (let loop ((fs fibers))
         (cond ((null? fs) #t)
               ((not (fiber? (car fs))) #f)
               (else (loop (cdr fs)))))
       #t)

;; Summary
(display pass)
(display " passed, ")
(display fail)
(display " failed")
(newline)
(when (> fail 0) (error "test failures" fail))
