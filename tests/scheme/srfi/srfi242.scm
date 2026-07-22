;; SRFI-242 (The CFG Language) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi242.scm
;;
;; This covers the static subset Kaappi implements: cfg, execute, halt,
;; bind, label*, call. See lib/srfi/242.sld's header for what's out of
;; scope (labels/finally/permute/define-cfg-*) and why.

(import (scheme base) (scheme process-context) (srfi 242) (srfi 64))

(test-begin "srfi-242")

;;; --- halt: the base case, evaluates result at that point ---
(test-equal "cfg + halt: trivial" 42 (cfg (halt) 42))

;;; --- execute: multi-way branch, one continuation invoked ---
(test-equal "execute: first continuation"
  'took-first
  (cfg (execute (lambda (yes no) (yes)) (() (halt)) (() (halt))) 'took-first))
(test-equal "execute: second continuation"
  'took-second
  (cfg (execute (lambda (yes no) (no)) (() (halt)) (() (halt))) 'took-second))

;;; --- execute: continuation formals receive proc-expr's call arguments ---
(test-equal "execute: continuation formals bind call arguments"
  30
  (cfg (execute (lambda (k) (k 10 20)) ((x y) (halt))) (+ x y)))

;;; --- bind: parallel let-values-style bindings ---
(test-equal "bind: single binding" 5 (cfg (bind (((x) 5)) (halt)) x))
(test-equal "bind: multiple bindings, in parallel"
  3
  (cfg (bind (((x) 1) ((y) 2)) (halt)) (+ x y)))
(test-equal "bind: multiple-value formals"
  8
  (cfg (bind (((q r) (floor/ 22 3))) (halt)) (+ q r)))

;;; --- label* + call: straight-line sequencing ---
(test-equal "label*: single label, called once"
  'reached
  (cfg (label* ((f (halt))) (call f)) 'reached))

(test-equal "label*: later label calls an earlier one"
  99
  (cfg (label* ((f (halt)) (g (call f))) (call g)) 99))

(test-equal "label*: body can call any previously bound label"
  'first
  (cfg (label* ((f (halt)) (g (halt))) (call f)) 'first))

;; Regression: label* is a STATIC label — a call re-expands the label's
;; term inline at the call site, so the same label reused from two
;; different scopes sees each call site's own bindings rather than
;; closing over one fixed definition-site environment.
(let ((run (lambda (flag)
             (cfg (label* ((f (halt)))
                    (execute (lambda (branch-a branch-b) (if flag (branch-a) (branch-b)))
                      (() (bind (((v) 10)) (call f)))
                      (() (bind (((v) 20)) (call f)))))
               v))))
  (test-equal "label*: static call picks up the call site's own binding (branch a)" 10 (run #t))
  (test-equal "label*: static call picks up the call site's own binding (branch b)" 20 (run #f)))

;;; --- composition with ordinary Scheme recursion for genuine loops ---
;; label*/call alone can't loop (a label's term can't reference itself —
;; see lib/srfi/242.sld's header). Real iteration composes a cfg term's
;; execute/halt with an ordinary tail-recursive Scheme procedure that
;; wraps a fresh cfg term per step, exactly as SRFI 265 describes this
;; SRFI's intended use: infrastructure for loop facilities, not a
;; self-contained looping construct. The recursive step is a plain tail
;; call from inside proc-expr itself (proc-expr is arbitrary Scheme code
;; that need only call one of its continuations *when it wants to leave
;; the graph*) — a continuation clause's own term must still be a real
;; cfg-term, so the recursive call can't live there.
(define (%fact-loop x a)
  (cfg (execute (lambda (done) (if (> x 6) (done) (%fact-loop (+ x 1) (* a x))))
         (() (halt)))
    a))
(test-equal "cfg composes with tail-recursive Scheme for a real loop (6!)" 720 (%fact-loop 1 1))

(let ((runner (test-runner-current)))
  (test-end "srfi-242")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
