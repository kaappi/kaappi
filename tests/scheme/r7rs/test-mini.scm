; Minimal test to verify the (chibi test) library works

; Inline test framework — don't rely on .sld loading for now
(define test-pass-count 0)
(define test-fail-count 0)

(define (test-begin name)
  (display "== ")
  (display name)
  (display " ==")
  (newline))

(define (test-end . args)
  (display "  ")
  (display test-pass-count)
  (display " pass, ")
  (display test-fail-count)
  (display " fail")
  (newline))

(define (run-test expected actual)
  (if (equal? expected actual)
      (set! test-pass-count (+ test-pass-count 1))
      (begin
        (set! test-fail-count (+ test-fail-count 1))
        (display "FAIL: expected ")
        (write expected)
        (display " got ")
        (write actual)
        (newline))))

; Sample tests from the chibi suite
(test-begin "Basic")

(run-test 8 (+ 3 5))
(run-test 6 (* 2 3))
(run-test #t (= 1 1))
(run-test #f (= 1 2))
(run-test '(a b c) (list 'a 'b 'c))
(run-test 3 (length '(a b c)))
(run-test '(1 2 3) (map + '(1 2 3)))
(run-test 7 (apply + '(3 4)))
(run-test "hello" (string-append "hel" "lo"))
(run-test #\a (string-ref "abc" 0))
(run-test 3 (vector-length #(1 2 3)))
(run-test 'b (vector-ref #(a b c) 1))

(test-end)
