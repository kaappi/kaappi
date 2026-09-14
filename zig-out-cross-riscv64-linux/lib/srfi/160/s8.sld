;;; SRFI 160 -- (srfi 160 s8): s8vector library.
;;; Core 9 procedures + validity predicate come from (srfi 160 base)
;;; unchanged; the SRFI-133-shaped extended surface is that same base
;;; library's generic `%uvec-*` engine, renamed or kind-closed here.
(define-library (srfi 160 s8)
  (import (scheme base)
          (rename (srfi 160 base)
                  (%uvec-fold s8vector-fold)
                  (%uvec-fold-right s8vector-fold-right)
                  (%uvec-map! s8vector-map!)
                  (%uvec-for-each s8vector-for-each)
                  (%uvec-count s8vector-count)
                  (%uvec-index s8vector-index)
                  (%uvec-index-right s8vector-index-right)
                  (%uvec-skip s8vector-skip)
                  (%uvec-skip-right s8vector-skip-right)
                  (%uvec-any s8vector-any)
                  (%uvec-every s8vector-every)
                  (%uvec-empty? s8vector-empty?)
                  (%uvec= s8vector=)
                  (%uvec-swap! s8vector-swap!)
                  (%uvec-fill! s8vector-fill!)
                  (%uvec-reverse! s8vector-reverse!)
                  (%uvec-copy! s8vector-copy!)
                  (%uvec-reverse-copy! s8vector-reverse-copy!)
                  (%uvec-unfold! s8vector-unfold!)
                  (%uvec-unfold-right! s8vector-unfold-right!)
                  (%uvec-reverse->list reverse-s8vector->list)
                  (%uvec-generator make-s8vector-generator)
                  (%uvec-write write-s8vector)))
  (export make-s8vector s8vector s8vector? s8vector-length s8vector-ref s8vector-set!
          s8vector->list list->s8vector s8?
          s8vector-unfold s8vector-unfold-right s8vector-unfold! s8vector-unfold-right!
          s8vector-copy s8vector-reverse-copy s8vector-append s8vector-concatenate
          s8vector-append-subvectors
          s8vector-empty? s8vector=
          s8vector-take s8vector-take-right s8vector-drop s8vector-drop-right s8vector-segment
          s8vector-fold s8vector-fold-right s8vector-map s8vector-map! s8vector-for-each
          s8vector-count s8vector-cumulate
          s8vector-take-while s8vector-take-while-right s8vector-drop-while s8vector-drop-while-right
          s8vector-index s8vector-index-right s8vector-skip s8vector-skip-right
          s8vector-any s8vector-every
          s8vector-partition s8vector-filter s8vector-remove
          s8vector-swap! s8vector-fill! s8vector-reverse! s8vector-copy! s8vector-reverse-copy!
          reverse-s8vector->list reverse-list->s8vector
          s8vector->vector vector->s8vector
          make-s8vector-generator
          s8vector-comparator
          write-s8vector)
  (begin
    (define (s8vector-unfold f len . seeds) (apply %uvec-unfold 's8 f len seeds))
    (define (s8vector-unfold-right f len . seeds) (apply %uvec-unfold-right 's8 f len seeds))
    (define (s8vector-copy v . args) (apply %uvec-copy 's8 v args))
    (define (s8vector-reverse-copy v . args) (apply %uvec-reverse-copy 's8 v args))
    (define (s8vector-append . vs) (apply %uvec-append 's8 vs))
    (define (s8vector-concatenate vs) (%uvec-concatenate 's8 vs))
    (define (s8vector-append-subvectors . args) (apply %uvec-append-subvectors 's8 args))
    (define (s8vector-take v n) (%uvec-take 's8 v n))
    (define (s8vector-take-right v n) (%uvec-take-right 's8 v n))
    (define (s8vector-drop v n) (%uvec-drop 's8 v n))
    (define (s8vector-drop-right v n) (%uvec-drop-right 's8 v n))
    (define (s8vector-segment v n) (%uvec-segment 's8 v n))
    (define (s8vector-take-while pred v) (%uvec-take-while 's8 pred v))
    (define (s8vector-take-while-right pred v) (%uvec-take-while-right 's8 pred v))
    (define (s8vector-drop-while pred v) (%uvec-drop-while 's8 pred v))
    (define (s8vector-drop-while-right pred v) (%uvec-drop-while-right 's8 pred v))
    (define (s8vector-map f v . vs) (apply %uvec-map 's8 f v vs))
    (define (s8vector-cumulate f knil v) (%uvec-cumulate 's8 f knil v))
    (define (s8vector-filter pred v) (%uvec-filter 's8 pred v))
    (define (s8vector-remove pred v) (%uvec-remove 's8 pred v))
    (define (s8vector-partition pred v) (%uvec-partition 's8 pred v))
    (define (reverse-list->s8vector lst) (%uvec-reverse-list-> 's8 lst))
    (define (s8vector->vector v . args) (apply %uvec->vector v args))
    (define (vector->s8vector vec . args) (apply %uvec-vector-> 's8 vec args))
    (define s8vector-comparator (%uvec-make-comparator 's8))))
