;; SRFI-221 (Generator/accumulator sub-library) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi221.scm

(import (scheme base) (scheme case-lambda) (scheme process-context)
        (srfi 41) (srfi 158) (srfi 221) (srfi 64))

(test-begin "srfi-221")

;;; --- accumulate-generated-values ---
(test-equal "accumulate-generated-values: basic"
  '(1 2 3 4)
  (accumulate-generated-values
    (list-accumulator)
    (generator 1 2 3 4)))

(test-equal "accumulate-generated-values: empty"
  '()
  (accumulate-generated-values
    (list-accumulator)
    (generator)))

;;; --- gdelete-duplicates ---
(test-equal "gdelete-duplicates: basic"
  '(1 2 3)
  (generator->list (gdelete-duplicates (generator 1 2 1 3 2 3))))

(test-equal "gdelete-duplicates: no duplicates"
  '(1 2 3)
  (generator->list (gdelete-duplicates (generator 1 2 3))))

(test-equal "gdelete-duplicates: all same"
  '(5)
  (generator->list (gdelete-duplicates (generator 5 5 5 5))))

(test-equal "gdelete-duplicates: empty"
  '()
  (generator->list (gdelete-duplicates (generator))))

(test-equal "gdelete-duplicates: custom equal"
  '("a" "b" "c")
  (generator->list
    (gdelete-duplicates (generator "a" "A" "b" "B" "c") string-ci=?)))

;;; --- genumerate ---
(test-equal "genumerate: basic"
  '((0 . a) (1 . b) (2 . c))
  (generator->list (genumerate (generator 'a 'b 'c))))

(test-equal "genumerate: empty"
  '()
  (generator->list (genumerate (generator))))

;;; --- gcompose-left ---
(test-equal "gcompose-left: basic"
  '(1 2 3 4)
  (generator->list
    (gcompose-left
      (lambda () (make-range-generator 1))
      (lambda (g) (gtake g 4)))))

(test-equal "gcompose-left: no ops"
  '(1 2 3)
  (generator->list
    (gcompose-left (lambda () (generator 1 2 3)))))

;;; --- gcompose-right ---
(test-equal "gcompose-right: basic"
  '(1 2 3 4)
  (generator->list
    (gcompose-right
      (lambda (g) (gtake g 4))
      (lambda () (make-range-generator 1)))))

;;; --- gchoice ---
(test-equal "gchoice: basic"
  '(1 2 1 3)
  (generator->list
    (gchoice
      (generator 0 1 0 2)
      (circular-generator 1)
      (circular-generator 2)
      (circular-generator 3))))

(test-equal "gchoice: exhausted sources"
  '(1 2 3)
  (generator->list
    (gchoice
      (generator 0 0 0 0 0 1 1 2)
      (generator 1)
      (generator 2)
      (generator 3))))

;;; --- generator->stream ---
(test-equal "generator->stream: basic"
  '(1 2 3)
  (stream->list (generator->stream (generator 1 2 3))))

(test-equal "generator->stream: empty"
  '()
  (stream->list (generator->stream (generator))))

;;; --- stream->generator ---
(test-equal "stream->generator: basic"
  '(1 2 3)
  (generator->list (stream->generator (stream 1 2 3))))

(test-equal "stream->generator: empty"
  '()
  (generator->list (stream->generator stream-null)))

(let ((runner (test-runner-current)))
  (test-end "srfi-221")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
