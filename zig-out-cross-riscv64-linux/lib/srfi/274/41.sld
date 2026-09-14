;;; SRFI 274 / SRFI 41 — (srfi 274 41): extended list->stream.
;;;
;;; See lib/srfi/274/base.sld for the shared start/end contract. The
;;; start+end case builds the stream lazily with stream-lambda, so forcing
;;; it never walks past the endth pair — circular lists are fine.
;;;
;;; Reference: https://srfi.schemers.org/srfi-274/srfi-274.html
;;; License: MIT
;;; Author: Peter McGoron (reference implementation); ported to Kaappi.
(define-library (srfi 274 41)
  (import (scheme base) (scheme case-lambda)
          (srfi 274 internal)
          (except (srfi 41) list->stream)
          (prefix (only (srfi 41) list->stream) srfi-41:))
  (export list->stream)
  (begin
    (define list->stream
      (case-lambda
        ((lst) (srfi-41:list->stream lst))
        ((lst start) (srfi-41:list->stream (list-tail lst start)))
        ((lst start end)
         (argcheck! 'list->stream start end lst)
         (letrec ((loop (stream-lambda (lst start)
                          (if (= start end)
                              stream-null
                              (stream-cons (car lst)
                                           (loop (cdr lst)
                                                 (+ start 1)))))))
           (loop (list-tail lst start) start)))))))
