;;; Audit: lib/srfi/35.sld (SRFI 35 — Conditions)
;;; Systematic audit v2, Phase 3.9 (docs/audit-strategy.md, tracking #1890).
;;;
;;; Oracle: SRFI 35, https://srfi.schemers.org/srfi-35/srfi-35.html
;;;
;;; The pre-existing tests/scheme/srfi/srfi35.scm uses an ad-hoc `check`
;;; framework and never touches 8 of the 23 exports. This file covers all 23
;;; under SRFI 64, and adds the question the unit was scoped around: how
;;; SRFI 35's condition world relates to R7RS's error-object world.
;;;
;;; Answer, asserted below: they are DISJOINT and self-consistent. A SRFI 35
;;; &error condition is not an R7RS error object and vice versa, in both
;;; directions and for both predicates. That is not a defect — SRFI 35
;;; predates R7RS and specifies its own hierarchy rooted at &condition — but
;;; nothing had ever pinned it, so a change in either direction was invisible.
;;; chibi-scheme could not serve as an oracle here: its (srfi 35) fails to
;;; load at all (it imports a missing `(srfi 35 internal)`).
;;;
;;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi35-audit.scm

(import (scheme base) (scheme write) (scheme process-context) (srfi 64) (srfi 35))

(test-begin "srfi35 audit")

(define (raises? thunk)
  (call-with-current-continuation
   (lambda (k) (with-exception-handler (lambda (e) (k #t)) (lambda () (thunk) #f)))))
(define (catch thunk)
  (call-with-current-continuation
   (lambda (k) (with-exception-handler (lambda (e) (k e)) thunk))))

;;; ------------------------------------------------------------------
;;; Condition types and the standard hierarchy
;;; ------------------------------------------------------------------

(test-assert "condition-type? on &condition" (condition-type? &condition))
(test-assert "condition-type? on &message" (condition-type? &message))
(test-assert "condition-type? on &serious" (condition-type? &serious))
(test-assert "condition-type? on &error" (condition-type? &error))
(test-assert "condition-type? on a non-type" (not (condition-type? 42)))
(test-assert "condition-type? on a condition instance"
             (not (condition-type? (make-condition &serious))))
(test-equal "condition-type-name of &condition" '&condition (condition-type-name &condition))
(test-equal "condition-type-name of &message" '&message (condition-type-name &message))
(test-equal "condition-type-name of &serious" '&serious (condition-type-name &serious))
(test-equal "condition-type-name of &error" '&error (condition-type-name &error))

;; "&message, &serious ... are subtypes of &condition; &error is a subtype of
;;  &serious."
(test-assert "&message is a subtype of &condition" (condition-subtype? &message &condition))
(test-assert "&serious is a subtype of &condition" (condition-subtype? &serious &condition))
(test-assert "&error is a subtype of &serious" (condition-subtype? &error &serious))
(test-assert "&error is transitively a subtype of &condition"
             (condition-subtype? &error &condition))
(test-assert "&message is not a subtype of &serious"
             (not (condition-subtype? &message &serious)))
(test-assert "&serious is not a subtype of &error" (not (condition-subtype? &serious &error)))
(test-assert "a type is a subtype of itself" (condition-subtype? &error &error))
(test-assert "&condition is not a subtype of &error" (not (condition-subtype? &condition &error)))

(test-assert "condition-type-supertype of &error is &serious"
             (eq? &serious (condition-type-supertype &error)))
(test-assert "condition-type-supertype of &serious is &condition"
             (eq? &condition (condition-type-supertype &serious)))
(test-assert "condition-type-supertype of &message is &condition"
             (eq? &condition (condition-type-supertype &message)))
(test-equal "condition-type-fields of &message" '(message) (condition-type-fields &message))
(test-equal "condition-type-fields of &error is empty" '() (condition-type-fields &error))
(test-equal "condition-type-fields of &condition is empty" '() (condition-type-fields &condition))
(test-equal "condition-type-all-fields of &message" '(message)
            (condition-type-all-fields &message))
(test-equal "condition-type-all-fields of &error is empty" '()
            (condition-type-all-fields &error))

;;; ------------------------------------------------------------------
;;; make-condition-type. "(make-condition-type name supertype field-names)"
;;; ------------------------------------------------------------------

(define &mine (make-condition-type '&mine &error '(x y)))
(test-assert "make-condition-type builds a condition type" (condition-type? &mine))
(test-equal "the new type keeps its name" '&mine (condition-type-name &mine))
(test-assert "the new type is a subtype of its supertype" (condition-subtype? &mine &error))
(test-assert "the new type is transitively a subtype of &condition"
             (condition-subtype? &mine &condition))
(test-assert "the new type's supertype is the one it was given"
             (eq? &error (condition-type-supertype &mine)))
(test-equal "the new type's own fields" '(x y) (condition-type-fields &mine))
(test-equal "the new type's all-fields includes only its own here" '(x y)
            (condition-type-all-fields &mine))
(test-assert "&error is not a subtype of the new type" (not (condition-subtype? &error &mine)))

(define &deeper (make-condition-type '&deeper &mine '(z)))
(test-equal "a grandchild type's own fields exclude inherited ones" '(z)
            (condition-type-fields &deeper))
(test-assert "a grandchild type's all-fields includes inherited ones"
             (let ((all (condition-type-all-fields &deeper)))
               (and (memq 'x all) (memq 'y all) (memq 'z all) #t)))
(test-assert "a grandchild is a subtype of its grandparent"
             (condition-subtype? &deeper &error))

;;; ------------------------------------------------------------------
;;; make-condition / condition-ref / condition-has-type?
;;; ------------------------------------------------------------------

(define c-msg (make-condition &message 'message "hello"))
(test-assert "make-condition builds a condition" (condition? c-msg))
(test-assert "a condition is not a condition type" (not (condition-type? c-msg)))
(test-assert "condition? on a plain value" (not (condition? 42)))
(test-equal "condition-message reads the message field" "hello" (condition-message c-msg))
(test-equal "condition-ref reads a named field" "hello" (condition-ref c-msg 'message))
(test-assert "condition-has-type? for its own type" (condition-has-type? c-msg &message))
(test-assert "condition-has-type? for its supertype" (condition-has-type? c-msg &condition))
(test-assert "condition-has-type? for an unrelated type"
             (not (condition-has-type? c-msg &error)))
(test-assert "condition-ref of a field the condition does not have raises"
             (raises? (lambda () (condition-ref c-msg 'nope))))
(test-assert "make-condition with a field left unsupplied raises"
             (raises? (lambda () (make-condition &message))))

(define c-mine (make-condition &mine 'x 1 'y 2))
(test-equal "a user type's fields are readable: x" 1 (condition-ref c-mine 'x))
(test-equal "a user type's fields are readable: y" 2 (condition-ref c-mine 'y))
(test-assert "a user condition has its own type" (condition-has-type? c-mine &mine))
(test-assert "a user condition has its supertype" (condition-has-type? c-mine &error))
(test-assert "a user condition has &serious transitively" (condition-has-type? c-mine &serious))
(test-assert "a user condition of a subtype of &error satisfies error?" (error? c-mine))
(test-assert "a user condition of a subtype of &error satisfies serious-condition?"
             (serious-condition? c-mine))

;;; ------------------------------------------------------------------
;;; The three standard predicates
;;; ------------------------------------------------------------------

(test-assert "message-condition? on a &message condition" (message-condition? c-msg))
(test-assert "message-condition? on a non-condition" (not (message-condition? 42)))
(test-assert "message-condition? on a plain &error condition"
             (not (message-condition? (make-condition &error))))
(test-assert "serious-condition? on a &serious condition"
             (serious-condition? (make-condition &serious)))
(test-assert "serious-condition? on a &message condition" (not (serious-condition? c-msg)))
(test-assert "serious-condition? on a non-condition" (not (serious-condition? 42)))
(test-assert "error? on an &error condition" (error? (make-condition &error)))
(test-assert "error? on a &serious condition" (not (error? (make-condition &serious))))
(test-assert "error? on a &message condition" (not (error? c-msg)))
(test-assert "error? on a non-condition" (not (error? 42)))

;;; ------------------------------------------------------------------
;;; Compound conditions
;;; ------------------------------------------------------------------

(define compound (make-compound-condition c-msg (make-condition &error)))
(test-assert "a compound condition is a condition" (condition? compound))
(test-assert "a compound condition has the first component's type"
             (condition-has-type? compound &message))
(test-assert "a compound condition has the second component's type"
             (condition-has-type? compound &error))
(test-assert "a compound condition has the supertypes of its components"
             (condition-has-type? compound &serious))
(test-equal "condition-message reaches into a compound condition"
            "hello" (condition-message compound))
(test-assert "error? sees the &error component of a compound condition" (error? compound))
(test-assert "message-condition? sees the &message component of a compound condition"
             (message-condition? compound))
(test-equal "condition-ref reaches a component's field" "hello" (condition-ref compound 'message))

(define extracted (extract-condition compound &message))
(test-assert "extract-condition returns a condition" (condition? extracted))
(test-assert "the extracted condition has the requested type"
             (condition-has-type? extracted &message))
(test-equal "the extracted condition keeps its field" "hello" (condition-message extracted))
(test-assert "extracting a type the compound does not have raises"
             (raises? (lambda () (extract-condition compound &mine))))
(test-assert "extract-condition on a simple condition of that type works"
             (condition? (extract-condition c-msg &message)))
(test-assert "make-compound-condition with one component is still a condition"
             (condition? (make-compound-condition c-msg)))

;;; ------------------------------------------------------------------
;;; The `condition` syntax
;;; ------------------------------------------------------------------

(define c-syntax (condition (&error) (&message (message "boom"))))
(test-assert "the condition syntax builds a condition" (condition? c-syntax))
(test-assert "the condition syntax includes a type with no fields"
             (condition-has-type? c-syntax &error))
(test-assert "the condition syntax includes a type with fields"
             (condition-has-type? c-syntax &message))
(test-equal "the condition syntax fills the field" "boom" (condition-message c-syntax))
(test-assert "the condition syntax result satisfies error?" (error? c-syntax))

(define-condition-type &my-io &error my-io? (port my-io-port))
(test-assert "define-condition-type defines a condition type" (condition-type? &my-io))
(test-assert "define-condition-type defines a working predicate"
             (my-io? (make-condition &my-io 'port 'p)))
(test-assert "the generated predicate rejects other conditions" (not (my-io? c-msg)))
(test-assert "the generated predicate rejects non-conditions" (not (my-io? 42)))
(test-equal "define-condition-type defines a working accessor"
            'p (my-io-port (make-condition &my-io 'port 'p)))
(test-assert "the generated type is a subtype of the declared supertype"
             (condition-subtype? &my-io &error))
(test-assert "a condition of the generated type satisfies error?"
             (error? (make-condition &my-io 'port 'p)))

;;; ------------------------------------------------------------------
;;; Raising and catching SRFI 35 conditions
;;; ------------------------------------------------------------------

(test-equal "a raised condition reaches the handler as itself"
            '(#t #t "hi")
            (let ((e (catch (lambda () (raise (condition (&error) (&message (message "hi"))))))))
              (list (condition? e) (error? e) (condition-message e))))
(test-assert "a raised condition can be caught by guard"
             (guard (e ((error? e) #t)) (raise (make-condition &error))))
(test-assert "guard can discriminate on a user condition type"
             (guard (e ((my-io? e) 'io) (#t 'other))
               (raise (make-condition &my-io 'port 'p))))
(test-equal "a condition raised through guard keeps its field"
            'p (guard (e ((my-io? e) (my-io-port e))) (raise (make-condition &my-io 'port 'p))))

;;; ------------------------------------------------------------------
;;; The seam with R7RS error objects. Nothing in SRFI 35 requires these two
;;; worlds to overlap, and in this implementation they do not — pinned in
;;; both directions so a future change is visible.
;;; ------------------------------------------------------------------

(test-equal "an R7RS error object is an error-object? but not a SRFI 35 error?"
            '(#f #t)
            (let ((e (catch (lambda () (error "boom")))))
              (list (error? e) (error-object? e))))
(test-assert "an R7RS error object is not a SRFI 35 condition"
             (not (condition? (catch (lambda () (error "boom"))))))
(test-equal "a SRFI 35 &error condition is a SRFI 35 error? but not an error-object?"
            '(#t #f)
            (let ((c (make-condition &error))) (list (error? c) (error-object? c))))
(test-assert "condition-message on an R7RS error object raises"
             (raises? (lambda () (condition-message (catch (lambda () (error "boom")))))))
(test-assert "error-object-message on a SRFI 35 condition raises"
             (raises? (lambda () (error-object-message (make-condition &message 'message "m")))))
(test-assert "a guard clause using error-object? does not catch a SRFI 35 condition"
             (guard (e ((error-object? e) #f) (#t #t)) (raise (make-condition &error))))
(test-assert "a guard clause using SRFI 35 error? does not catch an R7RS error object"
             (guard (e ((error? e) #f) (#t #t)) (error "boom")))

(let ((runner (test-runner-current)))
  (test-end "srfi35 audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
