;; Regression test for #1199: record accessors/mutators must check the record type
(import (scheme base) (scheme write) (scheme process-context) (srfi 64))

(test-begin "record-type-check")

(define-record-type point (make-point x y) point? (x point-x set-point-x!) (y point-y))
(define-record-type blob  (make-blob v)    blob?  (v blob-v))

;; Basic accessor/mutator work on the correct type
(test-equal "accessor on correct type" 1 (point-x (make-point 1 2)))
(test-equal "second field accessor" 2 (point-y (make-point 1 2)))
(let ((p (make-point 10 20)))
  (set-point-x! p 99)
  (test-equal "mutator on correct type" 99 (point-x p)))

;; Predicate correctly discriminates types
(test-assert "predicate true" (point? (make-point 1 2)))
(test-assert "predicate false for other record" (not (point? (make-blob 9))))

;; Cross-type accessor must error (was silently returning wrong field)
(test-assert "accessor rejects wrong record type"
  (guard (e (#t (error-object? e))) (point-x (make-blob 9)) #f))

;; Cross-type mutator must error (was silently overwriting wrong field)
(test-assert "mutator rejects wrong record type"
  (guard (e (#t (error-object? e))) (set-point-x! (make-blob 9) 42) #f))

;; Non-record arguments must still error
(test-assert "accessor rejects non-record"
  (guard (e (#t (error-object? e))) (point-x 42) #f))
(test-assert "mutator rejects non-record"
  (guard (e (#t (error-object? e))) (set-point-x! "not-a-record" 1) #f))

;; Records defined in body context (let body)
(test-assert "body-context record type checking"
  (let ()
    (define-record-type color (make-color r) color? (r color-r))
    (guard (e (#t (error-object? e))) (color-r (make-blob 5)) #f)))

(let ((runner (test-runner-current)))
  (test-end "record-type-check")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
