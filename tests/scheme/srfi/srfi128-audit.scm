;; SRFI 128 audit: default-hash must be depth-bounded (kaappi#2235).
;;
;; A cyclic key is "an error" under SRFI 128 / SRFI 146, but the failure mode
;; must stay bounded (no uncatchable KP3008 stack overflow). Before the depth
;; budget was added, a make-default-comparator hashmap keyed on a cyclic key
;; recursed default-hash into the stack cap and aborted the process.

(import (scheme base)
        (scheme write)
        (srfi 128)
        (srfi 146 hash))

(define failures 0)
(define (check name got want)
  (if (equal? got want)
      (begin (display "ok   ") (display name) (newline))
      (begin (set! failures (+ failures 1))
             (display "FAIL ") (display name)
             (display " got=") (write got)
             (display " want=") (write want) (newline))))

(define (ok-hash? h)
  (and (exact-integer? h) (<= 0 h)))

;; --- ordinary (acyclic) values still hash to stable non-negative integers ---
(check "hash-number"   (ok-hash? (default-hash 42)) #t)
(check "hash-negnum"   (ok-hash? (default-hash -7)) #t)
(check "hash-string"   (ok-hash? (default-hash "hello")) #t)
(check "hash-list"     (ok-hash? (default-hash '(1 2 3))) #t)
(check "hash-nested"   (ok-hash? (default-hash '(1 (2 . 3) #(4) "five"))) #t)
(check "hash-vector"   (ok-hash? (default-hash #(1 2 3))) #t)

;; default-hash is a pure function of value: equal inputs hash equal, and the
;; same input hashes the same twice.
(check "hash-stable"   (= (default-hash '(1 2 3)) (default-hash '(1 2 3))) #t)
(check "hash-equal-eq" (= (default-hash '(1 2)) (default-hash (list 1 2))) #t)

;; --- the regression: a cyclic key must TERMINATE, not abort the process ---
(define cyc (list 1 2 3))
(set-cdr! (cddr cyc) cyc)          ; cyc is now a cyclic list

;; default-hash on the cycle returns a bounded integer instead of overflowing.
(check "cyclic-hash-terminates" (ok-hash? (default-hash cyc)) #t)

;; and inserting the cyclic key into a make-default-comparator hashmap
;; completes (this is the exact repro from the issue).
(define hm (hashmap (make-default-comparator) cyc 'v))
(check "cyclic-hashmap-insert" (hashmap-contains? hm cyc) #t)

(newline)
(if (= failures 0)
    (begin (display "All SRFI 128 audit checks passed.") (newline))
    (begin (display "FAILURES: ") (display failures) (newline)
           (error "srfi128-audit failed")))
