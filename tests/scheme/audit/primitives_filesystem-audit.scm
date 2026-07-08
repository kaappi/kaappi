;; Audit tests for src/primitives_filesystem.zig — SRFI-170 filesystem,
;; process state, user/group db, time. Audit campaign Phase 2.5 (#1137).
;; This unit also serves as Phase 3.1's SRFI-170 coverage (see strategy doc).
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme write) (scheme file) (srfi 170) (srfi 60))
(import (chibi test))

(test-begin "primitives_filesystem audit")

(define D "/tmp/kaappi-audit-fs-suite")
;; rerun-safe setup
(define (rm-f p) (guard (e (#t #f)) (delete-file p)))
(define (rmdir-f p) (guard (e (#t #f)) (delete-directory p)))
(for-each (lambda (n) (rm-f (string-append D "/" n)))
          '("a.txt" ".hidden" "ln" "hard" "fifo"))
(rmdir-f (string-append D "/sub"))
(rmdir-f D)

(create-directory D)
(call-with-output-file (string-append D "/a.txt")
  (lambda (port) (display "aaaa" port)))
(call-with-output-file (string-append D "/.hidden")
  (lambda (port) (display "h" port)))

;;; --- directory-files: no . / .., dotfiles opt-in ---
(test '("a.txt") (directory-files D))
(test #t (and (member ".hidden" (directory-files D #t))
              (member "a.txt" (directory-files D #t)) #t))

;;; --- file-info with follow? flag ---
(let ((fi (file-info (string-append D "/a.txt") #t)))
  (test #t (file-info? fi))
  (test #f (file-info? 42))
  (test 4 (file-info:size fi))
  (test #t (file-info-regular? fi))
  (test #f (file-info-directory? fi))
  (test #t (and (exact? (file-info:mtime fi)) (exact? (file-info:atime fi))
                (exact? (file-info:ctime fi))))
  (test #t (>= (file-info:nlinks fi) 1))
  (test #t (= (file-info:uid fi) (user-uid))))
(test #t (file-info-directory? (file-info D #t)))
(test 'regular (file-info-type (file-info (string-append D "/a.txt") #t)))

;;; --- symlinks: follow? governs stat vs lstat ---
(create-symlink (string-append D "/a.txt") (string-append D "/ln"))
(test #t (file-info-symlink? (file-info (string-append D "/ln") #f)))
(test #f (file-info-symlink? (file-info (string-append D "/ln") #t)))
(test (string-append D "/a.txt") (read-symlink (string-append D "/ln")))
(test #t (string=? (real-path (string-append D "/ln"))
                   (real-path (string-append D "/a.txt"))))
(test 'symlink (file-info-type (file-info (string-append D "/ln") #f)))

;;; --- create-directory with permission bits ---
(create-directory (string-append D "/sub") #o700)
(test #o700 (logand (file-info:mode (file-info (string-append D "/sub") #t)) #o777))

;;; --- rename-file overwrites; set-file-mode; truncate-file ---
(call-with-output-file (string-append D "/b.txt") (lambda (port) (display "bb" port)))
(rename-file (string-append D "/b.txt") (string-append D "/a.txt"))
(test 2 (file-info:size (file-info (string-append D "/a.txt") #t)))
(set-file-mode (string-append D "/a.txt") #o600)
(test #o600 (logand (file-info:mode (file-info (string-append D "/a.txt") #t)) #o777))
(truncate-file (string-append D "/a.txt") 1)
(test 1 (file-info:size (file-info (string-append D "/a.txt") #t)))

;;; --- hard links; fifo; ownership; times ---
(create-hard-link (string-append D "/a.txt") (string-append D "/hard"))
(test 2 (file-info:nlinks (file-info (string-append D "/a.txt") #t)))
(create-fifo (string-append D "/fifo"))
(test #t (file-info-fifo? (file-info (string-append D "/fifo") #f)))
;; chown to self is always permitted (spec: 3-arg chown-style signature)
(test #t (begin (set-file-owner (string-append D "/a.txt") (user-uid) (user-gid)) #t))
(test #t (begin (set-file-times (string-append D "/a.txt")) #t))
;; FAIL: #1163 (owner/unchanged, group/unchanged constants not exported)
;; (test #t (begin (set-file-owner (string-append D "/a.txt")
;;                                 owner/unchanged group/unchanged) #t))

;;; --- temp files ---
(test #t (procedure? temp-file-prefix))     ; parameter object
(let ((tf (create-temp-file)))
  (test #t (file-exists? tf))
  (delete-file tf))
(let ((tf (create-temp-file (string-append D "/pfx-"))))
  (test #t (file-exists? tf))
  (delete-file tf))

;;; --- directory streams: dotfiles skipped by default, no . / .. ---
(let ((ds (open-directory D)))
  (define (drain acc)
    (let ((e (read-directory ds)))
      (if (eof-object? e) acc (drain (cons e acc)))))
  (let ((entries (drain '())))
    (test #f (member "." entries))
    (test #f (member ".." entries))
    (test #f (member ".hidden" entries))
    (test #t (and (member "a.txt" entries) #t)))
  (close-directory ds))

;;; --- process state ---
(test #t (> (pid) 0))
(test #t (string? (current-directory)))
(let ((old (umask)))
  (set-umask! #o027)
  (test #o027 (umask))
  (set-umask! old)
  (test old (umask)))
(test #t (number? (nice 0)))
(test #t (and (number? (user-uid)) (number? (user-gid))
              (number? (user-effective-uid)) (number? (user-effective-gid))))
(test #t (pair? (user-supplementary-gids)))

;;; --- environment variables (write side) ---
(set-environment-variable! "KAAPPI_AUDIT_VAR" "v1")
(test "v1" (get-environment-variable "KAAPPI_AUDIT_VAR"))
(delete-environment-variable! "KAAPPI_AUDIT_VAR")
(test #f (get-environment-variable "KAAPPI_AUDIT_VAR"))

;;; --- user/group database ---
(let ((ui (user-info (user-uid))))
  (test #t (user-info? ui))
  (test #f (user-info? "root"))
  (test #t (string? (user-info:name ui)))
  (test #t (string? (user-info:home-dir ui)))
  (test #t (string? (user-info:shell ui)))
  ;; by-name dispatch returns the same account
  (test (user-uid) (user-info:uid (user-info (user-info:name ui))))
  (test (user-info:gid ui) (user-info:gid (user-info (user-info:name ui)))))
(let ((gi (group-info (user-gid))))
  (test #t (group-info? gi))
  (test #t (string? (group-info:name gi)))
  (test (user-gid) (group-info:gid gi)))
(test (user-gid)
  (group-info:gid (group-info (group-info:name (group-info (user-gid))))))

;;; --- time ---
(test #t (>= (monotonic-time) 0))
(test #t (> (posix-time) 0))
;; FAIL: #1162 (posix-time/monotonic-time must return SRFI-19 time objects)
;; (test #t (let ((t (posix-time))) (and (not (number? t)) #t)))

;;; --- terminal? ---
(test #f (terminal? (open-input-string "x")))

;;; --- errors are catchable ---
(test #t (guard (e (#t #t)) (file-info "/nonexistent-kaappi-fs" #t)))
(test #t (guard (e (#t #t)) (delete-directory "/nonexistent-kaappi-fs")))
(test #t (guard (e (#t #t)) (delete-directory D)))          ; non-empty
(test #t (guard (e (#t #t)) (read-symlink (string-append D "/a.txt"))))
(test #t (guard (e (#t #t)) (create-directory D)))          ; exists
(test #t (guard (e (#t #t)) (directory-files "/nonexistent-kaappi-fs")))
(test #t (guard (e (#t #t)) (file-info 42 #t)))
(test #t (guard (e (#t #t)) (user-info #f)))
(test #t (guard (e (#t #t)) (group-info 3.14)))
(test #t (guard (e (#t #t)) (truncate-file (string-append D "/a.txt") "n")))

;;; --- cleanup ---
(for-each (lambda (n) (rm-f (string-append D "/" n)))
          '("a.txt" ".hidden" "ln" "hard" "fifo"))
(rmdir-f (string-append D "/sub"))
(rmdir-f D)
(test #f (file-exists? D))

(test-end "primitives_filesystem audit")
