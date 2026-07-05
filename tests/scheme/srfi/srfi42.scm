;; SRFI-42 (eager comprehensions) conformance tests — audit Phase 3c
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi42.scm

(import (scheme base) (srfi 42) (chibi test))

(test-begin "srfi-42")

;;; --- list-ec with the core generators ---
(test '(0 1 2 3) (list-ec (:range i 4) i))
(test '(2 3 4) (list-ec (:range i 2 5) i))
(test '(0 2 4) (list-ec (:range i 0 6 2) i))
(test '(a b) (list-ec (:list x '(a b)) x))
;; FAIL: #1216 (:string unusable in list-ec)
;; (test '(#\a #\b) (list-ec (:string c "ab") c))
;; FAIL: #1216 (:vector unusable in list-ec)
;; (test '(1 2) (list-ec (:vector x #(1 2)) x))

;;; --- accumulators ---
(test 6 (sum-ec (:range i 4) i))
(test 24 (product-ec (:list x '(2 3 4)) x))
(test 0 (min-ec (:range i 4) i))
(test 3 (max-ec (:range i 4) i))
(test 0 (first-ec 'none (:range i 4) i))
(test 3 (last-ec 'none (:range i 4) i))
(test 'none (first-ec 'none (:range i 0) i))
(test #t (any?-ec (:range i 4) (even? i)))
(test #f (every?-ec (:range i 4) (even? i)))
(test #t (every?-ec (:list x '(2 4)) (even? x)))
(test "ab" (string-ec (:list c '(#\a #\b)) c))
(test #(0 1) (vector-ec (:range i 2) i))
(test '(1 2 3 4) (append-ec (:list xs '((1 2) (3 4))) xs))

;;; --- do-ec for effects ---
(test '(0 1 2)
      (let ((acc '()))
        (do-ec (:range i 3) (set! acc (cons i acc)))
        (reverse acc)))

;;; --- fold-ec ---
;; FAIL: #1216 (fold-ec signature lacks the expression slot; spec form rejected)
;; (test 6 (fold-ec 0 (:range i 4) i +))

;;; --- nested generators (cartesian product, later loops fastest) ---
;; FAIL: #1216 (no multi-qualifier nesting)
;; (test '((1 . 3) (1 . 4) (2 . 3) (2 . 4))
;;       (list-ec (:list a '(1 2)) (:list b '(3 4)) (cons a b)))

;;; --- guards ---
;; FAIL: #1216 (no (if ...) guards)
;; (test '(0 2 4) (list-ec (:range i 6) (if (even? i)) i))

;;; --- :let and :while / :until ---
;; FAIL: #1216 (:let unusable in list-ec)
;; (test '(10) (list-ec (:let x 10) x))
;; FAIL: #1216 (:while unusable in list-ec)
;; (test '(0 1 2) (list-ec (:range i 100) (:while (< i 3)) i))
;; FAIL: #1216 (:until unusable in list-ec)
;; (test '(0 1 2 3) (list-ec (:range i 100) (:until (= i 3)) i))

;;; --- :integers with :while (infinite generator must stay bounded) ---
;; FAIL: #1216 (:integers+:while unsupported)
;; (test '(0 1 2) (list-ec (:integers i) (:while (< i 3)) i))

(test-end "srfi-42")
