;;; SRFI 193: Command Line
;;;
;;; Friendly wrappers around R7RS `command-line` (from `(scheme
;;; process-context)`) plus script-introspection procedures backed by the
;;; native `%script-path` primitive (`(kaappi sysinfo)`,
;;; src/primitives_sysinfo.zig -- shared with SRFI 59's `program-vicinity`,
;;; not yet implemented here).
;;;
;;; Terminology, per the SRFI: a *command* is a top-level program invoked
;;; with a command line; a *script* is a top-level program run from a file
;;; whose name is known to the implementation (not `load`ed, not
;;; `import`ed, not REPL-evaluated, not merely being compiled). A running
;;; program can be a command, a script, both at once, or neither.
;;;
;;; `command-line` itself is NOT redefined here -- it is imported from
;;; `(scheme process-context)` and re-exported unchanged (an R7RS library
;;; may export an imported binding by naming it in `export` with no
;;; corresponding local `define`). The SRFI says that when there is no
;;; script/command argv, `command-line` should return `("")`; this
;;; codebase's native `command-line` instead returns `()` (the empty list)
;;; in that situation (e.g. REPL/stdin), so `command-name`/`command-args`
;;; below explicitly treat both `()` and `("")` as "not a command" rather
;;; than assuming either shape and risking a `car`/`cdr` type error. Kaappi
;;; does not implement `command-line` as a SRFI-39 parameter object (the
;;; SRFI only encourages, not requires, this), so the `parameterize`-based
;;; rebinding it describes is not available.
;;;
;;; `command-name` and `script-directory` make discretionary choices the
;;; SRFI explicitly leaves to implementations:
;;;   - `command-name` strips the directory part and, if present, a single
;;;     trailing `.scm` or `.exe` extension, compared case-insensitively so
;;;     a Windows `FOO.EXE` and a Unix `foo` both become "foo" (the SRFI's
;;;     own example).
;;;   - `script-directory`'s result always ends with a directory separator
;;;     (the slice includes it), matching the SRFI's suggested use of
;;;     `string-append` to build sibling data-file paths.
;;; Both helpers recognize '/' and '\' as path separators regardless of host
;;; OS, since `%script-path` returns a plain OS path string (absolute,
;;; `.`/`..`-normalized, but not symlink-resolved) with no separator
;;; metadata attached.
(define-library (srfi 193)
  (import (scheme base)
          (scheme char)
          (scheme process-context)
          (kaappi sysinfo))

  (export
    command-line
    command-name
    command-args
    script-file
    script-directory)

  (begin
    ;; Index of the last path separator in s, or #f if s has none. Both
    ;; '/' and '\' are recognized on every platform (see file header).
    (define (%srfi193-last-separator s)
      (let loop ((i (- (string-length s) 1)))
        (cond ((< i 0) #f)
              ((let ((c (string-ref s i)))
                 (or (char=? c #\/) (char=? c #\\)))
               i)
              (else (loop (- i 1))))))

    ;; If name ends with suffix (case-insensitively), return name with that
    ;; suffix removed; otherwise #f. Never strips a suffix that would
    ;; consume the whole name.
    (define (%srfi193-strip-suffix name suffix)
      (let ((nlen (string-length name))
            (slen (string-length suffix)))
        (and (> nlen slen)
             (string-ci=? (substring name (- nlen slen) nlen) suffix)
             (substring name 0 (- nlen slen)))))

    (define (%srfi193-strip-known-extension name)
      (or (%srfi193-strip-suffix name ".scm")
          (%srfi193-strip-suffix name ".exe")
          name))

    ;; SRFI 193 `command-name`: a friendly version of (car (command-line)).
    ;; Guards against both "not a command" shapes this codebase's
    ;; command-line can produce -- () and ("") -- see file header.
    (define (command-name)
      (let ((cl (command-line)))
        (if (null? cl)
            #f
            (let ((s (car cl)))
              (if (= (string-length s) 0)
                  #f
                  (let* ((idx (%srfi193-last-separator s))
                         (base (if idx (substring s (+ idx 1) (string-length s)) s)))
                    (%srfi193-strip-known-extension base)))))))

    ;; SRFI 193 `command-args`: (cdr (command-line)), or '() when
    ;; command-line itself is already () (see file header).
    (define (command-args)
      (let ((cl (command-line)))
        (if (null? cl) '() (cdr cl))))

    ;; SRFI 193 `script-file`: already exactly what %script-path provides --
    ;; an absolute, un-symlink-resolved pathname, or #f when not running a
    ;; script (REPL, stdin, or a `load`ed/`import`ed file).
    (define (script-file)
      (%script-path))

    ;; SRFI 193 `script-directory`: the directory portion of script-file,
    ;; including the trailing separator, or #f if script-file is #f.
    (define (script-directory)
      (let ((f (script-file)))
        (and f
             (let ((idx (%srfi193-last-separator f)))
               (if idx (substring f 0 (+ idx 1)) "")))))))
