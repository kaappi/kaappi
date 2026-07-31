;; Audit tests for src/primitives_filesystem.zig — SRFI-170 filesystem,
;; process state, user/group db, time. Audit campaign Phase 2.5 (#1137),
;; extended by v2 Phase 2.12 (docs/audit-strategy.md) — the v2 pass covers
;; all 68 specs, the syscall error-path matrix (nonexistent / wrong kind /
;; permission / broken symlink / symlink loop / too long / empty / embedded
;; NUL / relative / vanished), file-info across every reachable file type,
;; the directory-object lifecycle, and the error taxonomy.
;; This unit also serves as Phase 3.1's SRFI-170 coverage (see strategy doc).
;; Run directly and read the printed counts — run-all.sh only sees exit codes.

(import (scheme base) (scheme write) (scheme file) (srfi 170) (srfi 60))
(import (scheme process-context) (srfi 64))
(import (only (srfi 18) make-thread thread-start! thread-join! time? time->seconds))

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
;; lstat must describe the link itself, and with the *modern* struct
;; layout: POSIX guarantees st_size = strlen(target), and the timestamps
;; must be sane. Guards the NetBSD __lstat50 versioned-symbol fix — the
;; plain compat lstat leaves the size/time fields shifted or with garbage
;; high bits (docs/dev/netbsd.md).
(let ((lfi (file-info (string-append D "/ln") #f)))
  (test-equal (string-length (string-append D "/a.txt")) (file-info:size lfi))
  (test-equal #t (< 0 (file-info:mtime lfi) 4102444800))) ; before year 2100

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
(test-equal #t (list? (user-supplementary-gids)))

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

;; =====================================================================
;; v2 Phase 2.12 additions.
;;
;; Every group below builds its fixtures under its own fresh directory and
;; removes them again, so nothing here depends on (or survives for) any
;; other group.  `with-scratch` is the only way a new fixture is created.
;; =====================================================================

(define scratch-counter 0)

;; Recursive remove: dotfiles included, symlinks unlinked not followed.
(define (rm-tree p)
  (guard (e (#t #f))
    (let ((ft (guard (e (#t #f)) (file-info-type (file-info p #f)))))
      (cond
        ((not ft) #f)
        ((eq? ft 'directory)
         (for-each (lambda (n) (rm-tree (string-append p "/" n)))
                   (directory-files p #t))
         (delete-directory p))
        (else (delete-file p))))))

;; Run `proc` with a brand-new empty directory; always tear it down.
(define (with-scratch proc)
  (set! scratch-counter (+ scratch-counter 1))
  (let ((dir (string-append (temp-file-prefix) "a212-"
                            (number->string (pid)) "-"
                            (number->string scratch-counter))))
    (rm-tree dir)
    (create-directory dir)
    (let ((result (guard (e (#t (rm-tree dir) (raise e))) (proc dir))))
      (rm-tree dir)
      result)))

(define (raised? thunk) (guard (e (#t #t)) (begin (thunk) #f)))
(define (file-err? thunk) (guard (e (#t (file-error? e))) (begin (thunk) 'no-raise)))
(define (msg-of thunk) (guard (e (#t (error-object-message e))) (begin (thunk) 'no-raise)))
(define (write-file p s) (call-with-output-file p (lambda (o) (display s o))))
(define NUL (string (integer->char 0)))

;;; =====================================================================
;;; A. Specs never exercised before this pass
;;;    file-info:device / :inode / :rdev / :blksize / :blocks / :gid,
;;;    file-info-socket?, file-info-device?, set-current-directory!,
;;;    user-info:full-name.
;;; =====================================================================

(with-scratch
 (lambda (dir)
   (write-file (string-append dir "/a") "abcd")
   (let ((fi (file-info (string-append dir "/a") #t)))
     ;; every numeric accessor yields an exact integer
     (test-equal #t (and (exact-integer? (file-info:device fi))
                         (exact-integer? (file-info:inode fi))
                         (exact-integer? (file-info:rdev fi))
                         (exact-integer? (file-info:blksize fi))
                         (exact-integer? (file-info:blocks fi))
                         (exact-integer? (file-info:gid fi))))
     ;; a regular file on a real filesystem: inode nonzero, rdev zero
     (test-equal #t (> (file-info:inode fi) 0))
     (test-equal 0 (file-info:rdev fi))
     (test-equal #t (> (file-info:blksize fi) 0))
     (test-equal #t (>= (file-info:blocks fi) 0))
     ;; a new file takes its group either from the creating process (System V)
     ;; or from the containing directory (BSD, incl. macOS) — both are POSIX
     (test-equal #t (or (= (file-info:gid fi) (user-gid))
                        (= (file-info:gid fi) (file-info:gid (file-info dir #t)))))
     ;; a regular file is neither socket nor device
     (test-equal #f (file-info-socket? fi))
     (test-equal #f (file-info-device? fi))
     ;; two different paths on the same filesystem share st_dev
     (write-file (string-append dir "/b") "z")
     (test-equal (file-info:device fi)
                 (file-info:device (file-info (string-append dir "/b") #t)))
     ;; ...and have distinct inodes
     (test-equal #f (= (file-info:inode fi)
                       (file-info:inode (file-info (string-append dir "/b") #t)))))
   ;; a hard link shares the inode; a copy does not
   (create-hard-link (string-append dir "/a") (string-append dir "/a-hard"))
   (test-equal (file-info:inode (file-info (string-append dir "/a") #t))
               (file-info:inode (file-info (string-append dir "/a-hard") #t)))
   ;; set-current-directory! round trip
   (let ((home (current-directory)))
     (set-current-directory! dir)
     (test-equal #t (string=? (real-path (current-directory)) (real-path dir)))
     ;; relative paths resolve against the new cwd
     (test-equal 'regular (file-info-type (file-info "a" #t)))
     (test-equal #t (string=? (real-path "a") (real-path (string-append dir "/a"))))
     (test-equal #t (string=? (real-path ".") (real-path dir)))
     (set-current-directory! home)
     (test-equal #t (string=? (real-path (current-directory)) (real-path home))))
   ;; user-info:full-name is a string (may legitimately be "")
   (test-equal #t (string? (user-info:full-name (user-info (user-uid)))))))

;;; =====================================================================
;;; B. Syscall error-path matrix.
;;;    For each failure mode: does the primitive raise a *catchable* error?
;;; =====================================================================

;;; B1. Nonexistent path — 12 procedures
(with-scratch
 (lambda (dir)
   (let ((nx (string-append dir "/does-not-exist")))
     (test-equal #t (raised? (lambda () (file-info nx #t))))
     (test-equal #t (raised? (lambda () (file-info nx #f))))
     (test-equal #t (raised? (lambda () (directory-files nx))))
     (test-equal #t (raised? (lambda () (open-directory nx))))
     (test-equal #t (raised? (lambda () (real-path nx))))
     (test-equal #t (raised? (lambda () (read-symlink nx))))
     (test-equal #t (raised? (lambda () (set-file-mode nx #o600))))
     (test-equal #t (raised? (lambda () (truncate-file nx 0))))
     (test-equal #t (raised? (lambda () (set-file-owner nx -1 -1))))
     (test-equal #t (raised? (lambda () (set-file-times nx))))
     (test-equal #t (raised? (lambda () (rename-file nx (string-append dir "/z")))))
     (test-equal #t (raised? (lambda () (create-hard-link nx (string-append dir "/z")))))
     (test-equal #t (raised? (lambda () (set-current-directory! nx))))
     (test-equal #t (raised? (lambda () (delete-directory nx))))
     ;; a missing *parent* directory, not a missing leaf
     (test-equal #t (raised? (lambda () (create-directory (string-append nx "/child")))))
     (test-equal #t (raised? (lambda () (create-fifo (string-append nx "/f")))))
     (test-equal #t (raised? (lambda () (create-temp-file (string-append nx "/pfx-"))))))))

;;; B2. Wrong kind of object — directory where a file is wanted and vice versa
(with-scratch
 (lambda (dir)
   (write-file (string-append dir "/f") "x")
   (create-directory (string-append dir "/d"))
   (let ((f (string-append dir "/f")) (d (string-append dir "/d")))
     ;; file supplied where a directory is required
     (test-equal #t (raised? (lambda () (directory-files f))))
     (test-equal #t (raised? (lambda () (open-directory f))))
     (test-equal #t (raised? (lambda () (delete-directory f))))
     (test-equal #t (raised? (lambda () (set-current-directory! f))))
     ;; a path with a non-directory component in the middle
     (test-equal #t (raised? (lambda () (file-info (string-append f "/inner") #t))))
     (test-equal #t (raised? (lambda () (file-info (string-append f "/") #t))))
     ;; directory supplied where a file is required
     (test-equal #t (raised? (lambda () (delete-file d))))
     (test-equal #t (raised? (lambda () (truncate-file d 0))))
     (test-equal #t (raised? (lambda () (create-hard-link d (string-append dir "/dl")))))
     ;; not a symlink
     (test-equal #t (raised? (lambda () (read-symlink f))))
     (test-equal #t (raised? (lambda () (read-symlink d))))
     ;; rename cannot cross the file/directory kind boundary
     (test-equal #t (raised? (lambda () (rename-file f d))))
     (test-equal #t (raised? (lambda () (rename-file d f))))
     ;; ...but a directory over an *empty* directory is allowed
     (create-directory (string-append dir "/d2"))
     (test-equal #t (begin (rename-file (string-append dir "/d2") d) #t))
     (test-equal 'directory (file-info-type (file-info d #t)))
     ;; a directory that is not empty cannot be removed
     (write-file (string-append d "/inner") "x")
     (test-equal #t (raised? (lambda () (delete-directory d)))))))

;;; B3. Permission denied
(with-scratch
 (lambda (dir)
   (create-directory (string-append dir "/noread") #o000)
   (let ((nr (string-append dir "/noread")))
     ;; running as root defeats every mode bit, so only assert when it bites
     (when (> (user-effective-uid) 0)
       (test-equal #t (raised? (lambda () (directory-files nr))))
       (test-equal #t (raised? (lambda () (open-directory nr))))
       (test-equal #t (raised? (lambda () (file-info (string-append nr "/x") #t))))
       (test-equal #t (raised? (lambda () (create-directory (string-append nr "/x")))))
       (test-equal #t (raised? (lambda () (create-temp-file (string-append nr "/p-"))))))
     ;; the directory itself is still stat-able — permission is on traversal
     (test-equal 'directory (file-info-type (file-info nr #t)))
     (set-file-mode nr #o700))))

;;; B4. Broken symlink — follow? selects between ENOENT and success
(with-scratch
 (lambda (dir)
   (let ((target (string-append dir "/missing")) (link (string-append dir "/broken")))
     (create-symlink target link)
     ;; lstat sees the link; stat does not see the target
     (test-equal 'symlink (file-info-type (file-info link #f)))
     (test-equal #t (file-info-symlink? (file-info link #f)))
     (test-equal #t (raised? (lambda () (file-info link #t))))
     ;; follow? defaults to #t, so the 1-argument form must fail too
     (test-equal #t (raised? (lambda () (file-info link))))
     ;; the link's own recorded size is strlen(target) — POSIX guarantee
     (test-equal (string-length target) (file-info:size (file-info link #f)))
     ;; the target text is readable even though the target is not
     (test-equal target (read-symlink link))
     ;; real-path resolves the whole chain, so it fails
     (test-equal #t (raised? (lambda () (real-path link))))
     ;; a broken link is still visible in its directory
     (test-equal '("broken") (directory-files dir))
     ;; and can be removed without touching the (absent) target
     (test-equal #t (begin (delete-file link) #t))
     (test-equal '() (directory-files dir)))))

;;; B5. Symlink loop (ELOOP)
(with-scratch
 (lambda (dir)
   (let ((a (string-append dir "/loopA")) (b (string-append dir "/loopB")))
     (create-symlink b a)
     (create-symlink a b)
     ;; lstat terminates; stat must report the loop rather than hang
     (test-equal 'symlink (file-info-type (file-info a #f)))
     (test-equal #t (raised? (lambda () (file-info a #t))))
     (test-equal #t (raised? (lambda () (real-path a))))
     (test-equal #t (raised? (lambda () (directory-files a))))
     (test-equal #t (raised? (lambda () (open-directory a))))
     ;; read-symlink reads one hop and stops
     (test-equal b (read-symlink a))
     (test-equal a (read-symlink b))
     ;; a self-loop is the degenerate case
     (let ((s (string-append dir "/self")))
       (create-symlink s s)
       (test-equal s (read-symlink s))
       (test-equal #t (raised? (lambda () (file-info s #t))))
       (test-equal 'symlink (file-info-type (file-info s #f)))))))

;;; B6. Path too long (ENAMETOOLONG)
(with-scratch
 (lambda (dir)
   (let ((long (string-append dir "/" (make-string 5000 #\z))))
     (test-equal #t (raised? (lambda () (file-info long #t))))
     (test-equal #t (raised? (lambda () (file-info long #f))))
     (test-equal #t (raised? (lambda () (directory-files long))))
     (test-equal #t (raised? (lambda () (open-directory long))))
     (test-equal #t (raised? (lambda () (create-directory long))))
     (test-equal #t (raised? (lambda () (delete-directory long))))
     (test-equal #t (raised? (lambda () (real-path long))))
     (test-equal #t (raised? (lambda () (read-symlink long))))
     (test-equal #t (raised? (lambda () (create-symlink long (string-append dir "/l")))))
     (test-equal #t (raised? (lambda () (set-file-mode long #o600))))
     (test-equal #t (raised? (lambda () (truncate-file long 0))))
     (test-equal #t (raised? (lambda () (create-fifo long))))
     (test-equal #t (raised? (lambda () (set-current-directory! long))))
     ;; create-temp-file catches an over-long prefix in its own buffer check
     (test-equal #t (raised? (lambda () (create-temp-file long)))))))

;;; B7. Empty path — must be a clean error, never a silent success
(with-scratch
 (lambda (dir)
   (test-equal #t (raised? (lambda () (file-info "" #t))))
   (test-equal #t (raised? (lambda () (directory-files ""))))
   (test-equal #t (raised? (lambda () (open-directory ""))))
   (test-equal #t (raised? (lambda () (create-directory ""))))
   (test-equal #t (raised? (lambda () (delete-directory ""))))
   (test-equal #t (raised? (lambda () (real-path ""))))
   (test-equal #t (raised? (lambda () (read-symlink ""))))
   (test-equal #t (raised? (lambda () (set-file-mode "" #o600))))
   (test-equal #t (raised? (lambda () (truncate-file "" 0))))
   (test-equal #t (raised? (lambda () (create-fifo ""))))
   (test-equal #t (raised? (lambda () (set-current-directory! ""))))
   (test-equal #t (raised? (lambda () (rename-file "" (string-append dir "/z")))))
   (test-equal #t (raised? (lambda () (rename-file (string-append dir "/z") ""))))
   (test-equal #t (raised? (lambda () (create-hard-link "" (string-append dir "/z")))))
   (test-equal #t (raised? (lambda () (create-hard-link (string-append dir "/z") ""))))
   ;; the *link path* must be non-empty; whether an empty symlink *target* is
   ;; accepted is a documented kernel divergence (BSD/macOS allow it, Linux
   ;; returns ENOENT), so only the link path is asserted here
   (test-equal #t (raised? (lambda () (create-symlink (string-append dir "/z") ""))))))

;;; B8. Embedded NUL — the guard must be uniform across every path argument.
;;;     `validatePathNoNul` is one helper; this pins that no call site skips it.
(with-scratch
 (lambda (dir)
   (write-file (string-append dir "/a") "x")
   (let* ((a (string-append dir "/a"))
          (bad (string-append a NUL "junk"))
          (baddir (string-append dir NUL "junk"))
          (nul-msg "path contains embedded NUL byte"))
     (test-equal nul-msg (msg-of (lambda () (file-info bad #t))))
     (test-equal nul-msg (msg-of (lambda () (directory-files baddir))))
     (test-equal nul-msg (msg-of (lambda () (open-directory baddir))))
     (test-equal nul-msg (msg-of (lambda () (create-directory baddir))))
     (test-equal nul-msg (msg-of (lambda () (delete-directory baddir))))
     (test-equal nul-msg (msg-of (lambda () (real-path baddir))))
     (test-equal nul-msg (msg-of (lambda () (read-symlink bad))))
     (test-equal nul-msg (msg-of (lambda () (set-file-mode bad #o600))))
     (test-equal nul-msg (msg-of (lambda () (truncate-file bad 1))))
     (test-equal nul-msg (msg-of (lambda () (create-fifo bad))))
     (test-equal nul-msg (msg-of (lambda () (set-file-owner bad -1 -1))))
     (test-equal nul-msg (msg-of (lambda () (set-file-times bad))))
     (test-equal nul-msg (msg-of (lambda () (set-current-directory! baddir))))
     ;; both arguments of every two-path procedure are checked
     (test-equal nul-msg (msg-of (lambda () (rename-file bad a))))
     (test-equal nul-msg (msg-of (lambda () (rename-file a bad))))
     (test-equal nul-msg (msg-of (lambda () (create-symlink bad a))))
     (test-equal nul-msg (msg-of (lambda () (create-symlink a bad))))
     (test-equal nul-msg (msg-of (lambda () (create-hard-link bad a))))
     (test-equal nul-msg (msg-of (lambda () (create-hard-link a bad))))
     ;; non-path string arguments go through the same guard
     (test-equal nul-msg (msg-of (lambda () (set-environment-variable! (string-append "KA" NUL "B") "v"))))
     (test-equal nul-msg (msg-of (lambda () (set-environment-variable! "KAAPPI_A212" (string-append "v" NUL "w")))))
     (test-equal nul-msg (msg-of (lambda () (delete-environment-variable! (string-append "KA" NUL "B")))))
     (test-equal nul-msg (msg-of (lambda () (user-info (string-append "root" NUL "x")))))
     (test-equal nul-msg (msg-of (lambda () (group-info (string-append "wheel" NUL "x")))))
     (test-equal nul-msg (msg-of (lambda () (create-temp-file (string-append dir "/p" NUL)))))
     ;; a NUL is rejected *before* the syscall — nothing is created
     (test-equal '("a") (directory-files dir)))))

;;; B9. A path that vanishes between one call and the next
(with-scratch
 (lambda (dir)
   (write-file (string-append dir "/t") "z")
   (let ((fi (file-info (string-append dir "/t") #t)))
     (delete-file (string-append dir "/t"))
     ;; a file-info is a snapshot: it stays readable after the file is gone
     (test-equal 1 (file-info:size fi))
     (test-equal 'regular (file-info-type fi))
     (test-equal #t (exact-integer? (file-info:inode fi)))
     ;; a fresh stat of the same path now fails
     (test-equal #t (raised? (lambda () (file-info (string-append dir "/t") #t)))))
   ;; a directory removed while a stream over it is open
   (create-directory (string-append dir "/vanish"))
   (write-file (string-append dir "/vanish/x") "1")
   (let ((ds (open-directory (string-append dir "/vanish"))))
     (delete-file (string-append dir "/vanish/x"))
     (delete-directory (string-append dir "/vanish"))
     ;; must terminate with EOF rather than crash or loop
     (test-equal #t (let loop ((n 0))
                      (let ((e (read-directory ds)))
                        (if (eof-object? e) (>= n 0) (loop (+ n 1))))))
     (test-equal #t (begin (close-directory ds) #t)))))

;;; B10. Relative vs absolute paths agree
(with-scratch
 (lambda (dir)
   (write-file (string-append dir "/r") "xy")
   (create-directory (string-append dir "/sub"))
   (let ((home (current-directory)))
     (set-current-directory! dir)
     (test-equal 2 (file-info:size (file-info "r" #t)))
     (test-equal 2 (file-info:size (file-info (string-append dir "/r") #t)))
     (test-equal (file-info:inode (file-info "r" #t))
                 (file-info:inode (file-info (string-append dir "/r") #t)))
     (test-equal 'directory (file-info-type (file-info "sub" #t)))
     (test-equal 'directory (file-info-type (file-info "." #t)))
     (test-equal 'directory (file-info-type (file-info ".." #t)))
     (test-equal #t (string=? (real-path "sub/..") (real-path ".")))
     (test-equal #t (> (length (directory-files ".")) 0))
     (set-current-directory! home))))

;;; =====================================================================
;;; C. file-info across every reachable file type.
;;;    (A socket needs a bind(2) this build cannot reach from Scheme; the
;;;    socket branch is exercised only through the negative predicate.)
;;; =====================================================================

(with-scratch
 (lambda (dir)
   (write-file (string-append dir "/reg") "abcd")
   (create-directory (string-append dir "/dir"))
   (create-fifo (string-append dir "/fifo"))
   (create-symlink (string-append dir "/reg") (string-append dir "/link"))
   (let ((reg (file-info (string-append dir "/reg") #t))
         (d (file-info (string-append dir "/dir") #t))
         (fifo (file-info (string-append dir "/fifo") #f))
         (lnk (file-info (string-append dir "/link") #f))
         (lnk-f (file-info (string-append dir "/link") #t)))
     ;; file-info-type agrees with the five predicates, exhaustively
     (test-equal 'regular (file-info-type reg))
     (test-equal 'directory (file-info-type d))
     (test-equal 'fifo (file-info-type fifo))
     (test-equal 'symlink (file-info-type lnk))
     (test-equal 'regular (file-info-type lnk-f))
     ;; exactly one predicate answers #t per object
     (test-equal '(#t #f #f #f #f)
                 (list (file-info-regular? reg) (file-info-directory? reg)
                       (file-info-symlink? reg) (file-info-fifo? reg)
                       (file-info-socket? reg)))
     (test-equal '(#f #t #f #f #f)
                 (list (file-info-regular? d) (file-info-directory? d)
                       (file-info-symlink? d) (file-info-fifo? d)
                       (file-info-socket? d)))
     (test-equal '(#f #f #f #t #f)
                 (list (file-info-regular? fifo) (file-info-directory? fifo)
                       (file-info-symlink? fifo) (file-info-fifo? fifo)
                       (file-info-socket? fifo)))
     (test-equal '(#f #f #t #f #f)
                 (list (file-info-regular? lnk) (file-info-directory? lnk)
                       (file-info-symlink? lnk) (file-info-fifo? lnk)
                       (file-info-socket? lnk)))
     ;; none of the four is a device
     (test-equal '(#f #f #f #f)
                 (list (file-info-device? reg) (file-info-device? d)
                       (file-info-device? fifo) (file-info-device? lnk)))
     ;; a symlink followed and not followed differ in identity, not just type
     (test-equal #f (= (file-info:inode lnk) (file-info:inode lnk-f)))
     (test-equal (file-info:inode reg) (file-info:inode lnk-f))
     ;; timestamps are seconds since the epoch, this century
     (for-each (lambda (fi)
                 (test-equal #t (and (< 946684800 (file-info:mtime fi) 4102444800)
                                     (< 946684800 (file-info:ctime fi) 4102444800))))
               (list reg d fifo lnk))
     ;; mode carries the type bits as well as the permission bits
     (test-equal #o100 (logand (arithmetic-shift (file-info:mode reg) -9) #o170))
     (test-equal #o040 (logand (arithmetic-shift (file-info:mode d) -9) #o170))
     ;; a directory has at least 2 links (itself and ".")
     (test-equal #t (>= (file-info:nlinks d) 2))
     (test-equal 1 (file-info:nlinks reg)))
   ;; nonzero rdev is what distinguishes a device node; no plain file has one
   (test-equal 0 (file-info:rdev (file-info (string-append dir "/reg") #t)))
   (test-equal 0 (file-info:rdev (file-info (string-append dir "/fifo") #f)))))

;; FAIL: TBD (file-info panics — SIGABRT, not catchable — on any path whose
;; st_dev is negative when read as i32; on macOS that is every entry under
;; /dev, whose devfs st_dev is 2998493978 = -1296473318 as i32.  The cast is
;; `.dev = @intCast(stat_buf.dev)` at src/primitives_filesystem.zig:134.
;; /dev/fd has st_rdev = 0 and still aborts, which discriminates dev from
;; rdev.  Enabling either line below aborts the whole suite.)
;; (test-equal 'char-special (file-info-type (file-info "/dev/null" #t)))
;; (test-equal #t (file-info-device? (file-info "/dev/null" #t)))
;; (test-equal 'directory (file-info-type (file-info "/dev/fd" #t)))
;;
;; Enabled control: an ordinary path on a filesystem whose st_dev is
;; positive stats without incident, so the failure is the device number and
;; not the char-device type or the /dev path text.
(test-equal 'directory (file-info-type (file-info "/tmp" #t)))
(test-equal #t (> (file-info:device (file-info "/tmp" #t)) 0))

;;; =====================================================================
;;; D. Directory-object lifecycle.
;;; =====================================================================

(with-scratch
 (lambda (dir)
   (for-each (lambda (n) (write-file (string-append dir "/" n) "x"))
             '("f1" "f2" "f3" ".dot1" ".dot2"))
   (define (drain ds) (let loop ((n 0))
                        (let ((e (read-directory ds)))
                          (if (eof-object? e) n (loop (+ n 1))))))
   ;; dotfiles: opt-in, and the flag is truthiness not eq-#t
   (let ((ds (open-directory dir)))     (test-equal 3 (drain ds)) (close-directory ds))
   (let ((ds (open-directory dir #f)))  (test-equal 3 (drain ds)) (close-directory ds))
   (let ((ds (open-directory dir #t)))  (test-equal 5 (drain ds)) (close-directory ds))
   (let ((ds (open-directory dir 0)))   (test-equal 5 (drain ds)) (close-directory ds))
   (let ((ds (open-directory dir '()))) (test-equal 5 (drain ds)) (close-directory ds))
   ;; directory-files must agree with the stream, and never yield "." or ".."
   (test-equal 3 (length (directory-files dir)))
   (test-equal 5 (length (directory-files dir #t)))
   (test-equal #f (member "." (directory-files dir #t)))
   (test-equal #f (member ".." (directory-files dir #t)))
   ;; reading past the end is idempotent EOF, not an error
   (let ((ds (open-directory dir)))
     (drain ds)
     (test-equal #t (eof-object? (read-directory ds)))
     (test-equal #t (eof-object? (read-directory ds)))
     (test-equal #t (eof-object? (read-directory ds)))
     ;; closing an already-exhausted stream is a no-op, and repeatable
     (test-equal #t (begin (close-directory ds) #t))
     (test-equal #t (begin (close-directory ds) #t))
     (test-equal #t (begin (close-directory ds) #t))
     ;; reading a closed stream yields EOF rather than crashing
     (test-equal #t (eof-object? (read-directory ds))))
   ;; closing early, mid-stream, is also safe
   (let ((ds (open-directory dir)))
     (test-equal #t (string? (read-directory ds)))
     (test-equal #t (begin (close-directory ds) #t))
     (test-equal #t (eof-object? (read-directory ds)))
     (test-equal #t (begin (close-directory ds) #t)))
   ;; type errors name the right argument type
   (test-equal #t (raised? (lambda () (read-directory 42))))
   (test-equal #t (raised? (lambda () (read-directory "not-a-stream"))))
   (test-equal #t (raised? (lambda () (read-directory (open-input-string "x")))))
   (test-equal #t (raised? (lambda () (close-directory 42))))
   (test-equal #t (raised? (lambda () (close-directory (open-input-string "x")))))
   ;; mutating the directory mid-traversal must terminate and yield strings
   (let ((ds (open-directory dir)))
     (test-equal #t (string? (read-directory ds)))
     (write-file (string-append dir "/f4") "x")
     (delete-file (string-append dir "/f1"))
     (test-equal #t (let loop ((n 0))
                      (let ((e (read-directory ds)))
                        (cond ((eof-object? e) (and (>= n 0) (<= n 5)))
                              ((string? e) (loop (+ n 1)))
                              (else #f)))))
     (close-directory ds))
   ;; a stream that is never closed is finalised by the GC, not leaked:
   ;; 3000 opens would exhaust the fd table if the DIR* were held
   (test-equal #t (let loop ((i 0))
                    (if (= i 3000) #t
                        (let ((ds (open-directory dir)))
                          (read-directory ds)
                          (loop (+ i 1))))))))

;;; A directory with more entries than one getdents buffer
(with-scratch
 (lambda (dir)
   (let loop ((i 0))
     (when (< i 2000)
       (write-file (string-append dir "/f" (number->string i)) "")
       (loop (+ i 1))))
   (test-equal 2000 (length (directory-files dir)))
   (let ((ds (open-directory dir)))
     (test-equal 2000 (let loop ((n 0))
                        (let ((e (read-directory ds)))
                          (if (eof-object? e) n (loop (+ n 1))))))
     (close-directory ds))
   ;; no duplicates and no omissions across the getdents buffer refills:
   ;; every expected name appears exactly once (marked into a bit vector, so
   ;; this stays linear rather than quadratic in the entry count)
   (test-equal #t
     (let ((seen (make-vector 2000 0)))
       (for-each (lambda (n)
                   (let ((i (string->number (substring n 1 (string-length n)))))
                     (when (and i (< -1 i 2000))
                       (vector-set! seen i (+ 1 (vector-ref seen i))))))
                 (directory-files dir))
       (let loop ((i 0))
         (cond ((= i 2000) #t)
               ((= 1 (vector-ref seen i)) (loop (+ i 1)))
               (else (list 'bad-count i (vector-ref seen i)))))))))

;;; =====================================================================
;;; E. Optional arguments that are silently discarded when mistyped.
;;;    Every disabled line below has an enabled control directly under it
;;;    proving the *same* validation fires for an in-band-but-invalid value,
;;;    so the gap is the type test, not a missing check.
;;; =====================================================================

(with-scratch
 (lambda (dir)
   ;; -- create-directory mode --
   ;; FAIL: TBD (a non-fixnum mode is silently discarded and 0o755 used:
   ;; `if (args.len > 1 and types.isFixnum(args[1]))` in createDirectoryFn)
   ;; (test-equal #t (raised? (lambda () (create-directory (string-append dir "/m1") "notanum"))))
   (test-equal #t (raised? (lambda () (create-directory (string-append dir "/m2") #o10000))))
   (test-equal #t (raised? (lambda () (create-directory (string-append dir "/m3") -1))))
   ;; the discarded-mode call succeeds outright, with the default mode
   (create-directory (string-append dir "/m4") "notanum")
   (test-equal 'directory (file-info-type (file-info (string-append dir "/m4") #t)))

   ;; -- create-fifo mode --
   ;; FAIL: TBD (same shape in createFifoFn — non-fixnum mode ignored, 0o664 used)
   ;; (test-equal #t (raised? (lambda () (create-fifo (string-append dir "/ff1") "notanum"))))
   (test-equal #t (raised? (lambda () (create-fifo (string-append dir "/ff2") #o10000))))
   (test-equal #t (raised? (lambda () (create-fifo (string-append dir "/ff3") -1))))

   ;; -- create-temp-file prefix --
   ;; FAIL: TBD (a non-string prefix is silently discarded and the default
   ;; temp-file-prefix used: `if (args.len > 0 and types.isString(args[0]))`)
   ;; (test-equal #t (raised? (lambda () (create-temp-file 42))))
   (test-equal #t (raised? (lambda () (create-temp-file (make-string 400 #\z)))))
   (let ((t (create-temp-file 42)))
     ;; it really did create a file — under the default prefix, not "42"
     (test-equal #t (file-exists? t))
     (delete-file t))

   ;; -- set-file-times --
   (write-file (string-append dir "/t") "x")
   (let ((p (string-append dir "/t")))
     (set-file-times p 1000000 2000000)
     (test-equal '(1000000 2000000)
                 (list (file-info:atime (file-info p #t)) (file-info:mtime (file-info p #t))))
     ;; the two sentinels work: -2 = leave alone, -1 = now
     (set-file-times p -2 -2)
     (test-equal '(1000000 2000000)
                 (list (file-info:atime (file-info p #t)) (file-info:mtime (file-info p #t))))
     (set-file-times p -2 3000000)
     (test-equal '(1000000 3000000)
                 (list (file-info:atime (file-info p #t)) (file-info:mtime (file-info p #t))))
     ;; FAIL: TBD (a non-fixnum, non-time argument falls through to UTIME_NOW
     ;; in timeArgToTimespec, so a mistyped time silently stamps the file with
     ;; the current clock instead of raising)
     ;; (test-equal #t (raised? (lambda () (set-file-times p "garbage" "garbage"))))
     ;; (test-equal #t (raised? (lambda () (set-file-times p 5.0 5.0))))
     ;; Enabled control: the *path* argument of the same call is type-checked
     (test-equal #t (raised? (lambda () (set-file-times 42))))
     ;; and the discarded-time call does mutate the file, to "now"
     (set-file-times p "garbage" "garbage")
     (test-equal #t (> (file-info:mtime (file-info p #t)) 1700000000)))

   ;; -- nice --
   ;; FAIL: TBD (a non-fixnum increment is silently discarded and the default
   ;; +1 applied, so `(nice "x")` really does renice the process:
   ;; `if (args.len > 0 and types.isFixnum(args[0]))` in niceFn)
   ;; (test-equal #t (raised? (lambda () (nice "x"))))
   ;; (test-equal #t (raised? (lambda () (nice (expt 2 100)))))
   ;; Enabled control: a fixnum outside c_int *is* rejected, so the range
   ;; check exists and only the type test is missing.
   (test-equal #t (raised? (lambda () (nice 999999999999))))
   (test-equal #t (exact-integer? (nice 0)))

   ;; -- directory-files / file-info extra arguments --
   ;; FAIL: TBD (SRFI 170 caps these at 2 and 1 arguments respectively; the
   ;; specs declare `.variadic` which has no upper bound, so surplus
   ;; arguments are accepted and ignored rather than reported)
   ;; (test-equal #t (raised? (lambda () (file-info (string-append dir "/t") #t 'extra))))
   ;; (test-equal #t (raised? (lambda () (create-temp-file "/tmp/x" "y"))))
   ;; Enabled control: too *few* arguments is reported correctly
   (test-equal #t (raised? (lambda () (file-info))))
   (test-equal #t (raised? (lambda () (rename-file (string-append dir "/t")))))
   (test-equal #t (raised? (lambda () (pid 1))))
   (test-equal #t (raised? (lambda () (umask 1))))
   (test-equal #t (raised? (lambda () (temp-file-prefix 1))))))

;;; =====================================================================
;;; F. Environment variables — the write side.
;;; =====================================================================

(test-equal #t (begin (set-environment-variable! "KAAPPI_A212_OK" "v1") #t))
(test-equal "v1" (get-environment-variable "KAAPPI_A212_OK"))
(test-equal #t (begin (set-environment-variable! "KAAPPI_A212_OK" "v2") #t))
(test-equal "v2" (get-environment-variable "KAAPPI_A212_OK"))
(test-equal "" (begin (set-environment-variable! "KAAPPI_A212_OK" "") (get-environment-variable "KAAPPI_A212_OK")))
(test-equal #t (begin (delete-environment-variable! "KAAPPI_A212_OK") #t))
(test-equal #f (get-environment-variable "KAAPPI_A212_OK"))
;; deleting a variable that was never set is not an error
(test-equal #t (begin (delete-environment-variable! "KAAPPI_A212_NEVER") #t))
;; the change is visible through get-environment-variables too
(set-environment-variable! "KAAPPI_A212_LIST" "here")
(test-equal '("KAAPPI_A212_LIST" . "here") (assoc "KAAPPI_A212_LIST" (get-environment-variables)))
(delete-environment-variable! "KAAPPI_A212_LIST")
(test-equal #f (assoc "KAAPPI_A212_LIST" (get-environment-variables)))
;; FAIL: TBD (setenv(3)'s return value is discarded — `_ = setenv(...)` in
;; platform.setEnv — so setEnvVarFn's raiseFileError branch is unreachable and
;; an EINVAL name silently does nothing.  A name containing "=" and an empty
;; name are both rejected by POSIX; both return normally here and set nothing.)
;; (test-equal #t (raised? (lambda () (set-environment-variable! "KAAPPI=A212" "v"))))
;; (test-equal #t (raised? (lambda () (set-environment-variable! "" "v"))))
;; Enabled control: the call really does nothing at all, under either spelling
(set-environment-variable! "KAAPPI=A212" "v")
(test-equal #f (get-environment-variable "KAAPPI"))
(test-equal #f (get-environment-variable "KAAPPI=A212"))
(test-equal #f (assoc "KAAPPI" (get-environment-variables)))

;;; =====================================================================
;;; G. Error taxonomy — which failures are file errors?
;;; =====================================================================

(with-scratch
 (lambda (dir)
   (write-file (string-append dir "/a") "x")
   (let ((a (string-append dir "/a")))
     ;; genuine filesystem failures are file errors and carry the path
     (test-equal #t (file-err? (lambda () (file-info (string-append dir "/nx") #t))))
     (test-equal #t (file-err? (lambda () (create-directory dir))))
     (test-equal #t (file-err? (lambda () (read-symlink a))))
     (test-equal #t (file-err? (lambda () (delete-directory (string-append dir "/nx")))))
     (test-equal #t (file-err? (lambda () (directory-files a))))
     (test-equal (list dir)
                 (guard (e (#t (error-object-irritants e))) (create-directory dir)))
     (test-equal (list a)
                 (guard (e (#t (error-object-irritants e))) (read-symlink a)))
     ;; wrong-type arguments are *not* file errors
     (test-equal #f (file-err? (lambda () (file-info 42 #t))))
     (test-equal #f (file-err? (lambda () (file-info:size 42))))
     (test-equal #f (file-err? (lambda () (directory-files 'sym))))
     (test-equal #f (file-err? (lambda () (read-directory 42))))
     (test-equal #f (file-err? (lambda () (user-info 1.0))))
     (test-equal #f (file-err? (lambda () (group-info (expt 2 100)))))
     ;; ...and they name the procedure and the expected type
     (test-equal "type error in 'file-info:size': expected file-info, got 42"
                 (msg-of (lambda () (file-info:size 42))))
     ;; FAIL: TBD (pure argument-range validation is raised through
     ;; raiseFileError, so `file-error?` answers #t for failures that never
     ;; touched the filesystem.  These are argError/KP3007 cases — "a value of
     ;; acceptable type the procedure rejects anyway" — not file errors.)
     ;; (test-equal #f (file-err? (lambda () (set-file-mode a #o10000))))
     ;; (test-equal #f (file-err? (lambda () (set-umask! -1))))
     ;; (test-equal #f (file-err? (lambda () (nice 999999999999))))
     ;; (test-equal #f (file-err? (lambda () (create-temp-file (make-string 400 #\z)))))
     ;; Enabled control: each of those does raise, and with its own message
     (test-equal "mode value out of range" (msg-of (lambda () (set-file-mode a #o10000))))
     (test-equal "mode value out of range" (msg-of (lambda () (set-umask! -1))))
     (test-equal "nice value out of range" (msg-of (lambda () (nice 999999999999))))
     (test-equal "temp file prefix too long"
                 (msg-of (lambda () (create-temp-file (make-string 400 #\z))))))))

;;; =====================================================================
;;; H. Cross-heap deep copy across the SRFI-18 thread boundary (D6).
;;; =====================================================================

;; Srfi18Time round-trips in full — the discriminating control for the four
;; types below, all of which this file also allocates.
(test-equal #t (let ((t (thread-join! (thread-start! (make-thread (lambda () (posix-time)))))))
                 (and (time? t) (> (time->seconds t) 1700000000))))

;; file-info / user-info / group-info / directory-object are listed as
;; UncopyableType in gc_deep_copy.zig, so a value of any of them must at
;; least fail *cleanly* — never corrupt, never crash.  The assertion is
;; written so that a future fix making them copyable keeps it green.
(with-scratch
 (lambda (dir)
   (write-file (string-append dir "/a") "abcd")
   (define (out-of-thread thunk ok?)
     (guard (e (#t (error-object? e)))
       (ok? (thread-join! (thread-start! (make-thread thunk))))))
   (test-equal #t (out-of-thread (lambda () (file-info (string-append dir "/a") #t))
                                 (lambda (v) (and (file-info? v) (= 4 (file-info:size v))))))
   (test-equal #t (out-of-thread (lambda () (user-info (user-uid)))
                                 (lambda (v) (and (user-info? v) (string? (user-info:name v))))))
   (test-equal #t (out-of-thread (lambda () (group-info (user-gid)))
                                 (lambda (v) (and (group-info? v) (string? (group-info:name v))))))
   (test-equal #t (out-of-thread (lambda () (open-directory dir))
                                 (lambda (v) (begin (close-directory v) #t))))
   ;; the same value travelling *into* a child thread
   (let ((fi (file-info (string-append dir "/a") #t)))
     (test-equal #t (guard (e (#t (error-object? e)))
                      (thread-join! (thread-start! (make-thread (lambda () (= 4 (file-info:size fi)))))))))))

;;; =====================================================================
;;; I. Behaviours confirmed correct — pinned so a refactor cannot lose them.
;;; =====================================================================

;;; I1. mode-bit range validation is shared and coherent across all 4 users
(with-scratch
 (lambda (dir)
   (write-file (string-append dir "/a") "x")
   (let ((a (string-append dir "/a")))
     ;; the full 12-bit mode is accepted; the kernel may still refuse to set
     ;; setgid when the caller is not in the file's group (POSIX permits that
     ;; silent clear), so only the 9 permission bits are asserted round-trip
     (set-file-mode a #o7777)
     (test-equal #o777 (logand (file-info:mode (file-info a #t)) #o777))
     (test-equal #o4000 (logand (file-info:mode (file-info a #t)) #o4000))
     (set-file-mode a #o000)
     (test-equal #o000 (logand (file-info:mode (file-info a #t)) #o777))
     (set-file-mode a #o644)
     (test-equal #o644 (logand (file-info:mode (file-info a #t)) #o777))
     ;; one boundary above and below the legal range, at all four call sites
     (for-each (lambda (bad)
                 (test-equal #t (raised? (lambda () (set-file-mode a bad))))
                 (test-equal #t (raised? (lambda () (set-umask! bad))))
                 (test-equal #t (raised? (lambda () (create-directory (string-append dir "/x") bad))))
                 (test-equal #t (raised? (lambda () (create-fifo (string-append dir "/y") bad)))))
               (list -1 #o10000 (- (expt 2 47) 1))))))

;;; I2. umask governs the default create mode, and an explicit mode wins
(with-scratch
 (lambda (dir)
   (let ((old (umask)))
     (set-umask! #o077)
     (create-directory (string-append dir "/u1"))
     (test-equal #o700 (logand (file-info:mode (file-info (string-append dir "/u1") #t)) #o777))
     (set-umask! #o000)
     (create-directory (string-append dir "/u2"))
     (test-equal #o755 (logand (file-info:mode (file-info (string-append dir "/u2") #t)) #o777))
     (create-directory (string-append dir "/u3") #o777)
     (test-equal #o777 (logand (file-info:mode (file-info (string-append dir "/u3") #t)) #o777))
     (set-umask! #o022)
     (test-equal #o022 (umask))
     (set-umask! old)
     (test-equal old (umask)))))

;;; I3. create-temp-file: unique, mode #o600 as SRFI 170 requires, and the
;;;     prefix is a literal path prefix (not a directory)
(with-scratch
 (lambda (dir)
   (let ((a (create-temp-file)) (b (create-temp-file)))
     (test-equal #f (string=? a b))
     (test-equal #t (and (file-exists? a) (file-exists? b)))
     (test-equal #o600 (logand (file-info:mode (file-info a #t)) #o777))
     (test-equal 'regular (file-info-type (file-info a #t)))
     (test-equal 0 (file-info:size (file-info a #t)))
     (delete-file a) (delete-file b))
   (let ((t (create-temp-file (string-append dir "/pfx-"))))
     (test-equal #t (file-exists? t))
     (test-equal #t (> (string-length t) (string-length (string-append dir "/pfx-"))))
     (test-equal #o600 (logand (file-info:mode (file-info t #t)) #o777))
     (delete-file t))
   ;; temp-file-prefix is a string and usable as a prefix in its own right
   (test-equal #t (string? (temp-file-prefix)))
   (let ((t (create-temp-file (temp-file-prefix))))
     (test-equal #t (file-exists? t))
     (delete-file t))))

;;; I4. user/group database: #f (not an error) for an unknown identifier —
;;;     SRFI 170: "if the identifier does not identify an existing user or
;;;     group, #f is returned; this does not constitute an error situation".
(test-equal #f (user-info "kaappi-no-such-user-a212"))
(test-equal #f (user-info ""))
(test-equal #f (group-info "kaappi-no-such-group-a212"))
;; an out-of-range id is a type error, a merely-unused one is #f
(test-equal #t (raised? (lambda () (user-info -1))))
(test-equal #t (raised? (lambda () (user-info 4294967296))))
(test-equal #t (raised? (lambda () (group-info -1))))
(test-equal #t (raised? (lambda () (user-info 1.0))))
(test-equal #t (raised? (lambda () (user-info (expt 2 100)))))
(test-equal #t (raised? (lambda () (group-info (expt 2 100)))))
(test-equal #t (raised? (lambda () (user-info #t))))
;; the accessors are type-disjoint: a group-info is not a user-info
(test-equal #t (raised? (lambda () (user-info:name (group-info (user-gid))))))
(test-equal #t (raised? (lambda () (group-info:name (user-info (user-uid))))))
(test-equal #f (user-info? (group-info (user-gid))))
(test-equal #f (group-info? (user-info (user-uid))))
;; uid 0 is root on every POSIX host
(test-equal "root" (user-info:name (user-info 0)))
(test-equal 0 (user-info:uid (user-info 0)))

;;; I5. terminal? follows the fd, and never guesses
(test-equal #f (terminal? (open-input-string "x")))
(test-equal #f (terminal? (open-output-string)))
(test-equal #f (terminal? (open-input-bytevector #u8(1 2 3))))
(with-scratch
 (lambda (dir)
   (write-file (string-append dir "/a") "x")
   (test-equal #f (call-with-input-file (string-append dir "/a") terminal?))
   (let ((i (open-input-file (string-append dir "/a"))))
     (close-port i)
     (test-equal #f (terminal? i)))))
(test-equal #t (raised? (lambda () (terminal? 42))))
(test-equal #t (raised? (lambda () (terminal? "not-a-port"))))

;;; I6. non-ASCII filenames survive the round trip, counted in codepoints
(with-scratch
 (lambda (dir)
   (let ((name "héllo-日本"))
     (write-file (string-append dir "/" name) "x")
     (test-equal (list name) (directory-files dir))
     (test-equal 8 (string-length (car (directory-files dir))))
     (test-equal 'regular (file-info-type (file-info (string-append dir "/" name) #f)))
     (let ((ds (open-directory dir)))
       (test-equal name (read-directory ds))
       (close-directory ds)))))

;;; I7. long symlink targets round-trip up to PATH_MAX-1
(with-scratch
 (lambda (dir)
   (for-each (lambda (n)
               (let ((target (make-string n #\y))
                     (link (string-append dir "/l" (number->string n))))
                 (create-symlink target link)
                 (test-equal n (string-length (read-symlink link)))
                 (test-equal target (read-symlink link))
                 (test-equal n (file-info:size (file-info link #f)))))
             '(1 255 1000 1023))))

;;; I8. GC pressure: many live file-info records stay intact
(with-scratch
 (lambda (dir)
   (write-file (string-append dir "/a") "abcd")
   (test-equal #t
     (let loop ((i 0) (acc '()))
       (if (= i 500)
           (and (= 500 (length acc))
                (let check ((l acc)) (cond ((null? l) #t)
                                           ((= 4 (file-info:size (car l))) (check (cdr l)))
                                           (else #f))))
           (loop (+ i 1) (cons (file-info (string-append dir "/a") #t) acc)))))
   ;; a file-info is a fresh object each time, never interned
   (test-equal #f (eqv? (file-info (string-append dir "/a") #t)
                        (file-info (string-append dir "/a") #t)))))

;;; I9. rename-file semantics
(with-scratch
 (lambda (dir)
   (write-file (string-append dir "/a") "aaaa")
   (write-file (string-append dir "/b") "bb")
   ;; renaming onto itself is a no-op, not a truncation
   (rename-file (string-append dir "/a") (string-append dir "/a"))
   (test-equal 4 (file-info:size (file-info (string-append dir "/a") #t)))
   ;; renaming over an existing file replaces it silently
   (rename-file (string-append dir "/b") (string-append dir "/a"))
   (test-equal 2 (file-info:size (file-info (string-append dir "/a") #t)))
   (test-equal #f (file-exists? (string-append dir "/b")))
   ;; a symlink is renamed as itself, never followed
   (create-symlink (string-append dir "/a") (string-append dir "/l"))
   (rename-file (string-append dir "/l") (string-append dir "/l2"))
   (test-equal 'symlink (file-info-type (file-info (string-append dir "/l2") #f)))
   (test-equal (string-append dir "/a") (read-symlink (string-append dir "/l2")))))

;;; I10. hard links, ownership and truncation
(with-scratch
 (lambda (dir)
   (write-file (string-append dir "/a") "abcdefgh")
   (let ((a (string-append dir "/a")) (h (string-append dir "/h")))
     (create-hard-link a h)
     (test-equal 2 (file-info:nlinks (file-info a #t)))
     (test-equal 2 (file-info:nlinks (file-info h #t)))
     (test-equal (file-info:inode (file-info a #t)) (file-info:inode (file-info h #t)))
     ;; truncation is visible through both names
     (truncate-file a 3)
     (test-equal 3 (file-info:size (file-info h #t)))
     (truncate-file h 0)
     (test-equal 0 (file-info:size (file-info a #t)))
     ;; growing a file with truncate leaves a sparse hole
     (truncate-file a 100000)
     (test-equal 100000 (file-info:size (file-info a #t)))
     (truncate-file a 0)
     ;; a negative length is rejected by the kernel
     (test-equal #t (raised? (lambda () (truncate-file a -1))))
     ;; a bignum length is a type error, not a silent truncation
     (test-equal #t (raised? (lambda () (truncate-file a (expt 2 60)))))
     ;; deleting one name leaves the other
     (delete-file h)
     (test-equal 1 (file-info:nlinks (file-info a #t)))
     ;; chown to the current owner is always permitted; so is "unchanged"
     (test-equal #t (begin (set-file-owner a (user-uid) (user-gid)) #t))
     (test-equal #t (begin (set-file-owner a owner/unchanged group/unchanged) #t))
     (test-equal -1 owner/unchanged)
     (test-equal -1 group/unchanged)
     ;; a non-integer owner is a type error
     (test-equal #t (raised? (lambda () (set-file-owner a "root" (user-gid)))))
     (test-equal #t (raised? (lambda () (set-file-owner a (user-uid) "wheel")))))))

;;; I11. process state
(test-equal #t (= (pid) (pid)))
(test-equal #t (> (pid) 0))
(test-equal #t (exact-integer? (user-effective-uid)))
(test-equal #t (exact-integer? (user-effective-gid)))
(test-equal #t (let loop ((l (user-supplementary-gids)))
                 (cond ((null? l) #t)
                       ((exact-integer? (car l)) (loop (cdr l)))
                       (else #f))))
;; posix-time and monotonic-time are time objects, not raw numbers
(test-equal #t (time? (posix-time)))
(test-equal #t (time? (monotonic-time)))
(test-equal #t (> (time->seconds (posix-time)) 1700000000))
(test-equal #t (>= (time->seconds (monotonic-time)) 0))
(test-equal #t (let ((a (time->seconds (monotonic-time))))
                 (>= (time->seconds (monotonic-time)) a)))

;;; =====================================================================
;;; End of v2 Phase 2.12 additions.
;;; =====================================================================

;;; --- cleanup ---
(for-each (lambda (n) (rm-f (string-append D "/" n)))
          '("a.txt" ".hidden" "ln" "hard" "fifo"))
(rmdir-f (string-append D "/sub"))
(rmdir-f D)
(test-equal #f (file-exists? D))

(let ((runner (test-runner-current)))
  (test-end "primitives_filesystem audit")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
