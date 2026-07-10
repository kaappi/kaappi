;; Audit tests for src/primitives_control.zig — exceptions, call/cc,
;; dynamic-wind, values. Audit campaign Phase 2.7 (#1137).
;; Procedure-level correctness; deep continuation interactions
;; (call/cc + guard + parameterize) are Phase 4B's unit.
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme write))
(import (scheme process-context) (srfi 64))

(test-begin "primitives_control audit")

;;; --- values / call-with-values ---
(test-equal 0 (call-with-values (lambda () (values)) (lambda args (length args))))
(test-equal 42 (+ 1 (values 41)))
(test-equal '(1 2 3) (call-with-values (lambda () (values 1 2 3)) list))
(test-equal -1 (call-with-values * -))

;;; --- raise / raise-continuable / with-exception-handler ---
(test-equal 101 (with-exception-handler (lambda (c) 100)
                  (lambda () (+ 1 (raise-continuable 'k)))))
;; handler returning from plain raise triggers a secondary exception
(test-equal 'secondary-raised
  (guard (outer (#t 'secondary-raised))
    (with-exception-handler (lambda (c) 'ignored)
      (lambda () (raise 'first) 'not-reached))))
;; handler runs with the OUTER handler installed
(test-equal '(outer-saw from-handler)
  (guard (e (#t (list 'outer-saw e)))
    (with-exception-handler (lambda (c) (raise 'from-handler))
      (lambda () (raise 'inner)))))
;; raise of a non-error object arrives unchanged
(test-equal '(#f sym) (guard (e (#t (list (error-object? e) e))) (raise 'sym)))

;;; --- error objects ---
(test-equal '(#t "m" (1 2))
  (guard (e (#t (list (error-object? e)
                      (error-object-message e)
                      (error-object-irritants e))))
    (error "m" 1 2)))
(test-equal '() (guard (e (#t (error-object-irritants e))) (error "m")))
(test-equal #f (error-object? 42))
(test-equal #f (guard (e (#t (file-error? e))) (error "x")))
(test-equal #f (guard (e (#t (read-error? e))) (error "x")))
(test-equal #t (guard (e (#t #t)) (error-object-message 42)))

;;; --- call/cc ---
(test-equal 42 (call/cc (lambda (k) (+ 1 (k 42)))))
(test-equal 7 (call/cc (lambda (k) 7)))
(test-equal 42 (call-with-current-continuation (lambda (k) (k 42))))
(test-equal '(1 2) (call-with-values
                     (lambda () (call/cc (lambda (k) (k 1 2))))
                     list))
(test-equal 3 (let ((n 0) (k* #f))
                (call/cc (lambda (k) (set! k* k)))
                (set! n (+ n 1))
                (if (< n 3) (k* #f))
                n))
;; re-entry with heap-cell and closure-captured counters works (contrast #1168)
(test-equal 3 (let ((n (vector 0)) (k* #f))
                (call/cc (lambda (k) (set! k* k)))
                (vector-set! n 0 (+ (vector-ref n 0) 1))
                (if (< (vector-ref n 0) 3) (k* #f))
                (vector-ref n 0)))
(test-equal 3 (let ((n 0) (k* #f))
                (define (read-n) n)
                (call/cc (lambda (k) (set! k* k)))
                (set! n (+ n 1))
                (if (< (read-n) 3) (k* #f))
                n))

;;; --- call/ec ---
(test-equal 42 (call/ec (lambda (k) (+ 1 (k 42)))))
(test-equal 7 (call-with-escape-continuation (lambda (k) 7)))

;;; --- dynamic-wind ---
(test-equal '(in body out)
  (let ((acc '()))
    (dynamic-wind (lambda () (set! acc (cons 'in acc)))
                  (lambda () (set! acc (cons 'body acc)) 'r)
                  (lambda () (set! acc (cons 'out acc))))
    (reverse acc)))
(test-equal 'val (dynamic-wind (lambda () 1) (lambda () 'val) (lambda () 2)))
(test-equal '(a b) (call-with-values
                     (lambda () (dynamic-wind (lambda () 1)
                                              (lambda () (values 'a 'b))
                                              (lambda () 2)))
                     list))
;; after-thunk runs when the body escapes
(test-equal '(in out)
  (let ((acc '()))
    (call/cc (lambda (k)
      (dynamic-wind (lambda () (set! acc (cons 'in acc)))
                    (lambda () (k 'escaped))
                    (lambda () (set! acc (cons 'out acc))))))
    (reverse acc)))
;; R7RS 6.10 spec example: re-entry re-runs before-thunk
(test-equal '(connect talk1 disconnect connect talk2 disconnect)
  (let ((path '()) (c #f))
    (let ((add (lambda (s) (set! path (cons s path)))))
      (dynamic-wind
        (lambda () (add 'connect))
        (lambda () (add (call/cc (lambda (c0) (set! c c0) 'talk1))))
        (lambda () (add 'disconnect)))
      (if (< (length path) 4)
          (c 'talk2)
          (reverse path)))))
;; errors in before-thunk propagate; after-thunk runs when body raises
(test-equal 'caught (guard (e (#t 'caught))
  (dynamic-wind (lambda () (error "in-before")) (lambda () 'body) (lambda () 'after))))
(test-equal #t (let ((ran #f))
                 (guard (e (#t ran))
                   (dynamic-wind (lambda () 1)
                                 (lambda () (error "boom"))
                                 (lambda () (set! ran #t))))))

;;; --- type errors are catchable ---
(test-equal #t (guard (e (#t #t)) (call/cc 42)))
(test-equal #t (guard (e (#t #t)) (dynamic-wind 1 2 3)))
(test-equal #t (guard (e (#t #t)) (call-with-values 42 list)))
(test-equal #t (guard (e (#t #t)) (with-exception-handler 42 (lambda () 1))))
(test-equal #t (guard (e (#t #t)) (call/ec "k")))

(let ((runner (test-runner-current)))
  (test-end "primitives_control audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
