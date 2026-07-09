;; Regression test for #1163: owner/unchanged and group/unchanged constants
(import (scheme base) (scheme write) (scheme process-context) (srfi 64) (srfi 170))

(test-begin "srfi-170-chown-constants")

;; Constants must be exported and equal to -1 (POSIX "unchanged" sentinel)
(test-equal "owner/unchanged is -1" -1 owner/unchanged)
(test-equal "group/unchanged is -1" -1 group/unchanged)

;; set-file-owner with both unchanged should be a no-op
(let ((tmp (create-temp-file)))
  (test-assert "set-file-owner with unchanged constants"
    (begin (set-file-owner tmp owner/unchanged group/unchanged) #t))
  (delete-file tmp))

;; set-file-owner with only owner unchanged
(let ((tmp (create-temp-file)))
  (test-assert "set-file-owner owner/unchanged keeps owner"
    (begin (set-file-owner tmp owner/unchanged (user-gid)) #t))
  (delete-file tmp))

;; set-file-owner with only group unchanged
(let ((tmp (create-temp-file)))
  (test-assert "set-file-owner group/unchanged keeps group"
    (begin (set-file-owner tmp (user-uid) group/unchanged) #t))
  (delete-file tmp))

(let ((runner (test-runner-current)))
  (test-end "srfi-170-chown-constants")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
