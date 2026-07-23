;; SRFI-173 (Hooks) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi173.scm

(import (scheme base) (scheme process-context) (srfi 173) (srfi 64))

(test-begin "srfi-173")

;;; --- construction and predicate ---
(test-assert "make-hook returns a hook" (hook? (make-hook 2)))
(test-assert "non-hook is not a hook" (not (hook? 42)))
(test-equal "make-hook starts with no procedures" '() (hook->list (make-hook 2)))

;;; --- hook-add!: single procedure invoked by hook-run ---
(let* ((h (make-hook 1))
       (result '()))
  (hook-add! h (lambda (x) (set! result (cons x result))))
  (hook-run h 5)
  (test-equal "hook-add!: single procedure invoked with correct argument"
    '(5) result))

;;; --- hook-add!: multiple procedures, all invoked (order unspecified) ---
(let* ((h (make-hook 1))
       (result '()))
  (hook-add! h (lambda (x) (set! result (cons (list 'a x) result))))
  (hook-add! h (lambda (x) (set! result (cons (list 'b x) result))))
  (hook-run h 9)
  (test-equal "hook-add!: both procedures invoked" 2 (length result))
  (test-assert "hook-add!: first procedure ran" (member '(a 9) result))
  (test-assert "hook-add!: second procedure ran" (member '(b 9) result)))

;;; --- hook-run: arguments delivered correctly (arity 2) ---
(let ((h (make-hook 2))
      (result #f))
  (hook-add! h (lambda (a b) (set! result (+ a b))))
  (hook-run h 3 4)
  (test-equal "hook-run passes arguments to stored procedure" 7 result))

;;; --- hook-delete! ---
(let* ((h (make-hook 1))
       (result '())
       (proc-a (lambda (x) (set! result (cons 'a result))))
       (proc-b (lambda (x) (set! result (cons 'b result)))))
  (hook-add! h proc-a)
  (hook-add! h proc-b)
  (hook-delete! h proc-a)
  (hook-run h 1)
  (test-equal "hook-delete!: removed procedure is not invoked" '(b) result)
  (test-equal "hook-delete!: hook->list reflects removal" (list proc-b)
    (hook->list h)))

;;; --- hook-reset! ---
(let* ((h (make-hook 0))
       (calls 0))
  (hook-add! h (lambda () (set! calls (+ calls 1))))
  (hook-add! h (lambda () (set! calls (+ calls 1))))
  (hook-reset! h)
  (test-equal "hook-reset!: clears the procedure list" '() (hook->list h))
  (hook-run h)
  (test-equal "hook-reset!: no procedures invoked after reset" 0 calls))

;;; --- list->hook ---
(let* ((result '())
       (proc-a (lambda (x) (set! result (cons 'a result))))
       (proc-b (lambda (x) (set! result (cons 'b result))))
       (h (list->hook 1 (list proc-a proc-b))))
  (test-equal "list->hook: initial procedure count" 2 (length (hook->list h)))
  (hook-run h 1)
  (test-equal "list->hook: both initial procedures invoked" 2 (length result))
  (test-assert "list->hook: proc-a present" (memq proc-a (hook->list h)))
  (test-assert "list->hook: proc-b present" (memq proc-b (hook->list h))))

;;; --- list->hook! ---
(let* ((h (make-hook 1))
       (result '())
       (proc-c (lambda (x) (set! result (cons 'c result)))))
  (hook-add! h (lambda (x) (set! result (cons 'should-not-run result))))
  (list->hook! h (list proc-c))
  (test-equal "list->hook!: replaces the procedure list" (list proc-c)
    (hook->list h))
  (hook-run h 1)
  (test-equal "list->hook!: only the new procedure runs" '(c) result))

;;; --- hook-run: arity mismatch is an error ---
(test-assert "hook-run: raises an error when argument count mismatches arity"
  (guard (e (#t #t))
    (hook-run (make-hook 2) 1)
    #f))

(let ((runner (test-runner-current)))
  (test-end "srfi-173")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
