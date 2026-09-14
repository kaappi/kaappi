;;; SRFI 160 -- (srfi 160 f32): f32vector library.
;;; Core 9 procedures + validity predicate come from (srfi 160 base)
;;; unchanged; the SRFI-133-shaped extended surface is that same base
;;; library's generic `%uvec-*` engine, renamed or kind-closed here.
(define-library (srfi 160 f32)
  (import (scheme base)
          (rename (srfi 160 base)
                  (%uvec-fold f32vector-fold)
                  (%uvec-fold-right f32vector-fold-right)
                  (%uvec-map! f32vector-map!)
                  (%uvec-for-each f32vector-for-each)
                  (%uvec-count f32vector-count)
                  (%uvec-index f32vector-index)
                  (%uvec-index-right f32vector-index-right)
                  (%uvec-skip f32vector-skip)
                  (%uvec-skip-right f32vector-skip-right)
                  (%uvec-any f32vector-any)
                  (%uvec-every f32vector-every)
                  (%uvec-empty? f32vector-empty?)
                  (%uvec= f32vector=)
                  (%uvec-swap! f32vector-swap!)
                  (%uvec-fill! f32vector-fill!)
                  (%uvec-reverse! f32vector-reverse!)
                  (%uvec-copy! f32vector-copy!)
                  (%uvec-reverse-copy! f32vector-reverse-copy!)
                  (%uvec-unfold! f32vector-unfold!)
                  (%uvec-unfold-right! f32vector-unfold-right!)
                  (%uvec-reverse->list reverse-f32vector->list)
                  (%uvec-generator make-f32vector-generator)
                  (%uvec-write write-f32vector)))
  (export make-f32vector f32vector f32vector? f32vector-length f32vector-ref f32vector-set!
          f32vector->list list->f32vector f32?
          f32vector-unfold f32vector-unfold-right f32vector-unfold! f32vector-unfold-right!
          f32vector-copy f32vector-reverse-copy f32vector-append f32vector-concatenate
          f32vector-append-subvectors
          f32vector-empty? f32vector=
          f32vector-take f32vector-take-right f32vector-drop f32vector-drop-right f32vector-segment
          f32vector-fold f32vector-fold-right f32vector-map f32vector-map! f32vector-for-each
          f32vector-count f32vector-cumulate
          f32vector-take-while f32vector-take-while-right f32vector-drop-while f32vector-drop-while-right
          f32vector-index f32vector-index-right f32vector-skip f32vector-skip-right
          f32vector-any f32vector-every
          f32vector-partition f32vector-filter f32vector-remove
          f32vector-swap! f32vector-fill! f32vector-reverse! f32vector-copy! f32vector-reverse-copy!
          reverse-f32vector->list reverse-list->f32vector
          f32vector->vector vector->f32vector
          make-f32vector-generator
          f32vector-comparator
          write-f32vector)
  (begin
    (define (f32vector-unfold f len . seeds) (apply %uvec-unfold 'f32 f len seeds))
    (define (f32vector-unfold-right f len . seeds) (apply %uvec-unfold-right 'f32 f len seeds))
    (define (f32vector-copy v . args) (apply %uvec-copy 'f32 v args))
    (define (f32vector-reverse-copy v . args) (apply %uvec-reverse-copy 'f32 v args))
    (define (f32vector-append . vs) (apply %uvec-append 'f32 vs))
    (define (f32vector-concatenate vs) (%uvec-concatenate 'f32 vs))
    (define (f32vector-append-subvectors . args) (apply %uvec-append-subvectors 'f32 args))
    (define (f32vector-take v n) (%uvec-take 'f32 v n))
    (define (f32vector-take-right v n) (%uvec-take-right 'f32 v n))
    (define (f32vector-drop v n) (%uvec-drop 'f32 v n))
    (define (f32vector-drop-right v n) (%uvec-drop-right 'f32 v n))
    (define (f32vector-segment v n) (%uvec-segment 'f32 v n))
    (define (f32vector-take-while pred v) (%uvec-take-while 'f32 pred v))
    (define (f32vector-take-while-right pred v) (%uvec-take-while-right 'f32 pred v))
    (define (f32vector-drop-while pred v) (%uvec-drop-while 'f32 pred v))
    (define (f32vector-drop-while-right pred v) (%uvec-drop-while-right 'f32 pred v))
    (define (f32vector-map f v . vs) (apply %uvec-map 'f32 f v vs))
    (define (f32vector-cumulate f knil v) (%uvec-cumulate 'f32 f knil v))
    (define (f32vector-filter pred v) (%uvec-filter 'f32 pred v))
    (define (f32vector-remove pred v) (%uvec-remove 'f32 pred v))
    (define (f32vector-partition pred v) (%uvec-partition 'f32 pred v))
    (define (reverse-list->f32vector lst) (%uvec-reverse-list-> 'f32 lst))
    (define (f32vector->vector v . args) (apply %uvec->vector v args))
    (define (vector->f32vector vec . args) (apply %uvec-vector-> 'f32 vec args))
    (define f32vector-comparator (%uvec-make-comparator 'f32))))
