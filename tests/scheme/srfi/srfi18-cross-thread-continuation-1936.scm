;; Regression test for #1936: invoking a continuation captured on another
;; OS thread produced a value outside the type lattice.
;;
;; A continuation lives in the heap of the thread that captured it. SRFI-18
;; values cross the thread boundary by deep copy, and a continuation is on
;; the uncopyable list -- so the ONLY way a child thread can reach a
;; parent-thread continuation is through the shared-globals path, bypassing
;; the copy check. Invoking it overwrote the child VM's state with the
;; parent's saved frames and resumed the parent's bytecode on the wrong VM;
;; the join then handed back a value on which every R7RS disjoint-type
;; predicate answered #f -- a value the type lattice does not allow, and one
;; a program cannot detect, branch on, or report.
;;
;; Fix: refuse the invocation with a catchable error (the issue's suggested
;; direction: "A raise is much better than a value no predicate
;; recognises"). Every continuation-invoke site checks that the continuation
;; is owned by the invoking VM's GC; same-thread invocation (any fiber on
;; the capturing thread) is unaffected.

(import (scheme base) (scheme write) (scheme process-context) (srfi 18) (srfi 64))

(test-begin "cross-thread-continuation-invoke-1936")

(define (msg-contains? s sub)
  (let ((ls (string-length s)) (lb (string-length sub)))
    (let loop ((i 0))
      (cond ((> (+ i lb) ls) #f)
            ((string=? (substring s i (+ i lb)) sub) #t)
            (else (loop (+ i 1)))))))

;; Same-thread call/cc still works (control for the mechanism itself).
(test-equal "control: same-thread continuation invocation still works"
  42 (call/cc (lambda (k) (k 42))))
(test-equal "control: same-thread escape continuation still works"
  42 (call-with-escape-continuation (lambda (k) (k 42))))

;; The cross-thread invoke must raise a catchable error, not return a value
;; every predicate rejects.
(define saved-k #f)
(call/cc (lambda (k) (set! saved-k k) 'captured))
(define t (make-thread (lambda () (saved-k 'from-child))))
(thread-start! t)
(test-assert "a child invoking a parent continuation gets a catchable error"
  (guard (e ((uncaught-exception? e)
             (let ((reason (uncaught-exception-reason e)))
               (and (error-object? reason)
                    (msg-contains? (error-object-message reason)
                                   "continuation belongs to another OS thread"))))
            (#t #f))
    (thread-join! t)
    #f))

;; Same for an ESCAPE continuation reached through a global.
(define saved-ec #f)
(call-with-escape-continuation (lambda (k) (set! saved-ec k) 'ec-captured))
(define t2 (make-thread (lambda () (saved-ec 'x))))
(thread-start! t2)
(test-assert "a child invoking a parent escape continuation gets a catchable error"
  (guard (e ((uncaught-exception? e)
             (let ((reason (uncaught-exception-reason e)))
               (and (error-object? reason)
                    (msg-contains? (error-object-message reason)
                                   "continuation belongs to another OS thread"))))
            (#t #f))
    (thread-join! t2)
    #f))

;; Control: a continuation captured AND invoked on the same thread (so the
;; invocation returns to its caller) still works. A plain `(saved-k ...)`
;; here would re-enter the TOP-LEVEL capture point and never return to this
;; assertion — the control must be self-contained.
(test-equal "control: same-thread invocation still returns to its caller"
  'from-child
  (let ((local-k #f))
    (let ((value (call/cc (lambda (k) (set! local-k k) 'captured))))
      (if (eq? value 'captured)
          (local-k 'from-child)
          value))))

;; Control: a continuation captured on a CHILD and returned through the join
;; is refused by the copy at the boundary -- the join raises the uncopyable
;; result error, not a value outside the lattice.
(define t3 (make-thread (lambda ()
                          (call/cc (lambda (k) k)))))
(thread-start! t3)
(test-assert "control: a child's continuation cannot cross back through join (uncopyable)"
  (guard (e ((and (error-object? e)
                  (msg-contains? (error-object-message e) "uncopyable"))
             #t)
            (#t #f))
    (thread-join! t3)
    #f))

(let ((runner (test-runner-current)))
  (test-end "cross-thread-continuation-invoke-1936")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
