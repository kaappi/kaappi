;;; SRFI 160 -- (srfi 160 u64): u64vector library.
;;; Core 9 procedures + validity predicate come from (srfi 160 base)
;;; unchanged; the SRFI-133-shaped extended surface is that same base
;;; library's generic `%uvec-*` engine, renamed or kind-closed here.
(define-library (srfi 160 u64)
  (import (scheme base)
          (rename (srfi 160 base)
                  (%uvec-fold u64vector-fold)
                  (%uvec-fold-right u64vector-fold-right)
                  (%uvec-map! u64vector-map!)
                  (%uvec-for-each u64vector-for-each)
                  (%uvec-count u64vector-count)
                  (%uvec-index u64vector-index)
                  (%uvec-index-right u64vector-index-right)
                  (%uvec-skip u64vector-skip)
                  (%uvec-skip-right u64vector-skip-right)
                  (%uvec-any u64vector-any)
                  (%uvec-every u64vector-every)
                  (%uvec-empty? u64vector-empty?)
                  (%uvec= u64vector=)
                  (%uvec-swap! u64vector-swap!)
                  (%uvec-fill! u64vector-fill!)
                  (%uvec-reverse! u64vector-reverse!)
                  (%uvec-copy! u64vector-copy!)
                  (%uvec-reverse-copy! u64vector-reverse-copy!)
                  (%uvec-unfold! u64vector-unfold!)
                  (%uvec-unfold-right! u64vector-unfold-right!)
                  (%uvec-reverse->list reverse-u64vector->list)
                  (%uvec-generator make-u64vector-generator)
                  (%uvec-write write-u64vector)))
  (export make-u64vector u64vector u64vector? u64vector-length u64vector-ref u64vector-set!
          u64vector->list list->u64vector u64?
          u64vector-unfold u64vector-unfold-right u64vector-unfold! u64vector-unfold-right!
          u64vector-copy u64vector-reverse-copy u64vector-append u64vector-concatenate
          u64vector-append-subvectors
          u64vector-empty? u64vector=
          u64vector-take u64vector-take-right u64vector-drop u64vector-drop-right u64vector-segment
          u64vector-fold u64vector-fold-right u64vector-map u64vector-map! u64vector-for-each
          u64vector-count u64vector-cumulate
          u64vector-take-while u64vector-take-while-right u64vector-drop-while u64vector-drop-while-right
          u64vector-index u64vector-index-right u64vector-skip u64vector-skip-right
          u64vector-any u64vector-every
          u64vector-partition u64vector-filter u64vector-remove
          u64vector-swap! u64vector-fill! u64vector-reverse! u64vector-copy! u64vector-reverse-copy!
          reverse-u64vector->list reverse-list->u64vector
          u64vector->vector vector->u64vector
          make-u64vector-generator
          u64vector-comparator
          write-u64vector)
  (begin
    (define (u64vector-unfold f len . seeds) (apply %uvec-unfold 'u64 f len seeds))
    (define (u64vector-unfold-right f len . seeds) (apply %uvec-unfold-right 'u64 f len seeds))
    (define (u64vector-copy v . args) (apply %uvec-copy 'u64 v args))
    (define (u64vector-reverse-copy v . args) (apply %uvec-reverse-copy 'u64 v args))
    (define (u64vector-append . vs) (apply %uvec-append 'u64 vs))
    (define (u64vector-concatenate vs) (%uvec-concatenate 'u64 vs))
    (define (u64vector-append-subvectors . args) (apply %uvec-append-subvectors 'u64 args))
    (define (u64vector-take v n) (%uvec-take 'u64 v n))
    (define (u64vector-take-right v n) (%uvec-take-right 'u64 v n))
    (define (u64vector-drop v n) (%uvec-drop 'u64 v n))
    (define (u64vector-drop-right v n) (%uvec-drop-right 'u64 v n))
    (define (u64vector-segment v n) (%uvec-segment 'u64 v n))
    (define (u64vector-take-while pred v) (%uvec-take-while 'u64 pred v))
    (define (u64vector-take-while-right pred v) (%uvec-take-while-right 'u64 pred v))
    (define (u64vector-drop-while pred v) (%uvec-drop-while 'u64 pred v))
    (define (u64vector-drop-while-right pred v) (%uvec-drop-while-right 'u64 pred v))
    (define (u64vector-map f v . vs) (apply %uvec-map 'u64 f v vs))
    (define (u64vector-cumulate f knil v) (%uvec-cumulate 'u64 f knil v))
    (define (u64vector-filter pred v) (%uvec-filter 'u64 pred v))
    (define (u64vector-remove pred v) (%uvec-remove 'u64 pred v))
    (define (u64vector-partition pred v) (%uvec-partition 'u64 pred v))
    (define (reverse-list->u64vector lst) (%uvec-reverse-list-> 'u64 lst))
    (define (u64vector->vector v . args) (apply %uvec->vector v args))
    (define (vector->u64vector vec . args) (apply %uvec-vector-> 'u64 vec args))
    (define u64vector-comparator (%uvec-make-comparator 'u64))))
