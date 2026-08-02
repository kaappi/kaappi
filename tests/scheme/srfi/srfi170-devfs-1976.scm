;; Regression test for #1976: file-info on devfs paths aborted the process.
;;
;; dev_t is signed on macOS and OpenBSD (i32), and devfs reports device ids
;; with the sign bit set -- macOS's /dev/null stats as st_dev = -1296473318.
;; doStat's range-checked @intCast into u64 turned that into an uncatchable
;; Zig panic (exit 134), taking down `(file-info "/dev/null" #t)` and even a
;; guard wrapped around it. The fix reinterprets the bits as unsigned before
;; widening (a device id is an opaque identity, not a quantity).

(import (scheme base) (scheme write) (scheme process-context) (srfi 64)
        (srfi 170))

(test-begin "srfi170-devfs-1976")

(cond-expand
  (windows
   ;; No devfs on Windows -- the signed-dev_t branch is exercised on the
   ;; POSIX CI legs. Pin only that a missing /dev path stays catchable.
   (test-assert "file-info on a /dev path succeeds or raises catchably"
                (guard (e (#t #t)) (file-info "/dev/null" #t) #t)))
  (else
   (test-assert "file-info /dev/null returns a file-info (used to abort)"
                (file-info? (file-info "/dev/null" #t)))
   (test-assert "file-info:device on /dev/null is a non-negative exact integer"
                (let ((d (file-info:device (file-info "/dev/null" #t))))
                  (and (exact-integer? d) (>= d 0))))
   (test-assert "file-info:rdev on /dev/null is a non-negative exact integer"
                (let ((r (file-info:rdev (file-info "/dev/null" #t))))
                  (and (exact-integer? r) (>= r 0))))
   (test-assert "/dev/null classifies as a device"
                (file-info-device? (file-info "/dev/null" #t)))
   ;; /dev/fd is the issue's discriminating control: a *directory* under
   ;; devfs with st_rdev = 0, so a failure here isolates st_dev. It can be
   ;; a broken /proc symlink on minimal containers, so accept a catchable
   ;; stat failure -- the regression being pinned is the uncatchable abort.
   (test-assert "file-info /dev/fd does not abort"
                (guard (e (#t 'stat-failed))
                  (begin (file-info "/dev/fd" #t) #t)))))

(let ((runner (test-runner-current)))
  (test-end "srfi170-devfs-1976")
  (when (> (test-runner-fail-count runner) 0) (exit 1)))
