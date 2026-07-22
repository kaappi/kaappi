;;; SRFI 29 (Localization) conformance tests
;;; Run: zig-out/bin/kaappi --lib-path lib tests/scheme/srfi/srfi29.scm

(import (scheme base) (scheme process-context) (scheme file) (srfi 29) (srfi 64) (srfi 170))

(test-begin "srfi-29")

;;; --- declare-bundle! + localized-template: exact / default-translation lookup ---

;; A bundle declared with only a package name is the spec's "default
;; translation" — reached once localized-template's automatic
;; (package language country) -> (package language) -> (package) fallback
;; bottoms out, since (current-language)/(current-country) default to en/us
;; and no bundle is declared at those more specific levels.
(declare-bundle! '(greetings) '((hello . "Hello, ~a!")))

(test-equal "localized-template finds the default-translation bundle"
  "Hello, ~a!"
  (localized-template 'greetings 'hello))

(test-equal "format substitutes ~a into a looked-up template"
  "Hello, World!"
  (format (localized-template 'greetings 'hello) "World"))

(test-equal "localized-template: bundle exists but message key is missing -> #f"
  #f
  (localized-template 'greetings 'goodbye))

(test-equal "localized-template: no bundle at all for this package -> #f"
  #f
  (localized-template 'no-such-package-anywhere 'no-such-key))

;;; --- declare-bundle! overwrite semantics ---

(declare-bundle! '(overwrite-test) '((k . "old")))
(declare-bundle! '(overwrite-test) '((k . "new")))

(test-equal "declare-bundle! overwrites an existing bundle at the same specifier"
  "new"
  (localized-template 'overwrite-test 'k))

;;; --- current-language / current-country / current-locale-details ---

(test-equal "current-language default is en" 'en (current-language))
(test-equal "current-country default is us" 'us (current-country))
(test-equal "current-locale-details default is the empty list" '() (current-locale-details))

(current-locale-details '(utf8))
(test-equal "current-locale-details setter/getter round trip"
  '(utf8)
  (current-locale-details))
(current-locale-details '())

;;; --- Locale fallback: declare a bundle at a general locale, look up under
;;; --- a more specific one, and confirm the specific->general fallback. ---

(declare-bundle! '(mathlib fr) '((pi . "Pi vaut environ ~a.")))

(current-language 'fr)
(current-country 'ca)
(test-equal "locale fallback: (mathlib fr ca) falls back to the (mathlib fr) bundle"
  "Pi vaut environ ~a."
  (localized-template 'mathlib 'pi))
(current-language 'en)
(current-country 'us)

;; No bundle at any fallback level (not even the package-only default) ->  #f.
(test-equal "locale fallback exhausted with no match anywhere -> #f"
  #f
  (localized-template 'mathlib 'nonexistent-message))

;;; --- The spec's own worked example (English + French), verbatim ---
;;; Confirms both plain ~a substitution and the ~N@* positional-reorder
;;; extension against the exact strings the SRFI-29 document itself shows.

(declare-bundle! '(hello-program en)
                 '((time . "Its ~a, ~a.")
                   (goodbye . "Goodbye, ~a.")))
(declare-bundle! '(hello-program fr)
                 '((time . "~1@*~a, c'est ~a.")
                   (goodbye . "Au revoir, ~a.")))

(define (localized-message package message-name . args)
  (apply format (cons (localized-template package message-name) args)))

(test-equal "spec example: English time"
  "Its 12:00, Fred."
  (localized-message 'hello-program 'time "12:00" "Fred"))
(test-equal "spec example: English goodbye"
  "Goodbye, Fred."
  (localized-message 'hello-program 'goodbye "Fred"))

(current-language 'fr)
(test-equal "spec example: French time uses ~N@* to reorder arguments"
  "Fred, c'est 12:00."
  (localized-message 'hello-program 'time "12:00" "Fred"))
(test-equal "spec example: French goodbye"
  "Au revoir, Fred."
  (localized-message 'hello-program 'goodbye "Fred"))
(current-language 'en)

;;; --- format directives directly ---

(test-equal "format: ~a display substitution" "hi there" (format "~a ~a" "hi" "there"))
(test-equal "format: ~s write substitution" "\"hi\"" (format "~s" "hi"))
(test-equal "format: ~% newline" "a\nb" (format "a~%b"))
(test-equal "format: ~~ literal tilde" "a~b" (format "a~~b"))
(test-equal "format: ~N@* references absolutely without consuming"
  "b a"
  (format "~1@*~a ~a" "a" "b"))
(test-equal "format: ~N@* can reference the same value more than once"
  "a a b"
  (format "~0@*~a ~a ~a" "a" "b"))

;;; --- store-bundle! / load-bundle! best-effort persistence ---

(define (%bundle-file-path specifier)
  (define (join lst)
    (cond ((null? lst) "")
          ((null? (cdr lst)) (symbol->string (car lst)))
          (else (string-append (symbol->string (car lst)) "-" (join (cdr lst))))))
  (string-append (temp-file-prefix) "srfi29-bundle-" (join specifier) ".scm"))

(test-equal "store-bundle! on an undeclared bundle fails (not fatal)"
  #f
  (store-bundle! '(never-declared-srfi29-test-pkg)))

(test-equal "load-bundle! with nothing ever stored fails (not fatal)"
  #f
  (load-bundle! '(never-stored-srfi29-test-pkg)))

(declare-bundle! '(storetest en) '((msg . "Stored: ~a")))
(test-equal "store-bundle! on a declared bundle succeeds" #t (store-bundle! '(storetest en)))
(test-assert "store-bundle! actually wrote a file at the deterministic path"
  (file-exists? (%bundle-file-path '(storetest en))))

;; Overwrite the in-memory bundle, then prove load-bundle! re-reads the
;; persisted version from disk rather than trusting in-memory state.
(declare-bundle! '(storetest en) '((msg . "Overwritten in memory, not yet reloaded")))
(test-equal "load-bundle! on a stored bundle succeeds" #t (load-bundle! '(storetest en)))
(test-equal "load-bundle! restored the persisted (not the overwritten) content"
  "Stored: ~a"
  (localized-template 'storetest 'msg))

;; Clean up the temp file this test created.
(when (file-exists? (%bundle-file-path '(storetest en)))
  (delete-file (%bundle-file-path '(storetest en))))

(let ((runner (test-runner-current)))
  (test-end "srfi-29")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
