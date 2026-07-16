;; Audit tests for src/primitives_filesystem.zig — SRFI-170 filesystem,
;; process state, user/group db, time. Audit campaign Phase 2.5 (#1137).
;; This unit also serves as Phase 3.1's SRFI-170 coverage (see strategy doc).
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme write) (scheme file) (srfi 170) (srfi 60))
(import (scheme process-context) (srfi 64))

;; symlinks/FIFOs/uid-gid are POSIX-only — skip there. (After the imports:
;; the skip branch calls exit, which (scheme process-context) provides.)
(cond-expand
  (windows (display "skipped on windows\n") (exit 0))
  (else #f))

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
(test-equal '("a.txt") (directory-files D))
(test-equal #t (and (member ".hidden" (directory-files D #t))
                    (member "a.txt" (directory-files D #t)) #t))

;;; --- file-info with follow? flag ---
(let ((fi (file-info (string-append D "/a.txt") #t)))
  (test-equal #t (file-info? fi))
  (test-equal #f (file-info? 42))
  (test-equal 4 (file-info:size fi))
  (test-equal #t (file-info-regular? fi))
  (test-equal #f (file-info-directory? fi))
  (test-equal #t (and (exact? (file-info:mtime fi)) (exact? (file-info:atime fi))
                      (exact? (file-info:ctime fi))))
  (test-equal #t (>= (file-info:nlinks fi) 1))
  (test-equal #t (= (file-info:uid fi) (user-uid))))
(test-equal #t (file-info-directory? (file-info D #t)))
(test-equal 'regular (file-info-type (file-info (string-append D "/a.txt") #t)))

;;; --- symlinks: follow? governs stat vs lstat ---
(create-symlink (string-append D "/a.txt") (string-append D "/ln"))
(test-equal #t (file-info-symlink? (file-info (string-append D "/ln") #f)))
(test-equal #f (file-info-symlink? (file-info (string-append D "/ln") #t)))
(test-equal (string-append D "/a.txt") (read-symlink (string-append D "/ln")))
(test-equal #t (string=? (real-path (string-append D "/ln"))
                         (real-path (string-append D "/a.txt"))))
(test-equal 'symlink (file-info-type (file-info (string-append D "/ln") #f)))

;;; --- create-directory with permission bits ---
(create-directory (string-append D "/sub") #o700)
(test-equal #o700 (logand (file-info:mode (file-info (string-append D "/sub") #t)) #o777))

;;; --- rename-file overwrites; set-file-mode; truncate-file ---
(call-with-output-file (string-append D "/b.txt") (lambda (port) (display "bb" port)))
(rename-file (string-append D "/b.txt") (string-append D "/a.txt"))
(test-equal 2 (file-info:size (file-info (string-append D "/a.txt") #t)))
(set-file-mode (string-append D "/a.txt") #o600)
(test-equal #o600 (logand (file-info:mode (file-info (string-append D "/a.txt") #t)) #o777))
(truncate-file (string-append D "/a.txt") 1)
(test-equal 1 (file-info:size (file-info (string-append D "/a.txt") #t)))

;;; --- hard links; fifo; ownership; times ---
(create-hard-link (string-append D "/a.txt") (string-append D "/hard"))
(test-equal 2 (file-info:nlinks (file-info (string-append D "/a.txt") #t)))
(create-fifo (string-append D "/fifo"))
(test-equal #t (file-info-fifo? (file-info (string-append D "/fifo") #f)))
;; chown to self is always permitted (spec: 3-arg chown-style signature)
(test-equal #t (begin (set-file-owner (string-append D "/a.txt") (user-uid) (user-gid)) #t))
(test-equal #t (begin (set-file-times (string-append D "/a.txt")) #t))
(test-equal #t (begin (set-file-owner (string-append D "/a.txt")
                                      owner/unchanged group/unchanged) #t))

;;; --- temp files ---
(test-equal #t (procedure? temp-file-prefix))     ; parameter object
(let ((tf (create-temp-file)))
  (test-equal #t (file-exists? tf))
  (delete-file tf))
(let ((tf (create-temp-file (string-append D "/pfx-"))))
  (test-equal #t (file-exists? tf))
  (delete-file tf))

;;; --- directory streams: dotfiles skipped by default, no . / .. ---
(let ((ds (open-directory D)))
  (define (drain acc)
    (let ((e (read-directory ds)))
      (if (eof-object? e) acc (drain (cons e acc)))))
  (let ((entries (drain '())))
    (test-equal #f (member "." entries))
    (test-equal #f (member ".." entries))
    (test-equal #f (member ".hidden" entries))
    (test-equal #t (and (member "a.txt" entries) #t)))
  (close-directory ds))

;;; --- process state ---
(test-equal #t (> (pid) 0))
(test-equal #t (string? (current-directory)))
(let ((old (umask)))
  (set-umask! #o027)
  (test-equal #o027 (umask))
  (set-umask! old)
  (test-equal old (umask)))
(test-equal #t (number? (nice 0)))
(test-equal #t (and (number? (user-uid)) (number? (user-gid))
                    (number? (user-effective-uid)) (number? (user-effective-gid))))
(test-equal #t (pair? (user-supplementary-gids)))

;;; --- environment variables (write side) ---
(set-environment-variable! "KAAPPI_AUDIT_VAR" "v1")
(test-equal "v1" (get-environment-variable "KAAPPI_AUDIT_VAR"))
(delete-environment-variable! "KAAPPI_AUDIT_VAR")
(test-equal #f (get-environment-variable "KAAPPI_AUDIT_VAR"))

;;; --- user/group database ---
(let ((ui (user-info (user-uid))))
  (test-equal #t (user-info? ui))
  (test-equal #f (user-info? "root"))
  (test-equal #t (string? (user-info:name ui)))
  (test-equal #t (string? (user-info:home-dir ui)))
  (test-equal #t (string? (user-info:shell ui)))
  ;; by-name dispatch returns the same account
  (test-equal (user-uid) (user-info:uid (user-info (user-info:name ui))))
  (test-equal (user-info:gid ui) (user-info:gid (user-info (user-info:name ui)))))
(let ((gi (group-info (user-gid))))
  (test-equal #t (group-info? gi))
  (test-equal #t (string? (group-info:name gi)))
  (test-equal (user-gid) (group-info:gid gi)))
(test-equal (user-gid)
  (group-info:gid (group-info (group-info:name (group-info (user-gid))))))

;;; --- time ---
(test-equal #t (not (number? (monotonic-time))))
(test-equal #t (not (number? (posix-time))))

;;; --- terminal? ---
(test-equal #f (terminal? (open-input-string "x")))

;;; --- errors are catchable ---
(test-equal #t (guard (e (#t #t)) (file-info "/nonexistent-kaappi-fs" #t)))
(test-equal #t (guard (e (#t #t)) (delete-directory "/nonexistent-kaappi-fs")))
(test-equal #t (guard (e (#t #t)) (delete-directory D)))          ; non-empty
(test-equal #t (guard (e (#t #t)) (read-symlink (string-append D "/a.txt"))))
(test-equal #t (guard (e (#t #t)) (create-directory D)))          ; exists
(test-equal #t (guard (e (#t #t)) (directory-files "/nonexistent-kaappi-fs")))
(test-equal #t (guard (e (#t #t)) (file-info 42 #t)))
(test-equal #t (guard (e (#t #t)) (user-info #f)))
(test-equal #t (guard (e (#t #t)) (group-info 3.14)))
(test-equal #t (guard (e (#t #t)) (truncate-file (string-append D "/a.txt") "n")))

;;; --- cleanup ---
(for-each (lambda (n) (rm-f (string-append D "/" n)))
          '("a.txt" ".hidden" "ln" "hard" "fifo"))
(rmdir-f (string-append D "/sub"))
(rmdir-f D)
(test-equal #f (file-exists? D))

(let ((runner (test-runner-current)))
  (test-end "primitives_filesystem audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
