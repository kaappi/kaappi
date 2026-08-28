;;; SRFI 274 base — (srfi 274 base): extended list-copy, list->string and
;;; list->vector.
;;;
;;; Each procedure takes (im-list [start [end]]). The start/end semantics
;;; follow vector-copy: 0 <= start <= end <= length, start inclusive, end
;;; exclusive. When `end` is supplied the procedure never inspects the cdr
;;; of the endth pair, so dotted and circular lists are legal with an
;;; explicit end. Passing an improper list *without* an explicit end is an
;;; error per the SRFI — diagnosed here by the underlying R7RS builtins,
;;; whose length walk detects dotted and circular lists alike. The sole
;;; exception is list-copy, which copies an improper list wholesale.
;;;
;;; Reference: https://srfi.schemers.org/srfi-274/srfi-274.html
;;; License: MIT
;;; Author: Peter McGoron (reference implementation); ported to Kaappi.
(define-library (srfi 274 base)
  (import (except (scheme base)
                  list-copy list->string list->vector)
          (scheme case-lambda)
          (srfi 274 internal)
          (prefix (only (scheme base)
                        list-copy list->string list->vector)
                  r7rs:))
  (export list-copy list->string list->vector)
  (begin
    (define list-copy
      (case-lambda
        ;; No start/end: the R7RS builtin already copies improper lists
        ;; wholesale (final cdrs shared, non-list returned unchanged) and
        ;; detects circular input, which is an error per the SRFI.
        ((lst) (r7rs:list-copy lst))
        ;; start only: keep the tail verbatim, dotted or not — the SRFI
        ;; defines this as (list-copy (drop im-list start)).
        ((lst start) (r7rs:list-copy (list-tail lst start)))
        ((lst start end)
         (argcheck! 'list-copy start end lst)
         (let ((returned (make-list (- end start))))
           (do ((head returned (cdr head))
                (i 0 (+ i 1))
                (lst (list-tail lst start) (cdr lst)))
               ((null? head) returned)
             (set-car! head (car lst)))))))

    (define list->string
      (case-lambda
        ((lst) (r7rs:list->string lst))
        ((lst start) (r7rs:list->string (list-tail lst start)))
        ((lst start end)
         ;; Bounded copy first (terminates on any im-list given end), then
         ;; the builtin does the character validation and string build.
         (r7rs:list->string (list-copy lst start end)))))

    (define list->vector
      (case-lambda
        ((lst) (r7rs:list->vector lst))
        ((lst start) (r7rs:list->vector (list-tail lst start)))
        ((lst start end)
         (argcheck! 'list->vector start end lst)
         (do ((returned (make-vector (- end start)))
              (i 0 (+ i 1))
              (lst (list-tail lst start) (cdr lst)))
             ((= i (- end start)) returned)
           (vector-set! returned i (car lst))))))))
