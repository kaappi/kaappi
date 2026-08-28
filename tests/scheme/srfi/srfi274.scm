;; SRFI-274 (extended list conversion procedures) conformance tests.
;;
;; Covers the three base conversions (list-copy, list->string,
;; list->vector), the collection conversions (list->stream, list->ideque,
;; list->generator) and all twelve list-><type>vector conversions, each
;; with range arguments, dotted lists, circular lists (bounded by `end`)
;; and the error cases. Adapted from the SRFI's official tests.scm (Peter
;; McGoron, MIT), extended with the error-case coverage and sub-library
;; availability checks.
;;
;; The extended conversions deliberately shadow the (scheme base) /
;; underlying-library names, so every original library is imported with
;; `except` for the name its (srfi 274 ...) counterpart replaces (R7RS 5.2
;; forbids importing one identifier with two different bindings).
;;
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi274.scm

(import (except (scheme base) list-copy list->string list->vector)
        (scheme write)
        ;; The bare (srfi 274) alias re-exports the same bindings as
        ;; (srfi 274 base), so loading both side by side is legal (R7RS 5.2)
        ;; and actually exercises the alias's import/export wiring —
        ;; cond-expand's (library ...) clause only probes existence.
        (srfi 274)
        (srfi 274 base)
        (except (srfi 41) list->stream) (srfi 274 41)
        (except (srfi 134) list->ideque) (srfi 274 134)
        (except (srfi 158) list->generator) (srfi 274 158)
        ;; All twelve homogeneous vector kinds: the underlying
        ;; (srfi 160 <type>) for <type>vector->list (with the conversion
        ;; name excepted), the extended conversion from (srfi 274 160
        ;; base), and the per-type re-export libraries to prove they carry
        ;; the same binding as the base.
        (except (srfi 160 s8) list->s8vector)
        (except (srfi 160 u8) list->u8vector)
        (except (srfi 160 s16) list->s16vector)
        (except (srfi 160 u16) list->u16vector)
        (except (srfi 160 s32) list->s32vector)
        (except (srfi 160 u32) list->u32vector)
        (except (srfi 160 s64) list->s64vector)
        (except (srfi 160 u64) list->u64vector)
        (except (srfi 160 f32) list->f32vector)
        (except (srfi 160 f64) list->f64vector)
        (except (srfi 160 c64) list->c64vector)
        (except (srfi 160 c128) list->c128vector)
        (srfi 274 160 base)
        (srfi 274 160 s8) (srfi 274 160 u8) (srfi 274 160 s16)
        (srfi 274 160 u16) (srfi 274 160 s32) (srfi 274 160 u32)
        (srfi 274 160 s64) (srfi 274 160 u64) (srfi 274 160 f32)
        (srfi 274 160 f64) (srfi 274 160 c64) (srfi 274 160 c128)
        (prefix (only (srfi 274 160 u8) list->u8vector) u8lib:)
        (srfi 64))

(test-begin "srfi-274")

(define clist '#1= (1 2 . #1#))

;;; ====================================================================
;;; Availability: the cond-expand feature id and every sub-library.
;;; ====================================================================

(test-equal "cond-expand srfi-274" #t (cond-expand (srfi-274 #t) (else #f)))
(test-equal "library (srfi 274)" #t (cond-expand ((library (srfi 274)) #t) (else #f)))
(test-equal "library (srfi 274 base)" #t (cond-expand ((library (srfi 274 base)) #t) (else #f)))
(test-equal "library (srfi 274 41)" #t (cond-expand ((library (srfi 274 41)) #t) (else #f)))
(test-equal "library (srfi 274 134)" #t (cond-expand ((library (srfi 274 134)) #t) (else #f)))
(test-equal "library (srfi 274 158)" #t (cond-expand ((library (srfi 274 158)) #t) (else #f)))
(test-equal "library (srfi 274 160 base)" #t
            (cond-expand ((library (srfi 274 160 base)) #t) (else #f)))
(test-equal "library (srfi 274 160 u8)" #t
            (cond-expand ((library (srfi 274 160 u8)) #t) (else #f)))

;;; The per-type libraries carry the same binding as (srfi 274 160 base):
;;; u8lib:list->u8vector is the prefixed import from (srfi 274 160 u8),
;;; list->u8vector the plain one from (srfi 274 160 base) — the identical
;;; procedure object, which is also why importing both is legal (R7RS 5.2).
(test-assert "per-type library carries base's binding"
             (eqv? u8lib:list->u8vector list->u8vector))

;;; ====================================================================
;;; list-copy
;;; ====================================================================

(test-group "list-copy"
  (test-equal "on proper list" '(1 2 3 4 5) (list-copy '(1 2 3 4 5)))
  (test-equal "on improper list" '(1 2 3 4 5 . 6) (list-copy '(1 2 3 4 5 . 6)))
  (test-equal "on object" 10 (list-copy 10))
  (test-equal "start on proper list" '(3 4 5) (list-copy '(1 2 3 4 5) 2))
  (test-equal "start and end on proper list, 1" '(3 4) (list-copy '(1 2 3 4 5) 2 4))
  (test-equal "start and end on proper list, 2" '(3 4 5) (list-copy '(1 2 3 4 5) 2 5))
  (test-equal "start on improper list" '(3 4 5 . 6) (list-copy '(1 2 3 4 5 . 6) 2))
  (test-equal "start and end on improper list" '(3 4 5) (list-copy '(1 2 3 4 5 . 6) 2 5))
  (test-equal "start is length" 6 (list-copy '(1 2 3 4 5 . 6) 5))
  (test-equal "start and end are length" '() (list-copy '(1 2 3 4 5 . 6) 5 5))
  (test-equal "start and end on circular list" '(2 1 2 1 2 1 2) (list-copy clist 1 8))
  ;; start+end always yields a proper list, even from a circular input.
  (test-assert "start+end result is proper on circular input"
               (list? (list-copy clist 0 11)))
  ;; Fresh pairs, shared cars: mutating the copy leaves the original alone,
  ;; and the cars are the very same objects as the original's.
  (let* ((a (vector 'first))
         (b (vector 'second))
         (orig (list a b))
         (copy (list-copy orig)))
    (set-car! copy 'z)
    (test-equal "copy is fresh" (list a b) orig)
    (test-assert "cars are shared" (eq? (cadr copy) b)))
  ;; An improper copy terminates in the *same* tail object, not a rebuilt
  ;; one — for the wholesale copy and the start-only copy alike.
  (test-assert "dotted tail shared, not rebuilt"
               (let* ((tail (vector 'tail))
                      (dotted (cons 1 (cons 2 (cons 3 tail)))))
                 (and (eq? (cdddr (list-copy dotted)) tail)
                      (eq? (cdr (list-copy dotted 2)) tail))))
  (test-error "circular list without end is an error" (list-copy clist))
  (test-error "start past end of list" (list-copy '(1 2 3) 4))
  (test-error "end past start on arguments" (list-copy '(1 2 3) 3 2))
  (test-error "end beyond length" (list-copy '(1 2 3) 0 4))
  (test-error "negative start" (list-copy '(1 2 3) -1 2))
  (test-error "inexact start" (list-copy '(1 2 3) 0.0 2))
  (test-error "inexact end" (list-copy '(1 2 3) 0 2.0))
  (test-error "four arguments" (list-copy '(1 2 3) 0 1 2)))

;;; ====================================================================
;;; list->string
;;; ====================================================================

(test-group "list->string"
  (test-equal "on proper list" "asdfg" (list->string '(#\a #\s #\d #\f #\g)))
  (test-equal "start on proper list" "dfg" (list->string '(#\a #\s #\d #\f #\g) 2))
  (test-equal "start and end on proper list, 1" "df"
              (list->string '(#\a #\s #\d #\f #\g) 2 4))
  (test-equal "start and end on proper list" "dfg"
              (list->string '(#\a #\s #\d #\f #\g) 2 5))
  (test-equal "start and end on improper list" "dfg"
              (list->string '(#\a #\s #\d #\f #\g . #\h) 2 5))
  (test-equal "start is length" "" (list->string '(#\a #\b #\c #\d #\e) 5))
  (test-equal "start and end are length" "" (list->string '(#\a #\b #\c #\d #\e) 5 5))
  (test-equal "start and end on circular list" "2121212"
              (list->string '#2= (#\1 #\2 . #2#) 1 8))
  ;; Spec inverse properties.
  (test-equal "inverse of string->list range"
              "cde" (list->string (string->list "abcde" 2 5)))
  (test-equal "string->list of a range conversion"
              '(#\c #\d) (string->list (list->string '(#\a #\b #\c #\d) 2 4)))
  (test-error "non-character element" (list->string '(#\a #\b 3) 0 3))
  (test-error "improper list without end" (list->string '(#\a #\b . #\c)))
  (test-error "improper list with start but no end"
              (list->string '(#\a #\b . #\c) 1))
  (test-error "end beyond length" (list->string '(#\a #\b) 0 5)))

;;; ====================================================================
;;; list->vector
;;; ====================================================================

(test-group "list->vector"
  (test-equal "on proper list" '#(1 2 3 4 5) (list->vector '(1 2 3 4 5)))
  (test-equal "start on proper list" '#(3 4 5) (list->vector '(1 2 3 4 5) 2))
  (test-equal "start and end on proper list, 1" '#(3 4) (list->vector '(1 2 3 4 5) 2 4))
  (test-equal "start and end on proper list, 2" '#(3 4 5) (list->vector '(1 2 3 4 5) 2 5))
  (test-equal "spec example" '#(do be doo) (list->vector '(do be do be doo . dah) 2 5))
  (test-equal "start and end on improper list" '#(3 4 5)
              (list->vector '(1 2 3 4 5 . 6) 2 5))
  (test-equal "start is length" '#() (list->vector '(1 2 3 4 5) 5))
  (test-equal "start and end are length" '#() (list->vector '(1 2 3 4 5) 5 5))
  (test-equal "start and end on circular list" '#(2 1 2 1 2 1 2)
              (list->vector clist 1 8))
  (test-error "improper list without end" (list->vector '(1 2 3 4 5 . 6)))
  (test-error "improper list with start but no end" (list->vector '(1 2 3 4 5 . 6) 2))
  (test-error "end beyond length" (list->vector '(1 2 3) 0 4))
  (test-error "start greater than end" (list->vector '(1 2 3) 2 1))
  (test-error "non-integer start" (list->vector '(1 2 3) 'a 2))
  ;; The range check reports a string message carrying its own procedure
  ;; name (R7RS 6.11), and each conversion attributes its own errors.
  (test-equal "range error message is a string naming the procedure"
              "list->vector: list is not long enough"
              (guard (e ((error-object? e) (error-object-message e)))
                (list->vector '(1 2 3) 0 5)))
  (test-equal "list->string range errors attributed to list->string"
              "list->string: list is not long enough"
              (guard (e ((error-object? e) (error-object-message e)))
                (list->string '(#\a #\b) 0 5))))

;;; ====================================================================
;;; Collection conversions: ranges round-trip through the collection's
;;; own ->list procedure (structure of the SRFI's official tests.scm).
;;; ====================================================================

(define (test-to-from list->* *->list)
  (test-equal "start and end on proper list, 1" '(3 4)
              (*->list (list->* '(1 2 3 4 5) 2 4)))
  (test-equal "start and end on proper list, 2" '(3 4 5)
              (*->list (list->* '(1 2 3 4 5) 2 5)))
  (test-equal "start and end on improper list" '(3 4 5)
              (*->list (list->* '(1 2 3 4 5 . 6) 2 5)))
  (test-equal "start only" '(3 4 5)
              (*->list (list->* '(1 2 3 4 5) 2)))
  (test-equal "whole list" '(1 2 3 4 5)
              (*->list (list->* '(1 2 3 4 5))))
  (test-equal "start is length" '()
              (*->list (list->* '(1 2 3 4 5) 5)))
  (test-equal "start and end are length" '()
              (*->list (list->* '(1 2 3 4 5) 5 5)))
  (test-equal "start and end on circular list" '(2 1 2 1 2 1 2)
              (*->list (list->* clist 1 8))))

(define (test-to-from/floats list->* *->list)
  (test-equal "floats, start and end" '(3.0 4.0 5.0)
              (*->list (list->* '(1.0 2.0 3.0 4.0 5.0) 2 5)))
  (test-equal "floats, improper list" '(3.0 4.0 5.0)
              (*->list (list->* '(1.0 2.0 3.0 4.0 5.0 . 6) 2 5)))
  (test-equal "floats, circular list" '(2.0 1.0 2.0 1.0 2.0 1.0 2.0)
              (*->list (list->* '#4= (1.0 2.0 . #4#) 1 8))))

(define (test-to-from/cplx list->* *->list)
  (test-equal "complex, start and end" '(3.0+3.0i 4.0+4.0i 5.0+5.0i)
              (*->list (list->* '(1.0+1.0i 2.0+2.0i 3.0+3.0i 4.0+4.0i 5.0+5.0i) 2 5)))
  (test-equal "complex, improper list" '(3.0+3.0i 4.0+4.0i 5.0+5.0i)
              (*->list (list->* '(1.0+1.0i 2.0+2.0i 3.0+3.0i 4.0+4.0i 5.0+5.0i . 6) 2 5)))
  (test-equal "complex, circular list" '(2.0+2.0i 1.0+1.0i 2.0+2.0i 1.0+1.0i 2.0+2.0i 1.0+1.0i 2.0+2.0i)
              (*->list (list->* '#5= (1.0+1.0i 2.0+2.0i . #5#) 1 8))))

(test-group "srfi 41 streams"
  (test-to-from list->stream stream->list)
  ;; Circular input without `end` is an error per the spec, but laziness
  ;; makes it silent here: nothing walks far enough to notice. These pin
  ;; the documented leniency (see srfi-implementation-notes.md, SRFI 274)
  ;; — an infinite stream whose elements cycle forever. stream-ref is used
  ;; because stream->list would not terminate.
  (test-equal "circular list without end: lenient infinite stream"
              1 (stream-ref (list->stream clist) 6))
  (test-equal "circular list with start only: lenient infinite stream"
              2 (stream-ref (list->stream clist 1) 6)))

(test-group "srfi 134 ideques"
  (test-to-from list->ideque ideque->list)
  ;; Same leniency as above for the start-only improper case: Kaappi's
  ;; simplified (srfi 134) never walks its input, so no error is raised.
  (test-assert "improper list with start only: lenient (see notes)"
               (begin (list->ideque '(1 2 . 3) 1) #t)))

(test-group "srfi 158 generators"
  (test-to-from list->generator generator->list)
  ;; The generator stops exactly at `end` and returns the eof object.
  (test-equal "generator returns eof past end"
              (eof-object)
              (let ((g (list->generator clist 0 3)))
                (g) (g) (g) (g)))
  ;; Circular input without `end`: same laziness leniency as streams —
  ;; an infinite generator cycling forever, pinned (see notes).
  (test-equal "circular list without end: lenient infinite generator"
              '(1 2 1 2 1)
              (let ((g (list->generator clist)))
                (list (g) (g) (g) (g) (g))))
  (test-equal "circular list with start only: lenient infinite generator"
              '(2 1 2 1 2)
              (let ((g (list->generator clist 1)))
                (list (g) (g) (g) (g) (g)))))

(test-group "srfi 160 homogeneous vectors"
  (test-group "s8vector"  (test-to-from list->s8vector s8vector->list))
  (test-group "u8vector"  (test-to-from list->u8vector u8vector->list))
  (test-group "s16vector" (test-to-from list->s16vector s16vector->list))
  (test-group "u16vector" (test-to-from list->u16vector u16vector->list))
  (test-group "s32vector" (test-to-from list->s32vector s32vector->list))
  (test-group "u32vector" (test-to-from list->u32vector u32vector->list))
  (test-group "s64vector" (test-to-from list->s64vector s64vector->list))
  (test-group "u64vector" (test-to-from list->u64vector u64vector->list))
  (test-group "f32vector" (test-to-from/floats list->f32vector f32vector->list))
  (test-group "f64vector" (test-to-from/floats list->f64vector f64vector->list))
  (test-group "c64vector" (test-to-from/cplx list->c64vector c64vector->list))
  (test-group "c128vector" (test-to-from/cplx list->c128vector c128vector->list))
  (test-error "improper list without end" (list->u8vector '(1 2 . 3)))
  (test-error "end beyond length" (list->s16vector '(1 2 3) 0 9))
  (test-error "element out of range" (list->u8vector '(1 2 300) 0 3)))

(let ((runner (test-runner-current)))
  (test-end "srfi-274")
  (when (> (test-runner-fail-count runner) 0)
    (exit 1)))
