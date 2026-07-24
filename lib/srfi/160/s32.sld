;;; SRFI 160 -- (srfi 160 s32): s32vector library.
;;; Core 9 procedures + validity predicate come from (srfi 160 base)
;;; unchanged; the SRFI-133-shaped extended surface is that same base
;;; library's generic `%uvec-*` engine, renamed or kind-closed here.
(define-library (srfi 160 s32)
  (import (scheme base)
          (rename (srfi 160 base)
                  (%uvec-fold s32vector-fold)
                  (%uvec-fold-right s32vector-fold-right)
                  (%uvec-map! s32vector-map!)
                  (%uvec-for-each s32vector-for-each)
                  (%uvec-count s32vector-count)
                  (%uvec-index s32vector-index)
                  (%uvec-index-right s32vector-index-right)
                  (%uvec-skip s32vector-skip)
                  (%uvec-skip-right s32vector-skip-right)
                  (%uvec-any s32vector-any)
                  (%uvec-every s32vector-every)
                  (%uvec-empty? s32vector-empty?)
                  (%uvec= s32vector=)
                  (%uvec-swap! s32vector-swap!)
                  (%uvec-fill! s32vector-fill!)
                  (%uvec-reverse! s32vector-reverse!)
                  (%uvec-copy! s32vector-copy!)
                  (%uvec-reverse-copy! s32vector-reverse-copy!)
                  (%uvec-unfold! s32vector-unfold!)
                  (%uvec-unfold-right! s32vector-unfold-right!)
                  (%uvec-reverse->list reverse-s32vector->list)
                  (%uvec-generator make-s32vector-generator)
                  (%uvec-write write-s32vector)))
  (export make-s32vector s32vector s32vector? s32vector-length s32vector-ref s32vector-set!
          s32vector->list list->s32vector s32?
          s32vector-unfold s32vector-unfold-right s32vector-unfold! s32vector-unfold-right!
          s32vector-copy s32vector-reverse-copy s32vector-append s32vector-concatenate
          s32vector-append-subvectors
          s32vector-empty? s32vector=
          s32vector-take s32vector-take-right s32vector-drop s32vector-drop-right s32vector-segment
          s32vector-fold s32vector-fold-right s32vector-map s32vector-map! s32vector-for-each
          s32vector-count s32vector-cumulate
          s32vector-take-while s32vector-take-while-right s32vector-drop-while s32vector-drop-while-right
          s32vector-index s32vector-index-right s32vector-skip s32vector-skip-right
          s32vector-any s32vector-every
          s32vector-partition s32vector-filter s32vector-remove
          s32vector-swap! s32vector-fill! s32vector-reverse! s32vector-copy! s32vector-reverse-copy!
          reverse-s32vector->list reverse-list->s32vector
          s32vector->vector vector->s32vector
          make-s32vector-generator
          s32vector-comparator
          write-s32vector)
  (begin
    (define (s32vector-unfold f len . seeds) (apply %uvec-unfold 's32 f len seeds))
    (define (s32vector-unfold-right f len . seeds) (apply %uvec-unfold-right 's32 f len seeds))
    (define (s32vector-copy v . args) (apply %uvec-copy 's32 v args))
    (define (s32vector-reverse-copy v . args) (apply %uvec-reverse-copy 's32 v args))
    (define (s32vector-append . vs) (apply %uvec-append 's32 vs))
    (define (s32vector-concatenate vs) (%uvec-concatenate 's32 vs))
    (define (s32vector-append-subvectors . args) (apply %uvec-append-subvectors 's32 args))
    (define (s32vector-take v n) (%uvec-take 's32 v n))
    (define (s32vector-take-right v n) (%uvec-take-right 's32 v n))
    (define (s32vector-drop v n) (%uvec-drop 's32 v n))
    (define (s32vector-drop-right v n) (%uvec-drop-right 's32 v n))
    (define (s32vector-segment v n) (%uvec-segment 's32 v n))
    (define (s32vector-take-while pred v) (%uvec-take-while 's32 pred v))
    (define (s32vector-take-while-right pred v) (%uvec-take-while-right 's32 pred v))
    (define (s32vector-drop-while pred v) (%uvec-drop-while 's32 pred v))
    (define (s32vector-drop-while-right pred v) (%uvec-drop-while-right 's32 pred v))
    (define (s32vector-map f v . vs) (apply %uvec-map 's32 f v vs))
    (define (s32vector-cumulate f knil v) (%uvec-cumulate 's32 f knil v))
    (define (s32vector-filter pred v) (%uvec-filter 's32 pred v))
    (define (s32vector-remove pred v) (%uvec-remove 's32 pred v))
    (define (s32vector-partition pred v) (%uvec-partition 's32 pred v))
    (define (reverse-list->s32vector lst) (%uvec-reverse-list-> 's32 lst))
    (define (s32vector->vector v . args) (apply %uvec->vector v args))
    (define (vector->s32vector vec . args) (apply %uvec-vector-> 's32 vec args))
    (define s32vector-comparator (%uvec-make-comparator 's32))))
