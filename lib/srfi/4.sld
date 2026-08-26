;;; SRFI 4 — Homogeneous numeric vector datatypes.
;;; Thin re-export over the (srfi 160 <tag>) substrate: same 8-procedure
;;; public API as before, now backed by the native NumericVector heap type
;;; (correct f32 truncation, consistent range-checking) instead of a
;;; bytevector/vector-wrapping record type. SRFI 4's own surface is all
;;; TEN kinds (u8/s8/u16/s16/u32/s32/u64/s64/f32/f64) -- the u64/s64 pair
;;; was missing from this hub (kaappi#2361), so a legal (import (srfi 4))
;;; program failed on u64vector/s64vector even though the substrate
;;; libraries existed all along.
(define-library (srfi 4)
  (import (srfi 160 u8) (srfi 160 s8) (srfi 160 u16) (srfi 160 s16)
          (srfi 160 u32) (srfi 160 s32) (srfi 160 u64) (srfi 160 s64)
          (srfi 160 f32) (srfi 160 f64))
  (export u8vector? make-u8vector u8vector u8vector-length
          u8vector-ref u8vector-set! u8vector->list list->u8vector
          s8vector? make-s8vector s8vector s8vector-length
          s8vector-ref s8vector-set! s8vector->list list->s8vector
          u16vector? make-u16vector u16vector u16vector-length
          u16vector-ref u16vector-set! u16vector->list list->u16vector
          s16vector? make-s16vector s16vector s16vector-length
          s16vector-ref s16vector-set! s16vector->list list->s16vector
          u32vector? make-u32vector u32vector u32vector-length
          u32vector-ref u32vector-set! u32vector->list list->u32vector
          s32vector? make-s32vector s32vector s32vector-length
          s32vector-ref s32vector-set! s32vector->list list->s32vector
          u64vector? make-u64vector u64vector u64vector-length
          u64vector-ref u64vector-set! u64vector->list list->u64vector
          s64vector? make-s64vector s64vector s64vector-length
          s64vector-ref s64vector-set! s64vector->list list->s64vector
          f32vector? make-f32vector f32vector f32vector-length
          f32vector-ref f32vector-set! f32vector->list list->f32vector
          f64vector? make-f64vector f64vector f64vector-length
          f64vector-ref f64vector-set! f64vector->list list->f64vector))
