;;; SRFI 274 internal — shared argument checking and range copying for the
;;; (srfi 274 ...) sub-libraries. Not part of the SRFI's public surface; do
;;; not import it from user code.
;;;
;;; The length check is bounded by `end` on purpose: it must terminate on
;;; circular lists (the whole point of the explicit `end` argument) and must
;;; never inspect the cdr of the endth pair.
(define-library (srfi 274 internal)
  (import (scheme base))
  (export argcheck! range-list)
  (begin
    (define (length>=? im-list end)
      (let loop ((lst im-list) (n end))
        (or (zero? n)
            (and (pair? lst)
                 (loop (cdr lst) (- n 1))))))

    ;; R7RS 6.11: `error` takes a *string* message. Building "who: msg"
    ;; keeps `who` out of the irritants and gives error-object-message the
    ;; same shape as every other diagnostic under lib/.
    (define (fail who msg . irritants)
      (apply error (string-append (symbol->string who) ": " msg) irritants))

    (define (argcheck! who start end im-list)
      (cond
        ((not (exact-integer? start))
         (fail who "start must be an exact integer" start))
        ((not (exact-integer? end))
         (fail who "end must be an exact integer" end))
        ((not (<= 0 start end))
         (fail who "invariant: (<= 0 start end)" start end))
        ((not (length>=? im-list end))
         (fail who "list is not long enough" im-list end))))

    ;; Check the range once, then copy it. Every converter that needs the
    ;; bounded elements as a proper list goes through here so the walk (and
    ;; the `who` on any error) happens exactly once per call.
    (define (range-list who im-list start end)
      (argcheck! who start end im-list)
      (let ((returned (make-list (- end start))))
        (do ((head returned (cdr head))
             (i 0 (+ i 1))
             (lst (list-tail im-list start) (cdr lst)))
            ((null? head) returned)
          (set-car! head (car lst)))))))
