;;; SRFI 137: Minimal Unique Types.
;;;
;;; A single procedure, make-type, returning 5 fresh, mutually-distinct
;;; procedures per call: type-accessor (a thunk returning the type payload),
;;; constructor, predicate, accessor, and make-subtype (itself returning
;;; another 5-tuple, whose instances additionally satisfy every ANCESTOR
;;; type's predicate/accessor -- "direct or indirect subtype", per spec).
;;;
;;; Built entirely on (srfi 237)'s record-type-descriptor inheritance:
;;; "subtype" here is exactly SRFI 237's `parent` relationship, and
;;; predicate/accessor subtype-recognition is exactly what
;;; record-predicate/record-accessor already provide. Each make-type/
;;; make-subtype call allocates a genuinely fresh, unexported RTD, so its
;;; constructor/predicate/accessor are unreachable except through the
;;; returned closures -- satisfying the spec's "distinct... from any other
;;; procedures returned by other calls to make-type" without needing any
;;; new machinery of its own.
(define-library (srfi 137)
  (import (scheme base) (srfi 237))
  (export make-type)
  (begin

    ;; The ROOT type owns the one real "payload" field; every subtype adds
    ;; ZERO fields of its own (there is exactly one payload per instance,
    ;; shared and visible through every ancestor's accessor -- not a
    ;; separate field per inheritance level), inheriting the root's single
    ;; field via the parent rtd/rcd chain instead. record-constructor's
    ;; default (no-protocol) inheritance threading then naturally forwards
    ;; a subtype constructor's one argument straight through to the root's
    ;; own constructor, so field 0 always ends up set to the given payload
    ;; regardless of how many subtype levels it passed through.
    (define (%make-type-impl type-payload parent-rtd parent-rcd)
      (let* ((rtd (make-record-type-descriptor 'srfi-137-type parent-rtd #f #f #f
                    (if parent-rtd #() #((immutable payload)))))
             (rcd (make-record-descriptor rtd parent-rcd #f))
             (ctor (record-constructor rcd))
             (pred (record-predicate rtd))
             (acc (record-accessor rtd 0)))
        (values
          (lambda () type-payload)
          ctor
          pred
          acc
          (lambda (subtype-payload) (%make-type-impl subtype-payload rtd rcd)))))

    (define (make-type type-payload) (%make-type-impl type-payload #f #f))))
