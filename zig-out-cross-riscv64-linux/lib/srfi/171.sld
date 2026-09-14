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

(define-library (srfi 171)
  (import (scheme base)
          (scheme case-lambda)
          (scheme write)
          (srfi 9)
          (srfi 69)
          (srfi 171 meta))
  (export rcons reverse-rcons
          rcount
          rany
          revery

          list-transduce
          vector-transduce
          string-transduce
          bytevector-u8-transduce
          port-transduce
          generator-transduce

          tmap
          tfilter
          tremove
          treplace
          tfilter-map
          tdrop
          tdrop-while
          ttake
          ttake-while
          tconcatenate
          tappend-map
          tdelete-neighbor-duplicates
          tdelete-duplicates
          tflatten
          tsegment
          tpartition
          tadd-between
          tenumerate
          tlog)

  (include "171-impl.scm"))
