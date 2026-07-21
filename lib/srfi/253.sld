;;; SRFI 253: Data (Type-)Checking
;;;
;;; Provides data validation and type-checking primitives: check-arg for
;;; argument validation, values-checked for return value checking,
;;; check-case for predicate dispatch, lambda-checked / define-checked /
;;; case-lambda-checked for checked procedures, and
;;; define-record-type-checked for records with field type constraints.
;;;
;;; Reference: https://srfi.schemers.org/srfi-253/srfi-253.html
;;; License: MIT
;;; Author: Artyom Bologov (reference impl); ported to Kaappi

(define-library (srfi 253)
  (import (scheme base)
          (scheme case-lambda))
  (export check-arg values-checked
          check-case
          lambda-checked define-checked
          case-lambda-checked
          define-record-type-checked)
  (begin

    ;; assume — checks the expression and raises on failure (debug branch).
    (define-syntax assume
      (syntax-rules ()
        ((_ expr rest ...)
         (or (and expr #t)
             (error "assumption violated" 'expr rest ...)))))

    ;; check-arg — validate a value against a predicate.
    (define-syntax check-arg
      (syntax-rules ()
        ((_ pred val caller)
         (assume (pred val) "argument should match the specification"
                 '(pred val) val caller))
        ((_ pred val)
         (check-arg pred val 'check-arg))))

    ;; values-checked — check return values against predicates.
    (define-syntax values-checked
      (syntax-rules ()
        ((_ (predicate) value)
         (let ((v value))
           (check-arg predicate v 'values-checked)
           v))
        ((_ (predicate ...) value ...)
         (values (values-checked (predicate) value) ...))))

    ;; check-case — predicate dispatch.
    (define-syntax %check-case
      (syntax-rules (else)
        ((_ val (clause ...) (else body ...))
         (cond
           clause ...
           (else body ...)))
        ((_ val ((clause-check clause-body ...) ...))
         (cond
           (clause-check clause-body ...)
           ...
           (else (assume (or clause-check ...)
                         "at least one branch of check-case should be true"
                         'clause-check ...))))
        ((_ val (clause ...) (pred body ...) rest ...)
         (%check-case
          val
          (clause ... ((pred val) body ...))
          rest ...))))
    (define-syntax check-case
      (syntax-rules ()
        ((_ value clause ...)
         (let ((v value))
           (%check-case v () clause ...)))))

    ;; %lambda-checked — internal helper for lambda-checked.
    ;; Processes argument list, separating checked (arg pred) from unchecked args,
    ;; builds arg list and check expressions, handles => return checking.
    (define-syntax %lambda-checked
      (syntax-rules (=>)
        ;; Terminal: with return check
        ((_ name (=> (returns ...) body ...) args (checks ...))
         (lambda args
           checks ...
           (values-checked
            (returns ...)
            (begin body ...))))
        ;; Terminal: without return check
        ((_ name (body ...) args (checks ...))
         (lambda args
           checks ...
           body ...))
        ;; Process checked arg (arg pred)
        ((_ name body (args ...) (checks ...) (arg pred) . rest)
         (%lambda-checked
          name body
          (args ... arg) (checks ... (check-arg pred arg 'name)) . rest))
        ;; Process unchecked arg
        ((_ name body (args ...) (checks ...) arg . rest)
         (%lambda-checked
          name body
          (args ... arg) (checks ...) . rest))
        ;; Rest arg (dotted tail)
        ((_ name body (args ...) (checks ...) . last)
         (%lambda-checked
          name body
          (args ... . last) (checks ...)))))

    ;; lambda-checked — lambda with type-checked arguments.
    (define-syntax lambda-checked
      (syntax-rules ()
        ((_ () body ...)
         (lambda () body ...))
        ((_ (arg . args) body ...)
         (%lambda-checked lambda-checked (body ...) () () arg . args))
        ;; Rest-arg lambda (no-op, can't check)
        ((_ arg body ...)
         (lambda arg body ...))))

    ;; define-checked — define with type-checked arguments or variable.
    (define-syntax define-checked
      (syntax-rules ()
        ;; Procedure
        ((_ (name . args) body ...)
         (define name (%lambda-checked name (body ...) () () . args)))
        ;; Variable
        ((_ name pred value)
         (define name (values-checked (pred) value)))))

    ;; case-lambda-checked — case-lambda with per-clause type checking.
    ;;
    ;; Strategy: two macros in CPS style.
    ;; %clc-clauses: iterates over clauses, dispatching each to %clc-process.
    ;; %clc-process: walks a single clause's arg list, accumulates checked
    ;; formals and check expressions, then calls back to %clc-clauses with the
    ;; finished clause appended.

    ;; %clc-process: walk one clause's arg list, then return to %clc-clauses.
    ;; Arguments: (done ...) (remaining ...) (formals ...) (checks ...) arg-tail (body ...)
    ;; "arg-tail" shrinks as args are consumed; () means all args processed.
    (define-syntax %clc-process
      (syntax-rules (=>)
        ;; All args consumed — body starts with =>  (return-value checking)
        ((_ (done ...) (remaining ...)
            formals (checks ...)
            () (=> (returns ...) body ...))
         (%clc-clauses
          (done ...
           (formals
            checks ...
            (values-checked (returns ...) (begin body ...))))
          remaining ...))
        ;; All args consumed — plain body
        ((_ (done ...) (remaining ...)
            formals (checks ...)
            () (body ...))
         (%clc-clauses
          (done ...
           (formals
            checks ...
            body ...))
          remaining ...))
        ;; Next arg is checked: (arg pred)
        ((_ done remaining
            (formals ...) (checks ...)
            ((arg pred) . rest)
            body)
         (%clc-process
          done remaining
          (formals ... arg)
          (checks ... (check-arg pred arg 'case-lambda-checked))
          rest body))
        ;; Next arg is unchecked
        ((_ done remaining
            (formals ...) (checks ...)
            (arg . rest)
            body)
         (%clc-process
          done remaining
          (formals ... arg) (checks ...)
          rest body))
        ;; Remaining arg-tail is a bare symbol (rest parameter)
        ((_ done remaining
            (formals ...) (checks ...)
            rest-sym
            body)
         (%clc-process
          done remaining
          (formals ... . rest-sym) (checks ...)
          () body))))

    ;; %clc-clauses: iterate over user clauses, accumulating done clauses.
    (define-syntax %clc-clauses
      (syntax-rules (=>)
        ;; No more clauses — emit case-lambda
        ((_ (done ...))
         (case-lambda done ...))
        ;; Clause with empty formals and => return check
        ((_ (done ...)
            (() => (returns ...) body ...)
            remaining ...)
         (%clc-clauses
          (done ...
           (() (values-checked (returns ...) (begin body ...))))
          remaining ...))
        ;; Clause with empty formals, plain body
        ((_ (done ...)
            (() body ...)
            remaining ...)
         (%clc-clauses
          (done ... (() body ...))
          remaining ...))
        ;; Clause with formals list (pair) — dispatch to %clc-process
        ((_ (done ...)
            ((first . more) body ...)
            remaining ...)
         (%clc-process
          (done ...) (remaining ...)
          () ()
          (first . more) (body ...)))
        ;; Clause with rest-arg (bare symbol)
        ((_ (done ...)
            (rest-sym body ...)
            remaining ...)
         (%clc-process
          (done ...) (remaining ...)
          () ()
          rest-sym (body ...)))))

    (define-syntax case-lambda-checked
      (syntax-rules ()
        ((_ clause ...)
         (%clc-clauses () clause ...))))

    ;; define-record-type-checked — record type with checked constructor,
    ;; accessors, and mutators.

    ;; Helper: process fields, building internal record fields and wrapper defs.
    (define-syntax %define-record-type-checked
      (syntax-rules ()
        ;; Terminal: all fields processed
        ((_ type-name constructor predicate
            (fields ...) (field-wrappers ...))
         (begin
           (define-record-type
               type-name constructor predicate
               fields ...)
           field-wrappers ...))
        ;; Field with accessor and mutator: (field pred accessor modifier)
        ((_ type-name constructor predicate
            (fields ...) (field-wrappers ...) (field pred accessor modifier)
            fields-to-process ...)
         (%define-record-type-checked
          type-name constructor predicate
          (fields ... (field internal-accessor internal-modifier))
          (field-wrappers
           ...
           (define-checked (accessor (record predicate))
             (internal-accessor record))
           (define-checked (modifier (record predicate) (val pred))
             (internal-modifier record val)))
          fields-to-process ...))
        ;; Field with accessor only: (field pred accessor)
        ((_ type-name constructor predicate
            (fields ...) (field-wrappers ...) (field pred accessor)
            fields-to-process ...)
         (%define-record-type-checked
          type-name constructor predicate
          (fields ... (field internal-accessor))
          (field-wrappers
           ...
           (define-checked (accessor (record predicate))
             (internal-accessor record)))
          fields-to-process ...))))

    ;; Helper: wrap the constructor with type checks on constructor args.
    ;; Walks the field list to build checked arg pairs.
    (define-syntax %wrap-constructor
      (syntax-rules ()
        ;; Terminal: all constructor fields processed
        ((_ constructor internal-constructor (arg-names ...) (args ...))
         (define-checked (constructor args ...)
           (internal-constructor arg-names ...)))
        ;; Process one field: extract (name pred ...)
        ((_ constructor internal-constructor (arg-names ...) (args ...)
            (name pred rest ...) fields-to-process ...)
         (%wrap-constructor constructor internal-constructor
                            (arg-names ... name) (args ... (name pred))
                            fields-to-process ...))))

    (define-syntax define-record-type-checked
      (syntax-rules ()
        ((_ type-name (constructor constructor-args ...) predicate field ...)
         (begin
           (%define-record-type-checked
            type-name
            (internal-constructor constructor-args ...)
            predicate
            () () field ...)
           (%wrap-constructor constructor internal-constructor () ()
                              field ...)))))))
