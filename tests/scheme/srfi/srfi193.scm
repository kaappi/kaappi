;;; SRFI 193 -- Command Line conformance test.
;;;
;;; command-line itself is R7RS-native and already exercised elsewhere; this
;;; suite covers the four procedures (srfi 193) layers on top of it:
;;; command-name, command-args, script-file, and script-directory. This
;;; file is always invoked as a script (a filename argument to kaappi, never
;;; `load`ed, `import`ed, or REPL-evaluated), so script-file/script-directory
;;; are exercised in their "running a script" branch, never their #f branch.
;;; Exact string content is intentionally not asserted beyond structural
;;; shape (no embedded path separator in command-name, a trailing separator
;;; on script-directory, etc.) since it varies with how the test is invoked
;;; (working directory, relative vs. absolute path passed on argv).

(import (scheme base) (scheme char) (scheme process-context) (srfi 64) (srfi 193))

;; True if c is a path separator on some supported host (POSIX '/' or
;; Windows '\'). script-file/script-directory accept both regardless of
;; the running host (see lib/srfi/193.sld's header comment), so assertions
;; here must too rather than assuming this suite always runs on POSIX.
(define (%path-separator? c)
  (or (char=? c #\/) (char=? c #\\)))

(test-begin "srfi-193")

;; (scheme base) has no string search primitive, so a couple of tiny local
;; helpers stand in for it.
(define (%contains-char? s c)
  (let loop ((i 0))
    (cond ((>= i (string-length s)) #f)
          ((char=? (string-ref s i) c) #t)
          (else (loop (+ i 1))))))

(define (%ends-with? s suffix)
  (let ((slen (string-length s)) (sflen (string-length suffix)))
    (and (>= slen sflen)
         (string=? (substring s (- slen sflen) slen) suffix))))

;;; --- command-name --------------------------------------------------------

(test-assert "command-name is a string or #f"
  (let ((r (command-name)))
    (or (string? r) (not r))))

;; This file is always run as a script with a non-empty argv[0], so
;; (car (command-line)) is never "" here and command-name is never #f.
(test-assert "command-name is a string when this file runs as a script"
  (string? (command-name)))

(test-assert "command-name has no directory separator"
  (let ((n (command-name)))
    (and (not (%contains-char? n #\/))
         (not (%contains-char? n #\\)))))

(test-assert "command-name has no leftover .scm extension"
  (not (%ends-with? (command-name) ".scm")))

;;; --- command-args --------------------------------------------------------

(test-assert "command-args is a list" (list? (command-args)))

(test-equal "command-args is (cdr (command-line))"
  (cdr (command-line)) (command-args))

;;; --- script-file -----------------------------------------------------------

(test-assert "script-file is a string when running as a script (this file)"
  (string? (script-file)))

(test-assert "script-file is an absolute path"
  (let ((f (script-file)))
    (and (> (string-length f) 0)
         (or (%path-separator? (string-ref f 0))
             ;; Windows drive-letter absolute path: "C:\..." or "C:/...".
             (and (>= (string-length f) 3)
                  (char-alphabetic? (string-ref f 0))
                  (char=? (string-ref f 1) #\:)
                  (%path-separator? (string-ref f 2)))))))

;;; --- script-directory ------------------------------------------------------

(test-assert "script-directory is a string when running as a script"
  (string? (script-directory)))

(test-assert "script-directory ends with a directory separator"
  (let ((d (script-directory)))
    (and (> (string-length d) 0)
         (%path-separator? (string-ref d (- (string-length d) 1))))))

(test-assert "script-directory is a prefix of script-file"
  (let ((d (script-directory)) (f (script-file)))
    (and (<= (string-length d) (string-length f))
         (string=? d (substring f 0 (string-length d))))))

;;; --- composition sanity ----------------------------------------------------

;; A common SRFI 193 idiom is (string-append (script-directory) "sibling")
;; to build a path to a file next to the running script. Sanity-check the
;; pieces compose without asserting exact content (which varies with how
;; the suite is invoked).
(test-assert "script-directory composes with command-name via string-append"
  (let* ((d (script-directory))
         (n (command-name))
         (composed (string-append d (or n "unknown") ".scm")))
    (and (>= (string-length composed) (string-length d))
         (string=? d (substring composed 0 (string-length d))))))

(let ((runner (test-runner-current)))
  (test-end "srfi-193")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
