;;; SRFI 273 test suite — Extensions to Data (Type-)Checking
;;;
;;; Covers what this SRFI adds over SRFI 253: define-check, declare-checked,
;;; define-values-checked, the check-impl? auxiliary syntax, and the =>
;;; return-value checking contributed to the (srfi 253) forms (which
;;; (srfi 273) re-exports). Follows the spec's own examples where it has
;;; them; the optimizable-pattern section checks that the suggested patterns
;;; compose as ordinary predicates (Kaappi does not statically recognize
;;; them — recognition is optional per the SRFI).

(import (scheme base)
        (scheme case-lambda)
        (scheme char)
        (srfi 1)
        (srfi 26)
        (srfi 235)
        (srfi 253)
        (srfi 273)
        (srfi 64))

(test-begin "srfi-273")

;;; ====================================================================
;;; Availability. The library loads standalone and answers its feature
;;; identifier.
;;; ====================================================================

(test-assert (cond-expand (srfi-273 #t) (else #f)))
(test-assert (cond-expand ((library (srfi 273)) #t) (else #f)))

;;; ====================================================================
;;; Re-exports. Importing (srfi 273) alone gives the full (srfi 253)
;;; vocabulary (extended with => return-value checking).
;;; ====================================================================

(test-begin "re-exports")

(test-assert (begin (check-arg integer? 3) #t))
(test-error (check-arg integer? "hello"))
(test-equal 3 (values-checked (integer?) 3))
(test-equal 'int (check-case 3 (integer? 'int) (else 'other)))
(test-assert ((lambda-checked ((a integer?)) #t) 3))
(test-assert (case-lambda-checked
              (((a integer?)) #t)
              (args #t)))
(define-record-type-checked <boxed>
  (make-boxed n)
  boxed?
  (n integer? boxed-n))
(test-assert (boxed-n (make-boxed 3)))
(test-error (boxed-n (make-boxed "hello")))

(test-end "re-exports")

;;; ====================================================================
;;; define-check
;;; ====================================================================

(test-begin "define-check")

;; The spec's examples.
(define-check any? (constantly #t))
(test-assert (any? 123))
(test-assert (any? "anything at all"))
(define-check email? string?)
(test-assert (email? "srfi-273@example.com"))
(test-assert (not (email? 42)))
(define-check positive-integer? (conjoin integer? positive?))
(test-assert (positive-integer? 3))
(test-assert (not (positive-integer? -3)))

;; The aliased checks compose with the SRFI 253 forms.
(test-assert (begin (check-arg email? "srfi-273@example.com") #t))
(test-error (check-arg positive-integer? -3))
(test-equal 4 (values-checked (positive-integer?) 4))
(test-error (values-checked (positive-integer?) -4))
(define-checked (twice (n positive-integer?)) => (positive-integer?) (* n 2))
(test-equal 8 (twice 4))
(test-error (twice -4))

;; A lambda works as the predicate too.
(define-check palindromic-string?
  (lambda (s)
    (and (string? s)
         (string=? s (list->string (reverse (string->list s)))))))
(test-assert (palindromic-string? "racecar"))
(test-assert (not (palindromic-string? "kaappi")))

(test-end "define-check")

;;; ====================================================================
;;; declare-checked
;;;
;;; Declarations are advisory: they expand to nothing (the reference
;;; implementation's choice), so what we test is that every shape expands
;;; and evaluates without error — including declarations for imported
;;; identifiers, which the spec "highly recommends" supporting — and that
;;; the separately defined procedure keeps its normal behavior.
;;; ====================================================================

(test-begin "declare-checked")

;; Value declaration, then the definition it anticipates.
(declare-checked numbered-answer integer?)
(define numbered-answer 42)
(test-equal 42 numbered-answer)

;; Procedure declaration with argument checks only.
(declare-checked (numbered-string (str string?) (idx integer?)))
(define (numbered-string str idx)
  (string-append str (number->string idx)))
(test-equal "x3" (numbered-string "x" 3))
(test-equal "x-3" (numbered-string "x" -3))

;; Procedure declaration with argument and return checks — the spec's
;; post-factum-hardening example.
(declare-checked (negative? (x real?)) => (boolean?))
(test-assert (negative? -1))
(test-assert (not (negative? 1)))

;; Declaring an imported variadic procedure.
(declare-checked (string-append (a string?) (b string?)) => (string?))
(test-equal "ab" (string-append "a" "b"))

;; Declarations also work in bodies, not just at the top level.
(test-assert
 (let ()
   (declare-checked local-decl integer?)
   #t))

;; The declaration's value is unspecified: it must evaluate without error
;; (the expression above did exactly that), which is all a portable program
;; may rely on.

(test-end "declare-checked")

;;; ====================================================================
;;; define-values-checked
;;; ====================================================================

(test-begin "define-values-checked")

(define-values-checked (q r) (integer? integer?) (values 3 1))
(test-equal 3 q)
(test-equal 1 r)

(define-values-checked (n) (integer?) 42)
(test-equal 42 n)

(define-values-checked (name rank) (string? symbol?) (values "kaappi" 'srfi))
(test-equal "kaappi" name)
(test-equal 'srfi rank)

;; The form is evaluated exactly once: its effects must not be duplicated.
(define effect-count 0)
(define-values-checked (a b) (integer? integer?)
  (begin
    (set! effect-count (+ effect-count 1))
    (values 1 2)))
(test-equal 1 effect-count)
(test-equal 1 a)
(test-equal 2 b)

;; Failing checks are errors at binding time.
(test-error
 (let ()
   (define-values-checked (n) (integer?) "hello")
   'ok))
(test-error
 (let ()
   (define-values-checked (a b) (integer? string?) (values 1 2))
   'ok))
;; Fewer values than variables is an error, as with define-values.
(test-error
 (let ()
   (define-values-checked (a b) (integer? integer?) (values 1))
   'ok))

(test-end "define-values-checked")

;;; ====================================================================
;;; check-impl?
;;;
;;; The (check-impl? datum) wrapper is discarded as a non-predicate and the
;;; datum is passed to the implementation unaltered. Kaappi has no
;;; implementation-specific check datatypes, so a bound datum behaves as
;;; itself and an unknown datum (uint, pointer, ...) is an unbound
;;; variable — the spec's (values-checked ((check-impl? uint)) -1) is an
;;; error here.
;;; ====================================================================

(test-begin "check-impl?")

(test-assert (values-checked ((check-impl? integer?)) 3))
(test-error (values-checked ((check-impl? integer?)) "hello"))
(test-error (values-checked ((check-impl? uint)) -1))

;; In check-arg (a macro here, so the auxiliary syntax is usable).
(test-assert (begin (check-arg (check-impl? string?) "ok") #t))
(test-error (check-arg (check-impl? string?) 3))

;; In checked argument position — the spec's FFI example shape. The
;; argument check runs before the body, so the unknown datum errors at
;; call time.
(define-checked (ffi-ref (data (check-impl? pointer)) (idx integer?)) idx)
(test-error (ffi-ref 'anything 0))
(define-checked (str-ref (s (check-impl? string?)) (idx integer?))
  (string-ref s idx))
(test-equal #\k (str-ref "kaappi" 0))

;; In check-case clauses.
(test-equal 'int (check-case 3 ((check-impl? integer?) 'int) (else 'other)))
(test-equal 'other (check-case "x" ((check-impl? integer?) 'int) (else 'other)))
(test-error (check-case "x" ((check-impl? no-such-check) 'int)))

;; A defined check from define-check composes through check-impl? too.
(test-assert (values-checked ((check-impl? email?)) "ab@example.org"))

(test-end "check-impl?")

;;; ====================================================================
;;; Return-value checks (=>). These extend the (srfi 253) forms; they are
;;; re-tested here because SRFI 273 is what specifies them.
;;; ====================================================================

(test-begin "return-value-checks")

;; lambda-checked
(test-equal 2 ((lambda-checked ((n integer?)) => (integer?) (+ n 1)) 1))
(test-error ((lambda-checked ((n integer?)) => (integer?) #t) 1))
;; Empty formals.
(test-equal 1 ((lambda-checked () => (integer?) 1)))
(test-error ((lambda-checked () => (integer?) #t)))
;; Rest formals.
(test-equal 3 ((lambda-checked all => (integer?) (length all)) 'a 'b 'c))
(test-error ((lambda-checked all => (integer?) #t) '()))
;; Multiple return values.
(define-values (m1 m2)
  ((lambda-checked ((n integer?)) => (integer? integer?) (values n n)) 7))
(test-equal 7 m1)
(test-equal 7 m2)
;; Each value is checked against its own predicate, in order, and the
;; returned order is preserved.
(define-values (s1 s2 s3)
  ((lambda-checked () => (integer? string? symbol?) (values 7 "x" 'sym))))
(test-equal 7 s1)
(test-equal "x" s2)
(test-equal 'sym s3)
(test-assert
 ((lambda-checked ((n integer?)) => (integer? string?) (values n "x")) 7))
(test-error
 ((lambda-checked ((n integer?)) => (string? integer?) (values n "x")) 7))
(test-error
 ((lambda-checked ((n string?)) => (integer? string?) (values n "x")) "n"))
;; The number of values must match the number of predicates — in either
;; direction, as with values-checked. The count is rejected up front, so the
;; error is the documented arity one whatever the predicates are: a short
;; value list must not pair predicate k with value k-M and fail inside a
;; predicate check instead.
(define (count-mismatch-error? thunk)
  (guard (ex ((and (error-object? ex)
                   (string=? (error-object-message ex)
                             "number of values and predicates should match"))
             #t))
    (thunk)
    #f))
(test-assert
 (count-mismatch-error?
  (lambda () ((lambda-checked () => (integer? string? symbol?) (values 1 'two))))))
(test-assert
 (count-mismatch-error?
  (lambda () ((lambda-checked () => (integer? string?) (values 1))))))
(test-assert
 (count-mismatch-error?
  (lambda () ((lambda-checked () => (integer? string?) (values))))))
(test-assert
 (count-mismatch-error?
  (lambda () ((lambda-checked () => (integer? string? symbol?)
                (values 1 'two "three" 'four))))))
;; A single predicate goes through its own fast path — any count other than
;; one is still an error.
(test-error
 ((lambda-checked () => (integer?) (values 1 'two "three"))))

;; define-checked
(define-checked (re-checked (n integer?)) => (integer?) (* n 2))
(test-equal 8 (re-checked 4))
(test-error (re-checked "four"))
(define-checked (re-checked-bad (n integer?)) => (string?) (* n 2))
(test-error (re-checked-bad 4))
(define-checked (re-multi (n integer?) (d integer?)) => (integer? integer?)
  (values (quotient n d) (remainder n d)))
(define-values (qq rr) (re-multi 7 2))
(test-equal 3 qq)
(test-equal 1 rr)
(test-error ((lambda-checked ((n integer?)) => (string?) (if (> n 0) n #t)) 5))

;; case-lambda-checked
(define clc-return
  (case-lambda-checked
   (() => (integer?) 1)
   (((n integer?)) => (integer?) (+ n 1))
   (args => (integer?) (length args))))
(test-equal 1 (clc-return))
(test-equal 3 (clc-return 2))
(test-equal 4 (clc-return 'a 'b 'c 'd))
(define clc-return-bad
  (case-lambda-checked
   (() => (integer?) #t)))
(test-error (clc-return-bad))

;; Unchecked argument lists with return checks still check the returns.
(test-equal 5 ((lambda-checked (a b) => (integer?) (+ a b)) 2 3))
(test-error ((lambda-checked (a b) => (integer?) #t) 2 3))

(test-end "return-value-checks")

;;; ====================================================================
;;; Optimizable patterns. Recognition is optional per the SRFI; here the
;;; patterns only need to work as ordinary checking predicates.
;;; ====================================================================

(test-begin "optimizable-patterns")

(test-assert ((disjoin integer? string?) 3))
(test-assert ((disjoin integer? string?) "x"))
(test-assert (not ((disjoin integer? string?) 'sym)))
(test-assert ((conjoin integer? positive?) 3))
(test-assert (not ((conjoin integer? positive?) -3)))
(test-assert ((complement integer?) "x"))
(test-assert (not ((complement integer?) 3)))
(test-assert ((cut memv <> '(1 2 3)) 2))
(test-assert (not ((cut memv <> '(1 2 3)) 4)))
(test-assert ((cut eqv? <> 'sym) 'sym))
(test-assert ((cut every integer? <>) '(1 2 3)))
(test-assert (not ((cut every integer? <>) '(1 "x" 3))))
(test-assert ((cut every char? <>) (string->list "kaappi")))
(test-assert ((constantly #t) 'anything))
(test-assert (not ((constantly #f) 'anything)))

;; Through the checking forms.
(test-assert (begin (check-arg (disjoin integer? string?) "ok") #t))
(test-error (check-arg (conjoin integer? positive?) -1))
(test-assert (begin (check-arg (cut every integer? <>) '(1 2)) #t))
(test-error (begin (check-arg (cut every integer? <>) '(1 #\a)) #t))
(test-equal 'small (check-case 3 ((cut memv <> '(1 2 3)) 'small) (else 'other)))
(test-equal 'other (check-case 9 ((cut memv <> '(1 2 3)) 'small) (else 'other)))

(test-end "optimizable-patterns")

;;; ---- summary ----

(let ((runner (test-runner-current)))
  (test-end "srfi-273")
  (when (> (test-runner-fail-count runner) 0)
    (exit 1)))
