;; SRFI-59 (Vicinity) conformance tests.
;;
;; Vicinities describe a file-system location abstractly enough that
;; combining them with `in-vicinity` stays portable even though each
;; individual procedure here is inherently file-system specific. See
;; lib/srfi/59.sld for the (documented) choices made where the spec leaves
;; behavior undefined or implementation-defined.

(import (scheme base) (scheme process-context) (srfi 64) (srfi 59))

(test-begin "srfi-59")

;; --- vicinity:suffix? ------------------------------------------------------

(test-assert "vicinity:suffix?: / is a separator" (vicinity:suffix? #\/))
(test-assert "vicinity:suffix?: a is not a separator"
             (not (vicinity:suffix? #\a)))
(test-assert "vicinity:suffix?: empty-ish char . is not a separator"
             (not (vicinity:suffix? #\.)))

;; --- make-vicinity -----------------------------------------------------

(test-equal "make-vicinity: returns dirpath unchanged"
            "/usr/local/lib/"
            (make-vicinity "/usr/local/lib/"))
(test-equal "make-vicinity: empty string round-trips" "" (make-vicinity ""))

;; --- pathname->vicinity ------------------------------------------------

(test-equal "pathname->vicinity: strips the trailing filename (spec example)"
            "/usr/local/lib/scm/"
            (pathname->vicinity "/usr/local/lib/scm/Link.scm"))

(test-equal "pathname->vicinity: a bare filename has the empty (current-directory) vicinity"
            ""
            (pathname->vicinity "foo.scm"))

(test-equal "pathname->vicinity: a single trailing separator is kept"
            "/"
            (pathname->vicinity "/"))

(test-equal "pathname->vicinity: nested directories"
            "/a/b/c/"
            (pathname->vicinity "/a/b/c/d.scm"))

;; --- user-vicinity / library-vicinity / implementation-vicinity --------

(test-equal "user-vicinity: empty string means current directory"
            ""
            (user-vicinity))
(test-equal "library-vicinity: no distinct directory in Kaappi"
            ""
            (library-vicinity))
(test-equal "implementation-vicinity: no distinct directory in Kaappi"
            ""
            (implementation-vicinity))

;; --- home-vicinity -------------------------------------------------------

;; Per spec, #f when there's no notion of a home directory; otherwise a
;; string ending in a vicinity separator (checked via vicinity:suffix?, not
;; a hardcoded "/", so this holds under the Windows cond-expand branch too).
(let ((home (home-vicinity)))
  (test-assert "home-vicinity: #f, or a separator-terminated string"
               (or (not home)
                   (and (string? home)
                        (positive? (string-length home))
                        (vicinity:suffix? (string-ref home
                                                      (- (string-length home) 1)))))))

;; --- in-vicinity -----------------------------------------------------

(test-equal "in-vicinity: string-append of vicinity and filename"
            "/usr/local/foo.scm"
            (in-vicinity "/usr/local/" "foo.scm"))

(test-equal "in-vicinity: empty vicinity yields the filename unchanged"
            "foo.scm"
            (in-vicinity (user-vicinity) "foo.scm"))

(test-equal "in-vicinity: an absolute filename overrides the (user-vicinity) empty vicinity"
            "/etc/foo.scm"
            (in-vicinity (user-vicinity) "/etc/foo.scm"))

;; --- sub-vicinity ----------------------------------------------------

(test-equal "sub-vicinity: combines vicinity, name, and a separator"
            "/usr/local/lib/myapp/"
            (sub-vicinity "/usr/local/lib/" "myapp"))

(test-equal "sub-vicinity: result composes with in-vicinity like any other vicinity"
            "/usr/local/lib/myapp/config.scm"
            (in-vicinity (sub-vicinity "/usr/local/lib/" "myapp") "config.scm"))

;; --- program-vicinity --------------------------------------------------

;; Both the direct `kaappi ... srfi59.scm` invocation and run-all.sh run this
;; file as the top-level script, so %script-path (and thus program-vicinity)
;; must see this file's own path, not #f.
(let ((vicinity (program-vicinity)))
  (test-assert "program-vicinity: a string when running as a script"
               (string? vicinity))
  (test-assert "program-vicinity: ends in a vicinity separator"
               (and (string? vicinity)
                    (positive? (string-length vicinity))
                    (vicinity:suffix? (string-ref vicinity
                                                  (- (string-length vicinity) 1))))))

;; program-vicinity should agree with pathname->vicinity applied to a path
;; that ends in this file's own name: composing it back with in-vicinity
;; must look like a normal path, not a fabricated one.
(test-assert "program-vicinity: composes with in-vicinity"
             (let* ((vicinity (program-vicinity)) (combined (in-vicinity vicinity
                                                                         "srfi59.scm")))
               (and (string? combined)
                    (string=? combined (string-append vicinity "srfi59.scm")))))

(let ((runner (test-runner-current)))
  (test-end "srfi-59")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
