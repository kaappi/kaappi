;;; SRFI 59: Vicinity
;;;
;;; A vicinity describes a location in a file system abstractly enough to
;;; hide "host, volume, directory, and version" -- on Kaappi, as on most
;;; systems, a vicinity is just a string that is ready to be fed straight
;;; into `string-append` alongside a filename.
;;;
;;; Design notes / spec ambiguities resolved:
;;;
;;; - program-vicinity is defined via "the currently loading Scheme code",
;;;   and the spec explicitly leaves its result undefined when no file is
;;;   loading. Kaappi tracks exactly this dynamically, as
;;;   vm.current_lib_dir (%current-lib-dir, kaappi sysinfo): the directory
;;;   of the top-level script for that script's whole execution, shadowed
;;;   by a nested `.sld`/`include`/`load`'s own directory only while that
;;;   nested load is on the stack (save/restore, so control returning to
;;;   the outer file sees the outer vicinity again) -- matching the SRFI's
;;;   own "currently loading" wording more precisely than the top-level
;;;   script's path alone would. #f when nothing is currently loading (a
;;;   REPL/stdin session that hasn't called `load`) -- the same shape as
;;;   home-vicinity's own #f-for-inapplicable convention -- so callers can
;;;   tell "nothing is loading" apart from "the vicinity is the current
;;;   directory" (a real, different vicinity: "").
;;;
;;; - library-vicinity is $KAAPPI_HOME/lib (default ~/.kaappi/lib): thottam's
;;;   installed-ecosystem-package directory, which main.zig already adds to
;;;   the library search path regardless of --lib-path (workspace CLAUDE.md's
;;;   "Auto-discovery" section) -- the closest Kaappi analogue to the spec's
;;;   "shared Scheme library" directory. implementation-vicinity is the
;;;   directory containing the running kaappi executable itself, the closest
;;;   analogue to "will likely contain startup code and messages and a
;;;   compiler" (kaappi's compiler is `kaappi compile`, built into this same
;;;   binary). Both return #f rather than "" when genuinely unavailable (no
;;;   home directory; no self-exe-path lookup on this platform) -- a real,
;;;   distinct answer from "" (a real vicinity: the current directory),
;;;   matching home-vicinity's own #f-for-inapplicable convention below.
;;;
;;; - home-vicinity appends a trailing "/" to $HOME (or, when HOME is unset,
;;;   %USERPROFILE% on Windows -- vanilla cmd.exe/PowerShell do not set HOME
;;;   the way git-bash/MSYS does) when it doesn't already end in a vicinity
;;;   separator, matching the reference implementation's own normalization
;;;   and the general vicinity convention that a vicinity string is always
;;;   ready for `string-append`.
;;;
;;; - vicinity:suffix? accepts only #\/ on POSIX. On Windows it also
;;;   accepts #\\ and #\: (the drive-letter separator), per the suffix
;;;   characters the spec itself lists. Construction (sub-vicinity, and the
;;;   trailing separator home-vicinity appends) always emits "/" rather
;;;   than branching on `cond-expand` a second time: Kaappi accepts and
;;;   prints "/"-separated paths natively on every supported platform,
;;;   Windows included.
;;;
;;; - This whole library is unavailable under `--sandbox`: it is a portable
;;;   `.sld` file, and `--sandbox` blocks every file-backed library load
;;;   (`vm_library.libraryIsAvailable`) unless the library is specifically
;;;   embedded in the binary, which this one is not. That blanket file-load
;;;   block is why this library is unreachable, not `(kaappi sysinfo)`
;;;   itself -- that native library is reachable directly under `--sandbox`
;;;   (unlike SRFI 170/192, which -- being built-in, not `.sld` files --
;;;   are excluded by their own `Lib.sandboxAllowed` entry instead), and
;;;   its three static build-info procedures (`%implementation-version`,
;;;   `%os-name`, `%cpu-architecture`) stay reachable there; only the
;;;   filesystem-path-revealing ones this library itself needs
;;;   (`%script-path`, `%current-lib-dir`, `%kaappi-lib-dir`,
;;;   `%implementation-dir`) opt out per-primitive
;;;   (`src/primitives_sysinfo.zig`).
(define-library (srfi 59)
  (import (scheme base) (scheme process-context) (kaappi sysinfo))
  (export program-vicinity
          library-vicinity
          implementation-vicinity
          user-vicinity
          home-vicinity
          in-vicinity
          sub-vicinity
          make-vicinity
          pathname->vicinity
          vicinity:suffix?)
  (begin

    (define (vicinity:suffix? char)
      (cond-expand (windows (or (eqv? char #\/) (eqv? char #\\) (eqv? char #\:)))
                   (else (eqv? char #\/))))

    ;; Directory portion of an arbitrary path, including the trailing
    ;; separator (spec example: "/usr/local/lib/scm/Link.scm" =>
    ;; "/usr/local/lib/scm/"). No separator at all means "current
    ;; directory", so the result is "" -- the same convention as
    ;; user-vicinity.
    (define (pathname->vicinity path)
      (let loop ((i (- (string-length path) 1)))
        (cond ((< i 0) "")
              ((vicinity:suffix? (string-ref path i)) (substring path 0 (+ i 1)))
              (else (loop (- i 1))))))

    (define (program-vicinity) (%current-lib-dir))

    ;; $KAAPPI_HOME/lib -- see header. #f if no home directory is available.
    (define (library-vicinity) (%kaappi-lib-dir))

    ;; Directory containing the running kaappi executable -- see header. #f
    ;; if this platform has no self-exe-path lookup.
    (define (implementation-vicinity) (%implementation-dir))

    (define (user-vicinity) "")

    (define (home-vicinity)
      (let ((home (or (get-environment-variable "HOME")
                       (cond-expand (windows (get-environment-variable "USERPROFILE"))
                                    (else #f)))))
        (and home
             (if (and (positive? (string-length home))
                      (vicinity:suffix? (string-ref home
                                                    (- (string-length home) 1))))
                 home
                 (string-append home "/")))))

    ;; "For most systems in-vicinity can be string-append" (spec). This also
    ;; satisfies the spec's override rule for free: when vicinity is ""
    ;; (user-vicinity) and filename is absolute, string-append yields
    ;; filename unchanged.
    (define (in-vicinity vicinity filename) (string-append vicinity filename))

    (define (sub-vicinity vicinity name) (string-append vicinity name "/"))

    (define (make-vicinity dirpath) dirpath)))
