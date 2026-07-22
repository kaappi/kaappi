;;; SRFI 29 — Localization
;;;
;;; A message-bundle / gettext-style localization system. Programs register
;;; "bundles" of translated message templates under a "bundle specifier" — a
;;; list of symbols of the form (package-name language country ...), most to
;;; least specific — and retrieve a template for the current locale via
;;; `localized-template`, which falls back to progressively shorter
;;; specifiers (dropping country, then language) when no exact match exists,
;;; e.g. a lookup for (mathlib fr ca) falls back to (mathlib fr) and then
;;; (mathlib) before giving up. Message templates are strings meant to be
;;; passed through a `format`-style substitution procedure together with the
;;; caller's arguments; `localized-template` itself returns the raw,
;;; unsubstituted template.
;;;
;;; Spec ambiguities resolved:
;;;
;;; - The Specification section's own procedure-signature heading spells the
;;;   store procedure "store-bundle" (no bang), but every other occurrence —
;;;   the worked example, the Implementation section's prose, and its actual
;;;   reference-implementation source — consistently spells it
;;;   "store-bundle!". Since it is a mutating/effectful operation exactly
;;;   like its siblings `declare-bundle!` and `load-bundle!` (both spelled
;;;   with "!" everywhere including their own signature headings), this
;;;   implementation follows the bang-suffixed spelling used everywhere else
;;;   in the document and by the reference implementation: `store-bundle!`.
;;;
;;; - The "Bundle Searching" section's prose says that once the fallback
;;;   search empties the bundle specifier, "an error should be raised."
;;;   The section defining `localized-template` itself instead says
;;;   unconditionally: "If no such message could be found, false (#f) is
;;;   returned" — with no carve-out for the exhausted-fallback case — and
;;;   the spec's own reference implementation of `localized-template`
;;;   returns `#f` in exactly this situation, never raising an error. This
;;;   implementation follows `localized-template`'s own procedure spec and
;;;   the reference implementation: a failed lookup at every fallback level
;;;   returns `#f`, never raises.
;;;
;;; - The "Bundle Searching" example specifier is a 3-element
;;;   (package language country) list, and the reference implementation's
;;;   `localized-template` builds exactly that shape internally
;;;   (`(cons package-name (list (current-language) (current-country)))`),
;;;   never folding `current-locale-details` into the automatic search.
;;;   This implementation matches that: `current-locale-details` is fully
;;;   implemented as its own get/set accessor (some programs may want it
;;;   for building custom specifiers to pass directly to `declare-bundle!`),
;;;   but `localized-template`'s automatic fallback chain is always
;;;   package -> package+language -> package+language+country, matching the
;;;   spec's own example and reference implementation.
;;;
;;; - The Specification section normatively extends SRFI 28's `format` with
;;;   one more directive, `~N@*` (N decimal digits): "Causes a
;;;   value-requiring escape code that follows this code immediately to
;;;   reference the Nth optional value absolutely, rather than the next
;;;   unconsumed value. The referenced value is not consumed." (N is
;;;   0-based, confirmed against the spec's own worked example: the French
;;;   template "~1@*~a, c'est ~a." applied to ("12:00" "Fred") must produce
;;;   "Fred, c'est 12:00.", so ~1@* must select the second argument.) This
;;;   directive exists so a translation can reorder positional arguments to
;;;   match the target language's word order. SRFI 29 does not export a
;;;   `format` binding of its own — its examples just call whatever `format`
;;;   is in scope — but Kaappi's existing (srfi 28) implements only the
;;;   base SRFI-28 directives (~a ~s ~% ~~), not this extension, and it must
;;;   stay that way for programs that import (srfi 28) alone. So, exactly
;;;   like SRFI 29's own reference implementation (which ships a complete
;;;   "SRFI-28 and SRFI-29 compliant version of format" alongside the
;;;   bundle machinery), this library exports its own `format` — a superset
;;;   of (srfi 28)'s that additionally understands ~N@*. Note: Kaappi's
;;;   `import` does not diagnose colliding export names between libraries
;;;   (verified empirically — it is a plain last-write-wins map insert, see
;;;   `importBinding` in src/vm_library.zig); a program that imports both
;;;   (srfi 28) and (srfi 29) unqualified silently gets whichever `format`
;;;   was imported *last*, with no warning either way. This is a pre-existing
;;;   Kaappi behavior across all libraries, not specific to this one, but it
;;;   is worth flagging here since this file is an unusually likely place to
;;;   trigger it. Use `rename`/`only`/`except` to be explicit, or just import
;;;   (srfi 29) alone when its templates are in use.
;;;
;;; `store-bundle!`/`load-bundle!`: the spec leaves the storage mechanism
;;; completely unspecified, explicitly allowing an implementation that
;;; "chooses not to provide any external mechanism" as long as both
;;; procedures are still defined and return #f — "This failure is not a
;;; fatal error." This implementation goes one step further and provides a
;;; genuine best-effort file-based mechanism using only portable R7RS
;;; (scheme file) I/O plus SRFI 170's `temp-file-prefix` (a built-in,
;;; cross-platform primitive that yields an OS-appropriate writable path
;;; prefix, e.g. "/tmp/kaappi-" on POSIX): a bundle for specifier
;;; (pkg lang country) is written as one `write`-able alist to a
;;; deterministically-named file under that prefix (so a later `load-bundle!`
;;; for the same specifier — in this run or a fresh process — finds it), and
;;; every file operation is wrapped in `guard` so any failure (read-only
;;; filesystem, missing file, corrupt contents, or the temp directory being
;;; unwritable in a locked-down environment) degrades to the spec-sanctioned
;;; `#f` rather than propagating an error.
;;;
;;; `current-language`/`current-country`/`current-locale-details` default to
;;; 'en / 'us / '() — placeholders, exactly as flagged by the spec's own
;;; reference implementation ("must be rewritten for each Scheme system to
;;; default to the actual locale of the session"): R7RS has no portable API
;;; for reading the host OS locale, so detecting a real default is out of
;;; scope here. They are ordinary mutable closure state shared VM-wide,
;;; which the spec explicitly permits ("for the entire Scheme system if
;;; such a distinction is not possible").

(define-library (srfi 29)
  (import (scheme base) (scheme write) (scheme read) (scheme file) (srfi 69) (srfi 170))
  (export
    current-language current-country current-locale-details
    declare-bundle! store-bundle! load-bundle!
    localized-template
    format)

  (begin

    ;; -------------------------------------------------------------------
    ;; Current locale
    ;; -------------------------------------------------------------------

    (define current-language
      (let ((value 'en))
        (lambda args
          (if (null? args)
              value
              (set! value (car args))))))

    (define current-country
      (let ((value 'us))
        (lambda args
          (if (null? args)
              value
              (set! value (car args))))))

    (define current-locale-details
      (let ((value '()))
        (lambda args
          (if (null? args)
              value
              (set! value (car args))))))

    ;; -------------------------------------------------------------------
    ;; Bundle registry
    ;; -------------------------------------------------------------------

    ;; bundle-specifier (a list of symbols, e.g. (mathlib fr ca)) -> its
    ;; association list of (message-template-name . template-string) pairs.
    ;; make-hash-table's default comparator is equal?, which is exactly what
    ;; a list-of-symbols key needs.
    (define %bundle-registry (make-hash-table))

    (define (declare-bundle! bundle-specifier association-list)
      (hash-table-set! %bundle-registry bundle-specifier association-list)
      (if #f #f))

    ;; All but the last element of a non-empty list.
    (define (%drop-last lst)
      (if (null? (cdr lst))
          '()
          (cons (car lst) (%drop-last (cdr lst)))))

    (define (localized-template package-name message-template-name)
      (let loop ((specifier (list package-name (current-language) (current-country))))
        (if (null? specifier)
            #f
            (let* ((bundle (hash-table-ref/default %bundle-registry specifier #f))
                   (entry (and bundle (assq message-template-name bundle))))
              (cond
                (entry (cdr entry))
                ((null? (cdr specifier)) #f)
                (else (loop (%drop-last specifier))))))))

    ;; -------------------------------------------------------------------
    ;; Best-effort persistence (store-bundle! / load-bundle!)
    ;; -------------------------------------------------------------------

    (define (%join-symbols specifier)
      (cond ((null? specifier) "")
            ((null? (cdr specifier)) (symbol->string (car specifier)))
            (else (string-append (symbol->string (car specifier)) "-"
                                  (%join-symbols (cdr specifier))))))

    (define (%bundle-file-path bundle-specifier)
      (string-append (temp-file-prefix) "srfi29-bundle-"
                      (%join-symbols bundle-specifier) ".scm"))

    ;; A minimal sanity check that DATUM looks like a bundle association
    ;; list, so load-bundle! never hands declare-bundle! garbage read back
    ;; from a corrupted or foreign file.
    (define (%bundle-alist? datum)
      (and (list? datum)
           (let loop ((lst datum))
             (or (null? lst)
                 (and (pair? (car lst)) (symbol? (caar lst)) (loop (cdr lst)))))))

    (define (store-bundle! bundle-specifier)
      (let ((bundle (hash-table-ref/default %bundle-registry bundle-specifier #f)))
        (if (not bundle)
            #f
            (guard (exn (#t #f))
              (call-with-output-file (%bundle-file-path bundle-specifier)
                (lambda (port) (write bundle port)))
              #t))))

    (define (load-bundle! bundle-specifier)
      (guard (exn (#t #f))
        (let ((path (%bundle-file-path bundle-specifier)))
          (if (not (file-exists? path))
              #f
              (let ((datum (call-with-input-file path read)))
                (if (%bundle-alist? datum)
                    (begin (declare-bundle! bundle-specifier datum) #t)
                    #f))))))

    ;; -------------------------------------------------------------------
    ;; format — SRFI 28's directives (~a ~s ~% ~~) plus SRFI 29's ~N@*
    ;; -------------------------------------------------------------------

    (define (%ascii-digit? c) (and (char>=? c #\0) (char<=? c #\9)))

    (define (format template . objects)
      (let* ((argv (list->vector objects))
             (len (string-length template))
             (out (open-output-string)))
        ;; cursor: index of the next unconsumed value. override: if set (by
        ;; a preceding ~N@*), the index the *next* value-requiring directive
        ;; (~a or ~s) must use instead, without advancing cursor or being
        ;; itself consumed.
        (let loop ((i 0) (cursor 0) (override #f))
          (if (>= i len)
              (get-output-string out)
              (let ((c (string-ref template i)))
                (if (and (char=? c #\~) (< (+ i 1) len))
                    (let ((d (string-ref template (+ i 1))))
                      (cond
                        ((%ascii-digit? d)
                         (let scan ((j (+ i 1)) (n 0))
                           (if (and (< j len) (%ascii-digit? (string-ref template j)))
                               (scan (+ j 1)
                                     (+ (* n 10)
                                        (- (char->integer (string-ref template j))
                                           (char->integer #\0))))
                               (if (and (< (+ j 1) len)
                                        (char=? (string-ref template j) #\@)
                                        (char=? (string-ref template (+ j 1)) #\*))
                                   (loop (+ j 2) cursor n)
                                   ;; Malformed ~N@* (no @* after the digits):
                                   ;; emit the tilde literally and retry from
                                   ;; just past it, same recovery SRFI-28's
                                   ;; own format uses for unknown codes.
                                   (begin (write-char c out) (loop (+ i 1) cursor override))))))
                        ((char=? d #\a)
                         (let ((idx (or override cursor)))
                           (display (vector-ref argv idx) out)
                           (loop (+ i 2) (if override cursor (+ cursor 1)) #f)))
                        ((char=? d #\s)
                         (let ((idx (or override cursor)))
                           (write (vector-ref argv idx) out)
                           (loop (+ i 2) (if override cursor (+ cursor 1)) #f)))
                        ((char=? d #\%)
                         (newline out)
                         (loop (+ i 2) cursor override))
                        ((char=? d #\~)
                         (write-char #\~ out)
                         (loop (+ i 2) cursor override))
                        (else
                         (write-char #\~ out)
                         (write-char d out)
                         (loop (+ i 2) cursor override))))
                    (begin (write-char c out) (loop (+ i 1) cursor override))))))))))
