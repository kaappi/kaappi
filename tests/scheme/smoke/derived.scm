;;; Phase 3: Derived expression forms

;; --- and ---
(display "(and) => ") (display (and)) (newline)
(display "(and 1) => ") (display (and 1)) (newline)
(display "(and 1 2 3) => ") (display (and 1 2 3)) (newline)
(display "(and 1 #f 3) => ") (display (and 1 #f 3)) (newline)
(display "(and #f (error \"not reached\")) => ") (display (and #f 42)) (newline)

;; --- or ---
(display "(or) => ") (display (or)) (newline)
(display "(or 1) => ") (display (or 1)) (newline)
(display "(or 1 2) => ") (display (or 1 2)) (newline)
(display "(or #f 2) => ") (display (or #f 2)) (newline)
(display "(or #f #f 3) => ") (display (or #f #f 3)) (newline)
(display "(or #f #f #f) => ") (display (or #f #f #f)) (newline)

;; --- when ---
(display "when #t: ")
(when #t (display "executed"))
(newline)
(display "when #f: ")
(when #f (display "should not appear"))
(newline)

;; --- unless ---
(display "unless #f: ")
(unless #f (display "executed"))
(newline)
(display "unless #t: ")
(unless #t (display "should not appear"))
(newline)

;; --- cond ---
(display "(cond (#t 1)) => ") (display (cond (#t 1))) (newline)
(display "(cond (#f 1) (else 2)) => ") (display (cond (#f 1) (else 2))) (newline)
(display "(cond (#f 1) (#t 2) (else 3)) => ") (display (cond (#f 1) (#t 2) (else 3))) (newline)
(display "(cond (#f 1)) => ") (display (cond (#f 1))) (newline)

;; cond with multiple body expressions
(define cond-result
  (cond (#t (+ 1 1) (+ 2 2) (+ 3 3))))
(display "cond multi-body => ") (display cond-result) (newline)

;; --- let ---
(display "(let ((x 1) (y 2)) (+ x y)) => ")
(display (let ((x 1) (y 2)) (+ x y))) (newline)

;; let with multiple body expressions
(display "let multi-body => ")
(display (let ((x 10)) (+ x 1) (+ x 2))) (newline)

;; --- let* ---
(display "(let* ((x 1) (y (+ x 1))) y) => ")
(display (let* ((x 1) (y (+ x 1))) y)) (newline)

(display "(let* ((x 1) (y (+ x 1)) (z (* y 3))) z) => ")
(display (let* ((x 1) (y (+ x 1)) (z (* y 3))) z)) (newline)

;; --- letrec ---
(display "letrec factorial => ")
(display
  (letrec ((f (lambda (n)
               (if (= n 0) 1
                   (* n (f (- n 1)))))))
    (f 5)))
(newline)

;; letrec with mutual recursion
(display "letrec even?/odd? => ")
(display
  (letrec ((my-even? (lambda (n) (if (= n 0) #t (my-odd? (- n 1)))))
           (my-odd?  (lambda (n) (if (= n 0) #f (my-even? (- n 1))))))
    (my-even? 10)))
(newline)

;; --- named let ---
(display "named let sum => ")
(display
  (let loop ((i 0) (s 0))
    (if (= i 5) s
        (loop (+ i 1) (+ s i)))))
(newline)

(display "named let countdown => ")
(let loop ((n 5))
  (when (> n 0)
    (display n) (display " ")
    (loop (- n 1))))
(newline)

;; --- do ---
(display "do sum => ")
(display
  (do ((i 0 (+ i 1))
       (s 0 (+ s i)))
      ((= i 5) s)))
(newline)

(display "do void => ")
(display
  (do ((i 0 (+ i 1)))
      ((= i 3))))
(newline)

(display "do with commands => ")
(do ((i 0 (+ i 1)))
    ((= i 4))
  (display i) (display " "))
(newline)

;; --- nested forms ---
(display "nested let/cond => ")
(display
  (let ((x 5))
    (cond
      ((= x 1) 10)
      ((= x 5) 50)
      (else 0))))
(newline)

(display "let inside do => ")
(display
  (do ((i 1 (+ i 1))
       (product 1 (let ((p (* product i))) p)))
      ((= i 6) product)))
(newline)

(display "All phase 3 tests complete.\n")
