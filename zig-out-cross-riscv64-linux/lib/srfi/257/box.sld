;;; SRFI 257 box sublibrary: ~box? and ~box patterns over SRFI 111 boxes.
;;;
;;; Ported to Kaappi from Sergei Egorov's reference implementation.
;;;
;;; SPDX-FileCopyrightText: 2024 Sergei Egorov
;;; SPDX-License-Identifier: MIT

(define-library (srfi 257 box)
  (import (scheme base) (srfi 111) (srfi 257))
  (export ~box? ~box)

(begin

(define-match-pattern ~box? ()
  ((_ p ...) (~and (~test box?) p ...)))


(define-match-pattern ~box ()
  ((_ p) (~and (~test box?) (~prop unbox => p))))

))
