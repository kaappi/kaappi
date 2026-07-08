(import (scheme base) (scheme write) (scheme file) (scheme time) (srfi 170))

(define pass 0)
(define fail 0)
(define (check name got expected)
  (if (equal? got expected) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1))
             (display "FAIL: ") (display name)
             (display " expected ") (write expected)
             (display " got ") (write got) (newline))))
(define (check-true name val)
  (if val (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))
(define (check-false name val)
  (if (not val) (set! pass (+ pass 1))
      (begin (set! fail (+ fail 1)) (display "FAIL: ") (display name) (newline))))

;;; ---- file-info on current directory ----
(let ((fi (file-info ".")))
  (check-true "file-info?" (file-info? fi))
  (check-true "file-info-directory?" (file-info-directory? fi))
  (check-false "file-info-regular?" (file-info-regular? fi))
  (check-false "file-info-symlink?" (file-info-symlink? fi))
  (check-true "file-info:device" (number? (file-info:device fi)))
  (check-true "file-info:inode" (number? (file-info:inode fi)))
  (check-true "file-info:nlinks" (> (file-info:nlinks fi) 0))
  (check-true "file-info:uid" (number? (file-info:uid fi)))
  (check-true "file-info:gid" (number? (file-info:gid fi)))
  (check-true "file-info:atime" (number? (file-info:atime fi)))
  (check-true "file-info:ctime" (number? (file-info:ctime fi)))
  (check-true "file-info:mtime" (number? (file-info:mtime fi)))
  (check-true "file-info:blksize" (number? (file-info:blksize fi)))
  (check-true "file-info:blocks" (number? (file-info:blocks fi))))

;;; ---- file-info on regular file ----
(define test-file "/tmp/kaappi-fs-test.txt")
(let ((p (open-output-file test-file)))
  (display "test data here" p)
  (close-port p))

(let ((fi (file-info test-file)))
  (check-true "regular file?" (file-info-regular? fi))
  (check-false "regular dir?" (file-info-directory? fi))
  (check-true "file-info:size" (> (file-info:size fi) 0)))

;;; ---- Symlink operations ----
(define link-path "/tmp/kaappi-fs-test-link")
(when (file-exists? link-path) (delete-file link-path))
(create-symlink test-file link-path)
(check-true "symlink exists" (file-exists? link-path))
(check "read-symlink" (read-symlink link-path) test-file)

;; file-info on symlink (follow=false)
(let ((fi (file-info link-path #f)))
  (check-true "symlink fi symlink?" (file-info-symlink? fi)))

;; file-info on symlink (follow=true, default)
(let ((fi (file-info link-path)))
  (check-true "followed fi regular?" (file-info-regular? fi)))

(delete-file link-path)

;;; ---- Directory operations ----
(define test-dir "/tmp/kaappi-fs-test-dir")
(when (file-exists? test-dir) (delete-directory test-dir))
(create-directory test-dir)
(check-true "created dir exists" (file-exists? test-dir))
(check-true "created is dir" (file-info-directory? (file-info test-dir)))

;; directory-files
(let ((files (directory-files ".")))
  (check-true "directory-files is list" (list? files))
  (check-true "directory-files non-empty" (> (length files) 0)))

;; open-directory / read-directory / close-directory
(let ((d (open-directory ".")))
  (let ((first-entry (read-directory d)))
    (check-true "read-directory string" (string? first-entry)))
  (close-directory d))

(delete-directory test-dir)

;;; ---- Process state ----
(check-true "pid positive" (> (pid) 0))
(check-true "umask number" (number? (umask)))
(check-true "user-uid" (number? (user-uid)))
(check-true "user-gid" (number? (user-gid)))
(check-true "user-effective-uid" (number? (user-effective-uid)))
(check-true "user-effective-gid" (number? (user-effective-gid)))
(check-true "user-supplementary-gids list" (list? (user-supplementary-gids)))
(check-true "current-directory" (string? (current-directory)))

;;; ---- Environment variables ----
(set-environment-variable! "_KAAPPI_FS_TEST" "test_value")
(check "get-env" (get-environment-variable "_KAAPPI_FS_TEST") "test_value")
(delete-environment-variable! "_KAAPPI_FS_TEST")
(check-false "deleted env" (get-environment-variable "_KAAPPI_FS_TEST"))

(let ((vars (get-environment-variables)))
  (check-true "env-vars is list" (list? vars)))

;;; ---- terminal? ----
(check-false "terminal? on file port" (terminal? (open-input-file test-file)))

;;; ---- User/group info ----
(let ((u (user-info (user-uid))))
  (check-true "user-info?" (user-info? u))
  (check-true "user-info:name string" (string? (user-info:name u)))
  (check-true "user-info:uid number" (number? (user-info:uid u)))
  (check-true "user-info:gid number" (number? (user-info:gid u)))
  (check-true "user-info:home-dir string" (string? (user-info:home-dir u)))
  (check-true "user-info:shell string" (string? (user-info:shell u))))

(let ((u (user-info (user-info:name (user-info (user-uid))))))
  (check-true "user-info by name" (user-info? u)))

(let ((g (group-info (user-gid))))
  (check-true "group-info?" (group-info? g))
  (check-true "group-info:name string" (string? (group-info:name g)))
  (check-true "group-info:gid number" (number? (group-info:gid g))))

;;; ---- File manipulation ----
;; rename-file
(define test-file2 "/tmp/kaappi-fs-test-renamed.txt")
(when (file-exists? test-file2) (delete-file test-file2))
(rename-file test-file test-file2)
(check-true "renamed exists" (file-exists? test-file2))
(check-false "original gone" (file-exists? test-file))
(rename-file test-file2 test-file)

;; set-file-mode
(set-file-mode test-file #o644)
(check-true "set-file-mode" #t)

;; truncate-file
(truncate-file test-file 5)
(let ((fi (file-info test-file)))
  (check "truncate-file size" (file-info:size fi) 5))

;; set-file-times (no error)
(set-file-times test-file)
(check-true "set-file-times" #t)

;;; ---- real-path ----
(check-true "real-path string" (string? (real-path ".")))
(check-true "real-path absolute" (char=? #\/ (string-ref (real-path ".") 0)))

;;; ---- posix-time / monotonic-time ----
(check-true "posix-time is time object" (time? (posix-time)))
(check-true "posix-time seconds positive" (> (time-second (posix-time)) 0))
(check-true "monotonic-time is time object" (time? (monotonic-time)))
(check-true "monotonic-time seconds non-negative" (>= (time-second (monotonic-time)) 0))

;;; ---- current-second / current-jiffy / jiffies-per-second ----
(check-true "current-second" (> (current-second) 0))
(check-true "current-jiffy" (> (current-jiffy) 0))
(check-true "jiffies-per-second" (> (jiffies-per-second) 0))

;;; ---- command-line ----
(check-true "command-line is list" (list? (command-line)))

;;; Cleanup
(delete-file test-file)

;;; Summary
(display pass) (display " passed, ") (display fail) (display " failed")
(newline)
(if (> fail 0) (error "Filesystem coverage tests failed" fail))
