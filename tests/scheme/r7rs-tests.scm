;; -*- coding: utf-8 -*-

(import (scheme base) (scheme char) (scheme lazy)
        (scheme inexact) (scheme complex) (scheme time)
        (scheme file) (scheme read) (scheme write)
        (scheme eval) (scheme process-context) (scheme case-lambda)
        (chibi test)
        )

;; R7RS test suite.  Covers all procedures and syntax in the small
;; language except `delete-file'.  Currently assumes full-unicode
;; support, the full numeric tower and all standard libraries
;; provided.
;;
;; Uses the (chibi test) library which is written in portable R7RS.
;; This is mostly a subset of SRFI-64, providing test-begin, test-end
;; and test, which could be defined as something like:
;;
;;   (define (test-begin . o) #f)
;;
;;   (define (test-end . o) #f)
;;
;;   (define-syntax test
;;     (syntax-rules ()
;;       ((test expected expr)
;;        (let ((res expr))
;;          (cond
;;           ((not (equal? expr expected))
;;            (display "FAIL: ")
;;            (write 'expr)
;;            (display ": expected ")
;;            (write expected)
;;            (display " but got ")
;;            (write res)
;;            (newline)))))))
;;
;; however (chibi test) provides nicer output, timings, and
;; approximate equivalence for floating point numbers.

(test-begin "R7RS")

(include "r7rs-4-expressions.scm")
(include "r7rs-5-program-structure.scm")
(include "r7rs-6-01-equivalence.scm")
(include "r7rs-6-02-numbers.scm")
(include "r7rs-6-03-to-06.scm")
(include "r7rs-6-07-strings.scm")
(include "r7rs-6-08-to-09.scm")
(include "r7rs-6-10-control.scm")
(include "r7rs-6-11-exceptions.scm")
(include "r7rs-6-12-to-14.scm")

(test-end)
