;;; SRFI 160 -- (srfi 160 c128): c128vector library.
;;; Core 9 procedures + validity predicate come from (srfi 160 base)
;;; unchanged; the SRFI-133-shaped extended surface is that same base
;;; library's generic `%uvec-*` engine, renamed or kind-closed here.
(define-library (srfi 160 c128)
  (import (scheme base)
          (rename (srfi 160 base)
                  (%uvec-fold c128vector-fold)
                  (%uvec-fold-right c128vector-fold-right)
                  (%uvec-map! c128vector-map!)
                  (%uvec-for-each c128vector-for-each)
                  (%uvec-count c128vector-count)
                  (%uvec-index c128vector-index)
                  (%uvec-index-right c128vector-index-right)
                  (%uvec-skip c128vector-skip)
                  (%uvec-skip-right c128vector-skip-right)
                  (%uvec-any c128vector-any)
                  (%uvec-every c128vector-every)
                  (%uvec-empty? c128vector-empty?)
                  (%uvec= c128vector=)
                  (%uvec-swap! c128vector-swap!)
                  (%uvec-fill! c128vector-fill!)
                  (%uvec-reverse! c128vector-reverse!)
                  (%uvec-copy! c128vector-copy!)
                  (%uvec-reverse-copy! c128vector-reverse-copy!)
                  (%uvec-unfold! c128vector-unfold!)
                  (%uvec-unfold-right! c128vector-unfold-right!)
                  (%uvec-reverse->list reverse-c128vector->list)
                  (%uvec-generator make-c128vector-generator)
                  (%uvec-write write-c128vector)))
  (export make-c128vector c128vector c128vector? c128vector-length c128vector-ref c128vector-set!
          c128vector->list list->c128vector c128?
          c128vector-unfold c128vector-unfold-right c128vector-unfold! c128vector-unfold-right!
          c128vector-copy c128vector-reverse-copy c128vector-append c128vector-concatenate
          c128vector-append-subvectors
          c128vector-empty? c128vector=
          c128vector-take c128vector-take-right c128vector-drop c128vector-drop-right c128vector-segment
          c128vector-fold c128vector-fold-right c128vector-map c128vector-map! c128vector-for-each
          c128vector-count c128vector-cumulate
          c128vector-take-while c128vector-take-while-right c128vector-drop-while c128vector-drop-while-right
          c128vector-index c128vector-index-right c128vector-skip c128vector-skip-right
          c128vector-any c128vector-every
          c128vector-partition c128vector-filter c128vector-remove
          c128vector-swap! c128vector-fill! c128vector-reverse! c128vector-copy! c128vector-reverse-copy!
          reverse-c128vector->list reverse-list->c128vector
          c128vector->vector vector->c128vector
          make-c128vector-generator
          c128vector-comparator
          write-c128vector)
  (begin
    (define (c128vector-unfold f len . seeds) (apply %uvec-unfold 'c128 f len seeds))
    (define (c128vector-unfold-right f len . seeds) (apply %uvec-unfold-right 'c128 f len seeds))
    (define (c128vector-copy v . args) (apply %uvec-copy 'c128 v args))
    (define (c128vector-reverse-copy v . args) (apply %uvec-reverse-copy 'c128 v args))
    (define (c128vector-append . vs) (apply %uvec-append 'c128 vs))
    (define (c128vector-concatenate vs) (%uvec-concatenate 'c128 vs))
    (define (c128vector-append-subvectors . args) (apply %uvec-append-subvectors 'c128 args))
    (define (c128vector-take v n) (%uvec-take 'c128 v n))
    (define (c128vector-take-right v n) (%uvec-take-right 'c128 v n))
    (define (c128vector-drop v n) (%uvec-drop 'c128 v n))
    (define (c128vector-drop-right v n) (%uvec-drop-right 'c128 v n))
    (define (c128vector-segment v n) (%uvec-segment 'c128 v n))
    (define (c128vector-take-while pred v) (%uvec-take-while 'c128 pred v))
    (define (c128vector-take-while-right pred v) (%uvec-take-while-right 'c128 pred v))
    (define (c128vector-drop-while pred v) (%uvec-drop-while 'c128 pred v))
    (define (c128vector-drop-while-right pred v) (%uvec-drop-while-right 'c128 pred v))
    (define (c128vector-map f v . vs) (apply %uvec-map 'c128 f v vs))
    (define (c128vector-cumulate f knil v) (%uvec-cumulate 'c128 f knil v))
    (define (c128vector-filter pred v) (%uvec-filter 'c128 pred v))
    (define (c128vector-remove pred v) (%uvec-remove 'c128 pred v))
    (define (c128vector-partition pred v) (%uvec-partition 'c128 pred v))
    (define (reverse-list->c128vector lst) (%uvec-reverse-list-> 'c128 lst))
    (define (c128vector->vector v . args) (apply %uvec->vector v args))
    (define (vector->c128vector vec . args) (apply %uvec-vector-> 'c128 vec args))
    (define c128vector-comparator (%uvec-make-comparator 'c128))))
