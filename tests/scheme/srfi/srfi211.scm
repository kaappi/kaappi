;; SRFI 211 (Scheme Macro Libraries) tests: the three sub-libraries Kaappi
;; provides — (srfi 211 explicit-renaming), (srfi 211 define-macro), and
;; (srfi 211 syntax-parameter) — each provided whole per the SRFI's
;; conformance rule ("If it provides a library, it has to provide it as a
;; whole"). The procedural-transformer engine work is issue #1699's last
;; slice; see lib/srfi/211/explicit-renaming.sld for mechanism notes.
;; Run directly: zig-out/bin/kaappi tests/scheme/srfi/srfi211.scm

(import (scheme base) (scheme process-context) (srfi 64)
        (srfi 211 explicit-renaming)
        (srfi 211 define-macro)
        (srfi 211 syntax-parameter))

(test-begin "srfi-211")

;;; --- explicit renaming: the classic swap! with hygienic tmp ---
(define-syntax swap!
  (er-macro-transformer
   (lambda (form rename compare)
     (let ((a (cadr form))
           (b (car (cddr form)))
           (tmp (rename 'tmp)))
       (list (rename 'let) (list (list tmp a))
             (list (rename 'set!) a b)
             (list (rename 'set!) b tmp))))))

(define sw-x 1)
(define sw-y 2)
(swap! sw-x sw-y)
(test-equal '(2 1) (list sw-x sw-y))

;; hygiene: a user variable literally named tmp survives the swap
(define tmp 'mine)
(define other 'yours)
(swap! tmp other)
(test-equal '(yours mine) (list tmp other))

;;; --- recursive ER macro (Clinger's my-or shape) ---
(define-syntax my-or
  (er-macro-transformer
   (lambda (form rename compare)
     (let ((exprs (cdr form)))
       (cond ((null? exprs) #f)
             ((null? (cdr exprs)) (car exprs))
             (else (list (rename 'let)
                         (list (list (rename 't) (car exprs)))
                         (list (rename 'if) (rename 't) (rename 't)
                               (cons (rename 'my-or) (cdr exprs))))))))))

(define t 'user-t)
(test-equal 'user-t (my-or #f #f t))
(test-equal 7 (my-or #f 7 (error "not reached")))

;;; --- rename consistency within one expansion, freshness across two ---
(define-syntax rename-same?
  (er-macro-transformer
   (lambda (form rename compare)
     (list (rename 'quote)
           (eq? (rename 'fresh-name-xyz) (rename 'fresh-name-xyz))))))
(test-equal #t (rename-same? ))

;; Freshness is checked via symbol->string, not a bare quoted rename: #1801
;; fixed renameForHygiene to hygiene-rename a template-introduced identifier
;; inside `(quote ...)` like any other during expansion, then strip that
;; rename back off wherever the compiler turns a quoted datum into a literal
;; Value -- correct per R7RS quote semantics (quote always yields the plain
;; datum, so `(rename-capture)` returning the SAME bare `fresh-name-uvw` both
;; times, not a distinct gensym, is now the right answer for `(list (rename
;; 'quote) (rename 'fresh-name-uvw))`). This test's original form relied on
;; the pre-fix bug (quote never stripped hygiene at all) to observe
;; distinctness; symbol->string sidesteps stripping (it only ever touches
;; symbols) so the test can still verify that `rename` itself produces a
;; genuinely fresh identifier per invocation.
(define-syntax rename-capture
  (er-macro-transformer
   (lambda (form rename compare)
     (list (rename 'quote) (symbol->string (rename 'fresh-name-uvw))))))
(test-assert "two invocations rename to distinct gensyms"
             (not (string=? (rename-capture) (rename-capture))))

;;; --- rename accepts a whole datum: leaves renamed, structure rebuilt ---
(define-syntax tree-rename
  (er-macro-transformer
   (lambda (form rename compare)
     (rename '(let ((fresh-leaf 7)) (* fresh-leaf 2))))))
(test-equal 14 (tree-rename))

;;; --- compare: the classic else-clause detection ---
(define-syntax cond1
  (er-macro-transformer
   (lambda (form rename compare)
     (let ((clause (cadr form)))
       (if (compare (car clause) (rename 'else))
           (cons (rename 'begin) (cdr clause))
           (list (rename 'if) (car clause)
                 (cons (rename 'begin) (cdr clause))
                 (list (rename 'quote) 'no-match)))))))
(test-equal 'fell-through (cond1 (else 'fell-through)))
(test-equal 'took-it (cond1 (#t 'took-it)))
(test-equal 'no-match (cond1 (#f 'skipped)))

;;; --- compare rejects non-identifiers ---
(define-syntax compare-nums
  (er-macro-transformer
   (lambda (form rename compare)
     (list (rename 'quote) (compare 1 1)))))
(test-equal #f (compare-nums))

;;; --- KEP-0006 four-quadrant acceptance test (kaappi#2388): compare is
;;; binding-aware free-identifier=? ---
;;; Against an ER cond-style transformer, the else/=> keyword checks must
;;; answer exactly what a syntax-rules literal with the same keywords
;;; answers -- the same binding, or both unbound (R7RS 4.3.2). Every
;;; quadrant below runs BOTH systems against the SAME expected value; that
;;; equivalence is the KEP-0018 unresolved-question-6 guarantee (an ER
;;; macro is exactly as hygienic as a syntax-rules one) for the
;;; auxiliary-keyword spellings, pinned here as a contract. The guarantee's
;;; boundary — spellings whose bare rename comes from renameForHygiene's
;;; other bare-returning branches — is pinned separately below.

(define-syntax erq-cond
  (er-macro-transformer
   (lambda (form rename compare)
     (let loop ((cs (cdr form)))
       (cond
         ((null? cs) (list (rename 'quote) 'no-clause))
         ((and (pair? (car cs)) (compare (caar cs) (rename 'else)))
          (cadr (car cs)))
         ((and (pair? (car cs)) (pair? (cdr (car cs)))
               (compare (cadr (car cs)) (rename '=>)))
          (list (rename 'let)
                (list (list (rename 't) (caar cs)))
                (list (rename 'if) (rename 't)
                      (list (caddr (car cs)) (rename 't))
                      (loop (cdr cs)))))
         (else (list (rename 'if) (caar cs) (cadr (car cs))
                     (loop (cdr cs)))))))))

(define-syntax srq-cond
  (syntax-rules (else =>)
    ((_ (else expr) rest ...) expr)
    ((_ (test => proc) rest ...)
     (let ((t test)) (if t (proc t) (srq-cond rest ...))))
    ((_ (test expr) rest ...) (if test expr (srq-cond rest ...)))
    ((_) 'no-clause)))

;; Quadrant 1: the else clause fires in both systems.
(test-equal 'q1 (erq-cond (#f 'a) (else 'q1)))
(test-equal 'q1 (srq-cond (#f 'a) (else 'q1)))

;; Quadrant 2: a use-site local rebinding of the keyword is a different
;; binding, so the clause is NOT an else clause in either system. With
;; else bound to #f the refused clause falls through to (#t 'q2); the
;; name-based compare this replaces answered 'wrong here.
(test-equal 'q2 (let ((else #f)) (erq-cond (#f 'a) (else 'wrong) (#t 'q2))))
(test-equal 'q2 (let ((else #f)) (srq-cond (#f 'a) (else 'wrong) (#t 'q2))))

;; Quadrant 3: an outer macro that introduces else into the cond it emits.
;; Unshadowed, it fires in both systems...
(define-syntax q3-er-wrap (syntax-rules () ((_) (erq-cond (#f 'x) (else 'q3)))))
(define-syntax q3-sr-wrap (syntax-rules () ((_) (srq-cond (#f 'x) (else 'q3)))))
(test-equal 'q3 (q3-er-wrap))
(test-equal 'q3 (q3-sr-wrap))
;; ...and under a same-spelling use-site local, both systems agree the
;; clause falls through: `else` is a reserved form the hygiene engine
;; keeps bare, so a user local of that spelling shadows a macro-introduced
;; one in syntax-rules literals and ER compare alike -- the one shared,
;; documented reserved-form deviation (identifiers the engine CAN mark,
;; like => in quadrant 4, stay hygienic).
(define-syntax q3b-er-wrap
  (syntax-rules () ((_) (erq-cond (#f 'x) (else 'wrong) (#t 'q3b)))))
(define-syntax q3b-sr-wrap
  (syntax-rules () ((_) (srq-cond (#f 'x) (else 'wrong) (#t 'q3b)))))
(test-equal 'q3b (let ((else #f)) (q3b-er-wrap)))
(test-equal 'q3b (let ((else #f)) (q3b-sr-wrap)))

;; Quadrant 4: the => variants. Unshadowed, the arrow fires in both...
(test-equal 1 (erq-cond ((- 1) => abs) (else 'no)))
(test-equal 1 (srq-cond ((- 1) => abs) (else 'no)))
;; ...a use-site local rebinding of => is refused by compare exactly as
;; the literal is refused, so the clause compiles as (test expr) whose
;; expr is the local's value in both systems...
(test-equal 7 (let ((=> 7)) (erq-cond (#t =>) (#t 'q4c))))
(test-equal 7 (let ((=> 7)) (srq-cond (#t =>) (#t 'q4c))))
;; ...and a macro-INTRODUCED => stays hygienic in both: the introducing
;; rename/template marks the identifier, and the shadowing local cannot
;; reach it.
(define-syntax q4d-er-wrap
  (er-macro-transformer
   (lambda (form rename compare)
     (list 'erq-cond
           (list 42 (rename '=>) (list 'lambda (list 'x)
                                       (list 'list ''arrow-er 'x)))
           (list #t ''fallback)))))
(define-syntax q4d-sr-wrap
  (syntax-rules ()
    ((_) (srq-cond (42 => (lambda (x) (list 'arrow-sr x)))
                   (#t 'fallback)))))
(test-equal '(arrow-er 42) (let ((=> #f)) (q4d-er-wrap)))
(test-equal '(arrow-sr 42) (let ((=> #f)) (q4d-sr-wrap)))

;; compare stays reflexive on plain use-site tokens (the pairwise
;; input-token comparison idiom, e.g. duplicate-key checks)...
(define-syntax er-token=?
  (er-macro-transformer
   (lambda (form rename compare)
     (list (rename 'quote) (compare (cadr form) (caddr form))))))
(test-assert "two identical use-site tokens compare equal" (er-token=? zz zz))
(test-assert "... even when the spelling is locally rebound at the use site"
             (let ((zz 1)) (er-token=? zz zz)))
;; ...but a token against the definition-side keyword of the same spelling
;; is refused under that rebinding regardless of argument order.
(define-syntax er-is-arrow-rev
  (er-macro-transformer
   (lambda (form rename compare)
     (list (rename 'quote) (compare (rename '=>) (cadr form))))))
(test-assert "reversed-argument compare under rebinding is also refused"
             (not (let ((=> 1)) (er-is-arrow-rev =>))))

;; The bound-keyword case from the #2398 evidence (SRFI 202's values
;; claw): renaming a GLOBAL-bound name yields a marked identifier, so an
;; unshadowed use still compares equal while a use-site local rebinding
;; of the spelling is refused.
(define-syntax er-is-values
  (er-macro-transformer
   (lambda (form rename compare)
     (list (rename 'quote) (compare (cadr form) (rename 'values))))))
(test-assert "unshadowed values compares equal to its rename"
             (er-is-values values))
(test-assert "a locally rebound values is refused"
             (not (let ((values 1)) (er-is-values values))))

;; Reflexivity of a rename against itself (the hoisted `r-*` rename style
;; the 241/202 ports use): free-identifier=? is an equivalence relation,
;; so a transformer comparing two of its OWN rename products must get #t
;; even where a use-site local shadows the bare spelling (#2401 review).
;; The spelling nowhere occurs in the macro-use input, which is what
;; separates this from the quadrant-2 shape above.
(define-syntax er-self-else?
  (er-macro-transformer
   (lambda (form rename compare)
     (list (rename 'quote) (compare (rename 'else) (rename 'else))))))
(test-assert "a rename compares equal to itself" (er-self-else?))
(test-assert "... even under a use-site shadow of the bare spelling"
             (let ((else 1)) (er-self-else?)))
(define-syntax er-self-arrow?
  (er-macro-transformer
   (lambda (form rename compare)
     (list (rename 'quote) (compare (rename '=>) (rename '=>))))))
(test-assert "a renamed (gensym-marked) keyword compares equal to itself"
             (let ((=> 1)) (er-self-arrow?)))

;; Boundary of the ER/syntax-rules parity guarantee, pinned as-is: a
;; spelling whose bare rename comes from renameForHygiene's OTHER
;; bare-returning branches (here: the VOID sentinel for a later internal
;; define in the use-site body) records no identity entry, so compare
;; answers the (reflexive) use-token view while a syntax-rules literal
;; refuses. Pre-existing divergence, not covered by the parity contract --
;; see the .sld header's qualified guarantee statement (#2401 review).
(define-syntax er-is-laterdef?
  (er-macro-transformer
   (lambda (form rename compare)
     (list (rename 'quote) (compare (cadr form) (rename 'laterdef))))))
(define-syntax sr-is-laterdef?
  (syntax-rules (laterdef) ((_ laterdef) #t) ((_ x) #f)))
(define (er-laterdef-probe)
  (define result
    (list (er-is-laterdef? laterdef) (let ((laterdef 1)) (er-is-laterdef? laterdef))))
  (define laterdef 9)
  result)
(test-equal '(#t #t) (er-laterdef-probe))

;;; --- identifier?: symbols (renamed or not) are identifiers ---
(test-assert "plain symbol" (identifier? 'x))
(test-assert "not a number" (not (identifier? 3)))
(test-assert "not a string" (not (identifier? "x")))
(test-assert "not a list" (not (identifier? '(x))))

;;; --- er transformer under let-syntax in a body scope ---
(define (body-er)
  (let-syntax ((double (er-macro-transformer
                        (lambda (f r c) (list (r '*) 2 (cadr f))))))
    (double 21)))
(test-equal 42 (body-er))

;;; --- a runtime transformer value bound then used as a spec (SRFI 211's
;;; constructors are real procedures returning transformer objects) ---
(define runtime-tx
  (er-macro-transformer (lambda (f r c) (list (r 'quote) 'via-value))))
(define-syntax via-value runtime-tx)
(test-equal 'via-value (via-value))

;;; --- lisp-transformer: whole macro-use datum, zero hygiene ---
(define-syntax lt-when
  (lisp-transformer
   (lambda (form)
     (list 'if (cadr form) (cons 'begin (cddr form)) #f))))
(test-equal 'yes (lt-when (> 2 1) 'yes))
(test-equal #f (lt-when (< 2 1) 'no))

;; the whole use (keyword included) is what proc receives
(define-syntax lt-head
  (lisp-transformer (lambda (form) (list 'quote (car form)))))
(test-equal 'lt-head (lt-head))

;; non-hygiene is the specified behavior: an introduced binding CAN
;; capture a use-site name (that's what old-style macros do)
(define-syntax lt-capture
  (lisp-transformer
   (lambda (form) (list 'let '((cap 'introduced)) (cadr form)))))
(test-equal 'introduced (lt-capture cap))

;;; --- define-macro, first form: (name . formals) destructures the cdr ---
(define-macro (dm-unless test . body)
  (list 'if test #f (cons 'begin body)))
(test-equal 'ran (dm-unless (= 1 2) 'ran))
(test-equal #f (dm-unless (= 1 1) 'not-run))

;; quasiquoted body, the classic defmacro idiom
(define-macro (dm-swap! a b)
  `(let ((fresh-dm-tmp ,a)) (set! ,a ,b) (set! ,b fresh-dm-tmp)))
(define dm-p 1)
(define dm-q 2)
(dm-swap! dm-p dm-q)
(test-equal '(2 1) (list dm-p dm-q))

;;; --- define-macro, second form: (name expander) ---
(define-macro dm-also-when
  (lambda (form) (list 'if (cadr form) (cons 'begin (cddr form)) #f)))
(test-equal 'w (dm-also-when #t 'w))

;;; --- variadic formals with fixed leaders ---
(define-macro (dm-list2 a b . rest)
  `(list ,b ,a ,@rest))
(test-equal '(2 1 3 4) (dm-list2 1 2 3 4))

;;; --- (srfi 211 syntax-parameter): SRFI 139's semantics under the
;;; SRFI 211 library name (forever/abort, the spec's own example) ---
(define-syntax-parameter abort
  (syntax-rules ()
    ((_ . _) (syntax-error "abort used outside of a loop"))))
(define-syntax forever
  (syntax-rules ()
    ((_ body1 body2 ...)
     (call-with-current-continuation
      (lambda (escape)
        (syntax-parameterize
            ((abort (syntax-rules () ((_ v) (escape v)))))
          (let loop () body1 body2 ... (loop))))))))
(define spin 0)
(test-equal 3 (forever (set! spin (+ spin 1))
                       (when (> spin 2) (abort spin))))

;;; --- ER macro defined in a library body: rename resolves the library's
;;; own non-exported helper at the use site ---
(define-library (t211 helperlib)
  (import (scheme base) (srfi 211 explicit-renaming))
  (export lib-twice combo is-lib-bound?)
  (begin
    (define (t211-helper x) (* x 2))
    (define lib-bound-var 'marker)
    (define-syntax lib-twice
      (er-macro-transformer
       (lambda (form rename compare)
         (list (rename 't211-helper) (cadr form)))))
    ;; compare against a rename of a name bound in the transformer's OWN
    ;; definition environment: outside that library, renameForHygiene's
    ;; #1812 branch marks it def-env-prefixed, and the marked identifier
    ;; must still compare equal to a use-site reference of the exported
    ;; binding (#2401 review -- this was the def_env/free regression).
    (define-syntax is-lib-bound?
      (er-macro-transformer
       (lambda (form rename compare)
         (list (rename 'quote) (compare (cadr form) (rename 'lib-bound-var))))))
    (define-syntax combo
      (syntax-rules ()
        ((_ e) (list (lib-twice e) e))))))
(import (t211 helperlib))
(test-equal 42 (lib-twice 21))
(test-equal '(20 10) (combo 10))
(test-assert "a def-env-marked rename compares equal to the use-site reference of the same exported binding"
             (is-lib-bound? lib-bound-var))
(test-assert "... but not under a use-site local rebinding of the spelling"
             (not (let ((lib-bound-var 1)) (is-lib-bound? lib-bound-var))))

(let ((runner (test-runner-current)))
  (test-end "srfi-211")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
