;;; SRFI 274 / SRFI 160 — (srfi 274 160 f32): extended list->f32vector.
;;; Thin re-export of the definition in (srfi 274 160 base); see that
;;; library and lib/srfi/274/base.sld for the start/end contract.
(define-library (srfi 274 160 f32)
  (import (srfi 274 160 base))
  (export list->f32vector))
