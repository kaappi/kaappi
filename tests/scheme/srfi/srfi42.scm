;; SRFI-42 (eager comprehensions) conformance tests
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi42.scm

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 42) (srfi 64))

(test-begin "srfi-42")

;;; --- list-ec with the core generators ---
(test-equal "range 1-arg" '(0 1 2 3) (list-ec (:range i 4) i))
(test-equal "range 2-arg" '(2 3 4) (list-ec (:range i 2 5) i))
(test-equal "range 3-arg" '(0 2 4) (list-ec (:range i 0 6 2) i))
(test-equal "list" '(a b) (list-ec (:list x '(a b)) x))
(test-equal "string" '(#\a #\b) (list-ec (:string c "ab") c))
(test-equal "vector" '(1 2) (list-ec (:vector x #(1 2)) x))

;;; --- accumulators ---
(test-equal "sum-ec" 6 (sum-ec (:range i 4) i))
(test-equal "product-ec" 24 (product-ec (:list x '(2 3 4)) x))
(test-equal "min-ec" 0 (min-ec (:range i 4) i))
(test-equal "max-ec" 3 (max-ec (:range i 4) i))
(test-equal "first-ec" 0 (first-ec 'none (:range i 4) i))
(test-equal "last-ec" 3 (last-ec 'none (:range i 4) i))
(test-equal "first-ec default" 'none (first-ec 'none (:range i 0) i))
(test-equal "any?-ec true" #t (any?-ec (:range i 4) (even? i)))
(test-equal "every?-ec false" #f (every?-ec (:range i 4) (even? i)))
(test-equal "every?-ec true" #t (every?-ec (:list x '(2 4)) (even? x)))
(test-equal "string-ec" "ab" (string-ec (:list c '(#\a #\b)) c))
(test-equal "vector-ec" #(0 1) (vector-ec (:range i 2) i))
(test-equal "append-ec" '(1 2 3 4) (append-ec (:list xs '((1 2) (3 4))) xs))

;;; --- do-ec for effects ---
(test-equal "do-ec"
  '(0 1 2)
  (let ((acc '()))
    (do-ec (:range i 3) (set! acc (cons i acc)))
    (reverse acc)))

;;; --- fold-ec (SRFI-42 signature: seed qualifier... expr proc) ---
(test-equal "fold-ec +" 6 (fold-ec 0 (:range i 4) i +))
(test-equal "fold-ec cons" '(2 1 0) (fold-ec '() (:range i 3) i cons))
(test-equal "fold-ec -" 2 (fold-ec 0 (:range i 1 4) i -))

;;; --- fold3-ec (seed qualifier... expr f1 f2) ---
(test-equal "fold3-ec" 6 (fold3-ec 'unused (:range i 1 4) i values +))
(test-equal "fold3-ec empty" 'empty (fold3-ec 'empty (:range i 0) i values +))

;;; --- nested generators (cartesian product, rightmost spins fastest) ---
(test-equal "nested list x list"
  '((1 . 3) (1 . 4) (2 . 3) (2 . 4))
  (list-ec (:list a '(1 2)) (:list b '(3 4)) (cons a b)))

(test-equal "nested range x range"
  '((0 0) (0 1) (1 0) (1 1))
  (list-ec (:range i 2) (:range j 2) (list i j)))

;;; --- guards ---
(test-equal "if guard" '(0 2 4) (list-ec (:range i 6) (if (even? i)) i))

(test-equal "not guard" '(1 3 5) (list-ec (:range i 6) (not (even? i)) i))

(test-equal "and guard" '(2 4) (list-ec (:range i 6) (and (even? i) (> i 0)) i))

(test-equal "or guard" '(0 1 3 5) (list-ec (:range i 6) (or (not (even? i)) (= i 0)) i))

;;; --- :let ---
(test-equal ":let" '(10) (list-ec (:let x 10) x))

(test-equal ":let with range"
  '(0 10 20)
  (list-ec (:range i 3) (:let x (* i 10)) x))

;;; --- :while (stop entire comprehension when test becomes false) ---
(test-equal ":while standalone" '(0 1 2)
  (list-ec (:range i 100) (:while (< i 3)) i))

(test-equal ":while wrapping generator" '(0 1 2 3 4)
  (list-ec (:while (:range i 10) (< i 5)) i))

;;; --- :until (include the triggering element, then stop) ---
(test-equal ":until" '(0 1 2 3) (list-ec (:range i 100) (:until (= i 3)) i))

;;; --- :integers with :while (infinite generator, bounded by :while) ---
(test-equal ":integers + :while"
  '(0 1 2)
  (list-ec (:integers i) (:while (< i 3)) i))

;;; --- combined: nested + guard ---
(test-equal "nested + guard"
  '((1 . 4) (2 . 3) (2 . 4))
  (list-ec (:list a '(1 2)) (:list b '(3 4)) (if (> (+ a b) 4)) (cons a b)))

(let ((runner (test-runner-current)))
  (test-end "srfi-42")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
