;;; SRFI 263 (Prototype Object System) conformance tests.
;;;
;;; Ports the reference implementation's test suite and adds coverage for the
;;; reflection procedures and mirror messages, working copy/copy-object,
;;; custom message-not-understood handlers, resend, private (non-symbol)
;;; selectors, and the (srfi 263 syntax) macros.

(import (scheme base)
        (scheme process-context)
        (scheme write)
        (srfi 1)
        (srfi 64)
        (srfi 263)
        (srfi 263 syntax))

(test-begin "srfi-263")

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

(test-assert "root has no ancestors"
             (null? ((*the-root-object* 'mirror) 'immediate-ancestor-list)))
(test-equal "root exposes 9 messages"
            9 (length ((*the-root-object* 'mirror) 'immediate-message-alist)))

(let ((class (*the-root-object* 'derive)))
  (test-assert "derived object's ancestor is the root"
               (eq? *the-root-object*
                    (car ((class 'mirror) 'immediate-ancestor-list))))

  (class 'set-method-slot! 'testmethod (lambda (self resend) 'success))
  (test-equal "method slot returns its value" 'success (class 'testmethod))

  (class 'set-value-slot! 'val 'set-val! 10)
  (test-equal "value slot getter" 10 (class 'val))
  (class 'set-val! 20)
  (test-equal "value slot after setter" 20 (class 'val))
  (test-equal "getter+setter add two messages"
              5 (length ((class 'mirror) 'immediate-message-alist)))

  (class 'set-value-slot! 'val 40)
  (test-equal "value slot with no setter" 40 (class 'val))
  (test-equal "redefining as getter-only drops the old setter"
              4 (length ((class 'mirror) 'immediate-message-alist)))

  ;; Deleting the setter keeps the getter.
  (class 'set-value-slot! 'val 'set-val! 10)
  (class 'delete-slot! 'set-val!)
  (test-equal "deleting the setter keeps the getter"
              4 (length ((class 'mirror) 'immediate-message-alist)))

  ;; Deleting the getter also deletes the setter.
  (class 'set-value-slot! 'val 'set-val! 10)
  (class 'delete-slot! 'val)
  (test-equal "deleting the getter also deletes the setter"
              3 (length ((class 'mirror) 'immediate-message-alist))))

;;; --------------------------------------------------------------------
;;; Inheritance
;;; --------------------------------------------------------------------

(let* ((firstlevel (*the-root-object* 'derive))
       (secondlevel (firstlevel 'derive)))
  (firstlevel 'set-method-slot! 'testmethod (lambda (self resend) 'success))
  (test-equal "method is inherited" 'success (secondlevel 'testmethod))

  (firstlevel 'set-value-slot! 'val 'set-val! 10)
  (test-equal "value is inherited" 10 (secondlevel 'val))

  ;; Setting through an inherited setter copies the slot onto the child.
  (secondlevel 'set-val! 20)
  (test-equal "parent value unchanged after child set" 10 (firstlevel 'val))
  (test-equal "child gets its own value" 20 (secondlevel 'val))

  (firstlevel 'set-value-slot! 'val #f 30)
  (test-equal "parent value can be changed independently" 30 (firstlevel 'val))
  (test-equal "child keeps its own value" 20 (secondlevel 'val))

  (test-equal "firstlevel full ancestry (self + root)"
              2 (length ((firstlevel 'mirror) 'full-ancestor-list)))
  (test-equal "secondlevel full ancestry (self + parent + root)"
              3 (length ((secondlevel 'mirror) 'full-ancestor-list)))

  ;; full-ancestor-list and has-ancestor return / test the real objects.
  (test-assert "full-ancestor-list contains the real parent"
               (and (memq firstlevel
                          ((secondlevel 'mirror) 'full-ancestor-list)) #t))
  (test-assert "has-ancestor is true for a real ancestor"
               ((secondlevel 'mirror) 'has-ancestor firstlevel))
  (test-assert "has-ancestor is false for self"
               (not ((secondlevel 'mirror) 'has-ancestor secondlevel)))
  (test-assert "has-ancestor is false for an unrelated object"
               (not ((secondlevel 'mirror) 'has-ancestor
                     (*the-root-object* 'derive)))))

;;; --------------------------------------------------------------------
;;; resend: to super from an overriding method, and to an explicit target
;;; --------------------------------------------------------------------

(let* ((base (*the-root-object* 'derive))
       (sub (base 'derive)))
  (base 'set-method-slot! 'name (lambda (self resend) 'base))
  (sub 'set-method-slot! 'name (lambda (self resend) (list 'sub (resend #f))))
  (test-equal "resend #f from an overriding method reaches the parent"
              '(sub base) (sub 'name)))

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

  (test-equal "adder method" 10 (adderclass 'inc 9))
  (test-equal "square method" 9 (squareclass 'square 3))
  (test-equal "method inherited across a second parent" 9 (mathclass 'inc 8))

  (test-assert "unknown message signals an error"
               (raises? (lambda () (adderclass 'nope 10))))

  ;; Both parents define 'reset -> ambiguous.
  (adderclass 'set-method-slot! 'reset (lambda (self resend x) 5))
  (squareclass 'set-method-slot! 'reset (lambda (self resend x) 5))
  (test-assert "ambiguous message signals an error"
               (raises? (lambda () (mathclass 'reset 1))))

  (test-equal "two immediate parents"
              2 (length ((mathclass 'mirror) 'immediate-ancestor-list)))
  (mathclass 'delete-slot! 'adder)
  (test-equal "deleting a parent slot removes the ancestor"
              1 (length ((mathclass 'mirror) 'immediate-ancestor-list))))

;;; --------------------------------------------------------------------
;;; Custom message-not-understood handler (SRFI-mandated, overridable)
;;; --------------------------------------------------------------------

(let ((obj (*the-root-object* 'derive)))
  (obj 'set-method-slot! 'message-not-understood
       (lambda (self resend message args) (list 'dnu message args)))
  (test-equal "custom message-not-understood intercepts unknown messages"
              '(dnu whatever (1 2)) (obj 'whatever 1 2)))

;;; --------------------------------------------------------------------
;;; Private messages: unforgeable non-symbol selectors
;;; --------------------------------------------------------------------

(let ((obj (*the-root-object* 'derive))
      (secret (list 'unforgeable)))
  (obj 'set-method-slot! secret (lambda (self resend) 'private-hit))
  (test-equal "dispatch on a non-symbol (unforgeable) selector"
              'private-hit (obj secret))
  (test-assert "the private selector is not reachable as a symbol"
               (raises? (lambda () (obj 'unforgeable)))))

;;; --------------------------------------------------------------------
;;; Slot reflection: slot?, slot-getter, slot-setter, slot-type; full-slot-list
;;; --------------------------------------------------------------------

(let ((cls (*the-root-object* 'derive)))
  (cls 'set-value-slot! 'foo 'set-foo! 1)
  (cls 'set-method-slot! 'bar (lambda (self resend) 'b))
  (let* ((slots ((cls 'mirror) 'immediate-slot-list))
         (foo (find (lambda (s) (eq? (slot-getter s) 'foo)) slots))
         (bar (find (lambda (s) (eq? (slot-getter s) 'bar)) slots))
         (par (find (lambda (s) (eq? (slot-type s) 'parent)) slots)))
    (test-assert "slot? recognises a slot" (slot? foo))
    (test-assert "slot? rejects a non-slot" (not (slot? 'foo)))
    (test-equal "value slot getter name" 'foo (slot-getter foo))
    (test-equal "value slot setter name" 'set-foo! (slot-setter foo))
    (test-equal "value slot type" 'value (slot-type foo))
    (test-equal "method slot type" 'method (slot-type bar))
    (test-equal "method slot has no setter" #f (slot-setter bar))
    (test-assert "parent slot present" (slot? par))
    (test-equal "parent slot type" 'parent (slot-type par))
    ;; full-slot-list includes the receiver's own slots (foo, bar) and does
    ;; not crash unioning slot records.
    (test-assert "full-slot-list includes the object's own slots"
                 (let ((getters (map slot-getter
                                     ((cls 'mirror) 'full-slot-list))))
                   (and (memq 'foo getters) (memq 'bar getters) #t)))))

;;; --------------------------------------------------------------------
;;; copy / copy-object: an independent duplicate (incl. the root object)
;;; --------------------------------------------------------------------

(let ((orig (*the-root-object* 'derive)))
  (orig 'set-value-slot! 'x 'set-x! 99)
  (orig 'set-method-slot! 'greet (lambda (self resend) 'hi))
  (let ((dup (orig 'copy)))
    (test-equal "copy duplicates value slots" 99 (dup 'x))
    (test-equal "copy duplicates method slots" 'hi (dup 'greet))
    (dup 'set-x! 5)
    (test-equal "mutating the copy leaves the original alone" 99 (orig 'x))
    (test-equal "the copy has its own value" 5 (dup 'x))
    (orig 'set-x! 77)
    (test-equal "mutating the original leaves the copy alone" 5 (dup 'x))
    (test-equal "the original has its own value" 77 (orig 'x))))

;; A copy of the parentless root object must not alias the global root.
(let ((rootcopy (*the-root-object* 'copy)))
  (rootcopy 'set-value-slot! 'copied-marker 123)
  (test-equal "root copy sees its own slot" 123 (rootcopy 'copied-marker))
  (test-assert "root copy does not pollute the global root object"
               (raises? (lambda () (*the-root-object* 'copied-marker)))))

;;; --------------------------------------------------------------------
;;; (srfi 263 syntax): define-object, define-method / set-method!,
;;; derive-object, copy-object
;;; --------------------------------------------------------------------

(define-object testobject (*the-root-object*)
  ((compute self resend a b) (+ a b))   ; method slot
  (val 10)                              ; value slot
  (testval set-testval! 50))            ; value slot with a setter

(test-equal "define-object method slot" 7 (testobject 'compute 3 4))
(test-equal "define-object value slot" 10 (testobject 'val))
(test-equal "define-object value+setter slot" 50 (testobject 'testval))
(testobject 'set-testval! 20)
(test-equal "define-object setter works" 20 (testobject 'testval))

;; define-method is SRFI 263's documented name; set-method! is the alias.
(define-method (testobject methodslot self resend a b) (* a b))
(test-equal "define-method adds a method" 42 (testobject 'methodslot 6 7))
(set-method! (testobject aliased self resend a) (- a 1))
(test-equal "set-method! alias adds a method" 4 (testobject 'aliased 5))

;; A secondary named parent exercises the repeated set-parent-slot! branch
;; of derive-object / copy-object.
(define helper (*the-root-object* 'derive))
(helper 'set-method-slot! 'help (lambda (self resend) 'helped))

(let ((d (derive-object (testobject (aux helper)) (extra 999))))
  (test-equal "derive-object adds a slot" 999 (d 'extra))
  (test-equal "derive-object inherits creation-parent slots" 10 (d 'val))
  (test-equal "derive-object inherits named-parent methods" 'helped (d 'help)))

(let ((cp (copy-object (testobject (aux helper)))))
  (test-equal "copy-object duplicates the object" 10 (cp 'val))
  (test-equal "copy-object inherits named-parent methods" 'helped (cp 'help))
  (cp 'set-testval! 1)
  (test-equal "copy-object is independent" 20 (testobject 'testval)))

;;; --------------------------------------------------------------------

(let ((runner (test-runner-current)))
  (test-end "srfi-263")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
