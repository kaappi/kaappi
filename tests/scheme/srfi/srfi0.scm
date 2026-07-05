;; SRFI-0 (cond-expand) conformance tests — audit Phase 3a
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi0.scm

(import (scheme base) (srfi 0) (chibi test))

(test-begin "srfi-0")

;; else clause
(test 'e (cond-expand (this-feature-does-not-exist 'x) (else 'e)))

;; a real feature matches (r7rs is required of conforming implementations)
(test 'r7 (cond-expand (r7rs 'r7) (else 'no)))

;; and / or / not requirements
(test 'a (cond-expand ((and r7rs r7rs) 'a) (else 'no)))
(test 'no (cond-expand ((and r7rs this-feature-does-not-exist) 'x) (else 'no)))
(test 'o (cond-expand ((or this-feature-does-not-exist r7rs) 'o) (else 'no)))
(test 'no (cond-expand ((or nope-1 nope-2) 'x) (else 'no)))
(test 'n (cond-expand ((not this-feature-does-not-exist) 'n) (else 'no)))
(test 'no (cond-expand ((not r7rs) 'x) (else 'no)))

;; empty (and) is true, empty (or) is false
(test 'a (cond-expand ((and) 'a) (else 'no)))
(test 'no (cond-expand ((or) 'x) (else 'no)))

;; library clauses
(test 'lib (cond-expand ((library (scheme base)) 'lib) (else 'no)))
(test 'nolib (cond-expand ((library (kaappi totally absent)) 'x) (else 'nolib)))

;; nested requirements
(test 'nested (cond-expand ((and (or nope r7rs) (not nope-2)) 'nested) (else 'no)))

;; first matching clause wins
(test 'first (cond-expand (r7rs 'first) (r7rs 'second) (else 'no)))

;; multiple body forms
(test 2 (cond-expand (r7rs (define-values (a) 1) (+ a 1)) (else 'no)))

(test-end "srfi-0")
