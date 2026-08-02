;; Regression probe for kaappi#2112 (FIXED): a cache HIT used to leave the
;; macro table empty, making a top-level `define-syntax` invisible to a
;; run-time `eval`.
;;
;; Audit v2, Phase 4E.  Was a KNOWN_DIFFS entry until the fix; now an
;; ordinary probe — cold and warm must agree on every line below.
;;
;; `define-syntax` is a *compiler* form: `compileDefineSyntax`
;; (src/compiler_define_syntax.zig) registers the transformer in the live macro
;; table as a side effect of compiling the file, and emits no bytecode that
;; would re-register it.  A cache HIT skips compilation entirely, so on the
;; warm run `vm.macros` never learned the name, and `eval` — which compiles
;; its argument at run time against that table — reported it as an undefined
;; variable (exit 1 where the cold run exited 0).
;;
;; The fix refuses to cache any file whose compilation registered a macro or
;; syntax property (`runFile` snapshots `vm.macros.count()` /
;; `vm.syntax_properties.count()` around each form's compilation, which also
;; catches a macro use expanding into a `define-syntax`).  This file is
;; therefore never cached — `--timings` reports `not cached: define-syntax` —
;; which makes cold and warm the identical configuration, exactly the safe
;; option kaappi#2112 blessed.  If caching is ever taught to replay these
;; registrations instead (the .sbc preamble mechanism), this probe verifies
;; the replay too, with no edits.
;;
;; `define-property` (SRFI 213) is the same shape and is included below: it
;; writes into the VM-owned `syntax_properties` table at compile time.

(define-syntax dbl (syntax-rules () ((_ x) (* 2 x))))
(define-syntax outer (syntax-rules () ((_ x) (inner x))))
(define-syntax inner (syntax-rules () ((_ x) (+ x 100))))
(define-property dbl kind 'doubler)

;; --- control: compile-time uses.  These agree cold and warm. -------------
(display (dbl 21))
(newline)
(display (outer 1))
(newline)

;; --- the divergence: run-time uses through `eval`. -----------------------
(display (guard (e (#t 'undefined)) (eval '(dbl 5) (interaction-environment))))
(newline)
(display (guard (e (#t 'undefined)) (eval '(outer 2) (interaction-environment))))
(newline)
(display (guard (e (#t 'undefined)) (eval '(let () (dbl 3)) (interaction-environment))))
(newline)

;; A plain global defined the ordinary way IS visible to eval in both runs —
;; globals are runtime state, macros are not.
(define (trip x) (* 3 x))
(display (guard (e (#t 'undefined)) (eval '(trip 4) (interaction-environment))))
(newline)
