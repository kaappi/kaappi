;; SRFI-238 (Codesets) conformance tests
;; Run: zig-out/bin/kaappi tests/scheme/srfi/srfi238.scm
;;
;; See lib/srfi/238.sld's header for the three codesets implemented here
;; ('iso3166, 'iso639, 'iso15924) and why each is a representative,
;; individually-verified subset of the corresponding ISO standard rather
;; than an exhaustive registry.

(import (scheme base) (scheme process-context) (srfi 238) (srfi 64))

(test-begin "srfi-238")

;;; --- codeset? ---

(test-assert "codeset?: iso3166 is known" (codeset? 'iso3166))
(test-assert "codeset?: iso639 is known" (codeset? 'iso639))
(test-assert "codeset?: iso15924 is known" (codeset? 'iso15924))
(test-assert "codeset?: an arbitrary symbol is not known" (not (codeset? 'not-a-real-codeset)))
(test-assert "codeset?: a non-symbol is not a codeset" (not (codeset? 42)))

;;; --- iso3166 (ISO 3166-1 country codes) ---

(test-equal "iso3166: alpha-2 -> numeric" 840 (codeset-number 'iso3166 'US))
(test-equal "iso3166: numeric -> alpha-2" 'US (codeset-symbol 'iso3166 840))
(test-equal "iso3166: alpha-2 -> message" "United States" (codeset-message 'iso3166 'US))
(test-equal "iso3166: numeric -> message" "United States" (codeset-message 'iso3166 840))
(test-equal "iso3166: symbol code returned as-is regardless of validity"
  'US (codeset-symbol 'iso3166 'US))
(test-equal "iso3166: integer code returned as-is regardless of validity"
  840 (codeset-number 'iso3166 840))
(test-equal "iso3166: unmatched numeric code has no symbol" #f (codeset-symbol 'iso3166 1))
(test-equal "iso3166: unmatched symbol has no message" #f (codeset-message 'iso3166 'ZZ))
(test-equal "iso3166: unmatched symbol has no number" #f (codeset-number 'iso3166 'ZZ))
(test-equal "iso3166: India numeric code" 356 (codeset-number 'iso3166 'IN))
(test-equal "iso3166: Japan message" "Japan" (codeset-message 'iso3166 'JP))
(test-equal "iso3166: Germany round-trip via number"
  'DE (codeset-symbol 'iso3166 (codeset-number 'iso3166 'DE)))
(test-assert "iso3166: codeset-symbols contains US" (memq 'US (codeset-symbols 'iso3166)))
(test-assert "iso3166: codeset-symbols has at least 50 entries"
  (>= (length (codeset-symbols 'iso3166)) 50))
(test-assert "iso3166: codeset-symbols has no duplicates"
  (let loop ((syms (codeset-symbols 'iso3166)))
    (or (null? syms)
        (and (not (memq (car syms) (cdr syms)))
             (loop (cdr syms))))))

;;; --- iso639 (ISO 639-1 language codes) ---

(test-equal "iso639: alpha-2 -> message" "English" (codeset-message 'iso639 'en))
(test-equal "iso639: French message" "French" (codeset-message 'iso639 'fr))
(test-equal "iso639: German message" "German" (codeset-message 'iso639 'de))
(test-equal "iso639: numeric side is always #f (no ISO 639 number space)"
  #f (codeset-number 'iso639 'en))
(test-equal "iso639: an integer code never matches a symbol (no numbers known)"
  #f (codeset-symbol 'iso639 1))
(test-equal "iso639: symbol code returned as-is" 'en (codeset-symbol 'iso639 'en))
(test-equal "iso639: unmatched symbol has no message" #f (codeset-message 'iso639 'zz))
(test-assert "iso639: codeset-symbols contains en" (memq 'en (codeset-symbols 'iso639)))
(test-assert "iso639: essentially-complete ISO 639-1 alpha-2 set has >= 150 entries"
  (>= (length (codeset-symbols 'iso639)) 150))
(test-assert "iso639: codeset-symbols has no duplicates"
  (let loop ((syms (codeset-symbols 'iso639)))
    (or (null? syms)
        (and (not (memq (car syms) (cdr syms)))
             (loop (cdr syms))))))

;;; --- iso15924 (ISO 15924 script codes) ---

(test-equal "iso15924: alpha-4 -> numeric" 215 (codeset-number 'iso15924 'Latn))
(test-equal "iso15924: numeric -> alpha-4" 'Latn (codeset-symbol 'iso15924 215))
(test-equal "iso15924: alpha-4 -> message" "Latin" (codeset-message 'iso15924 'Latn))
(test-equal "iso15924: numeric -> message" "Cyrillic" (codeset-message 'iso15924 220))
(test-equal "iso15924: Han numeric code" 500 (codeset-number 'iso15924 'Hani))
(test-equal "iso15924: the 'Common' pseudo-script" 998 (codeset-number 'iso15924 'Zyyy))
(test-equal "iso15924: the 'Inherited' pseudo-script" 'Zinh (codeset-symbol 'iso15924 994))
(test-equal "iso15924: unmatched numeric code has no symbol" #f (codeset-symbol 'iso15924 1))
(test-assert "iso15924: codeset-symbols contains Latn" (memq 'Latn (codeset-symbols 'iso15924)))
(test-assert "iso15924: codeset-symbols has at least 40 entries"
  (>= (length (codeset-symbols 'iso15924)) 40))
(test-assert "iso15924: codeset-symbols has no duplicates"
  (let loop ((syms (codeset-symbols 'iso15924)))
    (or (null? syms)
        (and (not (memq (car syms) (cdr syms)))
             (loop (cdr syms))))))

;;; --- unknown codesets: treated as empty, but distinguishable via codeset? ---

(test-equal "unknown codeset: codeset-symbols is empty"
  '() (codeset-symbols 'not-a-real-codeset))
(test-equal "unknown codeset: codeset-message is #f"
  #f (codeset-message 'not-a-real-codeset 'US))
(test-equal "unknown codeset: codeset-number on a symbol is #f"
  #f (codeset-number 'not-a-real-codeset 'US))
(test-equal "unknown codeset: a symbol code is still returned as-is"
  'US (codeset-symbol 'not-a-real-codeset 'US))
(test-equal "unknown codeset: an integer code is still returned as-is"
  840 (codeset-number 'not-a-real-codeset 840))
(test-assert "codeset? distinguishes an unknown codeset from a known one"
  (and (not (codeset? 'not-a-real-codeset)) (codeset? 'iso3166)))

;;; --- type errors: code must be a symbol or exact integer ---

(test-error "codeset-symbol: a string code is a type error"
  (codeset-symbol 'iso3166 "US"))
(test-error "codeset-number: a flonum code is a type error"
  (codeset-number 'iso3166 840.0))
(test-error "codeset-message: a list code is a type error"
  (codeset-message 'iso3166 (list 'US)))

(let ((runner (test-runner-current)))
  (test-end "srfi-238")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
