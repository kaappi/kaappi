;;; SRFI 274 internal — shared argument checking for the (srfi 274 ...)
;;; sub-libraries. Not part of the SRFI's public surface; do not import it
;;; from user code.
;;;
;;; The length check is bounded by `end` on purpose: it must terminate on
;;; circular lists (the whole point of the explicit `end` argument) and must
;;; never inspect the cdr of the endth pair.
(define-library (srfi 274 internal)
  (import (scheme base))
  (export argcheck!)
  (begin
    (define (length>=? im-list end)
      (let loop ((lst im-list) (n end))
        (or (zero? n)
            (and (pair? lst)
                 (loop (cdr lst) (- n 1))))))

    (define (argcheck! who start end im-list)
      (cond
        ((not (exact-integer? start))
         (error who "start must be an exact integer" start))
        ((not (exact-integer? end))
         (error who "end must be an exact integer" end))
        ((not (<= 0 start end))
         (error who "invariant: (<= 0 start end)" start end))
        ((not (length>=? im-list end))
         (error who "list is not long enough" im-list end))))))
