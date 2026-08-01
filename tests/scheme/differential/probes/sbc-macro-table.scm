;; Probe / KNOWN DIVERGENCE: a cache HIT leaves the macro table empty, so a
;; top-level `define-syntax` is invisible to a run-time `eval`.
;;
;; Audit v2, Phase 4E.  Listed in run-differential.sh's KNOWN_DIFFS, so the
;; suite stays green until the fix lands; delete the entry there (and this
;; note) once it does.  Tracked as kaappi#2112.
;;
;; `define-syntax` is a *compiler* form: `compileDefineSyntax`
;; (src/compiler_define_syntax.zig) registers the transformer in the live macro
;; table as a side effect of compiling the file, and emits no bytecode that
;; would re-register it.  A cache HIT skips compilation entirely, so on the
;; warm run `vm.macros` never learns the name, and `eval` — which compiles its
;; argument at run time against that table — reports it as an undefined
;; variable:
;;
;;   $ kaappi t.scm       # cold — cache MISS
;;   42
;;   10
;;   ...exit 0
;;
;;   $ kaappi t.scm       # warm — cache HIT
;;   42
;;   t.scm:3: error[KP3001]: undefined variable 'dbl'
;;   ...exit 1
;;
;; Discriminating control: the first line of output is the macro used at
;; *compile* time.  It agrees in both runs, because that use was already
;; compiled into the cached bytecode.  So the defect is precisely "compile-time
;; side effects of the source are not replayed on a HIT", not "macros are
;; broken after a HIT".
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
