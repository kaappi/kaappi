;;; SRFI 263 (Prototype Object System) conformance tests.
;;;
;;; Ports the reference implementation's test suite and adds coverage for
;;; the reflection procedures, working copy/copy-object, custom
;;; message-not-understood handlers, and the (srfi 263 syntax) macros.

(import (scheme base)
        (scheme write)
        (srfi 1)
        (srfi 263)
        (srfi 263 syntax))

(define pass 0)
(define fail 0)

(define (check name got expected)
  (if (equal? got expected)
      (set! pass (+ pass 1))
      (begin
        (set! fail (+ fail 1))
        (display "FAIL: ") (display name)
        (display " expected ") (write expected)
        (display " got ") (write got)
        (newline))))

(define (check-true name got) (check name (and got #t) #t))

;; #t if THUNK raises (used for message-not-understood / ambiguity).
(define (raises? thunk)
  (call-with-current-continuation
   (lambda (k)
     (with-exception-handler
         (lambda (e) (k #t))
       (lambda () (thunk) #f)))))

;;; --------------------------------------------------------------------
;;; Basic functionality (ported from the reference test suite)
;;; --------------------------------------------------------------------

(check-true "root has no ancestors"
            (null? ((*the-root-object* 'mirror) 'immediate-ancestor-list)))
(check "root exposes 9 messages"
       (length ((*the-root-object* 'mirror) 'immediate-message-alist)) 9)

(let ((class (*the-root-object* 'derive)))
  (check-true "derived object's ancestor is the root"
              (eq? *the-root-object*
                   (car ((class 'mirror) 'immediate-ancestor-list))))

  (class 'set-method-slot! 'testmethod (lambda (self resend) 'success))
  (check "method slot returns its value" (class 'testmethod) 'success)

  (class 'set-value-slot! 'val 'set-val! 10)
  (check "value slot getter" (class 'val) 10)
  (class 'set-val! 20)
  (check "value slot after setter" (class 'val) 20)
  (check "getter+setter add two messages"
         (length ((class 'mirror) 'immediate-message-alist)) 5)

  (class 'set-value-slot! 'val 40)
  (check "value slot with no setter" (class 'val) 40)
  (check "redefining as getter-only drops the old setter"
         (length ((class 'mirror) 'immediate-message-alist)) 4)

  ;; Deleting the setter keeps the getter.
  (class 'set-value-slot! 'val 'set-val! 10)
  (class 'delete-slot! 'set-val!)
  (check "deleting the setter keeps the getter"
         (length ((class 'mirror) 'immediate-message-alist)) 4)

  ;; Deleting the getter also deletes the setter.
  (class 'set-value-slot! 'val 'set-val! 10)
  (class 'delete-slot! 'val)
  (check "deleting the getter also deletes the setter"
         (length ((class 'mirror) 'immediate-message-alist)) 3))

;;; --------------------------------------------------------------------
;;; Inheritance
;;; --------------------------------------------------------------------

(let* ((firstlevel (*the-root-object* 'derive))
       (secondlevel (firstlevel 'derive)))
  (firstlevel 'set-method-slot! 'testmethod (lambda (self resend) 'success))
  (check "method is inherited" (secondlevel 'testmethod) 'success)

  (firstlevel 'set-value-slot! 'val 'set-val! 10)
  (check "value is inherited" (secondlevel 'val) 10)

  ;; Setting through an inherited setter copies the slot onto the child.
  (secondlevel 'set-val! 20)
  (check "parent value unchanged after child set" (firstlevel 'val) 10)
  (check "child gets its own value" (secondlevel 'val) 20)

  (firstlevel 'set-value-slot! 'val #f 30)
  (check "parent value can be changed independently" (firstlevel 'val) 30)
  (check "child keeps its own value" (secondlevel 'val) 20)

  (check "firstlevel full ancestry (self + root)"
         (length ((firstlevel 'mirror) 'full-ancestor-list)) 2)
  (check "secondlevel full ancestry (self + parent + root)"
         (length ((secondlevel 'mirror) 'full-ancestor-list)) 3))

;;; --------------------------------------------------------------------
;;; Multiple inheritance, message-not-understood and ambiguity
;;; --------------------------------------------------------------------

(let* ((adderclass (*the-root-object* 'derive))
       (squareclass (*the-root-object* 'derive))
       (mathclass (squareclass 'derive)))
  (adderclass 'set-method-slot! 'inc
              (lambda (self resend val) (+ val 1)))
  (squareclass 'set-method-slot! 'square
               (lambda (self resend val) (* val val)))
  (mathclass 'set-parent-slot! 'adder adderclass)

  (check "adder method" (adderclass 'inc 9) 10)
  (check "square method" (squareclass 'square 3) 9)
  (check "method inherited across a second parent" (mathclass 'inc 8) 9)

  (check-true "unknown message signals an error"
              (raises? (lambda () (adderclass 'nope 10))))

  ;; Both parents define 'reset -> ambiguous.
  (adderclass 'set-method-slot! 'reset (lambda (self resend x) 5))
  (squareclass 'set-method-slot! 'reset (lambda (self resend x) 5))
  (check-true "ambiguous message signals an error"
              (raises? (lambda () (mathclass 'reset 1))))

  (check "two immediate parents"
         (length ((mathclass 'mirror) 'immediate-ancestor-list)) 2)
  (mathclass 'delete-slot! 'adder)
  (check "deleting a parent slot removes the ancestor"
         (length ((mathclass 'mirror) 'immediate-ancestor-list)) 1))

;;; --------------------------------------------------------------------
;;; Custom message-not-understood handler (SRFI-mandated, overridable)
;;; --------------------------------------------------------------------

(let ((obj (*the-root-object* 'derive)))
  (obj 'set-method-slot! 'message-not-understood
       (lambda (self resend message args) (list 'dnu message args)))
  (check "custom message-not-understood intercepts unknown messages"
         (obj 'whatever 1 2) '(dnu whatever (1 2))))

;;; --------------------------------------------------------------------
;;; Slot reflection: slot?, slot-getter, slot-setter, slot-type
;;; --------------------------------------------------------------------

(let ((cls (*the-root-object* 'derive)))
  (cls 'set-value-slot! 'foo 'set-foo! 1)
  (cls 'set-method-slot! 'bar (lambda (self resend) 'b))
  (let* ((slots ((cls 'mirror) 'immediate-slot-list))
         (foo (find (lambda (s) (eq? (slot-getter s) 'foo)) slots))
         (bar (find (lambda (s) (eq? (slot-getter s) 'bar)) slots))
         (par (find (lambda (s) (eq? (slot-type s) 'parent)) slots)))
    (check-true "slot? recognises a slot" (slot? foo))
    (check-true "slot? rejects a non-slot" (not (slot? 'foo)))
    (check "value slot getter name" (slot-getter foo) 'foo)
    (check "value slot setter name" (slot-setter foo) 'set-foo!)
    (check "value slot type" (slot-type foo) 'value)
    (check "method slot type" (slot-type bar) 'method)
    (check "method slot has no setter" (slot-setter bar) #f)
    (check-true "parent slot present" (slot? par))
    (check "parent slot type" (slot-type par) 'parent)))

;;; --------------------------------------------------------------------
;;; copy / copy-object: an independent duplicate
;;; --------------------------------------------------------------------

(let ((orig (*the-root-object* 'derive)))
  (orig 'set-value-slot! 'x 'set-x! 99)
  (orig 'set-method-slot! 'greet (lambda (self resend) 'hi))
  (let ((dup (orig 'copy)))
    (check "copy duplicates value slots" (dup 'x) 99)
    (check "copy duplicates method slots" (dup 'greet) 'hi)
    (dup 'set-x! 5)
    (check "mutating the copy leaves the original alone" (orig 'x) 99)
    (check "the copy has its own value" (dup 'x) 5)
    (orig 'set-x! 77)
    (check "mutating the original leaves the copy alone" (dup 'x) 5)
    (check "the original has its own value" (orig 'x) 77)))

;;; --------------------------------------------------------------------
;;; (srfi 263 syntax): define-object, set-method!, derive-object, copy-object
;;; --------------------------------------------------------------------

(define-object testobject (*the-root-object*)
  ((compute self resend a b) (+ a b))   ; method slot
  (val 10)                              ; value slot
  (testval set-testval! 50))            ; value slot with a setter

(check "define-object method slot" (testobject 'compute 3 4) 7)
(check "define-object value slot" (testobject 'val) 10)
(check "define-object value+setter slot" (testobject 'testval) 50)
(testobject 'set-testval! 20)
(check "define-object setter works" (testobject 'testval) 20)

(set-method! (testobject methodslot self resend a b) (* a b))
(check "set-method! adds a method" (testobject 'methodslot 6 7) 42)

(let ((d (derive-object (testobject) (extra 999))))
  (check "derive-object adds a slot" (d 'extra) 999)
  (check "derive-object inherits parent slots" (d 'val) 10))

(let ((cp (copy-object (testobject))))
  (check "copy-object duplicates the object" (cp 'val) 10)
  (cp 'set-testval! 1)
  (check "copy-object is independent" (testobject 'testval) 20))

;;; --------------------------------------------------------------------

(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "SRFI 263 tests failed" fail))
