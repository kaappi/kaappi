;; SRFI 148 (Eager syntax-rules) tests -- ported verbatim (test logic
;; unchanged) from the SRFI's own reference test suite,
;; srfi/148/test.sld in https://srfi.schemers.org/srfi-148/srfi-148.tgz,
;; by Marc Nieper-Wißkirchen (2016), MIT-licensed. Only the harness
;; wrapper differs: the reference wraps this body in a `(srfi 148 test)`
;; library exporting a `run-tests` thunk (for embedding in a larger test
;; runner); this flattens it to a standalone script, matching every other
;; tests/scheme/srfi/*.scm file in this repo. The reference's top-level
;; `(include-library-declarations "../../custom-macro-transformers.scm")`
;; is dropped: that file's own cond-expand exists to shadow
;; define-syntax/let-syntax/letrec-syntax/syntax-rules with SRFI 147's
;; portable polyfill on hosts that lack native custom-transformer support
;; -- Kaappi's define-syntax et al. already implement SRFI 147 natively
;; (see lib/srfi/147.sld), so the shadowing is both unnecessary and (since
;; Kaappi doesn't declare a `custom-macro-transformers` cond-expand
;; feature) would otherwise fall through to importing the polyfill anyway.
;; em-syntax-rules is SRFI 148's core transformer -- see lib/srfi/148.sld's
;; header and issue #1699 for the multi-session investigation (perf cliff
;; #1775, usertext-marker spine gaps #1787/#1790, macro-chain depth wall
;; #1796/#1797) this library needed before it could compile at all.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi148.scm
;;
;; Deviations from the reference suite: none of the test logic itself was
;; changed. All ~142 assertions now pass -- the two general, pre-existing
;; engine bugs found while porting this suite (neither specific to SRFI 148
;; or to this library's own combinators) are both fixed:
;;   - #1800: a macro that expands to a bare (define x v) in body position
;;     didn't make x visible to later sibling forms in the same body.
;;     Reproduced with a plain, non-eager syntax-rules macro -- nothing to
;;     do with em-syntax-rules. Affected "Match quoted pattern with quoted
;;     element", "Match quoted pattern with eager macro use", "Match
;;     unquoted pattern with element", em-cons, em-list, em-append. Fixed:
;;     expandAndCompileMacroUse's post-expansion cleanup popped every
;;     compiler local added while compiling a macro's final expanded form
;;     back off before returning, on the mistaken assumption that everything
;;     added during a macro-use compile is transient chain bookkeeping
;;     (hygienic aliases). A body-scope `define` reached through the
;;     expansion adds a REAL, sibling-visible local, not an alias, and needs
;;     to survive.
;;   - #1801: two separate expansions of a macro whose template introduces
;;     "the same" literal symbol were wrongly bound-identifier=? to each
;;     other. Broke em-gensym/em-generate-temporaries, which deliberately
;;     rely on hygiene alone (not a counter) for uniqueness, per the
;;     reference's own (em-gensym) => 'g definition. Fixed:
;;     renameForHygiene hygiene-renames a template-introduced identifier
;;     inside `(quote ...)` exactly like any other during expansion, and the
;;     compiler strips that rename back off wherever it compiles a quoted
;;     datum to a literal Value (expander.stripHygieneFromDatum, called from
;;     quote and quasiquote compilation) -- see src/expander.zig and the
;;     regression tests in src/tests_macros.zig and
;;     tests/scheme/hygiene/quote-identifier-1801.scm.
;; A third, more severe issue (#1802: importing this library alone costs
;; ~80s, superlinearly in definition count, independent of test count) was
;; ALSO fixed separately (see lib/srfi/148.sld's own header); with all three
;; blockers resolved, this file is wired into run-all.sh.

(import (scheme base) (scheme process-context) (srfi 2) (srfi 64) (srfi 148))

(test-begin "SRFI 148")

(test-equal "Match quoted pattern with quoted element"
  10
  (let-syntax
      ((m
        (em-syntax-rules ()
          ((m 'a) 'a))))
    (m '(define x 10))
    x))

(test-equal "Match quoted pattern with eager macro use"
  10
  (letrec-syntax
      ((m1
        (em-syntax-rules ()
          ((m1 'define 'x) '(define x))))
       (m2
        (em-syntax-rules ()
          ((m2 '(d y)) '(d y 10)))))
    (m2 (m1 'define 'x))
    x))

(test-equal "Match unquoted pattern with element"
  10
  (letrec-syntax
      ((m
        (em-syntax-rules ()
          ((m a) 'a))))
    (m (define x 10))
    x))

(test-equal "eager macro uses in expression contexts"
  10
  (letrec-syntax
      ((m
        (em-syntax-rules ()
          ((m 'a 'b) '(+ a b)))))
    (em (m '5 '5))))

(test-equal "Self-quoting literals"
  10
  (letrec-syntax
      ((m
        (em-syntax-rules ()
          ((m 'a) 10))))
    (m 1)))

(test-equal "Quasiquotation in output element"
  10
  (letrec-syntax
      ((m1
        (em-syntax-rules ()
          ((m1 'a) '(+ a 3))))
       (m2
        (em-syntax-rules ()
          ((m2 'a 'b) `(+ ,(m1 'a) ,(m1 'b))))))
    (em (m2 '1 '3))))

(test-equal "Quasiquotation in input element"
  10
  (letrec-syntax
      ((m1
        (em-syntax-rules ()
          ((m1 'a) '(+ a 3))))
       (m2
        (em-syntax-rules ()
          ((m2 'a) 'a))))
    (em (m2 `(+ 5 ,(m1 '2))))))

(test-equal "Quasiquotation: vector"
  #((a . 1) 2 3)
  (em (em-quote `#(,(em-cons 'a '1) ,@(em-list 2 3)))))

(test-equal "Pattern binding"
  '(foo (foo))
  (letrec-syntax
      ((m
        (em-syntax-rules ()
          ((m 'a)
           ((em-make-list (em-2) 'a) => '(b c))
           ((em-list 'c) => 'd)
           '(a d)))))
    (em (em-quote (m 'foo)))))

(test-equal "Pattern binding with ellipsis"
  '(foo bar (foo))
  (letrec-syntax
      ((m
        (em-syntax-rules ()
          ((m 'a 'x ...)
           ((em-make-list (em-2) 'a) => '(b c ...))
           ('(c ...) => 'd)
           '(a x ... d)))))
    (em (em-quote (m 'foo 'bar)))))

(test-group "General"

  (test-equal "em-cut: without ..."
    '(a . <>)
    (em (em-quote (em-apply (em-cut 'em-cons <> '<>) 'a '()))))

  (test-equal "em-cut: with ..."
    '(a b c d)
    (em (em-quote (em-apply (em-cut 'em-list <> 'b <> ...) 'a 'c 'd '()))))

  (test-equal "em-cut: in operator position"
    '(a . <>)
    (em (em-quote ((em-cut 'em-cons <> '<>) 'a))))

  (test-equal "em-cute: without ..."
    '(a . <>)
    (em (em-quote (em-apply (em-cute 'em-cons <> '<>) 'a '()))))

  (test-equal "em-cute: with ..."
    '(a b c d)
    (em (em-quote (em-apply (em-cute 'em-list <> 'b <> ...) 'a 'c 'd '()))))

  (test-equal "em-cute: in operator position"
    '(a . <>)
    (em (em-quote ((em-cute 'em-cons <> '<>) 'a))))

  (test-equal "em-constant"
    'foo
    (em (em-quote ((em-constant 'foo) 'a 'b 'c))))

  (test-equal "em-quote"
    '(1 2 3)
    (em (em-quote (em-list 1 2 3))))

  (test-equal "em-eval"
    '(1 2 3)
    (em (em-eval '(em-list 'list 1 2 3))))

  (test-equal "em-apply"
    '(1 2 3 4 5 6)
    (em (em-apply 'em-list 'list 1 2 3 '(4 5 6))))

  (test-equal "em-call"
    '(1 2 3)
    (em (em-quote (em-call 'em-list '1 '2 '3))))

  (test-assert "em-gensym"
    (em (em-not (em-bound-identifier=? (em-gensym) (em-gensym)))))

  (test-assert "em-generate-temporaries"
    (em (em-not (em-apply 'em-bound-identifier=? (em-generate-temporaries (em-2)))))))

(test-group "Boolean logic"

  (test-equal "em-if: true test"
    'true
    (em (em-quote (em-if '#t 'true 'false))))

  (test-equal "em-if: false test"
    'false
    (em (em-quote (em-if '#f 'true 'false))))

  (test-equal "em-not"
    'false
    (em (em-quote (em-if (em-not '#t) 'true 'false))))

  (test-equal "em-or"
    'a
    (em (em-or '#f ''a (em-error "fail"))))

  (test-equal "em-and"
    '#f
    (em (em-and ''a ''b '#f (em-error "fail"))))

  (test-equal "em-null?: true"
    'true
    (em (em-quote (em-if (em-null? '()) 'true 'false))))

  (test-equal "em-null?: false"
    'false
    (em (em-quote (em-if (em-null? 'x) 'true 'false))))

  (test-equal "em-pair?: true"
    'true
    (em (em-quote (em-if (em-pair? '(a . b)) 'true 'false))))

  (test-equal "em-pair?: false"
    'false
    (em (em-quote (em-if (em-pair? '()) 'true 'false))))

  (test-equal "em-list?: true"
    'true
    (em (em-quote (em-if (em-list? '(a b)) 'true 'false))))

  (test-equal "em-list?: false"
    'false
    (em (em-quote (em-if (em-list? '(a . b)) 'true 'false))))

  (test-equal "em-boolean?: true"
    'true
    (em (em-quote (em-if (em-boolean? '#f) 'true 'false))))

  (test-equal "em-boolean?: false"
    'false
    (em (em-quote (em-if (em-boolean? '(a . b)) 'true 'false))))

  (test-equal "em-vector?: true"
    'true
    (em (em-quote (em-if (em-vector? '#(a b)) 'true 'false))))

  (test-equal "em-vector?: false"
    'false
    (em (em-quote (em-if (em-vector? '(a . b)) 'true 'false))))

  (test-equal "em-symbol?: true"
    'true
    (em (em-quote (em-if (em-symbol? 'a) 'true 'false))))

  (test-equal "em-symbol?: false"
    'false
    (em (em-quote (em-if (em-symbol? '(a . b)) 'true 'false))))

  (test-equal "em-bound-identifier=?: true"
    'true
    (letrec-syntax
        ((m
          (syntax-rules ()
            ((m a b)
             (em (em-quote (em-if (em-bound-identifier=? 'a 'b) 'true 'false)))))))
      (m c c)))

  (test-equal "em-bound-identifier=?: false"
    'false
    (letrec-syntax
        ((m
          (syntax-rules ()
            ((m a b)
             (em (em-quote (em-if (em-bound-identifier=? 'a 'b) 'true 'false)))))))
      (m c d)))

  (test-equal "em-free-identifier=?: true"
    'true
    (letrec-syntax
        ((m
          (syntax-rules ()
            ((m a)
             (em (em-quote (em-if (em-free-identifier=? 'a 'm) 'true 'false)))))))
      (m m)))

  (test-equal "em-free-identifier=?: false"
    'false
    (letrec-syntax
        ((m
          (syntax-rules ()
            ((m a)
             (em (em-quote (em-if (em-free-identifier=? 'a 'm) 'true 'false)))))))
      (m c)))

  (test-equal "em-equal?: numbers/true"
    'true
    (em (em-quote (em-if (em-equal? '10 '10) 'true 'false))))

  (test-equal "em-equal?: numbers/false"
    'false
    (em (em-quote (em-if (em-equal? '10 "foo") 'true 'false))))

  (test-equal "em-equal?: recursive/true"
    'true
    (em (em-quote (em-if (em-equal? '(a . #(1 2 ("x" "y")))
                                     '(a . #(1 2 ("x" "y"))))
                          'true
                          'false))))

  (test-equal "em-equal?: recursive/false"
    'false
    (em (em-quote (em-if (em-equal? '(a . #(1 2 ("x" y)))
                                     '(a . #(1 2 ("x" "y"))))
                          'true
                          'false)))))

(test-group "List processing"

  (test-group "Constructors"
    (test-equal "em-cons"
      10
      (let ()
        (em-cons 'define '(x 10))
        x))

    (test-equal "em-cons*"
      '(a b . c)
      (em (em-quote (em-cons* 'a 'b 'c))))

    (test-equal "em-list"
      10
      (let ()
        (em-list 'define 'x '10)
        x))

    (test-equal "em-make-list"
      '(a a a a a)
      (em (em-quote (em-make-list (em-5) 'a)))))

  (test-group "Selectors"

    (test-equal "em-car"
      'car
      (em (em-car '('car . 'cdr))))

    (test-equal "em-car"
      'cdr
      (em (em-cdr '('car . 'cdr))))

    (test-equal "em-caar"
      'a
      (em (em-quote (em-caar '((a . b) . c)))))

    (test-equal "em-cadr"
      'c
      (em (em-quote (em-cadr '((a . b) . (c . d))))))

    (test-equal "em-cdar"
      'b
      (em (em-quote (em-cdar '((a . b) . c)))))

    (test-equal "em-cddr"
      'd
      (em (em-quote (em-cddr '((a . b) . (c . d))))))

    (test-equal "em-first"
      1
      (em (em-quote (em-first '(1 2 3 4 5 6 7 8 9 10)))))

    (test-equal "em-second"
      2
      (em (em-quote (em-second '(1 2 3 4 5 6 7 8 9 10)))))

    (test-equal "em-third"
      3
      (em (em-quote (em-third '(1 2 3 4 5 6 7 8 9 10)))))

    (test-equal "em-fourth"
      4
      (em (em-quote (em-fourth '(1 2 3 4 5 6 7 8 9 10)))))

    (test-equal "em-fifth"
      5
      (em (em-quote (em-fifth '(1 2 3 4 5 6 7 8 9 10)))))

    (test-equal "em-sixth"
      6
      (em (em-quote (em-sixth '(1 2 3 4 5 6 7 8 9 10)))))

    (test-equal "em-seventh"
      7
      (em (em-quote (em-seventh '(1 2 3 4 5 6 7 8 9 10)))))

    (test-equal "em-eighth"
      8
      (em (em-quote (em-eighth '(1 2 3 4 5 6 7 8 9 10)))))

    (test-equal "em-ninth"
      9
      (em (em-quote (em-ninth '(1 2 3 4 5 6 7 8 9 10)))))

    (test-equal "em-tenth"
      10
      (em (em-quote (em-tenth '(1 2 3 4 5 6 7 8 9 10)))))

    (test-equal "em-list-tail"
      '(3 4 5)
      (em (em-quote (em-list-tail '(1 2 3 4 5) (em-2)))))

    (test-equal "em-list-ref"
      '4
      (em (em-quote (em-list-ref '(1 2 3 4 5) (em-3)))))

    (test-equal "em-take"
      '(1 2 3)
      (em (em-quote (em-take '(1 2 3) (em-3)))))

    (test-equal "em-take-right"
      '(2 3 . d)
      (em (em-quote (em-take-right '(0 1 2 3 . d) (em-2)))))

    (test-equal "em-drop-right"
      '(0 1)
      (em (em-quote (em-drop-right '(0 1 2 3 . d) (em-2)))))

    (test-equal "em-last"
      'c
      (em (em-quote (em-last '(a b c)))))

    (test-equal "em-last-pair"
      '(c)
      (em (em-quote (em-last-pair '(a b c))))))

  (test-group "Miscellaneous"
    (test-equal "em-append"
      10
      (let ()
        (em-append '(define) '(x) '(10))
        x))

    (test-equal "em-reverse"
      '(5 4 3 2 1)
      (em (em-quote (em-reverse '(1 2 3 4 5))))))

  (test-group "Folding, unfolding and mapping"

    (test-equal "em-fold"
      '(* b 2 (* a 1 ()))
      (em (em-quote (em-fold (em-cute 'em-list '* <> ...)
                              '()
                              '(a b c)
                              '(1 2)))))

    (test-equal "em-fold-right"
      '(* a 1 (* b 2 ()))
      (em (em-quote (em-fold-right (em-cute 'em-list '* <> ...)
                                    '()
                                    '(a b c)
                                    '(1 2)))))

    (test-equal "em-unfold"
      '(1 2 3)
      (em (em-quote (em-unfold 'em-null? 'em-car 'em-cdr '(1 2 3)))))

    (test-equal "em-unfold-right"
      '(3 2 1)
      (em (em-quote (em-unfold-right 'em-null? 'em-car 'em-cdr '(1 2 3)))))

    (test-equal "em-map"
      '((* . 1) (* . 2) (* . 3))
      (em (em-quote (em-map (em-cut 'em-cons '* <>) '(1 2 3)))))

    (test-equal "em-append-map"
      '(1 a 2 b 3 c)
      (em (em-quote (em-append-map 'em-list '(1 2 3) '(a b c))))))

  (test-group "Filtering"

    (test-equal "em-filter"
      '(foo foo)
      (em (em-quote (em-filter (em-cut 'em-equal? 'foo <>) '(foo bar baz foo)))))

    (test-equal "em-remove"
      '(bar baz)
      (em (em-quote (em-remove (em-cut 'em-equal? 'foo <>) '(foo bar baz foo))))))

  (test-group "Searching"
    (define-syntax pred
      (em-syntax-rules ()
        ((pred 'x 'y) (em-equal? 'x (em-car 'y)))))

    (test-equal "em-find"
      '(2 . b)
      (em (em-quote (em-find (em-cut 'pred 2 <>) '((1 . a) (2 . b) (3 . c))))))

    (test-equal "em-find-tail"
      '((2 . b) (3 . c))
      (em (em-quote (em-find-tail (em-cut 'pred 2 <>) '((1 . a) (2 . b) (3 . c))))))

    (test-equal "em-take-while"
      '()
      (em (em-quote (em-take-while (em-cut 'pred 2 <>) '((1 . a) (2 . b) (3 . c))))))

    (test-equal "em-drop-while"
      '((1 . a) (2 . b) (3 . c))
      (em (em-quote (em-drop-while (em-cut 'pred 2 <>) '((1 . a) (2 . b) (3 . c))))))

    (test-equal "em-any"
      '#t
      (em (em-quote (em-any (em-cut 'pred 2 <>) '((1 . a) (2 . b) (3 . c))))))

    (test-equal "em-every"
      '#f
      (em (em-quote (em-every (em-cut 'pred 2 <>) '((1 . a) (2 . b) (3 . c))))))

    (test-equal "em-member"
      '(2 3)
      (em (em-quote (em-member '2 '(1 2 3) 'em-equal?)))))

  (test-group "Association lists"

    (test-equal "em-assoc"
      '(2 . b)
      (em (em-quote (em-assoc '2 '((1 . a) (2 . b) (3 . c))))))

    (test-equal "em-assoc"
      '((1 . a) (3 . c))
      (em (em-quote (em-alist-delete '2 '((1 . a) (2 . b) (3 . c)))))))

  (test-group "Set operations"

    (test-assert "em-set<=: true"
      (em (em-set<= 'em-equal? '(1 2) '(1 2 3))))

    (test-assert "em-set<=: false"
      (em (em-not (em-set<= 'em-equal? '(3 1 2 3) '(1 2)))))

    (test-assert "em-set-adjoin"
      (em (em= (em-set-adjoin 'em-equal? '(1 2 3) '2 '4) (em-4))))

    (test-assert "em-set-union"
      (em (em= (em-set-union 'em-equal? '(1 2 3) '(3 4 5)) (em-5))))

    (test-assert "em-set-intersection"
      (em (em= (em-set-intersection 'em-equal? '(1 2 3) '(3 4 5)) (em-1))))

    (test-assert "em-set-difference"
      (em (em= (em-set-difference 'em-equal? '(1 2 3) '(3 4 5)) (em-2))))

    (test-assert "em-set-xor"
      (em (em= (em-set-xor 'em-equal? '(1 2 3) '(3 4 5)) (em-4))))))

(test-group "Vector processing"

  (test-equal "em-vector"
    #(10 20 30)
    (em (em-quote (em-vector 10 20 30))))

  (test-equal "em-list->vector"
    #(10 20 30)
    (em (em-quote (em-list->vector '(10 20 30)))))

  (test-equal "em-vector->list"
    '(10 20 30)
    (em (em-quote (em-vector->list #(10 20 30)))))

  (test-equal "em-vector-map"
    '#((1 . a) (2 . b) (3 . c))
    (em (em-quote (em-vector-map 'em-cons '#(1 2 3) '#(a b c d)))))

  (test-equal "em-vector-ref"
    20
    (em (em-quote (em-vector-ref #(10 20 30) (em-1))))))

(test-group "Combinatorics"

  (test-equal "em-0"
    #t
    (em (em= '() (em-0))))

  (test-equal "em-1"
    #t
    (em (em= '(0) (em-1))))

  (test-equal "em-2"
    #t
    (em (em= '(0 1) (em-2))))

  (test-equal "em-3"
    #t
    (em (em= '(0 1 2) (em-3))))

  (test-equal "em-4"
    #t
    (em (em= '(0 1 2 3) (em-4))))

  (test-equal "em-5"
    #t
    (em (em= '(0 1 2 3 4) (em-5))))

  (test-equal "em-6"
    #t
    (em (em= '(0 1 2 3 4 5) (em-6))))

  (test-equal "em-7"
    #t
    (em (em= '(0 1 2 3 4 5 6) (em-7))))

  (test-equal "em-8"
    #t
    (em (em= '(0 1 2 3 4 5 6 7) (em-8))))

  (test-equal "em-9"
    #t
    (em (em= '(0 1 2 3 4 5 6 7 8) (em-9))))

  (test-equal "em-10"
    #t
    (em (em= '(0 1 2 3 4 5 6 7 8 9) (em-10))))

  (test-assert "em=: true"
    (em (em-quote (em= '(1 2 3) '(a b c) '(foo bar baz)))))

  (test-assert "em=: false"
    (em (em-quote (em-not (em= '(1 2 3) '(a b c d) '(foo bar baz))))))

  (test-assert "em<: true"
    (em (em-quote (em< '(1) '(a b) '(foo bar baz)))))

  (test-assert "em<: false"
    (em (em-quote (em-not (em< '(1 2) '(a b c) '(foo bar baz))))))

  (test-assert "em<=: true"
    (em (em-quote (em<= '(1 2) '(a b c) '(foo bar baz)))))

  (test-assert "em<=: false"
    (em (em-quote (em-not (em<= '(1 2 3) '(a b c d) '(foo bar baz))))))

  (test-assert "em>: true"
    (em (em-quote (em> '(1 2 3 4 5) '(a b c d) '(foo bar baz)))))

  (test-assert "em>: false"
    (em (em-quote (em-not (em> '(1 2 3) '(a b c d) '(foo bar baz))))))

  (test-assert "em>=: true"
    (em (em-quote (em>= '(1 2 3 4) '(a b c d) '(foo bar baz)))))

  (test-assert "em>=: false"
    (em (em-quote (em-not (em>= '(1 2 3) '(a b c d) '(foo bar baz))))))

  (test-assert "em-zero?: true"
    (em (em-quote (em-zero? (em-0)))))

  (test-assert "em-zero?: false"
    (em (em-quote (em-not (em-zero? (em-1))))))

  (test-assert "em-even?: true"
    (em (em-quote (em-even? (em-4)))))

  (test-assert "em-even?: false"
    (em (em-quote (em-not (em-even? (em-3))))))

  (test-assert "em-odd?: true"
    (em (em-quote (em-odd? (em-1)))))

  (test-assert "em-odd?: false"
    (em (em-quote (em-not (em-odd? (em-2))))))

  (test-equal "em+"
    '(1 2 3 4 5 6 7 8)
    (em (em-quote (em+ '(1 2 3) '(4 5 6) '(7 8)))))

  (test-equal "em-"
    '(1 2 3)
    (em (em-quote (em- '(1 2 3 4 5 6 7 8) (em-2) (em-3)))))

  (test-equal "em*"
    '((1 a foo)
      (1 a bar)
      (2 a foo)
      (2 a bar))
    (em (em-quote (em* '(1 2) '(a) '(foo bar)))))

  (test-equal "em-quotient"
    '(1 3)
    (em (em-quote (em-quotient '(1 2 3 4 5) (em-2)))))

  (test-equal "em-remainder"
    '(5)
    (em (em-quote (em-remainder '(1 2 3 4 5) (em-2)))))

  (test-equal "em-binom"
    '((1 2)
      (1 3)
      (2 3))
    (em (em-quote (em-binom '(1 2 3) (em-2)))))

  (test-equal "em-fact"
    '((1 2 3)
      (1 3 2)
      (2 1 3)
      (2 3 1)
      (3 1 2)
      (3 2 1))
    (em (em-quote (em-fact '(1 2 3))))))

(test-group "Example from specification"

  (define-syntax simple-match
    (em-syntax-rules ()
      ((simple-match expr (pattern . body) ...)
       (em
        `(call-with-current-continuation
          (lambda (return)
            (let ((e expr))
              (or (and-let*
                      ,(%compile-pattern 'pattern 'e)
                    (call-with-values (lambda () . body) return))
                  ...
                  (error "does not match" expr)))))))))

  (define-syntax %compile-pattern
    (em-syntax-rules ()
      ((%compile-pattern '() 'e)
       '(((null? e))))
      ((%compile-pattern '(pattern1 pattern2 ...) 'e)
       `(((not (null? e)))
         (e1 (car e))
         (e2 (cdr e))
         ,@(%compile-pattern 'pattern1 'e1)
         ,@(%compile-pattern '(pattern2 ...) 'e2)))
      ((%compile-pattern 'x 'e)
       (em-if (em-symbol? 'x)
              '((x e))
              '(((equal? x e)))))))

  (test-equal 'ten (simple-match 10
                                 (10 'ten)
                                 ((11 x) x)))

  (test-equal 'eleven (simple-match '(11 eleven)
                                    (10 'ten)
                                    ((11 x) x))))

(let ((runner (test-runner-current)))
  (test-end "SRFI 148")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
