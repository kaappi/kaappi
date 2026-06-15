;;; Lazy evaluation compliance tests (R7RS 4.2.5)

;; promise?
(display (promise? (delay 1)))  ; => #t
(newline)
(display (promise? 42))         ; => #f
(newline)

;; force / delay
(display (force (delay (+ 1 2))))  ; => 3
(newline)

;; make-promise
(display (force (make-promise 42)))  ; => 42
(newline)

;; Memoization: delay should only evaluate once
(let ((count 0))
  (let ((p (delay (begin (set! count (+ count 1)) count))))
    (display (force p))  ; => 1
    (newline)
    (display (force p))  ; => 1 (cached)
    (newline)))

;; Nested delay
(display (force (delay (force (delay 99)))))  ; => 99
(newline)
