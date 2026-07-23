;; SRFI 112: Environment Inquiry
;; https://srfi.schemers.org/srfi-112/srfi-112.html
;;
;; Six zero-argument procedures returning human-readable information at run
;; time about the implementation and the hardware/software it runs on --
;; meant for bug reports, logging, and REPL banners, not for conditional
;; compilation (that job belongs to `cond-expand`/`features`). Each procedure
;; returns a string, or #f "if the implementation cannot provide an
;; appropriate and relevant result" (the SRFI's own wording); per the SRFI,
;; "no attempt is made to standardize the string values they return."
;;
;; implementation-version, cpu-architecture, and os-name wrap the native
;; `%implementation-version`/`%cpu-architecture`/`%os-name` primitives from
;; `(kaappi sysinfo)` (src/primitives_sysinfo.zig). os-name and
;; cpu-architecture report Zig's own target-enum spelling (e.g. "macos",
;; "aarch64" -- `@tagName(builtin.os.tag)` / `@tagName(builtin.cpu.arch)`),
;; which the SRFI permits since it disclaims any standard vocabulary.
;;
;; machine-name and os-version deliberately always return #f: the SRFI
;; explicitly sanctions #f when an implementation cannot provide a relevant
;; result, and a real hostname or OS-version lookup would need new
;; platform-specific code on every supported OS for a low-value,
;; non-standardized string -- a deliberate reduced scope, not an oversight.

(define-library (srfi 112)
  (export implementation-name
          implementation-version
          cpu-architecture
          machine-name
          os-name
          os-version)
  (import (scheme base)
          (kaappi sysinfo))
  (begin

    ;; Kaappi's own name; not a primitive since it never varies.
    (define (implementation-name) "kaappi")

    (define (implementation-version) (%implementation-version))

    (define (cpu-architecture) (%cpu-architecture))

    ;; Always #f -- see file header rationale.
    (define (machine-name) #f)

    (define (os-name) (%os-name))

    ;; Always #f -- see file header rationale.
    (define (os-version) #f)))
