;;; SRFI 7 — Feature-based program configuration language
;;;
;;; SRFI 7 predates R7RS: it defines a standalone, non-Scheme "configuration
;;; language" for describing which features/files/code a multi-file program
;;; needs, with feature-conditional inclusion. The SRFI's own text explains
;;; that its `cond-expand` sub-language was the direct ancestor of R7RS's
;;; standardized `cond-expand`, and that its `files`/`requires` clauses cover
;;; the same ground R7RS later formalized with `define-library`/`import`.
;;;
;;; This implementation is (deliberately) the SRFI's own second reference
;;; implementation almost verbatim: a syntax-rules macro layered directly on
;;; top of `cond-expand`, exactly as the SRFI text describes ("a `program`
;;; macro built on top of SRFI 0's cond-expand"). It needs no syntax-case, no
;;; custom ellipsis, and no bracket syntax, so it ports with only one
;;; substantive change from the original:
;;;
;;;   `requires` failure: SRFI 7 says "if any [required features] are
;;;   unavailable ... the program cannot be run." The original reference
;;;   expands `(requires id ...)` to a bare
;;;   `(cond-expand ((and id ...) 'okay))` with no `else` clause, relying on
;;;   the host's cond-expand to treat "no clause matched, and there is no
;;;   else" as an error. Kaappi's `cond-expand` instead treats that case as a
;;;   silent no-op (confirmed empirically), so the original form would let a
;;;   program with a missing required feature run anyway — silently wrong.
;;;   This port adds an explicit `else` branch that raises a clear error, so
;;;   `requires` actually enforces what the spec promises. The same fix is
;;;   applied to `feature-cond` without a user-supplied `else`: SRFI 7 says
;;;   "if no clause can be satisfied the <program> cannot be evaluated,"
;;;   which again needs an explicit error clause under Kaappi's cond-expand
;;;   semantics.
;;;
;;; `files` is implemented with `(load filename)`, exactly as SRFI 7's own
;;; text anticipates: "this version requires that load use the current
;;; evaluation environment." Because `load` is referenced only inside this
;;; library's macro template, hygiene resolves it against this library's own
;;; `(scheme load)` import — a program using `(files ...)` does not need to
;;; import `(scheme load)` itself.
;;;
;;; Scope notes:
;;;  - `process-program` (SRFI 7's other reference implementation, a plain
;;;    procedure that returns the resultant form list or #f) is not provided;
;;;    only the `program` macro is exported, matching what every other
;;;    portable SRFI in this repo does for macro-shaped features.
;;;  - A `<feature identifier>` is whatever `cond-expand` accepts, i.e.
;;;    anything satisfying `libraryIsAvailableSrfi261`/`srfiFeatureAvailable`
;;;    or the KEP-0004 platform identifiers (see kaappi/CLAUDE.md) — the SRFI
;;;    only says "a symbol which is the name of a SRFI," but Kaappi's
;;;    cond-expand already accepts platform features too, and there is no
;;;    reason to reject them here.
;;;  - `files` loads relative to the current working directory (whatever
;;;    `load` does), not relative to the file containing the `program` form,
;;;    since `load` is an ordinary runtime procedure with no notion of "the
;;;    source file currently being compiled."

(define-library (srfi 7)
  (import (scheme base) (scheme load))
  (export program)
  (begin

    (define-syntax program
      (syntax-rules (requires files code feature-cond else)
        ((program) (begin))

        ((program (requires feature-id ...) more ...)
         (begin (cond-expand
                  ((and feature-id ...) 'okay)
                  (else (error "program: required feature(s) not available"
                               '(feature-id ...))))
                (program more ...)))

        ((program (files filename ...) more ...)
         (begin (load filename) ...
                (program more ...)))

        ((program (code stuff ...) more ...)
         (begin stuff ...
                (program more ...)))

        ((program (feature-cond (requirement stuff ...) ... (else else-stuff ...)) more ...)
         (begin (cond-expand (requirement (program stuff ...)) ...
                              (else (program else-stuff ...)))
                (program more ...)))

        ((program (feature-cond (requirement stuff ...) ...) more ...)
         (begin (cond-expand (requirement (program stuff ...)) ...
                              (else (error "program: no feature-cond clause was satisfied")))
                (program more ...)))))))
