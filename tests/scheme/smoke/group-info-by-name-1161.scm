;; Regression test for #1161: group-info by name returned gid 0
;; std.c.getgrnam was misdeclared as returning ?*passwd instead of ?*group

(import (scheme base) (scheme write) (scheme process-context) (srfi 64) (srfi 170))

(test-begin "group-info-by-name")

(let* ((gid (user-gid))
       (gi-by-id (group-info gid))
       (name (group-info:name gi-by-id))
       (gi-by-name (group-info name)))
  (test-equal "by-name gid matches by-id gid"
    (group-info:gid gi-by-id)
    (group-info:gid gi-by-name))
  (test-equal "by-name name matches by-id name"
    (group-info:name gi-by-id)
    (group-info:name gi-by-name)))

(let ((runner (test-runner-current)))
  (test-end "group-info-by-name")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
