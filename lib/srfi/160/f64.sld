;;; SRFI 160 -- (srfi 160 f64): f64vector library.
;;; Core 9 procedures + validity predicate come from (srfi 160 base)
;;; unchanged; the SRFI-133-shaped extended surface is that same base
;;; library's generic `%uvec-*` engine, renamed or kind-closed here.
(define-library (srfi 160 f64)
  (import (scheme base)
          (rename (srfi 160 base)
                  (%uvec-fold f64vector-fold)
                  (%uvec-fold-right f64vector-fold-right)
                  (%uvec-map! f64vector-map!)
                  (%uvec-for-each f64vector-for-each)
                  (%uvec-count f64vector-count)
                  (%uvec-index f64vector-index)
                  (%uvec-index-right f64vector-index-right)
                  (%uvec-skip f64vector-skip)
                  (%uvec-skip-right f64vector-skip-right)
                  (%uvec-any f64vector-any)
                  (%uvec-every f64vector-every)
                  (%uvec-empty? f64vector-empty?)
                  (%uvec= f64vector=)
                  (%uvec-swap! f64vector-swap!)
                  (%uvec-fill! f64vector-fill!)
                  (%uvec-reverse! f64vector-reverse!)
                  (%uvec-copy! f64vector-copy!)
                  (%uvec-reverse-copy! f64vector-reverse-copy!)
                  (%uvec-unfold! f64vector-unfold!)
                  (%uvec-unfold-right! f64vector-unfold-right!)
                  (%uvec-reverse->list reverse-f64vector->list)
                  (%uvec-generator make-f64vector-generator)
                  (%uvec-write write-f64vector)))
  (export make-f64vector f64vector f64vector? f64vector-length f64vector-ref f64vector-set!
          f64vector->list list->f64vector f64?
          f64vector-unfold f64vector-unfold-right f64vector-unfold! f64vector-unfold-right!
          f64vector-copy f64vector-reverse-copy f64vector-append f64vector-concatenate
          f64vector-append-subvectors
          f64vector-empty? f64vector=
          f64vector-take f64vector-take-right f64vector-drop f64vector-drop-right f64vector-segment
          f64vector-fold f64vector-fold-right f64vector-map f64vector-map! f64vector-for-each
          f64vector-count f64vector-cumulate
          f64vector-take-while f64vector-take-while-right f64vector-drop-while f64vector-drop-while-right
          f64vector-index f64vector-index-right f64vector-skip f64vector-skip-right
          f64vector-any f64vector-every
          f64vector-partition f64vector-filter f64vector-remove
          f64vector-swap! f64vector-fill! f64vector-reverse! f64vector-copy! f64vector-reverse-copy!
          reverse-f64vector->list reverse-list->f64vector
          f64vector->vector vector->f64vector
          make-f64vector-generator
          f64vector-comparator
          write-f64vector)
  (begin
    (define (f64vector-unfold f len . seeds) (apply %uvec-unfold 'f64 f len seeds))
    (define (f64vector-unfold-right f len . seeds) (apply %uvec-unfold-right 'f64 f len seeds))
    (define (f64vector-copy v . args) (apply %uvec-copy 'f64 v args))
    (define (f64vector-reverse-copy v . args) (apply %uvec-reverse-copy 'f64 v args))
    (define (f64vector-append . vs) (apply %uvec-append 'f64 vs))
    (define (f64vector-concatenate vs) (%uvec-concatenate 'f64 vs))
    (define (f64vector-append-subvectors . args) (apply %uvec-append-subvectors 'f64 args))
    (define (f64vector-take v n) (%uvec-take 'f64 v n))
    (define (f64vector-take-right v n) (%uvec-take-right 'f64 v n))
    (define (f64vector-drop v n) (%uvec-drop 'f64 v n))
    (define (f64vector-drop-right v n) (%uvec-drop-right 'f64 v n))
    (define (f64vector-segment v n) (%uvec-segment 'f64 v n))
    (define (f64vector-take-while pred v) (%uvec-take-while 'f64 pred v))
    (define (f64vector-take-while-right pred v) (%uvec-take-while-right 'f64 pred v))
    (define (f64vector-drop-while pred v) (%uvec-drop-while 'f64 pred v))
    (define (f64vector-drop-while-right pred v) (%uvec-drop-while-right 'f64 pred v))
    (define (f64vector-map f v . vs) (apply %uvec-map 'f64 f v vs))
    (define (f64vector-cumulate f knil v) (%uvec-cumulate 'f64 f knil v))
    (define (f64vector-filter pred v) (%uvec-filter 'f64 pred v))
    (define (f64vector-remove pred v) (%uvec-remove 'f64 pred v))
    (define (f64vector-partition pred v) (%uvec-partition 'f64 pred v))
    (define (reverse-list->f64vector lst) (%uvec-reverse-list-> 'f64 lst))
    (define (f64vector->vector v . args) (apply %uvec->vector v args))
    (define (vector->f64vector vec . args) (apply %uvec-vector-> 'f64 vec args))
    (define f64vector-comparator (%uvec-make-comparator 'f64))))
