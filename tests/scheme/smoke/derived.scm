;;; Phase 3: Derived expression forms
(import (scheme base) (scheme process-context) (srfi 64))

(define %test-fail-count 0)
(test-begin "derived")

;; --- and ---
(test-group "and"
  (test-eqv "(and)" #t (and))
  (test-eqv "(and 1)" 1 (and 1))
  (test-eqv "(and 1 2 3)" 3 (and 1 2 3))
  (test-eqv "(and 1 #f 3)" #f (and 1 #f 3))
  (test-eqv "(and #f ...)" #f (and #f 42)))

;; --- or ---
(test-group "or"
  (test-eqv "(or)" #f (or))
  (test-eqv "(or 1)" 1 (or 1))
  (test-eqv "(or 1 2)" 1 (or 1 2))
  (test-eqv "(or #f 2)" 2 (or #f 2))
  (test-eqv "(or #f #f 3)" 3 (or #f #f 3))
  (test-eqv "(or #f #f #f)" #f (or #f #f #f)))

;; --- when ---
(test-group "when"
  (test-assert "when #t executes" (let ((x #f)) (when #t (set! x #t)) x))
  (test-assert "when #f skips" (let ((x #t)) (when #f (set! x #f)) x)))

;; --- unless ---
(test-group "unless"
  (test-assert "unless #f executes" (let ((x #f)) (unless #f (set! x #t)) x))
  (test-assert "unless #t skips" (let ((x #t)) (unless #t (set! x #f)) x)))

;; --- cond ---
(test-group "cond"
  (test-eqv "(cond (#t 1))" 1 (cond (#t 1)))
  (test-eqv "(cond (#f 1) (else 2))" 2 (cond (#f 1) (else 2)))
  (test-eqv "(cond (#f 1) (#t 2) (else 3))" 2 (cond (#f 1) (#t 2) (else 3)))
  (test-assert "(cond (#f 1)) is void" (begin (cond (#f 1)) #t))
  (test-eqv "cond multi-body" 6 (cond (#t (+ 1 1) (+ 2 2) (+ 3 3)))))

;; --- let ---
(test-group "let"
  (test-eqv "basic let" 3 (let ((x 1) (y 2)) (+ x y)))
  (test-eqv "let multi-body" 12 (let ((x 10)) (+ x 1) (+ x 2))))

;; --- let* ---
(test-group "let*"
  (test-eqv "let* sequential" 2 (let* ((x 1) (y (+ x 1))) y))
  (test-eqv "let* chained" 6 (let* ((x 1) (y (+ x 1)) (z (* y 3))) z)))

;; --- letrec ---
(test-group "letrec"
  (test-eqv "letrec factorial" 120
    (letrec ((f (lambda (n)
                 (if (= n 0) 1
                     (* n (f (- n 1)))))))
      (f 5)))
  (test-eqv "letrec mutual recursion" #t
    (letrec ((my-even? (lambda (n) (if (= n 0) #t (my-odd? (- n 1)))))
             (my-odd?  (lambda (n) (if (= n 0) #f (my-even? (- n 1))))))
      (my-even? 10))))

;; --- named let ---
(test-group "named let"
  (test-eqv "named let sum" 10
    (let loop ((i 0) (s 0))
      (if (= i 5) s
          (loop (+ i 1) (+ s i)))))
  (test-equal "named let countdown" '(5 4 3 2 1)
    (let loop ((n 5) (acc '()))
      (if (= n 0) (reverse acc)
          (loop (- n 1) (cons n acc))))))

;; --- do ---
(test-group "do"
  (test-eqv "do sum" 10
    (do ((i 0 (+ i 1))
         (s 0 (+ s i)))
        ((= i 5) s)))
  (test-assert "do void" (begin (do ((i 0 (+ i 1))) ((= i 3))) #t))
  (test-equal "do with commands" '(0 1 2 3)
    (let ((acc '()))
      (do ((i 0 (+ i 1)))
          ((= i 4) (reverse acc))
        (set! acc (cons i acc))))))

;; --- nested forms ---
(test-group "nested forms"
  (test-eqv "nested let/cond" 50
    (let ((x 5))
      (cond
        ((= x 1) 10)
        ((= x 5) 50)
        (else 0))))
  (test-eqv "let inside do" 120
    (do ((i 1 (+ i 1))
         (product 1 (let ((p (* product i))) p)))
        ((= i 6) product))))

(set! %test-fail-count (test-runner-fail-count (test-runner-current)))
(test-end "derived")
(if (> %test-fail-count 0) (exit 1))
