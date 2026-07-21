;; SRFI-255 (Restarting Conditions) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi255.scm
;;
;; See lib/srfi/255.sld for how this adapts an R6RS-condition-shaped SRFI
;; onto Kaappi's plain R7RS conditions.

(import (scheme base) (scheme process-context) (srfi 255) (srfi 64))

(test-begin "srfi-255")

;;; --- make-restarter / accessors / restart ---
(define r1 (make-restarter 'my-tag "a description" 'my-who '(x y)
                            (lambda (x y) (+ x y))))

(test-assert "restarter?: true for a restarter" (restarter? r1))
(test-assert "restarter?: false for other values" (not (restarter? 42)))
(test-equal "restarter-tag" 'my-tag (restarter-tag r1))
(test-equal "restarter-description" "a description" (restarter-description r1))
(test-equal "restarter-who" 'my-who (restarter-who r1))
(test-equal "restarter-formals" '(x y) (restarter-formals r1))
(test-equal "restart: invokes the invoker" 7 (restart r1 3 4))

;;; --- restarter-guard: normal path (no exception) never builds restarters ---
(define (safe-/ a b)
  (restarter-guard safe-/
    (con ((return-value v) "Return a specific value." #t v)
         ((return-zero) "Return zero." #t 0))
    (if (= b 0) (error "division by zero" a b) (/ a b))))

(test-equal "restarter-guard: normal path" 5 (safe-/ 10 2))

;;; --- restarter-guard + with-current-interactor: pick a restart by tag ---
(define (find-restarter tag rs)
  (cond ((null? rs) (error "no such restarter" tag))
        ((eq? (restarter-tag (car rs)) tag) (car rs))
        (else (find-restarter tag (cdr rs)))))

(test-equal "interactor: picks return-zero restart"
  0
  (with-current-interactor
    (lambda ()
      (parameterize
          ((current-interactor
            (lambda (con)
              (restart (find-restarter 'return-zero (restartable-condition-restarters con))))))
        (safe-/ 10 0)))))

(test-equal "interactor: picks return-value restart with an argument"
  42
  (with-current-interactor
    (lambda ()
      (parameterize
          ((current-interactor
            (lambda (con)
              (restart (find-restarter 'return-value (restartable-condition-restarters con)) 42))))
        (safe-/ 10 0)))))

;;; --- restarter-guard: condition-var is bound inside restart bodies ---
(define (safe-/2 a b)
  (restarter-guard safe-/2
    (con ((show-message) "Return the error message." #t (error-object-message con)))
    (if (= b 0) (error "boom" a b) (/ a b))))

(test-equal "condition-var: accessible from a restart body"
  "boom"
  (with-current-interactor
    (lambda ()
      (parameterize
          ((current-interactor
            (lambda (con) (restart (car (restartable-condition-restarters con))))))
        (safe-/2 10 0)))))

;;; --- restarter-guard: predicate filters which restarts are offered ---
(define (checked a)
  (restarter-guard checked
    (((only-if-negative) "Offered only for negative input." (< a 0) 'was-negative))
    (if (< a 0) (error "negative" a) a)))

(test-equal "predicate: restarter offered when predicate is true"
  'was-negative
  (with-current-interactor
    (lambda ()
      (parameterize
          ((current-interactor
            (lambda (con) (restart (car (restartable-condition-restarters con))))))
        (checked -5)))))

;;; --- restarter-guard caught directly via guard, no interactor needed ---
(test-equal "direct guard catch + restart"
  99
  (guard (con ((restartable-condition? con)
               (restart (find-restarter 'return-value (restartable-condition-restarters con)) 99)))
    (safe-/ 10 0)))

;;; --- restartable / define-restartable ---
(define-restartable (checked-sqrt x)
  (if (< x 0) (error "negative input" x) (* x x)))

(test-equal "define-restartable: normal path" 81 (checked-sqrt 9))

(test-equal "define-restartable: retry with new arguments via interactor"
  81
  (with-current-interactor
    (lambda ()
      (parameterize
          ((current-interactor
            (lambda (con) (restart (car (restartable-condition-restarters con)) 9))))
        (checked-sqrt -1)))))

(define add-restartable (restartable my-adder (lambda (a b) (+ a b))))
(test-equal "restartable: wraps a plain lambda" 7 (add-restartable 3 4))

;;; --- with-current-interactor passes through non-restartable conditions ---
(test-equal "with-current-interactor: non-restartable conditions propagate"
  'caught
  (guard (e (#t 'caught))
    (with-current-interactor (lambda () (error "plain error, no restarter")))))

(let ((runner (test-runner-current)))
  (test-end "srfi-255")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
