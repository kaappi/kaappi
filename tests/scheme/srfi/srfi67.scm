;;; SRFI 67 (Compare Procedures) conformance tests.

(import (scheme base)
        (scheme write)
        (scheme process-context)
        (srfi 64)
        (srfi 67))

(test-begin "srfi-67")

;;; --------------------------------------------------------------------
;;; if3 — 3-way conditional
;;; --------------------------------------------------------------------

(test-equal "if3 less"   'less   (if3 -1 'less 'equal 'greater))
(test-equal "if3 equal"  'equal  (if3  0 'less 'equal 'greater))
(test-equal "if3 greater" 'greater (if3  1 'less 'equal 'greater))

;;; --------------------------------------------------------------------
;;; if=?, if<?, if>?, if<=?, if>=?, if-not=?
;;; --------------------------------------------------------------------

(test-equal "if=? true"    'yes (if=?  0 'yes 'no))
(test-equal "if=? false"   'no  (if=? -1 'yes 'no))
(test-equal "if=? false/1" 'no  (if=?  1 'yes 'no))

(test-equal "if<? true"  'yes (if<? -1 'yes 'no))
(test-equal "if<? false" 'no  (if<?  0 'yes 'no))

(test-equal "if>? true"  'yes (if>?  1 'yes 'no))
(test-equal "if>? false" 'no  (if>?  0 'yes 'no))

(test-equal "if<=? true/eq"   'yes (if<=?  0 'yes 'no))
(test-equal "if<=? true/lt"   'yes (if<=? -1 'yes 'no))
(test-equal "if<=? false"     'no  (if<=?  1 'yes 'no))

(test-equal "if>=? true/eq"   'yes (if>=?  0 'yes 'no))
(test-equal "if>=? true/gt"   'yes (if>=?  1 'yes 'no))
(test-equal "if>=? false"     'no  (if>=? -1 'yes 'no))

(test-equal "if-not=? true/lt" 'yes (if-not=? -1 'yes 'no))
(test-equal "if-not=? true/gt" 'yes (if-not=?  1 'yes 'no))
(test-equal "if-not=? false"   'no  (if-not=?  0 'yes 'no))

;; Optional alternate (default is void-ish)
(test-equal "if<? no alternate" 'yes (if<? -1 'yes))

;;; --------------------------------------------------------------------
;;; boolean-compare
;;; --------------------------------------------------------------------

(test-equal "bool-cmp #f #f"  0 (boolean-compare #f #f))
(test-equal "bool-cmp #f #t" -1 (boolean-compare #f #t))
(test-equal "bool-cmp #t #f"  1 (boolean-compare #t #f))
(test-equal "bool-cmp #t #t"  0 (boolean-compare #t #t))

;;; --------------------------------------------------------------------
;;; char-compare, char-compare-ci
;;; --------------------------------------------------------------------

(test-equal "char-cmp a a"  0 (char-compare #\a #\a))
(test-equal "char-cmp a b" -1 (char-compare #\a #\b))
(test-equal "char-cmp b a"  1 (char-compare #\b #\a))

(test-equal "char-ci-cmp A a" 0 (char-compare-ci #\A #\a))
(test-equal "char-ci-cmp a B" -1 (char-compare-ci #\a #\B))

;;; --------------------------------------------------------------------
;;; string-compare, string-compare-ci
;;; --------------------------------------------------------------------

(test-equal "str-cmp equal"  0 (string-compare "abc" "abc"))
(test-equal "str-cmp less"  -1 (string-compare "abc" "abd"))
(test-equal "str-cmp greater" 1 (string-compare "abd" "abc"))
(test-equal "str-cmp prefix" -1 (string-compare "ab"  "abc"))

(test-equal "str-ci-cmp" 0 (string-compare-ci "ABC" "abc"))

;;; --------------------------------------------------------------------
;;; symbol-compare
;;; --------------------------------------------------------------------

(test-equal "sym-cmp equal"  0 (symbol-compare 'abc 'abc))
(test-equal "sym-cmp less"  -1 (symbol-compare 'abc 'abd))
(test-equal "sym-cmp greater" 1 (symbol-compare 'abd 'abc))

;;; --------------------------------------------------------------------
;;; integer-compare
;;; --------------------------------------------------------------------

(test-equal "int-cmp equal" 0 (integer-compare 5 5))
(test-equal "int-cmp less"  -1 (integer-compare 3 5))
(test-equal "int-cmp greater" 1 (integer-compare 5 3))

;;; --------------------------------------------------------------------
;;; rational-compare
;;; --------------------------------------------------------------------

(test-equal "rat-cmp equal" 0 (rational-compare 1/2 1/2))
(test-equal "rat-cmp less" -1 (rational-compare 1/3 1/2))
(test-equal "rat-cmp greater" 1 (rational-compare 2/3 1/2))

;;; --------------------------------------------------------------------
;;; real-compare
;;; --------------------------------------------------------------------

(test-equal "real-cmp equal" 0 (real-compare 3.14 3.14))
(test-equal "real-cmp less"  -1 (real-compare 2.71 3.14))
(test-equal "real-cmp greater" 1 (real-compare 3.14 2.71))

;;; --------------------------------------------------------------------
;;; number-compare (dispatches to complex-compare)
;;; --------------------------------------------------------------------

(test-equal "num-cmp integers" -1 (number-compare 1 2))
(test-equal "num-cmp reals"     0 (number-compare 3.0 3.0))

;;; --------------------------------------------------------------------
;;; Comparison predicates: =?, <?, >?, <=?, >=?, not=?
;;; (3-arg form: compare, x, y)
;;; --------------------------------------------------------------------

(test-assert "=? integer-compare 3 3" (=? integer-compare 3 3))
(test-assert "not (=? integer-compare 3 4)" (not (=? integer-compare 3 4)))

(test-assert "<? integer-compare 3 5" (<? integer-compare 3 5))
(test-assert "not (<? integer-compare 5 3)" (not (<? integer-compare 5 3)))

(test-assert ">? integer-compare 5 3" (>? integer-compare 5 3))
(test-assert "not (>? integer-compare 3 5)" (not (>? integer-compare 3 5)))

(test-assert "<=? integer-compare 3 3" (<=? integer-compare 3 3))
(test-assert "<=? integer-compare 3 5" (<=? integer-compare 3 5))
(test-assert "not (<=? integer-compare 5 3)" (not (<=? integer-compare 5 3)))

(test-assert ">=? integer-compare 5 3" (>=? integer-compare 5 3))
(test-assert ">=? integer-compare 3 3" (>=? integer-compare 3 3))
(test-assert "not (>=? integer-compare 3 5)" (not (>=? integer-compare 3 5)))

(test-assert "not=? integer-compare 3 5" (not=? integer-compare 3 5))
(test-assert "not (not=? integer-compare 3 3)" (not (not=? integer-compare 3 3)))

;; 2-arg form (uses default-compare)
(test-assert "=? 3 3 default"  (=? 3 3))
(test-assert "<? 3 5 default"  (<? 3 5))
(test-assert ">? 5 3 default"  (>? 5 3))
(test-assert "<=? 3 3 default" (<=? 3 3))
(test-assert ">=? 5 3 default" (>=? 5 3))
(test-assert "not=? 3 5 default" (not=? 3 5))

;; 1-arg form (returns a procedure)
(let ((less-than? (<? integer-compare)))
  (test-assert "<? returns procedure" (less-than? 1 2))
  (test-assert "<? returned proc false" (not (less-than? 2 1))))

;; 0-arg form (returns a procedure using default-compare)
(let ((dc-less? (<?)))
  (test-assert "<? 0-arg default" (dc-less? 1 2))
  (test-assert "<? 0-arg default false" (not (dc-less? 2 1))))

;;; --------------------------------------------------------------------
;;; 3-element interval tests
;;; --------------------------------------------------------------------

(test-assert "</<? 1 2 3"   (</<? integer-compare 1 2 3))
(test-assert "not </<? 1 2 2" (not (</<? integer-compare 1 2 2)))
(test-assert "not </<? 1 1 2" (not (</<? integer-compare 1 1 2)))

(test-assert "</<=? 1 2 3"  (</<=? integer-compare 1 2 3))
(test-assert "</<=? 1 2 2"  (</<=? integer-compare 1 2 2))
(test-assert "not </<=? 1 1 2" (not (</<=? integer-compare 1 1 2)))

(test-assert "<=/<? 1 2 3"  (<=/<? integer-compare 1 2 3))
(test-assert "<=/<? 1 1 3"  (<=/<? integer-compare 1 1 3))
(test-assert "not <=/<? 1 2 2" (not (<=/<? integer-compare 1 2 2)))

(test-assert "<=/<=? 1 2 3" (<=/<=? integer-compare 1 2 3))
(test-assert "<=/<=? 1 1 1" (<=/<=? integer-compare 1 1 1))

(test-assert ">/>? 3 2 1"   (>/>? integer-compare 3 2 1))
(test-assert "not >/>? 3 2 2" (not (>/>? integer-compare 3 2 2)))

(test-assert ">/>=? 3 2 1"  (>/>=? integer-compare 3 2 1))
(test-assert ">/>=? 3 2 2"  (>/>=? integer-compare 3 2 2))

(test-assert ">=/>? 3 2 1"  (>=/>? integer-compare 3 2 1))
(test-assert ">=/>? 3 3 1"  (>=/>? integer-compare 3 3 1))
(test-assert "not >=/>? 3 2 2" (not (>=/>? integer-compare 3 2 2)))

(test-assert ">=/>=? 3 2 1" (>=/>=? integer-compare 3 2 1))
(test-assert ">=/>=? 3 3 3" (>=/>=? integer-compare 3 3 3))

;;; --------------------------------------------------------------------
;;; Chain tests
;;; --------------------------------------------------------------------

(test-assert "chain<? 1 2 3"   (chain<? integer-compare 1 2 3))
(test-assert "chain<? 1 2 3 4" (chain<? integer-compare 1 2 3 4))
(test-assert "not chain<? 1 2 2" (not (chain<? integer-compare 1 2 2)))
(test-assert "not chain<? 1 3 2" (not (chain<? integer-compare 1 3 2)))
(test-assert "chain<? single"  (chain<? integer-compare 42))
(test-assert "chain<? empty"   (chain<? integer-compare))

(test-assert "chain=? 3 3 3"   (chain=? integer-compare 3 3 3))
(test-assert "not chain=? 3 3 4" (not (chain=? integer-compare 3 3 4)))

(test-assert "chain>? 3 2 1"   (chain>? integer-compare 3 2 1))
(test-assert "not chain>? 3 2 2" (not (chain>? integer-compare 3 2 2)))

(test-assert "chain<=? 1 2 2 3" (chain<=? integer-compare 1 2 2 3))
(test-assert "not chain<=? 1 2 1" (not (chain<=? integer-compare 1 2 1)))

(test-assert "chain>=? 3 2 2 1" (chain>=? integer-compare 3 2 2 1))
(test-assert "not chain>=? 3 2 3" (not (chain>=? integer-compare 3 2 3)))

;;; --------------------------------------------------------------------
;;; pairwise-not=?
;;; --------------------------------------------------------------------

(test-assert "pairwise-not=? 1 2 3"
             (pairwise-not=? integer-compare 1 2 3))
(test-assert "not pairwise-not=? 1 2 1"
             (not (pairwise-not=? integer-compare 1 2 1)))
(test-assert "pairwise-not=? single"
             (pairwise-not=? integer-compare 42))
(test-assert "pairwise-not=? empty"
             (pairwise-not=? integer-compare))
(test-assert "not pairwise-not=? 1 1"
             (not (pairwise-not=? integer-compare 1 1)))

;;; --------------------------------------------------------------------
;;; min-compare, max-compare
;;; --------------------------------------------------------------------

(test-equal "min-compare 2 args" 1 (min-compare integer-compare 3 1))
(test-equal "min-compare 3 args" 1 (min-compare integer-compare 3 1 2))
(test-equal "min-compare 4 args" 1 (min-compare integer-compare 4 1 3 2))
(test-equal "min-compare 1 arg"  5 (min-compare integer-compare 5))

(test-equal "max-compare 2 args" 3 (max-compare integer-compare 3 1))
(test-equal "max-compare 3 args" 3 (max-compare integer-compare 3 1 2))
(test-equal "max-compare 4 args" 4 (max-compare integer-compare 4 1 3 2))
(test-equal "max-compare 1 arg"  5 (max-compare integer-compare 5))

;; 5+ args (variadic path)
(test-equal "min-compare 5 args" 1 (min-compare integer-compare 5 3 1 4 2))
(test-equal "max-compare 5 args" 5 (max-compare integer-compare 5 3 1 4 2))

;;; --------------------------------------------------------------------
;;; kth-largest
;;; --------------------------------------------------------------------

(test-equal "kth-largest 0 of 3" 1 (kth-largest integer-compare 0 3 1 2))
(test-equal "kth-largest 1 of 3" 2 (kth-largest integer-compare 1 3 1 2))
(test-equal "kth-largest 2 of 3" 3 (kth-largest integer-compare 2 3 1 2))

(test-equal "kth-largest 0 of 2" 1 (kth-largest integer-compare 0 2 1))
(test-equal "kth-largest 1 of 2" 2 (kth-largest integer-compare 1 2 1))

(test-equal "kth-largest 0 of 1" 7 (kth-largest integer-compare 0 7))

;;; --------------------------------------------------------------------
;;; compare-by<, compare-by>, compare-by<=, compare-by>=
;;; --------------------------------------------------------------------

(test-equal "compare-by< lt"  -1 (compare-by< < 1 2))
(test-equal "compare-by< eq"   0 (compare-by< < 2 2))
(test-equal "compare-by< gt"   1 (compare-by< < 2 1))

(test-equal "compare-by> gt"   1 (compare-by> > 2 1))
(test-equal "compare-by> eq"   0 (compare-by> > 2 2))
(test-equal "compare-by> lt"  -1 (compare-by> > 1 2))

(test-equal "compare-by<= le"  -1 (compare-by<= <= 1 2))
(test-equal "compare-by<= eq"   0 (compare-by<= <= 2 2))
(test-equal "compare-by<= gt"   1 (compare-by<= <= 2 1))

(test-equal "compare-by>= ge"   1 (compare-by>= >= 2 1))
(test-equal "compare-by>= eq"   0 (compare-by>= >= 2 2))
(test-equal "compare-by>= lt"  -1 (compare-by>= >= 1 2))

;; 1-arg form returns a procedure
(let ((cmp (compare-by< <)))
  (test-equal "compare-by< 1-arg" -1 (cmp 1 2))
  (test-equal "compare-by< 1-arg eq" 0 (cmp 2 2)))

;;; --------------------------------------------------------------------
;;; compare-by=/< and compare-by=/>
;;; --------------------------------------------------------------------

(test-equal "compare-by=/< eq"  0 (compare-by=/< = < 2 2))
(test-equal "compare-by=/< lt" -1 (compare-by=/< = < 1 2))
(test-equal "compare-by=/< gt"  1 (compare-by=/< = < 2 1))

(test-equal "compare-by=/> eq"  0 (compare-by=/> = > 2 2))
(test-equal "compare-by=/> gt"  1 (compare-by=/> = > 2 1))
(test-equal "compare-by=/> lt" -1 (compare-by=/> = > 1 2))

;;; --------------------------------------------------------------------
;;; refine-compare
;;; --------------------------------------------------------------------

(test-equal "refine-compare empty" 0 (refine-compare))
(test-equal "refine-compare single" -1 (refine-compare -1))
(test-equal "refine-compare first wins" -1
            (refine-compare -1 (error "should not evaluate")))
(test-equal "refine-compare tie then less" -1
            (refine-compare 0 -1))
(test-equal "refine-compare tie then tie" 0
            (refine-compare 0 0))

;;; --------------------------------------------------------------------
;;; select-compare
;;; --------------------------------------------------------------------

;; select-compare requires x and y to be in scope at the use site.
;; Wrap in a procedure to give them names.
(let ((my-num-compare
       (lambda (x y)
         (select-compare x y
           (number? (number-compare x y))))))
  (test-equal "select-compare numbers" -1 (my-num-compare 1 2)))

(let ((my-str-compare
       (lambda (x y)
         (select-compare x y
           (string? (string-compare x y))))))
  (test-equal "select-compare strings" 1 (my-str-compare "b" "a")))

;; Mixed types: number < string in custom ordering
(let ((my-mixed-compare
       (lambda (x y)
         (select-compare x y
           (number? (number-compare x y))
           (string? (string-compare x y))))))
  (test-equal "select-compare mixed" -1 (my-mixed-compare 1 "a")))

;;; --------------------------------------------------------------------
;;; cond-compare
;;; --------------------------------------------------------------------

(test-equal "cond-compare both true" -1
            (cond-compare ((#t #t) -1)))

(test-equal "cond-compare x true y false" -1
            (cond-compare ((#t #f))))

(test-equal "cond-compare x false y true" 1
            (cond-compare ((#f #t))))

(test-equal "cond-compare else" 42
            (cond-compare (else 42)))

;;; --------------------------------------------------------------------
;;; pair-compare
;;; --------------------------------------------------------------------

;; 2-arg: uses default-compare
(test-equal "pair-compare (1 . 2) (1 . 2)" 0
            (pair-compare '(1 . 2) '(1 . 2)))
(test-equal "pair-compare (1 . 2) (1 . 3)" -1
            (pair-compare '(1 . 2) '(1 . 3)))
(test-equal "pair-compare (2 . 0) (1 . 0)" 1
            (pair-compare '(2 . 0) '(1 . 0)))

;; 3-arg: explicit compare for improper lists
(test-equal "pair-compare 3-arg list" 0
            (pair-compare integer-compare '(1 2 3) '(1 2 3)))
(test-equal "pair-compare 3-arg list <" -1
            (pair-compare integer-compare '(1 2 3) '(1 2 4)))

;; 4-arg: separate car/cdr comparators
(test-equal "pair-compare 4-arg" 0
            (pair-compare integer-compare integer-compare '(1 . 2) '(1 . 2)))
(test-equal "pair-compare 4-arg car <" -1
            (pair-compare integer-compare integer-compare '(1 . 5) '(2 . 3)))
(test-equal "pair-compare 4-arg car = cdr <" -1
            (pair-compare integer-compare integer-compare '(1 . 2) '(1 . 3)))

;;; --------------------------------------------------------------------
;;; pair-compare-car, pair-compare-cdr
;;; --------------------------------------------------------------------

(let ((cmp-car (pair-compare-car integer-compare))
      (cmp-cdr (pair-compare-cdr integer-compare)))
  (test-equal "pair-compare-car" -1 (cmp-car '(1 . 9) '(2 . 0)))
  (test-equal "pair-compare-cdr" 1  (cmp-cdr '(1 . 9) '(2 . 0))))

;;; --------------------------------------------------------------------
;;; list-compare
;;; --------------------------------------------------------------------

(test-equal "list-compare equal" 0
            (list-compare integer-compare '(1 2 3) '(1 2 3)))
(test-equal "list-compare shorter" -1
            (list-compare integer-compare '(1 2) '(1 2 3)))
(test-equal "list-compare element <" -1
            (list-compare integer-compare '(1 2 3) '(1 3 3)))

;; 2-arg (default-compare)
(test-equal "list-compare default" 0
            (list-compare '(1 2 3) '(1 2 3)))

;;; --------------------------------------------------------------------
;;; vector-compare
;;; --------------------------------------------------------------------

(test-equal "vector-compare equal" 0
            (vector-compare integer-compare '#(1 2 3) '#(1 2 3)))
(test-equal "vector-compare shorter wins" -1
            (vector-compare integer-compare '#(1 2) '#(1 2 3)))
(test-equal "vector-compare element <" -1
            (vector-compare integer-compare '#(1 2 3) '#(1 2 4)))

;; 2-arg (default-compare)
(test-equal "vector-compare default" 0
            (vector-compare '#(1 2 3) '#(1 2 3)))

;;; --------------------------------------------------------------------
;;; vector-compare-as-list
;;; --------------------------------------------------------------------

(test-equal "vector-compare-as-list equal" 0
            (vector-compare-as-list integer-compare '#(1 2 3) '#(1 2 3)))
(test-equal "vector-compare-as-list element <" -1
            (vector-compare-as-list integer-compare '#(1 2 3) '#(1 2 4)))
;; As list: shorter is less (length is a tiebreaker, not primary)
(test-equal "vector-compare-as-list shorter" -1
            (vector-compare-as-list integer-compare '#(1 2) '#(1 2 3)))

;;; --------------------------------------------------------------------
;;; list-compare-as-vector
;;; --------------------------------------------------------------------

(test-equal "list-compare-as-vector equal" 0
            (list-compare-as-vector integer-compare '(1 2 3) '(1 2 3)))
(test-equal "list-compare-as-vector shorter first" -1
            (list-compare-as-vector integer-compare '(1 2) '(1 2 3)))

;;; --------------------------------------------------------------------
;;; default-compare
;;; --------------------------------------------------------------------

;; Ordering: null < pair < boolean < char < string < symbol < number < vector
(test-equal "default-compare null null" 0
            (default-compare '() '()))
(test-equal "default-compare null < pair" -1
            (default-compare '() '(1)))
(test-equal "default-compare bool < char" -1
            (default-compare #f #\a))
(test-equal "default-compare char < string" -1
            (default-compare #\a "a"))
(test-equal "default-compare string < symbol" -1
            (default-compare "a" 'a))
(test-equal "default-compare symbol < number" -1
            (default-compare 'a 1))
(test-equal "default-compare number < vector" -1
            (default-compare 1 '#(1)))

;; Same-type ordering
(test-equal "default-compare numbers" -1 (default-compare 1 2))
(test-equal "default-compare strings"  1 (default-compare "b" "a"))
(test-equal "default-compare lists"    0 (default-compare '(1 2) '(1 2)))

;;; --------------------------------------------------------------------
;;; debug-compare
;;; --------------------------------------------------------------------

(let ((dc (debug-compare integer-compare)))
  (test-equal "debug-compare basic" -1 (dc 1 2))
  (test-equal "debug-compare equal"  0 (dc 3 3))
  (test-equal "debug-compare gt"     1 (dc 5 2)))

;;; --------------------------------------------------------------------
;;; Done
;;; --------------------------------------------------------------------

(let ((runner (test-runner-current)))
  (test-end "srfi-67")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
