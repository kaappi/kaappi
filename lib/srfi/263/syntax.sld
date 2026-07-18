;;; SRFI 263: Prototype Object System — syntactic sugar
;;;
;;; Convenience macros over the (srfi 263) message-passing protocol:
;;; define-method, derive-object, copy-object, and define-object.
;;;
;;; Ported to Kaappi from the reference implementation by Daniel Ziltener.
;;; Kaappi changes:
;;;   * The method macro is exported as `define-method`, the name the SRFI 263
;;;     document specifies. The reference implementation names it `set-method!`;
;;;     that name is kept as an alias for reference-implementation compatibility.
;;;   * The CHICKEN `(void)` in the empty-slots base case is written as the
;;;     R7RS unspecified value (if #f #f).
;;;
;;; SPDX-FileCopyrightText: 2026 Daniel Ziltener
;;; SPDX-License-Identifier: MIT

(define-library (srfi 263 syntax)
  (import (scheme base)
          (srfi 263))
  (export define-method
          set-method!
          derive-object
          copy-object
          define-object)
  (begin

    (define-syntax define-method
      (syntax-rules ()
        ((_ (obj message self resend args ...)
            body1 body ...)
         (obj 'set-method-slot! `message
              (lambda (self resend args ...)
                body1 body ...)))))

    ;; Reference-implementation alias for define-method.
    (define-syntax set-method!
      (syntax-rules ()
        ((_ (obj message self resend args ...)
            body1 body ...)
         (define-method (obj message self resend args ...)
           body1 body ...))))

    (define-syntax derive-object
      (syntax-rules ()
        ((_ (creation-parent (parent-name parent-object) ...)
            slots ...)
         (let ((o (creation-parent 'derive)))
           (o 'set-parent-slot! 'parent-name parent-object)
           ...
           (derive-object/add-slots! o slots ...)
           o))))

    (define-syntax copy-object
      (syntax-rules ()
        ((_ (creation-parent (parent-name parent-object) ...)
            slots ...)
         (let ((o (creation-parent 'copy)))
           (o 'set-parent-slot! 'parent-name parent-object)
           ...
           (derive-object/add-slots! o slots ...)
           o))))

    (define-syntax derive-object/add-slots!
      (syntax-rules ()
        ((_ o)
         (if #f #f))
        ((_ o ((method-name . method-args) body ...)
            slots ...)
         (begin
           (o 'set-method-slot! `method-name (lambda method-args
                                               body ...))
           (derive-object/add-slots! o slots ...)))
        ((_ o (slot-getter slot-setter slot-value)
            slots ...)
         (begin
           (o 'set-value-slot! `slot-getter `slot-setter slot-value)
           (derive-object/add-slots! o slots ...)))
        ((_ o (slot-getter slot-value)
            slots ...)
         (begin
           (o 'set-value-slot! `slot-getter slot-value)
           (derive-object/add-slots! o slots ...)))))

    (define-syntax define-object
      (syntax-rules ()
        ((_ name body ...)
         (define name
           (derive-object body ...)))))))
