;;; SRFI 181 — Custom Ports (including transcoded ports)
;;;
;;; The registry pre-registers every built-in Lib into vm.libraries at
;;; startup, keyed by canonical name -- a same-named .sld is checked second
;;; and never reached if the registry already has a match (see SRFI 248 for
;;; the identical, already-solved problem). So the native primitives behind
;;; this SRFI live under the sub-library `(srfi 181 primitives)`
;;; (`.srfi_181_primitives` in src/primitives.zig), and this file -- the
;;; only place `(srfi 181)` itself is defined -- imports that sub-library
;;; and re-exports its full surface. `(import (srfi 181))` therefore now
;;; loads through the normal .sld-file path rather than resolving directly
;;; against the registry; see vm_library.zig's sandbox-embedded table for
;;; why that matters under `--sandbox` (this file must be listed there for
;;; the custom-port constructors to remain sandbox-available, since that
;;; path only serves embedded libraries).
;;;
;;; See src/primitives_srfi181.zig for the custom-port implementation notes
;;; (GC-marking, the blocking-callback guard, the read/write funnel
;;; integration) -- unchanged by this reorganization.
;;;
;;; Transcoded ports (this file's `(begin ...)` body below) are almost
;;; entirely portable: codecs are plain interned symbols (eqv?-stable for
;;; free), and the transcoder itself is an opaque define-record-type, not
;;; a native heap type -- native code (%transcoded-port, in
;;; primitives_srfi181.zig) only ever sees the plain values this file
;;; unpacks from it, never the record itself.
;;;
;;; v1 supports only the UTF-8 codec. latin-1-codec/utf-16-codec are
;;; deliberately not exported at all here, rather than exported-but-
;;; always-erroring: there is no precedent in R7RS/SRFI for a binding
;;; that exists solely to fail, and a missing binding is exactly as
;;; discoverable via error handling (an unbound-variable condition) as a
;;; present-but-always-failing one would be.
;;;
;;; native-transcoder returns the UTF-8 codec, 'none eol-style, and
;;; 'replace error-handling-mode: 'none matches read-char's own current
;;; no-translation behavior (only read-line has its own separate, local
;;; CR/CRLF handling -- unrelated to any port-level transcoding concept),
;;; and 'replace is closer to today's silent-degrade-on-invalid-UTF-8
;;; behavior than 'raise would be.
;;;
;;; unknown-encoding-error? is a plain portable condition (make-codec's
;;; raise site is portable Scheme, right here) -- contrast
;;; i/o-decoding-error?/i/o-encoding-error?, which are native ErrorObjects
;;; because *their* raise site is deep inside primitives_io.zig's
;;; decode/encode loop.

(define-library (srfi 181)
  (import (srfi 181 primitives) (scheme base) (scheme char))
  (export make-custom-binary-input-port
          make-custom-binary-output-port
          make-custom-textual-input-port
          make-custom-textual-output-port
          make-custom-binary-input/output-port
          make-file-error

          transcoder?
          make-transcoder
          native-transcoder
          native-eol-style
          utf-8-codec
          make-codec
          transcoded-port
          bytevector->string
          string->bytevector
          unknown-encoding-error?
          unknown-encoding-error-name
          i/o-decoding-error?
          i/o-encoding-error?
          i/o-encoding-error-char)
  (begin

    ;;; --------------------------------------------------------------
    ;;; Codecs -- plain interned symbols, so eqv? identity is free (and
    ;;; actually stronger than the spec requires: (make-codec "utf-8")
    ;;; and (utf-8-codec) are eqv? to each other, not just
    ;;; self-consistent).
    ;;; --------------------------------------------------------------

    (define (utf-8-codec) 'utf-8)

    (define-record-type <unknown-encoding-error>
      (%make-unknown-encoding-error name)
      unknown-encoding-error?
      (name unknown-encoding-error-name))

    (define (make-codec name)
      (if (or (string-ci=? name "utf-8") (string-ci=? name "utf8"))
          'utf-8
          ;; The spec requires unknown-encoding-error-name's result to be
          ;; immutable ("it is an error to mutate this string") -- the
          ;; same contract symbol->string already has and enforces (via
          ;; the same flags.immutable check string-set! consults). There
          ;; is no portable "freeze this string" primitive, so round-trip
          ;; through a symbol: string->symbol accepts any string content
          ;; verbatim (no identifier-syntax restriction, per R7RS), and
          ;; symbol->string always returns a fresh, immutable copy -- this
          ;; also means the condition never aliases the caller's own
          ;; `name` string, so a caller mutating it afterward can't affect
          ;; the already-raised condition either.
          (raise (%make-unknown-encoding-error (symbol->string (string->symbol name))))))

    ;;; --------------------------------------------------------------
    ;;; Transcoders -- an opaque record; %transcoder-codec et al. are
    ;;; unexported and exist only so transcoded-port below can unpack one
    ;;; into the plain arguments %transcoded-port (native) expects.
    ;;; make-transcoder does not itself validate codec/eol-style/
    ;;; error-handling-mode -- the spec never says construction should
    ;;; reject unrecognized values, and since codecs are untyped symbols
    ;;; there is no way to enforce it any earlier than first use (in
    ;;; transcoded-port) regardless.
    ;;; --------------------------------------------------------------

    (define-record-type <transcoder>
      (make-transcoder codec eol-style error-handling-mode)
      transcoder?
      (codec %transcoder-codec)
      (eol-style %transcoder-eol-style)
      (error-handling-mode %transcoder-error-handling-mode))

    (define (native-eol-style)
      (cond-expand
        (windows 'crlf)
        (else 'lf)))

    (define (native-transcoder)
      (make-transcoder (utf-8-codec) 'none 'replace))

    ;;; --------------------------------------------------------------
    ;;; Transcoded ports
    ;;; --------------------------------------------------------------

    (define (transcoded-port binary-port transcoder)
      (%transcoded-port binary-port
                         (%transcoder-codec transcoder)
                         (%transcoder-eol-style transcoder)
                         (%transcoder-error-handling-mode transcoder)))

    ;; Routed through transcoded-port/read-char/write-string, not a
    ;; one-shot native primitive, so eol-style/error-mode translation
    ;; applies for free -- these aren't hot-path procedures, and
    ;; UTF-8-only decoding is close to "validate and copy" regardless.
    (define (bytevector->string bv transcoder)
      (let* ((bp (open-input-bytevector bv))
             (tp (transcoded-port bp transcoder))
             (out (open-output-string)))
        (let loop ()
          (let ((c (read-char tp)))
            (unless (eof-object? c)
              (write-char c out)
              (loop))))
        (get-output-string out)))

    (define (string->bytevector s transcoder)
      (let* ((bp (open-output-bytevector))
             (tp (transcoded-port bp transcoder)))
        (write-string s tp)
        (get-output-bytevector bp)))))
