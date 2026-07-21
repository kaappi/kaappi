;; SRFI-190 (Coroutine Generators) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi190.scm

(import (scheme base) (srfi 158) (srfi 190) (srfi 64))

(test-begin "srfi-190")

;;; --- coroutine-generator ---
(test-equal "coroutine-generator: basic"
  '(0 1 2)
  (generator->list
    (coroutine-generator
      (do ((i 0 (+ i 1)))
          ((= i 3))
        (yield i)))))

(test-equal "coroutine-generator: empty"
  '()
  (generator->list (coroutine-generator (values))))

(test-equal "coroutine-generator: single value"
  '(42)
  (generator->list (coroutine-generator (yield 42))))

(test-equal "coroutine-generator: strings"
  '("a" "b" "c")
  (generator->list
    (coroutine-generator
      (for-each yield '("a" "b" "c")))))

;;; --- define-coroutine-generator ---
(define-coroutine-generator (counting n)
  (do ((i 0 (+ i 1)))
      ((= i n))
    (yield i)))

(test-equal "define-coroutine-generator: with args"
  '(0 1 2 3 4)
  (generator->list (counting 5)))

(test-equal "define-coroutine-generator: zero"
  '()
  (generator->list (counting 0)))

(define-coroutine-generator (fibonacci-gen n)
  (let loop ((a 0) (b 1) (count 0))
    (when (< count n)
      (yield a)
      (loop b (+ a b) (+ count 1)))))

(test-equal "define-coroutine-generator: fibonacci"
  '(0 1 1 2 3 5 8)
  (generator->list (fibonacci-gen 7)))

;;; --- yield returns value from send ---
(test-equal "coroutine-generator: multiple yields"
  '(1 2 3 4 5)
  (generator->list
    (coroutine-generator
      (yield 1) (yield 2) (yield 3) (yield 4) (yield 5))))

(let ((runner (test-runner-current)))
  (test-end "srfi-190")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
