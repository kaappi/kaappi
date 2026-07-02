;; Regression test for #870: full continuation restore misread as escape
;; by callThunk — wind_count underflow panic when invoked inside dynamic-wind.

(define (main)
  (let ((k #f) (done (vector #f)))
    (define (deep n)
      (if (= n 0)
          (call/cc (lambda (c) (set! k c) 0))
          (+ 1 (deep (- n 1)))))
    (deep 5)
    (if (not (vector-ref done 0))
        (begin
          (vector-set! done 0 #t)
          (dynamic-wind
            (lambda () #f)
            (lambda () (k 0))
            (lambda () #f))))
    'ok))
(display (main))
(newline)
