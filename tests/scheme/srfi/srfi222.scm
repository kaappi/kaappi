;; SRFI 222 (Compound Objects) conformance tests.
;;
;; Written by the systematic audit v2, Phase 3.7 (issue #1890) -- SRFI 222
;; had no test file at all. The oracle is the SRFI's own Specification
;; section; chibi-scheme 0.12.0 does not ship SRFI 222, so there is no
;; cross-implementation oracle for this one.
;;
;; What this file pins is #2072: (srfi 222) used to export 5 of the spec's
;; 10 procedures, `make-compound' did not flatten nested compound objects,
;; and `compound-subobjects' raised on a non-compound instead of returning a
;; one-element list. `(cond-expand (srfi-222 ...))' answers #t regardless, so
;; nothing else in the tree could detect the shortfall.
;;
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi222.scm

(import (scheme base) (scheme write) (srfi 64) (srfi 222))

(test-begin "srfi-222")

;;; --------------------------------------------------------------------
;;; The spec's own worked example, rebuilt with record types.
;;; --------------------------------------------------------------------

(define-record-type <student>
  (student institution year gpa) student?
  (institution student-institution) (year student-year) (gpa student-gpa))

(define-record-type <teacher>
  (teacher institution hire-year salary) teacher?
  (institution teacher-institution) (hire-year teacher-hire-year)
  (salary teacher-salary))

(define alyssa (student 'MIT 1979 3.8))
(define george (make-compound 'teaching-assistant
                              (student 'MIT 1979 3.8)
                              (teacher 'MIT 1983 1000)))

;;; --------------------------------------------------------------------
;;; compound? -- "Returns #t if obj is a compound object, and #f otherwise."
;;; --------------------------------------------------------------------

(test-equal "compound? on a compound" #t (compound? george))
(test-equal "compound? on a non-compound record" #f (compound? alyssa))
(test-equal "compound? on a symbol" #f (compound? 'plain))
(test-equal "compound? on a list" #f (compound? (list 1 2)))
(test-equal "compound? on a vector" #f (compound? (vector 1 2)))
(test-equal "compound? on a number" #f (compound? 42))
(test-equal "compound? on a string" #f (compound? "s"))
(test-equal "compound? on the empty list" #f (compound? '()))
(test-equal "compound? on a procedure" #f (compound? car))
(test-equal "compound? on an empty compound" #t (compound? (make-compound)))

;; Compound objects are their own disjoint type.
(test-equal "a compound is not a pair" #f (pair? (make-compound 1)))
(test-equal "a compound is not a vector" #f (vector? (make-compound 1)))
(test-equal "a compound is not a procedure" #f (procedure? (make-compound 1)))
(test-equal "a compound is not a string" #f (string? (make-compound 1)))

;;; --------------------------------------------------------------------
;;; compound-length -- "If obj is a compound object, returns the number of
;;; its subobjects as an exact integer. Otherwise, it returns 1."
;;; --------------------------------------------------------------------

(test-equal "compound-length of the spec's george" 3 (compound-length george))
(test-equal "compound-length of a non-compound is 1" 1 (compound-length alyssa))
(test-equal "compound-length of a symbol is 1" 1 (compound-length 'plain))
(test-equal "compound-length of a list is 1 (not its length)" 1
            (compound-length (list 1 2 3)))
(test-equal "compound-length of the empty compound is 0" 0
            (compound-length (make-compound)))
(test-equal "compound-length is exact" #t (exact? (compound-length george)))
(test-equal "compound-length is an integer" #t (integer? (compound-length george)))

;;; --------------------------------------------------------------------
;;; compound-ref -- "If obj is a compound object, returns the kth subobject.
;;; Otherwise, obj is returned. In either case, it is an error if k is less
;;; than zero, or greater than or equal to (compound-length obj)."
;;; --------------------------------------------------------------------

(define flat (make-compound 'a 'b 'c))

(test-equal "compound-ref 0" 'a (compound-ref flat 0))
(test-equal "compound-ref 1" 'b (compound-ref flat 1))
(test-equal "compound-ref last" 'c (compound-ref flat 2))
(test-equal "compound-ref on a non-compound at 0 returns obj" 'plain
            (compound-ref 'plain 0))
(test-assert "compound-ref past the end raises"
             (guard (e (#t #t)) (compound-ref flat 3) #f))
(test-assert "compound-ref at a negative index raises"
             (guard (e (#t #t)) (compound-ref flat -1) #f))
(test-assert "compound-ref on a non-compound at 1 raises"
             (guard (e (#t #t)) (compound-ref 'plain 1) #f))
(test-assert "compound-ref on the empty compound raises"
             (guard (e (#t #t)) (compound-ref (make-compound) 0) #f))

;;; --------------------------------------------------------------------
;;; compound-subobjects -- the compound case, which is correct today.
;;; --------------------------------------------------------------------

(test-equal "compound-subobjects of a flat compound" '(a b c)
            (compound-subobjects flat))
(test-equal "compound-subobjects of the empty compound" '()
            (compound-subobjects (make-compound)))
(test-equal "compound-subobjects preserves order" '(1 2 3)
            (compound-subobjects (make-compound 1 2 3)))
(test-equal "compound-subobjects length agrees with compound-length" #t
            (= (length (compound-subobjects flat)) (compound-length flat)))

;;; --------------------------------------------------------------------
;;; make-compound -- the non-nesting cases, which are correct today.
;;; --------------------------------------------------------------------

(test-equal "make-compound with no arguments is an empty compound" 0
            (compound-length (make-compound)))
(test-equal "make-compound of one object" '(x) (compound-subobjects (make-compound 'x)))
(test-equal "make-compound accepts any Scheme object" '(1 "s" #\c ())
            (compound-subobjects (make-compound 1 "s" #\c '())))
(test-equal "make-compound returns a fresh object each time" #f
            (eq? (make-compound 1) (make-compound 1)))

;;; --------------------------------------------------------------------
;;; The library is reachable and advertises itself.
;;; --------------------------------------------------------------------

(test-equal "cond-expand sees srfi-222" #t (cond-expand (srfi-222 #t) (else #f)))
(test-equal "cond-expand sees (library (srfi 222))" #t
            (cond-expand ((library (srfi 222)) #t) (else #f)))

;;; --------------------------------------------------------------------
;;; #2072 -- three defects, one root cause (an incomplete port).
;;;
;;; (1) make-compound did not flatten nested compound objects, though the
;;;     spec says "If any object in objs is itself a compound object, it is
;;;     flattened into its subobjects, which are then added to the compound
;;;     object in sequence."
;;; --------------------------------------------------------------------

(test-equal "make-compound flattens a nested compound (length)" 4
            (compound-length (make-compound 1 2 (make-compound 3 4))))
(test-equal "make-compound flattens a nested compound (subobjects)" '(1 2 3 4)
            (compound-subobjects (make-compound 1 2 (make-compound 3 4))))
(test-equal "make-compound flattens a leading nested compound" '(1 2 3)
            (compound-subobjects (make-compound (make-compound 1 2) 3)))
(test-equal "make-compound flattens an empty nested compound away" '(1 2)
            (compound-subobjects (make-compound 1 (make-compound) 2)))
(test-equal "make-compound flattens two nested compounds" '(1 2 3 4)
            (compound-subobjects
             (make-compound (make-compound 1 2) (make-compound 3 4))))
(test-equal "flattening is one level deep per argument, applied recursively" '(1 2 3)
            (compound-subobjects
             (make-compound (make-compound 1 (make-compound 2)) 3)))

;;; (2) compound-subobjects raised on a non-compound; the spec says
;;;     "otherwise, returns a list containing only obj".

(test-equal "compound-subobjects of a non-compound is a one-element list" '(plain)
            (compound-subobjects 'plain))
(test-equal "compound-subobjects of a number" '(42) (compound-subobjects 42))
(test-equal "compound-subobjects of a list is the list in a list" '((1 2))
            (compound-subobjects (list 1 2)))

;;; (3) Five of the ten specified procedures were not exported at all:
;;;     compound-map, compound-map->list, compound-filter,
;;;     compound-predicate, compound-access. The assertions below are
;;;     written against the spec's own examples.

(test-equal "compound-map over a compound" '(-1 -2 -3 -4 -5)
            (compound-subobjects (compound-map - (make-compound 1 2 3 4 5))))
(test-equal "compound-map wraps a non-compound in a compound" '(-1)
            (compound-subobjects (compound-map - 1)))
(test-equal "compound-map flattens compound results" '(1 2 3 4)
            (compound-subobjects
             (compound-map (lambda (x) (make-compound x (+ x 1)))
                           (make-compound 1 3))))
(test-equal "compound-map->list over a compound" '(-1 -2 -3 -4 -5)
            (compound-map->list - (make-compound 1 2 3 4 5)))
(test-equal "compound-map->list of a non-compound is a one-element list" '(-1)
            (compound-map->list - 1))
(test-equal "compound-filter keeps the matching subobjects" '(2 4)
            (compound-subobjects (compound-filter even? (make-compound 1 2 3 4))))
(test-equal "compound-filter on a matching non-compound" '(2)
            (compound-subobjects (compound-filter even? 2)))
(test-equal "compound-filter on a non-matching non-compound" '()
            (compound-subobjects (compound-filter even? 1)))
(test-equal "compound-predicate on a matching subobject" #t
            (compound-predicate student? george))
(test-equal "compound-predicate on a matching non-compound" #t
            (compound-predicate student? alyssa))
;; The two #f-expecting cases are wrapped in a list: an undefined-variable
;; raise inside test-equal yields #f, which would satisfy a bare `#f'
;; expectation and pin nothing at all (checked by mutation test).
(test-equal "compound-predicate on a non-matching compound" '(#f ran)
            (list (compound-predicate string? george) 'ran))
(test-equal "compound-predicate on a non-matching non-compound" '(#f ran)
            (list (compound-predicate teacher? alyssa) 'ran))
(test-equal "compound-access finds the first matching subobject" 1983
            (compound-access teacher? teacher-hire-year #f george))
(test-equal "compound-access on a matching non-compound" 1979
            (compound-access student? student-year #f alyssa))
(test-equal "compound-access falls back to the default" 'none
            (compound-access teacher? teacher-hire-year 'none alyssa))

(let ((runner (test-runner-current)))
  (test-end "srfi-222")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
