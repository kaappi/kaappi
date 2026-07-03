;;; Regression test for #805: filesystem primitives must reject paths
;;; containing embedded NUL bytes instead of silently truncating them.

(import (scheme base) (scheme write) (scheme process-context) (srfi 64)
        (srfi 170))

(test-begin "filesystem-nul-path-805")

;; file-info with embedded NUL must raise an error, not stat the truncated path
(test-error "file-info rejects embedded NUL"
  (file-info (string-append "/etc" (string #\null) "bogus")))

;; current-directory is valid; set-current-directory! with NUL must error
(let ((cwd (current-directory)))
  (test-error "set-current-directory! rejects embedded NUL"
    (set-current-directory! (string-append cwd (string #\null) "x"))))

;; directory-files with embedded NUL must error
(test-error "directory-files rejects embedded NUL"
  (directory-files (string-append "/tmp" (string #\null) "nope")))

;; create-directory with embedded NUL must error
(test-error "create-directory rejects embedded NUL"
  (create-directory (string-append "/tmp/kaappi-test" (string #\null) "x")))

;; delete-directory with embedded NUL must error
(test-error "delete-directory rejects embedded NUL"
  (delete-directory (string-append "/tmp/kaappi-test" (string #\null) "x")))

;; rename-file with embedded NUL in either argument must error
(test-error "rename-file rejects embedded NUL in source"
  (rename-file (string-append "/tmp/a" (string #\null) "b") "/tmp/c"))
(test-error "rename-file rejects embedded NUL in target"
  (rename-file "/tmp/a" (string-append "/tmp/c" (string #\null) "d")))

;; real-path with embedded NUL must error
(test-error "real-path rejects embedded NUL"
  (real-path (string-append "/etc" (string #\null) "x")))

;; open-directory with embedded NUL must error
(test-error "open-directory rejects embedded NUL"
  (open-directory (string-append "/tmp" (string #\null) "x")))

;; Normal paths still work
(test-assert "file-info on /tmp succeeds"
  (file-info? (file-info "/tmp")))

(let ((runner (test-runner-current)))
  (test-end "filesystem-nul-path-805")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
