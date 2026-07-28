;; Regression test for #1801: two separate expansions of a macro whose
;; template introduces "the same" literal symbol inside `quote` were
;; wrongly bound-identifier=? to each other. renameForHygiene stripped
;; hygiene from a template-introduced identifier the instant it saw
;; QUOTE_FLAG, before any per-expansion distinguishing information could
;; ever be recorded -- so two macro-generated `'g`s always came out as the
;; exact same bare symbol at the SYNTAX level, not just as data.
;;
;; Found via SRFI 148's em-gensym, which relies on hygiene ALONE (not a
;; counter) for uniqueness: `(em-gensym)` is defined as `'g` and depends on
;; each expansion's `g` being a fresh, distinguishable identifier when
;; compared via bound-identifier=?. See tests/scheme/srfi/srfi148.scm's
;; "em-gensym"/"em-generate-temporaries" cases, which exercise this
;; directly through SRFI 148's own eager-syntax-rules machinery -- the
;; cases here isolate the same property without depending on that library.
;;
;; Fixed by hygiene-renaming a template-introduced identifier inside
;; `(quote ...)` exactly like any other during expansion (distinguishable
;; per-expansion, deduped within one expansion via the same scope_table as
;; everything else), then stripping that rename back off wherever the
;; compiler turns a quoted datum into a literal runtime Value
;; (expander.stripHygieneFromDatum, called from quote and quasiquote
;; compilation) -- so the actual VALUE two unrelated expansions produce is
;; still `eq?` once the code runs, even though the two are now
;; distinguishable as SYNTAX before that point.
(import (scheme base) (scheme write) (scheme process-context) (srfi 64) (srfi 148))

(test-begin "quote-identifier-1801")

;; --- The exact repro from #1801 ---

(test-assert "SRFI 148: em-gensym produces distinguishable identifiers per expansion"
  (em (em-not (em-bound-identifier=? (em-gensym) (em-gensym)))))

(test-assert "SRFI 148: em-generate-temporaries relies on the same property"
  (em (em-not (em-apply 'em-bound-identifier=? (em-generate-temporaries (em-2))))))

;; --- The fix must not change ordinary, non-macro-generating-macro
;;     behavior: a ordinary macro that quotes a fixed tag symbol must still
;;     produce `eq?` results across separate invocations once the code
;;     actually runs, exactly as before #1801. Only the SYNTAX-level
;;     identity (visible through bound-identifier=?-style tricks) changes;
;;     the runtime VALUE does not. ---

(define-syntax gen
  (syntax-rules ()
    ((gen) 'g)))

(test-assert "ordinary quoted-symbol macro: eq? across separate invocations"
  (eq? (gen) (gen)))

(test-equal "ordinary quoted-symbol macro: still prints as the plain symbol"
  'g
  (gen))

;; A macro quoting a whole literal list, not just a bare symbol.
(define-syntax gen-list
  (syntax-rules ()
    ((gen-list) '(a b c))))

(test-equal "ordinary quoted-list macro: unaffected by the fix"
  '(a b c)
  (gen-list))

(test-assert "ordinary quoted-list macro: equal? across separate invocations"
  (equal? (gen-list) (gen-list)))

;; --- A template-introduced identifier used consistently both as a `let`
;;     binding (real, executable code) and, quoted, as data referencing
;;     that same binding's name -- both occurrences must resolve to the
;;     SAME rename within one expansion, and both must strip back to the
;;     same base name once compiled, so the generated code still works.
;;     (Regression guard: an earlier version of this fix made the `let`
;;     binding hygiene-rename independently of a same-named quoted
;;     reference threaded through a SEPARATE, later macro expansion,
;;     desyncing the two -- see the "generated macro quoting user data"
;;     case below for that specific shape.) ---

(define-syntax with-e-bound
  (syntax-rules ()
    ((_ helper)
     `(let ((e 42))
        ,(helper 'e)))))

;; Quotes its argument back: (quote-arg 'e) expands to ''e, so evaluating
;; the assembled program yields the SYMBOL e, not the let-bound value 42.
;; What matters is WHICH symbol comes out: if the let binding's `e` and
;; this quoted reference to `e` ever get hygiene-renamed inconsistently
;; (the regression this guards against), the result is some other,
;; mismatched symbol instead of plain `e`.
(define-syntax quote-arg
  (syntax-rules ()
    ((_ x) 'x)))

(test-equal "let-bound identifier and its quoted, unquote-spliced reference agree"
  'e
  (eval (with-e-bound quote-arg) (interaction-environment)))

;; --- A macro-generating-macro that splices USER-SUPPLIED data (not its own
;;     template text) into a nested syntax-rules template must still treat
;;     that data as opaque/verbatim, never hygiene-renaming it -- this is
;;     the usertext-marker protection SRFI 257 relies on, and must survive
;;     unchanged by #1801's fix (which only affects a macro's OWN literal
;;     template text quoted directly, not pattern-variable values threaded
;;     through from a use site). ---

(define-syntax vb
  (syntax-rules ()
    ((_ e)
     (let-syntax ((g (syntax-rules () ((_) (vector-ref #(e) 0)))))
       (g)))))

(test-equal "usertext splice into a nested template stays verbatim (not renamed)"
  'foo
  (vb foo))

(let ((runner (test-runner-current)))
  (test-end "quote-identifier-1801")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
