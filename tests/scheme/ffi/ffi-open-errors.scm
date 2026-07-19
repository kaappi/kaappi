;; Regression test: ffi-open failure diagnostics.
;;   1. A name containing a path separator must not be re-searched under
;;      <home>/lib/ (dlopen semantics), so the reported error can never be
;;      about a "<home>/lib/<abs-path>" mashup the user never asked for.
;;   2. When a candidate exists on disk but fails to load (bad format, code
;;      signing, wrong architecture), that candidate's error is reported —
;;      not the "no such file" of whichever fallback probe ran last.
(import (scheme base)
        (scheme write)
        (scheme file)
        (scheme process-context)
        (srfi 64)
        (srfi 170))

(test-begin "ffi-open-errors")

;; A file that exists but is not a loadable shared library.
(define garbage-name "ffi-open-errors-garbage.tmp")
(define garbage-path (string-append (current-directory) "/" garbage-name))
(when (file-exists? garbage-path) (delete-file garbage-path))
(call-with-output-file garbage-path
                       (lambda (p)
                         (write-string "definitely not a shared library" p)))

(define (open-error-message target)
  (guard (e (#t (error-object-message e))) (ffi-open target) #f))

(test-assert "existing unloadable file: its own load error is reported"
             (let ((msg (open-error-message garbage-path)))
               (and (string? msg)
                    (string-contains msg garbage-name)
                    (not (string-contains msg
                                          (string-append garbage-name ".so")))
                    (not (string-contains msg
                                          (string-append garbage-name ".dylib")))
                    (not (string-contains msg
                                          (string-append garbage-name ".dll"))))))

(test-assert "missing library: requested name and probe note are reported"
             (let ((msg (open-error-message "kaappi-ffi-no-such-lib")))
               (and (string? msg)
                    (string-contains msg "kaappi-ffi-no-such-lib")
                    (string-contains msg "also tried"))))

(test-assert "path input: no home-dir mashup path is reported"
             (let ((msg (open-error-message "/kaappi-ffi-no-such-dir/libnope")))
               (and (string? msg)
                    (string-contains msg "libnope")
                    (not (string-contains msg "lib//")))))

(delete-file garbage-path)

(let ((runner (test-runner-current)))
  (test-end "ffi-open-errors")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
