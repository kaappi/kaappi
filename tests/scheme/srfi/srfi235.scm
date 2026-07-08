;; SRFI-235 (combinators) conformance tests — #1221
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi235.scm

(import (scheme base) (scheme write) (scheme process-context)
        (srfi 64) (srfi 235))

(test-begin "srfi-235")

;;; --- constantly ---
(test-equal "constantly: single value" 7 ((constantly 7) 'ignored 'args))
(test-equal "constantly: multiple values"
  '(1 2) (call-with-values (lambda () ((constantly 1 2) 'x)) list))

;;; --- complement ---
(test-assert "complement: odd" ((complement even?) 3))
(test-assert "complement: even" (not ((complement even?) 4)))

;;; --- swap ---
(test-equal "swap: cons" '(2 . 1) ((swap cons) 1 2))
(test-equal "swap: list with extra args" '(2 1 3 4) ((swap list) 1 2 3 4))

;;; --- flip ---
(test-equal "flip: list" '(3 2 1) ((flip list) 1 2 3))
(test-equal "flip: cons" '(2 . 1) ((flip cons) 1 2))

;;; --- on-left ---
(test-equal "on-left: applies to first arg" 10 ((on-left (lambda (x) (* x 2))) 5 99))

;;; --- on-right ---
(test-equal "on-right: applies to second arg" 198 ((on-right (lambda (x) (* x 2))) 5 99))

;;; --- on ---
(test-equal "on: sum of cars" 5 ((on + car) '(2 x) '(3 y)))
(test-assert "on: equal cars" ((on = car) '(1 a) '(1 b)))

;;; --- each-of ---
(let ((acc '()))
  ((each-of
    (lambda (x) (set! acc (cons (list 'a x) acc)))
    (lambda (x) (set! acc (cons (list 'b x) acc))))
   7)
  (test-equal "each-of: side effects" '((a 7) (b 7)) (reverse acc)))

;;; --- all-of ---
(test-assert "all-of: all even" ((all-of even?) '(2 4 6)))
(test-assert "all-of: not all even" (not ((all-of even?) '(2 3))))
(test-assert "all-of: empty list" ((all-of even?) '()))
(test-equal "all-of: returns last result" 2 ((all-of (lambda (x) x)) '(1 2)))
(test-equal "all-of: single element" 42 ((all-of (lambda (x) x)) '(42)))

;;; --- any-of ---
(test-assert "any-of: one even" ((any-of even?) '(1 2)))
(test-assert "any-of: none even" (not ((any-of even?) '(1 3))))
(test-assert "any-of: empty list" (not ((any-of even?) '())))
(test-equal "any-of: returns predicate result" 5 ((any-of (lambda (x) x)) '(#f 5)))

;;; --- conjoin ---
(test-assert "conjoin: number and odd" ((conjoin number? odd?) 3))
(test-assert "conjoin: number but even" (not ((conjoin number? odd?) 4)))
(test-assert "conjoin: not number" (not ((conjoin number? odd?) 'x)))
(test-assert "conjoin: no predicates" ((conjoin) 'anything))
(test-equal "conjoin: returns last value" 5 ((conjoin (lambda (x) x)) 5))
(test-equal "conjoin: multi-pred last value"
  #t ((conjoin number? odd?) 3))

;;; --- disjoin ---
(test-assert "disjoin: symbol" ((disjoin number? symbol?) 'x))
(test-assert "disjoin: number" ((disjoin number? symbol?) 1))
(test-assert "disjoin: neither" (not ((disjoin number? symbol?) "s")))
(test-assert "disjoin: no predicates" (not ((disjoin) 'anything)))
(test-equal "disjoin: returns first truthy" 5 ((disjoin (lambda (x) x)) 5))

;;; --- left-section ---
(test-equal "left-section: add 3" 7 ((left-section + 3) 4))
(test-equal "left-section: list prefix" '(1 2 3 4) ((left-section list 1 2) 3 4))
(test-equal "left-section: subtract" 1 ((left-section - 5) 4))

;;; --- right-section ---
(test-equal "right-section: subtract 1" 4 ((right-section - 1) 5))
(test-equal "right-section: cons" '(1 . 2) ((right-section cons 2) 1))

;;; --- apply-chain ---
(test-equal "apply-chain: compose add1 double"
  11 ((apply-chain (lambda (x) (+ x 1)) (lambda (x) (* x 2))) 5))
(test-equal "apply-chain: single proc" 6 ((apply-chain +) 1 2 3))
(test-equal "apply-chain: identity" '(1 2) (call-with-values
  (lambda () ((apply-chain) 1 2)) list))

;;; --- arguments-drop ---
(test-equal "arguments-drop: drop 2" '(3 4 5)
  ((arguments-drop list 2) 1 2 3 4 5))

;;; --- arguments-drop-right ---
(test-equal "arguments-drop-right: drop last 2" '(1 2 3)
  ((arguments-drop-right list 2) 1 2 3 4 5))

;;; --- arguments-take ---
(test-equal "arguments-take: take 3" '(1 2 3)
  ((arguments-take list 3) 1 2 3 4 5))

;;; --- arguments-take-right ---
(test-equal "arguments-take-right: take last 2" '(4 5)
  ((arguments-take-right list 2) 1 2 3 4 5))

;;; --- group-by ---
(test-equal "group-by: keys in order"
  '(1 2 3)
  (map caar ((group-by car) '((1 a) (2 b) (1 c) (3 d) (2 e) (3 f)))))
(test-equal "group-by: preserves order"
  '(((1 a) (1 c)) ((2 b) (2 e)) ((3 d) (3 f)))
  ((group-by car) '((1 a) (2 b) (1 c) (3 d) (2 e) (3 f))))
(test-equal "group-by: empty list" '() ((group-by car) '()))
(test-equal "group-by: custom ="
  '(("abc" "ABC") ("def"))
  ((group-by (lambda (x) x) string-ci=?) '("abc" "ABC" "def")))

;;; --- begin-procedure ---
(let ((acc '()))
  (test-equal "begin-procedure: returns last"
    3 (begin-procedure
        (lambda () (set! acc (cons 1 acc)) 1)
        (lambda () (set! acc (cons 2 acc)) 2)
        (lambda () (set! acc (cons 3 acc)) 3)))
  (test-equal "begin-procedure: order" '(1 2 3) (reverse acc)))

;;; --- if-procedure ---
(test-equal "if-procedure: true branch" 'yes
  (if-procedure #t (lambda () 'yes) (lambda () 'no)))
(test-equal "if-procedure: false branch" 'no
  (if-procedure #f (lambda () 'yes) (lambda () 'no)))

;;; --- when-procedure ---
(let ((acc '()))
  (when-procedure #t
    (lambda () (set! acc (cons 'a acc)))
    (lambda () (set! acc (cons 'b acc))))
  (test-equal "when-procedure: true runs thunks" '(a b) (reverse acc)))
(let ((acc '()))
  (when-procedure #f
    (lambda () (set! acc (cons 'a acc))))
  (test-equal "when-procedure: false skips" '() acc))

;;; --- unless-procedure ---
(let ((acc '()))
  (unless-procedure #f
    (lambda () (set! acc (cons 'a acc)))
    (lambda () (set! acc (cons 'b acc))))
  (test-equal "unless-procedure: false runs thunks" '(a b) (reverse acc)))
(let ((acc '()))
  (unless-procedure #t
    (lambda () (set! acc (cons 'a acc))))
  (test-equal "unless-procedure: true skips" '() acc))

;;; --- value-procedure ---
(test-equal "value-procedure: truthy" 10
  (value-procedure 5 (lambda (v) (* v 2)) (lambda () 'nope)))
(test-equal "value-procedure: false" 'nope
  (value-procedure #f (lambda (v) (* v 2)) (lambda () 'nope)))

;;; --- case-procedure ---
(let ((alist (list (cons 1 (lambda () 'one))
                   (cons 2 (lambda () 'two)))))
  (test-equal "case-procedure: match 1" 'one (case-procedure 1 alist))
  (test-equal "case-procedure: match 2" 'two (case-procedure 2 alist))
  (test-equal "case-procedure: no match with else" 'other
    (case-procedure 3 alist (lambda () 'other))))

;;; --- and-procedure ---
(test-assert "and-procedure: all true" (and-procedure (lambda () 1) (lambda () 2)))
(test-equal "and-procedure: returns last" 2
  (and-procedure (lambda () 1) (lambda () 2)))
(test-assert "and-procedure: short-circuit"
  (not (and-procedure (lambda () #f) (lambda () (error "should not run")))))
(test-assert "and-procedure: no thunks" (and-procedure))

;;; --- eager-and-procedure ---
(test-equal "eager-and-procedure: all true" 2
  (eager-and-procedure (lambda () 1) (lambda () 2)))
(let ((ran #f))
  (eager-and-procedure (lambda () #f) (lambda () (set! ran #t) 2))
  (test-assert "eager-and-procedure: runs all" ran))
(test-assert "eager-and-procedure: returns #f on false"
  (not (eager-and-procedure (lambda () #f) (lambda () 2))))
(let ((order '()))
  (eager-and-procedure
    (lambda () (set! order (cons 1 order)) 1)
    (lambda () (set! order (cons 2 order)) 2)
    (lambda () (set! order (cons 3 order)) 3))
  (test-equal "eager-and-procedure: left-to-right" '(1 2 3) (reverse order)))

;;; --- or-procedure ---
(test-equal "or-procedure: first true" 1
  (or-procedure (lambda () 1) (lambda () (error "should not run"))))
(test-assert "or-procedure: all false"
  (not (or-procedure (lambda () #f) (lambda () #f))))
(test-assert "or-procedure: no thunks"
  (not (or-procedure)))

;;; --- eager-or-procedure ---
(test-equal "eager-or-procedure: first true" 1
  (eager-or-procedure (lambda () 1) (lambda () 2)))
(let ((ran #f))
  (eager-or-procedure (lambda () 1) (lambda () (set! ran #t) 2))
  (test-assert "eager-or-procedure: runs all" ran))
(test-assert "eager-or-procedure: all false"
  (not (eager-or-procedure (lambda () #f) (lambda () #f))))
(let ((order '()))
  (eager-or-procedure
    (lambda () (set! order (cons 1 order)) #f)
    (lambda () (set! order (cons 2 order)) #f)
    (lambda () (set! order (cons 3 order)) #f))
  (test-equal "eager-or-procedure: left-to-right" '(1 2 3) (reverse order)))

;;; --- funcall-procedure ---
(test-equal "funcall-procedure" 42 (funcall-procedure (lambda () 42)))

;;; --- loop-procedure ---
(let ((count 0))
  (call-with-current-continuation
    (lambda (exit)
      (loop-procedure
        (lambda ()
          (set! count (+ count 1))
          (when (= count 5) (exit #t))))))
  (test-equal "loop-procedure: escape after 5" 5 count))

;;; --- while-procedure ---
(let ((count 0))
  (while-procedure (lambda () (set! count (+ count 1)) (< count 5)))
  (test-equal "while-procedure: stops when false" 5 count))

;;; --- until-procedure ---
(let ((count 0))
  (until-procedure (lambda () (set! count (+ count 1)) (= count 5)))
  (test-equal "until-procedure: stops when true" 5 count))

;;; --- always / never ---
(test-assert "always" (always 1 2 3))
(test-assert "always: no args" (always))
(test-assert "never" (not (never 1 2 3)))
(test-assert "never: no args" (not (never)))

;;; --- boolean ---
(test-equal "boolean: true" #t (boolean 42))
(test-equal "boolean: false" #f (boolean #f))
(test-equal "boolean: zero is true" #t (boolean 0))
(test-equal "boolean: empty string is true" #t (boolean ""))
(test-equal "boolean: #t stays #t" #t (boolean #t))

;;; --- compose / o (non-SRFI extras) ---
(test-equal "compose" 11 ((compose (lambda (x) (+ x 1)) (lambda (x) (* x 2))) 5))
(test-equal "o" 11 ((o (lambda (x) (+ x 1)) (lambda (x) (* x 2))) 5))

(let ((runner (test-runner-current)))
  (test-end "srfi-235")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
