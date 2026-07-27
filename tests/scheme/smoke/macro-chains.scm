;;; Head-position macro expansion chains (kaappi#1796): an expansion that
;;; is directly another macro use in the same position is compiled
;;; iteratively, so chain length is bounded by the expansion STEP limit
;;; (10,000), not the nesting depth cap (256) that guards native stack.
;;; Before the fix, the 400-link chain below failed with KP2003; the depth
;;; cap could not simply be raised, because deep chains then overflowed
;;; the native stack. Divergent-chain error cases live in the unit suite
;;; (src/tests_macro_chains.zig) — a compile error would abort this file.
(import (scheme base) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "macro-chains")

;; 1. Peano countdown: one chain link per list element, far past the
;; nesting-depth cap of 256.
(define-syntax count-down
  (syntax-rules ()
    ((_ ()) 'done)
    ((_ (s . rest)) (count-down rest))))

(test-eq "400-link head-position chain compiles and runs" 'done
  (count-down
    (s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s
     s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s
     s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s
     s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s
     s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s
     s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s
     s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s
     s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s
     s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s
     s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s s)))

;; 2. Hygiene across links: the reference to `secret` is introduced by the
;; FIRST link's template but only compiled after the second link has been
;; processed — early-link hygiene bookkeeping must survive to the final
;; form.
(define (chained-hygiene)
  (define secret 41)
  (define-syntax finishing
    (syntax-rules () ((_ e) e)))
  (define-syntax starting
    (syntax-rules () ((_) (finishing (+ secret 1)))))
  (starting))

(test-eqv "captured local from an early chain link resolves in the final form" 42
  (chained-hygiene))

;; 3. Argument material threads through a chain of three distinct macros.
(define-syntax hop3 (syntax-rules () ((_ v) (list 'c v))))
(define-syntax hop2 (syntax-rules () ((_ v) (hop3 (+ v 1)))))
(define-syntax hop1 (syntax-rules () ((_ v) (hop2 (* v 2)))))

(test-equal "three-macro chain threads its argument" '(c 21)
  (hop1 10))

;; 4. A chain inside a tail position keeps the tail flag: deep recursion
;; through a chained macro must not grow the VM stack either.
(define-syntax go (syntax-rules () ((_ f n) (go-really f n))))
(define-syntax go-really (syntax-rules () ((_ f n) (f n))))
(define (spin k) (if (= k 0) 'spun (go spin (- k 1))))

(test-eq "chained macro in tail position preserves tail calls" 'spun
  (spin 100000))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "macro-chains")
(if (> %test-fail-count 0) (exit 1))
