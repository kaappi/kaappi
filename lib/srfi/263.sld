;;; SRFI 263: Prototype Object System
;;;
;;; A prototype-based object system inspired by Self. Objects are
;;; represented as closures and communicate through message passing,
;;; with value slots, method slots, and parent slots for inheritance,
;;; plus a mirror interface for reflection.
;;;
;;; Ported to Kaappi from the reference implementation by Daniel Ziltener.
;;; Deviations from the reference, each marked "Kaappi:" at its call site:
;;;
;;;   Portability
;;;   * The CHICKEN-style private symbol `##srfi-263#obj-data` is written
;;;     with R7RS bar-quoting as |##srfi-263#obj-data|.
;;;   * The duplicate (dead) definition of `recursive-lookup` is dropped;
;;;     only the second, deduplicating one is kept.
;;;   * The root 'derive method returns a single value instead of relying on
;;;     CHICKEN truncating (values obj data) in a single-value context.
;;;
;;;   Spec-conformance bug fixes (untested by the reference test suite)
;;;   * copy: use the mirror's real 'immediate-* reflection messages (the
;;;     reference sends nonexistent 'get-* messages and crashes), and always
;;;     re-install 'mirror over the copy's own data so it is independent of
;;;     the original — including a copy of the parentless root object.
;;;   * message-not-understood / ambiguous-message-send: re-dispatch as a
;;;     message to the receiver so custom handler slots can intercept, per
;;;     the SRFI; the reference applies the bare symbol and cannot override.
;;;   * Reflection: the mirror's full-ancestor-list / full-slot-list are
;;;     driven from the mirrored object, not the mirror receiver, so they
;;;     return the real ancestors/slots (and the receiver's own slots);
;;;     full-slot-list dedups by getter name (slot is a record, not a pair);
;;;     the root's set-method-slot! slot records the message name, not the
;;;     procedure; and the SRFI's has-ancestor mirror message is provided.
;;;
;;;   Known limitation (a gap in the finalized SRFI itself, not fixed here)
;;;   * (resend #f ...) from a method inherited from a non-immediate ancestor
;;;     loops: resend restarts the lookup skipping only the original receiver,
;;;     so it re-finds the same ancestor method. A correct fix needs a
;;;     distinct-origin lookup the SRFI never specified. Resending to an
;;;     explicit target, and resend from a directly-overriding method, both
;;;     work. Likewise, ambiguity is detected per distinct procedure, so two
;;;     parents sharing one procedure object are not flagged ambiguous.
;;;
;;; SPDX-FileCopyrightText: 2026 Daniel Ziltener
;;; SPDX-License-Identifier: MIT

(define-library (srfi 263)
  (import (scheme base)
          (scheme case-lambda)
          (scheme cxr)
          (srfi 1))
  (export *the-root-object*
          slot?
          slot-getter
          slot-setter
          slot-type)
  (begin

    ;;; Core system

    (define-record-type slot
      (make-slot getter setter type)
      slot?
      (getter slot-getter)
      (setter slot-setter)
      (type slot-type))

    (define (delete-slot! obj-data slot)
      (let* ((message-alist (get-message-alist obj-data))
             (slot-list (get-slot-list obj-data))
             (parent-list (get-parent-list obj-data))
             (setter-predicate (lambda (item) (eq? (slot-setter item) slot)))
             (is-setter? (find setter-predicate slot-list))
             (slot-predicate (lambda (item)
                               (or (eq? (slot-getter item) slot)
                                  (eq? (slot-setter item) slot))))
             (slots (filter slot-predicate slot-list)))
        (if (= 1 (length slots))
            (let ((slot (car slots)))
              (if (eq? 'parent (slot-type slot))
                  (set-parent-list! obj-data
                                    (delete
                                     ((cdr (assq (slot-getter slot) message-alist)) #f #f)
                                     parent-list)))
              (set-message-alist!
               obj-data
               (if is-setter?
                   (alist-delete (slot-setter slot) message-alist)
                   (alist-delete (slot-getter slot)
                                 (alist-delete (slot-setter slot) message-alist))))
              (set-slot-list!
               obj-data
               (if is-setter?
                   (map (lambda (item)
                          (if (setter-predicate item)
                              (make-slot (slot-getter item) #f (slot-type item))
                              item))
                        slot-list)
                   (remove slot-predicate slot-list)))))))

    (define (slot-add-message-name type)
      (case type
        ((value) 'set-value-slot!)
        ((method) 'set-method-slot!)
        ((parent) 'set-parent-slot!)))

    (define (gen-accessors type getter-name setter-name value)
      (values
       (case type
         ((value) (lambda (self resend) value))
         ((method) value)
         ((parent) (lambda (self resend) value)))
       (if setter-name
           (lambda (self resend value)
             (apply self (slot-add-message-name type) getter-name
                    (if setter-name (list setter-name value) value)))
           #f)))

    (define (set-object-data-slots! obj-data type getter-name getter setter-name setter)
      (let ((new-messages (if setter
                              `((,getter-name . ,getter)
                                (,setter-name . ,setter))
                              `((,getter-name . ,getter)))))
        (set-message-alist!
         obj-data (append new-messages (get-message-alist obj-data)))
        (set-slot-list!
         obj-data (cons (make-slot getter-name setter-name type) (get-slot-list obj-data)))))

    (define (set-slot! obj-data type getter-name . args)
      (let* ((setter? (< 1 (length args)))
             (setter-name (and setter? (car args)))
             (value (if setter? (cadr args) (car args))))
        (let-values (((getter setter)
                      (gen-accessors type getter-name setter-name value)))
          (delete-slot! obj-data getter-name)
          (set-object-data-slots! obj-data type getter-name getter setter-name setter)
          (when (eq? type 'parent)
            (set-parent-list!
             obj-data (cons value (get-parent-list obj-data)))))))

    (define (method-finder name message-alist)
      (letrec ((mfinder
                (lambda (self)
                  (cond ((or
                          (assq name message-alist)
                          (assq name (get-message-alist ((self 'mirror) '|##srfi-263#obj-data|))))
                         => cdr)
                        (else #f)))))
        mfinder))

    (define (recursive-lookup self checker skip?)
      (cond
       ((and (not skip?) (checker self))
        => (lambda (alist-entry)
             (values alist-entry #t)))
       (else
        (let ((obj-data ((self 'mirror) '|##srfi-263#obj-data|)))
          (let loop ((parents (get-parent-list obj-data))
                     (handlers '())
                     (handler #f)
                     (found #f))
            (cond
             ((not (null? parents))
              (let-values (((new-handler new-found)
                            (recursive-lookup (car parents) checker #f)))
                (loop (cdr parents)
                      (if new-found (lset-adjoin eq? handlers new-handler) handlers)
                      (if new-found new-handler handler)
                      (or new-found found))))
             (else
              (if handler
                  (if (= 1 (length handlers))
                      (values handler found)
                      (values 'ambiguous-message-send #f))
                  (values 'message-not-understood #f)))))))))

    ;; Kaappi: collect self plus every ancestor, deduplicated. The reference
    ;; only includes `self` in the no-parents base case, so full-ancestor-list
    ;; on a non-root object dropped the object itself; folding (list self) into
    ;; the union restores the self+ancestors result the reference test expects.
    (define (recursive-ancestor-collector self)
      (let ((parents (get-parent-list ((self 'mirror) '|##srfi-263#obj-data|))))
        (apply lset-union
               eq?
               (list self)
               (map recursive-ancestor-collector parents))))

    (define (recursive-slot-collector self)
      (let ((classes (recursive-ancestor-collector self)))
        (apply lset-union
               ;; Kaappi: dedup by getter name. `slot` is a record, not a
               ;; pair — the reference's (car a) errors once two slot lists
               ;; are unioned. recursive-ancestor-collector now includes self,
               ;; so the receiver's own slots are part of full-slot-list.
               (lambda (a b)
                 (eq? (slot-getter a) (slot-getter b)))
               (list)
               (map (lambda (class)
                      (get-slot-list ((class 'mirror) '|##srfi-263#obj-data|)))
                    classes))))

    ;;;; Method running

    (define (send-with-error-handling caller method-lookup method-name message-alist parents-only args)
      (let-values (((method found?)
                    (recursive-lookup
                     method-lookup
                     (method-finder method-name message-alist)
                     parents-only)))
        (if found?
            (apply method caller (make-resender caller method-name) args)
            ;; Kaappi: when the message is not found, `method` is the symbol
            ;; 'message-not-understood or 'ambiguous-message-send. Per SRFI 263,
            ;; "the original message receiving object is sent a
            ;; message-not-understood message" — so re-dispatch it as a message
            ;; to `caller`, letting a custom handler slot intercept it. The
            ;; reference applies the bare symbol instead (an error only by
            ;; accident of it not being a procedure), which defeats overriding.
            (caller method method-name args))))

    (define (make-resender caller handler-name)
      (lambda (target-override . args)
        (let ((target (cond
                       ((eq? #f target-override)
                        caller)
                       (else target-override))))
          (send-with-error-handling caller target handler-name '() (eq? target-override #f) args))))

    ;;;; Root object

    (define-record-type object-data
      (make-object-data* message-alist slot-list parent-list)
      object-data?
      (message-alist get-message-alist set-message-alist!)
      (slot-list get-slot-list set-slot-list!)
      (parent-list get-parent-list set-parent-list!))

    (define (make-object-data)
      (make-object-data* '() '() '()))

    (define (*object* obj-data)
      (letrec
          ((obj-handler
            (lambda (message . args)
              (send-with-error-handling
               obj-handler obj-handler message (get-message-alist obj-data) #f args))))
        obj-handler))

    (define (set-method-slot! obj-data name . args)
      (apply set-slot! obj-data 'method name args))

    (define (derive-object obj mirror?)
      (let* ((obj-data (make-object-data))
             (derived-object (*object* obj-data)))
        (set-slot! obj-data 'parent 'parent obj)
        (set-method-slot!
         obj-data 'mirror
         (lambda (self resend)
           (let-values (((new-mirror new-mirror-data)
                         (derive-object (obj 'mirror) #t)))
             (populate-mirror new-mirror new-mirror-data self obj-data))))
        (when mirror?
          (set-method-slot! obj-data 'derive
                            (lambda (self resend)
                              (let-values (((new-obj new-data)
                                            (derive-object self #t)))
                                new-obj))))
        (values derived-object obj-data)))

    ;; Kaappi: `owner` is the object being mirrored. The reference passes the
    ;; mirror receiver (`self`) to the recursive collectors, so full-ancestor-
    ;; list / full-slot-list walked the parallel mirror hierarchy and returned
    ;; mirror objects instead of the real ancestors; drive them from `owner`
    ;; instead. Also installs `has-ancestor`, a mirror message the SRFI lists
    ;; but the reference omits.
    (define (populate-mirror mirror mirror-data owner obj-data)
      (map
       (lambda (name proc)
         (set-method-slot! mirror-data name proc))
       '(|##srfi-263#obj-data| immediate-message-alist
                    immediate-ancestor-list full-ancestor-list
                    immediate-slot-list full-slot-list has-ancestor)
       (list (lambda (self resend) obj-data)
             (lambda (self resend) (list-copy (get-message-alist obj-data)))
             (lambda (self resend) (list-copy (get-parent-list obj-data)))
             (lambda (self resend) (recursive-ancestor-collector owner))
             (lambda (self resend) (list-copy (get-slot-list obj-data)))
             (lambda (self resend) (recursive-slot-collector owner))
             (lambda (self resend candidate)
               (and (not (eq? candidate owner))
                    (and (memq candidate (recursive-ancestor-collector owner)) #t)))))
      mirror)

    (define *the-root-object*
      (let* ((obj-data (make-object-data))
             (object (*object* obj-data)))
        (set-message-alist!
         obj-data
         (alist-cons 'set-method-slot!
                     (lambda (self resend name . args)
                       (apply set-method-slot! ((self 'mirror) '|##srfi-263#obj-data|)
                              name args))
                     (get-message-alist obj-data)))
        (set-slot-list!
         obj-data
         ;; Kaappi: quote the getter name. The reference stores the
         ;; set-method-slot! procedure here, so reflection returned a
         ;; procedure instead of the 'set-method-slot! message name and
         ;; deletion by that name could not match it.
         (append (list (make-slot 'set-method-slot! #f 'method)) (get-slot-list obj-data)))
        (set-method-slot!
         obj-data 'mirror
         (lambda (self resend)
           (let-values (((root-mirror mirror-data) (derive-object *the-root-object* #t)))
             (populate-mirror root-mirror mirror-data self obj-data))))
        (set-method-slot!
         obj-data 'derive
         (lambda (self resend)
           ;; Kaappi: return a single value. The reference returns
           ;; (derive-object self #f) directly (two values) and relies on
           ;; CHICKEN truncating to the first in a single-value context;
           ;; R7RS leaves that unspecified, so match the single-value
           ;; pattern the derived-object 'derive method already uses.
           (let-values (((new-obj new-data) (derive-object self #f)))
             new-obj)))
        (set-method-slot!
         obj-data 'copy
         (lambda (self resend)
           ;; Kaappi: the reference sends the mirror 'get-message-alist,
           ;; 'get-slot-list and 'get-parent-list — messages no mirror
           ;; understands (they crash with "message not understood"), which is
           ;; why the reference test suite never exercises copy. The mirror
           ;; actually exposes the receiver's own definitions as
           ;; 'immediate-message-alist / 'immediate-slot-list /
           ;; 'immediate-ancestor-list, so use those to duplicate them.
           (let ((mirror (self 'mirror))
                 (new-data (make-object-data)))
             (set-message-alist! new-data (list-copy (mirror 'immediate-message-alist)))
             (set-slot-list! new-data (list-copy (mirror 'immediate-slot-list)))
             (set-parent-list! new-data (list-copy (mirror 'immediate-ancestor-list)))
             ;; Kaappi: the copied 'mirror method still closes over the
             ;; ORIGINAL's object-data, so set-value-slot!/set-parent-slot! on
             ;; the copy would mutate the original (copies were never
             ;; independent in the reference). Always re-install 'mirror over
             ;; the copy's own object-data — including when the copy has no
             ;; parents (a copy of *the-root-object*), which otherwise keeps
             ;; the original's mirror and mutates the global root. Chain the
             ;; mirror through the primary parent, or the root object itself
             ;; when the copy is parentless.
             (let* ((parents (get-parent-list new-data))
                    (mirror-base (if (null? parents) *the-root-object* (car parents))))
               (set-method-slot!
                new-data 'mirror
                (lambda (self resend)
                  (let-values (((new-mirror new-mirror-data)
                                (derive-object (mirror-base 'mirror) #t)))
                    (populate-mirror new-mirror new-mirror-data self new-data)))))
             (*object* new-data))))
        (set-method-slot!
         obj-data 'delete-slot!
         (lambda (self resend name)
           (delete-slot! ((self 'mirror) '|##srfi-263#obj-data|) name)))
        (set-method-slot!
         obj-data 'set-value-slot!
         (lambda (self resend name . args)
           (apply set-slot! ((self 'mirror) '|##srfi-263#obj-data|) 'value name args)))
        (set-method-slot!
         obj-data 'set-parent-slot!
         (lambda (self resend name . args)
           (apply set-slot! ((self 'mirror) '|##srfi-263#obj-data|) 'parent name args)))
        (set-method-slot!
         obj-data 'message-not-understood
         (lambda (self resend message args)
           (error "Message not understood" self message args)))
        (set-method-slot!
         obj-data 'ambiguous-message-send
         (lambda (self resend message args)
           (error "Message ambiguous" self message args)))
        object))))
