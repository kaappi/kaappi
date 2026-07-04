;; Regression test for #1093: map's callWithArgs result was unrooted
;; before the subsequent allocPair, allowing GC to collect it.
;; This caused SRFI-115 regexp compiled structures to be corrupted
;; when GC timing aligned (observed as "unknown tag 0.0" or
;; "type error in 'car': expected pair, got #<procedure>").

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 64) (srfi 115))

(test-begin "map-gc-root-1093")

;; Exercise map with a callback that allocates, creating GC pressure.
(test-equal "map result survives GC"
  '((a . 1) (b . 2) (c . 3))
  (map (lambda (x y) (cons x y)) '(a b c) '(1 2 3)))

;; Longer list to increase chance of GC firing mid-map
(let ((xs (map (lambda (n) (cons n (make-string 100 #\x)))
              '(1 2 3 4 5 6 7 8 9 10))))
  (test-equal "map 10 elements" 10 (length xs))
  (test-equal "map element intact" 1 (car (car xs))))

;; SRFI-115 regexp-replace-all — the original failing case.
(test-equal "regexp-replace-all #1093"
  "f00 b00"
  (regexp-replace-all "o" "foo boo" "0"))

;; Run multiple times to exercise different GC timings
(let loop ((i 0))
  (when (< i 50)
    (test-equal (string-append "regexp-replace-all iter " (number->string i))
      "f00 b00 m00"
      (regexp-replace-all "o" "foo boo moo" "0"))
    (loop (+ i 1))))

;; fold with a callback that allocates — exercises the acc rooting fix
(test-equal "fold cons"
  '(3 2 1)
  (fold cons '() '(1 2 3)))

(test-equal "fold allocating callback"
  '((3 . "x") (2 . "x") (1 . "x"))
  (fold (lambda (x acc) (cons (cons x "x") acc)) '() '(1 2 3)))

(let ((runner (test-runner-current)))
  (test-end "map-gc-root-1093")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
