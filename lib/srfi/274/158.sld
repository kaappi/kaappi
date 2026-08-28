;;; SRFI 274 / SRFI 158 — (srfi 274 158): extended list->generator.
;;;
;;; See lib/srfi/274/base.sld for the shared start/end contract. The
;;; start+end case returns a stateful closure that stops at `end`, so it
;;; never walks past the endth pair even on a circular list.
;;;
;;; Reference: https://srfi.schemers.org/srfi-274/srfi-274.html
;;; License: MIT
;;; Author: Peter McGoron (reference implementation); ported to Kaappi.
(define-library (srfi 274 158)
  (import (scheme base) (scheme case-lambda)
          (srfi 274 internal)
          (prefix (only (srfi 158) list->generator) srfi-158:))
  (export list->generator)
  (begin
    (define list->generator
      (case-lambda
        ((lst) (srfi-158:list->generator lst))
        ((lst start) (srfi-158:list->generator (list-tail lst start)))
        ((lst start end)
         (argcheck! 'list->generator start end lst)
         (let ((lst (list-tail lst start)))
           (lambda ()
             (if (= start end)
                 (eof-object)
                 (let ((el (car lst)))
                   (set! lst (cdr lst))
                   (set! start (+ start 1))
                   el)))))))))
