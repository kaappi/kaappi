;;; SRFI 160 -- (srfi 160 u32): u32vector library.
;;; Core 9 procedures + validity predicate come from (srfi 160 base)
;;; unchanged; the SRFI-133-shaped extended surface is that same base
;;; library's generic `%uvec-*` engine, renamed or kind-closed here.
(define-library (srfi 160 u32)
  (import (scheme base)
          (rename (srfi 160 base)
                  (%uvec-fold u32vector-fold)
                  (%uvec-fold-right u32vector-fold-right)
                  (%uvec-map! u32vector-map!)
                  (%uvec-for-each u32vector-for-each)
                  (%uvec-count u32vector-count)
                  (%uvec-index u32vector-index)
                  (%uvec-index-right u32vector-index-right)
                  (%uvec-skip u32vector-skip)
                  (%uvec-skip-right u32vector-skip-right)
                  (%uvec-any u32vector-any)
                  (%uvec-every u32vector-every)
                  (%uvec-empty? u32vector-empty?)
                  (%uvec= u32vector=)
                  (%uvec-swap! u32vector-swap!)
                  (%uvec-fill! u32vector-fill!)
                  (%uvec-reverse! u32vector-reverse!)
                  (%uvec-copy! u32vector-copy!)
                  (%uvec-reverse-copy! u32vector-reverse-copy!)
                  (%uvec-unfold! u32vector-unfold!)
                  (%uvec-unfold-right! u32vector-unfold-right!)
                  (%uvec-reverse->list reverse-u32vector->list)
                  (%uvec-generator make-u32vector-generator)
                  (%uvec-write write-u32vector)))
  (export make-u32vector u32vector u32vector? u32vector-length u32vector-ref u32vector-set!
          u32vector->list list->u32vector u32?
          u32vector-unfold u32vector-unfold-right u32vector-unfold! u32vector-unfold-right!
          u32vector-copy u32vector-reverse-copy u32vector-append u32vector-concatenate
          u32vector-append-subvectors
          u32vector-empty? u32vector=
          u32vector-take u32vector-take-right u32vector-drop u32vector-drop-right u32vector-segment
          u32vector-fold u32vector-fold-right u32vector-map u32vector-map! u32vector-for-each
          u32vector-count u32vector-cumulate
          u32vector-take-while u32vector-take-while-right u32vector-drop-while u32vector-drop-while-right
          u32vector-index u32vector-index-right u32vector-skip u32vector-skip-right
          u32vector-any u32vector-every
          u32vector-partition u32vector-filter u32vector-remove
          u32vector-swap! u32vector-fill! u32vector-reverse! u32vector-copy! u32vector-reverse-copy!
          reverse-u32vector->list reverse-list->u32vector
          u32vector->vector vector->u32vector
          make-u32vector-generator
          u32vector-comparator
          write-u32vector)
  (begin
    (define (u32vector-unfold f len . seeds) (apply %uvec-unfold 'u32 f len seeds))
    (define (u32vector-unfold-right f len . seeds) (apply %uvec-unfold-right 'u32 f len seeds))
    (define (u32vector-copy v . args) (apply %uvec-copy 'u32 v args))
    (define (u32vector-reverse-copy v . args) (apply %uvec-reverse-copy 'u32 v args))
    (define (u32vector-append . vs) (apply %uvec-append 'u32 vs))
    (define (u32vector-concatenate vs) (%uvec-concatenate 'u32 vs))
    (define (u32vector-append-subvectors . args) (apply %uvec-append-subvectors 'u32 args))
    (define (u32vector-take v n) (%uvec-take 'u32 v n))
    (define (u32vector-take-right v n) (%uvec-take-right 'u32 v n))
    (define (u32vector-drop v n) (%uvec-drop 'u32 v n))
    (define (u32vector-drop-right v n) (%uvec-drop-right 'u32 v n))
    (define (u32vector-segment v n) (%uvec-segment 'u32 v n))
    (define (u32vector-take-while pred v) (%uvec-take-while 'u32 pred v))
    (define (u32vector-take-while-right pred v) (%uvec-take-while-right 'u32 pred v))
    (define (u32vector-drop-while pred v) (%uvec-drop-while 'u32 pred v))
    (define (u32vector-drop-while-right pred v) (%uvec-drop-while-right 'u32 pred v))
    (define (u32vector-map f v . vs) (apply %uvec-map 'u32 f v vs))
    (define (u32vector-cumulate f knil v) (%uvec-cumulate 'u32 f knil v))
    (define (u32vector-filter pred v) (%uvec-filter 'u32 pred v))
    (define (u32vector-remove pred v) (%uvec-remove 'u32 pred v))
    (define (u32vector-partition pred v) (%uvec-partition 'u32 pred v))
    (define (reverse-list->u32vector lst) (%uvec-reverse-list-> 'u32 lst))
    (define (u32vector->vector v . args) (apply %uvec->vector v args))
    (define (vector->u32vector vec . args) (apply %uvec-vector-> 'u32 vec args))
    (define u32vector-comparator (%uvec-make-comparator 'u32))))
