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
;;;   loading. Kaappi's only notion of "the currently loading file" is
;;;   %script-path (kaappi sysinfo): the absolute path of the top-level
;;;   script named on the command line, or #f from the REPL/stdin/a
;;;   `load`ed or `import`ed file. We thread that #f straight through
;;;   instead of inventing a fallback string -- the same shape as
;;;   home-vicinity's own #f-for-inapplicable convention -- so callers can
;;;   tell "no script is loading" apart from "the script's vicinity is the
;;;   current directory" (a real, different vicinity: "").
;;;
;;; - library-vicinity and implementation-vicinity have no Kaappi analogue:
;;;   there is no separate "shared library directory" or "implementation
;;;   root" distinct from the ordinary library search path (--lib-path /
;;;   KAAPPI_HOME / thottam's ~/.kaappi/lib) or the installed binary's own
;;;   directory. Both return "" -- the same "current directory" convention
;;;   user-vicinity already uses -- rather than #f, so naive callers doing
;;;   `(in-vicinity (library-vicinity) name)` keep working via plain
;;;   string-append instead of failing on a non-string argument. #f is
;;;   reserved for home-vicinity, where "no such location on this platform"
;;;   is a real, distinct answer from "it's the current directory".
;;;
;;; - home-vicinity appends a trailing "/" to $HOME when it doesn't already
;;;   end in a vicinity separator, matching the reference implementation's
;;;   own normalization and the general vicinity convention that a
;;;   vicinity string is always ready for `string-append`.
;;;
;;; - vicinity:suffix? accepts only #\/ on POSIX. On Windows it also
;;;   accepts #\\ and #\: (the drive-letter separator), per the suffix
;;;   characters the spec itself lists. Construction (sub-vicinity, and the
;;;   trailing separator home-vicinity appends) always emits "/" rather
;;;   than branching on `cond-expand` a second time: Kaappi accepts and
;;;   prints "/"-separated paths natively on every supported platform,
;;;   Windows included.
;;;
;;; - (kaappi sysinfo) is not sandbox-available, so program-vicinity --
;;;   and therefore this whole library -- is unavailable under `--sandbox`,
;;;   the same restriction SRFI 170 and SRFI 192 already have.
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

    (define (program-vicinity)
      (let ((path (%script-path))) (and path (pathname->vicinity path))))

    ;; No distinct installed-library directory in Kaappi -- see header.
    (define (library-vicinity) "")

    ;; No distinct implementation-root directory in Kaappi -- see header.
    (define (implementation-vicinity) "")

    (define (user-vicinity) "")

    (define (home-vicinity)
      (let ((home (get-environment-variable "HOME")))
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
