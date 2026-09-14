;;; SRFI 160 -- (srfi 160 u8): u8vector library.
;;; Core 9 procedures + validity predicate come from (srfi 160 base)
;;; unchanged; the SRFI-133-shaped extended surface is that same base
;;; library's generic `%uvec-*` engine, renamed or kind-closed here.
(define-library (srfi 160 u8)
  (import (scheme base)
          (rename (srfi 160 base)
                  (%uvec-fold u8vector-fold)
                  (%uvec-fold-right u8vector-fold-right)
                  (%uvec-map! u8vector-map!)
                  (%uvec-for-each u8vector-for-each)
                  (%uvec-count u8vector-count)
                  (%uvec-index u8vector-index)
                  (%uvec-index-right u8vector-index-right)
                  (%uvec-skip u8vector-skip)
                  (%uvec-skip-right u8vector-skip-right)
                  (%uvec-any u8vector-any)
                  (%uvec-every u8vector-every)
                  (%uvec-empty? u8vector-empty?)
                  (%uvec= u8vector=)
                  (%uvec-swap! u8vector-swap!)
                  (%uvec-fill! u8vector-fill!)
                  (%uvec-reverse! u8vector-reverse!)
                  (%uvec-copy! u8vector-copy!)
                  (%uvec-reverse-copy! u8vector-reverse-copy!)
                  (%uvec-unfold! u8vector-unfold!)
                  (%uvec-unfold-right! u8vector-unfold-right!)
                  (%uvec-reverse->list reverse-u8vector->list)
                  (%uvec-generator make-u8vector-generator)
                  (%uvec-write write-u8vector)))
  (export make-u8vector u8vector u8vector? u8vector-length u8vector-ref u8vector-set!
          u8vector->list list->u8vector u8?
          u8vector-unfold u8vector-unfold-right u8vector-unfold! u8vector-unfold-right!
          u8vector-copy u8vector-reverse-copy u8vector-append u8vector-concatenate
          u8vector-append-subvectors
          u8vector-empty? u8vector=
          u8vector-take u8vector-take-right u8vector-drop u8vector-drop-right u8vector-segment
          u8vector-fold u8vector-fold-right u8vector-map u8vector-map! u8vector-for-each
          u8vector-count u8vector-cumulate
          u8vector-take-while u8vector-take-while-right u8vector-drop-while u8vector-drop-while-right
          u8vector-index u8vector-index-right u8vector-skip u8vector-skip-right
          u8vector-any u8vector-every
          u8vector-partition u8vector-filter u8vector-remove
          u8vector-swap! u8vector-fill! u8vector-reverse! u8vector-copy! u8vector-reverse-copy!
          reverse-u8vector->list reverse-list->u8vector
          u8vector->vector vector->u8vector
          make-u8vector-generator
          u8vector-comparator
          write-u8vector)
  (begin
    (define (u8vector-unfold f len . seeds) (apply %uvec-unfold 'u8 f len seeds))
    (define (u8vector-unfold-right f len . seeds) (apply %uvec-unfold-right 'u8 f len seeds))
    (define (u8vector-copy v . args) (apply %uvec-copy 'u8 v args))
    (define (u8vector-reverse-copy v . args) (apply %uvec-reverse-copy 'u8 v args))
    (define (u8vector-append . vs) (apply %uvec-append 'u8 vs))
    (define (u8vector-concatenate vs) (%uvec-concatenate 'u8 vs))
    (define (u8vector-append-subvectors . args) (apply %uvec-append-subvectors 'u8 args))
    (define (u8vector-take v n) (%uvec-take 'u8 v n))
    (define (u8vector-take-right v n) (%uvec-take-right 'u8 v n))
    (define (u8vector-drop v n) (%uvec-drop 'u8 v n))
    (define (u8vector-drop-right v n) (%uvec-drop-right 'u8 v n))
    (define (u8vector-segment v n) (%uvec-segment 'u8 v n))
    (define (u8vector-take-while pred v) (%uvec-take-while 'u8 pred v))
    (define (u8vector-take-while-right pred v) (%uvec-take-while-right 'u8 pred v))
    (define (u8vector-drop-while pred v) (%uvec-drop-while 'u8 pred v))
    (define (u8vector-drop-while-right pred v) (%uvec-drop-while-right 'u8 pred v))
    (define (u8vector-map f v . vs) (apply %uvec-map 'u8 f v vs))
    (define (u8vector-cumulate f knil v) (%uvec-cumulate 'u8 f knil v))
    (define (u8vector-filter pred v) (%uvec-filter 'u8 pred v))
    (define (u8vector-remove pred v) (%uvec-remove 'u8 pred v))
    (define (u8vector-partition pred v) (%uvec-partition 'u8 pred v))
    (define (reverse-list->u8vector lst) (%uvec-reverse-list-> 'u8 lst))
    (define (u8vector->vector v . args) (apply %uvec->vector v args))
    (define (vector->u8vector vec . args) (apply %uvec-vector-> 'u8 vec args))
    (define u8vector-comparator (%uvec-make-comparator 'u8))))
