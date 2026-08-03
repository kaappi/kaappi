;; Probe: the rule governing which files populate the `.sbc` cache at all —
;; and the control showing it is a TOP-LEVEL HEAD-POSITION rule, not a
;; whole-file scan.
;;
;; Audit v2, Phase 4E.  This is the file every other sbc-*.scm probe's header
;; points at, because a probe that stops populating the cache stops testing
;; anything and looks green.
;;
;; MEASURED RULE (src/main.zig `runFile`).  A run writes a cache entry iff all
;; three hold:
;;
;;   1. caching is enabled at all — not `--sandbox`, not `--no-ir-opt`, and a
;;      home directory resolves (`cache.pathForSource`);
;;   2. at least one top-level form compiled to a Function; and
;;   3. `first_toplevel_decl` stayed null — i.e. NO top-level form was claimed
;;      by `vm_eval.handleTopLevelForm`.
;;
;; Condition 3 is the one that matters, and it is much broader than
;; docs/dev/cache.md used to say ("a program that does not `import`").
;; `handleTopLevelForm` claims EIGHT head symbols — the `vm_eval.TopLevelHead`
;; enum, which is now the single source of truth all the consumers derive from:
;;
;;     import   define-library   define-record-type   define-values
;;     include  include-ci       begin                cond-expand
;;
;; Any one of them, once, anywhere at top level, makes the WHOLE file
;; uncacheable.  They share one reason: `handleTopLevelForm` interprets such a
;; form and appends no Function to the run's compiled list, so a HIT — which
;; compiles nothing — would skip its work entirely.  (The library-loading
;; rationale the source comment used to give covers only three of the eight.)
;; Measured over the harness's own default corpus: 40 of 345
;; files populate the cache; of the 305 that do not, 303 have a top-level
;; `import` and the other two are disabled by a top-level `begin` and a
;; top-level `define-values` respectively.  The import half is kaappi#1888.
;;
;; kaappi#2114 fixed the reporting: `--timings` names the head that actually
;; fired (`cache: MISS (not cached: top-level begin)`) instead of blaming
;; `imports` for all eight.  tests/scheme/cache/cache-decline-reason-2114.sh
;; pins one case per head.
;;
;; This file therefore contains NONE of the eight at top level — and, as the
;; control, uses four of them in NESTED position, where they are ordinary
;; compiler forms and leave caching alive.  If a future change makes the rule a
;; whole-file scan, this file stops populating the cache and the harness's
;; "cache exercised" count drops.

(define (chk name a b)
  (display name)
  (display " ")
  (display (if (equal? a b) "ok" (list "MISMATCH" a b)))
  (newline))

;; `begin` in a body, not at top level.
(define (nested-begin)
  (begin 1 2 3))
(chk "nested-begin" (nested-begin) 3)

;; `cond-expand` in a body.
(define (nested-cond-expand)
  (cond-expand (else 'chosen)))
(chk "nested-cond-expand" (nested-cond-expand) 'chosen)

;; `define-values` in a body.
(define (nested-define-values)
  (define-values (a b) (values 10 20))
  (+ a b))
(chk "nested-define-values" (nested-define-values) 30)

;; `define-record-type` in a body.
(define (nested-define-record-type)
  (define-record-type <pt> (mk x) pt? (x pt-x))
  (pt-x (mk 7)))
(chk "nested-define-record-type" (nested-define-record-type) 7)

;; A top-level `define` of a procedure whose body does all of the above at
;; once — the shape a real program takes when it avoids top-level declarations.
(chk "all-nested"
     (list (nested-begin) (nested-cond-expand)
           (nested-define-values) (nested-define-record-type))
     (list 3 'chosen 30 7))
