;;; SRFI 160 -- (srfi 160 s16): s16vector library.
;;; Core 9 procedures + validity predicate come from (srfi 160 base)
;;; unchanged; the SRFI-133-shaped extended surface is that same base
;;; library's generic `%uvec-*` engine, renamed or kind-closed here.
(define-library (srfi 160 s16)
  (import (scheme base)
          (rename (srfi 160 base)
                  (%uvec-fold s16vector-fold)
                  (%uvec-fold-right s16vector-fold-right)
                  (%uvec-map! s16vector-map!)
                  (%uvec-for-each s16vector-for-each)
                  (%uvec-count s16vector-count)
                  (%uvec-index s16vector-index)
                  (%uvec-index-right s16vector-index-right)
                  (%uvec-skip s16vector-skip)
                  (%uvec-skip-right s16vector-skip-right)
                  (%uvec-any s16vector-any)
                  (%uvec-every s16vector-every)
                  (%uvec-empty? s16vector-empty?)
                  (%uvec= s16vector=)
                  (%uvec-swap! s16vector-swap!)
                  (%uvec-fill! s16vector-fill!)
                  (%uvec-reverse! s16vector-reverse!)
                  (%uvec-copy! s16vector-copy!)
                  (%uvec-reverse-copy! s16vector-reverse-copy!)
                  (%uvec-unfold! s16vector-unfold!)
                  (%uvec-unfold-right! s16vector-unfold-right!)
                  (%uvec-reverse->list reverse-s16vector->list)
                  (%uvec-generator make-s16vector-generator)
                  (%uvec-write write-s16vector)))
  (export make-s16vector s16vector s16vector? s16vector-length s16vector-ref s16vector-set!
          s16vector->list list->s16vector s16?
          s16vector-unfold s16vector-unfold-right s16vector-unfold! s16vector-unfold-right!
          s16vector-copy s16vector-reverse-copy s16vector-append s16vector-concatenate
          s16vector-append-subvectors
          s16vector-empty? s16vector=
          s16vector-take s16vector-take-right s16vector-drop s16vector-drop-right s16vector-segment
          s16vector-fold s16vector-fold-right s16vector-map s16vector-map! s16vector-for-each
          s16vector-count s16vector-cumulate
          s16vector-take-while s16vector-take-while-right s16vector-drop-while s16vector-drop-while-right
          s16vector-index s16vector-index-right s16vector-skip s16vector-skip-right
          s16vector-any s16vector-every
          s16vector-partition s16vector-filter s16vector-remove
          s16vector-swap! s16vector-fill! s16vector-reverse! s16vector-copy! s16vector-reverse-copy!
          reverse-s16vector->list reverse-list->s16vector
          s16vector->vector vector->s16vector
          make-s16vector-generator
          s16vector-comparator
          write-s16vector)
  (begin
    (define (s16vector-unfold f len . seeds) (apply %uvec-unfold 's16 f len seeds))
    (define (s16vector-unfold-right f len . seeds) (apply %uvec-unfold-right 's16 f len seeds))
    (define (s16vector-copy v . args) (apply %uvec-copy 's16 v args))
    (define (s16vector-reverse-copy v . args) (apply %uvec-reverse-copy 's16 v args))
    (define (s16vector-append . vs) (apply %uvec-append 's16 vs))
    (define (s16vector-concatenate vs) (%uvec-concatenate 's16 vs))
    (define (s16vector-append-subvectors . args) (apply %uvec-append-subvectors 's16 args))
    (define (s16vector-take v n) (%uvec-take 's16 v n))
    (define (s16vector-take-right v n) (%uvec-take-right 's16 v n))
    (define (s16vector-drop v n) (%uvec-drop 's16 v n))
    (define (s16vector-drop-right v n) (%uvec-drop-right 's16 v n))
    (define (s16vector-segment v n) (%uvec-segment 's16 v n))
    (define (s16vector-take-while pred v) (%uvec-take-while 's16 pred v))
    (define (s16vector-take-while-right pred v) (%uvec-take-while-right 's16 pred v))
    (define (s16vector-drop-while pred v) (%uvec-drop-while 's16 pred v))
    (define (s16vector-drop-while-right pred v) (%uvec-drop-while-right 's16 pred v))
    (define (s16vector-map f v . vs) (apply %uvec-map 's16 f v vs))
    (define (s16vector-cumulate f knil v) (%uvec-cumulate 's16 f knil v))
    (define (s16vector-filter pred v) (%uvec-filter 's16 pred v))
    (define (s16vector-remove pred v) (%uvec-remove 's16 pred v))
    (define (s16vector-partition pred v) (%uvec-partition 's16 pred v))
    (define (reverse-list->s16vector lst) (%uvec-reverse-list-> 's16 lst))
    (define (s16vector->vector v . args) (apply %uvec->vector v args))
    (define (vector->s16vector vec . args) (apply %uvec-vector-> 's16 vec args))
    (define s16vector-comparator (%uvec-make-comparator 's16))))
