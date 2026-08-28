;;; SRFI 274 / SRFI 160 base — (srfi 274 160 base): extended
;;; list-><type>vector for all twelve homogeneous vector kinds.
;;;
;;; See lib/srfi/274/base.sld for the shared start/end contract. The
;;; per-kind libraries (srfi 274 160 u8) etc. re-export their single
;;; conversion from here, mirroring the (srfi 160 <type>) layout.
;;;
;;; Port note: the reference implementation builds the bounded vector with
;;; <type>vector-unfold to avoid an intermediate list. This port instead
;;; hands the bounded, always-proper range produced by (srfi 274 base)'s
;;; list-copy to the underlying one-argument converter — same result, one
;;; intermediate list, and it keeps the library from importing all twelve
;;; full (srfi 160 <type>) surfaces just for their unfold.
;;;
;;; Reference: https://srfi.schemers.org/srfi-274/srfi-274.html
;;; License: MIT
;;; Author: Peter McGoron (reference implementation); ported to Kaappi.
(define-library (srfi 274 160 base)
  (import (except (scheme base) list-copy)
          (scheme case-lambda)
          (srfi 274 internal)
          (only (srfi 274 base) list-copy)
          (prefix (only (srfi 160 base)
                        list->s8vector
                        list->u8vector
                        list->s16vector
                        list->u16vector
                        list->s32vector
                        list->u32vector
                        list->s64vector
                        list->u64vector
                        list->f32vector
                        list->f64vector
                        list->c64vector
                        list->c128vector)
                  srfi-160:))
  (export list->s8vector
          list->u8vector
          list->s16vector
          list->u16vector
          list->s32vector
          list->u32vector
          list->s64vector
          list->u64vector
          list->f32vector
          list->f64vector
          list->c64vector
          list->c128vector)
  (begin
    (define (converter who basic)
      (case-lambda
        ((lst) (basic lst))
        ((lst start) (basic (list-tail lst start)))
        ((lst start end)
         (argcheck! who start end lst)
         (basic (list-copy lst start end)))))

    (define list->s8vector   (converter 'list->s8vector   srfi-160:list->s8vector))
    (define list->u8vector   (converter 'list->u8vector   srfi-160:list->u8vector))
    (define list->s16vector  (converter 'list->s16vector  srfi-160:list->s16vector))
    (define list->u16vector  (converter 'list->u16vector  srfi-160:list->u16vector))
    (define list->s32vector  (converter 'list->s32vector  srfi-160:list->s32vector))
    (define list->u32vector  (converter 'list->u32vector  srfi-160:list->u32vector))
    (define list->s64vector  (converter 'list->s64vector  srfi-160:list->s64vector))
    (define list->u64vector  (converter 'list->u64vector  srfi-160:list->u64vector))
    (define list->f32vector  (converter 'list->f32vector  srfi-160:list->f32vector))
    (define list->f64vector  (converter 'list->f64vector  srfi-160:list->f64vector))
    (define list->c64vector  (converter 'list->c64vector  srfi-160:list->c64vector))
    (define list->c128vector (converter 'list->c128vector srfi-160:list->c128vector))))
