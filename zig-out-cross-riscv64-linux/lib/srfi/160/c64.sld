;;; SRFI 160 -- (srfi 160 c64): c64vector library.
;;; Core 9 procedures + validity predicate come from (srfi 160 base)
;;; unchanged; the SRFI-133-shaped extended surface is that same base
;;; library's generic `%uvec-*` engine, renamed or kind-closed here.
(define-library (srfi 160 c64)
  (import (scheme base)
          (rename (srfi 160 base)
                  (%uvec-fold c64vector-fold)
                  (%uvec-fold-right c64vector-fold-right)
                  (%uvec-map! c64vector-map!)
                  (%uvec-for-each c64vector-for-each)
                  (%uvec-count c64vector-count)
                  (%uvec-index c64vector-index)
                  (%uvec-index-right c64vector-index-right)
                  (%uvec-skip c64vector-skip)
                  (%uvec-skip-right c64vector-skip-right)
                  (%uvec-any c64vector-any)
                  (%uvec-every c64vector-every)
                  (%uvec-empty? c64vector-empty?)
                  (%uvec= c64vector=)
                  (%uvec-swap! c64vector-swap!)
                  (%uvec-fill! c64vector-fill!)
                  (%uvec-reverse! c64vector-reverse!)
                  (%uvec-copy! c64vector-copy!)
                  (%uvec-reverse-copy! c64vector-reverse-copy!)
                  (%uvec-unfold! c64vector-unfold!)
                  (%uvec-unfold-right! c64vector-unfold-right!)
                  (%uvec-reverse->list reverse-c64vector->list)
                  (%uvec-generator make-c64vector-generator)
                  (%uvec-write write-c64vector)))
  (export make-c64vector c64vector c64vector? c64vector-length c64vector-ref c64vector-set!
          c64vector->list list->c64vector c64?
          c64vector-unfold c64vector-unfold-right c64vector-unfold! c64vector-unfold-right!
          c64vector-copy c64vector-reverse-copy c64vector-append c64vector-concatenate
          c64vector-append-subvectors
          c64vector-empty? c64vector=
          c64vector-take c64vector-take-right c64vector-drop c64vector-drop-right c64vector-segment
          c64vector-fold c64vector-fold-right c64vector-map c64vector-map! c64vector-for-each
          c64vector-count c64vector-cumulate
          c64vector-take-while c64vector-take-while-right c64vector-drop-while c64vector-drop-while-right
          c64vector-index c64vector-index-right c64vector-skip c64vector-skip-right
          c64vector-any c64vector-every
          c64vector-partition c64vector-filter c64vector-remove
          c64vector-swap! c64vector-fill! c64vector-reverse! c64vector-copy! c64vector-reverse-copy!
          reverse-c64vector->list reverse-list->c64vector
          c64vector->vector vector->c64vector
          make-c64vector-generator
          c64vector-comparator
          write-c64vector)
  (begin
    (define (c64vector-unfold f len . seeds) (apply %uvec-unfold 'c64 f len seeds))
    (define (c64vector-unfold-right f len . seeds) (apply %uvec-unfold-right 'c64 f len seeds))
    (define (c64vector-copy v . args) (apply %uvec-copy 'c64 v args))
    (define (c64vector-reverse-copy v . args) (apply %uvec-reverse-copy 'c64 v args))
    (define (c64vector-append . vs) (apply %uvec-append 'c64 vs))
    (define (c64vector-concatenate vs) (%uvec-concatenate 'c64 vs))
    (define (c64vector-append-subvectors . args) (apply %uvec-append-subvectors 'c64 args))
    (define (c64vector-take v n) (%uvec-take 'c64 v n))
    (define (c64vector-take-right v n) (%uvec-take-right 'c64 v n))
    (define (c64vector-drop v n) (%uvec-drop 'c64 v n))
    (define (c64vector-drop-right v n) (%uvec-drop-right 'c64 v n))
    (define (c64vector-segment v n) (%uvec-segment 'c64 v n))
    (define (c64vector-take-while pred v) (%uvec-take-while 'c64 pred v))
    (define (c64vector-take-while-right pred v) (%uvec-take-while-right 'c64 pred v))
    (define (c64vector-drop-while pred v) (%uvec-drop-while 'c64 pred v))
    (define (c64vector-drop-while-right pred v) (%uvec-drop-while-right 'c64 pred v))
    (define (c64vector-map f v . vs) (apply %uvec-map 'c64 f v vs))
    (define (c64vector-cumulate f knil v) (%uvec-cumulate 'c64 f knil v))
    (define (c64vector-filter pred v) (%uvec-filter 'c64 pred v))
    (define (c64vector-remove pred v) (%uvec-remove 'c64 pred v))
    (define (c64vector-partition pred v) (%uvec-partition 'c64 pred v))
    (define (reverse-list->c64vector lst) (%uvec-reverse-list-> 'c64 lst))
    (define (c64vector->vector v . args) (apply %uvec->vector v args))
    (define (vector->c64vector vec . args) (apply %uvec-vector-> 'c64 vec args))
    (define c64vector-comparator (%uvec-make-comparator 'c64))))
