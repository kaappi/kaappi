;;; SRFI 274 / SRFI 134 — (srfi 274 134): extended list->ideque.
;;;
;;; See lib/srfi/274/base.sld for the shared start/end contract.
;;;
;;; Port note: the reference implementation builds the bounded ideque with
;;; ideque-unfold. Kaappi's (srfi 134) is a simplified list-backed port
;;; that does not export ideque-unfold, so the start+end case instead hands
;;; the bounded, always-proper range produced by (srfi 274 base)'s
;;; list-copy to the underlying list->ideque — same result, one
;;; intermediate list.
;;;
;;; Reference: https://srfi.schemers.org/srfi-274/srfi-274.html
;;; License: MIT
;;; Author: Peter McGoron (reference implementation); ported to Kaappi.
(define-library (srfi 274 134)
  (import (scheme base) (scheme case-lambda)
          (srfi 274 internal)
          (rename (only (srfi 274 base) list-copy)
                  (list-copy %range-list))
          (except (srfi 134) list->ideque)
          (prefix (only (srfi 134) list->ideque) srfi-134:))
  (export list->ideque)
  (begin
    (define list->ideque
      (case-lambda
        ((lst) (srfi-134:list->ideque lst))
        ((lst start) (srfi-134:list->ideque (list-tail lst start)))
        ((lst start end)
         (argcheck! 'list->ideque start end lst)
         (srfi-134:list->ideque (%range-list lst start end)))))))
