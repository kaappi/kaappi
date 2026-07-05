;; SRFI-41 (streams) conformance tests — audit Phase 3c
;; 15 derived-library exports are missing (#1210); tests cover what exists.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi41.scm

(import (scheme base) (srfi 41) (chibi test))

(test-begin "srfi-41")

;;; --- primitives ---
(test #t (stream-null? stream-null))
(test #t (stream? stream-null))
(test #f (stream-pair? stream-null))

(define s12 (stream-cons 1 (stream-cons 2 stream-null)))
(test #t (stream-pair? s12))
(test #t (stream? s12))
(test #f (stream-null? s12))
(test 1 (stream-car s12))
(test 2 (stream-car (stream-cdr s12)))
(test #t (stream-null? (stream-cdr (stream-cdr s12))))

;; stream-cons delays its element and tail
(define evaluated #f)
(define lazy-s (stream-cons (begin (set! evaluated #t) 'v) stream-null))
(test #f evaluated)
(test 'v (stream-car lazy-s))
(test #t evaluated)

;;; --- construction helpers ---
(test '(1 2 3) (stream->list (stream 1 2 3)))
(test '(1 2 3) (stream->list (list->stream '(1 2 3))))
(test '() (stream->list (stream)))

;;; --- infinite streams stay lazy ---
(define (ints n) (stream-cons n (ints (+ n 1))))
(define nat (ints 0))
(test '(0 1 2 3 4) (stream->list (stream-take 5 nat)))
(test 7 (stream-ref nat 7))
(test '(0 2 4) (stream->list (stream-take 3 (stream-filter even? nat))))
(test '(0 10 20) (stream->list (stream-take 3 (stream-map (lambda (x) (* 10 x)) nat))))
(test '(5 6) (stream->list (stream-take 2 (stream-drop 5 nat))))

;;; --- finite stream operations ---
(test 3 (stream-length (stream 1 2 3)))
(test 6 (stream-fold + 0 (stream 1 2 3)))
;; FAIL: #1215 (stream-append drops everything after the first stream)
;; (test '(1 2 3 4) (stream->list (stream-append (stream 1 2) (stream 3 4))))
;; FAIL: #1215 (stream-zip errors instead of stopping at the shortest stream)
;; (test '((1 a) (2 b)) (stream->list (stream-zip (stream 1 2) (stream 'a 'b 'c))))
(test '(a b c)
      (let ((acc '()))
        (stream-for-each (lambda (x) (set! acc (cons x acc))) (stream 'a 'b 'c))
        (reverse acc)))

;; stream-unfold: (stream-unfold map pred? gen base)
;; FAIL: #1215 (stream-unfold predicate sense inverted)
;; (test '(0 1 4 9)
;;       (stream->list (stream-unfold
;;                      (lambda (x) (* x x))
;;                      (lambda (x) (< x 4))
;;                      (lambda (x) (+ x 1))
;;                      0)))

;; stream-lambda
(define double-all
  (stream-lambda (s)
    (if (stream-null? s)
        stream-null
        (stream-cons (* 2 (stream-car s)) (double-all (stream-cdr s))))))
(test '(2 4 6) (stream->list (double-all (stream 1 2 3))))

;;; --- missing derived exports (#1210) ---
;; FAIL: #1210 (define-stream, stream-range, stream-from, stream-let,
;;              stream-match, stream-of, stream-iterate, stream-scan,
;;              stream-reverse, stream-concat, ... not exported)
;; (test '(0 1 2) (stream->list (stream-range 0 3)))
;; (test '(3 2 1) (stream->list (stream-reverse (stream 1 2 3))))
;; (test '(1 2 4) (stream->list (stream-take 3 (stream-iterate (lambda (x) (* 2 x)) 1))))

(test-end "srfi-41")
