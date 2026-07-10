;; SRFI-117 (mutable queues / list queues) conformance tests — Phase 3b
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi117.scm

(import (scheme base) (srfi 117) (scheme process-context) (srfi 64))

(test-begin "srfi-117")

;;; --- construction and basic state ---
(test-equal #t (list-queue? (list-queue)))
(test-equal #t (list-queue-empty? (list-queue)))
(test-equal #f (list-queue-empty? (list-queue 1)))
(test-equal '(1 2 3) (list-queue-list (list-queue 1 2 3)))
(test-equal '(1 2) (list-queue-list (make-list-queue (list 1 2))))

;;; --- front / back ---
(let ((q (list-queue 1 2 3)))
  (test-equal 1 (list-queue-front q))
  (test-equal 3 (list-queue-back q)))

;;; --- adding ---
(let ((q (list-queue 2)))
  (list-queue-add-front! q 1)
  (list-queue-add-back! q 3)
  (test-equal '(1 2 3) (list-queue-list q))
  (test-equal 1 (list-queue-front q))
  (test-equal 3 (list-queue-back q)))

;; FIFO behavior from empty
(let ((q (list-queue)))
  (list-queue-add-back! q 'a)
  (list-queue-add-back! q 'b)
  (list-queue-add-back! q 'c)
  (test-equal 'a (list-queue-remove-front! q))
  (test-equal 'b (list-queue-remove-front! q))
  (test-equal '(c) (list-queue-list q)))

;;; --- removing from both ends ---
(let ((q (list-queue 1 2 3)))
  (test-equal 1 (list-queue-remove-front! q))
  (test-equal 3 (list-queue-remove-back! q))
  (test-equal '(2) (list-queue-list q))
  (test-equal 2 (list-queue-remove-front! q))
  (test-equal #t (list-queue-empty? q)))

;; removing from an empty queue raises
(test-equal #t (guard (e (#t #t)) (list-queue-remove-front! (list-queue)) #f))
(test-equal #t (guard (e (#t #t)) (list-queue-remove-back! (list-queue)) #f))

;;; --- append / concatenate ---
(test-equal '(1 2 3 4)
            (list-queue-list (list-queue-append (list-queue 1 2) (list-queue 3 4))))
(test-equal '(1 2 3)
            (list-queue-list (list-queue-concatenate
                              (list (list-queue 1) (list-queue 2) (list-queue 3)))))

;;; --- map / for-each ---
(test-equal '(2 4 6)
            (list-queue-list (list-queue-map (lambda (x) (* 2 x)) (list-queue 1 2 3))))
(test-equal '(1 2 3)
            (let ((acc '()))
              (list-queue-for-each (lambda (x) (set! acc (cons x acc))) (list-queue 1 2 3))
              (reverse acc)))

;;; --- first-last returns both views ---
(call-with-values
    (lambda () (list-queue-first-last (list-queue 1 2 3)))
  (lambda (first last)
    (test-equal 1 (car first))
    (test-equal 3 (car last))))

(let ((runner (test-runner-current)))
  (test-end "srfi-117")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
