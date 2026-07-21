;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Copyright 2019 Linus Bjornstam
;;
;; You may use this code under either the license in the SRFI document or the
;; license below.
;;
;; Permission to use, copy, modify, and/or distribute this software for any
;; purpose with or without fee is hereby granted, provided that the above
;; copyright notice and this permission notice appear in all source copies.
;; The software is provided "as is", without any express or implied warranties.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-library (srfi 171 meta)
  (import (scheme base) (srfi 9))
  (export reduced reduced?
          unreduce
          ensure-reduced
          preserving-reduced

          list-reduce
          vector-reduce
          string-reduce
          bytevector-u8-reduce
          port-reduce
          generator-reduce)

  (include "../171-meta-impl.scm"))
