(import (scheme base) (scheme write) (scheme char) (srfi 13) (srfi 170))
(import (scheme process-context) (srfi 64))

(test-begin "SRFI completeness")

;;; ================================================================
;;; SRFI-13: string-unfold
;;; ================================================================
(test-equal "ABCDE" (string-unfold (lambda (x) (> x 4))
                                   (lambda (x) (integer->char (+ x 65)))
                                   (lambda (x) (+ x 1))
                                   0))
(test-equal "" (string-unfold (lambda (x) #t) values values 0))

;; With base string
(test-equal "baseABC" (string-unfold (lambda (x) (> x 2))
                                     (lambda (x) (integer->char (+ x 65)))
                                     (lambda (x) (+ x 1))
                                     0
                                     "base"))

;;; string-unfold-right
(test-equal "EDCBA" (string-unfold-right (lambda (x) (> x 4))
                                         (lambda (x) (integer->char (+ x 65)))
                                         (lambda (x) (+ x 1))
                                         0))

;;; ================================================================
;;; SRFI-13: string-index-right
;;; ================================================================
(test-equal 3 (string-index-right "abcabc" (lambda (c) (char=? c #\a))))
(test-equal 5 (string-index-right "abcabc" (lambda (c) (char=? c #\c))))
(test-equal #f (string-index-right "abcabc" (lambda (c) (char=? c #\z))))

;;; ================================================================
;;; SRFI-13: string-skip / string-skip-right
;;; ================================================================
(test-equal 3 (string-skip "aaabcd" (lambda (c) (char=? c #\a))))
(test-equal #f (string-skip "aaa" (lambda (c) (char=? c #\a))))
(test-equal 0 (string-skip "baaaa" (lambda (c) (char=? c #\a))))

(test-equal 2 (string-skip-right "abcaaa" (lambda (c) (char=? c #\a))))
(test-equal #f (string-skip-right "aaa" (lambda (c) (char=? c #\a))))

;;; ================================================================
;;; SRFI-170: file-info-type
;;; ================================================================
(test-equal 'directory (file-info-type (file-info ".")))
(call-with-output-file "/tmp/kaappi-srfi170-test.txt"
  (lambda (p) (display "x" p)))
(test-equal 'regular (file-info-type (file-info "/tmp/kaappi-srfi170-test.txt")))
(delete-file "/tmp/kaappi-srfi170-test.txt")

;;; ================================================================
;;; SRFI-170: temp-file-prefix
;;; ================================================================
(test-equal #t (string? (temp-file-prefix)))

;;; ================================================================
;;; SRFI-170: create-temp-file
;;; ================================================================
(let ((path (create-temp-file)))
  (test-equal #t (file-exists? path))
  (test-equal #t (string? path))
  (test-equal 'regular (file-info-type (file-info path)))
  (delete-file path))

(let ((runner (test-runner-current)))
  (test-end "SRFI completeness")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
