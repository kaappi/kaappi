;;; SRFI 160 -- (srfi 160 s64): s64vector library.
;;; Core 9 procedures + validity predicate come from (srfi 160 base)
;;; unchanged; the SRFI-133-shaped extended surface is that same base
;;; library's generic `%uvec-*` engine, renamed or kind-closed here.
(define-library (srfi 160 s64)
  (import (scheme base)
          (rename (srfi 160 base)
                  (%uvec-fold s64vector-fold)
                  (%uvec-fold-right s64vector-fold-right)
                  (%uvec-map! s64vector-map!)
                  (%uvec-for-each s64vector-for-each)
                  (%uvec-count s64vector-count)
                  (%uvec-index s64vector-index)
                  (%uvec-index-right s64vector-index-right)
                  (%uvec-skip s64vector-skip)
                  (%uvec-skip-right s64vector-skip-right)
                  (%uvec-any s64vector-any)
                  (%uvec-every s64vector-every)
                  (%uvec-empty? s64vector-empty?)
                  (%uvec= s64vector=)
                  (%uvec-swap! s64vector-swap!)
                  (%uvec-fill! s64vector-fill!)
                  (%uvec-reverse! s64vector-reverse!)
                  (%uvec-copy! s64vector-copy!)
                  (%uvec-reverse-copy! s64vector-reverse-copy!)
                  (%uvec-unfold! s64vector-unfold!)
                  (%uvec-unfold-right! s64vector-unfold-right!)
                  (%uvec-reverse->list reverse-s64vector->list)
                  (%uvec-generator make-s64vector-generator)
                  (%uvec-write write-s64vector)))
  (export make-s64vector s64vector s64vector? s64vector-length s64vector-ref s64vector-set!
          s64vector->list list->s64vector s64?
          s64vector-unfold s64vector-unfold-right s64vector-unfold! s64vector-unfold-right!
          s64vector-copy s64vector-reverse-copy s64vector-append s64vector-concatenate
          s64vector-append-subvectors
          s64vector-empty? s64vector=
          s64vector-take s64vector-take-right s64vector-drop s64vector-drop-right s64vector-segment
          s64vector-fold s64vector-fold-right s64vector-map s64vector-map! s64vector-for-each
          s64vector-count s64vector-cumulate
          s64vector-take-while s64vector-take-while-right s64vector-drop-while s64vector-drop-while-right
          s64vector-index s64vector-index-right s64vector-skip s64vector-skip-right
          s64vector-any s64vector-every
          s64vector-partition s64vector-filter s64vector-remove
          s64vector-swap! s64vector-fill! s64vector-reverse! s64vector-copy! s64vector-reverse-copy!
          reverse-s64vector->list reverse-list->s64vector
          s64vector->vector vector->s64vector
          make-s64vector-generator
          s64vector-comparator
          write-s64vector)
  (begin
    (define (s64vector-unfold f len . seeds) (apply %uvec-unfold 's64 f len seeds))
    (define (s64vector-unfold-right f len . seeds) (apply %uvec-unfold-right 's64 f len seeds))
    (define (s64vector-copy v . args) (apply %uvec-copy 's64 v args))
    (define (s64vector-reverse-copy v . args) (apply %uvec-reverse-copy 's64 v args))
    (define (s64vector-append . vs) (apply %uvec-append 's64 vs))
    (define (s64vector-concatenate vs) (%uvec-concatenate 's64 vs))
    (define (s64vector-append-subvectors . args) (apply %uvec-append-subvectors 's64 args))
    (define (s64vector-take v n) (%uvec-take 's64 v n))
    (define (s64vector-take-right v n) (%uvec-take-right 's64 v n))
    (define (s64vector-drop v n) (%uvec-drop 's64 v n))
    (define (s64vector-drop-right v n) (%uvec-drop-right 's64 v n))
    (define (s64vector-segment v n) (%uvec-segment 's64 v n))
    (define (s64vector-take-while pred v) (%uvec-take-while 's64 pred v))
    (define (s64vector-take-while-right pred v) (%uvec-take-while-right 's64 pred v))
    (define (s64vector-drop-while pred v) (%uvec-drop-while 's64 pred v))
    (define (s64vector-drop-while-right pred v) (%uvec-drop-while-right 's64 pred v))
    (define (s64vector-map f v . vs) (apply %uvec-map 's64 f v vs))
    (define (s64vector-cumulate f knil v) (%uvec-cumulate 's64 f knil v))
    (define (s64vector-filter pred v) (%uvec-filter 's64 pred v))
    (define (s64vector-remove pred v) (%uvec-remove 's64 pred v))
    (define (s64vector-partition pred v) (%uvec-partition 's64 pred v))
    (define (reverse-list->s64vector lst) (%uvec-reverse-list-> 's64 lst))
    (define (s64vector->vector v . args) (apply %uvec->vector v args))
    (define (vector->s64vector vec . args) (apply %uvec-vector-> 's64 vec args))
    (define s64vector-comparator (%uvec-make-comparator 's64))))
