;;; SRFI 231 -- Intervals and Generalized Arrays.
;;;
;;; Pure re-export hub over the 7 internal phase files this SRFI shipped
;;; across (issue #1694): misc, intervals, storage-classes, arrays, views,
;;; combinators, assembly -- same precedent as (srfi 4)'s thin re-export
;;; over (srfi 160 <tag>). Each phase file remains independently
;;; importable (e.g. code that only needs intervals can still
;;; `(import (srfi 231 intervals))` directly without pulling in the rest),
;;; but (srfi 231) itself is now, for the first time, a bare importable
;;; library exposing the SRFI's full 118-binding public surface.
;;;
;;; The only exclusions are 4 `%`-prefixed bindings in (srfi 231 arrays)
;;; (%make-array, %safe-getter, %safe-setter, %make-lex-indexer) --
;;; internal-only helpers for sibling files in this package to build
;;; custom-indexer specialized arrays, never part of SRFI 231's own
;;; spec surface (the same pattern as (srfi 160 base)'s %uvec-* helpers).
(define-library (srfi 231)
  (import (srfi 231 misc) (srfi 231 intervals) (srfi 231 storage-classes)
          (srfi 231 arrays) (srfi 231 views) (srfi 231 combinators)
          (srfi 231 assembly))
  (export
   ;; --- misc ---
   translation? permutation? index-rotate index-first index-last
   index-swap

   ;; --- intervals ---
   interval? make-interval interval-dimension interval-lower-bound
   interval-upper-bound interval-width interval-lower-bounds->list
   interval-upper-bounds->list interval-lower-bounds->vector
   interval-upper-bounds->vector interval-widths interval-volume
   interval-empty? interval= interval-subset?
   interval-contains-multi-index? interval-for-each interval-fold-left
   interval-fold-right interval-dilate interval-translate
   interval-permute interval-scale interval-intersect
   interval-cartesian-product interval-projections

   ;; --- storage-classes ---
   make-storage-class storage-class? storage-class-getter
   storage-class-setter storage-class-checker storage-class-maker
   storage-class-copier storage-class-length storage-class-default
   storage-class-data? storage-class-data->body generic-storage-class
   char-storage-class s8-storage-class s16-storage-class
   s32-storage-class s64-storage-class u1-storage-class
   u8-storage-class u16-storage-class u32-storage-class
   u64-storage-class f8-storage-class f16-storage-class
   f32-storage-class f64-storage-class c64-storage-class
   c128-storage-class

   ;; --- arrays ---
   array? mutable-array? specialized-array? make-array
   make-specialized-array make-specialized-array-from-data
   array-domain array-getter array-setter array-dimension array-ref
   array-set! array-freeze! array-empty? array-body array-indexer
   array-storage-class array-safe? array-packed?
   specialized-array-default-safe? specialized-array-default-mutable?

   ;; --- views ---
   specialized-array-share array-extract array-translate array-permute
   array-reverse array-curry array-tile array-sample array-copy
   array-copy! specialized-array-reshape

   ;; --- combinators ---
   array-map array-for-each array-fold-left array-fold-right
   array-reduce array-any array-every array-outer-product
   array-inner-product array->list list->array array->list*
   list*->array array->vector vector->array array->vector*
   vector*->array

   ;; --- assembly ---
   array-assign! array-stack array-stack! array-decurry array-decurry!
   array-append array-append! array-block array-block!))
