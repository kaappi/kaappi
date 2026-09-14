;;; SRFI 160 -- (srfi 160 u16): u16vector library.
;;; Core 9 procedures + validity predicate come from (srfi 160 base)
;;; unchanged; the SRFI-133-shaped extended surface is that same base
;;; library's generic `%uvec-*` engine, renamed or kind-closed here.
(define-library (srfi 160 u16)
  (import (scheme base)
          (rename (srfi 160 base)
                  (%uvec-fold u16vector-fold)
                  (%uvec-fold-right u16vector-fold-right)
                  (%uvec-map! u16vector-map!)
                  (%uvec-for-each u16vector-for-each)
                  (%uvec-count u16vector-count)
                  (%uvec-index u16vector-index)
                  (%uvec-index-right u16vector-index-right)
                  (%uvec-skip u16vector-skip)
                  (%uvec-skip-right u16vector-skip-right)
                  (%uvec-any u16vector-any)
                  (%uvec-every u16vector-every)
                  (%uvec-empty? u16vector-empty?)
                  (%uvec= u16vector=)
                  (%uvec-swap! u16vector-swap!)
                  (%uvec-fill! u16vector-fill!)
                  (%uvec-reverse! u16vector-reverse!)
                  (%uvec-copy! u16vector-copy!)
                  (%uvec-reverse-copy! u16vector-reverse-copy!)
                  (%uvec-unfold! u16vector-unfold!)
                  (%uvec-unfold-right! u16vector-unfold-right!)
                  (%uvec-reverse->list reverse-u16vector->list)
                  (%uvec-generator make-u16vector-generator)
                  (%uvec-write write-u16vector)))
  (export make-u16vector u16vector u16vector? u16vector-length u16vector-ref u16vector-set!
          u16vector->list list->u16vector u16?
          u16vector-unfold u16vector-unfold-right u16vector-unfold! u16vector-unfold-right!
          u16vector-copy u16vector-reverse-copy u16vector-append u16vector-concatenate
          u16vector-append-subvectors
          u16vector-empty? u16vector=
          u16vector-take u16vector-take-right u16vector-drop u16vector-drop-right u16vector-segment
          u16vector-fold u16vector-fold-right u16vector-map u16vector-map! u16vector-for-each
          u16vector-count u16vector-cumulate
          u16vector-take-while u16vector-take-while-right u16vector-drop-while u16vector-drop-while-right
          u16vector-index u16vector-index-right u16vector-skip u16vector-skip-right
          u16vector-any u16vector-every
          u16vector-partition u16vector-filter u16vector-remove
          u16vector-swap! u16vector-fill! u16vector-reverse! u16vector-copy! u16vector-reverse-copy!
          reverse-u16vector->list reverse-list->u16vector
          u16vector->vector vector->u16vector
          make-u16vector-generator
          u16vector-comparator
          write-u16vector)
  (begin
    (define (u16vector-unfold f len . seeds) (apply %uvec-unfold 'u16 f len seeds))
    (define (u16vector-unfold-right f len . seeds) (apply %uvec-unfold-right 'u16 f len seeds))
    (define (u16vector-copy v . args) (apply %uvec-copy 'u16 v args))
    (define (u16vector-reverse-copy v . args) (apply %uvec-reverse-copy 'u16 v args))
    (define (u16vector-append . vs) (apply %uvec-append 'u16 vs))
    (define (u16vector-concatenate vs) (%uvec-concatenate 'u16 vs))
    (define (u16vector-append-subvectors . args) (apply %uvec-append-subvectors 'u16 args))
    (define (u16vector-take v n) (%uvec-take 'u16 v n))
    (define (u16vector-take-right v n) (%uvec-take-right 'u16 v n))
    (define (u16vector-drop v n) (%uvec-drop 'u16 v n))
    (define (u16vector-drop-right v n) (%uvec-drop-right 'u16 v n))
    (define (u16vector-segment v n) (%uvec-segment 'u16 v n))
    (define (u16vector-take-while pred v) (%uvec-take-while 'u16 pred v))
    (define (u16vector-take-while-right pred v) (%uvec-take-while-right 'u16 pred v))
    (define (u16vector-drop-while pred v) (%uvec-drop-while 'u16 pred v))
    (define (u16vector-drop-while-right pred v) (%uvec-drop-while-right 'u16 pred v))
    (define (u16vector-map f v . vs) (apply %uvec-map 'u16 f v vs))
    (define (u16vector-cumulate f knil v) (%uvec-cumulate 'u16 f knil v))
    (define (u16vector-filter pred v) (%uvec-filter 'u16 pred v))
    (define (u16vector-remove pred v) (%uvec-remove 'u16 pred v))
    (define (u16vector-partition pred v) (%uvec-partition 'u16 pred v))
    (define (reverse-list->u16vector lst) (%uvec-reverse-list-> 'u16 lst))
    (define (u16vector->vector v . args) (apply %uvec->vector v args))
    (define (vector->u16vector vec . args) (apply %uvec-vector-> 'u16 vec args))
    (define u16vector-comparator (%uvec-make-comparator 'u16))))
