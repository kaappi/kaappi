;; SRFI-41 (streams) conformance tests
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi41.scm

(import (scheme base) (scheme write) (scheme process-context) (srfi 41) (srfi 64))

(test-begin "srfi-41")

;;; --- primitives ---
(test-assert "stream-null is stream-null?" (stream-null? stream-null))
(test-assert "stream-null is stream?" (stream? stream-null))
(test-assert "stream-null is not stream-pair?" (not (stream-pair? stream-null)))

(define s12 (stream-cons 1 (stream-cons 2 stream-null)))
(test-assert "stream-cons produces stream-pair?" (stream-pair? s12))
(test-assert "stream-cons produces stream?" (stream? s12))
(test-assert "stream-cons is not stream-null?" (not (stream-null? s12)))
(test-equal "stream-car" 1 (stream-car s12))
(test-equal "stream-car of cdr" 2 (stream-car (stream-cdr s12)))
(test-assert "stream-cdr of cdr is null" (stream-null? (stream-cdr (stream-cdr s12))))

;; stream-cons delays its element and tail
(define evaluated #f)
(define lazy-s (stream-cons (begin (set! evaluated #t) 'v) stream-null))
(test-assert "stream-cons delays element" (not evaluated))
(test-equal "stream-car forces element" 'v (stream-car lazy-s))
(test-assert "element now evaluated" evaluated)

;;; --- construction helpers ---
(test-equal "stream" '(1 2 3) (stream->list (stream 1 2 3)))
(test-equal "list->stream" '(1 2 3) (stream->list (list->stream '(1 2 3))))
(test-equal "empty stream" '() (stream->list (stream)))

;;; --- infinite streams stay lazy ---
(define (ints n) (stream-cons n (ints (+ n 1))))
(define nat (ints 0))
(test-equal "stream-take" '(0 1 2 3 4) (stream->list (stream-take 5 nat)))
(test-equal "stream-ref" 7 (stream-ref nat 7))
(test-equal "stream-filter" '(0 2 4)
  (stream->list (stream-take 3 (stream-filter even? nat))))
(test-equal "stream-map" '(0 10 20)
  (stream->list (stream-take 3 (stream-map (lambda (x) (* 10 x)) nat))))
(test-equal "stream-drop" '(5 6) (stream->list (stream-take 2 (stream-drop 5 nat))))

;;; --- finite stream operations ---
(test-equal "stream-length" 3 (stream-length (stream 1 2 3)))
(test-equal "stream-fold" 6 (stream-fold + 0 (stream 1 2 3)))
(test-equal "stream-append" '(1 2 3 4)
  (stream->list (stream-append (stream 1 2) (stream 3 4))))
(test-equal "stream-zip" '((1 a) (2 b))
  (stream->list (stream-zip (stream 1 2) (stream 'a 'b 'c))))
(test-equal "stream-for-each" '(a b c)
  (let ((acc '()))
    (stream-for-each (lambda (x) (set! acc (cons x acc))) (stream 'a 'b 'c))
    (reverse acc)))

;; stream-unfold: (stream-unfold map pred? gen base)
(test-equal "stream-unfold" '(0 1 4 9)
  (stream->list (stream-unfold
                  (lambda (x) (* x x))
                  (lambda (x) (< x 4))
                  (lambda (x) (+ x 1))
                  0)))

;; stream-lambda
(define double-all
  (stream-lambda (s)
    (if (stream-null? s) stream-null
        (stream-cons (* 2 (stream-car s)) (double-all (stream-cdr s))))))
(test-equal "stream-lambda" '(2 4 6) (stream->list (double-all (stream 1 2 3))))

;;; ======= derived library (#1210) =======

;;; --- define-stream ---
(define-stream (nats-from n) (stream-cons n (nats-from (+ n 1))))
(test-equal "define-stream" '(0 1 2 3 4)
  (stream->list (stream-take 5 (nats-from 0))))

;;; --- stream-let ---
(test-equal "stream-let" '(0 1 2 3 4)
  (stream->list (stream-let loop ((n 0))
    (if (= n 5) stream-null (stream-cons n (loop (+ n 1)))))))

;;; --- stream-from ---
(test-equal "stream-from default step" '(10 11 12 13 14)
  (stream->list (stream-take 5 (stream-from 10))))
(test-equal "stream-from step 3" '(0 3 6 9)
  (stream->list (stream-take 4 (stream-from 0 3))))
(test-equal "stream-from negative step" '(10 8 6)
  (stream->list (stream-take 3 (stream-from 10 -2))))

;;; --- stream-range ---
(test-equal "stream-range ascending" '(0 1 2 3 4) (stream->list (stream-range 0 5)))
(test-equal "stream-range descending" '(5 4 3 2 1) (stream->list (stream-range 5 0)))
(test-equal "stream-range step 2" '(0 2 4) (stream->list (stream-range 0 5 2)))
(test-equal "stream-range step -1" '(3 2 1) (stream->list (stream-range 3 0 -1)))
(test-equal "stream-range empty" '() (stream->list (stream-range 5 5)))
(test-equal "stream-range single" '(0) (stream->list (stream-range 0 1)))

;;; --- stream-iterate ---
(test-equal "stream-iterate" '(1 2 4 8 16)
  (stream->list (stream-take 5 (stream-iterate (lambda (x) (* 2 x)) 1))))
(test-equal "stream-iterate add1" '(0 1 2 3)
  (stream->list (stream-take 4 (stream-iterate (lambda (x) (+ x 1)) 0))))

;;; --- stream-constant ---
(test-equal "stream-constant single" '(7 7 7 7)
  (stream->list (stream-take 4 (stream-constant 7))))
(test-equal "stream-constant cycling" '(1 2 3 1 2 3 1)
  (stream->list (stream-take 7 (stream-constant 1 2 3))))
(test-equal "stream-constant two" '(a b a b a)
  (stream->list (stream-take 5 (stream-constant 'a 'b))))

;;; --- stream-take-while ---
(test-equal "stream-take-while" '(0 1 2 3 4)
  (stream->list (stream-take-while (lambda (x) (< x 5)) (stream-from 0))))
(test-equal "stream-take-while none" '()
  (stream->list (stream-take-while (lambda (x) (< x 0)) (stream-from 0))))
(test-equal "stream-take-while all (finite)" '(1 2 3)
  (stream->list (stream-take-while (lambda (x) (< x 10)) (stream 1 2 3))))

;;; --- stream-drop-while ---
(test-equal "stream-drop-while" '(5 6 7)
  (stream->list (stream-take 3 (stream-drop-while (lambda (x) (< x 5)) (stream-from 0)))))
(test-equal "stream-drop-while none" '(0 1)
  (stream->list (stream-take 2 (stream-drop-while (lambda (x) (< x 0)) (stream-from 0)))))
(test-equal "stream-drop-while all (finite)" '()
  (stream->list (stream-drop-while (lambda (x) (< x 10)) (stream 1 2 3))))

;;; --- stream-scan ---
(test-equal "stream-scan running sum" '(0 1 3 6)
  (stream->list (stream-scan + 0 (stream 1 2 3))))
(test-equal "stream-scan empty" '(0)
  (stream->list (stream-scan + 0 (stream))))
(test-equal "stream-scan multiplication" '(1 2 6 24)
  (stream->list (stream-scan * 1 (stream 2 3 4))))

;;; --- stream-reverse ---
(test-equal "stream-reverse" '(3 2 1) (stream->list (stream-reverse (stream 1 2 3))))
(test-equal "stream-reverse single" '(1) (stream->list (stream-reverse (stream 1))))
(test-equal "stream-reverse empty" '() (stream->list (stream-reverse (stream))))

;;; --- stream-concat ---
(test-equal "stream-concat" '(1 2 3 4)
  (stream->list (stream-concat (stream (stream 1 2) (stream 3 4)))))
(test-equal "stream-concat with empties" '(1 2)
  (stream->list (stream-concat (stream (stream) (stream 1 2) (stream)))))
(test-equal "stream-concat single" '(a b)
  (stream->list (stream-concat (stream (stream 'a 'b)))))
(test-equal "stream-concat empty" '()
  (stream->list (stream-concat (stream))))

;;; --- port->stream ---
(test-equal "port->stream" '(#\h #\e #\l #\l #\o)
  (stream->list (port->stream (open-input-string "hello"))))
(test-equal "port->stream empty" '()
  (stream->list (port->stream (open-input-string ""))))

;;; --- stream-unfolds ---
(test-equal "stream-unfolds" '((2 4 6 8 10) (20 40))
  (call-with-values
    (lambda ()
      (stream-unfolds
        (lambda (seed)
          (if (> seed 5)
              (values seed '() '())
              (values (+ seed 1)
                      (list (* seed 2))
                      (if (even? seed) (list (* seed 10)) #f))))
        1))
    (lambda (s1 s2)
      (list (stream->list s1) (stream->list s2)))))

;;; --- stream-match ---
(test-equal "stream-match empty" "empty"
  (stream-match stream-null (() "empty")))
(test-equal "stream-match pair" '(1 2 3)
  (stream-match (stream 1 2 3) ((a b c) (list a b c))))
(test-equal "stream-match wildcard" "wild"
  (stream-match (stream 1) (_ "wild")))
(test-equal "stream-match wildcard in pair" 2
  (stream-match (stream 1 2) ((_ b) b)))
(test-equal "stream-match rest binding" '(1 (2 3))
  (stream-match (stream 1 2 3) ((h . t) (list h (stream->list t)))))
(test-equal "stream-match multi-clause" 10
  (stream-match (stream 1) (() "empty") ((x) (* x 10))))
(test-equal "stream-match with fender" "big"
  (stream-match (stream 5) ((x) (> x 3) "big") ((x) "small")))
(test-equal "stream-match fender false" "small"
  (stream-match (stream 2) ((x) (> x 3) "big") ((x) "small")))

;;; --- stream-of ---
(test-equal "stream-of basic" '(1 4 9 16 25)
  (stream->list (stream-of (* x x) (x in (stream-range 1 6)))))
(test-equal "stream-of with filter" '(0 2 4 6 8)
  (stream->list (stream-of x (x in (stream-range 0 10)) (even? x))))
(test-equal "stream-of with is" '(11 22 33)
  (stream->list (stream-of (+ x y) (x in (stream-range 1 4)) (y is (* x 10)))))
(test-equal "stream-of nested" '((1 3) (1 4) (2 3) (2 4))
  (stream->list (stream-of (list x y)
                            (x in (stream 1 2))
                            (y in (stream 3 4)))))

;;; --- regression: #1215 stream-append with multiple streams ---
(test-equal "#1215 multi-append" '(1 2 3 4 5 6)
  (stream->list (stream-append (stream 1 2) (stream 3 4) (stream 5 6))))
(test-equal "#1215 append empty tail" '(1 2)
  (stream->list (stream-append (stream 1 2) (stream))))
(test-equal "#1215 append empty head" '(1 2)
  (stream->list (stream-append (stream) (stream 1 2))))

;;; --- regression: #1215 stream-zip edge cases ---
(test-equal "#1215 zip empty" '()
  (stream->list (stream-zip (stream) (stream 1 2))))
(test-equal "#1215 zip shorter first" '((1 10))
  (stream->list (stream-zip (stream 1) (stream 10 20))))
(test-equal "#1215 zip shorter second" '((1 10))
  (stream->list (stream-zip (stream 1 2) (stream 10))))

;;; --- regression: #1215 stream-unfold edge cases ---
(test-equal "#1215 unfold empty" '()
  (stream->list (stream-unfold values (lambda (x) #f) (lambda (x) (+ x 1)) 0)))
(test-equal "#1215 unfold single" '(0)
  (stream->list (stream-unfold values (lambda (x) (< x 1)) (lambda (x) (+ x 1)) 0)))

;;; --- regression: #1215 stream macro sibling arguments ---
(test-equal "#1215 two-streams" '((1 2) (3 4))
  (list (stream->list (stream 1 2)) (stream->list (stream 3 4))))
(test-equal "#1215 three-streams" '((a) (b) (c))
  (list (stream->list (stream 'a)) (stream->list (stream 'b)) (stream->list (stream 'c))))

(let ((runner (test-runner-current)))
  (test-end "srfi-41")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
