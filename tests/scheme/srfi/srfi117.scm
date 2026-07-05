;; SRFI-117 (mutable queues / list queues) conformance tests — Phase 3b
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi117.scm

(import (scheme base) (srfi 117) (chibi test))

(test-begin "srfi-117")

;;; --- construction and basic state ---
(test #t (list-queue? (list-queue)))
(test #t (list-queue-empty? (list-queue)))
(test #f (list-queue-empty? (list-queue 1)))
(test '(1 2 3) (list-queue-list (list-queue 1 2 3)))
(test '(1 2) (list-queue-list (make-list-queue (list 1 2))))

;;; --- front / back ---
(let ((q (list-queue 1 2 3)))
  (test 1 (list-queue-front q))
  (test 3 (list-queue-back q)))

;;; --- adding ---
(let ((q (list-queue 2)))
  (list-queue-add-front! q 1)
  (list-queue-add-back! q 3)
  (test '(1 2 3) (list-queue-list q))
  (test 1 (list-queue-front q))
  (test 3 (list-queue-back q)))

;; FIFO behavior from empty
(let ((q (list-queue)))
  (list-queue-add-back! q 'a)
  (list-queue-add-back! q 'b)
  (list-queue-add-back! q 'c)
  (test 'a (list-queue-remove-front! q))
  (test 'b (list-queue-remove-front! q))
  (test '(c) (list-queue-list q)))

;;; --- removing from both ends ---
(let ((q (list-queue 1 2 3)))
  (test 1 (list-queue-remove-front! q))
  (test 3 (list-queue-remove-back! q))
  (test '(2) (list-queue-list q))
  (test 2 (list-queue-remove-front! q))
  (test #t (list-queue-empty? q)))

;; removing from an empty queue raises
(test #t (guard (e (#t #t)) (list-queue-remove-front! (list-queue)) #f))
(test #t (guard (e (#t #t)) (list-queue-remove-back! (list-queue)) #f))

;;; --- append / concatenate ---
(test '(1 2 3 4)
      (list-queue-list (list-queue-append (list-queue 1 2) (list-queue 3 4))))
(test '(1 2 3)
      (list-queue-list (list-queue-concatenate
                        (list (list-queue 1) (list-queue 2) (list-queue 3)))))

;;; --- map / for-each ---
(test '(2 4 6)
      (list-queue-list (list-queue-map (lambda (x) (* 2 x)) (list-queue 1 2 3))))
(test '(1 2 3)
      (let ((acc '()))
        (list-queue-for-each (lambda (x) (set! acc (cons x acc))) (list-queue 1 2 3))
        (reverse acc)))

;;; --- first-last returns both views ---
(call-with-values
    (lambda () (list-queue-first-last (list-queue 1 2 3)))
  (lambda (first last)
    (test 1 (car first))
    (test 3 (car last))))

(test-end "srfi-117")
