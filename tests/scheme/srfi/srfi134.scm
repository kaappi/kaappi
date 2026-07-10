;; SRFI-134 (immutable deques) conformance tests — audit Phase 3b
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi134.scm

(import (scheme base) (srfi 134) (scheme process-context) (srfi 64))

(test-begin "srfi-134")

;;; --- construction ---
(test-equal #t (ideque? (ideque)))
(test-equal #t (ideque-empty? (ideque)))
(test-equal #f (ideque-empty? (ideque 1)))
(test-equal '(1 2 3) (ideque->list (ideque 1 2 3)))
(test-equal '(1 2 3) (ideque->list (list->ideque '(1 2 3))))
(test-equal 3 (ideque-length (ideque 1 2 3)))
(test-equal 0 (ideque-length (ideque)))

;;; --- front / back ---
(let ((d (ideque 1 2 3)))
  (test-equal 1 (ideque-front d))
  (test-equal 3 (ideque-back d)))

;;; --- persistence: add/remove return new deques, original unchanged ---
(let* ((d (ideque 2))
       (d2 (ideque-add-front d 1))
       (d3 (ideque-add-back d2 3)))
  (test-equal '(2) (ideque->list d))
  (test-equal '(1 2) (ideque->list d2))
  (test-equal '(1 2 3) (ideque->list d3)))

(let* ((d (ideque 1 2 3))
       (df (ideque-remove-front d))
       (db (ideque-remove-back d)))
  (test-equal '(1 2 3) (ideque->list d))
  (test-equal '(2 3) (ideque->list df))
  (test-equal '(1 2) (ideque->list db)))

;; alternating operations across both ends
(let loop ((d (ideque)) (i 0))
  (if (< i 4)
      (loop (ideque-add-back (ideque-add-front d i) (* 10 i)) (+ i 1))
      (test-equal '(3 2 1 0 0 10 20 30) (ideque->list d))))

;; removing from an empty deque raises
(test-equal #t (guard (e (#t #t)) (ideque-remove-front (ideque)) #f))
(test-equal #t (guard (e (#t #t)) (ideque-remove-back (ideque)) #f))

;;; --- higher-order operations ---
(test-equal '(2 4 6) (ideque->list (ideque-map (lambda (x) (* 2 x)) (ideque 1 2 3))))
(test-equal 6 (ideque-fold + 0 (ideque 1 2 3)))
(test-equal '(2) (ideque->list (ideque-filter even? (ideque 1 2 3))))
(test-equal '(1 2 3 4) (ideque->list (ideque-append (ideque 1 2) (ideque 3 4))))
(test-equal '(1 2 3)
            (let ((acc '()))
              (ideque-for-each (lambda (x) (set! acc (cons x acc))) (ideque 1 2 3))
              (reverse acc)))

;;; --- indexing and predicates over elements ---
(test-equal 'b (ideque-ref (ideque 'a 'b 'c) 1))
(test-equal #t (ideque-any even? (ideque 1 2 3)))
(test-equal #f (ideque-any even? (ideque 1 3 5)))
(test-equal #t (ideque-every odd? (ideque 1 3 5)))
(test-equal #f (ideque-every odd? (ideque 1 2 5)))

(let ((runner (test-runner-current)))
  (test-end "srfi-134")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
